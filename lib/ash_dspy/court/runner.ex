defmodule AshDspy.Court.Runner do
  @moduledoc false

  @typedoc """
  Result of a guarded call against the implementation surface.

  `{:ok, term}` means the call returned; any raise/exit/throw is captured as
  `{:error, reason}`. A returned `{:error, _}` from the implementation itself
  is *not* an `:error` here -- it is an ordinary output value and metrics
  compare it structurally like anything else.
  """
  @type guarded :: {:ok, term()} | {:error, term()}

  @doc "Loads the module; `{:module, mod}` or `:error`."
  @spec ensure(module()) :: {:module, module()} | :error
  def ensure(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, _} = ok -> ok
      _ -> :error
    end
  end

  def ensure(_), do: :error

  @doc "Calls `module.fun/arity` guarded; never raises."
  @spec call(module(), atom(), non_neg_integer(), list()) :: guarded()
  def call(module, fun, arity, args) do
    cond do
      ensure(module) == :error ->
        {:error, :not_loaded}

      not function_exported?(module, fun, arity) ->
        {:error, {:not_exported, {module, fun, arity}}}

      true ->
        apply(module, fun, args)
    end
  rescue
    e -> {:error, {:raised, Exception.message(e)}}
  catch
    :exit, reason -> {:error, {:exited, reason}}
    :throw, value -> {:error, {:threw, value}}
  end

  @doc """
  Runs the implementation's `run/2` (the lane-3 contract execution surface)
  guarded. Returns `{:ok, output}` or `{:error, reason}`.
  """
  @spec run(module(), map(), map()) :: guarded()
  def run(implementation_module, inputs, ctx) do
    call(implementation_module, :run, 2, [inputs, ctx])
  end

  @doc "Reads `class/0` from the implementation, guarded."
  @spec class(module()) :: guarded()
  def class(implementation_module), do: call(implementation_module, :class, 0, [])

  @doc "Reads `intelligence/0` from the implementation, guarded."
  @spec intelligence(module()) :: guarded()
  def intelligence(implementation_module), do: call(implementation_module, :intelligence, 0, [])

  @doc """
  Normalizes an implementation output for structural comparison: a bare
  `{:ok, map}` wrapper is unwrapped to the map (both conventions are accepted
  by the court); anything else is compared as-is.
  """
  @spec normalize_output(term()) :: term()
  def normalize_output({:ok, output}) when is_map(output), do: output
  def normalize_output(output), do: output

  @doc "Formats a float for a reason binary, e.g. `0.75`."
  @spec format_number(number()) :: String.t()
  def format_number(f) when is_float(f), do: :erlang.float_to_binary(f, decimals: 4)
  def format_number(i) when is_integer(i), do: Integer.to_string(i)
end
