defmodule AshDspy.Compiler.Canonical do
  @moduledoc """
  Canonical corpus serialization and evidence digests for `AshDspy.Compiler`.

  Canonicalization rules (applied recursively; documented so replay is byte-identical):

    * maps become JSON objects whose keys are emitted in ascending order of their
      canonical string form, so `:question` and `"question"` are identical keys
    * atoms become their string form (`:rule` -> `"rule"`; module atoms keep the
      `Elixir.` prefix), so atom/binary spellings of the same value digest identically
    * top-level corpus lists become JSON arrays whose ENTRIES are sorted by their own
      canonical encoding, so corpus order is irrelevant to the evidence digest
    * inner lists become JSON arrays in given order
    * binaries are emitted as JSON strings; binaries that are not valid UTF-8 are
      emitted as `"$b64:<base64>"` so the output is always valid JSON
    * integers use decimal form; floats use Erlang's deterministic `:short` form;
      `true`/`false`/`nil` map to `true`/`false`/`null`; any other term falls back to
      its `inspect/1` form as a JSON string
    * the evidence digest is `sha256(canonical_json(corpus) <> "|" <> verdict_digest)`,
      hex-encoded lowercase, via `:crypto.hash(:sha256, iodata)` — no new dependencies
  """

  @doc "Lowercase hex sha256 of `iodata`."
  @spec sha256_hex(iodata()) :: String.t()
  def sha256_hex(iodata) do
    iodata
    |> :crypto.hash(:sha256)
    |> Base.encode16(case: :lower)
  end

  @doc "Canonical JSON text for any term (rules in the module doc)."
  @spec json(term()) :: String.t()
  def json(term) do
    term
    |> encode()
    |> IO.iodata_to_binary()
  end

  @doc """
  Digest over the canonical corpus plus the Court verdict digest.

  Deterministic in (corpus content, verdict digest) and invariant to corpus entry
  order and to atom/binary spelling — the idempotence guarantee behind
  `AshDspy.Compiler.compile/3`.
  """
  @spec evidence_digest(term(), term()) :: String.t()
  def evidence_digest(corpus, verdict_digest) do
    encoded_entries =
      corpus
      |> List.wrap()
      |> Enum.map(&encode/1)
      |> Enum.sort()

    sha256_hex([?[, Enum.intersperse(encoded_entries, ?,), ?], ?|, digest_part(verdict_digest)])
  end

  ## encoders

  defp encode(%{} = map) do
    pairs =
      if is_struct(map) do
        map |> Map.from_struct() |> Map.put(:__struct__, map.__struct__)
      else
        map
      end

    pairs
    |> Enum.map(fn {key, value} -> {key_string(key), encode(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> [json_string(key), ?:, value] end)
    |> enclose(?{, ?})
  end

  defp encode(binary) when is_binary(binary) do
    if String.valid?(binary) do
      json_string(binary)
    else
      json_string("$b64:" <> Base.encode64(binary))
    end
  end

  defp encode(nil), do: "null"
  defp encode(true), do: "true"
  defp encode(false), do: "false"

  defp encode(atom) when is_atom(atom), do: json_string(to_string(atom))

  defp encode(integer) when is_integer(integer), do: Integer.to_string(integer)

  defp encode(float) when is_float(float), do: :erlang.float_to_binary(float, [:short])

  defp encode(list) when is_list(list) do
    list
    |> Enum.map(&encode/1)
    |> Enum.intersperse(?,)
    |> enclose(?[, ?])
  end

  defp encode(other), do: json_string(inspect(other))

  ## helpers

  defp enclose(inner, open, close), do: [open, inner, close]

  defp key_string(key) when is_binary(key), do: key
  defp key_string(key) when is_atom(key), do: to_string(key)
  defp key_string(key) when is_integer(key), do: Integer.to_string(key)
  defp key_string(other), do: inspect(other)

  defp json_string(string) when is_binary(string) do
    [?", escape_bytes(string), ?"]
  end

  defp escape_bytes(binary) do
    escape_bytes(binary, [])
  end

  defp escape_bytes(<<byte, rest::binary>>, acc) do
    escaped =
      cond do
        byte == ?" -> [?\\, ?"]
        byte == ?\\ -> [?\\, ?\\]
        byte == ?\n -> [?\\, ?n]
        byte == ?\r -> [?\\, ?r]
        byte == ?\t -> [?\\, ?t]
        byte < 0x20 -> [?\\, ?u, :io_lib.format("~4.16.0b", [byte])]
        true -> [byte]
      end

    escape_bytes(rest, [acc, escaped])
  end

  defp escape_bytes(<<>>, acc), do: acc

  defp digest_part(nil), do: "nil"
  defp digest_part(digest) when is_binary(digest), do: digest
  defp digest_part(other), do: inspect(other)
end
