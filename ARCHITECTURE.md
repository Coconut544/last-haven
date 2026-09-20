# Last Haven - Architecture

Godot 4.7 / GDScript. Android first. This document describes how the project is put together
and why, so changes can be made without breaking the seams.

## 1. Principles

1. **Data over code.** Items, recipes, building pieces, resource nodes and loot tables are
   `.tres` resources. Adding content means adding a file, not editing a system.
2. **Small systems with one job.** Health, inventory, crafting, loot, building, perception and
   persistence each live in their own script and communicate by signals.
3. **Gameplay never knows about UI.** Gameplay emits events on a bus; the HUD listens. Tests
   run the game with no HUD at all.
4. **Simplicity first, expansion second.** Every system has the simplest implementation that
   is correct, with the seams a bigger version will need (chunks, save format, ownership,
   server-callable state functions) already in place.
5. **Verification is part of the work.** Anything added must be exercised by the headless test
   runner or explicitly marked as untested.

## 2. Autoloads (4)

| Autoload | Script | Owns | Notes |
| --- | --- | --- | --- |
| `GameBootstrap` | `scripts/core/game_bootstrap.gd` | Nothing | Registers input actions if missing, applies runtime settings, logs one boot line |
| `GameEvents` | `scripts/core/game_events.gd` | Nothing | Signal bus; no state, no logic |
| `ItemDatabase` | `scripts/items/item_database.gd` | Read-only definition registry | Loads every `.tres` under `res://resources/`, validates it, exposes lookups by id |
| `SaveManager` | `scripts/save/save_manager.gd` | Save slots | Serializes the session; owns no gameplay data |

Anything else is a scene node. There is deliberately no `GameState` singleton: session state
lives in `Game` (the main scene root), entity state lives on the entity.

## 3. Scene tree

```
Main (Node2D, scripts/main/game.gd, y-sorted)
├── World (GameWorld)
│   ├── Ground            (WorldGround)        procedural terrain painting, z = -10
│   ├── ResourceNodes     (y-sorted)
│   ├── Structures        (y-sorted)
│   ├── LootBags          (y-sorted)
│   ├── Enemies           (y-sorted)
│   ├── EnemySpawner      (ZombieSpawner)
│   ├── DayNightCycle     (DayNightCycle, owns a CanvasModulate)
│   └── ChunkStreamer     (ChunkStreamer)
├── Player (Player, CharacterBody2D)
│   ├── Health (HealthComponent)  Stats (SurvivalStats)  Inventory (InventoryComponent)
│   ├── Interactor (Interactor)   Hurtbox (Hurtbox)      AttackHitbox (Hitbox)
│   ├── BuildSystem (BuildSystem, owns the ghost preview)
│   └── Camera2D (smoothed, limited to the world bounds)
├── Hud (Hud, CanvasLayer, process_mode = ALWAYS)
└── MainMenu (MainMenu, CanvasLayer)
```

The world and the player are `y_sort_enabled` so entities draw in depth order; the `Ground`
node draws underneath everything.

## 4. Systems

### Items and inventory
- `ItemDefinition` (`resources/items/*.tres`): id, category, stack size, weight, tool type,
  combat numbers, consumable effects, placeholder icon colour/glyph.
- `ItemStack`: a slot's contents. Pure data, serializable.
- `Inventory`: slot array with stacking, capacity, add/remove/transfer/split/sort/weight.
  Pure logic, no nodes - unit tested directly.
- `InventoryComponent`: attaches an `Inventory` to any node (player, crate, loot bag) and
  republishes changes on the event bus.
- `Ingredient`: "item id + quantity", reused by recipes, resource yields, building costs and
  loot results. Referencing items by id (not by resource reference) keeps data files free of
  cycles and makes saving trivial.

### Crafting
`Recipe` data + `CraftingSystem` static rules. `can_craft`, `get_missing` and `craft` are
all-or-nothing and side-effect free on failure. The crafting UI only calls these; it owns no
rules.

