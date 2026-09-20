class_name WorldRegions
extends RefCounted
## Static description of the prototype world: which regions exist, what they
## look like and what grows there.
##
## Kept in code for Phase 1 because the numbers change constantly while the
## prototype is tuned. Phase 6 (large world) moves this into .tres data and
## drives it from the chunk streamer.
##
## Coordinates are world pixels; the prototype world is a single 3072 x 3072 area
## centred on (0, 0).

enum Region { FOREST, RURAL, TOWN, INDUSTRIAL }

const WORLD_HALF_SIZE := 1536.0

## Region definitions:
## - rect: area in world pixels
## - ground: base ground colour
## - accent: patch colour scattered inside the region
## - resources: definition ids spawned here with `weight` as a share of the
##   node budget and `budget` as the number of nodes for the region
const REGIONS: Array[Dictionary] = [
	{
		"id": "forest",
		"name": "Northwood",
		"region": Region.FOREST,
		"rect": Rect2(-1536, -1536, 3072, 1400),
		"ground": Color(0.12, 0.18, 0.12),
		"accent": Color(0.15, 0.23, 0.14),
		"budget": 46,
		"resources": {
			"tree_pine": 0.5,
			"tree_birch": 0.25,
			"bush_berry": 0.15,
			"rock_small": 0.1,
		},
	},
	{
		"id": "rural",
		"name": "Hollow Fields",
		"region": Region.RURAL,
		"rect": Rect2(-1536, -136, 3072, 800),
		"ground": Color(0.15, 0.16, 0.12),
		"accent": Color(0.19, 0.2, 0.14),
		"budget": 34,
		"resources": {
			"tree_birch": 0.3,
			"bush_berry": 0.2,
			"rock_small": 0.3,
			"scrap_pile": 0.2,
		},
	},
	{
		"id": "town",
		"name": "Millbrook",
		"region": Region.TOWN,
		"rect": Rect2(-1536, 664, 3072, 500),
		"ground": Color(0.13, 0.13, 0.14),
		"accent": Color(0.17, 0.17, 0.18),
		"budget": 30,
		"resources": {
			"scrap_pile": 0.45,
			"rock_small": 0.15,
			"bush_berry": 0.1,
			"tree_birch": 0.3,
		},
	},
	{
		"id": "industrial",
		"name": "Ironworks",
		"region": Region.INDUSTRIAL,
		"rect": Rect2(-1536, 1164, 3072, 372),
		"ground": Color(0.1, 0.1, 0.11),
		"accent": Color(0.14, 0.13, 0.13),
		"budget": 24,
		"resources": {
			"scrap_pile": 0.6,
			"rock_small": 0.4,
		},
	},
]

## Spawn point for a new game (southern edge of the forest, facing the town).
const DEFAULT_SPAWN := Vector2(0, -420)


static func get_region_definitions() -> Array[Dictionary]:
	return REGIONS


static func get_region_ids() -> Array[String]:
	var ids: Array[String] = []
	for region in REGIONS:
		ids.append(str(region["id"]))
	return ids


## Which region contains a world position? Returns "" outside the world.
static func region_id_at(position: Vector2) -> String:
	for region in REGIONS:
		var rect: Rect2 = region["rect"]
		if rect.has_point(position):
			return str(region["id"])
	return ""


static func get_region(region_id: String) -> Dictionary:
	for region in REGIONS:
		if str(region["id"]) == region_id:
			return region
	return {}


static func get_ground_color(position: Vector2) -> Color:
	var region := get_region(region_id_at(position))
	if region.is_empty():
		return Color(0.09, 0.1, 0.09)
	return region["ground"]


static func is_inside_world(position: Vector2) -> bool:
	return absf(position.x) <= WORLD_HALF_SIZE and absf(position.y) <= WORLD_HALF_SIZE


static func clamp_to_world(position: Vector2) -> Vector2:
	var limit := WORLD_HALF_SIZE - 32.0
	return Vector2(clampf(position.x, -limit, limit), clampf(position.y, -limit, limit))


static func get_world_size() -> float:
	return WORLD_HALF_SIZE * 2.0
