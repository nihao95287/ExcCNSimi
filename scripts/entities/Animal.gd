class_name Animal
extends CharacterBody2D

@export_group("属性")
@export var species: String = "pig"
@export var move_speed: float = 30.0
@export var health: float = 2.0

@export_group("行为控制")
@export var move_frequency: float = 10.0
@export var frequency_variation: float = 0.5
@export var roam_radius: int = 15
@export var wounded_move_speed_multiplier: float = 0.45

const ITEM_DROP_SCENE = preload("res://scenes/ItemDrop.tscn")
const REACH_THRESHOLD: float = 4.0
const WOLF_ATTACK_RANGE: float = 24.0
const WOLF_ATTACK_INTERVAL: float = 2.6
const WOLF_RETREAT_AFTER_HOURS: float = 3.0

var path: Array[Vector2] = []
var current_target_pos: Vector2 = Vector2.ZERO
var idle_timer: float = 0.0
var is_wounded: bool = false
var is_idle: bool = true
var base_scale: Vector2 = Vector2.ONE
var attack_target: Node2D = null
var attack_timer: float = 0.0
var building_attack_counts: Dictionary = {}
var wolf_attack_elapsed_hours: float = 0.0
var wolf_is_retreating: bool = false

var _haul_manager: Node = null

func _ready() -> void:
	randomize()
	add_to_group("animals")
	_apply_species_defaults()

	_haul_manager = get_node_or_null("/root/HaulManager")
	if not _haul_manager:
		var scene = get_tree().current_scene
		if scene:
			_haul_manager = scene.find_child("HaulManager", true, false)

	is_idle = true
	idle_timer = randf_range(0.5, move_frequency)

func _apply_species_defaults() -> void:
	if species == "pig":
		base_scale = Vector2(2.6, 2.6)
	elif species == "chicken":
		base_scale = Vector2(0.5, 0.5)
	elif species == "wolf":
		base_scale = Vector2(0.9, 0.9)
		move_speed = 42.0
		health = max(health, 5)
	scale = base_scale

func _physics_process(delta: float) -> void:
	if species == "wolf":
		_handle_wolf_logic(delta)
		return

	if is_idle:
		_handle_idle_logic(delta)
	else:
		_handle_movement()

func _handle_movement() -> void:
	if current_target_pos == Vector2.ZERO:
		is_idle = true
		return

	var dir = (current_target_pos - global_position).normalized()
	var dist = global_position.distance_to(current_target_pos)

	if dist < REACH_THRESHOLD:
		if path.size() > 0:
			current_target_pos = path.pop_front()
		else:
			velocity = Vector2.ZERO
			current_target_pos = Vector2.ZERO
			is_idle = true
	else:
		velocity = dir * _get_current_move_speed()
		move_and_slide()

func _get_current_move_speed() -> float:
	if is_wounded and species != "wolf":
		return move_speed * wounded_move_speed_multiplier
	return move_speed

func _handle_idle_logic(delta: float) -> void:
	velocity = Vector2.ZERO
	idle_timer -= delta

	if idle_timer <= 0.0:
		if _set_random_path_target():
			is_idle = false
			_reset_idle_timer()

func _reset_idle_timer() -> void:
	var min_t = move_frequency * (1.0 - frequency_variation)
	var max_t = move_frequency * (1.0 + frequency_variation)
	idle_timer = randf_range(max(0.5, min_t), max_t)

func _set_random_path_target() -> bool:
	var tilemap = _get_tilemap_layer()
	if not tilemap:
		idle_timer = 0.2
		return false

	var current_cell = tilemap.local_to_map(tilemap.to_local(global_position))
	var max_attempts = 15
	for _attempt in range(max_attempts):
		var target_cell = current_cell
		var target_attempts = 10
		while target_attempts > 0:
			var random_offset = Vector2i(
				randi_range(-roam_radius, roam_radius),
				randi_range(-roam_radius, roam_radius)
			)
			target_cell = current_cell + random_offset
			if random_offset != Vector2i.ZERO and not _is_blocked_cell(target_cell):
				break
			target_attempts -= 1

		if target_attempts <= 0:
			continue

		var id_path = tilemap.get_path_coords(current_cell, target_cell, true)
		if id_path.size() <= 1:
			continue

		var path_is_blocked = false
		for i in range(1, id_path.size()):
			if _is_blocked_cell(id_path[i]):
				path_is_blocked = true
				break
		if path_is_blocked:
			continue

		var world_path: Array[Vector2] = []
		for coord in id_path:
			world_path.append(tilemap.to_global(tilemap.map_to_local(coord)))
		if world_path.size() > 1:
			world_path.remove_at(0)
		if world_path.is_empty():
			continue

		path = world_path
		current_target_pos = path.pop_front()
		return true

	idle_timer = 1.0
	return false

