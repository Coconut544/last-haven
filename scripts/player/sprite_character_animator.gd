class_name SpriteCharacterAnimator
extends CharacterAnimator
## Sprite-based character renderer with AnimationPlayer support.
##
## This is the template for integrating proper character models and sprite
## animations. When a character model is imported (e.g. from Aseprite, Spine,
## or a 3D render pipeline), this animator drives an AnimationPlayer or
## SpriteFrames to display the correct animation.
##
## Usage:
## 1. Import your character sprite sheet or model
## 2. Create an AnimationPlayer with animations named after AnimState values
## 3. Attach this script as the character's visual node
## 4. The Player script will automatically call update_from_player() each frame
##
## The animation naming convention matches AnimState keys in lowercase:
## "idle", "walk", "run", "sprint", "attack", "hurt", "death",
## "gather", "interact", "equip"
##
## Sprite flip is handled via flip_h based on facing direction.

## The sprite or AnimatedSprite2D that displays the character.
@export var character_sprite: NodePath

## AnimationPlayer that controls frame-based animations.
@export var animation_player: NodePath

## SpriteFrames resource for AnimatedSprite2D usage.
@export var sprite_frames: SpriteFrames

## Speed multiplier for walk/run animations relative to movement speed.
@export var animation_speed_scale: float = 1.0

## Whether to use AnimationPlayer (true) or AnimatedSprite2D (false).
@export var use_animation_player: bool = false

## Height offset for the sprite pivot (pixels from the character's feet).
@export var sprite_pivot_y: float = -16.0

## Equipment overlay sprites — one Sprite2D per equipment slot.
## Created dynamically when equipment changes.
var _equipment_sprites: Dictionary = {}

var _sprite: Node2D = null
var _anim_player: AnimationPlayer = null
var _anim_sprite: AnimatedSprite2D = null


func _ready() -> void:
	super._ready()
	_resolve_nodes()


func _resolve_nodes() -> void:
	if not character_sprite.is_empty():
		_sprite = get_node_or_null(character_sprite)
	if not animation_player.is_empty():
		_anim_player = get_node_or_null(animation_player) as AnimationPlayer
	# If using AnimatedSprite2D, create one if the sprite node is that type.
	if _sprite != null and _sprite is AnimatedSprite2D:
		_anim_sprite = _sprite as AnimatedSprite2D
		use_animation_player = false
	if sprite_frames != null and _anim_sprite != null:
		_anim_sprite.sprite_frames = sprite_frames


func update_from_player(player_node: Node2D) -> void:
	super.update_from_player(player_node)
	_apply_animation()
	_apply_flip()
	_update_equipment_overlays()


func _apply_animation() -> void:
	var anim_name := state_name(current_state).to_lower()

	if use_animation_player and _anim_player != null:
		if _anim_player.has_animation(anim_name):
			if not _anim_player.is_playing() or _anim_player.current_animation != anim_name:
				_anim_player.play(anim_name)
			# Speed scale based on movement.
			_anim_player.speed_scale = _movement_speed_scale()
		return

	if _anim_sprite != null:
		if _anim_sprite.sprite_frames != null and _anim_sprite.sprite_frames.has_animation(anim_name):
			if _anim_sprite.animation != anim_name:
				_anim_sprite.play(anim_name)
			_anim_sprite.speed_scale = _movement_speed_scale()


func _movement_speed_scale() -> float:
	match current_state:
		AnimState.WALK:
			return 0.6 * animation_speed_scale
		AnimState.RUN:
			return 1.0 * animation_speed_scale
		AnimState.SPRINT:
			return 1.4 * animation_speed_scale
		AnimState.IDLE:
			return 0.8 * animation_speed_scale
		_:
			return 1.0 * animation_speed_scale


func _apply_flip() -> void:
	if _anim_sprite != null:
		_anim_sprite.flip_h = (facing == Facing.LEFT)
	elif _sprite != null and _sprite is Sprite2D:
		(_sprite as Sprite2D).flip_h = (facing == Facing.LEFT)


# ===========================================================================
# Equipment overlay system
# ===========================================================================

## Creates or updates visual overlays for equipped items.
## Override this method to provide custom equipment rendering for your model.
func _update_equipment_overlays() -> void:
	for slot_name: String in CharacterAnimator.EQUIPMENT_DRAW_ORDER:
		var item_id := _get_equipment(slot_name)
		if item_id.is_empty():
			_remove_equipment_sprite(slot_name)
			continue
		_ensure_equipment_sprite(slot_name, item_id)


func _ensure_equipment_sprite(slot_name: String, item_id: String) -> void:
	if _equipment_sprites.has(slot_name):
		return
	# Create a placeholder sprite for the equipment slot.
	# In a real implementation, this would load the correct sprite region
	# from the character's texture atlas based on the item_id.
	var sprite := Sprite2D.new()
	sprite.name = "Equip_%s" % slot_name
	sprite.position = _equipment_slot_position(slot_name)
	sprite.z_index = _equipment_slot_z(slot_name)
	add_child(sprite)
	_equipment_sprites[slot_name] = sprite
	# Placeholder: tinted rectangle to show the slot exists.
	var definition := ItemDatabase.get_item(item_id)
	if definition != null:
		sprite.modulate = definition.icon_color
	sprite.texture = _create_placeholder_texture(slot_name)


func _remove_equipment_sprite(slot_name: String) -> void:
	if _equipment_sprites.has(slot_name):
		var sprite = _equipment_sprites[slot_name]
		if sprite != null and is_instance_valid(sprite):
			sprite.queue_free()
		_equipment_sprites.erase(slot_name)


func _equipment_slot_position(slot_name: String) -> Vector2:
	match slot_name:
		"head": return Vector2(0, -22)
		"body": return Vector2(0, -6)
		"backpack": return Vector2(0, -10)
		"weapon": return Vector2(10, -4)
		"tool": return Vector2(10, -4)
	return Vector2.ZERO


func _equipment_slot_z(slot_name: String) -> int:
	match slot_name:
		"backpack": return -1
		"body": return 0
		"head": return 2
		"weapon": return 3
		"tool": return 3
	return 0


func _create_placeholder_texture(slot_name: String) -> Texture2D:
	# Returns null — override with real sprite sheet regions.
	# The tinted Sprite2D with modulate still provides visual feedback.
	return null


## --- override for custom character model drawing ---
## If not using AnimationPlayer or AnimatedSprite2D, override this to draw
## your character model directly (e.g. with _draw() calls to a sprite atlas).
func draw_character() -> void:
	# When using sprite nodes, nothing needs to be drawn manually.
	# The sprite children handle rendering.
	pass
