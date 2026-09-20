extends Node
## Headless test runner for Last Haven.
##
## Run with:
##   godot --headless --path . res://tests/TestRunner.tscn
##
## Exits with code 0 when every check passes and 1 when something fails, which
## is what CI reacts to. Suites cover the data layer, the pure systems and one
## end-to-end pass through the real main scene (world + player + zombie + save).
##
## The save round trip uses slot 3, a slot reserved for tests.

const TEST_SLOT := 3

var checks: int = 0
var failures: Array[String] = []


func _ready() -> void:
	print("=== Last Haven test run ===")
	await get_tree().process_frame

	_run_item_database_suite()
	_run_inventory_suite()
	_run_crafting_suite()
	_run_loot_suite()
	_run_save_format_suite()
	_run_world_suite()
	_run_streaming_suite()
	_run_equipment_suite()
	_run_durability_suite()
	await _run_integration_suite()

	_finish()


# --- assertion helpers --------------------------------------------------------

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures.append(description)
	print("  FAIL: %s" % description)


func check_equal(actual: Variant, expected: Variant, description: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [description, expected, actual])


func check_near(actual: float, expected: float, tolerance: float, description: String) -> void:
	check(absf(actual - expected) <= tolerance,
			"%s (expected %.2f +/- %.2f, got %.2f)" % [description, expected, tolerance, actual])


func report(suite: String) -> void:
	print("  %s complete (%d checks so far)" % [suite, checks])


# --- suites -------------------------------------------------------------------

func _run_item_database_suite() -> void:
	print("- data: ItemDatabase")
	var problems := ItemDatabase.get_problems()
	check(problems.is_empty(), "definition data set must load without problems: %s" % [problems])
	check(ItemDatabase.get_item_count() >= 10, "expected at least 10 items, got %d" % ItemDatabase.get_item_count())
	check(ItemDatabase.get_recipes().size() >= 4, "expected at least 4 recipes")
	check(ItemDatabase.get_buildables().size() >= 3, "expected at least 3 buildables")
	check(ItemDatabase.get_resource_node_definitions().size() >= 3, "expected at least 3 resource node types")

	var ids: Array[String] = []
	for item: ItemDefinition in ItemDatabase.get_all_items():
		ids.append(item.id)
		check(item.stack_size >= 1, "item %s needs a positive stack size" % item.id)
	check(ids.size() == _unique_count(ids), "item ids must be unique")

	var wood := ItemDatabase.get_item("wood")
	check(wood != null and wood.display_name == "Wood", "wood definition must exist")
	var axe := ItemDatabase.get_item("axe")
	check(axe != null and axe.tool_type == ItemDefinition.ToolType.AXE, "axe must be an axe tool")
	check(ItemDatabase.get_item("does_not_exist") == null, "unknown item lookups must return null")

	# Check new equipment items exist.
	var helmet := ItemDatabase.get_item("leather_helmet")
	check(helmet != null, "leather_helmet item exists")
	check(helmet.equipment_slot == ItemDefinition.EquipmentSlot.HEAD, "leather_helmet goes in HEAD slot")
	var armor := ItemDatabase.get_item("leather_armor")
	check(armor != null, "leather_armor item exists")
	check(armor.equipment_slot == ItemDefinition.EquipmentSlot.BODY, "leather_armor goes in BODY slot")
	var backpack := ItemDatabase.get_item("military_backpack")
	check(backpack != null, "military_backpack item exists")
	check(backpack.equipment_slot == ItemDefinition.EquipmentSlot.BACKPACK, "military_backpack goes in BACKPACK slot")
	var repair_kit := ItemDatabase.get_item("repair_kit")
	check(repair_kit != null, "repair_kit item exists")
	check(repair_kit.category == ItemDefinition.Category.CONSUMABLE, "repair_kit is in CONSUMABLE category")
	report("items")


