# Benchmark: batched `solve_many` — native rayon vs pure Task.async_stream.
#
# All three strategies implement the same work on an identical normalized batch:
#
#   * sequential  — Enum.map over solve/2 (no parallelism; the baseline).
#   * pure        — Finance.Solver.Newton.solve_many (Task.async_stream).
#   * native      — FinanceRustler.Solver.solve_many (one NIF, rayon-parallel).
#
# The interesting case is a large batch of *tiny* problems: single-solve there was
# a tie, but the batch amortizes one NIF crossing (native) against one process
# spawn per item (pure).
#
# Run with:  mix run bench/solve_many.exs

opts = [guess: 0.1, tolerance: 1.0e-9, max_iterations: 100, precision: 6]

loan = fn pv, rate, n ->
  pmt = pv * rate / (1 - :math.pow(1 + rate, -n))
  [{0.0, pv * 1.0} | for(t <- 1..n, do: {t / 1.0, -pmt})]
end

tiny = [{0.0, -1000.0}, {1.0, 300.0}, {2.0, 400.0}, {3.0, 500.0}]
medium = loan.(100_000, 0.01, 60)

inputs = %{
  "tiny (4 flows) x 1_000" => List.duplicate(tiny, 1_000),
  "tiny (4 flows) x 50_000" => List.duplicate(tiny, 50_000),
  "medium (60-period) x 1_000" => List.duplicate(medium, 1_000),
  "medium (60-period) x 5_000" => List.duplicate(medium, 5_000)
}

sequential = fn batch -> Enum.map(batch, &Finance.Solver.Newton.solve(&1, opts)) end
pure = fn batch -> Finance.Solver.Newton.solve_many(batch, opts) end
native = fn batch -> FinanceRustler.Solver.solve_many(batch, opts) end

# --- correctness: all three must produce identical results ---
sample = List.duplicate(medium, 5) ++ List.duplicate(tiny, 5)
IO.puts("agreement:")
IO.puts("  sequential == pure  : #{sequential.(sample) == pure.(sample)}")
IO.puts("  pure       == native: #{pure.(sample) == native.(sample)}\n")

Benchee.run(
  %{
    "sequential (Enum.map)" => sequential,
    "pure (Task.async_stream)" => pure,
    "native (rayon NIF)" => native
  },
  inputs: inputs,
  time: 3,
  memory_time: 1,
  warmup: 1
)
