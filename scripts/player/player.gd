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


# --- placeholder visuals ------------------------------------------------------

func _draw() -> void:
	if is_dead:
		_draw_corpse()
		return
	var skin := Color(0.78, 0.62, 0.5)
	var shirt := _color_for("shirt", Color(0.33, 0.39, 0.34))
	var pants := _color_for("pants", Color(0.22, 0.24, 0.29))
	var hair := _color_for("hair", Color(0.16, 0.13, 0.11))

	draw_circle(Vector2(0, 10), 13.0, Color(0, 0, 0, 0.22))

	# Legs + boots.
	draw_rect(Rect2(-8, 1, 6, 11), pants, true)
	draw_rect(Rect2(2, 1, 6, 11), pants, true)
	draw_rect(Rect2(-8, 10, 6, 3), pants.darkened(0.4), true)
	draw_rect(Rect2(2, 10, 6, 3), pants.darkened(0.4), true)

	# Torso + arms.
	draw_rect(Rect2(-10, -9, 20, 12), shirt, true)
	draw_rect(Rect2(-13, -7, 4, 10), shirt.darkened(0.12), true)
	draw_rect(Rect2(9, -7, 4, 10), shirt.darkened(0.12), true)

	# Backpack, when one is equipped.
	var backpack := str(equipment.get("backpack", ""))
	if not backpack.is_empty():
		draw_rect(Rect2(-7, -11, 14, 8), _color_for("backpack", Color(0.4, 0.33, 0.22)), true)

	# Head, hair and face direction marker.
	draw_circle(Vector2(0, -15), 7.5, skin)
	draw_rect(Rect2(-7.5, -22, 15, 5), hair, true)
	draw_circle(Vector2(0, -15) + facing.normalized() * 4.0, 1.6, Color(0.12, 0.1, 0.1))

	_draw_held_item()
	_draw_attack_flash()


func _draw_held_item() -> void:
	var item := get_active_item()
	if item == null:
		return
	var direction := facing.normalized()
	var origin := direction * 12.0
	if item.category == ItemDefinition.Category.WEAPON or item.tool_type != ItemDefinition.ToolType.NONE:
		var handle_end := origin + direction * 10.0
		draw_line(origin, handle_end, Color(0.35, 0.26, 0.16), 3.0)
		draw_circle(handle_end, 3.5, item.icon_color)
	else:
		draw_circle(origin, 4.0, item.icon_color)


func _draw_attack_flash() -> void:
	if _attack_flash <= 0.0:
		return
	var direction := facing.normalized()
	var start := direction.angle() - 0.7
	var end := direction.angle() + 0.7
	var points := PackedVector2Array()
	for step in 8:
		var angle := lerpf(start, end, float(step) / 7.0)
		points.append(Vector2.RIGHT.rotated(angle) * (attack_hitbox.reach + 6.0))
	draw_polyline(points, Color(1.0, 0.95, 0.8, clampf(_attack_flash * 4.0, 0.0, 0.9)), 3.0)


func _draw_corpse() -> void:
	draw_circle(Vector2.ZERO, 12.0, Color(0, 0, 0, 0.3))
	draw_rect(Rect2(-10, -6, 20, 12), Color(0.3, 0.28, 0.26), true)
	draw_circle(Vector2(0, -10), 7.0, Color(0.66, 0.52, 0.42))
	draw_line(Vector2(-12, -4), Vector2(-16, 6), Color(0.55, 0.45, 0.35), 3.0)
	draw_line(Vector2(12, -4), Vector2(16, 6), Color(0.55, 0.45, 0.35), 3.0)