func _run_inventory_suite() -> void:
	print("- systems: Inventory")
	# Wood stacks to 50 per slot; overflow goes into the next free slot.
	var inventory := Inventory.new(2, "test_inventory")
	check_equal(inventory.add_item("wood", 10), 0, "adding 10 wood fits")
	check_equal(inventory.count_item("wood"), 10, "wood count")
	check_equal(inventory.add_item("wood", 45), 0, "a second slot absorbs the overflow")
	check_equal(inventory.count_item("wood"), 55, "wood is split across two stacks")
	check_equal(inventory.get_slot(0).quantity, 50, "the first stack is filled to the limit")
	check_equal(inventory.get_slot(1).quantity, 5, "the second stack holds the rest")
	check_equal(inventory.add_item("wood", 45), 0, "the second stack can be filled too")
	check_equal(inventory.count_item("wood"), 100, "both stacks are full")
	check_equal(inventory.add_item("wood", 10), 10, "a full inventory reports the leftover")
	check_equal(inventory.add_item("does_not_exist", 1), 1, "unknown items are rejected")

	check_equal(inventory.remove_item("wood", 20), 20, "removing 20 wood works")
	check_equal(inventory.count_item("wood"), 80, "wood count after removal")
	check_equal(inventory.remove_item("wood", 999), 80, "cannot remove more than is stored")
	check_equal(inventory.count_item("wood"), 0, "wood is gone")

	# Splitting and merging.
	var split_inventory := Inventory.new(2, "split")
	split_inventory.add_item("scrap", 7)
	check(split_inventory.split_stack(0), "splitting a stack of 7 works")
	check_equal(split_inventory.count_item("scrap"), 7, "splitting preserves the total")
	check_equal(split_inventory.get_slot(1).quantity, 3, "split leaves 3 in the new stack")

	# Transfers between inventories.
	var source := Inventory.new(2, "source")
	var target := Inventory.new(2, "target")
	source.add_item("fiber", 12)
	var leftover := source.transfer_to(target, 0)
	check_equal(leftover, 0, "transfer moves everything when there is room")
	check_equal(source.count_item("fiber"), 0, "source is emptied")
	check_equal(target.count_item("fiber"), 12, "target holds the fiber")

	# Sorting merges and orders.
	var messy := Inventory.new(4, "messy")
	messy.add_item("wood", 3)
	messy.add_item("stone", 2)
	messy.add_item("wood", 4)
	messy.sort()
	check_equal(messy.count_item("wood"), 7, "sorting merges duplicate stacks")
	check(messy.get_slot(0) != null, "sorted inventory starts with an occupied slot")

	# Serialization round trip.
	var restored := Inventory.new(4, "restored")
	restored.load_from_dict(messy.to_dict())
	check_equal(restored.count_item("wood"), 7, "inventory survives a save round trip")
	check_equal(restored.get_slot(0).item_id, messy.get_slot(0).item_id, "slot order is preserved")

	# Unknown saved items are dropped instead of breaking the inventory.
	var corrupt := Inventory.new(2, "corrupt")
	corrupt.load_from_dict({"capacity": 2, "slots": [{"item_id": "ghost_item", "quantity": 3}, null]})
	check_equal(corrupt.count_item("ghost_item"), 0, "unknown saved items are ignored")

	# Tool lookups and weight.
	var tools := Inventory.new(3, "tools")
	tools.add_item("axe", 1)
	check(tools.find_tool_slot(ItemDefinition.ToolType.AXE) == 0, "tool lookup finds the axe")
	check(tools.find_tool_slot(ItemDefinition.ToolType.PICKAXE) < 0, "tool lookup misses absent tools")
	check(tools.total_weight() > 0.0, "weight is reported")
	report("inventory")


func _run_crafting_suite() -> void:
	print("- systems: CraftingSystem")
	var inventory := Inventory.new(10, "crafting")
	var axe_recipe := ItemDatabase.get_recipe("axe")
	check(axe_recipe != null, "axe recipe exists")
	check(not CraftingSystem.can_craft(axe_recipe, inventory), "cannot craft with an empty inventory")

	inventory.add_item("wood", 3)
	inventory.add_item("stone", 2)
	check(not CraftingSystem.can_craft(axe_recipe, inventory), "missing fiber blocks crafting")
	var missing := CraftingSystem.get_missing(axe_recipe, inventory)
	check(missing.has("fiber"), "missing ingredients are reported")

	inventory.add_item("fiber", 2)
	check(CraftingSystem.can_craft(axe_recipe, inventory), "recipe becomes craftable with materials")
	check(CraftingSystem.craft(axe_recipe, inventory), "crafting succeeds")
	check_equal(inventory.count_item("axe"), 1, "the axe is in the inventory")
	check_equal(inventory.count_item("wood"), 0, "wood was consumed")
	check_equal(inventory.count_item("stone"), 0, "stone was consumed")
	check_equal(inventory.count_item("fiber"), 0, "fiber was consumed")

	# Failing crafts must not consume anything.
	var full := Inventory.new(1, "full")
	full.add_item("wood", 3)
	full.add_item("stone", 2)
	full.add_item("fiber", 2)
	var before := full.count_all_items()
	check(not CraftingSystem.craft(axe_recipe, full), "crafting fails when there is no room for the output")
	check_equal(full.count_all_items(), before, "a failed craft consumes nothing")

	# Equipment recipes exist.
	check(ItemDatabase.get_recipe("leather_helmet") != null, "leather_helmet recipe exists")
	check(ItemDatabase.get_recipe("leather_armor") != null, "leather_armor recipe exists")
	check(ItemDatabase.get_recipe("military_backpack") != null, "military_backpack recipe exists")
	check(ItemDatabase.get_recipe("repair_kit") != null, "repair_kit recipe exists")
	report("crafting")


