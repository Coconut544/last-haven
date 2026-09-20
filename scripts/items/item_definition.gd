class_name ItemDefinition
extends Resource
## Data-driven item definition.
##
## One .tres file per item lives in `res://resources/items/`. Systems look items
## up by `id` through the ItemDatabase autoload; nothing about the inventory,
## crafting or UI layers is hard-coded per item.

enum Category { MATERIAL, TOOL, WEAPON, CONSUMABLE, FOOD, BUILDING, MISC }
enum ToolType { NONE, AXE, PICKAXE, KNIFE, HAMMER }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, EXCEPTIONAL }

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.MATERIAL
@export var rarity: Rarity = Rarity.COMMON

@export_group("Stacking")
## Maximum units per inventory slot. 1 means the item never stacks.
@export_range(1, 999, 1) var stack_size: int = 20
## Mass of a single unit in kg. Used for future weight limits.
@export_range(0.0, 500.0, 0.01) var weight: float = 0.2

@export_group("Placeholder visuals")
## Until sprite art exists, item icons are drawn as coloured chips with a glyph.
@export var icon_color: Color = Color(0.6, 0.6, 0.6)
@export var icon_glyph: String = "?"

@export_group("Tool")
@export var tool_type: ToolType = ToolType.NONE
## Gathering speed multiplier when this tool matches a resource's preferred tool.
@export_range(1.0, 10.0, 0.1) var tool_power: float = 1.0
## Durability in uses. 0 means the item never wears out (prototype behaviour).
@export_range(0, 10000, 1) var durability: int = 0

@export_group("Combat")
@export_range(0.0, 200.0, 0.5) var attack_damage: float = 0.0
@export_range(0.1, 5.0, 0.05) var attack_cooldown: float = 0.6
@export_range(8.0, 200.0, 1.0) var attack_range: float = 34.0

@export_group("Consumable")
@export_range(0.0, 100.0, 0.5) var health_restore: float = 0.0
@export_range(0.0, 100.0, 0.5) var food_restore: float = 0.0
@export_range(0.0, 100.0, 0.5) var water_restore: float = 0.0


func is_tool() -> bool:
	return tool_type != ToolType.NONE


func is_stackable() -> bool:
	return stack_size > 1


func is_consumable() -> bool:
	return health_restore > 0.0 or food_restore > 0.0 or water_restore > 0.0


func body_slot_name() -> String:
	## Category name used by the inventory UI filter/columns.
	return Category.keys()[category].capitalize()


func validate() -> Array[String]:
	## Returns a list of problems; empty means the definition is usable.
	var problems: Array[String] = []
	if id.strip_edges().is_empty():
		problems.append("missing id")
	if display_name.strip_edges().is_empty():
		problems.append("missing display_name")
	if stack_size < 1:
		problems.append("stack_size must be >= 1")
	if weight < 0.0:
		problems.append("weight must be >= 0")
	if category == Category.TOOL and tool_type == ToolType.NONE:
		problems.append("category TOOL requires a tool_type")
	if attack_damage > 0.0 and attack_range <= 0.0:
		problems.append("weapon needs attack_range > 0")
	return problems


func _to_string() -> String:
	return "ItemDefinition(%s)" % id