### Combat
- `DamageInfo`: amount, type, source, knockback, hit position. Passed to the receiver so it can
  react without knowing the attacker.
- `HealthComponent`: the only way to change health. Emits `damaged`, `healed`, `died`.
- `Hurtbox` (Area2D): a target on `hurtbox_player` / `hurtbox_enemy`.
- `Hitbox` (Area2D): resolves hits with an explicit shape query during the active window
  instead of area signals, so one swing hits each target at most once and timing is
  deterministic. Player hitboxes mask `hurtbox_enemy`, zombie hitboxes mask `hurtbox_player`.

### Perception and AI
`Zombie` is a single script with an explicit state enum. Detection combines distance,
a `RayCast2D` line of sight (blocked by world geometry and resources) and sound:
`GameEvents.noise_emitted(position, radius, source)` is raised by sprinting, attacking and
building. Night raises detection range through the day/night node.

Navigation is steering plus a wall-slide nudge. There is no navigation mesh yet: baking one
before the world is large would be premature, and the prototypes' obstacles are convex enough
for steering.

### Building
- `BuildableDefinition` decides footprint, cost, health, behaviour (`SOLID`, `DOOR`,
  `STORAGE`, `DECORATION`) and colour.
- `Structure` implements all four behaviours; one scene serves every piece.
- `BuildSystem` (child of the player) owns build mode: grid snapping, ghost preview,
  validity query against `PhysicsLayers.BUILD_BLOCKERS`, cost payment through the player
  inventory, and placement through `GameWorld.add_structure`.
- Ownership is an id string (`owner_id`), ready to become an account id.

### World
- `WorldRegions`: the prototype region table (rects, ground colours, resource budgets).
- `GameWorld`: deterministic generation from a seed, runtime containers, spawning, and
  world state serialization.
- `WorldGround`: all terrain drawing.
- `DayNightCycle`: time of day, tint, clock, night visibility multiplier.
- `ZombieSpawner`: keeps a small population alive in a ring around the player, more at night,
  despawns stragglers.
- `ChunkStreamer`: distance-based activation. World objects join the `streamed` group and
  implement `set_streamed_active(active)`; chunks are re-evaluated every 0.25 s around the
  player. This is the seam that lets the world grow in Phase 6.

### Session
`Game` (`scripts/main/game.gd`) owns the lifecycle: main menu, new game, continue, save, load,
death/respawn hand-off, return to menu. It is the only place that knows about both the world
and the UI.

## 5. Physics layers

| Layer | Name | Used by |
| --- | --- | --- |
| 1 | world | Terrain obstacles, structures |
| 2 | player | Player body (mask: world, resource, enemy) |
| 3 | enemy | Zombie bodies (mask: world, resource, player) |
| 4 | resource | Gatherable bodies (trees, rocks) |
| 5 | interactable | Interaction areas on resources, structures, loot bags |
| 6 | hitbox | Attack areas |
| 7 | hurtbox_player | Player damage receiver |
| 8 | hurtbox_enemy | Enemy damage receiver |

Constants live in `scripts/core/physics_layers.gd`; scenes set the raw integers. Derived
masks: `BLOCKS_MOVEMENT`, `BUILD_BLOCKERS`, `SIGHT_BLOCKERS`.

## 6. Event bus

`GameEvents` carries: session lifecycle, health/stat changes, inventory/hotbar/container
changes, gathering, crafting, building, combat noise, enemy deaths, interaction prompts, world
time, toasts and save/load results.

Rules: gameplay never requires a listener; the bus carries no state; anything that needs a
return value is a direct method call instead (for example `target.interact(actor)`).

## 7. Interaction protocol

Interactables (resource nodes, doors, crates, loot bags) join the `interactable` group, expose
`get_interaction_label()`, and implement `interact(actor) -> bool`. The player's `Interactor`
area finds the nearest one and the HUD shows the label. Gathering is the one case where the
node delegates back to the actor (`actor.begin_gathering(self)`) because it needs time,
progress and interruption.