func _run_loot_suite() -> void:
	print("- systems: LootTable")
	var table := ItemDatabase.get_loot_table("zombie_standard")
	check(table != null, "zombie loot table exists")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var roll_a := table.roll(rng)
	rng.seed = 12345
	var roll_b := table.roll(rng)
	check(roll_a == roll_b, "loot rolls are deterministic for a given seed")
	check(not roll_a.is_empty(), "a guaranteed roll always awards something")
	for item_id: String in roll_a.keys():
		check(ItemDatabase.has_item(item_id), "rolled item %s exists" % item_id)
		check(int(roll_a[item_id]) >= 1, "rolled quantity for %s is positive" % item_id)

	var ingredients := table.roll_ingredients(rng)
	var total := 0
	for ingredient: Ingredient in ingredients:
		total += ingredient.quantity
	check(total > 0, "roll_ingredients returns usable data")

	# Chance based entries respect their probability over many rolls.
	var always := LootTable.new()
	var entry := LootEntry.create("wood", 1, 1, 0.0)
	entry.weight = 0.0
	var entries: Array[LootEntry] = [entry]
	always.entries = entries
	always.guaranteed_rolls = 0
	always.chance_rolls = 5
	check(always.roll(rng).is_empty(), "entries with zero chance never drop")
	report("loot")


func _run_save_format_suite() -> void:
	print("- systems: SaveManager slot format")
	SaveManager.delete_save(TEST_SLOT)
	check(not SaveManager.has_save(TEST_SLOT), "test slot starts empty")

	var payload := {
		"version": SaveManager.SAVE_VERSION,
		"seed": 99,
		"player": {"position": [12.0, -8.0]},
		"world": {"seed": 99},
	}
	check(SaveManager.write_slot_data(TEST_SLOT, payload), "writing a slot succeeds")
	check(SaveManager.has_save(TEST_SLOT), "the slot now exists")

	var read_back := SaveManager.read_slot(TEST_SLOT)
	check_equal(int(read_back.get("version", -1)), SaveManager.SAVE_VERSION, "version survives the round trip")
	var player_data: Dictionary = read_back.get("player", {})
	var player_position: Array = player_data.get("position", [])
	check_near(float(player_position[0]) if player_position.size() == 2 else 0.0, 12.0, 0.001,
			"player x position survives the round trip")

	var metadata := SaveManager.get_save_metadata(TEST_SLOT)
	check(bool(metadata.get("exists", false)), "metadata reports the slot as present")
	check_equal(int(metadata.get("seed", 0)), 99, "metadata exposes the world seed")

	var empty_metadata := SaveManager.get_save_metadata(1)
	if not SaveManager.has_save(1):
		check(not bool(empty_metadata.get("exists", false)), "empty slots report exists = false")

	check(SaveManager.delete_save(TEST_SLOT), "deleting the slot succeeds")
	check(not SaveManager.has_save(TEST_SLOT), "the slot is gone")
	report("save format")


