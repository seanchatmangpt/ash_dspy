defmodule AshDspy.Receipt do
  @moduledoc """
  Evidence for consequence-bearing ash_dspy capability operations.

  The struct shape is bound to `AshA2A.RuntimeReceipt` (same `@enforce_keys`,
  plus `:result`/`standing`/`metadata` with the same defaults:
  `standing: :observed`, `metadata: %{}`). Runtime receipts deliberately carry
  only observed provider standing. They do not confer Ash domain standing,
  capability admission, authority, or court standing.

  `receipt_id` honesty note: no UUID dependency is taken. The id is
  `"rcpt_" <>` 128 bits from `:crypto.strong_rand_bytes/1`, formatted per
  RFC 4122 UUIDv4 (version and variant bits set). Collision resistance rests
  on the CSPRNG alone; it is uuid-*shaped*, not a registered UUID.
  """

  @enforce_keys [:receipt_id, :provider, :operation, :subject, :status, :recorded_at]
  defstruct [
    :receipt_id,
    :provider,
    :operation,
    :subject,
    :status,
    :result,
    :recorded_at,
    standing: :observed,
    metadata: %{}
  ]

  @type t :: %__MODULE__{}

  @doc """
  Builds a receipt. Status is derived from `result` exactly as
  `AshA2A.RuntimeReceipt` derives it:

    * `:ok` and `{:ok, _}` => `:completed`
    * `{:error, _}` => `:failed`
    * anything else => `:observed`

  Options:

    * `:standing` - defaults `:observed`
    * `:metadata` - map or keyword, coerced with `Map.new/1`

  Unlike `AshA2A.RuntimeReceipt.new/5`, `result` is stored as passed (no pid
  summarization): ash_dspy results are JSON-friendly digest/score maps.
  """
  @spec new(atom() | String.t(), atom(), term(), term(), keyword()) :: t()
  def new(provider, operation, subject, result, opts \\ []) do
    %__MODULE__{
      receipt_id: "rcpt_" <> uuid_v4(),
      provider: provider,
      operation: operation,
      subject: subject,
      status: status(result),
      result: result,
      recorded_at: DateTime.utc_now(),
      standing: Keyword.get(opts, :standing, :observed),
      metadata: Map.new(Keyword.get(opts, :metadata, %{}))
    }
  end

  @doc """
  Builds a receipt for a capability route compile.

  `route` is read duck-typed (no compile-time reference to the Route module):
  it must be a map/struct exposing `:signature_id`, `:class` and
  `:implementation_module`. The evidence fields are taken from `opts` first,
  falling back to the same keys on the route:

    * `:evidence_digest`
    * `:verdict_digest` (required; also keys the replay binding)
    * `:scores`

  Derivations (pinned by the episode contract):

    * `provider` = `"<class>:<implementation_module>"` (module atoms have
      their `Elixir.` prefix stripped)
    * `operation` = `:capability_compile`
    * `subject` = the route's `signature_id`
    * `result` = `%{evidence_digest: ..., verdict_digest: ..., scores: ...}`
    * `metadata` carries `replay_binding: "court:<verdict_digest>"` and
      `reconstructed: false`, merged under any `opts[:metadata]`

  Raises `ArgumentError` when `:verdict_digest` cannot be resolved (the
  replay binding must not be fabricated as `court:` plus a null).
  """
  @spec for_route(term(), keyword()) :: t()
  def for_route(route, opts \\ [])

  def for_route(%{} = route, opts) when is_list(opts) do
    evidence_digest = fetch_field(opts, route, :evidence_digest)
    verdict_digest = fetch_field(opts, route, :verdict_digest)
    scores = fetch_field(opts, route, :scores)

    unless verdict_digest do
      raise ArgumentError,
            "AshDspy.Receipt.for_route/2 requires :verdict_digest (opts or route); " <>
              "refusing to fabricate a replay binding"
    end

    provider =
      "#{normalize_name(Map.get(route, :class))}:#{normalize_name(Map.get(route, :implementation_module))}"

    metadata =
      Map.merge(
        %{
          replay_binding: "court:" <> to_string(verdict_digest),
          reconstructed: false
        },
        Map.new(Keyword.get(opts, :metadata, %{}))
      )

    new(provider, :capability_compile, Map.get(route, :signature_id), %{
      evidence_digest: evidence_digest,
      verdict_digest: verdict_digest,
      scores: scores
    }, metadata: metadata)
  end

  # -- internals --------------------------------------------------------------

  defp fetch_field(opts, route, key), do: Keyword.get(opts, key) || Map.get(route, key)

  defp normalize_name(nil), do: "nil"
  defp normalize_name(name) when is_binary(name), do: name

  defp normalize_name(name) when is_atom(name) do
    name |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
  end

  defp normalize_name(other), do: to_string(other)

  defp status(:ok), do: :completed
  defp status({:ok, _}), do: :completed
  defp status({:error, _}), do: :failed
  defp status(_), do: :observed

  # 128 CSPRNG bits, RFC 4122 UUIDv4-formatted (version nibble = 4, variant
  # bits = 10). No UUID dependency; see the moduledoc honesty note.
  defp uuid_v4 do
    <<raw::unsigned-big-integer-size(128)>> = :crypto.strong_rand_bytes(16)

    versioned = :erlang.bor(:erlang.band(raw, 0xFFFFFFFFFFFF0FFF), 0x0000000000004000)

    variant =
      :erlang.bor(:erlang.band(versioned, 0x3FFFFFFFFFFFFFFF), 0x8000000000000000)

    hex =
      variant
      |> Integer.to_string(16)
      |> String.pad_leading(32, "0")

    <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
      e::binary-size(12)>> = hex

    Enum.join([a, b, c, d, e], "-")
  end
end
