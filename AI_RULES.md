# Last Haven - Rules for AI Agents

Binding rules for any AI agent working in this repository. They exist because unverified
"progress" is worse than no progress: it hides real state and costs more to undo than to do
right the first time.

## 1. Before changing anything

1. Inspect the repository: `README.md`, `ARCHITECTURE.md`, `GAME_DESIGN.md`, and
   `AI_HANDOFF.md` (current state and open work).
2. Find the system you are about to touch and read it fully. Read its callers.
3. Identify whether the change is data (a `.tres` file) or code. Prefer data.
4. Make the smallest correct change that satisfies the request. Do not refactor adjacent code.

## 2. Never

- Never fabricate files, APIs, function signatures, plugins or dependencies. If you are unsure
  whether something exists, check it in the repository or run the engine.
- Never claim something works when you have not run it. Say exactly what you ran and what you
  observed.
- Never guess a Godot API: verify by running the project headlessly.
- Never weaken, skip or delete a test to make a run pass. If a test's expectation is wrong, fix
  the expectation and say so in the commit message.
- Never disable error handling, validation or the data validation suite.
- Never commit secrets, keystores, `export_credentials.cfg`, `build/` output or `.godot/`.
- Never rewrite a working system without a written reason in `ARCHITECTURE.md`.
- Never create a second implementation of a system that already exists.
- Never remove working features to simplify a task.
- Never trust client-side values for anything valuable when adding networked code.

## 3. Always

- Run the test suite after a change:
  `godot --headless --path . res://tests/TestRunner.tscn`
- Run `--import` once after adding a script or scene (global class cache).
- Add or extend tests for any behaviour you add: the runner has `check`, `check_equal` and
  `check_near` helpers, and integration tests may `await get_tree().physics_frame`.
- Keep code typed, modular and documented where intent is not obvious.
- Keep gameplay free of UI references; use `GameEvents`.
- Keep new content data-driven, with validation in the definition's `validate()`.
- Update the relevant documentation in the same change: `GAME_DESIGN.md` for gameplay,
  `ARCHITECTURE.md` for structure or seams, `BUILD.md` for build changes, `ROADMAP.md` for
  phase status, and `AI_HANDOFF.md` at the end of the session.
- Report honestly: what changed, what you verified, what you could not verify and why.

## 4. Error handling loop

When something fails:

```
read the actual error -> find the root cause -> fix the cause -> re-run -> verify
```

Never hide an error, never add a workaround that masks it, never move on with a failing check.

## 5. Change control

- One system or fix per commit; explain *why* in the message.
- Do not silently change architecture. If a change affects seams described in
  `ARCHITECTURE.md`, update that document in the same commit.
- If a change would be large, implement the smallest useful slice first, verify it, and record
  the remainder in `ROADMAP.md` or `AI_HANDOFF.md`.

## 6. Scope discipline

The project is a commercial-grade game built incrementally. Do not rush toward a feature list.
A system is finished when it is **implemented -> tested -> verified -> documented**, and not
before. Partial work is acceptable; unverified claims are not.
