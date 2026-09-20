class_name InventoryComponent
extends Node
## Attaches an Inventory to any node (player, storage crate, loot bag).
##
## The component owns the data instance and forwards mutations to the global
## event bus so UI can react without knowing which entity changed.

signal inventory_changed(inventory: Inventory)

@export_range(1, 200, 1) var capacity: int = Inventory.DEFAULT_CAPACITY
## Leave empty to derive from the node path at runtime.
@export var inventory_id: String = ""

var inventory: Inventory


func _ready() -> void:
	var resolved_id := inventory_id
	if resolved_id.is_empty():
		resolved_id = "%s:%s" % [get_owner_name(), name]
	inventory = Inventory.new(capacity, resolved_id)
	inventory.changed.connect(_on_inventory_changed)


func get_owner_name() -> String:
	var owner_node := owner if owner != null else get_parent()
	return owner_node.name if owner_node != null else "unknown"


func add_item(item_id: String, quantity: int = 1) -> int:
	if inventory == null:
		return quantity
	return inventory.add_item(item_id, quantity)


func remove_item(item_id: String, quantity: int = 1) -> int:
	if inventory == null:
		return 0
	return inventory.remove_item(item_id, quantity)


func count_item(item_id: String) -> int:
	if inventory == null:
		return 0
	return inventory.count_item(item_id)


func has_tool(tool_type: ItemDefinition.ToolType) -> bool:
	if inventory == null:
		return false
	return inventory.find_tool_slot(tool_type) >= 0


## True when every ingredient of the recipe can be paid for.
func can_afford(cost: Array[Ingredient]) -> bool:
	if inventory == null:
		return false
	return inventory.has_items(_cost_to_dict(cost))


## Consumes a cost and returns false (without side effects) when unaffordable.
func pay_cost(cost: Array[Ingredient]) -> bool:
	if not can_afford(cost):
		return false
	for ingredient: Ingredient in cost:
		inventory.remove_item(ingredient.item_id, ingredient.quantity)
	return true


func refund_cost(cost: Array[Ingredient]) -> void:
	for ingredient: Ingredient in cost:
		inventory.add_item(ingredient.item_id, ingredient.quantity)


## `Inventory.changed` carries no arguments, so this forwards the inventory it
## belongs to instead - listeners need the data, not just the notification.
func _on_inventory_changed() -> void:
	inventory_changed.emit(inventory)
	GameEvents.inventory_changed.emit(inventory)


static func _cost_to_dict(cost: Array[Ingredient]) -> Dictionary:
	var requirements: Dictionary = {}
	for ingredient: Ingredient in cost:
		requirements[ingredient.item_id] = int(requirements.get(ingredient.item_id, 0)) + ingredient.quantity
	return requirements
