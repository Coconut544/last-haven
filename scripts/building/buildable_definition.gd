class_name BuildableDefinition
extends Resource
## Data-driven base building piece.
##
## One .tres per buildable in `res://resources/buildings/`. All buildables share
## `Structure.tscn`; the definition decides footprint, cost, health, behaviour
## (solid / door / storage) and visuals.

enum Category { FOUNDATION, STRUCTURE, STORAGE, DEFENSE, UTILITY }
## SOLID: blocks movement. DOOR: blocks movement until opened. STORAGE: contains
## its own inventory and can be looted by its owner. DECORATION: no collision at
## all (floors and other walkable pieces).
enum Behaviour { SOLID, DOOR, STORAGE, DECORATION }

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.STRUCTURE
@export var behaviour: Behaviour = Behaviour.SOLID
@export var cost: Array[Ingredient] = []
@export_range(0.0, 10.0, 0.05) var build_time: float = 0.0
@export_range(1.0, 5000.0, 1.0) var max_health: float = 200.0

@export_group("Placement")
## Footprint in build grid cells (grid cell size is BuildSystem.GRID_SIZE).
@export var occupancy: Vector2i = Vector2i(1, 1)
## Physical collision box used for blocking and build validation.
@export var collision_size: Vector2 = Vector2(30, 30)

@export_group("Storage")
@export_range(0, 100, 1) var storage_capacity: int = 0

@export_group("Visuals (placeholder art)")
@export var primary_color: Color = Color(0.45, 0.33, 0.2)
@export var accent_color: Color = Color(0.3, 0.22, 0.13)
@export_range(0.2, 3.0, 0.1) var height_scale: float = 1.0

@export_group("Scene")
@export_file("*.tscn") var scene_path: String = "res://scenes/world/Structure.tscn"


func cost_dict() -> Dictionary:
	var requirements: Dictionary = {}
	for ingredient: Ingredient in cost:
		requirements[ingredient.item_id] = int(requirements.get(ingredient.item_id, 0)) + ingredient.quantity
	return requirements


func describe_cost() -> String:
	var parts: Array[String] = []
	for ingredient: Ingredient in cost:
		parts.append(ingredient.describe())
	return " + ".join(parts)


func is_storage() -> bool:
	return behaviour == Behaviour.STORAGE


func blocks_movement() -> bool:
	return behaviour == Behaviour.SOLID or behaviour == Behaviour.DOOR


func validate() -> Array[String]:
	var problems: Array[String] = []
	if id.strip_edges().is_empty():
		problems.append("missing id")
	if display_name.strip_edges().is_empty():
		problems.append("missing display_name")
	if cost.is_empty():
		problems.append("has no cost")
	for ingredient: Ingredient in cost:
		if not ItemDatabase.has_item(ingredient.item_id):
			problems.append("unknown cost item '%s'" % ingredient.item_id)
		if ingredient.quantity < 1:
			problems.append("cost item '%s' needs quantity >= 1" % ingredient.item_id)
	if occupancy.x < 1 or occupancy.y < 1:
		problems.append("occupancy must be at least 1x1")
	if collision_size.x <= 0.0 or collision_size.y <= 0.0:
		problems.append("collision_size must be positive")
	if behaviour == Behaviour.STORAGE and storage_capacity < 1:
		problems.append("STORAGE behaviour needs storage_capacity >= 1")
	if scene_path.is_empty():
		problems.append("missing scene_path")
	return problems


func _to_string() -> String:
	return "BuildableDefinition(%s)" % id
