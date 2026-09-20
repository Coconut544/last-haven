class_name LootBag
extends Area2D
## Dropped loot on the ground (zombie drops, spilled inventory, storage spill).
##
## It is a container, not a pickup: interacting opens the transfer UI so the
## player chooses what to take, which keeps one code path for "any inventory
## that is not yours" (loot bags, base storage crates).

signal looted(bag: LootBag)

@export var despawn_seconds: float = 0.0

@onready var inventory_component: InventoryComponent = $Inventory

var _lifetime_left: float = 0.0


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("streamed")
	add_to_group("loot_bag")
	_lifetime_left = despawn_seconds
	set_process(despawn_seconds > 0.0)
	queue_redraw()


## Fills the bag. Must be called after the node is inside the tree, otherwise
## InventoryComponent has not created its Inventory yet.
func setup(ingredients: Array[Ingredient]) -> void:
	if not is_inside_tree():
		await ready
	for ingredient: Ingredient in ingredients:
		inventory_component.add_item(ingredient.item_id, ingredient.quantity)


func get_inventory() -> Inventory:
	return inventory_component.inventory if inventory_component != null else null


func is_empty() -> bool:
	var inventory := get_inventory()
	return inventory == null or inventory.count_all_items().is_empty()


func get_interaction_label() -> String:
	var inventory := get_inventory()
	var kinds := 0
	if inventory != null:
		kinds = inventory.count_all_items().size()
	return "Search Bag (%d)" % kinds


func interact(actor: Node) -> bool:
	var inventory := get_inventory()
	if inventory == null or inventory.count_all_items().is_empty():
		GameEvents.toast_requested.emit("The bag is empty.")
		return false
	GameEvents.container_opened.emit(inventory, "Loot Bag")
	GameEvents.interaction_used.emit(self)
	return true


func _process(delta: float) -> void:
	if despawn_seconds <= 0.0:
		return
	_lifetime_left -= delta
	if _lifetime_left <= 0.0:
		queue_free()


# --- streaming ----------------------------------------------------------------

func set_streamed_active(active: bool) -> void:
	visible = active
	monitoring = active


# --- persistence --------------------------------------------------------------

func serialize_state() -> Dictionary:
	var inventory := get_inventory()
	return {
		"position": [position.x, position.y],
		"inventory": inventory.to_dict() if inventory != null else {},
		"lifetime_left": _lifetime_left,
	}


func apply_state(state: Dictionary) -> void:
	var position_data: Array = state.get("position", [])
	if position_data.size() == 2:
		position = Vector2(float(position_data[0]), float(position_data[1]))
	_lifetime_left = float(state.get("lifetime_left", 0.0))
	var inventory := get_inventory()
	if inventory != null:
		inventory.load_from_dict(state.get("inventory", {}))


# --- placeholder visuals ------------------------------------------------------

func _draw() -> void:
	draw_circle(Vector2.ZERO, 11.0, Color(0.28, 0.24, 0.18))
	draw_circle(Vector2.ZERO, 11.0, Color(0.62, 0.5, 0.28), false, 2.0)
	draw_rect(Rect2(-7.0, -3.0, 14.0, 6.0), Color(0.45, 0.36, 0.2), true)
