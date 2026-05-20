extends StaticBody2D
class_name Building

@export var type: BuildingResource.BuildingType = BuildingResource.BuildingType.WALL
@export var max_health: float = 100.0
@export var current_health: float = 100.0

var grid_coord: Vector2i
var is_open: bool = false
var entities_inside: int = 0
var door_tween: Tween = null
var light_node: PointLight2D = null
var light_energy_day: float = 0.0
var light_energy_night: float = 0.0
var is_bed: bool = false
var is_workbench: bool = false
var blocks_arrows: bool = true
var room_id: int = -1
var owner_name: String = ""

const TILE_VISUAL_SIZE: float = 16.0
const DOOR_FADE_TIME: float = 0.18
const DOOR_CLOSE_DELAY: float = 0.15

func _ready() -> void:
	add_to_group("buildings")
	_sync_to_grid()
	_update_astar()
	_connect_door_area()

func setup(data: BuildingResource) -> void:
	type = data.type
	max_health = data.max_health
	current_health = min(current_health, max_health)
	if current_health <= 0.0:
		current_health = max_health
	blocks_arrows = data.blocks_arrows
	is_bed = data.is_bed
	is_workbench = data.is_workbench
	if data.is_bed:
		add_to_group("beds")
	if data.is_workbench:
		add_to_group("workbenches")
	_apply_icon(data.icon, data.visual_size)
	_setup_light(data)
	_update_astar()
	_connect_door_area()

func _process(_delta: float) -> void:
	_update_light_strength()

func _apply_icon(icon: Texture2D, visual_size: float = TILE_VISUAL_SIZE) -> void:
	if not icon:
		return

	var sprite = get_node_or_null("Sprite2D") as Sprite2D
	if not sprite:
		sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		add_child(sprite)

	sprite.texture = icon
	sprite.centered = true
	sprite.visible = true
	sprite.modulate = Color(1, 1, 1, 1)
	sprite.z_index = 10

	var tex_size = icon.get_size()
	if tex_size.x > 0 and tex_size.y > 0:
		var scale_factor = visual_size / max(tex_size.x, tex_size.y)
		sprite.scale = Vector2(scale_factor, scale_factor)

func _sync_to_grid() -> void:
	var tilemap = _get_tilemap()
	if tilemap:
		grid_coord = tilemap.local_to_map(tilemap.to_local(global_position))
		global_position = tilemap.to_global(tilemap.map_to_local(grid_coord))

func _update_astar() -> void:
	var tilemap = _get_tilemap()
	if tilemap and "astar_grid" in tilemap:
		var is_solid = (type != BuildingResource.BuildingType.DOOR)
		tilemap.astar_grid.set_point_solid(grid_coord, is_solid)

func _setup_light(data: BuildingResource) -> void:
	if not data.provides_light:
		if light_node:
			light_node.queue_free()
			light_node = null
		set_process(false)
		return

	light_energy_day = data.light_energy_day
	light_energy_night = data.light_energy_night

	light_node = get_node_or_null("PointLight2D") as PointLight2D
	if not light_node:
		light_node = PointLight2D.new()
		light_node.name = "PointLight2D"
		add_child(light_node)

	light_node.enabled = true
	light_node.color = Color(1.0, 0.66, 0.28)
	light_node.texture = _make_light_texture()
	light_node.texture_scale = data.light_radius
	light_node.z_index = 8
	set_process(true)
	_update_light_strength()

func _make_light_texture() -> Texture2D:
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1, 0.75, 0.28, 1))
	gradient.set_color(1, Color(1, 0.45, 0.05, 0))

	var texture = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture

func _update_light_strength() -> void:
	if not light_node:
		return

	var time_mgr = get_node_or_null("/root/TimeManager")
	var darkness = 1.0
	if time_mgr:
		var sun = time_mgr.get_sun_color()
		var brightness = (sun.r + sun.g + sun.b) / 3.0
		darkness = 1.0 - clamp((brightness - 0.18) / 0.82, 0.0, 1.0)

	light_node.energy = lerp(light_energy_day, light_energy_night, darkness)

