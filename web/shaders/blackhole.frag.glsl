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

void main() {
    float loopAngle = u_time;
    float cycle = u_cycle;
    vec2 uv = v_uv;
    vec2 centered = uv * 2.0 - 1.0;

    vec2 orbitA = vec2(cos(loopAngle), sin(loopAngle));
    vec2 orbitB = vec2(cos(loopAngle * 0.5 + 1.2), sin(loopAngle * 0.5 + 1.2));
    vec2 orbitC = vec2(cos(loopAngle * 0.8 - 0.9), sin(loopAngle * 0.8 - 0.9));
    float speedInfluence = mix(0.75, 1.35, saturate(u_acceleration * 0.4));

    vec3 paletteShadow = samplePalette(u_baseTexture, 0.05);
    vec3 paletteMid = samplePalette(u_baseTexture, 0.3);
    vec3 paletteBright = samplePalette(u_baseTexture, 0.72);
    vec3 paletteGlow = samplePalette(u_baseTexture, 0.88);

    vec3 gradBg = mix(paletteShadow * 0.35, paletteMid * 0.4, saturate(centered.y * 0.6 + 0.5));
    vec3 background = gradBg;
    float bgNoise = fbm(uv * 14.0 + orbitB * 1.6 + orbitC * 0.7);
    background += paletteShadow * 0.25 * bgNoise + paletteMid * 0.08 * bgNoise;
    float stars = starField(uv + orbitA * 0.007 + orbitB * 0.004 - orbitC * 0.003, cycle);
    background += paletteGlow * 0.4 * stars;

    vec2 warped = mix(uv, lensWarp(uv, 0.06 + 0.04 * u_warp), 0.35);
    vec2 swirled = swirl(warped, 0.12 + u_warp * 0.3);
    vec2 polar = tiltedPolar(swirled);
    float r = polar.x;
    float angle = polar.y;
    float viewBias = saturate(0.5 + 0.45 * sin(angle + 0.5));

    float photonMask = ringMask(r, 0.21, 0.29, 0.012);
    float photonFlicker = 0.75 + 0.25 * sin(loopAngle * 3.0 + angle * 2.2) + 0.12 * sin(loopAngle * 5.0);
    vec3 photonRing = paletteGlow * 2.2 * photonMask * photonFlicker * mix(0.7, 1.9, viewBias);

    float diskBand = smoothstep(0.22, 0.3, r) * (1.0 - smoothstep(0.3, 0.95, r));
    float diskFlow = 0.6 + 0.4 * sin(angle - loopAngle * 0.8);
    float diskRumple = fbm(vec2(r * 22.0, angle * 5.2) + orbitA * 2.1);
    float diskSpiral = fbm(vec2(r * 15.0, angle * 7.5) + orbitB * 1.7);
    float diskFilament = pow(saturate(0.5 + 0.5 * sin(angle * 12.0 + r * 19.0 - loopAngle * 2.6)), 2.2);
    float diskShock = smoothstep(0.18, 0.24, r) * (0.6 + 0.4 * sin(angle * 5.0 + loopAngle * 3.0));
    float diskEnergy = diskBand * mix(diskFlow, diskSpiral, 0.52);
    diskEnergy = pow(abs(diskEnergy), 1.05);
    diskEnergy *= speedInfluence * (0.85 + 0.45 * diskFilament + 0.3 * diskShock);
    vec3 diskBase = mix(paletteMid, paletteBright, clamp(diskEnergy * 1.4, 0.0, 1.0));
    vec3 diskColor = mix(diskBase, paletteGlow * 1.2, pow(viewBias, 1.3));
    vec3 disk = diskColor * diskEnergy * 1.7;

    float haloMask = smoothstep(0.2, 0.5, r) * (1.0 - smoothstep(0.5, 0.85, r));
    vec3 halo = mix(paletteShadow, paletteBright, 0.3) * haloMask * mix(0.6, 1.2, viewBias);

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
