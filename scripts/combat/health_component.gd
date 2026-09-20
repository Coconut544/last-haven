class_name HealthComponent
extends Node
## Health for anything that can be damaged (player, enemy, structure).
##
## Owns the value, emits the events, and nothing else. Combat code never writes
## to `current_health` directly; it goes through apply_damage() so every damage
## event is observable in one place.

signal health_changed(current: float, maximum: float)
signal damaged(info: DamageInfo)
signal died(info: DamageInfo)
signal healed(amount: float)

@export_range(1.0, 10000.0, 1.0) var max_health: float = 100.0
## When true the component ignores damage (used for debug / safe zones).
@export var invulnerable: bool = false
## When true the owning node is removed automatically on death.
@export var free_owner_on_death: bool = false

var current_health: float = 100.0


func _ready() -> void:
	current_health = max_health


## Sets health without emitting `damaged`/`died` - used by save loading.
func set_health(value: float) -> void:
	current_health = clampf(value, 0.0, max_health)
	health_changed.emit(current_health, max_health)


func set_max_health(value: float, keep_ratio: bool = true) -> void:
	var ratio := get_ratio() if max_health > 0.0 else 1.0
	max_health = maxf(1.0, value)
	current_health = current_health * ratio if keep_ratio else max_health
	current_health = clampf(current_health, 0.0, max_health)
	health_changed.emit(current_health, max_health)


## Applies damage and returns the amount actually removed.
func apply_damage(info: DamageInfo) -> float:
	if invulnerable or info == null or not is_alive():
		return 0.0
	var applied := minf(info.amount, current_health)
	if applied <= 0.0:
		return 0.0
	current_health -= applied
	info.amount = applied
	damaged.emit(info)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		died.emit(info)
		if free_owner_on_death:
			var target := owner if owner != null else get_parent()
			if target != null:
				target.queue_free()
	return applied


func heal(amount: float) -> float:
	if amount <= 0.0 or not is_alive():
		return 0.0
	var before := current_health
	current_health = minf(max_health, current_health + amount)
	var restored := current_health - before
	if restored > 0.0:
		healed.emit(restored)
		health_changed.emit(current_health, max_health)
	return restored


func kill() -> void:
	apply_damage(DamageInfo.create(current_health, null, DamageInfo.Type.ENVIRONMENT))


func is_alive() -> bool:
	return current_health > 0.0


func is_full() -> bool:
	return is_equal_approx(current_health, max_health)


func get_ratio() -> float:
	if max_health <= 0.0:
		return 0.0
	return clampf(current_health / max_health, 0.0, 1.0)


func restore_full() -> void:
	set_health(max_health)
