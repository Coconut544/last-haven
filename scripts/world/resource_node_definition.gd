class_name ResourceNodeDefinition
extends Resource
## Data-driven gatherable world node (tree, rock, bush, scrap pile).
##
## One .tres per node type in `res://resources/nodes/`. The world spawner picks
## definitions per region; ResourceNode.tscn renders and harvests any of them.

## Placeholder visuals until sprite art exists. Drawn procedurally by
## ResourceNode so the prototype ships without binary assets.
enum Visual { TREE, ROCK, BUSH, PILE }

@export var id: String = ""
@export var display_name: String = ""
@export var visual: Visual = Visual.TREE
@export var primary_color: Color = Color(0.24, 0.4, 0.2)
@export var accent_color: Color = Color(0.45, 0.33, 0.2)
@export_range(0.5, 3.0, 0.05) var visual_scale: float = 1.0

@export_group("Gathering")
## Number of harvests before the node is depleted.
@export_range(1, 50, 1) var max_uses: int = 3
@export_range(0.1, 30.0, 0.1) var gather_time: float = 1.6
## Tool that gathers this node efficiently.
@export var preferred_tool: ItemDefinition.ToolType = ItemDefinition.ToolType.NONE
## Speed multiplier when the preferred tool is equipped.
@export_range(1.0, 5.0, 0.1) var tool_speed_multiplier: float = 2.5
## Yield multiplier when the preferred tool is equipped.
@export_range(1.0, 5.0, 0.1) var tool_yield_multiplier: float = 1.5
## Items granted per harvest (before the tool multiplier).
@export var yields: Array[Ingredient] = []
## Optional extra loot rolled on the final harvest.
@export var bonus_loot_table_id: String = ""

@export_group("Lifecycle")
## Seconds until a depleted node comes back. 0 means it never respawns.
@export_range(0.0, 900.0, 1.0) var respawn_time: float = 90.0
@export_range(4.0, 64.0, 1.0) var collision_radius: float = 12.0
## Verb shown in the interaction prompt.
@export var interaction_verb: String = "Gather"


func get_definition() -> ResourceNodeDefinition:
	return self


func get_tool_label() -> String:
	if preferred_tool == ItemDefinition.ToolType.NONE:
		return ""
	return ItemDefinition.ToolType.keys()[preferred_tool].capitalize()


func get_interaction_label() -> String:
	var tool_label := get_tool_label()
	if tool_label.is_empty():
		return "%s %s" % [interaction_verb, display_name]
	return "%s %s (%s)" % [interaction_verb, display_name, tool_label]


## Items granted per harvest, scaled when the matching tool is used.
func roll_yields(rng: RandomNumberGenerator, tool_matched: bool) -> Array[Ingredient]:
	var results: Array[Ingredient] = []
	for ingredient: Ingredient in yields:
		var amount := maxi(1, ingredient.quantity)
		if tool_matched:
			amount = maxi(amount, int(round(float(amount) * tool_yield_multiplier)))
		results.append(Ingredient.create(ingredient.item_id, amount))
	return results


func get_gather_duration(tool_matched: bool) -> float:
	if tool_matched:
		return maxf(0.15, gather_time / tool_speed_multiplier)
	return gather_time


func validate() -> Array[String]:
	var problems: Array[String] = []
	if id.strip_edges().is_empty():
		problems.append("missing id")
	if display_name.strip_edges().is_empty():
		problems.append("missing display_name")
	if yields.is_empty():
		problems.append("has no yields")
	for ingredient: Ingredient in yields:
		if not ItemDatabase.has_item(ingredient.item_id):
			problems.append("unknown yield item '%s'" % ingredient.item_id)
	if preferred_tool != ItemDefinition.ToolType.NONE and tool_speed_multiplier < 1.0:
		problems.append("tool_speed_multiplier must be >= 1")
	if not bonus_loot_table_id.is_empty() and ItemDatabase.get_loot_table(bonus_loot_table_id) == null:
		problems.append("unknown bonus loot table '%s'" % bonus_loot_table_id)
	return problems


func _to_string() -> String:
	return "ResourceNodeDefinition(%s)" % id
