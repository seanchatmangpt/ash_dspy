defmodule AshDspy.Compiler.Candidate do
  @moduledoc """
  Candidate enumeration in lattice order plus eligibility probing for `AshDspy.Compiler`.

  Foreign-lane isolation: `AshDspy.Runtime.Lattice` and `AshDspy.Runtime.Implementations.*`
  (lane 3) are reached only through `Code.ensure_loaded?/1`, `function_exported?/3` and
  `apply/3` — never through compile-time remote calls or struct expansion — so this module
  compiles and runs before lane 3 lands. An unlanded candidate surfaces as `:not_eligible`;
  an unlanded lattice surfaces as an empty enumeration (`:no_eligible_candidates` at the
  pipeline level), never as a compile error or a raise.

  Eligibility probe convention (a candidate module may implement `eligible?/1` taking the
  pipeline ctx):

    * `true` or `:ok`                        -> `:eligible`
    * `false`                                -> `:not_eligible` (`:config_refused`)
    * `{:error, reason}` or a raised error   -> `:not_eligible` (a refused-for-config
      candidate is `:not_eligible`, not an error)
    * no `eligible?/1` callback while loaded -> assumed `:eligible`
    * module not loaded                      -> `:not_eligible` (`:module_unavailable`)
  """

  @lattice AshDspy.Runtime.Lattice
  @implementations AshDspy.Runtime.Implementations

  @enforce_keys [:class, :module, :status]
  defstruct [:class, :module, :status, :reason]

  @type t :: %__MODULE__{
          class: atom(),
          module: module(),
          status: :eligible | :not_eligible,
          reason: term()
        }

  @doc """
  Class atoms in lattice order (ascending intelligence), from
  `AshDspy.Runtime.Lattice.classes/0`. Refuses `:no_eligible_candidates` when the lattice
  module has not landed (zero candidates can be enumerated).
  """
  @spec classes() :: {:ok, [atom()]} | {:refused, :no_eligible_candidates}
  def classes do
    cond do
      not Code.ensure_loaded?(@lattice) ->
        {:refused, :no_eligible_candidates}

      not function_exported?(@lattice, :classes, 0) ->
        {:refused, :no_eligible_candidates}

      true ->
        try do
          {:ok, List.wrap(apply(@lattice, :classes, []))}
        rescue
          _ -> {:refused, :no_eligible_candidates}
        end
    end
  end

  @doc """
  Implementation module for a class: `AshDspy.Runtime.Implementations.<CamelizedClass>`
  (`:rule` -> `AshDspy.Runtime.Implementations.Rule`).
  """
  @spec implementation_module(atom()) :: module()
  def implementation_module(class) do
    Module.concat([@implementations, Macro.camelize(to_string(class))])
  end

  @doc """
  Probes every lattice class in lattice order and returns all candidates, eligible and
  not, ascending by intelligence.
  """
  @spec enumerate(term()) :: [t()]
  def enumerate(ctx) do
    case classes() do
      {:ok, classes} ->
        Enum.map(classes, fn class ->
          probe(class, implementation_module(class), ctx)
        end)

      {:refused, _reason} ->
        []
    end
  end

  @doc "Probes a single candidate module for eligibility under `ctx`."
  @spec probe(atom(), module(), term()) :: t()
  def probe(class, module, ctx) do
    cond do
      not Code.ensure_loaded?(module) ->
        not_eligible(class, module, :module_unavailable)

      not function_exported?(module, :eligible?, 1) ->
        eligible(class, module)

      true ->
        classify(class, module, safe_eligible?(module, ctx))
    end
  end

  ## helpers

  defp classify(class, module, result) do
    case result do
      true -> eligible(class, module)
      :ok -> eligible(class, module)
      false -> not_eligible(class, module, :config_refused)
      {:error, reason} -> not_eligible(class, module, reason)
      other -> not_eligible(class, module, {:ambiguous_probe, other})
    end
  end

  defp safe_eligible?(module, ctx) do
    apply(module, :eligible?, [ctx])
  rescue
    error -> {:error, {:probe_raised, Exception.message(error)}}
  end

  defp eligible(class, module) do
    %__MODULE__{class: class, module: module, status: :eligible}
  end

  defp not_eligible(class, module, reason) do
    %__MODULE__{class: class, module: module, status: :not_eligible, reason: reason}
  end
end
