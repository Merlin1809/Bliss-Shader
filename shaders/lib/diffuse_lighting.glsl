#if defined MAIN_SHADOW_PASS && (defined LPV_HANDHELD_SHADOWS && defined IS_LPV_ENABLED || defined PHOTONICS && defined PHOTONICS && !defined PH_ENABLE_HANDHELD_LIGHT) && !defined VOXY_PROGRAM
    float swapperlinZ2(float depth, float _near, float _far) {
        return (2.0 * _near) / (_far + _near - depth * (_far - _near));
    }

    float SSRT_Handlight_Shadows(vec3 viewPos, const bool depthCheck, vec3 lightDir, float noise, vec3 normals, bool hand){
        
        if(hand) return 1.0;

        vec3 WlightDir = normalize((gbufferModelViewInverse*vec4(lightDir, 1.0)).xyz);

        float NdotL = dot(normals, WlightDir);
        NdotL = smoothstep(0.0, 0.2, abs(NdotL));

        float shadows = 1.0;
        #if LPV_HANDHELD_SHADOWS_QUALITY == 0
            float samples = 10.0;
            float div = 0.0015;
        #else
            float samples = 20.0;
            float div = 0.0005;
        #endif

        float _near = near; float _far = far*4.0;

        if (depthCheck) {
            _near = dhVoxyNearPlane;
            _far = dhVoxyFarPlane;
        }

        vec3 position = toClipSpace3_DH(viewPos, depthCheck) ;
        
        //prevents the ray from going behind the camera
        float rayLength = ((viewPos.z + lightDir.z * _far * sqrt(3.)) > -_near) ? (-_near - viewPos.z) / lightDir.z : _far * sqrt(3.);

        vec3 direction = toClipSpace3_DH(viewPos + lightDir*rayLength, depthCheck) - position;
        direction.xyz = direction.xyz / max(max(abs(direction.x)/div, abs(direction.y)/div),400.0);	//fixed step size
        direction *= 6.0;

        position.xy *= RENDER_SCALE;
        direction.xy *= RENDER_SCALE;
        
        vec3 newPos = position + direction*noise;
        // literally shadow bias to fight shadow acne due to precision problems when comparing sampled depth and marched position
        //newPos += direction*0.3;


        for (int i = 0; i < int(samples); i++) {
            
            float samplePos;
		
            #if defined DISTANT_HORIZONS || defined VOXY
                if(depthCheck) {
                    samplePos = texelFetch(dhVoxyDepthTex1, ivec2(newPos.xy/texelSize),0).x;
                } else
            #endif
                {
                    samplePos = texelFetch(depthtex2, ivec2(newPos.xy/texelSize),0).x;
                }

            if(samplePos < newPos.z && samplePos > 0.0){// && (samplePos <= max(minZ,maxZ) && samplePos >= min(minZ,maxZ))){
                shadows = 0.0;
                break;
            } 
        
            newPos += direction;
        }

        return clamp(shadows*NdotL, 1.0-LPV_HANDHELD_SHADOWS_STRENGTH, 1.0);
    }
#endif

#if (defined IS_LPV_ENABLED || defined PHOTONICS && defined PHOTONICS && !defined PH_ENABLE_HANDHELD_LIGHT) && !defined VOXY_PROGRAM
    vec3 GetHandLight(const in int itemId, const in vec3 playerPos, inout float lightRange) {
        vec3 lightFinal = vec3(0.0);

        uint blockData = imageLoad(imgBlockData, itemId).r;
        vec4 lightColorRange = unpackUnorm4x8(blockData);
        lightRange = lightColorRange.a * 255.0;

        if (lightRange > 0.0) {
            vec3 lightColor = srgbToLinear(lightColorRange.rgb);
            float lightDist = length(playerPos+relativeEyePosition);
            // vec3 lightDir = playerPos / lightDist;
            const float NoL = 1.0;//max(dot(normal, lightDir), 0.0);
            float falloff = pow(1.0 - lightDist / lightRange, 3.0);
            lightFinal = lightColor * NoL * max(falloff, 0.0);
        }

        return lightFinal;
    }
#endif

#if defined PHOTONICS && !defined VOXY_PROGRAM && !defined PHOTONICS_INCLUDED && defined PHOTONICS_ACTIVE
    uniform sampler2D radiosity_direct;
    uniform sampler2D radiosity_direct_soft;
    uniform sampler2D radiosity_handheld;
#endif

#ifdef BELTBORNE_LANTERNS
uniform int IEXT_beltborne_lanterns_Id;
#endif