func _handle_wolf_logic(delta: float) -> void:
	wolf_attack_elapsed_hours += _delta_to_game_hours(delta)
	if wolf_is_retreating:
		_handle_wolf_retreat()
		return
	if wolf_attack_elapsed_hours >= WOLF_RETREAT_AFTER_HOURS:
		_start_wolf_retreat()
		return

	attack_timer = max(0.0, attack_timer - delta)
	if _wolf_target_invalid(attack_target):
		attack_target = null
		path.clear()
		current_target_pos = Vector2.ZERO

	if not is_instance_valid(attack_target):
		attack_target = _find_wolf_target()
		if attack_target:
			_set_path_to_target(attack_target)

	if not is_instance_valid(attack_target):
		velocity = Vector2.ZERO
		return

	var dist = global_position.distance_to(attack_target.global_position)
	if dist <= WOLF_ATTACK_RANGE:
		velocity = Vector2.ZERO
		path.clear()
		current_target_pos = global_position
		if attack_timer <= 0.0:
			attack_timer = WOLF_ATTACK_INTERVAL
			_wolf_attack(attack_target)
			if _wolf_target_invalid(attack_target):
				attack_target = null
				path.clear()
				current_target_pos = Vector2.ZERO
		return

	if current_target_pos == Vector2.ZERO:
		_set_path_to_target(attack_target)
	_handle_movement()

func _start_wolf_retreat() -> void:
	wolf_is_retreating = true
	attack_target = null
	path.clear()
	current_target_pos = Vector2.ZERO
	var tilemap = _get_tilemap_layer()
	if not tilemap:
		queue_free()
		return
	var target_cell = _find_retreat_edge_cell(tilemap)
	if target_cell == Vector2i(-99999, -99999):
		queue_free()
		return
	_set_path_to_cell(target_cell)
	EventBus.alert_message.emit("狼开始撤离了。")

func _handle_wolf_retreat() -> void:
	if current_target_pos == Vector2.ZERO and path.is_empty():
		queue_free()
		return
	_handle_movement()
	var tilemap = _get_tilemap_layer()
	if tilemap:
		var cell = tilemap.local_to_map(tilemap.to_local(global_position))
		var region = tilemap.astar_grid.region if "astar_grid" in tilemap and tilemap.astar_grid else Rect2i(0, 0, 0, 0)
		if cell.x <= region.position.x or cell.y <= region.position.y or cell.x >= region.position.x + region.size.x - 1 or cell.y >= region.position.y + region.size.y - 1:
			queue_free()

func _set_path_to_cell(target_cell: Vector2i) -> void:
	var tilemap = _get_tilemap_layer()
	if not tilemap:
		return
	var start_cell = tilemap.local_to_map(tilemap.to_local(global_position))
	var id_path = tilemap.get_path_coords(start_cell, target_cell, false)
	if id_path.size() <= 1:
		current_target_pos = tilemap.to_global(tilemap.map_to_local(target_cell))
		return
	var world_path: Array[Vector2] = []
	for coord in id_path:
		world_path.append(tilemap.to_global(tilemap.map_to_local(coord)))
	if world_path.size() > 1:
		world_path.remove_at(0)
	path = world_path
	current_target_pos = path.pop_front() if not path.is_empty() else tilemap.to_global(tilemap.map_to_local(target_cell))

func _find_retreat_edge_cell(tilemap: Node) -> Vector2i:
	if not tilemap or not ("astar_grid" in tilemap) or not tilemap.astar_grid:
		return Vector2i(-99999, -99999)
	var region = tilemap.astar_grid.region
	var current_cell = tilemap.local_to_map(tilemap.to_local(global_position))
	var candidates: Array[Vector2i] = []
	for x in range(region.position.x, region.position.x + region.size.x):
		candidates.append(Vector2i(x, region.position.y))
		candidates.append(Vector2i(x, region.position.y + region.size.y - 1))
	for y in range(region.position.y, region.position.y + region.size.y):
		candidates.append(Vector2i(region.position.x, y))
		candidates.append(Vector2i(region.position.x + region.size.x - 1, y))
	var best = Vector2i(-99999, -99999)
	var best_dist = INF
	for cell in candidates:
		if not tilemap.astar_grid.is_in_boundsv(cell) or tilemap.astar_grid.is_point_solid(cell):
			continue
		var id_path = tilemap.get_path_coords(current_cell, cell, false)
		if id_path.is_empty():
			continue
		var d = current_cell.distance_to(cell)
		if d < best_dist:
			best_dist = d
			best = cell
	return best

func _delta_to_game_hours(delta: float) -> float:
	var time_mgr = get_node_or_null("/root/TimeManager")
	var hours_per_second = time_mgr.hours_per_real_second if time_mgr and "hours_per_real_second" in time_mgr else 0.05
	return delta * hours_per_second

