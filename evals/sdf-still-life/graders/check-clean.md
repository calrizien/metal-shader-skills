---
type: regex
target: trace
pattern: 'checked \d+ unit\(s\) with the MSL 4\.1 compiler[\s\S]*?(?<!\d)0 error\(s\)(?![\s\S]*(?<!\d)[1-9]\d* error\(s\))'
arm: with-only
---
