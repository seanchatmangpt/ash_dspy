defmodule AshDspy.Court.Metrics.Null do
  @moduledoc """
  Fail-closed fallback for unresolvable metric specifications.

  Always refuses, so an unknown or malformed metric can never silently pass a
  court (`AshDspy.Court.Metric.resolve/1` routes here).
  """

  @behaviour AshDspy.Court.Metric

  @impl true
  def dimension, do: :unknown

  @impl true
  def score(_implementation_module, _corpus, _ctx), do: {:refused, :unresolved_metric}
end
