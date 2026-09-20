class_name ProceduralZombieAnimator
extends ZombieAnimator
## Default zombie renderer using procedural _draw() calls.
##
## Preserves all 4 variant drawing methods (Standard, Heavy, Fast, Special)
## from the original zombie.gd while adding animation-driven visual feedback:
## - Walk cycle with limb swing
## - Idle shamble sway
## - Hit flash overlay
## - Chase eye glow
## - Death collapse
##
## To replace with sprite-based art, swap this node for any ZombieAnimator
## subclass — the Zombie script does not change.

## Visual palette (refreshed each frame from variant).
var _body_color := Color(0.36, 0.44, 0.33)
var _skin_color := Color(0.55, 0.63, 0.48)
var _clothes_color := Color(0.30, 0.32, 0.28)
var _body_scale := 1.0

## Animation timers.
var _walk_cycle: float = 0.0
var _idle_sway: float = 0.0
var _hurt_flash: float = 0.0
var _death_progress: float = 0.0


func _ready() -> void:
	super._ready()
	base_anim_fps = 6.0  # Zombies are slower, shambling.


func _on_state_changed(old_state: AnimState, new_state: AnimState) -> void:
	match new_state:
		AnimState.HURT:
			_hurt_flash = 0.2
		AnimState.DEATH:
			_death_progress = 0.0


func update_from_zombie(zombie_node: Node2D) -> void:
	super.update_from_zombie(zombie_node)
	_refresh_variant_colors()
	var dt := delta_from_zombie()
	match current_state:
		AnimState.IDLE:
			_idle_sway = sin(state_time * 1.5) * 1.0
		AnimState.WANDER, AnimState.SEARCH, AnimState.RETURN:
			var cycle_speed := get_normalized_speed() * 6.0 + 2.0
			_walk_cycle += dt * cycle_speed
		AnimState.CHASE:
			var cycle_speed := get_normalized_speed() * 10.0 + 4.0
			_walk_cycle += dt * cycle_speed
		AnimState.HURT:
			_hurt_flash = maxf(0.0, _hurt_flash - dt * 4.0)
		AnimState.DEATH:
			_death_progress = minf(1.0, _death_progress + dt * 2.5)


func _draw() -> void:
	draw_zombie()


func draw_zombie() -> void:
	if zombie == null:
		return

	var hit_flash_val: float = 0.0
	var hv = zombie.get("_hit_flash")
	if hv != null:
		hit_flash_val = float(hv)

	var body := _body_color
	if hit_flash_val > 0.0:
		body = body.lerp(Color(0.95, 0.35, 0.3), 0.65)

	if current_state == AnimState.DEATH:
		_draw_corpse(body.darkened(0.45), _skin_color.darkened(0.4))
		return

	var s := _body_scale
	var dir := Vector2.RIGHT.rotated(facing_angle())
	var sway := _idle_sway if current_state == AnimState.IDLE else 0.0
	var walk_off := _walk_limb_offset() if (current_state == AnimState.WANDER or current_state == AnimState.CHASE or current_state == AnimState.SEARCH or current_state == AnimState.RETURN) else Vector2.ZERO

	# Shadow.
	draw_circle_sh(Vector2(0, 12 * s), 14.0 * s, Color(0, 0, 0, 0.22))

	# Draw variant-specific body.
	match visual_variant:
		0:  # STANDARD
			_draw_standard(body, _skin_color, _clothes_color, s, dir, sway, walk_off)
		1:  # HEAVY
			_draw_heavy(body, _skin_color, s, dir, sway, walk_off)
		2:  # FAST
			_draw_fast(body, _skin_color, s, dir, sway, walk_off)
		3:  # SPECIAL
			_draw_special(body, _skin_color, s, dir, sway, walk_off)

	# Hurt flash overlay.
	if _hurt_flash > 0.0:
		draw_circle_sh(Vector2(0, -5 * s), 20.0 * s, Color(1.0, 0.2, 0.1, _hurt_flash * 0.35))

	# Health bar.
	var health_comp = zombie.get("health")
	if health_comp != null:
		var is_full: bool = false
		if health_comp.has_method("is_full"):
			is_full = health_comp.is_full()
		if not is_full:
			var ratio: float = 1.0
			if health_comp.has_method("get_ratio"):
				ratio = health_comp.get_ratio()
			var bar_w := 24.0 * s
			draw_rounded_rect_sh(Rect2(-bar_w * 0.5, -28.0 * s, bar_w, 4.0), Color(0, 0, 0, 0.65), 1.0)
			draw_rounded_rect_sh(Rect2(-bar_w * 0.5, -28.0 * s, bar_w * ratio, 4.0), Color(0.8, 0.25, 0.2), 1.0)


