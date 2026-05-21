@tool
extends TileMapLayer

var DEBUG_MAP_LOGS: bool:
	get: return SettingsManager.settings.get("debug_logs", false)

@export_group("Map Settings")
@export var generateMap : bool :
	set(v):
		generateMap = false
		Generate_map()
@export var clearMap : bool :
	set(v):
		clearMap = false
		clear_Map()
@export var mapWidth : int = 50
@export var mapHeight : int = 50
@export var seed_val : int = 0
@export var map_type : int = 0

@export_group("Terrain Thresholds")
@export_range(-1.0, 1.0) var water_threshold : float = -0.6
@export_range(-1.0, 1.0) var light_grass_threshold : float = -0.4
@export_range(-1.0, 1.0) var dark_grass_threshold : float = -0.1
@export_range(-1.0, 1.0) var dirt_threshold : float = 0.2
@export_range(-1.0, 1.0) var rock_threshold : float = 0.5

@export_group("Animal Spawning")
@export_range(0.0, 1.0) var pig_spawn_chance : float = 0.0015
@export_range(0.0, 1.0) var chicken_spawn_chance : float = 0.003
@export_range(0.0, 1.0) var fiber_spawn_chance : float = 0.10

@export_group("Resource Regeneration")
@export var regeneration_enabled: bool = true
@export var regeneration_interval_hours: float = 2.0
@export var max_regenerated_resources: int = 180
@export var max_regenerated_animals: int = 28
@export var resource_regen_attempts_per_tick: int = 12
@export var animal_regen_attempts_per_tick: int = 5

var astar_grid: AStarGrid2D

const SCR_ANIMAL = "res://scripts/entities/Animal.gd"
const SCR_RESOURCE = "res://scripts/entities/ResourceNode.gd"
const GENERATION_COLUMNS_PER_FRAME: int = 8
var _generation_in_progress: bool = false
var _regen_elapsed_hours: float = 0.0
var _regen_rng := RandomNumberGenerator.new()

func _ready() -> void:
	if DEBUG_MAP_LOGS:
		print("=== Map._ready() 被调用 ===")
		print("  节点路径: ", get_path())
		print("  是否在树中: ", is_inside_tree())
		print("  Engine.is_editor_hint(): ", Engine.is_editor_hint())
	if not Engine.is_editor_hint():
		_regen_rng.randomize()
		call_deferred("Generate_map")

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not regeneration_enabled or _generation_in_progress:
		return
	if not astar_grid:
		return
	var time_mgr = get_node_or_null("/root/TimeManager")
	if time_mgr and "active_time_scale" in time_mgr and int(time_mgr.active_time_scale) == 0:
		return
	var hours_per_second = time_mgr.hours_per_real_second if time_mgr and "hours_per_real_second" in time_mgr else 0.05
	_regen_elapsed_hours += delta * hours_per_second
	if _regen_elapsed_hours < regeneration_interval_hours:
		return
	_regen_elapsed_hours = fmod(_regen_elapsed_hours, regeneration_interval_hours)
	_run_regeneration_tick()

func Generate_map() -> void:
	if _generation_in_progress:
		return
	_generation_in_progress = true
	if DEBUG_MAP_LOGS:
		print("=== Map.Generate_map() 开始 ===")
	clear_Map()
	
	astar_grid = AStarGrid2D.new()
	astar_grid.region = Rect2i(0, 0, mapWidth, mapHeight)
	astar_grid.cell_size = Vector2(1, 1)
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar_grid.update()
	
	var noise = FastNoiseLite.new()
	noise.seed = seed_val
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	
	var res_noise = FastNoiseLite.new()
	res_noise.seed = seed_val + 100
	res_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	res_noise.frequency = 0.08
	
	var center_coord = Vector2(mapWidth / 2.0, mapHeight / 2.0)
	var clear_radius = 8.0
	
	for x in range(mapWidth):
		for y in range(mapHeight):
			var v = noise.get_noise_2d(x, y)
			var cell_pos = Vector2i(x, y)
			var dist_to_center = Vector2(x, y).distance_to(center_coord)
			
			if dist_to_center < clear_radius + 5.0:
				var falloff = clamp(1.0 - (dist_to_center / (clear_radius + 5.0)), 0.0, 1.0)
				var safe_v = (light_grass_threshold + dark_grass_threshold) / 2.0
				v = lerp(v, safe_v, falloff * falloff)
			
			var is_solid = false
			if v < water_threshold:
				set_cell(cell_pos, 0, Vector2i(1,1), 0)
				is_solid = true
			elif v < light_grass_threshold:
				set_cell(cell_pos, 0, Vector2i(0,0), 0)
			elif v < dark_grass_threshold:
				set_cell(cell_pos, 0, Vector2i(1,0), 0)
			elif v < dirt_threshold:
				set_cell(cell_pos, 0, Vector2i(2,0), 0)
			elif v < rock_threshold:
				set_cell(cell_pos, 0, Vector2i(3,0), 0)
			else:
				set_cell(cell_pos, 0, Vector2i(0,1), 0)
				is_solid = true
				
			if is_solid:
				astar_grid.set_point_solid(cell_pos, true)
		if not Engine.is_editor_hint() and x % GENERATION_COLUMNS_PER_FRAME == 0:
			await get_tree().process_frame
	
	await _generate_resources(noise, res_noise, center_coord, clear_radius)
	await _generate_animals(noise, center_coord, clear_radius)
	
	if DEBUG_MAP_LOGS:
		print("生成完成：地形、资源、动物已就绪。")
	_generation_in_progress = false
	_emit_map_generated()

