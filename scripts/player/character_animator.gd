class_name CharacterAnimator
extends Node2D
## Extensible character rendering system for the player.
##
## This is the base class that defines the animation state machine and the
## interface that gameplay code (Player) uses to drive visuals. Concrete
## implementations handle HOW the character is drawn — procedurally, with
## sprites, or with a full animation player — without the Player script
## knowing which method is in use.
##
## Design goals:
## - Swap character models/animations without touching Player.gd
## - Equipment layers render on top of the base character
## - Animation states are explicit and auditable
## - The default (ProceduralCharacterAnimator) preserves the current _draw()
##   art while being replaceable by a sprite-based implementation

## All animation states the player character can be in.
## The state machine ensures only one state is active at a time.
enum AnimState {
	IDLE,
	WALK,
	RUN,
	SPRINT,
	ATTACK,
	HURT,
	DEATH,
	GATHER,
	INTERACT,
	EQUIP,
	## Transient: a brief flash when entering a new state.
	FALL,
}

## Direction the character is facing (4-way: UP, DOWN, LEFT, RIGHT).
## Derived from the player's facing vector but snapped to cardinal for
## cleaner sprite selection and animation blending.
enum Facing { DOWN, UP, LEFT, RIGHT }

## Current animation state — read by gameplay code, written by the animator.
var current_state: AnimState = AnimState.IDLE
var previous_state: AnimState = AnimState.IDLE
var facing: Facing = Facing.DOWN

## How long the current state has been active (seconds).
var state_time: float = 0.0

## Blending factor between previous and current state (0..1).
## Used by sprite-based animators for smooth transitions.
var blend_progress: float = 1.0

## Duration of the blend transition between states.
@export var blend_duration: float = 0.15

## Frame index within the current animation (for sprite sheet playback).
var anim_frame: int = 0

## Total frames in the current animation.
var anim_frame_count: int = 1

## Speed multiplier for animation playback (1.0 = normal).
var anim_speed: float = 1.0

## Whether the animation has completed one cycle (for one-shot states).
var anim_finished: bool = false

## Time accumulator for frame advance.
var _frame_timer: float = 0.0

## Pixels per second for the current animation's frame rate.
@export var base_anim_fps: float = 8.0

## The player node that owns this animator (set by Player._ready).
var player: Node2D = null

## Equipment layer definitions: slot name -> draw order.
## Lower order numbers are drawn first (behind the character).
const EQUIPMENT_DRAW_ORDER: Array[String] = ["backpack", "body", "head", "weapon", "tool"]

## Equipment slot -> cached visual data for the current frame.
var _equipment_cache: Dictionary = {}


func _ready() -> void:
	pass


## Called by Player every physics frame to update the animator's state.
## Subclasses must call super() or implement their own update logic.
func update_from_player(player_node: Node2D) -> void:
	player = player_node
	_update_state()
	_update_facing()
	_update_frame(delta_from_player())


func _update_state() -> void:
	if player == null:
		return
	var previous := current_state
	previous_state = previous

	if player.is_dead:
		_set_state(AnimState.DEATH)
		return

	# Check for active actions that override movement states.
	var attack_flash_val: float = float(player.get("_attack_flash"))
	if attack_flash_val > 0.0:
		_set_state(AnimState.ATTACK)
		return
	var gathering_val = player.get("_gathering")
	if gathering_val != null and gathering_val:
		_set_state(AnimState.GATHER)
		return

	# Movement-based states.
	var velocity: Vector2 = player.get("velocity")
	var speed := velocity.length()
	var is_sprinting: bool = false
	if player.has_method("_wants_to_sprint"):
		is_sprinting = player.call("_wants_to_sprint", velocity)

	if speed < 5.0:
		_set_state(AnimState.IDLE)
	elif is_sprinting or speed > 160.0:
		_set_state(AnimState.SPRINT)
	elif speed > 80.0:
		_set_state(AnimState.RUN)
	else:
		_set_state(AnimState.WALK)


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
	if player == null:
		return
	var dir: Vector2 = player.get("facing")
	if dir.length_squared() < 0.01:
		return
	# Snap to the dominant cardinal direction.
	if absf(dir.x) > absf(dir.y):
		facing = Facing.RIGHT if dir.x > 0 else Facing.LEFT
	else:
		facing = Facing.DOWN if dir.y > 0 else Facing.UP


