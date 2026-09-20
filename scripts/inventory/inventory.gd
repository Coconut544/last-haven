class_name Inventory
extends RefCounted
## Slot based inventory. Pure data + logic, no nodes and no UI.
##
## Entities own one through an InventoryComponent. Containers (loot bags, base
## storage) own one through the same component so both share this code path and
## serialize identically.
##
## Multiplayer note: this is the authoritative model that will later live on the
## server unchanged; only the owner of the data decides who may mutate it.

signal changed()
signal slot_changed(index: int)

const DEFAULT_CAPACITY := 20

## Stable identity used by save files and (later) server sync.
var inventory_id: String = ""
var slot_count: int = DEFAULT_CAPACITY
## Typed array of slot contents; empty slots are `null`.
var slots: Array[ItemStack] = []


func _init(capacity: int = DEFAULT_CAPACITY, id: String = "") -> void:
	inventory_id = id
	slot_count = maxi(1, capacity)
	slots.resize(slot_count)


func is_valid_index(index: int) -> bool:
	return index >= 0 and index < slot_count


func get_slot(index: int) -> ItemStack:
	if not is_valid_index(index):
		return null
	return slots[index]


## Adds up to `quantity` items and returns the amount that did NOT fit.
func add_item(item_id: String, quantity: int = 1) -> int:
	if quantity <= 0:
		return 0
	var definition := ItemDatabase.get_item(item_id)
	if definition == null:
		push_error("[Inventory] Unknown item id '%s'" % item_id)
		return quantity

	var remaining := quantity
	var stack_limit := maxi(1, definition.stack_size)

	# 1) Top up existing stacks first so partial stacks fill before new slots.
	for index in slot_count:
		if remaining <= 0:
			break
		var stack := slots[index]
		if stack == null or stack.item_id != item_id:
			continue
		var space := stack_limit - stack.quantity
		if space <= 0:
			continue
		var moved := mini(space, remaining)
		stack.quantity += moved
		remaining -= moved
		slot_changed.emit(index)

	# 2) Then fill empty slots.
	for index in slot_count:
		if remaining <= 0:
			break
		if slots[index] != null:
			continue
		var moved := mini(stack_limit, remaining)
		slots[index] = ItemStack.create(item_id, moved)
		remaining -= moved
		slot_changed.emit(index)

	if remaining != quantity:
		changed.emit()
	return remaining


## How many of `item_id` would fit right now.
func count_space_for(item_id: String) -> int:
	var definition := ItemDatabase.get_item(item_id)
	if definition == null:
		return 0
	var stack_limit := maxi(1, definition.stack_size)
	var space := 0
	for index in slot_count:
		var stack := slots[index]
		if stack == null:
			space += stack_limit
		elif stack.item_id == item_id:
			space += maxi(0, stack_limit - stack.quantity)
	return space


func count_item(item_id: String) -> int:
	var total := 0
	for stack in slots:
		if stack != null and stack.item_id == item_id:
			total += stack.quantity
	return total


## Item id -> total quantity, used by crafting checks and the save system.
func count_all_items() -> Dictionary:
	var totals: Dictionary = {}
	for stack in slots:
		if stack == null or stack.is_empty():
			continue
		totals[stack.item_id] = int(totals.get(stack.item_id, 0)) + stack.quantity
	return totals


## `requirements` maps item id -> required quantity.
func has_items(requirements: Dictionary) -> bool:
	for item_id: String in requirements.keys():
		if count_item(item_id) < int(requirements[item_id]):
			return false
	return true


## Returns the shortfall per item id; empty dictionary means "can afford".
func get_missing(requirements: Dictionary) -> Dictionary:
	var missing: Dictionary = {}
	for item_id: String in requirements.keys():
		var short := int(requirements[item_id]) - count_item(item_id)
		if short > 0:
			missing[item_id] = short
	return missing


## Removes up to `quantity` units. Returns how many were actually removed.
func remove_item(item_id: String, quantity: int = 1) -> int:
	if quantity <= 0:
		return 0
	var remaining := quantity
	for index in range(slot_count - 1, -1, -1):
		if remaining <= 0:
			break
		var stack := slots[index]
		if stack == null or stack.item_id != item_id:
			continue
		var taken := mini(stack.quantity, remaining)
		stack.quantity -= taken
		remaining -= taken
		if stack.quantity <= 0:
			slots[index] = null
		slot_changed.emit(index)
	var removed := quantity - remaining
	if removed > 0:
		changed.emit()
	return removed