func _run_world_suite() -> void:
	print("- world: generation")
	var world: GameWorld = load("res://scenes/world/World.tscn").instantiate()
	add_child(world)
	world.generate(4242)

	var resource_count := 0
	for child in world.resource_root.get_children():
		if child is ResourceNode:
			resource_count += 1
	check(resource_count > 40, "a generated world has gatherable resources (got %d)" % resource_count)
	check_equal(world.get_world_seed(), 4242, "the world keeps the seed it was generated with")

	var first_position := Vector2.ZERO
	var first_key := ""
	for child in world.resource_root.get_children():
		if child is ResourceNode:
			first_position = (child as ResourceNode).position
			first_key = (child as ResourceNode).node_key
			break
	check(not first_key.is_empty(), "resource nodes have stable save keys")

	# Same seed, same world.
	world.generate(4242)
	var repeat_position := Vector2.ZERO
	for child in world.resource_root.get_children():
		if child is ResourceNode:
			repeat_position = (child as ResourceNode).position
			break
	check(first_position == repeat_position, "generation is deterministic for a seed")

	# Regions.
	check_equal(WorldRegions.region_id_at(Vector2(0, -420)), "forest", "spawn point is in the forest")
	check_equal(WorldRegions.region_id_at(Vector2(0, 0)), "rural", "centre of the map is rural")
	check_equal(WorldRegions.region_id_at(Vector2(5000, 5000)), "", "outside the world has no region")

	# Structures and loot round trip through world state.
	var wall := ItemDatabase.get_buildable("wood_wall")
	check(wall != null, "wood_wall buildable exists")
	var structure := world.add_structure(wall, Vector2(64, 64), 0.0, "local_player")
	check(structure != null, "a structure can be added to the world")
	structure.apply_damage(50.0)
	var health_after_damage := structure.health.current_health
	check(health_after_damage < wall.max_health, "structures take damage")

	world.spawn_loot_bag(Vector2(96, 96), {"wood": 5})
	var state := world.serialize_state()
	check((state.get("structures", []) as Array).size() == 1, "world state includes the structure")
	check((state.get("loot_bags", []) as Array).size() == 1, "world state includes the loot bag")

	world.apply_state(state)
	await get_tree().process_frame
	var restored_structures := 0
	var restored_health := 0.0
	for child in world.structure_root.get_children():
		if child is Structure:
			restored_structures += 1
			restored_health = (child as Structure).health.current_health
	check_equal(restored_structures, 1, "world restore rebuilds the structure")
	check_near(restored_health, health_after_damage, 0.5, "structure health is restored")

	# Resource depletion is persisted.
	var node: ResourceNode = null
	for child in world.resource_root.get_children():
		if child is ResourceNode:
			node = child as ResourceNode
			break
	node.harvest(ItemDefinition.ToolType.NONE)
	var uses_after_harvest := node.uses_left
	check(uses_after_harvest < node.definition.max_uses, "harvesting reduces the node's uses")
	var depleted_state := world.serialize_state()
	var saved_resources: Array = depleted_state.get("resources", [])
	check(saved_resources.size() >= 1, "a partially harvested node is saved")

	# Simulate a fresh process: full uses, then restore the saved state.
	node.uses_left = node.definition.max_uses
	world.apply_state(depleted_state)
	check_equal(node.uses_left, uses_after_harvest, "restored node state is applied")

	world.queue_free()
	await get_tree().process_frame
	report("world")


func _run_streaming_suite() -> void:
	print("- world: chunk streaming")
	var streamer := ChunkStreamer.new()
	streamer.chunk_size = 384.0
	streamer.active_radius_chunks = 1
	check_equal(streamer.world_to_chunk(Vector2(0, 0)), Vector2i(0, 0), "origin maps to chunk 0,0")
	check_equal(streamer.world_to_chunk(Vector2(400, -400)), Vector2i(1, -2), "positions map to the right chunk")
	check(streamer.is_chunk_active(Vector2i(1, 1), Vector2i(0, 0)), "the neighbouring chunk is active")
	check(not streamer.is_chunk_active(Vector2i(3, 0), Vector2i(0, 0)), "a distant chunk is not active")
	streamer.enabled = false
	check(streamer.is_chunk_active(Vector2i(9, 9), Vector2i(0, 0)), "streaming can be disabled")
	streamer.free()
	report("streaming")


