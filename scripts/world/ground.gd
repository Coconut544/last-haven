class_name WorldGround
extends Node2D
## Paints the world ground: region tints, texture patches, survey grid and labels.
##
## Split out of GameWorld so world logic stays about state. When real terrain art
## arrives (Phase 6) only this node changes; nothing else knows how the ground is
## drawn.

@export var show_grid: bool = true
@export var show_region_names: bool = true
@export_range(32.0, 512.0, 8.0) var grid_step: float = 128.0
## Patches per region, used to break up the flat colour.
@export_range(0, 200, 1) var patches_per_region: int = 26

var _drawn_seed: int = 0
var _region_labels: Array[Dictionary] = []


func _ready() -> void:
	z_index = -10
	refresh()


## Rebuilds cached label data and redraws. Called by GameWorld after generation.
func refresh() -> void:
	var world := get_parent() as GameWorld
	_drawn_seed = world.get_world_seed() if world != null else 0
	_region_labels.clear()
	if show_region_names:
		for region: Dictionary in WorldRegions.get_region_definitions():
			var rect: Rect2 = region["rect"]
			_region_labels.append({"text": str(region["name"]), "position": rect.get_center()})
	queue_redraw()


func _draw() -> void:
	var half := WorldRegions.WORLD_HALF_SIZE
	var size := WorldRegions.get_world_size()

	# Base ground, then the per region tint on top of it.
	draw_rect(Rect2(-half, -half, size, size), Color(0.08, 0.09, 0.08), true)
	for region: Dictionary in WorldRegions.get_region_definitions():
		draw_rect(region["rect"], region["ground"], true)

	# Deterministic patches: same seed, same ground, every time.
	var patch_rng := RandomNumberGenerator.new()
	patch_rng.seed = _drawn_seed + 17
	for region: Dictionary in WorldRegions.get_region_definitions():
		var rect: Rect2 = region["rect"]
		for _index in patches_per_region:
			var spot := Vector2(
				patch_rng.randf_range(rect.position.x, rect.end.x),
				patch_rng.randf_range(rect.position.y, rect.end.y))
			draw_circle(spot, patch_rng.randf_range(18.0, 54.0), region["accent"])

	if show_grid:
		var faint := Color(1.0, 1.0, 1.0, 0.035)
		var x := -half
		while x <= half:
			draw_line(Vector2(x, -half), Vector2(x, half), faint, 1.0)
			x += grid_step
		var y := -half
		while y <= half:
			draw_line(Vector2(-half, y), Vector2(half, y), faint, 1.0)
			y += grid_step

	# World border: everything past this is outside the playable area.
	draw_rect(Rect2(-half, -half, size, size), Color(0.55, 0.45, 0.25, 0.5), false, 4.0)

	var font := ThemeDB.fallback_font
	if font == null:
		return
	for label: Dictionary in _region_labels:
		var text := str(label["text"])
		var text_position: Vector2 = label["position"]
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 40)
		draw_string(font, text_position - text_size * 0.5, text,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 40, Color(1.0, 1.0, 1.0, 0.13))
