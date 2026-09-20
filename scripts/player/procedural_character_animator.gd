class_name ProceduralCharacterAnimator
extends CharacterAnimator
## Default character renderer using procedural _draw() calls.
##
## This is the fallback implementation that preserves the current art style.
## When a sprite-based character model is available, swap this node for a
## SpriteCharacterAnimator (or any other CharacterAnimator subclass) and the
## Player script will automatically use the new renderer without code changes.
##
## Equipment is drawn as colored overlays on top of the base body.

## Skin / clothing palette — derived from equipment each frame.
var _skin := Color(0.78, 0.62, 0.5)
var _shirt := Color(0.33, 0.39, 0.34)
var _pants := Color(0.22, 0.24, 0.29)
var _hair := Color(0.16, 0.13, 0.11)
var _boots := Color(0.22, 0.17, 0.13)
var _belt := Color(0.28, 0.22, 0.16)

## Idle bobbing animation.
var _idle_bob: float = 0.0
var _walk_cycle: float = 0.0
## Hurt flash overlay.
var _hurt_flash: float = 0.0
## Death ragdoll progress.
var _death_progress: float = 0.0


func _ready() -> void:
	super._ready()
	base_anim_fps = 8.0


func _on_state_changed(old_state: AnimState, new_state: AnimState) -> void:
	match new_state:
		AnimState.HURT:
			_hurt_flash = 0.3
		AnimState.DEATH:
			_death_progress = 0.0
		AnimState.ATTACK:
			pass


func update_from_player(player_node: Node2D) -> void:
	super.update_from_player(player_node)
	# Update animation timers.
	var dt := delta_from_player()
	match current_state:
		AnimState.IDLE:
			_idle_bob = sin(state_time * 2.5) * 1.2
		AnimState.WALK, AnimState.RUN, AnimState.SPRINT:
			var cycle_speed := get_normalized_speed() * 12.0 + 4.0
			_walk_cycle += dt * cycle_speed
		AnimState.HURT:
			_hurt_flash = maxf(0.0, _hurt_flash - dt * 3.0)
		AnimState.DEATH:
			_death_progress = minf(1.0, _death_progress + dt * 3.0)


func _draw() -> void:
	draw_character()


func draw_character() -> void:
	if player == null:
		return

	_refresh_palette()

	match current_state:
		AnimState.DEATH:
			_draw_corpse()
		_:
			_draw_body()


func _refresh_palette() -> void:
	_skin = Color(0.78, 0.62, 0.5)
	_shirt = _equipment_color("shirt", Color(0.33, 0.39, 0.34))
	_pants = _equipment_color("pants", Color(0.22, 0.24, 0.29))
	_hair = _equipment_color("hair", Color(0.16, 0.13, 0.11))
	_boots = _equipment_color("boots", Color(0.22, 0.17, 0.13))
	_belt = Color(0.28, 0.22, 0.16)


# ===========================================================================
# Body drawing
# ===========================================================================

