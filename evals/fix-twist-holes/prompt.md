---
description: "Repair: the given map() twists a box without Lipschitz correction, so the march overshoots and the surface tears."
tags: [positive, repair]
expected_outcome: "final.metal keeps the twist but scales the distance (or the march step) to compensate, follows the hard rules, and passes the skill's checker."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

This Metal 4 shader is supposed to show a slowly orbiting twisted column, but the surface is full of holes and torn-looking bits, worst near the edges. Can you fix it without losing the twist? Save the fixed, standalone MSL 4.0 shader with fullscreenVertex and shaderFragment entry functions as `final.metal`.

```metal
// Twisted column
const float TWIST = 3.0;  // radians per unit of height

float2x2 rot(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(c, -s, s, c);
}

float sdBox(float3 p, float3 b) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float map(float3 p) {
    p.xz = p.xz * rot(TWIST * p.y);
    return sdBox(p, float3(0.45, 1.6, 0.45));
}

float3 calcNormal(float3 p) {
    float2 e = float2(1e-3, 0.0);
    return normalize(float3(map(p + e.xyy) - map(p - e.xyy),
                          map(p + e.yxy) - map(p - e.yxy),
                          map(p + e.yyx) - map(p - e.yyx)));
}

void shade(thread float4 &fragColor, float2 fragCoord) {
    float2 uv = (2.0 * fragCoord - resolution.xy) / resolution.y;

    float an = 0.3 * time;
    float3 ro = float3(4.0 * sin(an), 0.6, 4.0 * cos(an));
    float3 ww = normalize(-ro);
    float3 uu = normalize(cross(ww, float3(0.0, 1.0, 0.0)));
    float3 vv = cross(uu, ww);
    float3 rd = normalize(uv.x * uu + uv.y * vv + 1.8 * ww);

    float t = 0.0;
    bool hit = false;
    for (int i = 0; i < 100; i++) {
        float d = map(ro + rd * t);
        if (d < 0.001) { hit = true; break; }
        t += d;
        if (t > 20.0) break;
    }

    float3 col = float3(0.08, 0.09, 0.12) - 0.05 * uv.y;
    if (hit) {
        float3 p = ro + rd * t;
        float3 n = calcNormal(p);
        float3 l = normalize(float3(0.6, 0.8, 0.4));
        float dif = clamp(dot(n, l), 0.0, 1.0);
        col = float3(0.8, 0.55, 0.35) * (0.15 + 0.85 * dif);
    }
    fragColor = float4(pow(col, float3(0.4545)), 1.0);
}
```
