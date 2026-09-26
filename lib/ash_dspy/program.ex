defmodule AshDspy.Program do
  @moduledoc """
  Pure projection from `AshDspy.Resource` declarations to the JSON program
  model exported by `dspy-wasm`.

  No Python or DSPy semantics are reimplemented here: this module only turns
  admitted Ash metadata into the component's public request schema.
  """

  alias AshDspy.Resource
  alias AshDspy.Resource.Info

  @type error ::
          :signature_not_found
          | :signature_has_no_inputs
          | :signature_has_no_outputs
          | {:unsupported_type, term()}
          | {:undeclared_requirement_dimension, atom()}

  @doc "Builds the dspy-wasm program specification for one declared signature."
  def spec(resource, signature_name, opts \\ []) do
    opts = normalize_opts(opts)
    entities = Info.dspy(resource)

    with {:ok, signature} <- find_signature(entities, signature_name),
         :ok <- validate_dimensions(entities),
         {:ok, inputs} <- fields(entities, Resource.Input),
         {:ok, outputs} <- fields(entities, Resource.Output),
         :ok <- require_fields(inputs, :signature_has_no_inputs),
         :ok <- require_fields(outputs, :signature_has_no_outputs) do
      base = %{
        "module" => normalize_slug(Map.get(opts, :module, "predict")),
        "signature" => %{
          "inputs" => inputs,
          "outputs" => outputs,
          "instructions" => signature.description
        }
      }

      program =
        base
        |> Map.merge(json_ready(Map.get(opts, :program, %{})))
        |> maybe_put("adapter", optional_slug(opts, :adapter))
        |> maybe_put("program_state", Map.get(opts, :program_state))

      {:ok, drop_nil_signature_instructions(program)}
    end
  end

  @doc "Builds a `run` request."
  def run_request(resource, signature_name, inputs, opts \\ []) when is_map(inputs) do
    with {:ok, program} <- spec(resource, signature_name, opts) do
      {:ok,
       program
       |> Map.put("inputs", json_ready(inputs))
       |> merge_request(opts)}
    end
  end

  @doc "Builds a `render` request."
  def render_request(resource, signature_name, inputs, opts \\ []) when is_map(inputs) do
    run_request(resource, signature_name, inputs, opts)
  end

  @doc "Builds an `evaluate` request using the DSL's default metric when possible."
  def evaluate_request(resource, signature_name, devset, opts \\ []) when is_list(devset) do
    with {:ok, program} <- spec(resource, signature_name, opts) do
      {:ok,
       %{
         "program" => program,
         "devset" => json_ready(devset),
         "metric" => metric_spec(resource, opts)
       }
       |> merge_request(opts)}
    end
  end

  @doc "Builds a `compile` request whose returned program_state can be fed back to run."
  def compile_request(resource, signature_name, trainset, opts \\ []) when is_list(trainset) do
    opts = normalize_opts(opts)

    with {:ok, program} <- spec(resource, signature_name, opts) do
      request = %{
        "program" => program,
        "trainset" => json_ready(trainset),
        "metric" => metric_spec(resource, opts),
        "optimizer" => normalize_slug(Map.get(opts, :optimizer, "labeled-few-shot"))
      }

      {:ok,
       request
       |> maybe_put("valset", json_ready(Map.get(opts, :valset)))
       |> maybe_put("config", json_ready(Map.get(opts, :config)))
       |> maybe_put("compile_config", json_ready(Map.get(opts, :compile_config)))
       |> merge_request(opts)}
    end
  end

  @doc """
  Evaluates the declared requirement bounds for the metric represented by a
  dspy-wasm evaluation report. DSPy's Evaluate score is percentage-valued, so
  a DSL bound such as `90` means 90%.
  """
  def assess(resource, metric_name, %{"score" => score} = report)
      when is_number(score) do
    entities = Info.dspy(resource)
    metric = find_metric(entities, metric_name)

    checks =
      case metric do
        nil ->
          []

        metric ->
          dimension = metric.dimension

          entities
          |> Enum.filter(&match?(%Resource.Requirement{dimension: ^dimension}, &1))
          |> Enum.map(&check_requirement(&1, score))
      end

    Map.put(report, "ash_dspy", %{
      "metric" => normalize_metric_name(metric_name),
      "dimension" => metric && Atom.to_string(metric.dimension),
      "requirements" => checks,
      "requirements_met" => Enum.all?(checks, & &1["met"]),
      "minimize" =>
        entities
        |> Enum.filter(&match?(%Resource.Minimize{}, &1))
        |> Enum.map(&Atom.to_string(&1.objective))
    })
  end

  def assess(_resource, _metric_name, report), do: report

  @doc "Resolves the metric sent to dspy-wasm."
  def metric_spec(resource, opts \\ []) do
    opts = normalize_opts(opts)

    case Map.get(opts, :metric) do
      nil -> inferred_metric(resource)
      metric -> json_ready(metric)
    end
  end

  defp inferred_metric(resource) do
    entities = Info.dspy(resource)
    default_dimension = Spark.Dsl.Extension.get_opt(resource, [:dspy], :default_metric, nil)

    metric =
      if default_dimension do
        Enum.find(entities, &match?(%Resource.Metric{dimension: ^default_dimension}, &1))
      else
        Enum.find(entities, &match?(%Resource.Metric{}, &1))
      end

    if metric, do: Atom.to_string(metric.name), else: "exact_match"
  end

  defp find_signature(entities, name) do
    case Enum.find(entities, fn
           %Resource.Signature{name: declared} -> same_name?(declared, name)
           _ -> false
         end) do
      nil -> {:error, :signature_not_found}
      signature -> {:ok, signature}
    end
  end

  defp fields(entities, module) do
    entities
    |> Enum.filter(&is_struct(&1, module))
    |> Enum.reduce_while({:ok, %{}}, fn field, {:ok, acc} ->
      case dspy_type(field.type) do
        {:ok, type} ->
          value =
            %{"type" => type}
            |> maybe_put("desc", field.doc)

          {:cont, {:ok, Map.put(acc, Atom.to_string(field.name), value)}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  defp dspy_type(:string), do: {:ok, "str"}
  defp dspy_type(:integer), do: {:ok, "int"}
  defp dspy_type(:float), do: {:ok, "float"}
  defp dspy_type(:boolean), do: {:ok, "bool"}
  defp dspy_type(:map), do: {:ok, "dict"}
  defp dspy_type(:term), do: {:ok, "str"}
  defp dspy_type(:uuid), do: {:ok, "str"}
  defp dspy_type(:uuid_v7), do: {:ok, "str"}
  defp dspy_type(:date), do: {:ok, "str"}
  defp dspy_type(:time), do: {:ok, "str"}
  defp dspy_type(:utc_datetime), do: {:ok, "str"}
  defp dspy_type(:utc_datetime_usec), do: {:ok, "str"}
  defp dspy_type(:decimal), do: {:ok, "float"}

  defp dspy_type({:array, inner}) do
    with {:ok, type} <- dspy_type(inner), do: {:ok, "list[#{type}]"}
  end

  defp dspy_type(other), do: {:error, {:unsupported_type, other}}

  defp validate_dimensions(entities) do
    dimensions =
      entities
      |> Enum.filter(&match?(%Resource.Metric{}, &1))
      |> MapSet.new(& &1.dimension)

    entities
    |> Enum.filter(&match?(%Resource.Requirement{}, &1))
    |> Enum.reduce_while(:ok, fn requirement, :ok ->
      if MapSet.member?(dimensions, requirement.dimension) do
        {:cont, :ok}
      else
        {:halt, {:error, {:undeclared_requirement_dimension, requirement.dimension}}}
      end
    end)
  end

  defp require_fields(fields, error) when map_size(fields) == 0, do: {:error, error}
  defp require_fields(_fields, _error), do: :ok

  defp find_metric(entities, metric_name) do
    Enum.find(entities, fn
      %Resource.Metric{name: declared} -> same_name?(declared, metric_name)
      _ -> false
    end)
  end

  defp check_requirement(requirement, score) do
    met =
      case requirement.operator do
        :gte -> score >= requirement.bound
        :lte -> score <= requirement.bound
        :gt -> score > requirement.bound
        :lt -> score < requirement.bound
        :eq -> score == requirement.bound
      end

    %{
      "dimension" => Atom.to_string(requirement.dimension),
      "operator" => Atom.to_string(requirement.operator),
      "bound" => requirement.bound,
      "actual" => score,
      "met" => met
    }
  end

  defp merge_request(request, opts) do
    opts = normalize_opts(opts)
    Map.merge(request, json_ready(Map.get(opts, :request, %{})))
  end

  defp drop_nil_signature_instructions(%{"signature" => signature} = program) do
    signature =
      if is_nil(signature["instructions"]) do
        Map.delete(signature, "instructions")
      else
        signature
      end

    Map.put(program, "signature", signature)
  end

  defp optional_slug(opts, key) do
    opts = normalize_opts(opts)

    case Map.get(opts, key) do
      nil -> nil
      value -> normalize_slug(value)
    end
  end

  defp normalize_slug(value) when is_atom(value),
    do: value |> Atom.to_string() |> String.replace("_", "-")

  defp normalize_slug(value) when is_binary(value),
    do: String.replace(value, "_", "-")

  defp normalize_metric_name(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_metric_name(value) when is_binary(value), do: value
  defp normalize_metric_name(value), do: inspect(value)

  defp same_name?(declared, requested) when is_atom(declared) and is_atom(requested),
    do: declared == requested

  defp same_name?(declared, requested) when is_atom(declared) and is_binary(requested),
    do: Atom.to_string(declared) == requested

  defp same_name?(_declared, _requested), do: false

  defp json_ready(nil), do: nil
  defp json_ready(true), do: true
  defp json_ready(false), do: false
  defp json_ready(value) when is_atom(value), do: Atom.to_string(value)

  defp json_ready(value) when is_map(value) do
    Map.new(value, fn {key, child} -> {to_string(key), json_ready(child)} end)
  end

  defp json_ready(value) when is_list(value), do: Enum.map(value, &json_ready/1)
  defp json_ready(value) when is_tuple(value), do: value |> Tuple.to_list() |> json_ready()
  defp json_ready(value), do: value

  defp normalize_opts(opts) when is_list(opts), do: Map.new(opts)
  defp normalize_opts(opts) when is_map(opts), do: opts

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
