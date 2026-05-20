extends Resource
class_name BuildingResource

enum BuildingType { WALL, DOOR, OTHER }

@export var name: String = "Building"
@export var icon: Texture2D
@export var scene: PackedScene
@export var cost: Dictionary = {"wood": 10}
@export var type: BuildingType = BuildingType.WALL
@export var max_health: float = 100.0
@export var blocks_arrows: bool = true
@export var visual_size: float = 16.0
@export var is_farm_area: bool = false
@export var is_bed: bool = false
@export var is_workbench: bool = false
@export var provides_light: bool = false
@export var light_radius: float = 1.0
@export var light_energy_day: float = 0.2
@export var light_energy_night: float = 1.0
