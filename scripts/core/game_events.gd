extends Node
## Global signal bus (autoload).
##
## Gameplay systems emit, UI and other systems listen. This keeps gameplay code
## free of references to specific UI nodes and lets the HUD react to state it
## does not own.
##
## Rules for this file:
## - signals only, no game state, no logic;
## - add a signal when at least two unrelated systems need to know about it;
## - never let gameplay depend on a listener being connected.

## --- session ---
signal session_started(player: Node)
signal session_ended()
signal player_spawned(player: Node2D)
signal player_died()
signal player_respawned()

## --- player state ---
signal health_changed(current: float, maximum: float)
signal stat_changed(stat_id: String, value: float, maximum: float)

## --- inventory / items ---
signal inventory_changed(inventory: Inventory)
signal hotbar_changed(active_slot: int)
signal container_opened(inventory: Inventory, title: String)
signal container_closed()

## --- gathering / crafting / building ---
signal item_gathered(item_id: String, quantity: int)
signal item_crafted(recipe: Recipe)
signal gathering_started(target: Node)
signal gathering_progress(ratio: float)
signal gathering_cancelled()
signal resource_depleted(node: Node)
signal structure_built(definition: BuildableDefinition, position: Vector2)

## --- combat / enemies ---
signal noise_emitted(position: Vector2, radius: float, source: Node)
signal enemy_died(enemy: Node, position: Vector2)

## --- interaction ---
signal interactable_changed(target: Node, label: String)
signal interaction_used(target: Node)

## --- world time ---
signal time_changed(time_of_day: float, day: int)

## --- ui / persistence feedback ---
signal toast_requested(message: String)
signal save_completed(slot: int)
signal load_completed(slot: int)
signal save_failed(slot: int, reason: String)
