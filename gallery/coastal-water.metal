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
#define QUALITY 2 // 1 interactive: sky reflection | 2 high: land reflection | 3 still: 4x AA, more waves/steps
#define DEBUG_MODE 0 // 0 beauty | 1 optical path | 2 normals | 3 foam | 4 primary steps | 5 Fresnel | 6 transmission
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
float3 hemisphereLight(float3 n, float3 skyColor, float3 groundColor) {
    return mix(groundColor, skyColor, 0.5 + 0.5 * n.y);
}
float waterDispersion(float k, float depth, float gravity) {
    k = max(k,0.0);
    float e = exp(-2.0*k*max(depth,0.0));
    return sqrt(max(gravity,0.0)*k*(1.0-e)/(1.0+e));
}
float4 waterWaveD(float2 xz, float time, float2 direction, float wavelength, float amplitude, float depth, float footprint) {
    float dl = length(direction);
    float2 dir = dl>0.000001 ? direction/dl : float2(1.0,0.0);
    float lengthM = max(wavelength,0.0001);
    float k = TAU/lengthM;
    float keep = smoothstep(2.0,6.0,lengthM/max(footprint,0.000001));
    float phase = k*dot(dir,xz)-waterDispersion(k,depth,9.81)*time;
    float h = amplitude*keep*sin(phase);
    return float4(h, amplitude*keep*k*cos(phase)*dir, -k*k*h);
}
float fresnelDielectric(float cosIncident, float etaIncident, float etaTransmitted) {
    float ci = clamp(abs(cosIncident),0.0,1.0);
    float ei = max(etaIncident,0.000001), et = max(etaTransmitted,0.000001);
    if (abs(ei-et)<0.0000001) return 0.0;
    float sinT2 = (ei*ei)/(et*et)*max(0.0,1.0-ci*ci);
    if (sinT2>=1.0) return 1.0;
    float ct = sqrt(max(0.0,1.0-sinT2));
    float rs = (ei*ci-et*ct)/max(ei*ci+et*ct,0.000001);
    float rp = (et*ci-ei*ct)/max(et*ci+ei*ct,0.000001);
    return clamp(0.5*(rs*rs+rp*rp),0.0,1.0);
}
float3 beerTransmittance(float3 extinction, float pathLength) {
    return exp(-max(extinction,float3(0.0))*max(pathLength,0.0));
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
float3 sunDisk(float3 rd, float3 sunDir, float angularRadius, float pixelAngle) {
    float ang = acos(clamp(dot(rd, sunDir), -1.0, 1.0));
    float edge = 1.0 - smoothstep(angularRadius - pixelAngle, angularRadius + pixelAngle, ang);
    float r = clamp(ang / angularRadius, 0.0, 1.0);
    float muLimb = sqrt(max(1.0 - r * r, 0.0));
    float3 limb = pow(float3(muLimb), float3(0.397, 0.503, 0.652));
    return edge * limb;
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
const int WATER_AA=QUALITY==3?4:1;
const int WATER_WAVES=QUALITY==3?12:8;
const int WATER_STEPS=QUALITY==3?240:180;
const float3 COAST_SUN=normalize(float3(-0.35,0.62,-0.55));
const float3 EXTINCTION=float3(0.42,0.085,0.045);
const float WATER_IOR=1.333;
const float WATER_FAR=95.0;
float coastBed(float2 p) {
    float2 a=p-float2(-7.0,-8.0),b=p-float2(7.0,-19.0),c=p-float2(-5.0,-1.0);
    float islands=5.7*exp(-0.055*dot(a,a))+5.0*exp(-0.07*dot(b,b))+1.1*exp(-0.15*dot(c,c));
    return -2.4+islands*(1.0+0.18*gradientNoise(p*0.75))+0.12*sin(p.x*1.7)*sin(p.y*1.2);
}
float3 coastBedNormal(float2 p,float eps) {
    float2 d=float2(coastBed(p+float2(eps,0.0))-coastBed(p-float2(eps,0.0)),
                coastBed(p+float2(0.0,eps))-coastBed(p-float2(0.0,eps)))/(2.0*eps);
    return normalize(float3(-d.x,1.0,-d.y));
}
float4 coastWaves(float2 p,float footprint) {
    float4 sum=float4(0.0);
    for(int i=0;i<WATER_WAVES;i++) {
        float fi=float(i);
        float angle=0.7+fi*2.39996;
        float wavelength=4.5*pow(0.69,fi);
        float amp=0.075*pow(0.58,fi);
        // Fixed reference depth in phase avoids spatially varying frequency drifting out of phase along the shore.
        sum+=waterWaveD(p+float2(fi*1.37,fi*0.79),time,float2(cos(angle),sin(angle)),wavelength,amp,3.0,footprint);
    }
    return sum;
}
float2 traceCoast(float3 ro,float3 rd,bool includeWater,int maxSteps) {
    float t=0.01,previous=0.0;
    float closing=max(0.05,abs(rd.y)+4.0*length(rd.xz));
    for(int i=0;i<WATER_STEPS;i++) {
        if(i>=maxSteps)break;
        float3 p=ro+rd*t;
        float h=coastBed(p.xz);
        if(includeWater) {
            float geometryFootprint=2.0*t/(resolution.y*1.75*max(abs(rd.y),0.1));
            h=max(h,coastWaves(p.xz,geometryFootprint).x);
        }
        float gap=p.y-h;
        if(gap<0.0) {
            float lo=previous,hi=t;
            for(int j=0;j<10;j++) {
                float mid=0.5*(lo+hi);
                float3 q=ro+rd*mid;
                float surface=coastBed(q.xz);
                if(includeWater) {
                    float fp=2.0*mid/(resolution.y*1.75*max(abs(rd.y),0.1));
                    surface=max(surface,coastWaves(q.xz,fp).x);
                }
                if(q.y>surface)lo=mid;else hi=mid;
            }
            return float2(0.5*(lo+hi),float(i));
        }
        previous=t;
        t+=max(gap/closing,0.012+0.008*t);
        if(t>WATER_FAR)break;
    }
    if(includeWater && rd.y < -0.0001) return float2(max(0.01,-ro.y/rd.y),float(maxSteps));
    return float2(-1.0,float(maxSteps));
}
float3 coastSky(float3 rd) {
    float3 c=mix(float3(0.22,0.40,0.60),float3(0.025,0.13,0.36),sqrt(max(rd.y,0.0)));
    float clouds=smoothstep(0.1,0.55,fbm(rd.xz/max(rd.y+0.4,0.15)*1.3,4));
    c=mix(c,float3(0.95,0.97,1.0),clouds*0.18*smoothstep(0.03,0.3,rd.y));
    return c+float3(9.0,8.0,6.0)*sunDisk(rd,COAST_SUN,0.012,0.002);
}
float3 shadeCoastBed(float3 p,float3 n,bool submerged,float footprint) {
    float grain=0.5+0.5*fbm(p.xz*2.5,4)*(1.0-smoothstep(0.03,0.25,footprint));
    float rock=smoothstep(0.45,1.0,p.y)*(1.0-smoothstep(0.65,0.9,n.y));
    float3 sand=mix(float3(0.38,0.29,0.15),float3(0.7,0.59,0.37),grain);
    float3 albedo=mix(sand,float3(0.17,0.15,0.12),rock);
    float vegetation=smoothstep(1.2,2.0,p.y)*smoothstep(0.5,0.82,n.y);
    albedo=mix(albedo,float3(0.07,0.12,0.025),vegetation);
    float3 direct=float3(2.5,2.3,1.9)*max(dot(n,COAST_SUN),0.0);
    if(submerged) {
        direct*=beerTransmittance(EXTINCTION,max(-p.y,0.0)/COAST_SUN.y);
        float caustic=pow(max(0.0,sin(p.x*7.0+sin(p.z*4.0+time)*1.3)*sin(p.z*6.0+cos(p.x*4.0-time)*1.2)),9.0);
        float keep=1.0-smoothstep(0.02,0.12,footprint);
        direct*=1.0+caustic*keep*1.2; // projected artistic caustic pattern, not photon transport
    }
    return albedo*(direct+hemisphereLight(n,float3(0.35,0.43,0.5),float3(0.12,0.10,0.07)));
}
float3 renderCoast(float2 coord) {
    float2 uv=(2.0*coord-resolution.xy)/resolution.y;
    float3 ro=float3(0.0,3.5,7.5);
    float3 rd=cameraRay(cameraMatrix(ro,float3(-0.8,-0.1,-6.0),0.0),uv,1.75);
    float3 sky=coastSky(rd);
    float2 hit=traceCoast(ro,rd,true,WATER_STEPS);
#if DEBUG_MODE == 4
    return debugHeat(hit.y/float(WATER_STEPS));
#endif
    if(hit.x<0.0)return sky;
    float3 p=ro+rd*hit.x;
    float footprint=2.0*hit.x/(resolution.y*1.75);
    float bed=coastBed(p.xz);
    float3 col;
    if(bed>p.y-0.015) {
        float3 n=coastBedNormal(p.xz,max(footprint,0.003));
        col=shadeCoastBed(p,n,false,footprint);
    } else {
        float4 waves=coastWaves(p.xz,footprint/max(abs(rd.y),0.1));
        float3 n=normalize(float3(-waves.y,1.0,-waves.z));
        float3 v=-rd;
        float F=fresnelDielectric(max(dot(n,v),0.0),1.0,WATER_IOR);
        float3 refracted=refract(rd,n,1.0/WATER_IOR);
        float2 bottomHit=traceCoast(p-n*0.006,refracted,false,WATER_STEPS);
        float path=bottomHit.x>0.0?bottomHit.x:30.0;
        float3 bottomPoint=p-n*0.006+refracted*path;
        float3 bottomColor=shadeCoastBed(bottomPoint,coastBedNormal(bottomPoint.xz,0.01),true,footprint);
        float3 T=beerTransmittance(EXTINCTION,path);
        float3 body=bottomColor*T+float3(0.012,0.19,0.24)*(1.0-T); // approximate in-scattered body light
        float3 reflected=reflect(rd,n);
        float3 reflection=coastSky(normalize(float3(reflected.x,max(reflected.y,0.01),reflected.z)));
#if QUALITY >= 2
        float2 reflectedHit=traceCoast(p+n*0.015,reflected,false,WATER_STEPS);
        if(reflectedHit.x>0.0) {
            float3 rp=p+n*0.015+reflected*reflectedHit.x;
            if(rp.y>0.02)reflection=shadeCoastBed(rp,coastBedNormal(rp.xz,0.015),false,footprint);
        }
#endif
        float unresolved=smoothstep(0.02,0.18,footprint);
        float rough=mix(0.075,0.20,unresolved);
        float3 glint=specularGGX(n,v,COAST_SUN,rough,float3(0.02037))*float3(3.5,3.2,2.7);
        float shallow=1.0-smoothstep(0.08,0.5,max(p.y-bed,0.0));
        float shorePulse=0.5+0.5*sin((p.y-bed)*19.0-time*1.5+fbm(p.xz*2.0,3)*3.0);
        float foam=shallow*smoothstep(0.25,0.7,shorePulse)*0.8;
        foam+=0.12*smoothstep(0.18,0.6,-waves.w)*(1.0-unresolved);
        foam=clamp(foam,0.0,1.0);
        col=mix(body*(1.0-F)+reflection*F+glint,float3(0.8,0.84,0.82),foam);
#if DEBUG_MODE == 1
        return float3(path/12.0);
#elif DEBUG_MODE == 2
        return n*0.5+0.5;
#elif DEBUG_MODE == 3
        return float3(foam);
#elif DEBUG_MODE == 5
        return float3(F);
#elif DEBUG_MODE == 6
        return T;
#endif
    }
    return mix(col,coastSky(normalize(float3(rd.x,0.025,rd.z))),1.0-exp(-hit.x*0.003));
}
void shade(thread float4 &fragColor,float2 fragCoord) {
    float3 col=float3(0.0);
    for(int i=0;i<WATER_AA;i++) {
        float3 c=renderCoast(fragCoord+(WATER_AA>1?aaOffset(i):float2(0.0)));
#if DEBUG_MODE == 0
        c=tonemapAgX(c*1.05);
#endif
        col+=c/float(WATER_AA);
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
