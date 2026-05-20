@tool
extends TileMapLayer

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

@export_group("Terrain Thresholds")
@export_range(-1.0, 1.0) var water_threshold : float = -0.6
@export_range(-1.0, 1.0) var light_grass_threshold : float = -0.4
@export_range(-1.0, 1.0) var dark_grass_threshold : float = -0.1
@export_range(-1.0, 1.0) var dirt_threshold : float = 0.2
@export_range(-1.0, 1.0) var rock_threshold : float = 0.5

@export_group("Animal Spawning")
## 猪的生成概率
@export_range(0.0, 1.0) var pig_spawn_chance : float = 0.0015
## 鸡的生成概率
@export_range(0.0, 1.0) var chicken_spawn_chance : float = 0.003

var astar_grid: AStarGrid2D

# 资源路径常量
const TEX_PIG = "res://art/animals/pig.png"
const TEX_CHICKEN = "res://art/animals/chicken.png"
const SCR_ANIMAL = "res://Animal.gd"
const SCR_RESOURCE = "res://ResourceNode.gd"

func _ready() -> void:
	if not Engine.is_editor_hint():
		Generate_map()

# ──────────────────────────────────────────────────────
#  地图生成主逻辑
# ──────────────────────────────────────────────────────

func Generate_map():
	print("正在生成统一生态系统（含动物与肉类资源点）...")
	clear_Map() 
	
	# 初始化 AStar 寻路
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
	
	# 第一遍循环：地形与 AStar 阻挡
	for x in range(mapWidth):
		for y in range(mapHeight):
			var v = noise.get_noise_2d(x, y)
			var cell_pos = Vector2i(x, y)
			var dist_to_center = Vector2(x, y).distance_to(center_coord)
			
			# 出生点平坦化
			if dist_to_center < clear_radius + 5.0:
				var falloff = clamp(1.0 - (dist_to_center / (clear_radius + 5.0)), 0.0, 1.0)
				var safe_v = (light_grass_threshold + dark_grass_threshold) / 2.0
				v = lerp(v, safe_v, falloff * falloff)
				
			var is_solid = false
			if v < water_threshold:
				set_cell(cell_pos, 0, Vector2i(1,1), 0) # 使用旧版水槽坐标
				is_solid = true
			elif v < light_grass_threshold:
				set_cell(cell_pos, 0, Vector2i(0,0), 0) # 浅草
			elif v < dark_grass_threshold:
				set_cell(cell_pos, 0, Vector2i(1,0), 0) # 深草
			elif v < dirt_threshold:
				set_cell(cell_pos, 0, Vector2i(2,0), 0) # 泥地
			elif v < rock_threshold:
				set_cell(cell_pos, 0, Vector2i(3,0), 0) # 岩石
			else:
				set_cell(cell_pos, 0, Vector2i(0,1), 0) # 高山
				is_solid = true
				
			if is_solid:
				astar_grid.set_point_solid(cell_pos, true)
	
	# 第二遍：生成实体
	_generate_resources(noise, res_noise, center_coord, clear_radius)
	_generate_animals(noise, center_coord, clear_radius)
	
	print("生成完成：地形、资源、动物已就绪。")

# ──────────────────────────────────────────────────────
#  实体生成子逻辑
# ──────────────────────────────────────────────────────

func _generate_resources(noise, res_noise, center_coord, clear_radius):
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val
	for x in range(mapWidth):
		for y in range(mapHeight):
			var cell_pos = Vector2i(x, y)
			var v = noise.get_noise_2d(x, y)
			if Vector2(x, y).distance_to(center_coord) < clear_radius: continue
			if v < water_threshold or v >= rock_threshold: continue
			
			var rv = res_noise.get_noise_2d(x, y)
			
			# 泥地生成石头
			if v >= dirt_threshold and v < rock_threshold:
				if rv > 0.3 and rng.randf() < 0.12:
					_spawn_resource(cell_pos, 1) # ROCK
			# 草地生成树木
			elif v >= water_threshold and v < dark_grass_threshold:
				if rv < -0.1 and rng.randf() < 0.15:
					_spawn_resource(cell_pos, 0) # TREE

