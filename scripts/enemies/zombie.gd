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

## Visual variant controls the silhouette, colours, size and speed multiplier.
enum ZombieVariant { STANDARD, HEAVY, FAST, SPECIAL }

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

@export_group("Visual")
@export var visual_variant: ZombieVariant = ZombieVariant.STANDARD

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

## Visual colours derived from variant (refreshed on _draw).
var _body_color := Color(0.36, 0.44, 0.33)
var _skin_color := Color(0.55, 0.63, 0.48)
var _clothes_color := Color(0.30, 0.32, 0.28)
var _accent_color := Color(0.50, 0.15, 0.10)
var _body_scale := 1.0
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


# --- visuals ---------------------------------------------------------------

func _draw() -> void:
	_refresh_variant_colors()
	var body := _body_color
	var skin := _skin_color
	if _hit_flash > 0.0:
		body = body.lerp(Color(0.95, 0.35, 0.3), 0.65)
	if _dead:
		_draw_corpse(body.darkened(0.45), skin.darkened(0.4))
		return

	var s := _body_scale
	var dir := facing.normalized()

	# Shadow.
	_draw_circle(Vector2(0, 12 * s), 14.0 * s, Color(0, 0, 0, 0.22))

	match visual_variant:
		ZombieVariant.STANDARD:
			_draw_standard(body, skin, s, dir)
		ZombieVariant.HEAVY:
			_draw_heavy(body, skin, s, dir)
		ZombieVariant.FAST:
			_draw_fast(body, skin, s, dir)
		ZombieVariant.SPECIAL:
			_draw_special(body, skin, s, dir)

	# Health bar.
	if health != null and not health.is_full():
		var ratio := health.get_ratio()
		var bar_w := 24.0 * s
		_draw_rounded_rect(Rect2(-bar_w * 0.5, -28.0 * s, bar_w, 4.0), Color(0, 0, 0, 0.65), 1.0)
		_draw_rounded_rect(Rect2(-bar_w * 0.5, -28.0 * s, bar_w * ratio, 4.0), Color(0.8, 0.25, 0.2), 1.0)


## Standard infected survivor — common, hunched, shambling.
func _draw_standard(body: Color, skin: Color, s: float, dir: Vector2) -> void:
	# Legs (torn pants).
	_draw_rounded_rect(Rect2(-8 * s, 3 * s, 6 * s, 10 * s), body.darkened(0.15), 1.0)
	_draw_rounded_rect(Rect2(2 * s, 3 * s, 6 * s, 10 * s), body.darkened(0.15), 1.0)
	# Tattered shirt torso.
	_draw_rounded_rect(Rect2(-10 * s, -8 * s, 20 * s, 13 * s), _clothes_color, 2.0)
	# Tear on shirt.
	draw_line(Vector2(-4 * s, -2 * s), Vector2(2 * s, 4 * s), body.darkened(0.3), 1.0)
	# Arms (reaching forward, undead posture).
	var reach := dir * 12.0 * s
	_draw_rounded_rect(Rect2(-13 * s, -6 * s, 4 * s, 10 * s), skin.darkened(0.1), 1.0)
	_draw_rounded_rect(Rect2(9 * s, -6 * s, 4 * s, 10 * s), skin.darkened(0.1), 1.0)
	# Hands reaching.
	_draw_circle(Vector2(-11 * s, 4 * s) + dir * 3.0 * s, 3.0 * s, skin.darkened(0.15))
	_draw_circle(Vector2(11 * s, 4 * s) + dir * 3.0 * s, 3.0 * s, skin.darkened(0.15))
	# Head — bald with torn scalp.
	_draw_circle(Vector2(0, -14 * s), 8.0 * s, skin)
	_draw_circle(Vector2(0, -18 * s), 4.0 * s, skin.darkened(0.25))
	# Slack jaw.
	_draw_rounded_rect(Rect2(-3.5 * s, -10 * s, 7 * s, 4 * s), skin.darkened(0.35), 1.0)
	# Eyes glow when aggressive.
	if state == State.CHASE or state == State.ATTACK:
		_draw_circle(Vector2(-3 * s, -15 * s), 2.0 * s, Color(0.95, 0.35, 0.25))
		_draw_circle(Vector2(3 * s, -15 * s), 2.0 * s, Color(0.95, 0.35, 0.25))
	else:
		_draw_circle(Vector2(-3 * s, -15 * s), 1.5 * s, Color(0.6, 0.25, 0.2))
		_draw_circle(Vector2(3 * s, -15 * s), 1.5 * s, Color(0.6, 0.25, 0.2))


