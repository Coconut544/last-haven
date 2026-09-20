class_name Player
extends CharacterBody2D
## The survivor.
##
## Owns movement, the interaction/gathering loop, melee attacks, survival stats,
## the inventory and the build system. Everything it emits goes to the event bus,
## so the HUD can be swapped out without touching this file.
##
## Movement input comes from two sources that are merged here: the on-screen
## joystick calls `set_move_input()` and the keyboard actions are read directly,
## which keeps desktop testing possible without a separate code path.

signal died()
signal respawned()

## Fists: weaker and slower than any crafted weapon.
const BASE_ATTACK_DAMAGE := 6.0
const BASE_ATTACK_COOLDOWN := 0.55
const BASE_ATTACK_RANGE := 26.0
## Sprint is noisy; a zombie can hear it from here.
const SPRINT_NOISE_RADIUS := 190.0
const ATTACK_NOISE_RADIUS := 210.0

@export var walk_speed: float = 108.0
@export var run_speed: float = 178.0
@export var acceleration: float = 1200.0
@export var friction: float = 1500.0

@onready var health: HealthComponent = $Health
@onready var stats: SurvivalStats = $Stats
@onready var inventory_component: InventoryComponent = $Inventory
@onready var interactor: Interactor = $Interactor
@onready var attack_hitbox: Hitbox = $AttackHitbox
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var build_system: BuildSystem = $BuildSystem

## Vector set by the virtual joystick (already normalized, length 0..1).
var move_input: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.DOWN
## Inventory slot currently selected on the hotbar (slots 0-4 are the hotbar).
var active_slot: int = 0
## Modular appearance: slot name -> item id. Empty slots fall back to defaults.
var equipment: Dictionary = {}
var is_dead: bool = false

var _attack_cooldown: float = 0.0
var _attack_flash: float = 0.0
var _gathering: bool = false
var _gather_target: Node = null
var _gather_time: float = 0.0
var _gather_duration: float = 1.0
var _interaction_timer: float = 0.0
var _sprint_noise_timer: float = 0.0
var _last_facing: Vector2 = Vector2.DOWN


func _ready() -> void:
	add_to_group("player")
	stats.setup(health)
	build_system.set_inventory(inventory_component)
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	stats.stat_changed.connect(_on_stat_changed)
	if inventory_component.inventory != null:
		inventory_component.inventory.changed.connect(_on_inventory_changed)
	GameEvents.noise_emitted.connect(_on_noise)
	stats.emit_all()
	_on_health_changed(health.current_health, health.max_health)


# --- input --------------------------------------------------------------------

## Called by the virtual joystick UI.
func set_move_input(vector: Vector2) -> void:
	move_input = vector.limit_length(1.0)


func _read_move_input() -> Vector2:
	var vector := move_input
	if vector.length_squared() < 0.01:
		vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return vector.limit_length(1.0)


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _attack_flash > 0.0:
		_attack_flash -= delta
		queue_redraw()

	var input_vector := _read_move_input()
	_handle_movement(input_vector, delta)
	_update_gathering(delta)
	_tick_interaction(delta)
	_tick_actions(delta)


func _handle_movement(input_vector: Vector2, delta: float) -> void:
	var speed := walk_speed
	if _wants_to_sprint(input_vector):
		speed = run_speed
		stats.drain_stamina(stats.stamina_drain * delta)
		_sprint_noise_timer -= delta
		if _sprint_noise_timer <= 0.0:
			_sprint_noise_timer = 0.6
			GameEvents.noise_emitted.emit(global_position, SPRINT_NOISE_RADIUS, self)
	else:
		_sprint_noise_timer = 0.0

	var target_velocity := input_vector * speed
	var rate := acceleration if input_vector.length_squared() > 0.01 else friction
	velocity = velocity.move_toward(target_velocity, rate * delta)
	move_and_slide()

	if input_vector.length_squared() > 0.01:
		facing = input_vector.normalized()
		if facing != _last_facing:
			_last_facing = facing
			queue_redraw()


func _wants_to_sprint(input_vector: Vector2) -> bool:
	if input_vector.length_squared() < 0.01:
		return false
	if Input.is_action_pressed("run"):
		return stats.can_sprint()
	# On touch devices sprinting means pushing the stick to its edge.
	return input_vector.length() > 0.92 and stats.can_sprint()


