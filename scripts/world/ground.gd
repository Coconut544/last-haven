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
## Grass tufts and debris per region.
@export_range(0, 300, 1) var detail_per_region: int = 60

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
			var radius := patch_rng.randf_range(18.0, 54.0)
			draw_circle(spot, radius, region["accent"])
			# Secondary ring for softer blending.
			draw_circle(spot, radius * 1.4, Color(region["accent"].r, region["accent"].g, region["accent"].b, 0.3))

	# --- detail layer: grass tufts, dirt patches, debris, paths ---
	var detail_rng := RandomNumberGenerator.new()
	detail_rng.seed = _drawn_seed + 41
	for region: Dictionary in WorldRegions.get_region_definitions():
		var rect: Rect2 = region["rect"]
		var region_id: String = str(region["id"])
		for _index in detail_per_region:
			var pos := Vector2(
				detail_rng.randf_range(rect.position.x, rect.end.x),
				detail_rng.randf_range(rect.position.y, rect.end.y))
			var detail_type := detail_rng.randi_range(0, 4)
			match detail_type:
				0: # Grass tuft (short lines).
					_draw_grass_tuft(pos, detail_rng, region)
				1: # Dirt / worn patch.
					_draw_dirt_patch(pos, detail_rng, region)
				2: # Small pebble.
					_draw_pebble(pos, detail_rng, region)
				3: # Fallen twig.
					_draw_twig(pos, detail_rng)
				_: # Subtle ground variation.
					draw_circle(pos, detail_rng.randf_range(4.0, 10.0), Color(region["ground"].r, region["ground"].g, region["ground"].b, 0.25))

	# --- region transition blending (soft strips between adjacent regions) ---
	var regions := WorldRegions.get_region_definitions()
	for i in regions.size():
		var rect_a: Rect2 = regions[i]["rect"]
		var ground_a: Color = regions[i]["ground"]
		for j in range(i + 1, regions.size()):
			var rect_b: Rect2 = regions[j]["rect"]
			var ground_b: Color = regions[j]["ground"]
			_draw_region_blend(rect_a, ground_a, rect_b, ground_b)

	# --- abandoned road (runs through rural + town) ---
	_draw_road(true, 700.0, half, detail_rng)

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

	# World border.
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


func _draw_grass_tuft(pos: Vector2, rng: RandomNumberGenerator, region: Dictionary) -> void:
	var base_color := Color(region["ground"].r + 0.04, region["ground"].g + 0.08, region["ground"].b + 0.02, 0.55)
	var blades := rng.randi_range(2, 4)
	for i in blades:
		var angle := rng.randf_range(-0.5, 0.5)
		var len := rng.randf_range(4.0, 9.0)
		var offset := Vector2(rng.randf_range(-3.0, 3.0), 0)
		var tip := pos + offset + Vector2.RIGHT.rotated(angle - PI * 0.5) * len
		draw_line(pos + offset, tip, base_color, 1.0)


func _draw_dirt_patch(pos: Vector2, rng: RandomNumberGenerator, region: Dictionary) -> void:
	var dirt := Color(region["ground"].r - 0.02, region["ground"].g - 0.01, region["ground"].b - 0.01, 0.35)
	var radius := rng.randf_range(6.0, 16.0)
	draw_circle(pos, radius, dirt)
	draw_circle(pos + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)), radius * 0.6, dirt.darkened(0.05))


func _draw_pebble(pos: Vector2, rng: RandomNumberGenerator, region: Dictionary) -> void:
	var stone := Color(0.3, 0.3, 0.28, 0.4)
	var r := rng.randf_range(1.5, 3.5)
	draw_circle(pos, r, stone)
	draw_circle(pos + Vector2(0.5, -0.5), r * 0.5, stone.lightened(0.1))


