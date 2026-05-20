extends Node

signal farms_updated

const CROP_NONE: String = ""
const CROP_FIBER: String = "fiber"
const CROP_FOOD: String = "food"
const MAX_DAILY_WORK: float = 20.0
const NEGLECT_PENALTY: float = 5.0

var plots: Array[Dictionary] = []
var next_plot_id: int = 1

func _ready() -> void:
	var time_mgr = get_node_or_null("/root/TimeManager")
	if time_mgr and not time_mgr.day_passed.is_connected(_on_day_passed):
		time_mgr.day_passed.connect(_on_day_passed)

func reset() -> void:
	plots.clear()
	next_plot_id = 1
	_emit_updated()

func create_plot(cells: Array[Vector2i]) -> int:
	var unique: Array[Vector2i] = []
	for cell in cells:
		if not cell in unique and get_plot_at_cell(cell).is_empty():
			unique.append(cell)
	if unique.is_empty():
		return -1

	var plot := {
		"id": next_plot_id,
		"cells": unique,
		"crop": CROP_NONE,
		"growth": 0.0,
		"worked_today": 0.0,
		"mature": false,
		"reserved_by": "",
		"reserved_cells": {},
		"cell_growth": {},
		"cell_worked_today": {},
		"cell_mature": {},
		"cell_harvested": {},
	}
	plots.append(plot)
	next_plot_id += 1
	_emit_updated()
	return int(plot["id"])

func get_plots() -> Array[Dictionary]:
	return plots

func get_plot_at_cell(cell: Vector2i) -> Dictionary:
	for plot in plots:
		var cells: Array = plot.get("cells", [])
		if cell in cells:
			return plot
	return {}

func get_plot_by_id(plot_id: int) -> Dictionary:
	for plot in plots:
		if int(plot.get("id", -1)) == plot_id:
			return plot
	return {}

func set_crop(plot_id: int, crop: String) -> bool:
	if crop != CROP_FIBER and crop != CROP_FOOD:
		return false
	var plot = get_plot_by_id(plot_id)
	if plot.is_empty():
		return false
	if str(plot.get("crop", CROP_NONE)) != CROP_NONE:
		return false
	plot["crop"] = crop
	plot["growth"] = 0.0
	plot["worked_today"] = 0.0
	plot["mature"] = false
	plot["reserved_by"] = ""
	plot["reserved_cells"] = {}
	var cell_growth: Dictionary = {}
	var cell_worked_today: Dictionary = {}
	var cell_mature: Dictionary = {}
	var cell_harvested: Dictionary = {}
	for cell in plot.get("cells", []):
		var key = _cell_key(cell)
		cell_growth[key] = 0.0
		cell_worked_today[key] = 0.0
		cell_mature[key] = false
		cell_harvested[key] = false
	plot["cell_growth"] = cell_growth
	plot["cell_worked_today"] = cell_worked_today
	plot["cell_mature"] = cell_mature
	plot["cell_harvested"] = cell_harvested
	_emit_updated()
	return true

func remove_plot(plot_id: int) -> void:
	for i in range(plots.size() - 1, -1, -1):
		if int(plots[i].get("id", -1)) == plot_id:
			plots.remove_at(i)
			_emit_updated()
			return

func remove_plot_at_cell(cell: Vector2i) -> void:
	var plot = get_plot_at_cell(cell)
	if not plot.is_empty():
		remove_plot(int(plot.get("id", -1)))

func find_best_work_plot(world_pos: Vector2, tilemap: Node) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INF
	for plot in plots:
		if str(plot.get("crop", CROP_NONE)) == CROP_NONE:
			continue
		var cell = get_best_work_cell(plot, world_pos, tilemap)
		if cell.x == -99999:
			continue
		var dist = world_pos.distance_to(tilemap.to_global(tilemap.map_to_local(cell)) if tilemap else Vector2(cell))
		if dist < best_dist:
			best_dist = dist
			best = plot
	return best

