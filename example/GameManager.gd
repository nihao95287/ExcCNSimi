extends Node

# 信号：整合新版本肉类参数，兼容旧版信号逻辑
signal resources_updated(wood, stone, meat)
signal alert_message(message)
# 旧版教程事件信号（完整保留）
signal item_dropped   # 新的未搬运物品出现（树倒了/石头碎了）
signal item_stored    # 物品被存入仓库
signal stockpile_created  # 第一次划定仓库格子

var _stockpile_ever_created: bool = false # 旧版仓库标记（完整保留）

# 资源变量：整合新版肉类
var wood: int = 0
var stone: int = 0
var meat: int = 0 # 新增：肉类资源

# 旧版仓储与物品系统数组（完整保留）
var unhauled_items: Array[Node2D] = []
var stockpile_items: Array[Node2D] = []
var stockpile_cells: Array[Vector2i] = []

# 新版本肉类资源配置（完整保留）
const TEX_MEAT = "res://art/animals/meat.png"
const SCR_RESOURCE_ITEM = "res://ItemDrop.gd" 

# ── 新版本：掉落物生成逻辑（木材/石头/肉类通用，完整保留） ──────────────────
func spawn_dropped_item(pos: Vector2, type_string: String, count: int) -> void:
	var tilemap = get_tree().current_scene.find_child("TileMapLayer", true, false)
	
	for i in range(count):
		var drop = Node2D.new() 
		var item_script = load(SCR_RESOURCE_ITEM)
		if item_script:
			drop.set_script(item_script)
		
		# 类型映射：0=木头 1=石头 2=肉
		var type_idx = 0
		if type_string == "wood": type_idx = 0
		elif type_string == "stone": type_idx = 1
		elif type_string == "meat": type_idx = 2
		
		drop.set("item_type", type_idx)
		drop.set("amount", 1)
		
		# 随机偏移位置
		var offset = Vector2(randf_range(-20, 20), randf_range(-20, 20))
		drop.global_position = pos + offset
		
		# 网格坐标计算
		if tilemap and tilemap.has_method("local_to_map"):
			var g_coord = tilemap.local_to_map(drop.global_position)
			drop.set("grid_coord", g_coord)
		
		get_tree().current_scene.add_child(drop)
		
	print("[SYSTEM] 产生了 ", count, " 个 ", type_string)

# ── 旧版核心：物品注册逻辑（完整保留，兼容新版肉类物品） ──────────────────
func register_item(item: Node2D) -> void:
	# 兼容新版安全获取网格坐标
	var g_coord = item.get("grid_coord") if "grid_coord" in item else Vector2i(-1, -1)
	
	if is_stockpile_cell(g_coord):
		if not item in stockpile_items:
			stockpile_items.append(item)
			_recalculate_resources()
	else:
		if not item in unhauled_items:
			unhauled_items.append(item)
			item_dropped.emit()  # 旧版教程信号：有物品掉落

# ── 旧版核心：物品注销逻辑（完整保留） ──────────────────
func unregister_item(item: Node2D) -> void:
	if item in unhauled_items:
		unhauled_items.erase(item)
	if item in stockpile_items:
		stockpile_items.erase(item)
		_recalculate_resources()

# ── 旧版核心：物品入库逻辑（完整保留，兼容新版肉类） ──────────────────
func store_item(item: Node2D, cell: Vector2i) -> void:
	if item in unhauled_items:
		unhauled_items.erase(item)
	# 兼容新版属性赋值
	item.set("grid_coord", cell)
	
	if not item in stockpile_items:
		stockpile_items.append(item)
	_recalculate_resources()
	item_stored.emit()  # 旧版教程信号：物品入库
	print("物品已入库！")

# ── 旧版核心：仓库格子管理（完整保留） ──────────────────
func add_stockpile_cell(cell: Vector2i) -> void:
	if not cell in stockpile_cells:
		stockpile_cells.append(cell)
		if not _stockpile_ever_created:
			_stockpile_ever_created = true
			stockpile_created.emit()  # 旧版教程信号：第一次建仓库
		
		# 自动入库仓库格子上的物品（完整保留）
		var to_store = []
		for item in unhauled_items:
			var g_coord = item.get("grid_coord") if "grid_coord" in item else Vector2i(-1, -1)
			if is_instance_valid(item) and g_coord == cell:
				to_store.append(item)
		
		for item in to_store:
			store_item(item, cell)

# ── 旧版核心：判断是否为仓库格子（完整保留） ──────────────────
func is_stockpile_cell(cell: Vector2i) -> bool:
	return cell in stockpile_cells

# ── 旧版核心：获取空仓库格子（完整保留） ──────────────────
func get_empty_stockpile_cell() -> Vector2i:
	for cell in stockpile_cells:
		var occupied = false
		for item in stockpile_items:
			var g_coord = item.get("grid_coord") if "grid_coord" in item else Vector2i(-1, -1)
			if is_instance_valid(item) and g_coord == cell:
				occupied = true
				break
		if not occupied:
			return cell
	return Vector2i(-99999, -99999) # 无空位置

# ── 整合版：资源统计（旧版逻辑+新版肉类统计） ──────────────────
func _recalculate_resources() -> void:
	var total_wood = 0
	var total_stone = 0
	var total_meat = 0 # 新版肉类统计
	
	var valid_items: Array[Node2D] = []
	for item in stockpile_items:
		if is_instance_valid(item):
			valid_items.append(item)
			# 兼容新版安全读取物品属性
			var i_type = item.get("item_type")
			var i_amount = item.get("amount")
			
			if i_type == 0: # 旧版：木头
				total_wood += i_amount
			elif i_type == 1: # 旧版：石头
				total_stone += i_amount
			elif i_type == 2: # 新版：肉类
				total_meat += i_amount
				
	stockpile_items = valid_items
	
	# 更新所有资源
	wood = total_wood
	stone = total_stone
	meat = total_meat
	# 发射带肉类的更新信号
	resources_updated.emit(wood, stone, meat)

# ── 旧版核心：提示消息（完整保留） ──────────────────
func show_alert(msg: String) -> void:
	alert_message.emit(msg)
