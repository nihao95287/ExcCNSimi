extends Node2D

# 1. 节点引用
@onready var textures = [
	$ColorRect/ReferenceRect/TextureRect,
	$ColorRect/ReferenceRect/TextureRect1,
	$ColorRect/ReferenceRect/TextureRect2
]
@onready var return_button = $ColorRect/ReferenceRect/Return_Button
@onready var ok_button = $ColorRect/ReferenceRect/OK_Button

# 2. 配置参数
const BRIGHT_COLOR = Color(1.1, 1.1, 1.1, 1.0) 
const DARK_COLOR = Color(0.4, 0.4, 0.4, 1.0)   
const ANIM_SPEED = 0.2

# --- 核心：阈值预设 ---
const TERRAIN_PRESETS = [
	{
		"water_threshold": -0.6,
		"light_grass_threshold": -0.5,
		"dark_grass_threshold": -0.43,
		"dirt_threshold": -0.35,
		"rock_threshold": -0.3
	},
	{
		"water_threshold": -0.74,
		"light_grass_threshold": -0.71,
		"dark_grass_threshold": -0.53,
		"dirt_threshold": -0.4,
		"rock_threshold": -0.36
	},
	{
		"water_threshold": -0.8,
		"light_grass_threshold": -0.72,
		"dark_grass_threshold": -0.687,
		"dirt_threshold": -0.6,
		"rock_threshold": -0.511
	}
]

@export var map_scene_path: PackedScene = preload("res://Map_generate.tscn")

# 明确初始化
var selected_index: int = 0 

func _ready() -> void:
	# 确保按钮连接
	if return_button and not return_button.pressed.is_connected(_on_return_button_pressed):
		return_button.pressed.connect(_on_return_button_pressed)
	if ok_button and not ok_button.pressed.is_connected(_on_ok_button_pressed):
		ok_button.pressed.connect(_on_ok_button_pressed)

	# --- 初始化图片 ---
	for i in range(textures.size()):
		var tex = textures[i]
		if tex == null: continue
		
		tex.mouse_filter = Control.MOUSE_FILTER_STOP
		tex.pivot_offset = tex.size / 2 
		
		# 清除旧连接防止重复触发
		if tex.gui_input.is_connected(_on_texture_gui_input):
			tex.gui_input.disconnect(_on_texture_gui_input)
		
		# 重新连接
		tex.gui_input.connect(_on_texture_gui_input.bind(i))
	
	# --- 强制设置初始选择为第一个 ---
	selected_index = 0
	_apply_initial_highlight()

# 新增：初始高亮设置，不走 Tween 动画，直接设值防止“闪现”或“错位”
func _apply_initial_highlight() -> void:
	for i in range(textures.size()):
		if i == selected_index:
			textures[i].modulate = BRIGHT_COLOR
			textures[i].scale = Vector2(1.05, 1.05)
		else:
			textures[i].modulate = DARK_COLOR
			textures[i].scale = Vector2(1.0, 1.0)

func _on_texture_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 只有点击不同的图片才更新，防止重复触发 Tween
		if selected_index != index:
			selected_index = index 
			print("当前选择了场景索引: ", selected_index) # 调试用
			_highlight_node(textures[index])

func _highlight_node(active_node: TextureRect) -> void:
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for tex in textures:
		if tex == active_node:
			tween.tween_property(tex, "modulate", BRIGHT_COLOR, ANIM_SPEED)
			tween.tween_property(tex, "scale", Vector2(1.05, 1.05), ANIM_SPEED)
		else:
			tween.tween_property(tex, "modulate", DARK_COLOR, ANIM_SPEED)
			tween.tween_property(tex, "scale", Vector2(1.0, 1.0), ANIM_SPEED)

func _on_ok_button_pressed() -> void:
	if map_scene_path == null:
		print("错误：未指定场景")
		return

	var tree = get_tree()
	if not tree: return # 安全检查
	
	var root = tree.root
	var map_root_instance = map_scene_path.instantiate()
	
	# 重置位置
	if map_root_instance is Node2D:
		map_root_instance.position = Vector2.ZERO
	
	# 传值
	var map_layer = map_root_instance.get_node_or_null("TileMapLayer")
	if map_layer:
		map_layer.position = Vector2.ZERO
		var data = TERRAIN_PRESETS[selected_index]
		map_layer.water_threshold = data["water_threshold"]
		map_layer.light_grass_threshold = data["light_grass_threshold"]
		map_layer.dark_grass_threshold = data["dark_grass_threshold"]
		map_layer.dirt_threshold = data["dirt_threshold"]
		map_layer.rock_threshold = data["rock_threshold"]
		map_layer.generateMap = true
		print("确认：正在使用预设索引 ", selected_index, " 生成地图")
	
	# 切换
	root.add_child(map_root_instance)
	tree.current_scene = map_root_instance

	# 清理
	for child in root.get_children():
		if child == map_root_instance: continue
		if child.name == "Menu" or child.name == "MapData":
			child.queue_free()

	if is_inside_tree():
		queue_free()

func _on_return_button_pressed() -> void:
	queue_free()
