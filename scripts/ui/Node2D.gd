extends Node2D

var DEBUG_NODE2D_LOGS: bool:
	get: return SettingsManager.settings.get("debug_logs", false)

var camera: Camera2D
var selected_villager: Node2D = null
var is_building_stockpile: bool = false
var stockpile_visuals: Dictionary = {}
var stockpile_drag_start: Vector2i = Vector2i(-1, -1)
var stockpile_preview_panel: Panel
var is_building_farm: bool = false
var farm_visuals: Dictionary = {}
var farm_drag_start: Vector2i = Vector2i(-1, -1)
var villager_spawned: bool = false

var ui_layer: CanvasLayer
var wood_label: Label
var stone_label: Label
var meat_label: Label
var fiber_label: Label
var tooltip_label: Label
var char_info_panel: PanelContainer
var char_info_label: Label
var energy_bar: ProgressBar
var char_roster_btn: Button
var char_detail_dialog: PanelContainer
var char_detail_content: RichTextLabel
var mood_detail_dialog: PanelContainer
var mood_detail_content: RichTextLabel
var room_menu_dialog: PanelContainer
var room_menu_content: VBoxContainer
var current_viewing_villager_index: int = 0
var time_label: Label
var time_input: LineEdit
var canvas_modulate: CanvasModulate
var colonist_bar: HBoxContainer
var loading_layer: CanvasLayer
var loading_overlay: ColorRect
var is_loading_game: bool = false

var tut_panel: PanelContainer
var tut_step_label: Label
var tut_title_label: Label
var tut_desc_label: Label
var tut_next_btn: Button
var tut_skip_btn: Button
var tut_highlight_arrow: Label
var current_tutorial_step: int = 0
var tutorial_active: bool = true
var stockpile_btn: Button
var build_btn: Button
var construction_panel: PanelContainer = null
var room_btn: Button
var test_btn: Button
var test_menu_dialog: PanelContainer
var creature_menu_dialog: PanelContainer
var selected_creature_species: String = ""
var build_menu_instance: Node2D
var global_craft_panel: PanelContainer = null

const STOCKPILE_BUTTON_IDLE_TEXT := "📦 划定仓库区"
const STOCKPILE_BUTTON_ACTIVE_TEXT := "✅ 正在划定"

# 暂停菜单
var pause_overlay: ColorRect
var pause_menu_panel: PanelContainer
var is_game_paused: bool = false
var pause_settings_layer: CanvasLayer = null

# 存档：若不为空则在地图生成后进行恢复
var pending_save_data: Dictionary = {}

# 拆除上下文菜单
var demolish_context_panel: PanelContainer = null
var demolish_target_building: Node = null
var craft_context_panel: PanelContainer = null
var craft_hover_popup: PanelContainer = null
var craft_hover_label: Label = null
var craft_target_workbench: Node = null
var villager_inventory_dialog: PanelContainer = null
var villager_inventory_content: VBoxContainer = null
var inventory_view_villager: Node = null

# 房间名世界提示
var room_name_world_label: Label = null
var room_name_hide_timer: SceneTreeTimer = null

var TUTORIAL_STEPS = [
	["🌏 欢迎来到瓦鲁多！", "你的第一批部落成员正在这片荒野中。\n\n你需要引导他们采集资源、建设家园，才能在这片土地上生存下去。\n\n点击 [开始] 进入教程。", false],
	["① 选择村民", "使用 鼠标左键 点击地图上的村民（Godot 图标或人物精灵）来选中他。\n\n选中后，村民将高亮显示，状态栏也会显示他的名字。", true],
	["② 命令砍树", "已选中村民！\n\n现在在地图上找一棵 绿色方块（树木），使用 鼠标右键 点击它，命令村民前去砍伐。", true],
	["③ 等待木材", "村民正在赶路去砍树……\n\n砍伐需要消耗几秒时间，等待树木倒下。倒下后，地面上会出现一个 棕色木材图标。", true],
	["④ 划定仓库区", "木材掉落在地上了！\n\n现在点击顶部的 [划定仓库区] 按钮，然后在地面上 按住并拖拽鼠标左键，画出一片绿色区域作为仓库。", true],
	["⑤ 等待搬运", "仓库划定完成！\n\n你的村民在空闲时会 自动去捡起木材 并搬运到仓库中。顶部的木材计数会在入库后更新。", true],
	["🎉 教程完成！", "干得漂亮！你已经掌握了最基本的生存操作：\n\n• 选中村民 → 右键命令\n• 砍树采矿 → 物品掉落\n• 划仓库区 → 自动搬运\n\n继续探索吧，愿你的殖民地繁荣昌盛！", false],
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DEBUG_NODE2D_LOGS:
		print("=== Node2D._ready() 开始 ===")
		print("  Main节点路径: ", get_path())
		print("  是否在树中: ", is_inside_tree())
		print("  父节点: ", get_parent())
	_show_loading_overlay()
	
	canvas_modulate = CanvasModulate.new()
	add_child(canvas_modulate)
	
	stockpile_preview_panel = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 0.0, 0.3)
	style.border_color = Color(1.0, 1.0, 0.0, 0.8)
	style.set_border_width_all(2)
	stockpile_preview_panel.add_theme_stylebox_override("panel", style)
	stockpile_preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stockpile_preview_panel.z_index = 10
	stockpile_preview_panel.visible = false
	if DEBUG_NODE2D_LOGS:
		print("1. stockpile_preview_panel创建完成")
	
	_build_ui()
	if DEBUG_NODE2D_LOGS:
		print("2. _build_ui()完成")
	
	# 初始化建筑菜单
	var build_menu_scene = load("res://scenes/BuildMenu.tscn")
	if build_menu_scene:
		build_menu_instance = build_menu_scene.instantiate()
		ui_layer.add_child(build_menu_instance)
		# 注入测试资源
		if "buildings" in build_menu_instance:
			var res_paths = [
				"res://resources/StoneWall.tres",
				"res://resources/WoodWall.tres",
				"res://resources/StoneFence.tres",
				"res://resources/WoodFence.tres",
				"res://resources/StoneDoor.tres",
				"res://resources/WoodDoor.tres",
				"res://resources/StoneFenceDoor.tres",
				"res://resources/WoodFenceDoor.tres",
				"res://resources/Campfire.tres",
				"res://resources/Torch.tres",
				"res://resources/Bed.tres",
				"res://resources/Workbench.tres",
			]
			for path in res_paths:
				var building_res = load(path)
				if building_res:
					build_menu_instance.buildings.append(building_res)
			build_menu_instance._setup_menu()
	
	if has_node("TileMapLayer"):
		$TileMapLayer.add_child(stockpile_preview_panel)
		if DEBUG_NODE2D_LOGS:
			print("3. stockpile_preview已添加")
	
	_build_tutorial_panel()
	if DEBUG_NODE2D_LOGS:
		print("4. _build_tutorial_panel()完成")
	_show_tutorial_step(0)
	if DEBUG_NODE2D_LOGS:
		print("5. _show_tutorial_step()完成")
	
	if not EventBus.map_generated.is_connected(_on_map_generated):
		EventBus.map_generated.connect(_on_map_generated)
	if not EventBus.item_dropped.is_connected(_on_item_dropped):
		EventBus.item_dropped.connect(_on_item_dropped)
	if not EventBus.stockpile_created.is_connected(_on_stockpile_created):
		EventBus.stockpile_created.connect(_on_stockpile_created)
	if not EventBus.item_stored.is_connected(_on_item_stored):
		EventBus.item_stored.connect(_on_item_stored)
	if not EventBus.building_demolished.is_connected(_on_building_demolished_ui):
		EventBus.building_demolished.connect(_on_building_demolished_ui)
	if not EventBus.farm_build_requested.is_connected(_on_farm_build_requested):
		EventBus.farm_build_requested.connect(_on_farm_build_requested)
	if not EventBus.farm_updated.is_connected(_on_farm_updated):
		EventBus.farm_updated.connect(_on_farm_updated)
	var room_mgr = get_node_or_null("/root/RoomManager")
	if room_mgr and "rooms_updated" in room_mgr and not room_mgr.rooms_updated.is_connected(_on_rooms_updated):
		room_mgr.rooms_updated.connect(_on_rooms_updated)
	if DEBUG_NODE2D_LOGS:
		print("6. EventBus连接完成")
	
	camera = $Camera2D
	if camera:
		camera.make_current()
		camera.zoom = Vector2(2.0, 2.0)
		if DEBUG_NODE2D_LOGS:
			print("7. 相机设置完成")

func _on_map_generated(_map_type: int) -> void:
	if DEBUG_NODE2D_LOGS:
		print("=== _on_map_generated() ===")
	if not villager_spawned:
		villager_spawned = true
		if pending_save_data.is_empty():
			# 正常新游戏：先清空所有 autoload 残留数据，再生成新村民
			_reset_all_managers()
			_spawn_test_villager()
		else:
			# 读档：建完地形后还原动态状态（_restore_from_save 内部已重置）
			_restore_from_save(pending_save_data)
			pending_save_data = {}
		_hide_loading_overlay()

func _show_loading_overlay() -> void:
	is_loading_game = true
	if loading_layer:
		return

	var existing_layer = get_tree().root.get_node_or_null("GlobalLoadingLayer") as CanvasLayer
	if existing_layer:
		loading_layer = existing_layer
		loading_overlay = existing_layer.get_node_or_null("LoadingOverlay") as ColorRect
		return

	loading_layer = CanvasLayer.new()
	loading_layer.name = "GlobalLoadingLayer"
	loading_layer.layer = 100
	loading_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(loading_layer)

	loading_overlay = ColorRect.new()
	loading_overlay.name = "LoadingOverlay"
	loading_overlay.color = Color.BLACK
	loading_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	loading_layer.add_child(loading_overlay)

	var label = Label.new()
	label.text = "资源正疯狂加载中......"
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	label.offset_left = -520
	label.offset_top = -80
	label.offset_right = -36
	label.offset_bottom = -28
	loading_overlay.add_child(label)

func _hide_loading_overlay() -> void:
	if not loading_layer:
		return

	var layer_to_remove = loading_layer
	var overlay_to_fade = loading_overlay
	loading_layer = null
	loading_overlay = null

	var tween = create_tween()
	if is_instance_valid(overlay_to_fade):
		tween.tween_property(overlay_to_fade, "color:a", 0.0, 1.8)
		_set_stockpile_button_active()
		EventBus.alert_message.emit("仓库模式：按住左键拖动划定，右键取消")
	else:
		tween.tween_interval(1.8)
	tween.tween_callback(func():
		if is_instance_valid(layer_to_remove):
			layer_to_remove.queue_free()
		is_loading_game = false
	)

## 重置所有 autoload managers 的运行时状态
## 在新游戏开始时调用，防止上局数据（仓库格、物品列表等）残留
func _reset_all_managers() -> void:
	var stockpile_mgr = get_node_or_null("/root/StockpileManager")
	if stockpile_mgr:
		stockpile_mgr.stockpile_cells.clear()
		stockpile_mgr._stockpile_ever_created = false

	var haul_mgr = get_node_or_null("/root/HaulManager")
	if haul_mgr:
		haul_mgr.unhauled_items.clear()
		haul_mgr.stockpile_items.clear()

	var job_mgr = get_node_or_null("/root/JobManager")
	if job_mgr:
		job_mgr.jobs_queue.clear()

	var inv = get_node_or_null("/root/InventoryManager")
	if inv:
		inv.set_resources(0, 0, 0, 0)
		if "tools" in inv:
			for tool_id in inv.tools.keys():
				inv.tools[tool_id] = 0

	var time_mgr = get_node_or_null("/root/TimeManager")
	if time_mgr:
		time_mgr.current_day = 1
		time_mgr.current_hour = 8.0

	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr:
		save_mgr.reset_tracking()

	var room_mgr = get_node_or_null("/root/RoomManager")
	if room_mgr and room_mgr.has_method("reset"):
		room_mgr.reset()

	var wolf_mgr = get_node_or_null("/root/WolfManager")
	if wolf_mgr and wolf_mgr.has_method("reset"):
		wolf_mgr.reset()

	var farm_mgr = get_node_or_null("/root/FarmManager")
	if farm_mgr and farm_mgr.has_method("reset"):
		farm_mgr.reset()

	if DEBUG_NODE2D_LOGS:
		print("_reset_all_managers: 所有 autoload 数据已清空")


