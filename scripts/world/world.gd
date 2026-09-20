class_name GameWorld
extends Node2D
## The playable world: ground, gatherable resources, structures, loot and time.
##
## Responsibilities:
## - deterministic generation from a seed (save/load and later server-side
##   world building both rely on this);
## - spawning resource nodes per region, using the WorldRegions table;
## - owning the containers for runtime objects (structures, loot bags, enemies);
## - serializing world state through `serialize_state()` / `apply_state()`.
##
## The prototype world is a single 3072 x 3072 region. Phase 6 replaces the
## generator with chunked streaming; the container structure and the ChunkStreamer
## API are already in place for that.

signal world_ready()
signal structure_added(structure: Structure)

const RESOURCE_NODE_SCENE: PackedScene = preload("res://scenes/world/ResourceNode.tscn")
const STRUCTURE_SCENE: PackedScene = preload("res://scenes/world/Structure.tscn")
const LOOT_BAG_SCENE: PackedScene = preload("res://scenes/loot/LootBag.tscn")
const ZOMBIE_SCENE: PackedScene = preload("res://scenes/enemies/Zombie.tscn")

## 0 picks a seed from the system clock on first generation.
@export var world_seed: int = 0
@export var generate_on_ready: bool = true
## Multiplies every region's resource budget, for quick density experiments.
@export_range(0.1, 3.0, 0.05) var density_multiplier: float = 1.0
@export var min_resource_spacing: float = 44.0
## Keep this radius around the spawn point free of resources.
@export var spawn_clear_radius: float = 110.0

@onready var resource_root: Node2D = $ResourceNodes
@onready var structure_root: Node2D = $Structures
@onready var loot_root: Node2D = $LootBags
@onready var enemy_root: Node2D = $Enemies
@onready var day_night: DayNightCycle = $DayNightCycle
@onready var chunk_streamer: ChunkStreamer = $ChunkStreamer
@onready var enemy_spawner: ZombieSpawner = $EnemySpawner
@onready var ground: WorldGround = $Ground

var _rng := RandomNumberGenerator.new()
var _generated: bool = false
var _structure_counter: int = 0


func _ready() -> void:
	add_to_group("world")
	if generate_on_ready:
		generate(world_seed)
	world_ready.emit()


func get_world_seed() -> int:
	return world_seed


func is_generated() -> bool:
	return _generated


# --- generation ---------------------------------------------------------------

## Builds the world for a seed. Passing -1 keeps the current seed.
func generate(seed_value: int = -1) -> void:
	if seed_value >= 0:
		world_seed = seed_value
	if world_seed == 0:
		world_seed = int(Time.get_unix_time_from_system()) & 0x7fffffff
	_rng.seed = world_seed
	_clear_generated()
	_spawn_region_resources()
	_generated = true
	if ground != null:
		ground.refresh()


func _clear_generated() -> void:
	for root: Node in [resource_root, structure_root, loot_root, enemy_root]:
		if root == null:
			continue
		for child in root.get_children():
			child.queue_free()
	_structure_counter = 0


func _spawn_region_resources() -> void:
	for region: Dictionary in WorldRegions.get_region_definitions():
		var rect: Rect2 = region["rect"]
		var budget := int(round(float(region["budget"]) * density_multiplier))
		var weights: Dictionary = region["resources"]
		var placed: Array[Vector2] = []
		var attempts := 0
		var max_attempts := budget * 40
		while placed.size() < budget and attempts < max_attempts:
			attempts += 1
			var spot := Vector2(
				_rng.randf_range(rect.position.x, rect.end.x),
				_rng.randf_range(rect.position.y, rect.end.y))
			if spot.distance_to(WorldRegions.DEFAULT_SPAWN) < spawn_clear_radius:
				continue
			if not _is_spot_free(spot, placed, min_resource_spacing):
				continue
			placed.append(spot)
			spawn_resource_node(_pick_weighted_id(weights), spot)


func _is_spot_free(spot: Vector2, placed: Array[Vector2], min_distance: float) -> bool:
	for other in placed:
		if spot.distance_squared_to(other) < min_distance * min_distance:
			return false
	return true


func _pick_weighted_id(weights: Dictionary) -> String:
	var total := 0.0
	for key: String in weights.keys():
		total += float(weights[key])
	if total <= 0.0:
		return ""
	var target := _rng.randf_range(0.0, total)
	var accumulated := 0.0
	for key: String in weights.keys():
		accumulated += float(weights[key])
		if target <= accumulated:
			return key
	return str(weights.keys()[0])


# --- spawning -----------------------------------------------------------------

## Spawns one gatherable node. Returns null when the definition is unknown.
func spawn_resource_node(definition_id: String, spawn_position: Vector2) -> ResourceNode:
	var definition := ItemDatabase.get_resource_node_definition(definition_id)
	if definition == null:
		push_warning("[GameWorld] Unknown resource definition '%s'" % definition_id)
		return null
	var node := RESOURCE_NODE_SCENE.instantiate() as ResourceNode
	node.definition = definition
	node.position = spawn_position
	node.name = "%s_%d" % [definition_id, resource_root.get_child_count()]
	resource_root.add_child(node)
	return node


