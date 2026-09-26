defmodule AshDspy.Court.Metrics.Accuracy do
  @moduledoc """
  Accuracy dimension: fraction of corpus examples where the implementation's
  run output structurally equals the example's `outputs` map.

  Anti-vacuity: a run that raises, exits, throws, returns a non-map where a
  map is expected, or mismatches on any field counts as a miss -- a broken or
  refusing implementation cannot score above 0.0. An empty corpus scores 0.0
  here; the court additionally short-circuits empty corpora before scoring.
  """

  @behaviour AshDspy.Court.Metric

  alias AshDspy.Court.Runner

  @impl true
  def dimension, do: :accuracy

  @impl true
  def score(implementation_module, corpus, ctx) when is_list(corpus) do
    total = length(corpus)

    {hits, misses_meta} =
      Enum.reduce(corpus, {0, []}, fn example, {hits, misses} ->
        if hit?(implementation_module, example, ctx) do
          {hits + 1, misses}
        else
          {hits, [miss_meta(example) | misses]}
        end
      end)

    score = if total == 0, do: 0.0, else: hits * 1.0 / total
    {score, %{hits: hits, total: total, missed_examples: Enum.reverse(misses_meta)}}
  end

  def score(_implementation_module, _corpus, _ctx), do: {:refused, :corpus_not_a_list}

  defp hit?(implementation_module, example, ctx) do
    case example do
      %{inputs: inputs, outputs: expected} when is_map(inputs) and is_map(expected) ->
        case Runner.run(implementation_module, inputs, ctx) do
          {:ok, raw} ->
            Runner.normalize_output(raw) == expected

          {:error, _reason} ->
            false
        end

      _ ->
        false
    end
  end

  defp miss_meta(example) do
    case example do
      %{inputs: inputs} when is_map(inputs) -> %{inputs: inputs, cause: :mismatch_or_error}
      _ -> %{example: example, cause: :malformed_example}
    end
  end
end
