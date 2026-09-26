defmodule AshDspy.Runtime.Implementations.Generate do
  @moduledoc """
  Class `:generate` (intelligence 6) — deterministic template rendering.

  Configured with `ctx[:impl_config][:template]`: a 1-arity fn
  `(input_map) -> {:ok, output_map} | {:error, term}` (a bare output map is
  also accepted). Absent config refuses typed `:no_template`; a non-1-arity
  value refuses `:invalid_template_config`.

  Emits `[:ash_dspy, :allocation, :generate]` telemetry
  (`%{resolver: :generate}`) on every dispatched invocation. A typed refusal
  before dispatch emits nothing.
  """

  @behaviour AshDspy.Runtime.Implementation

  @telemetry_event [:ash_dspy, :allocation, :generate]
  @telemetry_measurements %{resolver: :generate}

  @impl true
  def class, do: :generate

  @impl true
  def intelligence, do: 6

  @impl true
  def run(input, ctx) do
    config =
      case ctx do
        ctx when is_map(ctx) -> Map.get(ctx, :impl_config, [])
        _other -> []
      end

    template =
      case config do
        config when is_list(config) -> Keyword.get(config, :template)
        config when is_map(config) -> Map.get(config, :template)
        _other -> nil
      end

    case template do
      nil ->
        {:refused, :no_template}

      template when is_function(template, 1) ->
        :telemetry.execute(@telemetry_event, @telemetry_measurements, %{})
        normalize(template.(input))

      _other ->
        {:refused, :invalid_template_config}
    end
  end

  defp normalize({:ok, output}) when is_map(output), do: {:ok, output}
  defp normalize({:error, reason}), do: {:refused, {:template_failed, reason}}
  defp normalize(output) when is_map(output), do: {:ok, output}
  defp normalize(other), do: {:refused, {:template_invalid_result, other}}
end
