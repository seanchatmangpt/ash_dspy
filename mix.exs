defmodule AshDspy.MixProject do
  use Mix.Project

  @version "26.9.25"
  @source_url "https://github.com/seanchatmangpt/ash_dspy"

  def project do
    [
      app: :ash_dspy,
      version: @version,
      elixir: "~> 1.18",
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
      {:jason, "~> 1.4", optional: true},
      # Hand-written runtime layer (lib/ash_dspy/runtime.ex). Repoint at a tag or
      # main once dspy-wasm PR #8 merges.
      {:dspy_wasm,
       git: "https://github.com/seanchatmangpt/dspy-wasm.git",
       branch: "claude/dspy-wasm-prod-readiness-0qb34s",
       sparse: "consumer/elixir"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "DSPy-style semantic signature DSL for Ash resources: declare typed inputs, " <>
      "outputs, metrics, requirement bounds, and minimization objectives directly " <>
      "on the resource via a single `dspy` section."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Sean Chatman"]
    ]
  end
end
