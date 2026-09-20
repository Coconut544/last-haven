class_name DayNightCycle
extends Node2D
## Very small day/night cycle: one CanvasModulate colour tint driven by a
## normalized time of day.
##
## Phase 1 scope: lighting, HUD clock and a hook enemies use to see further at
## night. Nothing here needs to change for the world to get bigger later.

signal hour_changed(hour: int, day: int)

## Real seconds for one in-game day.
@export_range(30.0, 3600.0, 1.0) var day_length_seconds: float = 480.0
## 0.0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = sunset.
@export_range(0.0, 1.0, 0.001) var time_of_day: float = 0.30
@export var day: int = 1
@export var paused: bool = false
## Multiplier applied to enemy detection range at night.
@export_range(1.0, 3.0, 0.05) var night_detection_multiplier: float = 1.5
@export var night_start_hour: float = 20.0
@export var day_start_hour: float = 6.0

## Key tints. Night is genuinely dark but still readable on a phone screen.
const TINT_NIGHT := Color(0.30, 0.34, 0.52)
const TINT_DAWN := Color(0.85, 0.72, 0.62)
const TINT_DAY := Color(1.0, 1.0, 1.0)
const TINT_DUSK := Color(0.78, 0.62, 0.55)

var _modulate: CanvasModulate
var _last_hour: int = -1


func _ready() -> void:
	add_to_group("day_night")
	_modulate = CanvasModulate.new()
	_modulate.name = "WorldTint"
	add_child(_modulate)
	_update_lighting()


func _process(delta: float) -> void:
	if paused:
		return
	advance(delta / maxf(1.0, day_length_seconds))


## Moves time forward by a normalized fraction of a day.
func advance(fraction: float) -> void:
	if fraction <= 0.0:
		return
	time_of_day += fraction
	while time_of_day >= 1.0:
		time_of_day -= 1.0
		day += 1
	_update_lighting()
	var hour := get_hour()
	if hour != _last_hour:
		_last_hour = hour
		hour_changed.emit(hour, day)
		GameEvents.time_changed.emit(time_of_day, day)


func get_hour() -> int:
	return int(floor(time_of_day * 24.0)) % 24


func get_clock_string() -> String:
	var total_minutes := int(time_of_day * 24.0 * 60.0)
	return "%02d:%02d" % [total_minutes / 60, total_minutes % 60]


func is_night() -> bool:
	var hour := float(get_hour()) + (time_of_day * 24.0 - float(get_hour()))
	return hour >= night_start_hour or hour < day_start_hour


## Detection range multiplier enemies should apply right now.
func get_visibility_multiplier() -> float:
	return night_detection_multiplier if is_night() else 1.0


func get_current_tint() -> Color:
	return _modulate.color if _modulate != null else TINT_DAY


func set_time_of_day(value: float, new_day: int = -1) -> void:
	time_of_day = fposmod(value, 1.0)
	if new_day > 0:
		day = new_day
	_update_lighting()


func _update_lighting() -> void:
	if _modulate == null:
		return
	_modulate.color = _sample_tint(time_of_day)


func _sample_tint(time: float) -> Color:
	# Piecewise blend through the four key tints; cheap and readable.
	if time < 0.20:
		return TINT_NIGHT.lerp(TINT_NIGHT, 0.0)
	if time < 0.30:
		return TINT_NIGHT.lerp(TINT_DAWN, (time - 0.20) / 0.10)
	if time < 0.40:
		return TINT_DAWN.lerp(TINT_DAY, (time - 0.30) / 0.10)
	if time < 0.70:
		return TINT_DAY
	if time < 0.80:
		return TINT_DAY.lerp(TINT_DUSK, (time - 0.70) / 0.10)
	if time < 0.90:
		return TINT_DUSK.lerp(TINT_NIGHT, (time - 0.80) / 0.10)
	return TINT_NIGHT


func serialize_state() -> Dictionary:
	return {"time_of_day": time_of_day, "day": day, "day_length_seconds": day_length_seconds}


func apply_state(state: Dictionary) -> void:
	set_time_of_day(float(state.get("time_of_day", time_of_day)), int(state.get("day", day)))


func reset() -> void:
	time_of_day = 0.30
	day = 1
	_update_lighting()