func _update_frame(delta: float) -> void:
	state_time += delta
	# Blend progress for transitions.
	if blend_progress < 1.0:
		blend_progress = minf(1.0, blend_progress + delta / maxf(0.001, blend_duration))

	# One-shot states: ATTACK, HURT, EQUIP, FALL — advance once then stop.
	match current_state:
		AnimState.ATTACK, AnimState.HURT, AnimState.EQUIP, AnimState.FALL:
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
			# Death plays once and stays on the last frame.
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


## Returns the movement speed normalized to a 0..1 range for animation blending.
func get_normalized_speed() -> float:
	if player == null:
		return 0.0
	var velocity: Vector2 = player.get("velocity")
	var run_speed: float = 178.0
	if player.get("run_speed") != null:
		run_speed = float(player.get("run_speed"))
	return clampf(velocity.length() / maxf(1.0, run_speed), 0.0, 1.0)


## Converts the player's facing vector to our Facing enum.
func vector_to_facing(dir: Vector2) -> Facing:
	if dir.length_squared() < 0.01:
		return Facing.DOWN
	if absf(dir.x) > absf(dir.y):
		return Facing.RIGHT if dir.x > 0 else Facing.LEFT
	return Facing.DOWN if dir.y > 0 else Facing.UP


## Returns the rotation angle (radians) for the facing direction.
func facing_angle() -> float:
	match facing:
		Facing.RIGHT: return 0.0
		Facing.DOWN: return PI * 0.5
		Facing.LEFT: return PI
		Facing.UP: return -PI * 0.5
	return 0.0


func delta_from_player() -> float:
	return 1.0 / 60.0  # Approximate; overridden by Player.


## --- equipment layer drawing (override in subclasses if needed) ---

## Returns the equipment item id for a given slot, or "" if empty.
func _get_equipment(slot: String) -> String:
	if player == null:
		return ""
	var equipment_comp = player.get("equipment_component")
	if equipment_comp == null:
		return ""
	return str(equipment_comp.get_equipped(slot))


## Returns the icon color for an equipment item (used by procedural fallback).
func _equipment_color(slot: String, fallback: Color) -> Color:
	var item_id := _get_equipment(slot)
	if item_id.is_empty():
		return fallback
	var definition := ItemDatabase.get_item(item_id)
	return definition.icon_color if definition != null else fallback


## --- drawing entry point ---

## The Player's _draw() calls this. Subclasses override to provide visuals.
func draw_character() -> void:
	# Base class draws nothing — subclasses override.
	pass


## Draws the attack flash arc (shared by all implementations).
func draw_attack_flash(reach: float, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var dir := Vector2.RIGHT.rotated(facing_angle())
	var start_angle := dir.angle() - 0.8
	var end_angle := dir.angle() + 0.8
	var points := PackedVector2Array()
	for step in 10:
		var a := lerpf(start_angle, end_angle, float(step) / 9.0)
		points.append(Vector2.RIGHT.rotated(a) * (reach + 4.0))
	draw_polyline(points, Color(1.0, 0.95, 0.8, alpha), 2.5)
	var arc_points := PackedVector2Array([Vector2.ZERO])
	for step in 12:
		var a := lerpf(start_angle, end_angle, float(step) / 11.0)
		arc_points.append(Vector2.RIGHT.rotated(a) * (reach - 4.0))
	draw_colored_polygon(arc_points, Color(1.0, 0.92, 0.75, alpha * 0.25))


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
