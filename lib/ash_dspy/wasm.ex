defmodule AshDspy.Wasm do
  @moduledoc """
  BEAM host for the `dspy-wasm` WebAssembly component.

  DSPy program semantics execute inside the WASI-P2 component. Network/provider
  and tool authority remain in the BEAM and cross only the two WIT imports
  declared by `chatman:dspy@0.1.0`.
  """

  alias Wasmex.Components
  alias Wasmex.Wasi.WasiP2Options

  @component_version "0.1.0"
  @lm_interface "chatman:dspy/lm@0.1.0"
  @tools_interface "chatman:dspy/tools@0.1.0"
  @request_exports ~w(run render evaluate compile)
  @default_timeout 120_000

  @type lm_result ::
          binary()
          | map()
          | {:ok, binary() | map()}
          | {:error, term()}

  @type lm_callback :: (map() -> lm_result())
  @type tool_callback :: (map() -> term()) | (() -> term())

  @doc "The exact dspy-wasm component version this host admits."
  def component_version_requirement, do: @component_version

  @doc "Loads the vendored consumer contract copied from dspy-wasm."
  def contract do
    :ash_dspy
    |> Application.app_dir("priv/dspy-contract.json")
    |> File.read!()
    |> Jason.decode!()
  end

  @doc """
  Starts one DSPy component instance.

  Required:
    * `:lm` — arity-1 callback receiving the decoded DSPy LM request.

  Component source, in priority order:
    * `:bytes`
    * `:path`
    * `config :ash_dspy, :dspy_wasm_path`
    * `DSPY_WASM_PATH`

  Optional `:tools` is a map of tool name to arity-0/1 callbacks.
  """
  def start_link(opts) when is_list(opts) or is_map(opts) do
    opts = Map.new(opts)

    with {:ok, lm} <- fetch_lm(opts),
         {:ok, source} <- component_source(opts) do
      component_opts =
        source
        |> Map.put(:wasi, %WasiP2Options{})
        |> Map.put(:imports, imports(lm, Map.get(opts, :tools, %{})))
        |> maybe_put(:name, Map.get(opts, :name))

      case Components.start_link(component_opts) do
        {:ok, pid} ->
          admit_component(pid)

        {:error, reason} ->
          {:error, {:component_start_failed, reason}}
      end
    end
  end

  @doc "Builds the exact namespaced WIT import map consumed by dspy-wasm."
  def imports(lm, tools \\ %{}) when is_function(lm, 1) and is_map(tools) do
    %{
      @lm_interface => %{
        "complete" => {:fn, fn request_json -> complete(lm, request_json) end}
      },
      @tools_interface => %{
        "call" => {:fn, fn name, args_json -> call_tool(tools, name, args_json) end}
      }
    }
  end

  def component_version(pid, timeout \\ 5_000),
    do: call_text(pid, "component-version", [], timeout)

  def runtime_info(pid, timeout \\ 5_000),
    do: call_json(pid, "runtime-info", [], timeout)

  def dspy_version(pid, timeout \\ 5_000),
    do: call_json(pid, "dspy-version", [], timeout)

  def capabilities(pid, timeout \\ 30_000),
    do: call_json(pid, "capabilities", [], timeout)

  def self_test(pid, timeout \\ @default_timeout),
    do: call_json(pid, "run-self-tests", [], timeout)

  def predict(pid, signature, inputs, timeout \\ @default_timeout)
      when is_binary(signature) and is_map(inputs) do
    with {:ok, inputs_json} <- Jason.encode(inputs) do
      call_json(pid, "predict", [signature, inputs_json], timeout)
    end
  end

  for export <- @request_exports do
    def unquote(String.to_atom(export))(pid, request, timeout \\ @default_timeout)
        when is_map(request) do
      call_request(pid, unquote(export), request, timeout)
    end
  end

  defp call_request(pid, export, request, timeout) do
    with {:ok, request_json} <- Jason.encode(request) do
      call_json(pid, export, [request_json], timeout)
    end
  end

  defp call_json(pid, export, args, timeout) do
    with {:ok, text} <- call_text(pid, export, args, timeout),
         {:ok, decoded} <- Jason.decode(text) do
      {:ok, decoded}
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:invalid_component_json, export, Exception.message(error)}}

      {:error, _} = error ->
        error
    end
  end

  defp call_text(pid, export, args, timeout) do
    case Components.call_function(pid, export, args, timeout) do
      {:ok, text} when is_binary(text) -> {:ok, text}
      {:ok, other} -> {:error, {:invalid_component_result, export, other}}
      {:error, reason} -> {:error, {:component_call_failed, export, reason}}
    end
  end

  defp admit_component(pid) do
    case component_version(pid) do
      {:ok, @component_version} ->
        {:ok, pid}

      {:ok, version} ->
        GenServer.stop(pid, :normal)
        {:error, {:component_version_mismatch, @component_version, version}}

      {:error, reason} ->
        GenServer.stop(pid, :normal)
        {:error, {:component_admission_failed, reason}}
    end
  end

  defp fetch_lm(%{lm: lm}) when is_function(lm, 1), do: {:ok, lm}
  defp fetch_lm(_opts), do: {:error, :lm_callback_required}

  defp component_source(opts) do
    cond do
      is_binary(Map.get(opts, :bytes)) ->
        {:ok, %{bytes: Map.fetch!(opts, :bytes)}}

      is_binary(Map.get(opts, :path)) ->
        {:ok, %{path: Map.fetch!(opts, :path)}}

      path = Application.get_env(:ash_dspy, :dspy_wasm_path) ->
        {:ok, %{path: path}}

      path = System.get_env("DSPY_WASM_PATH") ->
        {:ok, %{path: path}}

      true ->
        {:error, :dspy_wasm_component_required}
    end
  end

  defp complete(lm, request_json) do
    safe_envelope(fn ->
      request = Jason.decode!(request_json)

      case lm.(request) do
        {:ok, value} -> lm_envelope(value)
        {:error, reason} -> %{"error" => format_reason(reason)}
        value -> lm_envelope(value)
      end
    end)
  end

  defp lm_envelope(%{} = envelope), do: stringify_keys(envelope)
  defp lm_envelope(text) when is_binary(text), do: %{"text" => text}
  defp lm_envelope(other), do: %{"error" => "invalid LM callback result: #{inspect(other)}"}

  defp call_tool(tools, name, args_json) do
    safe_envelope(fn ->
      args = Jason.decode!(args_json)

      with {:ok, tool} <- fetch_tool(tools, name) do
        result =
          cond do
            is_function(tool, 1) -> tool.(args)
            is_function(tool, 0) -> tool.()
            true -> {:error, "tool #{inspect(name)} is not callable"}
          end

        case result do
          {:ok, value} -> %{"result" => value}
          {:error, reason} -> %{"error" => format_reason(reason)}
          value -> %{"result" => value}
        end
      else
        {:error, reason} -> %{"error" => format_reason(reason)}
      end
    end)
  end

  defp fetch_tool(tools, name) do
    Enum.find_value(tools, {:error, "unknown host tool #{inspect(name)}"}, fn
      {key, value} when is_atom(key) ->
        if Atom.to_string(key) == name, do: {:ok, value}

      {key, value} when is_binary(key) ->
        if key == name, do: {:ok, value}

      _ ->
        nil
    end)
  end

  defp safe_envelope(fun) do
    try do
      fun.() |> Jason.encode!()
    rescue
      exception ->
        Jason.encode!(%{
          "error" => "#{inspect(exception.__struct__)}: #{Exception.message(exception)}"
        })
    catch
      kind, reason ->
        Jason.encode!(%{"error" => "#{kind}: #{inspect(reason)}"})
    end
  end

  defp stringify_keys(value) when is_map(value) do
    Map.new(value, fn {key, child} -> {to_string(key), stringify_keys(child)} end)
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