func _tick_actions(_delta: float) -> void:
	if build_system.is_active():
		# In build mode the attack/interact buttons place the pending structure.
		return
	if Input.is_action_just_pressed("attack"):
		attack()
	elif Input.is_action_just_pressed("interact"):
		interact()


func _tick_interaction(delta: float) -> void:
	_interaction_timer -= delta
	if _interaction_timer > 0.0:
		return
	_interaction_timer = 0.15
	interactor.refresh()


# --- combat -------------------------------------------------------------------

func get_active_item() -> ItemDefinition:
	var inventory := get_inventory()
	if inventory == null:
		return null
	var stack := inventory.get_slot(active_slot)
	if stack == null:
		return null
	return stack.get_definition()


func get_tool_type() -> ItemDefinition.ToolType:
	var item := get_active_item()
	return item.tool_type if item != null else ItemDefinition.ToolType.NONE


func attack() -> bool:
	if is_dead or _attack_cooldown > 0.0:
		return false
	var item := get_active_item()
	var damage := BASE_ATTACK_DAMAGE
	var cooldown := BASE_ATTACK_COOLDOWN
	var reach := BASE_ATTACK_RANGE
	if item != null:
		if item.attack_damage > 0.0:
			damage = item.attack_damage
			cooldown = item.attack_cooldown
		reach = item.attack_range
	_attack_cooldown = maxf(0.15, cooldown)
	_attack_flash = 0.2
	attack_hitbox.reach = reach
	attack_hitbox.activate(facing, damage)
	cancel_gathering()
	GameEvents.noise_emitted.emit(global_position, ATTACK_NOISE_RADIUS, self)
	queue_redraw()
	return true


func _on_damaged(info: DamageInfo) -> void:
	if info == null:
		return
	cancel_gathering()
	queue_redraw()


# --- interaction / gathering --------------------------------------------------

func interact() -> bool:
	var target := interactor.get_target()
	if target == null:
		GameEvents.toast_requested.emit("Nothing here to use.")
		return false
	if target.has_method("interact"):
		return bool(target.interact(self))
	return false


## Called by gatherable nodes. Gathering is time based and interruptible.
func begin_gathering(target: Node) -> void:
	if is_dead or target == null or not target.has_method("harvest"):
		return
	if _gathering and _gather_target == target:
		return
	_gather_target = target
	_gathering = true
	_gather_time = 0.0
	_gather_duration = maxf(0.1, float(target.get_gather_duration(get_tool_type())))
	GameEvents.gathering_started.emit(target)


func cancel_gathering() -> void:
	if not _gathering:
		return
	_gathering = false
	_gather_target = null
	_gather_time = 0.0
	GameEvents.gathering_cancelled.emit()


func is_gathering() -> bool:
	return _gathering


func get_gather_target() -> Node:
	return _gather_target if _gathering else null


func _update_gathering(delta: float) -> void:
	if not _gathering:
		return
	if _gather_target == null or not is_instance_valid(_gather_target):
		cancel_gathering()
		return
	if not bool(_gather_target.can_gather()):
		cancel_gathering()
		return
	if global_position.distance_to((_gather_target as Node2D).global_position) > interactor.max_reach + 12.0:
		cancel_gathering()
		return

	_gather_time += delta
	GameEvents.gathering_progress.emit(clampf(_gather_time / _gather_duration, 0.0, 1.0))
	if _gather_time >= _gather_duration:
		_complete_gathering()


func _complete_gathering() -> void:
	var target := _gather_target
	cancel_gathering()
	if target == null or not is_instance_valid(target):
		return
	var harvested: Array = target.harvest(get_tool_type())
	if harvested.is_empty():
		return
	var dropped: Array[Ingredient] = []
	for entry in harvested:
		var ingredient := entry as Ingredient
		if ingredient == null:
			continue
		var leftover := inventory_component.add_item(ingredient.item_id, ingredient.quantity)
		var gained := ingredient.quantity - leftover
		if gained > 0:
			GameEvents.item_gathered.emit(ingredient.item_id, gained)
		if leftover > 0:
			dropped.append(Ingredient.create(ingredient.item_id, leftover))
			GameEvents.toast_requested.emit("Inventory full: %d x %s left behind"
					% [leftover, _item_label(ingredient.item_id)])
	if not dropped.is_empty():
		drop_ingredients(dropped)


