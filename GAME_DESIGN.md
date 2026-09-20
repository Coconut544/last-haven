# Last Haven - Game Design

Everything in this document describes the game as it is implemented, plus clearly marked
future work. Numbers are the actual values from the data files in `resources/`.

## 1. Identity

- **Genre:** open-world post-apocalyptic survival (survival, crafting, base building,
  exploration, PvE now; PvP and raiding later).
- **Platform:** Android first, landscape, touch controls. Engine and architecture keep iOS
  and desktop reachable.
- **Camera:** top-down / 2.5D, follows the player, not a side-scroller.
- **Tone:** grounded and serious. Survivors, salvage, weather-worn places, not spectacle.

## 2. Core loop

```
Explore -> Gather -> Craft -> Build -> Survive -> Fight -> Upgrade -> Explore further
```

Every system below feeds that loop, and nothing is added unless it makes one of those steps
better.

## 3. The prototype world

One deterministic world of **3072 x 3072** world units, generated from a seed. Four regions
are laid out north to south:

| Region | Name | Character | Resource mix |
| --- | --- | --- | --- |
| Forest | Northwood | Dense trees, the starting area | pine 50%, birch 25%, berries 15%, rock 10% |
| Rural | Hollow Fields | Open fields, scattered salvage | birch 30%, rock 30%, berries 20%, scrap 20% |
| Town | Millbrook | Abandoned settlement, best scrap | scrap 45%, birch 30%, rock 15%, berries 10% |
| Industrial | Ironworks | Highest risk, best metal | scrap 60%, rock 40% |

The player starts at `(0, -420)`, in the forest, with the town a short walk south.
Zombies are more common and see further at night.

**Region table location:** `scripts/world/world_regions.gd`. Phase 6 moves this into data
files and drives it from the chunk streamer.

## 4. Survival

| Stat | Max | Drain | Notes |
| --- | --- | --- | --- |
| Health | 100 | - | Regenerates only through items/crafting |
| Hunger | 100 | 0.12/s | ~14 minutes from full |
| Thirst | 100 | 0.18/s | The faster clock, on purpose |
| Stamina | 100 | 12/s sprinting | Regenerates 9/s after a 0.8 s delay |

At zero hunger or thirst the player takes 1.2 / 1.8 damage per second respectively.
Death drops the entire inventory as a loot bag at the body and lets the player respawn at
camp, which makes dying costly without being a wipe.

## 5. Resources

| Node | Found in | Uses | Gather time | Best tool | Yields per harvest |
| --- | --- | --- | --- | --- | --- |
| Pine | Forest | 3 | 2.2 s | Axe (2.5x faster, 1.5x yield) | 2-3 wood |
| Birch | Forest, Rural, Town | 2 | 1.8 s | Axe | 1-2 wood, 2-3 fiber |
| Rock outcrop | Rural, Town, Industrial | 3 | 2.6 s | Pickaxe | 2-3 stone |
| Berry bush | All | 2 | 1.4 s | none | 2 berries |
| Scrap pile | Rural, Town, Industrial | 3 | 2.0 s | none | 1-2 scrap, 1-2 metal |

Depleted nodes respawn after 80-150 seconds depending on the type. Gathering requires the
player to stand still: leaving range cancels the attempt. Items that do not fit in the
inventory are dropped on the ground as a loot bag rather than vanishing.

## 6. Items

| Item | Category | Stack | Notes |
| --- | --- | --- | --- |
| Wood, Stone, Fiber, Scrap, Metal, Cloth | Material | 40-60 | Salvage and building stock |
| Wild Berries | Food | 20 | +12 hunger |
| Canned Food | Food | 10 | +35 hunger, +5 health |
| Water | Food | 10 | +40 thirst |
| Bandage | Consumable | 10 | +25 health |
| Survival Knife | Tool | 1 | 12 damage, knife tasks, 120 durability |
| Stone Axe | Tool | 1 | 18 damage, fells trees, 150 durability |
| Pickaxe | Tool | 1 | 16 damage, breaks rock, 160 durability |
| Builder's Hammer | Tool | 1 | 14 damage, reserved for faster building later |

Hotbar slots 1-5 are the first five inventory slots; the selected slot decides the melee
weapon and the gathering tool. Durability is tracked in the save format but not yet
consumed - see `ROADMAP.md` Phase 3.

## 7. Crafting

