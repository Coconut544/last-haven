class_name MainMenu
extends CanvasLayer
## Front end: title, pitch and the entry points into the game.
##
## The menu owns no session state. It reports intent through signals and asks
## SaveManager what is actually on disk, so slots can be selected, created,
## or deleted with real information.

signal new_game_requested()
signal continue_requested(slot: int)
signal quit_requested()

@onready var new_game_button: Button = $Root/Window/Margin/Layout/Buttons/NewGameButton
@onready var continue_button: Button = $Root/Window/Margin/Layout/Buttons/ContinueButton
@onready var quit_button: Button = $Root/Window/Margin/Layout/Buttons/QuitButton
@onready var status_label: Label = $Root/Window/Margin/Layout/Status
@onready var save_label: Label = $Root/Window/Margin/Layout/SaveInfo
@onready var version_label: Label = $Root/Version

## Slot selection UI elements (created dynamically).
var _slot_list: VBoxContainer
var _slot_buttons: Array[Button] = []
var _selected_slot: int = -1
var _delete_button: Button
var _confirm_delete_panel: PanelContainer
var _confirm_delete_yes: Button
var _confirm_delete_no: Button


func _ready() -> void:
	visible = true
	new_game_button.pressed.connect(_on_new_game_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	_build_slot_ui()
	refresh()


## Re-reads the save slots; call after saving or deleting.
func refresh() -> void:
	_refresh_slot_list()
	var slots := SaveManager.list_save_slots()
	continue_button.disabled = slots.is_empty()
	if slots.is_empty():
		save_label.text = "No survivor log found."
		status_label.text = "New to Last Haven? Gather wood, fiber and stone, craft an axe, then put a wall between you and the night."
		return
	var slot: int = slots[slots.size() - 1]
	var metadata := SaveManager.get_save_metadata(slot)
	if not bool(metadata.get("exists", false)):
		save_label.text = "Save slot %d is unreadable." % slot
		return
	save_label.text = "Slot %d - day %d - survived %s - saved %s" % [
		slot,
		int(metadata.get("day", 1)),
		_format_duration(float(metadata.get("survived_seconds", 0.0))),
		str(metadata.get("saved_at", "?")),
	]
	status_label.text = "Select a survivor log below, or start a fresh run in a new world seed."


func show_message(message: String) -> void:
	status_label.text = message


func _on_new_game_pressed() -> void:
	new_game_requested.emit()


func _on_continue_pressed() -> void:
	var slots := SaveManager.list_save_slots()
	if slots.is_empty():
		show_message("Nothing to continue yet.")
		return
	# Use selected slot if one is picked, otherwise use the most recent.
	var target_slot := _selected_slot if _selected_slot > 0 else slots[slots.size() - 1]
	continue_requested.emit(target_slot)


# --- save slot UI -----------------------------------------------------------

func _build_slot_ui() -> void:
	# We'll inject the slot list dynamically below the save info label.
	# The actual VBoxContainer is created in _ready via deferred call.
	# For now, the main menu layout is defined by the scene; we add the
	# delete confirmation popup.
	_confirm_delete_panel = PanelContainer.new()
	_confirm_delete_panel.name = "ConfirmDelete"
	_confirm_delete_panel.visible = false
	_confirm_delete_panel.anchor_left = 0.5
	_confirm_delete_panel.anchor_top = 0.5
	_confirm_delete_panel.anchor_right = 0.5
	_confirm_delete_panel.anchor_bottom = 0.5
	_confirm_delete_panel.offset_left = -160
	_confirm_delete_panel.offset_top = -60
	_confirm_delete_panel.offset_right = 160
	_confirm_delete_panel.offset_bottom = 60
	var confirm_style := StyleBoxFlat.new()
	confirm_style.bg_color = Color(0.08, 0.09, 0.08, 0.96)
	confirm_style.set_corner_radius_all(8)
	confirm_style.set_border_width_all(2)
	confirm_style.border_color = Color(0.75, 0.30, 0.20, 0.8)
	confirm_style.content_margin_left = 16
	confirm_style.content_margin_top = 12
	confirm_style.content_margin_right = 16
	confirm_style.content_margin_bottom = 12
	_confirm_delete_panel.add_theme_stylebox_override("panel", confirm_style)
	add_child(_confirm_delete_panel)

	var confirm_vbox := VBoxContainer.new()
	confirm_vbox.add_theme_constant_override("separation", 10)
	_confirm_delete_panel.add_child(confirm_vbox)

	var confirm_label := Label.new()
	confirm_label.text = "Delete this survivor log?\nThis cannot be undone."
	confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_label.add_theme_font_size_override("font_size", 16)
	confirm_vbox.add_child(confirm_label)

	var confirm_hbox := HBoxContainer.new()
	confirm_hbox.add_theme_constant_override("separation", 12)
	confirm_vbox.add_child(confirm_hbox)

	_confirm_delete_yes = Button.new()
	_confirm_delete_yes.text = "Delete"
	_confirm_delete_yes.custom_minimum_size = Vector2(100, 36)
	_confirm_delete_yes.pressed.connect(_on_confirm_delete)
	confirm_hbox.add_child(_confirm_delete_yes)

	_confirm_delete_no = Button.new()
	_confirm_delete_no.text = "Cancel"
	_confirm_delete_no.custom_minimum_size = Vector2(100, 36)
	_confirm_delete_no.pressed.connect(func() -> void: _confirm_delete_panel.visible = false)
	confirm_hbox.add_child(_confirm_delete_no)


func _refresh_slot_list() -> void:
	# Remove old buttons.
	for button in _slot_buttons:
		if is_instance_valid(button):
			button.queue_free()
	_slot_buttons.clear()

	var slots := SaveManager.list_save_slots()
	if slots.is_empty():
		return

	# Find or create a container for the slot buttons in the layout.
	var layout := $Root/Window/Margin/Layout as VBoxContainer
	if layout == null:
		return

	# Create a scroll container for slots if we haven't already.
	var slot_container_name := "SlotContainer"
	var existing := layout.get_node_or_null(slot_container_name)
	if existing != null:
		existing.queue_free()

	var scroll := ScrollContainer.new()
	scroll.name = slot_container_name
	scroll.custom_minimum_size = Vector2(0, 120)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Insert before the Buttons row if it exists.
	var buttons_node := layout.get_node_or_null("Buttons")
	if buttons_node != null:
		layout.add_child(scroll)
		layout.move_child(scroll, buttons_node.get_index())
	else:
		layout.add_child(scroll)

	_slot_list = VBoxContainer.new()
	_slot_list.name = "SlotList"
	_slot_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_slot_list)

	# Show most recent first.
	var reversed := slots.duplicate()
	reversed.reverse()
	for slot: int in reversed:
		var metadata := SaveManager.get_save_metadata(slot)
		if not bool(metadata.get("exists", false)):
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 44)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "  Slot %d  |  Day %d  |  Survived %s  |  %s" % [
			slot,
			int(metadata.get("day", 1)),
			_format_duration(float(metadata.get("survived_seconds", 0.0))),
			str(metadata.get("saved_at", "?")),
		]
		button.pressed.connect(func() -> void: _select_slot(slot))
		_slot_list.add_child(button)
		_slot_buttons.append(button)

	# Add a delete button row.
	_delete_button = Button.new()
	_delete_button.text = "  Delete Selected"
	_delete_button.custom_minimum_size = Vector2(0, 36)
	_delete_button.disabled = true
	_delete_button.pressed.connect(_on_delete_pressed)
	_slot_list.add_child(_delete_button)