## Heavy / brute — wider, slower, bulkier silhouette, different clothing.
func _draw_heavy(body: Color, skin: Color, s: float, dir: Vector2) -> void:
	var hs := s * 1.25  # wider body.
	# Thick legs.
	_draw_rounded_rect(Rect2(-10 * hs, 2 * hs, 8 * hs, 12 * hs), body.darkened(0.2), 1.5)
	_draw_rounded_rect(Rect2(2 * hs, 2 * hs, 8 * hs, 12 * hs), body.darkened(0.2), 1.5)
	# Industrial vest / overalls.
	_draw_rounded_rect(Rect2(-13 * hs, -10 * hs, 26 * hs, 14 * hs), Color(0.28, 0.26, 0.24), 2.0)
	# Reflective stripe.
	draw_line(Vector2(-13 * hs, -4 * hs), Vector2(13 * hs, -4 * hs), Color(0.65, 0.55, 0.15), 2.0)
	# Massive arms.
	_draw_rounded_rect(Rect2(-17 * hs, -7 * hs, 5 * hs, 12 * hs), skin.darkened(0.05), 1.5)
	_draw_rounded_rect(Rect2(12 * hs, -7 * hs, 5 * hs, 12 * hs), skin.darkened(0.05), 1.5)
	# Big fists.
	_draw_circle(Vector2(-14.5 * hs, 5 * hs) + dir * 4.0 * hs, 4.5 * hs, skin.darkened(0.1))
	_draw_circle(Vector2(14.5 * hs, 5 * hs) + dir * 4.0 * hs, 4.5 * hs, skin.darkened(0.1))
	# Head — shaved, thick neck.
	_draw_circle(Vector2(0, -15 * hs), 9.0 * hs, skin)
	# Safety helmet remnant.
	_draw_rounded_rect(Rect2(-9 * hs, -22 * hs, 18 * hs, 5 * hs), Color(0.55, 0.50, 0.15), 2.0)
	# Eyes.
	if state == State.CHASE or state == State.ATTACK:
		_draw_circle(Vector2(-3.5 * hs, -16 * hs), 2.5 * hs, Color(0.95, 0.30, 0.20))
		_draw_circle(Vector2(3.5 * hs, -16 * hs), 2.5 * hs, Color(0.95, 0.30, 0.20))
	else:
		_draw_circle(Vector2(-3.5 * hs, -16 * hs), 1.8 * hs, Color(0.55, 0.20, 0.15))
		_draw_circle(Vector2(3.5 * hs, -16 * hs), 1.8 * hs, Color(0.55, 0.20, 0.15))