# --- inventory helpers --------------------------------------------------------

func get_inventory() -> Inventory:
	return inventory_component.inventory if inventory_component != null else null


func set_active_slot(index: int) -> void:
	var inventory := get_inventory()
	if inventory == null or not inventory.is_valid_index(index):
		return
	active_slot = index
	GameEvents.hotbar_changed.emit(active_slot)
	queue_redraw()


## Uses the item in a slot (consumables only). Returns true when consumed.
func use_slot(index: int) -> bool:
	var inventory := get_inventory()
	if inventory == null or is_dead:
		return false
	var stack := inventory.get_slot(index)
	if stack == null:
		return false
	var definition := stack.get_definition()
	if definition == null:
		return false
	if definition.is_consumable():
		if not stats.consume(definition):
			GameEvents.toast_requested.emit("%s has no effect right now." % definition.display_name)
			return false
		inventory.take_from_slot(index, 1)
		GameEvents.toast_requested.emit("Used %s" % definition.display_name)
		return true
	if definition.is_tool():
		set_active_slot(index)
		equip_from_slot(index)
		GameEvents.toast_requested.emit("Equipped %s" % definition.display_name)
		return true
	GameEvents.toast_requested.emit("%s cannot be used directly." % definition.display_name)
	return false


func equip_from_slot(index: int) -> void:
	var inventory := get_inventory()
	if inventory == null:
		return
	var stack := inventory.get_slot(index)
	if stack == null:
		return
	var definition := stack.get_definition()
	if definition == null:
		return
	equipment["tool"] = definition.id
	if definition.category == ItemDefinition.Category.WEAPON:
		equipment["weapon"] = definition.id
	queue_redraw()


## Drops items from a slot in front of the player.
func drop_slot(index: int, quantity: int = -1) -> bool:
	var inventory := get_inventory()
	if inventory == null:
		return false
	var stack := inventory.take_from_slot(index, quantity)
	if stack == null:
		return false
	drop_ingredients([Ingredient.create(stack.item_id, stack.quantity)])
	GameEvents.toast_requested.emit("Dropped %d x %s" % [stack.quantity, _item_label(stack.item_id)])
	return true


## Spills the whole inventory (used on death, and by the debug menu).
func drop_all_items() -> void:
	var inventory := get_inventory()
	if inventory == null:
		return
	var totals := inventory.count_all_items()
	if totals.is_empty():
		return
	var ingredients: Array[Ingredient] = []
	for item_id: String in totals.keys():
		ingredients.append(Ingredient.create(item_id, int(totals[item_id])))
	inventory.clear()
	drop_ingredients(ingredients)


func drop_ingredients(ingredients: Array[Ingredient]) -> void:
	if ingredients.is_empty():
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("spawn_loot_bag_from_ingredients"):
		return
	var drop_position := global_position + facing.normalized() * 26.0
	world.spawn_loot_bag_from_ingredients(drop_position, ingredients)


# --- health / death -----------------------------------------------------------

func _on_health_changed(current: float, maximum: float) -> void:
	GameEvents.health_changed.emit(current, maximum)


func _on_stat_changed(stat_id: String, value: float, maximum: float) -> void:
	GameEvents.stat_changed.emit(stat_id, value, maximum)


func _on_inventory_changed() -> void:
	queue_redraw()


func _on_noise(_position: Vector2, _radius: float, source: Node) -> void:
	if source == self:
		return


func _on_died(_info: DamageInfo) -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector2.ZERO
	cancel_gathering()
	interactor.set_deferred("monitoring", false)
	build_system.exit_build_mode()
	# Death is a real setback in this genre: the cargo stays on the ground.
	drop_all_items()
	died.emit()
	GameEvents.player_died.emit()
	queue_redraw()


## Prepares the survivor for a fresh run: new game, or the moment before a save
## is applied. Nothing is carried over.
func reset_for_new_game(spawn_position: Vector2) -> void:
	global_position = spawn_position
	facing = Vector2.DOWN
	_last_facing = Vector2.DOWN
	move_input = Vector2.ZERO
	is_dead = false
	active_slot = 0
	equipment.clear()
	_attack_cooldown = 0.0
	_attack_flash = 0.0
	cancel_gathering()
	build_system.exit_build_mode()
	health.set_max_health(health.max_health, false)
	health.restore_full()
	stats.reset()
	var inventory := get_inventory()
	if inventory != null:
		inventory.clear()
	interactor.set_deferred("monitoring", true)
	stats.emit_all()
	_on_health_changed(health.current_health, health.max_health)
	GameEvents.hotbar_changed.emit(active_slot)
	queue_redraw()


