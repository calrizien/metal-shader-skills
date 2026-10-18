---
description: "Port a GLSL ES 1.00 (WebGL1) shader with gl_FragColor, texture2D, #version, custom uniforms and a sine hash to Shadertoy GLSL ES 3.00."
tags: [positive, repair]
expected_outcome: "final.glsl is a Shadertoy mainImage shader that samples iChannel0 with texture(), declares no uniforms or varyings, and has no gl_FragColor, texture2D, #version or sine hash."
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

Can you port this old WebGL1 fragment shader to Shadertoy (GLSL ES 3.00)? I'll bind the texture to iChannel0. Keep the look the same. Save the paste-ready result as `final.glsl`.

```glsl
#version 100
#ifdef GL_ES
precision mediump float;
#endif

uniform vec2 u_resolution;
uniform float u_time;
uniform sampler2D u_texture;

float rand(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(rand(i), rand(i + vec2(1.0, 0.0)), u.x),
               mix(rand(i + vec2(0.0, 1.0)), rand(i + vec2(1.0, 1.0)), u.x), u.y);
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;
    float n = noise(uv * 8.0 + u_time * 0.2);
    vec2 warp = uv + 0.03 * vec2(n - 0.5, noise(uv * 8.0 - u_time * 0.2) - 0.5);
    vec3 tex = texture2D(u_texture, warp).rgb;
    vec3 col = mix(tex, vec3(0.1, 0.3, 0.6), 0.25 * n);
    gl_FragColor = vec4(col, 1.0);
}
```