func _emit_map_generated() -> void:
	EventBus.map_generated.emit(map_type)

func _generate_resources(noise, res_noise, center_coord, clear_radius) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val
	for x in range(mapWidth):
		for y in range(mapHeight):
			var cell_pos = Vector2i(x, y)
			var v = noise.get_noise_2d(x, y)
			if Vector2(x, y).distance_to(center_coord) < clear_radius: continue
			if v < water_threshold or v >= rock_threshold: continue
			
			var rv = res_noise.get_noise_2d(x, y)
			
			if v >= dirt_threshold and v < rock_threshold:
				if rv > 0.3 and rng.randf() < 0.12:
					_spawn_resource(cell_pos, 1)
			elif v >= water_threshold and v < dark_grass_threshold:
				if rv < -0.1 and rng.randf() < 0.15:
					_spawn_resource(cell_pos, 0)
			elif v >= light_grass_threshold and v < dirt_threshold:
				# 纤维生长在明亮草地区域（开阔地带）
				if rv > 0.15 and rng.randf() < fiber_spawn_chance:
					_spawn_resource(cell_pos, 3)
		if not Engine.is_editor_hint() and x % GENERATION_COLUMNS_PER_FRAME == 0:
			await get_tree().process_frame

func _spawn_resource(cell_pos: Vector2i, type_idx: int) -> void:
	if astar_grid.is_point_solid(cell_pos): return

	var res_node = StaticBody2D.new()
	var scr = load(SCR_RESOURCE)
	if scr: res_node.set_script(scr)

	res_node.add_to_group("resources")
	match type_idx:
		0: res_node.add_to_group("trees")
		1: res_node.add_to_group("rocks")
		3:
			res_node.add_to_group("fibers")
			res_node.add_to_group("trees")  # 共用采集逻辑

	if scr:
		res_node.type = type_idx
	res_node.grid_coord = cell_pos

	add_child(res_node)
	res_node.global_position = map_to_local(cell_pos)
	astar_grid.set_point_solid(cell_pos, true)

func _run_regeneration_tick() -> void:
	_regenerate_resources()
	_regenerate_animals()

func _regenerate_resources() -> void:
	if get_tree().get_nodes_in_group("resources").size() >= max_regenerated_resources:
		return
	var spawned = 0
	for _i in range(resource_regen_attempts_per_tick):
		if get_tree().get_nodes_in_group("resources").size() >= max_regenerated_resources:
			return
		var cell = _random_map_cell()
		if not _can_spawn_resource_at(cell):
			continue
		var type_idx = _pick_regenerated_resource_type(cell)
		if type_idx < 0:
			continue
		_spawn_resource(cell, type_idx)
		spawned += 1
		if spawned >= 3:
			return

func _regenerate_animals() -> void:
	if get_tree().get_nodes_in_group("animals").size() >= max_regenerated_animals:
		return
	var spawned = 0
	for _i in range(animal_regen_attempts_per_tick):
		if get_tree().get_nodes_in_group("animals").size() >= max_regenerated_animals:
			return
		var cell = _random_map_cell()
		if not _can_spawn_animal_at(cell):
			continue
		var species = "pig" if _regen_rng.randf() < 0.42 else "chicken"
		_spawn_animal(cell, species)
		spawned += 1
		if spawned >= 1:
			return

func _random_map_cell() -> Vector2i:
	return Vector2i(_regen_rng.randi_range(0, mapWidth - 1), _regen_rng.randi_range(0, mapHeight - 1))

func _can_spawn_resource_at(cell: Vector2i) -> bool:
	if not _is_valid_spawn_cell(cell):
		return false
	var center_coord = Vector2(mapWidth / 2.0, mapHeight / 2.0)
	if Vector2(cell).distance_to(center_coord) < 8.0:
		return false
	return true

func _can_spawn_animal_at(cell: Vector2i) -> bool:
	if not _is_valid_spawn_cell(cell):
		return false
	for animal in get_tree().get_nodes_in_group("animals"):
		if not is_instance_valid(animal):
			continue
		var animal_cell = local_to_map(to_local(animal.global_position))
		if animal_cell.distance_to(cell) < 4.0:
			return false
	return true

func _is_valid_spawn_cell(cell: Vector2i) -> bool:
	if not astar_grid or not astar_grid.is_in_boundsv(cell):
		return false
	if astar_grid.is_point_solid(cell):
		return false
	if get_cell_source_id(cell) < 0:
		return false
	var atlas = get_cell_atlas_coords(cell)
	if atlas == Vector2i(1, 1) or atlas == Vector2i(0, 1):
		return false
	if _has_dynamic_blocker_at(cell):
		return false
	return true

