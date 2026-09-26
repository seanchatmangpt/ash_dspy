defmodule AshDspy.DslTest do
  use ExUnit.Case, async: true

  # Hand-written residue, ledgered UNSUPPORTED(ash-extension-pack:composition-test-ash3-multimodule):
  # the pack's generated composition test (templates/composition_test.exs.tmpl:56)
  # destructures `[{fixture_module, _bytecode}] = Code.compile_string/1`, but an
  # Ash 3 resource compilation also emits `Inspect.<Fixture>` (and possibly other)
  # modules, so the single-element match can never succeed. This module performs
  # the same real, no-mocks verification (real compile + real Spark introspection)
  # and exercises every declared entity, the one_of schema vocabulary, and the
  # boolean defaults.

  @fixture_source """
  defmodule AshDspyDslFixture do
    use Ash.Resource,
      domain: nil,
      extensions: [AshDspy.Resource]

    attributes do
      uuid_primary_key :id
    end

    dspy do
      default_metric :accuracy
      default_minimize :token_cost

      signature :answer_question do
        description "Answer the question using the grounding passage."
      end

      input :question, :string, doc: "The question to answer."
      input :passage, :string
      output :answer, :string
      metric :exact_match, :accuracy
      requirement :accuracy, :gte, bound: 90
      minimize :token_cost
    end
  end
  """

  setup_all do
    compiled = Code.compile_string(@fixture_source)

    {fixture, _bytecode} =
      List.keyfind(compiled, AshDspyDslFixture, 0) || raise "fixture not compiled"

    %{fixture: fixture}
  end

  test "the compiled fixture actually carries the AshDspy.Resource extension", %{fixture: fixture} do
    assert AshDspy.Resource in Spark.extensions(fixture)
  end

  test "Info returns real, non-nil compiled state for the fixture", %{fixture: fixture} do
    refute is_nil(AshDspy.Resource.Info.compiled(fixture))
    assert match?({:ok, _}, AshDspy.Resource.Info.compiled_result(fixture))
    assert AshDspy.Resource.Info.compiled?(fixture)
  end

  test "dspy/1 returns every declared entity kind", %{fixture: fixture} do
    entities = AshDspy.Resource.Info.dspy(fixture)

    assert %AshDspy.Resource.Signature{name: :answer_question} =
             Enum.find(entities, &match?(%AshDspy.Resource.Signature{}, &1))

    assert %AshDspy.Resource.Input{name: :question, type: :string} =
             Enum.find(entities, &match?(%AshDspy.Resource.Input{name: :question}, &1))

    assert %AshDspy.Resource.Output{name: :answer, type: :string} =
             Enum.find(entities, &match?(%AshDspy.Resource.Output{}, &1))

    assert %AshDspy.Resource.Metric{name: :exact_match, dimension: :accuracy} =
             Enum.find(entities, &match?(%AshDspy.Resource.Metric{}, &1))

    assert %AshDspy.Resource.Requirement{dimension: :accuracy, operator: :gte, bound: 90} =
             Enum.find(entities, &match?(%AshDspy.Resource.Requirement{}, &1))

    assert %AshDspy.Resource.Minimize{objective: :token_cost} =
             Enum.find(entities, &match?(%AshDspy.Resource.Minimize{}, &1))
  end

  test "boolean field defaults from the spec apply to compiled entities", %{fixture: fixture} do
    entities = AshDspy.Resource.Info.dspy(fixture)

    question = Enum.find(entities, &match?(%AshDspy.Resource.Input{name: :question}, &1))
    assert question.required == true

    answer = Enum.find(entities, &match?(%AshDspy.Resource.Output{name: :answer}, &1))
    assert answer.required == false
  end

  test "Info getter quadruples read the compiled :dspy state", %{fixture: fixture} do
    assert match?({:ok, _}, AshDspy.Resource.Info.signature_programs_result(fixture))
    refute is_nil(AshDspy.Resource.Info.signature_programs(fixture))
    assert AshDspy.Resource.Info.signature_programs?(fixture)

    assert match?({:ok, _}, AshDspy.Resource.Info.compiled_routes_result(fixture))
    refute is_nil(AshDspy.Resource.Info.compiled_routes(fixture))

    assert match?({:ok, _}, AshDspy.Resource.Info.implementations_result(fixture))
    refute is_nil(AshDspy.Resource.Info.implementations(fixture))
  end

  test "one_of schema refuses an undeclared requirement operator" do
    bad_source = """
    defmodule AshDspyDslBadOperatorFixture do
      use Ash.Resource, domain: nil, extensions: [AshDspy.Resource]

      attributes do
        uuid_primary_key :id
      end

      dspy do
        requirement :accuracy, :band do
          bound 1
        end
      end
    end
    """

    assert_raise(Spark.Error.DslError, fn ->
      Code.compile_string(bad_source)
    end)
  end

  test "required fields are enforced: requirement without bound refuses to compile" do
    bad_source = """
    defmodule AshDspyDslNoBoundFixture do
      use Ash.Resource, domain: nil, extensions: [AshDspy.Resource]

      attributes do
        uuid_primary_key :id
      end

      dspy do
        requirement :accuracy, :gte
      end
    end
    """

    assert_raise(Spark.Error.DslError, fn ->
      Code.compile_string(bad_source)
    end)
  end
end
