# AI_HANDOFF

State of the repository at the end of the session that created the foundation.
Read this first, then `ARCHITECTURE.md` for how things fit together.

## 1. What this repository is now

Last Haven: a Godot 4.7 / GDScript Android survival game. The repository started empty
(one commit, a Godot `.gitignore`). It now contains a complete, tested Phase 0 foundation plus
the first playable milestone.

Content inventory (all loaded and validated at boot):
`items=14 recipes=5 buildables=4 loot_tables=2 resource_nodes=5 problems=0`
\- 43 GDScript files, 14 scenes, 30 data resources.

## 2. Verified in this session

Engine used for verification: **Godot 4.7.2 stable**, Linux headless binary, run from the
project root. No JDK, Android SDK or export templates were available in the workspace.

| Command | Result |
| --- | --- |
| `godot --headless --path . --import` | Clean: every script parses, every `.tres` loads, class cache builds |
| `godot --headless --path . res://tests/TestRunner.tscn` | **PASS - 139 checks, 0 failures**, stable across 3 consecutive runs |
| `godot --headless --path . --quit-after 240` | Boots the real main scene (autoloads, world, player, HUD, menu) with no script errors |

The test suite covers: definition data validation, `Inventory` (stacking/split/sort/transfer/
serialization), `CraftingSystem` (including atomic failure), `LootTable` (determinism and
probability), save slot format and metadata, deterministic world generation, structure and loot
restore, resource depletion persistence, chunk math, and one full integration pass (session
start, movement, gathering, crafting, building with cost payment, zombie detection/chase/damage,
killing a zombie, save + load round trip, death and respawn).

## 3. Not verified (be honest about this)

- **Android APK build.** `export_presets.cfg` and `.github/workflows/android-build.yml` are
  written from the documented Godot 4 Android process, but no export has ever been executed
  here. The first CI run should be treated as a debugging session.
- **CI workflows** have not been executed (no GitHub Actions runner in this workspace).
- **On-device behaviour**: touch ergonomics, performance, battery, felt input latency. Only
  headless logic and physics have been exercised.
- **Audio**: nothing exists yet.
- **Visuals**: everything is procedural placeholder geometry. No sprite, no atlas, no font
  asset (the HUD uses Godot's fallback font).

## 4. Known gaps and landmines

- `VirtualJoystick` is a **native Godot 4.7 class**. The touch stick is therefore named
  `TouchStick` (`scripts/ui/touch_stick.gd`). Do not rename it back.
- Autoload order is `GameBootstrap`, `GameEvents`, `ItemDatabase`, `SaveManager`. Bootstrap
  runs before the registry is loaded, so it must not read item counts (it logs engine/platform
  only). `ItemDatabase` logs the content summary itself.
- `Inventory.changed` carries no arguments; `InventoryComponent` republishes the inventory on
  `GameEvents.inventory_changed`. Signal signatures here are deliberate - mismatched argument
  counts silently break listeners.
- GDScript has no `Array.extend()`; use `append_array()` or a loop.
- `Interactor` reaches targets through the `interactable` group; a node that leaves that group
  (for example a plain wall) can never be prompted.
- Hit resolution uses an explicit shape query per swing (`Hitbox`), not `area_entered`. Do not
  "simplify" it back to signals: it would reintroduce missed/duplicate hits.
- World generation spacing checks are O(n^2). Fine at ~130 nodes; must become a spatial hash
  when the world grows (Phase 6).
- The test suite owns **save slot 3**. It writes and deletes that slot.
- `ItemDatabase` skips `.remap` suffixes when scanning folders, which is required for exported
  builds; keep that behaviour.
- Y-sorting depends on `y_sort_enabled` being set on `Main`, `World`, and the world's child
  containers. Adding a new world container without it will break draw order.

## 5. Where things live

| I want to change... | File |
| --- | --- |
| Session flow (menu, new game, load, death) | `scripts/main/game.gd`, `scenes/main/Main.tscn` |
| Movement, gathering, attacking, hotbar | `scripts/player/player.gd` |
| Hunger/thirst/stamina numbers | `scripts/player/survival_stats.gd` |
| World size, regions, resource distribution | `scripts/world/world_regions.gd` |
| Ground painting | `scripts/world/ground.gd` |
| Enemy behaviour | `scripts/enemies/zombie.gd` |
| Enemy population | `scripts/world/zombie_spawner.gd` |
| Building rules and placement | `scripts/building/build_system.gd` |
| Structure behaviours | `scripts/building/structure.gd` |
| Items / recipes / buildings / loot | `resources/**/*.tres` |
| HUD, panels, touch controls | `scripts/ui/*`, `scenes/ui/*` |
| Save format | `scripts/save/save_manager.gd` (+ each entity's `serialize_state`) |
| Tests | `tests/test_runner.gd` |

## 6. Next actions (in order)

1. **Run the Android workflow** (`Android build` -> Run workflow) and fix whatever the first
   real export reports. Until then the Android build is unproven.
2. **Save-slot UI**: create/overwrite/delete per slot with timestamps, and surface
   `SaveManager.get_save_metadata()` in the main menu (currently only the newest slot is
   offered).
3. **Tool durability**: consume `durability` on gathering/attacking, add repair with the
   hammer. The field already travels through `ItemStack` and the save file.
4. **Workbench** buildable plus `Recipe.required_station` enforcement (blocked crafts should
   show "needs workbench" in the crafting panel).
5. **Zombie variants** (runner, brute) and a night horde event; the spawner and detection code
   already expose the hooks.
6. **Art pass decision**: replace procedural drawing with sprites/atlases when the systems stop
   changing, and record the asset licence here before committing anything.

## 7. Working agreements

- Follow `AI_RULES.md`. Run the test suite after every change and extend it for new behaviour.
- Do not weaken checks or validation to get a green run.
- Keep `GAME_DESIGN.md`, `ARCHITECTURE.md`, `BUILD.md`, `ROADMAP.md` and this file current with
  the actual project state - this file is the contract with the next agent.
