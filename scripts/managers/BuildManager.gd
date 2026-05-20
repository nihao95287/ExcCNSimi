extends Node

@export var ghost_color_valid: Color = Color(0, 1, 0, 0.5)
@export var ghost_color_invalid: Color = Color(1, 0, 0, 0.5)

var current_building_data: BuildingResource = null
var ghost_sprite: Sprite2D = null
var is_building_mode: bool = false
const TILE_VISUAL_SIZE: float = 16.0

func _ready() -> void:
	EventBus.build_requested.connect(_on_build_requested)

func _on_build_requested(data: BuildingResource) -> void:
	if data and data.is_farm_area:
		_cancel_building_mode()
		EventBus.farm_build_requested.emit(data)
		return
	current_building_data = data
	is_building_mode = true
	_create_ghost()

func _create_ghost() -> void:
	if ghost_sprite:
		ghost_sprite.queue_free()

	ghost_sprite = Sprite2D.new()
	if current_building_data and current_building_data.icon:
		ghost_sprite.texture = current_building_data.icon
		_apply_sprite_tile_scale(ghost_sprite, current_building_data.icon)
	ghost_sprite.modulate = ghost_color_valid
	ghost_sprite.z_index = 20
	get_tree().current_scene.add_child(ghost_sprite)

func _input(event: InputEvent) -> void:
	if not is_building_mode:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place_building()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_building_mode()
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if is_building_mode and ghost_sprite:
		_update_ghost()

func _update_ghost() -> void:
	var tilemap = _get_tilemap()
	if not tilemap:
		return

	var grid_coord = _get_mouse_grid_coord(tilemap)
	ghost_sprite.global_position = tilemap.to_global(tilemap.map_to_local(grid_coord))

	var can_place = _check_placement_valid(grid_coord)
	ghost_sprite.modulate = ghost_color_valid if can_place else ghost_color_invalid

func _check_placement_valid(grid_coord: Vector2i) -> bool:
	var tilemap = _get_tilemap()
	if not tilemap or not current_building_data:
		return false
	if not tilemap.astar_grid or not tilemap.astar_grid.is_in_boundsv(grid_coord):
		return false

	if tilemap.astar_grid.is_point_solid(grid_coord):
		return false

	var haul_manager = get_node_or_null("/root/HaulManager")
	if haul_manager and haul_manager.has_method("is_stockpile_cell"):
		if haul_manager.is_stockpile_cell(grid_coord):
			return false

	var farm_manager = get_node_or_null("/root/FarmManager")
	if farm_manager and farm_manager.has_method("get_plot_at_cell"):
		if not farm_manager.get_plot_at_cell(grid_coord).is_empty():
			return false

	return true

func _place_building() -> void:
	var tilemap = _get_tilemap()
	if not tilemap or not current_building_data:
		return

	var grid_coord = _get_mouse_grid_coord(tilemap)

	if not _check_placement_valid(grid_coord):
		EventBus.alert_message.emit("此处不能建造")
		return

	if not _has_sufficient_resources():
		EventBus.alert_message.emit("资源不足，无法建造")
		return

	if not current_building_data.scene:
		EventBus.alert_message.emit("建筑资源缺少场景，无法建造")
		return

	_deduct_resources()

	var building = current_building_data.scene.instantiate()
	if "type" in building:
		building.type = current_building_data.type
	if "grid_coord" in building:
		building.grid_coord = grid_coord
	var source_path = current_building_data.resource_path
	if source_path != "":
		building.set_meta("building_resource_path", source_path)
	building.global_position = tilemap.to_global(tilemap.map_to_local(grid_coord))
	get_tree().current_scene.add_child(building)

	if building.has_method("setup"):
		building.setup(current_building_data)
	elif building.has_method("set_grid_coord"):
		building.set_grid_coord(grid_coord)

	EventBus.building_placed.emit(grid_coord, current_building_data.type)
	EventBus.alert_message.emit("建造完成")

func _has_sufficient_resources() -> bool:
	var inv_manager = get_node_or_null("/root/InventoryManager")
	if not inv_manager or not current_building_data:
		return false

	for res_name in current_building_data.cost.keys():
		var amount_needed = int(current_building_data.cost[res_name])
		var current_amount = int(inv_manager.get(res_name))
		if current_amount < amount_needed:
			return false
	return true

func _deduct_resources() -> void:
	var inv_manager = get_node_or_null("/root/InventoryManager")
	if not inv_manager:
		return

	var wood = inv_manager.wood
	var stone = inv_manager.stone
	var meat = inv_manager.meat
	var fiber = inv_manager.fiber

	for res_name in current_building_data.cost.keys():
		var amount_needed = int(current_building_data.cost[res_name])
		if res_name == "wood":
			wood -= amount_needed
		elif res_name == "stone":
			stone -= amount_needed
		elif res_name == "meat":
			meat -= amount_needed
		elif res_name == "fiber":
			fiber -= amount_needed

	inv_manager.set_resources(wood, stone, meat, fiber)

func _cancel_building_mode() -> void:
	is_building_mode = false
	current_building_data = null
	if ghost_sprite:
		ghost_sprite.queue_free()
		ghost_sprite = null

func _get_tilemap() -> TileMapLayer:
	var scene = get_tree().current_scene
	if scene:
		var tilemap = scene.find_child("TileMapLayer", true, false)
		if tilemap is TileMapLayer:
			return tilemap
	return null

func _get_mouse_grid_coord(tilemap: TileMapLayer) -> Vector2i:
	var local_pos = tilemap.to_local(tilemap.get_global_mouse_position())
	return tilemap.local_to_map(local_pos)

func _apply_sprite_tile_scale(sprite: Sprite2D, texture: Texture2D) -> void:
	var tex_size = texture.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		return
	var scale_factor = TILE_VISUAL_SIZE / max(tex_size.x, tex_size.y)
	sprite.scale = Vector2(scale_factor, scale_factor)
