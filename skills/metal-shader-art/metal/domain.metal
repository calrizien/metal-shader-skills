//! domain: transform the point BEFORE evaluating a distance (repetition, mirroring, polar sectors, folds,
//! twist, bend). Rigid transforms (repeat, mirror, rotate, fold) keep distances exact. Twist and bend
//! stretch space, so their results are only bounds after scaling (see each function).
//! Repetition uses floor(x + 0.5) for a fixed tie rule and stable signed cell IDs.

/// Cell index for repetition with period s (integer-valued; use with hash functions).
/// @use per-instance variation: hash12(domRepeatId(p.xz, s))
float domRepeatId(float p, float s) { return floor(p / s + 0.5); }
float2 domRepeatId(float2 p, float2 s) { return floor(p / s + 0.5); }
float3 domRepeatId(float3 p, float3 s) { return floor(p / s + 0.5); }

/// Infinite repetition with period s. Returns the local coordinate centered in its cell.
/// Exact only while each instance stays inside its own cell. For instances that vary per cell or
/// overhang, evaluate the 2 or 3 neighboring cells too (see references/sdf-library-guide.md).
/// @use forests, columns, tiles, crowds, star fields, city blocks
float domRepeat(float p, float s) { return p - s * floor(p / s + 0.5); }
float2 domRepeat(float2 p, float2 s) { return p - s * floor(p / s + 0.5); }
float3 domRepeat(float3 p, float3 s) { return p - s * floor(p / s + 0.5); }

/// Repetition limited to cells -lim..+lim on each axis (2*lim + 1 copies).
/// @use rows of windows, fence posts, a finite grid of buttons, colonnades
float2 domRepeatLimited(float2 p, float2 s, float2 lim) { return p - s * clamp(floor(p / s + 0.5), -lim, lim); }
float3 domRepeatLimited(float3 p, float3 s, float3 lim) { return p - s * clamp(floor(p / s + 0.5), -lim, lim); }

/// Mirrored repetition: every other cell is flipped, so shapes touching the cell border join seamlessly.
/// @use tiled ornaments, symmetric wallpaper, seamless pipes and rails
float2 domRepeatMirror(float2 p, float2 s) {
    float2 cell = floor(p / s + 0.5);
    float2 local = p - s * cell;
    return local * (1.0 - 2.0 * floorMod(cell, 2.0));
}

/// Polar repetition into n sectors around the origin. Returns the point rotated into the sector centered on +X.
/// Single evaluation: exact for shapes symmetric about their sector's center line. For asymmetric or per-sector-varying
/// shapes, evaluate this sector and its neighbor and take the min (see references/sdf-library-guide.md).
/// @use petals, spokes, gears, clock marks, radial ornaments, columns around a tower
float2 domPolar(float2 p, float n) {
    if (dot(p, p) < 1e-20) return p;
    float sector = TAU / n;
    float id = floor(atan2(p.y, p.x) / sector + 0.5);
    return rot2(-id * sector) * p;
}

/// Sector index in [0, n) for domPolar.
/// @use varying each petal, spoke or column
float domPolarId(float2 p, float n) {
    if (dot(p, p) < 1e-20) return 0.0;
    float sector = TAU / n;
    return floorMod(floor(atan2(p.y, p.x) / sector + 0.5), n);
}

/// Neighbor-checked polar repetition: ids (in [0, n)) of the sector holding p and of the adjacent sector p leans
/// toward. Evaluate the shape in both with domPolarSector and take the min. Use it when sectors vary (per-id length,
/// tilt, color) or are asymmetric. It covers shapes of similar size that stay inside their own sector; a shape that
/// reaches across its neighbor needs a wider search.
/// @use varied petals, tilted fan blades, gear teeth of mixed sizes, uneven clock marks, radial crowds
float2 domPolarPair(float2 p, float n) {
    if (dot(p, p) < 1e-20) return float2(0.0, 1.0);
    float sector = TAU / n;
    float a = atan2(p.y, p.x) / sector;
    float id = floor(a + 0.5);
    return floorMod(float2(id, id + ((a >= id) ? 1.0 : -1.0)), n);
}

/// Rotate p into the frame of polar sector id (its center line on +X). domPolarSector(p, domPolarId(p, n), n)
/// equals domPolar(p, n).
/// @use the second half of domPolarPair: evaluate a sector's shape by id
float2 domPolarSector(float2 p, float id, float n) { return rot2(-id * TAU / n) * p; }

/// Fold space across the plane through the origin with unit normal n. Points behind the plane are reflected.
/// @use kaleidoscopes, symmetric creatures, KIFS fractals, mirrored architecture
float3 domFold(float3 p, float3 n) { return p - 2.0 * min(dot(p, n), 0.0) * n; }

/// Twist around Y: rotate XZ by k * y. Divide the resulting distance by L = a/2 + sqrt(1 + a*a/4), a = k * R,
/// where R is the shape's max distance from the Y axis. Without that, the march overshoots.
/// @use twisted columns, drills, licorice, DNA-like spirals, towels
float3 domTwist(float3 p, float k) {
    float2 xz = rot2(k * p.y) * p.xz;
    return float3(xz.x, p.y, xz.y);
}

/// Bend in XY: rotate XY by k * x. Divide the resulting distance by about 1 + k * R (R = max |p.xy| of the shape).
/// @use bent beams, arches from boxes, bananas, curved horns
float3 domBend(float3 p, float k) {
    float2 xy = rot2(k * p.x) * p.xy;
    return float3(xy, p.z);
}
