defmodule AshDspy.Compiler do
  @moduledoc """
  `AshDspy.Compiler.compile/3` — the DSPy compilation pipeline.

      compile(program_or_signature_id_or_resource, corpus, opts)
        :: {:ok, route} | {:refused, term}

  where `route` is an `%AshDspy.Runtime.Route{}` (lane-3 contract; referenced only
  dynamically, see "Foreign-lane race policy" below).

  ## Pipeline

    1. Normalize the corpus — a list of `%{signature: binary | atom, inputs: map,
       outputs: map}`. An empty corpus refuses `:empty_corpus`. Missing `:inputs`/
       `:outputs` default to `%{}`; atom and string keys are both accepted and
       normalized.
    2. Enumerate candidate implementation modules in lattice order
       (`AshDspy.Compiler.Candidate`), probing eligibility. A candidate that refuses
       for missing config is `:not_eligible`, not an error.
    3. Evaluate each eligible candidate in ascending intelligence via
       `AshDspy.Court.evaluate(module, corpus, metric_opts, ctx)` (lane-5 contract:
       returns a `%AshDspy.Court.Verdict{}` with `:scores`, `:passed`, `:reasons`,
       `:digest`).
    4. Select the LOWEST-intelligence candidate whose verdict passed.
    5. Build the Route: `signature_id`, `implementation_module`, `class`,
       `evidence_digest` (sha256 over canonical corpus JSON + verdict digest), 
       `court_verdict`, `standing: :compiled`.

  ## Idempotence

  The same corpus + config yields a byte-identical Route: the corpus is canonically
  serialized (`AshDspy.Compiler.Canonical`) before digesting — invariant to corpus
  entry order and to atom/binary spelling of keys, signatures, and values.

  ## Typed refusals (tagged tuples only; the pipeline never raises)

    * `{:refused, :empty_corpus}`
    * `{:refused, :no_eligible_candidates}` — nothing enumerated (lattice absent) or
      every candidate refused config
    * `{:refused, {:no_qualifying_implementation, details}}` — candidates evaluated,
      none passed; `details` is `%{candidates: [...]}` listing per-candidate class,
      module, pass state and verdict reasons
    * `{:refused, :court_unavailable}` — `AshDspy.Court` not yet compiled (lane-5 race)
    * `{:refused, :route_unavailable}` — `AshDspy.Runtime.Route` not yet compiled
      (lane-3 race)
    * `{:refused, {:invalid_program, term}}`, `{:refused, {:invalid_corpus, term}}`,
      `{:refused, {:invalid_corpus_entry, entry, problem}}` — malformed inputs
    * `{:refused, {:no_signature_found | {:ambiguous_signatures, names} |
       {:unknown_signature, sig, names}, ...}}` — resource program resolution
    * `{:refused, {:route_fields_missing, keys}}` — landed Route struct drifted from
      the pinned field contract
    * `{:refused, {:compiler_exception, message}}` (or `{:compiler_threw, _}` /
      `{:compiler_exit, _}`) — last-resort guard; nothing escapes untagged

  ## Foreign-lane race policy

  Lane 3/5 modules (`AshDspy.Runtime.*`, `AshDspy.Court.*`) are referenced only
  dynamically (`Code.ensure_loaded?/1`, `function_exported?/3`, `apply/3`), never via
  compile-time remote calls or struct expansion, so this file compiles standalone and
  picks the real modules up once they land. `AshDspy.Resource.Info`/`Resource` structs
  are compiled in-repo and are referenced statically.

  ## opts

    * `:impl_config` — passed through to candidates and the Court via ctx
    * `:metric` — metric module handed to the Court (default
      `AshDspy.Court.Metrics.Accuracy`)
    * `:max_candidates` — cap on eligible candidates evaluated, in lattice order
      (lowest intelligence first)
    * `:signature` — when `program` is a resource declaring several signatures, picks
      one by name
  """

  alias AshDspy.Compiler.{Candidate, Canonical}
  alias AshDspy.Resource.Info

  @court AshDspy.Court
  @route AshDspy.Runtime.Route
  @default_metric AshDspy.Court.Metrics.Accuracy

  @route_fields [
    :signature_id,
    :implementation_module,
    :class,
    :evidence_digest,
    :court_verdict,
    :standing
  ]

  @typedoc "Lane-3 Route struct, bound by contract and resolved dynamically."
  @type route :: term()

  @typedoc "Every failure is a typed tagged tuple; nothing raises."
  @type refusal :: {:refused, term()}

  @doc """
  Compiles the lowest-intelligence implementation that passes the Court over `corpus`.

  `program` may be a signature id (atom or binary) or an `ash_dspy`-compiled resource
  module (its `dspy` signatures are read via `AshDspy.Resource.Info.dspy/1`).
  """
  @spec compile(term(), term(), keyword()) :: {:ok, route()} | refusal()
  def compile(program, corpus, opts \\ [])

  def compile(_program, [], _opts), do: {:refused, :empty_corpus}

  def compile(program, corpus, opts) when is_list(corpus) do
    with {:ok, signature_id} <- resolve_program(program, opts),
         {:ok, entries} <- normalize_corpus(corpus) do
      run_pipeline(signature_id, entries, opts)
    end
  rescue
    error -> {:refused, {:compiler_exception, Exception.message(error)}}
  catch
    :throw, value -> {:refused, {:compiler_threw, value}}
    :exit, reason -> {:refused, {:compiler_exit, reason}}
  end

  def compile(_program, corpus, _opts), do: {:refused, {:invalid_corpus, corpus}}

  ## program resolution

  defp resolve_program(program, _opts) when is_binary(program) do
    {:ok, normalize_signature_id(program)}
  end

  defp resolve_program(program, opts) when is_atom(program) and not is_boolean(program) do
    if resource_compiled?(program) do
      resolve_resource(program, opts)
    else
      {:ok, program}
    end
  end

  defp resolve_program(other, _opts), do: {:refused, {:invalid_program, other}}

  defp normalize_signature_id(id) when is_binary(id) do
    String.to_existing_atom(id)
  rescue
    _ -> id
  end

  defp resource_compiled?(module) do
    Code.ensure_loaded?(module) and Info.compiled?(module)
  rescue
    _ -> false
  end

  defp resolve_resource(resource, opts) do
    names =
      resource
      |> Info.dspy()
      |> List.wrap()
      |> Enum.filter(&match?(%AshDspy.Resource.Signature{}, &1))
      |> Enum.map(& &1.name)

    cond do
      names == [] ->
        {:refused, :no_signature_found}

      length(names) == 1 ->
        {:ok, hd(names)}

      true ->
        case Keyword.fetch(opts, :signature) do
          {:ok, signature} ->
            if signature in names do
              {:ok, signature}
            else
              {:refused, {:unknown_signature, signature, names}}
            end

          :error ->
            {:refused, {:ambiguous_signatures, names}}
        end
    end
  end

  ## corpus normalization

  defp normalize_corpus(corpus) do
    corpus
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case normalize_entry(entry) do
        {:ok, normalized} ->
          {:cont, {:ok, [normalized | acc]}}

        {:refused, problem} ->
          {:halt, {:refused, {:invalid_corpus_entry, entry, problem}}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      refused -> refused
    end
  end

  defp normalize_entry(entry) when is_map(entry) and not is_struct(entry) do
    signature = fetch_any(entry, [:signature, "signature"])
    inputs = fetch_any(entry, [:inputs, "inputs"])
    outputs = fetch_any(entry, [:outputs, "outputs"])

    with {:present, signature} when not is_nil(signature) <- {:present, signature},
         {:ok, signature} <- normalize_entry_signature(signature),
         {:ok, inputs} <- map_or_empty(inputs, :inputs),
         {:ok, outputs} <- map_or_empty(outputs, :outputs) do
      {:ok, %{signature: signature, inputs: inputs, outputs: outputs}}
    else
      {:present, nil} -> {:refused, :missing_signature}
      {:refused, problem} -> {:refused, problem}
    end
  end

  defp normalize_entry(_entry), do: {:refused, :not_a_map}

  defp normalize_entry_signature(signature) when is_atom(signature), do: {:ok, signature}

  defp normalize_entry_signature(signature) when is_binary(signature),
    do: {:ok, normalize_signature_id(signature)}

  defp normalize_entry_signature(other),
    do: {:refused, {:signature_not_atom_or_binary, other}}

  defp map_or_empty(nil, _field), do: {:ok, %{}}
  defp map_or_empty(map, _field) when is_map(map) and not is_struct(map), do: {:ok, map}
  defp map_or_empty(other, field), do: {:refused, {field, :not_a_map, other}}

  defp fetch_any(map, keys), do: Enum.find_value(keys, &Map.get(map, &1))

  ## pipeline

  defp run_pipeline(signature_id, entries, opts) do
    ctx = %{
      signature_id: signature_id,
      impl_config: Keyword.get(opts, :impl_config)
    }

    metric = Keyword.get(opts, :metric, @default_metric)
    metric_opts = [metric: metric]

    with {:court, true} <- {:court, court_available?()} do
      eligible =
        Candidate.enumerate(ctx)
        |> Enum.filter(&(&1.status == :eligible))
        |> limit(opts)

      cond do
        eligible == [] ->
          {:refused, :no_eligible_candidates}

        true ->
          case evaluate_all(eligible, entries, metric_opts, ctx) do
            {:ok, winner} ->
              build_route(signature_id, winner, entries)

            {:none_passed, results} ->
              {:refused, {:no_qualifying_implementation, %{candidates: results}}}
          end
      end
    else
      {:court, false} -> {:refused, :court_unavailable}
    end
  end

  defp court_available? do
    Code.ensure_loaded?(@court) and function_exported?(@court, :evaluate, 4)
  end

  defp limit(candidates, opts) do
    case Keyword.fetch(opts, :max_candidates) do
      {:ok, n} when is_integer(n) and n >= 0 -> Enum.take(candidates, n)
      _ -> candidates
    end
  end

  defp evaluate_all(candidates, entries, metric_opts, ctx) do
    results =
      Enum.map(candidates, fn candidate ->
        {candidate, evaluate_candidate(candidate, entries, metric_opts, ctx)}
      end)

    case Enum.find(results, fn {_candidate, verdict} -> verdict_state(verdict) == :passed end) do
      {candidate, verdict} ->
        {:ok, %{candidate: candidate, verdict: verdict, digest: verdict_digest(verdict)}}

      nil ->
        {:none_passed, Enum.map(results, &summarize/1)}
    end
  end

  defp evaluate_candidate(candidate, entries, metric_opts, ctx) do
    case apply(@court, :evaluate, [candidate.module, entries, metric_opts, ctx]) do
      {:ok, verdict} when is_map(verdict) -> verdict
      verdict when is_map(verdict) -> verdict
      other -> {:invalid_verdict, other}
    end
  rescue
    error -> {:court_raise, Exception.message(error)}
  end

  # Verdict fields are read dynamically (Map.get) so no lane-5 struct is ever expanded
  # at this module's compile time.
  defp verdict_state(verdict) when is_map(verdict) do
    if Map.get(verdict, :passed) in [true, :passed], do: :passed, else: :failed
  end

  defp verdict_state(_verdict), do: :failed

  defp verdict_digest(verdict) when is_map(verdict), do: Map.get(verdict, :digest)
  defp verdict_digest(_verdict), do: nil

  defp summarize({candidate, verdict}) do
    %{
      class: candidate.class,
      module: candidate.module,
      status: candidate.status,
      reason: Map.get(candidate, :reason),
      passed: verdict_state(verdict) == :passed,
      reasons: reasons(verdict),
      error: error_of(verdict)
    }
  end

  defp reasons(verdict) when is_map(verdict), do: List.wrap(Map.get(verdict, :reasons, []))
  defp reasons(_verdict), do: []

  defp error_of({tag, _} = error) when is_atom(tag) and not is_map(error), do: error
  defp error_of(_verdict), do: nil

  ## route construction

  defp build_route(signature_id, winner, entries) do
    if Code.ensure_loaded?(@route) do
      build_route_fields(signature_id, winner, entries)
    else
      {:refused, :route_unavailable}
    end
  end

  defp build_route_fields(signature_id, winner, entries) do
    empty = apply(@route, :__struct__, [])
    missing = Enum.reject(@route_fields, &Map.has_key?(empty, &1))

    if missing == [] do
      evidence_digest = Canonical.evidence_digest(entries, winner.digest)

      route =
        empty
        |> Map.put(:signature_id, signature_id)
        |> Map.put(:implementation_module, winner.candidate.module)
        |> Map.put(:class, winner.candidate.class)
        |> Map.put(:evidence_digest, evidence_digest)
        |> Map.put(:court_verdict, winner.verdict)
        |> Map.put(:standing, :compiled)

      {:ok, route}
    else
      {:refused, {:route_fields_missing, missing}}
    end
  end
end
