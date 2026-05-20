extends Node

signal item_dropped
signal haul_job_available(villager: Node2D)

var unhauled_items: Array[Node2D] = []
var stockpile_items: Array[Node2D] = []

const SCR_ITEM_DROP = preload("res://scripts/entities/ItemDrop.gd")

func _ready() -> void:
	EventBus.item_dropped.connect(_on_item_dropped)
	EventBus.stockpile_updated.connect(_on_stockpile_updated)

func register_item(item: Node2D) -> void:
	var g_coord = item.grid_coord if "grid_coord" in item else Vector2i(-1, -1)
	var item_id = item.item_id if "item_id" in item else ""

	var stockpile_manager = _get_stockpile_manager()
	var is_stockpile = stockpile_manager.is_stockpile_cell(g_coord) if stockpile_manager else false

	# 工具/制作物品即使落在仓库区域内也要搬运到正确的格子
	if is_stockpile and item_id == "":
		if not item in stockpile_items:
			stockpile_items.append(item)
	else:
		if not item in unhauled_items:
			unhauled_items.append(item)
			item_dropped.emit()

func unregister_item(item: Node2D) -> void:
	if item in unhauled_items:
		unhauled_items.erase(item)
	if item in stockpile_items:
		stockpile_items.erase(item)

func store_item(item: Node2D, cell: Vector2i) -> void:
	if item in unhauled_items:
		unhauled_items.erase(item)
	item.set("grid_coord", cell)

	if not item in stockpile_items:
		stockpile_items.append(item)

	var item_type = item.type if "type" in item else 0
	var item_amount = item.amount if "amount" in item else 1
	EventBus.item_stored.emit(item_type, item_amount)
	EventBus.resource_collected.emit(item_type, item_amount)

func _on_item_dropped(item: Node2D, item_type: int, amount: int) -> void:
	pass

func _on_stockpile_updated() -> void:
	pass

func get_unhauled_items() -> Array[Node2D]:
	return unhauled_items

func get_stockpile_items() -> Array[Node2D]:
	return stockpile_items

func get_empty_stockpile_cell() -> Vector2i:
	var reserved_cells: Array[Vector2i] = []
	for v in get_tree().get_nodes_in_group("villagers"):
		if v.current_task == Villager.Task.HAUL:
			reserved_cells.append(v.haul_target_cell)
	
	var stockpile_manager = _get_stockpile_manager()
	if stockpile_manager:
		return stockpile_manager.get_empty_stockpile_cell(stockpile_items, reserved_cells)
	return Vector2i(-99999, -99999)

func is_stockpile_cell(cell: Vector2i) -> bool:
	var stockpile_manager = _get_stockpile_manager()
	return stockpile_manager.is_stockpile_cell(cell) if stockpile_manager else false

func add_stockpile_cell(cell: Vector2i) -> void:
	var stockpile_manager = _get_stockpile_manager()
	if stockpile_manager:
		stockpile_manager.add_stockpile_cell(cell)

	var to_store = []
	for item in unhauled_items:
		var item_coord = item.grid_coord if "grid_coord" in item else Vector2i(-1, -1)
		if is_instance_valid(item) and item_coord == cell:
			to_store.append(item)

	for item in to_store:
		store_item(item, cell)

func remove_stockpile_cell(cell: Vector2i) -> void:
	var stockpile_manager = _get_stockpile_manager()
	if stockpile_manager and stockpile_manager.has_method("remove_stockpile_cell"):
		stockpile_manager.remove_stockpile_cell(cell)
	eject_stockpile_cell(cell)

func eject_stockpile_cell(cell: Vector2i) -> void:
	var moved := false
	for item in stockpile_items.duplicate():
		if not is_instance_valid(item):
			stockpile_items.erase(item)
			continue
		var item_coord = item.grid_coord if "grid_coord" in item else Vector2i(-1, -1)
		if item_coord == cell:
			stockpile_items.erase(item)
			if not item in unhauled_items:
				unhauled_items.append(item)
			if "is_reserved" in item:
				item.set("is_reserved", false)
			moved = true
	if moved:
		item_dropped.emit()
		EventBus.stockpile_updated.emit()

func find_best_haul_job(villager_pos: Vector2) -> Node2D:
	var best_item = null
	var min_dist = 999999.0
	for item in unhauled_items:
		if is_instance_valid(item) and not (item.is_reserved if "is_reserved" in item else false):
			var d = villager_pos.distance_to(item.global_position)
			if d < min_dist:
				min_dist = d
				best_item = item
	return best_item

func _get_stockpile_manager() -> Node:
	return get_node_or_null("/root/StockpileManager")
