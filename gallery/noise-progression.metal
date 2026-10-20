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
#define DEBUG_MODE 0 // 0 grayscale | 3 tile IDs | 5 unclipped scalar false color
const float TAU = 6.28318530717959;
float saturate(float x) { return clamp(x, 0.0, 1.0); }
float3 saturate(float3 x) { return clamp(x, 0.0, 1.0); }
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
float hash13(float3 p) {
    uint3 q = uint3(int3(floor(p)));
    return uintToUnit(pcgHash(q.x + pcgHash(q.y + pcgHash(q.z))));
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
float3 valueNoiseD(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = quinticFade(f), du = quinticFadeDeriv(f);
    float a = hash12(i);
    float b = hash12(i + float2(1.0, 0.0));
    float c = hash12(i + float2(0.0, 1.0));
    float d = hash12(i + float2(1.0, 1.0));
    float k1 = b - a, k2 = c - a, k3 = a - b - c + d;
    return float3(a + k1 * u.x + k2 * u.y + k3 * u.x * u.y,
                du * float2(k1 + k3 * u.y, k2 + k3 * u.x));
}
float valueNoise(float2 p) { return valueNoiseD(p).x; }
float valueNoise(float3 p) {
    float3 i = floor(p), f = fract(p);
    float3 u = quinticFade(f);
    return mix(mix(mix(hash13(i + float3(0, 0, 0)), hash13(i + float3(1, 0, 0)), u.x),
                   mix(hash13(i + float3(0, 1, 0)), hash13(i + float3(1, 1, 0)), u.x), u.y),
               mix(mix(hash13(i + float3(0, 0, 1)), hash13(i + float3(1, 0, 1)), u.x),
                   mix(hash13(i + float3(0, 1, 1)), hash13(i + float3(1, 1, 1)), u.x), u.y), u.z);
}
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
float simplexNoise(float2 p) { return simplexNoiseD(p, 0.0).x; }
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
float ridgedFbm(float2 p, int octaves) {
    const float2x2 octaveRotation = float2x2(0.8, 0.6, -0.6, 0.8);
    float sum = 0.0, amp = 0.5, weight = 1.0, norm = 0.0;
    for (int i = 0; i < FBM_MAX_OCTAVES; i++) {
        if (i >= octaves) break;
        float n = 1.0 - abs(gradientNoise(p) * 1.4);
        n *= n;
        sum += amp * n * weight;
        norm += amp;
        weight = clamp(n * 2.0, 0.0, 1.0);
        amp *= 0.5;
        p = 2.01 * (octaveRotation * p) + float2(17.13, -3.71);
    }
    return sum / norm;
}
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
float warpedFbm(float2 p, float strength, int octaves, thread float2 &q, thread float2 &r) {
    q = float2(fbm(p, octaves), fbm(p + float2(3.1, 7.4), octaves));
    r = float2(fbm(p + strength * q + float2(9.7, 2.6), octaves),
             fbm(p + strength * q + float2(6.3, 1.9), octaves));
    return fbm(p + strength * r, octaves);
}
float4 voronoi(float2 p, float jitter) {
    float2 ip = floor(p), fp = fract(p);
    float f1 = 8.0, f2 = 8.0;
    float2 nearest = float2(0.0);
    for (int j = -1; j <= 1; j++)
    for (int i = -1; i <= 1; i++) {
        float2 g = float2(float(i), float(j));
        float2 r = g + jitter * hash22(ip + g) - fp;
        float d = dot(r, r);
        if (d < f1) { f2 = f1; f1 = d; nearest = ip + g; }
        else if (d < f2) { f2 = d; }
    }
    return float4(sqrt(f1), sqrt(f2), nearest);
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
float hybridTerrainHeight(float2 p, int octaves) {
    int count = clamp(octaves, 1, FBM_MAX_OCTAVES);
    float2 warp = float2(fbm(p * 0.35, count), fbm(p * 0.35 + float2(19.1, -7.3), count));
    float2 q = p + 0.8 * warp;
    float broad = 0.5 + 0.5 * fbm(q * 0.45, count);
    float ridges = ridgedFbm(q * 1.7, count);
    float cells = 1.0 - clamp(voronoi(q * 2.5, 0.75).x, 0.0, 1.0);
    return clamp(0.45 * broad + 0.45 * ridges + 0.10 * cells, 0.0, 1.0);
}
float3 cosinePalette(float t, float3 a, float3 b, float3 c, float3 d) {
    return a + b * cos(TAU * (c * t + d));
}
float3 ditherTPDF(float2 fragCoord, int frame) {
    float2 r = hash22(float2(floor(fragCoord) + 7919.0 * float(frame % 1024)));
    return float3((r.x + r.y - 1.0) / 255.0);
}
const float SCALE = 5.0;
const int OCTAVES = 5;
float noiseStudy(int id, float2 p, float px) {
    if (id == 0) return 0.5 + 0.7 * gradientNoise(p);
    if (id == 1) return 1.0 - smoothstep(0.0, 0.13 + px, voronoiBorder(p, 0.85).x);
    if (id == 2) return 0.5 + 0.5 * simplexNoise(p);
    if (id == 3) return 0.5 + 0.5 * fbm(p, OCTAVES);
    if (id == 4) {
        float2 q, r;
        float f = warpedFbm(p * 0.6, 1.5, 3, q, r);
        return 0.5 + 0.5 * sin(p.x * 2.0 + 6.0 * f);
    }
    if (id == 5) return valueNoise(p);
    if (id == 6) {
        float4 cell = voronoi(p, 0.85);
        return saturate(1.8 * (cell.y - cell.x));
    }
    if (id == 7) return ridgedFbm(p, OCTAVES);
    if (id == 8) return billowFbm(p, OCTAVES);
    return hybridTerrainHeight(p, OCTAVES);
}
void shade(thread float4 &fragColor, float2 fragCoord) {
    float2 board = fragCoord / resolution.xy * float2(5.0, 2.0);
    int2 tile = int2(floor(board));
    int id = tile.x + (1 - tile.y) * 5;
    float2 local = fract(board);
    float2 p = local * SCALE + float2(1.23, 4.56);
    float px = SCALE * 5.0 / resolution.x;
    float f = noiseStudy(id, p, px);
    float3 col = float3(saturate(f)); // grayscale values are already display values
#if DEBUG_MODE == 3
    col = cosinePalette(float(id) / 10.0, float3(0.5), float3(0.4), float3(1.0), float3(0.0,0.3,0.6));
#elif DEBUG_MODE == 5
    col = float3(max(f,0.0), max(-f,0.0), max(f-1.0,0.0));
#endif
    float2 edge = min(local,1.0-local);
    float frame = smoothstep(0.01,0.025,min(edge.x,edge.y));
    col = mix(float3(0.035), col, frame);
    // The small white ticks identify columns 1–5 without font/texture dependencies.
    float tick = step(0.965,local.y) * step(0.1,local.x) * step(local.x,0.1+0.03*float(tile.x+1));
    col = mix(col,float3(0.9),tick);
    fragColor = float4(col + ditherTPDF(fragCoord,frame),1.0);
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
