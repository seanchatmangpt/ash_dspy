defmodule AshDspy.Runtime.Program do
  @moduledoc """
  Runtime view of one compiled `:dspy` signature on a resource.

  Built exclusively from persisted Info data via
  `AshDspy.Resource.Info.compiled_result/1` (persisted key `:ash_dspy_compiled`).
  The entity structs in the field lists are the real generated Spark entities
  (`AshDspy.Resource.{Signature,Input,Output,Metric,Requirement,Minimize}`) —
  this module is a projection over them, not a second hand-edited copy.
  """

  defstruct [
    :resource,
    :signature_id,
    :name,
    :description,
    :inputs,
    :outputs,
    :metrics,
    :requirements,
    :minimize
  ]

  @type t :: %__MODULE__{
          resource: module(),
          signature_id: atom(),
          name: atom(),
          description: String.t() | nil,
          inputs: [AshDspy.Resource.Input.t()],
          outputs: [AshDspy.Resource.Output.t()],
          metrics: [AshDspy.Resource.Metric.t()],
          requirements: [AshDspy.Resource.Requirement.t()],
          minimize: [AshDspy.Resource.Minimize.t()]
        }

  @doc """
  Builds the program for `signature_id` from `resource`'s compiled `:dspy` state.

  The `:dspy` section keeps its entities as one flat list, so inputs, outputs,
  metrics, requirements and minimizations are partitioned by struct type and
  carried in declaration order.

  Returns `{:ok, program}`, `{:error, :not_compiled}` when the resource has no
  compiled `ash_dspy` state, or `{:error, {:unknown_signature, signature_id}}`
  when no declared signature matches.
  """
  @spec from_resource(module(), atom()) ::
          {:ok, t()} | {:error, :not_compiled} | {:error, {:unknown_signature, atom()}}
  def from_resource(resource, signature_id) when is_atom(resource) and is_atom(signature_id) do
    case AshDspy.Resource.Info.compiled_result(resource) do
      {:ok, %{dspy: entities}} when is_list(entities) ->
        build(resource, signature_id, entities)

      _other ->
        {:error, :not_compiled}
    end
  end

  defp build(resource, signature_id, entities) do
    {signatures, rest} = split(entities, AshDspy.Resource.Signature)
    signature = Enum.find(signatures, &(&1.name == signature_id))

    case signature do
      nil ->
        {:error, {:unknown_signature, signature_id}}

      signature ->
        {inputs, rest} = split(rest, AshDspy.Resource.Input)
        {outputs, rest} = split(rest, AshDspy.Resource.Output)
        {metrics, rest} = split(rest, AshDspy.Resource.Metric)
        {requirements, minimizes} = split(rest, AshDspy.Resource.Requirement)

        {:ok,
         %__MODULE__{
           resource: resource,
           signature_id: signature_id,
           name: signature.name,
           description: signature.description,
           inputs: inputs,
           outputs: outputs,
           metrics: metrics,
           requirements: requirements,
           minimize: minimizes
         }}
    end
  end

  defp split(entities, module) do
    Enum.split_with(entities, &(&1.__struct__ == module))
  end
end
