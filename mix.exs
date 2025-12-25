defmodule DecisionLog.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/dkuku/decision_log"

  def project do
    [
      app: :decision_log,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "DecisionLog",
      source_url: @source_url
    ]
  end

  defp description do
    "A lightweight Elixir library for tracking decisions made during processing. Provides structured logging with compression support for PostgreSQL storage."
  end

  defp package do
    [
      name: "decision_log",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "examples"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:decorator, "~> 1.4"},
      {:styler, "~> 1.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false}
    ]
  end
end
