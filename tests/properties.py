"""Numerical property tests for the GLSL library, run on the GPU by the WebGL harness.

Each test becomes a fragment shader. Every pixel draws random inputs a, b (uniform in [0,1)^4) and runs
`int runTest(vec4 a, vec4 b)`, which returns failure bits. The harness counts failures per bit over a
128x128 grid and compares the rate with the test's allowance (default 0).

SDF tests are generated from compact specs. Bits:
  1  Lipschitz: |f(p) - f(q)| <= |p - q|. Every SDF in the library must satisfy this (safe to march).
  2  Exactness: projecting p onto the surface along the gradient lands on the zero set. Only @exact SDFs.
     Points on the medial axis legitimately fail, so a small rate is allowed.
  4  Sign: listed inside points are negative and outside points are positive.
  8  Brute force: matches a dense sampling of the curve (curves only).
"""

SDF3 = [
    # name, expression of p, domain half-size, inside points, outside points[, {"allow": {bit: rate}}]
    ("sdSphere", "sdSphere(p, 0.7)", 1.5, ["0,0,0", "0.5,0,0"], ["0.8,0,0", "1,1,1"]),
    ("sdBox", "sdBox(p, vec3(0.6, 0.3, 0.4))", 1.5, ["0,0,0", "0.55,0.25,0.35"], ["0.65,0,0", "0,0.35,0"]),
    ("sdRoundBox", "sdRoundBox(p, vec3(0.6, 0.4, 0.5), 0.1)", 1.5, ["0,0,0"], ["0.59,0.39,0.49", "0.7,0,0"]),
    ("sdBoxFrame", "sdBoxFrame(p, vec3(0.6, 0.5, 0.4), 0.05)", 1.5, ["0.58,0.48,0", "0.58,0,0.38"], ["0,0,0", "0.6,0,0"]),
    ("sdTorus", "sdTorus(p, vec2(0.6, 0.2))", 1.5, ["0.6,0,0", "0,0.1,0.6"], ["0,0,0", "0.6,0.25,0"]),
    ("sdCappedTorus", "sdCappedTorus(p, vec2(sin(1.2), cos(1.2)), 0.6, 0.15)", 1.5, ["0,0.6,0", "0.5,0.3,0"], ["0,-0.6,0", "0,0,0"]),
    ("sdLink", "sdLink(p, 0.3, 0.4, 0.1)", 1.5, ["0.4,0,0", "0,0.7,0"], ["0,0,0", "0.4,0,0.15"]),
    ("sdPlane", "sdPlane(p, normalize(vec3(0.3, 1.0, 0.2)), 0.2)", 1.5, ["0,-0.5,0"], ["0,0.5,0"]),
    ("sdCapsule", "sdCapsule(p, vec3(-0.5, -0.2, 0.1), vec3(0.4, 0.5, -0.2), 0.2)", 1.5, ["0,0.15,0", "-0.5,-0.2,0.1"], ["0,-0.5,0", "0.6,0.7,-0.2"]),
    ("sdVerticalCapsule", "sdVerticalCapsule(p, 0.8, 0.25)", 1.5, ["0,0.4,0", "0,-0.2,0"], ["0,1.1,0", "0.3,0.4,0"]),
    ("sdCylinder", "sdCylinder(p, 0.5, 0.4)", 1.5, ["0,0,0", "0.35,0.45,0"], ["0,0.55,0", "0.45,0,0"]),
    ("sdCappedCone", "sdCappedCone(p, 0.6, 0.6, 0.2)", 1.5, ["0,0,0", "0.5,-0.55,0", "0.15,0.55,0"], ["0,-0.65,0", "0,-1.2,0", "0.35,0.55,0", "0,0.65,0"]),
    ("sdCone", "sdCone(p, 1.2, 0.4)", 1.5, ["0,0.1,0", "0.3,0.05,0", "0,1.1,0"], ["0,-0.05,0", "0,-1.4,0", "0.1,-0.5,0", "0.35,0.5,0", "0,1.25,0"]),
    ("sdCone flat", "sdCone(p, 0.3, 1.2)", 1.5, ["0,0.1,0", "1.0,0.02,0"], ["0,-0.05,0", "0,0.35,0", "1.0,0.2,0"]),
    ("sdRoundCone", "sdRoundCone(p, 0.4, 0.15, 0.8)", 1.5, ["0,0,0", "0,0.8,0"], ["0,-0.45,0", "0,1.0,0", "0.4,0.4,0"]),
    ("sdEllipsoid", "sdEllipsoid(p, vec3(0.7, 0.35, 0.5))", 1.5, ["0,0,0", "0.6,0,0"], ["0.75,0,0", "0,0.4,0"]),
    ("sdCutHollowSphere", "sdCutHollowSphere(p, 0.6, 0.2, 0.05)", 1.5, ["0,-0.6,0", "0.6,0,0"], ["0,0,0", "0,0.6,0"]),
    ("sdHexPrism", "sdHexPrism(p, vec2(0.5, 0.3))", 1.5, ["0,0,0", "0,0.45,0.25"], ["0,0.55,0", "0,0,0.35"]),
    ("sdOctahedron", "sdOctahedron(p, 0.7)", 1.5, ["0,0,0", "0.6,0,0"], ["0.75,0,0", "0.3,0.3,0.3"]),
    ("sdGyroid", "sdGyroid(p, 6.0, 0.03)", 1.5, [], []),
    ("sdCutSphere", "sdCutSphere(p, 0.6, 0.2)", 1.5, ["0,0.4,0", "0.3,0.25,0"], ["0,0,0", "0,0.65,0", "0,-0.5,0"]),
    ("sdDeathStar", "sdDeathStar(p, 0.6, 0.45, 0.55)", 1.5, ["-0.4,0,0"], ["0.4,0,0", "0,0,0.7"]),
    ("sdQuadraticBezier 3D", "sdQuadraticBezier(p, vec3(-0.6, -0.3, 0.1), vec3(0.0, 0.9, -0.3), vec3(0.6, -0.2, 0.2)) - 0.1", 1.5, ["-0.6,-0.3,0.1"], ["0,-0.8,0"]),
    # operators and domain transforms on top of exact primitives
    ("smin", "smin(sdSphere(p - vec3(0.3, 0, 0), 0.4), sdBox(p + vec3(0.3, 0, 0), vec3(0.3)), 0.2)", 1.5, ["0,0,0"], ["0,0.6,0"]),
    ("sminCubic", "sminCubic(sdSphere(p - vec3(0.3, 0, 0), 0.4), sdSphere(p + vec3(0.3, 0, 0), 0.4), 0.2)", 1.5, ["0,0,0"], ["0,0.6,0"]),
    ("smoothSubtract", "smoothSubtract(sdBox(p, vec3(0.5)), sdSphere(p - vec3(0.5), 0.4), 0.1)", 1.5, ["-0.3,-0.3,-0.3"], ["0.45,0.45,0.45"]),
    ("opChamferUnion", "opChamferUnion(sdBox(p, vec3(0.5, 0.2, 0.5)), sdBox(p, vec3(0.2, 0.6, 0.2)), 0.1)", 1.5, ["0,0,0"], ["0.4,0.4,0"]),
    ("opStairsUnion", "opStairsUnion(sdBox(p, vec3(0.6, 0.1, 0.6)), sdBox(p, vec3(0.15, 0.6, 0.15)), 0.3, 4.0)", 1.5, ["0,0,0"], ["0.5,0.5,0"]),
    ("opEngrave", "opEngrave(sdBox(p, vec3(0.5)), sdPlane(p, vec3(1, 0, 0), 0.0), 0.05)", 1.5, ["0.3,0,0"], ["0,0,0.52", "0.6,0,0"]),
    ("opOnion", "opOnion(sdSphere(p, 0.6), 0.05)", 1.5, ["0.6,0,0"], ["0,0,0"]),
    ("opExtrude", "opExtrude(p, sdStar(p.xy, 0.6, 5, 2.5), 0.2)", 1.5, ["0,0,0"], ["0,0,0.3"]),
    ("opRevolve", "sdBox(opRevolve(p, 0.5), vec2(0.15, 0.3))", 1.5, ["0.5,0,0"], ["0,0,0", "0.5,0.35,0"]),
    ("opElongate", "sdSphere(opElongate(p, vec3(0.4, 0.0, 0.1)).xyz, 0.3) + opElongate(p, vec3(0.4, 0.0, 0.1)).w", 1.5, ["0,0,0", "0.6,0,0"], ["0.75,0,0", "0,0.35,0"]),
    ("domRepeat", "sdSphere(vec3(domRepeat(p.xz, vec2(0.5)), p.y).xzy, 0.15)", 1.5, ["0.5,0,0.5"], ["0.25,0,0.25"]),
    ("domPolar", "sdBox(vec3(domPolar(p.xz, 7.0) - vec2(0.6, 0.0), p.y).xzy, vec3(0.1, 0.3, 0.05))", 1.5, ["0.6,0,0"], ["0,0,0"]),
    ("domFold", "sdSphere(domFold(p, normalize(vec3(1, 1, 0))) - vec3(0.4, 0, 0), 0.2)", 1.5, ["0.4,0,0", "0,-0.4,0"], ["-0.4,0,0", "0,0.4,0"]),
    ("domTwist (scaled)", "sdBox(domTwist(p, 1.5), vec3(0.3, 0.6, 0.15)) / (0.75 * 0.335 / 1.0 + sqrt(1.0 + 0.25 * 0.5025 * 0.5025))", 1.5, ["0,0,0"], ["0,0.7,0"]),
]

