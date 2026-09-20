# Last Haven - Roadmap

The plan is intentionally incremental: small, playable, testable, expandable, production.

Legend: **[done]** implemented and covered by the test suite, **[partial]** usable but
incomplete, **[next]** the immediate work, **[planned]** designed for but not started.

## Phase 0 - Foundation [done]

- Godot 4.7 project, GDScript, mobile renderer, landscape orientation.
- Android export preset, `.gitignore`, build outputs excluded.
- Repository structure for scenes, scripts, resources, tests and workflows.
- Autoloads, input map with keyboard fallbacks, physics layer conventions.
- Documentation set: README, GAME_DESIGN, ARCHITECTURE, DEVELOPMENT, BUILD, ROADMAP, AI_RULES,
  AI_HANDOFF.
- GitHub Actions: validate (import + tests + boot) and Android debug APK.
- Headless test suite with unit and integration coverage.

## Phase 1 - Playable prototype [done]

- Player: movement, sprint with stamina, facing, camera follow, death/corpse state.
- Test world: 4 regions, deterministic generation, ~130 gatherable nodes.
- Gathering: timed, interruptible, tool-aware, items dropped when the inventory is full.
- Inventory: stacking, capacity, split, sort, transfers, container support.
- Crafting: data-driven recipes, all-or-nothing rules, category filtering UI.
- Touch HUD: virtual stick, action buttons, hotbar, prompts, gather progress, toasts.
- Day/night cycle with a HUD clock.
- Save/load with atomic writes, including world resource state and structures.

## Phase 2 - Base [partial]

Done: floors, walls, doors, storage crates; grid snapping; ghost preview; collision and cost
validation; ownership id; persistence; destruction spills crate contents.

Next:
- Material tiers (wood -> stone -> metal) with tiered pieces and upgrade-in-place.
- Repair with the hammer, and partial material refund on demolition.
- Workbench as a crafting station (`Recipe.required_station` is already modelled).
- Preview overlapping rules (allow walls on floors, block walls inside walls).
- Building tutorial prompt on first session.

## Phase 3 - Survival depth [partial]

Done: health, hunger, thirst, stamina, starvation/dehydration damage, consumables.

Next:
- Item durability consumption and repair.
- Cooking (campfire -> cooked food), water purification.
- Temperature/weather, clothing with warmth values.
- Status effects (bleeding, infection) and medical items.

## Phase 4 - Zombies [partial]

Done: one complete enemy with idle/wander/detect/chase/attack/search/return/death, sight,
sound and night detection, loot on death, population management and despawning.

Next:
- Variants: runner (fast, weak), brute (slow, high health, breaks structures).
- Hordes and a world-event spawner; night raid pressure.
- Navigation mesh or flow-field movement once the world and obstacle count grow.
- Enemy persistence budget (server-owned spawn budget in Phase 7).

## Phase 5 - Combat and loot [partial]

Done: melee attacks with per-weapon damage/cooldown/range, hitbox/hurtbox model, knockback,
enemy death loot, loot bags as containers, weighted and chance-based loot tables.

Next:
- Ranged weapons and ammunition.
- Weapon durability, condition and mods.
- Rarity-weighted loot pools, location-specific tables, rare containers.
- Combat feedback pass: hit effects, sounds, camera feedback.
- Armour and equipment slots affecting damage.

## Phase 6 - Large world [planned]

- Move the region table into data files and generate per chunk.
- Replace the O(n^2) resource spacing check with a spatial hash.
- Multi-region streaming with `ChunkStreamer` at chunk granularity (the API exists).
- Named locations, points of interest, interiors, and high-risk reward zones.
- World state persistence per chunk instead of one flat list.

## Phase 7 - Multiplayer foundation [planned]

- Accounts and authentication.
- Server-authoritative world: inventories, ownership, resources, damage, loot.
- Client prediction and reconciliation for movement.
- Region sharding and instance servers for capacity.
- Persistence backed by the database rather than local files.
- Anti-cheat: server validation for every state-changing action.

`serialize_state` / `apply_state`, id-based references, ownership ids and seeded world
generation were chosen in Phase 0 specifically to make this phase possible.

## Phase 8 - PvP [planned]

Player damage and death, PvP zones and safe areas, new-player protection, combat logging
rules, anti-abuse cooldowns, loot rules.

## Phase 9 - Base raiding [planned]

Structure damage rules, raid windows and cooldowns, defence pieces (spikes, traps, alarms,
turrets), loot protection limits, offline-raid protection.

## Phase 10 - Optimisation [planned]

Profiling on mid-range Android hardware, texture atlases, draw call reduction, memory budget,
battery and thermal targets, load time, crash-free session rate.

## Phase 11 - Release [planned]

Production art and audio pass, onboarding, settings (graphics, audio, controls, rebinding),
accessibility, localisation, analytics with consent, crash reporting, privacy policy, Play
Store listing, internal/closed/open testing tracks, staged rollout.

## Immediate next actions

1. Run the Android workflow once and fix whatever the first real export reports.
2. Add save-slot UI (create/overwrite/delete, per-slot timestamps) to the main menu.
3. Durability consumption for tools plus the repair interaction.
4. A workbench buildable that gates advanced recipes.
5. Zombie variants and a night horde event.
