//! raymarch: sphere tracing, normals, shadows and ambient occlusion.
//! Scene contract: float2 map(float3 p) returns distance and material ID.
//! The bundler places helpers and the scene in a thread-local ShaderScene.

float2 map(float3 p);

const int RAYMARCH_MAX_STEPS = 256;

/// Sphere-trace from ro along unit rd between tmin and tmax.
/// Returns float3(t, materialId, stepCount). t is -1 on a miss.
/// The hit threshold grows with t (about one pixel's footprint), so distant surfaces don't burn steps.
/// stepScale is 1 for exact or bound fields. Use < 1 (e.g. 0.6) when map() has Lipschitz > 1 (displacement, warps, twist).
/// @use every SDF raymarcher
/// @see https://iquilezles.org/articles/raymarchingdf/
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

/// Surface normal from 4 tetrahedral samples (cheaper than 6 central differences, and still centered).
/// eps should scale with distance, e.g. 0.0005 * t: that filters distant detail and avoids sparkling.
/// @use shading any SDF hit
/// @see https://iquilezles.org/articles/normalsSDF/
float3 calcNormal(float3 p, float eps) {
    float3 n = float3(0.0);
    for (int i = 0; i < 4; i++) {
        float3 e = 0.5773 * (2.0 * float3((((i + 3) >> 1) & 1), ((i >> 1) & 1), (i & 1)) - 1.0);
        n += e * map(p + e * eps).x;
    }
    return normalize(n);
}

/// Soft shadow toward a light along unit rd. k controls sharpness (k is about 1 / light angular size: 8 soft, 32 hard).
/// Uses the "closest approach between samples" estimate, which removes banding from sharp-cornered occluders.
/// Returns 0 (full shadow) .. 1 (lit).
/// @use sun shadows, contact shadows, penumbrae
/// @see https://iquilezles.org/articles/rmshadows/
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

/// Ambient occlusion from 5 distance samples along the normal. Compares the expected distance with the actual one.
/// scale is the sampling reach in scene units (about 0.12 for a unit-sized object). Returns 0 (occluded) .. 1 (open).
/// @use crevices, contact darkening, grounding objects on floors
/// @see https://iquilezles.org/articles/nvscene2008/rwwtt.pdf
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

/// Thickness behind a surface point, estimated by sampling the SDF inside along -n (an "inverse AO").
/// Returns 0 (thin, light passes through) .. 1 (thick). maxDepth is the deepest sample in scene units.
/// @use translucency, subsurface tint, wax and jade, glowing thin edges
float sdfThickness(float3 p, float3 n, float maxDepth) {
    float acc = 0.0;
    for (int i = 0; i < 4; i++) {
        float h = maxDepth * (float(i) + 1.0) / 4.0;
        acc += clamp(-map(p - n * h).x / h, 0.0, 1.0);
    }
    return acc / 4.0;
}
