class_name Zombie
extends CharacterBody2D
## The standard zombie: the first PvE threat of the game.
##
## One reliable enemy type with a complete behaviour loop:
## IDLE -> WANDER -> CHASE -> ATTACK -> SEARCH -> RETURN -> IDLE, plus DEAD.
##
## Detection uses distance, line of sight and noise (GameEvents.noise_emitted),
## and its range grows at night. Navigation is deliberately simple steering with
## a wall-slide nudge: the prototype world has no nav mesh yet, and adding
## NavigationAgent2D before the map is large would be premature (Phase 6).

enum State { IDLE, WANDER, CHASE, ATTACK, SEARCH, RETURN, DEAD }

@export_group("Movement")
@export var wander_speed: float = 26.0
@export var chase_speed: float = 64.0
@export var acceleration: float = 480.0

@export_group("Perception")
@export var detection_radius: float = 230.0
@export var lose_target_radius: float = 430.0
@export var attack_range: float = 28.0

@export_group("Combat")
@export var attack_damage: float = 8.0
@export var attack_cooldown: float = 1.2
@export var max_health: float = 45.0
@export var loot_table_id: String = "zombie_standard"

@export_group("Behaviour timing")
@export var idle_duration: float = 2.5
@export var wander_duration: float = 4.5
@export var search_duration: float = 6.0
@export var leash_radius: float = 280.0

@onready var health: HealthComponent = $Health
@onready var attack_hitbox: Hitbox = $AttackHitbox
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var sight: RayCast2D = $Sight

var state: State = State.IDLE
## Spawn point the zombie returns to when it loses interest.
var home_position: Vector2 = Vector2.ZERO
var target: Node2D = null
var facing: Vector2 = Vector2.DOWN

var _state_time: float = 0.0
var _attack_timer: float = 0.0
var _wander_direction: Vector2 = Vector2.DOWN
var _last_known_position: Vector2 = Vector2.ZERO
var _hit_flash: float = 0.0
var _dead: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("enemy")
	_rng.randomize()
	if home_position == Vector2.ZERO:
		home_position = global_position
	health.max_health = max_health
	health.current_health = max_health
	health.damaged.connect(_on_damaged)
	health.died.connect(_on_died)
	GameEvents.noise_emitted.connect(_on_noise)
	_set_state(State.IDLE)


func is_dead() -> bool:
	return _dead


func get_state_name() -> String:
	return State.keys()[state]


# --- state machine ------------------------------------------------------------

func _set_state(new_state: State) -> void:
	if _dead:
		return
	state = new_state
	_state_time = 0.0
	match new_state:
		State.IDLE:
			_state_time = idle_duration
		State.WANDER:
			_wander_direction = Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU))
			_state_time = wander_duration
		State.CHASE:
			pass
		State.ATTACK:
			_attack_timer = 0.35
		State.SEARCH:
			_state_time = search_duration
		State.RETURN:
			pass
		State.DEAD:
			pass
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_state_time -= delta
	if _hit_flash > 0.0:
		_hit_flash -= delta
		queue_redraw()

	_try_acquire_target()

	match state:
		State.IDLE:
			_tick_idle(delta)
		State.WANDER:
			_tick_wander(delta)
		State.CHASE:
			_tick_chase(delta)
		State.ATTACK:
			_tick_attack(delta)
		State.SEARCH:
			_tick_search(delta)
		State.RETURN:
			_tick_return(delta)


func _tick_idle(delta: float) -> void:
	_decelerate(delta)
	if _state_time <= 0.0:
		_set_state(State.WANDER)


func _tick_wander(delta: float) -> void:
	_move_towards(global_position + _wander_direction, wander_speed, delta)
	if _state_time <= 0.0 or global_position.distance_to(home_position) > leash_radius:
		_set_state(State.IDLE)


func _tick_chase(delta: float) -> void:
	var destination := _last_known_position
	if target != null and is_instance_valid(target):
		_last_known_position = target.global_position
		destination = _last_known_position
		if global_position.distance_to(destination) <= attack_range:
			_set_state(State.ATTACK)
			return
		elif global_position.distance_to(destination) > lose_target_radius:
			_set_state(State.SEARCH)
			return
	_move_towards(destination, chase_speed, delta)


