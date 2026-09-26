defmodule AshDspy.Court do
  @moduledoc """
  The court: evaluates an implementation module against a corpus across
  metric dimensions and returns a single `AshDspy.Court.Verdict`.

  Main entry point:

      AshDspy.Court.evaluate(implementation_module, corpus, metric_opts, ctx)

  - `implementation_module` -- a module exposing the lane-3 implementation
    contract (`class/0`, `intelligence/0`, `run/2`). Called dynamically; this
    module never defines that behaviour.
  - `corpus` -- list of `%{signature: term, inputs: map, outputs: map}`.
  - `metric_opts` -- keyword list or map. Keys: `:bounds` (map of dimension
    -> minimum passing float, overriding the defaults) and `:metrics` (map of
    dimension -> metric module overriding the defaults).
  - `ctx` -- map passed through to every metric run.

  Anti-vacuity is structural: the court fails an implementation that fails.
  Errors and refusals count as misses; determinism double-runs; an empty
  corpus never passes; a refusing dimension never passes; and the court never
  raises on a broken implementation -- it returns a failing verdict.

  Default gating bounds: `accuracy >= 1.0`, `determinism >= 1.0`,
  `replay >= 1.0`, `provenance >= 1.0`. `llm_residue` is reported but not
  gating by default, mirroring the minimize-objective semantics of the `dspy`
  DSL; an explicit bound in `:bounds` makes it gate.
  """

  alias AshDspy.Court.Metric
  alias AshDspy.Court.Runner
  alias AshDspy.Court.Verdict

  @default_bounds %{accuracy: 1.0, determinism: 1.0, replay: 1.0, provenance: 1.0}
  @default_metrics AshDspy.Court.Metric.default_metrics()

  @doc """
  Evaluates `implementation_module` against `corpus` and returns a
  `%AshDspy.Court.Verdict{}`. Never raises on implementation, corpus, or
  metric failure.
  """
  @spec evaluate(module(), [map()], keyword() | map(), map()) :: Verdict.t()
  def evaluate(implementation_module, corpus, metric_opts \\ [], ctx \\ %{})

  def evaluate(implementation_module, corpus, metric_opts, ctx) do
    opts = normalize_opts(metric_opts)
    corpus = normalize_corpus(corpus)
    corpus_digest = digest(:corpus, corpus)

    if corpus == [] do
      %Verdict{
        scores: %{},
        passed: false,
        reasons: ["empty_corpus"],
        digest: digest(:verdict, {implementation_module, %{}, corpus_digest})
      }
    else
      metrics = metric_set(opts)
      bounds = bound_set(opts)
      {scores, measure_reasons} = measure(metrics, implementation_module, corpus, ctx)
      {gate_passed, gate_reasons} = gate(scores, bounds)
      passed = gate_passed and measure_reasons == []

      %Verdict{
        scores: scores,
        passed: passed,
        reasons: Enum.reverse(measure_reasons) ++ gate_reasons,
        digest: digest(:verdict, {implementation_module, scores, corpus_digest})
      }
    end
  end

  @doc """
  Digests `{label, term}` to a lowercase sha256 hex binary via `:crypto`.
  """
  @spec digest(term(), term()) :: String.t()
  def digest(label, term) do
    _ = Application.ensure_all_started(:crypto)

    :crypto.hash(:sha256, :erlang.term_to_binary({label, term}))
    |> Base.encode16(case: :lower)
  end

  ## Internals

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts
  defp normalize_opts(_opts), do: %{}

  defp normalize_corpus(corpus) when is_list(corpus), do: corpus
  defp normalize_corpus(nil), do: []
  defp normalize_corpus(corpus), do: List.wrap(corpus)

  defp metric_set(opts) do
    overrides = to_map(Map.get(opts, :metrics, %{}))
    bounded = to_map(Map.get(opts, :bounds, %{}))

    dims =
      MapSet.new(Enum.map(@default_metrics, fn {d, _} -> d end))
      |> MapSet.union(MapSet.new(Map.keys(overrides)))
      |> MapSet.union(MapSet.new(Map.keys(bounded)))

    dims
    |> Enum.sort()
    |> Map.new(fn dim ->
      module =
        Map.get(overrides, dim) || Map.get(@default_metrics, dim) || Metric.resolve(dim)

      {dim, module}
    end)
  end

  defp bound_set(opts) do
    Map.merge(@default_bounds, to_map(Map.get(opts, :bounds, %{})))
  end

  defp to_map(map) when is_map(map), do: map
  defp to_map(opts) when is_list(opts), do: Map.new(opts)
  defp to_map(_), do: %{}

  defp measure(metrics, implementation_module, corpus, ctx) do
    Enum.flat_map_reduce(metrics, [], fn {dim, module}, reasons ->
      case guarded_score(module, implementation_module, corpus, ctx) do
        {score, _meta} when is_number(score) and score >= 0 and score <= 1 ->
          {[{dim, score * 1.0}], reasons}

        {score, _meta} when is_number(score) ->
          {[{dim, 0.0}], ["#{dim} out-of-range score #{Runner.format_number(score)}" | reasons]}

        {:refused, term} ->
          {[{dim, 0.0}], ["#{dim} refused: #{inspect(term)}" | reasons]}

        other ->
          {[{dim, 0.0}], ["#{dim} malformed score: #{inspect(other)}" | reasons]}
      end
    end)
  end

  defp guarded_score(module, implementation_module, corpus, ctx) do
    module.score(implementation_module, corpus, ctx)
  rescue
    e -> {:refused, {:metric_raised, module, Exception.message(e)}}
  catch
    :exit, reason -> {:refused, {:metric_exited, module, reason}}
    :throw, value -> {:refused, {:metric_threw, module, value}}
  end

  defp gate(scores, bounds) do
    bounds
    |> Enum.sort()
    |> Enum.reduce({true, []}, fn {dim, bound}, {ok, reasons} ->
      case Map.fetch(scores, dim) do
        {:ok, score} when score >= bound ->
          {ok, reasons}

        {:ok, score} ->
          {false,
           [
             "#{dim} #{Runner.format_number(score)} < bound #{Runner.format_number(bound)}"
             | reasons
           ]}

        :error ->
          {false, ["#{dim} unmeasured against bound #{Runner.format_number(bound)}" | reasons]}
      end
    end)
  end
end
