class_name Structure
extends StaticBody2D
## A player-built (or world-spawned) structure.
##
## One scene drives every buildable: the BuildableDefinition decides footprint,
## health, behaviour and colour. Behaviours implemented for Phase 2:
## - SOLID: blocks movement;
## - DOOR: blocks movement until opened (then it is walk-through);
## - STORAGE: owns an Inventory that the owner can open.
##
## Ownership is stored as an id string so it can move to a server-side account id
## later without touching this script.

signal destroyed(structure: Structure)
signal door_toggled(structure: Structure, open: bool)

@export var definition: BuildableDefinition
@export var owner_id: String = ""

@onready var health: HealthComponent = $Health
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var interaction_area: Area2D = $InteractionArea
@onready var interaction_shape: CollisionShape2D = $InteractionArea/CollisionShape2D
@onready var storage: InventoryComponent = $Storage

var door_open: bool = false
var _built_position := Vector2.ZERO


func _ready() -> void:
	add_to_group("structure")
	add_to_group("streamed")
	add_to_group("interactable")
	_built_position = position
	if definition == null:
		push_error("[Structure] %s is missing a definition" % name)
		return
	_apply_definition()
	health.died.connect(_on_died)
	queue_redraw()


func _apply_definition() -> void:
	health.set_max_health(definition.max_health, false)
	health.current_health = definition.max_health
	health.health_changed.emit(health.current_health, health.max_health)

	if body_shape != null and body_shape.shape is RectangleShape2D:
		var body_rect := body_shape.shape as RectangleShape2D
		body_rect.size = definition.collision_size
	# Decoration pieces (floors) are walkable and never block building.
	if body_shape != null:
		body_shape.set_deferred("disabled", not definition.blocks_movement())
	if interaction_shape != null and interaction_shape.shape is CircleShape2D:
		var interaction_circle := interaction_shape.shape as CircleShape2D
		interaction_circle.radius = maxf(definition.collision_size.length() * 0.6, 30.0)

	if storage != null:
		storage.capacity = maxi(1, definition.storage_capacity)
		storage.set_process(false)

	# Only doors and storage crates are worth interacting with; walls stay inert
	# so the interaction prompt never points at a plain wall.
	if interaction_area != null:
		interaction_area.monitoring = is_door() or is_storage()
	if not is_door() and not is_storage():
		remove_from_group("interactable")


func is_storage() -> bool:
	return definition != null and definition.is_storage()


func is_door() -> bool:
	return definition != null and definition.behaviour == BuildableDefinition.Behaviour.DOOR


func get_structure_id() -> String:
	return "%s@%d,%d" % [
		definition.id if definition != null else "unknown",
		roundi(global_position.x),
		roundi(global_position.y),
	]


# --- interaction --------------------------------------------------------------

func get_interaction_label() -> String:
	if definition == null:
		return "Structure"
	if is_door():
		return "%s Door" % ("Close" if door_open else "Open")
	if is_storage():
		return "Open %s" % definition.display_name
	return definition.display_name


func interact(actor: Node) -> bool:
	if is_door():
		toggle_door()
		GameEvents.interaction_used.emit(self)
		return true
	if is_storage():
		var inventory := get_inventory()
		if inventory != null:
			GameEvents.container_opened.emit(inventory, definition.display_name)
			GameEvents.interaction_used.emit(self)
			return true
	return false


func toggle_door() -> void:
	door_open = not door_open
	if body_shape != null:
		body_shape.set_deferred("disabled", door_open)
	door_toggled.emit(self, door_open)
	queue_redraw()


func get_inventory() -> Inventory:
	if storage == null or not is_storage():
		return null
	return storage.inventory


# --- damage / destruction -----------------------------------------------------

func apply_damage(amount: float, source: Node = null) -> float:
	return health.apply_damage(DamageInfo.create(amount, source, DamageInfo.Type.MELEE, global_position))


func repair(amount: float) -> float:
	return health.heal(amount)


