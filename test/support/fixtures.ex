defmodule AshDspy.TestSupport.Fixtures do
  @moduledoc false
end

defmodule AshDspy.TestSupport.TriageResource do
  @moduledoc """
  Real compiled Ash resource carrying the ticket-triage signature through the
  `AshDspy.Resource` extension -- the subject `Program.from_resource/2`
  compiles from. Mirrors the ashdspy-pack's shipped ticket-triage fixture:
  input :ticket, outputs :urgency (low/high) and :team.
  """

  use Ash.Resource,
    domain: nil,
    extensions: [AshDspy.Resource]

  attributes do
    uuid_primary_key :id
  end

  dspy do
    default_metric :accuracy
    default_minimize :token_cost

    signature :triage_ticket do
      description "Triage one support ticket into urgency and owning team."
    end

    input :ticket, :string, doc: "The raw ticket text."

    output :urgency, :string, doc: "One of low/high."
    output :team, :string, doc: "One of billing/technical/general."

    metric :exact_match, :accuracy
    requirement :accuracy, :gte, bound: 90
    minimize :token_cost
  end
end

defmodule AshDspy.TestSupport.BareResource do
  @moduledoc """
  A real Ash resource with NO dspy section -- the negative subject for
  from_resource refusals.
  """

  use Ash.Resource,
    domain: nil

  attributes do
    uuid_primary_key :id
  end
end