Streamed objects additionally implement `set_streamed_active(active)`.
Savable nodes implement `serialize_state() -> Dictionary` and `apply_state(state) -> void`.

## 8. Persistence

Slots live in `user://saves/slot_<n>.json` (3 slots). Writes go to `<slot>.json.tmp` and are
renamed into place; a failed rename falls back to a direct write. `SaveManager` asks the
player and the world for their state through the `serialize_state()` convention, so new
systems join the save file without `SaveManager` changing.

```jsonc
{
  "version": 1,
  "game_version": "0.1.0",
  "saved_at": "2026-09-20T11:20:00",
  "seed": 1234567,
  "player": {
    "position": [128.0, -64.0],
    "health": 82.0, "max_health": 100.0,
    "stats": { "hunger": 74.2, "thirst": 61.0, "stamina": 100.0, "survival_seconds": 214.5 },
    "inventory": { "inventory_id": "player", "capacity": 20, "slots": [ { "item_id": "wood", "quantity": 12 }, null ] },
    "active_slot": 0,
    "equipment": { "tool": "axe" },
    "facing": [1.0, 0.0]
  },
  "world": {
    "seed": 1234567,
    "day_night": { "time_of_day": 0.42, "day": 2, "day_length_seconds": 480.0 },
    "streaming": { "enabled": true, "chunk_size": 384.0, "active_radius_chunks": 1 },
    "resources": [ { "key": "tree_pine@-320,64", "uses_left": 2, "respawn_left": 0.0 } ],
    "structures": [ { "definition": "wood_wall", "position": [64.0, 64.0], "rotation": 0.0,
                      "owner": "local_player", "health": 170.0, "door_open": false } ],
    "loot_bags": [ { "position": [96.0, 96.0], "inventory": { "capacity": 12, "slots": [] } } ]
  }
}
```

Enemies are not saved; the spawner repopulates the world on load. Restoring a world clears
current structures and loot bags first, because the save is authoritative.

## 9. Multiplayer readiness (Phase 7, not implemented)

Nothing here ships networking, but the following decisions are already made so it is possible
later without a rewrite:

- **Server-authoritative state functions.** `serialize_state` / `apply_state` are the same
  shape a server would need to validate or replicate entity state.
- **Id-based references.** Items and definitions are referenced by string id everywhere, which
  transfers to the wire as-is.
- **Ownership ids.** Structures carry `owner_id`; inventories carry `inventory_id`.
- **Deterministic worlds.** Generation is fully determined by a seed, so a server and a client
  can build the same world from one integer.
- **No client-trust shortcuts.** Costs, crafting results and loot rolls already run once, in
  one place, on data that a server can own.
- **Seeded randomness.** Loot rolling takes a `RandomNumberGenerator` so the sequence is
  reproducible for tests and, later, for verification.

## 10. Performance notes

- `Engine.max_fps = 60`; physics at the default 60 Hz.
- Mobile renderer, no textures, no 3D.
- Resource nodes, structures and loot bags are distance-streamed; enemies are capped and
  despawn when far away.
- Procedural drawing replaces assets, so draw calls are modest but per-node; swapping in
  sprites/atlases later will reduce them further.
- World generation is O(n^2) in node count for spacing checks; fine at ~130 nodes, must move to
  a spatial hash when the world grows (Phase 6).

## 11. Testing strategy

`tests/test_runner.gd` runs the real project headlessly and exits non-zero on failure:

- data validation for every definition file;
- `Inventory`, `CraftingSystem`, `LootTable`, save format (unit-level);
- world generation determinism, structure/spawn restore, chunk math;
- one integration pass through `Main.tscn`: session start, movement, gathering, crafting,
  building with cost payment, a zombie detecting/chasing/damaging the player, killing a
  zombie, saving and loading a session, death and respawn.

The suite uses save slot 3, which is reserved for tests.
