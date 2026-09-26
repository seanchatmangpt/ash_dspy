defmodule AshDspy.WasmProjectionFixture do
  use Ash.Resource,
    domain: nil,
    extensions: [AshDspy.Resource]

  attributes do
    uuid_primary_key :id
  end

  dspy do
    default_metric(:accuracy)
    default_minimize(:token_cost)

    signature :answer_question do
      description "Answer the question using the grounding passage."
    end

    input(:question, :string, doc: "Question to answer.")
    input(:passage, :string, doc: "Grounding passage.")
    output(:answer, :string, doc: "Grounded answer.")
    metric(:exact_match, :accuracy)
    requirement(:accuracy, :gte, bound: 90)
    minimize(:token_cost)
  end
end

defmodule AshDspy.WasmProjectionTest do
  use ExUnit.Case, async: true

  alias AshDspy.Program
  alias AshDspy.Wasm

  @resource AshDspy.WasmProjectionFixture

  test "projects Ash entities to the dspy-wasm structured signature" do
    assert {:ok, program} = Program.spec(@resource, :answer_question)

    assert program["module"] == "predict"
    assert program["signature"]["instructions"] ==
             "Answer the question using the grounding passage."

    assert program["signature"]["inputs"] == %{
             "passage" => %{"type" => "str", "desc" => "Grounding passage."},
             "question" => %{"type" => "str", "desc" => "Question to answer."}
           }

    assert program["signature"]["outputs"] == %{
             "answer" => %{"type" => "str", "desc" => "Grounded answer."}
           }
  end

  test "runtime options stay data and reach the component request" do
    state = %{"__subject__" => %{"signature" => "fixture"}}

    assert {:ok, request} =
             Program.run_request(
               @resource,
               "answer_question",
               %{question: "Capital of France?", passage: "Paris is the capital of France."},
               module: :chain_of_thought,
               adapter: :json,
               program_state: state,
               request: %{trace: true}
             )

    assert request["module"] == "chain-of-thought"
    assert request["adapter"] == "json"
    assert request["program_state"] == state
    assert request["trace"] == true

    assert request["inputs"] == %{
             "question" => "Capital of France?",
             "passage" => "Paris is the capital of France."
           }
  end

  test "compile request uses the declared metric and optimizer vocabulary" do
    trainset = [
      %{question: "Capital of France?", passage: "Paris is in France.", answer: "Paris"}
    ]

    assert {:ok, request} =
             Program.compile_request(@resource, :answer_question, trainset,
               optimizer: :bootstrap_few_shot,
               config: %{max_bootstrapped_demos: 1}
             )

    assert request["metric"] == "exact_match"
    assert request["optimizer"] == "bootstrap-few-shot"
    assert request["config"] == %{"max_bootstrapped_demos" => 1}
    assert request["trainset"] == [
             %{
               "question" => "Capital of France?",
               "passage" => "Paris is in France.",
               "answer" => "Paris"
             }
           ]
  end

  test "evaluation report is checked against Ash requirement bounds" do
    admitted = Program.assess(@resource, "exact_match", %{"score" => 95.0})
    refused = Program.assess(@resource, "exact_match", %{"score" => 80.0})

    assert admitted["ash_dspy"]["requirements_met"] == true
    assert admitted["ash_dspy"]["requirements"] == [
             %{
               "dimension" => "accuracy",
               "operator" => "gte",
               "bound" => 90,
               "actual" => 95.0,
               "met" => true
             }
           ]

    assert refused["ash_dspy"]["requirements_met"] == false
  end

  test "host imports exactly match the admitted WIT namespaces" do
    imports =
      Wasm.imports(
        fn request ->
          assert is_list(request["messages"])
          "Paris"
        end,
        echo: fn args -> args end
      )

    assert Map.keys(imports) |> Enum.sort() ==
             ["chatman:dspy/lm@0.1.0", "chatman:dspy/tools@0.1.0"]

    {:fn, complete} = imports["chatman:dspy/lm@0.1.0"]["complete"]
    {:fn, call_tool} = imports["chatman:dspy/tools@0.1.0"]["call"]

    assert Jason.decode!(complete.(Jason.encode!(%{"messages" => []}))) == %{
             "text" => "Paris"
           }

    assert Jason.decode!(call_tool.("echo", Jason.encode!(%{"x" => 1}))) == %{
             "result" => %{"x" => 1}
           }
  end

  test "vendored contract is the exact component boundary this host admits" do
    contract = Wasm.contract()

    assert contract["component"] == "dspy-wasm"
    assert contract["component_version"] == Wasm.component_version_requirement()
    assert contract["target"] == "wasm32-wasip2"
    assert contract["world"] == "dspy"

    assert contract["imports"] == %{
             "chatman:dspy/lm@0.1.0" => ["complete"],
             "chatman:dspy/tools@0.1.0" => ["call"]
           }

    assert Enum.sort(contract["exports"]) ==
             Enum.sort(~w(
               component-version runtime-info dspy-version run-self-tests predict
               capabilities run render evaluate compile
             ))
  end

  @tag :wasm
  test "executes the Ash resource through the real dspy-wasm component" do
    path = System.fetch_env!("DSPY_WASM_PATH")

    lm = fn _request ->
      "[[ ## answer ## ]]\nParis\n\n[[ ## completed ## ]]"
    end

    assert {:ok, pid} = Wasm.start_link(path: path, lm: lm)

    assert {:ok, %{"state" => "ALIVE", "outputs" => %{"answer" => "Paris"}}} =
             AshDspy.run(
               pid,
               @resource,
               :answer_question,
               %{
                 question: "What is the capital of France?",
                 passage: "Paris is the capital of France."
               }
             )
  end
end
