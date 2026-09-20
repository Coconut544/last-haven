class_name EquipmentComponent
extends Node
## Manages equipped gear: head, body, backpack, weapon, tool.
##
## Each slot holds an item id (or empty string). Equipment affects gameplay:
## - backpack: adds bonus inventory capacity
## - body/head: adds damage reduction (armor)
## - weapon: adds attack damage bonus
## - tool: no direct stat effect, but controls the active tool type

signal equipment_changed(slot_name: String, item_id: String)

## Equipment slot names used as dictionary keys.
const SLOT_NAMES: Array[String] = ["head", "body", "backpack", "weapon", "tool"]

## Maps slot name -> item id. Empty string means nothing equipped.
var equipped: Dictionary = {}

## Computed stat bonuses (refreshed when equipment changes).
var bonus_capacity: int = 0
var bonus_damage_reduction: float = 0.0
var bonus_attack_damage: float = 0.0


func _ready() -> void:
	for slot: String in SLOT_NAMES:
		equipped[slot] = ""


## Equips an item into the appropriate slot. Returns the previously equipped
## item id (or "" if the slot was empty).
func equip(slot_name: String, item_id: String) -> String:
	if not SLOT_NAMES.has(slot_name):
		return ""
	var previous: String = str(equipped.get(slot_name, ""))
	equipped[slot_name] = item_id
	_recalculate_bonuses()
	equipment_changed.emit(slot_name, item_id)
	return previous


## Unequips a slot. Returns the item that was there.
func unequip(slot_name: String) -> String:
	return equip(slot_name, "")


## Returns the item id in a slot, or "" if empty.
func get_equipped(slot_name: String) -> String:
	return str(equipped.get(slot_name, ""))


## Returns the ItemDefinition of what is equipped in a slot, or null.
func get_equipped_definition(slot_name: String) -> ItemDefinition:
	var item_id := get_equipped(slot_name)
	if item_id.is_empty():
		return null
	return ItemDatabase.get_item(item_id)


## Auto-equips an item into its matching slot. If the slot already has something,
## the old item is returned so it can go back into the inventory.
func auto_equip(item_id: String) -> String:
	var definition := ItemDatabase.get_item(item_id)
	if definition == null:
		return ""
	var slot := _slot_for_definition(definition)
	if slot.is_empty():
		return ""
	return equip(slot, item_id)


## Determines which equipment slot an item belongs to.
func _slot_for_definition(definition: ItemDefinition) -> String:
	if definition == null:
		return ""
	# Use explicit equipment slot if set.
	if definition.equipment_slot != ItemDefinition.EquipmentSlot.NONE:
		return _slot_name_from_enum(definition.equipment_slot)
	# Fallback: derive from category and tool type.
	match definition.category:
		ItemDefinition.Category.WEAPON:
			return "weapon"
		ItemDefinition.Category.TOOL:
			return "tool"
		_:
			if definition.tool_type != ItemDefinition.ToolType.NONE:
				return "tool"
	return ""


func _slot_name_from_enum(slot_enum: ItemDefinition.EquipmentSlot) -> String:
	match slot_enum:
		ItemDefinition.EquipmentSlot.HEAD:
			return "head"
		ItemDefinition.EquipmentSlot.BODY:
			return "body"
		ItemDefinition.EquipmentSlot.BACKPACK:
			return "backpack"
		ItemDefinition.EquipmentSlot.WEAPON:
			return "weapon"
		ItemDefinition.EquipmentSlot.TOOL:
			return "tool"
		_:
			return ""


func _recalculate_bonuses() -> void:
	bonus_capacity = 0
	bonus_damage_reduction = 0.0
	bonus_attack_damage = 0.0
	for slot: String in SLOT_NAMES:
		var item_id := get_equipped(slot)
		if item_id.is_empty():
			continue
		var definition := ItemDatabase.get_item(item_id)
		if definition == null:
			continue
		match slot:
			"backpack":
				# Each backpack adds inventory capacity based on its weight.
				# Heavy backpacks add more slots.
				bonus_capacity += 4 if definition.weight >= 1.0 else 2
			"body":
				# Armor damage reduction: weight-based.
				bonus_damage_reduction += clampf(definition.weight * 0.15, 0.0, 0.35)
			"head":
				# Helmet provides minor damage reduction.
				bonus_damage_reduction += clampf(definition.weight * 0.08, 0.0, 0.15)
			"weapon":
				# Weapon adds its attack damage as a bonus.
				bonus_attack_damage += definition.attack_damage


## Applies damage reduction to an incoming amount. Returns the reduced damage.
func apply_armor(damage: float) -> float:
	return damage * (1.0 - clampf(bonus_damage_reduction, 0.0, 0.5))


## Serialization for save/load.
func serialize_state() -> Dictionary:
	return equipped.duplicate()


func apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	for slot: String in SLOT_NAMES:
		equipped[slot] = str(state.get(slot, ""))
	_recalculate_bonuses()
	for slot: String in SLOT_NAMES:
		equipment_changed.emit(slot, equipped[slot])
