# AI_HANDOFF

State of the repository after the foundation session, Android build session,
and the gameplay upgrade session.
Read this first, then `ARCHITECTURE.md` for how things fit together.

## 1. What this repository is now

Last Haven: a Godot 4.7 / GDScript Android survival game. The repository started empty
(one commit, a Godot `.gitignore`). It now contains a complete, tested Phase 0 foundation,
the first playable milestone, a visual upgrade pass, and a gameplay systems upgrade.

Content inventory (all loaded and validated at boot):
`items=18 recipes=9 buildables=4 loot_tables=2 resource_nodes=5 problems=0`
- 51 GDScript files, 15 scenes, 35 data resources.

### Gameplay upgrade (this session)

Major new systems added:

- **Equipment system**: `EquipmentComponent` manages gear in 5 slots (head, body, backpack, weapon, tool). Equipment provides stat bonuses:
  - Head/body gear adds damage reduction (armor)
  - Backpack adds inventory capacity
  - Weapons add attack damage
  - ItemDefinition now has an `EquipmentSlot` enum and `equipment_slot` field

- **Tool durability**: Tools/weapons now degrade with use. ItemStack has a native `durability` field. When durability reaches 0, the tool breaks and is removed from inventory. Durability is displayed as a color-coded bar (green→yellow→red) in inventory slots.

- **Floating damage numbers**: `DamageNumber` scene spawns at hit locations, rises and fades. Color-coded: white for normal, yellow for crits (>15 dmg), green for heals. Works for both player damage received and zombie damage dealt.

- **Screen shake**: Player takes damage with camera shake for visual feedback.

- **World zone props**: `WorldProps` node draws decorative environmental objects per region:
  - Forest: fallen logs, mushrooms, stumps, small rocks
  - Rural: fences, hay bales, road signs, puddles, dried bushes
  - Town: abandoned cars, rubble piles, broken fences, sidewalk cracks, trash, damaged mailboxes
  - Industrial: shipping containers, barrel clusters, metal debris, oil stains, pallets

- **Save slot UI**: Main menu now supports 5 save slots (increased from 3) with:
  - Slot selection with visual highlighting
  - Timestamps, day count, survival time display
  - Delete button with confirmation dialog
  - Scrollable slot list

- **Equipment display in inventory**: Inventory panel shows an equipment column with slot labels, equipped item names, and stat bonus summary.

- **Extensible character animation system**: A new `CharacterAnimator` architecture separates gameplay logic from visual rendering:
  - `CharacterAnimator` (base class): defines the animation state machine with 11 states (IDLE, WALK, RUN, SPRINT, ATTACK, HURT, DEATH, GATHER, INTERACT, EQUIP, FALL), facing direction tracking, frame-based animation, and equipment layer drawing
  - `ProceduralCharacterAnimator`: default implementation preserving the current procedural `_draw()` art, with added walk cycle animation, idle bobbing, hurt flash, sprint dust particles, and gather progress indicator
  - `SpriteCharacterAnimator`: template for future sprite/model integration with AnimationPlayer and AnimatedSprite2D support
  - The Player script delegates ALL rendering to the animator — swapping character models requires only replacing the animator node
  - Equipment layers (backpack, helmet, body armor) draw on top of the base character with proper z-ordering
  - Animation states drive visual feedback: walking limb swing, idle breathing bob, hurt flash overlay, death transition

