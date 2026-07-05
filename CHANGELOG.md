# Changelog

## 0.1.0

Initial release.

- `FinanceRustler.Solver` — a native `Finance.Solver` backend: the safeguarded
  Newton (`rtsafe`) root-finder ported to Rust via Rustler, kept in lockstep with
  the pure-Elixir solver so results match to `:precision`.
- `solve/2` for a single series, and `solve_many/2` for a whole batch in one call,
  parallelized across a rayon thread pool.
- Compiled from source; requires a Rust toolchain at build time.