func _walk_limb_offset() -> Vector2:
	var swing := sin(_walk_cycle) * 3.5
	return Vector2(swing, abs(sin(_walk_cycle * 0.5)) * 1.5)


func _refresh_variant_colors() -> void:
	match visual_variant:
		0:  # STANDARD
			_body_color = Color(0.36, 0.44, 0.33)
			_skin_color = Color(0.55, 0.63, 0.48)
			_clothes_color = Color(0.30, 0.32, 0.28)
			_body_scale = 1.0
		1:  # HEAVY
			_body_color = Color(0.32, 0.30, 0.28)
			_skin_color = Color(0.50, 0.45, 0.40)
			_clothes_color = Color(0.25, 0.24, 0.22)
			_body_scale = 1.3
		2:  # FAST
			_body_color = Color(0.40, 0.38, 0.35)
			_skin_color = Color(0.60, 0.55, 0.50)
			_clothes_color = Color(0.35, 0.18, 0.15)
			_body_scale = 0.85
		3:  # SPECIAL
			_body_color = Color(0.30, 0.38, 0.30)
			_skin_color = Color(0.50, 0.55, 0.45)
			_clothes_color = Color(0.25, 0.35, 0.38)
			_body_scale = 1.15


# ===========================================================================
# Standard variant — common, hunched, shambling infected survivor
# ===========================================================================

func _draw_standard(body: Color, skin: Color, clothes: Color, s: float, dir: Vector2, sway: float, walk_off: Vector2) -> void:
	# Legs (torn pants).
	draw_rounded_rect_sh(Rect2(-8 * s, 3 * s + walk_off.y * 0.5, 6 * s, 10 * s), body.darkened(0.15), 1.0)
	draw_rounded_rect_sh(Rect2(2 * s, 3 * s - walk_off.y * 0.5, 6 * s, 10 * s), body.darkened(0.15), 1.0)
	# Tattered shirt torso.
	draw_rounded_rect_sh(Rect2(-10 * s, -8 * s + sway, 20 * s, 13 * s), clothes, 2.0)
	# Tear on shirt.
	draw_line(Vector2(-4 * s, -2 * s + sway), Vector2(2 * s, 4 * s + sway), body.darkened(0.3), 1.0)
	# Arms (reaching forward, undead posture).
	var arm_reach := dir * 2.0 * s
	draw_rounded_rect_sh(Rect2(-13 * s + walk_off.x * 0.3, -6 * s + sway, 4 * s, 10 * s), skin.darkened(0.1), 1.0)
	draw_rounded_rect_sh(Rect2(9 * s - walk_off.x * 0.3, -6 * s + sway, 4 * s, 10 * s), skin.darkened(0.1), 1.0)
	# Hands reaching.
	draw_circle_sh(Vector2(-11 * s, 4 * s + sway) + arm_reach, 3.0 * s, skin.darkened(0.15))
	draw_circle_sh(Vector2(11 * s, 4 * s + sway) + arm_reach, 3.0 * s, skin.darkened(0.15))
	# Head — bald with torn scalp.
	draw_circle_sh(Vector2(0, -14 * s + sway), 8.0 * s, skin)
	draw_circle_sh(Vector2(0, -18 * s + sway), 4.0 * s, skin.darkened(0.25))
	# Slack jaw.
	draw_rounded_rect_sh(Rect2(-3.5 * s, -10 * s + sway, 7 * s, 4 * s), skin.darkened(0.35), 1.0)
	# Eyes glow when aggressive.
	_draw_eyes(Vector2(0, -15 * s + sway), s, skin, Color(0.95, 0.35, 0.25), Color(0.6, 0.25, 0.2))


# ===========================================================================
# Heavy variant — wider, slower, bulkier silhouette
# ===========================================================================

