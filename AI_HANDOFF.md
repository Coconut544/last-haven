# AI_HANDOFF

State of the repository after the foundation session and the Android build session.
Read this first, then `ARCHITECTURE.md` for how things fit together.

## 1. What this repository is now

Last Haven: a Godot 4.7 / GDScript Android survival game. The repository started empty
(one commit, a Godot `.gitignore`). It now contains a complete, tested Phase 0 foundation plus
the first playable milestone, and a visual upgrade pass (Milestones 1+2).

Content inventory (all loaded and validated at boot):
`items=14 recipes=5 buildables=4 loot_tables=2 resource_nodes=5 problems=0`
\- 43 GDScript files, 14 scenes, 30 data resources.

### Visual upgrade (this session)

All major entities now have recognizable procedural artwork (no longer generic rectangles):
- **Player**: detailed survivor with boots, jacket, belt, arms, head with hair/face, equipment-dependent weapon display, attack arc visual, and a proper corpse state.
- **Zombies**: 4 visual variants (Standard, Heavy, Fast, Special) with distinct silhouettes, clothing, body shapes, and color palettes. Each variant has weighted spawn probability and stat scaling (heavy=slow/tough, fast=quick/fragile, special=glowing veins/biohazard).
- **Resource nodes**: improved trees (layered canopy with branches), rocks (organic polygons with cracks), bushes (branch structure with berries), and scrap piles (irregular stacked shapes).
- **Ground**: multi-layered terrain with grass tufts, dirt patches, pebbles, twigs, region transition blending strips, and a procedural abandoned road through the rural/town zones.
- **Structures**: walls with plank seams and cross-beams, doors with hinges/handles, storage crates with reinforcement straps and metal brackets.
- **Hotbar**: upgraded from 5 to 8 slots.
- **ItemSlotButton**: category-based border colors (red=weapon, orange=tool, green=material, blue=consumable, brown=building), hover state, quantity badge.

## 2. Verified in this session

Engine used for verification: **Godot 4.7.2 stable**, Linux headless binary, run from the
project root. The Android export was verified with a locally installed JDK 17 + Android SDK +
export templates, and then independently in GitHub Actions.

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

### 2.1 Android build (verified)

The debug APK now builds for real. Build environment, all versions pinned in the workflow:

