defmodule AshDspy.Runtime.Implementation do
  @moduledoc """
  Behaviour for `AshDspy` runtime implementation classes.

  An implementation turns a program's input map into an output map at some
  intelligence rank. The rank ladder and class set live in
  `AshDspy.Runtime.Lattice`; this behaviour pins only the per-class shape.

  Context (`ctx`) is a map possibly carrying:

    * `:corpus` — evaluation corpus data (lane 4/5 concern; opaque here)
    * `:generate` — caller-supplied LLM fn `(prompt_map) -> {:ok, output_map} | {:error, term}`
    * `:transport` — capability invoke fn `(capability_uri, input_map) -> {:ok, map} | {:error, term}`
    * `:impl_config` — per-class configuration (keyword list or map)

  ## External capability invocations

  The lattice is exactly the 8 classes pinned by `AshDspy.Runtime.Lattice`.
  External-capability invocation is modeled as
  `AshDspy.Runtime.Implementations.Rule` (class `:rule`) configured with a
  `:transport` fn — there is deliberately no ninth class.
  """

  @type input_map :: %{optional(atom() | String.t()) => term()}
  @type output_map :: %{optional(atom() | String.t()) => term()}
  @type impl_config :: keyword() | map()
  @type ctx :: %{
          optional(:corpus) => term(),
          optional(:generate) => fun(),
          optional(:transport) => fun(),
          optional(:impl_config) => impl_config(),
          optional(atom()) => term()
        }
  @type result :: {:ok, output_map()} | {:refused, term()}

  @callback class :: atom()
  @callback intelligence :: pos_integer()
  @callback run(input_map(), ctx()) :: result()
end
