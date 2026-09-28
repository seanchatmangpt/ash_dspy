# Hand-written residue

`lib/ash_dspy/{resource,persist,verify,info}.ex` and the Igniter installer are
generated projections of `ontology.ttl` (see README, "Regeneration"). Everything
listed here is hand-written and is not touched by regeneration. Each entry
carries an UNSUPPORTED reason.

| file | reason |
|---|---|
| `lib/ash_dspy/formatter.ex` | Hand-written residue the ash-extension-pack does not generate. |
| `scripts/format.exs` | Hand-written residue: canonical, plugin-free format pass used after regeneration. |
| `test/ash_dspy_dsl_test.exs` | `UNSUPPORTED(ash-extension-pack:composition-test-ash3-multimodule)`: the pack's generated composition test destructures a single compiled module, but an Ash 3 resource compile emits several. |
| `lib/ash_dspy/runtime.ex` | `UNSUPPORTED(ash-extension-pack:runtime-host-integration)`: the pack projects the DSL and its introspection only; it has no template for executing a signature on a host. This module translates the compiled `dspy` entities for the dspy-wasm Elixir host (`dspy_wasm`) and checks `requirement`s against `evaluate` scores. |
| `test/ash_dspy_runtime_test.exs` | `UNSUPPORTED(ash-extension-pack:runtime-host-integration)`: tests for `lib/ash_dspy/runtime.ex`. Unit tests need no wasm; the `@tag :wasm` test boots the real component and needs `DSPY_WASM_PATH`. |
| `test/test_helper.exs` | Excludes the `:wasm` tag unless `DSPY_WASM_PATH` is set. |