func _draw_body() -> void:
	var dir := Vector2.RIGHT.rotated(facing_angle())
	var bob := _idle_bob if current_state == AnimState.IDLE else 0.0
	var walk_offset := _walk_limb_offset() if (current_state == AnimState.WALK or current_state == AnimState.RUN or current_state == AnimState.SPRINT) else Vector2.ZERO
	var hurt_offset := Vector2(randf_range(-1, 1), 0) * _hurt_flash * 3.0

	# Shadow.
	draw_circle_sh(Vector2(0, 14), 15.0, Color(0, 0, 0, 0.20))

	# --- legs & boots ---
	var leg_w := 5.0
	var leg_h := 10.0
	var leg_y := 2.0
	var boot_h := 3.5
	# Left leg.
	draw_rounded_rect_sh(Rect2(-8.5, leg_y + walk_offset.y * 0.5, leg_w, leg_h), _pants, 1.5)
	draw_rounded_rect_sh(Rect2(-8.5, leg_y + leg_h + walk_offset.y * 0.5, leg_w, boot_h), _boots, 1.5)
	# Right leg.
	draw_rounded_rect_sh(Rect2(3.5, leg_y - walk_offset.y * 0.5, leg_w, leg_h), _pants, 1.5)
	draw_rounded_rect_sh(Rect2(3.5, leg_y + leg_h - walk_offset.y * 0.5, leg_w, boot_h), _boots, 1.5)
	# Belt.
	draw_rect(Rect2(-10, -1, 20, 3.0), _belt, true)
	draw_circle_sh(Vector2(0, 0.5), 2.0, Color(0.6, 0.55, 0.4))

	# --- torso (jacket) ---
	var jacket := _shirt
	draw_rounded_rect_sh(Rect2(-11, -11 + bob, 22, 13), jacket, 2.0)
	# Collar.
	draw_line(Vector2(-5, -11 + bob), Vector2(5, -11 + bob), jacket.lightened(0.15), 1.5)
	# Zipper / seam.
	draw_line(Vector2(0, -11 + bob), Vector2(0, 2 + bob), jacket.darkened(0.25), 1.0)
	# Pockets.
	draw_rect(Rect2(-9, -3 + bob, 7, 5), jacket.darkened(0.08), true)
	draw_rect(Rect2(2, -3 + bob, 7, 5), jacket.darkened(0.08), true)

	# --- arms ---
	var arm_w := 4.0
	var arm_h := 9.0
	var arm_y := -8.0 + bob
	# Left arm.
	draw_rounded_rect_sh(Rect2(-14.0 + walk_offset.x * 0.3, arm_y, arm_w, arm_h), _shirt.darkened(0.10), 1.5)
	draw_circle_sh(Vector2(-14.0 + arm_w * 0.5 + walk_offset.x * 0.3, arm_y + arm_h + 1), 2.5, _skin)
	# Right arm (weapon hand).
	var right_arm_x := 10.0 + walk_offset.x * -0.3
	draw_rounded_rect_sh(Rect2(right_arm_x, arm_y, arm_w, arm_h), _shirt.darkened(0.10), 1.5)
	draw_circle_sh(Vector2(right_arm_x + arm_w * 0.5, arm_y + arm_h + 1), 2.5, _skin)

	# --- backpack (equipment layer) ---
	_draw_backpack(bob)

	# --- helmet (equipment layer) ---
	_draw_helmet(bob)

	# --- head ---
	var head_pos := Vector2(0, -16 + bob)
	draw_circle_sh(head_pos, 8.0, _skin)
	# Hair (hidden by helmet).
	var head_id := _get_equipment("head")
	if head_id.is_empty():
		draw_rounded_rect_sh(Rect2(-8, -24.5 + bob, 16, 6.5), _hair, 2.5)
		draw_rounded_rect_sh(Rect2(-8, -21 + bob, 3, 5), _hair.darkened(0.08), 1.0)
		draw_rounded_rect_sh(Rect2(5, -21 + bob, 3, 5), _hair.darkened(0.08), 1.0)
	# Face direction dot.
	var face_pos := head_pos + dir * 5.0
	draw_circle_sh(face_pos, 1.6, Color(0.12, 0.10, 0.10))
	# Eyes.
	var perp := Vector2(-dir.y, dir.x)
	draw_circle_sh(face_pos + perp * 2.2 - dir * 1.5, 1.1, Color(0.10, 0.08, 0.08))
	draw_circle_sh(face_pos - perp * 2.2 - dir * 1.5, 1.1, Color(0.10, 0.08, 0.08))

	# --- held item ---
	_draw_held_item(dir, bob)

	# --- attack flash ---
	var attack_flash_val: float = 0.0
	if player != null:
		attack_flash_val = float(player.get("_attack_flash"))
	if attack_flash_val > 0.0:
		var flash_alpha := clampf(attack_flash_val * 5.0, 0.0, 0.85)
		var reach := 26.0
		if player != null and player.has_method("get_active_item"):
			var item = player.get_active_item()
			if item != null and item.attack_range > 0.0:
				reach = item.attack_range
		draw_attack_flash(reach, flash_alpha)

	# --- hurt flash overlay ---
	if _hurt_flash > 0.0:
		draw_circle_sh(Vector2.ZERO, 18.0, Color(1.0, 0.2, 0.1, _hurt_flash * 0.3))

	# --- state-specific overlays ---
	match current_state:
		AnimState.GATHER:
			_draw_gather_indicator(bob)
		AnimState.SPRINT:
			_draw_sprint_dust(bob)


func _walk_limb_offset() -> Vector2:
	var swing := sin(_walk_cycle) * 4.0
	return Vector2(swing, abs(sin(_walk_cycle * 0.5)) * 2.0)


# ===========================================================================
# Equipment layers
# ===========================================================================

func _draw_backpack(bob: float) -> void:
	var backpack_id := _get_equipment("backpack")
	if backpack_id.is_empty():
		return
	var bp_color := _equipment_color("backpack", Color(0.40, 0.33, 0.22))
	draw_rounded_rect_sh(Rect2(-8, -14 + bob, 16, 10), bp_color.darkened(0.15), 2.0)
	draw_rounded_rect_sh(Rect2(-6, -12 + bob, 12, 6), bp_color, 2.0)
	draw_circle_sh(Vector2(0, -12 + bob), 1.5, Color(0.55, 0.50, 0.40))


