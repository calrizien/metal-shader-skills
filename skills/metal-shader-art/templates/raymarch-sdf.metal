// Studio still life: a smooth-blended sculpture on a plinth, with a gold ring.
// Shows: SDF modeling (smooth union whose blend weight also blends color), PBR key light with soft shadows,
// sky fill + bounce with AO, sky reflections, ray-footprint filtering, fog, AgX, supersampling, DEBUG_MODE.
// Paste-ready version: python3 scripts/metal_tools.py bundle templates/raymarch-sdf.metal -o scene.metal
// @render time=1.2

#define DEBUG_MODE 0   // 0 final | 1 distance slice | 2 normals | 3 material ids | 4 steps | 5 shadow/AO/blend | 6 light terms
#define AA 1           // samples per pixel (4-8 for stills)

// ---- art controls ----
const float3  SUN_DIR = normalize(float3(0.7, 0.6, -0.4));
const float3  SUN_COLOR = float3(3.2, 2.8, 2.3);
const float3  SKY_FILL = float3(0.35, 0.45, 0.6);
const float3  GROUND_FILL = float3(0.18, 0.15, 0.12);
const float BLEND = 0.25;        // smooth-union width: larger = softer, fleshier join
const float EXPOSURE = 1.0;
const float FOCAL = 2.2;         // larger = more telephoto

// Material ids: integer part = material, fractional part = blend weight between the two glazes.
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

// footprint = world-space size of one pixel at the hit, used to filter the floor pattern without derivatives.
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
