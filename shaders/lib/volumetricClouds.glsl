#define CIRRUS_LAYER 4
#define ALTOSTRATUS_LAYER 3
#define CUMULONIMBUS_LAYER 2
#define LARGECUMULUS_LAYER 1
#define SMALLCUMULUS_LAYER 0

#ifndef VOXY_PROGRAM
uniform float thunderStrength;
uniform int worldDay;
uniform int worldTime;
uniform float moonElevation;
uniform float worldTimeSmooth;
uniform float cloudTime;
#endif


#if CLOUD_MOVEMENT_TYPE == 0
	float cloud_movement = (worldTimeSmooth  + mod(worldDay,100)*24000.0) / 24.0 * Cloud_Speed;
#else
	float cloud_movement = cloudTime * Cloud_Speed;
#endif

float lightningFlashTimer = floor(frameTimeCounter * 11.0);
float randomSeed = fract(sin(dot(vec2(lightningFlashTimer), vec2(12.9898,78.233))) * 43758.5453);
float lightningFlash = mix(0.1, 2.5, randomSeed);

#if CUMULONIMBUS > 0
	float lightningDuration = 0.75 + CUMULONIMBUS_LIGHTNING_DELAY;
	float lightningTimer = floor(frameTimeCounter / lightningDuration);
	float timeInLightning = (frameTimeCounter / (lightningDuration) - lightningTimer) * lightningDuration;
	float lightningFade = smoothstep(0.6, 0.22, timeInLightning);
#endif

#if CUMULONIMBUS == 1 && !defined VOXY_PROGRAM
	uniform float cumulonimbusStrength;
#endif

#if defined CUMULONIMBUS_LIGHTNING && CUMULONIMBUS > 0
	float lightningStart = mix(20.0, 1.0, smoothstep(0.0, 0.085, timeInLightning));
	float lightningMid = smoothstep(0.0, 0.05, timeInLightning) * smoothstep(0.15, 0.066, timeInLightning);
#endif

#if defined DISTANT_HORIZONS || defined VOXY
	float distanceFogScale = -min((1.66/dhVoxyRenderDistance), 0.0006);
#else
	float distanceFogScale = -min((1.66/far), 0.0006);
#endif

float rand(float co){
	vec2 co2 = vec2(co, co*2.0);

    return fract(sin(dot(co2 ,vec2(12.9898,78.233))) * 43758.5453);
}

float getRainDensity(float currentDensity) {

	float extraDensity = min(currentDensity + rainStrength * 0.1 + thunderStrength * 0.1, 1.0);
	
	return extraDensity;
}

float densityAtPos(in vec3 pos){
	pos /= 18.;
	pos.xz *= 0.5;
	vec3 p = floor(pos);
	vec3 f = fract(pos);
	vec2 uv =  p.xz + f.xz + p.y * vec2(0.0,193.0);
	vec2 coord =  uv / 512.0;
	
	//The y channel has an offset to avoid using two textures fetches
	vec2 xy = texture(noisetex, coord).yx;

	return mix(xy.r,xy.g, f.y);
}


// Cirrus code shamelessly "borrowed" from photon shader and edited

vec2 hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
	p3 += dot(p3, p3.yzx+33.33);
	return fract((p3.xx+p3.yz)*p3.zy);
}

vec2 normalize_hash(vec2 p) {
	return normalize(hash2(p) - 0.5);
}

vec2 perlin_gradient(vec2 coord) {
	vec2 i = floor(coord);
	vec2 f = fract(coord);

	vec2 u 	= f * f * (3.0 - 2.0 * f); 					// Photon uses quintic interpolation
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0); 	// This ain't mathematically correct but it looks better ¯\_(ツ)_/¯

	vec2 g0 = normalize_hash(i);
	vec2 g1 = normalize_hash(i + vec2(1.0, 0.0));
	vec2 g2 = normalize_hash(i + vec2(0.0, 1.0));
	vec2 g3 = normalize_hash(i + vec2(1.0, 1.0));

	float v0 = dot(g0, f);
	float v1 = dot(g1, f - vec2(1.0, 0.0));
	float v2 = dot(g2, f - vec2(0.0, 1.0));
	float v3 = dot(g3, f - vec2(1.0, 1.0));

	vec2 omu = 1.0 - u;
	return vec2(
		((v1 - v0) * omu.y + (v3 - v2) * u.y) * du.x,
		((v2 - v0) * omu.x + (v3 - v1) * u.x) * du.y
	);
}

vec2 curl2D(vec2 coord) {
	vec2 gradient = perlin_gradient(coord);
	return vec2(gradient.y, -gradient.x);
}

