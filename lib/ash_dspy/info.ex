defmodule AshDspy.Resource.Info do
  @moduledoc """
  Public introspection API for `ash_dspy`.
  """

  @doc "Returns the raw `:dspy` DSL entities declared on `resource`."
  def dspy(resource) do
    Spark.Dsl.Extension.get_entities(resource, [:dspy])
  end

  @doc "Returns the transformer-normalized compiled state for `resource`, or `nil` if the extension is not present."
  def compiled(resource) do
    case compiled_result(resource) do
      {:ok, compiled} -> compiled
      {:error, _} -> nil
    end
  end

  @doc """
  Returns `{:ok, compiled}` or `{:error, :not_compiled}` for `resource`.

  """
  def compiled_result(resource) do
    case Spark.Dsl.Extension.get_persisted(resource, :ash_dspy_compiled, nil) do
      nil -> {:error, :not_compiled}
      compiled -> {:ok, compiled}
    end
  end

  @doc "Bang variant of `compiled_result/1` -- raises `ArgumentError` instead of returning `{:error, _}`."
  def compiled!(resource) do
    case compiled_result(resource) do
      {:ok, compiled} ->
        compiled

      {:error, reason} ->
        raise ArgumentError, "AshDspy.Resource.Info.compiled!/1: #{inspect(reason)}"
    end
  end

  @doc "Predicate: does `resource` carry compiled `ash_dspy` state?"
  def compiled?(resource) do
    match?({:ok, _}, compiled_result(resource))
  end

  @doc "Returns the `:dspy`-derived `compiled_routes`, or `nil` if `resource` has no compiled `ash_dspy` state."
  def compiled_routes(resource) do
    case compiled_routes_result(resource) do
      {:ok, value} -> value
      {:error, :not_found} -> nil
    end
  end

  @doc "Returns `{:ok, compiled_routes}` or `{:error, :not_found}` for `resource`'s `:dspy` section."
  def compiled_routes_result(resource) do
    case compiled_result(resource) do
      {:ok, %{dspy: value}} -> {:ok, value}
      {:ok, _compiled} -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  @doc "Bang variant of `compiled_routes_result/1` -- raises `ArgumentError` instead of returning `{:error, _}`."
  def compiled_routes!(resource) do
    case compiled_routes_result(resource) do
      {:ok, value} ->
        value

      {:error, reason} ->
        raise ArgumentError, "AshDspy.Resource.Info.compiled_routes!/1: #{inspect(reason)}"
    end
  end

  @doc "Predicate: does `resource` carry a `compiled_routes`?"
  def compiled_routes?(resource) do
    match?({:ok, _}, compiled_routes_result(resource))
  end

  @doc "Returns the `:dspy`-derived `implementations`, or `nil` if `resource` has no compiled `ash_dspy` state."
  def implementations(resource) do
    case implementations_result(resource) do
      {:ok, value} -> value
      {:error, :not_found} -> nil
    end
  end

  @doc "Returns `{:ok, implementations}` or `{:error, :not_found}` for `resource`'s `:dspy` section."
  def implementations_result(resource) do
    case compiled_result(resource) do
      {:ok, %{dspy: value}} -> {:ok, value}
      {:ok, _compiled} -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  @doc "Bang variant of `implementations_result/1` -- raises `ArgumentError` instead of returning `{:error, _}`."
  def implementations!(resource) do
    case implementations_result(resource) do
      {:ok, value} ->
        value

      {:error, reason} ->
        raise ArgumentError, "AshDspy.Resource.Info.implementations!/1: #{inspect(reason)}"
    end
  end

  @doc "Predicate: does `resource` carry a `implementations`?"
  def implementations?(resource) do
    match?({:ok, _}, implementations_result(resource))
  end

  @doc "Returns the `:dspy`-derived `signature_programs`, or `nil` if `resource` has no compiled `ash_dspy` state."
  def signature_programs(resource) do
    case signature_programs_result(resource) do
      {:ok, value} -> value
      {:error, :not_found} -> nil
    end
  end

  @doc "Returns `{:ok, signature_programs}` or `{:error, :not_found}` for `resource`'s `:dspy` section."
  def signature_programs_result(resource) do
    case compiled_result(resource) do
      {:ok, %{dspy: value}} -> {:ok, value}
      {:ok, _compiled} -> {:error, :not_found}
      {:error, _} = error -> error
    end
  end

  @doc "Bang variant of `signature_programs_result/1` -- raises `ArgumentError` instead of returning `{:error, _}`."
  def signature_programs!(resource) do
    case signature_programs_result(resource) do
      {:ok, value} ->
        value

      {:error, reason} ->
        raise ArgumentError, "AshDspy.Resource.Info.signature_programs!/1: #{inspect(reason)}"
    end
  end

  @doc "Predicate: does `resource` carry a `signature_programs`?"
  def signature_programs?(resource) do
    match?({:ok, _}, signature_programs_result(resource))
  end
end