func _run_equipment_suite() -> void:
	print("- systems: Equipment")
	var ec := EquipmentComponent.new()
	add_child(ec)

	# Empty by default.
	for slot: String in EquipmentComponent.SLOT_NAMES:
		check_equal(ec.get_equipped(slot), "", "slot %s starts empty" % slot)

	# Equip a helmet.
	var helmet := ItemDatabase.get_item("leather_helmet")
	check(helmet != null, "leather_helmet definition exists")
	var previous := ec.equip("head", "leather_helmet")
	check_equal(previous, "", "head slot was empty before")
	check_equal(ec.get_equipped("head"), "leather_helmet", "head slot now has helmet")
	check(ec.bonus_damage_reduction > 0.0, "helmet provides damage reduction")

	# Equip armor.
	var armor := ItemDatabase.get_item("leather_armor")
	check(armor != null, "leather_armor definition exists")
	ec.equip("body", "leather_armor")
	check(ec.bonus_damage_reduction > 0.1, "armor adds more damage reduction")

	# Auto-equip uses equipment_slot field.
	ec.unequip("head")
	ec.unequip("body")
	ec.unequip("backpack")
	var auto_result := ec.auto_equip("leather_helmet")
	check_equal(auto_result, "", "auto_equip puts helmet in head slot (returns empty previous)")
	check_equal(ec.get_equipped("head"), "leather_helmet", "helmet auto-equipped to head")

	# Equip backpack for capacity bonus.
	ec.auto_equip("military_backpack")
	check(ec.bonus_capacity > 0, "backpack provides capacity bonus")

	# Armor reduction.
	var reduced := ec.apply_armor(20.0)
	check(reduced < 20.0, "armor reduces incoming damage")
	check(reduced > 10.0, "armor does not reduce damage to zero")

	# Serialization.
	var state := ec.serialize_state()
	check(state.has("head"), "serialized state has head slot")
	check_equal(state["head"], "leather_helmet", "serialized head slot is correct")

	var ec2 := EquipmentComponent.new()
	add_child(ec2)
	ec2.apply_state(state)
	check_equal(ec2.get_equipped("head"), "leather_helmet", "restored head slot is correct")
	check(ec2.bonus_damage_reduction > 0.0, "restored damage reduction is applied")

	ec.queue_free()
	ec2.queue_free()
	report("equipment")


func _run_durability_suite() -> void:
	print("- systems: Tool Durability")
	var inventory := Inventory.new(4, "durability_test")

	# Axe has 150 durability.
	var axe := ItemDatabase.get_item("axe")
	check(axe != null and axe.durability > 0, "axe has durability")

	# Add an axe and check initial durability.
	inventory.add_item("axe", 1)
	var stack := inventory.get_slot(0)
	check(stack != null, "axe stack exists")
	check_equal(stack.durability, axe.durability, "new axe starts at full durability")

	# Simulate durability consumption.
	stack.durability -= 10
	check_equal(stack.durability, 140, "durability reduced correctly")

	# Knife has durability too.
	var knife := ItemDatabase.get_item("knife")
	check(knife != null and knife.durability > 0, "knife has durability")

	# Items without durability return 0.
	var wood := ItemDatabase.get_item("wood")
	check(wood != null and wood.durability == 0, "wood has no durability")

	report("durability")


