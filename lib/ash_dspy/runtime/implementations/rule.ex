defmodule AshDspy.Runtime.Implementations.Rule do
  @moduledoc """
  Class `:rule` (intelligence 3) — plain Elixir dispatch, no model in the loop.

  Two configuration modes under `ctx[:impl_config]`, `:apply` taking
  precedence when both are present:

    * `:apply` — 1-arity fn `(input_map) -> {:ok, output_map} | {:error, term}`
      (a bare output map is also accepted), or an MFA `{mod, fun, args}` called
      as `apply(mod, fun, [input_map | args])`. Absent config refuses typed
      `:no_apply_config`; a non-fn/non-MFA value refuses
      `:invalid_apply_config`.

    * `:transport` — capability invoke fn `(capability_uri, input_map) ->
      {:ok, map} | {:error, term}`. The capability URI is read from
      `impl_config[:capability_uri]`, then `ctx[:capability_uri]`; absence
      refuses `:no_capability_uri`. Missing transport fn refuses
      `:no_transport`.

  ## External capability invocations

  The lattice stays exactly 8 classes: external-capability invocation is
  modeled here, as a `:rule` implementation configured with `:transport`.
  There is deliberately no ninth `ExternalCapability` class and no
  `AshDspy.Runtime.Implementations.Lookup` module.

  Emits `[:ash_dspy, :allocation, :rule]` telemetry on every dispatched
  invocation (`%{resolver: :rule}` measurements; `%{mode: :apply | :transport}`
  metadata). A typed refusal before dispatch emits nothing.
  """

  @behaviour AshDspy.Runtime.Implementation

  @telemetry_event [:ash_dspy, :allocation, :rule]
  @telemetry_measurements %{resolver: :rule}

  @impl true
  def class, do: :rule

  @impl true
  def intelligence, do: 3

  @impl true
  def run(input, ctx) do
    config = impl_config(ctx)

    cond do
      apply = fetch(config, :apply) ->
        :telemetry.execute(@telemetry_event, @telemetry_measurements, %{mode: :apply})
        dispatch_apply(apply, input)

      fetch(config, :transport) != nil ->
        run_transport(config, ctx, input)

      true ->
        {:refused, :no_apply_config}
    end
  end

  defp dispatch_apply({mod, fun, args}, input)
       when is_atom(mod) and is_atom(fun) and is_list(args) do
    normalize_result(apply(mod, fun, [input | args]), :apply_failed, :apply_invalid_result)
  end

  defp dispatch_apply(fun, input) when is_function(fun, 1) do
    normalize_result(fun.(input), :apply_failed, :apply_invalid_result)
  end

  defp dispatch_apply(_other, _input), do: {:refused, :invalid_apply_config}

  defp run_transport(config, ctx, input) do
    case capability_uri(config, ctx) do
      {:ok, uri} ->
        transport = fetch(config, :transport)

        case transport do
          transport when is_function(transport, 2) ->
            :telemetry.execute(@telemetry_event, @telemetry_measurements, %{mode: :transport})
            normalize_result(transport.(uri, input), :transport_failed, :transport_invalid_result)

          _other ->
            {:refused, :invalid_transport_config}
        end

      {:refused, reason} ->
        {:refused, reason}
    end
  end

  defp capability_uri(config, ctx) do
    cond do
      uri = fetch(config, :capability_uri) ->
        {:ok, uri}

      is_map(ctx) and Map.get(ctx, :capability_uri) != nil ->
        {:ok, Map.get(ctx, :capability_uri)}

      true ->
        {:refused, :no_capability_uri}
    end
  end

  defp normalize_result({:ok, output}, _failed, _invalid) when is_map(output), do: {:ok, output}
  defp normalize_result({:error, reason}, failed, _invalid), do: {:refused, {failed, reason}}
  defp normalize_result(output, _failed, _invalid) when is_map(output), do: {:ok, output}
  defp normalize_result(other, _failed, invalid), do: {:refused, {invalid, other}}

  defp impl_config(ctx) when is_map(ctx), do: Map.get(ctx, :impl_config, [])
  defp impl_config(_other), do: []

  defp fetch(config, key) when is_list(config), do: Keyword.get(config, key)
  defp fetch(config, key) when is_map(config), do: Map.get(config, key)
  defp fetch(_other, _key), do: nil
end