## Brings the player back. Used by the death screen and by debug tools.
func respawn_at(spawn_position: Vector2) -> void:
	if not is_dead and health.is_alive():
		return
	global_position = spawn_position
	health.restore_full()
	stats.restore_full()
	is_dead = false
	facing = Vector2.DOWN
	move_input = Vector2.ZERO
	interactor.set_deferred("monitoring", true)
	stats.emit_all()
	_on_health_changed(health.current_health, health.max_health)
	respawned.emit()
	GameEvents.player_respawned.emit()
	queue_redraw()


# --- persistence --------------------------------------------------------------

func serialize_state() -> Dictionary:
	var inventory := get_inventory()
	return {
		"position": [global_position.x, global_position.y],
		"health": health.current_health,
		"max_health": health.max_health,
		"stats": stats.serialize_state(),
		"inventory": inventory.to_dict() if inventory != null else {},
		"active_slot": active_slot,
		"equipment": equipment.duplicate(),
		"facing": [facing.x, facing.y],
	}


func apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	var position_data: Array = state.get("position", [])
	if position_data.size() == 2:
		global_position = Vector2(float(position_data[0]), float(position_data[1]))
	var facing_data: Array = state.get("facing", [])
	if facing_data.size() == 2:
		facing = Vector2(float(facing_data[0]), float(facing_data[1]))

	health.set_max_health(float(state.get("max_health", health.max_health)), false)
	health.set_health(float(state.get("health", health.max_health)))
	stats.apply_state(state.get("stats", {}))

	var inventory := get_inventory()
	if inventory != null:
		inventory.load_from_dict(state.get("inventory", {}))

	active_slot = clampi(int(state.get("active_slot", active_slot)), 0, maxi(0, inventory.slot_count - 1)) if inventory != null else 0
	var saved_equipment: Variant = state.get("equipment", {})
	if typeof(saved_equipment) == TYPE_DICTIONARY:
		equipment = (saved_equipment as Dictionary).duplicate()

	is_dead = not health.is_alive()
	GameEvents.hotbar_changed.emit(active_slot)
	queue_redraw()


# --- helpers ------------------------------------------------------------------

func _item_label(item_id: String) -> String:
	var definition := ItemDatabase.get_item(item_id)
	return definition.display_name if definition != null else item_id


func _color_for(slot: String, fallback: Color) -> Color:
	var item_id := str(equipment.get(slot, ""))
	if item_id.is_empty():
		return fallback
	var definition := ItemDatabase.get_item(item_id)
	return definition.icon_color if definition != null else fallback


# --- visuals ---------------------------------------------------------------

## Skin / clothing colours derived from equipment.
var _skin := Color(0.78, 0.62, 0.5)
var _shirt := Color(0.33, 0.39, 0.34)
var _pants := Color(0.22, 0.24, 0.29)
var _hair := Color(0.16, 0.13, 0.11)
var _boots := Color(0.22, 0.17, 0.13)
var _belt := Color(0.28, 0.22, 0.16)


