defmodule AshDspy.SA2A.AgentCard do
  @moduledoc """
  RFC-SA2A-001 S10 -- a semantic capability declaration for an `AshDspy`
  compiled signature or route.

  ## Mirrored shape, not a copy

  This struct mirrors `AshA2A.Semantic.AgentCard` field-for-field: the same
  12 enforced keys, in the same order. `ash_a2a` is deliberately *not* a
  dependency of this project -- the shape is modeled locally by contract so
  a consumer of either declaration reads one vocabulary with one anti-grant
  discipline. Field names and the `to_turtle/1` predicate order are pinned
  to ash_a2a's `lib/ash_a2a/semantic/agent_card.ex`.

  ## A declaration is not a grant

  This is the single most important property of this struct and it is
  enforced, not merely stated. A `%AshDspy.SA2A.AgentCard{}` says "machinery
  exists here with this shape". It says nothing about whether the reader may
  invoke it. `grants_authority?/1` returns `false` unconditionally,
  `standing/1` returns `:declaration`, and the struct carries no authority
  token, no capability handle and no credential of any kind. A peer that
  reads a declaration and proceeds to act has not been authorized by this
  module. `authority_requirement` states what a caller would need. Stating
  a requirement is the opposite of satisfying it.

  ## Observational by construction

  An `AshDspy` signature is a typed observation of a computation: it declares
  inputs, outputs and evidence, never world-changing consequence. Every card
  projected from one carries `consequence_class: :observe`,
  `authority_requirement: :none` and empty `preconditions`/`effects`. When a
  compiled route exists, the card's `receipt_class` upgrades to
  `:court_receipt` -- naming the receipt an execution would emit -- but the
  anti-grant functions never change.

  ## Provider neutrality

  No vendor, model or provider identity ever enters a declaration. When
  implementation identity is needed at all it is described only by its
  implementation *class* and module name, and even that lives in optional
  turtle metadata comments (see `to_turtle/2`) -- never in the capability
  identity and never as a struct field.
  """

  @enforce_keys [
    :capability_iri,
    :input_shape,
    :output_shape,
    :preconditions,
    :effects,
    :consequence_class,
    :authority_requirement,
    :receipt_class,
    :planner_compatibility,
    :cost_envelope,
    :semantic_basis,
    :version
  ]
  defstruct [
    :capability_iri,
    :input_shape,
    :output_shape,
    :preconditions,
    :effects,
    :consequence_class,
    :authority_requirement,
    :receipt_class,
    :planner_compatibility,
    :cost_envelope,
    :semantic_basis,
    :version
  ]

  @type consequence_class :: :observe
  @type authority_requirement :: :none
  @type receipt_class :: :none | :court_receipt

  @type t :: %__MODULE__{
          capability_iri: String.t(),
          input_shape: String.t(),
          output_shape: String.t(),
          preconditions: [],
          effects: [],
          consequence_class: consequence_class(),
          authority_requirement: authority_requirement(),
          receipt_class: receipt_class(),
          planner_compatibility: [],
          cost_envelope: :unbounded | %{optional(atom()) => term()},
          semantic_basis: String.t(),
          version: String.t()
        }

  @doc """
  A declaration never grants anything. Always `false`.

  Present as a real function rather than a sentence in a moduledoc so a
  caller can assert on it and a reader can grep for it. (ash_a2a names this
  `grant?/1`; the ash_dspy contract pins `grants_authority?/1`.)
  """
  @spec grants_authority?(t()) :: false
  def grants_authority?(%__MODULE__{}), do: false

  @doc "The standing a declaration carries: `:declaration`. Never `:admitted`."
  @spec standing(t()) :: :declaration
  def standing(%__MODULE__{}), do: :declaration

  @doc """
  Deterministic RDF projection of a declaration, as Turtle.

  Mirrors ash_a2a's `to_turtle/1` shape: `sa2a:` prefixed predicates emitted
  in a fixed field order so the Turtle text is byte-stable for a given
  declaration. Plain string building only -- no RDF dependency. The
  `sa2a:grantsAuthority "false"` triple is always present.

  Accepts a single declaration or a list; a list is sorted by
  `capability_iri` before projection so the output is independent of input
  order.
  """
  @spec to_turtle(t() | [t()]) :: String.t()
  def to_turtle(declarations), do: to_turtle(declarations, [])

  @doc """
  `to_turtle/1` plus optional implementation metadata comments.

  Provider neutrality holds here too: the only implementation identity a
  turtle document may carry is its *class* and module name, emitted as
  Turtle comments between the prefix block and the body, never as
  predicates on the capability. Pass either:

    * `implementation: {class, module}` -- e.g. `{:compute, MyApp.Route}`
    * `implementation: route` -- any map/struct readable with
      `Map.get(route, :class)` and `Map.get(route, :implementation_module)`,
      so `%AshDspy.Runtime.Route{}` works without a compile-time dependency
    * `implementation: "free text"` -- emitted verbatim as a comment
  """
  @spec to_turtle(t() | [t()], keyword()) :: String.t()
  def to_turtle(%__MODULE__{} = declaration, opts), do: to_turtle([declaration], opts)

  def to_turtle(declarations, opts) when is_list(declarations) do
    body =
      declarations
      |> Enum.sort_by(& &1.capability_iri)
      |> Enum.map_join("\n", &declaration_turtle/1)

    comment_block =
      case implementation_comment_lines(opts) do
        [] -> ""
        lines -> Enum.map_join(lines, "\n", &("# " <> &1)) <> "\n"
      end

    """
    @prefix sa2a: <urn:sa2a:vocab#> .
    @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .

    """
    |> Kernel.<>(comment_block)
    |> Kernel.<>(body)
  end

  # Predicate order mirrors ash_a2a's declaration_turtle/1 exactly:
  # inputShape, outputShape, consequenceClass, authorityRequirement,
  # receiptClass, semanticBasis, version, costEnvelope, grantsAuthority,
  # then precondition*, effect*, plannerCompatibility*.
  defp declaration_turtle(%__MODULE__{} = declaration) do
    lines =
      [
        {"sa2a:inputShape", "<" <> declaration.input_shape <> ">"},
        {"sa2a:outputShape", "<" <> declaration.output_shape <> ">"},
        {"sa2a:consequenceClass", quoted(declaration.consequence_class)},
        {"sa2a:authorityRequirement", quoted(declaration.authority_requirement)},
        {"sa2a:receiptClass", quoted(declaration.receipt_class)},
        {"sa2a:semanticBasis", quoted(declaration.semantic_basis)},
        {"sa2a:version", quoted(declaration.version)},
        {"sa2a:costEnvelope", quoted(declaration.cost_envelope)},
        # Pinned contract: the anti-grant triple is a quoted string literal
        # (sa2a:grantsAuthority "false"), not an unquoted Turtle boolean --
        # contract wins over ash_a2a's raw `false` here.
        {"sa2a:grantsAuthority", "\"false\""}
      ] ++
        Enum.map(declaration.preconditions, &{"sa2a:precondition", quoted(&1)}) ++
        Enum.map(declaration.effects, &{"sa2a:effect", quoted(&1)}) ++
        Enum.map(declaration.planner_compatibility, &{"sa2a:plannerCompatibility", quoted(&1)})

    predicates = Enum.map_join(lines, " ;\n", fn {p, o} -> "  " <> p <> " " <> o end)

    "<" <>
      declaration.capability_iri <>
      "> rdf:type sa2a:CapabilityDeclaration ;\n" <> predicates <> " .\n"
  end

  defp implementation_comment_lines(opts) do
    case Keyword.fetch(opts, :implementation) do
      {:ok, description} when is_binary(description) -> [description]
      {:ok, {class, module}} -> ["class=" <> to_string(class) <> " module=" <> to_string(module)]
      {:ok, route} when is_map(route) -> route_comment_lines(route)
      {:ok, other} -> [to_string(other)]
      :error -> []
    end
  end

  # Implementation identity is class + module name only. Deliberately no
  # model, vendor, or provider field is read here.
  defp route_comment_lines(route) do
    class = Map.get(route, :class)
    module = Map.get(route, :implementation_module)

    case {class, module} do
      {nil, nil} -> []
      {nil, module} -> ["module=" <> to_string(module)]
      {class, nil} -> ["class=" <> to_string(class)]
      {class, module} -> ["class=" <> to_string(class) <> " module=" <> to_string(module)]
    end
  end

  defp quoted(value) when is_binary(value), do: escaped(value)
  defp quoted(value) when is_atom(value), do: "\"" <> Atom.to_string(value) <> "\""
  defp quoted(value), do: escaped(inspect(value))

  defp escaped(value) do
    replaced =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")

    "\"" <> replaced <> "\""
  end
end
