extends Node

const SAVE_PATH = "user://save_game.json"

var _removed_cells: Array[Dictionary] = []

func _ready() -> void:
	EventBus.resource_node_removed.connect(_on_resource_removed)

func _on_resource_removed(type: int, grid_x: int, grid_y: int) -> void:
	_removed_cells.append({"type": type, "x": grid_x, "y": grid_y})

func reset_tracking() -> void:
	_removed_cells.clear()

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

var DEBUG_SAVE_LOGS: bool:
	get: return SettingsManager.settings.get("debug_logs", false)

func save_game(main_node: Node) -> bool:
	var data: Dictionary = {}

	_save_time(data)
	_save_inventory(data)
	_save_wolf_state(data)
	_save_stockpiles(data)
	_save_farms(data)
	_save_map_params(data, main_node)
	_save_world_resources(data)
	_save_buildings(data)
	_save_craft_jobs(data)
	_save_rooms(data)
	_save_villagers(data)
	_save_animals(data)
	_save_items(data)
	_save_settings(data, main_node)

	data["removed_cells"] = _removed_cells.duplicate()

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot open save file. Error: %s" % FileAccess.get_open_error())
		return false

	file.store_string(JSON.stringify(data))
	file.close()
	if DEBUG_SAVE_LOGS:
		print("SaveManager: saved -> ", SAVE_PATH)
	return true

func load_save() -> Dictionary:
	if not has_save():
		push_warning("SaveManager: save file does not exist")
		return {}

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveManager: cannot read save file")
		return {}

	var text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(text) != OK:
		push_error("SaveManager: JSON parse failed")
		return {}
	return json.data

func _save_time(data: Dictionary) -> void:
	var time_mgr = get_node_or_null("/root/TimeManager")
	if time_mgr:
		data["time"] = {
			"day": time_mgr.current_day,
			"hour": time_mgr.current_hour,
		}

func _save_inventory(data: Dictionary) -> void:
	var inv = get_node_or_null("/root/InventoryManager")
	if inv:
		data["inventory"] = {
			"wood": inv.wood,
			"stone": inv.stone,
			"meat": inv.meat,
			"fiber": inv.fiber,
			"tools": inv.tools.duplicate() if "tools" in inv else {},
		}

func _save_wolf_state(data: Dictionary) -> void:
	var wolf_mgr = get_node_or_null("/root/WolfManager")
	if wolf_mgr and wolf_mgr.has_method("serialize"):
		data["wolf_state"] = wolf_mgr.serialize()

func _save_stockpiles(data: Dictionary) -> void:
	var stockpile_mgr = get_node_or_null("/root/StockpileManager")
	if not stockpile_mgr:
		return

	var cells_arr: Array = []
	for c in stockpile_mgr.get_stockpile_cells():
		cells_arr.append({"x": c.x, "y": c.y})
	data["stockpile_cells"] = cells_arr

func _save_farms(data: Dictionary) -> void:
	var farm_mgr = get_node_or_null("/root/FarmManager")
	if farm_mgr and farm_mgr.has_method("serialize"):
		data["farms"] = farm_mgr.serialize()

func _save_map_params(data: Dictionary, main_node: Node) -> void:
	var tilemap = main_node.get_node_or_null("TileMapLayer") if main_node else null
	if not tilemap:
		return

	data["map_params"] = {
		"seed_val": tilemap.seed_val if "seed_val" in tilemap else 0,
		"mapWidth": tilemap.mapWidth if "mapWidth" in tilemap else 256,
		"mapHeight": tilemap.mapHeight if "mapHeight" in tilemap else 256,
		"water_threshold": tilemap.water_threshold if "water_threshold" in tilemap else -0.6,
		"light_grass_threshold": tilemap.light_grass_threshold if "light_grass_threshold" in tilemap else -0.4,
		"dark_grass_threshold": tilemap.dark_grass_threshold if "dark_grass_threshold" in tilemap else -0.1,
		"dirt_threshold": tilemap.dirt_threshold if "dirt_threshold" in tilemap else 0.2,
		"rock_threshold": tilemap.rock_threshold if "rock_threshold" in tilemap else 0.5,
		"pig_spawn_chance": tilemap.pig_spawn_chance if "pig_spawn_chance" in tilemap else 0.0015,
		"chicken_spawn_chance": tilemap.chicken_spawn_chance if "chicken_spawn_chance" in tilemap else 0.003,
		"fiber_spawn_chance": tilemap.fiber_spawn_chance if "fiber_spawn_chance" in tilemap else 0.10,
	}

func _save_world_resources(data: Dictionary) -> void:
	var arr: Array = []
	for r in get_tree().get_nodes_in_group("resources"):
		if not is_instance_valid(r):
			continue
		var gc: Vector2i = r.get("grid_coord") if "grid_coord" in r else Vector2i(-1, -1)
		arr.append({
			"type": int(r.get("type") if "type" in r else 0),
			"grid_x": gc.x,
			"grid_y": gc.y,
			"pos_x": r.global_position.x,
			"pos_y": r.global_position.y,
			"current_health": float(r.get("current_health") if "current_health" in r else 100.0),
			"max_health": float(r.get("max_health") if "max_health" in r else 100.0),
			"gather_yield": int(r.get("gather_yield") if "gather_yield" in r else 15),
		})
	data["resource_nodes"] = arr

