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
// metal-shader-skills: MSL 4.1, MIT.
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
#define DEBUG_MODE 0   // 0 final | 1 height | 2 normals | 3 foam mask | 4 trace steps | 5 fresnel | 6 light terms
const float PI  = 3.14159265358979;
const float TAU = 6.28318530717959;
float dot2(float2 v) { return dot(v, v); }
float dot2(float3 v) { return dot(v, v); }
float2x2 rot2(float a) {
    float2 cs = normalize(float2(cos(a), sin(a)));
    return float2x2(cs.x, cs.y, -cs.y, cs.x);
}
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
float3 hash32(float2 p) {
    int2 q = int2(floor(p));
    return uintToUnit(pcg3d(uint3(q.x, q.y, 0x9E37u)));
}
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
float3 simplexNoiseD(float2 p, float rotation) {
    const float SKEW = 0.36602540378;     // (sqrt(3) - 1) / 2: square lattice -> triangle lattice
    const float UNSKEW = 0.21132486541;   // (3 - sqrt(3)) / 6
    float2 cell = floor(p + (p.x + p.y) * SKEW);
    float2 d0 = p - cell + (cell.x + cell.y) * UNSKEW;
    float2 o = (d0.x > d0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);   // which of the cell's two triangles holds p
    float2 corners[3] = {cell, cell + o, cell + 1.0};
    float2 offsets[3] = {d0, d0 - o + UNSKEW, d0 - 1.0 + 2.0 * UNSKEW};
    float2x2 spin = rot2(rotation);
    float3 sum = float3(0.0);
    for (int k = 0; k < 3; k++) {
        float2 d = offsets[k];
        float t = max(0.5 - dot(d, d), 0.0);
        float2 g = spin * latticeGradient(corners[k]);
        float gd = dot(g, d);
        float t3 = t * t * t;
        // value t^4 (g.d); gradient t^4 g - 8 t^3 (g.d) d
        sum += float3(t3 * t * gd, t3 * t * g - 8.0 * t3 * gd * d);
    }
    return 99.2 * sum;   // 1 / max over the simplex of sum t^4 |d|
}
float3 simplexNoiseD(float2 p) { return simplexNoiseD(p, 0.0); }
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
float billowFbm(float2 p, int octaves) {
    const float2x2 octaveRotation = float2x2(0.8, 0.6, -0.6, 0.8);
    float sum = 0.0, amp = 0.5, weight = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        float n = abs(gradientNoise(p) * 1.4);
        n = n * (2.0 - n);   // round the lobe tops, keep the creases sharp
        sum += amp * n * weight;
        norm += amp;
        weight = clamp(n * 1.5, 0.0, 1.0);
        amp *= 0.5;
        p = 2.01 * (octaveRotation * p) + float2(17.13, -3.71);
    }
    return sum / norm;
}
float billowFbm(float3 p, int octaves) {
    const float3x3 octaveRotation = float3x3(0.00, 0.80, 0.60,
                                     -0.80, 0.36, -0.48,
                                     -0.60, -0.48, 0.64);
    float sum = 0.0, amp = 0.5, weight = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        float n = min(abs(gradientNoise(p)) * 1.4, 1.0);
        n = n * (2.0 - n);
        sum += amp * n * weight;
        norm += amp;
        weight = clamp(n * 1.5, 0.0, 1.0);
        amp *= 0.5;
        p = 2.01 * (octaveRotation * p) + float3(17.13, -3.71, 5.29);
    }
    return sum / norm;
}
float3 voronoiBorder(float2 p, float jitter) {
    float2 ip = floor(p), fp = fract(p);
    float2 mg = float2(0.0), mr = float2(0.0);
    float md = 8.0;
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        float2 g = float2(float(i), float(j));
        float2 r = g + jitter * hash22(ip + g) - fp;
        float d = dot(r, r);
        if (d < md) { md = d; mr = r; mg = g; }
    }
    md = 8.0;
    for (int j = -2; j <= 2; j++)
    for (int i = -2; i <= 2; i++) {
        float2 g = mg + float2(float(i), float(j));
        float2 r = g + jitter * hash22(ip + g) - fp;
        if (dot2(mr - r) > 1e-5) {
            md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
        }
    }
    return float3(md, mr);
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
float3 fresnelSchlick(float u, float3 f0) {
    float m = clamp(1.0 - u, 0.0, 1.0);
    float m2 = m * m;
    return f0 + (1.0 - f0) * (m2 * m2 * m);
}
float distributionGGX(float NoH, float alpha) {
    float a2 = alpha * alpha;
    float d = NoH * NoH * (a2 - 1.0) + 1.0;
    return a2 / (PI * d * d);
}
float visibilitySmithGGX(float NoV, float NoL, float alpha) {
    float a2 = alpha * alpha;
    float gv = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
    float gl = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
    return 0.5 / max(gv + gl, 1e-6);
}
float3 specularGGX(float3 n, float3 v, float3 l, float roughness, float3 f0) {
    float3 h = normalize(v + l);
    float NoL = clamp(dot(n, l), 0.0, 1.0);
    float NoV = max(dot(n, v), 1e-4);
    float NoH = clamp(dot(n, h), 0.0, 1.0);
    float VoH = clamp(dot(v, h), 0.0, 1.0);
    float alpha = max(roughness, 0.045);
    alpha *= alpha;
    return PI * distributionGGX(NoH, alpha) * visibilitySmithGGX(NoV, NoL, alpha) * fresnelSchlick(VoH, f0) * NoL;
}
float3 linearToSrgb(float3 c) {
    c = max(c, 0.0);
    return mix(c * 12.92, 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}
float luminance(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }
float3 tonemapAgXPunchy(float3 c) {
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
    c = pow(max(c, 0.0), float3(1.35));
    float luma = dot(c, float3(0.2126, 0.7152, 0.0722));
    c = luma + 1.4 * (c - luma);
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
const float3  SUN_DIR = normalize(float3(0.2, 0.14, -1.0));
const float SUN_INTENSITY = 20.0;
const float WIND_ANGLE = 1.9;
const float SWELL_LENGTH = 34.0;
const float SWELL_HEIGHT = 0.8;
const float CHOP = 0.7;
const float CREST_SHARPNESS = 2.4;
const float RIPPLE = 0.008;
const float FOAM_AMOUNT = 1.0;
const float3  WATER_DEEP = float3(0.004, 0.02, 0.04);
const float3  WATER_GLOW = float3(0.05, 0.26, 0.25);
const float HAZE = 6.0;
const float CAMERA_HEIGHT = 3.0;
const float EXPOSURE = 0.9;
const float FOCAL = 2.0;
const float GRAVITY = 9.81;
const float WAVELENGTH_RATIO = 0.8;
const int   TRACE_WAVES = 12;
const int   SHADE_WAVES = 28;
const int   FOAM_WAVES = 6;
const float TRACE_FAR = 400.0;
void wave(int i, thread float2 &dir, thread float &k, thread float &amp, thread float &phase) {
    float fi = float(i);
    float3 h = hash32(float2(fi, 17.0));
    float a = WIND_ANGLE + mix(0.35, 1.3, min(fi / 12.0, 1.0)) * (2.0 * h.x - 1.0);
    dir = float2(cos(a), sin(a));
    k = TAU / (SWELL_LENGTH * pow(WAVELENGTH_RATIO, fi) * mix(0.85, 1.15, h.y));
    amp = SWELL_HEIGHT * pow(CHOP, fi);
    phase = TAU * h.z;
}
float wavePhase(float2 dir, float k, float phase, float2 xz) {
    return k * dot(dir, xz) - sqrt(GRAVITY * k) * time + phase;
}
float waveKeep(float2 dir, float k, float4 fp) {
    float footprint = length(float2(dot(dir, float2(-fp.y, fp.x)) * fp.z, dot(dir, fp.xy) * fp.w));
    return smoothstep(2.0, 6.0, TAU / (k * footprint));
}
float oceanHeight(float2 xz, int count, float4 fp) {
    float h = 0.0;
    for (int i = 0; i < SHADE_WAVES; i++) {
        if (i >= count) break;
        float2 dir; float k, amp, phase;
        wave(i, dir, k, amp, phase);
        h += waveKeep(dir, k, fp) * amp * (exp(CREST_SHARPNESS * (sin(wavePhase(dir, k, phase, xz)) - 1.0)) - 0.3);
    }
    return h;
}
float profileMaxSlope() {
    float s = CREST_SHARPNESS;
    float sn = (sqrt(1.0 + 4.0 * s * s) - 1.0) / (2.0 * s);
    return s * sqrt(1.0 - sn * sn) * exp(s * (sn - 1.0));
}
float3 oceanBounds() {
    float ampSum = 0.0, slopeSum = 0.0;
    for (int i = 0; i < TRACE_WAVES; i++) {
        float2 dir; float k, amp, phase;
        wave(i, dir, k, amp, phase);
        ampSum += amp;
        slopeSum += amp * k;
    }
    return float3(-0.3 * ampSum, 0.7 * ampSum, slopeSum * profileMaxSlope());
}
float2 traceOcean(float3 ro, float3 rd, float3 bounds, float4 pixelSpread) {
    if (rd.y >= 0.0) return float2(-1.0, 0.0);
    float t = max((ro.y - bounds.y) / -rd.y, 0.0);
    float tEnd = min((ro.y - bounds.x) / -rd.y, TRACE_FAR);
    float closing = -rd.y + 0.6 * bounds.z * length(rd.xz);
    float tPrev = t, gapPrev = 1e10;
    for (int i = 0; i < 200; i++) {
        float3 p = ro + rd * t;
        float gap = p.y - oceanHeight(p.xz, TRACE_WAVES, pixelSpread * float4(1.0, 1.0, t, t));
        if (gap < 0.0) return float2(mix(tPrev, t, gapPrev / (gapPrev - gap)), float(i));
        if (t >= tEnd) break;
        tPrev = t;
        gapPrev = gap;
        t = min(t + max(gap / closing, 0.004 * t), tEnd);
    }
    return float2(-1.0, 200.0);
}
float4 oceanDetail(float2 xz, float4 fp, thread float &lostSlope2, thread float &crest) {
    const float slopeRms = 0.3 + 0.06 * CREST_SHARPNESS;   // RMS of the profile's slope per unit a k
    float4 s = float4(0.0);
    lostSlope2 = 0.0;
    crest = 0.0;
    float crestMax = 0.0;
    for (int i = 0; i < SHADE_WAVES; i++) {
        float2 dir; float k, amp, phase;
        wave(i, dir, k, amp, phase);
        float keep = waveKeep(dir, k, fp);
        float theta = wavePhase(dir, k, phase, xz);
        float sn = sin(theta), cs = cos(theta);
        float e = exp(CREST_SHARPNESS * (sn - 1.0));
        float d1 = CREST_SHARPNESS * cs * e;                                      // dW/dtheta
        float d2 = CREST_SHARPNESS * (CREST_SHARPNESS * cs * cs - sn) * e;        // d2W/dtheta2
        s += keep * amp * float4(e - 0.3, k * d1 * dir, k * k * d2);
        lostSlope2 += (1.0 - keep) * (amp * k * slopeRms) * (amp * k * slopeRms);
        if (i < FOAM_WAVES) {
            crest -= keep * amp * k * k * d2;
            crestMax += amp * k * k * CREST_SHARPNESS;   // a crest's curvature: -W'' = s at the top
        }
    }
    crest /= crestMax;
    return s;
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
    float pixelAngle = 2.0 / (resolution.y * FOCAL);
    float viewKm = CAMERA_HEIGHT * 0.001;

#if DEBUG_MODE == 1
    return float3(0.5 + 0.5 * oceanHeight(uv * 30.0, SHADE_WAVES, float4(1.0, 0.0, 1e-4, 1e-4)) / SWELL_HEIGHT);
#endif

    float3 ro = float3(0.0, CAMERA_HEIGHT, 0.0);
    float3x3 cam = cameraMatrix(ro, ro + float3(0.0, -0.06, -1.0), 0.0);
    float3 rd = cameraRay(cam, uv, FOCAL);

    float3 sunColor = SUN_INTENSITY * 0.12 * sunTransmittance(viewKm, SUN_DIR);
    if (rd.y >= 0.0) {
        float3 sky = atmosphereSky(rd, SUN_DIR, viewKm, SUN_INTENSITY);
        return sky + sunColor * 40.0 * sunDisk(rd, SUN_DIR, 0.012, pixelAngle);
    }

    // pixel footprint on the water per meter of distance: pixelAngle across the view, stretched by 1/sin(grazing
    // angle) along it
    float4 pixelSpread = float4(normalize(rd.xz), pixelAngle, pixelAngle / max(-rd.y, 0.01));
    float3 bounds = oceanBounds();
    float2 hit = traceOcean(ro, rd, bounds, pixelSpread);
#if DEBUG_MODE == 4
    return debugHeat(hit.y / 200.0);
#endif
    // past TRACE_FAR the waves are below pixel size anyway: use the mean plane and let filtering do the rest
    float t = (hit.x > 0.0) ? hit.x : ro.y / -rd.y;
    float3 p = ro + rd * t;

    float4 fp = pixelSpread * float4(1.0, 1.0, t, t);
    float lostSlope2, crest;
    float4 wv = oceanDetail(p.xz, fp, lostSlope2, crest);
    float2 slope = wv.yz;

    // capillary ripples: two octaves of simplex flow noise whose gradients spin, so they churn instead of sliding
    float footprint = sqrt(fp.z * fp.w);   // ripples are isotropic: use the ellipse's mean size
    float keepRipple = smoothstep(2.0, 6.0, 0.8 / footprint);
    float3 r1 = simplexNoiseD(p.xz * 1.3 + float2(0.3, 0.9) * time, 1.3 * time);
    float3 r2 = simplexNoiseD(p.xz * 3.7 - float2(0.6, 0.2) * time, -2.1 * time);
    slope += RIPPLE * keepRipple * (1.3 * r1.yz + 0.5 * 3.7 * r2.yz * smoothstep(2.0, 6.0, 0.3 / footprint));
    lostSlope2 += RIPPLE * RIPPLE * 4.0 * (1.0 - keepRipple);
    float3 n = normalize(float3(-slope.x, 1.0, -slope.y));

    // foam: the convexity of the big waves' crests sets how much of a billow-noise lace is covered, so patches
    // grow from crisp filaments on mild crests to solid caps on the sharpest ones
    float lace = billowFbm(p.xz * float2(1.2, 2.4) + float2(0.0, 0.5 * time), 6);
    float coverage = 0.7 * smoothstep(0.08, 0.3, crest);   // below 1, so even the sharpest caps stay broken
    float foam = FOAM_AMOUNT * coverage * smoothstep(1.0 - coverage, 1.15 - coverage, lace);
    // inside a patch, foam is a network of bubbles: dense along Voronoi borders, thin inside the cells
    float bubbles = smoothstep(0.22, 0.0, voronoiBorder(p.xz * float2(2.5, 4.0), 1.0).x);
    foam *= mix(0.75, mix(0.4, 1.0, bubbles), smoothstep(2.0, 6.0, 0.3 / footprint));

    float3 v = -rd;
    float NoV = max(dot(n, v), 1e-3);
    float3 F = fresnelSchlick(NoV, float3(0.02));
    float3 refl = reflect(rd, n);
    refl.y = abs(refl.y);   // a reflection into the water would hit the next wave: fold it back to the sky
    float3 skyRefl = atmosphereSky(refl, SUN_DIR, viewKm, SUN_INTENSITY);
    float3 skyAmbient = atmosphereSky(float3(0.0, 1.0, 0.0), SUN_DIR, viewKm, SUN_INTENSITY);

    // sun glint: GGX whose roughness absorbs the slope variance of the waves filtered away at this distance
    float alpha = sqrt(0.02 * 0.02 + 2.0 * lostSlope2);
    float3 glint = specularGGX(n, v, SUN_DIR, sqrt(alpha), float3(0.02)) * sunColor;
    float3 reflection = F * skyRefl;

    // body: refracted light scattered back out, plus sunlight glowing through thin crests seen against the sun
    float backlit = pow(clamp(dot(rd, SUN_DIR), 0.0, 1.0), 4.0);
    float thin = smoothstep(0.45, 0.9, (wv.x - bounds.x) / (bounds.y - bounds.x));   // crest tops only
    float3 body = (1.0 - F) * (WATER_DEEP * (skyAmbient + sunColor * max(dot(n, SUN_DIR), 0.0))
                             + WATER_GLOW * sunColor * backlit * thin);

    // foam is a thin white scatterer: diffuse sun and sky light, plus sunlight shining through it from behind
    float3 foamColor = float3(0.9) * (sunColor * (max(dot(n, SUN_DIR), 0.0) + 0.5 * backlit) + 3.0 * skyAmbient);

#if DEBUG_MODE == 2
    return debugNormal(n);
#elif DEBUG_MODE == 3
    return float3(foam, clamp(crest, 0.0, 1.0), lace);
#elif DEBUG_MODE == 5
    return sqrt(F);
#elif DEBUG_MODE == 6
    return float3(luminance(reflection), luminance(glint) * 0.1, luminance(body) * 10.0);
#endif

    float3 col = mix(reflection + glint + body, foamColor, foam);
    // aerial perspective, with the haze color taken from the sky just above the horizon so the two meet without a seam
    float3 fogColor = atmosphereSky(normalize(float3(rd.x, 0.0, rd.z)), SUN_DIR, viewKm, SUN_INTENSITY);
    float3 airT = exp(-t * 0.001 * HAZE * atmosphereExtinction(atmosphereDensity(0.0)));
    return col * airT + fogColor * (1.0 - airT);
}
void shade(thread float4 &fragColor, float2 fragCoord) {
    float3 col = render(fragCoord);
#if DEBUG_MODE == 0
    col = linearToSrgb(tonemapAgXPunchy(col * EXPOSURE)) + ditherTPDF(fragCoord, frame);
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