float getCloudShape(int LayerIndex, int LOD, in vec3 position, float minHeight, float maxHeight){

	float coverage = 0.0;
	float shape = 0.0;
	float largeCloud = 0.0;
	float smallCloud = 0.0;

	vec3 samplePos = position*vec3(0.25, 0.005, 0.25);
	float tallness = maxHeight - minHeight;
	float posToMax = maxHeight - position.y;

	switch (LayerIndex){
    	default : { break; }

		#ifdef CloudLayer3
		case CIRRUS_LAYER: {
			coverage = SC_cirrus.x;

			vec2 coord = position.zx + 6.0*cloud_movement;
			
			vec2 curl = curl2D(0.00002 * coord) * 0.5
					+ curl2D(0.00005 * coord) * 0.25
					+ curl2D(0.00018 * coord) * 0.125;

			largeCloud = texture(noisetex, (position.xz + cloud_movement*2.0)/80000. * CloudLayer3_scale).b;
			smallCloud = texture(noisetex, (0.000005 / CloudLayer3_scale) * coord).r;
		
			float detail_amplitude = 0.3;
			float detail_frequency = 0.00002;
			float curl_strength    = 1.3;

			for (int i = 0; i < 3; ++i) {
				float detail = texture(noisetex, coord * detail_frequency + curl * curl_strength).r;

				smallCloud -= detail * detail_amplitude;

				detail_amplitude *= 0.5;
				detail_frequency *= 4.0;
				curl_strength 	 *= 2.7;
			}
			
			smallCloud = abs(largeCloud* -0.4) + smallCloud;

			float val = coverage;
			shape = min(max(val - smallCloud,0.0)/sqrt(val),1.0);

			if (position.y < (-0.0001 * minHeight + 0.8)*minHeight) shape = 0.0;

			return shape;
		}
		#endif

		#ifdef CloudLayer2
		case ALTOSTRATUS_LAYER: {
			coverage = SC_altostratus.x;
			coverage += Rain_coverage * rainStrength;
			coverage += Thunder_coverage * thunderStrength;

			largeCloud = texture(noisetex, (position.xz + cloud_movement*20.0)/100000. * CloudLayer2_scale).b;
			smallCloud = 1.0 - texture(noisetex, ((position.xz + vec2(-cloud_movement,cloud_movement)*20.0)/7500. - vec2(1.0-largeCloud, -largeCloud)/5.0) * CloudLayer2_scale).b;

			smallCloud = largeCloud + smallCloud * 0.4 * clamp(0.9-largeCloud,0.0,1.0);
			
			float val = coverage;
			shape = min(max(val - smallCloud,0.0)/sqrt(val),1.0);
			shape *= shape;

			if (position.y < (-0.0001 * minHeight + 0.8)*minHeight) shape = 0.0;

			return shape;
		}
		#endif

		#ifdef CloudLayer1
		case LARGECUMULUS_LAYER: {
			coverage = SC_largeCumulus.x;
			coverage += Rain_coverage * rainStrength;
			coverage += Thunder_coverage * thunderStrength;


			largeCloud = texture(noisetex, (samplePos.zx + cloud_movement*3.0)/10000.0 * CloudLayer1_scale).b;
			smallCloud = texture(noisetex, (samplePos.zx - cloud_movement*3.0)/2500.0 * CloudLayer1_scale).b;
			
			smallCloud = abs(largeCloud* -0.7) + smallCloud;

			float val = coverage;
			shape = min(max(val - smallCloud,0.0)/sqrt(val),1.0);

		break; }
		#endif

		#ifdef CloudLayer0
		case SMALLCUMULUS_LAYER: {
			coverage = SC_smallCumulus.x;
			coverage += Rain_coverage * rainStrength;
			coverage += Thunder_coverage * thunderStrength;

			largeCloud = texture(noisetex, (samplePos.xz + cloud_movement)/5000.0 * CloudLayer0_scale).b;
			smallCloud = 1.0-texture(noisetex, (samplePos.xz - cloud_movement)/500.0 * CloudLayer0_scale).r;

			smallCloud = abs(largeCloud-0.6) + smallCloud*smallCloud;

			float val = coverage;
			shape = min(max(val - smallCloud,0.0)/sqrt(val),1.0);
			
			// shape = abs(largeCloud*2.0 - 1.2)*0.5 - (1.0-smallCloud);
		break; }
		#endif
	}

	// clamp density of the cloud within its upper/lower bounds
	shape = min(min(shape, clamp(posToMax,0,1)), 1.0 - clamp(minHeight - position.y,0,1));

	// round out the bottom part slightly
	float bottomShape = 1.0-pow(1.0-min(max(position.y-minHeight,0.0) / 25.0, 1.0), 5.0);

	// carve out the upper part of clouds. make sure it rounds out at its upper bound
	float topShape = min(max(posToMax,0.0) / max(tallness,1.0),1.0);
	topShape = min(exp(-0.5 * (1.0-topShape)), 	1.0-pow(1.0-topShape,5.0));

	shape = max((shape - 1.0) + topShape * bottomShape, 0.0);

	/// erosion noise
	if(shape > 0.001){

		float erodeAmount = 0.5;
		// shrink the coverage slightly so it is a similar shape to clouds with erosion. this helps cloud lighting and cloud shadows.
		if (LOD < 1) return max(shape - 0.27*erodeAmount,0.0);

		samplePos.xz -= cloud_movement/4.0;

		// da wind
		// if(LayerIndex == SMALLCUMULUS_LAYER) 
		samplePos.xz += pow(max(position.y - (minHeight+20.0), 0.0) / (max(tallness,1.0)*0.20), 1.5);

 		float erosion = 0.0;
		float omShape = 1.0 - shape;

		switch (LayerIndex){  
    	    default : { break; }

			#ifdef CloudLayer0
			case SMALLCUMULUS_LAYER: {
				erosion += (1.0-densityAtPos(samplePos * CloudLayer0_detail * CloudLayer0_scale / 3.0)) * sqrt(omShape);

				float falloff = 1.0 - clamp(posToMax/(CloudLayer0_tallness/CloudLayer0_scale),0.0,1.0);
				erosion += abs(densityAtPos(samplePos * CloudLayer0_detail * CloudLayer0_scale) - falloff) * 0.75 * (omShape*omShape) * (1.0-falloff*0.25);

				erosion = erosion*erosion*erosion*erosion;
			break; }
			#endif
			
			#ifdef CloudLayer1
			case LARGECUMULUS_LAYER: {
				erosion += (1.0 - densityAtPos(samplePos * CloudLayer1_detail * CloudLayer1_scale / 3.571428)) * sqrt(omShape);

				float falloff = 1.0 - clamp(posToMax/(CloudLayer1_tallness/CloudLayer1_scale),0.0,1.0);
				erosion += abs(densityAtPos(samplePos * CloudLayer1_detail * CloudLayer1_scale) - falloff) * 0.75 * (omShape*omShape) * (1.0-falloff*0.5);

				erosion = erosion*erosion*erosion*erosion;
			break; }
			#endif
    	}

		return max(shape - erosion*erodeAmount,0.0);

	} else return 0.0;

}
#if CUMULONIMBUS > 0
vec2 getCumulonimbusShape(int LOD, in vec3 position, float minHeight, float maxHeight){

	float largeCloud = 0.0;
	float smallCloud = 0.0;

	vec3 samplePos = position*vec3(1.0, 1.0/48.0, 1.0)/4.0;
	float tallness = maxHeight - minHeight;
	float posToMax = maxHeight - position.y;

	float cumulonimbusScale = 1.0;
	//largeCloud = texture(noisetex, (samplePos.zx - cloud_movement*6.0) / 17000.0 * cumulonimbusScale * 0.2).b;
	
	//largeCloud = abs(largeCloud* -8.0);

	//float val = 2.8 + Rain_coverage * rainStrength;
	//float shape = min(max(val - largeCloud,0.0)/sqrt(val),1.0) * smoothstep(5000.0, 10000.0, length(position - cameraPosition));

	largeCloud = (max(sin((samplePos.x - cloud_movement*10.0)/2700) * cos((samplePos.z - cloud_movement*10.0)/2700), 0.0));
	largeCloud = mix(max(min(largeCloud - 0.25, 0.5)*2.0, 0.0), max(min(largeCloud, 0.25)*4.0, 0.0), thunderStrength);
	float shape = largeCloud * smoothstep(5000.0, 10000.0, length(position - cameraPosition));
	// return vec2(shape, 1.0);
	
	float isLarge = smoothstep(0.0, 1.0, shape);
	// isLarge = 0.0;

	float bottomShape = 1.0-pow(1.0-min(max(position.y-minHeight,0.0) / 5.0, 1.0), 5.0);


	float smallMaxHeight = (tallness*0.45 + minHeight);

	float shape2 = 0.0;
	if (position.y < smallMaxHeight) {
	float smallTallness = smallMaxHeight - minHeight;
	float posToMaxSmall = smallMaxHeight - position.y;

	smallCloud = 1.0-texture(noisetex, (samplePos.xz - cloud_movement*4.0) / 1800.0 * cumulonimbusScale * 0.2).r * smoothstep(smallMaxHeight, tallness*0.2+minHeight, position.y);
	
	shape2 = min(max(1.1 - smallCloud,0.0)/sqrt(1.1),1.0)  * smoothstep(5000.0, 7000.0, length(position - cameraPosition));

	shape2 = min(min(shape2, clamp(smallMaxHeight - position.y,0,1)), 1.0 - clamp(minHeight - position.y,0,1));

	float smallTopShape = min(max(posToMaxSmall,0.0) / max(smallTallness,1.0),1.0);
	smallTopShape = min(exp(23 * (1.0-smallTopShape)), 	1.0-pow(1.0-smallTopShape,9.0));

	shape2 = max((shape2 - 1.0) + smallTopShape * bottomShape, 0.0);
	}


	shape = min(min(shape, clamp(posToMax,0,1)), 1.0 - clamp(minHeight - position.y,0,1));

	float topShape = min(max(posToMax,0.0) / max(tallness,1.0),1.0);
	topShape = min(exp(-1.0 * (1.0-topShape)), 	1.0-pow(1.0-topShape,5.0));

	float topShape2 = min(max(posToMax,0.0) / max(tallness,1.0),1.0); 

	topShape2 = min(exp(-0.1 * (1.0-topShape2)), 	1.0-pow(1.0-topShape2,7.0));
	
	shape = max((shape - 1.0) + topShape * bottomShape + (1- topShape2) * bottomShape, 0.0);

	shape = pow(shape, 1 + smoothstep(tallness*0.4+minHeight, tallness*0.8+minHeight, position.y));

	shape += shape2;

	#if CUMULONIMBUS == 1
		shape *= pow(cumulonimbusStrength, mix(1.0, 6.0, smoothstep(tallness * 0.75 + minHeight, maxHeight, position.y)));
	#endif

	if(shape > 0.001){
		if (LOD < 1) return vec2(max(shape - 0.27*0.5,0.0), isLarge);

		samplePos.xz -= cloud_movement/4.0;
		samplePos.xz += pow( max(position.y - (minHeight+20.0), 0.0) / (max(tallness,1.0)*0.20), 1.5);

		float omShape = 1.0 - shape;

		float erosion = (1.0 - densityAtPos(samplePos * 190 * cumulonimbusScale*0.05)) * sqrt(omShape);

		float falloff = 1.0 - clamp((posToMax)/4600.0,0.0,1.0);

		erosion += abs(densityAtPos(samplePos * 580 * cumulonimbusScale*0.05) - falloff) * 0.65 * (omShape) * (1.0-falloff*0.5);

		erosion = erosion*erosion*erosion*erosion*smoothstep(maxHeight+40.0, tallness*0.5+minHeight, position.y);
		

		return vec2(max(shape - erosion*0.5,0.0), isLarge);
	} else return vec2(0.0, isLarge);
}
#endif
#if CUMULONIMBUS > 0 && defined CUMULONIMBUS_LIGHTNING
	vec3 getLightningPosition(float minHeight, float maxHeight) {
		float angle = rand(lightningTimer) * 6.28318530718;

		float rMin = 7000.0;
		float rMax = 13000.0;
		float radius = sqrt(mix(rMin * rMin, rMax * rMax, rand(lightningTimer + 1)));

		vec3 lightningPos = vec3(radius * cos(angle), minHeight + 0.62 * (maxHeight - minHeight), radius * sin(angle));

		float shapeAtLightningPos = getCumulonimbusShape(0, lightningPos, minHeight, maxHeight).x;
		float moveUp = 0.48;
		//if (shapeAtLightningPos < 0.1  && thunderStrength > 0.0) moveUp = mix(0.5, 0.1, thunderStrength);
		lightningPos.y = minHeight + (maxHeight - minHeight) * moveUp;
		lightningPos.y -= cameraPosition.y;

		if (shapeAtLightningPos < 0.1) lightningPos = vec3(0.0);

		#ifdef CUSTOM_LIGHTNING_POS
			lightningPos = vec3(CUSTOM_LIGHTNING_POS_X, CUSTOM_LIGHTNING_POS_Y, CUSTOM_LIGHTNING_POS_Z) - cameraPosition;
		#endif
		
		return lightningPos;
	}
#endif

#ifndef LIGHTNINGONLY

