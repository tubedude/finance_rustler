defmodule FinanceRustlerAddon.Solver do
  @moduledoc """
  A native `Finance.Solver` backed by a Rust NIF — the same safeguarded Newton
  (`rtsafe`) the pure-Elixir default uses, ported to Rust.

  This is an opt-in backend. Add both packages to your project and point the
  solver at this module:

      # mix.exs
      {:finance, "~> 1.4"},
      {:finance_rustler_addon, "~> 0.1"}

      # config/config.exs
      config :finance, solver: FinanceRustlerAddon.Solver

  or per call:

      Finance.CashFlow.xirr(flows, solver: FinanceRustlerAddon.Solver)

  The result matches the default solver — both find the same root to the
  requested `:precision`. This backend exists for throughput on long-horizon
  flows (and, later, batched solves), not to change any numbers.
  """

  @behaviour Finance.Solver

  use Rustler, otp_app: :finance_rustler_addon, crate: "finance_rustler_addon"

  @impl Finance.Solver
  def solve(flows, opts) do
    times = Enum.map(flows, fn {t, _amount} -> t * 1.0 end)
    amounts = Enum.map(flows, fn {_t, amount} -> amount * 1.0 end)

    guess = Keyword.fetch!(opts, :guess) * 1.0
    tolerance = Keyword.fetch!(opts, :tolerance) * 1.0
    max_iterations = Keyword.fetch!(opts, :max_iterations)

    case nif_solve(times, amounts, guess, tolerance, max_iterations) do
      {:ok, rate} -> {:ok, Float.round(rate, Keyword.fetch!(opts, :precision))}
      {:did_not_converge, _} -> {:error, :did_not_converge}
    end
  end

  # Replaced by the NIF at load time; this body only runs if the crate failed to
  # load (e.g. the native library wasn't compiled).
  defp nif_solve(_times, _amounts, _guess, _tolerance, _max_iterations) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