## Fast / runner — lean, thin, long limbs, ragged clothes.
func _draw_fast(body: Color, skin: Color, s: float, dir: Vector2) -> void:
	var fs := s * 0.9
	# Thin legs.
	_draw_rounded_rect(Rect2(-6 * fs, 2 * fs, 4 * fs, 12 * fs), body.darkened(0.1), 1.0)
	_draw_rounded_rect(Rect2(2 * fs, 2 * fs, 4 * fs, 12 * fs), body.darkened(0.1), 1.0)
	# Skinny torso — tattered hoodie.
	var hoodie := Color(0.35, 0.18, 0.15)
	_draw_rounded_rect(Rect2(-8 * fs, -9 * fs, 16 * fs, 12 * fs), hoodie, 1.5)
	# Hoodie strings.
	draw_line(Vector2(-2 * fs, -9 * fs), Vector2(-2 * fs, -4 * fs), Color(0.6, 0.55, 0.5), 1.0)
	draw_line(Vector2(2 * fs, -9 * fs), Vector2(2 * fs, -4 * fs), Color(0.6, 0.55, 0.5), 1.0)
	# Long reaching arms.
	var reach := dir * 14.0 * fs
	_draw_rounded_rect(Rect2(-12 * fs, -7 * fs, 3.5 * fs, 11 * fs), skin.darkened(0.15), 1.0)
	_draw_rounded_rect(Rect2(8.5 * fs, -7 * fs, 3.5 * fs, 11 * fs), skin.darkened(0.15), 1.0)
	_draw_circle(Vector2(-10.25 * fs, 4 * fs) + dir * 4.0 * fs, 2.5 * fs, skin.darkened(0.15))
	_draw_circle(Vector2(10.25 * fs, 4 * fs) + dir * 4.0 * fs, 2.5 * fs, skin.darkened(0.15))
	# Head — gaunt, sunken.
	_draw_circle(Vector2(0, -14 * fs), 6.5 * fs, skin)
	# Hollow cheeks.
	_draw_circle(Vector2(-3 * fs, -13 * fs), 2.0 * fs, skin.darkened(0.3))
	_draw_circle(Vector2(3 * fs, -13 * fs), 2.0 * fs, skin.darkened(0.3))
	# Eyes.
	if state == State.CHASE or state == State.ATTACK:
		_draw_circle(Vector2(-2.5 * fs, -15 * fs), 1.8 * fs, Color(0.95, 0.40, 0.20))
		_draw_circle(Vector2(2.5 * fs, -15 * fs), 1.8 * fs, Color(0.95, 0.40, 0.20))
	else:
		_draw_circle(Vector2(-2.5 * fs, -15 * fs), 1.2 * fs, Color(0.50, 0.22, 0.15))
		_draw_circle(Vector2(2.5 * fs, -15 * fs), 1.2 * fs, Color(0.50, 0.22, 0.15))


## Special / infected — biohazard appearance, glowing veins, bloated.
func _draw_special(body: Color, skin: Color, s: float, dir: Vector2) -> void:
	var ss := s * 1.1
	# Bloated legs.
	_draw_rounded_rect(Rect2(-9 * ss, 2 * ss, 7 * ss, 11 * ss), body.darkened(0.05), 1.5)
	_draw_rounded_rect(Rect2(2 * ss, 2 * ss, 7 * ss, 11 * ss), body.darkened(0.05), 1.5)
	# Bloated torso — hospital gown remnant.
	var gown := Color(0.25, 0.35, 0.38)
	_draw_rounded_rect(Rect2(-12 * ss, -10 * ss, 24 * ss, 14 * ss), gown, 2.0)
	# Biohazard veins (glowing lines across torso).
	_draw_circle(Vector2(-5 * ss, -4 * ss), 1.5 * ss, Color(0.2, 0.8, 0.3, 0.7))
	_draw_circle(Vector2(3 * ss, -2 * ss), 1.5 * ss, Color(0.2, 0.8, 0.3, 0.7))
	_draw_circle(Vector2(-1 * ss, 1 * ss), 1.5 * ss, Color(0.2, 0.8, 0.3, 0.7))
	draw_line(Vector2(-5 * ss, -4 * ss), Vector2(3 * ss, -2 * ss), Color(0.2, 0.7, 0.3, 0.5), 1.0)
	draw_line(Vector2(3 * ss, -2 * ss), Vector2(-1 * ss, 1 * ss), Color(0.2, 0.7, 0.3, 0.5), 1.0)
	# Arms.
	_draw_rounded_rect(Rect2(-15 * ss, -7 * ss, 4 * ss, 11 * ss), skin.darkened(0.1), 1.0)
	_draw_rounded_rect(Rect2(11 * ss, -7 * ss, 4 * ss, 11 * ss), skin.darkened(0.1), 1.0)
	_draw_circle(Vector2(-13 * ss, 4 * ss) + dir * 3.0 * ss, 3.5 * ss, skin.darkened(0.15))
	_draw_circle(Vector2(13 * ss, 4 * ss) + dir * 3.0 * ss, 3.5 * ss, skin.darkened(0.15))
	# Head — swollen, exposed skull.
	_draw_circle(Vector2(0, -15 * ss), 8.5 * ss, skin)
	# Exposed skull patch.
	_draw_circle(Vector2(0, -20 * ss), 4.0 * ss, skin.darkened(0.4))
	# Eyes — green glow.
	if state == State.CHASE or state == State.ATTACK:
		_draw_circle(Vector2(-3 * ss, -16 * ss), 2.2 * ss, Color(0.3, 0.95, 0.3))
		_draw_circle(Vector2(3 * ss, -16 * ss), 2.2 * ss, Color(0.3, 0.95, 0.3))
	else:
		_draw_circle(Vector2(-3 * ss, -16 * ss), 1.5 * ss, Color(0.2, 0.5, 0.2))
		_draw_circle(Vector2(3 * ss, -16 * ss), 1.5 * ss, Color(0.2, 0.5, 0.2))


