class_name WorldProps
extends Node2D
## Draws decorative world props per region: abandoned vehicles, ruined walls,
## debris, fences, puddles, and other environmental storytelling.
##
## Props are purely visual (no collision) and drawn procedurally so every
## seed looks slightly different. They layer on top of the WorldGround ground
## painting and below the resource nodes / structures.

## Number of prop clusters per region.
@export_range(0, 60, 1) var props_per_region: int = 18

var _drawn_seed: int = 0


func _ready() -> void:
	z_index = -5
	refresh()


func refresh() -> void:
	var world := get_parent() as GameWorld
	_drawn_seed = world.get_world_seed() if world != null else 0
	queue_redraw()


func _draw() -> void:
	if _drawn_seed == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _drawn_seed + 997

	for region: Dictionary in WorldRegions.get_region_definitions():
		var rect: Rect2 = region["rect"]
		var region_id: String = str(region["id"])
		for _i in props_per_region:
			var pos := Vector2(
				rng.randf_range(rect.position.x + 20, rect.end.x - 20),
				rng.randf_range(rect.position.y + 20, rect.end.y - 20))
			var prop_type := _pick_prop(rng, region_id)
			_draw_prop(pos, prop_type, rng, region_id)


func _pick_prop(rng: RandomNumberGenerator, region_id: String) -> int:
	match region_id:
		"forest":
			# Fallen logs, mushrooms, stumps, small clearings.
			return rng.randi_range(0, 3)
		"rural":
			# Fences, hay bales, signs, puddles.
			return rng.randi_range(0, 4)
		"town":
			# Abandoned cars, rubble piles, fences, broken sidewalks.
			return rng.randi_range(0, 5)
		"industrial":
			# Shipping containers, barrel clusters, metal debris, oil stains.
			return rng.randi_range(0, 4)
		_:
			return 0


func _draw_prop(pos: Vector2, prop_type: int, rng: RandomNumberGenerator, region_id: String) -> void:
	var rotation := rng.randf_range(-0.3, 0.3)
	match region_id:
		"forest":
			_draw_forest_prop(pos, prop_type, rng, rotation)
		"rural":
			_draw_rural_prop(pos, prop_type, rng, rotation)
		"town":
			_draw_town_prop(pos, prop_type, rng, rotation)
		"industrial":
			_draw_industrial_prop(pos, prop_type, rng, rotation)


# --- forest props ---

func _draw_forest_prop(pos: Vector2, prop_type: int, rng: RandomNumberGenerator, rot: float) -> void:
	match prop_type:
		0: # Fallen log.
			var log_len := rng.randf_range(30.0, 55.0)
			var log_color := Color(0.25, 0.18, 0.12, 0.5)
			var angle := rng.randf_range(0.0, PI)
			var end_pos := pos + Vector2.RIGHT.rotated(angle) * log_len
			draw_line(pos, end_pos, log_color, 4.0)
			draw_line(pos + Vector2(0, -1), end_pos + Vector2(0, -1), log_color.lightened(0.08), 2.0)
			# Small branch.
			if rng.randf() > 0.4:
				var mid := pos.lerp(end_pos, rng.randf_range(0.3, 0.7))
				var branch_angle := angle + (rng.randf_range(0.4, 0.8) if rng.randf() > 0.5 else -rng.randf_range(0.4, 0.8))
				draw_line(mid, mid + Vector2.RIGHT.rotated(branch_angle) * rng.randf_range(8, 16), log_color, 2.0)
		1: # Mushroom cluster.
			var mushroom_color := Color(0.65, 0.45, 0.30, 0.45)
			for _i in rng.randi_range(2, 4):
				var offset := Vector2(rng.randf_range(-8, 8), rng.randf_range(-6, 6))
				var cap_r := rng.randf_range(2.5, 5.0)
				# Stem.
				draw_line(pos + offset, pos + offset + Vector2(0, -3), mushroom_color.darkened(0.15), 1.5)
				# Cap.
				draw_circle(pos + offset + Vector2(0, -4), cap_r, mushroom_color)
				draw_circle(pos + offset + Vector2(-1, -5), cap_r * 0.5, mushroom_color.lightened(0.1))
		2: # Tree stump.
			var stump_color := Color(0.28, 0.20, 0.14, 0.45)
			var stump_r := rng.randf_range(5.0, 9.0)
			draw_circle(pos, stump_r, stump_color)
			draw_circle(pos, stump_r * 0.65, stump_color.lightened(0.08))
			draw_circle(pos, stump_r * 0.3, stump_color.darkened(0.05))
		3: # Rock cluster (small).
			var rock_color := Color(0.28, 0.28, 0.26, 0.35)
			for _i in rng.randi_range(2, 3):
				var offset := Vector2(rng.randf_range(-6, 6), rng.randf_range(-4, 4))
				var r := rng.randf_range(2.0, 5.0)
				draw_circle(pos + offset, r, rock_color)
				draw_circle(pos + offset + Vector2(0.5, -0.5), r * 0.5, rock_color.lightened(0.06))


