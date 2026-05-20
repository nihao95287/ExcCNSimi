extends Node

const WOLF_TEXTURE_PATH := "res://art/animals/howl.png"

var next_attack_day: int = 0

func _ready() -> void:
	randomize()
	var time_mgr = get_node_or_null("/root/TimeManager")
	if time_mgr:
		if not time_mgr.day_passed.is_connected(_on_day_passed):
			time_mgr.day_passed.connect(_on_day_passed)
		if next_attack_day <= 0:
			next_attack_day = time_mgr.current_day + randi_range(5, 7)

func reset() -> void:
	var time_mgr = get_node_or_null("/root/TimeManager")
	var current_day = time_mgr.current_day if time_mgr else 1
	next_attack_day = current_day + randi_range(5, 7)

func serialize() -> Dictionary:
	return {"next_attack_day": next_attack_day}

func restore(data: Dictionary) -> void:
	next_attack_day = int(data.get("next_attack_day", 0))
	if next_attack_day <= 0:
		reset()

func _on_day_passed(day: int) -> void:
	if next_attack_day <= 0:
		next_attack_day = day + randi_range(5, 7)
	if day >= next_attack_day:
		spawn_wolf()
		next_attack_day = day + randi_range(5, 7)

func spawn_wolf() -> void:
	var tilemap = _get_tilemap()
	if not tilemap:
		return

	var spawn_cell = _find_spawn_cell(tilemap)
	if spawn_cell == Vector2i(-99999, -99999):
		return

	var wolf = CharacterBody2D.new()
	var script = load("res://scripts/entities/Animal.gd")
	if script:
		wolf.set_script(script)
	wolf.name = "Wolf"
	wolf.add_to_group("animals")
	if "species" in wolf:
		wolf.species = "wolf"
	if "health" in wolf:
		wolf.health = 5

	var sprite = Sprite2D.new()
	if FileAccess.file_exists(WOLF_TEXTURE_PATH) or FileAccess.file_exists(WOLF_TEXTURE_PATH + ".import"):
		sprite.texture = load(WOLF_TEXTURE_PATH)
	else:
		sprite.texture = load("res://icon.svg")
	wolf.add_child(sprite)

	tilemap.add_child(wolf)
	wolf.global_position = tilemap.to_global(tilemap.map_to_local(spawn_cell))
	EventBus.alert_message.emit("狼群靠近了村庄！")

func _find_spawn_cell(tilemap: TileMapLayer) -> Vector2i:
	if not tilemap.astar_grid:
		return Vector2i(-99999, -99999)

	var region = tilemap.astar_grid.region
	for _i in range(80):
		var side = randi_range(0, 3)
		var x = randi_range(region.position.x, region.position.x + region.size.x - 1)
		var y = randi_range(region.position.y, region.position.y + region.size.y - 1)
		if side == 0:
			x = region.position.x
		elif side == 1:
			x = region.position.x + region.size.x - 1
		elif side == 2:
			y = region.position.y
		else:
			y = region.position.y + region.size.y - 1
		var cell = Vector2i(x, y)
		if tilemap.astar_grid.is_in_boundsv(cell) and not tilemap.astar_grid.is_point_solid(cell):
			return cell
	return Vector2i(-99999, -99999)

func _get_tilemap() -> TileMapLayer:
	var scene = get_tree().current_scene
	if scene:
		var tilemap = scene.find_child("TileMapLayer", true, false)
		if tilemap is TileMapLayer:
			return tilemap
	return null