func _draw_heavy(body: Color, skin: Color, s: float, dir: Vector2, sway: float, walk_off: Vector2) -> void:
	var hs := s * 1.25
	# Thick legs.
	draw_rounded_rect_sh(Rect2(-10 * hs, 2 * hs + walk_off.y * 0.5, 8 * hs, 12 * hs), body.darkened(0.2), 1.5)
	draw_rounded_rect_sh(Rect2(2 * hs, 2 * hs - walk_off.y * 0.5, 8 * hs, 12 * hs), body.darkened(0.2), 1.5)
	# Industrial vest / overalls.
	draw_rounded_rect_sh(Rect2(-13 * hs, -10 * hs + sway, 26 * hs, 14 * hs), Color(0.28, 0.26, 0.24), 2.0)
	# Reflective stripe.
	draw_line(Vector2(-13 * hs, -4 * hs + sway), Vector2(13 * hs, -4 * hs + sway), Color(0.65, 0.55, 0.15), 2.0)
	# Massive arms.
	draw_rounded_rect_sh(Rect2(-17 * hs + walk_off.x * 0.4, -7 * hs + sway, 5 * hs, 12 * hs), skin.darkened(0.05), 1.5)
	draw_rounded_rect_sh(Rect2(12 * hs - walk_off.x * 0.4, -7 * hs + sway, 5 * hs, 12 * hs), skin.darkened(0.05), 1.5)
	# Big fists.
	var arm_reach := dir * 4.0 * hs
	draw_circle_sh(Vector2(-14.5 * hs, 5 * hs + sway) + arm_reach, 4.5 * hs, skin.darkened(0.1))
	draw_circle_sh(Vector2(14.5 * hs, 5 * hs + sway) + arm_reach, 4.5 * hs, skin.darkened(0.1))
	# Head — shaved, thick neck.
	draw_circle_sh(Vector2(0, -15 * hs + sway), 9.0 * hs, skin)
	# Safety helmet remnant.
	draw_rounded_rect_sh(Rect2(-9 * hs, -22 * hs + sway, 18 * hs, 5 * hs), Color(0.55, 0.50, 0.15), 2.0)
	# Eyes.
	_draw_eyes(Vector2(0, -16 * hs + sway), hs, skin, Color(0.95, 0.30, 0.20), Color(0.55, 0.20, 0.15), 1.75)


# ===========================================================================
# Fast variant — lean, thin, long limbs, ragged clothes
# ===========================================================================

func _draw_fast(body: Color, skin: Color, s: float, dir: Vector2, sway: float, walk_off: Vector2) -> void:
	var fs := s * 0.9
	# Thin legs.
	draw_rounded_rect_sh(Rect2(-6 * fs, 2 * fs + walk_off.y * 0.7, 4 * fs, 12 * fs), body.darkened(0.1), 1.0)
	draw_rounded_rect_sh(Rect2(2 * fs, 2 * fs - walk_off.y * 0.7, 4 * fs, 12 * fs), body.darkened(0.1), 1.0)
	# Skinny torso — tattered hoodie.
	var hoodie := Color(0.35, 0.18, 0.15)
	draw_rounded_rect_sh(Rect2(-8 * fs, -9 * fs + sway, 16 * fs, 12 * fs), hoodie, 1.5)
	# Hoodie strings.
	draw_line(Vector2(-2 * fs, -9 * fs + sway), Vector2(-2 * fs, -4 * fs + sway), Color(0.6, 0.55, 0.5), 1.0)
	draw_line(Vector2(2 * fs, -9 * fs + sway), Vector2(2 * fs, -4 * fs + sway), Color(0.6, 0.55, 0.5), 1.0)
	# Long reaching arms.
	var arm_reach := dir * 4.0 * fs
	draw_rounded_rect_sh(Rect2(-12 * fs + walk_off.x * 0.5, -7 * fs + sway, 3.5 * fs, 11 * fs), skin.darkened(0.15), 1.0)
	draw_rounded_rect_sh(Rect2(8.5 * fs - walk_off.x * 0.5, -7 * fs + sway, 3.5 * fs, 11 * fs), skin.darkened(0.15), 1.0)
	draw_circle_sh(Vector2(-10.25 * fs, 4 * fs + sway) + arm_reach, 2.5 * fs, skin.darkened(0.15))
	draw_circle_sh(Vector2(10.25 * fs, 4 * fs + sway) + arm_reach, 2.5 * fs, skin.darkened(0.15))
	# Head — gaunt, sunken.
	draw_circle_sh(Vector2(0, -14 * fs + sway), 6.5 * fs, skin)
	# Hollow cheeks.
	draw_circle_sh(Vector2(-3 * fs, -13 * fs + sway), 2.0 * fs, skin.darkened(0.3))
	draw_circle_sh(Vector2(3 * fs, -13 * fs + sway), 2.0 * fs, skin.darkened(0.3))
	# Eyes.
	_draw_eyes(Vector2(0, -15 * fs + sway), fs, skin, Color(0.95, 0.40, 0.20), Color(0.50, 0.22, 0.15), 1.25)


# ===========================================================================
# Special variant — biohazard appearance, glowing veins, bloated
# ===========================================================================

