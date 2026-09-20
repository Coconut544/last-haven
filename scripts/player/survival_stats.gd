class_name SurvivalStats
extends Node
## Hunger, thirst and stamina for the player.
##
## Kept separate from HealthComponent because health is shared with enemies and
## structures while these three are player-only concerns. Health damage from
## starvation and dehydration is applied through the HealthComponent so there is
## still exactly one way to lose health.

signal stat_changed(stat_id: String, value: float, maximum: float)
signal depleted(stat_id: String)

@export var max_hunger: float = 100.0
@export var max_thirst: float = 100.0
@export var max_stamina: float = 100.0

@export_group("Drain / regen per second")
## ~14 minutes from full to empty: long enough to explore, short enough to matter.
@export_range(0.0, 5.0, 0.005) var hunger_drain: float = 0.12
## Dehydration is the faster clock, as it should be.
@export_range(0.0, 5.0, 0.005) var thirst_drain: float = 0.18
@export_range(0.0, 100.0, 0.5) var stamina_drain: float = 12.0
@export_range(0.0, 100.0, 0.5) var stamina_regen: float = 9.0
## Delay after sprinting before stamina starts regenerating.
@export_range(0.0, 10.0, 0.1) var stamina_regen_delay: float = 0.8

@export_group("Depletion damage")
@export_range(0.0, 20.0, 0.1) var starvation_damage: float = 1.2
@export_range(0.0, 20.0, 0.1) var dehydration_damage: float = 1.8
## Stamina floor required to start sprinting.
@export_range(0.0, 100.0, 1.0) var sprint_minimum_stamina: float = 5.0

@export_group("UI")
## How often stat changes are pushed to the UI (seconds).
@export_range(0.05, 2.0, 0.05) var ui_update_interval: float = 0.2

var hunger: float = 100.0
var thirst: float = 100.0
var stamina: float = 100.0
## Total time survived this life, saved with the player.
var survival_seconds: float = 0.0

var _health: HealthComponent
var _ui_timer: float = 0.0
var _stamina_delay_left: float = 0.0


func _ready() -> void:
	hunger = max_hunger
	thirst = max_thirst
	stamina = max_stamina


## Wires the component to the health it damages. Called by Player on ready.
func setup(health: HealthComponent) -> void:
	_health = health


func _process(delta: float) -> void:
	if _health == null or not _health.is_alive():
		return
	survival_seconds += delta

	if hunger > 0.0:
		hunger = maxf(0.0, hunger - hunger_drain * delta)
		if hunger <= 0.0:
			depleted.emit("hunger")
	if thirst > 0.0:
		thirst = maxf(0.0, thirst - thirst_drain * delta)
		if thirst <= 0.0:
			depleted.emit("thirst")

	if hunger <= 0.0:
		_health.apply_damage(DamageInfo.create(
				starvation_damage * delta, null, DamageInfo.Type.STARVATION, get_owner_center()))
	if thirst <= 0.0:
		_health.apply_damage(DamageInfo.create(
				dehydration_damage * delta, null, DamageInfo.Type.DEHYDRATION, get_owner_center()))

	_tick_stamina(delta)
	_tick_ui(delta)


func _tick_stamina(delta: float) -> void:
	if _stamina_delay_left > 0.0:
		_stamina_delay_left -= delta
		return
	if stamina < max_stamina:
		stamina = minf(max_stamina, stamina + stamina_regen * delta)


func _tick_ui(delta: float) -> void:
	_ui_timer -= delta
	if _ui_timer <= 0.0:
		_ui_timer = ui_update_interval
		emit_all()


func emit_all() -> void:
	stat_changed.emit("hunger", hunger, max_hunger)
	stat_changed.emit("thirst", thirst, max_thirst)
	stat_changed.emit("stamina", stamina, max_stamina)


# --- sprinting ----------------------------------------------------------------

func can_sprint() -> bool:
	return stamina > sprint_minimum_stamina


## Consumes stamina while sprinting. Returns false when too tired to sprint.
func drain_stamina(amount: float) -> bool:
	if amount <= 0.0:
		return can_sprint()
	_stamina_delay_left = stamina_regen_delay
	stamina = maxf(0.0, stamina - amount)
	if stamina <= 0.0:
		depleted.emit("stamina")
		return false
	return true


# --- consuming -----------------------------------------------------------------

## Applies a consumable item. Returns true when anything was restored.
func consume(definition: ItemDefinition) -> bool:
	if definition == null or not definition.is_consumable():
		return false
	var restored := false
	if definition.health_restore > 0.0 and _health != null:
		restored = _health.heal(definition.health_restore) > 0.0 or restored
	if definition.food_restore > 0.0:
		var before := hunger
		hunger = minf(max_hunger, hunger + definition.food_restore)
		restored = restored or hunger > before
	if definition.water_restore > 0.0:
		var before_thirst := thirst
		thirst = minf(max_thirst, thirst + definition.water_restore)
		restored = restored or thirst > before_thirst
	if restored:
		emit_all()
	return restored


# --- helpers -------------------------------------------------------------------

func get_ratio(stat_id: String) -> float:
	match stat_id:
		"hunger":
			return hunger / maxf(1.0, max_hunger)
		"thirst":
			return thirst / maxf(1.0, max_thirst)
		"stamina":
			return stamina / maxf(1.0, max_stamina)
	return 0.0


func get_value(stat_id: String) -> float:
	match stat_id:
		"hunger":
			return hunger
		"thirst":
			return thirst
		"stamina":
			return stamina
	return 0.0


func restore_full() -> void:
	hunger = max_hunger
	thirst = max_thirst
	stamina = max_stamina
	emit_all()


func reset() -> void:
	restore_full()
	survival_seconds = 0.0


func get_owner_center() -> Vector2:
	var parent_node := get_parent() as Node2D
	return parent_node.global_position if parent_node != null else Vector2.ZERO


# --- persistence --------------------------------------------------------------

func serialize_state() -> Dictionary:
	return {
		"hunger": hunger,
		"thirst": thirst,
		"stamina": stamina,
		"survival_seconds": survival_seconds,
	}


func apply_state(state: Dictionary) -> void:
	hunger = clampf(float(state.get("hunger", hunger)), 0.0, max_hunger)
	thirst = clampf(float(state.get("thirst", thirst)), 0.0, max_thirst)
	stamina = clampf(float(state.get("stamina", stamina)), 0.0, max_stamina)
	survival_seconds = float(state.get("survival_seconds", survival_seconds))
	emit_all()