func get_best_work_cell(plot: Dictionary, world_pos: Vector2, tilemap: Node) -> Vector2i:
	var reserved: Dictionary = plot.get("reserved_cells", {})
	var best_cell := Vector2i(-99999, -99999)
	var best_dist := INF
	for cell in plot.get("cells", []):
		var key = _cell_key(cell)
		if str(reserved.get(key, "")) != "":
			continue
		if bool((plot.get("cell_harvested", {}) as Dictionary).get(key, false)):
			continue
		if not bool((plot.get("cell_mature", {}) as Dictionary).get(key, false)):
			if float((plot.get("cell_worked_today", {}) as Dictionary).get(key, 0.0)) >= MAX_DAILY_WORK:
				continue
		var pos = tilemap.to_global(tilemap.map_to_local(cell)) if tilemap else Vector2(cell)
		var dist = world_pos.distance_to(pos)
		if dist < best_dist:
			best_dist = dist
			best_cell = cell
	return best_cell

func reserve_plot(plot_id: int, villager_name: String, cell: Vector2i = Vector2i(-99999, -99999)) -> bool:
	var plot = get_plot_by_id(plot_id)
	if plot.is_empty():
		return false
	if cell.x == -99999:
		if str(plot.get("reserved_by", "")) != "":
			return false
		plot["reserved_by"] = villager_name
		return true
	var reserved: Dictionary = plot.get("reserved_cells", {})
	var key = _cell_key(cell)
	if str(reserved.get(key, "")) != "":
		return false
	reserved[key] = villager_name
	plot["reserved_cells"] = reserved
	return true

func release_plot(plot_id: int, villager_name: String = "", cell: Vector2i = Vector2i(-99999, -99999)) -> void:
	var plot = get_plot_by_id(plot_id)
	if plot.is_empty():
		return
	if cell.x != -99999:
		var reserved: Dictionary = plot.get("reserved_cells", {})
		var key = _cell_key(cell)
		var owner = str(reserved.get(key, ""))
		if villager_name == "" or owner == villager_name:
			reserved.erase(key)
			plot["reserved_cells"] = reserved
		return
	var current = str(plot.get("reserved_by", ""))
	if villager_name == "" or current == villager_name:
		plot["reserved_by"] = ""

func get_plot_center(plot: Dictionary, tilemap: Node) -> Vector2:
	var cells: Array = plot.get("cells", [])
	if cells.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for cell in cells:
		if tilemap:
			total += tilemap.to_global(tilemap.map_to_local(cell))
		else:
			total += Vector2(cell)
	return total / float(cells.size())

func get_stage(plot: Dictionary, cell: Vector2i = Vector2i(-99999, -99999)) -> int:
	if str(plot.get("crop", CROP_NONE)) == CROP_NONE:
		return 0
	if cell.x != -99999:
		var key = _cell_key(cell)
		if bool((plot.get("cell_harvested", {}) as Dictionary).get(key, false)):
			return 0
	var growth := get_cell_growth(plot, cell) if cell.x != -99999 else float(plot.get("growth", 0.0))
	if growth < 34.0:
		return 1
	if growth < 67.0:
		return 2
	return 3

func get_cell_growth(plot: Dictionary, cell: Vector2i) -> float:
	var key = _cell_key(cell)
	return float((plot.get("cell_growth", {}) as Dictionary).get(key, float(plot.get("growth", 0.0))))

func work_plot(plot_id: int, cell: Vector2i = Vector2i(-99999, -99999)) -> Dictionary:
	var plot = get_plot_by_id(plot_id)
	if plot.is_empty():
		return {}
	if str(plot.get("crop", CROP_NONE)) == CROP_NONE:
		return {}

	var key = _cell_key(cell)
	var cell_growth: Dictionary = plot.get("cell_growth", {})
	var cell_worked_today: Dictionary = plot.get("cell_worked_today", {})
	var cell_mature: Dictionary = plot.get("cell_mature", {})
	var cell_harvested: Dictionary = plot.get("cell_harvested", {})
	if bool(cell_harvested.get(key, false)):
		return {}
	if bool(cell_mature.get(key, false)):
		return _harvest_cell(plot, cell)

	var worked_today := float(cell_worked_today.get(key, 0.0))
	if worked_today >= MAX_DAILY_WORK:
		return {"changed": false, "harvested": false}

	var gain = min(MAX_DAILY_WORK - worked_today, MAX_DAILY_WORK)
	cell_worked_today[key] = worked_today + gain
	cell_growth[key] = min(100.0, float(cell_growth.get(key, 0.0)) + gain)
	if float(cell_growth[key]) >= 100.0:
		cell_mature[key] = true
	plot["cell_growth"] = cell_growth
	plot["cell_worked_today"] = cell_worked_today
	plot["cell_mature"] = cell_mature
	plot["growth"] = _average_cell_growth(plot)
	plot["worked_today"] = _average_cell_worked_today(plot)
	plot["mature"] = _all_cells_mature_or_harvested(plot)
	_emit_updated()
	return {"changed": true, "harvested": false}

