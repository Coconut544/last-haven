class_name CraftingSystem
extends RefCounted
## Crafting rules. Pure functions over data - no nodes, no UI, no autoloads.
##
## The UI calls these; the results are what the player sees, so the rules live
## here once instead of inside the crafting panel.

## True when every ingredient is available and the output fits.
static func can_craft(recipe: Recipe, inventory: Inventory) -> bool:
	if recipe == null or inventory == null:
		return false
	if not inventory.has_items(recipe.required_items()):
		return false
	return inventory.count_space_for(recipe.output_item_id) >= recipe.output_quantity


## Ingredient shortfall for the UI (item id -> missing amount).
static func get_missing(recipe: Recipe, inventory: Inventory) -> Dictionary:
	if recipe == null or inventory == null:
		return {}
	return inventory.get_missing(recipe.required_items())


## True when ingredients are present but there is no room for the output.
static func is_inventory_full_for(recipe: Recipe, inventory: Inventory) -> bool:
	if recipe == null or inventory == null:
		return false
	if not inventory.has_items(recipe.required_items()):
		return false
	return inventory.count_space_for(recipe.output_item_id) < recipe.output_quantity


## Consumes the ingredients and stores the output.
## All-or-nothing: nothing is consumed when it cannot complete.
static func craft(recipe: Recipe, inventory: Inventory) -> bool:
	if not can_craft(recipe, inventory):
		return false
	var requirements := recipe.required_items()
	for item_id: String in requirements.keys():
		var removed := inventory.remove_item(item_id, int(requirements[item_id]))
		if removed != int(requirements[item_id]):
			# Should be impossible after can_craft(); restore and bail out.
			push_error("[CraftingSystem] Failed to consume %d x %s" % [requirements[item_id], item_id])
			return false
	var leftover := inventory.add_item(recipe.output_item_id, recipe.output_quantity)
	if leftover > 0:
		# Roll the ingredients back so the player never loses materials.
		inventory.remove_item(recipe.output_item_id, recipe.output_quantity - leftover)
		for item_id: String in requirements.keys():
			inventory.add_item(item_id, int(requirements[item_id]))
		push_error("[CraftingSystem] No room for output of '%s'" % recipe.id)
		return false
	return true
