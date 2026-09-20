class_name Interactor
extends Area2D
## Finds the interactable the player is standing next to.
##
## Uses overlapping Area2Ds for cheap detection, then resolves each area to the
## interactable node it belongs to (an ancestor in the "interactable" group) and
## keeps only the nearest one inside `max_reach`. The prompt text comes from the
## target itself via `get_interaction_label()`, so nothing here knows what kinds
## of interactables exist.

signal target_changed(target: Node)

@export_range(16.0, 200.0, 1.0) var max_reach: float = 52.0

var _candidates: Array[Node] = []
var _target: Node = null


func _ready() -> void:
	monitoring = true
	monitorable = false
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func get_target() -> Node:
	return _target


func get_target_label() -> String:
	if _target == null or not is_instance_valid(_target):
		return ""
	if _target.has_method("get_interaction_label"):
		return str(_target.get_interaction_label())
	return _target.name


## Re-evaluates candidates. Called a few times per second by the player.
func refresh() -> void:
	_prune()
	var previous := _target
	_target = _pick_nearest()
	if _target != previous:
		target_changed.emit(_target)
		GameEvents.interactable_changed.emit(_target, get_target_label())


func _prune() -> void:
	var alive: Array[Node] = []
	for candidate in _candidates:
		if candidate != null and is_instance_valid(candidate) and (candidate as Node).is_inside_tree():
			alive.append(candidate)
	_candidates = alive


func _pick_nearest() -> Node:
	var origin_node := get_parent() as Node2D
	var origin := origin_node.global_position if origin_node != null else global_position
	var best: Node = null
	var best_distance := INF
	for candidate in _candidates:
		var candidate_2d := candidate as Node2D
		if candidate_2d == null:
			continue
		var distance := origin.distance_to(candidate_2d.global_position)
		if distance > max_reach:
			continue
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _on_area_entered(area: Area2D) -> void:
	var interactable := _resolve_interactable(area)
	if interactable == null:
		return
	if not _candidates.has(interactable):
		_candidates.append(interactable)
	refresh()


func _on_area_exited(area: Area2D) -> void:
	var interactable := _resolve_interactable(area)
	if interactable == null:
		return
	_candidates.erase(interactable)
	refresh()


## Walks up from the detected area until it finds the interactable owner.
func _resolve_interactable(area: Node) -> Node:
	var node: Node = area
	while node != null:
		if node.is_in_group("interactable"):
			return node
		node = node.get_parent()
	return null
