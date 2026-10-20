//! sdf3d: 3D signed distance primitives. Each one is centered at the origin unless noted. Move or rotate the
//! point before calling (sdBox(p - center, size)), never the result.
//! Exactness tags:
//!   @exact  true Euclidean distance inside and outside (safe for smooth blending, AO, soft shadows, offsets)
//!   @bound  never overestimates (Lipschitz <= 1), so raymarching is safe, but offsets and blends are less accurate
//!   @approx exact zero set but may overestimate in places (see the function's note for the safe stepScale)
//! Formulas follow Inigo Quilez's distance-function catalog (https://iquilezles.org/articles/distfunctions/).
//! Implementations here are original and checked by tests/ (sign, Lipschitz bound, eikonal).

/// Sphere of radius r.
/// @exact
/// @use heads, eyes, fruit, planets, bubbles, joints
float sdSphere(float3 p, float r) { return length(p) - r; }

/// Axis-aligned box with half-extents b.
/// @exact
/// @use buildings, crates, bricks, pedestals, furniture
float sdBox(float3 p, float3 b) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

/// Box with rounded edges. The outer size stays b; r is the edge radius (r <= min(b)).
/// @exact
/// @use toys, product shots, soft architecture, dice, phone-like slabs
float sdRoundBox(float3 p, float3 b, float r) {
    float3 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
}

/// Wireframe box: edges of a box with half-extents b and edge thickness e.
/// @exact
/// @use scaffolding, cages, display frames, sci-fi structures
float sdBoxFrame(float3 p, float3 b, float e) {
    p = abs(p) - b;
    float3 q = abs(p + e) - e;
    return min(min(
        length(max(float3(p.x, q.y, q.z), 0.0)) + min(max(p.x, max(q.y, q.z)), 0.0),
        length(max(float3(q.x, p.y, q.z), 0.0)) + min(max(q.x, max(p.y, q.z)), 0.0)),
        length(max(float3(q.x, q.y, p.z), 0.0)) + min(max(q.x, max(q.y, p.z)), 0.0));
}

