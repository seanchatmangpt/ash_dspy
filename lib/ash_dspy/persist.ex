defmodule AshDspy.Resource.Persist do
  @moduledoc """
  Transformer for `ash_dspy`: normalizes the raw `:dspy`
  DSL entities into a compiled struct and persists it as `:ash_dspy_compiled`.
  """
  use Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    dspy_entities = Spark.Dsl.Transformer.get_entities(dsl_state, [:dspy])

    compiled = %{
      dspy: dspy_entities
    }

    {:ok, Spark.Dsl.Transformer.persist(dsl_state, :ash_dspy_compiled, compiled)}
  end
end