func _has_dynamic_blocker_at(cell: Vector2i) -> bool:
	for group_name in ["buildings", "doors", "resources"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node):
				continue
			if "grid_coord" in node and node.grid_coord == cell:
				return true
	return false

func _pick_regenerated_resource_type(cell: Vector2i) -> int:
	var atlas = get_cell_atlas_coords(cell)
	var roll = _regen_rng.randf()
	if atlas == Vector2i(3, 0):
		return 1 if roll < 0.55 else -1
	if atlas == Vector2i(0, 0) or atlas == Vector2i(1, 0):
		return 0 if roll < 0.45 else 3
	if atlas == Vector2i(2, 0):
		return 3 if roll < 0.35 else -1
	return -1

func _generate_animals(noise, center_coord, clear_radius) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val + 500
	
	for x in range(mapWidth):
		for y in range(mapHeight):
			var cell_pos = Vector2i(x, y)
			if astar_grid.is_point_solid(cell_pos): continue
			if Vector2(x, y).distance_to(center_coord) < clear_radius + 2.0: continue
			
			var v = noise.get_noise_2d(x, y)
			if v >= water_threshold and v < rock_threshold:
				if rng.randf() < pig_spawn_chance:
					_spawn_animal(cell_pos, "pig")
				elif rng.randf() < chicken_spawn_chance:
					_spawn_animal(cell_pos, "chicken")
		if not Engine.is_editor_hint() and x % GENERATION_COLUMNS_PER_FRAME == 0:
			await get_tree().process_frame

func _spawn_animal(cell_pos: Vector2i, species: String) -> void:
	var animal = CharacterBody2D.new()
	var scr = load(SCR_ANIMAL)
	if scr: animal.set_script(scr)
	
	animal.add_to_group("animals")
	if "species" in animal: animal.species = species
	
	var sprite = Sprite2D.new()
	var tex_path = "res://art/animals/pig.png" if species == "pig" else "res://art/animals/chicken.png"
	if FileAccess.file_exists(tex_path):
		sprite.texture = load(tex_path)
		# 尺寸现在由 Animal.gd 的 _ready 根据物种统一控制
	else:
		sprite.texture = load("res://icon.svg")
		sprite.scale = Vector2(0.3, 0.3)
	animal.add_child(sprite)
	
	add_child(animal)
	animal.global_position = map_to_local(cell_pos)

func remove_solid(cell_pos: Vector2i) -> void:
	if astar_grid:
		astar_grid.set_point_solid(cell_pos, false)

func get_path_coords(start: Vector2i, end: Vector2i, allow_adj: bool = true) -> Array[Vector2i]:
	if not astar_grid or not astar_grid.is_in_boundsv(start) or not astar_grid.is_in_boundsv(end):
		return []
	
	var actual_start = start
	if astar_grid.is_point_solid(start):
		for n in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var test = start + n
			if astar_grid.is_in_boundsv(test) and not astar_grid.is_point_solid(test):
				actual_start = test
				break
				
	var target = end
	if astar_grid.is_point_solid(end):
		if not allow_adj: return []
		target = _find_nearest_walkable(end, actual_start)
		if target == Vector2i(-1, -1): return []
		
	return astar_grid.get_id_path(actual_start, target)

func _find_nearest_walkable(center: Vector2i, ref: Vector2i) -> Vector2i:
	var best = Vector2i(-1, -1)
	var best_score = INF

	for radius in range(1, 3):
		for x in range(-radius, radius + 1):
			for y in range(-radius, radius + 1):
				var offset = Vector2i(x, y)
				if offset == Vector2i.ZERO:
					continue
				if max(abs(x), abs(y)) != radius:
					continue
				if Vector2(offset).length() > 2.0:
					continue

				var p = center + offset
				if not _is_walkable_cell(p):
					continue

				var id_path = astar_grid.get_id_path(ref, p)
				if id_path.is_empty():
					continue

				var score = Vector2(p).distance_squared_to(Vector2(ref)) - (_get_clearance_score(p) * 8.0)
				if score < best_score:
					best_score = score
					best = p

		if best != Vector2i(-1, -1):
			return best

	return best

func _is_walkable_cell(cell: Vector2i) -> bool:
	return astar_grid.is_in_boundsv(cell) and not astar_grid.is_point_solid(cell)

func is_water_cell(cell: Vector2i) -> bool:
	if not astar_grid or not astar_grid.is_in_boundsv(cell):
		return false
	return get_cell_atlas_coords(cell) == Vector2i(1, 1)

func _get_clearance_score(cell: Vector2i) -> int:
	var score = 0
	for offset in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if _is_walkable_cell(cell + offset):
			score += 2
	for offset in [Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		if _is_walkable_cell(cell + offset):
			score += 1
	return score

func clear_Map():
	clear()
	for child in get_children():
		if child.is_in_group("resources") or child.is_in_group("animals"):
			child.free()
	if astar_grid:
		astar_grid.update()