SDF2 = [
    ("sdCircle", "sdCircle(p, 0.6)", 1.2, ["0,0"], ["0.7,0"]),
    ("sdBox 2D", "sdBox(p, vec2(0.6, 0.3))", 1.2, ["0,0", "0.55,0.25"], ["0.65,0", "0,0.35"]),
    ("sdRoundedBox", "sdRoundedBox(p, vec2(0.6, 0.4), vec4(0.1, 0.3, 0.0, 0.2))", 1.2, ["0,0"], ["0.65,0", "-0.59,-0.39"]),
    ("sdSegment", "sdSegment(p, vec2(-0.5, -0.2), vec2(0.4, 0.5)) - 0.1", 1.2, ["0,0.15"], ["0,-0.5"]),
    ("sdUnevenCapsule", "sdUnevenCapsule(p, 0.3, 0.1, 0.7)", 1.2, ["0,0", "0,0.7"], ["0,-0.35", "0,0.85", "0.3,0.5"]),
    ("sdArc", "sdArc(p, vec2(sin(2.0), cos(2.0)), 0.6, 0.08)", 1.2, ["0,0.6", "0.6,0"], ["0,0", "0,-0.6"]),
    ("sdEquilateralTriangle", "sdEquilateralTriangle(p, 0.6)", 1.2, ["0,0", "0,0.5"], ["0,-0.4", "0,0.8"]),
    ("sdTriangle", "sdTriangle(p, vec2(-0.6, -0.4), vec2(0.7, -0.2), vec2(0.1, 0.6))", 1.2, ["0,0"], ["0,-0.5", "-0.5,0.5"]),
    ("sdTriangle cw", "sdTriangle(p, vec2(0.1, 0.6), vec2(0.7, -0.2), vec2(-0.6, -0.4))", 1.2, ["0,0"], ["0,-0.5"]),
    ("sdRegularPolygon", "sdRegularPolygon(p, 0.6, 6)", 1.2, ["0,0", "0,0.55"], ["0,0.65", "0.6,0"]),
    ("sdStar", "sdStar(p, 0.7, 5, 2.5)", 1.2, ["0,0", "0,0.65"], ["0,0.75", "0,-0.6"]),
    ("sdVesica", "sdVesica(p, 0.8, 0.5)", 1.2, ["0,0", "0,0.55"], ["0.35,0", "0,0.65"]),
    ("sdMoon", "sdMoon(p, 0.3, 0.6, 0.5)", 1.2, ["-0.5,0"], ["0.1,0", "0.7,0"]),
    ("sdHeart", "sdHeart(p + vec2(0.0, 0.5))", 1.2, ["0,0", "0.3,0.2"], ["0,-0.6", "0,0.55"]),
    ("sdRhombus", "sdRhombus(p, vec2(0.6, 0.35))", 1.2, ["0,0", "0.5,0"], ["0.65,0", "0.4,0.25"]),
    ("sdEllipse", "sdEllipse(p, vec2(0.7, 0.35))", 1.2, ["0,0"], ["0.75,0", "0,0.4"]),
    ("sdQuadraticBezier 2D", "sdQuadraticBezier(p, vec2(-0.7, -0.3), vec2(0.0, 0.9), vec2(0.6, -0.4)) - 0.05", 1.2, ["-0.7,-0.3"], ["0,-0.5"],
     {"allow": {"1": 0.001, "2": 0.03}}),   # ~1e-4 float noise in the cubic solve
    ("sdQuadraticBezier 2D straight", "sdQuadraticBezier(p, vec2(-0.6, -0.3), vec2(0.0, 0.0), vec2(0.6, 0.3)) - 0.05", 1.2, ["0,0"], ["0,0.3"]),
    ("hexEdgeDistance", "-hexEdgeDistance(hexGrid(p * 3.0).xy) / 3.0", 1.2, [], []),
    ("truchetArcs", "truchetArcs(p * 3.0, 0.1) / 3.0", 1.2, [], []),
]

