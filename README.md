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

## Seed runtime API

The seed runtime compiles, judges, and receipts a program entirely in
process. `AshDspy.Compiler.compile/3` walks the candidate lattice and returns
`{:ok, route}` — the lowest-intelligence implementation that passes — or
`{:refused, term}`; the pipeline never raises. `AshDspy.Court.evaluate/4`
scores an implementation module across the `accuracy`, `determinism`,
`replay`, and `provenance` dimensions into a single
`%AshDspy.Court.Verdict{}` (gating bounds default to `>= 1.0`). Every
consequential event lands in the evidence trio: `AshDspy.Ocel` (OCEL 2.0
ndjson events), `AshDspy.Receipt` (sealed runtime receipts), and
`AshDspy.Telemetry` (`:telemetry` counters). See
`examples/ticket_triage.exs` for the end-to-end seed path.

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

Beyond the generated projections, the ABB/SBB seed runtime — the compiler
(`lib/ash_dspy/compiler/`), the court (`lib/ash_dspy/court.ex`,
`lib/ash_dspy/court/`), the execution runtime (`lib/ash_dspy/runtime/`),
the sa2a projection (`lib/ash_dspy/sa2a/`), and the cross-cutting
`ocel.ex`, `receipt.ex`, `telemetry.ex`, `traces.ex`, `metric.ex` — is
deliberately hand-written seed surface (no admitted pack expresses those
semantics yet), ledgered cluster-by-cluster in `HANDWRITTEN.md`.
Separately, `lib/ash_dspy/formatter.ex`, `scripts/format.exs`, and
`test/ash_dspy_dsl_test.exs` are hand-written generation residue the pack
does not generate (each with an UNSUPPORTED reason recorded in the
repository's lane record, commit `3b6b527`, and in `HANDWRITTEN.md`).

## Install

`mix igniter.install ash_dspy` (or `mix ash_dspy.install --target MyApp.SomeResource`)
adds the formatter plugin and the `extensions: [AshDspy.Resource]` wiring.