func _draw() -> void:
	if is_dead:
		_draw_corpse()
		return
	_refresh_colors()
	var dir := facing.normalized()
	var facing_angle := dir.angle()

	# Shadow.
	_draw_circle(Vector2(0, 14), 15.0, Color(0, 0, 0, 0.20))

	# --- legs & boots (closer to camera) -----------------------------------
	var leg_w := 5.0
	var leg_h := 10.0
	var leg_y := 2.0
	var boot_h := 3.5
	# Left leg.
	_draw_rounded_rect(Rect2(-8.5, leg_y, leg_w, leg_h), _pants, 1.5)
	_draw_rounded_rect(Rect2(-8.5, leg_y + leg_h, leg_w, boot_h), _boots, 1.5)
	# Right leg.
	_draw_rounded_rect(Rect2(3.5, leg_y, leg_w, leg_h), _pants, 1.5)
	_draw_rounded_rect(Rect2(3.5, leg_y + leg_h, leg_w, boot_h), _boots, 1.5)
	# Belt.
	draw_rect(Rect2(-10, -1, 20, 3.0), _belt, true)
	draw_circle(Vector2(0, 0.5), 2.0, Color(0.6, 0.55, 0.4))

	# --- torso (jacket) -----------------------------------------------------
	var jacket := _shirt
	_draw_rounded_rect(Rect2(-11, -11, 22, 13), jacket, 2.0)
	# Collar.
	draw_line(Vector2(-5, -11), Vector2(5, -11), jacket.lightened(0.15), 1.5)
	# Zipper / seam line.
	draw_line(Vector2(0, -11), Vector2(0, 2), jacket.darkened(0.25), 1.0)
	# Pocket hints.
	draw_rect(Rect2(-9, -3, 7, 5), jacket.darkened(0.08), true)
	draw_rect(Rect2(2, -3, 7, 5), jacket.darkened(0.08), true)

	# --- arms (behind weapon hand) ------------------------------------------
	var arm_w := 4.0
	var arm_h := 9.0
	var left_arm_x := -14.0
	var right_arm_x := 10.0
	var arm_y := -8.0
	# Left arm.
	_draw_rounded_rect(Rect2(left_arm_x, arm_y, arm_w, arm_h), _shirt.darkened(0.10), 1.5)
	_draw_circle(Vector2(left_arm_x + arm_w * 0.5, arm_y + arm_h + 1), 2.5, _skin)
	# Right arm (holds weapon).
	_draw_rounded_rect(Rect2(right_arm_x, arm_y, arm_w, arm_h), _shirt.darkened(0.10), 1.5)
	_draw_circle(Vector2(right_arm_x + arm_w * 0.5, arm_y + arm_h + 1), 2.5, _skin)

	# --- backpack (if equipped, drawn behind torso) --------------------------
	var backpack_id := str(equipment.get("backpack", ""))
	if not backpack_id.is_empty():
		var bp_color := _color_for("backpack", Color(0.40, 0.33, 0.22))
		_draw_rounded_rect(Rect2(-8, -14, 16, 10), bp_color.darkened(0.15), 2.0)
		_draw_rounded_rect(Rect2(-6, -12, 12, 6), bp_color, 2.0)
		# Buckle.
		draw_circle(Vector2(0, -12), 1.5, Color(0.55, 0.50, 0.40))

	# --- head ----------------------------------------------------------------
	var head_pos := Vector2(0, -16)
	_draw_circle(head_pos, 8.0, _skin)
	# Hair (top of head).
	_draw_rounded_rect(Rect2(-8, -24.5, 16, 6.5), _hair, 2.5)
	# Side hair.
	_draw_rounded_rect(Rect2(-8, -21, 3, 5), _hair.darkened(0.08), 1.0)
	_draw_rounded_rect(Rect2(5, -21, 3, 5), _hair.darkened(0.08), 1.0)
	# Face direction dot.
	var face_pos := head_pos + dir * 5.0
	draw_circle(face_pos, 1.6, Color(0.12, 0.10, 0.10))
	# Eyes hint (two tiny dots offset from face direction).
	var perp := Vector2(-dir.y, dir.x)
	_draw_circle(face_pos + perp * 2.2 - dir * 1.5, 1.1, Color(0.10, 0.08, 0.08))
	_draw_circle(face_pos - perp * 2.2 - dir * 1.5, 1.1, Color(0.10, 0.08, 0.08))

	# --- held item -----------------------------------------------------------
	_draw_held_item()
	_draw_attack_flash()