func _draw_special(body: Color, skin: Color, s: float, dir: Vector2, sway: float, walk_off: Vector2) -> void:
	var ss := s * 1.1
	# Bloated legs.
	draw_rounded_rect_sh(Rect2(-9 * ss, 2 * ss + walk_off.y * 0.4, 7 * ss, 11 * ss), body.darkened(0.05), 1.5)
	draw_rounded_rect_sh(Rect2(2 * ss, 2 * ss - walk_off.y * 0.4, 7 * ss, 11 * ss), body.darkened(0.05), 1.5)
	# Bloated torso — hospital gown remnant.
	var gown := Color(0.25, 0.35, 0.38)
	draw_rounded_rect_sh(Rect2(-12 * ss, -10 * ss + sway, 24 * ss, 14 * ss), gown, 2.0)
	# Biohazard veins (glowing lines across torso).
	draw_circle_sh(Vector2(-5 * ss, -4 * ss + sway), 1.5 * ss, Color(0.2, 0.8, 0.3, 0.7))
	draw_circle_sh(Vector2(3 * ss, -2 * ss + sway), 1.5 * ss, Color(0.2, 0.8, 0.3, 0.7))
	draw_circle_sh(Vector2(-1 * ss, 1 * ss + sway), 1.5 * ss, Color(0.2, 0.8, 0.3, 0.7))
	draw_line(Vector2(-5 * ss, -4 * ss + sway), Vector2(3 * ss, -2 * ss + sway), Color(0.2, 0.7, 0.3, 0.5), 1.0)
	draw_line(Vector2(3 * ss, -2 * ss + sway), Vector2(-1 * ss, 1 * ss + sway), Color(0.2, 0.7, 0.3, 0.5), 1.0)
	# Arms.
	var arm_reach := dir * 3.0 * ss
	draw_rounded_rect_sh(Rect2(-15 * ss + walk_off.x * 0.4, -7 * ss + sway, 4 * ss, 11 * ss), skin.darkened(0.1), 1.0)
	draw_rounded_rect_sh(Rect2(11 * ss - walk_off.x * 0.4, -7 * ss + sway, 4 * ss, 11 * ss), skin.darkened(0.1), 1.0)
	draw_circle_sh(Vector2(-13 * ss, 4 * ss + sway) + arm_reach, 3.5 * ss, skin.darkened(0.15))
	draw_circle_sh(Vector2(13 * ss, 4 * ss + sway) + arm_reach, 3.5 * ss, skin.darkened(0.15))
	# Head — swollen, exposed skull.
	draw_circle_sh(Vector2(0, -15 * ss + sway), 8.5 * ss, skin)
	# Exposed skull patch.
	draw_circle_sh(Vector2(0, -20 * ss + sway), 4.0 * ss, skin.darkened(0.4))
	# Eyes — green glow.
	_draw_eyes(Vector2(0, -16 * ss + sway), ss, skin, Color(0.3, 0.95, 0.3), Color(0.2, 0.5, 0.2), 1.5)


# ===========================================================================
# Shared eye drawing
# ===========================================================================

func _draw_eyes(center: Vector2, s: float, skin: Color, aggressive_color: Color, idle_color: Color, spacing: float = 3.0) -> void:
	var is_aggressive := current_state == AnimState.CHASE or current_state == AnimState.ATTACK
	var eye_color := aggressive_color if is_aggressive else idle_color
	var eye_radius := 2.0 * s if is_aggressive else 1.5 * s
	# Eyes are centered at center, spaced horizontally.
	draw_circle_sh(Vector2(center.x - spacing * s, center.y), eye_radius, eye_color)
	draw_circle_sh(Vector2(center.x + spacing * s, center.y), eye_radius, eye_color)


# ===========================================================================
# Death / corpse
# ===========================================================================

func _draw_corpse(body: Color, skin: Color) -> void:
	var dir := Vector2.RIGHT.rotated(facing_angle())
	# Shadow.
	draw_circle_sh(Vector2(2, 4), 14.0, Color(0, 0, 0, 0.25))
	# Body.
	draw_rounded_rect_sh(Rect2(-10, -5, 20, 10), body, 2.0)
	# Head.
	draw_circle_sh(Vector2(-8, -6), 6.5, skin)
	# Arms sprawled.
	draw_line(Vector2(-10, -2), Vector2(-18, -8), skin.darkened(0.1), 2.5)
	draw_line(Vector2(8, -1), Vector2(16, 8), skin.darkened(0.1), 2.5)
	# Legs.
	draw_line(Vector2(-3, 5), Vector2(-8, 14), body.darkened(0.3), 3.0)
	draw_line(Vector2(3, 5), Vector2(8, 14), body.darkened(0.3), 3.0)
	# Blood pool.
	draw_circle_sh(Vector2(0, 8), 7.0, Color(0.4, 0.08, 0.06, 0.45))