func _connect_door_area() -> void:
	if type != BuildingResource.BuildingType.DOOR:
		return

	add_to_group("doors")
	var area = get_node_or_null("DetectionArea")
	if area:
		area.monitoring = true
		area.monitorable = true
		area.collision_mask = 1
		if not area.body_entered.is_connected(_on_body_entered):
			area.body_entered.connect(_on_body_entered)
		if not area.body_exited.is_connected(_on_body_exited):
			area.body_exited.connect(_on_body_exited)

func _get_tilemap() -> TileMapLayer:
	var scene = get_tree().current_scene
	if scene:
		var tilemap = scene.find_child("TileMapLayer", true, false)
		if tilemap is TileMapLayer:
			return tilemap
	return null

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("villagers"):
		entities_inside += 1
		if not is_open:
			_set_door_state(true)

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("villagers"):
		entities_inside -= 1
		if entities_inside <= 0:
			entities_inside = 0
			_set_door_state(false)

func _set_door_state(open: bool) -> void:
	is_open = open
	var sprite = get_node_or_null("Sprite2D") as Sprite2D
	set_collision_layer_value(1, not open)
	set_collision_mask_value(1, not open)
	set_collision_layer_value(4, not open)

	if not sprite:
		return

	if door_tween:
		door_tween.kill()

	sprite.visible = true
	door_tween = create_tween()
	if open:
		door_tween.tween_property(sprite, "modulate:a", 0.0, DOOR_FADE_TIME)
		door_tween.tween_callback(func(): sprite.visible = false)
	else:
		sprite.modulate.a = 0.0
		door_tween.tween_interval(DOOR_CLOSE_DELAY)
		door_tween.tween_callback(func(): sprite.visible = true)
		door_tween.tween_property(sprite, "modulate:a", 1.0, DOOR_FADE_TIME)

func take_damage(amount: float) -> void:
	current_health -= amount
	if current_health <= 0:
		_on_destroyed()

func _on_destroyed() -> void:
	var tilemap = _get_tilemap()
	if tilemap and "astar_grid" in tilemap:
		tilemap.astar_grid.set_point_solid(grid_coord, false)
	EventBus.building_demolished.emit(grid_coord, type)
	queue_free()

## 玩家主动拆除：返还一半建造资源，清除 AStar，通知 EventBus
func demolish() -> void:
	# 返还资源
	var building_resource_path = get_meta("building_resource_path", "") as String
	if building_resource_path != "":
		var data: BuildingResource = load(building_resource_path)
		if data and not data.cost.is_empty():
			var inv = get_node_or_null("/root/InventoryManager")
			if inv:
				var refund_wood = int(float(data.cost.get("wood", 0)) / 2.0)
				var refund_stone = int(float(data.cost.get("stone", 0)) / 2.0)
				var refund_meat = int(float(data.cost.get("meat", 0)) / 2.0)
				var refund_fiber = int(float(data.cost.get("fiber", 0)) / 2.0)
				inv.set_resources(
					inv.wood + refund_wood,
					inv.stone + refund_stone,
					inv.meat + refund_meat,
					inv.fiber + refund_fiber
				)
				var parts: Array[String] = []
				if refund_wood > 0: parts.append("木材 +%d" % refund_wood)
				if refund_stone > 0: parts.append("石头 +%d" % refund_stone)
				if refund_meat > 0: parts.append("肉类 +%d" % refund_meat)
				if refund_fiber > 0: parts.append("纤维 +%d" % refund_fiber)
				if parts.size() > 0:
					EventBus.alert_message.emit("拆除完成，返还资源：" + "，".join(parts))
				else:
					EventBus.alert_message.emit("拆除完成")

	# 清除 AStar 障碍标记
	var tilemap = _get_tilemap()
	if tilemap and "astar_grid" in tilemap:
		tilemap.astar_grid.set_point_solid(grid_coord, false)

	# 通知系统
	EventBus.building_demolished.emit(grid_coord, type)
	queue_free()
