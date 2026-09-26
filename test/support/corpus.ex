defmodule AshDspy.TestSupport.Corpus do
  @moduledoc """
  Lane 9 inline triage corpus (ashdspy-001).

  priv/corpus/triage/ (lane 6) was absent at lane-9 start, so the suite carries
  an equivalent INLINE corpus implementing the mission-documented rule:

    * ticket mentions refund / invoice / charge  -> team "billing"
    * else ticket mentions error / crash / bug   -> team "technical"
    * else                                       -> team "general"
    * urgency "high" iff an urgent word is present AND team != "general"
      (urgent words: urgent, asap, immediately, outage, production down,
      revenue); general is always "low".

  Keyword matching is case-insensitive substring matching. Billing outranks
  technical when both keyword families appear (first-match priority law).

  Also ships a DIVERGENT mini-corpus whose expected values deliberately break
  the rule -- the falsified variant the equivalence court runs against.
  """

  @billing_words ~w(refund invoice charge)
  @technical_words ~w(error crash bug)
  @urgent_words ~w(urgent asap immediately outage "production down" revenue)

  @typed_example %{
    id: :atom,
    input: %{ticket: :string},
    expected: %{urgency: :string, team: :string}
  }

  @doc "Keyword sets of the rule, for tests that pin the rule's vocabulary."
  def billing_words, do: @billing_words
  def technical_words, do: @technical_words
  def urgent_words, do: @urgent_words

  @doc """
  The rule itself: `#{inspect(@typed_example)}`-shaped input -> output.
  """
  def triage(ticket) when is_binary(ticket) do
    lower = String.downcase(ticket)

    cond do
      Enum.any?(@billing_words, &String.contains?(lower, &1)) ->
        team("billing", lower)

      Enum.any?(@technical_words, &String.contains?(lower, &1)) ->
        team("technical", lower)

      true ->
        %{urgency: "low", team: "general"}
    end
  end

  defp team(team_word, lower) do
    urgency =
      if Enum.any?(@urgent_words, &String.contains?(lower, &1)), do: "high", else: "low"

    %{urgency: urgency, team: team_word}
  end

  @doc """
  The rule-derivable corpus: every expected value is EXACTLY what
  `triage/1` computes. >= 12 examples per mission.
  """
  def corpus do
    [
      {"billing_low", "Please refund my invoice #1234"},
      {"billing_high", "URGENT: double charge on our account, refund immediately"},
      {"billing_low_2", "Question about an invoice line item"},
      {"billing_high_2", "We were charged twice, this is urgent"},
      {"technical_low", "Small bug in the report export"},
      {"technical_high", "The app crashes on login and this is blocking us, urgent"},
      {"technical_low_2", "Minor error message wording nit"},
      {"technical_high_2", "Production outage: full crash of the ingest pipeline, revenue impact"},
      {"general_low", "Where do I find the changelog?"},
      {"general_low_2", "Thanks for the release notes, great work"},
      {"general_low_3", "What license does the project use?"},
      {"mixed_priority", "Charge refunded, but the portal shows an error too"},
      {"case_insensitive", "REFUND REQUEST (ASAP)"},
      {"empty_boundary", ""}
    ]
    |> Enum.map(fn {id, ticket} ->
      %{id: id, input: %{ticket: ticket}, expected: triage(ticket)}
    end)
  end

  @doc """
  Divergent mini-corpus (>= 3 examples): expected values deliberately BREAK
  the rule, so a rule-faithful candidate must FAIL the accuracy dimension.
  """
  def divergent_corpus do
    [
      {"div_billing", "Please refund my invoice", %{urgency: "high", team: "technical"}},
      {"div_technical", "App crashes with an error", %{urgency: "low", team: "billing"}},
      {"div_general", "What license does the project use?", %{urgency: "high", team: "billing"}}
    ]
    |> Enum.map(fn {id, ticket, expected} ->
      %{id: id, input: %{ticket: ticket}, expected: expected}
    end)
  end

  @doc "One corpus entry rendered as a JSONL map (string keys), for file tests."
  def to_jsonl_map(%{id: id, input: input, expected: expected}) do
    %{
      "id" => to_string(id),
      "input" => stringify(input),
      "expected" => stringify(expected)
    }
  end

  @doc "The corpus as a JSONL string (one JSON object per line, trailing newline)."
  def to_jsonl(corpus) do
    corpus
    |> Enum.map(&Jason.encode!(to_jsonl_map(&1)))
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), to_string(v)} end)
end