func _build_ui() -> void:
	if DEBUG_NODE2D_LOGS:
		print("=== _build_ui() 开始 ===")
	ui_layer = CanvasLayer.new()
	# 暂停时 UI 层依然保持激活，使暂停菜单按钮可点击
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)
	
	var top_panel = PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	ui_layer.add_child(top_panel)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_panel.add_child(hbox)
	
	wood_label = Label.new()
	wood_label.text = "🪵 木材: 0"
	wood_label.add_theme_font_size_override("font_size", 36)
	hbox.add_child(wood_label)
	
	stone_label = Label.new()
	stone_label.text = "🪨 石头: 0"
	stone_label.add_theme_font_size_override("font_size", 36)
	hbox.add_child(stone_label)
	
	meat_label = Label.new()
	meat_label.text = "🍽 食物: 0"
	meat_label.add_theme_font_size_override("font_size", 36)
	hbox.add_child(meat_label)

	fiber_label = Label.new()
	fiber_label.text = "🌿 纤维: 0"
	fiber_label.add_theme_font_size_override("font_size", 36)
	fiber_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	hbox.add_child(fiber_label)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)
	
	build_btn = Button.new()
	build_btn.text = "🏗️ 建造 (B)"
	build_btn.add_theme_font_size_override("font_size", 28)
	build_btn.pressed.connect(_on_construction_btn_pressed)
	hbox.add_child(build_btn)
	
	# 建造分类子菜单
	_build_construction_panel()

	# 制作按钮
	var craft_btn = Button.new()
	craft_btn.text = "🔨 制作"
	craft_btn.add_theme_font_size_override("font_size", 28)
	craft_btn.pressed.connect(_on_global_craft_btn_pressed)
	hbox.add_child(craft_btn)

	room_btn = Button.new()
	room_btn.text = "房间菜单"
	room_btn.add_theme_font_size_override("font_size", 28)
	room_btn.pressed.connect(_on_room_btn_pressed)
	hbox.add_child(room_btn)
	
	char_roster_btn = Button.new()
	char_roster_btn.text = "📖 人物图鉴"
	char_roster_btn.add_theme_font_size_override("font_size", 28)
	char_roster_btn.pressed.connect(_on_char_roster_pressed)
	hbox.add_child(char_roster_btn)
	
	var colonist_panel = PanelContainer.new()
	colonist_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	colonist_panel.position = Vector2(0, 60)
	colonist_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var style2 = StyleBoxEmpty.new()
	colonist_panel.add_theme_stylebox_override("panel", style2)
	ui_layer.add_child(colonist_panel)
	
	colonist_bar = HBoxContainer.new()
	colonist_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	colonist_bar.add_theme_constant_override("separation", 16)
	colonist_panel.add_child(colonist_bar)

	
	# 添加作弊按钮 (测试用)
	var cheat_btn = Button.new()
	cheat_btn.text = "➕ 资源+100"
	cheat_btn.add_theme_font_size_override("font_size", 20)
	cheat_btn.pressed.connect(_on_cheat_btn_pressed)
	hbox.add_child(cheat_btn)

	time_input = LineEdit.new()
	time_input.placeholder_text = "时间 13:30"
	time_input.text = "8:00"
	time_input.custom_minimum_size = Vector2(130, 38)
	time_input.add_theme_font_size_override("font_size", 18)
	time_input.text_submitted.connect(func(_text): _on_set_time_pressed())
	hbox.add_child(time_input)

	var set_time_btn = Button.new()
	set_time_btn.text = "设置时间"
	set_time_btn.add_theme_font_size_override("font_size", 20)
	set_time_btn.pressed.connect(_on_set_time_pressed)
	hbox.add_child(set_time_btn)
	cheat_btn.visible = false
	time_input.visible = false
	set_time_btn.visible = false
	test_btn = Button.new()
	test_btn.text = "测试菜单"
	test_btn.add_theme_font_size_override("font_size", 24)
	test_btn.pressed.connect(_on_test_menu_pressed)
	hbox.add_child(test_btn)
	
	var time_hbox = HBoxContainer.new()
	time_hbox.add_theme_constant_override("separation", 10)
	time_hbox.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_child(time_hbox)
	
	time_label = Label.new()
	time_label.text = "Day 1 - 08:00"
	time_label.add_theme_font_size_override("font_size", 24)
	time_hbox.add_child(time_label)
	
	var btn_pause = Button.new()
	btn_pause.text = "⏸️"
	btn_pause.add_theme_font_size_override("font_size", 24)
	btn_pause.pressed.connect(_on_time_btn_pressed.bind(0))
	time_hbox.add_child(btn_pause)
	
	var btn_play = Button.new()
	btn_play.text = "▶️"
	btn_play.add_theme_font_size_override("font_size", 24)
	btn_play.pressed.connect(_on_time_btn_pressed.bind(1))
	time_hbox.add_child(btn_play)
	
	var btn_speed = Button.new()
	btn_speed.text = "⏩"
	btn_speed.add_theme_font_size_override("font_size", 24)
	btn_speed.pressed.connect(_on_time_btn_pressed.bind(2))
	time_hbox.add_child(btn_speed)
	
	var time_mgr = get_node_or_null("/root/TimeManager")
	if time_mgr:
		time_mgr.time_updated.connect(_on_time_updated)

	if DEBUG_NODE2D_LOGS:
		print("UI顶部栏创建完成")
	
	if not EventBus.resources_updated.is_connected(_on_resources_updated):
		EventBus.resources_updated.connect(_on_resources_updated)
	if not EventBus.alert_message.is_connected(_on_alert):
		EventBus.alert_message.connect(_on_alert)
	
	var bottom_panel = PanelContainer.new()
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	ui_layer.add_child(bottom_panel)
	var bottom_style = StyleBoxFlat.new()
	bottom_style.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	bottom_style.content_margin_top = 8
	bottom_style.content_margin_bottom = 8
	bottom_style.content_margin_left = 16
	bottom_panel.add_theme_stylebox_override("panel", bottom_style)
	
	tooltip_label = Label.new()
	tooltip_label.text = " 未选中村民 — 使用鼠标左键点击地图上的村民"
	tooltip_label.add_theme_font_size_override("font_size", 26)
	bottom_panel.add_child(tooltip_label)
	
	char_info_panel = PanelContainer.new()
	char_info_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	char_info_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	char_info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	char_info_panel.position = Vector2(-20, -70)
	char_info_panel.visible = false
	var style3 = StyleBoxFlat.new()
	style3.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style3.set_corner_radius_all(6)
	char_info_panel.add_theme_stylebox_override("panel", style3)
	ui_layer.add_child(char_info_panel)
	
	var charBox = MarginContainer.new()
	charBox.add_theme_constant_override("margin_left", 16)
	charBox.add_theme_constant_override("margin_right", 16)
	charBox.add_theme_constant_override("margin_top", 16)
	charBox.add_theme_constant_override("margin_bottom", 16)
	char_info_panel.add_child(charBox)

	var charVBox = VBoxContainer.new()
	charVBox.add_theme_constant_override("separation", 10)
	charBox.add_child(charVBox)
	
	char_info_label = Label.new()
	char_info_label.add_theme_font_size_override("font_size", 16)
	charVBox.add_child(char_info_label)

	energy_bar = ProgressBar.new()
	energy_bar.min_value = 0
	energy_bar.max_value = 100
	energy_bar.value = 100
	energy_bar.show_percentage = true
	energy_bar.custom_minimum_size = Vector2(220, 18)
	charVBox.add_child(energy_bar)
	
	_build_char_detail_dialog()
	_build_mood_detail_dialog()
	_build_room_menu_dialog()
	_build_test_menu_dialog()
	_build_creature_menu_dialog()
	_build_pause_menu()
	if DEBUG_NODE2D_LOGS:
		print("=== _build_ui() 完成 ===")

func _build_tutorial_panel() -> void:
	tut_panel = PanelContainer.new()
	tut_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tut_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tut_panel.grow_horizontal = Control.GROW_DIRECTION_END
	tut_panel.custom_minimum_size = Vector2(380, 0)
	tut_panel.position = Vector2(8, -8)
	
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
	
	tut_step_label = Label.new()
	tut_step_label.add_theme_font_size_override("font_size", 14)
	tut_step_label.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	vbox.add_child(tut_step_label)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	tut_title_label = Label.new()
	tut_title_label.add_theme_font_size_override("font_size", 20)
	tut_title_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
	vbox.add_child(tut_title_label)
	
	tut_desc_label = Label.new()
	tut_desc_label.add_theme_font_size_override("font_size", 15)
	tut_desc_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88))
	tut_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tut_desc_label.custom_minimum_size = Vector2(352, 0)
	vbox.add_child(tut_desc_label)
	
	tut_highlight_arrow = Label.new()
	tut_highlight_arrow.add_theme_font_size_override("font_size", 16)
	tut_highlight_arrow.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	tut_highlight_arrow.visible = false
	vbox.add_child(tut_highlight_arrow)
	
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
	
	tut_step_label.text = "📋 教程 — 步骤 %d / %d" % [max(step, 1), TUTORIAL_STEPS.size() - 1] if step > 0 else "📋 教程 — 欢迎"
	tut_title_label.text = data[0]
	tut_desc_label.text = data[1]
	
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
	
	tut_highlight_arrow.visible = false
	match step:
		4:
			tut_highlight_arrow.text = "⬆ 请点击顶部右侧的 [📦 划定仓库区] 按钮"
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

func _on_item_dropped(_item: Node2D = null, _item_type: int = 0, _amount: int = 0) -> void:
	if tutorial_active and current_tutorial_step == 3:
		_show_tutorial_step(4)

func _on_stockpile_created() -> void:
	if tutorial_active and current_tutorial_step == 4:
		_show_tutorial_step(5)

func _on_item_stored(_type: int, _amount: int) -> void:
	if tutorial_active and current_tutorial_step == 5:
		_show_tutorial_step(6)
		tut_next_btn.disabled = false

func _on_stockpile_btn_pressed() -> void:
	is_building_stockpile = not is_building_stockpile
	if is_building_stockpile:
		EventBus.alert_message.emit("仓库模式：点击并拖拽左键划定，右键取消")
	else:
		EventBus.alert_message.emit("已退出划定模式")
		if stockpile_drag_start != Vector2i(-1, -1):
			stockpile_drag_start = Vector2i(-1, -1)
			if stockpile_preview_panel:
				stockpile_preview_panel.visible = false

func _set_stockpile_button_idle() -> void:
	if stockpile_btn:
		stockpile_btn.text = STOCKPILE_BUTTON_IDLE_TEXT

func _set_stockpile_button_active() -> void:
	if stockpile_btn:
		stockpile_btn.text = STOCKPILE_BUTTON_ACTIVE_TEXT

func _on_farm_build_requested(_data: BuildingResource) -> void:
	is_building_farm = true
	is_building_stockpile = false
	farm_drag_start = Vector2i(-1, -1)
	if stockpile_preview_panel:
		stockpile_preview_panel.visible = false
	EventBus.alert_message.emit("农田模式：按住左键拖动画农田，右键取消")

func _ensure_stockpile_button_text() -> void:
	_set_stockpile_button_idle()

func _on_farm_updated() -> void:
	_rebuild_farm_visuals()

func _on_build_btn_pressed() -> void:
	EventBus.toggle_build_menu.emit()

func _on_construction_btn_pressed() -> void:
	if construction_panel:
		construction_panel.visible = not construction_panel.visible
		if construction_panel.visible:
			var vp_size = get_viewport().get_visible_rect().size
			construction_panel.position = (vp_size - construction_panel.size) / 2.0