func _on_died(_info: DamageInfo) -> void:
	# Spill contents before disappearing so stored loot is never silently lost.
	var inventory := get_inventory()
	if inventory != null and not inventory.count_all_items().is_empty():
		var world := get_tree().get_first_node_in_group("world")
		if world != null and world.has_method("spawn_loot_bag"):
			world.spawn_loot_bag(global_position, inventory.to_dict())
	destroyed.emit(self)
	queue_free()


# --- streaming ----------------------------------------------------------------

func set_streamed_active(active: bool) -> void:
	visible = active
	if body_shape != null:
		body_shape.set_deferred("disabled", not active or door_open)
	if interaction_area != null:
		interaction_area.monitoring = active and (is_door() or is_storage())


# --- persistence --------------------------------------------------------------

func serialize_state() -> Dictionary:
	var inventory := get_inventory()
	var state := {
		"definition": definition.id if definition != null else "",
		"position": [position.x, position.y],
		"rotation": rotation,
		"owner": owner_id,
		"health": health.current_health,
		"door_open": door_open,
	}
	if inventory != null:
		state["inventory"] = inventory.to_dict()
	return state


func apply_state(state: Dictionary) -> void:
	var position_data: Array = state.get("position", [])
	if position_data.size() == 2:
		position = Vector2(float(position_data[0]), float(position_data[1]))
	rotation = float(state.get("rotation", rotation))
	owner_id = str(state.get("owner", owner_id))
	health.set_health(float(state.get("health", health.max_health)))
	var should_open := bool(state.get("door_open", false))
	if should_open != door_open:
		toggle_door()
	var inventory := get_inventory()
	if inventory != null:
		inventory.load_from_dict(state.get("inventory", {}))


# --- visuals ---------------------------------------------------------------

func _draw_floor(rect: Rect2) -> void:
	var wood := definition.primary_color
	var grain := definition.accent_color
	# Base floor.
	draw_rect(rect, wood, true)
	# Plank lines.
	var plank_h := maxf(5.0, rect.size.y / 4.0)
	var y := rect.position.y + plank_h
	while y < rect.end.y:
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), grain.darkened(0.1), 1.0)
		y += plank_h
	# Nail dots.
	for i in 3:
		var nx := rect.position.x + rect.size.x * (0.2 + i * 0.3)
		draw_circle(Vector2(nx, rect.position.y + 3), 1.0, grain.darkened(0.2))
		draw_circle(Vector2(nx, rect.end.y - 3), 1.0, grain.darkened(0.2))
	# Border.
	draw_rect(rect, grain.darkened(0.05), false, 1.5)


func _draw() -> void:
	if definition == null:
		return
	var half := definition.collision_size * 0.5
	var rect := Rect2(-half, definition.collision_size)
	var wood := definition.primary_color
	var grain := definition.accent_color

	if definition.behaviour == BuildableDefinition.Behaviour.DECORATION:
		_draw_floor(rect)
		return

	if is_door():
		_draw_door(rect, wood, grain)
		return

	if is_storage():
		_draw_storage(rect, wood, grain)
		return

	# --- wall / fence / barricade ---
	var body_color := wood
	var dark := wood.darkened(0.12)
	# Main body.
	draw_rect(rect, body_color, true)
	# Vertical plank seams.
	var plank_w := maxf(6.0, rect.size.x / 4.0)
	var x := rect.position.x + plank_w
	while x < rect.end.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), grain.darkened(0.08), 1.0)
		x += plank_w
	# Horizontal cross-beam.
	draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y * 0.35),
		Vector2(rect.end.x, rect.position.y + rect.size.y * 0.35), grain, 2.5)
	# Nails.
	for i in 4:
		var nx := rect.position.x + rect.size.x * (0.15 + i * 0.23)
		draw_circle(Vector2(nx, rect.position.y + rect.size.y * 0.35), 1.2, grain.darkened(0.2))
	# Border.
	draw_rect(rect, grain.darkened(0.05), false, 2.0)

	# Health bar when damaged.
	if health != null and not health.is_full():
		var ratio := health.get_ratio()
		var bar_width := maxf(definition.collision_size.x, 24.0)
		var half_y := definition.collision_size.y * 0.5
		draw_rect(Rect2(-bar_width * 0.5, -half_y - 10.0, bar_width, 4.0), Color(0, 0, 0, 0.6), true)
		draw_rect(Rect2(-bar_width * 0.5, -half_y - 10.0, bar_width * ratio, 4.0),
				Color(0.85, 0.35, 0.25), true)


