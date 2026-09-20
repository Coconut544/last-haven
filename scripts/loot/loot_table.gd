class_name LootTable
extends Resource
## Data-driven loot table with two roll mechanics:
##
## - `guaranteed_rolls` weighted picks that always award something (unless the
##   table has no positive weights), used for "a crate always contains 2 things";
## - `chance_rolls` independent rolls where every entry can be tested for its own
##   `chance`, used for "rare find" style bonuses.
##
## Both are seeded through the caller-supplied RandomNumberGenerator so loot is
## reproducible in tests and (later) on a server.

@export var id: String = ""
@export var entries: Array[LootEntry] = []
@export_range(0, 20, 1) var guaranteed_rolls: int = 1
@export_range(0, 20, 1) var chance_rolls: int = 0

const MAX_QUANTITY_PER_ITEM := 9999


## Rolls the table. Returns item id -> quantity (may be empty).
func roll(rng: RandomNumberGenerator = null) -> Dictionary:
	var generator := rng
	if generator == null:
		generator = RandomNumberGenerator.new()
		generator.randomize()

	var results: Dictionary = {}
	for _roll in guaranteed_rolls:
		var picked := _pick_weighted(generator)
		if picked != null:
			_award(results, picked, picked.roll_quantity(generator))
	for _roll in chance_rolls:
		for entry: LootEntry in entries:
			if entry.chance > 0.0 and generator.randf() <= entry.chance:
				_award(results, entry, entry.roll_quantity(generator))
	return results


## Same as roll() but as an array of Ingredient, ready for an inventory.
func roll_ingredients(rng: RandomNumberGenerator = null) -> Array[Ingredient]:
	var rolled := roll(rng)
	var ingredients: Array[Ingredient] = []
	for item_id: String in rolled.keys():
		ingredients.append(Ingredient.create(item_id, int(rolled[item_id])))
	return ingredients


func get_total_weight() -> float:
	var total := 0.0
	for entry: LootEntry in entries:
		total += maxf(0.0, entry.weight)
	return total


func _pick_weighted(rng: RandomNumberGenerator) -> LootEntry:
	var total := get_total_weight()
	if total <= 0.0:
		return null
	var target := rng.randf_range(0.0, total)
	var accumulated := 0.0
	for entry: LootEntry in entries:
		var weight := maxf(0.0, entry.weight)
		if weight <= 0.0:
			continue
		accumulated += weight
		if target <= accumulated:
			return entry
	# Floating point safety net.
	for entry: LootEntry in entries:
		if entry.weight > 0.0:
			return entry
	return null


func _award(results: Dictionary, entry: LootEntry, quantity: int) -> void:
	if entry.item_id.is_empty() or quantity <= 0:
		return
	var total := int(results.get(entry.item_id, 0)) + quantity
	results[entry.item_id] = mini(total, MAX_QUANTITY_PER_ITEM)


func validate() -> Array[String]:
	var problems: Array[String] = []
	if id.strip_edges().is_empty():
		problems.append("missing id")
	if entries.is_empty():
		problems.append("has no entries")
	for entry: LootEntry in entries:
		for problem in entry.validate():
			problems.append(problem)
	if guaranteed_rolls > 0 and get_total_weight() <= 0.0:
		problems.append("guaranteed_rolls > 0 but no entry has weight > 0")
	return problems


func _to_string() -> String:
	return "LootTable(%s, %d entries)" % [id, entries.size()]