func _build_construction_panel() -> void:
	construction_panel = PanelContainer.new()
	construction_panel.visible = false
	construction_panel.z_index = 90
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.1, 0.96)
	style.border_color = Color(0.85, 0.7, 0.35, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	construction_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	construction_panel.add_child(vbox)

	var title = Label.new()
	title.text = "🏗️ 建造菜单"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	# 建筑按钮
	var buildings_btn = Button.new()
	buildings_btn.text = "🧱 建筑"
	buildings_btn.add_theme_font_size_override("font_size", 28)
	buildings_btn.custom_minimum_size = Vector2(220, 50)
	buildings_btn.pressed.connect(func():
		construction_panel.visible = false
		EventBus.toggle_build_menu.emit()
	)
	vbox.add_child(buildings_btn)

	# 区域按钮
	var zones_btn = Button.new()
	zones_btn.text = "📐 区域"
	zones_btn.add_theme_font_size_override("font_size", 28)
	zones_btn.custom_minimum_size = Vector2(220, 50)
	zones_btn.pressed.connect(func():
		construction_panel.visible = false
		_show_zone_submenu()
	)
	vbox.add_child(zones_btn)

	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.pressed.connect(func(): construction_panel.visible = false)
	vbox.add_child(close_btn)

	ui_layer.add_child(construction_panel)

var zone_submenu: PanelContainer = null

func _show_zone_submenu() -> void:
	if zone_submenu and is_instance_valid(zone_submenu):
		zone_submenu.visible = true
		var vp_size = get_viewport().get_visible_rect().size
		zone_submenu.position = (vp_size - zone_submenu.size) / 2.0
		return

	zone_submenu = PanelContainer.new()
	zone_submenu.z_index = 92
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.1, 0.96)
	style.border_color = Color(0.55, 0.8, 0.45, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	zone_submenu.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	zone_submenu.add_child(vbox)

	var title = Label.new()
	title.text = "📐 区域选择"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.6, 0.92, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	# 农田按钮
	var farm_btn = Button.new()
	farm_btn.text = "🌾 农田"
	farm_btn.add_theme_font_size_override("font_size", 26)
	farm_btn.custom_minimum_size = Vector2(200, 45)
	farm_btn.pressed.connect(func():
		zone_submenu.visible = false
		var farm_res = load("res://resources/Farm.tres")
		if farm_res:
			EventBus.build_requested.emit(farm_res)
	)
	vbox.add_child(farm_btn)

	# 仓库按钮
	var stockpile_zone_btn = Button.new()
	stockpile_zone_btn.text = "📦 仓库"
	stockpile_zone_btn.add_theme_font_size_override("font_size", 26)
	stockpile_zone_btn.custom_minimum_size = Vector2(200, 45)
	stockpile_zone_btn.pressed.connect(func():
		zone_submenu.visible = false
		_on_stockpile_btn_pressed()
	)
	vbox.add_child(stockpile_zone_btn)

	var close_btn = Button.new()
	close_btn.text = "返回"
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.pressed.connect(func(): zone_submenu.visible = false)
	vbox.add_child(close_btn)

	ui_layer.add_child(zone_submenu)

func _on_cheat_btn_pressed() -> void:
	var inv = get_node_or_null("/root/InventoryManager")
	if inv:
		inv.set_resources(inv.wood + 100, inv.stone + 100, inv.meat + 100, inv.fiber + 100)
		EventBus.alert_message.emit("作弊成功：资源 +100")

# ========== 全局制作面板 ==========

func _on_global_craft_btn_pressed() -> void:
	_build_global_craft_panel()
	if global_craft_panel:
		global_craft_panel.visible = not global_craft_panel.visible
		if global_craft_panel.visible:
			_refresh_global_craft_panel()
			var vp_size = get_viewport().get_visible_rect().size
			global_craft_panel.position = (vp_size - global_craft_panel.size) / 2.0

var _craft_panel_vbox: VBoxContainer = null

func _build_global_craft_panel() -> void:
	if global_craft_panel and is_instance_valid(global_craft_panel):
		return

	global_craft_panel = PanelContainer.new()
	global_craft_panel.visible = false
	global_craft_panel.z_index = 95
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.065, 0.97)
	style.border_color = Color(0.85, 0.65, 0.3, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	global_craft_panel.add_theme_stylebox_override("panel", style)

	_craft_panel_vbox = VBoxContainer.new()
	_craft_panel_vbox.add_theme_constant_override("separation", 6)
	global_craft_panel.add_child(_craft_panel_vbox)
	ui_layer.add_child(global_craft_panel)

func _refresh_global_craft_panel() -> void:
	if not _craft_panel_vbox:
		return
	# 清空旧内容
	for ch in _craft_panel_vbox.get_children():
		ch.queue_free()

	var job_mgr = get_node_or_null("/root/JobManager")
	if not job_mgr:
		return

	# 标题
	var title = Label.new()
	title.text = "🔨 制作"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_craft_panel_vbox.add_child(title)

	var sep1 = HSeparator.new()
	_craft_panel_vbox.add_child(sep1)

	# ==== 基础制作 ====
	var basic_title = Label.new()
	basic_title.text = "── 基础制作 ──"
	basic_title.add_theme_font_size_override("font_size", 22)
	basic_title.add_theme_color_override("font_color", Color(0.75, 0.92, 0.7))
	basic_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_craft_panel_vbox.add_child(basic_title)

	for recipe_id in job_mgr.get_basic_recipe_ids():
		var recipe: Dictionary = job_mgr.get_craft_recipe(str(recipe_id))
		if recipe.is_empty():
			continue
		var btn = Button.new()
		btn.text = str(recipe.get("name", recipe_id))
		btn.custom_minimum_size = Vector2(260, 42)
		btn.add_theme_font_size_override("font_size", 20)
		var icon_path = str(recipe.get("icon", ""))
		if icon_path != "":
			var tex = load(icon_path)
			if tex:
				btn.icon = tex
				btn.expand_icon = true
				btn.add_theme_constant_override("icon_max_width", 28)
		var rid = str(recipe_id)
		btn.mouse_entered.connect(func(): _show_craft_hover(recipe))
		btn.mouse_exited.connect(_hide_craft_hover)
		btn.pressed.connect(func(): _request_craft_from_panel(rid))
		_craft_panel_vbox.add_child(btn)

	var sep2 = HSeparator.new()
	_craft_panel_vbox.add_child(sep2)

	# ==== 工作台制作 ====
	var has_wb = job_mgr.has_workbench_in_world()

	var wb_title = Label.new()
	if has_wb:
		wb_title.text = "── 工作台配方 ──"
		wb_title.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
	else:
		wb_title.text = "── 工作台配方 (🔒未解锁) ──"
		wb_title.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	wb_title.add_theme_font_size_override("font_size", 22)
	wb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_craft_panel_vbox.add_child(wb_title)

	if not has_wb:
		var hint = Label.new()
		hint.text = "▶ 放置工作台以解锁更多配方"
		hint.add_theme_font_size_override("font_size", 18)
		hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_craft_panel_vbox.add_child(hint)

	for recipe_id in job_mgr.get_workbench_recipe_ids():
		var recipe: Dictionary = job_mgr.get_craft_recipe(str(recipe_id))
		if recipe.is_empty():
			continue
		var btn = Button.new()
		if has_wb:
			btn.text = str(recipe.get("name", recipe_id))
		else:
			btn.text = "🔒 " + str(recipe.get("name", recipe_id))
			btn.disabled = true
		btn.custom_minimum_size = Vector2(260, 42)
		btn.add_theme_font_size_override("font_size", 20)
		var icon_path = str(recipe.get("icon", ""))
		if icon_path != "":
			var tex = load(icon_path)
			if tex:
				btn.icon = tex
				btn.expand_icon = true
				btn.add_theme_constant_override("icon_max_width", 28)
		var rid = str(recipe_id)
		btn.mouse_entered.connect(func(): _show_craft_hover(recipe))
		btn.mouse_exited.connect(_hide_craft_hover)
		if has_wb:
			btn.pressed.connect(func(): _request_craft_from_panel(rid))
		_craft_panel_vbox.add_child(btn)

	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(func(): global_craft_panel.visible = false)
	_craft_panel_vbox.add_child(close_btn)

func _request_craft_from_panel(recipe_id: String) -> void:
	var job_mgr = get_node_or_null("/root/JobManager")
	if not job_mgr:
		return
	var recipe: Dictionary = job_mgr.get_craft_recipe(recipe_id)
	if recipe.is_empty():
		return
	if not _has_recipe_resources(recipe):
		EventBus.alert_message.emit("资源不足，无法制作 %s" % str(recipe.get("name", recipe_id)))
		return

	var is_basic = job_mgr.is_basic_recipe(recipe_id)

	if is_basic:
		# 基础配方：找一个空闲村民，在原地制作
		# 创建一个临时的"craft_spot"节点，让村民过去制作
		var villager = _find_idle_or_selected_villager()
		if not villager:
			EventBus.alert_message.emit("没有可用的村民来制作")
			return
		# 创建一个临时工作点（在村民位置）
		var craft_spot = Node2D.new()
		craft_spot.global_position = villager.global_position
		craft_spot.add_to_group("buildings")
		craft_spot.set_meta("is_workbench", true)
		craft_spot.set_meta("is_temp_craft_spot", true)
		craft_spot.set("is_workbench", true)
		get_tree().current_scene.add_child(craft_spot)
		_deduct_recipe_resources(recipe)
		if job_mgr.add_craft_job(recipe_id, craft_spot):
			EventBus.alert_message.emit("已安排制作：%s" % str(recipe.get("name", recipe_id)))
		else:
			EventBus.alert_message.emit("制作安排失败")
			craft_spot.queue_free()
	else:
		# 工作台配方：找最近的工作台
		var workbench = job_mgr.find_nearest_workbench(Vector2(960, 540))
		if not workbench:
			EventBus.alert_message.emit("需要先放置工作台")
			return
		_deduct_recipe_resources(recipe)
		if job_mgr.add_craft_job(recipe_id, workbench):
			EventBus.alert_message.emit("已安排合成：%s" % str(recipe.get("name", recipe_id)))
		else:
			EventBus.alert_message.emit("这个工作台已经有合成任务了")

	if global_craft_panel:
		global_craft_panel.visible = false

func _find_idle_or_selected_villager() -> Node2D:
	if selected_villager and is_instance_valid(selected_villager):
		return selected_villager
	for v in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(v) and "current_task" in v and v.current_task == 0:  # Task.IDLE == 0
			return v
	# 如果没有空闲的，返回第一个村民
	var villagers = get_tree().get_nodes_in_group("villagers")
	if villagers.size() > 0:
		return villagers[0]
	return null

func _update_stockpile_preview(end_coord: Vector2i) -> void:
	var drag_start = farm_drag_start if is_building_farm else stockpile_drag_start
	if drag_start == Vector2i(-1, -1): return
	var tilemap = $TileMapLayer
	if not tilemap: return
	
	var min_x = min(drag_start.x, end_coord.x)
	var max_x = max(drag_start.x, end_coord.x)
	var min_y = min(drag_start.y, end_coord.y)
	var max_y = max(drag_start.y, end_coord.y)
	
	var top_left_local = tilemap.map_to_local(Vector2i(min_x, min_y)) - Vector2(8, 8)
	var bottom_right_local = tilemap.map_to_local(Vector2i(max_x, max_y)) + Vector2(8, 8)
	
	stockpile_preview_panel.position = top_left_local
	stockpile_preview_panel.size = bottom_right_local - top_left_local

func _apply_stockpile_rect(start_coord: Vector2i, end_coord: Vector2i) -> void:
	var tilemap = $TileMapLayer
	var haul_manager = get_node_or_null("/root/HaulManager")
	if not tilemap: return

	var min_x = min(start_coord.x, end_coord.x)
	var max_x = max(start_coord.x, end_coord.x)
	var min_y = min(start_coord.y, end_coord.y)
	var max_y = max(start_coord.y, end_coord.y)

	var has_solid = false
	for cx in range(min_x, max_x + 1):
		for cy in range(min_y, max_y + 1):
			var c = Vector2i(cx, cy)
			if tilemap.astar_grid.is_in_boundsv(c) and tilemap.astar_grid.is_point_solid(c):
				has_solid = true
				break
		if has_solid: break

	if has_solid:
		EventBus.alert_message.emit("选取的区域内包含障碍物（非空地），无法划定仓库！")
		return

	for cx in range(min_x, max_x + 1):
		for cy in range(min_y, max_y + 1):
			var c = Vector2i(cx, cy)

			if haul_manager and not haul_manager.is_stockpile_cell(c):
				haul_manager.add_stockpile_cell(c)

				var visual_node = Node2D.new()
				var panel = Panel.new()
				var style = StyleBoxFlat.new()
				style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
				style.border_color = Color(1.0, 1.0, 0.0, 0.4)
				style.set_border_width_all(1)
				panel.add_theme_stylebox_override("panel", style)
				panel.size = Vector2(16, 16)
				panel.position = Vector2(-8, -8)
				panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
				visual_node.add_child(panel)

				visual_node.global_position = tilemap.map_to_local(c)
				tilemap.add_child(visual_node)
				stockpile_visuals[c] = visual_node

func _apply_farm_rect(start_coord: Vector2i, end_coord: Vector2i) -> void:
	var tilemap = $TileMapLayer
	var farm_mgr = get_node_or_null("/root/FarmManager")
	if not tilemap or not farm_mgr:
		return

	var min_x = min(start_coord.x, end_coord.x)
	var max_x = max(start_coord.x, end_coord.x)
	var min_y = min(start_coord.y, end_coord.y)
	var max_y = max(start_coord.y, end_coord.y)

	var cells: Array[Vector2i] = []
	var haul_manager = get_node_or_null("/root/HaulManager")
	for cx in range(min_x, max_x + 1):
		for cy in range(min_y, max_y + 1):
			var c = Vector2i(cx, cy)
			if not tilemap.astar_grid or not tilemap.astar_grid.is_in_boundsv(c):
				EventBus.alert_message.emit("农田矩形内有不可用地块，无法划定")
				return
			if tilemap.astar_grid.is_point_solid(c):
				EventBus.alert_message.emit("农田矩形内有障碍物，无法划定")
				return
			if haul_manager and haul_manager.has_method("is_stockpile_cell") and haul_manager.is_stockpile_cell(c):
				EventBus.alert_message.emit("农田不能和仓库区重叠")
				return
			if not farm_mgr.get_plot_at_cell(c).is_empty():
				EventBus.alert_message.emit("农田不能和已有农田重叠")
				return
			cells.append(c)

	if cells.is_empty():
		EventBus.alert_message.emit("这里不能划定农田")
		return

	var plot_id = farm_mgr.create_plot(cells)
	if plot_id != -1:
		EventBus.alert_message.emit("农田已划定，左键点击农田设置作物")

func _rebuild_farm_visuals() -> void:
	var tilemap = get_node_or_null("TileMapLayer")
	if not tilemap:
		return
	for visual in farm_visuals.values():
		if is_instance_valid(visual):
			visual.queue_free()
	farm_visuals.clear()

	var farm_mgr = get_node_or_null("/root/FarmManager")
	if not farm_mgr:
		return
	for plot in farm_mgr.get_plots():
		for cell in plot.get("cells", []):
			_create_farm_visual(tilemap, cell, plot)

func _create_farm_visual(tilemap: Node, cell: Vector2i, plot: Dictionary) -> void:
	var visual_node = Node2D.new()
	visual_node.z_index = 1

	var panel = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.38, 0.22, 0.10, 0.45)
	style.border_color = Color(0.75, 0.50, 0.22, 0.65)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	panel.size = Vector2(16, 16)
	panel.position = Vector2(-8, -8)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_node.add_child(panel)

	var crop = str(plot.get("crop", ""))
	if crop != "":
		var farm_mgr = get_node_or_null("/root/FarmManager")
		var stage = farm_mgr.get_stage(plot, cell) if farm_mgr else 1
		if stage <= 0:
			visual_node.global_position = tilemap.to_global(tilemap.map_to_local(cell))
			tilemap.add_child(visual_node)
			farm_visuals[cell] = visual_node
			return
		var tex_path = "res://art/crops/%s_stage%d.svg" % [crop, stage]
		if FileAccess.file_exists(tex_path) or FileAccess.file_exists(tex_path + ".import"):
			var sprite = Sprite2D.new()
			sprite.texture = load(tex_path)
			sprite.scale = Vector2(0.22, 0.22)
			sprite.z_index = 2
			visual_node.add_child(sprite)

	visual_node.global_position = tilemap.to_global(tilemap.map_to_local(cell))
	tilemap.add_child(visual_node)
	farm_visuals[cell] = visual_node

func _spawn_test_villager() -> void:
	var tilemap = $TileMapLayer
	if not tilemap: return
	if not tilemap.astar_grid:
		await get_tree().create_timer(1.0).timeout
		_spawn_test_villager()
		return
	var center_coord = Vector2i(tilemap.mapWidth / 2, tilemap.mapHeight / 2)
	var spawn_coord = center_coord
	while tilemap.astar_grid.is_point_solid(spawn_coord):
		spawn_coord.x += 1
		
	var names = ["阿福", "旺财", "来福"]
	for i in range(3):
		var sc = spawn_coord + Vector2i(i, 0)
		while tilemap.astar_grid.is_point_solid(sc):
			sc.y += 1
		
		var villager = CharacterBody2D.new()
		var val_script = load("res://scripts/entities/Villager.gd")
		if val_script: villager.set_script(val_script)
		villager.name = names[i]
		villager.z_index = 10
		
		var sprite = Sprite2D.new()
		var tex_idx = i + 1
		var tex_path = "res://art/characters/villager" + str(tex_idx) + ".png"
		if FileAccess.file_exists(tex_path) or FileAccess.file_exists(tex_path + ".import"):
			sprite.texture = load(tex_path)
			sprite.scale = Vector2(1.6, 1.6)
		else:
			sprite.texture = load("res://icon.svg")
			sprite.scale = Vector2(0.4, 0.4)
		villager.add_child(sprite)
		
		var collision = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(16, 16)
		collision.shape = shape
		villager.add_child(collision)
		
		var world_pos = tilemap.map_to_local(sc)
		villager.global_position = world_pos
		tilemap.add_child(villager)
		villager.input_pickable = true
		villager.add_to_group("villagers")
		
		if i == 0:
			camera.position = world_pos
			
		if colonist_bar:
			var btn = Button.new()
			btn.text = villager.name
			btn.custom_minimum_size = Vector2(80, 40)
			var tmp_vil = villager # capture for lambda
			btn.pressed.connect(func(): select_villager(tmp_vil))
			colonist_bar.add_child(btn)
			
	var all_vils = get_tree().get_nodes_in_group("villagers")
	for v in all_vils:
		for other in all_vils:
			if v != other:
				v.social_relations[other.name] = randi() % 111 - 30 # -30 to 80
	if DEBUG_NODE2D_LOGS:
		print("三名村民及其社会关系生成完成!")

