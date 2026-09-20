class_name PhysicsLayers
extends RefCounted
## Single source of truth for 2D physics layers.
##
## Layer indices are 1-based in the Godot inspector, so `WORLD` (layer 1) is
## bit 0 here. Every scene sets `collision_layer` / `collision_mask` from these
## values, and scripts use them for queries.
##
## Layer 1  world        static geometry and player-built structures
## Layer 2  player       player CharacterBody2D
## Layer 3  enemy        enemy CharacterBody2D
## Layer 4  resource     gatherable static bodies (trees, rocks, ...)
## Layer 5  interactable Area2D pick-up / interact zones
## Layer 6  hitbox       Area2D that deals damage
## Layer 7  hurtbox_player  Area2D that receives damage for the player
## Layer 8  hurtbox_enemy   Area2D that receives damage for enemies

const WORLD := 1 << 0
const PLAYER := 1 << 1
const ENEMY := 1 << 2
const RESOURCE := 1 << 3
const INTERACTABLE := 1 << 4
const HITBOX := 1 << 5
const HURTBOX_PLAYER := 1 << 6
const HURTBOX_ENEMY := 1 << 7

## Layers a walking character collides with.
const BLOCKS_MOVEMENT := WORLD | RESOURCE

## Layers that make a build spot invalid when occupied.
const BUILD_BLOCKERS := WORLD | RESOURCE | PLAYER | ENEMY

## Layers that block line of sight for enemy vision rays.
const SIGHT_BLOCKERS := WORLD | RESOURCE


## Human readable name for a single layer bit, used in debug output.
static func layer_name(layer_bit: int) -> String:
	match layer_bit:
		WORLD: return "world"
		PLAYER: return "player"
		ENEMY: return "enemy"
		RESOURCE: return "resource"
		INTERACTABLE: return "interactable"
		HITBOX: return "hitbox"
		HURTBOX_PLAYER: return "hurtbox_player"
		HURTBOX_ENEMY: return "hurtbox_enemy"
		_: return "unknown(0x%x)" % layer_bit


## Human readable list for a mask, used in debug output.
static func mask_names(mask: int) -> String:
	var names: Array[String] = []
	for bit: int in [WORLD, PLAYER, ENEMY, RESOURCE, INTERACTABLE, HITBOX, HURTBOX_PLAYER, HURTBOX_ENEMY]:
		if mask & bit:
			names.append(layer_name(bit))
	return ", ".join(names)