float getPlanetShadow(vec3 playerPos, vec3 WsunVec){
	float planetShadow = min(max(playerPos.y - (-100.0 + 1.0 / max(WsunVec.y*0.1, 0.0)),0.0) / 100.0, 1.0);
	
	planetShadow = mix(pow(1.0-pow(1.0-planetShadow,2.0),2.0), 1.0, pow(max(WsunVec.y, 0.0),2.0));
	
	return planetShadow;
}

float GetCloudShadow(vec3 playerPos, vec3 sunVector){

	#if defined CUSTOM_MOON_ROTATION && LIGHTNING_SHADOWS > 0
			#if LIGHTNING_SHADOWS < 2
			if (lightningBoltPosition.w > 0.0 && sunElevation < 0.0)
			#else
			if (lightningBoltPosition.w > 0.0)
			#endif
			{
				return 1.0;
			}
	#endif


	float totalShadow = getPlanetShadow(playerPos, sunVector);
	
	vec3 startPosition = playerPos;
	vec3 startOffset = sunVector / abs(sunVector.y);
	
	#if CLOUD_SHADOW_AMOUNT > 0 && defined VOLUMETRIC_CLOUDS
		float cloudShadows = 0.0;

		#ifdef CloudLayer0
			startPosition = playerPos + startOffset * max((CloudLayer0_height + 20.0) - playerPos.y, 0.0);
			cloudShadows = getCloudShape(SMALLCUMULUS_LAYER, 0, startPosition, CloudLayer0_height, CloudLayer0_height + CloudLayer0_tallness/CloudLayer0_scale)*(getRainDensity(SC_smallCumulus.y));
		#endif
		#ifdef CloudLayer1
			startPosition = playerPos + startOffset * max((CloudLayer1_height + 30.0) - playerPos.y, 0.0);
			cloudShadows += getCloudShape(LARGECUMULUS_LAYER, 0, startPosition, CloudLayer1_height, CloudLayer1_height + CloudLayer1_tallness/CloudLayer1_scale)*(getRainDensity(SC_largeCumulus.y));
		#endif
		#ifdef CloudLayer2
			startPosition = playerPos + startOffset * max(CloudLayer2_height - playerPos.y, 0.0);
			cloudShadows += getCloudShape(ALTOSTRATUS_LAYER, 0, startPosition, CloudLayer2_height, CloudLayer2_height + 5.0)*SC_altostratus.y * (1.0-abs(sunVector.y));
		#endif
		#if CUMULONIMBUS > 0
			float distanceFactor = clamp(degrees(acos(dot(vec3(0.0, 1.0, 0.0), sunVector))), 45.0, 90.0) - 45.0;
			
			startPosition = playerPos + sunVector * mix(7000, 18000, distanceFactor/45.0);
			cloudShadows += getCumulonimbusShape(0, startPosition, 600, 4600 + startPosition.y).x;
		#endif

		cloudShadows *= float(CLOUD_SHADOW_AMOUNT)/100.0;

		#if defined CloudLayer0 || defined CloudLayer1 || defined CloudLayer2 || CUMULONIMBUS > 0
			totalShadow *= exp((cloudShadows*cloudShadows) * -200.0);
		#endif
	#endif

	return totalShadow;
}

#ifndef CLOUDSHADOWSONLY
	vec3 getRayOrigin(
		vec3 rayStartPos,
		vec3 cameraPos,
		float dither,
		
		float minHeight,
		float maxHeight
	){

		vec3 cloudDist = vec3(1.0); 
		cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(cameraPos.y - minHeight ,0.0,clamp((maxHeight-15)-cameraPos.y ,0.0,1.0)));
		// allow passing through/above/below the plane without limits
		float flip = mix(max(cameraPos.y - maxHeight,0.0), max(minHeight - cameraPos.y,0.0), clamp(rayStartPos.y,0.0,1.0));

		// orient the ray to be a flat plane facing up/down
		// vec3 position = rayStartPos*dither + cameraPos + (rayStartPos/abs(rayStartPos.y)) * flip;
		vec3 position = rayStartPos*dither + cameraPos + (rayStartPos/length(rayStartPos/cloudDist)) * flip;
		
		return position;
	}
#endif

#if !defined CLOUDSHADOWSONLY && !defined CLOUD_SHADOW_PASS
uniform sampler2D colortex4;

#if CLOUD_PHASE == 0
	// Henyey-Greenstein
	float phaseCloud(float x, float g){
		float gg = g * g;
		return (gg * -0.25 + 0.25) * pow(-2.0 * (g * x) + (gg + 1.0), -1.5) / 3.14;
	}
#elif CLOUD_PHASE == 1
	// Cornette-Shanks
	float phaseCloud(float x, float g){
		return (3.0 * (1.0 - g * g) * (1.0 + x * x)) / (25.133 * (2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * x, 1.5));
	}
#else
	// HG-Draine
	float phaseCloud(in float x, in float g)
	{
		const float a = 0.9;
		float gg = g * g;
		return ((1 - gg)*(1 + a*x*x))/(4.*(1 + (a*(1 + 2*gg))/3.) * 3.1415926 * pow(1 + gg - 2*g*x,1.5));
	}
#endif



float getCloudScattering(
	int LayerIndex,
	vec3 rayPosition,
	vec3 sunVector,
	vec3 moonVector,
	float dither, 
	float minHeight,
	float maxHeight,
	float density
){
	int samples = 3;
	int LOD = 0;

	if(LayerIndex == CUMULONIMBUS_LAYER) samples = 7;

	if((LayerIndex == ALTOSTRATUS_LAYER) || (LayerIndex == CIRRUS_LAYER)) samples = 2;

	float shadow = 0.0;
	vec3 shadowRayPosition = vec3(0.0);

	float sunVis = smoothstep(-0.06, 0.01, sunElevation);
	sunVis = sunVis * sunVis;
	#if defined CAELUM_SUPPORT || !defined CUSTOM_MOON_ROTATION
		float moonVis = smoothstep(0.0, 0.075, -moonElevation);
	#else
		float  moonVis = smoothstep(0.0, 0.2, moonVector.y);
	#endif
	moonVis = moonVis * moonVis;

	moonVis *= smoothstep(0.06, -0.06, sunElevation);

	float isLarge = 80;
	vec3 lightVec = normalize(mix(moonVector, sunVector, smoothstep(-0.06, 0.06, sunElevation)));

	for (int i = 0; i < samples; i++){
		if((LayerIndex == ALTOSTRATUS_LAYER) || (LayerIndex == CIRRUS_LAYER)){
			shadowRayPosition = rayPosition + sunVector*sunVis * (0.25 + i * dither) * 200.0 + moonVector*moonVis * (0.25 + i * dither) * 200.0;
		} else
		#if CUMULONIMBUS > 0
		if((LayerIndex == LARGECUMULUS_LAYER) || (LayerIndex == SMALLCUMULUS_LAYER))
		#endif
		{
			shadowRayPosition = rayPosition + lightVec * (0.25 + i + dither)*20.0;
		}
		#if CUMULONIMBUS > 0
		else {
			shadowRayPosition = rayPosition + lightVec * (0.5 + i + dither)*isLarge;
		}
		#endif
		
		// float fadeddensity = density * pow(clamp((shadowRayPosition.y - minHeight)/(max(maxHeight-minHeight,1.0)*0.25),0.0,1.0),2.0);
		#if CUMULONIMBUS > 0
		if(LayerIndex != CUMULONIMBUS_LAYER) {
		#endif
			shadow += getCloudShape(LayerIndex, LOD, shadowRayPosition, minHeight, maxHeight) * density;
		#if CUMULONIMBUS > 0
		} else {
			shadow += getCumulonimbusShape(LOD, shadowRayPosition, minHeight, maxHeight).x * density;
			isLarge *= 1.374;
		}
		#endif
	}

	return shadow;
}

vec3 getCloudLighting(
	int LayerIndex,
	float shape,
	float shapeFaded,

	float sunShadowMask,
	vec3 directLightCol,
	vec3 directLightCol2,

	float indirectShadowMask,
	vec3 indirectLightCol,

	vec3 rayPosition,

	float backScatterPhase,
	vec4 phaseLevels,

	float backScatterPhase2,
	vec4 phaseLevels2
){

	vec3 heightScal = vec3(mix(1.0, 0.5, clamp(rayPosition.y, 0.0, 7000.0)/7000.0));

	directLightCol = pow(directLightCol, heightScal);

	directLightCol2 = pow(directLightCol2, heightScal);

	float beerCoef = -4.0;
	float powder = min(exp(beerCoef*exp(beerCoef*shapeFaded)) * 3.5, 1.0);
	float backscatter = powder * backScatterPhase;
	float forwardscatter = mix(mix(phaseLevels.x, phaseLevels.y, powder), mix(phaseLevels.z, phaseLevels.w, powder), powder);

	float backscatter2 = powder * backScatterPhase2;
	float forwardscatter2 = mix(mix(phaseLevels2.x, phaseLevels2.y, powder), mix(phaseLevels2.z, phaseLevels2.w, powder), powder);

	// backscatter = powder * phaseCloud(-backScatterPhase, 0.25) * 2.0;
	// forwardscatter = phaseCloud(backScatterPhase, mix(0.9,0.1,powder));

	float expBeer = 6.28 * exp((beerCoef-1.0)*sunShadowMask);

	vec3 directScattering = expBeer * directLightCol * (forwardscatter + backscatter);
	directScattering += expBeer * directLightCol2 * (forwardscatter2 + backscatter2);

	vec3 indirectScattering = indirectLightCol * mix(1.0, exp2(-5.0*shape), indirectShadowMask*indirectShadowMask);
	
	// return indirectScattering;
	// return directScattering;
	return indirectScattering + directScattering;
}

