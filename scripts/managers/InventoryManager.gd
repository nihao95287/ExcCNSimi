extends Node

signal resources_updated(wood: int, stone: int, meat: int, fiber: int)

var wood: int = 0
var stone: int = 0
var meat: int = 0
var fiber: int = 0
var tools: Dictionary = {
	"wood_axe": 0,
	"wood_pickaxe": 0,
	"stone_axe": 0,
	"stone_pickaxe": 0,
	"bow": 0,
	"arrow": 0,
	"fishing_rod": 0,
}

func _ready() -> void:
	EventBus.resource_collected.connect(_on_resource_collected)
	EventBus.resource_consumed.connect(_on_resource_consumed)
	EventBus.resource_destroyed.connect(_on_resource_destroyed)

func _on_resource_collected(resource_type: int, amount: int) -> void:
	add_resource(resource_type, amount)

func add_resource(resource_type: int, amount: int) -> void:
	match resource_type:
		0: wood  += amount
		1: stone += amount
		2: meat  += amount
		3: fiber += amount
	_emit_resources_updated()

func _on_resource_destroyed(resource_type: int) -> void:
	pass

func _on_resource_consumed(resource_type: int, amount: int) -> void:
	match resource_type:
		0: wood  = max(0, wood  - amount)
		1: stone = max(0, stone - amount)
		2: meat  = max(0, meat  - amount)
		3: fiber = max(0, fiber - amount)
	_emit_resources_updated()

func set_resources(w: int, s: int, m: int, f: int = 0) -> void:
	wood  = w
	stone = s
	meat  = m
	fiber = f
	_emit_resources_updated()

func add_tool(tool_id: String, amount: int = 1) -> void:
	tools[tool_id] = int(tools.get(tool_id, 0)) + amount

func get_tool_count(tool_id: String) -> int:
	return int(tools.get(tool_id, 0))

func _emit_resources_updated() -> void:
	resources_updated.emit(wood, stone, meat, fiber)
	EventBus.resources_updated.emit(wood, stone, meat, fiber)
