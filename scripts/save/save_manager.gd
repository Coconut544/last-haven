extends Node
## Local persistence (autoload).
##
## Saves the current session to a JSON slot under `user://saves/`. The manager
## owns no gameplay data: it asks the player and the world for their state via
## the `serialize_state()` / `apply_state(data)` convention, so new systems can
## join the save file without this file knowing about them.
##
## The same convention is what a server-authoritative backend will call later
## (see ARCHITECTURE.md, multiplayer section).
##
## Write path: data is written to `<slot>.json.tmp` and then renamed, so a crash
## or battery pull mid-write cannot leave a half-written save behind.

const SAVE_DIR := "user://saves"
const SAVE_VERSION := 1
const SAVE_FILE_TEMPLATE := "slot_%d.json"
const MAX_SLOTS := 3

## Slot used by the quick save / quick load actions.
var current_slot: int = 1
## Human readable reason for the last failure.
var last_error: String = ""


func _ready() -> void:
	var error := DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("[SaveManager] Cannot create %s (error %d)" % [SAVE_DIR, error])


func get_save_path(slot: int) -> String:
	return SAVE_DIR.path_join(SAVE_FILE_TEMPLATE % slot)


func has_save(slot: int = 1) -> bool:
	return FileAccess.file_exists(get_save_path(slot))


func list_save_slots() -> Array[int]:
	var slots: Array[int] = []
	for slot in range(1, MAX_SLOTS + 1):
		if has_save(slot):
			slots.append(slot)
	return slots


# --- saving -------------------------------------------------------------------

func save_game(slot: int = 1) -> bool:
	var player := get_player()
	var world := get_world()
	if player == null:
		return _fail(slot, "no player in the scene tree")

	var data := {
		"version": SAVE_VERSION,
		"game_version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"seed": world.get_world_seed() if world != null else 0,
		"player": _serialize_node(player),
		"world": _serialize_node(world),
	}
	if not write_slot_data(slot, data):
		return _fail(slot, last_error)
	current_slot = slot
	GameEvents.save_completed.emit(slot)
	return true


## Low level write, exposed for tests and tools.
func write_slot_data(slot: int, data: Dictionary) -> bool:
	var path := get_save_path(slot)
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		last_error = "cannot write %s (error %d)" % [tmp_path, FileAccess.get_open_error()]
		push_error("[SaveManager] %s" % last_error)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	var dir := DirAccess.open(SAVE_DIR)
	if dir != null and dir.rename(tmp_path.get_file(), path.get_file()) == OK:
		return true
	# Rename can fail on some platforms/filesystems; fall back to a direct write
	# so the player never silently loses progress.
	push_warning("[SaveManager] Atomic rename failed for slot %d, writing directly" % slot)
	var direct := FileAccess.open(path, FileAccess.WRITE)
	if direct == null:
		last_error = "cannot write %s (error %d)" % [path, FileAccess.get_open_error()]
		push_error("[SaveManager] %s" % last_error)
		return false
	direct.store_string(JSON.stringify(data, "\t"))
	direct.close()
	return true


# --- loading ------------------------------------------------------------------

func read_slot(slot: int = 1) -> Dictionary:
	var path := get_save_path(slot)
	if not FileAccess.file_exists(path):
		last_error = "save slot %d does not exist" % slot
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "cannot read %s (error %d)" % [path, FileAccess.get_open_error()]
		push_error("[SaveManager] %s" % last_error)
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		last_error = "save slot %d is corrupt" % slot
		push_error("[SaveManager] %s" % last_error)
		return {}
	return parsed


func load_game(slot: int = 1) -> bool:
	var data := read_slot(slot)
	if data.is_empty():
		return _fail(slot, last_error)
	var save_version := int(data.get("version", 0))
	if save_version > SAVE_VERSION:
		return _fail(slot, "save was written by a newer version (%d > %d)" % [save_version, SAVE_VERSION])
	var player := get_player()
	var world := get_world()
	if player == null or world == null:
		return _fail(slot, "cannot load without an active world and player")
	# World first: it rebuilds structures and resource state the player may
	# immediately interact with. Then the player state on top of it.
	_apply_state(world, data.get("world", {}))
	_apply_state(player, data.get("player", {}))
	current_slot = slot
	GameEvents.load_completed.emit(slot)
	return true


## Metadata for the main menu, safe to call when the slot is empty or corrupt.
func get_save_metadata(slot: int = 1) -> Dictionary:
	var data := read_slot(slot)
	if data.is_empty():
		return {"exists": false, "corrupt": has_save(slot), "slot": slot}
	var player: Dictionary = data.get("player", {})
	var stats: Dictionary = player.get("stats", {})
	return {
		"exists": true,
		"corrupt": false,
		"slot": slot,
		"version": int(data.get("version", 0)),
		"game_version": str(data.get("game_version", "?")),
		"saved_at": str(data.get("saved_at", "?")),
		"saved_at_unix": int(data.get("saved_at_unix", 0)),
		"seed": int(data.get("seed", 0)),
		"survived_seconds": float(stats.get("survival_seconds", 0.0)),
		"day": int(data.get("world", {}).get("day", 1)),
	}


func delete_save(slot: int = 1) -> bool:
	if not has_save(slot):
		return false
	var error := DirAccess.remove_absolute(get_save_path(slot))
	if error != OK:
		last_error = "cannot delete slot %d (error %d)" % [slot, error]
		push_error("[SaveManager] %s" % last_error)
		return false
	return true


# --- helpers ------------------------------------------------------------------

func get_player() -> Node:
	return get_tree().get_first_node_in_group("player")


func get_world() -> Node:
	return get_tree().get_first_node_in_group("world")


func _serialize_node(node: Node) -> Dictionary:
	if node == null:
		return {}
	if not node.has_method("serialize_state"):
		push_warning("[SaveManager] %s cannot be saved (no serialize_state())" % node.get_path())
		return {}
	var state: Dictionary = node.serialize_state()
	return state


func _apply_state(node: Node, state: Dictionary) -> void:
	if state.is_empty():
		push_warning("[SaveManager] Nothing to restore for %s" % node.get_path())
		return
	if not node.has_method("apply_state"):
		push_warning("[SaveManager] %s cannot be restored (no apply_state())" % node.get_path())
		return
	node.apply_state(state)


func _fail(slot: int, reason: String) -> bool:
	last_error = reason
	push_warning("[SaveManager] %s" % reason)
	GameEvents.save_failed.emit(slot, reason)
	return false
