class_name ResourceNode
extends StaticBody2D
## A gatherable world object: tree, rock, bush or scrap pile.
##
## Behaviour and yields come entirely from a ResourceNodeDefinition, so adding a
## new resource type is a data change, not a code change.
##
## Lifecycle: `uses_left` counts harvests. When it reaches 0 the node is depleted
## (no collision, drawn as a stump), and after `respawn_time` it comes back - 
## both states are saved by GameWorld.

signal harvested(items: Array, actor: Node)
signal depleted(node: ResourceNode)
signal respawned(node: ResourceNode)

@export var definition: ResourceNodeDefinition

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var interaction_area: Area2D = $InteractionArea
@onready var interaction_shape: CollisionShape2D = $InteractionArea/CollisionShape2D

var uses_left: int = 1
var respawn_left: float = 0.0
## Stable identity used by save files ("definition_id@x,y").
var node_key: String = ""

var _rng := RandomNumberGenerator.new()
var _active: bool = true


func _ready() -> void:
	add_to_group("resource_node")
	add_to_group("streamed")
	add_to_group("interactable")
	_rng.seed = hash(node_key if not node_key.is_empty() else str(position)) | 1
	if definition == null:
		push_error("[ResourceNode] %s is missing a definition" % name)
		return
	node_key = build_key(definition.id, position)
	uses_left = definition.max_uses
	_apply_definition()
	queue_redraw()


static func build_key(definition_id: String, world_position: Vector2) -> String:
	return "%s@%d,%d" % [definition_id, roundi(world_position.x), roundi(world_position.y)]


func _apply_definition() -> void:
	if collision_shape != null and collision_shape.shape is CircleShape2D:
		var body_circle := collision_shape.shape as CircleShape2D
		body_circle.radius = definition.collision_radius
	if interaction_shape != null and interaction_shape.shape is CircleShape2D:
		var interaction_circle := interaction_shape.shape as CircleShape2D
		interaction_circle.radius = maxf(38.0, definition.collision_radius + 26.0)


func _process(delta: float) -> void:
	if respawn_left <= 0.0:
		return
	respawn_left -= delta
	if respawn_left <= 0.0:
		_respawn()


# --- gathering ----------------------------------------------------------------

func is_depleted() -> bool:
	return uses_left <= 0


func can_gather() -> bool:
	return definition != null and not is_depleted()


func get_interaction_label() -> String:
	if definition == null:
		return "Gather"
	if is_depleted():
		return "%s (depleted)" % definition.display_name
	return definition.get_interaction_label()


## Seconds this actor would need with their current tool.
func get_gather_duration(tool_type: ItemDefinition.ToolType) -> float:
	if definition == null:
		return 1.0
	return definition.get_gather_duration(is_tool_matched(tool_type))


func is_tool_matched(tool_type: ItemDefinition.ToolType) -> bool:
	if definition == null:
		return false
	if definition.preferred_tool == ItemDefinition.ToolType.NONE:
		return false
	return definition.preferred_tool == tool_type


## Called by Player when a gather completes. Returns the items granted.
func harvest(tool_type: ItemDefinition.ToolType) -> Array[Ingredient]:
	if definition == null or is_depleted():
		return []
	var matched := is_tool_matched(tool_type)
	var granted := definition.roll_yields(_rng, matched)
	if not definition.bonus_loot_table_id.is_empty() and uses_left == 1:
		var table := ItemDatabase.get_loot_table(definition.bonus_loot_table_id)
		if table != null:
			granted.append_array(table.roll_ingredients(_rng))
	uses_left = maxi(0, uses_left - 1)
	harvested.emit(granted, null)
	if uses_left <= 0:
		_deplete()
	queue_redraw()
	return granted


func _deplete() -> void:
	respawn_left = definition.respawn_time
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
	if interaction_area != null:
		interaction_area.monitoring = false
	depleted.emit(self)
	GameEvents.resource_depleted.emit(self)
	queue_redraw()


func _respawn() -> void:
	uses_left = definition.max_uses
	if collision_shape != null:
		collision_shape.set_deferred("disabled", false)
	if interaction_area != null:
		interaction_area.monitoring = true
	respawned.emit(self)
	queue_redraw()


# --- interaction --------------------------------------------------------------

## Gathering needs time and progress feedback, so the node hands control to the
## actor instead of completing instantly.
func interact(actor: Node) -> bool:
	if actor == null or not actor.has_method("begin_gathering"):
		return false
	if not can_gather():
		GameEvents.toast_requested.emit("This %s is exhausted." % definition.display_name)
		return false
	actor.begin_gathering(self)
	GameEvents.interaction_used.emit(self)
	return true


