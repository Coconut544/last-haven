class_name Hud
extends CanvasLayer
## In-game HUD: vitals, hotbar, touch controls, prompts, panels and toasts.
##
## The HUD is a pure observer of the event bus plus a thin command layer into the
## player (attack, interact, move input, panels). It never mutates game state
## directly, so gameplay keeps working with the HUD hidden (tests run that way).

signal respawn_requested()
signal save_requested()
signal load_requested()
signal quit_to_menu_requested()

const HOTBAR_SLOTS := 5
const TOAST_LIFETIME := 3.0

@onready var health_bar: ProgressBar = $Root/Vitals/HealthBar
@onready var hunger_bar: ProgressBar = $Root/Vitals/HungerBar
@onready var thirst_bar: ProgressBar = $Root/Vitals/ThirstBar
@onready var stamina_bar: ProgressBar = $Root/Vitals/StaminaBar
@onready var clock_label: Label = $Root/Status/ClockLabel
@onready var region_label: Label = $Root/Status/RegionLabel
@onready var prompt_label: Label = $Root/Prompt
@onready var gather_bar: ProgressBar = $Root/GatherBar
@onready var toasts: VBoxContainer = $Root/Toasts
@onready var hotbar: HBoxContainer = $Root/Hotbar
@onready var joystick: TouchStick = $Root/Joystick
@onready var attack_button: Button = $Root/Actions/AttackButton
@onready var interact_button: Button = $Root/Actions/InteractButton
@onready var inventory_button: Button = $Root/Actions/MenuButtons/InventoryButton
@onready var craft_button: Button = $Root/Actions/MenuButtons/CraftButton
@onready var build_button: Button = $Root/Actions/MenuButtons/BuildButton
@onready var build_hud: PanelContainer = $Root/BuildHud
@onready var build_label: Label = $Root/BuildHud/Row/BuildLabel
@onready var confirm_button: Button = $Root/BuildHud/Row/ConfirmButton
@onready var rotate_button: Button = $Root/BuildHud/Row/RotateButton
@onready var cancel_button: Button = $Root/BuildHud/Row/CancelButton
@onready var inventory_panel: InventoryPanel = $Root/InventoryPanel
@onready var crafting_panel: CraftingPanel = $Root/CraftingPanel
@onready var build_panel: BuildPanel = $Root/BuildPanel
@onready var pause_panel: PanelContainer = $Root/PausePanel
@onready var resume_button: Button = $Root/PausePanel/Margin/Layout/ResumeButton
@onready var save_button: Button = $Root/PausePanel/Margin/Layout/SaveButton
@onready var load_button: Button = $Root/PausePanel/Margin/Layout/LoadButton
@onready var quit_button: Button = $Root/PausePanel/Margin/Layout/QuitButton
@onready var death_panel: PanelContainer = $Root/DeathPanel
@onready var death_label: Label = $Root/DeathPanel/Margin/Layout/DeathLabel
@onready var respawn_button: Button = $Root/DeathPanel/Margin/Layout/RespawnButton
@onready var death_quit_button: Button = $Root/DeathPanel/Margin/Layout/QuitButton

var _player: Player
var _hotbar_slots: Array[ItemSlotButton] = []
var _ui_timer: float = 0.0


func _ready() -> void:
	_connect_buttons()
	_connect_events()
	gather_bar.visible = false
	build_hud.visible = false
	pause_panel.visible = false
	death_panel.visible = false
	prompt_label.text = ""
	clock_label.text = "--:--"
	region_label.text = ""


func _connect_buttons() -> void:
	attack_button.pressed.connect(_on_attack_pressed)
	interact_button.pressed.connect(_on_interact_pressed)
	inventory_button.pressed.connect(func() -> void: inventory_panel.toggle())
	craft_button.pressed.connect(func() -> void: crafting_panel.toggle())
	build_button.pressed.connect(func() -> void: build_panel.toggle())
	confirm_button.pressed.connect(_on_confirm_build_pressed)
	rotate_button.pressed.connect(_on_rotate_build_pressed)
	cancel_button.pressed.connect(_on_cancel_build_pressed)
	resume_button.pressed.connect(_resume)
	save_button.pressed.connect(func() -> void: save_requested.emit())
	load_button.pressed.connect(func() -> void: load_requested.emit())
	quit_button.pressed.connect(_on_quit_pressed)
	respawn_button.pressed.connect(_on_respawn_pressed)
	death_quit_button.pressed.connect(_on_quit_pressed)
	joystick.moved.connect(_on_joystick_moved)
	joystick.released.connect(func() -> void: _on_joystick_moved(Vector2.ZERO))
	build_panel.buildable_selected.connect(_on_buildable_selected)


