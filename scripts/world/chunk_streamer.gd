class_name ChunkStreamer
extends Node
## Distance based activation for world objects.
##
## The prototype world is small enough to keep everything awake, but the systems
## that will make a large world possible have to exist early: every world object
## registers itself in the "streamed" group and implements
## `set_streamed_active(active: bool)`. Objects far from the player are disabled
## (no process, no physics, invisible), which is what keeps CPU, physics and draw
## calls flat as the map grows in Phase 6.
##
## Chunks are square and indexed by `floor(position / chunk_size)`.

## Side length of a chunk in world pixels.
@export_range(64.0, 2048.0, 16.0) var chunk_size: float = 384.0
## How many chunks around the player chunk stay active (1 = 3x3 chunks).
@export_range(0, 6, 1) var active_radius_chunks: int = 1
## How often positions are re-evaluated, in seconds. Continuous checking is
## wasted work on a slow moving top-down camera.
@export_range(0.05, 2.0, 0.05) var update_interval: float = 0.25
## When false nothing is ever deactivated - handy while debugging.
@export var enabled: bool = true

## Emitted with the number of objects that changed state.
signal streaming_updated(active_count: int, inactive_count: int)

var _timer: float = 0.0
var _active_count: int = 0
var _inactive_count: int = 0
## Chunk key -> Array[Node] of nodes registered in that chunk.
var _chunks: Dictionary = {}
var _last_chunk := Vector2i(9999, 9999)


func _ready() -> void:
	set_process(enabled)
	# Defer the first pass so siblings have finished _ready().
	call_deferred("refresh")


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = update_interval
	var target := _get_target_position()
	refresh(target)


## Rebuilds the chunk index and re-evaluates every object.
func refresh(target_position: Vector2 = Vector2.INF) -> void:
	var position := target_position if target_position != Vector2.INF else _get_target_position()
	_rebuild_index()
	var active_chunk := world_to_chunk(position)
	_last_chunk = active_chunk
	_active_count = 0
	_inactive_count = 0
	for chunk_key: Vector2i in _chunks.keys():
		var is_active := is_chunk_active(chunk_key, active_chunk)
		for node in _chunks[chunk_key]:
			if not is_instance_valid(node):
				continue
			_apply_state(node, is_active)
			if is_active:
				_active_count += 1
			else:
				_inactive_count += 1
	streaming_updated.emit(_active_count, _inactive_count)


func is_chunk_active(chunk_key: Vector2i, center_chunk: Vector2i) -> bool:
	if not enabled:
		return true
	var delta := (chunk_key - center_chunk).abs()
	return delta.x <= active_radius_chunks and delta.y <= active_radius_chunks


func world_to_chunk(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / chunk_size), floori(position.y / chunk_size))


func get_stats() -> Dictionary:
	return {
		"chunks": _chunks.size(),
		"active": _active_count,
		"inactive": _inactive_count,
		"chunk_size": chunk_size,
		"radius": active_radius_chunks,
	}


func _rebuild_index() -> void:
	_chunks.clear()
	for node in get_tree().get_nodes_in_group("streamed"):
		if not (node is Node2D):
			continue
		var node_2d := node as Node2D
		if not is_instance_valid(node_2d):
			continue
		var chunk_key := world_to_chunk(node_2d.global_position)
		if not _chunks.has(chunk_key):
			_chunks[chunk_key] = []
		_chunks[chunk_key].append(node_2d)


func _apply_state(node: Node2D, active: bool) -> void:
	if node.has_method("set_streamed_active"):
		node.set_streamed_active(active)
		return
	# Generic fallback: freeze processing, hide, and disable collision.
	node.visible = active
	node.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if node is CollisionObject2D:
		var collision_object := node as CollisionObject2D
		if collision_object.collision_layer != 0 and not active:
			collision_object.set_meta("streamed_layer", collision_object.collision_layer)
			collision_object.collision_layer = 0
		elif active and collision_object.has_meta("streamed_layer"):
			collision_object.collision_layer = int(collision_object.get_meta("streamed_layer"))


func _get_target_position() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		return player.global_position
	return Vector2.ZERO


func serialize_state() -> Dictionary:
	return {
		"enabled": enabled,
		"chunk_size": chunk_size,
		"active_radius_chunks": active_radius_chunks,
	}


func apply_state(state: Dictionary) -> void:
	enabled = bool(state.get("enabled", enabled))
	chunk_size = float(state.get("chunk_size", chunk_size))
	active_radius_chunks = int(state.get("active_radius_chunks", active_radius_chunks))
