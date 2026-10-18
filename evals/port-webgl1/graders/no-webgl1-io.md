---
type: regex
target:
  source: file
  path: final.glsl
pattern: '(?:^|\n)[ \t]*(?:uniform|varying|attribute)\b'
match: not_contains
---
