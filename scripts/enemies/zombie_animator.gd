class_name ZombieAnimator
extends Node2D
## Extensible zombie character rendering system.
##
## This is the base class that defines animation states and the interface
## the Zombie script uses to drive visuals. Concrete implementations handle
## HOW the zombie is drawn — procedurally per-variant, with sprites, or with
## a full animation player — without the Zombie script knowing which method
## is in use.
##
## Design goals (mirrors the player's CharacterAnimator):
## - Swap zombie models/animations without touching zombie.gd
## - Variant-specific drawing is the animator's responsibility
## - Animation states are explicit and auditable
## - The default (ProceduralZombieAnimator) preserves the current _draw() art
## - Compatible with the existing AI: the Zombie script reads/writes its own
##   State enum; the animator maps those to visual states.

## Visual animation states for the zombie.
## Maps from the Zombie's gameplay State to visual representations.
enum AnimState {
	IDLE,
	WANDER,
	CHASE,
	ATTACK,
	SEARCH,
	RETURN,
	HURT,
	DEATH,
}

## Direction the zombie is facing (4-way: UP, DOWN, LEFT, RIGHT).
enum Facing { DOWN, UP, LEFT, RIGHT }

## Current animation state.
var current_state: AnimState = AnimState.IDLE
var previous_state: AnimState = AnimState.IDLE
var facing: Facing = Facing.DOWN

## How long the current state has been active (seconds).
var state_time: float = 0.0

## Blending factor between previous and current state (0..1).
var blend_progress: float = 1.0

## Duration of the blend transition between states.
@export var blend_duration: float = 0.15

## Frame index within the current animation (for sprite sheet playback).
var anim_frame: int = 0

## Total frames in the current animation.
var anim_frame_count: int = 1

## Speed multiplier for animation playback.
var anim_speed: float = 1.0

## Whether the animation has completed one cycle (for one-shot states).
var anim_finished: bool = false

## Time accumulator for frame advance.
var _frame_timer: float = 0.0

## Pixels per second for the current animation's frame rate.
@export var base_anim_fps: float = 8.0

## The zombie node that owns this animator.
var zombie: Node2D = null

## Visual variant — set from the zombie's visual_variant.
var visual_variant: int = 0  ## Matches Zombie.ZombieVariant values.

## Visual properties derived from variant (refreshed each frame by subclass).
var body_scale: float = 1.0
var body_color := Color(0.36, 0.44, 0.33)
var skin_color := Color(0.55, 0.63, 0.48)
var clothes_color := Color(0.30, 0.32, 0.28)


func _ready() -> void:
	pass


## Called by Zombie every physics frame to update the animator's state.
## Reads gameplay state from the zombie and maps it to animation state.
func update_from_zombie(zombie_node: Node2D) -> void:
	zombie = zombie_node
	_update_variant()
	_update_state()
	_update_facing()
	_update_frame(delta_from_zombie())


func _update_variant() -> void:
	if zombie == null:
		return
	# Read the variant from the zombie if it exposes it.
	var v = zombie.get("visual_variant")
	if v != null:
		visual_variant = int(v)


func _update_state() -> void:
	if zombie == null:
		return
	previous_state = current_state

	var zombie_dead: bool = false
	var dead_val = zombie.get("_dead")
	if dead_val != null:
		zombie_dead = dead_val

	if zombie_dead:
		_set_state(AnimState.DEATH)
		return

	# Map the zombie's gameplay state to our animation state.
	var zombie_state = zombie.get("state")
	if zombie_state == null:
		return

	var state_val: int = int(zombie_state)
	# Zombie.State enum: IDLE=0, WANDER=1, CHASE=2, ATTACK=3, SEARCH=4, RETURN=5, DEAD=6
	match state_val:
		0:  # IDLE
			_set_state(AnimState.IDLE)
		1:  # WANDER
			_set_state(AnimState.WANDER)
		2:  # CHASE
			_set_state(AnimState.CHASE)
		3:  # ATTACK
			_set_state(AnimState.ATTACK)
		4:  # SEARCH
			_set_state(AnimState.SEARCH)
		5:  # RETURN
			_set_state(AnimState.RETURN)
		6:  # DEAD
			_set_state(AnimState.DEATH)


