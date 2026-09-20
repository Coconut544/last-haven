class_name DamageNumber
extends Node2D
## Floating damage number that rises, fades, and frees itself.
##
## Spawned by combat systems to give the player visual feedback on hits.
## Numbers are color-coded: white for normal, yellow for crits, green for heals.

var value: float = 0.0
var is_heal: bool = false
var _velocity: Vector2 = Vector2.ZERO
var _lifetime: float = 0.0
var _max_lifetime: float = 0.85
var _alpha: float = 1.0
var _scale_target: float = 1.0

const CRIT_THRESHOLD := 15.0


func setup(damage: float, heal: bool = false) -> void:
	value = damage
	is_heal = heal
	# Drift upward and slightly random sideways.
	_velocity = Vector2(randf_range(-18.0, 18.0), -65.0)
	_lifetime = 0.0
	_scale_target = 1.0
	# Big hits pop more.
	if absf(damage) >= CRIT_THRESHOLD:
		_scale_target = 1.4
	queue_redraw()


func _process(delta: float) -> void:
	_lifetime += delta
	# Rise and decelerate.
	_velocity.y += 80.0 * delta  # gentle gravity pull.
	position += _velocity * delta
	# Fade out in the last third.
	var fade_start := _max_lifetime * 0.55
	if _lifetime > fade_start:
		_alpha = clampf(1.0 - (_lifetime - fade_start) / (_max_lifetime - fade_start), 0.0, 1.0)
	modulate.a = _alpha
	if _lifetime >= _max_lifetime:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var text := "%d" % roundi(value)
	var color := Color(0.95, 0.93, 0.85)
	if is_heal:
		color = Color(0.3, 0.85, 0.35)
	elif absf(value) >= CRIT_THRESHOLD:
		color = Color(1.0, 0.85, 0.25)
	# Outline for readability.
	var outline_color := Color(0, 0, 0, _alpha * 0.7)
	var font_size := 16
	if _scale_target > 1.2:
		font_size = 20
	for offset: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		draw_string(font, offset, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, outline_color)
	draw_string(font, Vector2.ZERO, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)
