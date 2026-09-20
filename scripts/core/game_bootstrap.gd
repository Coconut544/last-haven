extends Node
## Startup bootstrap (autoload).
##
## Responsibilities:
## - guarantee every gameplay input action exists, even if the project settings
##   input map is damaged or a partial checkout is opened;
## - apply a small set of runtime settings that are cheaper to express in code
##   than in project.godot (frame cap for mobile battery life);
## - log one boot line so runtime issues are easy to correlate with a build.
##
## It deliberately owns no game state.

## Actions that gameplay code reads. The value is the deadzone used if the
## action has to be created from scratch.
const REQUIRED_ACTIONS: Dictionary = {
	"move_left": 0.2,
	"move_right": 0.2,
	"move_up": 0.2,
	"move_down": 0.2,
	"run": 0.5,
	"attack": 0.5,
	"interact": 0.5,
	"toggle_inventory": 0.5,
	"toggle_crafting": 0.5,
	"toggle_build": 0.5,
	"rotate_structure": 0.5,
	"quick_save": 0.5,
	"quick_load": 0.5,
}

## Fallback keyboard bindings (physical keycodes) used only when an action is
## missing entirely. The authoritative input map lives in project.godot /
## the editor, these exist so the game is never unplayable.
const FALLBACK_KEYS: Dictionary = {
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"move_up": [KEY_W],
	"move_down": [KEY_S],
	"run": [KEY_SHIFT],
	"attack": [KEY_SPACE],
	"interact": [KEY_E],
	"toggle_inventory": [KEY_I],
	"toggle_crafting": [KEY_C],
	"toggle_build": [KEY_B],
	"rotate_structure": [KEY_R],
	"quick_save": [KEY_F5],
	"quick_load": [KEY_F9],
}


func _ready() -> void:
	_ensure_input_actions()
	_apply_runtime_settings()
	# Item counts are logged by ItemDatabase itself: autoload order means this
	# script runs before the definition registry has loaded anything.
	print("[LastHaven] boot engine=%s platform=%s" % [
		Engine.get_version_info().get("string", "unknown"),
		OS.get_name(),
	])


## Creates missing actions and fills in empty ones with fallback keys.
## Existing user bindings are never overwritten.
func _ensure_input_actions() -> void:
	var created: Array[String] = []
	for action: String in REQUIRED_ACTIONS.keys():
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, float(REQUIRED_ACTIONS[action]))
		_add_fallback_events(action)
		created.append(action)

	var empty: Array[String] = []
	for action: String in REQUIRED_ACTIONS.keys():
		if InputMap.action_get_events(action).is_empty():
			_add_fallback_events(action)
			empty.append(action)

	if not created.is_empty():
		push_warning("[GameBootstrap] Missing input actions were created: %s" % [created])
	if not empty.is_empty():
		push_warning("[GameBootstrap] Input actions had no events, fallback keys applied: %s" % [empty])


func _add_fallback_events(action: String) -> void:
	var keys: Array = FALLBACK_KEYS.get(action, [])
	for keycode: int in keys:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		InputMap.action_add_event(action, event)


func _apply_runtime_settings() -> void:
	# 60 FPS is plenty for a top-down survival game and halves GPU/battery cost
	# compared to running uncapped on mobile.
	Engine.max_fps = 60
