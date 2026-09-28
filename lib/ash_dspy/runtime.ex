defmodule AshDspy.Runtime do
  @moduledoc """
  Runs an `AshDspy.Resource` signature on a `DspyWasm.Host`.

  Hand-written (not generated from `ontology.ttl`; see HANDWRITTEN.md). It reads
  the resource's declared entities through `AshDspy.Resource.Info`, converts them
  to the plain-map shape `DspyWasm.Signature.to_spec/1` takes, and drives the
  dspy-wasm component.

  The `dspy` section is flat: every `input`/`output` belongs to the resource and
  a `signature` entity only names the program and supplies its description, so
  `signature_name` selects the description and the same fields are used for
  every signature.
  """

  alias AshDspy.Resource.{Input, Metric, Output, Requirement, Signature}
  alias AshDspy.Resource.Info

  @doc """
  The plain-map signature (`%{description:, inputs:, outputs:}`) for
  `signature_name` on `resource`, or `{:error, reason}`.
  """
  def signature(resource, signature_name) do
    entities = Info.dspy(resource)

    case Enum.find(entities, &match?(%Signature{name: ^signature_name}, &1)) do
      nil ->
        {:error, {:unknown_signature, signature_name}}

      %Signature{description: description} ->
        {:ok,
         %{
           description: description,
           inputs: for(%Input{} = i <- entities, do: field(i)),
           outputs: for(%Output{} = o <- entities, do: field(o))
         }}
    end
  end

  @doc "The resource's `requirement` entities as `[%{dimension:, operator:, bound:}]`."
  def requirements(resource) do
    for %Requirement{dimension: d, operator: op, bound: b} <- Info.dspy(resource),
        do: %{dimension: d, operator: op, bound: b}
  end

  @doc """
  Builds the dspy-wasm program spec (`"signature"`, `"instructions"`, `"module"`)
  for `signature_name`. `opts[:module]` defaults to `"predict"`.
  """
  def spec(resource, signature_name, opts \\ []) do
    with {:ok, signature} <- signature(resource, signature_name),
         {:ok, spec} <- DspyWasm.Signature.to_spec(signature) do
      {:ok, Map.put(spec, "module", Keyword.get(opts, :module, "predict"))}
    end
  end

  @doc """
  Runs `signature_name` of `resource` on `inputs` (a map keyed by input name).
  Returns `{:ok, outputs}`, `{:error, {:refused, message}}` for a FAILED report,
  or `{:error, reason}` for a transport or translation failure.
  """
  def run(host, resource, signature_name, inputs, opts \\ []) do
    with {:ok, spec} <- spec(resource, signature_name, opts),
         {:ok, report} <- DspyWasm.run(host, Map.put(spec, "inputs", stringify(inputs))) do
      interpret_run(report)
    end
  end

  @doc "Maps a `run` report to `{:ok, outputs}` or `{:error, reason}`."
  def interpret_run(%{"state" => "ALIVE", "outputs" => outputs}), do: {:ok, outputs}
  def interpret_run(%{"state" => "FAILED"} = report), do: {:error, {:refused, report["message"]}}
  def interpret_run(report), do: {:error, {:unexpected_report, report}}

  @doc """
  Runs `evaluate` on `devset` (a list of maps with the input and output fields)
  and checks each of the resource's requirements against the percent score.

  Options: `:module` (default `"predict"`), `:metric` (default: the resource's
  first `metric` name, or `"exact_match"`, on the first output field).

  Returns `{:ok, %{score: percent, results: [%{requirement:, pass?:}]}}` or
  `{:error, reason}`.
  """
  def evaluate(host, resource, signature_name, devset, opts \\ []) do
    with {:ok, spec} <- spec(resource, signature_name, opts),
         {:ok, signature} <- signature(resource, signature_name),
         request = evaluate_request(resource, spec, signature, devset, opts),
         {:ok, report} <- DspyWasm.evaluate(host, request) do
      interpret_evaluate(resource, report)
    end
  end

  @doc false
  def evaluate_request(resource, spec, %{outputs: [first | _]}, devset, opts) do
    metric = Keyword.get(opts, :metric) || default_metric(resource)

    %{
      "program" => spec,
      "devset" => Enum.map(devset, &stringify/1),
      "metric" => %{"name" => to_string(metric), "field" => to_string(first.name)}
    }
  end

  @doc "Maps an `evaluate` report to `{:ok, %{score:, results:}}` or `{:error, reason}`."
  def interpret_evaluate(resource, %{"state" => "FAILED"} = report) do
    _ = resource
    {:error, {:refused, report["message"]}}
  end

  def interpret_evaluate(resource, report) do
    with {:ok, score} <- DspyWasm.Requirement.score(report) do
      {:ok, %{score: score, results: check_requirements(requirements(resource), score)}}
    end
  end

  @doc "Checks each requirement against a percent `score`."
  def check_requirements(requirements, score) do
    for requirement <- requirements,
        do: %{
          requirement: requirement,
          pass?: DspyWasm.Requirement.satisfied?(requirement, score)
        }
  end

  defp default_metric(resource) do
    case Enum.find(Info.dspy(resource), &match?(%Metric{}, &1)) do
      %Metric{name: name} -> name
      nil -> "exact_match"
    end
  end

  defp field(%{name: name, type: type, doc: doc, required: required}),
    do: %{name: name, type: type, doc: doc, required: required}

  defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