# --- rural props ---

func _draw_rural_prop(pos: Vector2, prop_type: int, rng: RandomNumberGenerator, rot: float) -> void:
	match prop_type:
		0: # Fence section.
			var fence_color := Color(0.32, 0.25, 0.18, 0.45)
			var fence_len := rng.randf_range(30.0, 60.0)
			var angle := rng.randf_range(-0.2, 0.2)
			var dir := Vector2.RIGHT.rotated(angle)
			# Posts.
			draw_line(pos - dir * fence_len * 0.5, pos - dir * fence_len * 0.5 + Vector2(0, -6), fence_color, 2.5)
			draw_line(pos + dir * fence_len * 0.5, pos + dir * fence_len * 0.5 + Vector2(0, -6), fence_color, 2.5)
			# Rails.
			draw_line(pos - dir * fence_len * 0.5 + Vector2(0, -4), pos + dir * fence_len * 0.5 + Vector2(0, -4), fence_color, 1.5)
			draw_line(pos - dir * fence_len * 0.5 + Vector2(0, -8), pos + dir * fence_len * 0.5 + Vector2(0, -8), fence_color, 1.5)
		1: # Hay bale.
			var hay_color := Color(0.55, 0.48, 0.25, 0.4)
			var bale_size := Vector2(rng.randf_range(10, 16), rng.randf_range(8, 12))
			_draw_rounded_rect_prop(Rect2(pos - bale_size * 0.5, bale_size), hay_color, 3.0)
			# Binding line.
			draw_line(pos + Vector2(0, -bale_size.y * 0.3), pos + Vector2(0, bale_size.y * 0.3), hay_color.darkened(0.15), 1.0)
		2: # Road sign (fallen/tilted).
			var post_color := Color(0.35, 0.33, 0.30, 0.4)
			var sign_color := Color(0.5, 0.45, 0.2, 0.35)
			# Post.
			draw_line(pos, pos + Vector2(0, -14), post_color, 2.0)
			# Sign (tilted).
			var tilt := rng.randf_range(-0.4, 0.4)
			_draw_rounded_rect_prop(Rect2(pos.x - 7, pos.y - 18, 14, 6), sign_color, 1.0)
		3: # Puddle.
			var puddle_color := Color(0.15, 0.18, 0.22, 0.2)
			var puddle_r := rng.randf_range(6.0, 14.0)
			draw_circle(pos, puddle_r, puddle_color)
			draw_circle(pos + Vector2(2, -1), puddle_r * 0.6, puddle_color.lightened(0.05))
		4: # Dried bush.
			var bush_color := Color(0.30, 0.25, 0.18, 0.35)
			# Bare branches.
			for _i in rng.randi_range(2, 4):
				var angle := rng.randf_range(0, TAU)
				var len := rng.randf_range(6.0, 14.0)
				draw_line(pos, pos + Vector2.RIGHT.rotated(angle) * len, bush_color, 1.0)


# --- town props ---

