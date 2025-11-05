precision highp float;

uniform sampler2D u_baseTexture;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_cycle;
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

float fbm(vec2 uv) {
    float value = 0.0;
    float amplitude = 0.55;
    float frequency = 1.6;
    for (int i = 0; i < 6; ++i) {
        value += amplitude * noise(uv * frequency);
        frequency *= 2.02;
        amplitude *= 0.46;
    }
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

// Distant galaxy
float distantGalaxy(vec2 uv, vec2 position, float rotation, float size, float seed) {
    vec2 p = uv - position;
    p = rotate(p, rotation);
    
    // Elliptical shape
    p.y *= 0.4 + hash(vec2(seed, seed + 1.0)) * 0.3;
    float dist = length(p) / size;
    
    // Galaxy core
    float core = exp(-dist * 12.0);
    
    // Spiral arms (for spiral galaxies)
    float angle = atan(p.y, p.x);
    float spiral1 = fbm(vec2(dist * 8.0 + angle * 0.8, angle * 3.0)) * 0.6;
    float spiral2 = fbm(vec2(dist * 8.0 - angle * 0.8, -angle * 3.0)) * 0.6;
    
    // Galaxy disk
    float disk = exp(-dist * 4.5) * (1.0 + spiral1 + spiral2) * 0.3;
    
    // Combine
    float galaxy = core * 0.8 + disk;
    galaxy *= smoothstep(1.5, 0.0, dist);
    
    return saturate(galaxy);
}

// Milky Way-style nebula clouds
float nebulaCloud(vec2 uv, vec2 offset, float scale) {
    vec2 p = uv * scale + offset;
    float cloud = fbm(p * 2.5) * 0.6;
    cloud += fbm(p * 5.0) * 0.3;
    cloud += fbm(p * 10.0) * 0.1;
    return pow(saturate(cloud), 1.8);
}

// Dust lanes for galaxy background
float dustLanes(vec2 uv, vec2 offset) {
    vec2 p = uv + offset;
    float dust = fbm(vec2(p.x * 15.0, p.y * 3.0)) * 0.7;
    dust += fbm(vec2(p.x * 8.0, p.y * 6.0)) * 0.3;
    return saturate(dust);
}

// Wispy filaments
float filamentStructure(vec2 uv, vec2 offset, float angle) {
    vec2 p = rotate(uv + offset, angle);
    float filament = fbm(vec2(p.x * 25.0, p.y * 4.0)) * 0.6;
    filament += fbm(vec2(p.x * 50.0, p.y * 8.0)) * 0.4;
    return pow(saturate(filament), 3.0);
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
    
    // ========== MINIMAL STAR FIELD ==========
    
    // Just one sparse layer of stars
    float stars = starFieldEnhanced(uv + orbitA * 0.008, cycle, 400.0, 0.5, 1.0);
    vec3 starTint = mix(vec3(0.9, 0.95, 1.0), vec3(1.0, 1.0, 1.0), 0.7);
    
    background += starTint * stars * 0.25;
    
    // ========== NO COMETS OR SHOOTING STARS ==========
    // (Removed to fix bugs and reduce clutter)
    
    // Very subtle filaments
    float filament1 = filamentStructure(uv, vec2(0.2, -0.1), 0.4);
    vec3 filamentColor = paletteShadow * 0.5 * filament1 * 0.012;
    
    background += filamentColor;

    // ========== GRAVITATIONAL LENSING & WARPING ==========
    
    vec2 warped = mix(uv, lensWarp(uv, 0.06 + 0.04 * u_warp), 0.35);
    vec2 swirled = swirl(warped, 0.12 + u_warp * 0.3);
    vec2 polar = tiltedPolar(swirled);
    float r = polar.x;
    float angle = polar.y;
    float viewTilt = sin(angle + 0.35);
    float jetBias = saturate(0.6 + 0.4 * viewTilt);

    // Black hole shadow mask
    float holeMask = smoothstep(0.08, 0.2, r);
    background *= holeMask;

    // ========== PHOTON SPHERE & EINSTEIN RING ==========
    
    float photonMask = ringMask(r, 0.21, 0.29, 0.012);
    
    // Enhanced photon sphere with orbital variations
    float photonFlicker = 0.8 + 0.15 * fbm(vec2(angle * 3.2, loopAngle * 2.8));
    photonFlicker += 0.05 * fbm(vec2(angle * 8.5, loopAngle * 5.1));
    photonFlicker += 0.03 * fbm(vec2(angle * 16.0, loopAngle * 7.3));
    
    // Gravitational lensing caustics
    float causticDetail = fbm(vec2(angle * 12.0, r * 80.0) + orbitA * 3.5);
    photonFlicker *= 1.0 + causticDetail * 0.2;
    
    vec3 photonRing = paletteGlow * 2.2 * photonMask * photonFlicker * mix(1.0, 1.35, jetBias);

    // ========== ENHANCED ACCRETION DISK ==========
    
    // Realistic asymmetric disk structure
    float angularAsymmetry = fbm(vec2(angle * 2.5, loopAngle * 0.6)) * 0.08;
    float radialLumpiness = fbm(vec2(angle * 4.0, r * 15.0) + orbitA * 1.8) * 0.06;
    float clumpiness = fbm(vec2(angle * 6.5, r * 22.0) + orbitB * 2.2) * 0.05;
    
    // Irregular disk boundaries (realistic)
    float innerBoundary = 0.26 + angularAsymmetry * 0.5 + radialLumpiness * 0.3;
    float outerBoundary = 0.78 + clumpiness * 0.6 + angularAsymmetry * 0.4;
    float diskBand = smoothstep(0.2, innerBoundary, r) * (1.0 - smoothstep(0.275, outerBoundary, r));
    
    // Realistic disk gaps and inhomogeneities
    float diskGaps = fbm(vec2(angle * 8.0, r * 35.0) + orbitC * 2.5);
    diskBand *= 0.7 + 0.3 * diskGaps;
    
    // Relativistic Doppler boosting (approaching side much brighter and bluer)
    float dopplerPhase = angle - loopAngle * 1.1;
    float approach = saturate(0.5 + 0.5 * cos(dopplerPhase));
    float dopplerShift = mix(0.7, 1.4, approach);

    // Multi-scale turbulent cascade (from large to small scale)
    float turbulence1 = fbm(vec2(r * 25.0, angle * 8.0) + orbitA * 2.8);
    float turbulence2 = fbm(vec2(r * 45.0, angle * 12.0) + orbitB * 3.2);
    float turbulence3 = fbm(vec2(r * 85.0, angle * 18.0) + orbitC * 4.1);
    float turbulence4 = fbm(vec2(r * 130.0, angle * 25.0) - orbitA * 5.3);
    float turbulence5 = fbm(vec2(r * 180.0, angle * 32.0) + orbitB * 6.7);

    // Additional fine detail layers
    float vortexDetail = fbm(vec2(angle * 9.0 - loopAngle * 0.8, r * 50.0));
    float shearDetail = fbm(vec2(angle * 18.0, r * 85.0) + orbitC * 3.4);
    float sparkDetail = pow(fbm(vec2(angle * 22.0, r * 140.0) + orbitB * 5.6), 4.0);

    // Magnetic field structure (creates spiral patterns)
    float magneticField = fbm(vec2(angle * 4.5 + loopAngle * 0.8, r * 35.0)) * 0.3;

    // Gravitational redshift (dimmer near event horizon due to time dilation)
    float redshift = smoothstep(0.18, 0.36, r);

    // Temperature variations (hotter inner disk, cooler outer regions)
    float tempVariation = fbm(vec2(r * 60.0, angle * 15.0) + orbitB * 2.5);
    float innerTemp = smoothstep(0.5, 0.24, r);

    // Differential rotation (Keplerian velocity profile)
    float rotationSpeed = 1.0 / sqrt(r + 0.1);
    float diskFlow = fbm(vec2(angle * 6.0 - loopAngle * 1.1 * rotationSpeed, r * 20.0));
    float diskSpiral = fbm(vec2(r * 18.0, angle * 10.0) + orbitB * 2.4);

    // Shock fronts and reconnection flares
    float shockFront = pow(fbm(vec2(angle * 15.0 + loopAngle * 2.0, r * 40.0)), 3.2) * 0.35;
    float reconnection = pow(fbm(vec2(angle * 12.0, r * 60.0) + orbitC * 4.9), 4.0) * 0.45;

    // Combine all disk physics
    float diskEnergy = diskBand * mix(diskFlow, diskSpiral, 0.42);
    diskEnergy = pow(abs(diskEnergy), 0.78);
    diskEnergy *= speedInfluence * dopplerShift * redshift;
    diskEnergy *= 0.85 + turbulence1 * 0.45 + turbulence2 * 0.35 + turbulence3 * 0.25;
    diskEnergy *= 1.0 + turbulence4 * 0.22 + turbulence5 * 0.18;
    diskEnergy *= 1.0 + vortexDetail * 0.25 + shearDetail * 0.3;
    diskEnergy *= 1.0 + magneticField * 0.32 + tempVariation * 0.28;
    diskEnergy *= 1.0 + innerTemp * 0.5 + shockFront * 0.55 + reconnection * 0.6;
    diskEnergy *= 1.45;

    // Doppler color shift (warm toward viewer, cool away)
    vec3 warmTint = vec3(1.25, 0.78, 0.55);
    vec3 coolTint = vec3(0.65, 0.82, 1.2);
    vec3 dopplerTint = mix(warmTint, coolTint, approach);

    // Base disk color and highlights
    vec3 diskBase = mix(paletteMid, paletteBright, clamp(diskEnergy * 1.5, 0.0, 1.0)) * dopplerTint;
    vec3 diskHighlights = mix(paletteBright, paletteGlow, clamp(turbulence3 * 0.45 + vortexDetail * 0.35 + sparkDetail * 0.6, 0.0, 1.0));

    // Hot inner rim (photon sphere spill light)
    float innerRim = smoothstep(0.24, 0.27, r) * (1.0 - smoothstep(0.29, 0.33, r));
    float rimPulse = innerRim * (1.0 + shearDetail * 0.6 + sparkDetail * 1.2);
    vec3 rimColor = paletteGlow * mix(0.9, 1.6, approach) * rimPulse;

    // Localized flares / hot spots
    float hotspotMask = pow(fbm(vec2(angle * 14.0, r * 120.0) + orbitA * 4.7), 3.0);
    vec3 hotSpots = paletteGlow * vec3(1.2, 0.95, 0.7) * hotspotMask * diskBand * (0.4 + approach * 0.6);

    vec3 diskColor = mix(diskBase, diskHighlights, clamp(diskEnergy * 0.8, 0.0, 1.0));
    vec3 disk = diskColor * diskEnergy * 1.95 + rimColor + hotSpots;

    // ========== ENHANCED OUTER DISK STRUCTURES ==========
    
    // Turbulent outer disk with spiral density waves
    float outerSwirlMask = smoothstep(0.32, 0.5, r) * (1.0 - smoothstep(0.55, 0.85, r));
    float outerTurbulence = fbm(vec2(r * 22.0, angle * 5.5) + orbitB * 1.9);
    float outerGlow = fbm(vec2(r * 35.0, angle * 8.0) + orbitC * 2.3);
    float spiralWaves = fbm(vec2(r * 12.0, angle * 4.0 - loopAngle * 0.8));
    
    vec3 outerSwirl = mix(paletteShadow, paletteMid, 0.4) * outerSwirlMask;
    outerSwirl *= (outerTurbulence * 0.45 + outerGlow * 0.35 + spiralWaves * 0.3) * 0.25;

    // ========== EVENT HORIZON DETAIL ==========
    
    // Inner disk halo with gravitational time dilation effects
    float haloMask = smoothstep(0.26, 0.34, r) * (1.0 - smoothstep(0.36, 0.5, r));
    float haloDetail = fbm(vec2(r * 50.0, angle * 12.0) + orbitA * 3.1);
    float haloFlicker = 0.9 + 0.1 * cos(loopAngle * 8.0 + angle * 6.0);
    
    vec3 halo = mix(paletteShadow, paletteMid, 0.25 + haloDetail * 0.35) * haloMask;
    halo *= (0.2 + haloDetail * 0.15) * haloFlicker;

    // ========== RELATIVISTIC JETS ==========
    
    // Polar jets with proper turbulent structure (dimmer)
    float jetAngular = pow(abs(sin(angle)), 6.5);
    float jetCore = smoothstep(0.18, 0.35, r) * (1.0 - smoothstep(0.38, 0.95, r));
    float jetNoise = fbm(vec2(angle * 8.5, r * 13.0) + orbitC * 1.9);
    float jetTurbulence = fbm(vec2(angle * 15.0, r * 22.0) + orbitA * 2.7);
    float jetInstability = fbm(vec2(angle * 25.0, r * 35.0) + orbitD * 3.8);
    float jetPulse = 0.65 + 0.35 * cos(loopAngle * 3.5);
    
    // Jet magnetic collimation
    float jetFocus = 1.0 + 0.3 * exp(-pow(abs(sin(angle)), 2.0) * 15.0);
    
    vec3 jetColor = mix(paletteMid, paletteGlow, 0.65);
    vec3 jets = jetColor * jetAngular * jetCore * jetFocus;
    jets *= (0.3 + 0.35 * jetNoise + 0.2 * jetTurbulence + 0.12 * jetInstability);
    jets *= jetPulse * u_jetIntensity * mix(0.4, 0.85, jetBias);

    // ========== INNERMOST STABLE CIRCULAR ORBIT (ISCO) GLOW ==========
    
    float innerGlowMask = smoothstep(0.2, 0.26, r) * (1.0 - smoothstep(0.28, 0.36, r));
    float innerGlowDetail = fbm(vec2(r * 65.0, angle * 20.0) + orbitB * 3.5);
    float innerShimmer = fbm(vec2(r * 120.0, angle * 35.0) + orbitC * 5.2);
    float iscoEmission = 0.8 + 0.2 * cos(loopAngle * 6.0 + angle * 4.0);
    
    vec3 innerGlow = mix(paletteShadow, paletteMid, 0.45 + innerGlowDetail * 0.25) * innerGlowMask;
    innerGlow *= (0.5 + innerGlowDetail * 0.28 + innerShimmer * 0.15) * iscoEmission;

    float innerMask = smoothstep(0.16, 0.3, r);
    float outerMask = 1.0 - smoothstep(0.82, 1.08, r);

    vec3 emission = outerSwirl + halo + disk + photonRing + jets + innerGlow * 0.5;
    emission *= innerMask * outerMask;

    vec3 color = background + emission;
    color = filmic(color * 1.65);
    color = clamp(color, 0.0, 1.0);

    gl_FragColor = vec4(color, 1.0);
}
