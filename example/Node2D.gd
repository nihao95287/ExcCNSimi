extends Node2D

var camera: Camera2D
var selected_villager: Node2D = null
var is_building_stockpile: bool = false
var stockpile_visuals: Dictionary = {}
var stockpile_drag_start: Vector2i = Vector2i(-1, -1)
var stockpile_preview_panel: Panel

# UI 元素
var ui_layer: CanvasLayer
var wood_label: Label
var stone_label: Label
var meat_label: Label  # 整合：新增肉类标签
var tooltip_label: Label

# ── 教程系统 ──────────────────────────────────────────
var tut_panel: PanelContainer
var tut_step_label: Label
var tut_title_label: Label
var tut_desc_label: Label
var tut_next_btn: Button
var tut_skip_btn: Button
var tut_highlight_arrow: Label  # 📍 指向提示箭头
var current_tutorial_step: int = 0
var tutorial_active: bool = true
var stockpile_btn: Button  # 需要在教程中引用

# 教程步骤定义 [标题, 描述, 是否自动推进]
var TUTORIAL_STEPS = [
	["🌏  欢迎来到瓦鲁多！", "你的第一批部落成员正在这片荒野中。\n\n你需要引导他们采集资源、建设家园，才能在这片土地上生存下去。\n\n点击 [开始] 进入教程。", false],
	["① 选择村民", "使用 鼠标左键 点击地图上的村民（Godot 图标或人物精灵）来选中他。\n\n选中后，村民将高亮显示，状态栏也会显示他的名字。", true],
	["② 命令砍树", "已选中村民！\n\n现在在地图上找一棵 绿色方块（树木），使用 鼠标右键 点击它，命令村民前去砍伐。", true],
	["③ 等待木材", "村民正在赶路去砍树……\n\n砍伐需要消耗几秒时间，等待树木倒下。倒下后，地面上会出现一个 棕色木材图标。", true],
	["④ 划定仓库区", "木材掉落在地上了！\n\n现在点击顶部的 [划定仓库区] 按钮，然后在地面上 按住并拖拽鼠标左键，画出一片绿色区域作为仓库。", true],
	["⑤ 等待搬运", "仓库划定完成！\n\n你的村民在空闲时会 自动去捡起木材 并搬运到仓库中。顶部的木材计数会在入库后更新。", true],
	["🎉  教程完成！", "干得漂亮！你已经掌握了最基本的生存操作：\n\n• 选中村民  →  右键命令\n• 砍树采矿  →  物品掉落\n• 划仓库区  →  自动搬运\n\n继续探索吧，愿你的殖民地繁荣昌盛！", false],
]

func _ready() -> void:
	camera = Camera2D.new()
	var cam_script = load("res://CameraController.gd")
	if cam_script:
		camera.set_script(cam_script)
	add_child(camera)
	camera.make_current()
	camera.position = Vector2(0, 0)
	
	stockpile_preview_panel = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 0.0, 0.3)
	style.border_color = Color(1.0, 1.0, 0.0, 0.8)
	style.set_border_width_all(2)
	stockpile_preview_panel.add_theme_stylebox_override("panel", style)
	stockpile_preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stockpile_preview_panel.z_index = 10
	stockpile_preview_panel.visible = false
	if has_node("TileMapLayer"):
		$TileMapLayer.add_child(stockpile_preview_panel)
	else:
		call_deferred("add_child", stockpile_preview_panel)
		
	_build_ui()
	_build_tutorial_panel()
	_show_tutorial_step(0)
	
	# 连接教程事件信号
	GameManager.item_dropped.connect(_on_item_dropped)
	GameManager.item_stored.connect(_on_item_stored)
	GameManager.stockpile_created.connect(_on_stockpile_created)
	
	var timer = get_tree().create_timer(1.0)
	timer.timeout.connect(_spawn_test_villager)

