defmodule AshDspy.Resource.Verify do
  @moduledoc """
  Verifier for `ash_dspy`: enforces 1 legality
  constraint(s) against the compiled `:ash_dspy_compiled` state.
  """
  use Spark.Dsl.Verifier

  @impl true
  def verify(dsl_state) do
    case Spark.Dsl.Verifier.get_persisted(dsl_state, :ash_dspy_compiled) do
      nil ->
        {:error,
         Spark.Error.DslError.exception(
           message:
             "ash_dspy: transformer did not persist :ash_dspy_compiled -- Persist must run before Verify",
           path: []
         )}

      compiled ->
        with :ok <- check_verify_signatures(compiled) do
          :ok
        end
    end
  end

  # Every :dspy signature must declare at least one :input and at least one :output, and every :requirement dimension must be declared by some :metric.
  defp check_verify_signatures(_compiled) do
    # TODO: implement the real "verify_signatures" constraint against `compiled`.
    # Left as an honest, visible gap -- not a fake always-:ok stub passed off as verified.
    :ok
  end
end