func _save_buildings(data: Dictionary) -> void:
	var arr: Array = []
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		var gc: Vector2i = b.get("grid_coord") if "grid_coord" in b else Vector2i(-1, -1)
		var building_resource_path = ""
		if b.has_meta("building_resource_path"):
			building_resource_path = str(b.get_meta("building_resource_path"))
		arr.append({
			"type": int(b.get("type") if "type" in b else 0),
			"grid_x": gc.x,
			"grid_y": gc.y,
			"pos_x": b.global_position.x,
			"pos_y": b.global_position.y,
			"current_health": float(b.get("current_health") if "current_health" in b else 100.0),
			"max_health": float(b.get("max_health") if "max_health" in b else 100.0),
			"is_open": bool(b.get("is_open") if "is_open" in b else false),
			"building_resource_path": building_resource_path,
		})
	data["buildings"] = arr

func _save_craft_jobs(data: Dictionary) -> void:
	var job_mgr = get_node_or_null("/root/JobManager")
	if not job_mgr or not "jobs_queue" in job_mgr:
		return
	var arr: Array = []
	for job in job_mgr.jobs_queue:
		if str(job.get("type", "")) != "CRAFT":
			continue
		var target = job.get("target")
		if not is_instance_valid(target):
			continue
		var gc: Vector2i = target.get("grid_coord") if "grid_coord" in target else Vector2i(-1, -1)
		arr.append({
			"recipe_id": str(job.get("recipe_id", "")),
			"progress_minutes": float(job.get("progress_minutes", 0.0)),
			"grid_x": gc.x,
			"grid_y": gc.y,
		})
	data["craft_jobs"] = arr

func _save_rooms(data: Dictionary) -> void:
	var room_mgr = get_node_or_null("/root/RoomManager")
	if room_mgr and room_mgr.has_method("serialize"):
		data["rooms"] = room_mgr.serialize()

func _save_villagers(data: Dictionary) -> void:
	var arr: Array = []
	for v in get_tree().get_nodes_in_group("villagers"):
		if not is_instance_valid(v):
			continue
		var social: Dictionary = v.social_relations.duplicate() if "social_relations" in v else {}
		arr.append({
			"name": v.name,
			"pos_x": v.global_position.x,
			"pos_y": v.global_position.y,
			"hunger": v.get("hunger") if "hunger" in v else 100.0,
			"energy": v.get("energy") if "energy" in v else 100.0,
			"mood": v.get("mood") if "mood" in v else 100,
			"base_mood": v.get("base_mood") if "base_mood" in v else 100.0,
			"mood_penalties": v.get("mood_penalties") if "mood_penalties" in v else {},
			"health": v.get("health") if "health" in v else 100.0,
			"max_health": v.get("max_health") if "max_health" in v else 100.0,
			"is_on_strike": v.get("is_on_strike") if "is_on_strike" in v else false,
			"strike_timer": v.get("strike_timer") if "strike_timer" in v else 0.0,
			"strike_check_timer": v.get("strike_check_timer") if "strike_check_timer" in v else 0.0,
			"is_unconscious": v.get("is_unconscious") if "is_unconscious" in v else false,
			"unconscious_elapsed_hours": v.get("unconscious_elapsed_hours") if "unconscious_elapsed_hours" in v else 0.0,
			"wolf_hit_count": v.get("wolf_hit_count") if "wolf_hit_count" in v else 0,
			"skill_woodcut": v.get("skill_woodcut") if "skill_woodcut" in v else 1,
			"skill_mining": v.get("skill_mining") if "skill_mining" in v else 1,
			"skill_melee": v.get("skill_melee") if "skill_melee" in v else 1,
			"inventory": v.get("inventory") if "inventory" in v else {},
			"equipped_tool_id": v.get("equipped_tool_id") if "equipped_tool_id" in v else "",
			"social_relations": social,
		})
	data["villagers"] = arr

func _save_animals(data: Dictionary) -> void:
	var arr: Array = []
	for a in get_tree().get_nodes_in_group("animals"):
		if not is_instance_valid(a):
			continue
		arr.append({
			"species": a.get("species") if "species" in a else "pig",
			"pos_x": a.global_position.x,
			"pos_y": a.global_position.y,
			"health": a.get("health") if "health" in a else 2,
		})
	data["animals"] = arr

func _save_items(data: Dictionary) -> void:
	var haul_mgr = get_node_or_null("/root/HaulManager")
	var arr: Array = []
	if haul_mgr:
		var seen: Array[Node2D] = []
		for it in haul_mgr.get_unhauled_items():
			if is_instance_valid(it):
				seen.append(it)
		for it in haul_mgr.get_stockpile_items():
			if is_instance_valid(it) and not it in seen:
				seen.append(it)
		for it in get_tree().get_nodes_in_group("tool_drops"):
			if is_instance_valid(it) and not it in seen:
				seen.append(it)

		for it in seen:
			var gc: Vector2i = it.get("grid_coord") if "grid_coord" in it else Vector2i(-1, -1)
			arr.append({
				"type": int(it.get("type") if "type" in it else 0),
				"item_id": str(it.get("item_id") if "item_id" in it else ""),
				"amount": int(it.get("amount") if "amount" in it else 1),
				"grid_x": gc.x,
				"grid_y": gc.y,
				"pos_x": it.global_position.x,
				"pos_y": it.global_position.y,
			})
	data["items"] = arr

func _save_settings(data: Dictionary, _main_node: Node) -> void:
	data["settings"] = {}
