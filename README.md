# ash_dspy

DSPy-style semantic signature DSL for Ash resources, manufactured by
[ggen](https://github.com/seanchatmangpt/ggen-marketplace) from the
`ash-extension-pack` ontology (`ontology.ttl`, vocabulary `aex:`).

Declare typed inputs, outputs, metrics, requirement bounds, and minimization
objectives on any `Ash.Resource` via a single `dspy` section:

```elixir
defmodule MyApp.Answer do
  use Ash.Resource, extensions: [AshDspy.Resource]

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
```

Introspect with `AshDspy.Resource.Info` (`dspy/1`, `compiled/1`,
`signature_programs/1`, `compiled_routes/1`, `implementations/1`, each with
`_result/1`, `!/1`, `?/1` forms).

## Regeneration

`lib/ash_dspy/{resource,persist,verify,info}.ex` and the Igniter installer are
**generated projections** of `ontology.ttl` — never hand-edit them. Edit the
ontology, then re-run the sync procedure:

1. Render the pack templates scoped to this repo's ontology. (The plain Rust
   `ggen sync run` unions the pack's own fixture ontology into the data graph
   and leaks other specs' files into this repo — recorded as
   `UNSUPPORTED(ggen:rust-e2e-ash-extension-pack)`; the scoped renderer follows
   the `packs/ash-extension-pack/verify/render_check.exs` pattern.)
2. `mix run scripts/format.exs` — canonical, plugin-free format pass.
3. `mix format --check-formatted` (must stay green), `mix compile
   --warnings-as-errors`, `mix test`.

`lib/ash_dspy/formatter.ex`, `scripts/format.exs`, and
`test/ash_dspy_dsl_test.exs` are hand-written residue the pack does not
generate (each with an UNSUPPORTED reason in the repo's lane record /
HANDWRITTEN.md).

## Install

`mix igniter.install ash_dspy` (or `mix ash_dspy.install --target MyApp.SomeResource`)
adds the formatter plugin and the `extensions: [AshDspy.Resource]` wiring.
