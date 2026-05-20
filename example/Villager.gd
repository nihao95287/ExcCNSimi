extends CharacterBody2D

@export var move_speed: float = 200.0
@export var gather_speed: float = 1.0 # 采集频率/攻击频率

# 整合：加入 ATTACK 状态
enum Task { IDLE, MOVE, GATHER, HAUL, ATTACK }

var current_task: Task = Task.IDLE
var path: Array[Vector2] = []
var is_selected: bool = false
var current_target_pos: Vector2

# 整合：加入动物目标引用
var target_resource: Node2D = null
var target_animal: Node2D = null
var gather_timer: float = 0.0
var tool_sprite: Sprite2D = null

# 搬运相关
var carried_item: Node2D = null
var haul_target_cell: Vector2i
var idle_timer: float = 0.0

func _ready() -> void:
	input_pickable = true
	tool_sprite = Sprite2D.new()
	tool_sprite.visible = false
	tool_sprite.scale = Vector2(2.0, 2.0)
	add_child(tool_sprite)

# 整合：保留旧版本的统一目标清理函数
func _clear_targets() -> void:
	if carried_item: _drop_current_item()
	# 整合：清理旧版本的搬运预留状态
	if current_task == Task.HAUL and target_resource and carried_item == null:
		target_resource.is_reserved = false
	target_resource = null
	target_animal = null
	if tool_sprite: tool_sprite.visible = false
	path.clear()

func command_move(new_path: Array[Vector2]) -> void:
	_clear_targets()
	current_task = Task.MOVE
	path = new_path
	if path.size() > 0:
		current_target_pos = path.pop_front()
	else:
		current_target_pos = global_position

func command_gather(new_path: Array[Vector2], resource: Node2D) -> void:
	_clear_targets()
	current_task = Task.GATHER
	path = new_path
	if path.size() > 0:
		current_target_pos = path.pop_front()
	else:
		current_target_pos = global_position
	target_resource = resource
	gather_timer = 0.0
	
	if tool_sprite and resource:
		if resource.type == 0: # TREE
			tool_sprite.texture = load("res://art/tools/axe1.png")
		elif resource.type == 1: # ROCK
			tool_sprite.texture = load("res://art/tools/pickaxe1.png")
		tool_sprite.position = Vector2(8, -8) # 保留新版本的工具位置
		tool_sprite.visible = false

# 整合：加入旧版本的攻击指令函数
func command_attack(new_path: Array[Vector2], animal: Node2D) -> void:
	_clear_targets()
	current_task = Task.ATTACK
	path = new_path
	if path.size() > 0:
		current_target_pos = path.pop_front()
	target_animal = animal
	gather_timer = 0.0
	# 攻击时默认拿斧头（或者你可以换成剑的贴图）
	if tool_sprite:
		tool_sprite.texture = load("res://art/tools/axe1.png")
		tool_sprite.position = Vector2(16, -16)

func _physics_process(delta: float) -> void:
	# 整合：将 ATTACK 加入移动处理逻辑
	if current_task in [Task.MOVE, Task.GATHER, Task.HAUL, Task.ATTACK]:
		_handle_movement()
	
	if current_task == Task.GATHER:
		_handle_gathering(delta)
	
	# 整合：加入攻击逻辑处理
	if current_task == Task.ATTACK:
		_handle_combat(delta)
		
		
	if current_task == Task.IDLE:
		idle_timer += delta
		if idle_timer > 1.0:
			idle_timer = 0.0
			_search_for_haul_job()

	# 整合：保留旧版本的简洁写法
	modulate = Color(1.2, 1.2, 1.2, 1.0) if is_selected else Color(1.0, 1.0, 1.0, 1.0)

func _handle_movement() -> void:
	if current_target_pos == Vector2.ZERO and path.is_empty(): return
	
	var dir = (current_target_pos - global_position).normalized()
	var dist = global_position.distance_to(current_target_pos)
	
	# 整合：保留新版本的平滑移动修复（移除提前打断的BUG）
	var reach_threshold = 4.0
	if path.is_empty():
		reach_threshold = 4.0
		
	if dist < reach_threshold:
		if path.size() > 0:
			current_target_pos = path.pop_front()
		else:
			if current_task == Task.MOVE:
				current_task = Task.IDLE
			elif current_task == Task.HAUL:
				_process_haul_step()
			velocity = Vector2.ZERO
	else:
		velocity = dir * move_speed
		move_and_slide()

# 整合：加入旧版本的战斗处理函数（适配新版本的距离阈值）
func _handle_combat(delta: float) -> void:
	if not is_instance_valid(target_animal):
		current_task = Task.IDLE
		if tool_sprite: tool_sprite.visible = false
		return
	
	var dist_to_ani = global_position.distance_to(target_animal.global_position)
	# 整合：使用新版本的合理距离阈值（32.0）
	if dist_to_ani <= 64:
		if tool_sprite: tool_sprite.visible = true
		
		# 整合：加入旧版本的工具挥动动画
		tool_sprite.rotation = sin(Time.get_ticks_msec() * 0.02) * 0.5
		
		gather_timer += delta
		if gather_timer >= gather_speed:
			gather_timer = 0.0
			if target_animal.has_method("take_damage"):
				target_animal.take_damage(1)

