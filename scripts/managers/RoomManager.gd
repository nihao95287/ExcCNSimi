extends Node

signal rooms_updated

const MAX_ROOM_SIZE: int = 400

var rooms: Array[Dictionary] = []
var next_room_id: int = 1

func _ready() -> void:
	if not EventBus.building_placed.is_connected(_on_building_placed):
		EventBus.building_placed.connect(_on_building_placed)
	if not EventBus.building_demolished.is_connected(_on_building_demolished):
		EventBus.building_demolished.connect(_on_building_demolished)

func _on_building_placed(_coord: Vector2i, _type: int) -> void:
	rebuild_rooms()

func _on_building_demolished(_coord: Vector2i, _type: int) -> void:
	rebuild_rooms()

func reset() -> void:
	rooms.clear()
	next_room_id = 1
	rooms_updated.emit()

func rebuild_rooms() -> void:
	var tilemap = _get_tilemap()
	if not tilemap or not tilemap.astar_grid:
		return

	# 保存旧的 owner 和 name 映射（用 cells_key 对应）
	var old_owners: Dictionary = {}
	var old_names: Dictionary = {}
	for room in rooms:
		var key = _cells_key(room.get("cells", []))
		if key == "":
			continue
		var owner = str(room.get("owner", ""))
		if owner != "":
			old_owners[key] = owner
		var rname = str(room.get("name", ""))
		if rname != "":
			old_names[key] = rname

	rooms.clear()
	next_room_id = 1

	var boundary: Dictionary = _get_boundary_cells()
	var door_coords: Dictionary = _get_door_cells()

	var seeds: Array[Vector2i] = []
	for c in boundary.keys():
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = c + d
			if _is_in_bounds(tilemap, n) and not boundary.has(n):
				seeds.append(n)

	var visited_global: Dictionary = {}
	var seen_room_keys: Dictionary = {}
	for seed in seeds:
		if visited_global.has(seed):
			continue
		var result = _flood_room(tilemap, seed, boundary, visited_global)
		if not bool(result.get("enclosed", false)):
			continue
		var cells: Array = result.get("cells", [])
		if cells.is_empty():
			continue

		# 检查：房间必须包含至少一个合法门
		if not _room_has_valid_door(cells, boundary, door_coords):
			continue

		var key = _cells_key(cells)
		if seen_room_keys.has(key):
			continue
		seen_room_keys[key] = true

		var owner = str(old_owners.get(key, ""))
		var rname = str(old_names.get(key, ""))
		if rname == "":
			rname = "房间 %d" % next_room_id
		rooms.append({
			"id": next_room_id,
			"cells": cells,
			"owner": owner,
			"name": rname,
		})
		next_room_id += 1

	_update_bed_claims()
	rooms_updated.emit()

## 检查一个封闭区域是否含有至少一个合法门
## 合法门：门格子的左右两侧邻格都是墙/边界（横向门洞），
##         或上下两侧邻格都是墙/边界（纵向门洞）
func _room_has_valid_door(cells: Array, boundary: Dictionary, door_coords: Dictionary) -> bool:
	var cell_set: Dictionary = {}
	for c in cells:
		cell_set[c] = true

	# 找到与该房间相邻的门格
	for door_coord in door_coords.keys():
		# 先检查这个门格是否紧邻房间（上下左右至少一个格属于 cells）
		var adjacent_to_room = false
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if cell_set.has(door_coord + d):
				adjacent_to_room = true
				break
		if not adjacent_to_room:
			continue

		# 检查门是否合法：两侧相对方向都是墙/边界
		var left = door_coord + Vector2i.LEFT
		var right = door_coord + Vector2i.RIGHT
		var up = door_coord + Vector2i.UP
		var down = door_coord + Vector2i.DOWN

		var left_wall = boundary.has(left)
		var right_wall = boundary.has(right)
		var up_wall = boundary.has(up)
		var down_wall = boundary.has(down)

		# 横向门洞：左右都是墙，且上下不同时是墙（排除拐角）
		if left_wall and right_wall and not (up_wall and down_wall):
			return true
		# 纵向门洞：上下都是墙，且左右不同时是墙（排除拐角）
		if up_wall and down_wall and not (left_wall and right_wall):
			return true

	return false

func assign_room(room_id: int, owner_name: String) -> void:
	for room in rooms:
		if int(room.get("id", -1)) == room_id:
			room["owner"] = owner_name
		elif owner_name != "" and str(room.get("owner", "")) == owner_name:
			room["owner"] = ""
	_update_bed_claims()
	rooms_updated.emit()

func rename_room(room_id: int, new_name: String) -> void:
	for room in rooms:
		if int(room.get("id", -1)) == room_id:
			room["name"] = new_name.strip_edges()
			break
	rooms_updated.emit()

func clear_owner(owner_name: String) -> void:
	for room in rooms:
		if str(room.get("owner", "")) == owner_name:
			room["owner"] = ""
	_update_bed_claims()
	rooms_updated.emit()

func get_rooms() -> Array[Dictionary]:
	return rooms

func get_room_for_owner(owner_name: String) -> Dictionary:
	for room in rooms:
		if str(room.get("owner", "")) == owner_name:
			return room
	return {}

