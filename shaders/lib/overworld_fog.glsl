uniform float noPuddleAreas;

float densityAtPosFog(in vec3 pos){
	pos /= 18.;
	pos.xz *= 0.5;
	vec3 p = floor(pos);
	vec3 f = fract(pos);
	f = (f*f) * (3.-2.*f);
	vec2 uv =  p.xz + f.xz + p.y * vec2(0.0,193.0);
	vec2 coord =  uv / 512.0;
	vec2 xy = texture(noisetex, coord).yx;
	return mix(xy.r,xy.g, f.y);
}


float cloudVol(in vec3 pos, float maxDistance){
	
	float fogYstart = FOG_START_HEIGHT + 3.0;
	vec3 samplePos = pos*vec3(1.0,1./24.,1.0);
	vec3 samplePos2 = pos*vec3(1.0,1./48.,1.0);
	
	float uniformFog = 0.0;

	float low_gradientFog = exp2(-0.15 * max(pos.y - fogYstart,0.0));
	float medium_gradientFog = exp2(-0.06 * max(pos.y - fogYstart,0.0));
	float high_gradientFog = exp2(-0.001 * max(pos.y - fogYstart,0.0));
	
	float fog_shape = 0.0;
	float fog_erosion = 0.0;
	if(sandStorm < 1.0 && snowStorm < 1.0){
		fog_shape = 1.0 - densityAtPosFog(samplePos * 24.0);
		fog_erosion = 1.0 - densityAtPosFog(samplePos2 * 200.0 - vec3(min(max(fog_shape - 0.6 ,0.0) * 2.0 ,1.0)*200.0));
	}
	
	float cloudyFog = max(min(max(fog_shape - 0.6 ,0.0) * 2.0 ,1.0) - fog_erosion * 0.4	, 0.0)	*	exp(-0.05 * max(pos.y - (fogYstart+20),0.0));
	float rainyFog = (high_gradientFog * 0.0085 + medium_gradientFog) * rainStrength * noPuddleAreas * (1.0 + thunderStrength) * RainFog_amount;

	#ifdef PER_BIOME_ENVIRONMENT
		rainyFog += high_gradientFog * isPaleGarden * PALE_GARDEN_UNIFORM_DENSITY;
	#endif
	
	if(sandStorm > 0.0 || snowStorm > 0.0){
		float IntenseFogs = pow(1.0 - densityAtPosFog( (samplePos2  - vec3(frameTimeCounter,0,frameTimeCounter)*15.0) * 100.0),2.0) * mix(1.0, medium_gradientFog, snowStorm);
		cloudyFog = mix(cloudyFog, IntenseFogs, sandStorm+snowStorm);

		low_gradientFog = mix(low_gradientFog, 1.0, sandStorm+snowStorm);
	}

	FogDensities(low_gradientFog, cloudyFog, maxDistance, SC_fog.x, SC_fog.y);

	return uniformFog + low_gradientFog + cloudyFog + rainyFog;
}

float phaseRayleigh(float cosTheta) {
	const float oneOverPi 	= 1.0 / acos(-1.0);
	const vec2 mul_add = vec2(0.1, 0.28) * oneOverPi;
	return cosTheta * mul_add.x + mul_add.y; // optimized version from [Elek09], divided by 4 pi for energy conservation
}
float fogPhase(float lightPoint){
	float linear = clamp(-lightPoint*0.5+0.5,0.001,1.0);
	float linear2 = 1.0 - clamp(lightPoint,0.0,1.0);

	float exponential = exp2(pow(linear,0.3) * -15.0 ) * 1.5;
	exponential += sqrt(exp2(sqrt(linear) * -12.5));

	// float exponential = 1.0 / (linear * 10.0 + 0.05);

	return exponential;
}

uniform ivec2 eyeBrightness;