func _draw_town_prop(pos: Vector2, prop_type: int, rng: RandomNumberGenerator, rot: float) -> void:
	match prop_type:
		0: # Abandoned car (top-down).
			_draw_abandoned_car(pos, rng)
		1: # Rubble pile.
			var rubble_color := Color(0.25, 0.24, 0.23, 0.4)
			var rubble_r := rng.randf_range(8.0, 18.0)
			# Irregular rubble shape.
			var pts := PackedVector2Array()
			for i in 6:
				var angle := float(i) / 6.0 * TAU
				var r := rubble_r * rng.randf_range(0.6, 1.0)
				pts.append(pos + Vector2.RIGHT.rotated(angle) * r)
			draw_colored_polygon(pts, rubble_color)
			# Individual stones.
			for _i in rng.randi_range(2, 4):
				var offset := Vector2(rng.randf_range(-rubble_r, rubble_r), rng.randf_range(-rubble_r, rubble_r))
				draw_circle(pos + offset, rng.randf_range(1.5, 3.0), rubble_color.lightened(0.06))
		2: # Broken fence.
			var fence_color := Color(0.30, 0.28, 0.26, 0.4)
			var fence_len := rng.randf_range(20.0, 40.0)
			var angle := rng.randf_range(-0.3, 0.3)
			var dir := Vector2.RIGHT.rotated(angle)
			# Posts (some broken/missing).
			for i in rng.randi_range(2, 4):
				var post_pos := pos + dir * (float(i) * fence_len / 4.0 - fence_len * 0.5)
				var post_height := rng.randf_range(4.0, 8.0)
				draw_line(post_pos, post_pos + Vector2(0, -post_height), fence_color, 2.0)
			# Partial rail.
			draw_line(pos - dir * fence_len * 0.3, pos + dir * fence_len * 0.2, fence_color, 1.5)
		3: # Sidewalk crack / debris.
			var concrete := Color(0.28, 0.28, 0.27, 0.3)
			# Crack line.
			var crack_len := rng.randf_range(12.0, 25.0)
			var crack_angle := rng.randf_range(0, PI)
			var crack_end := pos + Vector2.RIGHT.rotated(crack_angle) * crack_len
			draw_line(pos, crack_end, concrete, 1.0)
			# Branch crack.
			var mid := pos.lerp(crack_end, rng.randf_range(0.3, 0.7))
			draw_line(mid, mid + Vector2.RIGHT.rotated(crack_angle + 0.7) * crack_len * 0.4, concrete, 1.0)
		4: # Trash / debris.
			var trash_color := Color(0.35, 0.32, 0.28, 0.35)
			for _i in rng.randi_range(2, 5):
				var offset := Vector2(rng.randf_range(-10, 10), rng.randf_range(-8, 8))
				var size := rng.randf_range(1.5, 3.5)
				draw_circle(pos + offset, size, trash_color)
		5: # Destroyed mailbox / hydrant.
			var metal := Color(0.35, 0.33, 0.30, 0.4)
			# Base.
			_draw_rounded_rect_prop(Rect2(pos.x - 2, pos.y - 4, 4, 6), metal, 1.0)
			# Bent top.
			draw_line(pos + Vector2(0, -4), pos + Vector2(3, -7), metal, 2.0)


# --- industrial props ---

func _draw_industrial_prop(pos: Vector2, prop_type: int, rng: RandomNumberGenerator, rot: float) -> void:
	match prop_type:
		0: # Shipping container (top-down).
			_draw_shipping_container(pos, rng)
		1: # Barrel cluster.
			var barrel_color := Color(0.30, 0.30, 0.28, 0.4)
			var rust := Color(0.40, 0.25, 0.15, 0.35)
			for _i in rng.randi_range(2, 4):
				var offset := Vector2(rng.randf_range(-10, 10), rng.randf_range(-8, 8))
				var barrel_r := rng.randf_range(4.0, 6.0)
				draw_circle(pos + offset, barrel_r, barrel_color)
				draw_circle(pos + offset, barrel_r * 0.6, barrel_color.lightened(0.05))
				# Rust ring.
				draw_circle(pos + offset, barrel_r * 0.8, Color(rust.r, rust.g, rust.b, 0.2))
		2: # Metal debris.
			var metal := Color(0.32, 0.30, 0.28, 0.35)
			# Angular metal piece.
			var pts := PackedVector2Array([
				pos + Vector2(-6, -2), pos + Vector2(-2, -8),
				pos + Vector2(5, -5), pos + Vector2(7, 1),
				pos + Vector2(3, 5), pos + Vector2(-4, 3),
			])
			draw_colored_polygon(pts, metal)
			draw_polyline(pts, metal.darkened(0.1), 1.0)
		3: # Oil stain.
			var oil := Color(0.10, 0.10, 0.10, 0.2)
			var stain_r := rng.randf_range(8.0, 18.0)
			draw_circle(pos, stain_r, oil)
			draw_circle(pos + Vector2(3, -2), stain_r * 0.6, Color(0.08, 0.12, 0.10, 0.15))
		4: # Pallet / crate remnant.
			var wood := Color(0.30, 0.24, 0.16, 0.4)
			var crate_size := Vector2(rng.randf_range(10, 18), rng.randf_range(8, 14))
			_draw_rounded_rect_prop(Rect2(pos - crate_size * 0.5, crate_size), wood, 1.5)
			# Plank lines.
			var plank_y := pos.y - crate_size.y * 0.3
			draw_line(Vector2(pos.x - crate_size.x * 0.4, plank_y), Vector2(pos.x + crate_size.x * 0.4, plank_y), wood.darkened(0.1), 1.0)


