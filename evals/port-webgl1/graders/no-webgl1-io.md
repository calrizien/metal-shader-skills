---
type: regex
target:
  source: file
  path: final.metal
pattern: '(?:^|\n)[ \t]*(?:uniform|varying|attribute)\b'
match: not_contains
---
