defmodule AshDspy.Runtime.Route do
  @moduledoc """
  Evidence-bound route record: which implementation class serves a signature,
  on what evidence, under what court verdict and standing.

  `:court_verdict` holds a `%AshDspy.Court.Verdict{}` (admission-court
  contract). That struct belongs to another lane's surface; it is referenced
  here by type only — no runtime construction of it happens in this module.
  """

  defstruct [
    :signature_id,
    :implementation_module,
    :class,
    :evidence_digest,
    :court_verdict,
    :standing
  ]

  @type class :: AshDspy.Runtime.Lattice.class()

  @type court_verdict :: AshDspy.Court.Verdict.t()

  @type standing :: :admitted | :candidate | :refused | :blocked

  @type t :: %__MODULE__{
          signature_id: atom() | nil,
          implementation_module: module() | nil,
          class: class() | nil,
          evidence_digest: String.t() | nil,
          court_verdict: court_verdict() | nil,
          standing: standing() | nil
        }
end
