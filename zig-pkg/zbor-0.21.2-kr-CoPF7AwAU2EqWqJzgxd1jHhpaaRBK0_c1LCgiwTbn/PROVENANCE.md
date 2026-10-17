# Zbor build compatibility

Source: https://codeberg.org/r4gus/zbor
Revision: `658c1c0ec607557b52d2e2a42acbfad31058ecee`, version `0.21.2`.
Original package hash: `zbor-0.21.2-kr-CoPF7AwAU2EqWqJzgxd1jHhpaaRBK0_c1LCgiwTbn`.
License: MIT; see `license`.

Local patch: `build.zig` supplies the original debug default when Zig 0.18's
`standardOptimizeOption` returns null. Library sources are unchanged.
