defmodule AshDspy.RuntimeTest do
  use ExUnit.Case, async: true

  alias AshDspy.Runtime

  @fixture_source """
  defmodule AshDspyRuntimeFixture do
    use Ash.Resource,
      domain: nil,
      extensions: [AshDspy.Resource]

    attributes do
      uuid_primary_key :id
    end

    dspy do
      signature :answer_question do
        description "Answer the question using the grounding passage."
      end

      input :question, :string, doc: "The question to answer."
      input :passage, :string
      output :answer, :string
      metric :exact_match, :accuracy
      requirement :accuracy, :gte, bound: 90
      requirement :accuracy, :lt, bound: 100
    end
  end
  """

  setup_all do
    compiled = Code.compile_string(@fixture_source)

    {fixture, _} =
      List.keyfind(compiled, AshDspyRuntimeFixture, 0) || raise "fixture not compiled"

    %{fixture: fixture}
  end

  test "signature/2 converts a real compiled resource to plain maps", %{fixture: fixture} do
    assert {:ok, signature} = Runtime.signature(fixture, :answer_question)

    assert signature.description == "Answer the question using the grounding passage."

    assert [
             %{name: :question, type: :string, doc: "The question to answer.", required: true},
             %{name: :passage, type: :string, doc: nil, required: true}
           ] = signature.inputs

    assert [%{name: :answer, type: :string, doc: nil, required: false}] = signature.outputs
  end

  test "signature/2 refuses an undeclared signature", %{fixture: fixture} do
    assert {:error, {:unknown_signature, :nope}} = Runtime.signature(fixture, :nope)
  end

  test "spec/3 builds the dspy-wasm program spec with a default module", %{fixture: fixture} do
    assert {:ok, spec} = Runtime.spec(fixture, :answer_question)
    assert spec["signature"] == "question: str, passage: str -> answer: str"
    assert spec["module"] == "predict"
    assert spec["instructions"] =~ "Answer the question using the grounding passage."
    assert spec["instructions"] =~ "question: The question to answer."

    assert {:ok, %{"module" => "chain-of-thought"}} =
             Runtime.spec(fixture, :answer_question, module: "chain-of-thought")
  end

  test "requirements/1 reads the declared bounds", %{fixture: fixture} do
    assert [
             %{dimension: :accuracy, operator: :gte, bound: 90},
             %{dimension: :accuracy, operator: :lt, bound: 100}
           ] = Runtime.requirements(fixture)
  end

  test "check_requirements/2 compares against the percent score", %{fixture: fixture} do
    reqs = Runtime.requirements(fixture)
    assert [%{pass?: true}, %{pass?: true}] = Runtime.check_requirements(reqs, 95.0)
    assert [%{pass?: false}, %{pass?: true}] = Runtime.check_requirements(reqs, 50.0)
    assert [%{pass?: true}, %{pass?: false}] = Runtime.check_requirements(reqs, 100.0)
  end

  test "interpret_run/1 maps reports to results" do
    assert {:ok, %{"answer" => "Paris"}} =
             Runtime.interpret_run(%{"state" => "ALIVE", "outputs" => %{"answer" => "Paris"}})

    assert {:error, {:refused, "bad request"}} =
             Runtime.interpret_run(%{"state" => "FAILED", "message" => "bad request"})

    assert {:error, {:unexpected_report, _}} = Runtime.interpret_run(%{"state" => "??"})
  end

  test "interpret_evaluate/2 checks requirements and maps a refusal", %{fixture: fixture} do
    assert {:ok, %{score: 95.0, results: [%{pass?: true}, %{pass?: true}]}} =
             Runtime.interpret_evaluate(fixture, %{"state" => "ALIVE", "score" => 95.0})

    assert {:error, {:refused, "no devset"}} =
             Runtime.interpret_evaluate(fixture, %{"state" => "FAILED", "message" => "no devset"})

    assert {:error, {:no_score, _}} = Runtime.interpret_evaluate(fixture, %{"state" => "ALIVE"})
  end

  test "an unmappable type is an error, not a crash" do
    assert {:error, {:unsupported_type, :weird}} =
             DspyWasm.Signature.to_spec(%{
               inputs: [%{name: :a, type: :weird, doc: nil, required: true}],
               outputs: [%{name: :b, type: :string, doc: nil, required: false}]
             })
  end

  describe "against the real component" do
    @describetag :wasm
    @describetag timeout: 300_000

    @answer "[[ ## answer ## ]]\nParis\n\n[[ ## completed ## ]]"

    setup %{fixture: fixture} do
      path =
        System.get_env("DSPY_WASM_PATH") ||
          flunk("set DSPY_WASM_PATH to a built dspy.wasm (skips are failures here)")

      lm = fn _request -> {:ok, Jason.encode!(%{"text" => @answer})} end
      {:ok, host} = DspyWasm.Host.start_link(path: path, lm: lm)
      assert :ok = DspyWasm.Host.await_ready(host)
      %{host: host, fixture: fixture}
    end

    test "run/5 returns the outputs of the resource's signature", %{host: host, fixture: fixture} do
      inputs = %{question: "capital of France?", passage: "Paris is the capital of France."}
      assert {:ok, %{"answer" => "Paris"}} = Runtime.run(host, fixture, :answer_question, inputs)
    end

    test "run/5 maps a refusal", %{host: host, fixture: fixture} do
      assert {:error, {:refused, message}} =
               Runtime.run(host, fixture, :answer_question, %{question: "x", passage: "y"},
                 module: "no-such-module"
               )

      assert is_binary(message)
    end

    test "evaluate/5 drives the requirements", %{host: host, fixture: fixture} do
      devset = [
        %{question: "France?", passage: "p", answer: "Paris"},
        %{question: "Peru?", passage: "p", answer: "Lima"}
      ]

      assert {:ok, %{score: 50.0, results: [%{pass?: false}, %{pass?: true}]}} =
               Runtime.evaluate(host, fixture, :answer_question, devset)
    end
  end
end
