class_name TouchStick
extends Control
## On-screen movement stick for touch devices.
##
## Handles screen-touch events only (project settings emulate touch from mouse,
## so desktop testing works through the same code path). Emits a normalized
## direction whose length is the stick displacement, which lets the player sprint
## by pushing the stick to its edge.
##
## Keyboard movement is read by the Player directly, so this control is optional
## at runtime rather than the only way to move.
##
## Named TouchStick rather than VirtualJoystick because Godot 4.7 ships a native
## VirtualJoystick node.

signal moved(direction: Vector2)
signal released()

@export_range(40.0, 300.0, 1.0) var radius: float = 108.0
@export_range(8.0, 120.0, 1.0) var knob_radius: float = 44.0
## When true the stick base jumps to wherever the player touches inside this
## control, which is far more forgiving on a phone than a fixed centre.
@export var dynamic_center: bool = true
@export var base_color: Color = Color(1.0, 1.0, 1.0, 0.10)
@export var rim_color: Color = Color(1.0, 1.0, 1.0, 0.22)
@export var knob_color: Color = Color(0.92, 0.9, 0.82, 0.35)

var _pointer_index: int = -1
var _center: Vector2 = Vector2.ZERO
var _knob: Vector2 = Vector2.ZERO
var _active: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center = size * 0.5
	_knob = _center


func is_active() -> bool:
	return _active


## Current stick direction, length 0..1.
func get_direction() -> Vector2:
	if not _active:
		return Vector2.ZERO
	return (_knob - _center) / maxf(1.0, radius)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not visible:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)


func _handle_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if _pointer_index >= 0 or not get_global_rect().has_point(touch.position):
			return
		_pointer_index = touch.index
		_center = size * 0.5
		if dynamic_center:
			_center = Vector2(
				clampf(touch.position.x - global_position.x, knob_radius, size.x - knob_radius),
				clampf(touch.position.y - global_position.y, knob_radius, size.y - knob_radius))
		_active = true
		_apply(touch.position)
		accept_event()
	elif touch.index == _pointer_index:
		_reset()


func _handle_drag(drag: InputEventScreenDrag) -> void:
	if drag.index != _pointer_index:
		return
	if get_tree().paused:
		return
	_apply(drag.position)
	accept_event()


func _apply(touch_position: Vector2) -> void:
	var local := touch_position - global_position
	var offset := local - _center
	if offset.length() > radius:
		offset = offset.normalized() * radius
	_knob = _center + offset
	queue_redraw()
	moved.emit(offset / maxf(1.0, radius))


func _reset() -> void:
	_pointer_index = -1
	_active = false
	_knob = size * 0.5
	_center = size * 0.5
	queue_redraw()
	released.emit()
	moved.emit(Vector2.ZERO)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_reset()


func _draw() -> void:
	draw_circle(_center, radius, base_color)
	draw_circle(_center, radius, rim_color, false, 3.0)
	var direction := _knob - _center
	if direction.length() > 0.1:
		draw_line(_center, _knob, rim_color, 3.0)
	draw_circle(_knob, knob_radius, knob_color)
	draw_circle(_knob, knob_radius, rim_color, false, 2.0)
