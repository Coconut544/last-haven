class_name InventoryPanel
extends Control
## Backpack UI plus the container side used for loot bags and storage crates.
## Also shows equipped gear with slot labels and stat bonuses.
##
## The panel only reads/writes Inventory data through the player and the opened
## container, and it closes itself when the player walks away (the player emits
## container_closed through GameEvents when it does).

signal closed()

@onready var grid: GridContainer = $Window/Margin/Layout/Columns/BackpackColumn/Grid
@onready var summary_label: Label = $Window/Margin/Layout/Columns/BackpackColumn/Summary
@onready var container_column: VBoxContainer = $Window/Margin/Layout/Columns/ContainerColumn
@onready var container_title: Label = $Window/Margin/Layout/Columns/ContainerColumn/Title
@onready var container_grid: GridContainer = $Window/Margin/Layout/Columns/ContainerColumn/Grid
@onready var use_button: Button = $Window/Margin/Layout/Actions/UseButton
@onready var drop_button: Button = $Window/Margin/Layout/Actions/DropButton
@onready var split_button: Button = $Window/Margin/Layout/Actions/SplitButton
@onready var move_button: Button = $Window/Margin/Layout/Actions/MoveButton
@onready var sort_button: Button = $Window/Margin/Layout/Actions/SortButton
@onready var take_all_button: Button = $Window/Margin/Layout/Actions/TakeAllButton
@onready var close_button: Button = $Window/Margin/Layout/Actions/CloseButton

var _player: Player
var _container_inventory: Inventory
var _selected_index: int = -1
var _slots: Array[ItemSlotButton] = []
var _container_slots: Array[ItemSlotButton] = []

## Equipment display (created dynamically).
var _equipment_column: VBoxContainer
var _equipment_labels: Dictionary = {}
var _equipment_stat_label: Label


func _ready() -> void:
	visible = false
	use_button.pressed.connect(_on_use_pressed)
	drop_button.pressed.connect(_on_drop_pressed)
	split_button.pressed.connect(_on_split_pressed)
	move_button.pressed.connect(_on_move_pressed)
	sort_button.pressed.connect(_on_sort_pressed)
	take_all_button.pressed.connect(_on_take_all_pressed)
	close_button.pressed.connect(close)
	GameEvents.container_opened.connect(_on_container_opened)
	GameEvents.container_closed.connect(_on_container_closed)
	GameEvents.inventory_changed.connect(_on_inventory_changed)
	_build_equipment_column()


## Called once by the HUD when the session starts.
func setup(player: Player) -> void:
	_player = player


func open() -> void:
	visible = true
	_rebuild()
	if _selected_index < 0:
		_select_first_occupied()


func close() -> void:
	if not visible:
		return
	visible = false
	_selected_index = -1
	if _container_inventory != null:
		_container_inventory = null
		GameEvents.container_closed.emit()
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func is_open() -> bool:
	return visible


# --- equipment column ---------------------------------------------------------

func _build_equipment_column() -> void:
	_equipment_column = VBoxContainer.new()
	_equipment_column.name = "EquipmentColumn"
	_equipment_column.add_theme_constant_override("separation", 6)
	_equipment_column.custom_minimum_size = Vector2(140, 0)

	var title := Label.new()
	title.text = "Equipment"
	title.add_theme_font_size_override("font_size", 20)
	_equipment_column.add_child(title)

	var slot_names: Array[String] = ["head", "body", "backpack", "weapon", "tool"]
	for slot_name: String in slot_names:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_equipment_column.add_child(row)

		var label := Label.new()
		label.text = slot_name.capitalize() + ":"
		label.add_theme_font_size_override("font_size", 13)
		label.custom_minimum_size = Vector2(65, 0)
		row.add_child(label)

		var value_label := Label.new()
		value_label.text = "Empty"
		value_label.add_theme_font_size_override("font_size", 13)
		value_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.5))
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(value_label)
		_equipment_labels[slot_name] = value_label

	# Stat bonuses summary.
	_equipment_stat_label = Label.new()
	_equipment_stat_label.add_theme_font_size_override("font_size", 12)
	_equipment_stat_label.add_theme_color_override("font_color", Color(0.45, 0.55, 0.40))
	_equipment_stat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_equipment_column.add_child(_equipment_stat_label)

	# Insert equipment column into the layout.
	var columns := get_node_or_null("Window/Margin/Layout/Columns")
	if columns != null:
		columns.add_child(_equipment_column)
		# Move equipment column to the right side (after backpack, before container).
		columns.move_child(_equipment_column, 1)


