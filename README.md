# FinanceRustler

[![CI](https://github.com/tubedude/finance_rustler/actions/workflows/ci.yml/badge.svg)](https://github.com/tubedude/finance_rustler/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/finance_rustler.svg)](https://hex.pm/packages/finance_rustler)
[![Hex Docs](https://img.shields.io/badge/hex-docs-8e5ea2.svg)](https://hexdocs.pm/finance_rustler)

A native solver backend for [`finance`](https://hex.pm/packages/finance) — the
safeguarded Newton (`rtsafe`) root-finder behind `irr`, `xirr`, `rate`, and
`ytm`, ported to Rust with [Rustler](https://github.com/rusterlium/rustler).

It plugs into `finance`'s `Finance.Solver` behaviour as a swappable backend, the
way [`EXLA`](https://hex.pm/packages/exla) plugs into Nx. The dependency runs one
way — `finance_rustler` depends on `finance`, never the reverse — so the core
library stays pure and unaware this package exists.

The numbers don't change: results match the built-in solver to the requested
`:precision`. What changes is throughput, above all `solve_many/2`, which solves
a whole batch in one call across a rayon thread pool.

## Installation

Add both packages — `finance` for the API, `finance_rustler` for the backend:

```elixir
def deps do
  [
    {:finance, "~> 1.6"},
    {:finance_rustler, "~> 0.2"}
  ]
end
```

Precompiled binaries ship for Linux (`x86_64`/`aarch64`, gnu) and macOS
(`x86_64`/`aarch64`), so on those targets nothing extra is needed. On other
platforms (musl, Windows), set `FINANCE_RUSTLER_BUILD=1` and have a Rust toolchain
(`cargo`/`rustc`) to compile the NIF from source.

## Usage

Point `finance` at the backend once, in config:

```elixir
# config/config.exs
config :finance, solver: FinanceRustler.Solver
```

or choose it per call:

```elixir
Finance.CashFlow.xirr(flows, solver: FinanceRustler.Solver)

Finance.CashFlow.xirr_many(portfolio, solver: FinanceRustler.Solver)
```

Nothing else changes — the same `finance` functions, the same results.

## Performance

The backend earns its keep on batches. `bench/solve_many.exs` pits `solve_many/2`
against the pure-Elixir solver (chunked `Task.async_stream`) and a plain
sequential map — median time to solve the whole batch:

| batch                  | native (rayon) | pure (chunked) | sequential |
| ---------------------- | -------------- | -------------- | ---------- |
| 1,000 × 4-flow         | 2.4 ms         | 7.6 ms         | 8.1 ms     |
| 1,000 × 60-period loan | 14.8 ms        | 23.7 ms        | 185 ms     |
| 5,000 × 60-period loan | 114 ms         | 98 ms          | 1,004 ms   |

Both parallel strategies beat a sequential map by an order of magnitude. The
native backend leads on batches of many small series — one NIF crossing plus
rayon, against one process spawn per series — and keeps the arithmetic off the
BEAM schedulers. On large batches of costlier series the chunked pure solver
draws level, so this backend is an option for throughput, not a requirement.

Run them yourself:

```bash
mix run bench/solve_many.exs       # batch: native vs pure vs sequential
mix run bench/native_vs_pure.exs   # single solve, by flow length
```

## Building and testing

```bash
mix deps.get
FINANCE_RUSTLER_BUILD=1 mix compile   # builds native/finance_rustler via cargo
FINANCE_RUSTLER_BUILD=1 mix test      # parity tests against the pure-Elixir solver
```

The parity tests assert that every result — single and batched, success and
error — matches `finance`'s default solver exactly.

Downstream projects on Linux and macOS get the precompiled binary via
[`rustler_precompiled`](https://hex.pm/packages/rustler_precompiled) and need no
Rust toolchain. Cutting a release: push a `v*` tag, let the release workflow build
the Linux and macOS NIFs and attach them to the GitHub release, then run
`FINANCE_RUSTLER_BUILD=1 mix rustler_precompiled.download FinanceRustler.Solver --all`
to generate the checksum file, commit it, and `mix hex.publish`.

## License

MIT — see [LICENSE](LICENSE).
