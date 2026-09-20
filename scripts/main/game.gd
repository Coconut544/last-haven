extends Node2D
## Session manager for the main scene.
##
## Owns the lifecycle of one play session: front end, world generation, spawning
## the survivor, saving/loading and returning to the menu. It is the only place
## that knows about both the world and the UI, which keeps gameplay systems free
## of session plumbing.

@onready var world: GameWorld = $World
@onready var player: Player = $Player
@onready var hud: Hud = $Hud
@onready var main_menu: MainMenu = $MainMenu

var _session_active: bool = false


func _ready() -> void:
	main_menu.new_game_requested.connect(start_new_game)
	main_menu.continue_requested.connect(continue_game)
	main_menu.quit_requested.connect(quit_game)
	hud.respawn_requested.connect(_on_respawn_requested)
	hud.save_requested.connect(func() -> void: save_game())
	hud.load_requested.connect(func() -> void: load_game())
	hud.quit_to_menu_requested.connect(quit_to_menu)
	hud.setup(player)
	_set_session_active(false)
	main_menu.refresh()


# --- session lifecycle --------------------------------------------------------

func start_new_game() -> void:
	world.generate(0)
	player.reset_for_new_game(world.get_spawn_position())
	_set_session_active(true)
	hud.show_toast("Day 1. Gather wood, stone and fiber before dark.")
	GameEvents.session_started.emit(player)


## Loads the most recent save by default.
func continue_game(slot: int = -1) -> void:
	var target_slot := slot
	if target_slot <= 0:
		var slots := SaveManager.list_save_slots()
		if slots.is_empty():
			main_menu.refresh()
			main_menu.show_message("No survivor log found - start a new run.")
			return
		target_slot = slots[slots.size() - 1]
	var metadata := SaveManager.get_save_metadata(target_slot)
	if not bool(metadata.get("exists", false)):
		main_menu.show_message("Save slot %d could not be read." % target_slot)
		return
	# Rebuild the exact world the save was made in, then restore state on top.
	world.generate(int(metadata.get("seed", 0)))
	player.reset_for_new_game(world.get_spawn_position())
	_set_session_active(true)
	if not SaveManager.load_game(target_slot):
		hud.show_toast("Load failed: %s" % SaveManager.last_error)
		quit_to_menu()
		return
	GameEvents.session_started.emit(player)
	hud.refresh_world_labels()


## Returns false when there is no session or the write failed.
func save_game(slot: int = -1) -> bool:
	if not _session_active:
		return false
	var saved := SaveManager.save_game(slot if slot > 0 else SaveManager.current_slot)
	main_menu.refresh()
	return saved


func load_game(slot: int = -1) -> bool:
	if not _session_active:
		return false
	var target_slot := slot if slot > 0 else SaveManager.current_slot
	var loaded := SaveManager.load_game(target_slot)
	if not loaded:
		hud.show_toast("Load failed: %s" % SaveManager.last_error)
	return loaded


func quit_to_menu() -> void:
	if not _session_active:
		return
	get_tree().paused = false
	_set_session_active(false)
	main_menu.refresh()
	main_menu.show_message("Run ended. Start a new one or continue the last log.")


func quit_game() -> void:
	# Give save systems a chance to finish, then leave.
	get_tree().quit()


func _set_session_active(active: bool) -> void:
	_session_active = active
	world.visible = active
	player.visible = active
	hud.visible = active
	main_menu.visible = not active
	world.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	player.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if not active:
		player.set_move_input(Vector2.ZERO)
		GameEvents.session_ended.emit()


func is_session_active() -> bool:
	return _session_active


func _on_respawn_requested() -> void:
	player.respawn_at(world.get_spawn_position())
	hud.show_toast("You wake up at the camp. Recover your cargo where you fell.")


# --- debug / developer shortcuts ---------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _session_active:
		return
	if event.is_action_pressed("quick_save"):
		save_game()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quick_load"):
		load_game()
		get_viewport().set_input_as_handled()