func _update_equipment_display() -> void:
	if _player == null or _player.equipment_component == null:
		return
	var ec := _player.equipment_component
	for slot_name: String in EquipmentComponent.SLOT_NAMES:
		var label: Label = _equipment_labels.get(slot_name, null)
		if label == null:
			continue
		var item_id := ec.get_equipped(slot_name)
		if item_id.is_empty():
			label.text = "Empty"
			label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		else:
			var def := ItemDatabase.get_item(item_id)
			label.text = def.display_name if def != null else item_id
			label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))

	# Show stat bonuses.
	var bonus_text := ""
	if ec.bonus_capacity > 0:
		bonus_text += " +%d capacity" % ec.bonus_capacity
	if ec.bonus_damage_reduction > 0.0:
		bonus_text += "  -%.0f%% damage" % (ec.bonus_damage_reduction * 100.0)
	if ec.bonus_attack_damage > 0.0:
		bonus_text += "  +%.0f attack" % ec.bonus_attack_damage
	_equipment_stat_label.text = bonus_text if not bonus_text.is_empty() else "No bonuses"


# --- building the grids -------------------------------------------------------

func _rebuild() -> void:
	_build_player_grid()
	_build_container_grid()
	_update_summary()
	_update_action_buttons()
	_update_equipment_display()


func _build_player_grid() -> void:
	var inventory := _get_inventory()
	for slot in _slots:
		slot.queue_free()
	_slots.clear()
	if inventory == null:
		return
	grid.columns = 5
	for index in inventory.slot_count:
		var button := ItemSlotButton.new()
		button.setup(inventory.get_slot(index), index)
		button.set_selected(index == _selected_index)
		button.slot_pressed.connect(_on_slot_pressed)
		grid.add_child(button)
		_slots.append(button)


func _build_container_grid() -> void:
	for slot in _container_slots:
		slot.queue_free()
	_container_slots.clear()
	var has_container := _container_inventory != null
	container_column.visible = has_container
	if not has_container:
		return
	container_grid.columns = 4
	for index in _container_inventory.slot_count:
		var button := ItemSlotButton.new()
		button.setup(_container_inventory.get_slot(index), index)
		button.slot_pressed.connect(_on_container_slot_pressed)
		container_grid.add_child(button)
		_container_slots.append(button)


func _update_summary() -> void:
	var inventory := _get_inventory()
	if inventory == null:
		summary_label.text = "No inventory"
		return
	var bonus := 0
	if _player != null and _player.equipment_component != null:
		bonus = _player.equipment_component.bonus_capacity
	var extra := " (+%d equipped)" % bonus if bonus > 0 else ""
	summary_label.text = "%d/%d%s slots used - %.1f kg" % [
		_count_used_slots(inventory), inventory.slot_count, extra, inventory.total_weight()]


func _count_used_slots(inventory: Inventory) -> int:
	var used := 0
	for index in inventory.slot_count:
		if inventory.get_slot(index) != null:
			used += 1
	return used


