defmodule AshDspy.Court.Metrics.LLMResidue do
  @moduledoc """
  LLM-residue dimension: `1.0 - (class == :llm and 1 or 0)`.

  A non-LLM class scores 1.0; the `:llm` class scores 0.0. If the class
  cannot be read structurally from the implementation, this is a refusal.
  Reported by the court but not gating by default, mirroring the
  minimize-objective semantics of the `dspy` DSL.
  """

  @behaviour AshDspy.Court.Metric

  alias AshDspy.Court.Runner

  @impl true
  def dimension, do: :llm_residue

  @impl true
  def score(implementation_module, _corpus, _ctx) do
    case Runner.class(implementation_module) do
      {:ok, :llm} ->
        {0.0, %{class: :llm, residue: true}}

      {:ok, class} ->
        {1.0, %{class: class, residue: false}}

      {:error, reason} ->
        {:refused, {:class_unreadable, implementation_module, reason}}
    end
  end
end
