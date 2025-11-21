precision highp float;

uniform sampler2D u_baseTexture;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_cycle;
uniform float u_elapsed; // Continuous time for seamless rotation
uniform float u_acceleration;
uniform float u_warp;
uniform float u_jetIntensity;

varying vec2 v_uv;

const float PI = 3.141592653589793;
const float TAU = 6.283185307179586;
const float EVENT_HORIZON = 0.22;
const float PHOTON_SPHERE = 0.29;
const float ISCO_RADIUS = 0.42;

float saturate(float v) {
    return clamp(v, 0.0, 1.0);
}

vec2 rotate(vec2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

vec2 swirl(vec2 uv, float strength) {
    vec2 p = uv * 2.0 - 1.0;
    float r = length(p);
    float theta = atan(p.y, p.x);
    // Faster swirl - increased multiplier from 1.0 to 2.8
    float s = strength * smoothstep(0.08, 1.0, r) * 2.8;
    theta += s;
    vec2 rotated = vec2(cos(theta), sin(theta)) * r;
    return rotated * 0.5 + 0.5;
}

vec2 lensWarp(vec2 uv, float strength) {
    vec2 p = uv * 2.0 - 1.0;
    float r2 = dot(p, p);
    float factor = 1.0 + strength / (r2 + 0.22);
    p *= factor;
    return p * 0.5 + 0.5;
}

vec2 tiltedPolar(vec2 uv) {
    vec2 p = uv * 2.0 - 1.0;
    p = rotate(p, 0.18);
    p.y *= 0.9;
    p.x *= 1.04;
    float r = length(p);
    float angle = atan(p.y, p.x);
    return vec2(r, angle);
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 uv) {
    vec2 id = floor(uv);
    vec2 f = fract(uv);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(id);
    float b = hash(id + vec2(1.0, 0.0));
    float c = hash(id + vec2(0.0, 1.0));
    float d = hash(id + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Optimized fbm - reduced from 6 to 3 octaves for performance
float fbm(vec2 uv) {
    float value = 0.0;
    float amplitude = 0.55;
    float frequency = 1.6;
    for (int i = 0; i < 3; ++i) {
        value += amplitude * noise(uv * frequency);
        frequency *= 2.02;
        amplitude *= 0.46;
    }
    return value;
}

// Fast fbm with only 2 octaves for background elements
float fbmFast(vec2 uv) {
    float value = 0.0;
    value += 0.55 * noise(uv * 1.6);
    value += 0.25 * noise(uv * 3.23);
    return value;
}

// Enhanced star field with multiple sizes and colors
float starFieldEnhanced(vec2 uv, float cycle, float density, float sizeVariation, float seed) {
    float baseAngle = cycle * TAU;
    vec2 shift = vec2(cos(baseAngle + seed), sin(baseAngle + seed)) * 0.012;
    vec2 grid = (uv + shift) * density;
    vec2 cell = floor(grid);
    vec2 local = fract(grid) - 0.5;
    float dist = length(local);
    float rnd = hash(cell + seed);
    
    // Seamless twinkle
    float twinkleSpeed = 1.2 + hash(cell + seed + 13.7) * 1.8;
    float twinklePhase = hash(cell + seed + 27.3) * TAU;
    float twinkle = 0.6 + 0.4 * cos(baseAngle * twinkleSpeed + twinklePhase);
    
    // Variable star sizes
    float starSize = 0.4 + hash(cell + seed + 41.1) * sizeVariation;
    float star = saturate(starSize - dist * (3.0 + hash(cell + seed + 55.9) * 4.0));
    
    // Variable star density
    float threshold = 1.0 - density * 0.003;
    star *= step(threshold, rnd);
    
    return star * twinkle;
}

// Optimized distant galaxy - much simpler
float distantGalaxy(vec2 uv, vec2 position, float rotation, float size, float seed) {
    vec2 p = uv - position;
    p = rotate(p, rotation);
    p.y *= 0.4;
    float dist = length(p) / size;
    
    // Just core and simple disk, no spiral arms
    float core = exp(-dist * 12.0);
    float disk = exp(-dist * 4.5) * 0.3;
    
    float galaxy = core * 0.8 + disk;
    galaxy *= smoothstep(1.5, 0.0, dist);
    
    return saturate(galaxy);
}

// Optimized nebula - use fbmFast instead of fbm
float nebulaCloud(vec2 uv, vec2 offset, float scale) {
    vec2 p = uv * scale + offset;
    float cloud = fbmFast(p * 2.5);
    return pow(saturate(cloud), 1.8);
}

// Optimized dust lanes
float dustLanes(vec2 uv, vec2 offset) {
    vec2 p = uv + offset;
    return saturate(fbmFast(vec2(p.x * 15.0, p.y * 3.0)));
}

// Optimized filaments
float filamentStructure(vec2 uv, vec2 offset, float angle) {
    vec2 p = rotate(uv + offset, angle);
    return pow(saturate(fbmFast(vec2(p.x * 25.0, p.y * 4.0))), 3.0);
}

float ringMask(float radius, float inner, float outer, float softness) {
    float innerEdge = smoothstep(inner - softness, inner + softness, radius);
    float outerEdge = smoothstep(outer - softness, outer + softness, radius);
    return saturate(innerEdge - outerEdge);
}

vec3 filmic(vec3 color) {
    color = max(vec3(0.0), color);
    return (color * (6.2 * color + 0.5)) / (color * (6.2 * color + 1.7) + 0.06);
}

vec3 samplePalette(sampler2D tex, float t) {
    vec2 baseUV = vec2(clamp(t, 0.0, 1.0), 0.5);
    vec3 accum = vec3(0.0);
    float weight = 0.0;
    for (int i = -2; i <= 2; ++i) {
        float offset = float(i) * 0.015;
        float w = 1.0 - abs(float(i)) * 0.22;
        vec2 sampleUV = vec2(clamp(baseUV.x + offset, 0.0, 1.0), clamp(baseUV.y + offset * 0.4, 0.0, 1.0));
        accum += texture2D(tex, sampleUV).rgb * w;
        weight += w;
    }
    return accum / weight;
}

vec3 sampleCombinedPalette(float t) {
    return samplePalette(u_baseTexture, t);
}

// Simple Schwarzschild-style gravitational lensing
vec2 gravitationalLens(vec2 uv, float schwarzschildRadius, float lensStrength, out float lensTerm) {
    vec2 p = uv * 2.0 - 1.0;
    float r = length(p);
    float safeR = max(r, 1e-4);
    float invR = 1.0 / safeR;
    // Bend grows quickly as we get close to the horizon, clamped to avoid tearing
    float bend = lensStrength * (schwarzschildRadius * invR * invR);
    bend = clamp(bend, 0.0, 0.85);
    float caustic = smoothstep(schwarzschildRadius * 0.75, schwarzschildRadius * 1.35, r);
    vec2 dir = p * invR;
    vec2 warped = p + dir * bend * caustic;
    lensTerm = bend * caustic;
    return warped * 0.5 + 0.5;
}

float schwarzschildRedshift(float r, float schwarzschildRadius) {
    float safeR = max(r, schwarzschildRadius + 0.01);
    float redshift = sqrt(1.0 - schwarzschildRadius / safeR);
    return clamp(redshift, 0.35, 1.0);
}

float relativisticBeaming(float cosTheta, float beta) {
    float gamma = inversesqrt(max(1e-5, 1.0 - beta * beta));
    float doppler = 1.0 / (gamma * (1.0 - beta * cosTheta));
    return pow(doppler, 3.0);
}

void main() {
    float loopAngle = u_time;
    float cycle = u_cycle;
    vec2 rawUV = v_uv;

    float schwarzschildRadius = PHOTON_SPHERE;
    float lensTerm = 0.0;
    float lensStrength = mix(0.38, 0.65, u_warp);
    vec2 lensUV = gravitationalLens(rawUV, schwarzschildRadius, lensStrength, lensTerm);
    vec2 centered = lensUV * 2.0 - 1.0;

    // Use smooth periodic functions for seamless looping - no discontinuities
    vec2 orbitA = vec2(cos(loopAngle), sin(loopAngle));
    vec2 orbitB = vec2(cos(loopAngle * 0.5), sin(loopAngle * 0.5));
    vec2 orbitC = vec2(cos(loopAngle * 0.3), sin(loopAngle * 0.3));
    float speedInfluence = mix(0.85, 1.55, saturate(u_acceleration * 0.45));

    vec3 paletteShadow = sampleCombinedPalette(0.05);
    vec3 paletteMid = sampleCombinedPalette(0.3);
    vec3 paletteBright = sampleCombinedPalette(0.72);
    vec3 paletteGlow = sampleCombinedPalette(0.88);

    // ========== COSMIC BACKGROUND WITH LENSING ==========
    vec3 background = paletteShadow * 0.02;

    vec2 galaxyUV = lensUV + orbitA * 0.006;
    float nebula1 = nebulaCloud(galaxyUV, vec2(0.3, 0.1), 2.0);
    float nebula2 = nebulaCloud(galaxyUV, vec2(-0.4, 0.5), 1.5);
    float dust = dustLanes(galaxyUV, orbitB * 0.01);

    vec3 nebulaColor1 = mix(paletteShadow, paletteMid * vec3(0.8, 0.6, 1.2), 0.2) * nebula1 * 0.018;
    vec3 nebulaColor2 = mix(paletteShadow, paletteMid * vec3(1.2, 0.7, 0.8), 0.25) * nebula2 * 0.014;
    vec3 dustColor = paletteShadow * 0.08 * dust;

    float radialFalloff = pow(saturate(1.25 - length(centered)), 2.2);

    background += nebulaColor1 + nebulaColor2;
    background -= dustColor * 0.32;
    background += paletteMid * 0.012 * radialFalloff;

    float galaxy1 = distantGalaxy(lensUV, vec2(0.35, 0.45), 0.3, 0.08, 1.0);
    vec3 galaxyColor1 = mix(vec3(1.0, 0.9, 0.7), vec3(1.0, 1.0, 1.0), 0.6) * galaxy1 * 0.025;
    background += galaxyColor1;

    vec2 starGrid1 = lensUV * 300.0;
    vec2 starCell1 = floor(starGrid1);
    float starRnd1 = hash(starCell1);
    float star1 = step(0.99, starRnd1) * saturate(1.0 - length(fract(starGrid1) - 0.5) * 8.0);

    vec2 starGrid2 = lensUV * 450.0;
    vec2 starCell2 = floor(starGrid2);
    float starRnd2 = hash(starCell2);
    float star2 = step(0.995, starRnd2) * saturate(1.0 - length(fract(starGrid2) - 0.5) * 10.0);

    float twinkle1 = 0.6 + 0.4 * sin(starRnd1 * 100.0);
    float twinkle2 = 0.7 + 0.3 * sin(starRnd2 * 100.0);
    background += vec3(0.95, 1.0, 1.1) * star1 * twinkle1 * 2.1;
    background += vec3(1.1, 0.98, 0.9) * star2 * twinkle2 * 1.8;

    vec2 starGrid3 = lensUV * 600.0;
    vec2 starCell3 = floor(starGrid3);
    float starRnd3 = hash(starCell3);
    float star3 = step(0.997, starRnd3) * saturate(1.0 - length(fract(starGrid3) - 0.5) * 12.0);
    float twinkle3 = 0.65 + 0.35 * sin(starRnd3 * 100.0);
    background += vec3(1.1, 1.04, 1.0) * star3 * twinkle3 * 1.6;

    vec2 starGrid4 = lensUV * 850.0;
    vec2 starCell4 = floor(starGrid4);
    float starRnd4 = hash(starCell4);
    float star4 = step(0.9985, starRnd4) * saturate(1.0 - length(fract(starGrid4) - 0.5) * 14.0);
    float twinkle4 = 0.7 + 0.3 * sin(starRnd4 * 120.0);
    background += vec3(1.2, 1.05, 0.95) * star4 * twinkle4 * 2.2;

    float milkyWay = nebulaCloud(lensUV, vec2(0.0, 0.0), 1.5) * 0.028;
    background += paletteMid * milkyWay;

    float inflowRadius = length(centered);
    float inflowMask = smoothstep(0.78, 1.3, inflowRadius) * (1.0 - smoothstep(1.3, 1.62, inflowRadius));
    float inflowAngle = atan(centered.y, centered.x);
    float inflowPhase = cycle * TAU;
    float inflowSpiral = fbm(vec2(inflowRadius * 2.8 - inflowPhase * 1.8, inflowAngle * 3.6));
    float inflowFine = fbmFast(vec2(inflowRadius * 22.0, inflowAngle * 10.0 - inflowPhase * 1.8));
    float inflowShear = 0.6 + 0.4 * sin(inflowAngle * 2.8 - inflowPhase * 1.5);
    float inflowCurl = 0.5 + 0.5 * fbmFast(vec2(centered * 7.5 - inflowPhase));
    float inflowIntensity = inflowMask * (0.08 + 0.38 * inflowSpiral + 0.22 * inflowFine) * inflowShear * inflowCurl;
    vec3 inflowColor = mix(paletteShadow, paletteMid, 0.38);
    background += inflowColor * inflowIntensity * 0.32;

    float mirageMask = smoothstep(PHOTON_SPHERE, PHOTON_SPHERE * 1.8, inflowRadius);
    float mirageNoise = fbmFast(lensUV * 3.5 + orbitC * 0.5);
    background += paletteBright * 0.015 * mirageNoise * mirageMask * (0.5 + lensTerm);

    float lensGlow = exp(-pow(max(0.0, abs(inflowRadius - schwarzschildRadius) * 12.0), 1.1));
    background += paletteMid * lensGlow * 0.05 * (0.7 + lensTerm);

    // ========== GEOMETRY AND ORBITAL SETUP ==========
    vec2 warped = mix(lensUV, lensWarp(lensUV, 0.08 + 0.05 * u_warp), 0.35);
    vec2 swirled = mix(warped, swirl(warped, 0.08 + u_warp * 0.18), 0.55);
    vec2 polar = tiltedPolar(swirled);
    float r = polar.x;
    float baseAngle = polar.y;
    float angle = baseAngle - u_elapsed * 0.15; // counter-clockwise

    float inclination = 0.72;
    float velBeta = mix(0.55, 0.72, saturate(u_acceleration * 0.55));
    float cosView = sin(angle) * sin(inclination);
    float beaming = relativisticBeaming(cosView, velBeta);
    beaming = clamp(beaming, 0.4, 3.6);
    float spectralShift = clamp(pow(beaming, 0.2), 0.75, 1.35);
    float gravFade = schwarzschildRedshift(r, schwarzschildRadius);

    float viewTilt = sin(angle + 0.35);
    float jetBias = saturate(0.6 + 0.4 * viewTilt);

    // Black hole shadow and near-horizon lensing
    float holeMask = smoothstep(EVENT_HORIZON * 0.7, PHOTON_SPHERE, r);
    float horizonDetail = fbm(vec2(angle * 12.0, r * 55.0));
    float horizonMicroDetail = fbmFast(vec2(angle * 26.0, r * 92.0));
    float lensingRing = smoothstep(PHOTON_SPHERE - 0.035, PHOTON_SPHERE - 0.01, r) * (1.0 - smoothstep(PHOTON_SPHERE + 0.01, PHOTON_SPHERE + 0.05, r));
    lensingRing *= 0.65 + 0.35 * horizonDetail;
    float photonShadow = smoothstep(PHOTON_SPHERE - 0.015, PHOTON_SPHERE + 0.01, r) * (1.0 - smoothstep(PHOTON_SPHERE + 0.02, PHOTON_SPHERE + 0.07, r));
    photonShadow *= 0.55 + 0.25 * horizonDetail + 0.2 * horizonMicroDetail;

    background *= (1.0 - lensingRing * 0.25);
    background *= (1.0 - photonShadow * 0.4);
    background *= holeMask;
    background += paletteShadow * lensingRing * 0.08 * (0.6 + lensTerm);

    // ========== PHOTON SPHERE ==========
    float photonMask = ringMask(r, PHOTON_SPHERE - 0.01, PHOTON_SPHERE + 0.07, 0.012);
    float photonTurbulence = fbm(vec2(angle * 8.0, r * 60.0));
    float photonDetail = fbmFast(vec2(angle * 20.0, r * 100.0));
    float photonBrightness = 1.0 + 0.32 * photonTurbulence + 0.16 * photonDetail;
    float photonBeaming = mix(0.78, 1.6, saturate(0.5 + 0.5 * cosView));

    vec3 photonRing = paletteGlow * 2.3 * photonMask * photonBrightness * photonBeaming * (0.9 + lensTerm);
    float secondaryMask = ringMask(r, PHOTON_SPHERE + 0.06, PHOTON_SPHERE + 0.12, 0.008);
    vec3 secondaryRing = paletteGlow * 1.1 * secondaryMask * (0.5 + 0.6 * photonTurbulence) * (0.7 + lensTerm * 0.8);

    // ========== ACCRETION DISK ==========
    float diskBand = smoothstep(PHOTON_SPHERE + 0.005, ISCO_RADIUS, r) * (1.0 - smoothstep(0.5, 0.92, r));
    float diskEdgeDetail = fbmFast(vec2(angle * 8.0, r * 30.0));
    diskBand *= 0.92 + 0.08 * diskEdgeDetail;

    float spiralLarge = fbm(vec2(r * 11.0, angle * 6.0));
    float spiralMedium = fbm(vec2(r * 22.0, angle * 12.0));
    float detailFine = fbmFast(vec2(r * 45.0, angle * 22.0));
    float detailUltra = fbmFast(vec2(r * 70.0, angle * 31.0));
    float diskStructure = spiralLarge * 0.4 + spiralMedium * 0.27 + detailFine * 0.22 + detailUltra * 0.11;

    float tempProfile = pow(max(r, EVENT_HORIZON + 0.02), -0.75);
    float temp01 = clamp((tempProfile - 0.9) / 2.4, 0.0, 1.0);

    float innerHeat = smoothstep(0.56, 0.32, r);
    float hotSpots = pow(saturate(fbm(vec2(r * 38.0, angle * 15.0))), 2.0) * innerHeat;

    float diskEnergy = diskBand * (0.65 + diskStructure * 0.65);
    diskEnergy *= beaming * gravFade * speedInfluence;
    diskEnergy *= 1.0 + innerHeat * 0.85 + hotSpots * 0.55;
    diskEnergy *= 1.35;

    vec3 warmTint = vec3(1.35, 0.82, 0.5);
    vec3 coolTint = vec3(0.5, 0.7, 1.2);
    vec3 dopplerTint = mix(coolTint, warmTint, saturate(0.5 + 0.5 * cosView));

    vec3 diskBase = sampleCombinedPalette(clamp(temp01 * spectralShift, 0.0, 1.0)) * dopplerTint;
    vec3 diskHighlights = mix(paletteBright, paletteGlow, clamp(detailFine * 0.9 + detailUltra * 0.3, 0.0, 1.0));
    vec3 hotSpotColor = paletteGlow * 1.35 * hotSpots;

    float innerRim = smoothstep(PHOTON_SPHERE + 0.01, PHOTON_SPHERE + 0.05, r) * (1.0 - smoothstep(PHOTON_SPHERE + 0.06, PHOTON_SPHERE + 0.1, r));
    float rimDetail = fbmFast(vec2(angle * 19.0, r * 62.0));
    vec3 rimGlow = paletteGlow * innerRim * mix(1.0, 2.2, saturate(0.5 + 0.5 * cosView)) * (1.1 + rimDetail * 0.45);

    vec3 diskColor = mix(diskBase, diskHighlights, clamp(diskEnergy * 0.7, 0.0, 1.0));
    diskColor += hotSpotColor;
    vec3 disk = diskColor * diskEnergy * 1.8 + rimGlow;

    float farSideMask = smoothstep(PHOTON_SPHERE + 0.03, ISCO_RADIUS - 0.03, r) * smoothstep(-0.38, 0.3, centered.y);
    vec3 farSide = diskBase * diskEnergy * farSideMask * (0.18 + lensTerm * 0.7);
    disk += farSide;

    // ========== OUTER DISK / ENVELOPE ==========
    float outerWarpSeed = fbmFast(vec2(baseAngle * 5.0, r * 14.0 - cycle * 3.2));
    float outerWarp = 0.025 * (outerWarpSeed - 0.5);
    float outerGlowMask = smoothstep(0.34 + outerWarp, 0.54 + outerWarp, r) * (1.0 - smoothstep(0.6 + outerWarp, 0.9 + outerWarp, r));
    float outerDetail = fbmFast(vec2(baseAngle * 5.2, r * 18.0));
    vec3 outerGlow = mix(paletteShadow, paletteMid, 0.32 + outerDetail * 0.12) * outerGlowMask * (0.2 + outerDetail * 0.06);
    float outerClumps = fbm(vec2(baseAngle * 2.6 + cycle * 0.6, r * 11.0));
    float outerUneven = smoothstep(0.2, 0.82, outerClumps + 0.22 * sin(baseAngle * 2.2 + cycle * TAU * 0.28));
    vec3 outerClouds = mix(vec3(0.35, 0.42, 0.5), paletteMid, 0.45 + outerClumps * 0.25) * outerGlowMask * outerUneven * 0.24;
    outerGlow += outerClouds;

    // ========== HALO ==========
    float haloMask = smoothstep(0.27, 0.34, r) * (1.0 - smoothstep(0.37, 0.48, r));
    float haloDetail = fbmFast(vec2(baseAngle * 9.0 + cycle * 0.5, r * 35.0));
    vec3 halo = mix(paletteShadow, paletteMid, 0.26 + haloDetail * 0.1) * haloMask * (0.18 + haloDetail * 0.06);

    // ========== JETS ==========
    float jetAngular = pow(abs(sin(angle)), 7.5);
    float jetCore = smoothstep(PHOTON_SPHERE + 0.02, ISCO_RADIUS, r) * (1.0 - smoothstep(0.56, 1.05, r));
    float jetDetail = fbmFast(vec2(angle * 8.0, r * 12.0));
    float jetFine = fbmFast(vec2(angle * 16.0, r * 24.0));
    float jetStructure = jetDetail * 0.7 + jetFine * 0.3;
    float jetFocus = 1.0 + 0.35 * exp(-pow(abs(sin(angle)), 2.0) * 15.0);

    vec3 jetColor = mix(paletteMid, paletteGlow, 0.7);
    vec3 jets = jetColor * jetAngular * jetCore * jetFocus * (0.5 + 0.5 * jetStructure);
    jets *= u_jetIntensity * mix(0.45, 0.9, jetBias) * (0.6 + lensTerm * 0.4);
    float jetAxis = pow(saturate(1.0 - abs(sin(angle))), 12.0);
    float plasmaBeam = jetAxis * smoothstep(0.32, 0.54, r) * (1.0 - smoothstep(0.6, 1.1, r));
    plasmaBeam *= 0.9 + 0.3 * jetStructure;
    vec3 plasmaColor = mix(vec3(0.7, 0.95, 1.45), paletteGlow, 0.55);
    jets += plasmaColor * plasmaBeam * u_jetIntensity * 1.05;

    // ========== INNER GLOW ==========
    float innerGlowMask = smoothstep(PHOTON_SPHERE - 0.02, PHOTON_SPHERE + 0.06, r) * (1.0 - smoothstep(PHOTON_SPHERE + 0.08, PHOTON_SPHERE + 0.16, r));
    float innerDetail = fbmFast(vec2(angle * 16.0, r * 52.0));
    vec3 innerGlow = mix(paletteShadow, paletteMid, 0.5 + innerDetail * 0.15) * innerGlowMask * (0.65 + innerDetail * 0.25);

    float innerMask = smoothstep(EVENT_HORIZON, 0.38, r);
    float outerMask = 1.0 - smoothstep(0.84, 1.1, r);

    vec3 emission = outerGlow + halo + disk + photonRing + secondaryRing + jets + innerGlow * 0.5;
    emission *= innerMask * outerMask;

    vec3 color = background + emission;
    color = filmic(color * 1.65);
    color = clamp(color, 0.0, 1.0);

    gl_FragColor = vec4(color, 1.0);
}