func _draw_helmet(bob: float) -> void:
	var head_id := _get_equipment("head")
	if head_id.is_empty():
		return
	var helmet_color := _equipment_color("head", Color(0.35, 0.35, 0.35))
	draw_rounded_rect_sh(Rect2(-9, -25 + bob, 18, 7), helmet_color, 3.0)
	draw_rounded_rect_sh(Rect2(-7, -20 + bob, 14, 4), helmet_color.darkened(0.1), 1.5)


# ===========================================================================
# Held item
# ===========================================================================

func _draw_held_item(dir: Vector2, bob: float) -> void:
	if player == null:
		return
	if not player.has_method("get_active_item"):
		return
	var item = player.get_active_item()
	if item == null:
		return
	var origin := dir * 13.0 + Vector2(10, -5 + bob)
	if item.category == ItemDefinition.Category.WEAPON or item.tool_type != ItemDefinition.ToolType.NONE:
		var handle_end := origin + dir * 6.0
		draw_line(origin, handle_end, Color(0.35, 0.26, 0.16), 2.5)
		match item.tool_type:
			ItemDefinition.ToolType.AXE:
				draw_circle_sh(handle_end + dir * 3.0, 4.5, Color(0.5, 0.5, 0.52))
				draw_line(handle_end, handle_end + dir * 3.0, Color(0.45, 0.45, 0.48), 2.0)
			ItemDefinition.ToolType.KNIFE:
				draw_line(handle_end, handle_end + dir * 8.0, Color(0.65, 0.65, 0.7), 2.0)
			ItemDefinition.ToolType.PICKAXE:
				var perp := Vector2(-dir.y, dir.x)
				draw_line(handle_end + perp * 5, handle_end - perp * 5, Color(0.5, 0.5, 0.52), 3.0)
			ItemDefinition.ToolType.HAMMER:
				draw_rect(Rect2(handle_end.x - 4, handle_end.y - 3, 8, 6), Color(0.48, 0.48, 0.5), true)
			_:
				draw_circle_sh(handle_end, 4.0, item.icon_color)
	else:
		draw_circle_sh(origin, 4.5, item.icon_color)


# ===========================================================================
# State-specific visual effects
# ===========================================================================

func _draw_gather_indicator(bob: float) -> void:
	if player == null:
		return
	var progress := 0.0
	if player.has_method("is_gathering") and player.is_gathering():
		var target = player.get_gather_target()
		if target != null and target.has_method("get_gather_duration"):
			var duration: float = target.get_gather_duration(player.get_tool_type())
			var gather_time: float = float(player.get("_gather_time"))
			progress = clampf(gather_time / maxf(0.1, duration), 0.0, 1.0)
	var center := Vector2(0, -28 + bob)
	var radius := 6.0
	var start_angle := -PI * 0.5
	var end_angle := start_angle + TAU * progress
	var points := PackedVector2Array()
	for i in 16:
		var a := lerpf(start_angle, end_angle, float(i) / 15.0)
		points.append(center + Vector2.RIGHT.rotated(a) * radius)
	if points.size() >= 2:
		draw_polyline(points, Color(0.85, 0.80, 0.40, 0.8), 2.0)


func _draw_sprint_dust(bob: float) -> void:
	var t := fmod(state_time * 4.0, 1.0)
	for i in 3:
		var phase := fmod(t + float(i) * 0.33, 1.0)
		var alpha := (1.0 - phase) * 0.25
		var offset := Vector2(0, 8 + phase * 12) - Vector2.RIGHT.rotated(facing_angle()) * (4 + phase * 8)
		draw_circle_sh(offset, 2.0 + phase * 2.0, Color(0.5, 0.45, 0.35, alpha))


# ===========================================================================
# Death / corpse
# ===========================================================================

func _draw_corpse() -> void:
	var corpse_color := Color(0.28, 0.26, 0.24)
	var skin_color := Color(0.60, 0.48, 0.38)
	# Shadow.
	draw_circle_sh(Vector2(2, 4), 14.0, Color(0, 0, 0, 0.25))
	# Body.
	draw_rounded_rect_sh(Rect2(-10, -5, 20, 10), corpse_color, 2.0)
	# Head.
	draw_circle_sh(Vector2(-8, -6), 6.5, skin_color)
	# Arms sprawled.
	draw_line(Vector2(-10, -2), Vector2(-18, -8), Color(0.55, 0.45, 0.38), 2.5)
	draw_line(Vector2(8, -1), Vector2(16, 8), Color(0.55, 0.45, 0.38), 2.5)
	# Legs.
	draw_line(Vector2(-3, 5), Vector2(-8, 14), Color(0.20, 0.19, 0.18), 3.0)
	draw_line(Vector2(3, 5), Vector2(8, 14), Color(0.20, 0.19, 0.18), 3.0)
	# Blood pool.
	draw_circle_sh(Vector2(0, 8), 8.0, Color(0.35, 0.08, 0.06, 0.45))
