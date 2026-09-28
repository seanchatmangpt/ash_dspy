# The :wasm integration test boots the real dspy-wasm component (about a minute).
# It runs when DSPY_WASM_PATH is set; `mix test --include wasm` without the
# variable runs it and it fails, it does not skip.
exclude = if System.get_env("DSPY_WASM_PATH"), do: [], else: [:wasm]
ExUnit.start(exclude: exclude)
