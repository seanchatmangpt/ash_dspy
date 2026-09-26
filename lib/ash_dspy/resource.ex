defmodule AshDspy.Resource do
  @moduledoc """
  Spark.Dsl.Extension for `ash_dspy`.

  Manufactured by ash-extension-core-pack from an admitted `aex:AshExtensionSpec` --
  do not hand-edit; regenerate from the spec instead.
  """

  defmodule Signature do
    @moduledoc false

    @enforce_keys [:name]

    defstruct [
      :name,
      :description,
      :__identifier__,
      :__spark_metadata__
    ]
  end

  defmodule Input do
    @moduledoc false

    @enforce_keys [:name, :type]

    defstruct [
      :name,
      :type,
      :doc,
      :__identifier__,
      :__spark_metadata__,
      required: true
    ]
  end

  defmodule Output do
    @moduledoc false

    @enforce_keys [:name, :type]

    defstruct [
      :name,
      :type,
      :doc,
      :__identifier__,
      :__spark_metadata__,
      required: false
    ]
  end

  defmodule Metric do
    @moduledoc false

    @enforce_keys [:name, :dimension]

    defstruct [
      :name,
      :dimension,
      :doc,
      :__identifier__,
      :__spark_metadata__
    ]
  end

  defmodule Requirement do
    @moduledoc false

    @enforce_keys [:dimension, :operator]

    defstruct [
      :dimension,
      :operator,
      :bound,
      :doc,
      :__identifier__,
      :__spark_metadata__
    ]
  end

  defmodule Minimize do
    @moduledoc false

    @enforce_keys [:objective]

    defstruct [
      :objective,
      :doc,
      :__identifier__,
      :__spark_metadata__
    ]
  end

  @signature %Spark.Dsl.Entity{
    name: :signature,
    target: Signature,
    args: [:name],
    identifier: :name,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The signature's atom name, e.g. :answer_question."
      ],
      description: [
        type: :string,
        required: false,
        doc:
          "Human-readable statement of what transforms this signature's inputs into its outputs."
      ]
    ]
  }

  @input %Spark.Dsl.Entity{
    name: :input,
    target: Input,
    args: [:name, :type],
    identifier: :name,
    schema: [
      name: [type: :atom, required: true, doc: "The input field's atom name, e.g. :question."],
      type: [type: :atom, required: true, doc: "The Ash type atom for this input, e.g. :string."],
      doc: [
        type: :string,
        required: false,
        doc:
          "Human-readable description of this input; becomes part of the rendered signature prompt."
      ],
      required: [
        type: :boolean,
        required: false,
        default: true,
        doc:
          "Whether this input must be provided to every program compiled from the owning signature."
      ]
    ]
  }

  @output %Spark.Dsl.Entity{
    name: :output,
    target: Output,
    args: [:name, :type],
    identifier: :name,
    schema: [
      name: [type: :atom, required: true, doc: "The output field's atom name, e.g. :answer."],
      type: [type: :atom, required: true, doc: "The Ash type atom for this output, e.g. :string."],
      doc: [type: :string, required: false, doc: "Human-readable description of this output."],
      required: [
        type: :boolean,
        required: false,
        default: false,
        doc: "Whether an output postcondition is enforced for this field."
      ]
    ]
  }

  @metric %Spark.Dsl.Entity{
    name: :metric,
    target: Metric,
    args: [:name, :dimension],
    identifier: :name,
    schema: [
      name: [type: :atom, required: true, doc: "The metric's atom name, e.g. :exact_match."],
      dimension: [
        type: :atom,
        required: true,
        doc: "The evaluation dimension this metric measures, e.g. :accuracy."
      ],
      doc: [
        type: :string,
        required: false,
        doc: "Human-readable description of how the metric is computed."
      ]
    ]
  }

  @requirement %Spark.Dsl.Entity{
    name: :requirement,
    target: Requirement,
    args: [:dimension, :operator],
    schema: [
      dimension: [
        type: :atom,
        required: true,
        doc: "The metric dimension this requirement constrains, e.g. :accuracy."
      ],
      operator: [
        type: {:one_of, [:gte, :lte, :gt, :lt, :eq]},
        required: true,
        doc: "Comparison operator applied to the dimension's measured value."
      ],
      bound: [
        type: :integer,
        required: true,
        doc:
          "Threshold the measured value must satisfy under `operator`, in the dimension's own unit (the pack's closed field-type set has integer but no float, so bounds are expressed in whole units, e.g. percent 0-100)."
      ],
      doc: [
        type: :string,
        required: false,
        doc: "Human-readable statement of what this requirement demands."
      ]
    ]
  }

  @minimize %Spark.Dsl.Entity{
    name: :minimize,
    target: Minimize,
    args: [:objective],
    identifier: :objective,
    schema: [
      objective: [
        type: :atom,
        required: true,
        doc: "The objective to minimize, e.g. :token_cost."
      ],
      doc: [
        type: :string,
        required: false,
        doc: "Human-readable statement of what minimizing this objective means."
      ]
    ]
  }

  @dspy %Spark.Dsl.Section{
    name: :dspy,
    describe: "Declares DSPy-style semantic signatures on an Ash resource.",
    schema: [
      default_metric: [type: :atom],
      default_minimize: [type: :atom]
    ],
    entities: [
      @signature,
      @input,
      @output,
      @metric,
      @requirement,
      @minimize
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@dspy],
    transformers: [AshDspy.Resource.Persist],
    verifiers: [AshDspy.Resource.Verify]
end