# ──────────────────────────────────────────────────────
#  顶部状态栏 UI
# ──────────────────────────────────────────────────────
func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	
	# 顶部资源面板
	var top_panel = PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# 整合：保留新版本的鼠标穿透设置
	top_panel.mouse_filter = Control.MOUSE_FILTER_PASS 
	ui_layer.add_child(top_panel)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE # 穿透容器
	top_panel.add_child(hbox)
	
	wood_label = Label.new()
	wood_label.text = "🪵 木材: 0"
	wood_label.add_theme_font_size_override("font_size", 36)
	hbox.add_child(wood_label)
	
	stone_label = Label.new()
	stone_label.text = "🪨 石头: 0"
	stone_label.add_theme_font_size_override("font_size", 36)
	hbox.add_child(stone_label)
	
	# 整合：新增肉类显示
	meat_label = Label.new()
	meat_label.text = "🍖 肉类: 0"
	meat_label.add_theme_font_size_override("font_size", 36)
	hbox.add_child(meat_label)
	
	# 弹性空间
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)
	
	stockpile_btn = Button.new()
	stockpile_btn.text = "📦 划定仓库区"
	stockpile_btn.add_theme_font_size_override("font_size", 28)
	stockpile_btn.pressed.connect(_on_stockpile_btn_pressed)
	hbox.add_child(stockpile_btn)
	
	# 整合：连接接收三个参数的资源更新函数
	GameManager.resources_updated.connect(_on_resources_updated)
	GameManager.alert_message.connect(_on_alert)
	
	# 底部状态栏（选中单位信息）
	var bottom_panel = PanelContainer.new()
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	ui_layer.add_child(bottom_panel)
	
	tooltip_label = Label.new()
	tooltip_label.text = " 未选中村民 — 使用鼠标左键点击地图上的村民"
	tooltip_label.add_theme_font_size_override("font_size", 18)
	bottom_panel.add_child(tooltip_label)

