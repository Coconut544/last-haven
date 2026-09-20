class_name Recipe
extends Resource
## Data-driven crafting recipe.
##
## One .tres per recipe in `res://resources/recipes/`. Ingredients and output are
## referenced by item id so recipes never depend on script/code changes.

enum Category { TOOLS, WEAPONS, SURVIVAL, CONSTRUCTION, UTILITIES }

@export var id: String = ""
@export var display_name: String = ""
@export var category: Category = Category.TOOLS
@export var output_item_id: String = ""
@export_range(1, 99, 1) var output_quantity: int = 1
@export var ingredients: Array[Ingredient] = []
## Seconds the craft takes. 0 means instant (used for hand crafting).
@export_range(0.0, 60.0, 0.1) var craft_time: float = 0.0
## Empty means "craftable anywhere". A station id (e.g. "workbench") requires the
## player to be near that station - reserved for Phase 2/3, not enforced yet.
@export var required_station: String = ""


## item id -> required quantity.
func required_items() -> Dictionary:
	var requirements: Dictionary = {}
	for ingredient: Ingredient in ingredients:
		requirements[ingredient.item_id] = int(requirements.get(ingredient.item_id, 0)) + ingredient.quantity
	return requirements


func get_output_definition() -> ItemDefinition:
	return ItemDatabase.get_item(output_item_id)


func describe_cost() -> String:
	var parts: Array[String] = []
	for ingredient: Ingredient in ingredients:
		parts.append(ingredient.describe())
	return " + ".join(parts)


func validate() -> Array[String]:
	var problems: Array[String] = []
	if id.strip_edges().is_empty():
		problems.append("missing id")
	if display_name.strip_edges().is_empty():
		problems.append("missing display_name")
	if output_item_id.strip_edges().is_empty():
		problems.append("missing output_item_id")
	elif not ItemDatabase.has_item(output_item_id):
		problems.append("unknown output item '%s'" % output_item_id)
	if output_quantity < 1:
		problems.append("output_quantity must be >= 1")
	if ingredients.is_empty():
		problems.append("has no ingredients")
	for ingredient: Ingredient in ingredients:
		if not ItemDatabase.has_item(ingredient.item_id):
			problems.append("unknown ingredient item '%s'" % ingredient.item_id)
		if ingredient.quantity < 1:
			problems.append("ingredient '%s' needs quantity >= 1" % ingredient.item_id)
	return problems


func _to_string() -> String:
	return "Recipe(%s)" % id
