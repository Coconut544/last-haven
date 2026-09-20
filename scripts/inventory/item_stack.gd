class_name ItemStack
extends RefCounted
## One inventory slot's worth of a single item type.
##
## Pure data + a few helpers. It never touches nodes and never mutates an
## inventory, which keeps it cheap to serialize and easy to test.

var item_id: String = ""
var quantity: int = 0
## Remaining durability, -1 when the item does not track durability yet.
var durability: int = -1


static func create(id: String, amount: int = 1) -> ItemStack:
	var stack := ItemStack.new()
	stack.item_id = id
	stack.quantity = maxi(0, amount)
	var definition := ItemDatabase.get_item(id)
	if definition != null and definition.durability > 0:
		stack.durability = definition.durability
	return stack


func is_empty() -> bool:
	return item_id.is_empty() or quantity <= 0


func get_definition() -> ItemDefinition:
	return ItemDatabase.get_item(item_id)


func get_stack_limit() -> int:
	var definition := get_definition()
	if definition == null:
		return 1
	return maxi(1, definition.stack_size)


func get_weight() -> float:
	var definition := get_definition()
	if definition == null:
		return 0.0
	return definition.weight * float(quantity)


func can_merge_with(other: ItemStack) -> bool:
	return other != null and not other.is_empty() and not is_empty() and other.item_id == item_id


func copy() -> ItemStack:
	var stack := ItemStack.new()
	stack.item_id = item_id
	stack.quantity = quantity
	stack.durability = durability
	return stack


func to_dict() -> Dictionary:
	var data := {"item_id": item_id, "quantity": quantity}
	if durability >= 0:
		data["durability"] = durability
	return data


static func from_dict(data: Dictionary) -> ItemStack:
	var stack := ItemStack.new()
	stack.item_id = str(data.get("item_id", ""))
	stack.quantity = int(data.get("quantity", 0))
	stack.durability = int(data.get("durability", -1))
	return stack


func _to_string() -> String:
	return "ItemStack(%dx%s)" % [quantity, item_id]
