defmodule AshDspy.Court.Metrics.Determinism do
  @moduledoc """
  Determinism dimension: each corpus input is run twice and both runs must
  produce structurally identical outputs.

  The ctx map is passed unchanged to both runs; Elixir term immutability makes
  each call a fresh snapshot of the context. Any run error (raise/exit/throw),
  any refusal-shaped result, or any divergence scores 0.0. An empty corpus
  scores 0.0; the court short-circuits empty corpora before scoring.
  """

  @behaviour AshDspy.Court.Metric

  alias AshDspy.Court.Runner

  @impl true
  def dimension, do: :determinism

  @impl true
  def score(implementation_module, corpus, ctx) when is_list(corpus) do
    total = length(corpus)

    if total == 0 do
      {0.0, %{pairs: 0, diverged: []}}
    else
      {stable?, diverged} =
        Enum.reduce(corpus, {true, []}, fn example, {stable?, diverged} ->
          case pair_verdict(implementation_module, example, ctx) do
            :same ->
              {stable?, diverged}

            {:different, detail} ->
              {false, [detail | diverged]}
          end
        end)

      score = if stable?, do: 1.0, else: 0.0
      {score, %{pairs: total, diverged: Enum.reverse(diverged)}}
    end
  end

  def score(_implementation_module, _corpus, _ctx), do: {:refused, :corpus_not_a_list}

  defp pair_verdict(implementation_module, example, ctx) do
    case example do
      %{inputs: inputs} when is_map(inputs) ->
        first = Runner.run(implementation_module, inputs, ctx)
        second = Runner.run(implementation_module, inputs, ctx)

        case {first, second} do
          {{:ok, a}, {:ok, b}} ->
            if Runner.normalize_output(a) == Runner.normalize_output(b) do
              :same
            else
              {:different, %{inputs: inputs, cause: :outputs_diverged}}
            end

          _ ->
            {:different, %{inputs: inputs, cause: :run_error}}
        end

      _ ->
        {:different, %{example: example, cause: :malformed_example}}
    end
  end
end
