# examples/ticket_triage.exs
#
# End-to-end ash_dspy demo:
#
#   1. Define the demo `:triage` signature on an INLINE Ash.Resource host
#      (`AshDspy.Resource` is a resource extension, so the host is required;
#      no repo/DB is ever touched -- only the DSL surface + runtime).
#   2. Load priv/corpus/triage/triage_corpus.jsonl via AshDspy.Traces.import_jsonl/2.
#      While that corpus file has not landed, the script falls back to a small
#      INLINE demo corpus and says so honestly.
#   3. Install a deterministic plain-fn rule implementation under
#      opts :impl_config -> AshDspy.Runtime.Implementations.Rule :apply mode.
#   4. AshDspy.Compiler.compile/3 -> print the Route (court must select :rule,
#      the lowest-intelligence class that passes).
#   5. REPLAY: re-run compile and assert an identical evidence_digest.
#   6. Project the SA2A capability card (AshDspy.SA2A.project/2 over the
#      Runtime.Program bound to the Route).
#   7. Seal an AshDspy.Receipt.for_route/2 (verdict digest = replay binding).
#   8. Print a summary block (route class, verdict scores, receipt id, card iri).
#
# Run:
#
#   MIX_BUILD_ROOT=_build-lane10 mix run examples/ticket_triage.exs
#
# The script NEVER raises: every stage is guarded, and a missing sibling or
# corpus prints `{:refused, term}` honestly and degrades.

defmodule AshDspyExamples.TriageRules do
  @moduledoc """
  Deterministic keyword triage rules -- the plain-fn implementation handed to
  the compiler as `impl_config: [apply: &triage/1]`. The intelligence lattice
  ranks `:rule` third (reuse, compose, rule, ...), so when a rule expresses
  the capability the court must select the rule and `Allocation_LLM` is 0.
  """

  @outage_words ~w(outage down unavailable cannot-connect cant-connect production-down)
  @bug_words ~w(bug error crash exception traceback broken fails failure stacktrace)
  @feature_words ~w(feature request enhancement add-support would-be-nice roadmap)
  @question_words ~w(question how-do how-can docs documentation)

  @doc "1-arity `(input_map) -> output_map` rule fn (Rule :apply mode)."
  def triage(input) do
    text = input |> text_of() |> String.downcase()

    cond do
      any_word?(text, @outage_words) -> %{category: "outage", confidence: 95}
      any_word?(text, @bug_words) -> %{category: "bug", confidence: 88}
      any_word?(text, @feature_words) -> %{category: "feature", confidence: 90}
      any_word?(text, @question_words) -> %{category: "question", confidence: 92}
      true -> %{category: "other", confidence: 80}
    end
  end

  # Tolerant input reader: flat atom- or string-key maps, or an :input envelope.
  defp text_of(input) when is_map(input) do
    keys = [:ticket_text, "ticket_text", :text, "text"]

    flat_value(input, keys) ||
      case flat_value(input, [:input, "input"]) do
        %{} = nested -> flat_value(nested, keys) || ""
        nil -> ""
        other -> to_string(other)
      end
      |> to_string()
  end

  defp text_of(other), do: to_string(other || "")

  defp flat_value(map, keys) when is_map(map) do
    Enum.find_value(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} -> value
        :error -> nil
      end
    end)
  end

  defp any_word?(text, words) do
    Enum.any?(words, fn word -> String.contains?(text, String.replace(word, "-", " ")) end)
  end
end

defmodule AshDspyExamples.Support do
  @moduledoc false

  # Runs a stage, converting any raise/exit into {:refused, term}.
  def stage(label, fun) do
    result =
      try do
        {:ok, fun.()}
      rescue
        e -> {:refused, {:raised, label, Exception.message(e)}}
      catch
        :exit, reason -> {:refused, {:exited, label, reason}}
      end

    IO.puts("[#{label}] #{inspect(result, limit: 20)}")
    result
  end

  def field(map, key, default \\ nil)

  def field(map, key, default) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> default
    end
  end

  def field(_other, _key, default), do: default

  def loaded?(module), do: Code.ensure_loaded?(module)

  def show(nil), do: "(absent)"
  def show(value), do: inspect(value)
end