func _draw_held_item() -> void:
	var item := get_active_item()
	if item == null:
		return
	var direction := facing.normalized()
	var origin := direction * 13.0 + Vector2(10, -5) # right hand area
	if item.category == ItemDefinition.Category.WEAPON or item.tool_type != ItemDefinition.ToolType.NONE:
		# Handle.
		var handle_end := origin + direction * 6.0
		draw_line(origin, handle_end, Color(0.35, 0.26, 0.16), 2.5)
		# Head / blade.
		if item.tool_type == ItemDefinition.ToolType.AXE:
			# Axe head.
			draw_circle(handle_end + direction * 3.0, 4.5, Color(0.5, 0.5, 0.52))
			draw_line(handle_end, handle_end + direction * 3.0, Color(0.45, 0.45, 0.48), 2.0)
		elif item.tool_type == ItemDefinition.ToolType.KNIFE:
			# Knife blade.
			draw_line(handle_end, handle_end + direction * 8.0, Color(0.65, 0.65, 0.7), 2.0)
		elif item.tool_type == ItemDefinition.ToolType.PICKAXE:
			# Pickaxe head.
			var perp := Vector2(-direction.y, direction.x)
			draw_line(handle_end + perp * 5, handle_end - perp * 5, Color(0.5, 0.5, 0.52), 3.0)
		elif item.tool_type == ItemDefinition.ToolType.HAMMER:
			# Hammer head.
			draw_rect(Rect2(handle_end.x - 4, handle_end.y - 3, 8, 6), Color(0.48, 0.48, 0.5), true)
		else:
			# Generic weapon.
			draw_circle(handle_end, 4.0, item.icon_color)
	else:
		# Consumable or misc held item.
		draw_circle(origin, 4.5, item.icon_color)


func _draw_attack_flash() -> void:
	if _attack_flash <= 0.0:
		return
	var direction := facing.normalized()
	var start_angle := direction.angle() - 0.8
	var end_angle := direction.angle() + 0.8
	var points := PackedVector2Array()
	for step in 10:
		var a := lerpf(start_angle, end_angle, float(step) / 9.0)
		points.append(Vector2.RIGHT.rotated(a) * (attack_hitbox.reach + 4.0))
	var alpha := clampf(_attack_flash * 5.0, 0.0, 0.85)
	draw_polyline(points, Color(1.0, 0.95, 0.8, alpha), 2.5)
	# Slash arc fill.
	var arc_points := PackedVector2Array([Vector2.ZERO])
	for step in 12:
		var a := lerpf(start_angle, end_angle, float(step) / 11.0)
		arc_points.append(Vector2.RIGHT.rotated(a) * (attack_hitbox.reach - 4.0))
	draw_colored_polygon(arc_points, Color(1.0, 0.92, 0.75, alpha * 0.25))


func _draw_corpse() -> void:
	var dir := facing.normalized()
	var corpse_color := Color(0.28, 0.26, 0.24)
	var skin_color := Color(0.60, 0.48, 0.38)
	# Shadow.
	_draw_circle(Vector2(2, 4), 14.0, Color(0, 0, 0, 0.25))
	# Body (lying on side).
	_draw_rounded_rect(Rect2(-10, -5, 20, 10), corpse_color, 2.0)
	# Head.
	_draw_circle(Vector2(-8, -6), 6.5, skin_color)
	# Arms sprawled.
	draw_line(Vector2(-10, -2), Vector2(-18, -8), Color(0.55, 0.45, 0.38), 2.5)
	draw_line(Vector2(8, -1), Vector2(16, 8), Color(0.55, 0.45, 0.38), 2.5)
	# Legs.
	draw_line(Vector2(-3, 5), Vector2(-8, 14), Color(0.20, 0.19, 0.18), 3.0)
	draw_line(Vector2(3, 5), Vector2(8, 14), Color(0.20, 0.19, 0.18), 3.0)
	# Blood pool.
	_draw_circle(Vector2(0, 8), 8.0, Color(0.35, 0.08, 0.06, 0.45))


# --- tiny drawing helpers --------------------------------------------------

func _refresh_colors() -> void:
	_skin = Color(0.78, 0.62, 0.5)
	_shirt = _color_for("shirt", Color(0.33, 0.39, 0.34))
	_pants = _color_for("pants", Color(0.22, 0.24, 0.29))
	_hair = _color_for("hair", Color(0.16, 0.13, 0.11))
	_boots = _color_for("boots", Color(0.22, 0.17, 0.13))
	_belt = Color(0.28, 0.22, 0.16)


func _draw_circle(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius, color)


func _draw_rounded_rect(rect: Rect2, color: Color, radius: float) -> void:
	# Approximate rounded rect with polygon for _draw compatibility.
	draw_rect(rect, color, true)
	# Corners.
	_draw_circle(Vector2(rect.position.x + radius, rect.position.y + radius), radius, color)
	_draw_circle(Vector2(rect.end.x - radius, rect.position.y + radius), radius, color)
	_draw_circle(Vector2(rect.position.x + radius, rect.end.y - radius), radius, color)
	_draw_circle(Vector2(rect.end.x - radius, rect.end.y - radius), radius, color)