vec3 doBlockLightLighting(
    vec3 lightColor, float lightmap,
    vec3 playerPos, vec3 lpvPos
    #ifdef MAIN_SHADOW_PASS
    , vec3 viewPos, bool depthCheck, float noise, vec3 normals, bool hand
    #endif

    , bool glowframe
    , bool particles
){
    lightmap = clamp(lightmap,0.0,1.0);

    float lightmapBrightspot = min(max(lightmap-0.7,0.0)*3.3333,1.0);
    lightmapBrightspot *= lightmapBrightspot*lightmapBrightspot;

    float lightmapLight = 1.0-sqrt(1.0-lightmap);
    lightmapLight *= lightmapLight;

    float lightmapCurve = mix(lightmapLight, 2.5, lightmapBrightspot);
    vec3 blockLight = lightmapCurve * lightColor;
    
    #if defined IS_LPV_ENABLED && defined MC_GL_ARB_shader_image_load_store && (!defined PHOTONICS_LIGHT_PASS || !defined PHOTONICS || !defined PH_ENABLE_BLOCKLIGHT || !defined PHOTONICS_ACTIVE) && !defined VOXY_PROGRAM
        vec4 lpvSample = SampleLpvLinear(lpvPos);

        #ifdef VANILLA_LIGHTMAP_MASK
            lpvSample.rgb *= lightmapCurve;
        #endif

        if(particles) {
            float luma = dot(lpvSample.rgb,vec3(0.21, 0.72, 0.07));
            lpvSample.rgb += lightmapCurve * (1.0 - clamp(luma * 2.0, 0.0, 1.0));
        } 
        else if(glowframe) lpvSample.rgb += lightmapCurve * (1.0 - lightmap);

        // vec3 lpvBlockLight = GetLpvBlockLight(lpvSample);

        // create a smooth falloff at the edges of the voxel volume.
        const float fadeLength = 10.0; // in meters
        vec3 cubicRadius = clamp(min(((LpvSize3-1.0) - lpvPos)/fadeLength, lpvPos/fadeLength), 0.0, 1.0);
        float voxelRangeFalloff = cubicRadius.x*cubicRadius.y*cubicRadius.z;
        voxelRangeFalloff = 1.0 - pow(1.0-pow(voxelRangeFalloff,1.5),3.0);
        
        // outside the voxel volume, lerp to vanilla lighting as a fallback
        blockLight = mix(blockLight, lpvSample.rgb + lightColor * 2.5 * min(max(lightmap-0.999,0.0)/(1.0-0.999),1.0), voxelRangeFalloff);

        #ifdef Hand_Held_lights
            // create handheld lightsources

            #if !defined PH_ENABLE_HANDHELD_LIGHT || !defined PHOTONICS_LIGHT_PASS
                if (heldItemId > 0){
                        float lightRange = 0.0;
                        vec3 handLightCol = GetHandLight(heldItemId, playerPos, lightRange);

                        #if defined MAIN_SHADOW_PASS && defined LPV_HANDHELD_SHADOWS
                            if (lightRange > 0.0 && firstPersonCamera) handLightCol *=  SSRT_Handlight_Shadows(viewPos, depthCheck, -(viewPos + vec3(-0.25, 0.2, 0.0)), noise, normals, hand);
                        #endif

                        #ifdef WEATHER
                            handLightCol *= 0.5;
                        #endif

                        blockLight += handLightCol;
                }
                

                if (heldItemId2 > 0){
                        float lightRange2 = 0.0;
                        vec3 handLightCol2 = GetHandLight(heldItemId2, playerPos, lightRange2);
                        
                        #if defined MAIN_SHADOW_PASS && defined LPV_HANDHELD_SHADOWS
                            if (lightRange2 > 0.0 && firstPersonCamera) handLightCol2 *= SSRT_Handlight_Shadows(viewPos, depthCheck, -(viewPos + vec3(0.25, 0.2, 0.0)), noise, normals, hand);
                        #endif

                        #ifdef WEATHER
                            handLightCol2 *= 0.5;
                        #endif

                        blockLight += handLightCol2;
                }

                #ifdef BELTBORNE_LANTERNS
                    if (IEXT_beltborne_lanterns_Id > 0){
                            float lightRange2 = 0.0;
                            vec3 handLightCol2 = GetHandLight(IEXT_beltborne_lanterns_Id, playerPos, lightRange2);
                            
                            #if defined MAIN_SHADOW_PASS && defined LPV_HANDHELD_SHADOWS
                                if (lightRange2 > 0.0 && firstPersonCamera) handLightCol2 *= SSRT_Handlight_Shadows(viewPos, depthCheck, -(viewPos + vec3(0.125, 0.2, 0.0)), noise, normals, hand);
                            #endif

                            #ifdef WEATHER
                                handLightCol2 *= 0.5;
                            #endif

                            blockLight += handLightCol2;
                    }
                #endif
            #endif

            #if defined PH_ENABLE_HANDHELD_LIGHT && !defined PH_ENABLE_BLOCKLIGHT && defined PHOTONICS_INCLUDED
                vec3 ph_direct_hand = sample_photonics_handheld(gl_FragCoord.xy*texelSize/RENDER_SCALE).xyz;
                blockLight += ph_direct_hand * 1.35;
            #endif
        #endif
    #endif
    
    #if defined PHOTONICS && defined PH_ENABLE_BLOCKLIGHT && !defined WEATHER && defined PHOTONICS_LIGHT_PASS && !defined VOXY_PROGRAM && defined PHOTONICS_ACTIVE
        #if defined DISTANT_HORIZONS || defined VOXY
        if(!depthCheck)
        #endif
        {
            vec3 photonicsLight = vec3(0.0);
            vec3 handLight = vec3(0.0);

            #if defined PH_ENABLE_HANDHELD_LIGHT
                vec3 ph_direct_hand = sample_photonics_handheld(gl_FragCoord.xy*texelSize/RENDER_SCALE).xyz;
                handLight = ph_direct_hand * 1.35;
            #else
                #ifdef Hand_Held_lights
                    if (heldItemId > 0){
                            float lightRange = 0.0;
                            vec3 handLightCol = GetHandLight(heldItemId, playerPos, lightRange);

                            #if defined MAIN_SHADOW_PASS && defined LPV_HANDHELD_SHADOWS
                                if (lightRange > 0.0 && firstPersonCamera) handLightCol *=  SSRT_Handlight_Shadows(viewPos, depthCheck, -(viewPos + vec3(-0.25, 0.2, 0.0)), noise, normals, hand);
                            #endif

                            #ifdef WEATHER
                                handLightCol *= 0.5;
                            #endif

                            handLight += handLightCol;
                    }
                    

                    if (heldItemId2 > 0){
                            float lightRange2 = 0.0;
                            vec3 handLightCol2 = GetHandLight(heldItemId2, playerPos, lightRange2);
                            
                            #if defined MAIN_SHADOW_PASS && defined LPV_HANDHELD_SHADOWS
                                if (lightRange2 > 0.0 && firstPersonCamera) handLightCol2 *= SSRT_Handlight_Shadows(viewPos, depthCheck, -(viewPos + vec3(0.25, 0.2, 0.0)), noise, normals, hand);
                            #endif

                            #ifdef WEATHER
                                handLightCol2 *= 0.5;
                            #endif

                            handLight += handLightCol2;
                    }

                    #ifdef BELTBORNE_LANTERNS
                        if (IEXT_beltborne_lanterns_Id > 0){
                                float lightRange2 = 0.0;
                                vec3 handLightCol3 = GetHandLight(IEXT_beltborne_lanterns_Id, playerPos, lightRange2);
                                
                                #if defined MAIN_SHADOW_PASS && defined LPV_HANDHELD_SHADOWS
                                    if (lightRange2 > 0.0 && firstPersonCamera) handLightCol3 *= SSRT_Handlight_Shadows(viewPos, depthCheck, -(viewPos + vec3(0.125, 0.2, 0.0)), noise, normals, hand);
                                #endif

                                #ifdef WEATHER
                                    handLightCol3 *= 0.5;
                                #endif

                                handLight += handLightCol3;
                        }
                    #endif
                #endif
            #endif

            #ifdef PH_ENABLE_BLOCKLIGHT
                vec3 ph_direct = sample_photonics_direct(gl_FragCoord.xy*texelSize/RENDER_SCALE).xyz;
                photonicsLight += ph_direct;
                photonicsLight += lightColor * 2.5 * min(max(lightmap-0.999,0.0)/(1.0-0.999),1.0);
            #endif

            #if defined DISTANT_HORIZONS || defined VOXY
				float photonicsFalloff = smoothstep(min(far, 256.0), min(0.9*far, 230.0), length(playerPos));
			#else
				float photonicsFalloff = smoothstep(256.0, 230.0, length(playerPos));
			#endif

            
            blockLight = mix(blockLight, photonicsLight+handLight, photonicsFalloff);
        }
    #endif

    return blockLight * TORCH_AMOUNT;
}