func _update_action_buttons() -> void:
	var inventory := _get_inventory()
	var stack: ItemStack = null
	if inventory != null and inventory.is_valid_index(_selected_index):
		stack = inventory.get_slot(_selected_index)
	var has_selection := stack != null
	use_button.disabled = not has_selection
	drop_button.disabled = not has_selection
	split_button.disabled = not has_selection or stack.quantity < 2
	move_button.disabled = not has_selection or _container_inventory == null
	take_all_button.disabled = _container_inventory == null
	sort_button.disabled = inventory == null


# --- selection ----------------------------------------------------------------

func _select_first_occupied() -> void:
	var inventory := _get_inventory()
	if inventory == null:
		return
	for index in inventory.slot_count:
		if inventory.get_slot(index) != null:
			_set_selection(index)
			return


func _set_selection(index: int) -> void:
	_selected_index = index
	for button in _slots:
		button.set_selected(button.slot_index == index)
	_update_action_buttons()


func _on_slot_pressed(index: int) -> void:
	_set_selection(index)


func _on_container_slot_pressed(index: int) -> void:
	if _container_inventory == null or _player == null:
		return
	var target := _player.get_inventory()
	if target == null:
		return
	# transfer_to returns whatever did not fit, so anything left over means the
	# backpack filled up mid-transfer.
	var leftover := _container_inventory.transfer_to(target, index)
	if leftover > 0:
		GameEvents.toast_requested.emit("Backpack full: %d items stay in the container." % leftover)
	_rebuild()


# --- actions ------------------------------------------------------------------

func _on_use_pressed() -> void:
	if _player == null or _selected_index < 0:
		return
	_player.use_slot(_selected_index)
	_rebuild()


func _on_drop_pressed() -> void:
	if _player == null or _selected_index < 0:
		return
	_player.drop_slot(_selected_index)
	_rebuild()


func _on_split_pressed() -> void:
	var inventory := _get_inventory()
	if inventory == null:
		return
	inventory.split_stack(_selected_index)
	_rebuild()


func _on_move_pressed() -> void:
	var inventory := _get_inventory()
	if inventory == null or _container_inventory == null:
		return
	inventory.transfer_to(_container_inventory, _selected_index)
	_rebuild()


func _on_sort_pressed() -> void:
	var inventory := _get_inventory()
	if inventory == null:
		return
	inventory.sort()
	_selected_index = -1
	_rebuild()


func _on_take_all_pressed() -> void:
	if _container_inventory == null or _player == null:
		return
	var target := _player.get_inventory()
	if target == null:
		return
	var totals := _container_inventory.count_all_items()
	var leftover_total := 0
	for item_id: String in totals.keys():
		var leftover := target.add_item(item_id, int(totals[item_id]))
		if leftover > 0:
			_container_inventory.remove_item(item_id, int(totals[item_id]) - leftover)
			leftover_total += leftover
		else:
			_container_inventory.remove_item(item_id, int(totals[item_id]))
	if leftover_total > 0:
		GameEvents.toast_requested.emit("Backpack full: %d items left behind." % leftover_total)
	_rebuild()


# --- events -------------------------------------------------------------------

func _on_container_opened(inventory: Inventory, title: String) -> void:
	_container_inventory = inventory
	container_title.text = title if not title.is_empty() else "Container"
	open()
	_rebuild()


func _on_container_closed() -> void:
	if _container_inventory == null:
		return
	_container_inventory = null
	container_column.visible = false
	_rebuild()


func _on_inventory_changed(_inventory: Inventory) -> void:
	if not visible:
		return
	# Refresh slot contents without rebuilding the whole grid on every change.
	for button in _slots:
		var inventory := _get_inventory()
		button.setup(inventory.get_slot(button.slot_index) if inventory != null else null, button.slot_index)
	for button in _container_slots:
		if _container_inventory != null:
			button.setup(_container_inventory.get_slot(button.slot_index), button.slot_index)
	_update_summary()
	_update_action_buttons()
	_update_equipment_display()


func _get_inventory() -> Inventory:
	return _player.get_inventory() if _player != null else null


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