func select_villager(villager: Node2D) -> void:
	if selected_villager and selected_villager != villager:
		selected_villager.is_selected = false
		if "has_node" in selected_villager and selected_villager.has_node("SelectionRing"):
			selected_villager.get_node("SelectionRing").queue_free()
		
	selected_villager = villager
	selected_villager.is_selected = true
	
	# 添加高亮光环
	if not selected_villager.has_node("SelectionRing"):
		var ring = Sprite2D.new()
		ring.name = "SelectionRing"
		var tex_path = "res://art/ui/selection_ring.png"
		if FileAccess.file_exists(tex_path) or FileAccess.file_exists(tex_path + ".import"):
			ring.texture = load(tex_path)
			ring.scale = Vector2(0.3, 0.3)
			ring.modulate = Color(1.0, 1.0, 0.0, 0.6)
			ring.z_index = -1
			selected_villager.add_child(ring)
			
	tooltip_label.text = " 已选中：%s — 右键点击树木（绿色）或石头（灰色）发出命令" % villager.name
	if char_info_panel:
		char_info_panel.visible = true
		_update_char_info()
	
	if tutorial_active and current_tutorial_step == 1:
		_show_tutorial_step(2)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if is_loading_game or loading_layer:
				get_viewport().set_input_as_handled()
				return
			if selected_creature_species != "":
				selected_creature_species = ""
				EventBus.alert_message.emit("已取消生成生物")
				get_viewport().set_input_as_handled()
				return
			_toggle_pause()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_B:
			if not is_game_paused:
				_on_construction_btn_pressed()

	if selected_creature_species != "":
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			selected_creature_species = ""
			EventBus.alert_message.emit("已取消生成生物")
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_spawn_test_creature(selected_creature_species, get_global_mouse_position())
			get_viewport().set_input_as_handled()
			return

	if is_building_farm:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			is_building_farm = false
			farm_drag_start = Vector2i(-1, -1)
			if stockpile_preview_panel:
				stockpile_preview_panel.visible = false
			EventBus.alert_message.emit("已取消农田划定")
			get_viewport().set_input_as_handled()
			return
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			var tilemap = $TileMapLayer
			if tilemap:
				var mouse_pos = get_global_mouse_position()
				var coord = tilemap.local_to_map(tilemap.to_local(mouse_pos))
				if event.pressed:
					farm_drag_start = coord
					_update_stockpile_preview(coord)
					stockpile_preview_panel.visible = true
				else:
					if farm_drag_start != Vector2i(-1, -1):
						_apply_farm_rect(farm_drag_start, coord)
						farm_drag_start = Vector2i(-1, -1)
						stockpile_preview_panel.visible = false
						is_building_farm = false
			get_viewport().set_input_as_handled()
			return
		elif event is InputEventMouseMotion and farm_drag_start != Vector2i(-1, -1):
			var tilemap = $TileMapLayer
			if tilemap:
				var mouse_pos = get_global_mouse_position()
				var coord = tilemap.local_to_map(tilemap.to_local(mouse_pos))
				_update_stockpile_preview(coord)
			get_viewport().set_input_as_handled()
			return

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
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 先关闭可能打开的拆除菜单
		_close_demolish_menu()
		_close_craft_menu()
		if not is_building_stockpile:
			if selected_villager:
				var mouse_pos = get_global_mouse_position()
				var tool_drop = _get_tool_drop_at(mouse_pos)
				if tool_drop:
					_pickup_tool_drop(selected_villager, tool_drop)
					get_viewport().set_input_as_handled()
					return
				selected_villager.is_selected = false
				if "has_node" in selected_villager and selected_villager.has_node("SelectionRing"):
					selected_villager.get_node("SelectionRing").queue_free()
				selected_villager = null
				tooltip_label.text = " 未选中村民 — 使用鼠标左键点击地图上的村民"
				if char_info_panel: char_info_panel.visible = false
			else:
				# 无选中村民时，左键点击检测建筑（可拆除）或房间空地（显示房间名）
				var mouse_pos = get_global_mouse_position()
				var clicked_building = _get_building_at(mouse_pos)
				if clicked_building:
					_show_demolish_menu(clicked_building, mouse_pos)
					get_viewport().set_input_as_handled()
				else:
					var area_tilemap = $TileMapLayer
					if area_tilemap:
						var clicked_cell = area_tilemap.local_to_map(area_tilemap.to_local(mouse_pos))
						var farm_mgr = get_node_or_null("/root/FarmManager")
						if farm_mgr and not farm_mgr.get_plot_at_cell(clicked_cell).is_empty():
							_show_farm_cell_menu(clicked_cell, mouse_pos)
							get_viewport().set_input_as_handled()
							return
						var haul_mgr = get_node_or_null("/root/HaulManager")
						if haul_mgr and haul_mgr.has_method("is_stockpile_cell") and haul_mgr.is_stockpile_cell(clicked_cell):
							_show_stockpile_cell_menu(clicked_cell, mouse_pos)
							get_viewport().set_input_as_handled()
							return
					# 检查是否点击了某个房间内的空地
					var tilemap = $TileMapLayer
					if tilemap:
						var coord = tilemap.local_to_map(tilemap.to_local(mouse_pos))
						var room_mgr = get_node_or_null("/root/RoomManager")
						if room_mgr and room_mgr.has_method("get_room_at_coord"):
							var room = room_mgr.get_room_at_coord(coord)
							if not room.is_empty():
								_show_room_name_at(mouse_pos, str(room.get("name", "房间")))
								get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# 右键关闭拆除菜单
		_close_demolish_menu()
		_close_craft_menu()
		var mouse_pos = get_global_mouse_position()
		if selected_villager:
			var clicked_villager = _get_villager_at(mouse_pos)
			if clicked_villager and clicked_villager != selected_villager and bool(clicked_villager.get("is_unconscious") if "is_unconscious" in clicked_villager else false):
				if selected_villager.has_method("use_bandage_on") and selected_villager.use_bandage_on(clicked_villager):
					EventBus.alert_message.emit("%s 使用绷带救醒了 %s" % [selected_villager.name, clicked_villager.name])
				else:
					EventBus.alert_message.emit("%s 没有绷带，无法救治" % selected_villager.name)
				get_viewport().set_input_as_handled()
				return
			if clicked_villager == selected_villager or _is_clicking_villager(selected_villager, mouse_pos):
				_show_villager_inventory(selected_villager)
				get_viewport().set_input_as_handled()
				return
		var clicked_building = _get_building_at(mouse_pos)
		if clicked_building and bool(clicked_building.get("is_workbench") if "is_workbench" in clicked_building else false):
			_show_craft_menu(clicked_building, mouse_pos)
			get_viewport().set_input_as_handled()
			return

		var space_state = get_world_2d().direct_space_state
		var params = PhysicsPointQueryParameters2D.new()
		params.position = mouse_pos
		params.collide_with_bodies = true
		params.collision_mask = 0xFFFFFFFF
		var results = space_state.intersect_point(params, 16)
		
		var target_res = null
		var target_animal = null
		
		for res in results:
			if res.collider and res.collider.has_method("gather"):
				target_res = res.collider
				break
			if res.collider and res.collider.is_in_group("animals"):
				target_animal = res.collider
				break
		
		if target_res == null and target_animal == null:
			for node in get_tree().get_nodes_in_group("trees") + get_tree().get_nodes_in_group("rocks"):
				if is_instance_valid(node) and node.global_position.distance_to(mouse_pos) < 14.0:
					target_res = node; break
			
			if target_res == null:
				for node in get_tree().get_nodes_in_group("animals"):
					if is_instance_valid(node) and node.global_position.distance_to(mouse_pos) < 24.0:
						target_animal = node; break

		var clicked_job_target = target_animal if target_animal else target_res
		var job_mgr_for_cancel = get_node_or_null("/root/JobManager")
		if clicked_job_target and job_mgr_for_cancel and job_mgr_for_cancel.has_method("has_job") and job_mgr_for_cancel.has_job(clicked_job_target):
			job_mgr_for_cancel.remove_job(clicked_job_target)
			clicked_job_target.modulate = Color(1.0, 1.0, 1.0)
			EventBus.alert_message.emit("已取消该目标的命令")
			get_viewport().set_input_as_handled()
			return
		
		if selected_villager:
			var tilemap = $TileMapLayer
			if tilemap:
				var start_c = tilemap.local_to_map(selected_villager.global_position)
				if target_animal:
					var end_c = tilemap.local_to_map(target_animal.global_position)
					var id_path = tilemap.get_path_coords(start_c, end_c, true)
					if id_path.size() > 0:
						var world_path: Array[Vector2] = []
						for c in id_path: world_path.append(tilemap.map_to_local(c))
						if world_path.size() > 1: world_path.remove_at(0)
						selected_villager.command_attack(world_path, target_animal)
						EventBus.alert_message.emit("正在前往猎杀 " + target_animal.species)
						
				elif target_res:
					var end_c = target_res.grid_coord
					var id_path = tilemap.get_path_coords(start_c, end_c, true)
					if id_path.size() > 0:
						var world_path: Array[Vector2] = []
						for c in id_path: world_path.append(tilemap.map_to_local(c))
						if world_path.size() > 1: world_path.remove_at(0)
						selected_villager.command_gather(world_path, target_res)
						if tutorial_active and current_tutorial_step == 2:
							_show_tutorial_step(3)
						
				else:
					var end_c = tilemap.local_to_map(mouse_pos)
					var id_path = tilemap.get_path_coords(start_c, end_c, false)
					if id_path.size() > 0:
						var world_path: Array[Vector2] = []
						for c in id_path: world_path.append(tilemap.map_to_local(c))
						if world_path.size() > 1: world_path.remove_at(0)
						selected_villager.command_move(world_path)
		else:
			# Not selecting anyone: Add Global Job
			var job_mgr = get_node_or_null("/root/JobManager")
			if job_mgr:
				if target_animal:
					job_mgr.add_job("HUNT", target_animal)
					target_animal.modulate = Color(1.0, 0.5, 0.5)
					EventBus.alert_message.emit("已标记全局任务：猎杀 " + target_animal.species)
				elif target_res:
					job_mgr.add_job("GATHER", target_res)
					target_res.modulate = Color(0.8, 0.8, 1.0)
					if tutorial_active and current_tutorial_step == 2:
						_show_tutorial_step(3)
					EventBus.alert_message.emit("已标记全局任务：开采资源")

func _on_resources_updated(w: int, s: int, m: int, f: int = 0) -> void:
	if is_instance_valid(wood_label):  wood_label.text  = "🪵 木材: %d" % w
	if is_instance_valid(stone_label): stone_label.text = "🪨 石头: %d" % s
	if is_instance_valid(meat_label):  meat_label.text  = "🍽 食物: %d" % m
	if is_instance_valid(fiber_label): fiber_label.text = "🌿 纤维: %d" % f

func _on_alert(msg: String) -> void:
	if is_instance_valid(tooltip_label): tooltip_label.text = " " + msg

func _on_time_btn_pressed(level: int) -> void:
	var time_mgr = get_node_or_null("/root/TimeManager")
	if time_mgr:
		time_mgr.set_time_scale(level)

func _on_set_time_pressed() -> void:
	var time_mgr = get_node_or_null("/root/TimeManager")
	if not time_mgr or not time_input:
		return

	var parsed_hour = _parse_time_input(time_input.text)
	if parsed_hour < 0.0:
		EventBus.alert_message.emit("请输入 0-23、13.5 或 13:30 格式的时间")
		return

	time_mgr.current_hour = parsed_hour
	var minute = int(fmod(time_mgr.current_hour * 60.0, 60.0))
	time_mgr.time_updated.emit(time_mgr.current_day, time_mgr.current_hour, minute)
	EventBus.alert_message.emit("时间已设置为 %02d:%02d" % [int(time_mgr.current_hour), minute])

func _parse_time_input(text: String) -> float:
	var trimmed = text.strip_edges()
	if trimmed.is_empty():
		return -1.0

	if ":" in trimmed:
		var parts = trimmed.split(":", false)
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return -1.0
		var hour = int(parts[0])
		var minute = int(parts[1])
		if hour < 0 or hour > 23 or minute < 0 or minute > 59:
			return -1.0
		return float(hour) + float(minute) / 60.0

	if not trimmed.is_valid_float():
		return -1.0
	var hour_float = float(trimmed)
	if hour_float < 0.0 or hour_float >= 24.0:
		return -1.0
	return hour_float

func _on_time_updated(day: int, hour: float, minute: int) -> void:
	if time_label:
		time_label.text = "Day %d - %02d:%02d" % [day, int(hour), minute]

func _process(_delta: float) -> void:
	# 仓库按钮状态不再需要在_process中维护（已移至区域子菜单）
	pass

	if selected_villager and char_info_panel and char_info_panel.visible:
		_update_char_info()
	if char_detail_dialog and char_detail_dialog.visible:
		_update_char_detail_dialog()
	if mood_detail_dialog and mood_detail_dialog.visible:
		_update_mood_detail_dialog()

	var time_mgr = get_node_or_null("/root/TimeManager")
	if time_mgr and is_instance_valid(canvas_modulate):
		canvas_modulate.color = time_mgr.get_sun_color()

func _update_char_info() -> void:
	if not is_instance_valid(selected_villager): return
	var text = "【%s】状态面板\n" % selected_villager.name
	var task_name = "空闲"
	var is_unconscious = bool(selected_villager.get("is_unconscious") if "is_unconscious" in selected_villager else false)
	var t = selected_villager.get("current_task") if "current_task" in selected_villager else 0
	if t == 1: task_name = "移动"
	elif t == 2: task_name = "采集"
	elif t == 3: task_name = "搬运"
	elif t == 4: task_name = "战斗"
	elif t == 5: task_name = "进食"
	elif t == 6: task_name = "休息"
	elif t == 7: task_name = "劳作"
	elif t == 8: task_name = "合成"
	if is_unconscious:
		task_name = "昏迷倒地"
	
	text += "当前行为: %s\n\n" % task_name
	if is_unconscious:
		text += "昏迷状态: 被狼重创，倒地不起，无法接受任何指令。\n\n"
	
	var h = selected_villager.get("hunger") if "hunger" in selected_villager else 100.0
	text += "🍗 饱食度: %d / 100\n\n" % int(h)
	var e = selected_villager.get("energy") if "energy" in selected_villager else 100.0
	text += "🛏 精力值: %d / 100\n\n" % int(e)
	if energy_bar:
		energy_bar.value = e
		energy_bar.tooltip_text = "🛏 精力值: %d / 100" % int(e)
	text += "--- 技能特长 ---\n"
	var sw = selected_villager.get("skill_woodcut") if "skill_woodcut" in selected_villager else 0
	var sm = selected_villager.get("skill_mining") if "skill_mining" in selected_villager else 0
	var sa = selected_villager.get("skill_melee") if "skill_melee" in selected_villager else 0
	text += "🪓 伐木度: %d\n" % sw
	text += "⛏️ 采矿度: %d\n" % sm
	text += "⚔️ 格斗度: %d" % sa
	if char_info_label: char_info_label.text = text

func _build_char_detail_dialog() -> void:
	char_detail_dialog = PanelContainer.new()
	char_detail_dialog.set_anchors_preset(Control.PRESET_CENTER)
	char_detail_dialog.custom_minimum_size = Vector2(400, 450)
	char_detail_dialog.visible = false
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 0.98)
	style.border_color = Color(0.5, 0.7, 1.0, 0.8)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	char_detail_dialog.add_theme_stylebox_override("panel", style)
	ui_layer.add_child(char_detail_dialog)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	char_detail_dialog.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)
	
	var nav_hbox = HBoxContainer.new()
	nav_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_hbox.add_theme_constant_override("separation", 30)
	vbox.add_child(nav_hbox)
	
	var prev_btn = Button.new()
	prev_btn.text = "◀ 上一位"
	prev_btn.add_theme_font_size_override("font_size", 20)
	prev_btn.pressed.connect(_on_prev_villager)
	nav_hbox.add_child(prev_btn)
	
	var title_lbl = Label.new()
	title_lbl.text = "📘 人物图鉴档案"
	title_lbl.add_theme_font_size_override("font_size", 24)
	nav_hbox.add_child(title_lbl)
	
	var next_btn = Button.new()
	next_btn.text = "下一位 ▶"
	next_btn.add_theme_font_size_override("font_size", 20)
	next_btn.pressed.connect(_on_next_villager)
	nav_hbox.add_child(next_btn)
	
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	char_detail_content = RichTextLabel.new()
	char_detail_content.bbcode_enabled = true
	char_detail_content.scroll_active = false
	char_detail_content.fit_content = true
	char_detail_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	char_detail_content.add_theme_font_size_override("normal_font_size", 18)
	vbox.add_child(char_detail_content)

	var mood_btn = Button.new()
	mood_btn.text = "查看情绪明细"
	mood_btn.add_theme_font_size_override("font_size", 20)
	mood_btn.pressed.connect(_on_mood_detail_pressed)
	vbox.add_child(mood_btn)
	
	var close_btn = Button.new()
	close_btn.text = "关闭 (Close)"
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(func():
		char_detail_dialog.visible = false
	)
	vbox.add_child(close_btn)

func _get_all_villagers() -> Array:
	return get_tree().get_nodes_in_group("villagers")

func _on_char_roster_pressed() -> void:
	var vils = _get_all_villagers()
	if vils.is_empty(): 
		EventBus.alert_message.emit("当前没有村民！")
		return
	
	if current_viewing_villager_index >= vils.size() or current_viewing_villager_index < 0:
		current_viewing_villager_index = 0
		
	_update_char_detail_dialog()
	char_detail_dialog.visible = true

func _on_prev_villager() -> void:
	var vils = _get_all_villagers()
	if vils.is_empty(): return
	current_viewing_villager_index -= 1
	if current_viewing_villager_index < 0:
		current_viewing_villager_index = vils.size() - 1
	_update_char_detail_dialog()

func _on_next_villager() -> void:
	var vils = _get_all_villagers()
	if vils.is_empty(): return
	current_viewing_villager_index += 1
	if current_viewing_villager_index >= vils.size():
		current_viewing_villager_index = 0
	_update_char_detail_dialog()

