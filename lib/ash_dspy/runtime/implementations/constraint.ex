defmodule AshDspy.Runtime.Implementations.Constraint do
  @moduledoc """
  Class `:constraint` (intelligence 5).

  UNSUPPORTED(ash_dspy:constraint) — declared unsupported in v26.9.25; no runtime exists.
  """

  @behaviour AshDspy.Runtime.Implementation

  @impl true
  def class, do: :constraint

  @impl true
  def intelligence, do: 5

  @impl true
  def run(_input, _ctx), do: {:refused, :unsupported_implementation_class}
end
