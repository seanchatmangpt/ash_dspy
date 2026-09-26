defmodule AshDspy.Court.Metrics.Replay do
  @moduledoc """
  Replay dimension: a re-run produces the same output and the implementation
  behaves as a pure function of (inputs, ctx).

  This is a *proxy*, stated honestly. What it can detect:

  - second-run output divergence (replay failure),
  - run errors (raise/exit/throw),
  - process-dictionary writes by the implementation during a run,
  - creation of new ETS tables during a run,
  - leakage of a probe reference planted in the ctx into the output.

  What it cannot detect (known blind spot, recorded): mutations to
  pre-existing external stores -- an ETS table created before the run, an
  agent, a `:persistent_term`, or process state outside the calling process.
  In BEAM terms the corpus and ctx are immutable, so this proxy is the
  strongest structural check available without instrumenting the
  implementation itself.
  """

  @behaviour AshDspy.Court.Metric

  alias AshDspy.Court.Runner

  @probe_key :__ash_dspy_court_replay_probe__

  @impl true
  def dimension, do: :replay

  @impl true
  def score(implementation_module, corpus, ctx) when is_list(corpus) do
    if corpus == [] do
      {0.0, %{examples: 0, impure: []}}
    else
      probe = make_ref()
      probe_ctx = Map.put(ctx, @probe_key, probe)
      {pure?, evidence} = walk(implementation_module, corpus, probe_ctx, probe, true, [])
      score = if pure?, do: 1.0, else: 0.0
      {score, %{examples: length(corpus), impure: Enum.reverse(evidence)}}
    end
  end

  def score(_implementation_module, _corpus, _ctx), do: {:refused, :corpus_not_a_list}

  defp walk(_impl, [], _probe_ctx, _probe, pure?, evidence), do: {pure?, evidence}

  defp walk(impl, [example | rest], probe_ctx, probe, pure?, evidence) do
    case example_verdict(impl, example, probe_ctx, probe) do
      :pure -> walk(impl, rest, probe_ctx, probe, pure?, evidence)
      {:impure, detail} -> walk(impl, rest, probe_ctx, probe, false, [detail | evidence])
    end
  end

  defp example_verdict(impl, example, probe_ctx, probe) do
    case example do
      %{inputs: inputs} when is_map(inputs) ->
        pdict_before = :erlang.get()
        ets_before = length(:ets.all())

        first = Runner.run(impl, inputs, probe_ctx)
        second = Runner.run(impl, inputs, probe_ctx)

        pdict_after = :erlang.get()
        ets_after = length(:ets.all())

        cond do
          match?({{:ok, _}, {:ok, _}}, {first, second}) ->
            {:ok, out_a} = first
            {:ok, out_b} = second

            cond do
              Runner.normalize_output(out_a) != Runner.normalize_output(out_b) ->
                {:impure, %{inputs: inputs, cause: :rerun_diverged}}

              pdict_after != pdict_before ->
                {:impure, %{inputs: inputs, cause: :process_dictionary_mutated}}

              ets_after != ets_before ->
                {:impure, %{inputs: inputs, cause: :ets_tables_created}}

              leaks_probe?(out_a, probe) or leaks_probe?(out_b, probe) ->
                {:impure, %{inputs: inputs, cause: :ctx_probe_leaked_into_output}}

              true ->
                :pure
            end

          true ->
            {:impure, %{inputs: inputs, cause: :run_error}}
        end

      _ ->
        {:impure, %{example: example, cause: :malformed_example}}
    end
  end

  defp leaks_probe?(output, probe) do
    output
    |> inspect(limit: :infinity)
    |> String.contains?(inspect(probe))
  end
end