vec4 raymarchCloud(
	int LayerIndex,
	int samples,
	vec3 rayPosition,
	vec3 rayDirection,
	float dither,

	float minHeight,
	float maxHeight,

	vec3 sunVector,
	vec3 moonVector,
	vec3 sunScattering, 
	vec3 moonScattering, 
	vec3 skyScattering,

	float referenceDistance,
	vec3 sampledSkyCol,

	inout vec2 cloudPlaneDistance,

	float backScatterPhase,
	vec4 phaseLevels,

	float backScatterPhase2,
	vec4 phaseLevels2
){
	vec3 color = vec3(0.0);
	float totalAbsorbance = 1.0;

	#if AURORA_LOCATION > 0
		#ifdef LUT
			const float mult = 0.375*AURORA_BRIGHTNESS;
		#else
			const float mult = 0.015*AURORA_BRIGHTNESS;
		#endif

		const vec3 auroraColor = sin(vec3(AURORA_R, AURORA_G, AURORA_B) + 0.63) * 0.5 + 0.5;

		vec3 auroraLighting = mult*auroraColor * auroraAmount * smoothstep(0.0, -0.1, sunVector.y) * smoothstep(0.1, 0.0, moonVector.y);
	#endif

	// if(LayerIndex == SMALLCUMULUS_LAYER || LayerIndex == LARGECUMULUS_LAYER || LayerIndex == CUMULONIMBUS_LAYER) {
		// float planetShadow = getPlanetShadow(rayPosition, sunVector);
		// sunScattering *= planetShadow;
		// sunMultiScattering *= planetShadow;

		// float planetShadow = getPlanetShadow(rayPosition, moonVector);
		// moonScattering *= planetShadow;
		// moonMultiScattering *= planetShadow;
	// }

	float distanceFactor = length(rayDirection);

	float densityTresholdCheck = 0.0;

	if(LayerIndex == SMALLCUMULUS_LAYER) densityTresholdCheck = 0.06;
	if(LayerIndex == LARGECUMULUS_LAYER || LayerIndex == CUMULONIMBUS_LAYER) densityTresholdCheck = 0.02;
	if((LayerIndex == ALTOSTRATUS_LAYER) || (LayerIndex == CIRRUS_LAYER)) densityTresholdCheck = 0.01;

	densityTresholdCheck = mix(1e-5, densityTresholdCheck, dither);

	if((LayerIndex == ALTOSTRATUS_LAYER) || (LayerIndex == CIRRUS_LAYER)){
		float density = 0.0;
		vec3 newPos = rayPosition - cameraPosition;

		if(LayerIndex == ALTOSTRATUS_LAYER) {
			density = SC_altostratus.y;
			density *= smoothstep(CloudLayer2_distance, CloudLayer2_distance*0.5, length(newPos));
		} else {
			density = SC_cirrus.y;
			density *= smoothstep(CloudLayer3_distance, CloudLayer3_distance*0.5, length(newPos));
		}
		if (density == 0.0) return vec4(color, totalAbsorbance);

		bool ifAboveOrBelowPlane = max(mix(-1.0, 1.0, clamp(cameraPosition.y - minHeight,0.0,1.0)) * normalize(rayDirection).y + 0.0001,0.0) > 0.0;

		// check if the ray staring position is going farther than the reference distance, if yes, dont begin marching. this is to check for intersections with the world.
		// check if the camera is above or below the cloud plane, so it doesnt waste work on the opposite hemisphere
		#ifndef VL_CLOUDS_DEFERRED
			if(length(newPos) > referenceDistance || ifAboveOrBelowPlane) return vec4(color, totalAbsorbance);
		#else
			if(ifAboveOrBelowPlane) return vec4(color, totalAbsorbance);
		#endif

		float shape = getCloudShape(LayerIndex, 1, rayPosition, minHeight, maxHeight);
		float shapeWithDensity = shape*density;

		if(shapeWithDensity > mix(1e-5, 0.06, dither)){
			cloudPlaneDistance.x = length(newPos); cloudPlaneDistance.y = 0.0;
		}

		// check if the pixel has visible clouds before doing work.
		if(shapeWithDensity > 1e-5){

			// can add the initial cloud shape sample for a free shadow starting step :D
			float sunShadowMask = getCloudScattering(LayerIndex, rayPosition, sunVector, moonVector, dither, minHeight, maxHeight, density) * (1.0-abs(WsunVec.y));
			float indirectShadowMask = 0.5;

			vec3 lighting = getCloudLighting(LayerIndex, shapeWithDensity, shapeWithDensity, sunShadowMask, sunScattering, moonScattering, indirectShadowMask, skyScattering, rayPosition, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2);

			#if AURORA_LOCATION > 0
				lighting += auroraLighting;
			#endif
			
			newPos.xz /= max(newPos.y,0.0)*0.0025 + 1.0;
			// newPos.y = min(newPos.y,0.0);

			float distancefog = exp2(0.4*distanceFogScale*length(newPos.xz));
			vec3 atmosphereHaze = (sampledSkyCol - sampledSkyCol * distancefog);
			lighting = lighting * distancefog + atmosphereHaze;

			float densityCoeff = exp(-distanceFactor*shapeWithDensity);			
			color += (lighting - lighting * densityCoeff) * totalAbsorbance;
			totalAbsorbance *= densityCoeff;
		}

		return vec4(color, totalAbsorbance);
	}

	if(LayerIndex < ALTOSTRATUS_LAYER){

		vec3 newPos = rayPosition - cameraPosition;

		float densityLarge = getRainDensity(SC_largeCumulus.y);

		float density = 0.0;

		if(LayerIndex == SMALLCUMULUS_LAYER) density = getRainDensity(SC_smallCumulus.y) * smoothstep(CloudLayer0_distance, CloudLayer0_distance*0.5, length(newPos));

		if(LayerIndex == LARGECUMULUS_LAYER) density = getRainDensity(SC_largeCumulus.y) * smoothstep(CloudLayer1_distance, CloudLayer1_distance*0.5, length(newPos));

		if(LayerIndex == CUMULONIMBUS_LAYER) density = 0.8;

		if (density < 0.01) return vec4(color, totalAbsorbance);

		#if AURORA_LOCATION == 0
			float skylightOcclusion = 1.0;
			#if defined CloudLayer1 && defined CloudLayer0
				if(LayerIndex == SMALLCUMULUS_LAYER) {
					float upperLayerOcclusion = getCloudShape(LARGECUMULUS_LAYER, 0, rayPosition + vec3(0.0,1.0,0.0) * max((CloudLayer1_height+20) - rayPosition.y,0.0), CloudLayer1_height, CloudLayer1_height+100.0);
					skylightOcclusion = mix(mix(0.0,0.2,densityLarge), 1.0, pow(1.0 - upperLayerOcclusion*densityLarge,2));
				}
			#endif
		#endif

		vec3 lightningPos = vec3(0.0);
		#if CUMULONIMBUS > 0 && defined CUMULONIMBUS_LIGHTNING
			if(LayerIndex == CUMULONIMBUS_LAYER || thunderStrength > 0.0){		
				lightningPos = getLightningPosition(minHeight, maxHeight);
			}
		#endif

		vec3 mainLightVec = normalize(mix(moonVector, sunVector, smoothstep(-0.06, 0.06, sunElevation)));

		float tallness = maxHeight - minHeight;

		bool maxFogDistReached = false;

		for(int i = 0; i < samples; i++) {
			newPos = rayPosition - cameraPosition;

			// check if the ray staring position is going farther than the reference distance, if yes, dont begin marching. this is to check for intersections with the world.
			#ifndef VL_CLOUDS_DEFERRED
				if(length(newPos) > referenceDistance) break;
			#endif

			float rayHeightInCloud = rayPosition.y - minHeight;

			// check if the pixel is in the bounding box before doing work.
			if(clamp(rayPosition.y - maxHeight,0.0,1.0) < 1.0 && clamp(rayHeightInCloud,0.0,1.0) > 0.0){
				
				float shape = 0.0;
				float isLarge = 1.0;
				#if CUMULONIMBUS > 0
				if (LayerIndex != CUMULONIMBUS_LAYER) {
				#endif
					shape = getCloudShape(LayerIndex, 1, rayPosition, minHeight, maxHeight);
				#if CUMULONIMBUS > 0
				} else {
					vec2 cumulonimbusCloud = getCumulonimbusShape(1, rayPosition, minHeight, maxHeight);
					shape = cumulonimbusCloud.x;
					isLarge = 1.0 + 4.0 * cumulonimbusCloud.y;
				}
				#endif
				float shapeWithDensity = shape*density*isLarge;
				float shapeWithDensityFaded = shape*density * pow(clamp((rayHeightInCloud)/(max(tallness,1.0)*0.25),0.0,1.0),2.0);

				if(shapeWithDensityFaded > densityTresholdCheck && !maxFogDistReached){
					cloudPlaneDistance.x = length(newPos); cloudPlaneDistance.y = 0.0;
					maxFogDistReached = true;
				}

				// check if the pixel has visible clouds before doing work.
				if(shapeWithDensityFaded > 1e-5){
					
					#ifdef TERRAIN_SHADOW_ON_CLOUDS
						#ifdef CUSTOM_MOON_ROTATION
							vec3 fragposition = mat3(customShadowMatrixSSBO) * newPos + customShadowMatrixSSBO[3].xyz;
						#else
							vec3 fragposition = mat3(shadowModelView) * newPos + shadowModelView[3].xyz;
						#endif
						fragposition = diagonal3(shadowProjection) * fragposition + shadowProjection[3].xyz;

						#if defined DISTORT_SHADOWMAP && defined OVERWORLD_SHADER
							float distortFactor = calcDistort(fragposition.xy);
						#else
							float distortFactor = 1.0;
						#endif

						vec3 shadowPos = vec3(fragposition.xy * distortFactor, fragposition.z);

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
					#else
						const vec3 sh = vec3(1.0);
					#endif
					
					#if AURORA_LOCATION > 0
						float skylightOcclusion = 1.0;
						#if defined CloudLayer1 && defined CloudLayer0
							if(LayerIndex == SMALLCUMULUS_LAYER) {
								float upperLayerOcclusion = getCloudShape(LARGECUMULUS_LAYER, 0, rayPosition + vec3(0.0,1.0,0.0) * max((CloudLayer1_height+20) - rayPosition.y,0.0), CloudLayer1_height, CloudLayer1_height+CloudLayer1_height/CloudLayer1_scale);
								skylightOcclusion = mix(mix(0.0,0.2,densityLarge), 1.0, pow(1.0 - upperLayerOcclusion*densityLarge,5));
							}
						#endif
					#endif
					
					// can add the initial cloud shape sample for a free shadow starting step :D
					float indirectShadowMask = 1.0 - min(max(rayHeightInCloud,0.0) / max(tallness,1.0), 1.0);
					
					float sunShadowMask = getCloudScattering(LayerIndex, rayPosition, sunVector, moonVector, dither, minHeight, maxHeight, density);
					
					vec3 shadowStartPos = vec3(0.0);
					// do cloud shadows from one layer to another
					// large cumulus layer -> small cumulus layer
					#if defined CloudLayer0 && defined CloudLayer1
						if(LayerIndex == SMALLCUMULUS_LAYER){
							shadowStartPos = rayPosition + mainLightVec / abs(mainLightVec.y) * max((CloudLayer1_height + 20.0) - rayPosition.y, 0.0);
							sunShadowMask += 3.0 * getCloudShape(LARGECUMULUS_LAYER, 0, shadowStartPos, CloudLayer1_height, CloudLayer1_height+CloudLayer1_tallness/CloudLayer1_scale)*densityLarge;
						}
					#endif
					// cumulonimbus layer -> other cumulus layers
					#if (defined CloudLayer0 || defined CloudLayer1) && CUMULONIMBUS > 0
						if(LayerIndex != CUMULONIMBUS_LAYER){
							float distanceFactor = clamp(degrees(acos(dot(vec3(0.0, 1.0, 0.0), mainLightVec))), 45.0, 90.0) - 45.0;
			
							shadowStartPos = rayPosition + mainLightVec * 9000.;
							sunShadowMask += getCumulonimbusShape(0, shadowStartPos, 600., 4600.+shadowStartPos.y).x * 3.0;
						}
					#endif
					// altostratus layer -> all cumulus layers
					#ifdef CloudLayer2
						shadowStartPos = rayPosition + mainLightVec / abs(mainLightVec.y) * max(CloudLayer2_height - rayPosition.y, 0.0);
						sunShadowMask += getCloudShape(ALTOSTRATUS_LAYER, 0, shadowStartPos, CloudLayer2_height, CloudLayer2_height) * SC_altostratus.y * (1.0-abs(mainLightVec.y));
					#endif
					
					vec3 lighting = getCloudLighting(LayerIndex, shapeWithDensity, shapeWithDensityFaded, sunShadowMask, sunScattering*sh, moonScattering*sh, indirectShadowMask, skyScattering*skylightOcclusion, rayPosition, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2);

					float lightningIntensity = 0.0;
					
					// normal lightning strikes
					float horizontalDist = length((newPos.xz) - lightningBoltPosition.xz);
					if (horizontalDist < 7500.0 && lightningBoltPosition.w > 0.0) {
						lightningIntensity = exp(-horizontalDist * 0.006) * density * lightningFlash;
						lighting = mix(lighting, vec3(1.3,1.5,3.0), lightningIntensity);
					}

					// lightning strikes in cumulonimbus clouds
					#if defined CUMULONIMBUS_LIGHTNING && CUMULONIMBUS > 0
						if(LayerIndex == CUMULONIMBUS_LAYER || thunderStrength > 0.0){		
							horizontalDist = length(newPos.xz);
							float lightningDist = length((newPos) - lightningPos);
							
							if (lightningDist < 6000.0 && lightningPos != vec3(0.0)) {
								
									lightningIntensity = smoothstep(6000.0, 50.0, lightningDist) * smoothstep(0.15, 1.0, shapeWithDensity) * lightningFlash;
									lightningIntensity *= (1.0 - smoothstep(minHeight, 1.05 * maxHeight, rayPosition.y));
									lightningIntensity *= smoothstep(17000, 14000, horizontalDist);
									lightningIntensity *= lightningFade;

									vec3 lightningStrength = vec3(CUSTOM_LIGHTNING_R, 1.05*CUSTOM_LIGHTNING_G, 1.22*CUSTOM_LIGHTNING_B) * CUMULONIMBUS_LIGHTNING_BRIGHTNESS * 0.125;
									lighting = mix(lighting, lightningStrength, lightningIntensity);
							}
						}
					#endif

					#if AURORA_LOCATION > 0
						lighting += auroraLighting * min(max(rayHeightInCloud,0.0) / max(tallness,1.0), 1.0) * skylightOcclusion*skylightOcclusion;
					#endif

					
					newPos.xz /= max(newPos.y,0.0)*0.0025 + 1.0;
					// newPos.y = min(newPos.y,0.0);

					float distancefog = exp2((distanceFogScale)*length(newPos.xz));

					vec3 atmosphereHaze = (sampledSkyCol - sampledSkyCol * distancefog);
					lighting = lighting * distancefog + atmosphereHaze;

					float densityCoeff = exp(-distanceFactor*shapeWithDensityFaded);
					color += (lighting - lighting * densityCoeff) * totalAbsorbance;
					
					totalAbsorbance *= densityCoeff;
					
					// check if you can see through the cloud on the pixel before doing the next iteration
					if (totalAbsorbance < 1e-5) break;
					
				}
			}
			
			rayPosition += rayDirection;
			
		}
		return vec4(color, totalAbsorbance);
	}

}

