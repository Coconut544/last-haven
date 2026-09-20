class_name BuildPanel
extends Control
## Build menu: lists every buildable from the data set with its cost and whether
## the player can currently afford it. Selecting one hands the definition to the
## player's BuildSystem, which then handles the ghost and placement.

signal closed()
signal buildable_selected(definition: BuildableDefinition)

@onready var list: VBoxContainer = $Window/Margin/Layout/Scroll/BuildableList
@onready var detail_label: Label = $Window/Margin/Layout/Detail
@onready var close_button: Button = $Window/Margin/Layout/CloseButton

var _player: Player
var _rows: Array[Button] = []


func _ready() -> void:
	visible = false
	close_button.pressed.connect(close)
	GameEvents.inventory_changed.connect(_on_inventory_changed)


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


func _rebuild() -> void:
	for row in _rows:
		row.queue_free()
	_rows.clear()
	if _player == null:
		return
	for definition: BuildableDefinition in ItemDatabase.get_buildables():
		var row := _make_row(definition)
		list.add_child(row)
		_rows.append(row)
	detail_label.text = "Pick a piece to place. Drag the stick to move, then confirm on the HUD."


func _make_row(definition: BuildableDefinition) -> Button:
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 48)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.focus_mode = Control.FOCUS_NONE
	row.clip_text = true
	row.text = "%s  -  %s" % [definition.display_name, definition.describe_cost()]
	row.tooltip_text = definition.description
	var affordable := _player.build_system.can_afford(definition)
	if not affordable:
		row.modulate = Color(0.8, 0.7, 0.7)
		var missing := _player.build_system.get_missing_cost(definition)
		var parts: Array[String] = []
		for item_id: String in missing.keys():
			parts.append("%d x %s" % [int(missing[item_id]), item_id])
		if not parts.is_empty():
			row.text += "   (missing %s)" % ", ".join(parts)
	row.pressed.connect(func() -> void: _select(definition))
	row.mouse_entered.connect(func() -> void: detail_label.text = definition.description)
	return row


func _select(definition: BuildableDefinition) -> void:
	buildable_selected.emit(definition)
	close()


func _on_inventory_changed(_inventory: Inventory) -> void:
	if visible:
		_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