/// Torus in the XZ plane. t.x = major radius, t.y = tube radius.
/// @exact
/// @use rings, donuts, tires, halos, lifebuoys
float sdTorus(float3 p, float2 t) {
    float2 q = float2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

/// Partial torus (arc) in the XY plane, symmetric about +Y. sc = float2(sin, cos) of the half-aperture angle,
/// ra = major radius, rb = tube radius.
/// @exact
/// @use horns, handles, eyebrows, arches, croissant shapes, magnets
float sdCappedTorus(float3 p, float2 sc, float ra, float rb) {
    p.x = abs(p.x);
    float k = (sc.y * p.x > sc.x * p.y) ? dot(p.xy, sc) : length(p.xy);
    return sqrt(max(dot(p, p) + ra * ra - 2.0 * ra * k, 0.0)) - rb;
}

/// Chain link: a torus stretched along Y by le. r1 = major radius, r2 = tube radius.
/// @exact
/// @use chains, rings, jewelry, fences
float sdLink(float3 p, float le, float r1, float r2) {
    float3 q = float3(p.x, max(abs(p.y) - le, 0.0), p.z);
    return length(float2(length(q.xy) - r1, q.z)) - r2;
}

/// Infinite plane through the origin offset by h along unit normal n: dot(p, n) + h.
/// @exact
/// @use ground, walls, water surface, clipping half-spaces
float sdPlane(float3 p, float3 n, float h) { return dot(p, n) + h; }

/// Capsule: segment a-b swept by radius r.
/// @exact
/// @use limbs, fingers, branches, hair strands, pills, bones
float sdCapsule(float3 p, float3 a, float3 b, float r) {
    float3 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

/// Vertical capsule from y = 0 to y = h, radius r.
/// @exact
/// @use upright limbs, posts, bottles, candles
float sdVerticalCapsule(float3 p, float h, float r) {
    p.y -= clamp(p.y, 0.0, h);
    return length(p) - r;
}

/// Vertical capped cylinder from y = -h to y = +h, radius r.
/// @exact
/// @use columns, cans, coins, logs, wheels (rotate first)
float sdCylinder(float3 p, float h, float r) {
    float2 d = abs(float2(length(p.xz), p.y)) - float2(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

/// Capped cone (frustum) from y = -h (radius r1) to y = +h (radius r2). Set r2 = 0 for a pointed cone.
/// Exact everywhere, including the base cap. Points below the base are outside.
/// @exact
/// @use trees, roofs, spikes, lampshades, volcanoes, party hats, vases
float sdCappedCone(float3 p, float h, float r1, float r2) {
    float2 q = float2(length(p.xz), p.y);
    float2 top = float2(r2, h);
    float2 side = float2(r2 - r1, 2.0 * h);
    float2 toCap = float2(q.x - min(q.x, (q.y < 0.0) ? r1 : r2), abs(q.y) - h);
    float2 toSide = q - top + side * clamp(dot(top - q, side) / dot2(side), 0.0, 1.0);
    float s = (toSide.x < 0.0 && toCap.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot2(toCap), dot2(toSide)));
}

/// Pointed cone with its base disk (radius r) at y = 0 and apex at y = h.
/// @exact
/// @use evergreen trees, spikes, horns, mountains, wizard hats
float sdCone(float3 p, float h, float r) {
    return sdCappedCone(p - float3(0.0, 0.5 * h, 0.0), 0.5 * h, r, 0.0);
}

/// Round cone: sphere r1 at y = 0 smoothly hulled with sphere r2 at y = h.
/// @exact
/// @use limbs, fingers, tree trunks, carrots, teardrops, tentacle segments
float sdRoundCone(float3 p, float r1, float r2, float h) {
    float b = (r1 - r2) / h;
    float a = sqrt(1.0 - b * b);
    float2 q = float2(length(p.xz), p.y);
    float k = dot(q, float2(-b, a));
    if (k < 0.0) return length(q) - r1;
    if (k > a * h) return length(q - float2(0.0, h)) - r2;
    return dot(q, float2(a, b)) - r1;
}

/// Ellipsoid with semi-axes r. A fast approximation: the zero set is exact and the field is a bound outside for
/// aspect ratios up to about 2:1. Inside, and for more stretched ellipsoids, the gradient exceeds 1 (measured: 2.5
/// at 4:1). March with stepScale 0.7-0.8 there, or build long shapes from sdCapsule / sdRoundCone instead.
/// @approx
/// @use heads, bodies, eggs, pebbles, leaves (flat), muscles, clouds of blobs
float sdEllipsoid(float3 p, float3 r) {
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    if (k1 < 1e-8) return -min(r.x, min(r.y, r.z));
    return k0 * (k0 - 1.0) / k1;
}

/// Hollow spherical cap (bowl) of radius r, cut by the plane y = h, with shell thickness t. The opening faces +Y.
/// @exact
/// @use bowls, cups, helmets, shells, satellite dishes, eye sockets
float sdCutHollowSphere(float3 p, float r, float h, float t) {
    float w = sqrt(r * r - h * h);
    float2 q = float2(length(p.xz), p.y);
    return ((h * q.x < w * q.y) ? length(q - float2(w, h)) : abs(length(q) - r)) - t;
}

/// Hexagonal prism along Z. h.x = inradius of the hexagon, h.y = half-length.
/// @exact
/// @use pencils, bolts, crystals, basalt columns, honeycomb cells
float sdHexPrism(float3 p, float2 h) {
    const float3 k = float3(-0.8660254, 0.5, 0.57735027);
    p = abs(p);
    p.xy -= 2.0 * min(dot(k.xy, p.xy), 0.0) * k.xy;
    float2 d = float2(length(p.xy - float2(clamp(p.x, -k.z * h.x, k.z * h.x), h.x)) * sign(p.y - h.x),
                  p.z - h.y);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

/// Regular octahedron with "radius" s (vertex distance from center). Bound version.
/// @bound
/// @use gems, crystals, diamonds, abstract motifs
float sdOctahedron(float3 p, float s) {
    p = abs(p);
    return (p.x + p.y + p.z - s) * 0.57735027;
}

/// Gyroid sheet with cell scale `scale` and half-thickness t. The infinite triply-periodic surface
/// sin x cos y + sin y cos z + sin z cos x = 0. Intersect with a bounding shape.
/// @bound
/// @use lattices, coral, bone interiors, sponges, sci-fi infill, organic architecture
float sdGyroid(float3 p, float scale, float t) {
    p *= scale;
    float g = dot(sin(p), cos(p.yzx));
    return (abs(g) / scale - t) * 0.57735027;
}

/// Sphere of radius r cut by the plane y = h, keeping the cap ABOVE the plane. h = 0 gives a dome on the ground;
/// negative h keeps more than half. Needs |h| < r.
/// @exact
/// @use domes, mushroom caps, half-buried rocks, igloos, bread loaves
float sdCutSphere(float3 p, float r, float h) {
    float w = sqrt(max(r * r - h * h, 0.0));
    float2 q = float2(length(p.xz), p.y);
    float s = max((h - r) * q.x * q.x + w * w * (h + r - 2.0 * q.y), h * q.x - w * q.y);
    return (s < 0.0) ? length(q) - r : (q.x < w) ? h - q.y : length(q - float2(w, h));
}

/// Sphere ra at the origin with sphere rb at (d, 0, 0) carved out, exact including the crease rim.
/// A plain opSubtract of two spheres is only a bound.
/// @exact
/// @use eye sockets, craters, bitten fruit, nostrils, scooped shapes
float sdDeathStar(float3 p, float ra, float rb, float d) {
    float a = (ra * ra - rb * rb + d * d) / (2.0 * d);
    float b = sqrt(max(ra * ra - a * a, 0.0));
    float2 q = float2(p.x, length(p.yz));
    if (q.x * b - q.y * a > d * max(b - q.y, 0.0)) return length(q - float2(a, b));
    return max(length(q) - ra, -(length(q - float2(d, 0.0)) - rb));
}

/// Unsigned distance to a 3D quadratic Bezier curve A-B-C; subtract a radius for a tube.
/// Solves the closest-point cubic analytically. Falls back to a segment when the curve is straight.
/// @exact
/// @use hair strands, tentacles, stems, whiskers, horns, cables, curved tubes
float sdQuadraticBezier(float3 pos, float3 A, float3 B, float3 C) {
    float3 a = B - A;
    float3 b = A - 2.0 * B + C;
    float3 c = a * 2.0;
    float3 d = A - pos;
    float bb = dot(b, b);
    if (bb < 1e-10) {
        float3 pa = pos - A, ca = C - A;
        return length(pa - ca * clamp(dot(pa, ca) / dot(ca, ca), 0.0, 1.0));
    }
    float kk = 1.0 / bb;
    float kx = kk * dot(a, b);
    float ky = kk * (2.0 * dot(a, a) + dot(d, b)) / 3.0;
    float kz = kk * dot(d, a);
    float pp = ky - kx * kx;
    float q = kx * (2.0 * kx * kx - 3.0 * ky) + kz;
    float h = q * q + 4.0 * pp * pp * pp;
    float res;
    if (h >= 0.0) {
        h = sqrt(h);
        float2 x = (float2(h, -h) - q) / 2.0;
        float2 uv = sign(x) * pow(abs(x), float2(1.0 / 3.0));
        float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        res = dot2(d + (c + b * t) * t);
    } else {
        float z = sqrt(-pp);
        float v = acos(clamp(q / (pp * z * 2.0), -1.0, 1.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.7320508;
        float2 t = clamp(float2(m + m, -n - m) * z - kx, 0.0, 1.0);
        res = min(dot2(d + (c + b * t.x) * t.x), dot2(d + (c + b * t.y) * t.y));
    }
    return sqrt(res);
}
