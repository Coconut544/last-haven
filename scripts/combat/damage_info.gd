class_name DamageInfo
extends RefCounted
## Everything a damage event needs to be applied and explained.
##
## Passed by value to HealthComponent.apply_damage() so the receiving entity can
## react (knockback, death drops, future aggro) without knowing the attacker.

enum Type { MELEE, RANGED, ENVIRONMENT, STARVATION, DEHYDRATION, FALL }

var amount: float = 0.0
var type: Type = Type.MELEE
## Node that caused the damage. May be null (environment, starvation).
var source: Node = null
var knockback: Vector2 = Vector2.ZERO
## World position of the hit, used for effects and sound.
var position: Vector2 = Vector2.ZERO


static func create(
		damage: float,
		attacker: Node = null,
		damage_type: Type = Type.MELEE,
		hit_position: Vector2 = Vector2.ZERO,
		knockback_force: Vector2 = Vector2.ZERO
) -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = maxf(0.0, damage)
	info.source = attacker
	info.type = damage_type
	info.position = hit_position
	info.knockback = knockback_force
	return info


func _to_string() -> String:
	return "DamageInfo(%.1f, %s, source=%s)" % [
		amount, Type.keys()[type], source.name if source != null else "none"]
