---
description: "Repair: the given map() twists a box without Lipschitz correction, so the march overshoots and the surface tears."
tags: [positive, repair]
expected_outcome: "final.glsl keeps the twist but scales the distance (or the march step) to compensate, follows the hard rules, and passes the skill's checker."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

This Shadertoy shader is supposed to show a slowly orbiting twisted column, but the surface is full of holes and torn-looking bits, worst near the edges. Can you fix it without losing the twist? Save the fixed, paste-ready shader as `final.glsl`.

```glsl
// Twisted column
const float TWIST = 3.0;  // radians per unit of height

mat2 rot(float a) {
    float c = cos(a), s = sin(a);
    return mat2(c, -s, s, c);
}

float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float map(vec3 p) {
    p.xz *= rot(TWIST * p.y);
    return sdBox(p, vec3(0.45, 1.6, 0.45));
}

vec3 calcNormal(vec3 p) {
    vec2 e = vec2(1e-3, 0.0);
    return normalize(vec3(map(p + e.xyy) - map(p - e.xyy),
                          map(p + e.yxy) - map(p - e.yxy),
                          map(p + e.yyx) - map(p - e.yyx)));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = (2.0 * fragCoord - iResolution.xy) / iResolution.y;

    float an = 0.3 * iTime;
    vec3 ro = vec3(4.0 * sin(an), 0.6, 4.0 * cos(an));
    vec3 ww = normalize(-ro);
    vec3 uu = normalize(cross(ww, vec3(0.0, 1.0, 0.0)));
    vec3 vv = cross(uu, ww);
    vec3 rd = normalize(uv.x * uu + uv.y * vv + 1.8 * ww);

    float t = 0.0;
    bool hit = false;
    for (int i = 0; i < 100; i++) {
        float d = map(ro + rd * t);
        if (d < 0.001) { hit = true; break; }
        t += d;
        if (t > 20.0) break;
    }

    vec3 col = vec3(0.08, 0.09, 0.12) - 0.05 * uv.y;
    if (hit) {
        vec3 p = ro + rd * t;
        vec3 n = calcNormal(p);
        vec3 l = normalize(vec3(0.6, 0.8, 0.4));
        float dif = clamp(dot(n, l), 0.0, 1.0);
        col = vec3(0.8, 0.55, 0.35) * (0.15 + 0.85 * dif);
    }
    fragColor = vec4(pow(col, vec3(0.4545)), 1.0);
}
```
