class_name ItemDrop
extends Node2D

var DEBUG_ITEM_DROP_LOGS: bool:
	get: return SettingsManager.settings.get("debug_logs", false)

@export var type: int = 0
@export var amount: int = 1
@export var item_id: String = ""

var grid_coord: Vector2i
var is_reserved: bool = false

func _ready() -> void:
	z_index = 10
	if not Engine.is_editor_hint():
		var haul = get_node_or_null("/root/HaulManager")
		if haul and item_id == "":
			haul.register_item(self)
		_update_visual()

func _update_visual() -> void:
	for child in get_children():
		child.queue_free()

	if item_id != "":
		add_to_group("tool_drops")
		var sprite = Sprite2D.new()
		sprite.name = "Visual"
		sprite.texture = load(_get_tool_icon_path(item_id))
		sprite.scale = _get_tool_drop_scale(item_id)
		add_child(sprite)
		if amount > 1:
			var label = Label.new()
			label.text = "x%d" % amount
			label.position = Vector2(6, 4)
			label.scale = Vector2(0.5, 0.5)
			label.add_theme_font_size_override("font_size", 18)
			add_child(label)
		return

	if type == 3:
		var sprite = Sprite2D.new()
		sprite.name = "Visual"
		sprite.texture = load("res://art/objects/grass.png")
		sprite.scale = Vector2(0.35, 0.35)
		add_child(sprite)
		return

	var color_rect = ColorRect.new()
	color_rect.name = "Visual"
	color_rect.size = Vector2(12, 12)
	var colors = [
		Color(0.55, 0.35, 0.15),  # 0: 木材 - 棕色
		Color(0.55, 0.55, 0.55),  # 1: 石头 - 灰色
		Color(0.85, 0.20, 0.20),  # 2: 肉类 - 红色
		Color(0.35, 0.85, 0.25),  # 3: 纤维 - 亮绿色
	]
	var col = colors[type] if type < colors.size() else Color(1.0, 1.0, 1.0)
	color_rect.color = col
	color_rect.position = Vector2(-6, -6)
	add_child(color_rect)

func _get_tool_icon_path(id: String) -> String:
	match id:
		"wood_axe":
			return "res://art/a/tools/axe1.png"
		"wood_pickaxe":
			return "res://art/a/tools/pickaxe1.png"
		"stone_axe":
			return "res://art/a/tools/axe2.png"
		"stone_pickaxe":
			return "res://art/a/tools/pickaxe2.png"
		"bandage":
			return "res://art/tools/bandage.svg"
		"wood_sword":
			return "res://art/a/tools/spear1.png"
		"stone_sword":
			return "res://art/a/tools/spear2.png"
		"bow":
			return "res://art/tools/bow.svg"
		"arrow":
			return "res://art/tools/arrow.svg"
		"fishing_rod":
			return "res://art/tools/fishing_rod.svg"
		_:
			return "res://icon.svg"

func _get_tool_drop_scale(id: String) -> Vector2:
	match id:
		"bandage":
			return Vector2(0.3, 0.3)
		"wood_sword", "stone_sword":
			return Vector2(0.5, 0.5)
		"bow", "arrow", "fishing_rod":
			return Vector2(0.45, 0.45)
		_:
			return Vector2(0.4, 0.4)

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		EventBus.item_registered.emit(self)
		get_viewport().set_input_as_handled()