func _update_char_detail_dialog() -> void:
	var vils = _get_all_villagers()
	if vils.is_empty(): return
	if current_viewing_villager_index >= vils.size() or current_viewing_villager_index < 0:
		current_viewing_villager_index = 0
		
	var vil = vils[current_viewing_villager_index]
	var is_unconscious = bool(vil.get("is_unconscious") if "is_unconscious" in vil else false)
	
	var t = vil.get("current_task") if "current_task" in vil else 0
	var task_name = ["[color=gray]空闲中[/color]", "[color=yellow]正在前往目标[/color]", "[color=orange]努力采集中[/color]", "[color=cyan]搬运物资中[/color]", "[color=red]激烈战斗中[/color]", "[color=green]享受美食中[/color]"][t] if t < 6 else "未知"
	if t == 6:
		task_name = "[color=#88ccff]正在休息[/color]"
	elif t == 7:
		task_name = "[color=#92d66b]正在劳作[/color]"
	if is_unconscious:
		task_name = "[color=#ff7777]昏迷倒地[/color]"
	
	var h = vil.get("hunger") if "hunger" in vil else 100.0
	var e = vil.get("energy") if "energy" in vil else 100.0
	var m = vil.get("mood") if "mood" in vil else 100
	
	var sw = vil.get("skill_woodcut") if "skill_woodcut" in vil else 0
	var sm = vil.get("skill_mining") if "skill_mining" in vil else 0
	var sa = vil.get("skill_melee") if "skill_melee" in vil else 0
	
	var bbcode = ""
	bbcode += "[b]姓名[/b]: [color=yellow]" + vil.name + "[/color]\n"
	bbcode += "===============================\n"
	bbcode += "[b]💡 实时状态 (Status)[/b]\n"
	bbcode += "当前行为: %s\n" % task_name
	bbcode += "🍗 饱食度: %d / 100\n" % int(h)
	bbcode += "🛏 精力值: %d / 100\n" % int(e)
	bbcode += "😊 心情值: %d / 100\n\n" % m
	if is_unconscious:
		bbcode += "[color=#ff9999]状态说明: 被狼重创后昏迷，身体横倒，无法移动、采集、战斗、进食或休息。[/color]\n\n"
	
	bbcode += "[b]💪 个人天赋 (Skills)[/b] (1-20级)\n"
	bbcode += "[color=#e3a857]🪓 伐木专精:[/color] %d 级\n" % sw
	bbcode += "[color=#aaaaaa]⛏️ 采矿专精:[/color] %d 级\n" % sm
	bbcode += "[color=#ff5555]⚔️ 格斗专精:[/color] %d 级\n\n" % sa
	
	bbcode += "[b]🗣️ 社会关系 (Social Network)[/b]\n"
	var rels = vil.get("social_relations") if "social_relations" in vil else {}
	if rels.is_empty():
		bbcode += "[color=gray]孤僻，没有认识的人。[/color]"
	else:
		for o_name in rels.keys():
			var val = rels[o_name]
			var desc = "[color=green]挚友[/color]"
			if val < -10: desc = "[color=red]仇视[/color]"
			elif val < 30: desc = "[color=gray]点头之交[/color]"
			bbcode += "    与 [b]%s[/b] 的羁绊: %d  [%s]\n" % [o_name, val, desc]
			
	if char_detail_content: char_detail_content.text = bbcode

# ============================================================
# 暂停菜单
# ============================================================
func _build_mood_detail_dialog() -> void:
	mood_detail_dialog = PanelContainer.new()
	mood_detail_dialog.set_anchors_preset(Control.PRESET_CENTER)
	mood_detail_dialog.custom_minimum_size = Vector2(420, 320)
	mood_detail_dialog.visible = false
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.14, 0.98)
	style.border_color = Color(0.9, 0.65, 0.35, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	mood_detail_dialog.add_theme_stylebox_override("panel", style)
	ui_layer.add_child(mood_detail_dialog)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	mood_detail_dialog.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "情绪明细"
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	mood_detail_content = RichTextLabel.new()
	mood_detail_content.bbcode_enabled = true
	mood_detail_content.fit_content = true
	mood_detail_content.custom_minimum_size = Vector2(360, 190)
	mood_detail_content.add_theme_font_size_override("normal_font_size", 18)
	vbox.add_child(mood_detail_content)

	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(func(): mood_detail_dialog.visible = false)
	vbox.add_child(close_btn)

func _on_mood_detail_pressed() -> void:
	_update_mood_detail_dialog()
	if mood_detail_dialog:
		mood_detail_dialog.visible = true

func _update_mood_detail_dialog() -> void:
	var vils = _get_all_villagers()
	if vils.is_empty() or not mood_detail_content:
		return
	if current_viewing_villager_index >= vils.size() or current_viewing_villager_index < 0:
		current_viewing_villager_index = 0
	var vil = vils[current_viewing_villager_index]
	var breakdown = vil.get_mood_breakdown() if vil.has_method("get_mood_breakdown") else {}
	var penalties: Dictionary = breakdown.get("penalties", {}) if breakdown.has("penalties") else {}
	var current_mood = int(breakdown.get("current", vil.get("mood") if "mood" in vil else 100))
	var penalty_names = {
		"no_room": "没有自己的房间",
		"no_bed": "没有自己的床",
		"injured": "受伤",
		"hunger": "饥饿",
		"fatigue": "疲劳"
	}
	var penalty_caps = {
		"no_room": 20,
		"no_bed": 10,
		"injured": 45,
		"hunger": 25,
		"fatigue": 20
	}

	var text = ""
	text += "[b]%s[/b]\n" % vil.name
	text += "当前情绪值: [color=yellow]%d / 100[/color]\n\n" % current_mood
	if bool(breakdown.get("is_unconscious", false)):
		text += "[color=#ff9999]昏迷中：情绪固定为 50，无法执行指令。[/color]\n\n"
	if bool(breakdown.get("is_on_strike", false)):
		text += "[color=#ffcc66]罢工中：%s。[/color]\n\n" % str(breakdown.get("strike_reason", "情绪过低"))
	
	var penalty_lines = ""
	for key in penalties.keys():
		var val = float(penalties[key])
		var rounded_val = int(round(val))
		if rounded_val > 0:
			var display_name = penalty_names.get(key, key)
			var cap = penalty_caps.get(key, 0)
			if cap > 0:
				penalty_lines += "%s: -%d / %d\n" % [display_name, rounded_val, cap]
			else:
				penalty_lines += "%s: -%d\n" % [display_name, rounded_val]
	
	if penalty_lines != "":
		text += "扣除原因:\n" + penalty_lines
	else:
		text += "[color=gray]目前没有任何负面情绪影响因素。[/color]\n"
		
	mood_detail_content.text = text

func _build_room_menu_dialog() -> void:
	room_menu_dialog = PanelContainer.new()
	room_menu_dialog.set_anchors_preset(Control.PRESET_CENTER)
	room_menu_dialog.custom_minimum_size = Vector2(520, 420)
	room_menu_dialog.visible = false
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.13, 0.98)
	style.border_color = Color(0.45, 0.85, 0.7, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	room_menu_dialog.add_theme_stylebox_override("panel", style)
	ui_layer.add_child(room_menu_dialog)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	room_menu_dialog.add_child(margin)

	var root_vbox = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(root_vbox)

	var title = Label.new()
	title.text = "房间菜单"
	title.add_theme_font_size_override("font_size", 24)
	root_vbox.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 290)
	root_vbox.add_child(scroll)

	room_menu_content = VBoxContainer.new()
	room_menu_content.add_theme_constant_override("separation", 10)
	scroll.add_child(room_menu_content)

	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(func(): room_menu_dialog.visible = false)
	root_vbox.add_child(close_btn)

func _on_room_btn_pressed() -> void:
	var room_mgr = get_node_or_null("/root/RoomManager")
	if room_mgr and room_mgr.has_method("rebuild_rooms"):
		room_mgr.rebuild_rooms()
	_update_room_menu()
	if room_menu_dialog:
		room_menu_dialog.visible = true

func _on_rooms_updated() -> void:
	if room_menu_dialog and room_menu_dialog.visible:
		_update_room_menu()

func _update_room_menu() -> void:
	if not room_menu_content:
		return
	for child in room_menu_content.get_children():
		child.queue_free()

	var room_mgr = get_node_or_null("/root/RoomManager")
	if not room_mgr or not room_mgr.has_method("get_rooms"):
		return
	var rooms = room_mgr.get_rooms()
	if rooms.is_empty():
		var empty_label = Label.new()
		empty_label.text = "还没有检测到由墙和门围成的封闭房间。"
		empty_label.add_theme_font_size_override("font_size", 18)
		room_menu_content.add_child(empty_label)
		return

	var villagers = _get_all_villagers()
	for room in rooms:
		# --- 第一行：房间信息 + 重命名 ---
		var name_row = HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 8)
		room_menu_content.add_child(name_row)

		var room_name = str(room.get("name", "房间 %d" % int(room.get("id", 0))))
		var owner_text = str(room.get("owner", ""))
		if owner_text == "":
			owner_text = "未分配"

		var name_label = Label.new()
		name_label.text = "【%s】  面积:%d  分配:%s" % [room_name, room.get("cells", []).size(), owner_text]
		name_label.custom_minimum_size = Vector2(280, 0)
		name_label.add_theme_font_size_override("font_size", 16)
		name_row.add_child(name_label)

		var rename_btn = Button.new()
		rename_btn.text = "✏ 重命名"
		rename_btn.add_theme_font_size_override("font_size", 14)
		var cap_room_id = int(room.get("id", 0))
		var cap_room_name = room_name
		rename_btn.pressed.connect(func():
			_show_rename_room_dialog(cap_room_id, cap_room_name)
		)
		name_row.add_child(rename_btn)

		# --- 第二行：分配村民 ---
		var assign_row = HBoxContainer.new()
		assign_row.add_theme_constant_override("separation", 8)
		room_menu_content.add_child(assign_row)

		var assign_label = Label.new()
		assign_label.text = "  分配给:"
		assign_label.add_theme_font_size_override("font_size", 14)
		assign_row.add_child(assign_label)

		var clear_btn = Button.new()
		clear_btn.text = "清空"
		clear_btn.add_theme_font_size_override("font_size", 14)
		clear_btn.pressed.connect(func(room_id = int(room.get("id", 0))):
			room_mgr.assign_room(room_id, "")
		)
		assign_row.add_child(clear_btn)

		for vil in villagers:
			var btn = Button.new()
			btn.text = vil.name
			btn.add_theme_font_size_override("font_size", 14)
			btn.pressed.connect(func(room_id = int(room.get("id", 0)), owner = vil.name):
				room_mgr.assign_room(room_id, owner)
			)
			assign_row.add_child(btn)

		# 分隔线
		var sep = HSeparator.new()
		room_menu_content.add_child(sep)

## =========================================================
## 拆除上下文菜单
## =========================================================