func _handle_gathering(delta: float) -> void:
	if not is_instance_valid(target_resource):
		current_task = Task.IDLE
		if tool_sprite: tool_sprite.visible = false
		return
	
	var dist_to_res = global_position.distance_to(target_resource.global_position)
	# 整合：保留新版本的合理距离阈值
	if dist_to_res <= 32.0:
		if tool_sprite: tool_sprite.visible = true
		
		# 整合：加入旧版本的工具挥动动画
		tool_sprite.rotation = sin(Time.get_ticks_msec() * 0.02) * 0.5
		
		gather_timer += delta
		if gather_timer >= gather_speed:
			gather_timer = 0.0
			if target_resource.has_method("gather"):
				var done = target_resource.gather(30.0, self)
				if done:
					current_task = Task.IDLE
					path.clear()
					if tool_sprite: tool_sprite.visible = false

# --- 搬运逻辑：保留新版本的完整实现 ---
func _search_for_haul_job() -> void:
	var best_item = null
	var min_dist = 999999.0
	for item in GameManager.unhauled_items:
		if is_instance_valid(item) and not item.is_reserved:
			var d = global_position.distance_to(item.global_position)
			if d < min_dist:
				min_dist = d
				best_item = item
				
	if best_item:
		var empty_cell = GameManager.get_empty_stockpile_cell()
		if empty_cell.x != -99999:
			best_item.is_reserved = true
			command_haul(best_item, empty_cell)

func command_haul(item: Node2D, dest_cell: Vector2i) -> void:
	var tilemap = get_parent().get_node_or_null("TileMapLayer")
	if not tilemap: return
	
	var start_coord = tilemap.local_to_map(global_position)
	var id_path = tilemap.get_path_coords(start_coord, item.grid_coord, true)
	
	if id_path.size() > 0:
		var world_path: Array[Vector2] = []
		for coord in id_path:
			world_path.append(tilemap.map_to_local(coord))
		if world_path.size() > 1:
			world_path.pop_front()
			
		current_task = Task.HAUL
		target_resource = item
		haul_target_cell = dest_cell
		path = world_path
		if path.size() > 0:
			current_target_pos = path.pop_front()
		else:
			current_target_pos = global_position
		carried_item = null
	else:
		item.is_reserved = false

func _process_haul_step() -> void:
	if carried_item == null: # 刚抵达物品所在地
		if not is_instance_valid(target_resource): 
			current_task = Task.IDLE
			return
			
		carried_item = target_resource
		var parent = carried_item.get_parent()
		if parent: parent.remove_child(carried_item)
		add_child(carried_item)
		carried_item.position = Vector2(0, -12) # 保留新版本的举在头顶位置
		carried_item.scale = Vector2(1.0, 1.0)
		
		# 开始前往仓库
		var tilemap = get_parent().get_node_or_null("TileMapLayer")
		if tilemap:
			var start_coord = tilemap.local_to_map(global_position)
			var id_path = tilemap.get_path_coords(start_coord, haul_target_cell, true)
			if id_path.size() > 0:
				var world_path: Array[Vector2] = []
				for coord in id_path:
					world_path.append(tilemap.map_to_local(coord))
				if world_path.size() > 1:
					world_path.pop_front()
				path = world_path
				if path.size() > 0:
					current_target_pos = path.pop_front()
			else:
				# 无法到达仓库，原地放下
				_drop_item_at(start_coord)
	else:
		# 已抵达仓库，放下物品
		_drop_item_at(haul_target_cell)

func _drop_current_item() -> void:
	var tilemap = get_parent().get_node_or_null("TileMapLayer")
	if tilemap:
		var cur_cell = tilemap.local_to_map(global_position)
		_drop_item_at(cur_cell)

func _drop_item_at(drop_cell: Vector2i) -> void:
	if carried_item and is_instance_valid(carried_item):
		var tilemap = get_parent().get_node_or_null("TileMapLayer")
		remove_child(carried_item)
		if tilemap:
			tilemap.add_child(carried_item)
			carried_item.scale = Vector2(1,1)
			carried_item.global_position = tilemap.map_to_local(drop_cell)
		carried_item.is_reserved = false
		
		if GameManager.is_stockpile_cell(drop_cell):
			GameManager.store_item(carried_item, drop_cell)
		else:
			carried_item.grid_coord = drop_cell
			if not carried_item in GameManager.unhauled_items:
				GameManager.register_item(carried_item)
				
	carried_item = null
	current_task = Task.IDLE

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var map_node = get_tree().current_scene
		if map_node.has_method("select_villager"):
			map_node.select_villager(self)
		get_viewport().set_input_as_handled()
