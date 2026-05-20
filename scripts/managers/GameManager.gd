extends Node

signal resources_updated(wood: int, stone: int, meat: int, fiber: int)
signal alert_message(message: String)
signal item_dropped
signal item_stored
signal stockpile_created

func _ready() -> void:
	_connect_manager_signals()

func _connect_manager_signals() -> void:
	var inventory = get_node_or_null("/root/InventoryManager")
	if inventory:
		inventory.resources_updated.connect(_on_resources_updated.bind())

	var stockpile = get_node_or_null("/root/StockpileManager")
	if stockpile:
		stockpile.stockpile_created.connect(_on_stockpile_created.bind())

	var haul = get_node_or_null("/root/HaulManager")
	if haul:
		haul.item_dropped.connect(_on_item_dropped_internal.bind())

func spawn_dropped_item(pos: Vector2, type_idx: int, count: int) -> void:
	var tilemap = get_tree().current_scene.find_child("TileMapLayer", true, false)

	for i in range(count):
		var drop = Node2D.new()
		drop.set_script(preload("res://scripts/entities/ItemDrop.gd"))
		drop.set("type", type_idx)
		drop.set("amount", 1)

		var offset = Vector2(randf_range(-20, 20), randf_range(-20, 20))
		drop.global_position = pos + offset

		if tilemap and tilemap.has_method("local_to_map"):
			var g_coord = tilemap.local_to_map(drop.global_position)
			drop.set("grid_coord", g_coord)

		get_tree().current_scene.add_child(drop)

	item_dropped.emit()

func register_item(item: Node2D) -> void:
	var haul = get_node_or_null("/root/HaulManager")
	if haul:
		haul.register_item(item)

func unregister_item(item: Node2D) -> void:
	var haul = get_node_or_null("/root/HaulManager")
	if haul:
		haul.unregister_item(item)

func store_item(item: Node2D, cell: Vector2i) -> void:
	var haul = get_node_or_null("/root/HaulManager")
	if haul:
		haul.store_item(item, cell)
	item_stored.emit()

func add_stockpile_cell(cell: Vector2i) -> void:
	var haul = get_node_or_null("/root/HaulManager")
	if haul:
		haul.add_stockpile_cell(cell)

func is_stockpile_cell(cell: Vector2i) -> bool:
	var haul = get_node_or_null("/root/HaulManager")
	return haul.is_stockpile_cell(cell) if haul else false

func get_empty_stockpile_cell() -> Vector2i:
	var haul = get_node_or_null("/root/HaulManager")
	return haul.get_empty_stockpile_cell() if haul else Vector2i(-99999, -99999)

func get_unhauled_items() -> Array[Node2D]:
	var haul = get_node_or_null("/root/HaulManager")
	return haul.get_unhauled_items() if haul else []

func show_alert(msg: String) -> void:
	alert_message.emit(msg)

func _on_resources_updated(w: int, s: int, m: int, f: int) -> void:
	resources_updated.emit(w, s, m, f)

func _on_item_dropped_internal() -> void:
	item_dropped.emit()

func _on_stockpile_created() -> void:
	stockpile_created.emit()
