# HANDWRITTEN

Hand-written residue the `ash-extension-pack` does not generate. Each row
carries an `UNSUPPORTED` reason recorded in the lane record (commit `3b6b527`);
the ledger shrinks monotonically as the pack grows the missing capability.
Cluster rows (added 2026-09-27) cover the ABB/SBB seed surface from commit
`5d985d5`, one row per directory cluster.

| path | semantic element | missing capability | intended owner pack | date |
|---|---|---|---|---|
| `lib/ash_dspy/formatter.ex` | Spark.Formatter plugin the generated installer registers | pack ships no formatter template | `ash-extension-pack` | 2026-09-25 |
| `scripts/format.exs` | canonical plugin-free format pass | mix format write mode does not converge with `--check-formatted` on the generated installer | `ash-extension-pack` | 2026-09-25 |
| `test/ash_dspy_dsl_test.exs` | full-`dspy`-fixture composition test | generated composition test template is defective against Ash 3 multi-module `compile_string` | `ash-extension-pack` | 2026-09-25 |
| `lib/ash_dspy/compiler/` — `compiler.ex`, `candidate.ex`, `canonical.ex` | DSPy compile seed: `AshDspy.Compiler.compile/3` pipeline, candidate enumeration in lattice order, canonical corpus serialization/evidence digests | ABB/SBB seed: no admitted pack expresses DSPy compile semantics | `ash-extension-pack` | 2026-09-27 |
| `lib/ash_dspy/court.ex`, `lib/ash_dspy/court/` — `runner.ex`, `verdict.ex`, `metrics/accuracy.ex`, `metrics/determinism.ex`, `metrics/llm_residue.ex`, `metrics/null.ex`, `metrics/provenance.ex`, `metrics/replay.ex` | ABB/SBB seed: the court — implementation-vs-corpus evaluation (`AshDspy.Court`), runner, verdict struct, and the 6 court metrics | ABB/SBB seed: no admitted pack expresses evaluation-court semantics | `ash-extension-pack` | 2026-09-27 |
| `lib/ash_dspy/runtime/` — `route.ex`, `implementation.ex`, `lattice.ex`, `program.ex`, `implementations/compose.ex`, `implementations/constraint.ex`, `implementations/generate.ex`, `implementations/llm.ex`, `implementations/plan.ex`, `implementations/reuse.ex`, `implementations/rule.ex`, `implementations/specialized_model.ex` | ABB/SBB seed: execution runtime — evidence-bound routes, implementation behaviour, precedence lattice over the 8 implementation classes, runtime program view, and the 8 implementations themselves | ABB/SBB seed: no admitted pack expresses runtime/implementation-lattice semantics | `ash-extension-pack` | 2026-09-27 |
| `lib/ash_dspy/sa2a/` — `sa2a.ex`, `agent_card.ex` | ABB/SBB seed: RFC-SA2A-001 S10 projection — compiled signature to semantic agent card | ABB/SBB seed: no admitted pack expresses agent-card projection semantics | `ash-extension-pack` | 2026-09-27 |
| `lib/ash_dspy/ocel.ex`, `lib/ash_dspy/receipt.ex`, `lib/ash_dspy/telemetry.ex`, `lib/ash_dspy/traces.ex`, `lib/ash_dspy/metric.ex` | ABB/SBB seed: cross-cutting evidence/telemetry — OCEL 2.0 event emission, capability-operation receipts, `:telemetry` helpers, DSPy trace-file transport, court metric behaviour | ABB/SBB seed: no admitted pack expresses seed evidence/telemetry semantics | `ash-extension-pack` | 2026-09-27 |
