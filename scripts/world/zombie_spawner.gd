class_name ZombieSpawner
extends Node
## Keeps a target number of zombies alive in a ring around the player.
##
## Deliberately simple and always-on: the world keeps a small enemy population up
## to date, more of them at night, and despawns ones the player has long left
## behind so memory and physics cost stay flat.
##
## Phase 4/6 replaces the "ring around the player" rule with region spawn tables
## and a server-authoritative spawn budget.

@export var base_limit: int = 5
@export var night_bonus: int = 3
@export_range(50.0, 3000.0, 10.0) var min_spawn_distance: float = 460.0
@export_range(100.0, 4000.0, 10.0) var max_spawn_distance: float = 900.0
@export_range(1.0, 300.0, 1.0) var spawn_interval: float = 22.0
## Enemies further than this from the player are removed.
@export_range(200.0, 6000.0, 50.0) var despawn_distance: float = 1800.0
@export var spawn_radius: float = 18.0

var _world: Node
var _timer: float = 4.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_world = get_parent()
	_rng.randomize()


func _process(delta: float) -> void:
	if _world == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = spawn_interval
	_despawn_distant()
	if _get_alive_count() < get_target_population():
		spawn_one()


func get_target_population() -> int:
	var bonus := night_bonus if _is_night() else 0
	return base_limit + bonus


func get_alive_count() -> int:
	return _get_alive_count()


func _is_night() -> bool:
	var cycle := get_tree().get_first_node_in_group("day_night")
	if cycle == null or not cycle.has_method("is_night"):
		return false
	return bool(cycle.is_night())


## Spawns one zombie at a valid position. Returns null when no spot was found.
func spawn_one() -> Node2D:
	var spot := find_spawn_position()
	if spot == Vector2.INF:
		return null
	if not _world.has_method("spawn_enemy"):
		return null
	return _world.spawn_enemy(spot)


## Looks for an unoccupied spot in the ring around the player.
func find_spawn_position() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var origin := player.global_position if player != null else Vector2.ZERO
	for _attempt in 24:
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(min_spawn_distance, max_spawn_distance)
		var candidate := origin + Vector2.RIGHT.rotated(angle) * distance
		if not WorldRegions.is_inside_world(candidate):
			continue
		if _is_occupied(candidate):
			continue
		return candidate
	return Vector2.INF


func _is_occupied(world_position: Vector2) -> bool:
	var space_state := get_viewport().world_2d.direct_space_state
	if space_state == null:
		return false
	var shape := CircleShape2D.new()
	shape.radius = spawn_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, world_position)
	query.collision_mask = PhysicsLayers.BUILD_BLOCKERS
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return not space_state.intersect_shape(query, 1).is_empty()


func _despawn_distant() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.global_position.distance_to(player.global_position) > despawn_distance:
			enemy.queue_free()


func _get_alive_count() -> int:
	if _world != null and _world.has_method("get_enemy_count"):
		return int(_world.get_enemy_count())
	var count := 0
	for node in get_tree().get_nodes_in_group("enemy"):
		if node is Zombie and not (node as Zombie).is_dead():
			count += 1
	return count
