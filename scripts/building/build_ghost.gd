class_name BuildGhost
extends Node2D
## Placement preview for the build system.
##
## Draws the footprint of the pending structure, green when the spot is valid and
## red when it is not, so players know before confirming.

var definition: BuildableDefinition
var valid: bool = true

const COLOR_VALID := Color(0.42, 0.95, 0.5, 0.45)
const COLOR_INVALID := Color(0.98, 0.38, 0.34, 0.45)


func setup(buildable: BuildableDefinition) -> void:
	definition = buildable
	queue_redraw()


func set_valid(is_valid: bool) -> void:
	if valid == is_valid:
		return
	valid = is_valid
	queue_redraw()


func _draw() -> void:
	if definition == null:
		return
	var color := COLOR_VALID if valid else COLOR_INVALID
	var half := definition.collision_size * 0.5
	var rect := Rect2(-half, definition.collision_size)
	draw_rect(rect, color, true)
	draw_rect(rect, color.lightened(0.35), false, 2.0)
	# Occupancy cells so grid snapping is visible.
	var cell := float(BuildSystem.GRID_SIZE)
	for x in definition.occupancy.x:
		for y in definition.occupancy.y:
			var offset := Vector2(
				(float(x) - float(definition.occupancy.x) * 0.5 + 0.5) * cell,
				(float(y) - float(definition.occupancy.y) * 0.5 + 0.5) * cell)
			draw_rect(Rect2(offset - Vector2(cell, cell) * 0.5, Vector2(cell, cell)),
					color.lightened(0.5), false, 1.0)
