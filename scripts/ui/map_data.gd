extends Node2D

@onready var textures: Array[TextureRect] = [
	$ColorRect/ReferenceRect/TextureRect,
	$ColorRect/ReferenceRect/TextureRect1,
	$ColorRect/ReferenceRect/TextureRect2,
]
@onready var return_button: Button = $ColorRect/ReferenceRect/Return_Button
@onready var ok_button: Button = $ColorRect/ReferenceRect/OK_Button

const BRIGHT_COLOR: Color = Color(1.1, 1.1, 1.1, 1.0)
const DARK_COLOR: Color = Color(0.4, 0.4, 0.4, 1.0)
const ANIM_SPEED: float = 0.2

const TERRAIN_PRESETS: Array[Dictionary] = [
	{
		"water_threshold": -0.68,
		"light_grass_threshold": -0.5,
		"dark_grass_threshold": -0.43,
		"dirt_threshold": -0.35,
		"rock_threshold": -0.3,
	},
	{
		"water_threshold": -0.74,
		"light_grass_threshold": -0.71,
		"dark_grass_threshold": -0.53,
		"dirt_threshold": -0.4,
		"rock_threshold": -0.36,
	},
	{
		"water_threshold": -0.8,
		"light_grass_threshold": -0.72,
		"dark_grass_threshold": -0.687,
		"dirt_threshold": -0.6,
		"rock_threshold": -0.511,
	},
]

@export var map_scene_path: String = "res://scenes/Main.tscn"

var selected_index: int = 0

func _ready() -> void:
	if return_button and not return_button.pressed.is_connected(_on_return_button_pressed):
		return_button.pressed.connect(_on_return_button_pressed)
	if ok_button and not ok_button.pressed.is_connected(_on_ok_button_pressed):
		ok_button.pressed.connect(_on_ok_button_pressed)

	for i in range(textures.size()):
		var tex = textures[i]
		if tex == null:
			continue
		tex.mouse_filter = Control.MOUSE_FILTER_STOP
		tex.pivot_offset = tex.size / 2
		if tex.gui_input.is_connected(_on_texture_gui_input):
			tex.gui_input.disconnect(_on_texture_gui_input)
		tex.gui_input.connect(_on_texture_gui_input.bind(i))

	selected_index = 0
	_apply_initial_highlight()

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
		if selected_index != index:
			selected_index = index
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
	_show_loading_overlay()
	if ok_button:
		ok_button.disabled = true
	await get_tree().process_frame

	if map_scene_path == "":
		return

	var map_scene = load(map_scene_path)
	if not map_scene:
		return

	var tree = get_tree()
	if not tree:
		return

	var root = tree.root
	var map_root_instance = map_scene.instantiate()

	if map_root_instance is Node2D:
		map_root_instance.position = Vector2.ZERO

	var map_layer = map_root_instance.get_node_or_null("TileMapLayer")
	if map_layer:
		map_layer.position = Vector2.ZERO
		var data = TERRAIN_PRESETS[selected_index]
		map_layer.water_threshold = data["water_threshold"]
		map_layer.light_grass_threshold = data["light_grass_threshold"]
		map_layer.dark_grass_threshold = data["dark_grass_threshold"]
		map_layer.dirt_threshold = data["dirt_threshold"]
		map_layer.rock_threshold = data["rock_threshold"]
		map_layer.map_type = selected_index

	root.add_child(map_root_instance)
	tree.current_scene = map_root_instance

	for child in root.get_children():
		if child == map_root_instance:
			continue
		if child.name == "Menu" or child.name == "MapData" or child == self:
			child.queue_free()

	if is_inside_tree():
		queue_free()

func _on_return_button_pressed() -> void:
	queue_free()

func _show_loading_overlay() -> void:
	var root = get_tree().root
	var old = root.get_node_or_null("GlobalLoadingLayer")
	if old:
		old.queue_free()

	var layer = CanvasLayer.new()
	layer.name = "GlobalLoadingLayer"
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(layer)

	var overlay = ColorRect.new()
	overlay.name = "LoadingOverlay"
	overlay.color = Color.BLACK
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(overlay)

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
	overlay.add_child(label)
