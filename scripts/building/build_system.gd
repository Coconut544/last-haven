class_name BuildSystem
extends Node
## Player base building.
##
## Owned by the player (it needs the player's inventory and facing direction) but
## it only ever talks to the world through `GameWorld.add_structure()`, so it
## stays independent of how structures are stored or streamed.
##
## Placement rules for Phase 1/2:
## - the ghost snaps to a 32 px grid and sits one cell in front of the player;
## - a spot is invalid when it overlaps world geometry, resources, enemies or
##   another structure;
## - costs are paid from the player inventory, all-or-nothing;
## - a structure is owned by `owner_id` (the local player for now).

signal build_mode_changed(active: bool, definition: BuildableDefinition)
signal placement_failed(reason: String)
signal structure_placed(structure: Structure)

const GRID_SIZE := 32

## How far in front of the player the ghost is placed.
@export var placement_distance: float = 44.0
@export var snap_to_grid: bool = true

var active: bool = false
var definition: BuildableDefinition
var owner_id: String = "local_player"
var rotation_steps: int = 0

var _inventory: InventoryComponent
var _world: Node
var _ghost: BuildGhost
var _player: Node2D
var _valid: bool = false


func _ready() -> void:
	_player = get_parent() as Node2D
	_world = get_tree().get_first_node_in_group("world")
	_ghost = BuildGhost.new()
	_ghost.name = "BuildGhost"
	_ghost.visible = false
	_ghost.z_index = 5
	add_child(_ghost)
	set_process(false)


func set_inventory(inventory: InventoryComponent) -> void:
	_inventory = inventory


func is_active() -> bool:
	return active


## Enters build mode with a chosen buildable, or exits when `buildable` is null.
func set_buildable(buildable: BuildableDefinition) -> void:
	if buildable == null:
		exit_build_mode()
		return
	definition = buildable
	active = true
	rotation_steps = 0
	_ghost.setup(buildable)
	_ghost.visible = true
	set_process(true)
	_refresh_ghost()
	build_mode_changed.emit(true, definition)


func enter_build_mode(buildable: BuildableDefinition) -> void:
	set_buildable(buildable)


func exit_build_mode() -> void:
	active = false
	definition = null
	_valid = false
	if _ghost != null:
		_ghost.visible = false
	set_process(false)
	build_mode_changed.emit(false, null)


func rotate_structure() -> void:
	if not active:
		return
	rotation_steps = (rotation_steps + 1) % 4
	_refresh_ghost()


func get_rotation_radians() -> float:
	return float(rotation_steps) * PI * 0.5


func _process(_delta: float) -> void:
	_refresh_ghost()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("rotate_structure"):
		rotate_structure()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or event.is_action_pressed("attack"):
		confirm_placement()
		get_viewport().set_input_as_handled()


## World position the pending structure would occupy.
func get_target_position() -> Vector2:
	if _player == null:
		return Vector2.ZERO
	var facing: Vector2 = Vector2.DOWN
	var reported_facing: Variant = _player.get("facing")
	if typeof(reported_facing) == TYPE_VECTOR2 and reported_facing != Vector2.ZERO:
		facing = reported_facing
	var target: Vector2 = _player.global_position + facing.normalized() * placement_distance
	return snap_position(target)


func snap_position(target: Vector2) -> Vector2:
	if not snap_to_grid:
		return target
	return Vector2(
		roundf(target.x / float(GRID_SIZE)) * float(GRID_SIZE),
		roundf(target.y / float(GRID_SIZE)) * float(GRID_SIZE))


func _refresh_ghost() -> void:
	if _ghost == null or definition == null:
		return
	var target := get_target_position()
	_ghost.global_position = target
	_ghost.global_rotation = get_rotation_radians()
	_valid = is_placement_valid(target, definition, get_rotation_radians())
	_ghost.set_valid(_valid)


func is_placement_valid(position: Vector2, buildable: BuildableDefinition, rotation_radians: float = 0.0) -> bool:
	if buildable == null:
		return false
	if not WorldRegions.is_inside_world(position):
		return false
	var space_state := get_viewport().world_2d.direct_space_state
	if space_state == null:
		return false
	var shape := RectangleShape2D.new()
	# Slightly smaller than the real footprint so flush placement stays possible
	# without the ghost flickering between valid and invalid.
	shape.size = buildable.collision_size - Vector2(4, 4)
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(rotation_radians, position)
	query.collision_mask = PhysicsLayers.BUILD_BLOCKERS
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if _player is CollisionObject2D:
		query.exclude = [(_player as CollisionObject2D).get_rid()]
	return space_state.intersect_shape(query, 1).is_empty()


func can_afford(buildable: BuildableDefinition = null) -> bool:
	var target := buildable if buildable != null else definition
	if target == null or _inventory == null:
		return false
	return _inventory.can_afford(target.cost)


func get_missing_cost(buildable: BuildableDefinition = null) -> Dictionary:
	var target := buildable if buildable != null else definition
	if target == null or _inventory == null:
		return {}
	return _inventory.inventory.get_missing(target.cost_dict())


## Places the pending structure. Returns true when something was built.
func confirm_placement() -> bool:
	if not active or definition == null:
		return false
	if _world == null:
		_world = get_tree().get_first_node_in_group("world")
	if _world == null:
		placement_failed.emit("No world loaded")
		return false
	if not _valid:
		placement_failed.emit("Cannot build there")
		return false
	if _inventory == null:
		placement_failed.emit("No inventory")
		return false
	if not _inventory.can_afford(definition.cost):
		placement_failed.emit("Not enough materials for %s" % definition.display_name)
		return false

	var target := get_target_position()
	var rotation_radians := get_rotation_radians()
	# Re-check right before paying so a moving enemy cannot slip in between.
	if not is_placement_valid(target, definition, rotation_radians):
		placement_failed.emit("Cannot build there")
		return false

	var structure: Structure = _world.add_structure(definition, target, rotation_radians, owner_id)
	if structure == null:
		placement_failed.emit("Building failed")
		return false

	# Pay only after the structure exists, and roll back if payment is rejected.
	if not _inventory.pay_cost(definition.cost):
		structure.queue_free()
		placement_failed.emit("Not enough materials for %s" % definition.display_name)
		return false

	structure_placed.emit(structure)
	GameEvents.structure_built.emit(definition, target)
	# Building is noisy work.
	GameEvents.noise_emitted.emit(target, 220.0, _player)
	return true
