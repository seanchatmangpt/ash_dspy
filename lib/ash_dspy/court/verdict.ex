defmodule AshDspy.Court.Verdict do
  @moduledoc """
  Verdict struct produced by `AshDspy.Court.evaluate/4`.

  - `:scores` — map of dimension atom -> measured float.
  - `:passed` — true only when every gating dimension meets its bound and no
    dimension refused.
  - `:reasons` — list of binaries explaining every failure or refusal.
  - `:digest` — lowercase sha256 hex binding {implementation_module, scores,
    corpus_digest}.
  """

  defstruct scores: %{}, passed: false, reasons: [], digest: nil

  @type t :: %__MODULE__{
          scores: %{optional(atom()) => float()},
          passed: boolean(),
          reasons: [String.t()],
          digest: String.t() | nil
        }
end
