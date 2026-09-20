class_name Ingredient
extends Resource
## A quantity of an item.
##
## Reused everywhere a system needs "item + amount": crafting inputs, resource
## yields, building costs and loot results. Referencing items by id (instead of
## by resource reference) keeps data files free of cyclic dependencies and makes
## save games trivial to serialize.

@export var item_id: String = ""
@export_range(1, 999, 1) var quantity: int = 1


static func create(id: String, amount: int = 1) -> Ingredient:
	var ingredient := Ingredient.new()
	ingredient.item_id = id
	ingredient.quantity = amount
	return ingredient


func to_dict() -> Dictionary:
	return {"item_id": item_id, "quantity": quantity}


static func from_dict(data: Dictionary) -> Ingredient:
	return create(str(data.get("item_id", "")), int(data.get("quantity", 1)))


func describe() -> String:
	var definition := ItemDatabase.get_item(item_id)
	var label := definition.display_name if definition != null else item_id
	return "%d x %s" % [quantity, label]


func _to_string() -> String:
	return "Ingredient(%dx%s)" % [quantity, item_id]
