extends Node

signal resource_collected(resource_type: int, amount: int)
signal resource_hit(resource_type: int)
signal resource_consumed(resource_type: int, amount: int)
signal resource_destroyed(resource_type: int)
signal resource_node_removed(type: int, grid_x: int, grid_y: int)
signal item_stored(item_type: int, amount: int)
signal resources_updated(wood: int, stone: int, meat: int, fiber: int)
signal item_dropped(item: Node2D, item_type: int, amount: int)
signal item_registered(item: Node2D)
signal item_unregistered(item: Node2D)
signal villager_idle(villager: Node2D)
signal villager_task_assigned(villager: Node2D, task_type: String, target: Node2D)
signal villager_task_completed(villager: Node2D)
signal stockpile_created
signal stockpile_updated
signal farm_build_requested(data: BuildingResource)
signal farm_updated
signal season_changed(season: int)
signal day_changed(day: int)
signal night_started()
signal day_started()
signal alert_message(message: String)
signal animal_killed(species: String)
signal animal_hit(species: String)
signal map_generated(map_type: int)

# --- 音频系统信号 ---
signal play_sfx(sfx_name: String)
signal play_bgm(bgm_name: String, fade_duration: float)
signal stop_bgm(fade_duration: float)
signal play_ambient(ambient_name: String)
signal stop_ambient(ambient_name: String)
signal volume_changed(bus_name: String, volume: float)

# --- 建筑相关信号 ---
signal toggle_build_menu()
signal build_requested(data: BuildingResource)
signal building_placed(coord: Vector2i, type: int)
signal building_demolished(coord: Vector2i, type: int)
