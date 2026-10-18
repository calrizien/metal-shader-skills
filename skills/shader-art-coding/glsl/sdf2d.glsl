//! sdf2d: 2D signed distance primitives for posters, icons, UI, motion graphics, and as profiles for
//! opExtrude / opRevolve. Centered at the origin unless noted. Negative inside.
//! Formulas follow Inigo Quilez's 2D distance catalog (https://iquilezles.org/articles/distfunctions2d/).
//! Implementations are original and tested (sign, Lipschitz, brute-force distance for curves).
//! Tags: @exact true distance, @bound never overestimates, @approx exact zero set but may overestimate in places.

/// Circle of radius r.
/// @exact
/// @use dots, eyes, suns, bubbles, rings (with opOnion)
float sdCircle(vec2 p, float r) { return length(p) - r; }

/// Axis-aligned rectangle with half-extents b.
/// @exact
/// @use panels, bars, windows, buttons, building silhouettes
float sdBox(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

/// Rectangle with half-extents b and per-corner radii r = (top-right, bottom-right, top-left, bottom-left).
/// @exact
/// @use UI cards, buttons, speech bubbles, tags, rounded windows
float sdRoundedBox(vec2 p, vec2 b, vec4 r) {
    r.xy = (p.x > 0.0) ? r.xy : r.zw;
    r.x = (p.y > 0.0) ? r.x : r.y;
    vec2 q = abs(p) - b + r.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
}

/// Unsigned distance to segment a-b. Subtract a width to get a stroke.
/// @exact
/// @use lines, strokes, stems, rays, hands of a clock, rain streaks
float sdSegment(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

/// Tapered capsule: circle r1 at origin hulled with circle r2 at (0, h).
/// @exact
/// @use petals, tails, teardrops, brush dabs, fingers, flames
float sdUnevenCapsule(vec2 p, float r1, float r2, float h) {
    p.x = abs(p.x);
    float b = (r1 - r2) / h;
    float a = sqrt(1.0 - b * b);
    float k = dot(p, vec2(-b, a));
    if (k < 0.0) return length(p) - r1;
    if (k > a * h) return length(p - vec2(0.0, h)) - r2;
    return dot(p, vec2(a, b)) - r1;
}

/// Circular arc symmetric about +Y. sc = vec2(sin, cos) of the half-aperture, ra = radius, rb = stroke half-width.
/// @exact
/// @use smiles, eyebrows, rainbows, gauges, progress rings, horseshoes
float sdArc(vec2 p, vec2 sc, float ra, float rb) {
    p.x = abs(p.x);
    return ((sc.y * p.x > sc.x * p.y) ? length(p - sc * ra) : abs(length(p) - ra)) - rb;
}

/// Equilateral triangle with circumradius-like size r, pointing up.
/// @exact
/// @use play icons, warning signs, mountains, arrows, tri-patterns
float sdEquilateralTriangle(vec2 p, float r) {
    const float k = 1.7320508;
    p.x = abs(p.x) - r;
    p.y = p.y + r / k;
    if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
    p.x -= clamp(p.x, -2.0 * r, 0.0);
    return -length(p) * sign(p.y);
}

/// Arbitrary triangle p0, p1, p2 (any winding).
/// @exact
/// @use shards, low-poly art, arrowheads, beaks, teeth
float sdTriangle(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
    vec2 e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
    vec2 v0 = p - p0, v1 = p - p1, v2 = p - p2;
    vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                     vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                     vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

/// Regular n-gon with circumradius r, one vertex pointing up.
/// @exact
/// @use badges, hexagonal tiles, pentagons, stop signs, gems (2D)
float sdRegularPolygon(vec2 p, float r, int n) {
    float an = PI / float(n);
    vec2 acs = vec2(cos(an), sin(an));
    float len = length(p);
    if (len < 1e-12) return -r * acs.x;
    float bn = mod(atan(p.x, p.y), 2.0 * an) - an;
    p = len * vec2(cos(bn), abs(sin(bn)));
    p -= r * acs;
    p.y += clamp(-p.y, 0.0, r * acs.y);
    return length(p) * sign(p.x);
}

/// Star with n points and outer radius r. m in [2, n] sets the inner angle: m = 2 is the spikiest and m = n is a regular n-gon.
/// @exact
/// @use stars, sparkles, badges, flowers (with opRound), sheriff badges
float sdStar(vec2 p, float r, int n, float m) {
    float an = PI / float(n);
    float en = PI / m;
    vec2 acs = vec2(cos(an), sin(an));
    vec2 ecs = vec2(cos(en), sin(en));
    float len = length(p);
    if (len < 1e-12) return -r * acs.x;
    float bn = mod(atan(p.x, p.y), 2.0 * an) - an;
    p = len * vec2(cos(bn), abs(sin(bn)));
    p -= r * acs;
    p += ecs * clamp(-dot(p, ecs), 0.0, r * acs.y / ecs.y);
    return length(p) * sign(p.x);
}

/// Vesica (lens): intersection of two circles of radius r whose centers sit at (+-d, 0). Points along Y. Needs d < r.
/// @exact
/// @use leaves, petals, eyes, fish bodies, almond shapes, gothic arches
float sdVesica(vec2 p, float r, float d) {
    p = abs(p);
    float b = sqrt(r * r - d * d);
    return ((p.y - b) * d > p.x * b) ? length(p - vec2(0.0, b))
                                     : length(p - vec2(-d, 0.0)) - r;
}

/// Crescent: disk ra at origin minus disk rb at (d, 0).
/// @exact
/// @use moons, claws, bananas (bent), shadows on spheres, logos
float sdMoon(vec2 p, float d, float ra, float rb) {
    p.y = abs(p.y);
    float a = (ra * ra - rb * rb + d * d) / (2.0 * d);
    float b = sqrt(max(ra * ra - a * a, 0.0));
    if (d * (p.x * b - p.y * a) > d * d * max(b - p.y, 0.0)) return length(p - vec2(a, b));
    return max(length(p) - ra, -(length(p - vec2(d, 0.0)) - rb));
}

/// Heart with its bottom tip at the origin, about 1 unit tall.
/// @exact
/// @use hearts, valentines, health icons, leaves (squashed)
float sdHeart(vec2 p) {
    p.x = abs(p.x);
    if (p.y + p.x > 1.0) return sqrt(dot2(p - vec2(0.25, 0.75))) - 0.35355339;
    return sqrt(min(dot2(p - vec2(0.0, 1.0)), dot2(p - 0.5 * max(p.x + p.y, 0.0)))) * sign(p.x - p.y);
}

/// Rhombus with half-diagonals b.
/// @exact
/// @use diamonds, kites, card suits, argyle, harlequin patterns
float sdRhombus(vec2 p, vec2 b) {
    p = abs(p);
    vec2 t = b - 2.0 * p;
    float h = clamp((t.x * b.x - t.y * b.y) / dot(b, b), -1.0, 1.0);
    float d = length(p - 0.5 * b * vec2(1.0 - h, 1.0 + h));
    return d * sign(p.x * b.y + p.y * b.x - b.x * b.y);
}

/// Ellipse with semi-axes r. A fast approximation: exact zero set, a bound outside up to about 2:1 aspect,
/// gradient above 1 inside and for flatter ellipses. Fine for fills and strokes; avoid for exact offsets.
/// @approx
/// @use eyes, pupils, ovals, shadows under objects, planet rings (with opOnion)
float sdEllipse(vec2 p, vec2 r) {
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    if (k1 < 1e-8) return -min(r.x, r.y);
    return k0 * (k0 - 1.0) / k1;
}

/// Unsigned distance to a quadratic Bezier curve A-B-C. Solves the closest-point cubic analytically.
/// Falls back to a segment when the curve degenerates to a line. Float error in the cubic solve is about 1e-4.
/// @exact
/// @use brush strokes, hair, calligraphy, tendrils, eyelashes, smooth paths, font-like curves
float sdQuadraticBezier(vec2 pos, vec2 A, vec2 B, vec2 C) {
    vec2 a = B - A;
    vec2 b = A - 2.0 * B + C;
    vec2 c = a * 2.0;
    vec2 d = A - pos;
    float bb = dot(b, b);
    if (bb < 1e-10) return sdSegment(pos, A, C);
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
        vec2 x = (vec2(h, -h) - q) / 2.0;
        vec2 uv = sign(x) * pow(abs(x), vec2(1.0 / 3.0));
        float t = clamp(uv.x + uv.y - kx, 0.0, 1.0);
        res = dot2(d + (c + b * t) * t);
    } else {
        float z = sqrt(-pp);
        float v = acos(clamp(q / (pp * z * 2.0), -1.0, 1.0)) / 3.0;
        float m = cos(v);
        float n = sin(v) * 1.7320508;
        vec2 t = clamp(vec2(m + m, -n - m) * z - kx, 0.0, 1.0);
        res = min(dot2(d + (c + b * t.x) * t.x), dot2(d + (c + b * t.y) * t.y));
    }
    return sqrt(res);
}
