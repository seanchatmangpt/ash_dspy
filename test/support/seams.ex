defmodule AshDspy.TestSupport.Seams do
  @moduledoc """
  Lane 9 seam isolators.

  Lanes 3-8 land their lib/ modules in parallel with this test wave, so every
  place where the pinned contract leaves a sibling-shaped hole (return-tuple
  vs bare struct, option key names, sink paths) is isolated HERE. Rebinding a
  seam after a sibling lands = edit this file + the marked assertions, not the
  whole suite.
  """

  alias AshDspy.Runtime.Route
  alias AshDspy.TestSupport.{Corpus, RuleTriage, StubLLM}

  @doc "Program for the triage fixture resource, normalizing the return shape."
  def program do
    program(AshDspy.TestSupport.TriageResource)
  end

  def program(resource) do
    case AshDspy.Runtime.Program.from_resource(resource, []) do
      {:ok, program} ->
        program

      %module{} = program when module == AshDspy.Runtime.Program ->
        program

      other ->
        raise "SEAM(runtime/program): unexpected Program.from_resource/2 shape: #{inspect(other)}"
    end
  end

  @doc """
  Default compile opts: both triage candidates (rule + stub LLM) and the
  injected stub fn under `:llm` (NO network; the fn IS the model).
  """
  def compile_opts(overrides \\ []) do
    Keyword.merge(
      [candidates: [RuleTriage, StubLLM], llm: llm_fn(), rule: {Corpus, :triage}],
      overrides
    )
  end

  @doc "Injectable stub LLM fn: returns the RULE-correct output for any ticket."
  def llm_fn do
    fn input, _ctx ->
      {:ok, Corpus.triage(ticket_of(input))}
    end
  end

  @doc """
  Divergent-taught stub LLM fn: answers EXACTLY the divergent corpus's
  expected values (which break the rule), keyed by ticket text.
  """
  def divergent_llm_fn do
    answers =
      Map.new(Corpus.divergent_corpus(), fn %{input: input, expected: expected} ->
        {input.ticket, expected}
      end)

    fn input, _ctx ->
      case Map.fetch(answers, ticket_of(input)) do
        {:ok, expected} -> {:ok, expected}
        :error -> {:refused, :unknown_input}
      end
    end
  end

  @doc "A hand-built Route -- every field of the pinned defstruct."
  def route(opts \\ []) do
    struct!(
      Route,
      Keyword.merge(
        [
          signature_id: :triage_ticket,
          implementation_module: RuleTriage,
          class: :rule,
          evidence_digest: "sha256:" <> String.duplicate("a", 64),
          court_verdict: verdict(true),
          standing: :candidate
        ],
        opts
      )
    )
  end

  @doc "A hand-built Court.Verdict with the five ontology dimensions."
  def verdict(passed) when is_boolean(passed) do
    struct(
      AshDspy.Court.Verdict,
      scores: %{
        accuracy: if(passed, do: 1.0, else: 0.0),
        determinism: 1.0,
        replay: 1.0,
        provenance: 1.0,
        llm_residue: 0.0
      },
      passed: passed,
      reasons: if(passed, do: [], do: ["accuracy below bound"]),
      digest: "sha256:" <> String.duplicate(String.downcase(Integer.to_string(passed, 36)), 64)
    )
  end

  @doc "Extracts the typed refusal reason from {:refused, _} | {:error, _}."
  def refusal({:refused, reason}), do: reason
  def refusal({:error, reason}), do: reason

  def refusal(other),
    do: raise("SEAM(refusal): expected {:refused, _} or {:error, _}, got: #{inspect(other)}")

  # ── Ocel sink discovery ──────────────────────────────────────────────────

  @doc """
  Emits one Ocel event carrying `marker` plus a token-ish key with a secret
  value, then locates the JSON line in whatever sink the module uses.
  Returns {path, decoded_line_map}.
  """
  def emit_and_locate(marker) do
    secret = "sk-SUPERSECRET-#{marker}"

    result =
      AshDspy.Ocel.emit_event("lane9_test_activity", "lane9_test_object", %{
        marker: marker,
        api_key: secret,
        auth_token: secret,
        password: secret
      })

    path =
      case result do
        {:ok, %AshDspy.Ocel.Event{}} -> default_paths() |> Enum.find(&File.exists?/1)
        {:ok, path} when is_binary(path) -> path
        {:ok, %{path: path}} when is_binary(path) -> path
        %AshDspy.Ocel.Event{} -> default_paths() |> Enum.find(&File.exists?/1)
        :ok -> default_paths() |> Enum.find(&File.exists?/1)
        other -> raise "SEAM(ocel/emit): unexpected emit_event/3 shape: #{inspect(other)}"
      end

    case path do
      nil ->
        raise """
        SEAM(ocel/sink): could not locate the Ocel JSONL sink.
        emit_event/3 returned: #{inspect(result)}
        searched: #{inspect(default_paths())}
        """

      path ->
        line =
          path
          |> File.read!()
          |> String.split("\n", trim: true)
          |> Enum.map(&Jason.decode!/1)
          |> Enum.find(fn event -> event_includes_marker?(event, marker) end)

        {path, line, secret}
    end
  end

  defp event_includes_marker?(event, marker) when is_map(event) do
    inspect(event) =~ to_string(marker)
  end

  defp default_paths do
    app_env = Application.get_env(:ash_dspy, :ocel_path)

    [
      app_env,
      Path.expand("log/ocel.ndjson"),
      Path.expand("ocel.ndjson"),
      Path.expand("log/ash_dspy_ocel.ndjson"),
      Path.expand("priv/ocel.ndjson"),
      Path.join(System.tmp_dir!(), "ash_dspy_ocel.ndjson")
    ]
    |> Enum.reject(&is_nil/1)
  end

  # ── Traces file plumbing ─────────────────────────────────────────────────

  @doc "priv/corpus/triage/ (lane 6) corpus file paths, when lane 6 has landed."
  def corpus_file_paths do
    dir = Path.expand("priv/corpus/triage", File.cwd!())

    case File.ls(dir) do
      {:ok, files} -> dir |> String.graphemes() |> List.to_string() |> dir_paths(files)
      _ -> []
    end
  end

  defp dir_paths(dir, files),
    do: Enum.map(files, fn f -> Path.join(dir, f) end) |> Enum.filter(&String.ends_with?(&1, ".jsonl"))

  defp ticket_of(%{ticket: t}) when is_binary(t), do: t
  defp ticket_of(%{"ticket" => t}) when is_binary(t), do: t
  defp ticket_of(other) when is_map(other), do: other |> inspect() |> Corpus.triage() |> then(fn _ -> "" end)
end
