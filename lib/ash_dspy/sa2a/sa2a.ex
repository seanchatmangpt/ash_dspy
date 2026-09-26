defmodule AshDspy.SA2A do
  @moduledoc """
  RFC-SA2A-001 S10 projection for `AshDspy`: turns a compiled signature
  program -- optionally bound to a runtime route -- into a semantic
  capability declaration (`AshDspy.SA2A.AgentCard`).

  ## What a projection is

  `project/2` derives every field; there is no second hand-authored
  capability model. A card says "machinery exists here with this shape".
  It never says "you may invoke it": `grants_authority?/1` is `false`
  unconditionally and `standing/1` is `:declaration`. The only
  authority-bearing fact on the card is `authority_requirement`, which
  states what a caller would need -- a statement of a requirement, not
  its satisfaction.

  ## The route contract

  The second argument is a `%AshDspy.Runtime.Route{}` struct (or any map
  carrying the same keys): `signature_id`, `implementation_module`,
  `class`, `evidence_digest`, `court_verdict`, `standing`. It is read
  with `Map/2` (`Map.get/2`) only, and its shape is referenced in `@type`
  below -- this module compiles independently of the route module. A
  route binds the declaration to courted evidence: `receipt_class`
  upgrades to `:court_receipt` and `semantic_basis` names the court
  verdict digest prefix. A route present still grants nothing.
  """

  alias AshDspy.SA2A.AgentCard

  # Mirrors mix.exs @version; kept literal so projection is stable even
  # when called from an env where Mix is not available.
  @default_version "26.9.25"

  @typedoc """
  Contract shape of `%AshDspy.Runtime.Route{}` (referenced by contract in
  `@type` only -- never structurally, so this module compiles without it).
  """
  @type route_contract :: %{
          optional(:signature_id) => term(),
          optional(:implementation_module) => term(),
          optional(:class) => term(),
          optional(:evidence_digest) => term(),
          optional(:court_verdict) => term(),
          optional(:standing) => term()
        }

  @type signature_program :: module() | String.t() | map()

  @doc """
  Projects one capability declaration from a signature program and an
  optional route.

  The signature program may be a module, a binary id, or any map carrying
  `:signature_id` (also accepts `:id` or the string key
  `"signature_id"`). Raises `ArgumentError` when no signature id can be
  derived. Options:

    * `:version` -- profile version stamped on the card
      (default `"#{@default_version}"`)
    * `:cost_envelope` -- declared resource bound; `:unbounded` by
      default. RFC-SA2A-001 §10 requires a real bound in bounded
      profiles, so pass a map of bounds there rather than leaving the
      default.
  """
  @spec project(signature_program(), route_contract() | nil, keyword()) :: AgentCard.t()
  def project(signature_program, route_or_nil, opts \\ [])

  def project(signature_program, route_or_nil, opts) when is_list(opts) do
    id = signature_id(signature_program)
    version = opts[:version] || @default_version

    %AgentCard{
      capability_iri: "urn:ashdspy:capability:" <> id <> ":v" <> version,
      input_shape: "urn:sa2a:shape:" <> id <> ":input",
      output_shape: "urn:sa2a:shape:" <> id <> ":output",
      preconditions: [],
      effects: [],
      consequence_class: :observe,
      authority_requirement: :none,
      receipt_class: receipt_class(route_or_nil),
      planner_compatibility: [],
      cost_envelope: opts[:cost_envelope] || :unbounded,
      semantic_basis: semantic_basis(route_or_nil),
      version: version
    }
  end

  @doc """
  Convenience for the common case of projecting straight from a route:
  `project_route(route, opts)` pulls the signature info from `opts`
  (`:signature_id`, `:version`, ...) and reads `:signature_id` off the
  route itself as a fallback. Raises `ArgumentError` on a `nil` route or
  when no signature id is available from either source.
  """
  @spec project_route(route_contract(), keyword()) :: AgentCard.t()
  def project_route(route, opts \\ [])

  def project_route(route, opts) when is_list(opts) do
    case route do
      nil ->
        raise ArgumentError,
              "ash_dspy.sa2a: project_route/2 requires a route, got nil"

      route ->
        id = opts[:signature_id] || required_route_signature_id(route)
        project(id, route, opts)
    end
  end

  defp required_route_signature_id(route) do
    case Map.get(route, :signature_id) do
      nil ->
        raise ArgumentError,
              "ash_dspy.sa2a: no :signature_id in opts nor on the route -- " <>
                "cannot derive capability identity"

      id ->
        to_string(id)
    end
  end

  @doc """
  A declaration never grants anything. Always `false`, executable rather
  than documented.
  """
  @spec grants_authority?(AgentCard.t()) :: false
  def grants_authority?(%AgentCard{} = card), do: AgentCard.grants_authority?(card)

  @doc "The standing of a projected declaration: `:declaration`."
  @spec standing(AgentCard.t()) :: :declaration
  def standing(%AgentCard{} = card), do: AgentCard.standing(card)

  @doc """
  Deterministic Turtle projection. See `AshDspy.SA2A.AgentCard.to_turtle/1`.
  """
  @spec to_turtle(AgentCard.t() | [AgentCard.t()]) :: String.t()
  def to_turtle(card_or_cards), do: AgentCard.to_turtle(card_or_cards)

  @doc "Turtle projection with optional implementation metadata comments."
  @spec to_turtle(AgentCard.t() | [AgentCard.t()], keyword()) :: String.t()
  def to_turtle(card_or_cards, opts), do: AgentCard.to_turtle(card_or_cards, opts)

  # A route is courted evidence: its execution emits a court receipt.
  # Without a route there is nothing to receipt.
  defp receipt_class(nil), do: :none
  defp receipt_class(route) when is_map(route), do: :court_receipt

  defp semantic_basis(nil), do: "ashdspy signature declaration"

  defp semantic_basis(route) when is_map(route) do
    digest =
      Map.get(route, :evidence_digest) || Map.get(route, :court_verdict) || "unknown"

    prefix = digest |> to_string() |> String.slice(0, 8)
    "ashdspy compiled route (court verdict " <> prefix <> ")"
  end

  defp signature_id(program) when is_binary(program), do: program
  defp signature_id(program) when is_atom(program) and program != nil, do: Atom.to_string(program)

  defp signature_id(program) when is_map(program) do
    with :error <- Map.fetch(program, :signature_id),
         :error <- Map.fetch(program, :id),
         :error <- Map.fetch(program, "signature_id") do
      raise ArgumentError,
            "ash_dspy.sa2a: signature program has no :signature_id -- cannot derive " <>
              "capability identity from #{inspect(program)}"
    else
      {:ok, id} -> to_string(id)
    end
  end

  defp signature_id(program) do
    raise ArgumentError,
          "ash_dspy.sa2a: cannot derive a signature id from #{inspect(program)}"
  end
end
