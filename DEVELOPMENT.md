# Last Haven - Development Guide

## 1. Prerequisites

- Godot **4.7.x** standard build (the project is validated against 4.7.2). No Mono, no plugins.
- Optional: JDK 17 + Android SDK + Godot export templates for local Android builds (`BUILD.md`).

## 2. Everyday commands

```bash
# Run the game (or press F5 in the editor)
godot --path .

# Headless test suite - exits non-zero when something fails
godot --headless --path . res://tests/TestRunner.tscn

# Import assets and refresh the class cache after adding scripts/scenes
godot --headless --path . --import

# Boot the real game headlessly for N frames (catches runtime errors in the full stack)
godot --headless --path . --quit-after 180
```

Always run the test suite before considering work done. When you add a new script, run
`--import` once so the global class cache is updated before anything references the class.

## 3. Code conventions

- **Typed GDScript.** Annotate variables, parameters and return types. Use `-> void` and
  explicit `Array[Ingredient]`/`Dictionary` types where they help.
- **Tabs** for indentation (Godot default), max ~100 columns.
- **One responsibility per script.** If a file needs a table of contents, split it.
- **Signals over direct UI calls.** Gameplay raises events on `GameEvents`; UI listens.
- **No hidden global state.** Autoloads are limited to the four listed in `ARCHITECTURE.md`.
  Session and entity state live on the session/entity, never in a static variable.
- **Document intent, not mechanics.** A short `##` block explaining what a script owns and why
  beats line-by-line comments. Comment the non-obvious (a workaround, a tuning reason).
- **Never leave dead code or commented-out blocks.** Delete it; Git remembers.
- **Data files over constants.** Tuning numbers that a designer would change belong in `.tres`.

## 4. Adding content

### A new item
1. Copy an existing file in `resources/items/` (for example `wood.tres`) to `<id>.tres`.
2. Set `id` (must match the file name by convention), `display_name`, `description`, category,
   stack size, weight, placeholder colour/glyph, and any tool/combat/consumable numbers.
3. Run the tests: `ItemDatabase` validates every file and fails the run on problems.

### A new recipe
1. Copy a file in `resources/recipes/`.
2. Set `id`, `display_name`, `category`, `output_item_id`, `output_quantity`, and add one
   `Ingredient` sub-resource per input.
3. Items referenced by the recipe must exist; validation checks this.

### A new building piece
1. Copy a file in `resources/buildings/`.
2. Pick a `behaviour`: `SOLID` (blocks), `DOOR` (blocks until opened), `STORAGE` (has an
   inventory, set `storage_capacity`), `DECORATION` (walkable, e.g. floors).
3. Set `cost`, `max_health`, `occupancy`, `collision_size` and colours. Leave `scene_path` at
   the default unless the piece needs its own scene.

### A new resource node type
1. Copy a file in `resources/nodes/`.
2. Choose a `visual` (`TREE`, `ROCK`, `BUSH`, `PILE`) and colours, then set gathering numbers,
   `preferred_tool`, `yields` and `respawn_time`.
3. To place it in the world, add it to a region's `resources` weights in
   `scripts/world/world_regions.gd`.

### A new loot table
1. Copy a file in `resources/loot/`.
2. Add `LootEntry` sub-resources (`min`/`max` quantity, `chance`, `weight`, `rarity`).
3. `guaranteed_rolls` are weighted picks that always award something; `chance_rolls` test every
   entry against its own `chance`.

### A new system
1. Put the rules in a plain script (a `RefCounted` or static functions) so it is testable
   without a scene tree - follow `CraftingSystem` and `Inventory` as the model.
2. Wrap it in a node only when it needs the tree (physics, timers, signals).
3. Emit changes on `GameEvents` rather than calling UI.
4. Add a suite to `tests/test_runner.gd` that fails when the rules break.

## 5. Testing

The runner is intentionally dependency-free (no GUT/addons). Add checks with
`check(condition, description)` / `check_equal(actual, expected, description)` /
`check_near(actual, expected, tolerance, description)` inside a suite function, and call
`report("suite name")` at the end. Integration tests may `await get_tree().physics_frame`.

Rules for tests:
- A test that only checks "it did not crash" is not a test. Assert behaviour.
- Never disable or weaken a check to get a green run. Fix the code or the expectation,
  whichever is actually wrong (and say which in the commit message).
- Test data problems are real bugs: the data validation suite must stay empty of problems.

## 6. Debugging

- `game_bootstrap` logs one boot line; `ItemDatabase` logs a content summary (counts and
  problems) at startup. Missing or broken `.tres` files are reported there.
- The HUD is optional: comment out its node or run the game with the session inactive and the
  gameplay still runs headlessly, which is how the integration test works.
- `ChunkStreamer.enabled = false` keeps everything awake while investigating a streaming bug.
- `GameWorld.density_multiplier` changes resource density without touching the region table.
- Tuning that is easy to reach for: `Zombie.detection_radius`, `SurvivalStats.*_drain`,
  `DayNightCycle.day_length_seconds`, `BuildSystem.GRID_SIZE`.

## 7. Git and review

- Keep commits focused: one system or fix per commit, with a message that says why.
- Do not commit: `build/`, exported binaries, keystores, `export_credentials.cfg`, `.godot/`.
  All are in `.gitignore`; keep it that way.
- Update `ARCHITECTURE.md` when a seam changes, `GAME_DESIGN.md` when gameplay numbers or
  rules change, and `AI_HANDOFF.md` at the end of any substantial work session.