func _draw_door(rect: Rect2, wood: Color, grain: Color) -> void:
	if door_open:
		# Open door — just a dark opening.
		draw_rect(rect, wood.darkened(0.5), true)
		draw_rect(rect, grain.darkened(0.2), false, 2.0)
		return
	# Closed door.
	draw_rect(rect, wood, true)
	# Planks.
	var plank_w := maxf(6.0, rect.size.x / 3.0)
	var x := rect.position.x + plank_w
	while x < rect.end.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), grain.darkened(0.08), 1.0)
		x += plank_w
	# Cross brace.
	draw_line(Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.end.y), grain, 1.5)
	draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), grain, 1.5)
	# Hinges.
	var hinge_y1 := rect.position.y + 6.0
	var hinge_y2 := rect.end.y - 6.0
	draw_circle(Vector2(rect.position.x + 3, hinge_y1), 2.0, Color(0.35, 0.32, 0.30))
	draw_circle(Vector2(rect.position.x + 3, hinge_y2), 2.0, Color(0.35, 0.32, 0.30))
	# Handle.
	draw_circle(Vector2(rect.end.x - 5, rect.position.y + rect.size.y * 0.5), 2.5, Color(0.5, 0.48, 0.42))
	# Border.
	draw_rect(rect, grain.darkened(0.05), false, 2.0)


func _draw_storage(rect: Rect2, wood: Color, grain: Color) -> void:
	# Crate body.
	draw_rect(rect, wood.darkened(0.05), true)
	# Reinforcement straps.
	var strap_color := Color(0.30, 0.28, 0.25)
	draw_line(Vector2(rect.position.x + 2, rect.position.y), Vector2(rect.position.x + 2, rect.end.y), strap_color, 2.0)
	draw_line(Vector2(rect.end.x - 2, rect.position.y), Vector2(rect.end.x - 2, rect.end.y), strap_color, 2.0)
	# Horizontal strap.
	draw_line(Vector2(rect.position.x, rect.position.y + rect.size.y * 0.45),
		Vector2(rect.end.x, rect.position.y + rect.size.y * 0.45), strap_color, 2.0)
	# Metal corner brackets.
	var bracket_color := Color(0.45, 0.42, 0.38)
	for corner in [Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x - 6, rect.position.y),
			Vector2(rect.position.x, rect.end.y - 6), Vector2(rect.end.x - 6, rect.end.y - 6)]:
		draw_rect(Rect2(corner, Vector2(6, 6)), bracket_color, true)
	# Lid line.
	draw_line(Vector2(rect.position.x, rect.position.y + 4), Vector2(rect.end.x, rect.position.y + 4), grain.lightened(0.1), 1.5)
	# Handle on top.
	var cx := rect.position.x + rect.size.x * 0.5
	draw_line(Vector2(cx - 5, rect.position.y - 3), Vector2(cx + 5, rect.position.y - 3), strap_color, 2.0)
	# Border.
	draw_rect(rect, grain.darkened(0.05), false, 2.0)

	# Health bar when damaged.
	if health != null and not health.is_full():
		var ratio := health.get_ratio()
		var bar_width := maxf(definition.collision_size.x, 24.0)
		var half_y := definition.collision_size.y * 0.5
		draw_rect(Rect2(-bar_width * 0.5, -half_y - 10.0, bar_width, 4.0), Color(0, 0, 0, 0.6), true)
		draw_rect(Rect2(-bar_width * 0.5, -half_y - 10.0, bar_width * ratio, 4.0),
				Color(0.85, 0.35, 0.25), true)