# --- streaming ----------------------------------------------------------------

func set_streamed_active(active: bool) -> void:
	_active = active
	visible = active
	set_process(active and respawn_left > 0.0)
	if collision_shape != null:
		collision_shape.set_deferred("disabled", not active or is_depleted())
	if interaction_area != null:
		interaction_area.monitoring = active and not is_depleted()


# --- persistence --------------------------------------------------------------

func get_save_state() -> Dictionary:
	return {
		"key": node_key,
		"uses_left": uses_left,
		"respawn_left": respawn_left,
	}

func apply_save_state(state: Dictionary) -> void:
	uses_left = int(state.get("uses_left", uses_left))
	respawn_left = float(state.get("respawn_left", 0.0))
	if uses_left <= 0:
		respawn_left = maxf(respawn_left, 0.1)
		_deplete_shapes_only()
	queue_redraw()


func _deplete_shapes_only() -> void:
	if collision_shape != null:
		collision_shape.set_deferred("disabled", true)
	if interaction_area != null:
		interaction_area.monitoring = false


# --- placeholder visuals ------------------------------------------------------

func _draw() -> void:
	if definition == null:
		return
	var scale_factor := definition.visual_scale
	match definition.visual:
		ResourceNodeDefinition.Visual.TREE:
			_draw_tree(scale_factor)
		ResourceNodeDefinition.Visual.ROCK:
			_draw_rock(scale_factor)
		ResourceNodeDefinition.Visual.BUSH:
			_draw_bush(scale_factor)
		_:
			_draw_pile(scale_factor)


func _draw_tree(scale_factor: float) -> void:
	var depleted_now := is_depleted()
	var trunk_height := 26.0 * scale_factor
	draw_rect(Rect2(-3.0 * scale_factor, -trunk_height * 0.4, 6.0 * scale_factor, trunk_height),
			definition.accent_color, true)
	if depleted_now:
		# Stump: short trunk plus a cut top.
		draw_circle(Vector2(0, -trunk_height * 0.4), 5.0 * scale_factor, definition.accent_color.lightened(0.15))
		return
	var canopy := definition.primary_color
	draw_circle(Vector2(0, -trunk_height * 0.75), 17.0 * scale_factor, canopy)
	draw_circle(Vector2(-11.0, -trunk_height * 0.45), 12.0 * scale_factor, canopy.darkened(0.12))
	draw_circle(Vector2(11.0, -trunk_height * 0.45), 12.0 * scale_factor, canopy.darkened(0.12))
	draw_circle(Vector2(0, -trunk_height * 1.1), 11.0 * scale_factor, canopy.lightened(0.1))


func _draw_rock(scale_factor: float) -> void:
	var color := definition.primary_color
	if is_depleted():
		color = color.darkened(0.3)
	var points := PackedVector2Array([
		Vector2(-12, 6), Vector2(-8, -8), Vector2(0, -12),
		Vector2(9, -7), Vector2(12, 5), Vector2(4, 10),
	])
	var scaled := PackedVector2Array()
	for point in points:
		scaled.append(point * scale_factor)
	draw_colored_polygon(scaled, color)
	draw_polyline(scaled, definition.accent_color, 2.0)


func _draw_bush(scale_factor: float) -> void:
	var color := definition.primary_color
	if is_depleted():
		color = color.darkened(0.25)
	draw_circle(Vector2.ZERO, 10.0 * scale_factor, color)
	draw_circle(Vector2(-7.0 * scale_factor, 3.0), 7.0 * scale_factor, color.darkened(0.1))
	draw_circle(Vector2(7.0 * scale_factor, 3.0), 7.0 * scale_factor, color.darkened(0.1))
	if not is_depleted():
		draw_circle(Vector2(-3.0, -2.0), 2.6 * scale_factor, definition.accent_color.lightened(0.25))
		draw_circle(Vector2(5.0, 1.0), 2.6 * scale_factor, definition.accent_color.lightened(0.25))


func _draw_pile(scale_factor: float) -> void:
	var color := definition.primary_color
	if is_depleted():
		color = color.darkened(0.35)
	draw_rect(Rect2(-13.0 * scale_factor, -9.0 * scale_factor, 26.0 * scale_factor, 18.0 * scale_factor),
			color, true)
	draw_rect(Rect2(-13.0 * scale_factor, -9.0 * scale_factor, 26.0 * scale_factor, 18.0 * scale_factor),
			definition.accent_color, false, 2.0)
	if not is_depleted():
		draw_line(Vector2(-8.0, 2.0) * scale_factor, Vector2(8.0, -4.0) * scale_factor,
				definition.accent_color.lightened(0.3), 2.0)
