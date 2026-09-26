defmodule AshDspy.Runtime.Lattice do
  @moduledoc """
  Precedence lattice over the 8 implementation classes.

  Lower intelligence rank = higher precedence = tried first. The order is
  fixed: reuse(1) compose(2) rule(3) plan(4) constraint(5) generate(6)
  specialized_model(7) llm(8).

  `lowest_intelligence/2` is the selection primitive: lower wins; on equal
  intelligence the winner is the class that sorts first by class name, so the
  same inputs always produce the same winner (deterministic tiebreak, no
  ambient state, no randomness).
  """

  @precedence [
    reuse: 1,
    compose: 2,
    rule: 3,
    plan: 4,
    constraint: 5,
    generate: 6,
    specialized_model: 7,
    llm: 8
  ]

  @type class ::
          :reuse
          | :compose
          | :rule
          | :plan
          | :constraint
          | :generate
          | :specialized_model
          | :llm

  @doc "All 8 lattice classes in precedence order (rank 1 first)."
  @spec classes() :: [class(), ...]
  def classes, do: Keyword.keys(@precedence)

  @doc "Intelligence rank of `class` (1 = highest precedence). Raises `ArgumentError` on an unknown class — selection never silently accepts an unranked class."
  @spec intelligence(class()) :: pos_integer()
  def intelligence(class) when is_atom(class) do
    case Keyword.fetch(@precedence, class) do
      {:ok, rank} ->
        rank

      :error ->
        raise ArgumentError,
              "AshDspy.Runtime.Lattice.intelligence/1: unknown implementation class #{inspect(class)}"
    end
  end

  @doc """
  Returns the lower-intelligence of `class_a` and `class_b` (lower wins).

  On equal intelligence the winner is the class name that sorts first —
  deterministic, so the same inputs always yield the same winner.
  Raises `ArgumentError` on an unknown class.
  """
  @spec lowest_intelligence(class(), class()) :: class()
  def lowest_intelligence(class_a, class_b) when is_atom(class_a) and is_atom(class_b) do
    rank_a = intelligence(class_a)
    rank_b = intelligence(class_b)

    cond do
      rank_a < rank_b ->
        class_a

      rank_b < rank_a ->
        class_b

      true ->
        if Atom.to_string(class_a) <= Atom.to_string(class_b) do
          class_a
        else
          class_b
        end
    end
  end
end