func _find_wolf_target() -> Node2D:
	var best: Node2D = null
	var best_dist = INF

	for villager in get_tree().get_nodes_in_group("villagers"):
		if not is_instance_valid(villager):
			continue
		if bool(villager.get("is_unconscious") if "is_unconscious" in villager else false):
			continue
		var d = global_position.distance_to(villager.global_position)
		if d < best_dist:
			best_dist = d
			best = villager

	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building):
			continue
		var type_val = int(building.get("type") if "type" in building else -1)
		if type_val != BuildingResource.BuildingType.WALL and type_val != BuildingResource.BuildingType.DOOR:
			continue
		var d = global_position.distance_to(building.global_position)
		if d < best_dist:
			best_dist = d
			best = building

	return best

func _wolf_target_invalid(target: Node2D) -> bool:
	if not is_instance_valid(target):
		return true
	if target.is_in_group("villagers"):
		return bool(target.get("is_unconscious") if "is_unconscious" in target else false)
	return false

func _set_path_to_target(target: Node2D) -> void:
	var tilemap = _get_tilemap_layer()
	if not tilemap or not is_instance_valid(target):
		return

	var start_cell = tilemap.local_to_map(tilemap.to_local(global_position))
	var end_cell = tilemap.local_to_map(tilemap.to_local(target.global_position))
	if "grid_coord" in target:
		end_cell = target.grid_coord

	var id_path = tilemap.get_path_coords(start_cell, end_cell, true)
	if id_path.size() <= 1:
		path.clear()
		current_target_pos = target.global_position
		return

	var world_path: Array[Vector2] = []
	for coord in id_path:
		world_path.append(tilemap.to_global(tilemap.map_to_local(coord)))
	if world_path.size() > 1:
		world_path.remove_at(0)
	path = world_path
	current_target_pos = path.pop_front() if not path.is_empty() else target.global_position

func _wolf_attack(target: Node2D) -> void:
	if target.is_in_group("villagers"):
		if target.has_method("receive_wolf_attack"):
			target.receive_wolf_attack()
		if _wolf_target_invalid(target):
			attack_target = null
		return

	if target.is_in_group("buildings"):
		var type_val = int(target.get("type") if "type" in target else -1)
		if type_val != BuildingResource.BuildingType.WALL and type_val != BuildingResource.BuildingType.DOOR:
			attack_target = null
			return

		var key = str(target.get_instance_id())
		var hit_count = int(building_attack_counts.get(key, 0)) + 1
		if hit_count >= 3:
			building_attack_counts.erase(key)
			EventBus.alert_message.emit("狼破坏了一段墙或门！")
			if target.has_method("take_damage"):
				target.take_damage(999999.0)
			else:
				target.queue_free()
			attack_target = null
		else:
			building_attack_counts[key] = hit_count

func _is_blocked_cell(cell: Vector2i) -> bool:
	var tilemap = _get_tilemap_layer()
	if not tilemap:
		return false

	if "astar_grid" in tilemap:
		if not tilemap.astar_grid.is_in_boundsv(cell):
			return true
		if tilemap.astar_grid.is_point_solid(cell):
			return true

	if _has_door_at(cell):
		return true

	return false

func _has_door_at(cell: Vector2i) -> bool:
	for door in get_tree().get_nodes_in_group("doors"):
		if is_instance_valid(door) and "grid_coord" in door and door.grid_coord == cell:
			return true
	return false

func _get_tilemap_layer() -> Node:
	var parent = get_parent()
	if parent and parent.has_method("local_to_map") and parent.has_method("map_to_local") and parent.has_method("get_path_coords"):
		return parent

	var scene = get_tree().current_scene
	if scene:
		var tilemap_node = scene.get_node_or_null("TileMapLayer")
		if tilemap_node and tilemap_node.has_method("get_path_coords"):
			return tilemap_node
	return null

func take_damage(amount: float) -> void:
	health -= amount
	is_wounded = true
	
	# 触发受击信号
	EventBus.animal_hit.emit(species)

	var tween = create_tween().set_parallel(true)
	modulate = Color.RED
	scale = base_scale * 1.1
	tween.tween_property(self, "modulate", Color.WHITE, 0.2)
	tween.tween_property(self, "scale", base_scale, 0.2)

	if species != "wolf" and _set_random_path_target():
		is_idle = false

	if health <= 0:
		_on_death()

func _on_death() -> void:
	if species == "wolf":
		EventBus.animal_killed.emit(species)
		queue_free()
		return

	var parent = get_parent()
	if ITEM_DROP_SCENE and parent:
		var drop = ITEM_DROP_SCENE.instantiate()
		parent.add_child(drop)
		drop.global_position = global_position

		if "type" in drop:
			drop.type = 2
		if "amount" in drop:
			drop.amount = 2

		var nav = _get_tilemap_layer()
		if nav and "grid_coord" in drop:
			drop.grid_coord = nav.local_to_map(nav.to_local(global_position))

		EventBus.item_dropped.emit(drop, 2, 2)

	EventBus.animal_killed.emit(species)
	queue_free()