func _harvest_cell(plot: Dictionary, cell: Vector2i) -> Dictionary:
	var crop := str(plot.get("crop", CROP_NONE))
	var amount = 1
	var resource_type = 3 if crop == CROP_FIBER else 2
	EventBus.resource_collected.emit(resource_type, amount)

	var key = _cell_key(cell)
	var cell_growth: Dictionary = plot.get("cell_growth", {})
	var cell_worked_today: Dictionary = plot.get("cell_worked_today", {})
	var cell_mature: Dictionary = plot.get("cell_mature", {})
	var cell_harvested: Dictionary = plot.get("cell_harvested", {})
	cell_growth[key] = 0.0
	cell_worked_today[key] = 0.0
	cell_mature[key] = false
	cell_harvested[key] = true
	plot["cell_growth"] = cell_growth
	plot["cell_worked_today"] = cell_worked_today
	plot["cell_mature"] = cell_mature
	plot["cell_harvested"] = cell_harvested
	if _all_cells_harvested(plot):
		plot["crop"] = CROP_NONE
		plot["growth"] = 0.0
		plot["worked_today"] = 0.0
		plot["mature"] = false
		plot["reserved_by"] = ""
		plot["reserved_cells"] = {}
		plot["cell_growth"] = {}
		plot["cell_worked_today"] = {}
		plot["cell_mature"] = {}
		plot["cell_harvested"] = {}
	else:
		plot["growth"] = _average_cell_growth(plot)
		plot["worked_today"] = _average_cell_worked_today(plot)
		plot["mature"] = _all_cells_mature_or_harvested(plot)
	_emit_updated()
	return {"changed": true, "harvested": true, "crop": crop, "amount": amount}

func _on_day_passed(_day: int) -> void:
	var changed := false
	for plot in plots:
		if str(plot.get("crop", CROP_NONE)) == CROP_NONE:
			continue
		var cell_growth: Dictionary = plot.get("cell_growth", {})
		var cell_worked_today: Dictionary = plot.get("cell_worked_today", {})
		var cell_mature: Dictionary = plot.get("cell_mature", {})
		var cell_harvested: Dictionary = plot.get("cell_harvested", {})
		for cell in plot.get("cells", []):
			var key = _cell_key(cell)
			if bool(cell_harvested.get(key, false)):
				continue
			if float(cell_worked_today.get(key, 0.0)) <= 0.0 and not bool(cell_mature.get(key, false)):
				cell_growth[key] = max(0.0, float(cell_growth.get(key, 0.0)) - NEGLECT_PENALTY)
				changed = true
			if float(cell_worked_today.get(key, 0.0)) != 0.0:
				changed = true
			cell_worked_today[key] = 0.0
		plot["cell_growth"] = cell_growth
		plot["cell_worked_today"] = cell_worked_today
		plot["growth"] = _average_cell_growth(plot)
		plot["worked_today"] = 0.0
	if changed:
		_emit_updated()

func serialize() -> Dictionary:
	var arr: Array = []
	for plot in plots:
		var cells_arr: Array = []
		for cell in plot.get("cells", []):
			cells_arr.append({"x": cell.x, "y": cell.y})
		arr.append({
			"id": int(plot.get("id", -1)),
			"cells": cells_arr,
			"crop": str(plot.get("crop", CROP_NONE)),
			"growth": float(plot.get("growth", 0.0)),
			"worked_today": float(plot.get("worked_today", 0.0)),
			"mature": bool(plot.get("mature", false)),
			"reserved_by": "",
			"reserved_cells": {},
			"cell_growth": plot.get("cell_growth", {}),
			"cell_worked_today": plot.get("cell_worked_today", {}),
			"cell_mature": plot.get("cell_mature", {}),
			"cell_harvested": plot.get("cell_harvested", {}),
		})
	return {"next_plot_id": next_plot_id, "plots": arr}