vec4 GetVolumetricFog(
	in vec3 viewPosition,
	in vec3 sunVector,
	in vec2 dither,
	in vec3 LightColor,
	in vec3 AmbientColor,
	in vec3 AveragedAmbientColor,
	in float cloudPlaneDistance
){
	#ifndef TOGGLE_VL_FOG
		return vec4(0.0,0.0,0.0,1.0);
	#endif
	
	int SAMPLECOUNT = VL_SAMPLES;

	//project pixel position into projected shadowmap space
	vec3 dVWorld = mat3(gbufferModelViewInverse) * viewPosition;
	vec3 playerPos = dVWorld + gbufferModelViewInverse[3].xyz;
	// vec3 rayStartPos = playerPos - gbufferModelViewInverse[3].xyz;
	#ifdef CUSTOM_MOON_ROTATION
		vec3 fragposition = mat3(customShadowMatrixSSBO) * playerPos  + customShadowMatrixSSBO[3].xyz;
	#else
		vec3 fragposition = mat3(shadowModelView) * playerPos + shadowModelView[3].xyz;
	#endif
	fragposition = diagonal3(shadowProjection) * fragposition + shadowProjection[3].xyz;

	//project view origin into projected shadowmap space
	vec3 start = toShadowSpaceProjected(vec3(0.0));

	//rayvector into projected shadow map space
	//we can use a projected vector because its orthographic projection
	//however we still have to send it to curved shadow map space every step
	vec3 dV = fragposition - start;

	vec3 rayDir = normalize(playerPos);

	float rayLength = length(dVWorld);

	#if defined DISTANT_HORIZONS || defined VOXY
		float maxLength = min(min(rayLength, cloudPlaneDistance), max(far, dhVoxyRenderDistance))/rayLength;
		// float maxLength = min(length(dVWorld), max(far, dhVoxyRenderDistance))/length(dVWorld);
	#else
		float maxLength = min(min(rayLength, cloudPlaneDistance), far)/rayLength;
	#endif
	
	dV *= maxLength;
	dVWorld *= maxLength;

	float dL = length(dVWorld)/8.0;

	const float expFactor = 11.0;

	/// -------------  COLOR/LIGHTING STUFF ------------- \\\
	
	vec3 color = vec3(0.0);
	vec3 finalAbsorbance = vec3(1.0);

	float totalAbsorbance = 1.0;

	// float fogAbsorbance = 1.0;
	// float atmosphereAbsorbance = 1.0;
	vec3 atmosphereAbsorbance = vec3(1.0);

	float SdotV = dot(sunVector, rayDir);

	///// ----- fog lighting
	//Mie phase + somewhat simulates multiple scattering (Horizon zero down cloud approx)
	float sunPhase = fogPhase(SdotV)*5.0;
	float skyPhase = 0.5 + pow(1.0-pow(1.0-clamp(rayDir.y*0.5+0.5,0.0,1.0),2.0),5.0)*2.0;
	float rayL = phaseRayleigh(SdotV);

	vec3 rC = vec3(sky_coefficientRayleighR*1e-6, sky_coefficientRayleighG*1e-5, sky_coefficientRayleighB*1e-5) ;
	vec3 mC = vec3(fog_coefficientMieR*1e-6, fog_coefficientMieG*1e-6, fog_coefficientMieB*1e-6);
	
	#if defined EXCLUDE_WRITE_TO_LUT && defined USE_CUSTOM_FOG_LIGHTING_COLORS
		LightColor = dot(LightColor,vec3(0.21, 0.72, 0.07)) * vec3(DIRECTLIGHT_FOG_R,DIRECTLIGHT_FOG_G,DIRECTLIGHT_FOG_B);
		AmbientColor = dot(AmbientColor,vec3(0.21, 0.72, 0.07)) * vec3(INDIRECTLIGHT_FOG_R,INDIRECTLIGHT_FOG_G,INDIRECTLIGHT_FOG_B);
	#endif

	vec3 skyLightPhased = AmbientColor;
	vec3 LightSourcePhased = LightColor;

	skyLightPhased *= skyPhase;
	LightSourcePhased *= sunPhase;

	#ifdef AMBIENT_LIGHT_ONLY
		LightSourcePhased = vec3(0.0);
	#endif

	#ifdef PER_BIOME_ENVIRONMENT
		vec3 biomeDirect = LightSourcePhased; 
		vec3 biomeIndirect = skyLightPhased;
		float inBiome = BiomeVLFogColors(biomeDirect, biomeIndirect);
	#endif

	float inACave = 1.0 - caveDetection;
	float lightLevelZero = pow(clamp(eyeBrightnessSmooth.y/240.0 ,0.0,1.0),3.0);

	// SkyLightColor *= lightLevelZero*0.9 + 0.1;
	// vec3 finalsceneColor = vec3(0.0);


	for (int i = 0; i < SAMPLECOUNT; i++) {
		float d = (pow(expFactor, float(i+dither.x)/float(SAMPLECOUNT))/expFactor - 1.0/expFactor)/(1-1.0/expFactor);
		float dd = pow(expFactor, float(i+dither.y)/float(SAMPLECOUNT)) * log(expFactor) / float(SAMPLECOUNT)/(expFactor-1.0);

		// #ifdef VOLUMETRIC_CLOUDS
		// 	// check if the fog intersects clouds
		// 	if(length(d*dVWorld) > cloudPlaneDistance) break;
		// #endif

		vec3 progress = start.xyz + d*dV;
		vec3 progressP = gbufferModelViewInverse[3].xyz + d*dVWorld;
		vec3 progressW = progressP + cameraPosition;

		//------------------------------------
		//------ SAMPLE SHADOWS FOR FOG EFFECTS
		//------------------------------------
			#if defined DISTORT_SHADOWMAP
				float distortFactor = calcDistort(progress.xy);
			#else
				float distortFactor = 1.0;
			#endif
			vec3 shadowPos = vec3(progress.xy*distortFactor, progress.z);

			vec3 sh = vec3(1.0);
			if (abs(shadowPos.x) < 1.0-0.5/2048. && abs(shadowPos.y) < 1.0-0.5/2048.){
				shadowPos = shadowPos*vec3(0.5,0.5,0.5/6.0)+0.5;
				if (shadowPos.z < 1.0 && shadowPos.z > 0.0) {
					#ifdef TRANSLUCENT_COLORED_SHADOWS
						sh = vec3(texture(shadowtex0HW, shadowPos).x);

						if(texture(shadowtex1HW, shadowPos).x > shadowPos.z && sh.x < 1.0){
							vec4 translucentShadow = texture(shadowcolor0, shadowPos.xy);
							if(translucentShadow.a < 0.9) sh = normalize(translucentShadow.rgb+0.0001);
						}
					#else
						sh = vec3(texture(shadowtex0HW, shadowPos).x);
					#endif
				}
			}

			sh *= GetCloudShadow(progressW, sunVector);


		#ifdef PER_BIOME_ENVIRONMENT
			float maxDistance = inBiome * min(max(1.0 -  length(d*dVWorld.xz)/(32*8),0.0)*2.0,1.0);
			float fogDensity = cloudVol(progressW, maxDistance) * inACave;
		#else
			float fogDensity = cloudVol(progressW, 0.0) * inACave;
		#endif

		//------------------------------------
		//------ MAIN FOG EFFECT
		//------------------------------------
			float fogVolumeCoeff = exp(-fogDensity*dd*dL); // this is like beer-lambert law or something

			#ifdef PER_BIOME_ENVIRONMENT
				vec3 indirectLight = mix(skyLightPhased, biomeIndirect, maxDistance);
				vec3 DirectLight = mix(LightSourcePhased, biomeDirect, maxDistance) * sh;
			#else
				vec3 indirectLight = skyLightPhased;
				vec3 DirectLight = LightSourcePhased * sh;
			#endif

			vec3 Lightning = Iris_Lightningflash_VLfog(progressP);
			vec3 lighting = DirectLight + indirectLight + 0.0025 * Lightning;
			
			color += (lighting - lighting * fogVolumeCoeff) * totalAbsorbance;

			// kill fog absorbance when in caves.
			totalAbsorbance *= mix(1.0, fogVolumeCoeff, lightLevelZero);
			if(totalAbsorbance < 0.01) break;

		//------------------------------------
		//------ ATMOSPHERE HAZE EFFECT
		//------------------------------------

			// maximum range for atmosphere haze, basically.
			float planetVolume = smoothstep(1.0 - exp(clamp(1.0 - length(progressP) / (16.0*150.0), 0.0,1.0) * -10.0), 0.0, progressP.y-500.0);

			// just air
			vec2 airCoef = exp2(-max(progressW.y-SEA_LEVEL,0.0)/vec2(8.0e3, 1.2e3)*vec2(6.0,7.0)) * 192.0 * Haze_amount * planetVolume;

			// Pbr for air, yolo mix between mie and rayleigh for water droplets
			vec3 rL = rC*airCoef.x;
			vec3 m =  mC*(airCoef.y+fogDensity*300.0);

			// calculate the atmosphere haze seperately and purely additive to color, do not contribute to absorbtion.
			vec3 atmosphereVolumeCoeff = exp(-(rL+m)*dd*dL);
			// vec3 Atmosphere = LightSourcePhased * sh * (rayL*rL + sunPhase*m) + AveragedAmbientColor * (rL+m);
			vec3 Atmosphere = (LightSourcePhased * sh * (rayL*rL + sunPhase*m) + AveragedAmbientColor * (rL+m) * (lightLevelZero*0.99 + 0.01)) * inACave;
			color += (Atmosphere - Atmosphere * atmosphereVolumeCoeff) / (rL+m+1e-6) * atmosphereAbsorbance;
	
			atmosphereAbsorbance *= atmosphereVolumeCoeff*fogVolumeCoeff;

			// totalAbsorbance *= dot(atmosphereVolumeCoeff,vec3(0.33333));
	}

	// sceneColor = finalsceneColor;

	// atmosphereAlpha = atmosphereAbsorbance;
	
	return vec4(color, totalAbsorbance);
}