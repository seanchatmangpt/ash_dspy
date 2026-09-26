defmodule AshDspy.Telemetry do
  @moduledoc """
  `:telemetry` event helpers for ash_dspy (allocation-counter pattern bound to
  the xaas `SemanticDrive` event style: structured events feeding counters).

  Emitted events:

    * `[:ash_dspy, :allocation, <class>]` — via `allocation/3`; `<class>` is
      the allocation class atom (e.g. `:rule`). `measurements` carries the
      numeric counters, `metadata` the provenance.
    * `[:ash_dspy, :receipt, :sealed]` — via `receipt_sealed/2`; measurements
      is `%{receipts: 1}`, metadata carries the receipt identity fields.

  `attach_test_handler/0` attaches a handler that `send/2`s every matching
  event to the calling process as `{:telemetry_event, event, measurements,
  metadata}` — the standard test observation shape. It returns the handler id;
  detach with `detach/1` (a thin wrapper over `:telemetry.detach/1`).

  `:telemetry` matches exact event names only (no wildcard), so the default
  handler covers the pinned contract events
  (`[:ash_dspy, :allocation, :rule]`, `[:ash_dspy, :receipt, :sealed]`); pass
  an explicit event list to observe additional allocation classes.
  """

  @allocation_prefix [:ash_dspy, :allocation]
  @receipt_sealed [:ash_dspy, :receipt, :sealed]

  @default_events [[:ash_dspy, :allocation, :rule], @receipt_sealed]

  @doc "The exact event names `attach_test_handler/0` covers by default."
  @spec default_events() :: [[atom(), ...]]
  def default_events, do: @default_events

  @doc """
  Emits `[:ash_dspy, :allocation, class]` with `measurements` (numeric
  counters) and `metadata` (provenance). Returns `:ok`.
  """
  @spec allocation(atom(), map(), map()) :: :ok
  def allocation(class, measurements, metadata \\ %{})
      when is_atom(class) and is_map(measurements) and is_map(metadata) do
    :telemetry.execute(@allocation_prefix ++ [class], measurements, metadata)
  end

  @doc """
  Emits `[:ash_dspy, :receipt, :sealed]` for a built `AshDspy.Receipt`.
  Measurements: `%{receipts: 1}`. Metadata: receipt_id, provider, operation,
  status, standing, merged under `extra` (map or keyword).
  """
  @spec receipt_sealed(AshDspy.Receipt.t(), map() | keyword()) :: :ok
  def receipt_sealed(receipt, extra \\ %{}) do
    metadata =
      Map.merge(
        %{
          receipt_id: receipt.receipt_id,
          provider: receipt.provider,
          operation: receipt.operation,
          status: receipt.status,
          standing: receipt.standing
        },
        Map.new(extra)
      )

    :telemetry.execute(@receipt_sealed, %{receipts: 1}, metadata)
  end

  @doc """
  Attaches a test handler over `events` (default `default_events/0`). The
  handler sends each event to the attaching process as
  `{:telemetry_event, event, measurements, metadata}`. Returns the handler id;
  detach with `detach/1`. Attaching twice with the same id is an error — the
  id is unique per call.
  """
  @spec attach_test_handler([[atom(), ...]]) :: String.t()
  def attach_test_handler(events \\ @default_events) when is_list(events) do
    id = "ash_dspy_test_handler_" <> unique_ref()

    :ok = :telemetry.attach_many(id, events, &__MODULE__.test_handler/4, %{test_pid: self()})

    id
  end

  @doc "The test handler body: forwards the event to the attaching process."
  @spec test_handler([atom(), ...], map(), map(), %{test_pid: pid()}) :: :ok
  def test_handler(event, measurements, metadata, %{test_pid: pid}) do
    send(pid, {:telemetry_event, event, measurements, metadata})
    :ok
  end

  @doc "Detaches a handler previously returned by `attach_test_handler/0`."
  @spec detach(String.t()) :: :ok
  def detach(handler_id), do: :telemetry.detach(handler_id)

  defp unique_ref do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
