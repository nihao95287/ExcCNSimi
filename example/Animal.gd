extends CharacterBody2D

# ── 动物属性 ──────────────────────────────────────────
@export var species: String = "pig"
@export var move_speed: float = 40.0
@export var idle_time_range: Vector2 = Vector2(2.0, 5.0)
@export var max_health: float = 3.0 # 改为 float 提高兼容性

var health: float
var tilemap: Node2D 
var current_path: Array[Vector2i] = []
var is_moving: bool = false
var is_dead: bool = false 
var base_scale: Vector2 = Vector2(1.0, 1.0) # 存储基础缩放

@onready var timer: Timer = Timer.new()

func _ready() -> void:
	# 确保分组，方便 Main.gd 的右键射线检测
	add_to_group("animals")
	
	# --- 关键修复：碰撞体与探测 ---
	input_pickable = true 
	_ensure_collision_shape()
	
	health = max_health
	
	# 【修改】根据物种设置基础尺寸：pig 放大，chicken 缩小
	if species == "pig":
		base_scale = Vector2(3, 3)
	elif species == "chicken":
		base_scale = Vector2(0.5, 0.5)
	scale = base_scale
	
	# 获取 TileMapLayer (假设在场景树中名为 TileMapLayer)
	tilemap = get_parent().get_node_or_null("TileMapLayer")
	if not tilemap:
		tilemap = get_parent() # 兜底逻辑
	
	add_child(timer)
	timer.one_shot = true
	timer.timeout.connect(_on_behavior_timer_timeout)
	
	_start_idling()

func _ensure_collision_shape() -> void:
	if get_node_or_null("CollisionShape2D") == null:
		var col_shape = CollisionShape2D.new()
		var circle = CircleShape2D.new()
		circle.radius = 28.0 # 稍微加大点击判定范围
		col_shape.shape = circle
		add_child(col_shape)

func _physics_process(_delta: float) -> void:
	if is_dead: return
	
	if is_moving and current_path.size() > 0:
		_move_logic()
	else:
		velocity = Vector2.ZERO # 确保不滑动
		move_and_slide()

# ── 战斗系统 ──────────────────────────────────────────

## 兼容村民脚本的攻击调用
func take_damage(amount: float) -> void:
	if is_dead: return
	
	health -= amount
	
	# 视觉反馈：受击缩放 + 闪红
	var tween = create_tween().set_parallel(true)
	modulate = Color.RED
	scale = base_scale * 1.1 # 变红并稍微放大
	tween.tween_property(self, "modulate", Color.WHITE, 0.2)
	tween.tween_property(self, "scale", base_scale, 0.2)
	
	# 受击逻辑反应
	is_moving = false
	current_path.clear()
	
	if health <= 0:
		_die()
	else:
		# 受到攻击后，0.3秒后尝试逃跑
		if timer.is_stopped():
			timer.start(0.3)

func _die() -> void:
	if is_dead: return
	is_dead = true
	
	# 停止一切物理行为
	set_physics_process(false)
	
	# 掉落数量逻辑
	var drop_count = 3 if species == "pig" else 1
	
	# 统一调用 GameManager
	if GameManager.has_method("spawn_dropped_item"):
		GameManager.spawn_dropped_item(global_position, "meat", drop_count)
		GameManager.show_alert("猎获了 " + species + "，获得肉块！")
	
	# 播放一个简单的消失动画再删除
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.finished.connect(queue_free)

# ── 移动与 AI 逻辑 ──────────────────────────────────────────

func _move_logic() -> void:
	var target_pos = tilemap.map_to_local(current_path[0])
	var direction = global_position.direction_to(target_pos)
	
	velocity = direction * move_speed
	move_and_slide()
	
	# 转向处理：查找第一个 Sprite2D 节点
	for child in get_children():
		if child is Sprite2D:
			child.flip_h = direction.x < 0
			break
	
	# 到达判定（像素距离）
	if global_position.distance_to(target_pos) < 4.0:
		current_path.pop_front()
		if current_path.size() == 0:
			_start_idling()

func _start_idling() -> void:
	is_moving = false
	var wait_time = randf_range(idle_time_range.x, idle_time_range.y)
	timer.start(wait_time)

func _on_behavior_timer_timeout() -> void:
	if is_dead: return
	
	# 如果健康值不满（被打过），逃跑概率增加
	var move_chance = 0.8 if health < max_health else 0.4
	
	if randf() < move_chance:
		_pick_random_destination()
	else:
		_start_idling()

func _pick_random_destination() -> void:
	if not tilemap or not tilemap.has_method("get_path_coords"): 
		_start_idling()
		return
	
	var my_coord = tilemap.local_to_map(global_position)
	var wander_range = 5
	
	# 【核心修改】寻找不穿过障碍物或仓库区的有效路径
	var max_attempts = 10
	for attempt in range(max_attempts):
		var target_coord = my_coord + Vector2i(
			randi_range(-wander_range, wander_range),
			randi_range(-wander_range, wander_range)
		)
		
		# 1. 目标不能是不可通行格子
		if _is_blocked_cell(target_coord):
			continue
			
		# 2. 获取路径并验证
		var new_path = tilemap.get_path_coords(my_coord, target_coord, false)
		if new_path.size() <= 1:
			continue
			
		# 3. 检查路径点是否包含不可通行格子（起点除外）
		var path_blocked = false
		for i in range(1, new_path.size()):
			if _is_blocked_cell(new_path[i]):
				path_blocked = true
				break
		
		if path_blocked:
			continue
			
		# 验证通过，开始移动
		current_path = new_path
		current_path.pop_front() # 移除起始点
		is_moving = true
		return

	# 所有尝试均失败
	_start_idling()

# --- 【新增】辅助函数：判断格子是否不可通行 ---
func _is_blocked_cell(cell: Vector2i) -> bool:
	if not tilemap: return false
	
	# 1. 检测网格本身的 solid 状态 (包含了墙壁、天然岩石、水面等)
	if "astar_grid" in tilemap and tilemap.astar_grid.is_point_solid(cell):
		return true
		
	# 2. 检测仓库区 (通过 GameManager)
	if _is_stockpile_cell(cell):
		return true
		
	return false

# --- 【新增】辅助函数：判断是否为仓库区 ---
func _is_stockpile_cell(cell: Vector2i) -> bool:
	# 兼容 example 目录下的 GameManager 逻辑
	if Engine.has_meta("GameManager"): # 或者直接调用全局变量（Godot单例）
		return GameManager.is_stockpile_cell(cell)
	# 也可以通过 get_node 寻找
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		return gm.is_stockpile_cell(cell)
	return false
