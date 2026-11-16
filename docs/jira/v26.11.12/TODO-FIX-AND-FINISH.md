# TODO-FIX-AND-FINISH (ash_dspy)

Standing: UNVERIFIED

Source: `ash_surface/docs/jira/v26.11.11/PROJECT-REVIEWS.md` R3, re-read where marked confirmed.

## Fix

- HIGH `lib/ash_dspy/court/runner.ex:27-37` returns raw `apply/3` result, not `{:ok,_}`
  (confirmed). Check: a real impl passes the court in a test.
- HIGH `lib/ash_dspy/metrics/provenance.ex`, `llm_residue.ex`, `accuracy.ex` paths moved;
  bare-atom `class/0` raise and missing `{:refused,_}` clause UNVERIFIED.
- HIGH `lib/ash_dspy/court.ex:139-145` rescues into `{:refused,...}` (confirmed); whether
  `Compiler.compile/3` then refuses everything UNVERIFIED. Check: compile of a real impl succeeds.
- MED `lib/ash_dspy/court.ex:34` hard-coded bounds 1.0 for all metrics (confirmed); DSL
  requirement/metric/minimize decorative UNVERIFIED.
- MED `lib/ash_dspy/verify.ex:27-31` `check_verify_signatures` returns `:ok` with a TODO
  (confirmed). Check: a signature with no input/output fails verification.
- MED `lib/ash_dspy/sa2a/agent_card.ex:168-169` IRIs interpolated as `<...>` unescaped
  (confirmed). Check: IRI with `>` is rejected or escaped.
- MED `lib/ash_dspy/ocel.ex:111-118` `redact(attributes)` merged last, can overwrite `ocel:*`
  keys (confirmed). Check: attribute `ocel:activity` cannot override the event.
- MED `:metric` option dropped (`compiler.ex:238-239`), corpus not filtered by signature
  (`compiler.ex:198-236`), `route.ex:24` type, `receipt.ex:92-98,129` raise: UNVERIFIED.
- LOW `court.ex:80` digest via `term_to_binary` (confirmed, line ~80).
- LOW `mix.exs:21-33` deps lack `:telemetry`/`:crypto` (confirmed `extra_applications` is
  `[:logger]` only; `:crypto` is also started at runtime in court.ex).
- LOW CI tripwire vacuous (`ci.yml:57,80`), stale `priv/` cites: UNVERIFIED.

## Finish

- Add tests for the seed runtime: only `test/ash_dspy_dsl_test.exs` exists (confirmed);
  `test/support/*.ex` exist but `mix.exs` has no `elixirc_paths` (confirmed). Check: `mix test`
  exercises court, compiler, ocel, receipt, traces.
- Implement `Verify.check_verify_signatures`.
- Make README evidence-trio claim true or remove it (UNVERIFIED).

## Commit hygiene

- `HANDWRITTEN.md` untracked (confirmed `??`) but cited at `README.md:71,75` and
  `.github/workflows/ci.yml:52` (confirmed).
- Modified, uncommitted: `README.md`, `lib/ash_dspy/ocel.ex`, `lib/ash_dspy/receipt.ex`,
  `test/support/{corpus,fixtures,implementations,seams}.ex`.
Check: `git status --short` clean after commit.

## Decide

- Whether DSL requirement/metric/minimize drive court bounds or are removed.
- Whether `Court.digest` moves to canonical JSON (`compiler/canonical.ex`).

## Reuse

- `AshDspy.Compiler.Canonical.json/1` + `evidence_digest/2` (`canonical.ex:33,47`).
- OCEL deep redaction (`ocel.ex:152-163`) after the `:111-118` fix.
- `Court.Metric.resolve/1` fail-closed gating (`court.ex:148-167`).
- Atom-free JSONL traces (`traces.ex`).

## See Also

`ash_surface/docs/jira/v26.11.11/PROJECT-REVIEWS.md` · `HANDWRITTEN.md`
