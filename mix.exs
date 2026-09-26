defmodule AshDspy.MixProject do
  use Mix.Project

  @version "26.9.26"
  @source_url "https://github.com/seanchatmangpt/ash_dspy"

  def project do
    [
      app: :ash_dspy,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: description(),
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:ash, "~> 3.0"},
      {:spark, "~> 2.2"},
      {:igniter, "~> 0.5", optional: true},
      {:jason, "~> 1.4"},
      {:wasmex, "~> 0.14.0"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "DSPy semantics for Ash resources through a WASI-P2 component: declare typed inputs, " <>
      "outputs, metrics, requirement bounds, and minimization objectives on the resource, " <>
      "then execute DSPy through dspy-wasm without embedding Python in the BEAM."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Sean Chatman"]
    ]
  end
end
