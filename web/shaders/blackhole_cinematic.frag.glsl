precision highp float;

uniform sampler2D u_baseTexture;
uniform vec2 u_resolution;
uniform float u_time;
uniform float u_cycle;
uniform float u_elapsed;
uniform float u_acceleration;
uniform float u_warp;
uniform float u_jetIntensity;

varying vec2 v_uv;

const float PI = 3.141592653589793;
const float TAU = 6.283185307179586;

float saturate(float v) {
    return clamp(v, 0.0, 1.0);
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
    float frequency = 1.7;
    for (int i = 0; i < 4; ++i) {
        value += amplitude * noise(uv * frequency);
        frequency *= 2.03;
        amplitude *= 0.48;
    }
    return value;
}

vec3 samplePalette(float t) {
    vec2 baseUV = vec2(clamp(t, 0.0, 1.0), 0.5);
    vec3 accum = vec3(0.0);
    float weight = 0.0;
    for (int i = -2; i <= 2; ++i) {
        float offset = float(i) * 0.0125;
        float w = 1.0 - abs(float(i)) * 0.28;
        vec2 sampleUV = vec2(clamp(baseUV.x + offset, 0.0, 1.0), baseUV.y);
        accum += texture2D(u_baseTexture, sampleUV).rgb * w;
        weight += w;
    }
    return accum / weight;
}

vec3 filmic(vec3 color) {
    color = max(vec3(0.0), color - 0.004);
    return (color * (6.2 * color + 0.5)) / (color * (6.2 * color + 1.7) + 0.06);
}

float ringMask(float r, float inner, float outer, float softness) {
    float innerEdge = smoothstep(inner - softness, inner + softness, r);
    float outerEdge = smoothstep(outer - softness, outer + softness, r);
    return saturate(innerEdge - outerEdge);
}

vec2 sampleDisk(vec2 pos, float spin, float innerRadius, float outerRadius, float flatten) {
    vec2 q = vec2(pos.x, pos.y / max(flatten, 0.0001));
    float radius = length(q);
    float mask = smoothstep(innerRadius, innerRadius + 0.012, radius) * (1.0 - smoothstep(outerRadius, outerRadius + 0.04, radius));
    if (mask <= 0.0) {
        return vec2(0.0);
    }

    float angle = atan(q.y, q.x) - spin;
    float streak = pow(saturate(0.45 + 0.55 * sin(angle * 10.0 + radius * 35.0)), 3.0);
    float turbulence = fbm(vec2(radius * 24.0, angle * 5.5));
    float micro = fbm(vec2(radius * 58.0, angle * 12.0));

    float energy = mask * (0.28 + turbulence * 0.38 + micro * 0.25 + streak * 0.6);
    float highlight = mask * (0.16 + streak * 0.84 + micro * 0.28);
    return vec2(energy, highlight);
}

void main() {
    float aspect = u_resolution.x / u_resolution.y;
    vec2 p = vec2((v_uv.x - 0.5) * aspect * 1.6, (v_uv.y - 0.5) * 1.6);

    vec3 colShadow = samplePalette(0.05);
    vec3 colMid = samplePalette(0.35);
    vec3 colBright = samplePalette(0.65);
    vec3 colGlow = samplePalette(0.92);

    vec3 background = mix(vec3(0.006, 0.01, 0.015), colShadow, 0.35);
    background += colBright * 0.015 * ringMask(length(p * vec2(0.4, 0.2)), 1.2, 1.6, 0.08);

    float speed = mix(1.8, 2.8, saturate(u_acceleration * 0.5));
    float spin = u_elapsed * speed;

    float innerRadius = 0.24;
    float outerRadius = 0.76;

    vec2 diskPos = vec2(p.x, p.y * 0.32);
    vec2 diskSampleVal = sampleDisk(diskPos, spin, innerRadius, outerRadius, 0.32);

    vec3 diskBaseColor = mix(colMid, colBright, saturate(diskSampleVal.x * 1.4));
    diskBaseColor = mix(diskBaseColor, colGlow, saturate(diskSampleVal.y * 1.2));
    vec3 diskEmission = diskBaseColor * (diskSampleVal.x * 1.9) + colGlow * diskSampleVal.y * 1.6;

    float lensOffset = 0.62;
    float lensCompression = 0.55;

    vec2 topPos = vec2(p.x, (p.y - lensOffset) * lensCompression);
    vec2 topSampleVal = sampleDisk(topPos, spin, innerRadius, outerRadius, 0.34);
    vec3 topColor = mix(colMid, colGlow, saturate(topSampleVal.y * 1.4));
    vec3 topEmission = topColor * (topSampleVal.x * 1.5 + topSampleVal.y * 2.2);

    vec2 bottomPos = vec2(p.x, (p.y + lensOffset) * lensCompression);
    vec2 bottomSampleVal = sampleDisk(bottomPos, spin, innerRadius, outerRadius, 0.34);
    vec3 bottomColor = mix(colMid, colGlow, saturate(bottomSampleVal.y * 1.2));
    vec3 bottomEmission = bottomColor * (bottomSampleVal.x * 1.2 + bottomSampleVal.y * 1.6);

    float photonRadius = length(vec2(p.x, p.y * 0.58));
    float photonBand = ringMask(photonRadius, 0.27, 0.33, 0.01);
    float photonDetail = fbm(vec2(p.x * 18.0, p.y * 26.0 + spin * 0.8));
    vec3 photonColor = mix(colBright, colGlow, 0.8) * (1.8 + photonDetail * 0.8) * photonBand;

    float rimRadius = length(vec2(p.x, p.y * 0.42));
    float rimBand = ringMask(rimRadius, 0.24, 0.27, 0.006);
    vec3 rimColor = colGlow * (1.4 + fbm(vec2(p.x * 35.0, p.y * 70.0 + spin))) * rimBand;

    float horizonRadius = length(vec2(p.x, p.y * 0.55));
    float horizonMask = smoothstep(0.215, 0.24, horizonRadius);

    vec3 emission = diskEmission + topEmission + bottomEmission + photonColor + rimColor;
    vec3 color = mix(vec3(0.0), background + emission, horizonMask);

    color = filmic(color * 1.4);
    color = pow(color, vec3(0.92));
    color = clamp(color, 0.0, 1.0);

    gl_FragColor = vec4(color, 1.0);
}
