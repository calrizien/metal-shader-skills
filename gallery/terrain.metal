/*
MIT License

Copyright (c) 2026 gokayfem

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
// metal-shader-skills: MSL 4.0, MIT.
// Derived from https://github.com/gokayfem/shader-skills
// Metal fork: https://github.com/calrizien/metal-shader-skills
#include <metal_stdlib>
using namespace metal;

// Shared ABI: 16 bytes, alignment 8. Swift: SIMD2<Float>, Float, UInt32.
struct ShaderUniforms {
    float2 resolution;
    float time;
    uint frame;
};
vertex float4 fullscreenVertex(uint id [[vertex_id]]) {
    const float2 positions[3] = {float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0)};
    return float4(positions[id], 0.0, 1.0);
}

struct ShaderScene {
    float2 resolution;
    float time;
    int frame;
#define DEBUG_MODE 0   // 0 final | 1 height map | 2 normals | 3 material masks | 4 steps | 5 shadow | 6 light terms
const float PI  = 3.14159265358979;
const float TAU = 6.28318530717959;
uint pcgHash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}
uint3 pcg3d(uint3 v) {
    v = v * 1664525u + 1013904223u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    v ^= v >> 16u;
    v.x += v.y * v.z;
    v.y += v.z * v.x;
    v.z += v.x * v.y;
    return v;
}
float uintToUnit(uint h) { return float(h >> 8u) * (1.0 / 16777216.0); }
float2 uintToUnit(uint2 h) { return float2(h >> 8u) * (1.0 / 16777216.0); }
float3 uintToUnit(uint3 h) { return float3(h >> 8u) * (1.0 / 16777216.0); }
float4 uintToUnit(uint4 h) { return float4(h >> 8u) * (1.0 / 16777216.0); }
float hash12(float2 p) {
    uint2 q = uint2(int2(floor(p)));
    return uintToUnit(pcgHash(q.x + pcgHash(q.y)));
}
float2 hash22(float2 p) {
    int2 q = int2(floor(p));
    return uintToUnit(pcg3d(uint3(q.x, q.y, 0x2545u))).xy;
}
float3 hash33(float3 p) { return uintToUnit(pcg3d(uint3(int3(floor(p))))); }
float2 quinticFade(float2 f) { return f * f * f * (f * (f * 6.0 - 15.0) + 10.0); }
float3 quinticFade(float3 f) { return f * f * f * (f * (f * 6.0 - 15.0) + 10.0); }
float2 quinticFadeDeriv(float2 f) { return 30.0 * f * f * (f * (f - 2.0) + 1.0); }
float3 quinticFadeDeriv(float3 f) { return 30.0 * f * f * (f * (f - 2.0) + 1.0); }
float2 latticeGradient(float2 cell) {
    float a = TAU * hash12(cell);
    return float2(cos(a), sin(a));
}
float3 gradientNoiseD(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = quinticFade(f), du = quinticFadeDeriv(f);
    float2 ga = latticeGradient(i);
    float2 gb = latticeGradient(i + float2(1.0, 0.0));
    float2 gc = latticeGradient(i + float2(0.0, 1.0));
    float2 gd = latticeGradient(i + float2(1.0, 1.0));
    float va = dot(ga, f);
    float vb = dot(gb, f - float2(1.0, 0.0));
    float vc = dot(gc, f - float2(0.0, 1.0));
    float vd = dot(gd, f - float2(1.0, 1.0));
    float k = va - vb - vc + vd;
    float value = va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * k;
    float2 deriv = ga + u.x * (gb - ga) + u.y * (gc - ga) + u.x * u.y * (ga - gb - gc + gd)
               + du * (float2(vb - va, vc - va) + u.yx * k);
    return float3(value, deriv);
}
float gradientNoise(float2 p) { return gradientNoiseD(p).x; }
float latticeGradDot(float3 cell, float3 corner, float3 f) {
    float3 g = hash33(cell + corner) * 2.0 - 1.0;
    return dot(g, f - corner);
}
float gradientNoise(float3 p) {
    float3 i = floor(p), f = fract(p);
    float3 u = quinticFade(f);
    return mix(mix(mix(latticeGradDot(i, float3(0, 0, 0), f), latticeGradDot(i, float3(1, 0, 0), f), u.x),
                   mix(latticeGradDot(i, float3(0, 1, 0), f), latticeGradDot(i, float3(1, 1, 0), f), u.x), u.y),
               mix(mix(latticeGradDot(i, float3(0, 0, 1), f), latticeGradDot(i, float3(1, 0, 1), f), u.x),
                   mix(latticeGradDot(i, float3(0, 1, 1), f), latticeGradDot(i, float3(1, 1, 1), f), u.x), u.y), u.z);
}
float4 gradientNoiseD(float3 p) {
    float3 i = floor(p), f = fract(p);
    float3 u = quinticFade(f), du = quinticFadeDeriv(f);
    float3 g000 = hash33(i) * 2.0 - 1.0;
    float3 g100 = hash33(i + float3(1, 0, 0)) * 2.0 - 1.0;
    float3 g010 = hash33(i + float3(0, 1, 0)) * 2.0 - 1.0;
    float3 g110 = hash33(i + float3(1, 1, 0)) * 2.0 - 1.0;
    float3 g001 = hash33(i + float3(0, 0, 1)) * 2.0 - 1.0;
    float3 g101 = hash33(i + float3(1, 0, 1)) * 2.0 - 1.0;
    float3 g011 = hash33(i + float3(0, 1, 1)) * 2.0 - 1.0;
    float3 g111 = hash33(i + float3(1, 1, 1)) * 2.0 - 1.0;
    float v000 = dot(g000, f);
    float v100 = dot(g100, f - float3(1, 0, 0));
    float v010 = dot(g010, f - float3(0, 1, 0));
    float v110 = dot(g110, f - float3(1, 1, 0));
    float v001 = dot(g001, f - float3(0, 0, 1));
    float v101 = dot(g101, f - float3(1, 0, 1));
    float v011 = dot(g011, f - float3(0, 1, 1));
    float v111 = dot(g111, f - float3(1, 1, 1));
    // value = v000 + kx u.x + ky u.y + kz u.z + kxy u.x u.y + kyz u.y u.z + kzx u.z u.x + kxyz u.x u.y u.z
    float kx = v100 - v000, ky = v010 - v000, kz = v001 - v000;
    float kxy = v000 - v100 - v010 + v110;
    float kyz = v000 - v010 - v001 + v011;
    float kzx = v000 - v100 - v001 + v101;
    float kxyz = -v000 + v100 + v010 - v110 + v001 - v101 - v011 + v111;
    float value = v000 + kx * u.x + ky * u.y + kz * u.z
                + kxy * u.x * u.y + kyz * u.y * u.z + kzx * u.z * u.x + kxyz * u.x * u.y * u.z;
    float3 grad = g000 + (g100 - g000) * u.x + (g010 - g000) * u.y + (g001 - g000) * u.z
              + (g000 - g100 - g010 + g110) * u.x * u.y
              + (g000 - g010 - g001 + g011) * u.y * u.z
              + (g000 - g100 - g001 + g101) * u.z * u.x
              + (-g000 + g100 + g010 - g110 + g001 - g101 - g011 + g111) * u.x * u.y * u.z
              + du * float3(kx + kxy * u.y + kzx * u.z + kxyz * u.y * u.z,
                          ky + kxy * u.x + kyz * u.z + kxyz * u.x * u.z,
                          kz + kyz * u.y + kzx * u.x + kxyz * u.x * u.y);
    return float4(value, grad);
}
const int FBM_MAX_OCTAVES = 12;
float fbm(float2 p, int octaves, float lacunarity, float persistence) {
    const float2x2 octaveRotation = float2x2(0.8, 0.6, -0.6, 0.8);
    float sum = 0.0, amp = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        sum += amp * gradientNoise(p);
        norm += amp;
        amp *= persistence;
        p = lacunarity * (octaveRotation * p) + float2(17.13, -3.71);
    }
    return 1.4 * sum / norm;
}
float fbm(float2 p, int octaves) { return fbm(p, octaves, 2.01, 0.5); }
float fbm(float3 p, int octaves, float lacunarity, float persistence) {
    const float3x3 octaveRotation = float3x3(0.00, 0.80, 0.60,
                                     -0.80, 0.36, -0.48,
                                     -0.60, -0.48, 0.64);
    float sum = 0.0, amp = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        sum += amp * gradientNoise(p);
        norm += amp;
        amp *= persistence;
        p = lacunarity * (octaveRotation * p) + float3(17.13, -3.71, 5.29);
    }
    return sum / norm;
}
float erodedFbm(float2 p, int octaves) {
    const float2x2 octaveRotation = float2x2(0.8, 0.6, -0.6, 0.8);
    float h = 0.0, amp = 0.5;
    float2 slope = float2(0.0);
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        float3 n = gradientNoiseD(p);
        slope += n.yz;
        h += amp * n.x / (1.0 + dot(slope, slope));
        amp *= 0.5;
        p = 2.0 * (octaveRotation * p);
    }
    return 2.0 * h;
}
const int RAYMARCH_MAX_STEPS = 256;
float3 raymarch(float3 ro, float3 rd, float tmin, float tmax, float stepScale) {
    float t = tmin;
    for (int i = 0; i < RAYMARCH_MAX_STEPS; i++) {
        float2 h = map(ro + rd * t);
        if (abs(h.x) < max(0.0002 * t, 1e-5)) return float3(t, h.y, float(i));
        t += h.x * stepScale;
        if (t > tmax) break;
    }
    return float3(-1.0, -1.0, float(RAYMARCH_MAX_STEPS));
}
float3 calcNormal(float3 p, float eps) {
    float3 n = float3(0.0);
    for (int i = 0; i < 4; i++) {
        float3 e = 0.5773 * (2.0 * float3((((i + 3) >> 1) & 1), ((i >> 1) & 1), (i & 1)) - 1.0);
        n += e * map(p + e * eps).x;
    }
    return normalize(n);
}
float softShadow(float3 ro, float3 rd, float tmin, float tmax, float k) {
    float res = 1.0;
    float t = tmin;
    float ph = 1e10;
    for (int i = 0; i < 64; i++) {
        float h = map(ro + rd * t).x;
        if (h < 0.0001) return 0.0;
        float y = h * h / (2.0 * ph);
        float d = sqrt(max(h * h - y * y, 0.0));
        res = min(res, k * d / max(t - y, 1e-4));
        ph = h;
        t += clamp(h, 0.005, 0.5);
        if (res < 0.001 || t > tmax) break;
    }
    res = clamp(res, 0.0, 1.0);
    return res * res * (3.0 - 2.0 * res);
}
float2 iSphere(float3 ro, float3 rd, float3 c, float r) {
    float3 oc = ro - c;
    float b = dot(oc, rd);
    float3 qc = oc - b * rd;
    float h = r * r - dot(qc, qc);
    if (h < 0.0) return float2(-1.0);
    h = sqrt(h);
    return float2(-b - h, -b + h);
}
float3x3 cameraMatrix(float3 ro, float3 ta, float roll) {
    float3 w = normalize(ta - ro);
    float3 up = float3(sin(roll), cos(roll), 0.0);
    float3 u = normalize(cross(w, up));
    float3 v = cross(u, w);
    return float3x3(u, v, w);
}
float3 cameraRay(float3x3 cam, float2 uv, float focal) {
    return normalize(cam * float3(uv, focal));
}
float3 linearToSrgb(float3 c) {
    c = max(c, 0.0);
    return mix(c * 12.92, 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}
float luminance(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }
float3 tonemapAgX(float3 c) {
    const float3x3 inset = float3x3(0.842479062253094, 0.0423282422610123, 0.0423756549057051,
                            0.0784335999999992, 0.878468636469772, 0.0784336,
                            0.0792237451477643, 0.0791661274605434, 0.879142973793104);
    const float3x3 outset = float3x3(1.19687900512017, -0.0528968517574562, -0.0529716355144438,
                             -0.0980208811401368, 1.15190312990417, -0.0980434501171241,
                             -0.0990297440797205, -0.0989611768448433, 1.15107367264116);
    const float minEv = -12.47393, maxEv = 4.026069;
    c = inset * max(c, 0.0);
    c = clamp((log2(max(c, 1e-10)) - minEv) / (maxEv - minEv), 0.0, 1.0);
    float3 x2 = c * c, x4 = x2 * x2;
    c = 15.5 * x4 * x2 - 40.14 * x4 * c + 31.96 * x4 - 6.868 * x2 * c + 0.4298 * x2 + 0.1191 * c - 0.00232;
    c = outset * c;
    return pow(max(c, 0.0), float3(2.2));
}
float phaseRayleigh(float mu) { return 3.0 / (16.0 * PI) * (1.0 + mu * mu); }
float phaseCornetteShanks(float mu, float g) {
    float g2 = g * g;
    return 3.0 / (8.0 * PI) * (1.0 - g2) * (1.0 + mu * mu)
         / ((2.0 + g2) * pow(max(1.0 + g2 - 2.0 * g * mu, 1e-6), 1.5));
}
void volumeStep(thread float3 &radiance, thread float3 &transmittance, float3 sigmaT, float3 inScatter, float ds) {
    float3 stepT = exp(-sigmaT * ds);
    float3 integral = (inScatter - inScatter * stepT) / max(sigmaT, float3(1e-7));
    radiance += transmittance * integral;
    transmittance *= stepT;
}
float3 sunDisk(float3 rd, float3 sunDir, float angularRadius, float pixelAngle) {
    float ang = acos(clamp(dot(rd, sunDir), -1.0, 1.0));
    float edge = 1.0 - smoothstep(angularRadius - pixelAngle, angularRadius + pixelAngle, ang);
    float r = clamp(ang / angularRadius, 0.0, 1.0);
    float muLimb = sqrt(max(1.0 - r * r, 0.0));
    float3 limb = pow(float3(muLimb), float3(0.397, 0.503, 0.652));
    return edge * limb;
}
const float ATMOSPHERE_GROUND_KM = 6360.0;
const float ATMOSPHERE_TOP_KM = 6460.0;
float3 atmosphereDensity(float h) {
    return float3(exp(-h / 8.0), exp(-h / 1.2), max(0.0, 1.0 - abs(h - 25.0) / 15.0));
}
float3 atmosphereExtinction(float3 density) {
    const float3 rayleigh = float3(5.802, 13.558, 33.1) * 1e-3;
    const float mie = (3.996 + 4.40) * 1e-3;
    const float3 ozone = float3(0.650, 1.881, 0.085) * 1e-3;
    return rayleigh * density.x + mie * density.y + ozone * density.z;
}
float3 atmosphereSky(float3 rd, float3 sunDir, float viewHeightKm, float sunIntensity) {
    const float3 rayleighScatter = float3(5.802, 13.558, 33.1) * 1e-3;
    const float mieScatter = 3.996e-3;
    float3 ro = float3(0.0, ATMOSPHERE_GROUND_KM + max(viewHeightKm, 0.001), 0.0);
    float2 top = iSphere(ro, rd, float3(0.0), ATMOSPHERE_TOP_KM);
    if (top.y <= 0.0) return float3(0.0);
    float2 ground = iSphere(ro, rd, float3(0.0), ATMOSPHERE_GROUND_KM);
    float tStart = max(top.x, 0.0);
    float tEnd = (ground.x > 0.0) ? ground.x : top.y;
    float mu = dot(rd, sunDir);
    float pR = phaseRayleigh(mu);
    float pM = phaseCornetteShanks(mu, 0.8);
    const int VIEW_STEPS = 16;
    const int LIGHT_STEPS = 8;
    float dt = (tEnd - tStart) / float(VIEW_STEPS);
    float3 radiance = float3(0.0), transmittance = float3(1.0);
    for (int i = 0; i < VIEW_STEPS; i++) {
        float3 p = ro + rd * (tStart + (float(i) + 0.5) * dt);
        float3 dens = atmosphereDensity(length(p) - ATMOSPHERE_GROUND_KM);
        float3 sunT = float3(0.0);
        if (iSphere(p, sunDir, float3(0.0), ATMOSPHERE_GROUND_KM).x < 0.0) {
            float tl = iSphere(p, sunDir, float3(0.0), ATMOSPHERE_TOP_KM).y;
            float dl = tl / float(LIGHT_STEPS);
            float3 depth = float3(0.0);
            for (int j = 0; j < LIGHT_STEPS; j++) {
                float3 q = p + sunDir * ((float(j) + 0.5) * dl);
                depth += atmosphereExtinction(atmosphereDensity(length(q) - ATMOSPHERE_GROUND_KM)) * dl;
            }
            sunT = exp(-depth);
        }
        float3 scatter = sunT * (rayleighScatter * dens.x * pR + mieScatter * dens.y * pM) * sunIntensity;
        volumeStep(radiance, transmittance, atmosphereExtinction(dens), scatter, dt);
    }
    return radiance;
}
float3 ditherTPDF(float2 fragCoord, int frame) {
    float2 r = hash22(float2(floor(fragCoord) + 7919.0 * float(frame % 1024)));
    return float3((r.x + r.y - 1.0) / 255.0);
}
float3 debugNormal(float3 n) { return 0.5 + 0.5 * n; }
float3 debugHeat(float t) {
    t = clamp(t, 0.0, 1.0);
    return clamp(float3(1.5 * t, 1.6 * t * t * t - 0.1, 0.9 * sin(PI * t) + 0.2 * t * t), 0.0, 1.0);
}
const float3  SUN_DIR = normalize(float3(0.85, 0.2, -0.45));
const float SUN_INTENSITY = 20.0;
const float TERRAIN_SCALE = 0.32;
const float TERRAIN_HEIGHT = 2.0;
const float SNOW_LINE = 1.05;
const float EXPOSURE = 1.4;
const float FOCAL = 1.8;
float terrainHeight(float2 xz) { return TERRAIN_HEIGHT * erodedFbm(xz * TERRAIN_SCALE, 9); }
float2 map(float3 p) {
    // p.y - h(xz) is not a distance on slopes. Scaling by 0.45 keeps the march safe for slopes up to about 63 degrees.
    return float2(0.45 * (p.y - terrainHeight(p.xz)), 1.0);
}
float3 sunTransmittance(float heightKm, float3 dir) {
    float3 ro = float3(0.0, ATMOSPHERE_GROUND_KM + heightKm, 0.0);
    if (iSphere(ro, dir, float3(0.0), ATMOSPHERE_GROUND_KM).x > 0.0) return float3(0.0);
    float tl = iSphere(ro, dir, float3(0.0), ATMOSPHERE_TOP_KM).y;
    float3 depth = float3(0.0);
    for (int i = 0; i < 12; i++) {
        float3 q = ro + dir * ((float(i) + 0.5) * tl / 12.0);
        depth += atmosphereExtinction(atmosphereDensity(length(q) - ATMOSPHERE_GROUND_KM)) * tl / 12.0;
    }
    return exp(-depth);
}
float3 render(float2 fragCoord) {
    float2 uv = (2.0 * fragCoord - resolution.xy) / resolution.y;

#if DEBUG_MODE == 1
    return float3(terrainHeight(uv * 8.0) / TERRAIN_HEIGHT * 0.5 + 0.3);
#endif

    float3 ro = float3(-3.0 + 0.2 * time, 0.0, 4.0 - 0.6 * time);
    ro.y = terrainHeight(ro.xz) + 0.9;
    float3 ta = ro + float3(0.25, -0.16, -1.0);
    float3x3 cam = cameraMatrix(ro, ta, 0.0);
    float3 rd = cameraRay(cam, uv, FOCAL);

    float3 sky = atmosphereSky(rd, SUN_DIR, ro.y, SUN_INTENSITY);
    float3 sunColor = SUN_INTENSITY * 0.12 * sunTransmittance(ro.y, SUN_DIR);
    float3 hit = raymarch(ro, rd, 0.01, 40.0, 1.0);
#if DEBUG_MODE == 4
    return debugHeat(hit.z / float(RAYMARCH_MAX_STEPS));
#endif
    if (hit.x < 0.0) {
        return sky + sunColor * 40.0 * sunDisk(rd, SUN_DIR, 0.012, 2.0 / (resolution.y * FOCAL));
    }

    float t = hit.x;
    float3 p = ro + rd * t;
    float3 n = calcNormal(p, 0.001 * t);

    // material masks: rock on steep slopes, grass on flats, snow on high upward-facing ground
    float flatness = smoothstep(0.72, 0.88, n.y);
    float snow = smoothstep(SNOW_LINE - 0.15, SNOW_LINE + 0.1, p.y + 0.25 * fbm(p.xz * 6.0, 3))
               * smoothstep(0.55, 0.8, n.y);
    float grain = 0.5 + 0.5 * fbm(p.xz * 40.0, 4);
    float3 rock = mix(float3(0.10, 0.085, 0.07), float3(0.20, 0.17, 0.14), grain);
    float3 grass = mix(float3(0.06, 0.08, 0.03), float3(0.11, 0.12, 0.05), grain);
    float3 albedo = mix(rock, grass, flatness * (1.0 - smoothstep(0.6, 1.0, p.y)));
    albedo = mix(albedo, float3(0.85, 0.88, 0.92), snow);

    float sha = softShadow(p + n * 0.01, SUN_DIR, 0.02, 20.0, 16.0);
    float NoL = clamp(dot(n, SUN_DIR), 0.0, 1.0);
    float3 skyAmbient = atmosphereSky(float3(0.0, 1.0, 0.0), SUN_DIR, p.y, SUN_INTENSITY);
    float3 key = albedo * sunColor * NoL * sha;
    float3 fill = albedo * skyAmbient * (0.5 + 0.5 * n.y) * 2.0;
    float3 bounce = albedo * sunColor * 0.08 * clamp(dot(n, normalize(float3(-SUN_DIR.x, 0.0, -SUN_DIR.z))), 0.0, 1.0);

#if DEBUG_MODE == 2
    return debugNormal(n);
#elif DEBUG_MODE == 3
    return float3(1.0 - flatness, flatness, snow);
#elif DEBUG_MODE == 5
    return float3(sha);
#elif DEBUG_MODE == 6
    return float3(luminance(key), luminance(fill), luminance(bounce)) * 2.0;
#endif

    float3 col = key + fill + bounce;
    // aerial perspective: attenuate by the air between camera and hit and fill with sky color. Use the sky at the
    // horizon-clamped direction: below the planet's horizon the sky integral jumps, which would print a seam.
    float3 fogColor = atmosphereSky(normalize(float3(rd.x, max(rd.y, 0.02), rd.z)), SUN_DIR, ro.y, SUN_INTENSITY);
    float3 airT = exp(-t * atmosphereExtinction(atmosphereDensity(0.5 * (ro.y + p.y))) * 4.0);
    return col * airT + fogColor * (1.0 - airT);
}
void shade(thread float4 &fragColor, float2 fragCoord) {
    float3 col = render(fragCoord);
#if DEBUG_MODE == 0
    col = linearToSrgb(tonemapAgX(col * EXPOSURE)) + ditherTPDF(fragCoord, frame);
#endif
    fragColor = float4(col, 1.0);
}
};

fragment float4 shaderFragment(float4 position [[position]],
                               constant ShaderUniforms &uniforms [[buffer(0)]]) {
    ShaderScene scene{uniforms.resolution, uniforms.time, int(uniforms.frame)};
    float4 color = float4(0.0);
    // Metal's viewport origin is top-left. Scene math uses a bottom-left origin.
    scene.shade(color, float2(position.x, uniforms.resolution.y - position.y));
    return color;
}