func _connect_events() -> void:
	GameEvents.health_changed.connect(_on_health_changed)
	GameEvents.stat_changed.connect(_on_stat_changed)
	GameEvents.interactable_changed.connect(_on_interactable_changed)
	GameEvents.gathering_started.connect(_on_gathering_started)
	GameEvents.gathering_progress.connect(_on_gathering_progress)
	GameEvents.gathering_cancelled.connect(_on_gathering_cancelled)
	GameEvents.toast_requested.connect(show_toast)
	GameEvents.inventory_changed.connect(_on_inventory_changed)
	GameEvents.hotbar_changed.connect(_on_hotbar_changed)
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.save_completed.connect(func(slot: int) -> void: show_toast("Saved to slot %d" % slot))
	GameEvents.load_completed.connect(func(slot: int) -> void: show_toast("Loaded slot %d" % slot))
	GameEvents.save_failed.connect(func(_slot: int, reason: String) -> void: show_toast("Save failed: %s" % reason))
	GameEvents.time_changed.connect(_on_time_changed)


## Called by the session manager once the player exists.
func setup(player: Player) -> void:
	_player = player
	inventory_panel.setup(player)
	crafting_panel.setup(player)
	build_panel.setup(player)
	if not player.build_system.build_mode_changed.is_connected(_on_build_mode_changed):
		player.build_system.build_mode_changed.connect(_on_build_mode_changed)
	if not player.build_system.placement_failed.is_connected(_on_placement_failed):
		player.build_system.placement_failed.connect(_on_placement_failed)
	_on_health_changed(player.health.current_health, player.health.max_health)
	player.stats.emit_all()
	_refresh_hotbar()
	refresh_world_labels()


func _process(delta: float) -> void:
	_ui_timer -= delta
	if _ui_timer > 0.0:
		return
	_ui_timer = 0.35
	refresh_world_labels()
	_refresh_build_hud()


# --- vitals -------------------------------------------------------------------

func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current


func _on_stat_changed(stat_id: String, value: float, maximum: float) -> void:
	match stat_id:
		"hunger":
			hunger_bar.max_value = maximum
			hunger_bar.value = value
		"thirst":
			thirst_bar.max_value = maximum
			thirst_bar.value = value
		"stamina":
			stamina_bar.max_value = maximum
			stamina_bar.value = value


func _on_time_changed(_time_of_day: float, _day: int) -> void:
	refresh_world_labels()


func refresh_world_labels() -> void:
	var cycle := get_tree().get_first_node_in_group("day_night")
	if cycle != null and cycle.has_method("get_clock_string"):
		clock_label.text = "Day %d  %s" % [cycle.get("day"), cycle.get_clock_string()]
		var is_night: bool = cycle.is_night()
		clock_label.modulate = Color(0.75, 0.8, 1.0) if is_night else Color(1, 1, 1)
	if _player == null:
		return
	var world := get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("get_region_name_at"):
		region_label.text = str(world.get_region_name_at(_player.global_position))


# --- hotbar -------------------------------------------------------------------

func _refresh_hotbar() -> void:
	for slot in _hotbar_slots:
		slot.queue_free()
	_hotbar_slots.clear()
	if _player == null:
		return
	var inventory := _player.get_inventory()
	if inventory == null:
		return
	for index in mini(HOTBAR_SLOTS, inventory.slot_count):
		var button := ItemSlotButton.new()
		button.custom_minimum_size = Vector2(64, 64)
		button.setup(inventory.get_slot(index), index)
		button.set_selected(index == _player.active_slot)
		button.slot_pressed.connect(_on_hotbar_slot_pressed)
		hotbar.add_child(button)
		_hotbar_slots.append(button)


func _on_hotbar_slot_pressed(index: int) -> void:
	if _player == null:
		return
	_player.set_active_slot(index)
	_refresh_hotbar()


func _on_hotbar_changed(index: int) -> void:
	for button in _hotbar_slots:
		button.set_selected(button.slot_index == index)


