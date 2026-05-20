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
	
	# 支持 WASD 和方向键
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		move_dir.x += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		move_dir.x -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		move_dir.y += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		move_dir.y -= 1
		
	# 根据缩放比例调整移动速度
	if move_dir != Vector2.ZERO:
		position += move_dir.normalized() * move_speed * delta * (1.0 / zoom.x)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# 鼠标滚轮缩放
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_camera(zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_camera(-zoom_speed)
		
		# 鼠标中键拖拽平移改为左键
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var parent = get_parent()
				if parent and "is_building_stockpile" in parent and parent.is_building_stockpile:
					pass # 在划定仓库时禁止相机平移
				else:
					is_dragging = true
					last_mouse_pos = event.position
			else:
				is_dragging = false
				
	elif event is InputEventMouseMotion and is_dragging:
		var delta_pos = event.position - last_mouse_pos
		# 同样根据缩放比例调整拖拽灵敏度
		position -= delta_pos * (1.0 / zoom.x)
		last_mouse_pos = event.position

func _zoom_camera(amount: float) -> void:
	var old_zoom = zoom
	zoom += Vector2(amount, amount)
	zoom.x = clamp(zoom.x, min_zoom, max_zoom)
	zoom.y = clamp(zoom.y, min_zoom, max_zoom)
	
	# 这里后续可以加入以鼠标当前位置为中心的缩放逻辑
