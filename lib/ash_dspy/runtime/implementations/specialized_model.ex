defmodule AshDspy.Runtime.Implementations.SpecializedModel do
  @moduledoc """
  Class `:specialized_model` (intelligence 7).

  UNSUPPORTED(ash_dspy:specialized_model) — declared unsupported in v26.9.25; no runtime exists.
  """

  @behaviour AshDspy.Runtime.Implementation

  @impl true
  def class, do: :specialized_model

  @impl true
  def intelligence, do: 7

  @impl true
  def run(_input, _ctx), do: {:refused, :unsupported_implementation_class}
end
