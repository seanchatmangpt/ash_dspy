defmodule AshDspy.Runtime.Implementations.LLM do
  @moduledoc """
  Class `:llm` (intelligence 8) — lowest-precedence, highest-capability
  fallback.

  Primary path: `ctx[:generate]`, a caller-supplied 1-arity fn
  `(prompt_map) -> {:ok, output_map} | {:error, term}`. The prompt map carries
  the input under `:inputs`.

  Default path (only when `ctx[:generate]` is absent): probes
  `Code.ensure_loaded?(ReqLLM)`; when loaded, builds a default call via
  `ReqLLM.generate_object/3` with the model taken from
  `Application.get_env(:ash_dspy, :llm_profiles, [])` under role `:default`
  and the object schema from `ctx[:impl_config][:schema]`. Every failure on
  this path is a typed refusal — `:no_llm_adapter` (ReqLLM not loaded),
  `:no_default_llm_profile`, `:no_default_llm_model`, `:no_llm_schema`,
  `{:llm_failed, reason}`, `{:llm_adapter_error, message}`. No credentials or
  vendor ids are ever hardcoded and no network call happens unless ReqLLM is
  actually loaded and fully configured.

  Emits `[:ash_dspy, :allocation, :llm]` telemetry
  (`%{resolver: :llm}` measurements; `%{adapter: ...}` metadata) on every
  dispatched invocation. A typed refusal before dispatch emits nothing.
  """

  @behaviour AshDspy.Runtime.Implementation

  @telemetry_event [:ash_dspy, :allocation, :llm]
  @telemetry_measurements %{resolver: :llm}

  @impl true
  def class, do: :llm

  @impl true
  def intelligence, do: 8

  @impl true
  def run(input, ctx) do
    ctx =
      case ctx do
        ctx when is_map(ctx) -> ctx
        _other -> %{}
      end

    case Map.get(ctx, :generate) do
      generate when is_function(generate, 1) ->
        :telemetry.execute(@telemetry_event, @telemetry_measurements, %{adapter: :ctx_generate})
        run_generate(generate, input)

      nil ->
        run_default_adapter(input, ctx)

      _other ->
        {:refused, :invalid_generate_config}
    end
  end

  defp run_generate(generate, input) do
    case generate.(%{inputs: input}) do
      {:ok, output} when is_map(output) ->
        {:ok, output}

      {:error, reason} ->
        {:refused, {:llm_failed, reason}}

      output when is_map(output) ->
        {:ok, output}

      other ->
        {:refused, {:llm_invalid_result, other}}
    end
  end

  defp run_default_adapter(input, ctx) do
    if Code.ensure_loaded?(ReqLLM) do
      case default_model() do
        {:refused, reason} ->
          {:refused, reason}

        {:ok, model} ->
          case schema(ctx) do
            {:refused, reason} ->
              {:refused, reason}

            {:ok, object_schema} ->
              call_req_llm(model, %{inputs: input}, object_schema)
          end
      end
    else
      {:refused, :no_llm_adapter}
    end
  end

  defp call_req_llm(model, prompt, object_schema) do
    :telemetry.execute(@telemetry_event, @telemetry_measurements, %{adapter: :req_llm})

    try do
      # Dynamic dispatch: ReqLLM is an optional runtime-only adapter, never a
      # compile-time dependency, so the call must not xref-resolve it.
      result = apply(ReqLLM, :generate_object, [model, prompt, object_schema])
      normalize_response(result)
    rescue
      exception ->
        {:refused, {:llm_adapter_error, Exception.message(exception)}}
    end
  end

  defp normalize_response({:ok, response}) when is_map(response) do
    object = Map.get(response, :object)

    if is_map(object) do
      {:ok, object}
    else
      {:ok, response}
    end
  end

  defp normalize_response({:error, reason}), do: {:refused, {:llm_failed, reason}}
  defp normalize_response(other), do: {:refused, {:llm_invalid_result, other}}

  defp default_model do
    case Application.get_env(:ash_dspy, :llm_profiles, []) do
      profiles when is_list(profiles) ->
        case Keyword.get(profiles, :default) do
          nil ->
            {:refused, :no_default_llm_profile}

          profile ->
            case model_from(profile) do
              nil -> {:refused, :no_default_llm_model}
              model -> {:ok, model}
            end
        end

      _other ->
        {:refused, :no_default_llm_profile}
    end
  end

  defp model_from(profile) when is_list(profile), do: Keyword.get(profile, :model)
  defp model_from(profile) when is_map(profile), do: Map.get(profile, :model)
  defp model_from(_other), do: nil

  defp schema(ctx) do
    object_schema =
      case Map.get(ctx, :impl_config, []) do
        config when is_list(config) -> Keyword.get(config, :schema)
        config when is_map(config) -> Map.get(config, :schema)
        _other -> nil
      end

    case object_schema do
      nil -> {:refused, :no_llm_schema}
      object_schema -> {:ok, object_schema}
    end
  end
end