vec4 GetVolumetricClouds(
	vec3 viewPos,
	vec2 dither,
	vec3 sunVector,
	vec3 moonVector,
	vec3 directLightCol,
	vec3 directLightCol2,
	vec3 indirectLightCol,

	inout float cloudPlaneDistance,
	inout vec2 cloudDistance
){	
	#ifndef VOLUMETRIC_CLOUDS
		#if defined VOXY || defined DISTANT_HORIZONS
			cloudPlaneDistance = max(far*8.0, dhVoxyFarPlane*2.0);
		#else
			cloudPlaneDistance = far*8.0;
		#endif
		return vec4(0.0,0.0,0.0,1.0);
	#endif



	vec3 color = vec3(0.0);
	float totalAbsorbance = 1.0;
	vec4 cloudColor = vec4(color, totalAbsorbance);
	vec4 cloudColorOriginal = cloudColor;

	float cloudheight = CloudLayer0_tallness / CloudLayer0_scale;
	float minHeight = CloudLayer0_height;
	float maxHeight = cloudheight + minHeight;

	#if defined OVERWORLD_SHADER && defined AETHER_FLAG
		minHeight = CloudLayer0_height - 350.0;
		maxHeight = cloudheight + minHeight;
	#endif

	float heightRelativeToClouds = clamp(1.0 - max(cameraPosition.y - minHeight,0.0) / 100.0 ,0.0,1.0);

	#if defined DISTANT_HORIZONS || defined VOXY
		const float maxdist = dhVoxyFarPlane - 16.0;
	#else
		const float maxdist = far + 16.0*5.0;
	#endif

   	float lViewPosM = length(viewPos) < maxdist ? length(viewPos) - 1.0 : 100000000.0;
	vec4 NormPlayerPos = normalize(gbufferModelViewInverse * vec4(viewPos, 1.0) + vec4(gbufferModelViewInverse[3].xyz,0.0));

	// vec3 signedSunVec = sunVector;
	vec3 unsignedSunVec = sunVector; //mix(moonVector, sunVector, clamp(float(sunElevation > 1e-5)*2.0-1.0 ,0,1));
	// vec3 signedMoonVec = moonVector;
	vec3 unsignedMoonVec = moonVector;

	float SdotV = dot(unsignedSunVec, NormPlayerPos.xyz);
	float SdotV2 = dot(unsignedMoonVec, NormPlayerPos.xyz);
	
	#ifdef SKY_GROUND
		NormPlayerPos.y += 0.03 * heightRelativeToClouds;
	#endif

	int samples = CLOUD_SAMPLES;
	// int samples = 30;
   
   	///------- setup the ray
	// vec3 cloudDist = vec3(1.0); cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(maxHeight - cameraPosition.y,0.0,1.0));
	vec3 cloudDist = vec3(1.0);

	float cloudMix = clamp(smoothstep(minHeight - 400.0, minHeight + 45.0, cameraPosition.y),0.0,clamp(smoothstep(maxHeight + 300.0, maxHeight - 60.0, cameraPosition.y) ,0.0,1.0));
	cloudDist.xz = mix(vec2(255.0), vec2(5.5), cloudMix);

	// vec3 rayDirection = NormPlayerPos.xyz * (cloudheight/abs(NormPlayerPos.y)/samples);
	vec3 rayDirection = NormPlayerPos.xyz * (cloudheight/length(NormPlayerPos.xyz/min(cloudDist, 0.05*lViewPosM))/samples);
	vec3 rayPosition = getRayOrigin(rayDirection, cameraPosition, dither.y, minHeight, maxHeight);
	
	vec3 sampledSkyCol = skyFromTex(normalize(rayPosition-cameraPosition), colortex4)/1200.0;
	#ifdef SKY_GROUND
		#if CUMULONIMBUS > 1
			heightRelativeToClouds = clamp(1.0 - max(cameraPosition.y - 6000,0.0) / 100.0 ,0.0,1.0);
		#endif
		sampledSkyCol = mix(sampledSkyCol, indirectLightCol, heightRelativeToClouds);
	#endif

	sampledSkyCol *= Sky_Brightness;

	// setup for getting distance
	vec3 playerPos = mat3(gbufferModelViewInverse) * viewPos;

	#if defined DISTANT_HORIZONS || defined VOXY
		float maxLength = min(length(playerPos), max(far, dhVoxyRenderDistance))/length(playerPos);
	#else
		float maxLength = min(length(playerPos), far)/length(playerPos);
	#endif
	playerPos *= maxLength;

	float startDistance = length(playerPos);

	float sunVis = smoothstep(-0.06, 0.1, sunElevation);

	#if defined CAELUM_SUPPORT || !defined CUSTOM_MOON_ROTATION
		float moonVis = smoothstep(0.0, 0.075, -moonElevation);
	#else
		float moonVis = smoothstep(0.0, 0.2, moonVector.y);
	#endif

	#if defined EXCLUDE_WRITE_TO_LUT && defined USE_CUSTOM_CLOUD_LIGHTING_COLORS
		directLightCol = dot(directLightCol,vec3(0.21, 0.72, 0.07)) * vec3(DIRECTLIGHT_CLOUDS_R,DIRECTLIGHT_CLOUDS_G,DIRECTLIGHT_CLOUDS_B);
		directLightCol2 = dot(directLightCol2,vec3(0.21, 0.72, 0.07)) * vec3(DIRECTLIGHT_CLOUDS_R,DIRECTLIGHT_CLOUDS_G,DIRECTLIGHT_CLOUDS_B);
		indirectLightCol = dot(indirectLightCol,vec3(0.21, 0.72, 0.07)) * vec3(INDIRECTLIGHT_CLOUDS_R,INDIRECTLIGHT_CLOUDS_G,INDIRECTLIGHT_CLOUDS_B);
	#endif

	///------- do color stuff outside of the raymarcher loop
	// vec3 sunScattering = directLightCol * (phaseCloud(SdotV, 0.85) + phaseCloud(SdotV, 0.75));
	// vec3 sunMultiScattering = directLightCol;
	// vec3 moonScattering = directLightCol2 * (phaseCloud(SdotV2, 0.85) + phaseCloud(SdotV2, 0.75));
	// vec3 moonMultiScattering = directLightCol2;

	// the idea is to interpolate between 4 HG function calls with different G parameters

	float backScatterPhase = 0.0;
	vec4 phaseLevels = vec4(0.0);
	
	if(sunVis > 0.0) {
		backScatterPhase = phaseCloud(-SdotV, 0.25) * 2.0;
		phaseLevels = vec4(phaseCloud(SdotV, 0.80), phaseCloud(SdotV, 0.55), phaseCloud(SdotV, 0.35), phaseCloud(SdotV, 0.10));
	}

	float backScatterPhase2 = 0.0;
	vec4 phaseLevels2 = vec4(0.0);

	if(moonVis > 0.0) {
		backScatterPhase2 = phaseCloud(-SdotV2, 0.25) * 2.0;
		phaseLevels2 = vec4(phaseCloud(SdotV2, 0.80), phaseCloud(SdotV2, 0.55), phaseCloud(SdotV2, 0.35), phaseCloud(SdotV2, 0.10));
	}

	// backScatterPhase = SdotV;

	vec3 sunScattering = directLightCol * sunVis * sunVis;
	vec3 moonScattering = directLightCol2 * moonVis * moonVis * (1.0 - sunVis * sunVis);

	vec3 skyScattering = indirectLightCol * (1.0 + sunVis);

	// vec3 moonScattering3 = moonScattering * moonVis;	
	// vec3 moonMultiScattering3 = moonMultiScattering * moonVis;
	// 
	// moonVis = moonVis * moonVis;
	// vec3 sunScattering2 = sunScattering * sunVis;
	// vec3 sunMultiScattering2 = sunMultiScattering * sunVis;
	// vec3 moonScattering2 = moonScattering * moonVis;
	// vec3 moonMultiScattering2 = moonMultiScattering * moonVis;

	bool mixBelowLayer0 = cameraPosition.y < CloudLayer0_height + CloudLayer0_tallness;
	bool mixBelowLayer1 = cameraPosition.y < CloudLayer1_height;

	

   	////-------  RENDER SMALL CUMULUS CLOUDS
		vec4 smallCumulusClouds = cloudColorOriginal;

		vec2 cloudLayer0_Distance = vec2(startDistance, 1.0);
		#ifdef CloudLayer0
			#if defined CUMULONIMBUS_LIGHTNING && CUMULONIMBUS > 0
				float smallCumulusDistance = length(rayPosition - cameraPosition);
			#endif

			smallCumulusClouds = raymarchCloud(SMALLCUMULUS_LAYER, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, unsignedSunVec, unsignedMoonVec, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer0_Distance, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2);
			cloudColor.a *= smallCumulusClouds.a;
		#endif

	////------- RENDER LARGE CUMULUS CLOUDS
		vec4 largeCumulusClouds = cloudColorOriginal;

		#ifdef CloudLayer1
			vec2 cloudLayer1_Distance = vec2(startDistance, 1.0);
			if(cloudColor.a > 1e-5 || !mixBelowLayer1) {
				cloudheight = CloudLayer1_tallness;
				minHeight = CloudLayer1_height;
				maxHeight = cloudheight + minHeight;

				cloudMix = clamp(smoothstep(minHeight - 400.0, minHeight + 45.0, cameraPosition.y),0.0,clamp(smoothstep(maxHeight + 300.0, maxHeight - 60.0, cameraPosition.y) ,0.0,1.0));
				cloudDist.xz = mix(vec2(255.0), vec2(5.0), cloudMix);
				rayDirection = NormPlayerPos.xyz * (cloudheight/length(NormPlayerPos.xyz/cloudDist)/samples);
				rayPosition = getRayOrigin(rayDirection, cameraPosition, dither.y, minHeight, maxHeight);

				largeCumulusClouds = raymarchCloud(LARGECUMULUS_LAYER, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, unsignedSunVec, unsignedMoonVec, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer1_Distance, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2);
				cloudColor.a *= largeCumulusClouds.a;
			}
			#if defined CUMULONIMBUS_LIGHTNING && CUMULONIMBUS > 0
				float largeCumulusDistance = length(rayPosition - cameraPosition);
			#endif
		#endif

	////------- RENDER CUMULONIMBUS CLOUDS
		vec4 cumulonimbusClouds = cloudColorOriginal;

		#if CUMULONIMBUS > 0
			vec2 cloudLayer4_Distance = vec2(startDistance, 1.0);
			if((cloudColor.a > 1e-5) || !mixBelowLayer0) {
				cloudheight = 4000;
				minHeight = 600;
				maxHeight = cloudheight + minHeight;
				int cumulonimbusSamples = 2*samples;
				
				cloudDist.xz = vec2(8.0);
				rayDirection = NormPlayerPos.xyz * (cloudheight/length(NormPlayerPos.xyz/cloudDist)/cumulonimbusSamples);
				rayPosition = getRayOrigin(rayDirection, cameraPosition, dither.y, minHeight, maxHeight);

				cumulonimbusClouds = raymarchCloud(CUMULONIMBUS_LAYER, cumulonimbusSamples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, unsignedSunVec, unsignedMoonVec, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer4_Distance, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2);
				cloudColor.a *= cumulonimbusClouds.a;
			}
			#if defined CUMULONIMBUS_LIGHTNING && CUMULONIMBUS > 0
				float cumulonimbusDistance = length(rayPosition - cameraPosition);
			#endif
		#endif

	// #if defined CAELUM_SUPPORT || !defined CUSTOM_MOON_ROTATION
	// 	moonVis = smoothstep(-0.04, 0.015, -moonElevation);
	// #else
	// 	moonVis = smoothstep(0.0, 0.2, moonVector.y);
	// #endif
	// 
	// moonScattering2 = moonScattering * moonVis;
	// moonMultiScattering2 = moonMultiScattering * moonVis;
	
   	////------- RENDER ALTOSTRATUS CLOUDS
		vec4 altoStratusClouds = cloudColorOriginal;
		
		#ifdef CloudLayer2
			vec2 cloudLayer2_Distance = vec2(startDistance, 1.0);
			if(cloudColor.a > 1e-5) {
				cloudheight = 5.0;
				minHeight = CloudLayer2_height;
				maxHeight = cloudheight + minHeight;
				
				cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(cameraPosition.y - minHeight,0.0,clamp((maxHeight-15) - cameraPosition.y ,0.0,1.0)));
				rayDirection = NormPlayerPos.xyz * (cloudheight/length(NormPlayerPos.xyz/cloudDist));
				rayPosition = getRayOrigin(rayDirection, cameraPosition, dither.y, minHeight, maxHeight);

				altoStratusClouds = raymarchCloud(ALTOSTRATUS_LAYER, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, unsignedSunVec, unsignedMoonVec, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer2_Distance, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2);
				cloudColor.a *= altoStratusClouds.a;
			}
		#endif

	////------- RENDER CIRRUS CLOUDS
		vec4 cirrusClouds = cloudColorOriginal;
		
		#ifdef CloudLayer3
			vec2 cloudLayer3_Distance = vec2(startDistance, 1.0);
			if(cloudColor.a > 1e-5) {
				cloudheight = 5.0;
				minHeight = CloudLayer3_height;
				maxHeight = cloudheight + minHeight;
				
				cloudDist.xz = mix(vec2(255.0), vec2(5.0), clamp(cameraPosition.y - minHeight,0.0,clamp((maxHeight-15) - cameraPosition.y ,0.0,1.0)));
				rayDirection = NormPlayerPos.xyz * (cloudheight/length(NormPlayerPos.xyz/cloudDist));
				rayPosition = getRayOrigin(rayDirection, cameraPosition, dither.y, minHeight, maxHeight);

				cirrusClouds = raymarchCloud(CIRRUS_LAYER, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, unsignedSunVec, unsignedMoonVec, sunScattering, moonScattering, skyScattering, lViewPosM, sampledSkyCol, cloudLayer3_Distance, backScatterPhase, phaseLevels, backScatterPhase2, phaseLevels2);
				cloudColor.a *= cirrusClouds.a;
			}
		#endif

   	////------- BLEND LAYERS

	#if defined CloudLayer0 && defined CloudLayer1
		if (cameraPosition.y > CloudLayer1_height) {
			vec2 temp = cloudLayer1_Distance;
			cloudLayer1_Distance = cloudLayer0_Distance;
			cloudLayer0_Distance = temp;
		}
	#endif

	#if defined CloudLayer0
		#if defined CloudLayer1
			#if defined CloudLayer2
				#if defined CloudLayer3
					float temp = mix(cloudLayer2_Distance.x, cloudLayer3_Distance.x, cloudLayer2_Distance.y);
					temp = mix(cloudLayer1_Distance.x, temp, cloudLayer1_Distance.y);
					cloudPlaneDistance = mix(cloudLayer0_Distance.x, temp, cloudLayer0_Distance.y);
				#else
					float temp = mix(cloudLayer1_Distance.x, cloudLayer2_Distance.x, cloudLayer1_Distance.y);
					cloudPlaneDistance = mix(cloudLayer0_Distance.x, temp, cloudLayer0_Distance.y);
				#endif
			#else
				#if defined CloudLayer3
					float temp = mix(cloudLayer1_Distance.x, cloudLayer3_Distance.x, cloudLayer1_Distance.y);
					cloudPlaneDistance = mix(cloudLayer0_Distance.x, temp, cloudLayer0_Distance.y);
				#else
					cloudPlaneDistance = mix(cloudLayer0_Distance.x, cloudLayer1_Distance.x, cloudLayer0_Distance.y);
				#endif
			#endif
		#else
			#if defined CloudLayer2
				#if defined CloudLayer3
					float temp = mix(cloudLayer2_Distance.x, cloudLayer3_Distance.x, cloudLayer2_Distance.y);
					cloudPlaneDistance = mix(cloudLayer0_Distance.x, temp, cloudLayer0_Distance.y);
				#else
					cloudPlaneDistance = mix(cloudLayer0_Distance.x, cloudLayer2_Distance.x, cloudLayer0_Distance.y);
				#endif
			#else
				#if defined CloudLayer3
					cloudPlaneDistance = mix(cloudLayer0_Distance.x, cloudLayer3_Distance.x, cloudLayer0_Distance.y);
				#else
					cloudPlaneDistance = cloudLayer0_Distance.x;
				#endif
			#endif
		#endif
	#else
		#if defined CloudLayer1
			#if defined CloudLayer2
				#if defined CloudLayer3
					float temp = mix(cloudLayer2_Distance.x, cloudLayer3_Distance.x, cloudLayer2_Distance.y);
					cloudPlaneDistance = mix(cloudLayer1_Distance.x, temp, cloudLayer1_Distance.y);
				#else
					cloudPlaneDistance = mix(cloudLayer1_Distance.x, cloudLayer2_Distance.x, cloudLayer1_Distance.y);
				#endif
			#else
				#if defined CloudLayer3
					cloudPlaneDistance = mix(cloudLayer1_Distance.x, cloudLayer3_Distance.x, cloudLayer1_Distance.y);
				#else
					cloudPlaneDistance = cloudLayer1_Distance.x;
				#endif
			#endif
		#else
			#if defined CloudLayer2
				#if defined CloudLayer3
					cloudPlaneDistance = mix(cloudLayer2_Distance.x, cloudLayer3_Distance.x, cloudLayer2_Distance.y);
				#else
					cloudPlaneDistance = cloudLayer2_Distance.x;
				#endif
			#else
				#if defined CloudLayer3
					cloudPlaneDistance = cloudLayer3_Distance.x;
				#else
					cloudPlaneDistance = 0.0;
				#endif
			#endif
		#endif
	#endif



	#if defined CUMULONIMBUS_LIGHTNING && CUMULONIMBUS > 0
		#ifdef CloudLayer0
			if (smallCumulusClouds.a < 1.0) cloudDistance.r = smallCumulusDistance;
		#endif

		#ifdef CloudLayer1
			if (largeCumulusClouds.a < 1.0) cloudDistance.r = largeCumulusDistance;
		#endif

		#if defined CloudLayer0 && defined CloudLayer1
		if(cameraPosition.y < CloudLayer1_height) {
			if (largeCumulusClouds.a < 1.0) cloudDistance.r = largeCumulusDistance;
			if (smallCumulusClouds.a < 1.0) cloudDistance.r = smallCumulusDistance;
		} else {
			if (smallCumulusClouds.a < 1.0) cloudDistance.r = smallCumulusDistance;
			if (largeCumulusClouds.a < 1.0) cloudDistance.r = largeCumulusDistance;
		}
		#endif

		if (cumulonimbusClouds.a < 1.0) cloudDistance.g = cumulonimbusDistance;

		if(cloudDistance.r > 15000.0) cloudDistance.r = 0.0;
		if(cloudDistance.g > 15000.0) cloudDistance.g = 0.0;
	#endif

	#ifdef CloudLayer3
		cloudColor.rgb = cirrusClouds.rgb;
	#endif
	#ifdef CloudLayer2
		cloudColor.rgb *= altoStratusClouds.a;
		cloudColor.rgb += altoStratusClouds.rgb;
	#endif

	if(mixBelowLayer0) {
		#if CUMULONIMBUS > 0
			cloudColor.rgb *= cumulonimbusClouds.a;
			cloudColor.rgb += cumulonimbusClouds.rgb;
		#endif
		#ifdef CloudLayer1
			cloudColor.rgb *= largeCumulusClouds.a;
			cloudColor.rgb += largeCumulusClouds.rgb;
		#endif
		#ifdef CloudLayer0
			cloudColor.rgb *= smallCumulusClouds.a;
			cloudColor.rgb += smallCumulusClouds.rgb;
		#endif
	} else if(mixBelowLayer1) {
		#ifdef CloudLayer0
			cloudColor.rgb *= smallCumulusClouds.a;
			cloudColor.rgb += smallCumulusClouds.rgb;
		#endif	
		#if CUMULONIMBUS > 0
			cloudColor.rgb *= cumulonimbusClouds.a;
			cloudColor.rgb += cumulonimbusClouds.rgb;
		#endif
		#ifdef CloudLayer1
			cloudColor.rgb *= largeCumulusClouds.a;
			cloudColor.rgb += largeCumulusClouds.rgb;
		#endif
	} else {
		#ifdef CloudLayer0
			cloudColor.rgb *= smallCumulusClouds.a;
			cloudColor.rgb += smallCumulusClouds.rgb;
		#endif	
		#ifdef CloudLayer1
			cloudColor.rgb *= largeCumulusClouds.a;
			cloudColor.rgb += largeCumulusClouds.rgb;
		#endif
		#if CUMULONIMBUS > 0
			cloudColor.rgb *= cumulonimbusClouds.a;
			cloudColor.rgb += cumulonimbusClouds.rgb;
		#endif
	}
	color = cloudColor.rgb;
	totalAbsorbance = cloudColor.a;

	return vec4(color, totalAbsorbance);
}
#endif

