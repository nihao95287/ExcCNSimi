extends Node2D

var DEBUG_MENU_LOGS: bool:
	get: return SettingsManager.settings.get("debug_logs", false)

func _ready() -> void:
	if DEBUG_MENU_LOGS:
		print("=== Menu._ready() ===")
	$CenterContainer/VBox/Start_Button.pressed.connect(_on_start_button_pressed)
	$CenterContainer/VBox/Continue_Button.pressed.connect(_on_continue_button_pressed)
	$CenterContainer/VBox/Settings_Button.pressed.connect(_on_settings_button_pressed)
	$CenterContainer/VBox/Exit_Button.pressed.connect(_on_exit_button_pressed)
	if DEBUG_MENU_LOGS:
		print("Menu按钮已连接")

	# 播放菜单 BGM
	if EventBus:
		EventBus.play_bgm.emit("menu", 1.5)

	# 根据是否有存档，调整 Continue 按钮外观
	var save_mgr = get_node_or_null("/root/SaveManager")
	var continue_btn = $CenterContainer/VBox/Continue_Button
	if save_mgr and save_mgr.has_save():
		continue_btn.modulate = Color(1.0, 1.0, 1.0, 1.0)
	else:
		# 灰显但仍可见，点击时会提示"无存档"
		continue_btn.modulate = Color(0.6, 0.6, 0.6, 0.75)

func _on_start_button_pressed() -> void:
	if DEBUG_MENU_LOGS:
		print("=== 开始游戏按钮被点击 ===")
	var map_data_scene = load("res://scenes/MapData.tscn")
	if map_data_scene:
		if DEBUG_MENU_LOGS:
			print("创建MapData场景...")
		var overlay = map_data_scene.instantiate()
		add_child(overlay)
		if DEBUG_MENU_LOGS:
			print("MapData已添加为子节点")
	else:
		push_error("错误：无法加载MapData场景")

func _on_continue_button_pressed() -> void:
	if DEBUG_MENU_LOGS:
		print("=== 继续游戏按钮被点击 ===")
	var save_mgr = get_node_or_null("/root/SaveManager")
	if not save_mgr or not save_mgr.has_save():
		if DEBUG_MENU_LOGS:
			print("没有存档，无法继续")
		# 临时显示一个提示 Label
		_show_no_save_hint()
		return

	var data = save_mgr.load_save()
	if data.is_empty():
		if DEBUG_MENU_LOGS:
			print("存档读取失败")
		return

	# 加载 Main 场景
	var main_scene = load("res://scenes/Main.tscn")
	if not main_scene:
		push_error("错误：无法加载 Main.tscn")
		return

	var main_instance = main_scene.instantiate()

	# 注入存档数据（在 _ready 之前写入，等 map_generated 信号后再恢复）
	if "pending_save_data" in main_instance:
		main_instance.pending_save_data = data

	# 注入地图参数（让 TileMapLayer 用相同 seed 重建地形）
	if data.has("map_params"):
		var mp = data["map_params"]
		var tilemap = main_instance.get_node_or_null("TileMapLayer")
		if tilemap:
			if "seed_val" in tilemap: tilemap.seed_val = int(mp.get("seed_val", 0))
			if "mapWidth" in tilemap: tilemap.mapWidth = int(mp.get("mapWidth", 256))
			if "mapHeight" in tilemap: tilemap.mapHeight = int(mp.get("mapHeight", 256))
			if "water_threshold" in tilemap: tilemap.water_threshold = float(mp.get("water_threshold", -0.6))
			if "light_grass_threshold" in tilemap: tilemap.light_grass_threshold = float(mp.get("light_grass_threshold", -0.4))
			if "dark_grass_threshold" in tilemap: tilemap.dark_grass_threshold = float(mp.get("dark_grass_threshold", -0.1))
			if "dirt_threshold" in tilemap: tilemap.dirt_threshold = float(mp.get("dirt_threshold", 0.2))
			if "rock_threshold" in tilemap: tilemap.rock_threshold = float(mp.get("rock_threshold", 0.5))
			if "pig_spawn_chance" in tilemap: tilemap.pig_spawn_chance = float(mp.get("pig_spawn_chance", 0.0015))
			if "chicken_spawn_chance" in tilemap: tilemap.chicken_spawn_chance = float(mp.get("chicken_spawn_chance", 0.003))
			if "fiber_spawn_chance" in tilemap: tilemap.fiber_spawn_chance = float(mp.get("fiber_spawn_chance", 0.10))

	var root = get_tree().root
	root.add_child(main_instance)
	get_tree().current_scene = main_instance

	# 删除 Menu 及其他非 autoload 旧节点
	var autoloads = ["EventBus", "GameManager", "InventoryManager", "StockpileManager",
					"HaulManager", "BuildManager", "RoomManager", "JobManager", "TimeManager", "WolfManager", "SaveManager", "FarmManager", "AudioManager", "SettingsManager"]
	var to_free: Array[Node] = []
	for child in root.get_children():
		if child == main_instance: continue
		if child.name in autoloads: continue
		to_free.append(child)
	for n in to_free:
		n.queue_free()

	if DEBUG_MENU_LOGS:
		print("=== 读档完成，已跳转到游戏场景 ===")

func _on_settings_button_pressed() -> void:
	if DEBUG_MENU_LOGS:
		print("=== 设置按钮被点击 ===")
	var settings_script = load("res://scripts/ui/SettingsMenu.gd")
	if settings_script:
		var settings_ui = CanvasLayer.new()
		settings_ui.set_script(settings_script)
		add_child(settings_ui)
	else:
		push_error("错误：无法加载 SettingsMenu.gd")

func _on_exit_button_pressed() -> void:
	get_tree().quit()

func _show_no_save_hint() -> void:
	# 如果已经有提示则先删除
	var old = get_node_or_null("NoSaveHint")
	if old: old.queue_free()

	var lbl = Label.new()
	lbl.name = "NoSaveHint"
	lbl.text = "⚠  暂无存档，请先开始新游戏"
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	lbl.grow_vertical = Control.GROW_DIRECTION_BOTH
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(get_viewport_rect().size / 2) + Vector2(0, 80)
	add_child(lbl)

	# 1.5 秒后淡出并删除
	var tween = create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.5)
	tween.tween_callback(lbl.queue_free)