## Removes a whole or partial stack from one slot and returns it.
func take_from_slot(index: int, quantity: int = -1) -> ItemStack:
	var stack := get_slot(index)
	if stack == null:
		return null
	var amount := stack.quantity if quantity < 0 else mini(quantity, stack.quantity)
	if amount <= 0:
		return null
	var taken := stack.copy()
	taken.quantity = amount
	stack.quantity -= amount
	if stack.quantity <= 0:
		slots[index] = null
	slot_changed.emit(index)
	changed.emit()
	return taken


func move_or_swap(from_index: int, to_index: int) -> bool:
	if not is_valid_index(from_index) or not is_valid_index(to_index) or from_index == to_index:
		return false
	var source := slots[from_index]
	if source == null:
		return false
	var destination := slots[to_index]
	if destination != null and destination.can_merge_with(source):
		var space := destination.get_stack_limit() - destination.quantity
		var moved := mini(space, source.quantity)
		if moved <= 0:
			return false
		destination.quantity += moved
		source.quantity -= moved
		if source.quantity <= 0:
			slots[from_index] = null
	else:
		slots[from_index] = destination
		slots[to_index] = source
	slot_changed.emit(from_index)
	slot_changed.emit(to_index)
	changed.emit()
	return true


## Moves items into another inventory (loot bag, storage crate, ...).
## Returns the number of units that could not be transferred.
func transfer_to(target: Inventory, from_index: int, quantity: int = -1) -> int:
	if target == null:
		return 0
	var stack := get_slot(from_index)
	if stack == null:
		return 0
	var amount := stack.quantity if quantity < 0 else mini(quantity, stack.quantity)
	var leftover := target.add_item(stack.item_id, amount)
	var moved := amount - leftover
	if moved > 0:
		remove_item(stack.item_id, moved)
	return leftover


## Splits a slot in half into the first free slot. Returns true when it split.
func split_stack(index: int) -> bool:
	var stack := get_slot(index)
	if stack == null or stack.quantity < 2:
		return false
	var free_index := first_empty_slot()
	if free_index < 0:
		return false
	var half := stack.quantity / 2
	slots[free_index] = ItemStack.create(stack.item_id, half)
	stack.quantity -= half
	slot_changed.emit(index)
	slot_changed.emit(free_index)
	changed.emit()
	return true


## Merges duplicate stacks and sorts by category, then name, then id.
func sort() -> void:
	var totals := count_all_items()
	for index in slot_count:
		slots[index] = null
	var ids := totals.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var left := ItemDatabase.get_item(a)
		var right := ItemDatabase.get_item(b)
		var left_key := "%d_%s_%s" % [left.category if left else 99, left.display_name if left else a, a]
		var right_key := "%d_%s_%s" % [right.category if right else 99, right.display_name if right else b, b]
		return left_key < right_key)
	for item_id: String in ids:
		add_item(item_id, int(totals[item_id]))
	changed.emit()


func first_empty_slot() -> int:
	for index in slot_count:
		if slots[index] == null:
			return index
	return -1


func is_full() -> bool:
	return first_empty_slot() < 0


func total_weight() -> float:
	var total := 0.0
	for stack in slots:
		if stack != null:
			total += stack.get_weight()
	return total


## Slot index of the first item matching a tool type, or -1.
func find_tool_slot(tool_type: ItemDefinition.ToolType) -> int:
	for index in slot_count:
		var stack := slots[index]
		if stack == null:
			continue
		var definition := stack.get_definition()
		if definition != null and definition.tool_type == tool_type:
			return index
	return -1


func clear() -> void:
	for index in slot_count:
		slots[index] = null
		slot_changed.emit(index)
	changed.emit()


func to_dict() -> Dictionary:
	var slot_data: Array = []
	for stack in slots:
		slot_data.append(null if stack == null or stack.is_empty() else stack.to_dict())
	return {
		"inventory_id": inventory_id,
		"capacity": slot_count,
		"slots": slot_data,
	}


## Replaces contents from save data. Unknown items and bad data are skipped
## instead of corrupting the inventory.
func load_from_dict(data: Dictionary) -> void:
	inventory_id = str(data.get("inventory_id", inventory_id))
	slot_count = maxi(1, int(data.get("capacity", slot_count)))
	slots = []
	slots.resize(slot_count)
	var slot_data: Array = data.get("slots", [])
	for index in mini(slot_data.size(), slot_count):
		var entry = slot_data[index]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var stack := ItemStack.from_dict(entry)
		if stack.is_empty():
			continue
		if not ItemDatabase.has_item(stack.item_id):
			push_warning("[Inventory] Dropping unknown saved item '%s'" % stack.item_id)
			continue
		slots[index] = stack
	changed.emit()


func _to_string() -> String:
	return "Inventory(%s, %d slots, %.2f kg)" % [inventory_id, slot_count, total_weight()]