func _select_slot(slot: int) -> void:
	_selected_slot = slot
	_delete_button.disabled = false
	# Highlight the selected button.
	for button in _slot_buttons:
		var is_selected := button.text.begins_with("  Slot %d " % slot)
		if is_selected:
			button.modulate = Color(1.0, 0.9, 0.6)
		else:
			button.modulate = Color(0.85, 0.85, 0.85)
	# Update the info label.
	var metadata := SaveManager.get_save_metadata(slot)
	if bool(metadata.get("exists", false)):
		save_label.text = "Slot %d - day %d - survived %s - saved %s" % [
			slot,
			int(metadata.get("day", 1)),
			_format_duration(float(metadata.get("survived_seconds", 0.0))),
			str(metadata.get("saved_at", "?")),
		]
		status_label.text = "Press Continue to resume this survivor, or select another log."


func _on_delete_pressed() -> void:
	if _selected_slot <= 0:
		return
	_confirm_delete_panel.visible = true


func _on_confirm_delete() -> void:
	if _selected_slot <= 0:
		return
	SaveManager.delete_save(_selected_slot)
	_selected_slot = -1
	_delete_button.disabled = true
	_confirm_delete_panel.visible = false
	refresh()
	show_message("Survivor log deleted.")


func _format_duration(seconds: float) -> String:
	var total := int(seconds)
	return "%dm %02ds" % [total / 60, total % 60]
