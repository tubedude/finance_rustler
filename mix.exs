defmodule FinanceRustler.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/tubedude/finance_rustler"

  def project do
    [
      app: :finance_rustler,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "A native (Rustler) solver backend for the Finance library: the safeguarded " <>
          "Newton (rtsafe) root-finder, ported to Rust.",
      package: package(),
      name: "FinanceRustler",
      source_url: @source_url,
      docs: [main: "FinanceRustler.Solver", source_url: @source_url]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      # Dev/test resolves Finance from the local checkout; a release switches this
      # to {:finance, "~> 1.4"} from Hex. The dependency is one-way — Finance never
      # references this package.
      {:finance, path: "../finance-elixir"},
      {:rustler, "~> 0.38"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:benchee, "~> 1.3", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"finance" => "https://hex.pm/packages/finance", "GitHub" => @source_url},
      # Ship the Rust source, never the build artifacts under target/.
      files: ~w(lib native/finance_rustler/src native/finance_rustler/Cargo.toml
                mix.exs README.md .formatter.exs)
    ]
  end
end
