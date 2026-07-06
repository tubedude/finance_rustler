defmodule FinanceRustler.Solver do
  @moduledoc """
  A native `Finance.Solver` backed by a Rust NIF — the same safeguarded Newton
  (`rtsafe`) the pure-Elixir default uses, ported to Rust.

  This is an opt-in backend. Add both packages to your project and point the
  solver at this module:

      # mix.exs
      {:finance, "~> 1.6"},
      {:finance_rustler, "~> 0.1"}

      # config/config.exs
      config :finance, solver: FinanceRustler.Solver

  or per call:

      Finance.CashFlow.xirr(flows, solver: FinanceRustler.Solver)

  The result matches the default solver — both find the same root to the
  requested `:precision`. This backend exists for throughput: `solve_many/2` runs
  a whole batch in one call, parallelized across a rayon thread pool, and single
  solves are faster on long-horizon flows. It changes no numbers.
  """

  @behaviour Finance.Solver

  @version Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :finance_rustler,
    crate: "finance_rustler",
    base_url: "https://github.com/tubedude/finance_rustler/releases/download/v#{@version}",
    force_build: System.get_env("FINANCE_RUSTLER_BUILD") in ["1", "true"],
    version: @version,
    nif_versions: ["2.15"],
    targets: ~w(
      x86_64-unknown-linux-gnu
      aarch64-unknown-linux-gnu
    )

  @impl Finance.Solver
  def solve(flows, opts) do
    {times, amounts} = split(flows)

    times
    |> nif_solve(amounts, guess(opts), tolerance(opts), Keyword.fetch!(opts, :max_iterations))
    |> to_result(Keyword.fetch!(opts, :precision))
  end

  @impl Finance.Solver
  def solve_many(batch, opts) do
    problems = Enum.map(batch, &split/1)
    precision = Keyword.fetch!(opts, :precision)

    problems
    |> nif_solve_many(guess(opts), tolerance(opts), Keyword.fetch!(opts, :max_iterations))
    |> Enum.map(&to_result(&1, precision))
  end

  defp split(flows) do
    {Enum.map(flows, fn {t, _a} -> t * 1.0 end), Enum.map(flows, fn {_t, a} -> a * 1.0 end)}
  end

  defp guess(opts), do: Keyword.fetch!(opts, :guess) * 1.0
  defp tolerance(opts), do: Keyword.fetch!(opts, :tolerance) * 1.0

  # `+ 0.0` collapses a negative zero, matching `Finance.Solver.Newton`.
  defp to_result({:ok, rate}, precision), do: {:ok, Float.round(rate, precision) + 0.0}
  defp to_result({:did_not_converge, _rate}, _precision), do: {:error, :did_not_converge}

  # Replaced by the NIFs at load time; these bodies only run if the crate failed
  # to load (e.g. the native library wasn't compiled).
  defp nif_solve(_times, _amounts, _guess, _tolerance, _max_iterations) do
    :erlang.nif_error(:nif_not_loaded)
  end

  defp nif_solve_many(_batch, _guess, _tolerance, _max_iterations) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
