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


# --- visuals ---------------------------------------------------------------

## Shadow helper.
func _draw_shadow(center: Vector2, radius: float, alpha: float = 0.18) -> void:
	draw_circle(center, radius, Color(0, 0, 0, alpha))


func _draw_rounded_rect(rect: Rect2, color: Color, radius: float) -> void:
	draw_rect(rect, color, true)
	draw_circle(Vector2(rect.position.x + radius, rect.position.y + radius), radius, color)
	draw_circle(Vector2(rect.end.x - radius, rect.position.y + radius), radius, color)
	draw_circle(Vector2(rect.position.x + radius, rect.end.y - radius), radius, color)
	draw_circle(Vector2(rect.end.x - radius, rect.end.y - radius), radius, color)


func _draw() -> void:
	if definition == null:
		return
	var sf := definition.visual_scale
	match definition.visual:
		ResourceNodeDefinition.Visual.TREE:
			_draw_tree(sf)
		ResourceNodeDefinition.Visual.ROCK:
			_draw_rock(sf)
		ResourceNodeDefinition.Visual.BUSH:
			_draw_bush(sf)
		_:
			_draw_pile(sf)


func _draw_tree(sf: float) -> void:
	var depleted := is_depleted()
	var trunk_h := 30.0 * sf
	var bark := definition.accent_color
	var canopy := definition.primary_color

	# Shadow.
	_draw_shadow(Vector2(0, 4 * sf), 16.0 * sf)

	# Trunk — tapered rectangle.
	_draw_rounded_rect(Rect2(-3.5 * sf, -trunk_h * 0.35, 7.0 * sf, trunk_h), bark, 2.0)
	# Bark texture lines.
	draw_line(Vector2(-1 * sf, -trunk_h * 0.2), Vector2(-1 * sf, trunk_h * 0.3), bark.lightened(0.1), 1.0)
	draw_line(Vector2(1.5 * sf, -trunk_h * 0.25), Vector2(1.5 * sf, trunk_h * 0.15), bark.darkened(0.1), 1.0)

	if depleted:
		# Stump.
		_draw_rounded_rect(Rect2(-6 * sf, -4 * sf, 12 * sf, 8 * sf), bark.lightened(0.12), 2.0)
		draw_circle(Vector2(0, -4 * sf), 6 * sf, bark.lightened(0.2))
		# Ring.
		draw_circle(Vector2(0, -4 * sf), 3 * sf, bark.darkened(0.05))
		return

	# Main canopy — layered circles for organic shape.
	draw_circle(Vector2(-8 * sf, -trunk_h * 0.5), 13.0 * sf, canopy.darkened(0.15))
	draw_circle(Vector2(8 * sf, -trunk_h * 0.5), 13.0 * sf, canopy.darkened(0.15))
	draw_circle(Vector2(0, -trunk_h * 0.7), 16.0 * sf, canopy)
	draw_circle(Vector2(-5 * sf, -trunk_h * 0.9), 11.0 * sf, canopy.lightened(0.08))
	draw_circle(Vector2(5 * sf, -trunk_h * 0.85), 10.0 * sf, canopy.lightened(0.06))
	# Highlight.
	draw_circle(Vector2(3 * sf, -trunk_h * 1.05), 6.0 * sf, canopy.lightened(0.15))
	# Small branches peeking out.
	draw_line(Vector2(-5 * sf, -trunk_h * 0.3), Vector2(-14 * sf, -trunk_h * 0.45), bark, 2.0)
	draw_line(Vector2(5 * sf, -trunk_h * 0.3), Vector2(12 * sf, -trunk_h * 0.4), bark, 2.0)


func _draw_rock(sf: float) -> void:
	var color := definition.primary_color
	var outline := definition.accent_color
	if is_depleted():
		color = color.darkened(0.35)
		outline = outline.darkened(0.3)

	# Shadow.
	_draw_shadow(Vector2(2 * sf, 6 * sf), 14.0 * sf)

	# Main boulder — organic polygon.
	var main_pts := PackedVector2Array([
		Vector2(-14, 5), Vector2(-10, -7), Vector2(-3, -12),
		Vector2(5, -10), Vector2(12, -4), Vector2(14, 5),
		Vector2(8, 10), Vector2(-6, 9),
	])
	var scaled_main := PackedVector2Array()
	for p in main_pts:
		scaled_main.append(p * sf)
	draw_colored_polygon(scaled_main, color)
	# Outline.
	draw_polyline(scaled_main, outline.darkened(0.15), 2.0)

	# Smaller rock beside it.
	var small_pts := PackedVector2Array([
		Vector2(8, 2), Vector2(14, -3), Vector2(18, 2),
		Vector2(14, 8),
	])
	var scaled_small := PackedVector2Array()
	for p in small_pts:
		scaled_small.append(p * sf)
	draw_colored_polygon(scaled_small, color.darkened(0.1))

	# Crack / highlight line.
	draw_line(Vector2(-6, -6) * sf, Vector2(4, -2) * sf, color.lightened(0.12), 1.5)
	# Speckle.
	draw_circle(Vector2(-2, -4) * sf, 2.0 * sf, color.lightened(0.08))
	draw_circle(Vector2(6, 1) * sf, 1.5 * sf, color.lightened(0.06))


