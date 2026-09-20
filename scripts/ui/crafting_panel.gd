class_name CraftingPanel
extends Control
## Crafting UI.
##
## Recipe rows are generated from the ItemDatabase registry, and affordability
## comes from CraftingSystem, so this file never names a specific item or recipe.

signal closed()

@onready var category_row: HBoxContainer = $Window/Margin/Layout/CategoryRow
@onready var recipe_list: VBoxContainer = $Window/Margin/Layout/Scroll/RecipeList
@onready var detail_label: Label = $Window/Margin/Layout/Detail
@onready var close_button: Button = $Window/Margin/Layout/CloseButton

var _player: Player
var _category: int = -1
var _rows: Array[Button] = []
var _category_buttons: Array[Button] = []


func _ready() -> void:
	visible = false
	close_button.pressed.connect(close)
	GameEvents.inventory_changed.connect(_on_inventory_changed)
	_build_category_buttons()


func setup(player: Player) -> void:
	_player = player


func open() -> void:
	visible = true
	_rebuild()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func is_open() -> bool:
	return visible


func _build_category_buttons() -> void:
	var all_button := Button.new()
	all_button.text = "All"
	all_button.custom_minimum_size = Vector2(84, 44)
	all_button.pressed.connect(func() -> void: _set_category(-1))
	category_row.add_child(all_button)
	_category_buttons.append(all_button)
	for index in Recipe.Category.size():
		var button := Button.new()
		button.text = Recipe.Category.keys()[index].capitalize()
		button.custom_minimum_size = Vector2(96, 44)
		button.pressed.connect(func() -> void: _set_category(index))
		category_row.add_child(button)
		_category_buttons.append(button)


func _set_category(category: int) -> void:
	_category = category
	_rebuild()


func _rebuild() -> void:
	for row in _rows:
		row.queue_free()
	_rows.clear()
	if _player == null:
		return
	var recipes := ItemDatabase.get_recipes()
	for recipe: Recipe in recipes:
		if _category >= 0 and recipe.category != _category:
			continue
		var row := _make_row(recipe)
		recipe_list.add_child(row)
		_rows.append(row)
	for index in _category_buttons.size():
		var is_active := (index - 1) == _category
		_category_buttons[index].modulate = Color(1, 1, 1) if is_active else Color(0.75, 0.75, 0.75)
	_update_detail()


func _make_row(recipe: Recipe) -> Button:
	var inventory := _player.get_inventory()
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 46)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.focus_mode = Control.FOCUS_NONE
	row.clip_text = true
	var output := recipe.get_output_definition()
	var output_name := output.display_name if output != null else recipe.output_item_id
	row.text = "%s  -  %s" % [output_name, recipe.describe_cost()]
	var missing := CraftingSystem.get_missing(recipe, inventory)
	if missing.is_empty():
		row.disabled = not CraftingSystem.can_craft(recipe, inventory)
		if row.disabled and CraftingSystem.is_inventory_full_for(recipe, inventory):
			row.text += "   (inventory full)"
	else:
		var parts: Array[String] = []
		for item_id: String in missing.keys():
			parts.append("%d x %s" % [int(missing[item_id]), item_id])
		row.text += "   (missing %s)" % ", ".join(parts)
		row.modulate = Color(0.8, 0.7, 0.7)
	row.tooltip_text = output.description if output != null else ""
	row.pressed.connect(func() -> void: _craft(recipe))
	row.mouse_entered.connect(func() -> void: _show_detail(recipe))
	return row


func _craft(recipe: Recipe) -> void:
	if _player == null:
		return
	var inventory := _player.get_inventory()
	if not CraftingSystem.can_craft(recipe, inventory):
		GameEvents.toast_requested.emit("Not enough materials for %s." % recipe.display_name)
		return
	if CraftingSystem.craft(recipe, inventory):
		GameEvents.item_crafted.emit(recipe)
		GameEvents.toast_requested.emit("Crafted %s" % recipe.display_name)
	else:
		GameEvents.toast_requested.emit("Crafting failed: %s" % recipe.display_name)
	_rebuild()


func _show_detail(recipe: Recipe) -> void:
	detail_label.text = "%s - %s" % [recipe.display_name, recipe.describe_cost()]


func _update_detail() -> void:
	detail_label.text = "Select a recipe. Rows stay disabled until you have the materials."


func _on_inventory_changed(_inventory: Inventory) -> void:
	if visible:
		_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
