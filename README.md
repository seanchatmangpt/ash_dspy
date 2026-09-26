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

## WebAssembly runtime

`ash_dspy` executes DSPy through the `dspy-wasm` WASI-P2 component; it does
not embed CPython in the BEAM. The admitted producer is pinned in
`priv/dspy-wasm.lock.json`, and its WIT + machine-readable consumer contract
are vendored under `priv/`.

Start a component by supplying the built `dspy.wasm` and an LM callback.
The callback receives DSPy's decoded LM request; returning a string supplies
completion text, while returning a map supplies the full LM response envelope.

```elixir
{:ok, dspy} =
  AshDspy.Wasm.start_link(
    path: System.fetch_env!("DSPY_WASM_PATH"),
    lm: fn request ->
      MyApp.LM.complete(request)
    end,
    tools: %{
      search: fn %{"query" => query} -> MyApp.Search.run(query) end
    }
  )

{:ok, report} =
  AshDspy.run(
    dspy,
    MyApp.Answer,
    :answer_question,
    %{question: "Capital of France?", passage: "Paris is the capital of France."},
    module: :chain_of_thought
  )
```

The same resource can be sent to `AshDspy.render/5`, `AshDspy.evaluate/5`,
and `AshDspy.compile/5`. A `compile` result's `"program_state"` can be
passed back as `program_state:` to later `run` calls; dspy-wasm enforces
subject binding on that state.

Provider/network authority and host-tool authority remain outside the
component. They cross only `chatman:dspy/lm@0.1.0` and
`chatman:dspy/tools@0.1.0`.

### Real component court

The normal suite verifies projection and ABI wiring without rebuilding the
large WASI dependency closure. To execute the full Ash -> Wasmex -> dspy-wasm
path against a built component:

```bash
DSPY_WASM_PATH=/path/to/dspy-wasm/dist/dspy.wasm mix test --include wasm
```

