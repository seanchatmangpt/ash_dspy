defmodule AshDspy.Runtime.Implementations.Compose do
  @moduledoc """
  Class `:compose` (intelligence 2).

  UNSUPPORTED(ash_dspy:compose) — declared unsupported in v26.9.25; no runtime exists.
  """

  @behaviour AshDspy.Runtime.Implementation

  @impl true
  def class, do: :compose

  @impl true
  def intelligence, do: 2

  @impl true
  def run(_input, _ctx), do: {:refused, :unsupported_implementation_class}
end
