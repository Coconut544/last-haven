class_name MainMenu
extends CanvasLayer
## Front end: title, pitch and the entry points into the game.
##
## The menu owns no session state. It reports intent through signals and asks
## SaveManager what is actually on disk, so "Continue" can never offer a slot
## that does not exist.

signal new_game_requested()
signal continue_requested(slot: int)
signal quit_requested()

@onready var new_game_button: Button = $Root/Window/Margin/Layout/Buttons/NewGameButton
@onready var continue_button: Button = $Root/Window/Margin/Layout/Buttons/ContinueButton
@onready var quit_button: Button = $Root/Window/Margin/Layout/Buttons/QuitButton
@onready var status_label: Label = $Root/Window/Margin/Layout/Status
@onready var save_label: Label = $Root/Window/Margin/Layout/SaveInfo
@onready var version_label: Label = $Root/Version


func _ready() -> void:
	visible = true
	new_game_button.pressed.connect(func() -> void: new_game_requested.emit())
	continue_button.pressed.connect(_on_continue_pressed)
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	refresh()


## Re-reads the save slots; call after saving or deleting.
func refresh() -> void:
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
	status_label.text = "Continue where you left off, or start a fresh run in a new world seed."


func show_message(message: String) -> void:
	status_label.text = message


func _on_continue_pressed() -> void:
	var slots := SaveManager.list_save_slots()
	if slots.is_empty():
		show_message("Nothing to continue yet.")
		return
	continue_requested.emit(slots[slots.size() - 1])


func _format_duration(seconds: float) -> String:
	var total := int(seconds)
	return "%dm %02ds" % [total / 60, total % 60]
