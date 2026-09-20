# Last Haven

Open-world post-apocalyptic survival for Android. Built with **Godot 4.7** and **GDScript**.

You are a survivor in a world that ended quietly. Gather what is left, craft the tools you
need, raise a shelter, and hold it through the night.

> **Project state: Phase 0 complete + the first playable milestone (Phase 1 slice).**
> The foundation is real and tested: world generation, gathering, inventory, crafting,
> base building, a complete zombie AI, melee combat, survival stats, day/night, local
> saving and a touch-first HUD. All art is procedural placeholder geometry - no binary
> assets yet, by design.

## Current state

| Area | Status |
| --- | --- |
| Godot project, autoloads, input map, Android export preset | Done |
| Data-driven content (items, recipes, building pieces, resource nodes, loot tables) | Done - 14 items, 5 recipes, 4 buildables, 5 resource types, 2 loot tables |
| Deterministic world generation + region table | Done - one 3072 x 3072 prototype world, 4 regions |
| Player: movement, sprint, camera, gathering, melee, survival stats, modular equipment slots | Done |
| Inventory with stacking, splitting, sorting, transfers, containers | Done |
| Crafting (all-or-nothing, data-driven) | Done |
| Base building: grid snap, ghost preview, collision + cost validation, doors, storage | Done |
| Zombie AI: idle, wander, detect (sight/noise/night), chase, attack, search, return, death, loot | Done |
| Day/night cycle affecting lighting and enemy detection | Done |
| Save/load: atomic JSON slots, world + player + structures + containers | Done |
| Touch HUD: virtual stick, action buttons, hotbar, inventory, crafting, build menu | Done |
| Headless test suite (139 checks) + GitHub Actions validate workflow | Done |
| Android APK via GitHub Actions | Workflow written, **not yet executed** - see `BUILD.md` |
| Multiplayer, PvP, base raiding, large-world streaming | Not started (designed for, see `ROADMAP.md`) |

## Requirements

- **Godot 4.7.x** (standard, non-Mono). The project is validated against **4.7.2**.
- For Android exports: JDK 17, the Android SDK, and the Godot export templates (see `BUILD.md`).

## Run it

1. Open the project folder in Godot (4.7.x).
2. Press **F5** (or run `godot --path .`).
3. **New Game** starts a run. Touch controls work with a mouse too (touch emulation is on).

Desktop shortcuts: `WASD`/arrows move, `Shift` sprint, `Space` attack, `E` interact,
`I` inventory, `C` crafting, `B` build, `R` rotate while placing, `Esc` pause, `F5`/`F9` save/load.

## Test it

```bash
# Headless test suite (unit + integration). Exits non-zero on failure.
godot --headless --path . res://tests/TestRunner.tscn

# Boot the real game headlessly for 180 frames and check for script errors.
godot --headless --path . --quit-after 180
```

Both commands run in CI on every push (`.github/workflows/validate.yml`).

## Repository layout

```
project.godot            Godot project: autoloads, input map, layers, mobile settings
export_presets.cfg       Android debug export preset (no secrets)
scenes/                  main, world, player, enemies, loot, ui  (14 scenes)
scripts/                 core, items, inventory, crafting, loot, combat,
                         building, world, player, enemies, save, ui, main
resources/               items, recipes, buildings, nodes, loot  (30 data .tres files)
tests/                   headless test runner
.github/workflows/       validate.yml, android-build.yml
```

## Documentation

| File | Contents |
| --- | --- |
| `GAME_DESIGN.md` | Gameplay, systems, balance numbers and content tables |
| `ARCHITECTURE.md` | Technical design: layers, systems, data flow, save format, multiplayer path |
| `DEVELOPMENT.md` | Workflow, conventions, how to add content, debugging |
| `BUILD.md` | Local and CI builds, Android setup, signing policy |
| `ROADMAP.md` | Development phases and current position |
| `AI_RULES.md` | Rules for AI agents working on this repository |
| `AI_HANDOFF.md` | Current state and next actions for the next agent |

## Assets and licensing

All visuals are drawn procedurally in code (coloured shapes) and all audio is absent so far.
That keeps the repository free of copyrighted or unclear-licensed material while the systems
are built. Any future asset pack must be original, commissioned, or licensed for commercial
use, and recorded here before it is committed.
