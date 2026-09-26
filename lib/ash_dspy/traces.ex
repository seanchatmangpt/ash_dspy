defmodule AshDspy.Traces do
  @moduledoc """
  Faithful JSONL transport between DSPy-style trace files and corpus examples.

  Corpus example shape (pinned contract, consumed by downstream lanes):

      %{signature: binary() | atom(), inputs: map(), outputs: map()}

  Accepted line shape (DSPy-style JSONL):

      {"signature": "triage", "inputs": {...}, "outputs": {...}}

  Lines may carry extra keys; unknown keys are dropped and counted in the meta
  returned by `import_jsonl_with_meta/2`.

  The `:signature` opt filters the corpus to a single signature and stamps the
  opt value (verbatim, so an atom opt yields atom signatures) onto every kept
  example. Matching compares the string forms, so a binary line signature
  matches an atom opt and vice versa.

  The `:validate` opt takes a spec map mirroring the compiled DSL entities
  (`AshDspy.Resource.Input` defaults `required: true`; `AshDspy.Resource.Output`
  defaults `required: false`; the DSL carries no `one_of` container, so
  `:one_of` is supplied per output field in the spec):

      %{
        inputs: %{ticket: %{}},
        outputs: %{urgency: %{one_of: ["low", "high"]}, team: %{one_of: [...]}}
      }

  Canonical export encoding: one JSON object per line with sorted keys,
  trailing newline at end of file. Determinism holds for objects of at most 31
  keys (small-map term-order iteration, which for binary keys is byte order);
  corpus objects are far below this bound. Signatures are canonicalized to
  binaries on export; import never atomizes (no `String.to_atom/1` on external
  data).

  This module is transport only. It never judges example content beyond the
  optional `:validate` spec, and it is the truth for the Python bridge example
  in `priv/python/sa2a_dspy.py` (that file is documentation, not runtime).
  """

  @known_keys [:signature, :inputs, :outputs]

  @type example :: %{
          required(:signature) => binary() | atom(),
          required(:inputs) => map(),
          required(:outputs) => map()
        }

  @type field_spec :: %{
          optional(:required) => boolean(),
          optional(:one_of) => [term()]
        }

  @type spec :: %{
          optional(:inputs) => %{(atom() | binary()) => field_spec()},
          optional(:outputs) => %{(atom() | binary()) => field_spec()}
        }

  @type meta :: %{
          line_count: non_neg_integer(),
          blank_lines: non_neg_integer(),
          example_count: non_neg_integer(),
          dropped_unknown_keys: non_neg_integer(),
          dropped_by_signature: non_neg_integer()
        }

  @doc """
  Imports DSPy-style JSONL traces into a corpus.

  `path_or_lines` is a file path binary or a list of lines. Returns
  `{:ok, corpus}` or a typed `{:refused, term}`:

    * `{:refused, {:read_error, reason}}` -- path could not be read
    * `{:refused, {:malformed_line, line_no}}` -- line is not valid JSON
    * `{:refused, {:invalid_example, line_no, reason}}` -- JSON parsed but the
      example violates the shape contract or the `:validate` spec
    * `{:refused, {:invalid_opt, opt}}` -- malformed option value
    * `{:refused, :jason_not_available}` -- the optional Jason dep is absent

  An empty file (or one of only blank lines) yields `{:ok, []}`; refusal on an
  empty corpus is the caller's (downstream lane's) decision.

  Options:

    * `:signature` (atom | binary) -- keep only examples of this signature and
      stamp the opt value onto them
    * `:validate` (spec map) -- validate kept examples against the spec
  """
  @spec import_jsonl(binary() | Enumerable.t(), keyword()) ::
          {:ok, [example()]} | {:refused, term()}
  def import_jsonl(path_or_lines, opts \\ []) do
    case import_jsonl_with_meta(path_or_lines, opts) do
      {:ok, corpus, _meta} -> {:ok, corpus}
      {:refused, _reason} = refused -> refused
    end
  end

  @doc """
  Same as `import_jsonl/2` but returns transport meta alongside the corpus:

      {:ok, corpus, %{
        line_count: n, blank_lines: n, example_count: n,
        dropped_unknown_keys: n, dropped_by_signature: n
      }}
  """
  @spec import_jsonl_with_meta(binary() | Enumerable.t(), keyword()) ::
          {:ok, [example()], meta()} | {:refused, term()}
  def import_jsonl_with_meta(path_or_lines, opts \\ []) do
    with :ok <- check_jason(),
         :ok <- check_validate_opt(Keyword.get(opts, :validate)) do
      case read_lines(path_or_lines) do
        {:ok, lines} -> run_import(lines, opts)
        {:error, reason} -> {:refused, {:read_error, reason}}
      end
    end
  end

  @doc """
  Exports a corpus to `path` as canonical JSONL (one object per line, sorted
  keys, trailing newline). Returns `:ok` or `{:error, term}`. An empty corpus
  writes a zero-byte file.
  """
  @spec export_jsonl([example()], binary()) :: :ok | {:error, term()}
  def export_jsonl(corpus, path) when is_list(corpus) and is_binary(path) do
    with :ok <- check_jason(),
         {:ok, reversed_lines} <- encode_lines(corpus) do
      lines = Enum.reverse(reversed_lines)
      iodata = Enum.intersperse(lines, "\n") ++ tail_newline(lines)
      File.write(path, iodata)
    end
  end

  def export_jsonl(_corpus, _path), do: {:error, :invalid_corpus}

  # # # Import internals # # #

  defp check_jason do
    if Code.ensure_loaded?(Jason), do: :ok, else: {:refused, :jason_not_available}
  end

  defp check_validate_opt(nil), do: :ok
  defp check_validate_opt(spec) when is_map(spec), do: :ok
  defp check_validate_opt(_), do: {:refused, {:invalid_opt, :validate}}

  defp read_lines(path) when is_binary(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, String.split(content, "\n")}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_lines(lines) when is_list(lines), do: {:ok, lines}
  defp read_lines(enum), do: {:ok, Enum.to_list(enum)}

  defp run_import(lines, opts) do
    signature_filter = Keyword.get(opts, :signature)
    spec = Keyword.get(opts, :validate)

    empty_meta = %{
      line_count: 0,
      blank_lines: 0,
      example_count: 0,
      dropped_unknown_keys: 0,
      dropped_by_signature: 0
    }

    Enum.reduce_while(Enum.with_index(lines, 1), {:ok, [], empty_meta}, fn {line, line_no},
                                                                           {:ok, examples, meta} ->
      step(line, line_no, examples, meta, signature_filter, spec)
    end)
    |> finish_import()
  end

  defp step(line, line_no, examples, meta, signature_filter, spec) do
    cond do
      line == "" or String.trim_leading(line) == "" ->
        {:cont, {:ok, examples, bump(meta, :blank_lines)}}

      true ->
        case Jason.decode(line) do
          {:error, _} ->
            {:halt, {:refused, {:malformed_line, line_no}}}

          {:ok, value} when is_map(value) ->
            import_object(value, line_no, examples, meta, signature_filter, spec)

          {:ok, _} ->
            {:halt, {:refused, {:invalid_example, line_no, :not_an_object}}}
        end
    end
  end

  defp import_object(object, line_no, examples, meta, signature_filter, spec) do
    dropped = map_size(object) - Enum.count(@known_keys, &known_key_present?(object, &1))

    with {:ok, signature} <- fetch_signature(object, line_no),
         {:ok, inputs} <- fetch_map_field(object, :inputs, line_no),
         {:ok, outputs} <- fetch_map_field(object, :outputs, line_no) do
      cond do
        signature_filter && !sig_match?(signature, signature_filter) ->
          {:cont,
           {:ok, examples,
            meta |> bump(:dropped_by_signature) |> add(:dropped_unknown_keys, dropped)}}

        true ->
          stamped = if signature_filter, do: signature_filter, else: signature
          example = %{signature: stamped, inputs: inputs, outputs: outputs}

          case validate_example(inputs, outputs, spec) do
            :ok ->
              {:cont,
               {:ok, [example | examples],
                meta |> bump(:example_count) |> add(:dropped_unknown_keys, dropped)}}

            {:error, reason} ->
              {:halt, {:refused, {:invalid_example, line_no, {:validation, reason}}}}
          end
      end
    else
      {:refused, reason} -> {:halt, {:refused, reason}}
    end
  end

  defp finish_import({:ok, examples, meta}), do: {:ok, Enum.reverse(examples), meta}
  defp finish_import({:refused, reason}), do: {:refused, reason}

  defp known_key_present?(object, key) do
    Map.has_key?(object, key) or Map.has_key?(object, Atom.to_string(key))
  end

  defp fetch_signature(object, line_no) do
    case fetch_key(object, :signature) do
      :error -> {:refused, {:invalid_example, line_no, :missing_signature}}
      {:ok, sig} when is_atom(sig) or is_binary(sig) -> {:ok, sig}
      {:ok, _} -> {:refused, {:invalid_example, line_no, :invalid_signature}}
    end
  end

  defp fetch_map_field(object, key, line_no) do
    case fetch_key(object, key) do
      :error -> {:refused, {:invalid_example, line_no, :"missing_#{key}"}}
      {:ok, value} when is_map(value) and not is_struct(value) -> {:ok, value}
      {:ok, _} -> {:refused, {:invalid_example, line_no, :"invalid_#{key}"}}
    end
  end

  defp fetch_key(map, key) when is_atom(key) do
    cond do
      Map.has_key?(map, key) -> Map.fetch(map, key)
      Map.has_key?(map, Atom.to_string(key)) -> Map.fetch(map, Atom.to_string(key))
      true -> :error
    end
  end

  defp sig_match?(sig, filter) when sig == filter, do: true

  defp sig_match?(sig, filter) when is_binary(sig) and is_atom(filter),
    do: sig == Atom.to_string(filter)

  defp sig_match?(sig, filter) when is_atom(sig) and is_binary(filter),
    do: filter == Atom.to_string(sig)

  defp sig_match?(_, _), do: false

  # # # Validation (opt-in spec) # # #

  defp validate_example(_inputs, _outputs, nil), do: :ok

  defp validate_example(inputs, outputs, spec) do
    with :ok <- check_inputs(inputs, Map.get(spec, :inputs, %{})),
         :ok <- check_outputs(outputs, Map.get(spec, :outputs, %{})) do
      :ok
    end
  end

  defp check_inputs(inputs, field_specs) do
    Enum.reduce_while(field_specs, :ok, fn {field, field_spec}, :ok ->
      # AshDspy.Resource.Input defaults required: true.
      required? = Map.get(fetch_spec(field_spec), :required, true)

      case fetch_key(inputs, field) do
        {:ok, _} -> {:cont, :ok}
        :error when required? -> {:halt, {:error, {:missing_input, field}}}
        :error -> {:cont, :ok}
      end
    end)
  end

  defp check_outputs(outputs, field_specs) do
    Enum.reduce_while(field_specs, :ok, fn {field, field_spec}, :ok ->
      fspec = fetch_spec(field_spec)

      case fetch_key(outputs, field) do
        {:ok, value} ->
          case Map.fetch(fspec, :one_of) do
            {:ok, allowed} when is_list(allowed) ->
              if value in allowed do
                {:cont, :ok}
              else
                {:halt, {:error, {:value_not_in_one_of, field, value}}}
              end

            _ ->
              {:cont, :ok}
          end

        :error ->
          # AshDspy.Resource.Output defaults required: false.
          if Map.get(fspec, :required, false),
            do: {:halt, {:error, {:missing_output, field}}},
            else: {:cont, :ok}
      end
    end)
  end

  defp fetch_spec(spec) when is_map(spec), do: spec
  defp fetch_spec(_), do: %{}

  # # # Export internals # # #

  defp encode_lines(corpus) do
    Enum.reduce_while(corpus, {:ok, []}, fn example, {:ok, acc} ->
      case encode_line(example) do
        {:ok, line} -> {:cont, {:ok, [line | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp tail_newline([]), do: []
  defp tail_newline(_lines), do: ["\n"]

  defp encode_line(example) when is_map(example) do
    with {:ok, signature} <- export_signature(example),
         {:ok, inputs} <- export_map_field(example, :inputs),
         {:ok, outputs} <- export_map_field(example, :outputs) do
      line =
        canonicalize_line(%{"signature" => signature, "inputs" => inputs, "outputs" => outputs})

      case line do
        {:ok, ordered} -> Jason.encode(ordered)
        {:error, _} = error -> error
      end
    end
  end

  defp encode_line(_example), do: {:error, :invalid_example}

  defp export_signature(example) do
    case fetch_key(example, :signature) do
      {:ok, sig} when is_atom(sig) -> {:ok, Atom.to_string(sig)}
      {:ok, sig} when is_binary(sig) -> {:ok, sig}
      _ -> {:error, {:invalid_signature, fetch_lenient(example, :signature)}}
    end
  end

  defp export_map_field(example, key) do
    case fetch_key(example, key) do
      {:ok, value} when is_map(value) and not is_struct(value) -> {:ok, value}
      _ -> {:error, {:"invalid_#{key}", fetch_lenient(example, key)}}
    end
  end

  defp fetch_lenient(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  # Rebuilds the object with binary keys inserted in sorted order. Small maps
  # (<= 31 keys) iterate in term order, which for binaries is byte order, so
  # Jason.encode emits sorted keys without depending on encoder internals.
  defp canonicalize_line(object) do
    object
    |> Enum.map(fn {key, value} -> {key_to_binary!(key), value} end)
    |> Enum.sort(:asc)
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      case canonicalize_value(value) do
        {:ok, canonical} -> Map.put(acc, key, canonical)
        {:error, _} = error -> throw({:canonical_error, error})
      end
    end)
    |> then(&{:ok, &1})
  catch
    {:canonical_error, error} -> error
  end

  defp canonicalize_value(value) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, inner}, {:ok, acc} ->
      case canonicalize_value(inner) do
        {:ok, canonical} -> {:cont, {:ok, Map.put(acc, key_to_binary!(key), canonical)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp canonicalize_value(value) when is_list(value) do
    Enum.reduce_while(value, {:ok, []}, fn inner, {:ok, acc} ->
      case canonicalize_value(inner) do
        {:ok, canonical} -> {:cont, {:ok, [canonical | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp canonicalize_value(value), do: {:ok, value}

  defp key_to_binary!(key) when is_binary(key), do: key
  defp key_to_binary!(key) when is_atom(key), do: Atom.to_string(key)
  defp key_to_binary!(key) when is_integer(key), do: Integer.to_string(key)

  defp bump(meta, key), do: Map.update!(meta, key, &(&1 + 1))

  defp add(meta, key, n), do: Map.update!(meta, key, &(&1 + n))
end
