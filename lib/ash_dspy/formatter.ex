defmodule AshDspy.Formatter do
  @moduledoc """
  Spark.Formatter plugin helper for the `ash_dspy` DSL (`:dspy` section).

  Hand-written residue: the ash-extension-pack generates this package's
  extension/transformer/verifier/Info/installer/composition-test from
  `ontology.ttl`, but ships no formatter-plugin template, while its generated
  installer (`lib/mix/tasks/ash_dspy.install.ex`) registers this module as the
  consumer's formatter plugin. Mirrors the real ash_r2rml formatter shape.
  """

  @doc "Returns the list of Spark extensions exported by ash_dspy."
  def extensions, do: [AshDspy.Resource]

  @doc "Mix.Tasks.Format plugin callback"
  def features(_opts) do
    [extensions: [".ex", ".exs"]]
  end

  @doc "Mix.Tasks.Format plugin format callback"
  def format(contents, opts) do
    if Code.ensure_loaded?(Spark.Formatter) do
      opts_with_spark =
        Keyword.update(opts, :spark, [extensions: [AshDspy.Resource]], fn spark ->
          Keyword.update(spark, :extensions, [AshDspy.Resource], &[AshDspy.Resource | &1])
        end)

      Spark.Formatter.format(contents, opts_with_spark)
    else
      contents
    end
  end
end