func _on_inventory_changed(_inventory: Inventory) -> void:
	_refresh_hotbar()


# --- touch controls -----------------------------------------------------------

func _on_joystick_moved(direction: Vector2) -> void:
	if _player == null:
		return
	_player.set_move_input(Vector2.ZERO if get_tree().paused else direction)


func _on_attack_pressed() -> void:
	if _player == null:
		return
	if _player.build_system.is_active():
		_player.build_system.confirm_placement()
		return
	_player.attack()


func _on_interact_pressed() -> void:
	if _player == null:
		return
	if _player.build_system.is_active():
		_player.build_system.confirm_placement()
		return
	_player.interact()


# --- prompts / gathering ------------------------------------------------------

func _on_interactable_changed(target: Node, label: String) -> void:
	if target == null:
		prompt_label.text = ""
		return
	prompt_label.text = "[ Interact ] %s" % label


func _on_gathering_started(target: Node) -> void:
	gather_bar.visible = true
	gather_bar.value = 0.0
	if target != null and target.has_method("get_interaction_label"):
		prompt_label.text = str(target.get_interaction_label())


func _on_gathering_progress(ratio: float) -> void:
	gather_bar.visible = true
	gather_bar.value = clampf(ratio, 0.0, 1.0) * 100.0


func _on_gathering_cancelled() -> void:
	gather_bar.visible = false
	gather_bar.value = 0.0


# --- building -----------------------------------------------------------------

func _on_buildable_selected(definition: BuildableDefinition) -> void:
	if _player == null:
		return
	_player.build_system.enter_build_mode(definition)


func _on_build_mode_changed(active: bool, definition: BuildableDefinition) -> void:
	build_hud.visible = active
	if active and definition != null:
		build_label.text = "Placing: %s" % definition.display_name


func _on_confirm_build_pressed() -> void:
	if _player != null:
		_player.build_system.confirm_placement()


func _on_rotate_build_pressed() -> void:
	if _player != null:
		_player.build_system.rotate_structure()


func _on_cancel_build_pressed() -> void:
	if _player != null:
		_player.build_system.exit_build_mode()


func _on_placement_failed(reason: String) -> void:
	show_toast(reason)


func _refresh_build_hud() -> void:
	if _player == null or not _player.build_system.is_active():
		return
	var definition := _player.build_system.definition
	if definition == null:
		return
	var valid := _player.build_system.can_afford(definition)
	var suffix := "" if valid else "  (missing materials)"
	build_label.text = "Placing: %s%s" % [definition.display_name, suffix]


# --- panels / pause / death ---------------------------------------------------

func _close_open_panels() -> bool:
	var closed_something := false
	if inventory_panel.is_open():
		inventory_panel.close()
		closed_something = true
	if crafting_panel.is_open():
		crafting_panel.close()
		closed_something = true
	if build_panel.is_open():
		build_panel.close()
		closed_something = true
	return closed_something


func toggle_pause() -> void:
	if pause_panel.visible:
		_resume()
	else:
		_pause()


func _pause() -> void:
	if _close_open_panels():
		return
	pause_panel.visible = true
	death_panel.visible = false
	get_tree().paused = true
	_on_joystick_moved(Vector2.ZERO)


func _resume() -> void:
	pause_panel.visible = false
	get_tree().paused = false


func _on_quit_pressed() -> void:
	_resume()
	death_panel.visible = false
	quit_to_menu_requested.emit()


func _on_respawn_pressed() -> void:
	death_panel.visible = false
	get_tree().paused = false
	respawn_requested.emit()


func _on_player_died() -> void:
	var survived := 0.0
	if _player != null:
		survived = _player.stats.survival_seconds
	death_label.text = "You did not make it.\nSurvived %d minutes %02d seconds.\nYour cargo is on the ground where you fell." % [
		int(survived) / 60, int(survived) % 60]
	death_panel.visible = true
	get_tree().paused = true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if not _close_open_panels():
			toggle_pause()
		get_viewport().set_input_as_handled()


# --- feedback -----------------------------------------------------------------

func show_toast(message: String) -> void:
	if message.strip_edges().is_empty():
		return
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.85))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_y", 2)
	toasts.add_child(label)
	var tween := create_tween()
	tween.tween_interval(TOAST_LIFETIME)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)
