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
    float s = strength * smoothstep(0.08, 1.0, r);
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

float starField(vec2 uv, float cycle) {
    float baseAngle = cycle * TAU;
    vec2 shift = vec2(cos(baseAngle), sin(baseAngle)) * 0.015;
    vec2 grid = (uv + shift) * vec2(220.0, 160.0);
    vec2 cell = floor(grid);
    vec2 local = fract(grid) - 0.5;
    float dist = length(local);
    float rnd = hash(cell);
    float twinkleAngle = baseAngle * (1.6 + 0.8 * hash(cell + 11.3)) + hash(cell + 5.7) * TAU;
    float twinkle = 0.55 + 0.45 * sin(twinkleAngle);
    float star = saturate(0.45 - dist * (2.8 + hash(cell + 7.9) * 3.5));
    star *= step(0.995, rnd);
    return star * twinkle;
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

    vec2 orbitA = vec2(cos(loopAngle), sin(loopAngle));
    vec2 orbitB = vec2(cos(loopAngle * 0.5 + 1.2), sin(loopAngle * 0.5 + 1.2));
    vec2 orbitC = vec2(cos(loopAngle * 0.8 - 0.9), sin(loopAngle * 0.8 - 0.9));
    float speedInfluence = mix(0.85, 1.55, saturate(u_acceleration * 0.45));

    vec3 paletteShadow = sampleCombinedPalette(0.05);
    vec3 paletteMid = sampleCombinedPalette(0.3);
    vec3 paletteBright = sampleCombinedPalette(0.72);
    vec3 paletteGlow = sampleCombinedPalette(0.88);

    vec3 background = paletteShadow * 0.02 + paletteMid * 0.04;
    float stars = starField(uv + orbitA * 0.007 + orbitB * 0.004 - orbitC * 0.003, cycle);
    float denseStars = starField(rotate(uv * 1.6 - orbitB * 0.02, 0.28) + orbitA * 0.021, cycle * 1.3 + 0.17);
    float sparkling = starField(rotate(uv * 2.3 + orbitC * 0.031, -0.41), cycle * 1.9 + 0.62);
    vec3 starTint = mix(paletteBright, paletteGlow, 0.6);
    background += starTint * 0.9 * stars;
    background += mix(paletteMid, paletteGlow, 0.75) * 0.5 * denseStars;
    background += mix(paletteShadow, paletteBright, 0.4) * 0.35 * sparkling;

    float galacticPlane = exp(-pow(centered.y * 2.8, 2.2));
    float planeDrift = 0.35 + 0.65 * sin(loopAngle * 2.2 + centered.x * 6.0);
    vec3 planeColor = mix(paletteMid, paletteGlow, 0.55);
    background += planeColor * galacticPlane * planeDrift * 0.18;

    float nebulaField = fbm(uv * 18.0 + orbitA * 1.4) * fbm(rotate(uv, 0.32) * 12.0 - orbitB * 1.1);
    float nebulaMask = smoothstep(0.55, 0.92, nebulaField);
    vec3 nebulaColor = mix(paletteMid, paletteGlow, 0.8);
    background += nebulaColor * nebulaMask * 0.35;

    vec2 warped = mix(uv, lensWarp(uv, 0.06 + 0.04 * u_warp), 0.35);
    vec2 swirled = swirl(warped, 0.12 + u_warp * 0.3);
    vec2 polar = tiltedPolar(swirled);
    float r = polar.x;
    float angle = polar.y;
    float viewBias = saturate(0.5 + 0.45 * sin(angle + 0.5));

    float holeMask = smoothstep(0.08, 0.2, r);
    background *= holeMask;

    float photonMask = ringMask(r, 0.21, 0.29, 0.012);
    float photonFlicker = 0.75 + 0.25 * sin(loopAngle * 3.0 + angle * 2.2) + 0.12 * sin(loopAngle * 5.0);
    vec3 photonRing = paletteGlow * 2.2 * photonMask * photonFlicker * mix(0.7, 1.9, viewBias);

    float diskBand = smoothstep(0.2, 0.26, r) * (1.0 - smoothstep(0.275, 0.78, r));
    float diskFlow = 0.62 + 0.38 * sin(angle - loopAngle * 1.15);
    float diskRumple = fbm(vec2(r * 28.0, angle * 6.4) + orbitA * 2.6);
    float diskSpiral = fbm(vec2(r * 18.0, angle * 10.0) + orbitB * 2.4);
    float diskFilament = pow(saturate(0.54 + 0.46 * sin(angle * 12.0 + r * 28.0 - loopAngle * 5.6)), 2.55);
    float diskShock = smoothstep(0.18, 0.23, r) * (0.6 + 0.4 * sin(angle * 6.0 + loopAngle * 4.6));
    float shearNoise = fbm(vec2(r * 58.0, angle * 34.0) + orbitA * 5.4);
    float filamentNoise = fbm(vec2(r * 92.0, angle * 42.0) + orbitB * 7.6);
    float caustic = pow(saturate(0.48 + 0.52 * sin(angle * 34.0 - loopAngle * 7.4)), 2.8);
    float microCaustic = fbm(vec2(r * 140.0, angle * 70.0) + orbitC * 9.2);
    float diskEnergy = diskBand * mix(diskFlow, diskSpiral, 0.55);
    diskEnergy = pow(abs(diskEnergy), 1.08);
    diskEnergy *= speedInfluence * (0.88 + 0.48 * diskFilament + 0.32 * diskShock);
    diskEnergy *= 1.0 + diskRumple * 0.32 + shearNoise * 0.65 + filamentNoise * 0.5 + caustic * 0.8 + microCaustic * 0.25;
    diskEnergy *= mix(1.0, 1.35, viewBias);
    vec3 diskBase = mix(paletteMid, paletteBright, clamp(diskEnergy * 1.7, 0.0, 1.0));
    vec3 diskHighlights = mix(paletteBright, paletteGlow, clamp(0.5 + caustic * 0.5 + microCaustic * 0.35, 0.0, 1.0));
    vec3 diskColor = mix(diskBase, diskHighlights, clamp(diskEnergy, 0.0, 1.0));
    vec3 disk = diskColor * diskEnergy * 2.0;

    float haloMask = smoothstep(0.26, 0.36, r) * (1.0 - smoothstep(0.4, 0.68, r));
    vec3 halo = mix(paletteShadow, paletteMid, 0.12) * haloMask * 0.14;

    float jetAngular = pow(abs(sin(angle)), 6.0);
    float jetCore = smoothstep(0.18, 0.35, r) * (1.0 - smoothstep(0.38, 0.95, r));
    float jetNoise = fbm(vec2(angle * 8.5, r * 13.0) + orbitC * 1.9);
    float jetPulse = 0.6 + 0.4 * sin(loopAngle * 4.0 + angle * 4.5);
    vec3 jetColor = mix(paletteMid, paletteGlow, 0.6);
    vec3 jets = jetColor * jetAngular * jetCore * (0.35 + 0.65 * jetNoise) * jetPulse * u_jetIntensity * mix(0.35, 0.95, viewBias);

    vec3 innerGlow = mix(paletteShadow, paletteMid, 0.5) * smoothstep(0.2, 0.26, r) * (1.0 - smoothstep(0.28, 0.36, r));

    float innerMask = smoothstep(0.16, 0.3, r);
    float outerMask = 1.0 - smoothstep(0.9, 1.2, r);

    vec3 emission = halo + disk + photonRing + jets + innerGlow * 0.4;
    emission *= innerMask * outerMask;

    vec3 color = background + emission;
    color = filmic(color * 1.7);
    color = clamp(color, 0.0, 1.0);

    gl_FragColor = vec4(color, 1.0);
}