func _set_state(new_state: AnimState) -> void:
	if new_state == current_state:
		return
	previous_state = current_state
	current_state = new_state
	state_time = 0.0
	blend_progress = 0.0
	anim_frame = 0
	anim_finished = false
	_frame_timer = 0.0
	_on_state_changed(previous_state, new_state)


## Override in subclasses to react to state transitions.
func _on_state_changed(old_state: AnimState, new_state: AnimState) -> void:
	pass


func _update_facing() -> void:
	if zombie == null:
		return
	var dir = zombie.get("facing")
	if dir == null:
		return
	var dir_vec: Vector2 = dir
	if dir_vec.length_squared() < 0.01:
		return
	if absf(dir_vec.x) > absf(dir_vec.y):
		facing = Facing.RIGHT if dir_vec.x > 0 else Facing.LEFT
	else:
		facing = Facing.DOWN if dir_vec.y > 0 else Facing.UP


func _update_frame(delta: float) -> void:
	state_time += delta
	if blend_progress < 1.0:
		blend_progress = minf(1.0, blend_progress + delta / maxf(0.001, blend_duration))

	# One-shot states: ATTACK, HURT — advance once then stop.
	match current_state:
		AnimState.ATTACK, AnimState.HURT:
			_frame_timer += delta * anim_speed
			var frame_duration := 1.0 / base_anim_fps
			if _frame_timer >= frame_duration:
				_frame_timer -= frame_duration
				anim_frame += 1
				if anim_frame >= anim_frame_count:
					anim_frame = anim_frame_count - 1
					anim_finished = true
			return
		AnimState.DEATH:
			if not anim_finished:
				_frame_timer += delta * anim_speed
				var frame_duration := 1.0 / base_anim_fps
				if _frame_timer >= frame_duration:
					_frame_timer -= frame_duration
					anim_frame += 1
					if anim_frame >= anim_frame_count:
						anim_frame = anim_frame_count - 1
						anim_finished = true
			return

	# Looping states: advance and wrap.
	_frame_timer += delta * anim_speed
	var frame_duration := 1.0 / base_anim_fps
	if _frame_timer >= frame_duration:
		_frame_timer -= frame_duration
		anim_frame += 1
		if anim_frame >= anim_frame_count:
			anim_frame = 0


## Returns the zombie's movement speed normalized to 0..1.
func get_normalized_speed() -> float:
	if zombie == null:
		return 0.0
	var velocity = zombie.get("velocity")
	if velocity == null:
		return 0.0
	var chase_speed: float = 64.0
	var cs = zombie.get("chase_speed")
	if cs != null:
		chase_speed = float(cs)
	return clampf(velocity.length() / maxf(1.0, chase_speed), 0.0, 1.0)


## Returns the facing angle in radians.
func facing_angle() -> float:
	match facing:
		Facing.RIGHT: return 0.0
		Facing.DOWN: return PI * 0.5
		Facing.LEFT: return PI
		Facing.UP: return -PI * 0.5
	return 0.0


func delta_from_zombie() -> float:
	return 1.0 / 60.0


## --- drawing entry point ---

## The Zombie's _draw() calls this. Subclasses override to provide visuals.
func draw_zombie() -> void:
	pass


## --- shared drawing helpers ---

func draw_circle_sh(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius, color)


func draw_rounded_rect_sh(rect: Rect2, color: Color, radius: float) -> void:
	draw_rect(rect, color, true)
	draw_circle(Vector2(rect.position.x + radius, rect.position.y + radius), radius, color)
	draw_circle(Vector2(rect.end.x - radius, rect.position.y + radius), radius, color)
	draw_circle(Vector2(rect.position.x + radius, rect.end.y - radius), radius, color)
	draw_circle(Vector2(rect.end.x - radius, rect.end.y - radius), radius, color)


## Returns a human-readable name for a state (for debug).
func state_name(state: AnimState) -> String:
	return AnimState.keys()[state]


func facing_name() -> String:
	return Facing.keys()[facing]
