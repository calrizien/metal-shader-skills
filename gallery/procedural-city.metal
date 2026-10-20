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
#define DEBUG_MODE 0 // 0 beauty | 2 normals | 3 parcel IDs | 4 steps | 5 window mask
const float PI  = 3.14159265358979;
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
float3 hash32(float2 p) {
    int2 q = int2(floor(p));
    return uintToUnit(pcg3d(uint3(q.x, q.y, 0x9E37u)));
}
float filteredStripes(float x, float w) {
    w = max(w, 1e-4);
    float a = x + 0.5 * w, b = x - 0.5 * w;
    float ia = floor(a) * 0.5 + max(fract(a) - 0.5, 0.0);
    float ib = floor(b) * 0.5 + max(fract(b) - 0.5, 0.0);
    return (ia - ib) / w;
}
float sdBox(float3 p, float3 b) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}
float sdRoundBox(float3 p, float3 b, float r) {
    float3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}
float sdCapsule(float3 p, float3 a, float3 b, float r) {
    float3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}
float sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
float domRepeatId(float p, float s) { return floor(p / s + 0.5); }
float2 domRepeatId(float2 p, float2 s) { return floor(p / s + 0.5); }
float3 domRepeatId(float3 p, float3 s) { return floor(p / s + 0.5); }
float domRepeat(float p, float s) { return p - s * floor(p / s + 0.5); }
float2 domRepeat(float2 p, float2 s) { return p - s * floor(p / s + 0.5); }
float3 domRepeat(float3 p, float3 s) { return p - s * floor(p / s + 0.5); }
float4 buildingProfile(float2 parcel, float2 heightRange, float2 halfWidthRange) {
    float3 h = hash32(parcel);
    return float4(mix(heightRange.x,heightRange.y,h.x*h.x),
                mix(halfWidthRange.x,halfWidthRange.y,h.y),
                mix(halfWidthRange.x,halfWidthRange.y,h.z),
                floor(3.0*hash12(parcel+float2(83.0,19.0))));
}
float facadeWindowMask(float2 uv, float2 fill, float2 footprint) {
    fill = clamp(fill,0.0,1.0);
    float2 w = max(footprint,float2(0.0001));
    float2 a = uv + 0.5*fill + 0.5*w;
    float2 b = uv + 0.5*fill - 0.5*w;
    float2 ia = floor(a)*fill + min(fract(a),fill);
    float2 ib = floor(b)*fill + min(fract(b),fill);
    float2 coverage = clamp((ia-ib)/w,0.0,1.0);
    return coverage.x*coverage.y;
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
float3 hemisphereLight(float3 n, float3 skyColor, float3 groundColor) {
    return mix(groundColor, skyColor, 0.5 + 0.5 * n.y);
}
float3 linearToSrgb(float3 c) {
    c = max(c, 0.0);
    return mix(c * 12.92, 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055, step(0.0031308, c));
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
float heightFog(float3 ro, float3 rd, float t, float a, float b) {
    float base = a * exp(-ro.y * b);
    float amount = (abs(rd.y) < 1e-4) ? base * t
                                       : base * (1.0 - exp(-t * rd.y * b)) / (rd.y * b);
    return 1.0 - exp(-max(amount, 0.0));
}
float2 aaOffset(int i) {
    return fract(0.5 + float(i) * float2(0.7548776662, 0.5698402910)) - 0.5;
}
float3 ditherTPDF(float2 fragCoord, int frame) {
    float2 r = hash22(float2(floor(fragCoord) + 7919.0 * float(frame % 1024)));
    return float3((r.x + r.y - 1.0) / 255.0);
}
float3 debugHeat(float t) {
    t = clamp(t, 0.0, 1.0);
    return clamp(float3(1.5 * t, 1.6 * t * t * t - 0.1, 0.9 * sin(PI * t) + 0.2 * t * t), 0.0, 1.0);
}
const float PARCEL = 3.6;
const float3 CITY_SUN = normalize(float3(-0.6,0.6,0.4));
const int AA = 1;
float4 cityProfile(float2 id) {
    float4 b = buildingProfile(id,float2(2.8,13.0),float2(0.75,1.13));
    if (length(id)<0.5) b=float4(18.0,1.15,1.15,2.0);
    return b;
}
float2 map(float3 p) {
    float2 id=domRepeatId(p.xz,float2(PARCEL));
    float2 local=p.xz-id*PARCEL;
    float2 res=float2(p.y,0.0);
    for(int z=-1;z<=1;z++) for(int x=-1;x<=1;x++) {
        float2 cell=id+float2(float(x),float(z));
        float4 b=cityProfile(cell);
        float3 q=p-float3(cell.x*PARCEL,0.0,cell.y*PARCEL);
        float body=sdRoundBox(q-float3(0.0,b.x*0.38,0.0),float3(b.y,b.x*0.38,b.z)-0.035,0.035);
        float upper=sdRoundBox(q-float3(0.0,b.x*0.83,0.0),float3(b.y*0.72,b.x*0.17,b.z*0.72)-0.025,0.025);
        float podium=sdBox(q-float3(0.0,0.35,0.0),float3(b.y+0.15,0.35,b.z+0.15));
        float d=min(podium,min(body,upper));
        if(b.w>0.5) d=min(d,sdBox(q-float3(0.0,b.x+0.22,0.0),float3(b.y*0.45,0.22,b.z*0.5)));
        if(b.w>1.5) d=min(d,sdCapsule(q,float3(0.0,b.x,0.0),float3(0.0,b.x+1.1,0.0),0.035));
        if(d<res.x)res=float2(d,1.0);
    }
    float unvisited=min(1.5*PARCEL-abs(local.x),1.5*PARCEL-abs(local.y));
    res.x=min(res.x,unvisited);
    return res;
}
float3 citySky(float3 rd) {
    float h=smoothstep(-0.12,0.7,rd.y);
    float3 c=mix(float3(0.10,0.12,0.19),float3(0.012,0.028,0.07),h);
    c+=float3(0.12,0.055,0.025)*pow(max(dot(rd,CITY_SUN),0.0),12.0);
    return c;
}
float3 renderCity(float2 coord) {
    float2 uv=(2.0*coord-resolution.xy)/resolution.y;
    float orbit=0.5+0.035*time;
    float3 ro=float3(32.0*sin(orbit),17.0,32.0*cos(orbit));
    float3 rd=cameraRay(cameraMatrix(ro,float3(0.0,6.0,0.0),0.0),uv,1.85);
    float3 sky=citySky(rd);
    float3 hit=raymarch(ro,rd,0.05,110.0,0.95);
#if DEBUG_MODE == 4
    return debugHeat(hit.z/256.0);
#endif
    if(hit.x<0.0)return sky;
    float3 p=ro+rd*hit.x;
    float3 n=calcNormal(p,max(0.001,hit.x*0.00015));
    float2 id=domRepeatId(p.xz,float2(PARCEL));
    float4 b=cityProfile(id);
    float variation=hash12(id);
    float fp=2.0*hit.x/(resolution.y*1.85);
    fp/=max(abs(dot(n,rd)),0.15);
    float3 albedo=mix(float3(0.16,0.19,0.21),float3(0.32,0.29,0.25),variation);
    float windows=0.0;
    float3 emission=float3(0.0);
    if(hit.y>0.5 && n.y<0.6) {
        float2 facade=float2(abs(n.x)>abs(n.z)?p.z:p.x,p.y);
        float2 grid=facade/float2(0.30,0.43);
        windows=facadeWindowMask(grid,float2(0.62,0.65),float2(fp*3.8,fp*2.5));
        float occupied=step(0.42,hash13(float3(floor(grid+0.5),variation*100.0)));
        float keep=1.0-smoothstep(0.3,1.2,fp/0.30);
        occupied=mix(0.58,occupied,keep);
        float3 glass=float3(0.018,0.035,0.055)+citySky(reflect(rd,n))*0.3;
        albedo=mix(albedo,glass,windows);
        emission=windows*occupied*mix(float3(0.6,0.22,0.055),float3(1.2,0.74,0.33),variation)*0.8;
    } else if(hit.y<0.5) {
        albedo=float3(0.045,0.05,0.06);
        float2 streets=abs(domRepeat(p.xz,float2(PARCEL)));
        float marking=(1.0-smoothstep(0.025,0.025+fp,abs(streets.x-PARCEL*0.5)))
                     *filteredStripes(p.z*1.3,fp*1.3);
        albedo=mix(albedo,float3(0.42,0.32,0.13),marking);
    }
    float ao=calcAO(p,n,0.18);
    float shadow=softShadow(p+n*0.015,CITY_SUN,0.02,20.0,10.0);
    float3 col=shadePBR(n,-rd,CITY_SUN,albedo,0.4,0.15)*float3(0.9,0.75,0.6)*shadow;
    col+=albedo*hemisphereLight(n,float3(0.30,0.43,0.66),float3(0.07,0.065,0.055))*ao;
    col+=emission;
#if DEBUG_MODE == 2
    return n*0.5+0.5;
#elif DEBUG_MODE == 3
    return hash33(float3(id,0.0));
#elif DEBUG_MODE == 5
    return float3(windows);
#endif
    float haze=heightFog(ro,rd,hit.x,0.006,0.055);
    return mix(col,citySky(normalize(float3(rd.x,0.06,rd.z))),haze);
}
void shade(thread float4 &fragColor,float2 fragCoord) {
    float3 col=float3(0.0);
    for(int i=0;i<AA;i++) {
        float3 sampleColor=renderCity(fragCoord+(AA>1?aaOffset(i):float2(0.0)));
#if DEBUG_MODE == 0
        sampleColor=tonemapAgX(sampleColor*1.05);
#endif
        col+=sampleColor/float(AA);
    }
#if DEBUG_MODE == 0
    col=linearToSrgb(col)+ditherTPDF(fragCoord,frame);
#endif
    fragColor=float4(col,1.0);
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