func _run_integration_suite() -> void:
	print("- integration: main scene, combat, survival and saving")
	var main: Node2D = load("res://scenes/main/Main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	check(not main.is_session_active(), "the game starts on the main menu")

	main.start_new_game()
	await get_tree().process_frame
	check(main.is_session_active(), "starting a new game activates the session")

	var player: Player = main.player
	var world: GameWorld = main.world
	check(world.is_generated(), "the world is generated for the session")
	check(player.health.is_alive(), "the player starts alive")
	check_near(player.global_position.x, world.get_spawn_position().x, 1.0, "the player spawns at the camp")

	# Equipment component exists on the player.
	check(player.equipment_component != null, "player has an equipment component")
	check(player.equipment_component.get_equipped("head") == "", "head starts empty")

	# Movement: simulate input the way the joystick does.
	var start_position := player.global_position
	player.set_move_input(Vector2.RIGHT)
	for _frame in 30:
		await get_tree().physics_frame
	player.set_move_input(Vector2.ZERO)
	check(player.global_position.x > start_position.x + 5.0, "the player moves when input is given")
	check(player.facing.x > 0.5, "the player faces the movement direction")

	# Gathering: put a tree next to the player and harvest it.
	var tree := world.spawn_resource_node("tree_pine", player.global_position + Vector2(26, 0))
	check(tree != null and tree.can_gather(), "a tree can be spawned and gathered")
	var gathered_tree := tree.harvest(ItemDefinition.ToolType.AXE)
	var gathered_total := 0
	for ingredient: Ingredient in gathered_tree:
		gathered_total += ingredient.quantity
	check(gathered_total > 0, "harvesting yields items")
	check(tree.uses_left == tree.definition.max_uses - 1, "harvesting consumes one use")

	# Inventory integration.
	player.inventory_component.add_item("wood", 6)
	check_equal(player.get_inventory().count_item("wood"), 6, "gathered wood reaches the inventory")

	# Crafting through the player inventory.
	var knife_recipe := ItemDatabase.get_recipe("knife")
	player.inventory_component.add_item("scrap", 1)
	check(CraftingSystem.craft(knife_recipe, player.get_inventory()), "crafting a knife from gathered materials works")
	check_equal(player.get_inventory().count_item("knife"), 1, "the knife is in the inventory")

	# Equipment: equip the knife and verify the equipment component updates.
	player.equipment_component.auto_equip("knife")
	check_equal(player.equipment_component.get_equipped("tool"), "knife", "knife equipped in tool slot")

	# Building: a wall costs materials and creates a structure.
	tree.queue_free()
	await get_tree().process_frame
	player.global_position = world.get_spawn_position()
	player.facing = Vector2.DOWN
	await get_tree().physics_frame
	player.inventory_component.add_item("wood", 10)
	var wall := ItemDatabase.get_buildable("wood_wall")
	var wall_wood_cost := int(wall.cost_dict().get("wood", 0))
	var wood_before_build := player.get_inventory().count_item("wood")
	var build_system: BuildSystem = player.build_system
	build_system.enter_build_mode(wall)
	check(build_system.is_active(), "build mode activates")
	var placed := build_system.confirm_placement()
	check(placed, "a wall can be placed in front of the player")
	check_equal(player.get_inventory().count_item("wood"), wood_before_build - wall_wood_cost,
		"building paid the wood cost")
	build_system.exit_build_mode()
	check(not build_system.is_active(), "build mode exits")

	# Combat: a zombie must detect, chase and hurt the player, then die to hits.
	player.global_position = world.get_spawn_position()
	var zombie := world.spawn_enemy(player.global_position + Vector2(90, 0))
	check(zombie != null, "a zombie can be spawned")
	var saw_chase := false
	var player_health_before := player.health.current_health
	for _frame in 240:
		await get_tree().physics_frame
		if zombie.is_dead():
			break
		if zombie.state == Zombie.State.CHASE or zombie.state == Zombie.State.ATTACK:
			saw_chase = true
	check(saw_chase, "the zombie detects and chases the player")
	check(player.health.current_health < player_health_before, "the zombie damages the player in melee")

	var zombie_health_before := zombie.health.current_health
	zombie.health.apply_damage(DamageInfo.create(500.0, player))
	check(zombie.health.current_health <= 0.0, "zombies can be killed")
	check(zombie.is_dead(), "the zombie switches to its dead state")
	await get_tree().process_frame
	check(zombie_health_before > 0.0, "the zombie had health before the killing blow")

	# Save and load the whole session.
	player.global_position = Vector2(128, -64)
	player.inventory_component.add_item("stone", 4)
	var saved_health := player.health.current_health
	SaveManager.delete_save(TEST_SLOT)
	check(main.save_game(TEST_SLOT), "saving the session works: %s" % SaveManager.last_error)
	check(SaveManager.has_save(TEST_SLOT), "the save file exists after saving")

	player.global_position = Vector2(-400, 400)
	player.inventory_component.remove_item("stone", 4)
	check(main.load_game(TEST_SLOT), "loading the session works: %s" % SaveManager.last_error)
	await get_tree().process_frame
	check_near(player.global_position.x, 128.0, 1.0, "the loaded player position is restored")
	check_near(player.global_position.y, -64.0, 1.0, "the loaded player position is restored (y)")
	check_near(player.health.current_health, saved_health, 0.5, "loaded health matches the save")
	check_equal(player.get_inventory().count_item("stone"), 4, "loaded inventory matches the save")

	# Death and respawn.
	player.health.apply_damage(DamageInfo.create(1000.0, null))
	check(player.is_dead, "the player dies at zero health")
	var died_again := player.is_dead
	check(died_again, "death state is stable")
	player.respawn_at(world.get_spawn_position())
	check(not player.is_dead and player.health.is_alive(), "the player can respawn")

	SaveManager.delete_save(TEST_SLOT)
	main.queue_free()
	await get_tree().process_frame
	report("integration")


# --- helpers ------------------------------------------------------------------

func _unique_count(values: Array[String]) -> int:
	var seen: Dictionary = {}
	for value in values:
		seen[value] = true
	return seen.size()


func _finish() -> void:
	print("=== %d checks, %d failures ===" % [checks, failures.size()])
	if failures.is_empty():
		print("RESULT: PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		print("FAILED: %s" % failure)
	print("RESULT: FAIL")
	get_tree().quit(1)
