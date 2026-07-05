# FinanceRustler

A native solver backend for [`finance`](https://hex.pm/packages/finance): the
safeguarded Newton (`rtsafe`) root-finder behind `irr`/`xirr`/`rate`/`ytm`,
implemented in Rust via [Rustler](https://github.com/rusterlium/rustler).

It plugs into `finance`'s `Finance.Solver` behaviour. The dependency is one-way —
`finance_rustler` depends on `finance`, never the reverse — so the core
library stays pure and unaware of this package (the Nx + EXLA / Ecto + adapter
model).

## Usage

Add both packages to your project:

```elixir
# mix.exs
{:finance, "~> 1.4"},
{:finance_rustler, "~> 0.1"}
```

Then point the solver at this backend, globally:

```elixir
# config/config.exs
config :finance, solver: FinanceRustler.Solver
```

or per call:

```elixir
Finance.CashFlow.xirr(flows, solver: FinanceRustler.Solver)
```

Results are identical to the default solver — both find the same root to the
requested `:precision`. This backend is for throughput on long-horizon flows
(and, later, batched solves), not to change any numbers.

## Building

This package compiles a Rust NIF, so it needs a Rust toolchain
(`cargo`/`rustc`) at build time:

```bash
mix deps.get
mix compile        # builds native/finance_rustler via cargo
mix test           # parity tests against the pure-Elixir solver
```

A future release will ship precompiled binaries via `rustler_precompiled` so
end users don't need Rust installed.

## Status

Early. The single-solve `Finance.Solver` implementation is in place and tested
for parity; a batched `xirr_many`/`irr_many` API (the real throughput win) is
planned.