## Adds a structure. `state` restores health, door state and storage contents.
func add_structure(
		definition: BuildableDefinition,
		spawn_position: Vector2,
		rotation_radians: float = 0.0,
		owner_id: String = "",
		state: Dictionary = {}
) -> Structure:
	if definition == null:
		return null
	var scene := STRUCTURE_SCENE
	if not definition.scene_path.is_empty() and definition.scene_path != "res://scenes/world/Structure.tscn":
		var custom := load(definition.scene_path)
		if custom is PackedScene:
			scene = custom
	var structure := scene.instantiate() as Structure
	if structure == null:
		push_error("[GameWorld] %s is not a Structure scene" % definition.scene_path)
		return null
	structure.definition = definition
	structure.owner_id = owner_id
	structure.position = spawn_position
	structure.rotation = rotation_radians
	structure.name = "Structure_%d" % _structure_counter
	_structure_counter += 1
	structure_root.add_child(structure)
	if not state.is_empty():
		structure.apply_state(state)
	structure_added.emit(structure)
	return structure


## Drops a loot bag holding `items` (item id -> quantity).
func spawn_loot_bag(spawn_position: Vector2, items: Dictionary) -> LootBag:
	var bag := LOOT_BAG_SCENE.instantiate() as LootBag
	bag.position = spawn_position
	bag.name = "LootBag_%d" % loot_root.get_child_count()
	loot_root.add_child(bag)
	var ingredients: Array[Ingredient] = []
	for item_id: String in items.keys():
		ingredients.append(Ingredient.create(item_id, int(items[item_id])))
	bag.setup(ingredients)
	return bag


## Convenience wrapper used by enemies and by fallen players.
func spawn_loot_bag_from_ingredients(spawn_position: Vector2, ingredients: Array[Ingredient]) -> LootBag:
	var items: Dictionary = {}
	for ingredient: Ingredient in ingredients:
		items[ingredient.item_id] = int(items.get(ingredient.item_id, 0)) + ingredient.quantity
	return spawn_loot_bag(spawn_position, items)


func spawn_enemy(spawn_position: Vector2) -> Zombie:
	var zombie := ZOMBIE_SCENE.instantiate() as Zombie
	zombie.position = spawn_position
	zombie.home_position = spawn_position
	zombie.name = "Zombie_%d" % enemy_root.get_child_count()
	enemy_root.add_child(zombie)
	return zombie


func get_enemy_count() -> int:
	var count := 0
	for child in enemy_root.get_children():
		if child is Zombie and not (child as Zombie).is_dead():
			count += 1
	return count


func get_spawn_position() -> Vector2:
	return WorldRegions.DEFAULT_SPAWN


func get_region_name_at(world_position: Vector2) -> String:
	var region := WorldRegions.get_region(WorldRegions.region_id_at(world_position))
	return str(region.get("name", "The Wilds"))


# --- chunk streaming ----------------------------------------------------------

func refresh_streaming() -> void:
	if chunk_streamer != null:
		chunk_streamer.refresh()


# --- persistence --------------------------------------------------------------

func serialize_state() -> Dictionary:
	var resources: Array = []
	if resource_root != null:
		for child in resource_root.get_children():
			if child is ResourceNode:
				var node := child as ResourceNode
				var max_uses := node.definition.max_uses if node.definition != null else 0
				if node.is_depleted() or node.uses_left < max_uses:
					resources.append(node.get_save_state())

	var structures: Array = []
	if structure_root != null:
		for child in structure_root.get_children():
			if child is Structure:
				structures.append((child as Structure).serialize_state())

	var loot_bags: Array = []
	if loot_root != null:
		for child in loot_root.get_children():
			if child is LootBag:
				var bag := child as LootBag
				if not bag.is_empty():
					loot_bags.append(bag.serialize_state())

	return {
		"seed": world_seed,
		"day_night": day_night.serialize_state() if day_night != null else {},
		"streaming": chunk_streamer.serialize_state() if chunk_streamer != null else {},
		"resources": resources,
		"structures": structures,
		"loot_bags": loot_bags,
	}


func apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	var saved_seed := int(state.get("seed", 0))
	if saved_seed != 0 and (saved_seed != world_seed or not _generated):
		generate(saved_seed)
	if day_night != null:
		day_night.apply_state(state.get("day_night", {}))
	if chunk_streamer != null:
		chunk_streamer.apply_state(state.get("streaming", {}))
	_restore_resources(state.get("resources", []))
	_restore_structures(state.get("structures", []))
	_restore_loot_bags(state.get("loot_bags", []))
	refresh_streaming()


func _restore_resources(saved: Array) -> void:
	if saved.is_empty():
		return
	var by_key: Dictionary = {}
	for entry in saved:
		if typeof(entry) == TYPE_DICTIONARY:
			by_key[str(entry.get("key", ""))] = entry
	for child in resource_root.get_children():
		if not (child is ResourceNode):
			continue
		var node := child as ResourceNode
		var entry: Variant = by_key.get(node.node_key)
		if typeof(entry) == TYPE_DICTIONARY:
			node.apply_save_state(entry)


func _restore_structures(saved: Array) -> void:
	# A loaded save is authoritative: clear what is currently built.
	for child in structure_root.get_children():
		child.queue_free()
	for entry in saved:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var definition := ItemDatabase.get_buildable(str(entry.get("definition", "")))
		if definition == null:
			push_warning("[GameWorld] Skipping unknown saved structure '%s'" % entry.get("definition", ""))
			continue
		var position_data: Array = entry.get("position", [])
		var structure_position := Vector2.ZERO
		if position_data.size() == 2:
			structure_position = Vector2(float(position_data[0]), float(position_data[1]))
		add_structure(definition, structure_position, float(entry.get("rotation", 0.0)),
				str(entry.get("owner", "")), entry)


func _restore_loot_bags(saved: Array) -> void:
	for child in loot_root.get_children():
		child.queue_free()
	for entry in saved:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var bag := LOOT_BAG_SCENE.instantiate() as LootBag
		loot_root.add_child(bag)
		bag.apply_state(entry)