func has_room(owner_name: String) -> bool:
	return not get_room_for_owner(owner_name).is_empty()

func has_bed_for(owner_name: String) -> bool:
	for bed in get_tree().get_nodes_in_group("beds"):
		if not is_instance_valid(bed):
			continue
		if str(bed.get("owner_name") if "owner_name" in bed else "") == owner_name:
			return true
	return false

func can_use_bed(bed: Node, villager_name: String) -> bool:
	if not is_instance_valid(bed):
		return false
	var owner = str(bed.get("owner_name") if "owner_name" in bed else "")
	return owner == "" or owner == villager_name

## 根据世界格坐标查找所属房间，返回房间字典（未找到则返回空 {}）
func get_room_at_coord(coord: Vector2i) -> Dictionary:
	for room in rooms:
		for c in room.get("cells", []):
			if c == coord:
				return room
	return {}

func serialize() -> Array:
	var data: Array = []
	for room in rooms:
		var cells_arr: Array = []
		for c in room.get("cells", []):
			cells_arr.append({"x": c.x, "y": c.y})
		data.append({
			"id": int(room.get("id", 0)),
			"owner": str(room.get("owner", "")),
			"name": str(room.get("name", "")),
			"cells": cells_arr,
		})
	return data

func restore(saved_rooms: Array) -> void:
	rebuild_rooms()
	for saved in saved_rooms:
		var saved_cells: Array = []
		for cd in saved.get("cells", []):
			saved_cells.append(Vector2i(int(cd.get("x", 0)), int(cd.get("y", 0))))
		var key = _cells_key(saved_cells)
		for room in rooms:
			if _cells_key(room.get("cells", [])) == key:
				room["owner"] = str(saved.get("owner", ""))
				var sname = str(saved.get("name", ""))
				if sname != "":
					room["name"] = sname
				break
	_update_bed_claims()
	rooms_updated.emit()

func _flood_room(tilemap: TileMapLayer, start: Vector2i, boundary: Dictionary, visited_global: Dictionary) -> Dictionary:
	var stack: Array[Vector2i] = [start]
	var visited: Dictionary = {}
	var cells: Array[Vector2i] = []
	var enclosed = true

	while not stack.is_empty():
		var current: Vector2i = stack.pop_back()
		if visited.has(current) or boundary.has(current):
			continue
		visited[current] = true
		visited_global[current] = true
		cells.append(current)

		if cells.size() > MAX_ROOM_SIZE:
			enclosed = false
			break

		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = current + d
			if boundary.has(n):
				continue
			if not _is_in_bounds(tilemap, n):
				enclosed = false
				break
			if not visited.has(n):
				stack.append(n)
		if not enclosed:
			break

	return {"enclosed": enclosed, "cells": cells}

func _get_boundary_cells() -> Dictionary:
	var boundary: Dictionary = {}
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		var type_val = int(b.get("type") if "type" in b else -1)
		if type_val != BuildingResource.BuildingType.WALL and type_val != BuildingResource.BuildingType.DOOR:
			continue
		var gc: Vector2i = b.get("grid_coord") if "grid_coord" in b else Vector2i(-99999, -99999)
		boundary[gc] = true
	return boundary

## 获取所有门格坐标（用于合法门检测）
func _get_door_cells() -> Dictionary:
	var door_coords: Dictionary = {}
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		var type_val = int(b.get("type") if "type" in b else -1)
		if type_val != BuildingResource.BuildingType.DOOR:
			continue
		var gc: Vector2i = b.get("grid_coord") if "grid_coord" in b else Vector2i(-99999, -99999)
		door_coords[gc] = true
	return door_coords

func _update_bed_claims() -> void:
	for bed in get_tree().get_nodes_in_group("beds"):
		if not is_instance_valid(bed):
			continue
		if "room_id" in bed:
			bed.room_id = -1
		if "owner_name" in bed:
			bed.owner_name = ""

	for room in rooms:
		var id = int(room.get("id", -1))
		var owner = str(room.get("owner", ""))
		var cell_lookup: Dictionary = {}
		for c in room.get("cells", []):
			cell_lookup[c] = true
		for bed in get_tree().get_nodes_in_group("beds"):
			if not is_instance_valid(bed):
				continue
			var gc: Vector2i = bed.get("grid_coord") if "grid_coord" in bed else Vector2i(-99999, -99999)
			if cell_lookup.has(gc):
				if "room_id" in bed:
					bed.room_id = id
				if owner != "" and "owner_name" in bed:
					bed.owner_name = owner

func _cells_key(cells: Array) -> String:
	var parts: Array[String] = []
	for c in cells:
		parts.append("%d,%d" % [c.x, c.y])
	parts.sort()
	return "|".join(parts)

func _is_in_bounds(tilemap: TileMapLayer, coord: Vector2i) -> bool:
	return tilemap.astar_grid.is_in_boundsv(coord)

func _get_tilemap() -> TileMapLayer:
	var scene = get_tree().current_scene
	if scene:
		var tilemap = scene.find_child("TileMapLayer", true, false)
		if tilemap is TileMapLayer:
			return tilemap
	return null