func _build_villager_inventory_dialog() -> void:
	villager_inventory_dialog = PanelContainer.new()
	villager_inventory_dialog.set_anchors_preset(Control.PRESET_CENTER)
	villager_inventory_dialog.custom_minimum_size = Vector2(360, 280)
	villager_inventory_dialog.visible = false
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.97)
	style.border_color = Color(0.55, 0.78, 1.0, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	villager_inventory_dialog.add_theme_stylebox_override("panel", style)
	ui_layer.add_child(villager_inventory_dialog)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	villager_inventory_dialog.add_child(margin)

	villager_inventory_content = VBoxContainer.new()
	villager_inventory_content.add_theme_constant_override("separation", 8)
	margin.add_child(villager_inventory_content)

func _show_villager_inventory(villager: Node) -> void:
	if not villager_inventory_dialog or not is_instance_valid(villager_inventory_dialog):
		_build_villager_inventory_dialog()
	inventory_view_villager = villager
	_update_villager_inventory_dialog()
	if villager_inventory_dialog:
		villager_inventory_dialog.visible = true

func _update_villager_inventory_dialog() -> void:
	if not villager_inventory_content:
		return
	for child in villager_inventory_content.get_children():
		child.queue_free()
	if not is_instance_valid(inventory_view_villager):
		return

	var title = Label.new()
	title.text = "%s 的物品栏" % inventory_view_villager.name
	title.add_theme_font_size_override("font_size", 22)
	villager_inventory_content.add_child(title)

	var equipped = str(inventory_view_villager.get("equipped_tool_id") if "equipped_tool_id" in inventory_view_villager else "")
	var equip_label = Label.new()
	equip_label.text = "已装备: %s" % (_tool_display_name(equipped) if equipped != "" else "无")
	equip_label.add_theme_font_size_override("font_size", 16)
	villager_inventory_content.add_child(equip_label)

	var tools: Dictionary = inventory_view_villager.get_inventory_tools() if inventory_view_villager.has_method("get_inventory_tools") else {}
	if tools.is_empty():
		var empty = Label.new()
		empty.text = "空"
		empty.add_theme_font_size_override("font_size", 16)
		villager_inventory_content.add_child(empty)
	else:
		for tool_id in tools.keys():
			var row = Button.new()
			row.text = "%s x%d%s" % [_tool_display_name(str(tool_id)), int(tools[tool_id]), "  [装备中]" if equipped == str(tool_id) else ""]
			row.add_theme_font_size_override("font_size", 16)
			row.gui_input.connect(func(event, id = str(tool_id)):
				if event is InputEventMouseButton and event.pressed:
					if event.button_index == MOUSE_BUTTON_RIGHT:
						_drop_villager_tool(id)
						get_viewport().set_input_as_handled()
					elif event.button_index == MOUSE_BUTTON_LEFT and is_instance_valid(inventory_view_villager):
						if id == "bandage" and inventory_view_villager.has_method("manual_use_bandage"):
							inventory_view_villager.manual_use_bandage()
						elif inventory_view_villager.has_method("equip_tool"):
							inventory_view_villager.equip_tool(id)
						elif id != "bandage" and id != "arrow":
							inventory_view_villager.equipped_tool_id = id
						_update_villager_inventory_dialog()
						get_viewport().set_input_as_handled()
			)
			villager_inventory_content.add_child(row)

	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(func(): villager_inventory_dialog.visible = false)
	villager_inventory_content.add_child(close_btn)

func _drop_villager_tool(tool_id: String) -> void:
	if not is_instance_valid(inventory_view_villager):
		return
	if not inventory_view_villager.has_method("remove_tool_from_inventory"):
		return
	if not inventory_view_villager.remove_tool_from_inventory(tool_id, 1):
		return
	_spawn_tool_drop(tool_id, inventory_view_villager.global_position + Vector2(12, 8))
	_update_villager_inventory_dialog()

func _pickup_tool_drop(villager: Node, drop: Node) -> void:
	var tool_id = str(drop.get("item_id") if "item_id" in drop else "")
	if tool_id == "" or not villager.has_method("add_tool_to_inventory"):
		return
	if villager.has_method("can_add_tool") and not villager.can_add_tool(tool_id):
		EventBus.alert_message.emit("%s 已经携带同类工具或武器，不能再拿 %s" % [villager.name, _tool_display_name(tool_id)])
		return
	var amount = int(drop.get("amount") if "amount" in drop else 1)
	villager.add_tool_to_inventory(tool_id, max(1, amount), tool_id != "bandage" and tool_id != "arrow")
	var haul_mgr = get_node_or_null("/root/HaulManager")
	if haul_mgr and haul_mgr.has_method("unregister_item"):
		haul_mgr.unregister_item(drop)
	drop.queue_free()
	EventBus.alert_message.emit("%s 捡起并装备了 %s" % [villager.name, _tool_display_name(tool_id)])
	if villager_inventory_dialog and villager_inventory_dialog.visible and inventory_view_villager == villager:
		_update_villager_inventory_dialog()

func _spawn_tool_drop(tool_id: String, world_pos: Vector2) -> void:
	var tilemap = $TileMapLayer
	if not tilemap:
		return
	var item_scene = load("res://scenes/ItemDrop.tscn")
	if not item_scene:
		return
	var drop = item_scene.instantiate()
	if "item_id" in drop:
		drop.item_id = tool_id
	if "type" in drop:
		drop.type = -1
	if "amount" in drop:
		drop.amount = 1
	var cell = tilemap.local_to_map(tilemap.to_local(world_pos))
	if "grid_coord" in drop:
		drop.grid_coord = cell
	tilemap.add_child(drop)
	drop.global_position = world_pos

func _get_tool_drop_at(world_pos: Vector2) -> Node:
	var best: Node = null
	var best_dist = INF
	for drop in get_tree().get_nodes_in_group("tool_drops"):
		if not is_instance_valid(drop):
			continue
		var d = drop.global_position.distance_to(world_pos)
		if d < 18.0 and d < best_dist:
			best = drop
			best_dist = d
	return best

func _is_clicking_villager(villager: Node, world_pos: Vector2) -> bool:
	return is_instance_valid(villager) and villager.global_position.distance_to(world_pos) < 18.0

func _get_villager_at(world_pos: Vector2) -> Node:
	var best: Node = null
	var best_dist = INF
	for vil in get_tree().get_nodes_in_group("villagers"):
		if not is_instance_valid(vil):
			continue
		var d = vil.global_position.distance_to(world_pos)
		if d < 20.0 and d < best_dist:
			best = vil
			best_dist = d
	return best

func _tool_display_name(tool_id: String) -> String:
	match tool_id:
		"wood_axe":
			return "木斧头"
		"wood_pickaxe":
			return "木稿子"
		"stone_axe":
			return "石斧头"
		"stone_pickaxe":
			return "石稿子"
		"bandage":
			return "绷带"
		"wood_sword":
			return "木剑"
		"stone_sword":
			return "石剑"
		"bow":
			return "弓"
		"arrow":
			return "箭"
		"fishing_rod":
			return "钓鱼竿"
		_:
			return tool_id

func _show_craft_menu(workbench: Node, world_pos: Vector2) -> void:
	_close_craft_menu()
	craft_target_workbench = workbench

	craft_context_panel = _make_context_panel(Color(0.45, 0.72, 1.0, 0.9))
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	craft_context_panel.add_child(vbox)

	var title = Label.new()
	title.text = "工作台"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
	vbox.add_child(title)

	var job_mgr = get_node_or_null("/root/JobManager")
	if not job_mgr or not job_mgr.has_method("get_recipe_ids"):
		var missing = Label.new()
		missing.text = "合成系统未就绪"
		vbox.add_child(missing)
	else:
		for recipe_id in job_mgr.get_recipe_ids():
			var recipe: Dictionary = job_mgr.get_craft_recipe(str(recipe_id))
			if recipe.is_empty():
				continue
			var btn = Button.new()
			btn.text = str(recipe.get("name", recipe_id))
			btn.custom_minimum_size = Vector2(190, 38)
			btn.add_theme_font_size_override("font_size", 16)
			var rid = str(recipe_id)
			var icon_path = str(recipe.get("icon", ""))
			if icon_path != "":
				btn.icon = load(icon_path)
				btn.expand_icon = true
				btn.add_theme_constant_override("icon_max_width", _craft_icon_max_width(rid))
			btn.mouse_entered.connect(func(): _show_craft_hover(recipe))
			btn.mouse_exited.connect(_hide_craft_hover)
			btn.pressed.connect(func(): _request_craft(rid))
			vbox.add_child(btn)

	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.pressed.connect(_close_craft_menu)
	vbox.add_child(close_btn)

	_setup_craft_hover()
	_place_control_panel(craft_context_panel, world_pos)

func _craft_icon_max_width(recipe_id: String) -> int:
	match recipe_id:
		"bandage":
			return 18
		"wood_sword", "stone_sword", "bow", "fishing_rod":
			return 34
		"arrow":
			return 22
		_:
			return 26

func _setup_craft_hover() -> void:
	if craft_hover_popup and is_instance_valid(craft_hover_popup):
		return
	craft_hover_popup = PanelContainer.new()
	craft_hover_popup.visible = false
	craft_hover_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	craft_hover_popup.z_index = 230
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.96)
	style.border_color = Color(0.6, 0.8, 1.0, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	craft_hover_popup.add_theme_stylebox_override("panel", style)
	craft_hover_label = Label.new()
	craft_hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	craft_hover_label.custom_minimum_size = Vector2(260, 0)
	craft_hover_label.add_theme_font_size_override("font_size", 15)
	craft_hover_label.add_theme_color_override("font_color", Color(0.95, 0.94, 0.88))
	craft_hover_popup.add_child(craft_hover_label)
	ui_layer.add_child(craft_hover_popup)

func _show_craft_hover(recipe: Dictionary) -> void:
	_setup_craft_hover()
	if not craft_hover_popup or not craft_hover_label:
		return
	craft_hover_label.text = _craft_popup_text(recipe)
	craft_hover_popup.visible = true
	craft_hover_popup.global_position = get_viewport().get_mouse_position() + Vector2(18, 18)

func _hide_craft_hover() -> void:
	if craft_hover_popup:
		craft_hover_popup.visible = false

func _craft_popup_text(recipe: Dictionary) -> String:
	var parts: Array[String] = []
	var cost: Dictionary = recipe.get("cost", {})
	for key in cost.keys():
		parts.append("%s x%d" % [_res_display_name(str(key)), int(cost[key])])
	return "%s\n%s\n合成时间：%d 分钟\n消耗：%s" % [
		str(recipe.get("name", "")),
		str(recipe.get("desc", "")),
		int(recipe.get("time_minutes", 0)),
		"、".join(parts)
	]

func _request_craft(recipe_id: String) -> void:
	var job_mgr = get_node_or_null("/root/JobManager")
	if not job_mgr or not job_mgr.has_method("get_craft_recipe") or not is_instance_valid(craft_target_workbench):
		return
	var recipe: Dictionary = job_mgr.get_craft_recipe(recipe_id)
	if recipe.is_empty():
		return
	if not _has_recipe_resources(recipe):
		EventBus.alert_message.emit("资源不足，无法合成 %s" % str(recipe.get("name", recipe_id)))
		return
	if job_mgr.has_method("add_craft_job") and not job_mgr.add_craft_job(recipe_id, craft_target_workbench):
		EventBus.alert_message.emit("这个工作台已经有合成任务了")
		return
	_deduct_recipe_resources(recipe)
	EventBus.alert_message.emit("已安排合成：%s" % str(recipe.get("name", recipe_id)))
	_close_craft_menu()

func _has_recipe_resources(recipe: Dictionary) -> bool:
	var inv = get_node_or_null("/root/InventoryManager")
	if not inv:
		return false
	var cost: Dictionary = recipe.get("cost", {})
	for key in cost.keys():
		if int(inv.get(str(key)) if str(key) in inv else 0) < int(cost[key]):
			return false
	return true

func _deduct_recipe_resources(recipe: Dictionary) -> void:
	var cost: Dictionary = recipe.get("cost", {})
	for key in cost.keys():
		EventBus.resource_consumed.emit(_res_type_id(str(key)), int(cost[key]))

func _res_type_id(name: String) -> int:
	match name:
		"wood":
			return 0
		"stone":
			return 1
		"meat", "food":
			return 2
		"fiber":
			return 3
		_:
			return -1

func _res_display_name(name: String) -> String:
	match name:
		"wood":
			return "木头"
		"stone":
			return "石头"
		"meat", "food":
			return "食物"
		"fiber":
			return "纤维"
		_:
			return name

func _close_craft_menu() -> void:
	_hide_craft_hover()
	if craft_context_panel and is_instance_valid(craft_context_panel):
		craft_context_panel.queue_free()
	craft_context_panel = null
	craft_target_workbench = null

func _get_building_at(world_pos: Vector2) -> Node:
	var space_state = get_world_2d().direct_space_state
	var params = PhysicsPointQueryParameters2D.new()
	params.position = world_pos
	params.collide_with_bodies = true
	params.collision_mask = 0xFFFFFFFF
	var results = space_state.intersect_point(params, 8)
	for res in results:
		var col = res.collider
		if is_instance_valid(col) and col.is_in_group("buildings"):
			return col
	return null

func _show_demolish_menu(building: Node, world_pos: Vector2) -> void:
	_close_demolish_menu()
	demolish_target_building = building

	demolish_context_panel = PanelContainer.new()
	demolish_context_panel.z_index = 200

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.border_color = Color(1.0, 0.35, 0.25, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	demolish_context_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	demolish_context_panel.add_child(vbox)

	# 建筑名称提示
	var type_name = _get_building_type_name(building)
	var info_label = Label.new()
	info_label.text = type_name
	info_label.add_theme_font_size_override("font_size", 15)
	info_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	vbox.add_child(info_label)

	# 返还资源预览
	var refund_text = _calc_refund_text(building)
	if refund_text != "":
		var refund_label = Label.new()
		refund_label.text = "返还: " + refund_text
		refund_label.add_theme_font_size_override("font_size", 13)
		refund_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55))
		vbox.add_child(refund_label)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	var demolish_btn = Button.new()
	demolish_btn.text = "🔨 拆除"
	demolish_btn.add_theme_font_size_override("font_size", 16)
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.4, 0.08, 0.05, 1.0)
	normal_style.border_color = Color(0.9, 0.3, 0.2, 0.8)
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(4)
	demolish_btn.add_theme_stylebox_override("normal", normal_style)
	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.65, 0.12, 0.08, 1.0)
	hover_style.border_color = Color(1.0, 0.4, 0.3, 1.0)
	hover_style.set_border_width_all(1)
	hover_style.set_corner_radius_all(4)
	demolish_btn.add_theme_stylebox_override("hover", hover_style)
	demolish_btn.add_theme_color_override("font_color", Color(1.0, 0.75, 0.7))
	demolish_btn.pressed.connect(_on_demolish_confirmed)
	vbox.add_child(demolish_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 14)
	cancel_btn.pressed.connect(_close_demolish_menu)
	vbox.add_child(cancel_btn)

	ui_layer.add_child(demolish_context_panel)
	# CanvasLayer 子节点 position 即屏幕空间坐标
	var cam = get_viewport().get_camera_2d()
	var screen_pos: Vector2
	if cam:
		screen_pos = cam.get_viewport_transform() * world_pos
	else:
		screen_pos = world_pos
	# 确保菜单不超出右侧屏幕
	var vp_size = get_viewport().get_visible_rect().size
	var offset = Vector2(12, -20)
	demolish_context_panel.position = screen_pos + offset
	# 等一帧让 size 计算完成后再做边界检查
	await get_tree().process_frame
	if is_instance_valid(demolish_context_panel):
		var panel_size = demolish_context_panel.size
		var pos = demolish_context_panel.position
		if pos.x + panel_size.x > vp_size.x:
			pos.x = vp_size.x - panel_size.x - 8
		if pos.y + panel_size.y > vp_size.y:
			pos.y = screen_pos.y - panel_size.y - 4
		demolish_context_panel.position = pos

func _show_farm_cell_menu(cell: Vector2i, world_pos: Vector2) -> void:
	_close_demolish_menu()
	var farm_mgr = get_node_or_null("/root/FarmManager")
	if not farm_mgr:
		return
	var plot = farm_mgr.get_plot_at_cell(cell)
	if plot.is_empty():
		return
	var plot_id = int(plot.get("id", -1))
	var crop = str(plot.get("crop", ""))
	var growth = int(round(farm_mgr.get_cell_growth(plot, cell) if farm_mgr.has_method("get_cell_growth") else float(plot.get("growth", 0.0))))

	demolish_context_panel = _make_context_panel(Color(0.45, 0.70, 0.30, 0.9))
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	demolish_context_panel.add_child(vbox)

	var info = Label.new()
	info.text = "农田组\n格子: %d\n当前格成长: %d/100\n作物: %s" % [(plot.get("cells", []) as Array).size(), growth, _crop_display_name(crop)]
	info.add_theme_font_size_override("font_size", 16)
	vbox.add_child(info)

	if crop == "":
		var fiber_btn = Button.new()
		fiber_btn.text = "种植纤维"
		fiber_btn.pressed.connect(func():
			farm_mgr.set_crop(plot_id, "fiber")
			_close_demolish_menu()
		)
		vbox.add_child(fiber_btn)

		var food_btn = Button.new()
		food_btn.text = "种植食物"
		food_btn.pressed.connect(func():
			farm_mgr.set_crop(plot_id, "food")
			_close_demolish_menu()
		)
		vbox.add_child(food_btn)

	var demolish_btn = Button.new()
	demolish_btn.text = "拆除农田"
	demolish_btn.pressed.connect(func():
		farm_mgr.remove_plot(plot_id)
		_close_demolish_menu()
	)
	vbox.add_child(demolish_btn)

	_add_context_cancel(vbox)
	_place_context_panel(world_pos)

func _show_stockpile_cell_menu(cell: Vector2i, world_pos: Vector2) -> void:
	_close_demolish_menu()
	demolish_context_panel = _make_context_panel(Color(0.95, 0.78, 0.28, 0.9))
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	demolish_context_panel.add_child(vbox)

	var info = Label.new()
	info.text = "仓库区"
	info.add_theme_font_size_override("font_size", 16)
	vbox.add_child(info)

	var demolish_btn = Button.new()
	demolish_btn.text = "拆除此格"
	demolish_btn.pressed.connect(func():
		_demolish_stockpile_cell(cell)
		_close_demolish_menu()
	)
	vbox.add_child(demolish_btn)

	_add_context_cancel(vbox)
	_place_context_panel(world_pos)

func _make_context_panel(border_color: Color) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.z_index = 200
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	ui_layer.add_child(panel)
	return panel

func _add_context_cancel(vbox: VBoxContainer) -> void:
	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(_close_demolish_menu)
	vbox.add_child(cancel_btn)

func _place_context_panel(world_pos: Vector2) -> void:
	if not demolish_context_panel:
		return
	_place_control_panel(demolish_context_panel, world_pos)

func _place_control_panel(panel: Control, world_pos: Vector2) -> void:
	if not panel:
		return
	var cam = get_viewport().get_camera_2d()
	var screen_pos = cam.get_viewport_transform() * world_pos if cam else world_pos
	panel.position = screen_pos + Vector2(12, -20)

func _crop_display_name(crop: String) -> String:
	match crop:
		"fiber":
			return "纤维"
		"food":
			return "食物"
		_:
			return "未设置"

func _demolish_stockpile_cell(cell: Vector2i) -> void:
	var haul_mgr = get_node_or_null("/root/HaulManager")
	if haul_mgr and haul_mgr.has_method("remove_stockpile_cell"):
		haul_mgr.remove_stockpile_cell(cell)
	else:
		var stockpile_mgr = get_node_or_null("/root/StockpileManager")
		if stockpile_mgr and stockpile_mgr.has_method("remove_stockpile_cell"):
			stockpile_mgr.remove_stockpile_cell(cell)
	if stockpile_visuals.has(cell):
		var visual = stockpile_visuals[cell]
		if is_instance_valid(visual):
			visual.queue_free()
		stockpile_visuals.erase(cell)
	EventBus.alert_message.emit("已拆除仓库格")

func _on_demolish_confirmed() -> void:
	if is_instance_valid(demolish_target_building) and demolish_target_building.has_method("demolish"):
		demolish_target_building.demolish()
	demolish_target_building = null
	_close_demolish_menu()

func _close_demolish_menu() -> void:
	if demolish_context_panel and is_instance_valid(demolish_context_panel):
		demolish_context_panel.queue_free()
		demolish_context_panel = null
	demolish_target_building = null

func _get_building_type_name(building: Node) -> String:
	var t = int(building.get("type") if "type" in building else -1)
	match t:
		BuildingResource.BuildingType.WALL:
			return "🧱 墙壁"
		BuildingResource.BuildingType.DOOR:
			return "🚪 门"
		_:
			return "建筑"

func _calc_refund_text(building: Node) -> String:
	var path = building.get_meta("building_resource_path", "") as String if building.has_meta("building_resource_path") else ""
	if path == "":
		return ""
	var data: BuildingResource = load(path)
	if not data or data.cost.is_empty():
		return ""
	var parts: Array[String] = []
	for res_name in data.cost.keys():
		var half = int(float(data.cost[res_name]) / 2.0)
		if half > 0:
			parts.append("%s×%d" % [_res_short_name(res_name), half])
	return "，".join(parts)

