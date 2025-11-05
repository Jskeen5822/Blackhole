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

void main() {
    float loopAngle = u_time;
    float cycle = u_cycle;
    vec2 uv = v_uv;
    vec2 centered = uv * 2.0 - 1.0;

    // Use smooth periodic functions for seamless looping - no discontinuities
    vec2 orbitA = vec2(cos(loopAngle), sin(loopAngle));
    vec2 orbitB = vec2(cos(loopAngle * 0.5), sin(loopAngle * 0.5));
    vec2 orbitC = vec2(cos(loopAngle * 0.3), sin(loopAngle * 0.3));
    vec2 orbitD = vec2(cos(loopAngle * 0.7), sin(loopAngle * 0.7));
    float speedInfluence = mix(0.85, 1.55, saturate(u_acceleration * 0.45));

    vec3 paletteShadow = sampleCombinedPalette(0.05);
    vec3 paletteMid = sampleCombinedPalette(0.3);
    vec3 paletteBright = sampleCombinedPalette(0.72);
    vec3 paletteGlow = sampleCombinedPalette(0.88);

    // ========== ENHANCED COSMIC BACKGROUND ==========
    
    // Base deep space color - darker
    vec3 background = paletteShadow * 0.02;
    
    // Milky Way-style nebula backdrop (extremely subtle)
    vec2 galaxyUV = uv + orbitA * 0.008;
    float nebula1 = nebulaCloud(galaxyUV, vec2(0.3, 0.1), 2.0);
    float nebula2 = nebulaCloud(galaxyUV, vec2(-0.4, 0.5), 1.5);
    float dust = dustLanes(galaxyUV, orbitB * 0.01);
    
    // Nebula colors (extremely subtle)
    vec3 nebulaColor1 = mix(paletteShadow, paletteMid * vec3(0.8, 0.6, 1.2), 0.2) * nebula1 * 0.015;
    vec3 nebulaColor2 = mix(paletteShadow, paletteMid * vec3(1.2, 0.7, 0.8), 0.25) * nebula2 * 0.012;
    
    vec3 dustColor = paletteShadow * 0.08 * dust;
    
    // Radial falloff for depth
    float radialFalloff = pow(saturate(1.3 - length(centered)), 2.2);
    
    background += nebulaColor1 + nebulaColor2;
    background -= dustColor * 0.3;
    background += paletteMid * 0.01 * radialFalloff;
    
    // ========== DISTANT GALAXIES ==========
    
    // Just one very dim distant galaxy
    float galaxy1 = distantGalaxy(uv, vec2(0.35, 0.45), 0.3, 0.08, 1.0);
    vec3 galaxyColor1 = mix(vec3(1.0, 0.9, 0.7), vec3(1.0, 1.0, 1.0), 0.6) * galaxy1 * 0.02;
    
    background += galaxyColor1;
    
    // ========== STATIC STAR BACKGROUND (NO MOVEMENT) ==========
    
    // Dense static starfield - looks like deep space
    vec2 starGrid1 = uv * 300.0;
    vec2 starCell1 = floor(starGrid1);
    float starRnd1 = hash(starCell1);
    float star1 = step(0.99, starRnd1) * saturate(1.0 - length(fract(starGrid1) - 0.5) * 8.0);
    
    // Second layer at different scale for depth
    vec2 starGrid2 = uv * 450.0;
    vec2 starCell2 = floor(starGrid2);
    float starRnd2 = hash(starCell2);
    float star2 = step(0.995, starRnd2) * saturate(1.0 - length(fract(starGrid2) - 0.5) * 10.0);
    
    // Subtle twinkling (very slow, based on position not time)
    float twinkle1 = 0.6 + 0.4 * sin(starRnd1 * 100.0);
    float twinkle2 = 0.7 + 0.3 * sin(starRnd2 * 100.0);
    // Add stars to background (brighter and more varied)
    background += vec3(0.95, 1.0, 1.1) * star1 * twinkle1 * 2.1;
    background += vec3(1.1, 0.98, 0.9) * star2 * twinkle2 * 1.8;
    
    // Add third layer for even more star density
    vec2 starGrid3 = uv * 600.0;
    vec2 starCell3 = floor(starGrid3);
    float starRnd3 = hash(starCell3);
    float star3 = step(0.997, starRnd3) * saturate(1.0 - length(fract(starGrid3) - 0.5) * 12.0);
    float twinkle3 = 0.65 + 0.35 * sin(starRnd3 * 100.0);
    background += vec3(1.1, 1.04, 1.0) * star3 * twinkle3 * 1.6;

    // Fourth sparse, bright stars
    vec2 starGrid4 = uv * 850.0;
    vec2 starCell4 = floor(starGrid4);
    float starRnd4 = hash(starCell4);
    float star4 = step(0.9985, starRnd4) * saturate(1.0 - length(fract(starGrid4) - 0.5) * 14.0);
    float twinkle4 = 0.7 + 0.3 * sin(starRnd4 * 120.0);
    background += vec3(1.2, 1.05, 0.95) * star4 * twinkle4 * 2.2;
    
    // Very faint Milky Way glow (static)
    float milkyWay = nebulaCloud(uv, vec2(0.0, 0.0), 1.5) * 0.03;
    background += paletteMid * milkyWay;

    // Subtle inflow fog being pulled toward the disk
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
    background += inflowColor * inflowIntensity * 0.3;

    vec2 warped = mix(uv, lensWarp(uv, 0.06 + 0.04 * u_warp), 0.35);
    vec2 swirled = swirl(warped, 0.12 + u_warp * 0.3);
    vec2 polar = tiltedPolar(swirled);
    float r = polar.x;
    float baseAngle = polar.y;
    float angle = baseAngle;

    // CINEMATIC: Continuous counter-clockwise rotation using elapsed time (no loop reset)
    float diskRotation = u_elapsed * 0.15; // Uses continuous time for seamless infinite rotation
    angle -= diskRotation; // Negative for counter-clockwise

    float viewTilt = sin(angle + 0.35);
    float jetBias = saturate(0.6 + 0.4 * viewTilt);

    // Black hole shadow with realistic gravitational lensing detail
    float holeMask = smoothstep(0.12, 0.28, r);
    
    // Enhanced event horizon with photon sphere lensing effects
    float horizonDetail = fbm(vec2(angle * 12.0, r * 55.0));
    float horizonMicroDetail = fbmFast(vec2(angle * 26.0, r * 92.0));
    
    // Create subtle lensing distortion ring
    float lensingRing = smoothstep(0.24, 0.26, r) * (1.0 - smoothstep(0.27, 0.3, r));
    lensingRing *= 0.7 + 0.3 * horizonDetail;
    
    // Photon sphere shadow (where light barely escapes)
    float photonShadow = smoothstep(0.25, 0.28, r) * (1.0 - smoothstep(0.29, 0.33, r));
    photonShadow *= 0.5 + 0.3 * horizonDetail + 0.2 * horizonMicroDetail;
    
    background *= (1.0 - lensingRing * 0.25);
    background *= (1.0 - photonShadow * 0.35);
    background *= holeMask;

    // ========== PHOTON SPHERE (EINSTEIN RING) ==========
    
    float photonMask = ringMask(r, 0.26, 0.36, 0.015);
    
    // CINEMATIC: More realistic photon ring with turbulence and beaming
    float photonTurbulence = fbm(vec2(angle * 8.0, r * 60.0));
    float photonDetail = fbmFast(vec2(angle * 20.0, r * 100.0));
    float photonBrightness = 1.0 + 0.3 * photonTurbulence + 0.15 * photonDetail;
    photonBrightness *= 0.85 + 0.15 * sin(angle * 4.0); // Slight asymmetry from viewing angle
    float photonApproach = saturate(0.5 + 0.5 * cos(angle));
    float photonBeaming = mix(0.7, 1.5, photonApproach);
    
    vec3 photonRing = paletteGlow * 2.6 * photonMask * photonBrightness * photonBeaming * mix(1.0, 1.4, jetBias);
    
    // ========== CINEMATIC ACCRETION DISK ==========
    
    // Clean disk boundaries with more realistic falloff
    float diskBand = smoothstep(0.26, 0.36, r) * (1.0 - smoothstep(0.4, 0.82, r));
    float diskEdgeDetail = fbmFast(vec2(angle * 8.0, r * 30.0));
    diskBand *= 0.88 + 0.12 * diskEdgeDetail;
    
    // CINEMATIC: Doppler - recalculate with NEW angle (includes rotation)
    float approach = saturate(0.5 + 0.5 * cos(angle));
    float dopplerShift = mix(0.55, 1.7, approach); // Strong cinematic contrast
    
    // Multi-scale turbulence for realistic disk structure
    float spiralLarge = fbm(vec2(r * 11.0, angle * 6.0));
    float spiralMedium = fbm(vec2(r * 24.0, angle * 11.0));
    float detailFine = fbmFast(vec2(r * 48.0, angle * 19.0));
    float detailUltra = fbmFast(vec2(r * 65.0, angle * 28.0));
    
    // Combine scales for realistic turbulent structure
    float diskStructure = spiralLarge * 0.42 + spiralMedium * 0.28 + detailFine * 0.2 + detailUltra * 0.1;
    
    // Gravitational effects
    float redshift = smoothstep(0.22, 0.42, r);
    float innerHeat = smoothstep(0.58, 0.32, r);
    
    // Temperature-dependent disk features
    float hotSpots = fbm(vec2(r * 38.0, angle * 15.0));
    hotSpots = pow(saturate(hotSpots), 2.0) * innerHeat;
    
    // Energy calculation with more realistic physics
    float diskEnergy = diskBand * (0.7 + diskStructure * 0.6);
    diskEnergy *= speedInfluence * dopplerShift * redshift;
    diskEnergy *= 1.0 + innerHeat * 0.8 + hotSpots * 0.5;
    diskEnergy *= 1.6;

    // Cinematic color tinting from Doppler with more contrast
    vec3 warmTint = vec3(1.45, 0.85, 0.52);
    vec3 coolTint = vec3(0.52, 0.68, 1.2);
    vec3 dopplerTint = mix(coolTint, warmTint, approach);
    
    // Enhanced color mixing with hot spots
    vec3 diskBase = mix(paletteMid, paletteBright, clamp(diskEnergy * 1.65, 0.0, 1.0)) * dopplerTint;
    vec3 diskHighlights = mix(paletteBright, paletteGlow, clamp(detailFine * 0.75 + detailUltra * 0.25, 0.0, 1.0));
    vec3 hotSpotColor = paletteGlow * 1.5 * hotSpots;
    
    // Bright inner rim with temperature gradient
    float innerRim = smoothstep(0.3, 0.34, r) * (1.0 - smoothstep(0.35, 0.39, r));
    float rimDetail = fbmFast(vec2(angle * 19.0, r * 62.0));
    vec3 rimGlow = paletteGlow * innerRim * mix(1.0, 2.2, approach) * (1.2 + rimDetail * 0.4);
    
    vec3 diskColor = mix(diskBase, diskHighlights, clamp(diskEnergy * 0.8, 0.0, 1.0));
    diskColor += hotSpotColor;
    vec3 disk = diskColor * diskEnergy * 2.1 + rimGlow;

    // ========== ENHANCED OUTER DISK ==========
    
    float outerWarpSeed = fbmFast(vec2(baseAngle * 5.0, r * 14.0 - cycle * 3.2));
    float outerWarp = 0.025 * (outerWarpSeed - 0.5);
    float outerGlowMask = smoothstep(0.34 + outerWarp, 0.52 + outerWarp, r) * (1.0 - smoothstep(0.58 + outerWarp, 0.84 + outerWarp, r));
    float outerDetail = fbmFast(vec2(baseAngle * 5.2, r * 18.0));
    vec3 outerGlow = mix(paletteShadow, paletteMid, 0.32 + outerDetail * 0.12) * outerGlowMask * (0.18 + outerDetail * 0.05);
    float outerClumps = fbm(vec2(baseAngle * 2.6 + cycle * 0.6, r * 11.0));
    float outerUneven = smoothstep(0.2, 0.82, outerClumps + 0.22 * sin(baseAngle * 2.2 + cycle * TAU * 0.28));
    vec3 outerClouds = mix(vec3(0.35, 0.42, 0.5), paletteMid, 0.45 + outerClumps * 0.25) * outerGlowMask * outerUneven * 0.22;
    outerGlow += outerClouds;

    // ========== ENHANCED HALO ==========
    
    float haloMask = smoothstep(0.27, 0.32, r) * (1.0 - smoothstep(0.35, 0.45, r));
    float haloDetail = fbmFast(vec2(baseAngle * 9.0 + cycle * 0.5, r * 35.0));
    vec3 halo = mix(paletteShadow, paletteMid, 0.26 + haloDetail * 0.1) * haloMask * (0.16 + haloDetail * 0.05);

    // ========== ENHANCED JETS ==========
    
    float jetAngular = pow(abs(sin(angle)), 6.5);
    float jetCore = smoothstep(0.28, 0.48, r) * (1.0 - smoothstep(0.52, 0.98, r));
    float jetDetail = fbmFast(vec2(angle * 8.0, r * 12.0));
    float jetFine = fbmFast(vec2(angle * 16.0, r * 24.0));
    float jetStructure = jetDetail * 0.7 + jetFine * 0.3;
    float jetFocus = 1.0 + 0.35 * exp(-pow(abs(sin(angle)), 2.0) * 15.0);
    
    vec3 jetColor = mix(paletteMid, paletteGlow, 0.7);
    vec3 jets = jetColor * jetAngular * jetCore * jetFocus * (0.5 + 0.5 * jetStructure);
    jets *= u_jetIntensity * mix(0.45, 0.9, jetBias);
    float jetAxis = pow(saturate(1.0 - abs(sin(angle))), 12.0);
    float plasmaBeam = jetAxis * smoothstep(0.32, 0.52, r) * (1.0 - smoothstep(0.56, 1.05, r));
    plasmaBeam *= 0.9 + 0.3 * jetStructure;
    vec3 plasmaColor = mix(vec3(0.7, 0.95, 1.45), paletteGlow, 0.55);
    jets += plasmaColor * plasmaBeam * u_jetIntensity * 1.1;

    // ========== ENHANCED INNER GLOW ==========
    
    float innerGlowMask = smoothstep(0.26, 0.34, r) * (1.0 - smoothstep(0.36, 0.44, r));
    float innerDetail = fbmFast(vec2(angle * 16.0, r * 52.0));
    vec3 innerGlow = mix(paletteShadow, paletteMid, 0.5 + innerDetail * 0.15) * innerGlowMask * (0.65 + innerDetail * 0.2);

    float innerMask = smoothstep(0.22, 0.38, r);
    float outerMask = 1.0 - smoothstep(0.84, 1.1, r);

    vec3 emission = outerGlow + halo + disk + photonRing + jets + innerGlow * 0.5;
    emission *= innerMask * outerMask;

    vec3 color = background + emission;
    color = filmic(color * 1.65);
    color = clamp(color, 0.0, 1.0);

    gl_FragColor = vec4(color, 1.0);
}
