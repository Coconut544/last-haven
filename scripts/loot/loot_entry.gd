class_name LootEntry
extends Resource
## One possible result inside a LootTable.

@export var item_id: String = ""
@export_range(1, 999, 1) var min_quantity: int = 1
@export_range(1, 999, 1) var max_quantity: int = 1
## Independent probability for chance rolls, 0..1. Weighted picks ignore this.
@export_range(0.0, 1.0, 0.01) var chance: float = 1.0
## Relative weight for guaranteed weighted picks. 0 removes it from picks.
@export_range(0.0, 100.0, 0.1) var weight: float = 1.0
@export var rarity: ItemDefinition.Rarity = ItemDefinition.Rarity.COMMON


static func create(id: String, minimum: int, maximum: int, chance_ratio: float = 1.0) -> LootEntry:
	var entry := LootEntry.new()
	entry.item_id = id
	entry.min_quantity = minimum
	entry.max_quantity = maximum
	entry.chance = chance_ratio
	return entry


func roll_quantity(rng: RandomNumberGenerator) -> int:
	var low := maxi(1, min_quantity)
	var high := maxi(low, max_quantity)
	return rng.randi_range(low, high)


func validate() -> Array[String]:
	var problems: Array[String] = []
	if item_id.strip_edges().is_empty():
		problems.append("loot entry is missing item_id")
	elif not ItemDatabase.has_item(item_id):
		problems.append("loot entry references unknown item '%s'" % item_id)
	if min_quantity < 1:
		problems.append("min_quantity must be >= 1 for '%s'" % item_id)
	if max_quantity < min_quantity:
		problems.append("max_quantity < min_quantity for '%s'" % item_id)
	if chance < 0.0 or chance > 1.0:
		problems.append("chance must be between 0 and 1 for '%s'" % item_id)
	return problems


func _to_string() -> String:
	return "LootEntry(%s %d-%d chance=%.2f weight=%.1f)" % [item_id, min_quantity, max_quantity, chance, weight]
