defmodule AshDspy.TestSupport.Implementations do
  @moduledoc false
end

defmodule AshDspy.TestSupport.RuleTriage do
  @moduledoc """
  A REAL `AshDspy.Runtime.Implementation` behaviour implementation at class
  `:rule` (intelligence 3): `run/2` executes the inline corpus rule directly
  and deterministically. This is the Machine(x) half of the equivalence court.
  """

  @behaviour AshDspy.Runtime.Implementation

  @impl true
  def class, do: :rule

  @impl true
  def intelligence, do: 3

  @impl true
  def run(%{ticket: ticket} = _input, _ctx), do: {:ok, AshDspy.TestSupport.Corpus.triage(ticket)}

  def run(input, _ctx) when is_map(input),
    do: {:ok, AshDspy.TestSupport.Corpus.triage(Map.get(input, "ticket", ""))}

  def run(_input, _ctx), do: {:refused, :invalid_input}
end

defmodule AshDspy.TestSupport.StubLLM do
  @moduledoc """
  A REAL behaviour implementation at class `:llm` (intelligence 8): `run/2`
  delegates to the injected stub fn under `:llm` in ctx. NO network, NO real
  model -- the fn IS the model. Tests inject `AshDspy.TestSupport.llm_stub/1`
  so the "LLM" equals the rule (equivalence court) or is taught divergent
  answers (falsified variant).
  """

  @behaviour AshDspy.Runtime.Implementation

  @impl true
  def class, do: :llm

  @impl true
  def intelligence, do: 8

  @impl true
  def run(input, ctx) do
    llm = ctx[:llm] || ctx["llm"]

    if is_function(llm) do
      case llm.(input, ctx) do
        {:ok, _} = ok -> ok
        {:refused, _} = refused -> refused
        map when is_map(map) -> {:ok, map}
      end
    else
      {:refused, :no_llm_adapter}
    end
  end
end

defmodule AshDspy.TestSupport.BrokenRule do
  @moduledoc """
  A behaviour implementation at class `:rule` that outputs the WRONG answer on
  every input: urgency/team always the divergent corner. Court must fail it
  with reasons -- the anti-vacuity half of the court tests.
  """

  @behaviour AshDspy.Runtime.Implementation

  @impl true
  def class, do: :rule

  @impl true
  def intelligence, do: 3

  @impl true
  def run(_input, _ctx), do: {:ok, %{urgency: "high", team: "general"}}
end

defmodule AshDspy.TestSupport.FlakyRule do
  @moduledoc """
  A behaviour implementation at class `:rule` whose output is
  NON-deterministic: parity of `:erlang.unique_integer/1` flips the team
  between two values while staying shape-valid. The court's determinism /
  replay dimension must fail it.
  """

  @behaviour AshDspy.Runtime.Implementation

  @impl true
  def class, do: :rule

  @impl true
  def intelligence, do: 3

  @impl true
  def run(input, _ctx) do
    ticket =
      case input do
        %{ticket: t} -> t
        %{"ticket" => t} -> t
        _ -> ""
      end

    team = if :erlang.unique_integer([:positive, :monotonic]) |> rem(2) == 0 do
      "general"
    else
      "billing"
    end

    {:ok, AshDspy.TestSupport.Corpus.triage(ticket) |> Map.put(:team, team)}
  end
end
