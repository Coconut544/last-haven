class_name Hurtbox
extends Area2D
## Damage receiver for a character or structure.
##
## Lives on a dedicated physics layer (see PhysicsLayers) so an attacker's
## Hitbox can be masked to exactly the targets it should be able to hit.

## Health to route damage into. Leave empty to search the parent on ready.
@export var health_path: NodePath

var _health: HealthComponent


func _ready() -> void:
	# A hurtbox only needs to be detectable; it never scans for overlaps.
	monitoring = false
	monitorable = true
	_health = _resolve_health()


func _resolve_health() -> HealthComponent:
	if not health_path.is_empty():
		var node := get_node_or_null(health_path)
		if node is HealthComponent:
			return node
	var parent := get_parent()
	if parent != null:
		for child in parent.get_children():
			if child is HealthComponent:
				return child
	push_warning("[Hurtbox] %s has no HealthComponent to route damage into" % get_path())
	return null


func get_health() -> HealthComponent:
	if _health == null:
		_health = _resolve_health()
	return _health


## Returns the damage actually applied.
func receive_damage(info: DamageInfo) -> float:
	var health := get_health()
	if health == null:
		return 0.0
	return health.apply_damage(info)


func is_alive() -> bool:
	var health := get_health()
	return health != null and health.is_alive()
