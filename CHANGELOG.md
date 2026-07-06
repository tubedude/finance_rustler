# Changelog

## 0.2.0

Requires `finance ~> 1.6`.

- Port the guess-anchored interior-scan bracket from `finance` 1.6.0, restoring
  lockstep parity with the pure-Elixir solver. The previous release used the older
  endpoint-only bracket, so against `finance >= 1.6.0` it could not find a root when
  the NPV crossed zero an even number of times (a series with more than one IRR),
  and it ignored `:guess` when selecting among multiple roots. Both now match the
  default solver exactly, and the parity tests cover the multi-root cases.

## 0.1.0

Initial release.

- `FinanceRustler.Solver` — a native `Finance.Solver` backend: the safeguarded
  Newton (`rtsafe`) root-finder ported to Rust via Rustler, kept in lockstep with
  the pure-Elixir solver so results match to `:precision`.
- `solve/2` for a single series, and `solve_many/2` for a whole batch in one call,
  parallelized across a rayon thread pool.
- Ships precompiled binaries for Linux (`x86_64` and `aarch64`, gnu) via
  `rustler_precompiled`; other platforms compile from source with a Rust toolchain.