#endif

#ifdef CLOUD_SHADOW_PASS

float raymarchCloudSimple(
	int LayerIndex,
	int samples,
	vec3 rayPosition,
	vec3 rayDirection,
	float dither,

	float minHeight,
	float maxHeight,

	vec3 startPos
){
	float totalAbsorbance = 1.0;
	float distanceFactor = length(rayDirection);

	float densityTresholdCheck = 0.0;

	if(LayerIndex == SMALLCUMULUS_LAYER) densityTresholdCheck = 0.06;
	if(LayerIndex == LARGECUMULUS_LAYER || LayerIndex == CUMULONIMBUS_LAYER) densityTresholdCheck = 0.02;
	if(LayerIndex == ALTOSTRATUS_LAYER) densityTresholdCheck = 0.01;

	densityTresholdCheck = mix(1e-5, densityTresholdCheck, dither);

	if(LayerIndex == ALTOSTRATUS_LAYER){
		vec3 newPos = rayPosition - startPos;

		float density = SC_altostratus.y;
		density *= smoothstep(CloudLayer2_distance, CloudLayer2_distance*0.5, length(newPos));

		if (density == 0.0) return totalAbsorbance;

		bool ifAboveOrBelowPlane = max(mix(-1.0, 1.0, clamp(startPos.y - minHeight,0.0,1.0)) * normalize(rayDirection).y + 0.0001,0.0) > 0.0;

		if(ifAboveOrBelowPlane) return totalAbsorbance;

		float shape = getCloudShape(LayerIndex, 1, rayPosition, minHeight, maxHeight);
		float shapeWithDensity = shape*density;

		// check if the pixel has visible clouds before doing work.
		if(shapeWithDensity > 1e-5){
			float densityCoeff = exp(-distanceFactor*shapeWithDensity);			
			totalAbsorbance *= densityCoeff;
		}

		return totalAbsorbance;
	}


	if(LayerIndex < ALTOSTRATUS_LAYER){

		vec3 newPos = rayPosition - startPos;

		float densityLarge = getRainDensity(SC_largeCumulus.y);

		float density = 0.0;

		if(LayerIndex == SMALLCUMULUS_LAYER) density = getRainDensity(SC_smallCumulus.y) * smoothstep(CloudLayer0_distance, CloudLayer0_distance*0.5, length(newPos));
		if(LayerIndex == LARGECUMULUS_LAYER) density = getRainDensity(SC_largeCumulus.y) * smoothstep(CloudLayer1_distance, CloudLayer1_distance*0.5, length(newPos));
		if(LayerIndex == CUMULONIMBUS_LAYER) density = 0.8;

		if (density < 0.01) return totalAbsorbance;

		float tallness = maxHeight - minHeight;

		for(int i = 0; i < samples; i++) {
			newPos = rayPosition - startPos;

			float rayHeightInCloud = rayPosition.y - minHeight;

			// check if the pixel is in the bounding box before doing work.
			if(clamp(rayPosition.y - maxHeight,0.0,1.0) < 1.0 && clamp(rayHeightInCloud,0.0,1.0) > 0.0){
				
				float shape = 0.0;
				float isLarge = 1.0;
				#if CUMULONIMBUS > 0
				if (LayerIndex != CUMULONIMBUS_LAYER) {
				#endif
					shape = getCloudShape(LayerIndex, 1, rayPosition, minHeight, maxHeight);
				#if CUMULONIMBUS > 0
				} else {
					vec2 cumulonimbusCloud = getCumulonimbusShape(1, rayPosition, minHeight, maxHeight);
					shape = cumulonimbusCloud.x;
					isLarge = 1.0 + 4.0 * cumulonimbusCloud.y;
				}
				#endif
				float shapeWithDensity = shape*density*isLarge;
				float shapeWithDensityFaded = shape*density * pow(clamp((rayHeightInCloud)/(max(tallness,1.0)*0.25),0.0,1.0),2.0);

				// check if the pixel has visible clouds before doing work.
				if(shapeWithDensityFaded > 1e-5){
					float densityCoeff = exp(-distanceFactor*shapeWithDensityFaded);					
					totalAbsorbance *= densityCoeff;
					
					// check if you can see through the cloud on the pixel before doing the next iteration
					if (totalAbsorbance < 1e-5) break;
					
				}
			}
			
			rayPosition += rayDirection;
			
		}
	}
	

	return totalAbsorbance;
}

