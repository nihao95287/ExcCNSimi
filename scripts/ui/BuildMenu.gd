extends Node2D

@export var buildings: Array[BuildingResource] = []

@onready var grid_container: GridContainer = $ColorRect/ReferenceRect/GridContainer

const BUILD_BUTTON_SIZE: Vector2 = Vector2(150, 150)
const BUILD_GRID_H_SEPARATION: int = 72
const BUILD_GRID_V_SEPARATION: int = 56
const POPUP_OFFSET: Vector2 = Vector2(20, 20)

var hover_popup: PanelContainer
var hover_label: Label
var hovered_building: BuildingResource = null

func _ready() -> void:
	EventBus.toggle_build_menu.connect(_on_toggle_build_menu)
	_setup_hover_popup()
	_setup_menu()
	visible = false

	var return_btn = get_node_or_null("ColorRect/ReferenceRect/Return_Button")
	if return_btn:
		return_btn.pressed.connect(func(): visible = false)

	var ok_btn = get_node_or_null("ColorRect/ReferenceRect/OK_Button")
	if ok_btn:
		ok_btn.pressed.connect(func(): visible = false)

func _process(_delta: float) -> void:
	if hover_popup and hover_popup.visible:
		hover_popup.global_position = get_global_mouse_position() + POPUP_OFFSET

func _setup_menu() -> void:
	if not grid_container:
		return

	grid_container.add_theme_constant_override("h_separation", BUILD_GRID_H_SEPARATION)
	grid_container.add_theme_constant_override("v_separation", BUILD_GRID_V_SEPARATION)

	for child in grid_container.get_children():
		child.queue_free()

	for building in buildings:
		var btn = TextureButton.new()
		btn.custom_minimum_size = BUILD_BUTTON_SIZE
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.ignore_texture_size = true

		if building.icon:
			btn.texture_normal = building.icon

		btn.tooltip_text = _build_popup_text(building)
		btn.mouse_entered.connect(_show_building_popup.bind(building))
		btn.mouse_exited.connect(_hide_building_popup)
		btn.pressed.connect(_on_building_selected.bind(building))
		grid_container.add_child(btn)

func _setup_hover_popup() -> void:
	hover_popup = PanelContainer.new()
	hover_popup.visible = false
	hover_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_popup.z_index = 100

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.055, 0.05, 0.94)
	style.border_color = Color(0.95, 0.78, 0.42, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	hover_popup.add_theme_stylebox_override("panel", style)

	hover_label = Label.new()
	hover_label.add_theme_font_size_override("font_size", 26)
	hover_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.86))
	hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_label.custom_minimum_size = Vector2(230, 0)
	hover_popup.add_child(hover_label)
	add_child(hover_popup)

func _show_building_popup(building: BuildingResource) -> void:
	hovered_building = building
	hover_label.text = _build_popup_text(building)
	hover_popup.visible = true
	hover_popup.global_position = get_global_mouse_position() + POPUP_OFFSET

func _hide_building_popup() -> void:
	hovered_building = null
	if hover_popup:
		hover_popup.visible = false

func _build_popup_text(building: BuildingResource) -> String:
	var lines: Array[String] = [building.name, "消耗资源:"]
	if building.cost.is_empty():
		lines.append("无")
	else:
		for res_name in building.cost.keys():
			lines.append("%s: %s" % [_resource_display_name(str(res_name)), str(building.cost[res_name])])
	return "\n".join(lines)

func _resource_display_name(res_name: String) -> String:
	match res_name:
		"wood":
			return "木材"
		"stone":
			return "石头"
		"meat":
			return "食物"
		"fiber":
			return "纤维"
		_:
			return res_name

func _on_building_selected(data: BuildingResource) -> void:
	_hide_building_popup()
	EventBus.build_requested.emit(data)
	visible = false

func _on_toggle_build_menu() -> void:
	visible = !visible
	if not visible:
		_hide_building_popup()
