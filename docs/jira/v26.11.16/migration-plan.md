# ash_dspy migration plan v26.11.16

Standing: UNVERIFIED

## Identity
- Path: /Users/sac/ash_dspy
- Remote: https://github.com/seanchatmangpt/ash_dspy.git
- Branch@sha: feat/v26926-ashdspy-abb-sbb-seed@e3dcc4f (upstream origin/same), last 2026-10-07,
  5 commits
- Size: 185 MB
- Languages/build: Elixir (mix.exs, mix.lock), ggen.toml/ggen.lock, ontology.ttl
- Nested repos: none

## Observed state
- Dirty 7 (M): README.md, lib/ash_dspy/{ocel,receipt}.ex,
  test/support/{corpus,fixtures,implementations,seams}.ex
- Untracked 2: HANDWRITTEN.md, docs/ (contains docs/jira/v26.11.12)
- ahead 0 / behind 0, stash 0. Other branches: main, modep/preserve-20260926T1930Z-ashdspy
  (both tracked on origin).
- No _build or deps dir present (185 MB is mostly git objects/templates).

## What it is
DSPy-style semantic signature DSL for Ash resources, manufactured by ggen from the
ash-extension-pack ontology.

## Classification
ACTIVE (census). Feature branch with in-flight edits from October.

## Migration risk
MEDIUM. 7 modified source/test files + HANDWRITTEN.md + docs/ are uncommitted and would be lost.
Everything committed is pushed.

## Recommended action
COMMIT-PUSH
1. `cd /Users/sac/ash_dspy && git diff --stat`
2. `git add -A && git commit -m "wip(ash_dspy): ocel/receipt edits, handwritten ledger, jira docs"`
3. `git push origin feat/v26926-ashdspy-abb-sbb-seed`
4. `rm -rf _build deps` (if present at migration time)
5. Clone fresh on new machine; check out the feature branch.

## First commands on the new machine
`mix deps.get && mix compile && mix test`

## See Also
- ../v26.11.12/
- /Users/sac/docs/jira/v26.11.16/README.md