func _res_short_name(res_name: String) -> String:
	match res_name:
		"wood": return "木"
		"stone": return "石"
		"meat": return "食物"
		"fiber": return "纤"
		_: return res_name

func _on_building_demolished_ui(_coord: Vector2i, _type: int) -> void:
	# 拆除后如果房间菜单打开则刷新
	if room_menu_dialog and room_menu_dialog.visible:
		_update_room_menu()

## =========================================================
## 房间名世界提示
## =========================================================

func _show_room_name_at(world_pos: Vector2, room_name: String) -> void:
	# 隐藏旧的提示
	if is_instance_valid(room_name_world_label):
		room_name_world_label.queue_free()
		room_name_world_label = null

	var label = Label.new()
	label.text = room_name
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	label.z_index = 50
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.05, 0.05, 0.08, 0.55)
	bg_style.set_corner_radius_all(4)
	bg_style.content_margin_left = 10
	bg_style.content_margin_right = 10
	bg_style.content_margin_top = 4
	bg_style.content_margin_bottom = 4
	label.add_theme_stylebox_override("normal", bg_style)

	# 将提示放在 CanvasLayer 中以便跟随屏幕
	var lc = CanvasLayer.new()
	lc.layer = 30
	lc.name = "RoomNameLayer"
	add_child(lc)
	lc.add_child(label)

	# 位置转换为屏幕坐标（CanvasLayer 子节点 position = 屏幕像素）
	var cam = get_viewport().get_camera_2d()
	if cam:
		var screen_pos = cam.get_viewport_transform() * world_pos
		label.position = screen_pos + Vector2(-60, -50)
	else:
		label.position = world_pos + Vector2(-60, -50)

	room_name_world_label = label

	# 淡入
	var tw = label.create_tween()
	label.modulate.a = 0.0
	tw.tween_property(label, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.8)
	tw.tween_property(label, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		if is_instance_valid(lc): lc.queue_free()
		room_name_world_label = null
	)

## =========================================================
## 重命名房间对话框
## =========================================================

func _show_rename_room_dialog(room_id: int, current_name: String) -> void:
	# 创建一个简单的输入弹窗
	var dialog = PanelContainer.new()
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.custom_minimum_size = Vector2(360, 160)
	dialog.z_index = 300

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.14, 0.98)
	style.border_color = Color(0.45, 0.85, 0.7, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	dialog.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	dialog.add_child(vbox)

	var title = Label.new()
	title.text = "为房间重命名"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.8, 0.95, 0.9))
	vbox.add_child(title)

	var line_edit = LineEdit.new()
	line_edit.text = current_name
	line_edit.custom_minimum_size = Vector2(300, 38)
	line_edit.add_theme_font_size_override("font_size", 18)
	line_edit.select_all_on_focus = true
	vbox.add_child(line_edit)

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消"
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.pressed.connect(func(): dialog.queue_free())
	btn_row.add_child(cancel_btn)

	var confirm_btn = Button.new()
	confirm_btn.text = "确认"
	confirm_btn.add_theme_font_size_override("font_size", 16)
	confirm_btn.pressed.connect(func():
		var new_name = line_edit.text.strip_edges()
		if new_name == "":
			new_name = "房间 %d" % room_id
		var rm = get_node_or_null("/root/RoomManager")
		if rm and rm.has_method("rename_room"):
			rm.rename_room(room_id, new_name)
		dialog.queue_free()
	)
	btn_row.add_child(confirm_btn)

	# 回车也确认
	line_edit.text_submitted.connect(func(_t):
		confirm_btn.emit_signal("pressed")
	)

	ui_layer.add_child(dialog)
	# 聚焦输入框
	await get_tree().process_frame
	if is_instance_valid(line_edit):
		line_edit.grab_focus()

func _build_test_menu_dialog() -> void:
	test_menu_dialog = PanelContainer.new()
	test_menu_dialog.set_anchors_preset(Control.PRESET_CENTER)
	test_menu_dialog.custom_minimum_size = Vector2(420, 300)
	test_menu_dialog.visible = false
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.98)
	style.border_color = Color(0.75, 0.75, 0.35, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	test_menu_dialog.add_theme_stylebox_override("panel", style)
	ui_layer.add_child(test_menu_dialog)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	test_menu_dialog.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "测试菜单"
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	var resource_btn = Button.new()
	resource_btn.text = "资源 +100"
	resource_btn.add_theme_font_size_override("font_size", 20)
	resource_btn.pressed.connect(_on_cheat_btn_pressed)
	vbox.add_child(resource_btn)

	var time_row = HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 8)
	vbox.add_child(time_row)

	time_input = LineEdit.new()
	time_input.placeholder_text = "时间 13:30"
	time_input.text = "8:00"
	time_input.custom_minimum_size = Vector2(160, 38)
	time_input.add_theme_font_size_override("font_size", 18)
	time_input.text_submitted.connect(func(_text): _on_set_time_pressed())
	time_row.add_child(time_input)

	var set_time_btn = Button.new()
	set_time_btn.text = "设置时间"
	set_time_btn.add_theme_font_size_override("font_size", 18)
	set_time_btn.pressed.connect(_on_set_time_pressed)
	time_row.add_child(set_time_btn)

	var creature_btn = Button.new()
	creature_btn.text = "生物菜单"
	creature_btn.add_theme_font_size_override("font_size", 20)
	creature_btn.pressed.connect(_on_creature_menu_pressed)
	vbox.add_child(creature_btn)

	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(func(): test_menu_dialog.visible = false)
	vbox.add_child(close_btn)

func _on_test_menu_pressed() -> void:
	if test_menu_dialog:
		test_menu_dialog.visible = not test_menu_dialog.visible

func _build_creature_menu_dialog() -> void:
	creature_menu_dialog = PanelContainer.new()
	creature_menu_dialog.set_anchors_preset(Control.PRESET_CENTER)
	creature_menu_dialog.custom_minimum_size = Vector2(360, 260)
	creature_menu_dialog.visible = false
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.10, 0.98)
	style.border_color = Color(0.4, 0.85, 0.55, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	creature_menu_dialog.add_theme_stylebox_override("panel", style)
	ui_layer.add_child(creature_menu_dialog)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	creature_menu_dialog.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title = Label.new()
	title.text = "生物菜单"
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	_add_creature_select_button(vbox, "猪", "pig")
	_add_creature_select_button(vbox, "鸡", "chicken")
	_add_creature_select_button(vbox, "狼", "wolf")

	var close_btn = Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(func(): creature_menu_dialog.visible = false)
	vbox.add_child(close_btn)

func _add_creature_select_button(parent: Node, label: String, species: String) -> void:
	var btn = Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(func():
		selected_creature_species = species
		if creature_menu_dialog:
			creature_menu_dialog.visible = false
		if test_menu_dialog:
			test_menu_dialog.visible = false
		EventBus.alert_message.emit("已选择生物：%s，左键点击地图生成，右键取消" % label)
	)
	parent.add_child(btn)

func _on_creature_menu_pressed() -> void:
	if creature_menu_dialog:
		creature_menu_dialog.visible = true

func _spawn_test_creature(species: String, world_pos: Vector2) -> void:
	var tilemap = get_node_or_null("TileMapLayer")
	if not tilemap:
		return

	var cell = tilemap.local_to_map(tilemap.to_local(world_pos))
	if "astar_grid" in tilemap and tilemap.astar_grid:
		if not tilemap.astar_grid.is_in_boundsv(cell) or tilemap.astar_grid.is_point_solid(cell):
			EventBus.alert_message.emit("这里不能生成生物")
			return

	var animal = CharacterBody2D.new()
	var scr = load("res://scripts/entities/Animal.gd")
	if scr:
		animal.set_script(scr)
	animal.add_to_group("animals")
	if "species" in animal:
		animal.species = species
	if "health" in animal:
		animal.health = 5 if species == "wolf" else 2

	var sprite = Sprite2D.new()
	var tex_path = "res://art/animals/pig.png"
	if species == "chicken":
		tex_path = "res://art/animals/chicken.png"
	elif species == "wolf":
		tex_path = "res://art/animals/howl.png"
	if FileAccess.file_exists(tex_path) or FileAccess.file_exists(tex_path + ".import"):
		sprite.texture = load(tex_path)
	else:
		sprite.texture = load("res://icon.svg")
		sprite.scale = Vector2(0.3, 0.3)
	animal.add_child(sprite)
	tilemap.add_child(animal)
	animal.global_position = tilemap.to_global(tilemap.map_to_local(cell))
	EventBus.alert_message.emit("已生成生物：%s" % species)

func _build_pause_menu() -> void:
	# 半透明遮罩层
	pause_overlay = ColorRect.new()
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.color = Color(0.0, 0.0, 0.05, 0.72)
	pause_overlay.visible = false
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(pause_overlay)

	# 中央菜单卡片
	pause_menu_panel = PanelContainer.new()
	pause_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_menu_panel.custom_minimum_size = Vector2(480, 500)
	pause_menu_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_menu_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.08, 0.08, 0.12, 0.97)
	card_style.border_color = Color(0.45, 0.65, 1.0, 0.9)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(14)
	card_style.content_margin_left = 0
	card_style.content_margin_right = 0
	card_style.content_margin_top = 0
	card_style.content_margin_bottom = 0
	pause_menu_panel.add_theme_stylebox_override("panel", card_style)
	pause_overlay.add_child(pause_menu_panel)

	# 手动居中（锚点在遮罩内）
	pause_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_menu_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pause_menu_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 42)
	margin.add_theme_constant_override("margin_bottom", 42)
	pause_menu_panel.add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 22)
	margin.add_child(vbox)

	# 标题
	var title = Label.new()
	title.text = "⏸  游戏已暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.85, 0.93, 1.0))
	vbox.add_child(title)

	var sep = HSeparator.new()
	var sep_style = StyleBoxFlat.new()
	sep_style.bg_color = Color(0.35, 0.55, 0.9, 0.5)
	sep_style.content_margin_top = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer1)

	# --- 按钮工厂 ---
	var resume_btn = _make_pause_btn("▶  继续游戏", Color(0.25, 0.8, 0.45))
	resume_btn.pressed.connect(_on_pause_resume)
	vbox.add_child(resume_btn)

	var save_btn = _make_pause_btn("💾  保存进度", Color(0.45, 0.7, 1.0))
	save_btn.pressed.connect(_on_pause_save)
	vbox.add_child(save_btn)

	var settings_btn = _make_pause_btn("设置", Color(0.75, 0.65, 1.0))
	settings_btn.pressed.connect(_on_pause_settings)
	vbox.add_child(settings_btn)

	var menu_btn = _make_pause_btn("🏠  返回主菜单", Color(1.0, 0.55, 0.35))
	menu_btn.pressed.connect(_on_pause_return_menu)
	vbox.add_child(menu_btn)

	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer2)

	var hint = Label.new()
	hint.text = "按 Esc 继续游戏"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	vbox.add_child(hint)

func _make_pause_btn(label_text: String, accent: Color) -> Button:
	var btn = Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(340, 64)
	btn.add_theme_font_size_override("font_size", 26)

	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(accent.r * 0.18, accent.g * 0.18, accent.b * 0.18, 1.0)
	normal_style.border_color = Color(accent.r * 0.7, accent.g * 0.7, accent.b * 0.7, 0.85)
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(8)
	normal_style.content_margin_left = 16
	normal_style.content_margin_right = 16
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style = StyleBoxFlat.new()
	hover_style.bg_color = Color(accent.r * 0.32, accent.g * 0.32, accent.b * 0.32, 1.0)
	hover_style.border_color = accent
	hover_style.set_border_width_all(2)
	hover_style.set_corner_radius_all(8)
	hover_style.content_margin_left = 16
	hover_style.content_margin_right = 16
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = StyleBoxFlat.new()
	pressed_style.bg_color = Color(accent.r * 0.45, accent.g * 0.45, accent.b * 0.45, 1.0)
	pressed_style.border_color = accent
	pressed_style.set_border_width_all(2)
	pressed_style.set_corner_radius_all(8)
	pressed_style.content_margin_left = 16
	pressed_style.content_margin_right = 16
	btn.add_theme_stylebox_override("pressed", pressed_style)

	btn.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	return btn

func _toggle_pause() -> void:
	if is_loading_game or loading_layer:
		return
	is_game_paused = not is_game_paused
	get_tree().paused = is_game_paused
	pause_overlay.visible = is_game_paused
	if not is_game_paused:
		# 恢复时关闭其他可能打开的弹窗
		if char_detail_dialog: char_detail_dialog.visible = false

		if pause_settings_layer and is_instance_valid(pause_settings_layer):
			pause_settings_layer.queue_free()
		pause_settings_layer = null

func _on_pause_resume() -> void:
	_toggle_pause()

func _on_pause_save() -> void:
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr:
		var ok = save_mgr.save_game(self)
		if ok:
			EventBus.alert_message.emit("💾 游戏已保存！")
		else:
			EventBus.alert_message.emit("⚠️ 保存失败，请检查日志")
	else:
		EventBus.alert_message.emit("⚠️ SaveManager 不可用")

func _on_pause_settings() -> void:
	if pause_settings_layer and is_instance_valid(pause_settings_layer):
		pause_settings_layer.queue_free()
		pause_settings_layer = null
		return

	var settings_script = load("res://scripts/ui/SettingsMenu.gd")
	if not settings_script:
		EventBus.alert_message.emit("Settings menu unavailable")
		return

	pause_settings_layer = CanvasLayer.new()
	pause_settings_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_settings_layer.set_script(settings_script)
	ui_layer.add_child(pause_settings_layer)

func _on_pause_return_menu() -> void:
	# 先恢复暂停，再切换场景，避免场景树暂停导致问题
	get_tree().paused = false
	is_game_paused = false

	var menu_scene = load("res://scenes/Menu.tscn")
	if not menu_scene:
		print("错误：无法加载 Menu.tscn")
		return

	var root = get_tree().root
	var menu_instance = menu_scene.instantiate()
	root.add_child(menu_instance)
	get_tree().current_scene = menu_instance

	# 删除当前游戏主场景（即本节点所在的 Main 场景）
	# 同时清理掉可能残留的其它非 autoload、非菜单子节点
	var to_free: Array[Node] = []
	var autoloads = ["EventBus", "GameManager", "InventoryManager", "StockpileManager",
						"HaulManager", "BuildManager", "RoomManager", "JobManager", "TimeManager", "WolfManager", "SaveManager", "FarmManager", "AudioManager", "SettingsManager"]
	for child in root.get_children():
		if child == menu_instance:
			continue
		# autoload 节点不删除（它们以 "/root/NodeName" 注册，name 匹配 project.godot 中的 key）
		if child.name in autoloads:
			continue
		to_free.append(child)
	for n in to_free:
		n.queue_free()