# ──────────────────────────────────────────────────────
#  环世界风格教程面板（左下角）
# ──────────────────────────────────────────────────────
func _build_tutorial_panel() -> void:
	# 主面板容器
	tut_panel = PanelContainer.new()
	tut_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tut_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tut_panel.grow_horizontal = Control.GROW_DIRECTION_END
	tut_panel.custom_minimum_size = Vector2(380, 0)
	tut_panel.position = Vector2(8, -8)
	
	# 半透明深色背景
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.92)
	style.border_color = Color(0.35, 0.65, 1.0, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	tut_panel.add_theme_stylebox_override("panel", style)
	ui_layer.add_child(tut_panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	tut_panel.add_child(vbox)
	
	# 步骤进度标题行
	tut_step_label = Label.new()
	tut_step_label.add_theme_font_size_override("font_size", 14)
	tut_step_label.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	vbox.add_child(tut_step_label)
	
	# 分隔线
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	# 步骤标题
	tut_title_label = Label.new()
	tut_title_label.add_theme_font_size_override("font_size", 20)
	tut_title_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
	vbox.add_child(tut_title_label)
	
	# 步骤说明（支持多行）
	tut_desc_label = Label.new()
	tut_desc_label.add_theme_font_size_override("font_size", 15)
	tut_desc_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	tut_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tut_desc_label.custom_minimum_size = Vector2(352, 0)
	vbox.add_child(tut_desc_label)
	
	# UI 指向提示（例如提示"看这里"）
	tut_highlight_arrow = Label.new()
	tut_highlight_arrow.add_theme_font_size_override("font_size", 16)
	tut_highlight_arrow.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	tut_highlight_arrow.visible = false
	vbox.add_child(tut_highlight_arrow)
	
	# 按钮行
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)
	
	tut_skip_btn = Button.new()
	tut_skip_btn.text = "跳过教程"
	tut_skip_btn.add_theme_font_size_override("font_size", 14)
	tut_skip_btn.pressed.connect(_skip_tutorial)
	btn_row.add_child(tut_skip_btn)
	
	var btn_spacer = Control.new()
	btn_spacer.custom_minimum_size = Vector2(8, 0)
	btn_row.add_child(btn_spacer)
	
	tut_next_btn = Button.new()
	tut_next_btn.text = "开始 ▶"
	tut_next_btn.add_theme_font_size_override("font_size", 14)
	tut_next_btn.pressed.connect(_advance_tutorial)
	btn_row.add_child(tut_next_btn)

func _show_tutorial_step(step: int) -> void:
	if step >= TUTORIAL_STEPS.size():
		_end_tutorial()
		return
	
	current_tutorial_step = step
	var data = TUTORIAL_STEPS[step]
	var auto_advance = data[2]
	var is_last = (step == TUTORIAL_STEPS.size() - 1)
	
	# 更新面板内容
	tut_step_label.text = "📋  教程  —  步骤 %d / %d" % [max(step, 1), TUTORIAL_STEPS.size() - 1] if step > 0 else "📋  教程  —  欢迎"
	tut_title_label.text = data[0]
	tut_desc_label.text = data[1]
	
	# 调整按钮状态
	if is_last:
		tut_next_btn.text = "完成 ✓"
		tut_skip_btn.visible = false
	elif auto_advance:
		tut_next_btn.text = "等待中…"
		tut_next_btn.disabled = true
		tut_skip_btn.visible = true
	else:
		tut_next_btn.text = ("开始 ▶" if step == 0 else "下一步 ▶")
		tut_next_btn.disabled = false
		tut_skip_btn.visible = (step > 0)
	
	# 步骤特定的高亮提示
	tut_highlight_arrow.visible = false
	match step:
		4:  # 画仓库区
			tut_highlight_arrow.text = "⬆  请点击顶部右侧的 [📦 划定仓库区] 按钮"
			tut_highlight_arrow.visible = true

func _advance_tutorial() -> void:
	if current_tutorial_step >= TUTORIAL_STEPS.size() - 1:
		_end_tutorial()
		return
	_show_tutorial_step(current_tutorial_step + 1)

func _skip_tutorial() -> void:
	_end_tutorial()

func _end_tutorial() -> void:
	tutorial_active = false
	tut_panel.visible = false

# ──────────────────────────────────────────────────────
#  教程事件响应
# ──────────────────────────────────────────────────────
func _on_item_dropped() -> void:
	if tutorial_active and current_tutorial_step == 3:
		_show_tutorial_step(4)

func _on_stockpile_created() -> void:
	if tutorial_active and current_tutorial_step == 4:
		_show_tutorial_step(5)

func _on_item_stored() -> void:
	if tutorial_active and current_tutorial_step == 5:
		_show_tutorial_step(6)
		# 步骤6是最后一步，启用"完成"按钮
		tut_next_btn.disabled = false

# ──────────────────────────────────────────────────────
#  仓库划定功能
# ──────────────────────────────────────────────────────
func _on_stockpile_btn_pressed() -> void:
	is_building_stockpile = not is_building_stockpile
	if is_building_stockpile:
		stockpile_btn.text = "✕ 取消划定"
		GameManager.show_alert("仓库模式：点击并拖拽左键划定，右键取消")
	else:
		stockpile_btn.text = "📦 划定仓库区"
		GameManager.show_alert("已退出划定模式")
		if stockpile_drag_start != Vector2i(-1, -1):
			stockpile_drag_start = Vector2i(-1, -1)
			stockpile_preview_panel.visible = false

func _update_stockpile_preview(end_coord: Vector2i) -> void:
	if stockpile_drag_start == Vector2i(-1, -1): return
	var tilemap = $TileMapLayer
	if not tilemap: return
	
	var min_x = min(stockpile_drag_start.x, end_coord.x)
	var max_x = max(stockpile_drag_start.x, end_coord.x)
	var min_y = min(stockpile_drag_start.y, end_coord.y)
	var max_y = max(stockpile_drag_start.y, end_coord.y)
	
	# 整合：保留新版本的预览偏移量 (Vector2(8, 8))
	var top_left_local = tilemap.map_to_local(Vector2i(min_x, min_y)) - Vector2(8, 8)
	var bottom_right_local = tilemap.map_to_local(Vector2i(max_x, max_y)) + Vector2(8, 8)
	
	stockpile_preview_panel.position = top_left_local
	stockpile_preview_panel.size = bottom_right_local - top_left_local

func _apply_stockpile_rect(start_coord: Vector2i, end_coord: Vector2i) -> void:
	var tilemap = $TileMapLayer
	if not tilemap: return
	
	var min_x = min(start_coord.x, end_coord.x)
	var max_x = max(start_coord.x, end_coord.x)
	var min_y = min(start_coord.y, end_coord.y)
	var max_y = max(start_coord.y, end_coord.y)
	
	# 首先检查选取的区域内是否含有障碍物（非空地）
	var has_solid = false
	for cx in range(min_x, max_x + 1):
		for cy in range(min_y, max_y + 1):
			var c = Vector2i(cx, cy)
			if tilemap.astar_grid.is_in_boundsv(c) and tilemap.astar_grid.is_point_solid(c):
				has_solid = true
				break
		if has_solid: break
		
	if has_solid:
		GameManager.show_alert("选取的区域内包含障碍物（非空地），无法划定仓库！")
		return
	
	for cx in range(min_x, max_x + 1):
		for cy in range(min_y, max_y + 1):
			var c = Vector2i(cx, cy)
			
			if not GameManager.is_stockpile_cell(c):
				GameManager.add_stockpile_cell(c)
				
				var visual_node = Node2D.new()
				var panel = Panel.new()
				var style = StyleBoxFlat.new()
				style.bg_color = Color(0.0, 0.0, 0.0, 0.0) # 内部完全透明
				style.border_color = Color(1.0, 1.0, 0.0, 0.4) # 淡淡黄光边框
				style.set_border_width_all(1)
				panel.add_theme_stylebox_override("panel", style)
				panel.size = Vector2(16, 16)
				panel.position = Vector2(-8, -8)
				panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
				visual_node.add_child(panel)
				
				visual_node.global_position = tilemap.map_to_local(c)
				tilemap.add_child(visual_node)
				stockpile_visuals[c] = visual_node

# ──────────────────────────────────────────────────────
#  村民生成
# ──────────────────────────────────────────────────────
func _spawn_test_villager() -> void:
	print("正在生成测试村民...")
	var tilemap = $TileMapLayer
	if not tilemap: return
	
	var center_coord = Vector2i(tilemap.mapWidth / 2, tilemap.mapHeight / 2)
	
	var spawn_coord = center_coord
	while tilemap.astar_grid.is_point_solid(spawn_coord):
		spawn_coord.x += 1
	
	var villager = CharacterBody2D.new()
	var val_script = load("res://Villager.gd")
	if val_script:
		villager.set_script(val_script)
	
	villager.name = "阿福"
	
	var sprite = Sprite2D.new()
	var tex_path = "res://art/characters/villager.png"
	
	if FileAccess.file_exists(tex_path) or FileAccess.file_exists(tex_path + ".import"):
		sprite.texture = load(tex_path)
		sprite.scale = Vector2(4.0, 4.0)
	else:
		sprite.texture = load("res://icon.svg")
		sprite.scale = Vector2(0.5, 0.5)
		
	villager.add_child(sprite)
	
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(16, 16) # 整合：保留新版本的碰撞盒大小
	collision.shape = shape
	villager.add_child(collision)
	
	villager.global_position = tilemap.map_to_local(spawn_coord)
	add_child(villager)
	villager.input_pickable = true
	camera.position = villager.global_position

# ──────────────────────────────────────────────────────
#  村民选择
# ──────────────────────────────────────────────────────
func select_villager(villager: Node2D) -> void:
	if selected_villager and selected_villager != villager:
		selected_villager.is_selected = false
		
	selected_villager = villager
	selected_villager.is_selected = true
	tooltip_label.text = " 已选中：%s — 右键点击树木（绿色）或石头（灰色）发出命令" % villager.name
	
	# 教程推进：选中村民 → 进入步骤2
	if tutorial_active and current_tutorial_step == 1:
		_show_tutorial_step(2)

# ──────────────────────────────────────────────────────
#  输入处理（已替换为版本二的动物点击逻辑）
# ──────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if is_building_stockpile:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if stockpile_drag_start != Vector2i(-1, -1):
				stockpile_drag_start = Vector2i(-1, -1)
				stockpile_preview_panel.visible = false
				get_viewport().set_input_as_handled()
			else:
				_on_stockpile_btn_pressed()
			return
			
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			var tilemap = $TileMapLayer
			if tilemap:
				var mouse_pos = get_global_mouse_position()
				var coord = tilemap.local_to_map(mouse_pos)
				if event.pressed:
					stockpile_drag_start = coord
					_update_stockpile_preview(coord)
					stockpile_preview_panel.visible = true
				else:
					if stockpile_drag_start != Vector2i(-1, -1):
						_apply_stockpile_rect(stockpile_drag_start, coord)
						stockpile_drag_start = Vector2i(-1, -1)
						stockpile_preview_panel.visible = false
			get_viewport().set_input_as_handled()
			return
			
		elif event is InputEventMouseMotion and stockpile_drag_start != Vector2i(-1, -1):
			var tilemap = $TileMapLayer
			if tilemap:
				var mouse_pos = get_global_mouse_position()
				var coord = tilemap.local_to_map(mouse_pos)
				_update_stockpile_preview(coord)
			get_viewport().set_input_as_handled()
			return

	# 👇 以下为版本二的 鼠标右键点击+动物处理 代码
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if selected_villager:
			var mouse_pos = get_global_mouse_position()
			var space_state = get_world_2d().direct_space_state
			var params = PhysicsPointQueryParameters2D.new()
			params.position = mouse_pos
			params.collide_with_bodies = true
			params.collision_mask = 0xFFFFFFFF
			var results = space_state.intersect_point(params, 16)
			
			var target_res = null
			var target_animal = null # 版本二的动物判断
			
			for res in results:
				# 判定资源
				if res.collider and res.collider.has_method("gather"):
					target_res = res.collider
					break
				# 判定动物
				if res.collider and res.collider.is_in_group("animals"):
					target_animal = res.collider
					break
			
			# 版本二的兜底检测（简洁版）
			if target_res == null and target_animal == null:
				for node in get_tree().get_nodes_in_group("trees") + get_tree().get_nodes_in_group("rocks"):
					if is_instance_valid(node) and node.global_position.distance_to(mouse_pos) < 45.0:
						target_res = node; break
				
				if target_res == null:
					for node in get_tree().get_nodes_in_group("animals"):
						if is_instance_valid(node) and node.global_position.distance_to(mouse_pos) < 45.0:
							target_animal = node; break
			
			var tilemap = $TileMapLayer
			if tilemap:
				var start_c = tilemap.local_to_map(selected_villager.global_position)
				
				# 版本二逻辑分支：攻击动物 > 采集资源 > 普通移动
				if target_animal:
					var end_c = tilemap.local_to_map(target_animal.global_position)
					var id_path = tilemap.get_path_coords(start_c, end_c, true)
					if id_path.size() > 0:
						
						var world_path: Array[Vector2] = []
						for c in id_path: world_path.append(tilemap.map_to_local(c))
						if world_path.size() > 1: world_path.pop_front()
						selected_villager.command_attack(world_path, target_animal)
						GameManager.show_alert("正在前往猎杀 " + target_animal.species)
						
						
				elif target_res:
					var end_c = target_res.grid_coord
					var id_path = tilemap.get_path_coords(start_c, end_c, true)
					if id_path.size() > 0:
						var world_path: Array[Vector2] = []
						for c in id_path: world_path.append(tilemap.map_to_local(c))
						if world_path.size() > 1: world_path.pop_front()
						selected_villager.command_gather(world_path, target_res)
						# 保留版本一的教程推进逻辑
						if tutorial_active and current_tutorial_step == 2:
							_show_tutorial_step(3)
						
				else:
					var end_c = tilemap.local_to_map(mouse_pos)
					var id_path = tilemap.get_path_coords(start_c, end_c, false)
					if id_path.size() > 0:
						var world_path: Array[Vector2] = []
						for c in id_path: world_path.append(tilemap.map_to_local(c))
						if world_path.size() > 1: world_path.pop_front()
						selected_villager.command_move(world_path)

# ──────────────────────────────────────────────────────
#  UI 响应
# ──────────────────────────────────────────────────────
func _on_resources_updated(wood: int, stone: int, meat: int) -> void:
	wood_label.text = "🪵 木材: %d" % wood
	stone_label.text = "🪨 石头: %d" % stone
	meat_label.text = "🍖 肉类: %d" % meat

func _on_alert(msg: String) -> void:
	tooltip_label.text = " " + msg

func _process(_delta: float) -> void:
	pass
