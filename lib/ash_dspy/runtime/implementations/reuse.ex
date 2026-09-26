defmodule AshDspy.Runtime.Implementations.Reuse do
  @moduledoc """
  Class `:reuse` (intelligence 1).

  UNSUPPORTED(ash_dspy:reuse) — declared unsupported in v26.9.25; no runtime exists.
  """

  @behaviour AshDspy.Runtime.Implementation

  @impl true
  def class, do: :reuse

  @impl true
  def intelligence, do: 1

  @impl true
  def run(_input, _ctx), do: {:refused, :unsupported_implementation_class}
end