# ============================================================
# 读档恢复
# ============================================================
func _restore_from_save(data: Dictionary) -> void:
	if DEBUG_NODE2D_LOGS:
		print("=== _restore_from_save() 开始 ===")
	var tilemap = get_node_or_null("TileMapLayer")

	# --- 0. 重置 autoload managers 的运行时数据，避免与上局叠加 ---
	var stockpile_mgr_pre = get_node_or_null("/root/StockpileManager")
	if stockpile_mgr_pre:
		stockpile_mgr_pre.stockpile_cells.clear()
		stockpile_mgr_pre._stockpile_ever_created = false
	var haul_mgr_pre = get_node_or_null("/root/HaulManager")
	if haul_mgr_pre:
		haul_mgr_pre.unhauled_items.clear()
		haul_mgr_pre.stockpile_items.clear()
	var job_mgr_pre = get_node_or_null("/root/JobManager")
	if job_mgr_pre:
		job_mgr_pre.jobs_queue.clear()
	# 同时重置 SaveManager 的销毁追踪列表（避免旧局坐标重复记录）
	var save_mgr_ref = get_node_or_null("/root/SaveManager")
	if save_mgr_ref: save_mgr_ref.reset_tracking()
	var farm_mgr_pre = get_node_or_null("/root/FarmManager")
	if farm_mgr_pre and farm_mgr_pre.has_method("reset"):
		farm_mgr_pre.reset()

	# --- 1. 地图已按 seed 重新生成，直接删掉自动生成的动物（资源节点通过 removed_cells 处理）---
	if tilemap:
		var nodes_to_free: Array[Node] = []
		for child in tilemap.get_children():
			if child.is_in_group("animals") or child.is_in_group("buildings") or (data.has("resource_nodes") and child.is_in_group("resources")):
				nodes_to_free.append(child)
		for child in nodes_to_free:
			tilemap.remove_child(child)
			child.free()

	# --- 2. 库存资源 ---
	var inv = get_node_or_null("/root/InventoryManager")
	if inv and data.has("inventory"):
		var d = data["inventory"]
		inv.set_resources(int(d.get("wood", 0)), int(d.get("stone", 0)), int(d.get("meat", 0)), int(d.get("fiber", 0)))
		if "tools" in inv:
			var saved_tools: Dictionary = d.get("tools", {})
			for tool_id in inv.tools.keys():
				inv.tools[tool_id] = int(saved_tools.get(tool_id, inv.tools.get(tool_id, 0)))

	# --- 3. 时间 ---
	var time_mgr = get_node_or_null("/root/TimeManager")
	if time_mgr and data.has("time"):
		var d = data["time"]
		time_mgr.current_day = int(d.get("day", 1))
		time_mgr.current_hour = float(d.get("hour", 8.0))

	var wolf_mgr = get_node_or_null("/root/WolfManager")
	if wolf_mgr and data.has("wolf_state") and wolf_mgr.has_method("restore"):
		wolf_mgr.restore(data["wolf_state"])

	# --- 4. 仓库单元格 + 视觉 ---
	var stockpile_mgr = get_node_or_null("/root/StockpileManager")
	if stockpile_mgr and data.has("stockpile_cells"):
		var haul_mgr = get_node_or_null("/root/HaulManager")
		for cd in data["stockpile_cells"]:
			var cell = Vector2i(int(cd.get("x", 0)), int(cd.get("y", 0)))
			stockpile_mgr.stockpile_cells.append(cell)
			if haul_mgr:
				# 不调用 add_stockpile_cell 避免触发信号，直接写入并生成视觉
				_restore_stockpile_visual(tilemap, cell)
		# 手动触发一次更新相关 UI
		EventBus.stockpile_updated.emit()

	var farm_mgr = get_node_or_null("/root/FarmManager")
	if farm_mgr and data.has("farms") and farm_mgr.has_method("restore"):
		farm_mgr.restore(data["farms"])
		_rebuild_farm_visuals()

	# --- 5. 资源节点：地图已按 seed 重新生成，只需将"已销毁坐标"对应的节点删尼 ---
	if tilemap and data.has("removed_cells") and not data.has("resource_nodes"):
		for rc in data["removed_cells"]:
			var cell = Vector2i(int(rc.get("x", 0)), int(rc.get("y", 0)))
			# 在地图子节点中找到这个坐标的资源节点并删除
			for child in tilemap.get_children():
				if child.is_in_group("resources"):
					var gc = child.get("grid_coord") if "grid_coord" in child else Vector2i(-999, -999)
					if gc == cell:
						# 还原 删除该格 AStar solid 状态
						if child.has_method("_get_tilemap_layer"):
							pass # remove_solid 在 queue_free 前调用可能导致问题
						tilemap.astar_grid.set_point_solid(cell, false)
						child.queue_free()
						break

	if tilemap and data.has("resource_nodes"):
		for rd in data["resource_nodes"]:
			_restore_resource_node(tilemap, rd)

	if tilemap and data.has("buildings"):
		for bd in data["buildings"]:
			_restore_building(tilemap, bd)

	if data.has("craft_jobs"):
		_restore_craft_jobs(data["craft_jobs"])

	var room_mgr = get_node_or_null("/root/RoomManager")
	if room_mgr and data.has("rooms") and room_mgr.has_method("restore"):
		room_mgr.restore(data["rooms"])
	elif room_mgr and room_mgr.has_method("rebuild_rooms"):
		room_mgr.rebuild_rooms()

	# --- 6. 动物 ---
	if tilemap and data.has("animals"):
		for ad in data["animals"]:
			_restore_animal(tilemap, ad)

	# --- 7. 掉落物（ItemDrop）---
	if tilemap and data.has("items"):
		for itd in data["items"]:
			_restore_item_drop(tilemap, itd)

	# --- 8. 村民 ---
	if tilemap and data.has("villagers"):
		for vd in data["villagers"]:
			_restore_villager(tilemap, vd)

	if data.has("settings"):
		_restore_settings(data["settings"])

	# 跳过教程
	tutorial_active = false
	if tut_panel: tut_panel.visible = false

	if DEBUG_NODE2D_LOGS:
		print("=== _restore_from_save() 完成 ===")

func _restore_stockpile_visual(tilemap: Node, cell: Vector2i) -> void:
	if not tilemap: return
	var visual_node = Node2D.new()
	var panel = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.border_color = Color(1.0, 1.0, 0.0, 0.4)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	panel.size = Vector2(16, 16)
	panel.position = Vector2(-8, -8)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_node.add_child(panel)
	visual_node.global_position = tilemap.map_to_local(cell)
	tilemap.add_child(visual_node)
	stockpile_visuals[cell] = visual_node

func _restore_resource_node(tilemap: Node, rd: Dictionary) -> void:
	var res_node = StaticBody2D.new()
	var scr = load("res://scripts/entities/ResourceNode.gd")
	if scr:
		res_node.set_script(scr)

	var type_idx = int(rd.get("type", 0))
	var gc = Vector2i(int(rd.get("grid_x", 0)), int(rd.get("grid_y", 0)))
	res_node.add_to_group("resources")
	match type_idx:
		0:
			res_node.add_to_group("trees")
		1:
			res_node.add_to_group("rocks")
		3:
			res_node.add_to_group("fibers")
			res_node.add_to_group("trees")

	if "type" in res_node:
		res_node.type = type_idx
	if "max_health" in res_node:
		res_node.max_health = float(rd.get("max_health", 100.0))
	if "gather_yield" in res_node:
		res_node.gather_yield = int(rd.get("gather_yield", 15))
	if "grid_coord" in res_node:
		res_node.grid_coord = gc

	tilemap.add_child(res_node)
	res_node.global_position = Vector2(float(rd.get("pos_x", tilemap.to_global(tilemap.map_to_local(gc)).x)), float(rd.get("pos_y", tilemap.to_global(tilemap.map_to_local(gc)).y)))
	if "current_health" in res_node:
		res_node.current_health = float(rd.get("current_health", res_node.max_health if "max_health" in res_node else 100.0))
	if "astar_grid" in tilemap and tilemap.astar_grid:
		tilemap.astar_grid.set_point_solid(gc, true)

func _restore_building(tilemap: Node, bd: Dictionary) -> void:
	var building_resource_path = str(bd.get("building_resource_path", ""))
	var building_res: BuildingResource = null
	if building_resource_path != "":
		building_res = load(building_resource_path)

	if not building_res:
		building_res = _fallback_building_resource(int(bd.get("type", 0)))
	if not building_res or not building_res.scene:
		return

	var gc = Vector2i(int(bd.get("grid_x", 0)), int(bd.get("grid_y", 0)))
	var building = building_res.scene.instantiate()
	if "type" in building:
		building.type = int(bd.get("type", building_res.type))
	if "grid_coord" in building:
		building.grid_coord = gc
	if building_resource_path != "":
		building.set_meta("building_resource_path", building_resource_path)

	building.global_position = Vector2(float(bd.get("pos_x", tilemap.to_global(tilemap.map_to_local(gc)).x)), float(bd.get("pos_y", tilemap.to_global(tilemap.map_to_local(gc)).y)))
	get_tree().current_scene.add_child(building)

	if building.has_method("setup"):
		building.setup(building_res)
	if "max_health" in building:
		building.max_health = float(bd.get("max_health", building_res.max_health))
	if "current_health" in building:
		building.current_health = float(bd.get("current_health", building.max_health))
	if "is_open" in building and bool(bd.get("is_open", false)) and building.has_method("_set_door_state"):
		building._set_door_state(true)

func _restore_craft_jobs(saved_jobs: Array) -> void:
	var job_mgr = get_node_or_null("/root/JobManager")
	if not job_mgr or not job_mgr.has_method("add_craft_job"):
		return
	for jd in saved_jobs:
		var cell = Vector2i(int(jd.get("grid_x", 0)), int(jd.get("grid_y", 0)))
		var workbench = _find_building_at_cell(cell)
		if not is_instance_valid(workbench):
			continue
		var recipe_id = str(jd.get("recipe_id", ""))
		if recipe_id == "":
			continue
		if job_mgr.add_craft_job(recipe_id, workbench):
			var progress = float(jd.get("progress_minutes", 0.0))
			if progress > 0.0 and job_mgr.has_method("add_craft_progress"):
				job_mgr.add_craft_progress(workbench, progress)

func _find_building_at_cell(cell: Vector2i) -> Node:
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		var gc: Vector2i = b.get("grid_coord") if "grid_coord" in b else Vector2i(-99999, -99999)
		if gc == cell:
			return b
	return null

func _restore_settings(settings: Dictionary) -> void:
	pass

func _fallback_building_resource(type_idx: int) -> BuildingResource:
	var path = "res://resources/WoodDoor.tres" if type_idx == BuildingResource.BuildingType.DOOR else "res://resources/WoodWall.tres"
	return load(path)

func _restore_animal(tilemap: Node, ad: Dictionary) -> void:
	var species = ad.get("species", "pig")
	var pos = Vector2(float(ad.get("pos_x", 0)), float(ad.get("pos_y", 0)))
	var hp = int(ad.get("health", 2))

	var animal = CharacterBody2D.new()
	var scr = load("res://scripts/entities/Animal.gd")
	if scr: animal.set_script(scr)
	animal.add_to_group("animals")
	if "species" in animal: animal.species = species
	if "health" in animal: animal.health = hp

	var sprite = Sprite2D.new()
	var tex_path = "res://art/animals/pig.png"
	if species == "chicken":
		tex_path = "res://art/animals/chicken.png"
	elif species == "wolf":
		tex_path = "res://art/animals/howl.png"
	if FileAccess.file_exists(tex_path):
		sprite.texture = load(tex_path)
	else:
		sprite.texture = load("res://icon.svg")
		sprite.scale = Vector2(0.3, 0.3)
	animal.add_child(sprite)
	tilemap.add_child(animal)
	animal.global_position = pos

func _restore_item_drop(tilemap: Node, itd: Dictionary) -> void:
	var item_scene = load("res://scenes/ItemDrop.tscn")
	if not item_scene: return
	var item = item_scene.instantiate()
	item.type = int(itd.get("type", 0))
	if "item_id" in item:
		item.item_id = str(itd.get("item_id", ""))
	item.amount = int(itd.get("amount", 1))
	var gc = Vector2i(int(itd.get("grid_x", 0)), int(itd.get("grid_y", 0)))
	item.grid_coord = gc
	tilemap.add_child(item)
	item.global_position = Vector2(float(itd.get("pos_x", 0)), float(itd.get("pos_y", 0)))
	# ItemDrop._ready() 会自动注册到 HaulManager

func _restore_villager(tilemap: Node, vd: Dictionary) -> void:
	var vil_name = vd.get("name", "村民")
	var pos = Vector2(float(vd.get("pos_x", 0)), float(vd.get("pos_y", 0)))

	var villager = CharacterBody2D.new()
	var val_script = load("res://scripts/entities/Villager.gd")
	if val_script: villager.set_script(val_script)
	villager.name = vil_name
	villager.z_index = 10

	var sprite = Sprite2D.new()
	var names_known = ["阿福", "旺财", "来福"]
	var tex_idx = (names_known.find(vil_name) + 1) if vil_name in names_known else 1
	var tex_path = "res://art/characters/villager" + str(tex_idx) + ".png"
	if FileAccess.file_exists(tex_path) or FileAccess.file_exists(tex_path + ".import"):
		sprite.texture = load(tex_path)
		sprite.scale = Vector2(1.6, 1.6)
	else:
		sprite.texture = load("res://icon.svg")
		sprite.scale = Vector2(0.4, 0.4)
	villager.add_child(sprite)

	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(16, 16)
	collision.shape = shape
	villager.add_child(collision)

	tilemap.add_child(villager)
	villager.global_position = pos
	villager.input_pickable = true
	villager.add_to_group("villagers")

	# 恢复属性
	if "hunger" in villager: villager.hunger = float(vd.get("hunger", 100.0))
	if "energy" in villager: villager.energy = float(vd.get("energy", 100.0))
	if "mood" in villager: villager.mood = int(vd.get("mood", 100))
	if "base_mood" in villager: villager.base_mood = float(vd.get("base_mood", 100.0))
	if "mood_penalties" in villager: villager.mood_penalties = vd.get("mood_penalties", {})
	if "health" in villager: villager.health = float(vd.get("health", 100.0))
	if "max_health" in villager: villager.max_health = float(vd.get("max_health", 100.0))
	if "is_on_strike" in villager: villager.is_on_strike = bool(vd.get("is_on_strike", false))
	if "strike_timer" in villager: villager.strike_timer = float(vd.get("strike_timer", 0.0))
	if "strike_check_timer" in villager: villager.strike_check_timer = float(vd.get("strike_check_timer", 0.0))
	if "wolf_hit_count" in villager: villager.wolf_hit_count = int(vd.get("wolf_hit_count", 0))
	if "unconscious_elapsed_hours" in villager: villager.unconscious_elapsed_hours = float(vd.get("unconscious_elapsed_hours", 0.0))
	if "is_unconscious" in villager:
		villager.is_unconscious = bool(vd.get("is_unconscious", false))
		if villager.is_unconscious and villager.has_method("set_unconscious"):
			villager.set_unconscious(true)
			villager.unconscious_elapsed_hours = float(vd.get("unconscious_elapsed_hours", 0.0))
	if "skill_woodcut" in villager: villager.skill_woodcut = int(vd.get("skill_woodcut", 1))
	if "skill_mining" in villager: villager.skill_mining = int(vd.get("skill_mining", 1))
	if "skill_melee" in villager: villager.skill_melee = int(vd.get("skill_melee", 1))
	if "inventory" in villager: villager.inventory = vd.get("inventory", {})
	if "equipped_tool_id" in villager: villager.equipped_tool_id = str(vd.get("equipped_tool_id", ""))
	if "social_relations" in villager:
		var sr = vd.get("social_relations", {})
		villager.social_relations = sr

	# 执行首位村民相机定位
	if camera and villager == get_tree().get_nodes_in_group("villagers").front():
		camera.position = pos

	# 添加人物图鉴按钮
	if colonist_bar:
		var btn = Button.new()
		btn.text = vil_name
		btn.custom_minimum_size = Vector2(80, 40)
		var tmp_vil = villager
		btn.pressed.connect(func(): select_villager(tmp_vil))
		colonist_bar.add_child(btn)