func _draw_twig(pos: Vector2, rng: RandomNumberGenerator) -> void:
	var wood := Color(0.3, 0.22, 0.14, 0.35)
	var angle := rng.randf_range(0, PI)
	var len := rng.randf_range(6.0, 14.0)
	var end_pos := pos + Vector2.RIGHT.rotated(angle) * len
	draw_line(pos, end_pos, wood, 1.5)
	# Small branch offshoot.
	if rng.randf() > 0.5:
		var branch_len := len * 0.4
		var mid := pos.lerp(end_pos, 0.5)
		draw_line(mid, mid + Vector2.RIGHT.rotated(angle + 0.6) * branch_len, wood, 1.0)


func _draw_region_blend(rect_a: Rect2, color_a: Color, rect_b: Rect2, color_b: Color) -> void:
	# Only blend if regions share an edge (adjacent).
	var overlap := rect_a.intersection(rect_b)
	if overlap.size.x * overlap.size.y == 0.0:
		# Check for touching edges (within 2px).
		var touches_x := absf(rect_a.end.x - rect_b.position.x) < 2.0 or absf(rect_b.end.x - rect_a.position.x) < 2.0
		var touches_y := absf(rect_a.end.y - rect_b.position.y) < 2.0 or absf(rect_b.end.y - rect_a.position.y) < 2.0
		if not (touches_x or touches_y):
			return

	# Draw a soft blended strip along the shared edge.
	var blend_color := color_a.lerp(color_b, 0.5)
	blend_color.a = 0.15
	var strip_w := 20.0
	# Horizontal edge.
	if absf(rect_a.end.y - rect_b.position.y) < 2.0 or absf(rect_b.end.y - rect_a.position.y) < 2.0:
		var y := (rect_a.end.y + rect_b.position.y) * 0.5
		var x_start := maxf(rect_a.position.x, rect_b.position.x)
		var x_end := minf(rect_a.end.x, rect_b.end.x)
		draw_rect(Rect2(x_start, y - strip_w * 0.5, x_end - x_start, strip_w), blend_color, true)
	# Vertical edge.
	if absf(rect_a.end.x - rect_b.position.x) < 2.0 or absf(rect_b.end.x - rect_a.position.x) < 2.0:
		var x := (rect_a.end.x + rect_b.position.x) * 0.5
		var y_start := maxf(rect_a.position.y, rect_b.position.y)
		var y_end := minf(rect_a.end.y, rect_b.end.y)
		draw_rect(Rect2(x - strip_w * 0.5, y_start, strip_w, y_end - y_start), blend_color, true)


func _draw_road(horizontal: bool, position_val: float, half: float, rng: RandomNumberGenerator) -> void:
	var road_color := Color(0.14, 0.13, 0.12, 0.5)
	var shoulder := Color(0.16, 0.15, 0.13, 0.25)
	var road_h := 24.0
	if horizontal:
		# Shoulder.
		draw_rect(Rect2(-half, position_val - road_h * 0.7, half * 2.0, road_h * 1.4), shoulder, true)
		# Road surface.
		draw_rect(Rect2(-half, position_val - road_h * 0.5, half * 2.0, road_h), road_color, true)
		# Center line (dashed, faded).
		var dash_x := -half
		while dash_x < half:
			draw_rect(Rect2(dash_x, position_val - 0.5, 20.0, 1.0), Color(0.5, 0.45, 0.2, 0.25), true)
			dash_x += 40.0
		# Potholes / damage.
		for i in 8:
			var px := rng.randf_range(-half + 100, half - 100)
			draw_circle(Vector2(px, position_val + rng.randf_range(-6, 6)), rng.randf_range(3, 7), road_color.darkened(0.2))
	# Shoulder edge lines.
	var edge_alpha := 0.2
	draw_line(Vector2(-half, position_val - road_h * 0.5), Vector2(half, position_val - road_h * 0.5), Color(0.4, 0.38, 0.3, edge_alpha), 1.0)
	draw_line(Vector2(-half, position_val + road_h * 0.5), Vector2(half, position_val + road_h * 0.5), Color(0.4, 0.38, 0.3, edge_alpha), 1.0)