# --- shared vehicle drawing ---

func _draw_abandoned_car(pos: Vector2, rng: RandomNumberGenerator) -> void:
	var body_color := Color(rng.randf_range(0.2, 0.4), rng.randf_range(0.18, 0.35), rng.randf_range(0.15, 0.3), 0.4)
	var car_w := rng.randf_range(14.0, 20.0)
	var car_h := rng.randf_range(24.0, 32.0)
	var angle := rng.randf_range(-0.5, 0.5)
	# Body.
	_draw_rounded_rect_prop(Rect2(pos.x - car_w * 0.5, pos.y - car_h * 0.5, car_w, car_h), body_color, 3.0)
	# Windshield (darker).
	var windshield := Rect2(pos.x - car_w * 0.35, pos.y - car_h * 0.3, car_w * 0.7, car_h * 0.25)
	_draw_rounded_rect_prop(windshield, body_color.darkened(0.25), 2.0)
	# Headlights.
	draw_circle(Vector2(pos.x - car_w * 0.3, pos.y - car_h * 0.45), 2.0, Color(0.85, 0.82, 0.6, 0.3))
	draw_circle(Vector2(pos.x + car_w * 0.3, pos.y - car_h * 0.45), 2.0, Color(0.85, 0.82, 0.6, 0.3))
	# Wheels (dark circles).
	var wheel_color := Color(0.12, 0.12, 0.12, 0.35)
	draw_circle(Vector2(pos.x - car_w * 0.5, pos.y - car_h * 0.3), 3.0, wheel_color)
	draw_circle(Vector2(pos.x + car_w * 0.5, pos.y - car_h * 0.3), 3.0, wheel_color)
	draw_circle(Vector2(pos.x - car_w * 0.5, pos.y + car_h * 0.3), 3.0, wheel_color)
	draw_circle(Vector2(pos.x + car_w * 0.5, pos.y + car_h * 0.3), 3.0, wheel_color)
	# Rust/damage marks.
	if rng.randf() > 0.4:
		var rust_color := Color(0.40, 0.22, 0.12, 0.25)
		draw_circle(pos + Vector2(rng.randf_range(-4, 4), rng.randf_range(-6, 6)), rng.randf_range(2, 5), rust_color)


func _draw_shipping_container(pos: Vector2, rng: RandomNumberGenerator) -> void:
	var container_color := Color(rng.randf_range(0.25, 0.45), rng.randf_range(0.25, 0.35), rng.randf_range(0.2, 0.3), 0.35)
	var c_w := rng.randf_range(20.0, 30.0)
	var c_h := rng.randf_range(12.0, 18.0)
	# Main body.
	_draw_rounded_rect_prop(Rect2(pos.x - c_w * 0.5, pos.y - c_h * 0.5, c_w, c_h), container_color, 2.0)
	# Corrugated lines.
	var line_color := container_color.darkened(0.08)
	var line_spacing := c_h / 4.0
	for i in 3:
		var ly := pos.y - c_h * 0.5 + line_spacing * (i + 1)
		draw_line(Vector2(pos.x - c_w * 0.45, ly), Vector2(pos.x + c_w * 0.45, ly), line_color, 1.0)
	# Edge highlights.
	draw_line(Vector2(pos.x - c_w * 0.5, pos.y - c_h * 0.5), Vector2(pos.x + c_w * 0.5, pos.y - c_h * 0.5),
			container_color.lightened(0.08), 1.5)
	# Door handles.
	draw_circle(Vector2(pos.x + c_w * 0.45, pos.y), 1.5, Color(0.4, 0.38, 0.35, 0.4))


func _draw_rounded_rect_prop(rect: Rect2, color: Color, radius: float) -> void:
	draw_rect(rect, color, true)
	draw_circle(Vector2(rect.position.x + radius, rect.position.y + radius), radius, color)
	draw_circle(Vector2(rect.end.x - radius, rect.position.y + radius), radius, color)
	draw_circle(Vector2(rect.position.x + radius, rect.end.y - radius), radius, color)
	draw_circle(Vector2(rect.end.x - radius, rect.end.y - radius), radius, color)
