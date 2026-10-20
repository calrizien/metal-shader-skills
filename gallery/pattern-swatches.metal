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
#define DEBUG_MODE 0   // 0 final | 3 tile ids
const float TAU = 6.28318530717959;
float saturate(float x) { return clamp(x, 0.0, 1.0); }
float3 saturate(float3 x) { return clamp(x, 0.0, 1.0); }
float dot2(float2 v) { return dot(v, v); }
float dot2(float3 v) { return dot(v, v); }
float floorMod(float x, float y) { return x - y * floor(x / y); }
float2 floorMod(float2 x, float2 y) { return x - y * floor(x / y); }
float2 floorMod(float2 x, float y) { return x - y * floor(x / y); }
float3 floorMod(float3 x, float3 y) { return x - y * floor(x / y); }
float3 floorMod(float3 x, float y) { return x - y * floor(x / y); }
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
float warpedFbm(float2 p, float strength, int octaves, thread float2 &q, thread float2 &r) {
    q = float2(fbm(p, octaves), fbm(p + float2(3.1, 7.4), octaves));
    r = float2(fbm(p + strength * q + float2(9.7, 2.6), octaves),
             fbm(p + strength * q + float2(6.3, 1.9), octaves));
    return fbm(p + strength * r, octaves);
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
float smoothVoronoi(float2 p, float k) {
    float2 ip = floor(p), fp = fract(p);
    float acc = 0.0;
    for (int j = -2; j <= 2; j++)
    for (int i = -2; i <= 2; i++) {
        float2 g = float2(float(i), float(j));
        float2 r = g + hash22(ip + g) - fp;
        acc += exp2(-k * length(r));
    }
    return -log2(acc) / k;
}
float2 triangleWave(float2 x) { return 1.0 - 2.0 * abs(fract(x * 0.5) - 0.5); }
float filteredChecker(float2 p, float2 w) {
    w = max(w, 1e-4);
    float2 i = (triangleWave(p + 0.5 * w) - triangleWave(p - 0.5 * w)) / w;
    return 0.5 - 0.5 * i.x * i.y;
}
float4 hexGrid(float2 p) {
    const float2 s = float2(1.0, 1.7320508);
    float2 a = floorMod(p, s) - 0.5 * s;
    float2 b = floorMod(p - 0.5 * s, s) - 0.5 * s;
    float2 local = (dot(a, a) < dot(b, b)) ? a : b;
    float2 center = p - local;
    float2 id = floor(float2(center.x * 2.0, center.y * 1.1547005) + 0.5);
    return float4(local, id);
}
float hexEdgeDistance(float2 local) {
    float2 a = abs(local);
    return 0.5 - max(a.x, dot(a, float2(0.5, 0.8660254)));
}
float truchetArcs(float2 p, float w) {
    float2 id = floor(p);
    float2 f = fract(p) - 0.5;
    if (hash12(id) < 0.5) f.x = -f.x;
    float2 q = f - 0.5 * sign(f.x + f.y + 1e-6);
    return abs(length(q) - 0.5) - w;
}
float3 srgbToLinear(float3 c) {
    c = max(c, 0.0);
    return mix(c / 12.92, pow((c + 0.055) / 1.055, float3(2.4)), step(0.04045, c));
}
float3 linearToSrgb(float3 c) {
    c = max(c, 0.0);
    return mix(c * 12.92, 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
}
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
float3 oklchToLinearSrgb(float3 lch) {
    return oklabToLinearSrgb(float3(lch.x, lch.y * cos(lch.z), lch.y * sin(lch.z)));
}
float fillAA(float d) {
    float w = length(float2(dfdx(d), dfdy(d)));
    return clamp(0.5 - d / max(w, 1e-6), 0.0, 1.0);
}
float fillAA(float d, float px) { return clamp(0.5 - d / px, 0.0, 1.0); }
float3 ditherTPDF(float2 fragCoord, int frame) {
    float2 r = hash22(float2(floor(fragCoord) + 7919.0 * float(frame % 1024)));
    return float3((r.x + r.y - 1.0) / 255.0);
}
float3 debugIdColor(float id) {
    return 0.55 + 0.45 * cos(TAU * (0.618034 * id + float3(0.0, 0.33, 0.67)));
}
float3 marble(float2 p) {
    float2 q, r;
    float f = warpedFbm(p * 1.5, 3.0, 5, q, r);
    float3 col = mixOklab(srgbToLinear(float3(0.92, 0.90, 0.86)), srgbToLinear(float3(0.35, 0.38, 0.45)), saturate(length(q) * 0.9));
    col = mix(col, srgbToLinear(float3(0.62, 0.42, 0.30)), saturate(r.y * r.y * 2.0));
    return col * (0.85 + 0.25 * f);
}
float3 crackedEarth(float2 p, float px) {
    float3 v = voronoiBorder(p * 4.0, 0.9);
    float2 cell = floor(p * 4.0 + v.yz);
    float tint = hash12(cell);
    float3 col = mix(srgbToLinear(float3(0.62, 0.44, 0.30)), srgbToLinear(float3(0.75, 0.58, 0.40)), tint);
    col *= 0.75 + 0.25 * smoothstep(0.0, 0.25, v.x);          // plates darken toward their curled edges
    float plate = fillAA(0.03 - v.x, px * 4.0);                 // cracks: border distance < 0.03 cell units
    return mix(srgbToLinear(float3(0.12, 0.08, 0.06)), col, plate);
}
float3 hexTiles(float2 p, float px) {
    float4 h = hexGrid(p * 5.0);
    float edge = hexEdgeDistance(h.xy);
    float3 base = oklchToLinearSrgb(float3(0.7, 0.09, 3.6 + 0.8 * hash12(h.zw)));
    float bevel = smoothstep(0.0, 0.12, edge);
    return mix(float3(0.02), base * (0.7 + 0.3 * bevel), smoothstep(0.03 - px * 5.0, 0.03 + px * 5.0, edge));
}
float3 truchet(float2 p, float px) {
    float d = truchetArcs(p * 5.0, 0.12) / 5.0;
    float stripe = truchetArcs(p * 5.0, 0.03) / 5.0;
    float3 col = srgbToLinear(float3(0.08, 0.10, 0.16));
    col = mix(col, srgbToLinear(float3(0.95, 0.75, 0.30)), fillAA(d, px));
    return mix(col, srgbToLinear(float3(0.55, 0.20, 0.10)), fillAA(stripe, px));
}
float3 organicCells(float2 p) {
    float s = smoothVoronoi(p * 5.0, 12.0);
    float3 col = mixOklab(srgbToLinear(float3(0.95, 0.55, 0.55)), srgbToLinear(float3(0.35, 0.05, 0.15)), saturate(s * 1.6));
    return col * (0.6 + 0.4 * smoothstep(0.1, 0.5, s));
}
float3 checker(float2 p, float px) {
    // perspective floor: the filtered checker stays grey instead of moire in the distance
    float z = 1.0 / max(0.55 - p.y, 0.02);
    float2 floorUV = float2(p.x * z, z) * 1.5;
    float c = filteredChecker(floorUV, float2(px * z * z * 1.5 + px * z * 1.5));
    return mix(float3(0.05), float3(0.8), c) * smoothstep(0.55, 0.3, p.y);
}
void shade(thread float4 &fragColor, float2 fragCoord) {
    float2 uv = fragCoord / resolution.y;
    float px = 1.0 / resolution.y;
    float aspect = resolution.x / resolution.y;
    float2 grid = float2(3.0, 2.0);
    float2 tileSize = float2(aspect, 1.0) / grid;
    float2 id = floor(uv / tileSize);
    float2 local = (uv - id * tileSize) / tileSize.y;        // 0..(tile aspect) x 0..1
    float2 p = local - 0.5 * float2(tileSize.x / tileSize.y, 1.0);
    float k = id.x + 3.0 * (1.0 - id.y);
    float lpx = px / tileSize.y;

    float3 col;
    if (k < 0.5) col = marble(p + 0.05 * time);
    else if (k < 1.5) col = crackedEarth(p, lpx);
    else if (k < 2.5) col = hexTiles(p, lpx);
    else if (k < 3.5) col = truchet(p, lpx);
    else if (k < 4.5) col = organicCells(p + float2(0.0, 0.03 * time));
    else col = checker(p, lpx);

    // tile frame
    float2 e = min(local, float2(tileSize.x / tileSize.y, 1.0) - local);
    col *= smoothstep(0.0, 0.02, min(e.x, e.y));

#if DEBUG_MODE == 3
    col = debugIdColor(k);
#endif
    fragColor = float4(linearToSrgb(col) + ditherTPDF(fragCoord, frame), 1.0);
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
