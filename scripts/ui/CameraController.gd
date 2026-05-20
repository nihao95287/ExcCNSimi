extends Camera2D

@export var move_speed: float = 800.0
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.2
@export var max_zoom: float = 3.0

var is_dragging: bool = false
var last_mouse_pos: Vector2

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	var move_dir = Vector2.ZERO
	
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		move_dir.x += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		move_dir.x -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		move_dir.y += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		move_dir.y -= 1
		
	if move_dir != Vector2.ZERO:
		position += move_dir.normalized() * move_speed * delta * (1.0 / zoom.x)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_camera(zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_camera(-zoom_speed)
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _parent_is_area_dragging():
					pass
				else:
					is_dragging = true
					last_mouse_pos = event.position
			else:
				is_dragging = false
				
	elif event is InputEventMouseMotion and is_dragging:
		var delta_pos = event.position - last_mouse_pos
		position -= delta_pos * (1.0 / zoom.x)
		last_mouse_pos = event.position

func _zoom_camera(amount: float) -> void:
	var old_zoom = zoom
	zoom += Vector2(amount, amount)
	zoom.x = clamp(zoom.x, min_zoom, max_zoom)
	zoom.y = clamp(zoom.y, min_zoom, max_zoom)

func _parent_is_area_dragging() -> bool:
	var parent_node = get_parent()
	if not parent_node:
		return false
	if "is_building_stockpile" in parent_node and parent_node.is_building_stockpile:
		return true
	if "is_building_farm" in parent_node and parent_node.is_building_farm:
		return true
	return false