func _spawn_resource(cell_pos: Vector2i, type: int) -> void:
	if astar_grid.is_point_solid(cell_pos): return
	
	var res_node = StaticBody2D.new()
	var scr = load(SCR_RESOURCE)
	if scr: res_node.set_script(scr)
	
	res_node.add_to_group("resources")
	res_node.add_to_group("trees" if type == 0 else "rocks")
	
	# 统一属性赋值
	if "type" in res_node: res_node.type = type
	if "grid_coord" in res_node: res_node.grid_coord = cell_pos
	
	add_child(res_node)
	res_node.global_position = map_to_local(cell_pos)
	
	# 更新寻路阻挡
	astar_grid.set_point_solid(cell_pos, true)

func _generate_animals(noise, center_coord, clear_radius):
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val + 500
	
	for x in range(mapWidth):
		for y in range(mapHeight):
			var cell_pos = Vector2i(x, y)
			if astar_grid.is_point_solid(cell_pos): continue
			if Vector2(x, y).distance_to(center_coord) < clear_radius + 2.0: continue
			
			var v = noise.get_noise_2d(x, y)
			# 在可通行的陆地上生成
			if v >= water_threshold and v < rock_threshold:
				if rng.randf() < pig_spawn_chance:
					_spawn_animal(cell_pos, "pig")
				elif rng.randf() < chicken_spawn_chance:
					_spawn_animal(cell_pos, "chicken")

func _spawn_animal(cell_pos: Vector2i, species: String) -> void:
	var animal = CharacterBody2D.new()
	var scr = load(SCR_ANIMAL)
	if scr: animal.set_script(scr)
	
	animal.add_to_group("animals")
	if "species" in animal: animal.species = species
	
	var sprite = Sprite2D.new()
	var tex_path = TEX_PIG if species == "pig" else TEX_CHICKEN
	if FileAccess.file_exists(tex_path):
		sprite.texture = load(tex_path)
		# 尺寸现在由 Animal.gd 的 _ready 根据物种统一控制
	else:
		sprite.texture = load("res://icon.svg")
		sprite.scale = Vector2(0.3, 0.3)
		sprite.modulate = Color.PINK if species == "pig" else Color.YELLOW
		
	animal.add_child(sprite)
	add_child(animal)
	animal.global_position = map_to_local(cell_pos)

# ──────────────────────────────────────────────────────
#  功能性接口
# ──────────────────────────────────────────────────────

func remove_solid(cell_pos: Vector2i) -> void:
	if astar_grid:
		astar_grid.set_point_solid(cell_pos, false)

func get_path_coords(start: Vector2i, end: Vector2i, allow_adj: bool = true) -> Array[Vector2i]:
	if not astar_grid or not astar_grid.is_in_boundsv(start) or not astar_grid.is_in_boundsv(end):
		return []
	
	# 旧版补救逻辑：如果起点本身是实心的（由于微位移进入），找邻居作为起点
	var actual_start = start
	if astar_grid.is_point_solid(start):
		for n in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var test = start + n
			if astar_grid.is_in_boundsv(test) and not astar_grid.is_point_solid(test):
				actual_start = test
				break
				
	# 如果终点是实心（如采集树），寻找邻近点
	var target = end
	if astar_grid.is_point_solid(end):
		if not allow_adj: return []
		target = _find_nearest_walkable(end, actual_start)
		if target == Vector2i(-1, -1): return []
		
	return astar_grid.get_id_path(actual_start, target)

func _find_nearest_walkable(center: Vector2i, ref: Vector2i) -> Vector2i:
	var best = Vector2i(-1, -1)
	var min_d = INF
	# 包含对角线的全方位探测
	var neighbors = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, 
					 Vector2i(1,1), Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1)]
	for d in neighbors:
		var p = center + d
		if astar_grid.is_in_boundsv(p) and not astar_grid.is_point_solid(p):
			var d_sq = Vector2(p).distance_squared_to(Vector2(ref))
			if d_sq < min_d:
				min_d = d_sq
				best = p
	return best

func clear_Map():
	clear()
	# 清理所有动态生成的子节点
	for child in get_children():
		if child.is_in_group("resources") or child.is_in_group("animals"):
			child.free()
	if astar_grid:
		astar_grid.update()