vec3 doIndirectLighting(
    vec3 lightColor, vec3 minimumLightColor, float lightmap
){

    // float lightmapCurve = pow(1.0-pow(1.0-lightmap,2.0),2.0);
    // float lightmapCurve = lightmap*lightmap;
    float lightmapCurve = (pow(lightmap,15.0)*2.0 + lightmap*lightmap)/3.0; //make sure its 0.0-1.0

    vec3 indirectLight = lightColor * lightmapCurve * ambient_brightness;  

    // indirectLight = max(indirectLight, minimumLightColor * (MIN_LIGHT_AMOUNT * 0.02 * 0.2 + nightVision));
    indirectLight += mix(minimumLightColor * (MIN_LIGHT_AMOUNT * 0.004 + nightVision*0.02), minimumLightColor * (MIN_LIGHT_AMOUNT_INSIDE * 0.004 + nightVision*0.02), 1.0-lightmap);

    return indirectLight;
}

#ifndef VOXY_PROGRAM
uniform float centerDepthSmooth;
#ifdef IEXT_ENABLED
uniform bool IEXT_KEY_0;
#endif

vec3 calculateFlashlight(in vec2 texcoord, in vec3 viewPos, in vec3 albedo, in vec3 normal, out vec4 flashLightSpecularData, bool hand){
    #ifdef IEXT_ENABLED
    if(IEXT_KEY_0) return vec3(0.0);
    #endif

	// vec3 shiftedViewPos = viewPos + vec3(-0.25, 0.2, 0.0);
	// vec3 shiftedPlayerPos = mat3(gbufferModelViewInverse) * shiftedViewPos + gbufferModelViewInverse[3].xyz + (cameraPosition - previousCameraPosition) * 3.0;
	// shiftedViewPos = mat3(gbufferPreviousModelView) * shiftedPlayerPos + gbufferPreviousModelView[3].xyz;
	vec3 shiftedViewPos;
    vec3 shiftedPlayerPos;
	float forwardOffset;

    #ifdef VIVECRAFT
        if (vivecraftIsVR) {
	        forwardOffset = 0.0;
            shiftedPlayerPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz + vivecraftRelativeMainHandPos;
            shiftedViewPos = shiftedPlayerPos * mat3(vivecraftRelativeMainHandRot);
        } else
    #endif
    {
	    forwardOffset = 0.5;
        shiftedViewPos = viewPos + vec3(-0.25, 0.2, 0.0);
        shiftedPlayerPos = mat3(gbufferModelViewInverse) * shiftedViewPos + gbufferModelViewInverse[3].xyz + (cameraPosition - previousCameraPosition) * 3.0;
        shiftedViewPos = mat3(gbufferPreviousModelView) * shiftedPlayerPos + gbufferPreviousModelView[3].xyz;
    }

    
    
    vec2 scaledViewPos = shiftedViewPos.xy / max(-shiftedViewPos.z - forwardOffset, 1e-7);
	float linearDistance = length(shiftedPlayerPos);
	float shiftedLinearDistance = length(scaledViewPos);

	float lightFalloff = 1.0 - clamp(1.0-linearDistance/FLASHLIGHT_RANGE, -0.999,1.0);
	lightFalloff = max(exp(-10.0 * FLASHLIGHT_BRIGHTNESS_FALLOFF_MULT * lightFalloff),0.0);

	#if defined FLASHLIGHT_SPECULAR && (defined DEFERRED_SPECULAR || defined FORWARD_SPECULAR)
		float flashLightSpecular = lightFalloff * exp2(-7.0*shiftedLinearDistance*shiftedLinearDistance) * FLASHLIGHT_BRIGHTNESS_MULT;
		flashLightSpecularData = vec4(normalize(shiftedPlayerPos), flashLightSpecular);	
	#endif

	float projectedCircle = clamp(1.0 - shiftedLinearDistance*FLASHLIGHT_SIZE,0.0,1.0);
	float lenseDirt = texture(noisetex, scaledViewPos * 0.2 + 0.1).b;
	float lenseShape = (pow(abs(pow(abs(projectedCircle-1.0),2.0)*2.0 - 0.5),2.0) + lenseDirt*0.2) * 10.0;
	
	float offsetNdotL = clamp(dot(-normal, normalize(shiftedPlayerPos)),0,1);
	vec3 flashlightDiffuse = vec3(1.0) * lightFalloff * offsetNdotL * pow(1.0-pow(1.0-projectedCircle,2),2) * lenseShape * FLASHLIGHT_BRIGHTNESS_MULT;
	
	if(hand){
		flashlightDiffuse = vec3(0.0);
		flashLightSpecularData = vec4(0.0);
	}

	#ifdef FLASHLIGHT_BOUNCED_INDIRECT
		float lightWidth = 1.0+linearDistance*3.0;
		vec3 pointPos = mat3(gbufferModelViewInverse) *  (toScreenSpace(vec3(texcoord, centerDepthSmooth)) + vec3(-0.25, 0.2, 0.0));
		float flashLightHitPoint = distance(pointPos, shiftedPlayerPos);

		float indirectFlashLight = exp(-10.0 * (1.0 - clamp(1.0-length(shiftedViewPos.xy)/lightWidth,0.0,1.0)) );
		indirectFlashLight *= pow(clamp(1.0-flashLightHitPoint/lightWidth,0,1),2.0);

		flashlightDiffuse += albedo/150.0 * indirectFlashLight * lightFalloff;
	#endif

	return flashlightDiffuse * vec3(FLASHLIGHT_R,FLASHLIGHT_G,FLASHLIGHT_B);
}
#endif
