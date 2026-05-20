extends Node

signal stockpile_created
signal stockpile_updated
signal stockpile_full

var stockpile_cells: Array[Vector2i] = []
var _stockpile_ever_created: bool = false

func _ready() -> void:
	EventBus.item_stored.connect(_on_item_stored)

func is_stockpile_cell(cell: Vector2i) -> bool:
	return cell in stockpile_cells

func add_stockpile_cell(cell: Vector2i) -> void:
	if not cell in stockpile_cells:
		stockpile_cells.append(cell)
		if not _stockpile_ever_created:
			_stockpile_ever_created = true
			stockpile_created.emit()
			EventBus.stockpile_created.emit()
		stockpile_updated.emit()
		EventBus.stockpile_updated.emit()

func remove_stockpile_cell(cell: Vector2i) -> void:
	if cell in stockpile_cells:
		stockpile_cells.erase(cell)
		stockpile_updated.emit()
		EventBus.stockpile_updated.emit()

func get_empty_stockpile_cell(stockpile_items: Array[Node2D], reserved_cells: Array[Vector2i] = []) -> Vector2i:
	for cell in stockpile_cells:
		if cell in reserved_cells:
			continue
			
		var occupied = false
		for item in stockpile_items:
			var item_coord = item.grid_coord if "grid_coord" in item else Vector2i(-1, -1)
			if is_instance_valid(item) and item_coord == cell:
				occupied = true
				break
		if not occupied:
			return cell
	return Vector2i(-99999, -99999)

func _on_item_stored(_item_type: int, _amount: int) -> void:
	stockpile_updated.emit()
	EventBus.stockpile_updated.emit()

func get_stockpile_cells() -> Array[Vector2i]:
	return stockpile_cells

func get_stockpile_count() -> int:
	return stockpile_cells.size()