defmodule AshDspyExamples.Runner do
  @moduledoc false

  import AshDspyExamples.Support, only: [stage: 2, field: 2, field: 3, loaded?: 1, show: 1]

  alias AshDspyExamples.TriageRules

  @corpus_path "priv/corpus/triage/triage_corpus.jsonl"
  @resource AshDspyExamples.TicketTriage
  @signature :triage
  @impl_config [apply: &TriageRules.triage/1]

  # Inline demo corpus used ONLY when the corpus file has not landed yet.
  # Outputs are atom-key maps exactly matching the rule's deterministic
  # outputs, which is what AshDspy.Court.Metrics.Accuracy requires
  # (structural equality). The court still verifies every entry.
  @inline_corpus [
    %{signature: @signature, inputs: %{ticket_text: "Production outage: API returns 500 for all requests"},
      outputs: %{category: "outage", confidence: 95}},
    %{signature: @signature, inputs: %{ticket_text: "App crashes on login with a stacktrace"},
      outputs: %{category: "bug", confidence: 88}},
    %{signature: @signature, inputs: %{ticket_text: "Feature request: add support for SSO"},
      outputs: %{category: "feature", confidence: 90}},
    %{signature: @signature, inputs: %{ticket_text: "Question: how do I rotate the API keys?"},
      outputs: %{category: "question", confidence: 92}},
    %{signature: @signature, inputs: %{ticket_text: "The service is down and customers cannot connect"},
      outputs: %{category: "outage", confidence: 95}},
    %{signature: @signature, inputs: %{ticket_text: "Typo in the readme"},
      outputs: %{category: "other", confidence: 80}}
  ]

  def run do
    resource_stage()
    corpus_result = corpus_stage()
    IO.puts("[ctx] impl_config: #{inspect(@impl_config)} (rule fn under Rule :apply mode)")

    smoke = TriageRules.triage(%{ticket_text: "Production outage: API returns 500"})
    IO.puts("[ctx] rule smoke test: #{inspect(smoke)}")

    compile_result = compile_stage(corpus_result)
    replay_result = replay_stage(corpus_result, compile_result)
    card_result = card_stage(compile_result)
    receipt_result = receipt_stage(compile_result)

    summary(compile_result, replay_result, card_result, receipt_result)
    :ok
  end

  # -- 1. inline demo resource -------------------------------------------------

  defp resource_stage do
    stage("resource", fn ->
      defmodule Elixir.AshDspyExamples.TicketTriage do
        @moduledoc "Demo host resource for the :triage signature (defined INLINE in this example)."

        use Ash.Resource,
          domain: nil,
          extensions: [AshDspy.Resource]

        attributes do
          uuid_primary_key :id
        end

        dspy do
          default_metric :accuracy
          default_minimize :token_cost

          signature :triage do
            description "Classify a support ticket into a category with a confidence score."
          end

          input :ticket_text, :string, doc: "The raw ticket body."
          input :component_hint, :string, doc: "Optional component hint.", required: false
          output :category, :string
          output :confidence, :integer
          metric :exact_match, :accuracy
          requirement :accuracy, :gte, bound: 90
          minimize :token_cost
        end
      end

      entities =
        if loaded?(AshDspy.Resource.Info), do: AshDspy.Resource.Info.dspy(@resource), else: []

      %{
        resource: @resource,
        extensions: Spark.extensions(@resource),
        entity_count: length(entities),
        signature: @signature
      }
    end)

    :ok
  end

  # -- 2. trace corpus (Traces.import_jsonl, inline fallback while file absent) --

  defp corpus_stage do
    result =
      stage("traces", fn ->
        cond do
          not loaded?(AshDspy.Traces) ->
            {:refused, {:missing_module, AshDspy.Traces}}

          true ->
            AshDspy.Traces.import_jsonl(@corpus_path)
        end
      end)

    case result do
      {:ok, {:ok, corpus}} ->
        IO.puts("[traces] corpus loaded from #{@corpus_path} (#{length(corpus)} examples)")
        {:ok, %{source: {:file, @corpus_path}, corpus: corpus}}

      {:ok, {:refused, reason}} ->
        IO.puts(
          "[traces] corpus file unavailable (#{inspect(reason)}); using INLINE demo corpus (#{length(@inline_corpus)} examples)"
        )

        {:ok, %{source: :inline_fallback, corpus: @inline_corpus}}

      {:refused, reason} = refused ->
        IO.puts("[traces] degrading to INLINE demo corpus after: #{inspect(reason)}")
        {:ok, %{source: :inline_fallback, corpus: @inline_corpus, refused: refused}}
    end
  end

  # -- 4. compile ------------------------------------------------------------------

  defp compile_stage(corpus_result) do
    corpus = field(corpus_result, :corpus, [])

    stage("compile", fn ->
      cond do
        not loaded?(AshDspy.Compiler) ->
          {:refused, {:missing_module, AshDspy.Compiler}}

        true ->
          AshDspy.Compiler.compile(@resource, corpus, impl_config: @impl_config)
      end
    end)
  end

  defp rerun_compile(corpus) do
    AshDspy.Compiler.compile(@resource, corpus, impl_config: @impl_config)
  end

  # -- 5. replay (identical evidence_digest) -----------------------------------------

  defp replay_stage(corpus_result, {:ok, %{} = route}) do
    corpus = field(corpus_result, :corpus, [])

    stage("replay", fn ->
      digest_before = field(route, :evidence_digest)

      cond do
        is_nil(digest_before) ->
          {:refused, :no_evidence_digest_on_route}

        true ->
          case rerun_compile(corpus) do
            {:ok, replayed} ->
              digest_after = field(replayed, :evidence_digest)

              if digest_before == digest_after do
                {:ok, %{digest: digest_before, replay_digest: digest_after, verdict: :identical}}
              else
                {:ok, %{digest: digest_before, replay_digest: digest_after, verdict: :DIVERGED}}
              end

            {:refused, _} = refused ->
              {:refused, {:replay_refused, refused}}
          end
      end
    end)
  end

  defp replay_stage(_corpus_result, _), do: stage("replay", fn -> {:refused, :no_route_available} end)

  # -- 6. SA2A capability card (Runtime.Program bound to the Route) --------------------

  defp card_stage({:ok, %{} = route}) do
    stage("sa2a", fn ->
      cond do
        not loaded?(AshDspy.SA2A) ->
          {:refused, {:missing_module, AshDspy.SA2A}}

        not loaded?(AshDspy.Runtime.Program) ->
          {:refused, {:missing_module, AshDspy.Runtime.Program}}

        true ->
          with {:ok, program} <- AshDspy.Runtime.Program.from_resource(@resource, @signature) do
            AshDspy.SA2A.project(program, route)
          end
      end
    end)
  end

  defp card_stage(_), do: stage("sa2a", fn -> {:refused, :no_route_available} end)

  # -- 7. receipt (verdict digest = replay binding) --------------------------------------

  defp receipt_stage({:ok, %{} = route}) do
    stage("receipt", fn ->
      verdict = field(route, :court_verdict)
      verdict_digest = field(verdict, :digest)

      cond do
        not loaded?(AshDspy.Receipt) ->
          {:refused, {:missing_module, AshDspy.Receipt}}

        is_nil(verdict_digest) ->
          {:refused, :no_verdict_digest}

        true ->
          AshDspy.Receipt.for_route(route,
            verdict_digest: verdict_digest,
            scores: field(verdict, :scores, %{})
          )
      end
    end)
  end

  defp receipt_stage(_), do: stage("receipt", fn -> {:refused, :no_route_available} end)

  # -- summary -------------------------------------------------------------------------------

  defp summary(compile_result, replay_result, card_result, receipt_result) do
    route = value_map(compile_result)
    card = value_map(card_result)
    receipt = value_map(receipt_result)
    replay = value_map(replay_result)
    verdict = field(route, :court_verdict)

    IO.puts("")
    IO.puts("==== ash_dspy ticket triage -- summary ====")
    IO.puts("signature        : #{show(field(route, :signature_id))}")
    IO.puts("route class      : #{show(field(route, :class))} (#{show(field(route, :implementation_module))})")
    IO.puts("standing         : #{show(field(route, :standing))}")
    IO.puts("verdict scores   : #{show(field(verdict, :scores))}")
    IO.puts("verdict passed   : #{show(field(verdict, :passed))}")
    IO.puts("evidence_digest  : #{digest_line(replay)}")
    IO.puts("replay verdict   : #{show(field(replay, :verdict))}")
    IO.puts("receipt id       : #{show(field(receipt, :receipt_id))}")
    IO.puts("card iri         : #{show(field(card, :capability_iri))}")
    IO.puts("===========================================")
  end

  defp value({:ok, value}), do: value
  defp value(_), do: nil

  defp value_map(result) do
    case value(result) do
      %{} = map -> map
      _ -> nil
    end
  end

  defp digest_line(replay) do
    case field(replay, :verdict) do
      :identical -> "#{field(replay, :digest)} (identical on replay)"
      nil -> "(absent)"
      _ -> "DIVERGED: #{field(replay, :digest)} vs #{field(replay, :replay_digest)}"
    end
  end
end

case AshDspyExamples.Runner.run() do
  :ok -> :ok
  other -> IO.inspect(other, label: "runner")
end
