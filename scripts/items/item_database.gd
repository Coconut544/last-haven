extends Node
## Definition registry (autoload).
##
## Loads every data-driven definition from `res://resources/` once at startup and
## exposes read-only lookups by id. Gameplay code asks this registry for
## definitions instead of loading resources directly, so new content is added by
## dropping a .tres file into the right folder - no code changes.
##
## This autoload owns no mutable game state.

const ITEM_DIR := "res://resources/items"
const RECIPE_DIR := "res://resources/recipes"
const BUILDABLE_DIR := "res://resources/buildings"
const LOOT_DIR := "res://resources/loot"
const RESOURCE_NODE_DIR := "res://resources/nodes"

var _items: Dictionary = {}
var _recipes: Dictionary = {}
var _buildables: Dictionary = {}
var _loot_tables: Dictionary = {}
var _resource_nodes: Dictionary = {}

var _problems: Array[String] = []


func _ready() -> void:
	reload()
	print("[ItemDatabase] %s" % get_summary())


## (Re)loads all definition folders. Safe to call multiple times.
func reload() -> void:
	_items.clear()
	_recipes.clear()
	_buildables.clear()
	_loot_tables.clear()
	_resource_nodes.clear()
	_problems.clear()

	_load_dir(ITEM_DIR, _items, "ItemDefinition")
	_load_dir(RECIPE_DIR, _recipes, "Recipe")
	_load_dir(BUILDABLE_DIR, _buildables, "BuildableDefinition")
	_load_dir(LOOT_DIR, _loot_tables, "LootTable")
	_load_dir(RESOURCE_NODE_DIR, _resource_nodes, "ResourceNodeDefinition")

	_validate_all()
	if not _problems.is_empty():
		for problem in _problems:
			push_error("[ItemDatabase] %s" % problem)


## Scans a folder (including .remap entries in exported builds) for resources
## with an `id` property and indexes them.
func _load_dir(path: String, target: Dictionary, expected_class: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		_problems.append("cannot open definition folder %s" % path)
		return
	for file_name in dir.get_files():
		var name := file_name
		# Exported projects list converted resources as "<name>.remap".
		if name.ends_with(".remap"):
			name = name.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var resource_path := path.path_join(name)
		var resource := load(resource_path)
		if resource == null:
			_problems.append("failed to load %s" % resource_path)
			continue
		if not (resource is Resource) or resource.get("id") == null:
			_problems.append("%s is not a %s (missing 'id')" % [resource_path, expected_class])
			continue
		var id := str(resource.get("id"))
		if id.strip_edges().is_empty():
			_problems.append("%s has an empty id" % resource_path)
			continue
		if target.has(id):
			_problems.append("duplicate %s id '%s' in %s" % [expected_class, id, resource_path])
			continue
		target[id] = resource


func _validate_all() -> void:
	for id: String in _items.keys():
		var definition: ItemDefinition = _items[id]
		for problem in definition.validate():
			_problems.append("item '%s': %s" % [id, problem])
	for id: String in _recipes.keys():
		var recipe: Recipe = _recipes[id]
		for problem in recipe.validate():
			_problems.append("recipe '%s': %s" % [id, problem])
	for id: String in _buildables.keys():
		var buildable: BuildableDefinition = _buildables[id]
		for problem in buildable.validate():
			_problems.append("buildable '%s': %s" % [id, problem])
	for id: String in _resource_nodes.keys():
		var node_definition: ResourceNodeDefinition = _resource_nodes[id]
		for problem in node_definition.validate():
			_problems.append("resource node '%s': %s" % [id, problem])
	for id: String in _loot_tables.keys():
		var table: LootTable = _loot_tables[id]
		for problem in table.validate():
			_problems.append("loot table '%s': %s" % [id, problem])


# --- lookups -----------------------------------------------------------------

func get_item(id: String) -> ItemDefinition:
	return _items.get(id, null)


func has_item(id: String) -> bool:
	return _items.has(id)


func get_item_count() -> int:
	return _items.size()


func get_all_items() -> Array:
	var values := _items.values()
	values.sort_custom(func(a: ItemDefinition, b: ItemDefinition) -> bool: return a.id < b.id)
	return values


func get_recipe(id: String) -> Recipe:
	return _recipes.get(id, null)


func get_recipes() -> Array:
	var values := _recipes.values()
	values.sort_custom(func(a: Recipe, b: Recipe) -> bool:
		if a.category != b.category:
			return a.category < b.category
		return a.display_name < b.display_name)
	return values


func get_recipes_for_category(category: Recipe.Category) -> Array:
	return get_recipes().filter(func(recipe: Recipe) -> bool: return recipe.category == category)


func get_buildable(id: String) -> BuildableDefinition:
	return _buildables.get(id, null)


func get_buildables() -> Array:
	var values := _buildables.values()
	values.sort_custom(func(a: BuildableDefinition, b: BuildableDefinition) -> bool:
		if a.category != b.category:
			return a.category < b.category
		return a.display_name < b.display_name)
	return values


func get_loot_table(id: String) -> LootTable:
	return _loot_tables.get(id, null)


func get_resource_node_definition(id: String) -> ResourceNodeDefinition:
	return _resource_nodes.get(id, null)


func get_resource_node_definitions() -> Array:
	return _resource_nodes.values()


## Problems found while loading, empty when the data set is healthy.
func get_problems() -> Array[String]:
	return _problems.duplicate()


func get_summary() -> String:
	return "items=%d recipes=%d buildables=%d loot_tables=%d resource_nodes=%d problems=%d" % [
		_items.size(), _recipes.size(), _buildables.size(), _loot_tables.size(),
		_resource_nodes.size(), _problems.size(),
	]
