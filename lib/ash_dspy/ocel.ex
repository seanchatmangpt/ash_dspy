defmodule AshDspy.Ocel do
  @moduledoc """
  OCEL 2.0-style ndjson event emission for ash_dspy (object-centric process
  vocabulary bound to the xaas telemetry emitters: `ocel:`-prefixed keys).

  Each emitted line is one flat event object:

      %{
        "ocel:timestamp" => iso8601,
        "ocel:activity"  => event_type,
        "ocel:objects"   => object_refs,
        ...attributes (merged at top level)
      }

  Allowed `event_type` vocabulary (pinned): `"capability.compile"`,
  `"capability.select"`, `"provider.replace"`, `"receipt.persist"`.

  Destination: `Application.get_env(:ash_dspy, :ocel_path, nil)`. When the
  path is `nil` emission is a typed no-op (`{:ok, :disabled}`) — this module
  never invents a write location.

  Redaction is fail-safe and deep: any map key (at any nesting level, atoms
  included) matching `~r/secret|token|key|credential/i` is dropped at emit,
  in both attributes and object refs. Over-redaction is acceptable; leakage
  is not.

  Encoding failure is typed: `{:error, {:encode_failure, reason}}`.
  """

  @event_types ~w(capability.compile capability.select provider.replace receipt.persist)
  @secret_key_regex ~r/secret|token|key|credential/i

  @typedoc "The pinned activity vocabulary."
  @type event_type ::
          String.t()

  @doc "The pinned activity vocabulary."
  @spec event_types() :: [String.t()]
  def event_types, do: @event_types

  @doc """
  Appends one OCEL event line to the configured `:ocel_path`.

    * `event_type` — one of `event_types/0`; anything else is
      `{:error, {:unknown_event_type, given, allowed}}`
    * `object_refs` — list of JSON-encodable object references (ids or
      `%{"ocel:id" => ..., "ocel:type" => ...}` maps); redacted deeply
    * `attributes` — map of top-level event attributes; redacted deeply

  Returns `{:ok, :disabled}` when no `:ocel_path` is configured,
  `{:ok, path}` on a witnessed append, `{:error, term}` otherwise.
  """
  @spec emit_event(event_type(), list(), map()) :: {:ok, :disabled | String.t()} | {:error, term()}
  def emit_event(event_type, object_refs, attributes \\ %{})

  def emit_event(event_type, object_refs, attributes)
      when is_binary(event_type) and is_list(object_refs) and is_map(attributes) do
    if event_type in @event_types do
      case Application.get_env(:ash_dspy, :ocel_path, nil) do
        nil ->
          {:ok, :disabled}

        path when is_binary(path) ->
          write_event(path, event_type, object_refs, attributes)
      end
    else
      {:error, {:unknown_event_type, event_type, @event_types}}
    end
  end

  def emit_event(event_type, _object_refs, _attributes) do
    {:error, {:invalid_event_args, event_type}}
  end

  @doc """
  Emits a `provider.replace` event when a route replaces a prior route for
  the same signature. `route_replacement/3` compares the old and new
  implementations: identical implementations emit nothing
  (`{:ok, :unchanged}`); a real replacement emits `provider.replace` with the
  signature and both route implementations as object refs.

  Returns are those of `emit_event/3` plus `{:ok, :unchanged}`.
  """
  @spec route_replacement(term(), term(), term()) ::
          {:ok, :disabled | :unchanged | String.t()} | {:error, term()}
  def route_replacement(signature_id, old_implementation, new_implementation) do
    if old_implementation == new_implementation do
      {:ok, :unchanged}
    else
      emit_event(
        "provider.replace",
        [
          %{"ocel:id" => "signature:" <> to_string(signature_id), "ocel:type" => "Signature"},
          %{"ocel:id" => "route:" <> inspect(old_implementation), "ocel:type" => "Route"},
          %{"ocel:id" => "route:" <> inspect(new_implementation), "ocel:type" => "Route"}
        ],
        %{
          "signature_id" => to_string(signature_id),
          "old_implementation" => inspect(old_implementation),
          "new_implementation" => inspect(new_implementation)
        }
      )
    end
  end

  # -- internals --------------------------------------------------------------

  defp write_event(path, event_type, object_refs, attributes) do
    line =
      Map.merge(
        %{
          "ocel:timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "ocel:activity" => event_type,
          "ocel:objects" => redact(object_refs)
        },
        redact(attributes)
      )

    with {:ok, json} <- encode(line),
         :ok <- append_line(path, json) do
      {:ok, path}
    end
  end

  defp encode(line) do
    case Jason.encode(line) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:encode_failure, reason}}
    end
  rescue
    reason -> {:error, {:encode_failure, reason}}
  end

  defp append_line(path, json) do
    case File.open(path, [:append, :utf8]) do
      {:ok, device} ->
        try do
          IO.binwrite(device, json <> "\n")
          :ok
        after
          File.close(device)
        end

      {:error, reason} ->
        {:error, {:ocel_write_failure, path, reason}}
    end
  end

  # Deep, fail-safe redaction: drop any map key matching the secret regex at
  # any depth; recurse through maps and lists. Non-map/list values pass.
  defp redact(%{} = map) do
    map
    |> Map.filter(fn {key, _value} -> not secret_key?(key) end)
    |> Map.new(fn {key, value} -> {key, redact(value)} end)
  end

  defp redact(list) when is_list(list), do: Enum.map(list, &redact/1)
  defp redact(value), do: value

  defp secret_key?(key) when is_binary(key), do: Regex.match?(@secret_key_regex, key)
  defp secret_key?(key) when is_atom(key), do: secret_key?(Atom.to_string(key))
  defp secret_key?(_key), do: false
end
