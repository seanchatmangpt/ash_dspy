defmodule AshDspy.Court.Metrics.Provenance do
  @moduledoc """
  Provenance dimension: 1.0 when the implementation module declares both
  `class/0` and `intelligence/0` (the lane-3 behaviour surface).

  This is a structural check, not a guess: the functions must exist and return
  non-nil atoms/values. Anything missing, unloaded, or raising is a refusal,
  which fails the court.
  """

  @behaviour AshDspy.Court.Metric

  alias AshDspy.Court.Runner

  @impl true
  def dimension, do: :provenance

  @impl true
  def score(implementation_module, _corpus, _ctx) do
    with {:ok, class} <- Runner.class(implementation_module),
         {:ok, intelligence} <- Runner.intelligence(implementation_module),
         true <- declared?(class) || {:missing, :class},
         true <- declared?(intelligence) || {:missing, :intelligence} do
      {1.0, %{class: class, intelligence: intelligence}}
    else
      {:error, reason} ->
        {:refused, {:provenance_declaration_unreadable, implementation_module, reason}}

      {:missing, which} ->
        {:refused, {:missing_declaration, implementation_module, which}}

      false ->
        {:refused, {:missing_declaration, implementation_module, :class}}
    end
  end

  # `nil` and bare booleans are not declarations; any other term is.
  defp declared?(nil), do: false
  defp declared?(value) when is_boolean(value), do: value
  defp declared?(_value), do: true
end