| Recipe | Category | Cost |
| --- | --- | --- |
| Survival Knife | Tools | 2 wood, 1 scrap |
| Stone Axe | Tools | 3 wood, 2 stone, 2 fiber |
| Pickaxe | Tools | 3 wood, 3 stone |
| Builder's Hammer | Tools | 2 wood, 2 stone, 2 scrap |
| Bandage | Survival | 1 cloth, 3 fiber |

Crafting is all-or-nothing: if the ingredients are missing, or the output would not fit, the
craft fails and nothing is consumed. Stations (`workbench`) are modelled in the data
(`required_station`) but not enforced yet.

## 8. Base building

| Piece | Cost | Health | Behaviour |
| --- | --- | --- | --- |
| Wood Floor | 1 wood | 60 | Walkable decoration, does not block building |
| Wood Wall | 2 wood | 220 | Blocks movement |
| Wood Door | 2 wood, 1 scrap | 160 | Blocks movement until opened |
| Storage Crate | 3 wood, 2 fiber | 120 | 12 inventory slots |

Placement snap to a 32 px grid, one cell in front of the player, with a colour-coded ghost
preview. A spot is rejected when it overlaps world geometry, resources, enemies, another
structure, or lies outside the world. Costs are paid only after the structure exists, and are
refunded if the payment fails. Materials are not returned when a structure is destroyed; the
stored contents of a crate spill out as a loot bag.

Building progression (wood -> stone -> metal), repair, and defensive pieces are planned for
Phase 2/3.

## 9. Zombies

One reliable enemy type, tuned so it can be understood and extended:

- **States:** idle -> wander -> chase -> attack -> search -> return, plus dead.
- **Speed:** 26 wander, 64 chase (player walks 108, sprints 178).
- **Perception:** 230 units of sight with a line-of-sight raycast; sound events (sprinting,
  attacking, building) send it to investigate; both scale up at night (x1.5).
- **Attack:** 8 damage, 1.2 s cooldown, 28 unit reach.
- **Health:** 45. Two axe hits, three knife hits.
- **Death:** drops a loot bag rolled from `zombie_standard` (cloth, scrap, fiber guaranteed;
  food, bandages, metal and rarely a knife as bonus rolls).

Variants (runner, brute) and hordes are Phase 4 work.

## 10. Loot

Loot tables use two mechanics, both data-driven: `guaranteed_rolls` are weighted picks that
always award something, `chance_rolls` test every entry against its own probability.

| Table | Guaranteed | Bonus | Used by |
| --- | --- | --- | --- |
| `zombie_standard` | 1 | 1 | Every zombie death |
| `common_crate` | 2 | 1 | World containers and future building loot |

Rarity (`Common` -> `Exceptional`) is stored per entry and currently only surfaced through
item definitions; rarity-weighted pools, rarity-dependent quantities and location-specific
tables are Phase 2/5 work.

## 11. Day and night

One in-game day is 480 real seconds. The cycle tints the world through a `CanvasModulate`
(`night -> dawn -> day -> dusk -> night`), drives the HUD clock, and raises enemy detection
range at night. Night currently does not change spawn counts (planned with the Phase 4
horde pass).

## 12. Controls

**Touch**

- Bottom left: virtual stick. Distance from centre is speed; pushing to the edge sprints.
- Bottom right: **Attack** and **Use** (contextual interact).
- Above them: **Bag**, **Craft**, **Build**.
- Bottom centre: five hotbar slots; tap to select.
- Contextual prompt and gather progress appear above the player.
- All interactive elements are at least 52 px tall, sized for thumbs.

**Desktop (development)**

Movement `WASD`/arrows, sprint `Shift`, attack `Space`, interact `E`, inventory `I`,
crafting `C`, build `B`, rotate `R`, save `F5`, load `F9`, pause/back `Esc`.

## 13. Death, saving and progression

- **Death:** inventory drops on the ground, the death panel offers respawn at camp.
- **Saving:** three local slots. Saving is atomic (write to a temp file, then rename), so a
  crash mid-write cannot corrupt a save.
- **Progression:** not implemented yet. Planned: character skills (gathering speed, combat,
  carrying capacity) and item tier progression, both server-authoritative in Phase 7.

## 14. Explicitly out of scope for now

Multiplayer, PvP, base raiding, weather, vehicles, NPC traders, cooking, farming, ranged
weapons, crafting stations, tech trees, and any store/analytics integration. See
`ROADMAP.md` for the phases they belong to.