func _draw_bush(sf: float) -> void:
	var color := definition.primary_color
	var berry := definition.accent_color
	if is_depleted():
		color = color.darkened(0.3)

	# Shadow.
	_draw_shadow(Vector2(0, 5 * sf), 11.0 * sf)

	# Bare branches (always visible, even when depleted).
	draw_line(Vector2(-4, 0) * sf, Vector2(-12, -10) * sf, Color(0.3, 0.22, 0.15), 1.5)
	draw_line(Vector2(4, 0) * sf, Vector2(10, -8) * sf, Color(0.3, 0.22, 0.15), 1.5)
	draw_line(Vector2(0, 2) * sf, Vector2(0, -12) * sf, Color(0.3, 0.22, 0.15), 1.5)

	if not is_depleted():
		# Leaf clusters.
		draw_circle(Vector2(0, -4 * sf), 9.0 * sf, color)
		draw_circle(Vector2(-7 * sf, 1 * sf), 7.0 * sf, color.darkened(0.08))
		draw_circle(Vector2(7 * sf, 1 * sf), 7.0 * sf, color.darkened(0.08))
		draw_circle(Vector2(-3 * sf, -8 * sf), 6.0 * sf, color.lightened(0.06))
		draw_circle(Vector2(4 * sf, -7 * sf), 5.5 * sf, color.lightened(0.04))
		# Berries / flowers.
		draw_circle(Vector2(-4 * sf, -3 * sf), 2.2 * sf, berry.lightened(0.15))
		draw_circle(Vector2(3 * sf, -5 * sf), 2.0 * sf, berry.lightened(0.15))
		draw_circle(Vector2(6 * sf, 0), 1.8 * sf, berry.lightened(0.1))
	else:
		# Withered stub.
		draw_circle(Vector2(0, 0), 4.0 * sf, color.darkened(0.2))


func _draw_pile(sf: float) -> void:
	var color := definition.primary_color
	var outline := definition.accent_color
	if is_depleted():
		color = color.darkened(0.4)
		outline = outline.darkened(0.3)

	# Shadow.
	_draw_shadow(Vector2(1 * sf, 6 * sf), 13.0 * sf)

	# Main pile body — stacked irregular shapes.
	var body_pts := PackedVector2Array([
		Vector2(-14, 4), Vector2(-10, -6), Vector2(-4, -10),
		Vector2(4, -9), Vector2(11, -5), Vector2(13, 4),
		Vector2(7, 9), Vector2(-8, 8),
	])
	var scaled_body := PackedVector2Array()
	for p in body_pts:
		scaled_body.append(p * sf)
	draw_colored_polygon(scaled_body, color)
	draw_polyline(scaled_body, outline.darkened(0.1), 2.0)

	# Individual pieces on top.
	var piece1 := PackedVector2Array([
		Vector2(-6, -3), Vector2(-3, -8), Vector2(2, -5),
	])
	var scaled_p1 := PackedVector2Array()
	for p in piece1:
		scaled_p1.append(p * sf)
	draw_colored_polygon(scaled_p1, color.lightened(0.08))

	var piece2 := PackedVector2Array([
		Vector2(2, -2), Vector2(7, -7), Vector2(10, -1),
	])
	var scaled_p2 := PackedVector2Array()
	for p in piece2:
		scaled_p2.append(p * sf)
	draw_colored_polygon(scaled_p2, color.darkened(0.05))

	# Highlight specks.
	draw_circle(Vector2(-2, -5) * sf, 1.5 * sf, color.lightened(0.12))
	draw_circle(Vector2(5, -4) * sf, 1.5 * sf, color.lightened(0.1))
