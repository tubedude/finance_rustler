defmodule FinanceRustler.SolverTest do
  use ExUnit.Case, async: true

  @native FinanceRustler.Solver

  describe "parity with the default (pure-Elixir) solver" do
    test "reproduces the xirr regression anchors exactly" do
      cases = [
        {[{2015, 11, 1}, {2015, 10, 1}, {2015, 6, 1}], [-800_000, -2_200_000, 1_000_000],
         21.118359},
        {[{1985, 1, 1}, {1990, 1, 1}, {1995, 1, 1}], [1000, -600, -200], -0.034592},
        {[{2011, 12, 7}, {2011, 12, 7}, {2013, 5, 21}, {2013, 5, 21}],
         [1000.0, 2000.0, -2000.0, -4000.0], 0.610359}
      ]

      for {dates, values, expected} <- cases do
        assert Finance.CashFlow.xirr(dates, values, solver: @native) == {:ok, expected}
      end
    end

    test "matches the default solver across a spread of loans (rate x term)" do
      for rate_bp <- [10, 100, 500, 1200, 3000],
          nper <- [12, 60, 180, 480] do
        rate = rate_bp / 10_000
        pmt = -(100_000 * rate / (1 - :math.pow(1 + rate, -nper)))

        default = Finance.TVM.rate(nper, pmt, 100_000, 0.0, 0, precision: 10)
        native = Finance.TVM.rate(nper, pmt, 100_000, 0.0, 0, precision: 10, solver: @native)

        assert native == default, "mismatch at rate_bp=#{rate_bp} nper=#{nper}"
      end
    end

    test "reports :did_not_converge like the default when no root can be bracketed" do
      # An all-positive annuity has no rate.
      assert Finance.TVM.rate(10, 100, 1000, 0.0, 0, solver: @native) ==
               {:error, :did_not_converge}
    end

    test "honours :precision the same way" do
      flows = [{~D[2019-01-01], -1000}, {~D[2020-01-01], 1100}]
      assert Finance.CashFlow.xirr(flows, solver: @native, precision: 2) == {:ok, 0.1}
      assert Finance.CashFlow.xirr(flows, solver: @native) == Finance.CashFlow.xirr(flows)
    end
  end

  describe "native batch (solve_many) parity" do
    test "irr_many matches the default solver, including failed series" do
      series = [[-1000, 1100], [-1000, 500, 500, 300], [100, 200], [], [-500, 250, 250, 100]]

      assert Finance.CashFlow.irr_many(series, solver: @native) ==
               Finance.CashFlow.irr_many(series)
    end

    test "xirr_many matches the default solver" do
      series = [
        [{~D[2019-01-01], -1000}, {~D[2020-01-01], 1100}],
        [{~D[2015-06-01], 1_000_000}, {~D[2015-10-01], -2_200_000}, {~D[2015-11-01], -800_000}],
        [{~D[2019-01-01], -1000}, {~D[2020-01-01], 1200}]
      ]

      assert Finance.CashFlow.xirr_many(series, solver: @native) ==
               Finance.CashFlow.xirr_many(series)
    end

    test "the batch solves a large portfolio in one rayon-parallel call" do
      series = for _ <- 1..500, do: [-1000, 300, 400, 500]
      results = Finance.CashFlow.irr_many(series, solver: @native)
      assert length(results) == 500
      assert Enum.all?(results, &(&1 == {:ok, 0.088963}))
    end
  end
end
