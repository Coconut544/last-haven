class_name Hitbox
extends Area2D
## Damage dealer for melee attacks (player swings, zombie claws).
##
## Damage is resolved with an explicit shape query during the active window
## instead of relying on area_entered signals. That keeps hit timing
## deterministic for one swing (each target is hit at most once) and avoids
## missed hits when the attacker and target are already overlapping.

signal hit_landed(hurtbox: Hurtbox, damage: float)

## Base damage when no weapon damage is supplied per swing.
@export_range(0.0, 500.0, 0.5) var damage: float = 8.0
## Physics layer(s) this hitbox may damage.
@export_flags_2d_physics var damage_mask: int = PhysicsLayers.HURTBOX_ENEMY
## Distance in front of the attacker where the swing connects.
@export_range(4.0, 120.0, 1.0) var reach: float = 26.0
## How long the swing stays active.
@export_range(0.05, 2.0, 0.01) var active_time: float = 0.18
@export_range(0.0, 800.0, 5.0) var knockback_force: float = 140.0

var _active: bool = false
var _time_left: float = 0.0
var _hit_this_swing: Array[Hurtbox] = []
var _attacker: Node2D


func _ready() -> void:
	monitoring = false
	monitorable = false
	set_physics_process(false)
	_attacker = get_parent() as Node2D


func is_active() -> bool:
	return _active


## Starts a swing in `direction`. `damage_override` >= 0 replaces the base damage.
func activate(direction: Vector2, damage_override: float = -1.0) -> void:
	var facing := direction.normalized()
	if facing == Vector2.ZERO:
		facing = Vector2.RIGHT
	rotation = facing.angle()
	position = facing * reach
	damage = damage_override if damage_override >= 0.0 else damage
	_active = true
	_time_left = active_time
	_hit_this_swing.clear()
	set_physics_process(true)


func deactivate() -> void:
	_active = false
	_time_left = 0.0
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_time_left -= delta
	_apply_hits()
	if _time_left <= 0.0:
		deactivate()


func _apply_hits() -> void:
	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return
	var shape := _get_query_shape()
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = damage_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.exclude = []
	for result in space_state.intersect_shape(query, 8):
		var collider = result.get("collider")
		if not (collider is Hurtbox):
			continue
		var hurtbox := collider as Hurtbox
		if _hit_this_swing.has(hurtbox) or not hurtbox.is_alive():
			continue
		_hit_this_swing.append(hurtbox)
		var knockback := Vector2.RIGHT.rotated(rotation) * knockback_force
		var info := DamageInfo.create(damage, _attacker, DamageInfo.Type.MELEE, global_position, knockback)
		var applied := hurtbox.receive_damage(info)
		if applied > 0.0:
			hit_landed.emit(hurtbox, applied)


func _get_query_shape() -> Shape2D:
	if shape_owner_get_shape_count(0) > 0:
		return shape_owner_get_shape(0, 0)
	var fallback := CircleShape2D.new()
	fallback.radius = 18.0
	return fallback