| Component | Version |
| --- | --- |
| Godot | 4.7.2 stable (`Godot_v4.7.2-stable_linux.x86_64`) |
| Export templates | 4.7.2.stable (`android_debug.apk`, `android_release.apk`, `android_source.zip`) |
| JDK | Temurin 17 (verified with 17.0.20.1) - required because the export runs `apksigner` |
| Android SDK | `platform-tools`, `build-tools;36.0.0`, `platforms;android-36` (matches the template's targetSdk 36) |
| Artifact | `build/android/last-haven.apk`, 28,656,730 bytes, signed (APK Signature Scheme v2 + v3) |

| Evidence | Result |
| --- | --- |
| Local `--export-debug` (same flags as CI) | APK produced and signed; identical byte size to the CI artifact |
| GitHub Actions `Android build` run [35508726118](https://github.com/Coconut544/last-haven/actions/runs/35508726118) (push to `main`, cache miss) | **success** - every step green including APK validation and artifact upload |
| GitHub Actions `Android build` run [35508835085](https://github.com/Coconut544/last-haven/actions/runs/35508835085) (later `main`, cache hit) | **success** - same result through the cached-templates path, with the Godot install step skipped, and with `actions/setup-java@v5` |
| GitHub Actions `Validate` runs 35508726142 and 35508835110 | success - 139 checks, 0 failures on each of the Android commits |
| Both uploaded artifacts, downloaded and re-verified outside CI | sha256 matches the hash each run reported; zip integrity OK; `application-id com.lasthaven.game`; `version 0.1.0` (code 1); `min-sdk 24`; `target-sdk 36`; contains `/lib/arm64-v8a/libgodot_android.so` and `/assets/assets.sparsepck`; `apksigner verify` passes |

The first real CI run (35508672957) failed in `android-actions/setup-android@v3`, which runs
`sdkmanager tools` as part of its default package list; that legacy package no longer exists in
the SDK repository. The action was removed in favour of locating the runner's SDK and installing
only the three packages the export uses.

## 3. Not verified (be honest about this)

- **On-device behaviour.** No Android device or emulator was available. The emulator route is
  also blocked by design: the preset builds **arm64-v8a only**, so an x86_64 emulator image
  cannot run it. Launch, touch ergonomics, performance, battery and felt input latency are
  therefore unverified - the arm64 APK needs a physical device.
- **A crash-free launch of the *APK*.** What is verified is that the same project boots headless
  with no script errors, and that the exported artifact contains the engine binary and the packed
  game data. That is not the same as watching an installed APK start.
- **Audio**: nothing exists yet.
- **Visuals**: all entity and world visuals are now detailed procedural artwork (not simple
  rectangles). No sprite atlas or external art assets exist yet — all drawing is done via `_draw()`
  calls. The visual quality is recognizable and consistent but will eventually benefit from
  sprite/texture replacement for performance and polish.

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
- **Android export is fussy about exact names and paths.** `export/android/java_sdk_path` is
  mandatory (the export runs `apksigner`), and the editor settings file is version specific:
  `~/.config/godot/editor_settings-<major>.<minor>.tres` (`editor_settings-4.7.tres` for 4.7.2).
  A wrongly named file is ignored silently. See `BUILD.md` section 3.
- `project.godot` must keep `rendering/textures/vram_compression/import_etc2_astc=true`, or every
  Android export fails with "ETC2/ASTC texture compression is required".
- Each CI run generates a **fresh** debug keystore, so two CI-built APKs have different signing
  certificates and cannot upgrade over one another (`adb install` requires an uninstall first).
  Use one stable local debug keystore for device work.
- `gh workflow run` against these workflows returns `HTTP 403` (the managed integration has no
  `actions: write`). Trigger builds by pushing to `main`, opening a PR against `main`, or from
  the Actions tab.
- A `pull_request` synchronize event did **not** start any workflow run for the PR that the
  managed integration itself opened (see section 5); pushes to `main` do trigger runs, which is
  why the Android workflow is anchored there.
- Every CI run generates a **new** debug key, so each APK has a different certificate and a
  different sha256 even though the byte size is stable at 28,656,730. That is expected.
- CI still warns that `actions/checkout@v4`, `actions/cache@v4` and `actions/upload-artifact@v4`
  target the deprecated Node 20 runtime (they are forced onto Node 24 and still work), and that
  `ubuntu-latest` migrates to Ubuntu 26 on 2026-10-19. `actions/setup-java` was already moved to
  `@v5`, which cleared its deprecation warning.

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

1. **Install the debug APK on a physical arm64 device** (download `last-haven-debug-apk` from
   the latest `Android build` run) and smoke-test launch, the touch stick, gathering and frame
   time. This is the only part of the pipeline CI cannot cover.
2. **Equipment system (Milestone 2)**: add `EquipmentSlot` enum to `ItemDefinition`, create
   equipment slots (head, body, backpack, weapon, tool) in the inventory panel, and make
   equipment affect gameplay (backpack = inventory capacity, armor = damage reduction).
3. **Drag-and-drop inventory (Milestone 3)**: implement touch-based drag-and-drop for
   assigning items to hotbar slots and equipment slots.
4. **Save-slot UI**: create/overwrite/delete per slot with timestamps, and surface
   `SaveManager.get_save_metadata()` in the main menu.
5. **Tool durability**: consume `durability` on gathering/attacking, add repair with the
   hammer.
6. **Workbench** buildable plus `Recipe.required_station` enforcement.
7. **Combat expansion (Milestone 6)**: weapon-specific attack animations, hit effects,
   damage numbers, ranged weapons.
8. **Traps and explosives (Milestone 5)**: spike trap, bear trap, grenade system.
9. **World zones (Milestone 7)**: forest/road/ruins/industrial visual differentiation.
10. **Audio (Milestone 8)**: footsteps, gathering, combat, zombie sounds, UI clicks.

## 7. Working agreements

- Follow `AI_RULES.md`. Run the test suite after every change and extend it for new behaviour.
- Do not weaken checks or validation to get a green run.
- Keep `GAME_DESIGN.md`, `ARCHITECTURE.md`, `BUILD.md`, `ROADMAP.md` and this file current with
  the actual project state - this file is the contract with the next agent.
