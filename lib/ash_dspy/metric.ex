defmodule AshDspy.Court.Metric do
  @moduledoc """
  Behaviour for court evaluation dimensions.

  A metric measures one named dimension of an implementation against a corpus.
  Implemented by the five default dimensions under `AshDspy.Court.Metrics.*`
  and by any user-supplied module; resolved by `resolve/1`.

  The execution surface is lane 3's implementation contract (`class/0`,
  `intelligence/0`, `run/2`); this behaviour never defines it, only calls it.
  """

  @callback dimension() :: atom()

  @typedoc "Measured outcome for one dimension: a score with metadata, or a refusal."
  @type outcome :: {score :: float(), meta :: term()} | {:refused, term()}

  @callback score(implementation_module :: module(), corpus :: [map()], ctx :: map()) ::
              outcome()

  @typedoc "Dimension atom -> metric module."
  @type metric_map :: %{optional(atom()) => module()}

  @defaults %{
    accuracy: AshDspy.Court.Metrics.Accuracy,
    determinism: AshDspy.Court.Metrics.Determinism,
    replay: AshDspy.Court.Metrics.Replay,
    provenance: AshDspy.Court.Metrics.Provenance,
    llm_residue: AshDspy.Court.Metrics.LLMResidue
  }

  @spec default_metrics() :: metric_map()
  def default_metrics, do: @defaults

  @doc """
  Resolves a metric specification to a metric module.

  - A dimension atom present in the default set resolves to its default module
    (e.g. `:accuracy` -> `AshDspy.Court.Metrics.Accuracy`).
  - Any other atom that loads as a module exporting `dimension/0` resolves to
    itself.
  - Everything else falls back to `AshDspy.Court.Metrics.Null`, which refuses.
    Fail-closed: an unresolvable metric can never pass a court.
  """
  @spec resolve(term()) :: module()
  def resolve(spec)

  def resolve(spec) when is_atom(spec) and is_map_key(@defaults, spec) do
    Map.fetch!(@defaults, spec)
  end

  def resolve(spec) when is_atom(spec) do
    case Code.ensure_loaded(spec) do
      {:module, ^spec} ->
        if function_exported?(spec, :dimension, 0) do
          spec
        else
          AshDspy.Court.Metrics.Null
        end

      _ ->
        AshDspy.Court.Metrics.Null
    end
  end

  def resolve(_spec), do: AshDspy.Court.Metrics.Null
end