func _draw_corpse(body: Color, skin: Color) -> void:
	var dir := facing.normalized()
	_draw_circle(Vector2(2, 4), 14.0, Color(0, 0, 0, 0.25))
	_draw_rounded_rect(Rect2(-10, -5, 20, 10), body, 2.0)
	_draw_circle(Vector2(-8, -6), 6.5, skin)
	draw_line(Vector2(-10, -2), Vector2(-18, -8), skin.darkened(0.1), 2.5)
	draw_line(Vector2(8, -1), Vector2(16, 8), skin.darkened(0.1), 2.5)
	draw_line(Vector2(-3, 5), Vector2(-8, 14), body.darkened(0.3), 3.0)
	draw_line(Vector2(3, 5), Vector2(8, 14), body.darkened(0.3), 3.0)
	_draw_circle(Vector2(0, 8), 7.0, Color(0.4, 0.08, 0.06, 0.45))


func _refresh_variant_colors() -> void:
	match visual_variant:
		ZombieVariant.STANDARD:
			_body_color = Color(0.36, 0.44, 0.33)
			_skin_color = Color(0.55, 0.63, 0.48)
			_clothes_color = Color(0.30, 0.32, 0.28)
			_body_scale = 1.0
		ZombieVariant.HEAVY:
			_body_color = Color(0.32, 0.30, 0.28)
			_skin_color = Color(0.50, 0.45, 0.40)
			_clothes_color = Color(0.25, 0.24, 0.22)
			_body_scale = 1.3
		ZombieVariant.FAST:
			_body_color = Color(0.40, 0.38, 0.35)
			_skin_color = Color(0.60, 0.55, 0.50)
			_clothes_color = Color(0.35, 0.18, 0.15)
			_body_scale = 0.85
		ZombieVariant.SPECIAL:
			_body_color = Color(0.30, 0.38, 0.30)
			_skin_color = Color(0.50, 0.55, 0.45)
			_clothes_color = Color(0.25, 0.35, 0.38)
			_body_scale = 1.15


# --- tiny drawing helpers --------------------------------------------------

func _draw_circle(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius, color)


func _draw_rounded_rect(rect: Rect2, color: Color, radius: float) -> void:
	draw_rect(rect, color, true)
	_draw_circle(Vector2(rect.position.x + radius, rect.position.y + radius), radius, color)
	_draw_circle(Vector2(rect.end.x - radius, rect.position.y + radius), radius, color)
	_draw_circle(Vector2(rect.position.x + radius, rect.end.y - radius), radius, color)
	_draw_circle(Vector2(rect.end.x - radius, rect.end.y - radius), radius, color)