vec4 GetVolumetricCloudsSimple(
	vec2 dither,
	vec3 lightDir,
	vec2 offset,
	vec3 startPos
){
	float totalAbsorbance = 1.0;

	float heightRelativeToClouds = clamp(1.0 - max(cameraPosition.y - CloudLayer0_height,0.0) / 100.0 ,0.0,1.0);

	vec3 NormPlayerPos = lightDir;

	#ifdef SKY_GROUND
		NormPlayerPos.y += 0.03 * heightRelativeToClouds;
	#endif

	int samples = 5;
	vec3 cloudDist = vec3(1.0);

	vec3 rayDirection;
	vec3 rayPosition;

	float cloudheight;
	float minHeight;
	float maxHeight;

	float altoStratusClouds = 1.0;
	#ifdef CloudLayer2
		cloudheight = 5.0;
		minHeight = CloudLayer2_height;
		maxHeight = cloudheight + minHeight;
		
		cloudDist.xz = vec2(255.0);
		rayDirection = NormPlayerPos.xyz * (cloudheight/length(NormPlayerPos.xyz/cloudDist));
		rayPosition = getRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight);

		rayPosition.xz += offset;

		altoStratusClouds = raymarchCloudSimple(ALTOSTRATUS_LAYER, 1, rayPosition, rayDirection, dither.x, minHeight, maxHeight, startPos);
		totalAbsorbance *= altoStratusClouds;
	#endif

	float largeCumulusClouds = 1.0;
	#ifdef CloudLayer1
		if(totalAbsorbance > 1e-5) {
			cloudheight = CloudLayer1_tallness;
			minHeight = CloudLayer1_height;
			maxHeight = cloudheight + minHeight;

			cloudDist.xz = vec2(255.0);
			rayDirection = NormPlayerPos.xyz * (cloudheight/length(NormPlayerPos.xyz/cloudDist)/samples);
			rayPosition = getRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight);

			rayPosition.xz += offset;

			largeCumulusClouds = raymarchCloudSimple(LARGECUMULUS_LAYER, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, startPos);
			totalAbsorbance *= largeCumulusClouds;
		}
	#endif

	float smallCumulusClouds = 1.0;
	#ifdef CloudLayer0
		if(totalAbsorbance > 1e-5) {
			cloudheight = CloudLayer0_tallness / CloudLayer0_scale;
			minHeight = CloudLayer0_height;
			maxHeight = cloudheight + minHeight;

			#if defined OVERWORLD_SHADER && defined AETHER_FLAG
				minHeight = CloudLayer0_height - 350.0;
				maxHeight = cloudheight + minHeight;
			#endif

			cloudDist.xz = vec2(255.0);
			rayDirection = NormPlayerPos.xyz * (cloudheight/length(NormPlayerPos.xyz/cloudDist)/samples);
			rayPosition = getRayOrigin(rayDirection, startPos, dither.y, minHeight, maxHeight);

			rayPosition.xz += offset;

			smallCumulusClouds = raymarchCloudSimple(SMALLCUMULUS_LAYER, samples, rayPosition, rayDirection, dither.x, minHeight, maxHeight, startPos);
			totalAbsorbance *= smallCumulusClouds;
		}
	#endif



	return vec4(smallCumulusClouds, largeCumulusClouds, altoStratusClouds, totalAbsorbance);
}

#endif