func _tick_attack(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_set_state(State.SEARCH)
		return
	var distance := global_position.distance_to(target.global_position)
	if distance > attack_range * 1.6:
		_set_state(State.CHASE)
		return
	_decelerate(delta * 2.0)
	facing = (target.global_position - global_position).normalized()
	if _attack_timer <= 0.0:
		_strike()


func _tick_search(delta: float) -> void:
	# Walk to where the target was last seen, then keep listening for a while.
	var distance := global_position.distance_to(_last_known_position)
	if distance > 24.0:
		_move_towards(_last_known_position, wander_speed * 2.2, delta)
	else:
		_decelerate(delta)
	if _state_time <= 0.0:
		_set_state(State.RETURN)


func _tick_return(delta: float) -> void:
	var distance := global_position.distance_to(home_position)
	if distance <= 20.0:
		_set_state(State.IDLE)
		return
	_move_towards(home_position, wander_speed * 1.6, delta)


func _strike() -> void:
	_attack_timer = attack_cooldown
	attack_hitbox.reach = attack_range * 0.6
	attack_hitbox.activate(facing, attack_damage)
	GameEvents.noise_emitted.emit(global_position, 150.0, self)
	queue_redraw()


# --- perception ---------------------------------------------------------------

func _try_acquire_target() -> void:
	if state == State.CHASE or state == State.ATTACK or state == State.DEAD:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not is_instance_valid(player):
		target = null
		return
	if not can_see(player):
		target = null
		return
	target = player
	_last_known_position = player.global_position
	_set_state(State.CHASE)


func get_detection_radius() -> float:
	var cycle := get_tree().get_first_node_in_group("day_night")
	if cycle != null and cycle.has_method("get_visibility_multiplier"):
		return detection_radius * float(cycle.get_visibility_multiplier())
	return detection_radius


func can_see(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if global_position.distance_to(node.global_position) > get_detection_radius():
		return false
	return has_line_of_sight(node.global_position)


func has_line_of_sight(point: Vector2) -> bool:
	if sight == null:
		return true
	sight.target_position = to_local(point)
	sight.force_raycast_update()
	return not sight.is_colliding()


## Sound detection: a loud enough event nearby makes the zombie investigate.
func _on_noise(noise_position: Vector2, radius: float, source: Node) -> void:
	if _dead or source == self:
		return
	if state == State.CHASE or state == State.ATTACK:
		return
	if global_position.distance_to(noise_position) > radius * 1.6:
		return
	_last_known_position = noise_position
	target = null
	_set_state(State.SEARCH)


func _on_damaged(info: DamageInfo) -> void:
	_hit_flash = 0.18
	if info != null and info.source is Node2D:
		# Being hit always gives away the attacker's position.
		target = info.source as Node2D
		_last_known_position = target.global_position
		if state != State.ATTACK:
			_set_state(State.CHASE)
	queue_redraw()


# --- movement -----------------------------------------------------------------

func _move_towards(destination: Vector2, speed: float, delta: float) -> void:
	var offset := destination - global_position
	if offset.length() < 6.0:
		_decelerate(delta)
		return
	facing = offset.normalized()
	velocity = velocity.move_toward(facing * speed, acceleration * delta)
	move_and_slide()
	# No nav mesh yet: slide along walls by pushing sideways when blocked.
	if is_on_wall():
		var normal := get_wall_normal()
		velocity += normal.rotated(PI * 0.5) * speed * 0.6
	queue_redraw()


func _decelerate(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
	move_and_slide()


# --- death --------------------------------------------------------------------

func _on_died(_info: DamageInfo) -> void:
	if _dead:
		return
	_dead = true
	state = State.DEAD
	velocity = Vector2.ZERO
	set_physics_process(false)
	attack_hitbox.deactivate()
	if hurtbox != null:
		hurtbox.set_deferred("monitorable", false)
	_spawn_loot()
	GameEvents.enemy_died.emit(self, global_position)
	queue_redraw()
	# Small delay so the death state is visible before the node disappears.
	await get_tree().create_timer(0.4).timeout
	queue_free()


func _spawn_loot() -> void:
	var table := ItemDatabase.get_loot_table(loot_table_id)
	if table == null:
		push_warning("[Zombie] Unknown loot table '%s'" % loot_table_id)
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null or not world.has_method("spawn_loot_bag_from_ingredients"):
		return
	var ingredients := table.roll_ingredients(_rng)
	if ingredients.is_empty():
		return
	world.spawn_loot_bag_from_ingredients(global_position, ingredients)


# --- placeholder visuals ------------------------------------------------------

func _draw() -> void:
	var body := Color(0.36, 0.44, 0.33)
	var skin := Color(0.55, 0.63, 0.48)
	if _hit_flash > 0.0:
		body = body.lerp(Color(0.95, 0.35, 0.3), 0.6)
	if _dead:
		body = body.darkened(0.45)
		skin = skin.darkened(0.4)

	draw_circle(Vector2(0, 10), 13.0, Color(0, 0, 0, 0.22))
	# Hunched torso and legs.
	draw_rect(Rect2(-9, -6, 18, 14), body, true)
	draw_rect(Rect2(-8, 6, 6, 9), body.darkened(0.15), true)
	draw_rect(Rect2(2, 6, 6, 9), body.darkened(0.15), true)
	# Head with a slack jaw and glowing eyes.
	draw_circle(Vector2(0, -13), 7.0, skin)
	draw_rect(Rect2(-4, -9, 8, 3), skin.darkened(0.35), true)
	if state == State.CHASE or state == State.ATTACK:
		draw_circle(Vector2(-2.6, -14), 1.5, Color(0.95, 0.35, 0.25))
		draw_circle(Vector2(2.6, -14), 1.5, Color(0.95, 0.35, 0.25))
	# Reaching arms toward the target.
	var reach := facing.normalized() * 11.0
	draw_line(Vector2(-7, -4), Vector2(-7, -4) + reach, skin.darkened(0.1), 3.5)
	draw_line(Vector2(7, -4), Vector2(7, -4) + reach, skin.darkened(0.1), 3.5)

	if health != null and not health.is_full():
		var ratio := health.get_ratio()
		draw_rect(Rect2(-12, -26, 24, 4), Color(0, 0, 0, 0.6), true)
		draw_rect(Rect2(-12, -26, 24 * ratio, 4), Color(0.8, 0.25, 0.2), true)