# Curves checked against brute-force sampling (bit 8): name -> (expr of p, point on curve at parameter t).
BRUTE = {
    "sdQuadraticBezier 2D": ("vec2", "mix(mix(vec2(-0.7, -0.3), vec2(0.0, 0.9), t), mix(vec2(0.0, 0.9), vec2(0.6, -0.4), t), t)", 0.05),
    "sdQuadraticBezier 2D straight": ("vec2", "mix(vec2(-0.6, -0.3), vec2(0.6, 0.3), t)", 0.05),
    "sdQuadraticBezier 3D": ("vec3", "mix(mix(vec3(-0.6, -0.3, 0.1), vec3(0.0, 0.9, -0.3), t), mix(vec3(0.0, 0.9, -0.3), vec3(0.6, -0.2, 0.2), t), t)", 0.1),
}

# Allowed failure rates for the exactness bit (medial-axis noise). Everything else must be 0.
EXACT_ALLOWANCE = 0.01

# Hand-written properties. Each body is the inside of `int runTest(vec4 a, vec4 b)`; return failure bits.
PROPERTIES = [
    ("hash ranges and integer-input semantics", """
        vec2 cell = floor((a.xy - 0.5) * 2e5);
        int f = 0;
        float h = hash12(cell);
        if (!(h >= 0.0 && h < 1.0)) f |= 1;
        if (hash12(cell) != hash12(cell + 0.25)) f |= 2;          // fractional part is ignored
        if (hash12(vec2(-0.0, cell.y)) != hash12(vec2(0.0, cell.y))) f |= 4;  // -0.0 == 0.0
        vec3 h3 = hash33(vec3(cell, cell.x - cell.y));
        if (any(lessThan(h3, vec3(0.0))) || any(greaterThanEqual(h3, vec3(1.0)))) f |= 1;
        if (hash12(cell) == hash12(cell + vec2(1.0, 0.0)) && hash12(cell) == hash12(cell + vec2(0.0, 1.0))) f |= 8;
        return f;""", {}),
    ("valueNoiseD derivative matches finite difference", """
        vec2 p = (a.xy - 0.5) * 40.0;
        vec3 n = valueNoiseD(p);
        float e = 1e-3;
        vec2 fd = vec2(valueNoise(p + vec2(e, 0.0)) - valueNoise(p - vec2(e, 0.0)),
                       valueNoise(p + vec2(0.0, e)) - valueNoise(p - vec2(0.0, e))) / (2.0 * e);
        int f = 0;
        if (length(n.yz - fd) > 0.02 * (1.0 + length(fd))) f |= 1;
        if (n.x < -1e-5 || n.x > 1.0 + 1e-5) f |= 2;
        return f;""", {}),
    ("gradientNoiseD derivative matches finite difference", """
        vec2 p = (a.xy - 0.5) * 40.0;
        vec3 n = gradientNoiseD(p);
        float e = 1e-3;
        vec2 fd = vec2(gradientNoise(p + vec2(e, 0.0)) - gradientNoise(p - vec2(e, 0.0)),
                       gradientNoise(p + vec2(0.0, e)) - gradientNoise(p - vec2(0.0, e))) / (2.0 * e);
        int f = 0;
        if (length(n.yz - fd) > 0.02 * (1.0 + length(fd))) f |= 1;
        if (abs(n.x) > 0.75) f |= 2;
        return f;""", {}),
    ("curlNoise is divergence-free", """
        vec2 p = (a.xy - 0.5) * 20.0;
        float e = 1e-3;
        float div = (curlNoise(p + vec2(e, 0.0)).x - curlNoise(p - vec2(e, 0.0)).x
                   + curlNoise(p + vec2(0.0, e)).y - curlNoise(p - vec2(0.0, e)).y) / (2.0 * e);
        return abs(div) > 0.05 ? 1 : 0;""", {}),
    ("noise and fbm ranges", """
        vec2 p = (a.xy - 0.5) * 200.0;
        vec3 q = (a.xyz - 0.5) * 50.0;
        int f = 0;
        float v = fbm(p, 6);
        if (isnan(v) || abs(v) > 1.5) f |= 1;
        float g = gradientNoise(q);
        if (isnan(g) || abs(g) > 1.2) f |= 2;
        float vn = valueNoise(q);
        if (vn < -1e-5 || vn > 1.0 + 1e-5) f |= 4;
        float er = erodedFbm(p, 8);
        if (isnan(er) || er < -1.5 || er > 1.5) f |= 8;
        return f;""", {}),
    ("voronoi: F1 <= F2, border distance non-negative", """
        vec2 p = (a.xy - 0.5) * 50.0;
        vec4 v = voronoi(p, 1.0);
        vec3 e = voronoiBorder(p, 1.0);
        int f = 0;
        if (v.x > v.y + 1e-5) f |= 1;
        if (e.x < -1e-4 || e.x > 1.0) f |= 2;
        if (abs(length(e.yz) - v.x) > 1e-3) f |= 4;   // both agree on the nearest point
        return f;""", {}),
    ("hexGrid ids are integers and local stays inside the hexagon", """
        vec2 p = (a.xy - 0.5) * 60.0;
        vec4 h = hexGrid(p);
        int f = 0;
        if (any(greaterThan(abs(h.zw - floor(h.zw + 0.5)), vec2(1e-3)))) f |= 1;
        if (hexEdgeDistance(h.xy) < -1e-4) f |= 2;
        return f;""", {}),
    ("smooth unions never exceed min and match it far apart", """
        float x = (a.x - 0.5) * 4.0, y = (a.y - 0.5) * 4.0, k = 0.05 + a.z;
        int f = 0;
        if (smin(x, y, k) > min(x, y) + 1e-6 || sminCubic(x, y, k) > min(x, y) + 1e-6) f |= 1;
        if (abs(x - y) >= k && (abs(smin(x, y, k) - min(x, y)) > 1e-6 || abs(sminCubic(x, y, k) - min(x, y)) > 1e-6)) f |= 2;
        if (min(x, y) - smin(x, y, k) > 0.25 * k + 1e-6) f |= 4;
        if (abs(sminBlend(x, y, k).x - smin(x, y, k)) > 1e-6) f |= 8;
        return f;""", {}),
    ("domain transforms preserve distances", """
        vec2 p = (a.xy - 0.5) * 4.0;
        vec3 q = (b.xyz - 0.5) * 4.0;
        int f = 0;
        if (abs(length(domPolar(p, 7.0)) - length(p)) > 1e-4) f |= 1;
        if (abs(length(domFold(q, normalize(vec3(1.0, 2.0, -1.0)))) - length(q)) > 1e-4) f |= 2;
        if (abs(length(domTwist(q, 2.0)) - length(q)) > 1e-4) f |= 4;
        vec2 r = domRepeat(p, vec2(0.7));
        if (any(greaterThan(abs(r), vec2(0.35 + 1e-4)))) f |= 8;
        return f;""", {}),
    ("intersectors agree with SDFs", """
        vec3 ro = (a.xyz - 0.5) * 6.0;
        vec3 rd = normalize(b.xyz - 0.5 + 1e-4);
        int f = 0;
        vec2 ts = iSphere(ro, rd, vec3(0.2, -0.1, 0.3), 0.8);
        if (ts.x > 0.0 && abs(sdSphere(ro + rd * ts.x - vec3(0.2, -0.1, 0.3), 0.8)) > 1e-3) f |= 1;
        vec2 tb = iBox(ro, rd, vec3(0.7, 0.4, 0.5));
        if (tb.x > 0.0 && abs(sdBox(ro + rd * tb.x, vec3(0.7, 0.4, 0.5))) > 1e-3) f |= 2;
        float tp = iPlane(ro, rd, normalize(vec3(0.2, 1.0, 0.1)), 0.3);
        if (tp > 0.0 && abs(sdPlane(ro + rd * tp, normalize(vec3(0.2, 1.0, 0.1)), 0.3)) > 1e-3) f |= 4;
        return f;""", {}),
    ("cameraMatrix is orthonormal", """
        vec3 ro = (a.xyz - 0.5) * 10.0;
        vec3 ta = ro + normalize(b.xyz - 0.5 + 1e-3) * (0.5 + 5.0 * a.w);
        mat3 m = cameraMatrix(ro, ta, (b.w - 0.5) * 2.0);
        mat3 i = transpose(m) * m;
        int f = 0;
        if (abs(i[0][0] - 1.0) + abs(i[1][1] - 1.0) + abs(i[2][2] - 1.0) + abs(i[0][1]) + abs(i[0][2]) + abs(i[1][2]) > 1e-3) f |= 1;
        return f;""", {"1": 0.002}),   # degenerate when looking straight up/down
]
