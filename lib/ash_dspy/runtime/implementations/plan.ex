defmodule AshDspy.Runtime.Implementations.Plan do
  @moduledoc """
  Class `:plan` (intelligence 4).

  UNSUPPORTED(ash_dspy:plan) — declared unsupported in v26.9.25; no runtime exists.
  """

  @behaviour AshDspy.Runtime.Implementation

  @impl true
  def class, do: :plan

  @impl true
  def intelligence, do: 4

  @impl true
  def run(_input, _ctx), do: {:refused, :unsupported_implementation_class}
end
