//! intersect: analytic ray-primitive intersections. Rays are ro + t * rd with unit rd.
//! Use them for bounding volumes (clip the raymarch range to where the scene can be), exact floors and water planes,
//! glass spheres and eyeballs, and cheap reflections.
//! Formulas follow https://iquilezles.org/articles/intersectors/.

/// Ray vs plane dot(p, n) + h = 0 (unit n). Returns t, which is negative when the plane is behind the ray or parallel to it.
/// @use floors, water, mirrors, clipping marches to a ground plane
float iPlane(float3 ro, float3 rd, float3 n, float h) {
    float denom = dot(rd, n);
    if (abs(denom) < 1e-8) return -1.0;
    return -(dot(ro, n) + h) / denom;
}

/// Ray vs sphere centered at c with radius r. Returns float2(tNear, tFar), or float2(-1) on a miss.
/// Uses the precision-friendly form that measures from the closest point on the ray.
/// @use bounding spheres, glass balls, eyeballs, planets, bubbles
float2 iSphere(float3 ro, float3 rd, float3 c, float r) {
    float3 oc = ro - c;
    float b = dot(oc, rd);
    float3 qc = oc - b * rd;
    float h = r * r - dot(qc, qc);
    if (h < 0.0) return float2(-1.0);
    h = sqrt(h);
    return float2(-b - h, -b + h);
}

/// Ray vs axis-aligned box centered at the origin with half-extents b (slab method).
/// Returns float2(tNear, tFar), or float2(-1) on a miss. Works when the ray starts inside (tNear < 0 < tFar).
/// @use bounding boxes for raymarching, glass cubes, rooms
float2 iBox(float3 ro, float3 rd, float3 b) {
    float3 m = 1.0 / rd;
    float3 n = m * ro;
    float3 k = abs(m) * b;
    float3 t1 = -n - k;
    float3 t2 = -n + k;
    float tN = max(max(t1.x, t1.y), t1.z);
    float tF = min(min(t2.x, t2.y), t2.z);
    if (tN > tF || tF < 0.0) return float2(-1.0);
    return float2(tN, tF);
}
