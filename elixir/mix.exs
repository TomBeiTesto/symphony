defmodule SymphonyElixir.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :symphony_elixir,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      test_coverage: [threshold: 80],
      escript: [main_module: SymphonyElixir.CLI]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "specs.check": :test,
        "pr_body.check": :test,
        coveralls: :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {SymphonyElixir.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.11"},
      {:req, "~> 0.5"},
      {:solid, "~> 0.15"},
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.6"},
      {:file_system, "~> 1.0"},

      # Dev/Test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.2", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      lint: ["format --check-formatted", "credo --strict"],
      quality: ["lint", "dialyzer"],
      "specs.check": ["run lib/mix/tasks/specs_check.exs"]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/project.plt"},
      plt_add_apps: [:mix],
      flags: [:unmatched_returns, :error_handling, :no_opaque]
    ]
  end
end
