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
#define DEBUG_MODE 0   // 0 final | 1 distance slice | 2 normals | 3 material ids | 4 steps | 5 shadow/AO/blend | 6 light terms
#define AA 1           // samples per pixel (4-8 for stills)
const float PI  = 3.14159265358979;
const float TAU = 6.28318530717959;
float2x2 rot2(float a) {
    float2 cs = normalize(float2(cos(a), sin(a)));
    return float2x2(cs.x, cs.y, -cs.y, cs.x);
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
float2 hash22(float2 p) {
    int2 q = int2(floor(p));
    return uintToUnit(pcg3d(uint3(q.x, q.y, 0x2545u))).xy;
}
float2 triangleWave(float2 x) { return 1.0 - 2.0 * abs(fract(x * 0.5) - 0.5); }
float filteredChecker(float2 p, float2 w) {
    w = max(w, 1e-4);
    float2 i = (triangleWave(p + 0.5 * w) - triangleWave(p - 0.5 * w)) / w;
    return 0.5 - 0.5 * i.x * i.y;
}
float sdSphere(float3 p, float r) { return length(p) - r; }
float sdRoundBox(float3 p, float3 b, float r) {
    float3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}
float sdTorus(float3 p, float2 t) {
    float2 q = float2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
float smax(float a, float b, float k) { return -smin(-a, -b, k); }
float smoothSubtract(float a, float b, float k) { return smax(a, -b, k); }
float2 sminBlend(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return float2(mix(b, a, h) - k * h * (1.0 - h), h);
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
float calcAO(float3 p, float3 n, float scale) {
    float occ = 0.0;
    float weight = 1.0;
    for (int i = 0; i < 5; i++) {
        float h = 0.01 + scale * float(i) / 4.0;
        float d = map(p + h * n).x;
        occ += (h - d) * weight;
        weight *= 0.95;
    }
    return clamp(1.0 - 3.0 * occ / max(scale / 0.12, 1e-3), 0.0, 1.0);
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
float3 shadePBR(float3 n, float3 v, float3 l, float3 albedo, float roughness, float metallic) {
    float3 f0 = mix(float3(0.04), albedo, metallic);
    float NoL = clamp(dot(n, l), 0.0, 1.0);
    float3 F = fresnelSchlick(max(dot(n, v), 0.0), f0);
    float3 diffuse = albedo * (1.0 - metallic) * (1.0 - F) * NoL;
    return diffuse + specularGGX(n, v, l, roughness, f0);
}
float3 envBRDFApprox(float3 f0, float NoV, float roughness) {
    float4 r = roughness * float4(-1.0, -0.0275, -0.572, 0.022) + float4(1.0, 0.0425, 1.04, -0.04);
    float a = min(r.x * r.x, exp2(-9.28 * NoV)) * r.x + r.y;
    float2 ab = float2(-1.04, 1.04) * a + r.zw;
    return f0 * ab.x + ab.y;
}
float3 hemisphereLight(float3 n, float3 skyColor, float3 groundColor) {
    return mix(groundColor, skyColor, 0.5 + 0.5 * n.y);
}
float3 srgbToLinear(float3 c) {
    c = max(c, 0.0);
    return mix(c / 12.92, pow((c + 0.055) / 1.055, float3(2.4)), step(0.04045, c));
}
float3 linearToSrgb(float3 c) {
    c = max(c, 0.0);
    return mix(c * 12.92, 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}
float luminance(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }
float3 linearSrgbToOklab(float3 c) {
    float3 lms = c * float3x3(0.4122214708, 0.5363325363, 0.0514459929,
                        0.2119034982, 0.6806995451, 0.1073969566,
                        0.0883024619, 0.2817188376, 0.6299787005);
    lms = sign(lms) * pow(abs(lms), float3(1.0 / 3.0));
    return lms * float3x3(0.2104542553, 0.7936177850, -0.0040720468,
                      1.9779984951, -2.4285922050, 0.4505937099,
                      0.0259040371, 0.7827717662, -0.8086757660);
}
float3 oklabToLinearSrgb(float3 lab) {
    float3 lms = lab * float3x3(1.0, 0.3963377774, 0.2158037573,
                          1.0, -0.1055613458, -0.0638541728,
                          1.0, -0.0894841775, -1.2914855480);
    lms = lms * lms * lms;
    return lms * float3x3(4.0767416621, -3.3077115913, 0.2309699292,
                      -1.2684380046, 2.6097574011, -0.3413193965,
                      -0.0041960863, -0.7034186147, 1.7076147010);
}
float3 mixOklab(float3 a, float3 b, float t) {
    return oklabToLinearSrgb(mix(linearSrgbToOklab(a), linearSrgbToOklab(b), t));
}
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
float distanceFog(float t, float density) { return 1.0 - exp(-t * density); }
float3 simpleSky(float3 rd, float3 sunDir) {
    float y = max(rd.y, 0.0);
    float3 zenith = float3(0.12, 0.28, 0.62);
    float3 horizon = float3(0.62, 0.74, 0.88);
    float3 col = mix(horizon, zenith, pow(y, 0.5));
    col = mix(col, float3(0.28, 0.26, 0.24), smoothstep(0.0, -0.08, rd.y));
    float mu = max(dot(rd, sunDir), 0.0);
    col += float3(1.0, 0.75, 0.45) * (0.25 * pow(mu, 8.0) + 0.6 * pow(mu, 64.0) + 2.0 * pow(mu, 512.0));
    return col;
}
float2 aaOffset(int i) {
    return fract(0.5 + float(i) * float2(0.7548776662, 0.5698402910)) - 0.5;
}
float3 ditherTPDF(float2 fragCoord, int frame) {
    float2 r = hash22(float2(floor(fragCoord) + 7919.0 * float(frame % 1024)));
    return float3((r.x + r.y - 1.0) / 255.0);
}
float3 debugDistance(float d) {
    float3 col = (d > 0.0) ? float3(0.9, 0.6, 0.3) : float3(0.4, 0.7, 0.85);
    col *= 1.0 - exp(-4.0 * abs(d));
    col *= 0.8 + 0.2 * cos(TAU * d / 0.1);
    return mix(col, float3(1.0), 1.0 - smoothstep(0.0, 0.01, abs(d)));
}
float3 debugNormal(float3 n) { return 0.5 + 0.5 * n; }
float3 debugIdColor(float id) {
    return 0.55 + 0.45 * cos(TAU * (0.618034 * id + float3(0.0, 0.33, 0.67)));
}
float3 debugHeat(float t) {
    t = clamp(t, 0.0, 1.0);
    return clamp(float3(1.5 * t, 1.6 * t * t * t - 0.1, 0.9 * sin(PI * t) + 0.2 * t * t), 0.0, 1.0);
}
const float3  SUN_DIR = normalize(float3(0.7, 0.6, -0.4));
const float3  SUN_COLOR = float3(3.2, 2.8, 2.3);
const float3  SKY_FILL = float3(0.35, 0.45, 0.6);
const float3  GROUND_FILL = float3(0.18, 0.15, 0.12);
const float BLEND = 0.25;
const float EXPOSURE = 1.0;
const float FOCAL = 2.2;
const float MAT_FLOOR = 1.0;
const float MAT_PLINTH = 2.0;
const float MAT_GLAZE = 3.0;
const float MAT_GOLD = 4.0;
float2 map(float3 p) {
    float2 res = float2(p.y, MAT_FLOOR);

    float plinth = sdRoundBox(p - float3(0.0, 0.3, 0.0), float3(0.9, 0.3, 0.9), 0.04);
    if (plinth < res.x) res = float2(plinth, MAT_PLINTH);

    // Sculpture: a rounded block and a ball melted together. sminBlend's weight drives the glaze color.
    float3 q = p - float3(0.0, 1.0, 0.0);
    q.xz = rot2(0.6) * q.xz;
    float block = sdRoundBox(q, float3(0.32, 0.38, 0.32), 0.08);
    float ball = sdSphere(q - float3(0.16, 0.44, 0.05), 0.3);
    float2 blob = sminBlend(block, ball, BLEND);
    blob.x = smoothSubtract(blob.x, sdTorus(q - float3(0.0, -0.08, 0.0), float2(0.4, 0.05)), 0.04);
    if (blob.x < res.x) res = float2(blob.x, MAT_GLAZE + 0.99 * blob.y);

    // Gold ring standing on the plinth.
    float3 r = p - float3(-0.45, 0.8, -0.5);
    r.yz = rot2(1.25) * r.yz;
    float ring = sdTorus(r, float2(0.17, 0.035));
    if (ring < res.x) res = float2(ring, MAT_GOLD);
    return res;
}
void material(float id, float3 p, float footprint, thread float3 &albedo, thread float &rough, thread float &metal) {
    float m = floor(id);
    rough = 0.5;
    metal = 0.0;
    if (m == MAT_FLOOR) {
        float checker = filteredChecker(p.xz * 2.0, float2(footprint * 2.0));
        albedo = mix(float3(0.30, 0.28, 0.26), float3(0.42, 0.40, 0.37), checker);
        rough = 0.7;
    } else if (m == MAT_PLINTH) {
        albedo = float3(0.55, 0.53, 0.5);
        rough = 0.85;
    } else if (m == MAT_GLAZE) {
        float w = fract(id) / 0.99;
        albedo = mixOklab(srgbToLinear(float3(0.95, 0.45, 0.25)), srgbToLinear(float3(0.15, 0.55, 0.6)), w);
        rough = 0.25;
    } else {
        albedo = float3(1.0, 0.78, 0.34);
        rough = 0.2;
        metal = 1.0;
    }
}
float3 render(float2 fragCoord) {
    float2 uv = (2.0 * fragCoord - resolution.xy) / resolution.y;
    float an = 0.35 * time;
    float3 ro = float3(3.4 * sin(an), 1.9, -3.4 * cos(an));
    float3 ta = float3(0.0, 0.85, 0.0);
    float3x3 cam = cameraMatrix(ro, ta, 0.0);
    float3 rd = cameraRay(cam, uv, FOCAL);

#if DEBUG_MODE == 1
    return debugDistance(map(float3(uv.x * 1.6, uv.y * 1.6 + 0.9, 0.0)).x);   // slice at z = 0
#endif

    float3 sky = simpleSky(rd, SUN_DIR);
    float3 hit = raymarch(ro, rd, 0.1, 30.0, 1.0);
#if DEBUG_MODE == 4
    return debugHeat(hit.z / float(RAYMARCH_MAX_STEPS));
#endif
    if (hit.x < 0.0) return sky;

    float t = hit.x;
    float3 p = ro + rd * t;
    float3 n = calcNormal(p, 0.0005 * t);
    float3 v = -rd;
    float3 albedo;
    float rough, metal;
    material(hit.y, p, t * 2.0 / (resolution.y * FOCAL), albedo, rough, metal);

    float sha = softShadow(p + n * 0.002, SUN_DIR, 0.01, 8.0, 12.0);
    float ao = calcAO(p, n, 0.15);
    float3 refl = reflect(rd, n);
    float3 f0 = mix(float3(0.04), albedo, metal);

    float3 key = shadePBR(n, v, SUN_DIR, albedo, rough, metal) * SUN_COLOR * sha;
    float3 fill = albedo * (1.0 - metal) * hemisphereLight(n, SKY_FILL, GROUND_FILL) * ao;
    float3 spec = envBRDFApprox(f0, max(dot(n, v), 0.0), rough) * simpleSky(refl, SUN_DIR)
              * ao * smoothstep(-0.1, 0.3, refl.y);
    float3 bounceDir = normalize(float3(-SUN_DIR.x, 0.0, -SUN_DIR.z));
    float3 bounce = albedo * (1.0 - metal) * float3(0.25, 0.18, 0.12) * clamp(dot(n, bounceDir), 0.0, 1.0) * ao;

#if DEBUG_MODE == 2
    return debugNormal(n);
#elif DEBUG_MODE == 3
    return debugIdColor(floor(hit.y));
#elif DEBUG_MODE == 5
    return float3(sha, ao, fract(hit.y) / 0.99);
#elif DEBUG_MODE == 6
    return float3(luminance(key), luminance(fill + bounce), luminance(spec));
#endif

    float3 col = key + fill + spec + bounce;
    return mix(col, sky, distanceFog(t, 0.02));
}
void shade(thread float4 &fragColor, float2 fragCoord) {
    float3 acc = float3(0.0);
    for (int i = 0; i < AA; i++) {
        float3 c = render(fragCoord + (AA > 1 ? aaOffset(i) : float2(0.0)));
#if DEBUG_MODE == 0
        c = tonemapAgX(c * EXPOSURE);   // tonemap per sample so bright edges antialias
#endif
        acc += c;
    }
    float3 col = acc / float(AA);
#if DEBUG_MODE == 0
    col = linearToSrgb(col) + ditherTPDF(fragCoord, frame);
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
