defmodule AshDspy do
  @moduledoc """
  Runtime facade that projects `AshDspy.Resource` declarations into
  `dspy-wasm` and executes them through `AshDspy.Wasm`.
  """

  alias AshDspy.Program
  alias AshDspy.Wasm

  @doc "Runs one declared DSPy signature through the WebAssembly component."
  def run(pid, resource, signature, inputs, opts \\ []) do
    with {:ok, request} <- Program.run_request(resource, signature, inputs, opts) do
      Wasm.run(pid, request, timeout(opts))
    end
  end

  @doc "Renders the prompt for one declared signature without calling the LM."
  def render(pid, resource, signature, inputs \\ %{}, opts \\ []) do
    with {:ok, request} <- Program.render_request(resource, signature, inputs, opts) do
      Wasm.render(pid, request, timeout(opts))
    end
  end

  @doc """
  Evaluates a declared signature inside DSPy and applies Ash requirement bounds
  to the returned score.
  """
  def evaluate(pid, resource, signature, devset, opts \\ []) do
    metric = Program.metric_spec(resource, opts)

    with {:ok, request} <- Program.evaluate_request(resource, signature, devset, opts),
         {:ok, report} <- Wasm.evaluate(pid, request, timeout(opts)) do
      {:ok, Program.assess(resource, metric_name(metric), report)}
    end
  end

  @doc """
  Compiles/optimizes a declared signature inside DSPy. The returned
  `"program_state"` can be supplied as `program_state:` on a later run.
  """
  def compile(pid, resource, signature, trainset, opts \\ []) do
    with {:ok, request} <- Program.compile_request(resource, signature, trainset, opts) do
      Wasm.compile(pid, request, timeout(opts))
    end
  end

  defp timeout(opts) when is_list(opts), do: Keyword.get(opts, :timeout, 120_000)
  defp timeout(opts) when is_map(opts), do: Map.get(opts, :timeout, 120_000)

  defp metric_name(metric) when is_atom(metric), do: Atom.to_string(metric)
  defp metric_name(metric) when is_binary(metric), do: metric
  defp metric_name(%{"name" => name}), do: name
  defp metric_name(%{name: name}), do: name
  defp metric_name(_), do: "exact_match"
end
