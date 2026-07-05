# Benchmark: native (Rust NIF) solver vs the pure-Elixir solver.
#
# Both implement `Finance.Solver`. This calls `solve/2` directly on already-
# normalized flows, so it measures the solver itself — and, for the native one,
# the cost of marshalling two f64 lists across the NIF boundary and back. The
# question the plan flagged: does the Rust NIF actually beat pure Elixir once you
# pay for that crossing, and at what flow length does it start to win?
#
# Run with:  mix run bench/native_vs_pure.exs

pure = Finance.Solver.Newton
native = FinanceRustler.Solver

opts = [guess: 0.1, tolerance: 1.0e-9, max_iterations: 100, precision: 6]

loan = fn pv, rate, n ->
  pmt = pv * rate / (1 - :math.pow(1 + rate, -n))
  [{0.0, pv * 1.0} | for(t <- 1..n, do: {t / 1.0, -pmt})]
end

inputs = %{
  "easy — 4 flows" => [{0.0, -1000.0}, {1.0, 300.0}, {2.0, 400.0}, {3.0, 500.0}],
  "medium — 60-period loan" => loan.(100_000, 0.01, 60),
  "long — 480-period loan" => loan.(100_000, 0.004, 480),
  "xlong — 2000-period loan" => loan.(100_000, 0.002, 2000)
}

# --- correctness: the native solver must match the pure one to :precision ---
IO.puts("agreement (native must equal pure):\n")

for {label, flows} <- inputs do
  p = pure.solve(flows, opts)
  n = native.solve(flows, opts)
  IO.puts("  #{String.pad_trailing(label, 26)} pure=#{inspect(p)}  native=#{inspect(n)}  equal=#{p == n}")
end

IO.puts("")

Benchee.run(
  %{
    "pure (Elixir rtsafe)" => fn flows -> pure.solve(flows, opts) end,
    "native (Rust NIF)" => fn flows -> native.solve(flows, opts) end
  },
  inputs: inputs,
  time: 3,
  memory_time: 1,
  warmup: 1
)