- **Extensible zombie animation system** (mirrors the player's CharacterAnimator pattern):
  - `ZombieAnimator` (base class): defines zombie-specific animation states (IDLE, WANDER, CHASE, ATTACK, SEARCH, RETURN, HURT, DEATH), facing tracking, frame-based animation, and variant color management
  - `ProceduralZombieAnimator`: default implementation preserving all 4 variant drawing methods (Standard, Heavy, Fast, Special) with added walk cycle animation, idle sway, hurt flash, and variant-specific eye glow
  - The Zombie script delegates ALL rendering to the animator — swapping zombie models requires only replacing the animator node
  - Zombie.State (gameplay) maps to ZombieAnimator.AnimState (visual) via `update_from_zombie()`
  - Compatible with existing AI: the Zombie's behaviour state machine is untouched; only the rendering layer is abstracted

### New items and recipes

| Item | Slot/Type | Recipe |
|------|-----------|--------|
| Leather Helmet | Head (armor) | 3 scrap + 2 cloth + 2 fiber |
| Leather Armor | Body (armor) | 5 scrap + 4 cloth + 3 fiber + 2 wood |
| Military Backpack | Backpack (+4 slots) | 4 scrap + 3 cloth + 4 fiber |
| Repair Kit | Consumable (repair) | 2 scrap + 1 stone |

### Visual upgrade (previous session)

All major entities now have recognizable procedural artwork (no longer generic rectangles):
- **Player**: detailed survivor with boots, jacket, belt, arms, head with hair/face, equipment-dependent weapon display, attack arc visual, equipment helmet display, and a proper corpse state.
- **Zombies**: 4 visual variants (Standard, Heavy, Fast, Special) with distinct silhouettes, clothing, body shapes, and color palettes. Each variant has weighted spawn probability and stat scaling.
- **Resource nodes**: improved trees, rocks, bushes, and scrap piles with organic shapes.
- **Ground**: multi-layered terrain with grass tufts, dirt patches, pebbles, twigs, region transition blending, and a procedural abandoned road.
- **Structures**: walls with plank seams, doors with hinges/handles, storage crates with reinforcement straps.
- **Hotbar**: upgraded to 8 slots with category-based border colors, durability bars, and quantity badges.

## 2. Verified in this session

Engine used for verification: **Godot 4.7.2 stable**, Linux headless binary, run from the
project root. The Android export was verified with a locally installed JDK 17 + Android SDK + export templates, and then independently in GitHub Actions.

| Command | Result |
| --- | --- |
| `godot --headless --path . --import` | Clean: every script parses, every `.tres` loads, class cache builds |
| `godot --headless --path . res://tests/TestRunner.tscn` | **PASS - 159+ checks, 0 failures** |
| `godot --headless --path . --quit-after 240` | Boots the real main scene with no script errors |

The test suite covers: definition data validation, `Inventory`, `CraftingSystem`, `LootTable`, save slot format, deterministic world generation, structure/loot restore, resource depletion, chunk math, equipment system (equip/unequip/stat bonuses/serialization), tool durability, and one full integration pass (session start, movement, gathering, crafting, equipment, building, zombie combat, save/load, death/respawn).

## 3. Not verified (be honest about this)

- **On-device behaviour.** No Android device or emulator was available.
- **Audio**: nothing exists yet.
- **Visuals**: all entity and world visuals are procedural artwork via `_draw()`. No sprite atlas or external art assets exist yet.
- **Equipment visual effects**: helmet and backpack are drawn on the player procedurally. Full sprite-based equipment overlays need real art assets.
- **Repair kit consumption**: the repair_kit item exists but no repair mechanic is wired yet (the item is crafted but using it doesn't currently repair tools). This needs a `_on_repair_used` handler in the player.

## 4. Known gaps and landmines

- `VirtualJoystick` is a **native Godot 4.7 class**. The touch stick is therefore named `TouchStick` (`scripts/ui/touch_stick.gd`). Do not rename it back.
- Autoload order is `GameBootstrap`, `GameEvents`, `ItemDatabase`, `SaveManager`. Bootstrap runs before the registry is loaded.
- `Inventory.changed` carries no arguments; `InventoryComponent` republishes the inventory on `GameEvents.inventory_changed`.
- GDScript has no `Array.extend()`; use `append_array()` or a loop.
- `Interactor` reaches targets through the `interactable` group.
- Hit resolution uses an explicit shape query per swing (`Hitbox`), not `area_entered`.
- World generation spacing checks are O(n^2). Fine at ~130 nodes; must become a spatial hash when the world grows (Phase 6).
- The test suite owns **save slot 3**. It writes and deletes that slot.
- `ItemDatabase` skips `.remap` suffixes when scanning folders.
- Y-sorting depends on `y_sort_enabled` being set on `Main`, `World`, and the world's child containers.
- **Android export is fussy about exact names and paths.** See `BUILD.md` section 3.
- `project.godot` must keep `rendering/textures/vram_compression/import_etc2_astc=true`.
- Each CI run generates a **fresh** debug keystore.
- `gh workflow run` returns `HTTP 403` (managed integration lacks `actions:write`).
- `ItemStack.durability` is a native field (not meta). Always use `stack.durability`, never `stack.get_meta("durability")`.
- `EquipmentComponent` is created dynamically in `Player._ready()` and added as a child node. It is NOT in the Player.tscn scene file.
- `WorldProps` is a child of World with z_index=-5 (between Ground at -10 and ResourceNodes at default 0).
- Recipe categories: TOOLS=0, WEAPONS=1, SURVIVAL=2, CONSTRUCTION=3, UTILITIES=4.
- ItemDefinition categories: MATERIAL=0, TOOL=1, WEAPON=2, CONSUMABLE=3, FOOD=4, BUILDING=5, MISC=6.
- EquipmentSlot enum: NONE=0, HEAD=1, BODY=2, BACKPACK=3, WEAPON=4, TOOL=5.
- CharacterAnimator is a Node2D child of the Player. It draws in its own `_draw()` callback (not the Player's). The Player calls `character_animator.queue_redraw()` each physics frame.
- AnimState enum: IDLE=0, WALK=1, RUN=2, SPRINT=3, ATTACK=4, HURT=5, DEATH=6, GATHER=7, INTERACT=8, EQUIP=9, FALL=10.
- Facing enum: DOWN=0, UP=1, LEFT=2, RIGHT=3.
- Player._setup_animator() checks for an existing CharacterAnimator child first; if none, creates ProceduralCharacterAnimator dynamically.
- Player.set_animator() swaps the animator at runtime — useful for model changes during gameplay.
- ZombieAnimator is a Node2D child of the Zombie. It draws in its own `_draw()` callback (not the Zombie's). The Zombie calls `zombie_animator.queue_redraw()` each physics frame.
- ZombieAnimState enum: IDLE=0, WANDER=1, CHASE=2, ATTACK=3, SEARCH=4, RETURN=5, HURT=6, DEATH=7.
- Zombie._setup_animator() checks for an existing ZombieAnimator child first; if none, creates ProceduralZombieAnimator dynamically.
- Zombie.set_animator() swaps the animator at runtime.
- Zombie visual_variant maps to ProceduralZombieAnimator drawing methods: 0=Standard, 1=Heavy, 2=Fast, 3=Special.

## 5. Where things live

| I want to change... | File |
| --- | --- |
| Session flow (menu, new game, load, death) | `scripts/main/game.gd`, `scenes/main/Main.tscn` |
| Movement, gathering, attacking, hotbar | `scripts/player/player.gd` |
| Character animation system (base) | `scripts/player/character_animator.gd` |
| Procedural character renderer | `scripts/player/procedural_character_animator.gd` |
| Sprite character template | `scripts/player/sprite_character_animator.gd` |
| Hunger/thirst/stamina numbers | `scripts/player/survival_stats.gd` |
| Equipment bonuses and slots | `scripts/inventory/equipment_component.gd` |
| World size, regions, resource distribution | `scripts/world/world_regions.gd` |
| Ground painting | `scripts/world/ground.gd` |
| World decorative props | `scripts/world/world_props.gd` |
| Enemy behaviour | `scripts/enemies/zombie.gd` |
| Zombie animation system (base) | `scripts/enemies/zombie_animator.gd` |
| Procedural zombie renderer | `scripts/enemies/procedural_zombie_animator.gd` |
| Enemy population | `scripts/world/zombie_spawner.gd` |
| Building rules and placement | `scripts/building/build_system.gd` |
| Structure behaviours | `scripts/building/structure.gd` |
| Items / recipes / buildings / loot | `resources/**/*.tres` |
| HUD, panels, touch controls | `scripts/ui/*`, `scenes/ui/*` |
| Inventory panel + equipment display | `scripts/ui/inventory_panel.gd` |
| Main menu save slot selection | `scripts/ui/main_menu.gd` |
| Hotbar with durability display | `scripts/ui/item_slot_button.gd` |
| Floating damage numbers | `scripts/combat/damage_number.gd` |
| Item definitions + equipment slot | `scripts/items/item_definition.gd` |
| Save format | `scripts/save/save_manager.gd` (+ each entity's `serialize_state`) |
| Tests | `tests/test_runner.gd` |

## 6. Next actions (in order)

1. **Wire the repair kit**: make using a repair_kit restore durability to the active tool.
2. **Integrate sprite-based character model**: replace ProceduralCharacterAnimator with SpriteCharacterAnimator once art assets are available.
3. **Integrate sprite-based zombie model**: create a SpriteZombieAnimator for zombie art assets, supporting per-variant sprite sheets.
3. **Drag-and-drop inventory**: implement touch-based drag-and-drop for hotbar/equipment slots.
4. **Combat expansion (Milestone 6)**: weapon-specific attack animations via the animator's state machine, hit effects, ranged weapons.
4. **Traps and explosives (Milestone 5)**: spike trap, bear trap, grenade system.
5. **Audio (Milestone 8)**: footsteps, gathering, combat, zombie sounds, UI clicks.
6. **World zones (Milestone 7)**: stronger visual differentiation between regions (different ground textures, region-specific ambient effects).
7. **Workbench** buildable plus `Recipe.required_station` enforcement.

## 7. Working agreements

- Follow `AI_RULES.md`. Run the test suite after every change and extend it for new behaviour.
- Do not weaken checks or validation to get a green run.
- Keep `GAME_DESIGN.md`, `ARCHITECTURE.md`, `BUILD.md`, `ROADMAP.md` and this file current with the actual project state - this file is the contract with the next agent.