func restore(data: Dictionary) -> void:
	plots.clear()
	next_plot_id = int(data.get("next_plot_id", 1))
	for pd in data.get("plots", []):
		var cells: Array[Vector2i] = []
		for cd in pd.get("cells", []):
			cells.append(Vector2i(int(cd.get("x", 0)), int(cd.get("y", 0))))
		var id = int(pd.get("id", next_plot_id))
		var restored_plot = {
			"id": id,
			"cells": cells,
			"crop": str(pd.get("crop", CROP_NONE)),
			"growth": float(pd.get("growth", 0.0)),
			"worked_today": float(pd.get("worked_today", 0.0)),
			"mature": bool(pd.get("mature", false)),
			"reserved_by": "",
			"reserved_cells": {},
			"cell_growth": pd.get("cell_growth", {}),
			"cell_worked_today": pd.get("cell_worked_today", {}),
			"cell_mature": pd.get("cell_mature", {}),
			"cell_harvested": pd.get("cell_harvested", {}),
		}
		_backfill_cell_state(restored_plot)
		plots.append(restored_plot)
		next_plot_id = max(next_plot_id, id + 1)
	_emit_updated()

func _emit_updated() -> void:
	farms_updated.emit()
	EventBus.farm_updated.emit()

func _backfill_cell_state(plot: Dictionary) -> void:
	if str(plot.get("crop", CROP_NONE)) == CROP_NONE:
		return
	var cell_growth: Dictionary = plot.get("cell_growth", {})
	var cell_worked_today: Dictionary = plot.get("cell_worked_today", {})
	var cell_mature: Dictionary = plot.get("cell_mature", {})
	var cell_harvested: Dictionary = plot.get("cell_harvested", {})
	for cell in plot.get("cells", []):
		var key = _cell_key(cell)
		if not cell_growth.has(key):
			cell_growth[key] = float(plot.get("growth", 0.0))
		if not cell_worked_today.has(key):
			cell_worked_today[key] = 0.0
		if not cell_mature.has(key):
			cell_mature[key] = bool(plot.get("mature", false))
		if not cell_harvested.has(key):
			cell_harvested[key] = false
	plot["cell_growth"] = cell_growth
	plot["cell_worked_today"] = cell_worked_today
	plot["cell_mature"] = cell_mature
	plot["cell_harvested"] = cell_harvested

func _average_cell_growth(plot: Dictionary) -> float:
	var total := 0.0
	var count := 0
	var cell_growth: Dictionary = plot.get("cell_growth", {})
	var cell_harvested: Dictionary = plot.get("cell_harvested", {})
	for cell in plot.get("cells", []):
		var key = _cell_key(cell)
		if bool(cell_harvested.get(key, false)):
			continue
		total += float(cell_growth.get(key, 0.0))
		count += 1
	return total / float(max(1, count))

func _average_cell_worked_today(plot: Dictionary) -> float:
	var total := 0.0
	var count := 0
	var cell_worked_today: Dictionary = plot.get("cell_worked_today", {})
	var cell_harvested: Dictionary = plot.get("cell_harvested", {})
	for cell in plot.get("cells", []):
		var key = _cell_key(cell)
		if bool(cell_harvested.get(key, false)):
			continue
		total += float(cell_worked_today.get(key, 0.0))
		count += 1
	return total / float(max(1, count))

func _all_cells_mature_or_harvested(plot: Dictionary) -> bool:
	var cell_mature: Dictionary = plot.get("cell_mature", {})
	var cell_harvested: Dictionary = plot.get("cell_harvested", {})
	for cell in plot.get("cells", []):
		var key = _cell_key(cell)
		if not bool(cell_harvested.get(key, false)) and not bool(cell_mature.get(key, false)):
			return false
	return true

func _all_cells_harvested(plot: Dictionary) -> bool:
	var cell_harvested: Dictionary = plot.get("cell_harvested", {})
	for cell in plot.get("cells", []):
		if not bool(cell_harvested.get(_cell_key(cell), false)):
			return false
	return true

func _cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]
