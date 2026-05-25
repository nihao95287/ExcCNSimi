class_name Villager
extends CharacterBody2D

@export var move_speed: float = 200.0
@export var gather_speed: float = 1.0

var DEBUG_VILLAGER_LOGS: bool:
	get: return SettingsManager.settings.get("debug_logs", false)

const REACH_THRESHOLD: float = 8.0
const STUCK_REPATH_TIME: float = 0.8
const STUCK_MIN_PROGRESS: float = 1.0
const BODY_COLLISION_SIZE: Vector2 = Vector2(10, 10)
const GATHER_RANGE: float = 32.0
const EAT_RANGE: float = 32.0
const ATTACK_RANGE: float = 34.0
const BOW_ATTACK_RANGE: float = 140.0
const ARROW_FLIGHT_SPEED: float = 360.0
const ATTACK_CHASE_SPEED_MULTIPLIER: float = 0.65
const UNARMED_ATTACK_DAMAGE: float = 0.35
const WOOD_SWORD_ATTACK_DAMAGE: float = 0.65
const STONE_SWORD_ATTACK_DAMAGE: float = 0.9
const BOW_ATTACK_DAMAGE: float = 0.75
const SLEEP_RANGE: float = 18.0
const FARM_WORK_RANGE: float = 24.0
const CRAFT_STOP_RANGE: float = 24.0
const CRAFT_WORK_RANGE: float = 36.0
const FARM_WORK_MINUTES_PER_CELL: float = 10.0
const HUNGER_DRAIN_HOURS: float = 24.0
const ENERGY_DRAIN_HOURS: float = 24.0
const ENERGY_RECOVER_HOURS: float = 8.0
const SLEEP_THRESHOLD: float = 20.0
const MOOD_PENALTY_HOURS: float = 24.0
const ROOM_BED_MOOD_PENALTY_HOURS: float = 6.0
const INJURED_MOOD_PENALTY_HOURS: float = 0.35
const INJURED_MOOD_PENALTY_CAP: float = 45.0
const UNCONSCIOUS_RECOVER_HOURS: float = 3.0
const BANDAGE_HEAL_AMOUNT: float = 45.0
const BANDAGE_USE_HEALTH_RATIO: float = 0.65
const STRIKE_MOOD_THRESHOLD: int = 30
const PERMANENT_STRIKE_MOOD_THRESHOLD: int = 15
const FISHING_RANGE: float = 28.0
const FISHING_MINUTES: float = 45.0

enum Task { IDLE, MOVE, GATHER, HAUL, ATTACK, EAT, SLEEP, WORK, CRAFT, FISH }

var current_task: Task = Task.IDLE
var path: Array[Vector2] = []
var is_selected: bool = false
var current_target_pos: Vector2 = Vector2.ZERO
var movement_goal_pos: Vector2 = Vector2.ZERO
var _last_target_distance: float = INF
var _stuck_timer: float = 0.0

var target_resource: Node2D = null
var target_animal: Node2D = null
var gather_timer: float = 0.0
var tool_sprite: Sprite2D = null

var hunger: float = 100.0
var max_hunger: float = 100.0
var target_food: Node2D = null
var energy: float = 100.0
var max_energy: float = 100.0
var target_bed: Node2D = null
var target_farm_plot_id: int = -1
var target_farm_cell: Vector2i = Vector2i(-99999, -99999)
var target_workbench: Node2D = null
var target_recipe_id: String = ""
var craft_timer_minutes: float = 0.0
var _sleep_sprite: Sprite2D = null
var _body_sprite: Sprite2D = null
var is_unconscious: bool = false
var unconscious_elapsed_hours: float = 0.0
var wolf_hit_count: int = 0
var max_health: float = 100.0
var health: float = 100.0

var carried_item: Node2D = null
var haul_target_cell: Vector2i
var idle_timer: float = 0.0

var skill_woodcut: int = 1
var skill_mining: int = 1
var skill_melee: int = 1
var inventory: Dictionary = {}
var equipped_tool_id: String = ""

var social_relations: Dictionary = {}
var mood: int = 100
var base_mood: float = 100.0
var mood_penalties: Dictionary = {
	"no_room": 0.0,
	"no_bed": 0.0,
	"injured": 0.0,
	"hunger": 0.0,
	"fatigue": 0.0,
}
var is_on_strike: bool = false
var strike_timer: float = 0.0
var strike_check_timer: float = 0.0
var strike_reason: String = ""

var target_fishing_cell: Vector2i = Vector2i(-99999, -99999)
var target_water_cell: Vector2i = Vector2i(-99999, -99999)
var fishing_timer_minutes: float = 0.0

var _haul_manager: Node = null
var _event_bus: Node = null

func _ready() -> void:
	_haul_manager = get_node_or_null("/root/HaulManager")
	_event_bus = get_node_or_null("/root/EventBus")
	if not _event_bus:
		_event_bus = EventBus

	if _haul_manager and _event_bus:
		_event_bus.stockpile_updated.connect(_on_stockpile_updated)

	add_to_group("villagers")
	input_pickable = true
	_body_sprite = _find_body_sprite()
	_setup_collision_shape()
	tool_sprite = Sprite2D.new()
	tool_sprite.visible = false
	tool_sprite.scale = Vector2(2.0, 2.0)
	add_child(tool_sprite)
	
	skill_woodcut = randi() % 20 + 1
	skill_mining = randi() % 20 + 1
	skill_melee = randi() % 20 + 1

func _setup_collision_shape() -> void:
	collision_mask = 0

	var collision = get_node_or_null("CollisionShape2D")
	if not collision:
		collision = CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		add_child(collision)

	var rect = collision.shape as RectangleShape2D
	if not rect:
		rect = RectangleShape2D.new()
		collision.shape = rect
	rect.size = BODY_COLLISION_SIZE

func inject_haul_manager(manager: Node) -> void:
	_haul_manager = manager

func inject_event_bus(bus: Node) -> void:
	_event_bus = bus

func _get_tilemap_layer() -> Node:
	var parent = get_parent()
	if parent and parent.has_method("local_to_map") and parent.has_method("map_to_local") and parent.has_method("get_path_coords"):
		return parent
	var scene = get_tree().current_scene
	if scene:
		return scene.get_node_or_null("TileMapLayer")
	return null

func _on_stockpile_updated():
	if current_task == Task.IDLE:
		_search_for_job()

func command_move(new_path: Array[Vector2]) -> void:
	if is_unconscious:
		return
	_clear_targets()
	current_task = Task.MOVE
	_set_path(new_path)

func command_gather(new_path: Array[Vector2], resource: Node2D) -> void:
	if is_unconscious:
		return
	_clear_targets()
	current_task = Task.GATHER
	_set_path(new_path)
	target_resource = resource
	gather_timer = 0.0
	
	if tool_sprite and resource:
		var tool_level = _get_tool_level_for_resource(resource)
		var tool_path = _get_tool_texture_path(resource, tool_level)
		tool_sprite.texture = load(tool_path) if tool_path != "" else null
		tool_sprite.scale = Vector2(2.0, 2.0)
		tool_sprite.position = Vector2(8, -8)
		tool_sprite.visible = false

func command_attack(new_path: Array[Vector2], animal: Node2D) -> void:
	if is_unconscious:
		return
	_clear_targets()
	current_task = Task.ATTACK
	_set_path(new_path)
	target_animal = animal
	gather_timer = 0.0
	if tool_sprite:
		var weapon_path = _get_weapon_texture_path()
		tool_sprite.texture = load(weapon_path) if weapon_path != "" else null
		tool_sprite.scale = _get_weapon_sprite_scale()
		tool_sprite.position = Vector2(16, -16)
		tool_sprite.visible = false

func command_haul(item: Node2D, dest_cell: Vector2i) -> void:
	if is_unconscious:
		return
	var tilemap = _get_tilemap_layer()
	if not tilemap: return
	
	var start_coord = tilemap.local_to_map(global_position)
	var item_grid_coord = item.grid_coord if "grid_coord" in item else Vector2i(-1, -1)
	var id_path = tilemap.get_path_coords(start_coord, item_grid_coord, true)
	
	if id_path.size() > 0:
		var world_path: Array[Vector2] = []
		for coord in id_path:
			world_path.append(tilemap.map_to_local(coord))
		if world_path.size() > 1:
			world_path.remove_at(0)
			
		current_task = Task.HAUL
		target_resource = item
		haul_target_cell = dest_cell
		_set_path(world_path)
		carried_item = null
		_event_bus.villager_task_assigned.emit(self, "haul", item)
	else:
		# No valid path to target item, release reservation so others can retry later.
		if "is_reserved" in item:
			item.set("is_reserved", false)

func _physics_process(delta: float) -> void:
	if is_unconscious:
		velocity = Vector2.ZERO
		mood = 50
		_apply_unconscious_pose()
		_update_unconscious_recovery(delta)
		return

	_update_hunger(delta)
	_update_energy(delta)
	_update_mood(delta)
	_try_auto_use_bandage()
	_update_strike(delta)
	if is_on_strike:
		velocity = Vector2.ZERO
		if tool_sprite:
			tool_sprite.visible = false
		return
	
	if current_task in [Task.MOVE, Task.GATHER, Task.HAUL, Task.ATTACK, Task.EAT, Task.SLEEP, Task.WORK, Task.CRAFT, Task.FISH]:
		_handle_movement(delta)
	
	if current_task == Task.GATHER:
		_handle_gathering(delta)
	
	if current_task == Task.ATTACK:
		_handle_combat(delta)
		
	if current_task == Task.EAT:
		_handle_eating(delta)

	if current_task == Task.SLEEP:
		_handle_sleeping(delta)

	if current_task == Task.WORK:
		_handle_farm_work(delta)

	if current_task == Task.CRAFT:
		_handle_crafting(delta)

	if current_task == Task.FISH:
		_handle_fishing(delta)
			
	if current_task == Task.IDLE:
		idle_timer += delta
		if idle_timer > 1.0:
			idle_timer = 0.0
			_search_for_job()

	modulate = Color(1.2, 1.2, 1.2, 1.0) if is_selected else Color(1.0, 1.0, 1.0, 1.0)

func _handle_movement(delta: float) -> void:
	if current_target_pos == Vector2.ZERO and path.is_empty(): return
	if _stop_if_interaction_target_reached():
		return

	var dir = (current_target_pos - global_position).normalized()
	var dist = global_position.distance_to(current_target_pos)

	if dist <= REACH_THRESHOLD:
		if path.size() > 0:
			current_target_pos = path[0]
			path.remove_at(0)
			_reset_stuck_tracking()
		else:
			if current_task == Task.MOVE:
				current_task = Task.IDLE
				_event_bus.villager_idle.emit(self)
			elif current_task == Task.HAUL:
				_process_haul_step()
		velocity = Vector2.ZERO
	else:
		_update_stuck_tracking(dist, delta)
		if _stuck_timer >= STUCK_REPATH_TIME:
			if _try_repath_to_current_goal():
				return
			if current_task == Task.ATTACK:
				_reset_stuck_tracking()
				return
			_finish_unreachable_task()
			return

		var step_speed = min(move_speed, dist / max(delta, 0.001))
		velocity = dir * step_speed
		move_and_slide()

func _stop_if_interaction_target_reached() -> bool:
	var target: Node2D = null
	var interaction_range = 0.0

	if current_task == Task.GATHER and is_instance_valid(target_resource):
		target = target_resource
		interaction_range = GATHER_RANGE
	elif current_task == Task.ATTACK and is_instance_valid(target_animal):
		target = target_animal
		interaction_range = _get_attack_range()
	elif current_task == Task.EAT and is_instance_valid(target_food):
		target = target_food
		interaction_range = EAT_RANGE
	elif current_task == Task.SLEEP and is_instance_valid(target_bed):
		target = target_bed
		interaction_range = SLEEP_RANGE
	elif current_task == Task.WORK:
		var tilemap = _get_tilemap_layer()
		if tilemap and target_farm_cell.x != -99999:
			var farm_pos = tilemap.to_global(tilemap.map_to_local(target_farm_cell))
			if global_position.distance_to(farm_pos) <= FARM_WORK_RANGE:
				velocity = Vector2.ZERO
				path.clear()
				current_target_pos = global_position
				_reset_stuck_tracking()
				return true
		return false
	elif current_task == Task.CRAFT and is_instance_valid(target_workbench):
		target = target_workbench
		interaction_range = CRAFT_STOP_RANGE
	elif current_task == Task.FISH and target_fishing_cell.x != -99999:
		var tilemap = _get_tilemap_layer()
		if tilemap:
			var fish_pos = tilemap.to_global(tilemap.map_to_local(target_fishing_cell))
			if global_position.distance_to(fish_pos) <= FISHING_RANGE:
				velocity = Vector2.ZERO
				path.clear()
				current_target_pos = global_position
				return true
		return false
	else:
		return false

	if global_position.distance_to(target.global_position) > interaction_range:
		return false

	velocity = Vector2.ZERO
	path.clear()
	current_target_pos = global_position
	_reset_stuck_tracking()
	return true

func _set_path(new_path: Array[Vector2]) -> void:
	path.clear()
	path.append_array(new_path)
	movement_goal_pos = path[path.size() - 1] if path.size() > 0 else global_position
	if path.size() > 0:
		current_target_pos = path[0]
		path.remove_at(0)
	else:
		current_target_pos = global_position
	_reset_stuck_tracking()

func _reset_stuck_tracking() -> void:
	_last_target_distance = INF
	_stuck_timer = 0.0

func _update_stuck_tracking(dist: float, delta: float) -> void:
	if dist < _last_target_distance - STUCK_MIN_PROGRESS:
		_stuck_timer = 0.0
	else:
		_stuck_timer += delta
	_last_target_distance = dist

func _try_repath_to_current_goal() -> bool:
	var tilemap = _get_tilemap_layer()
	if not tilemap:
		return false

	var start_coord = tilemap.local_to_map(tilemap.to_local(global_position))
	var goal_coord = tilemap.local_to_map(tilemap.to_local(movement_goal_pos))

	if current_task == Task.GATHER and is_instance_valid(target_resource):
		goal_coord = target_resource.grid_coord if "grid_coord" in target_resource else tilemap.local_to_map(tilemap.to_local(target_resource.global_position))
	elif current_task == Task.ATTACK and is_instance_valid(target_animal):
		goal_coord = tilemap.local_to_map(tilemap.to_local(target_animal.global_position))
	elif current_task == Task.EAT and is_instance_valid(target_food):
		goal_coord = target_food.grid_coord if "grid_coord" in target_food else tilemap.local_to_map(tilemap.to_local(target_food.global_position))
	elif current_task == Task.HAUL and carried_item != null:
		goal_coord = haul_target_cell
	elif current_task == Task.WORK and target_farm_cell.x != -99999:
		goal_coord = target_farm_cell
	elif current_task == Task.CRAFT and is_instance_valid(target_workbench):
		goal_coord = tilemap.local_to_map(tilemap.to_local(target_workbench.global_position))
	elif current_task == Task.FISH and target_fishing_cell.x != -99999:
		goal_coord = target_fishing_cell

	var id_path = tilemap.get_path_coords(start_coord, goal_coord, current_task != Task.MOVE)
	if id_path.size() <= 1:
		return false

	var world_path: Array[Vector2] = []
	for coord in id_path:
		world_path.append(tilemap.to_global(tilemap.map_to_local(coord)))
	if world_path.size() > 1:
		world_path.remove_at(0)
	if world_path.is_empty():
		return false

	_set_path(world_path)
	return true

func _finish_unreachable_task() -> void:
	velocity = Vector2.ZERO
	path.clear()
	current_target_pos = Vector2.ZERO
	if current_task == Task.HAUL and carried_item:
		_drop_current_item()
		return
	if current_task == Task.HAUL and target_resource and "is_reserved" in target_resource:
		target_resource.set("is_reserved", false)
	if current_task == Task.GATHER and target_resource:
		var job_mgr = get_node_or_null("/root/JobManager")
		if job_mgr:
			job_mgr.abandon_job(target_resource)
	if current_task == Task.ATTACK and target_animal:
		var job_mgr = get_node_or_null("/root/JobManager")
		if job_mgr:
			job_mgr.abandon_job(target_animal)
	if current_task == Task.CRAFT and target_workbench:
		var job_mgr = get_node_or_null("/root/JobManager")
		if job_mgr:
			job_mgr.abandon_job(target_workbench)
	if target_food and "is_reserved" in target_food:
		target_food.set("is_reserved", false)
	_clear_targets()
	current_task = Task.IDLE
	_event_bus.villager_idle.emit(self)

func _update_energy(delta: float) -> void:
	var time_mgr = get_node_or_null("/root/TimeManager")
	var hours_per_second = time_mgr.hours_per_real_second if time_mgr and "hours_per_real_second" in time_mgr else 0.05
	var game_hours = delta * hours_per_second
	if current_task == Task.SLEEP:
		return
	energy = max(0.0, energy - (max_energy / ENERGY_DRAIN_HOURS) * game_hours)

func _update_hunger(delta: float) -> void:
	var time_mgr = get_node_or_null("/root/TimeManager")
	var hours_per_second = time_mgr.hours_per_real_second if time_mgr and "hours_per_real_second" in time_mgr else 0.05
	var game_hours = delta * hours_per_second
	hunger = max(0.0, hunger - (max_hunger / HUNGER_DRAIN_HOURS) * game_hours)

func _update_mood(delta: float) -> void:
	var time_mgr = get_node_or_null("/root/TimeManager")
	var hours_per_second = time_mgr.hours_per_real_second if time_mgr and "hours_per_real_second" in time_mgr else 0.05
	var game_hours = delta * hours_per_second
	var room_mgr = get_node_or_null("/root/RoomManager")

	var has_owned_room = room_mgr.has_room(name) if room_mgr and room_mgr.has_method("has_room") else false
	var has_owned_bed = room_mgr.has_bed_for(name) if room_mgr and room_mgr.has_method("has_bed_for") else false

	_adjust_mood_penalty("no_room", not has_owned_room, 20.0, game_hours, ROOM_BED_MOOD_PENALTY_HOURS)
	_adjust_mood_penalty("no_bed", not has_owned_bed, 10.0, game_hours, ROOM_BED_MOOD_PENALTY_HOURS)
	if has_owned_room:
		mood_penalties["no_room"] = 0.0
	if has_owned_bed:
		mood_penalties["no_bed"] = 0.0

	var injured = health < max_health
	_adjust_mood_penalty("injured", injured, INJURED_MOOD_PENALTY_CAP, game_hours, INJURED_MOOD_PENALTY_HOURS)
	if not injured:
		mood_penalties["injured"] = 0.0

	# 饥饿惩罚：饱食度低于 30 时开始扣分，上限 25
	_adjust_mood_penalty("hunger", hunger < 30.0, 25.0, game_hours)
	
	# 疲劳惩罚：精力低于 20 时开始扣分，上限 20
	_adjust_mood_penalty("fatigue", energy < 20.0, 20.0, game_hours)

	var total_penalty = 0.0
	for value in mood_penalties.values():
		total_penalty += float(value)
	mood = int(round(clamp(base_mood - total_penalty, 10.0, 100.0)))

func _adjust_mood_penalty(key: String, active: bool, cap: float, game_hours: float, penalty_hours: float = MOOD_PENALTY_HOURS) -> void:
	var current = float(mood_penalties.get(key, 0.0))
	var delta_value = (cap / max(penalty_hours, 0.001)) * game_hours
	if active:
		current = min(cap, current + delta_value)
	else:
		current = max(0.0, current - delta_value)
	mood_penalties[key] = current

func manual_use_bandage() -> bool:
	if is_unconscious:
		return false
	if health >= max_health:
		EventBus.alert_message.emit("%s 身体健康，无需使用绷带" % name)
		return false
	return _consume_owned_bandage()

func _try_auto_use_bandage() -> void:
	if is_unconscious:
		return
	if health >= max_health * BANDAGE_USE_HEALTH_RATIO:
		return
	if int(inventory.get("bandage", 0)) > 0:
		if _consume_owned_bandage():
			return
	_consume_stockpile_bandage()

func _consume_owned_bandage() -> bool:
	if not remove_tool_from_inventory("bandage", 1):
		return false
	health = min(max_health, health + BANDAGE_HEAL_AMOUNT)
	EventBus.alert_message.emit("%s 使用绷带治疗了伤口" % name)
	return true

func _consume_stockpile_bandage() -> bool:
	var haul_mgr = _haul_manager if _haul_manager else get_node_or_null("/root/HaulManager")
	if not haul_mgr or not haul_mgr.has_method("get_stockpile_items"):
		return false
	for item in haul_mgr.get_stockpile_items():
		if not is_instance_valid(item):
			continue
		if str(item.get("item_id") if "item_id" in item else "") != "bandage":
			continue
		var amount = int(item.get("amount") if "amount" in item else 1)
		if amount <= 0:
			continue
		if "amount" in item:
			item.amount = amount - 1
		health = min(max_health, health + BANDAGE_HEAL_AMOUNT)
		if int(item.get("amount") if "amount" in item else 0) <= 0:
			if haul_mgr.has_method("unregister_item"):
				haul_mgr.unregister_item(item)
			item.queue_free()
		elif item.has_method("_update_visual"):
			item._update_visual()
		EventBus.alert_message.emit("%s 从仓库取用绷带治疗了伤口" % name)
		return true
	return false

func _update_strike(delta: float) -> void:
	var time_mgr = get_node_or_null("/root/TimeManager")
	var hours_per_second = time_mgr.hours_per_real_second if time_mgr and "hours_per_real_second" in time_mgr else 0.05
	var game_hours = delta * hours_per_second

	if mood < PERMANENT_STRIKE_MOOD_THRESHOLD:
		if not is_on_strike:
			_start_strike(true)
		strike_timer = INF
		return

	if is_on_strike:
		if strike_timer == INF:
			strike_timer = randf_range(1.0, 2.5)
		strike_timer -= game_hours
		if strike_timer <= 0.0:
			is_on_strike = false
			strike_reason = ""
			strike_check_timer = randf_range(1.0, 3.0)
			_event_bus.villager_idle.emit(self)
		return

	if mood < STRIKE_MOOD_THRESHOLD:
		strike_check_timer -= game_hours
		if strike_check_timer <= 0.0:
			_start_strike(false)
	else:
		strike_check_timer = randf_range(1.0, 3.0)

func _start_strike(permanent: bool) -> void:
	is_on_strike = true
	strike_reason = "情绪过低"
	strike_timer = INF if permanent else randf_range(1.5, 4.0)
	if current_task not in [Task.EAT, Task.SLEEP]:
		_clear_targets()
		current_task = Task.IDLE
		path.clear()
		current_target_pos = global_position
	EventBus.alert_message.emit("%s 情绪过低，开始罢工" % name)

func get_mood_breakdown() -> Dictionary:
	return {
		"base": base_mood,
		"current": mood,
		"penalties": mood_penalties.duplicate(),
		"is_unconscious": is_unconscious,
		"is_on_strike": is_on_strike,
		"strike_reason": strike_reason,
	}

func command_sleep(new_path: Array[Vector2], bed: Node2D) -> void:
	if is_unconscious:
		return
	_clear_targets()
	current_task = Task.SLEEP
	_set_path(new_path)
	target_bed = bed

func command_work(new_path: Array[Vector2], plot_id: int, farm_cell: Vector2i) -> void:
	if is_unconscious:
		return
	_clear_targets()
	current_task = Task.WORK
	_set_path(new_path)
	target_farm_plot_id = plot_id
	target_farm_cell = farm_cell
	gather_timer = 0.0

func command_craft(new_path: Array[Vector2], workbench: Node2D, recipe_id: String) -> void:
	if is_unconscious:
		return
	_clear_targets()
	current_task = Task.CRAFT
	_set_path(new_path)
	target_workbench = workbench
	target_recipe_id = recipe_id
	var job_mgr = get_node_or_null("/root/JobManager")
	craft_timer_minutes = job_mgr.get_craft_progress(workbench) if job_mgr and job_mgr.has_method("get_craft_progress") else 0.0
	if tool_sprite:
		tool_sprite.texture = null
		tool_sprite.visible = false

func command_fish(new_path: Array[Vector2], shore_cell: Vector2i, water_cell: Vector2i) -> void:
	if is_unconscious:
		return
	_clear_targets()
	current_task = Task.FISH
	_set_path(new_path)
	target_fishing_cell = shore_cell
	target_water_cell = water_cell
	fishing_timer_minutes = 0.0

func _handle_farm_work(delta: float) -> void:
	var tilemap = _get_tilemap_layer()
	var farm_mgr = get_node_or_null("/root/FarmManager")
	if not tilemap or not farm_mgr or target_farm_plot_id == -1:
		_release_target_farm()
		current_task = Task.IDLE
		_event_bus.villager_idle.emit(self)
		return

	var farm_pos = tilemap.to_global(tilemap.map_to_local(target_farm_cell))
	if global_position.distance_to(farm_pos) > FARM_WORK_RANGE:
		return

	velocity = Vector2.ZERO
	var time_mgr = get_node_or_null("/root/TimeManager")
	var hours_per_second = time_mgr.hours_per_real_second if time_mgr and "hours_per_real_second" in time_mgr else 0.05
	gather_timer += delta * hours_per_second * 60.0
	if gather_timer < FARM_WORK_MINUTES_PER_CELL:
		return

	gather_timer = 0.0
	var result = farm_mgr.work_plot(target_farm_plot_id, target_farm_cell)
	if bool(result.get("harvested", false)):
		var crop_name = "纤维" if str(result.get("crop", "")) == "fiber" else "食物"
		EventBus.alert_message.emit("%s 收获了%s x%d" % [name, crop_name, int(result.get("amount", 0))])
	else:
		EventBus.alert_message.emit("%s 完成了一次农田劳作" % name)

	_release_target_farm()
	current_task = Task.IDLE
	target_farm_plot_id = -1
	target_farm_cell = Vector2i(-99999, -99999)
	_event_bus.villager_task_completed.emit(self)
	_event_bus.villager_idle.emit(self)

func _release_target_farm() -> void:
	if target_farm_plot_id == -1:
		return
	var farm_mgr = get_node_or_null("/root/FarmManager")
	if farm_mgr and farm_mgr.has_method("release_plot"):
		farm_mgr.release_plot(target_farm_plot_id, name, target_farm_cell)

func _handle_crafting(delta: float) -> void:
	if not is_instance_valid(target_workbench) or target_recipe_id == "":
		_finish_crafting(false)
		return

	if global_position.distance_to(target_workbench.global_position) > CRAFT_WORK_RANGE:
		if tool_sprite:
			tool_sprite.visible = false
		return

	velocity = Vector2.ZERO
	path.clear()
	current_target_pos = global_position
	if tool_sprite:
		tool_sprite.visible = false

	var recipe = _get_recipe(target_recipe_id)
	if recipe.is_empty():
		_finish_crafting(false)
		return

	var time_mgr = get_node_or_null("/root/TimeManager")
	var hours_per_second = time_mgr.hours_per_real_second if time_mgr and "hours_per_real_second" in time_mgr else 0.05
	var added_minutes = delta * hours_per_second * 60.0
	var job_mgr = get_node_or_null("/root/JobManager")
	if job_mgr and job_mgr.has_method("add_craft_progress"):
		var shared_progress = job_mgr.add_craft_progress(target_workbench, added_minutes)
		if shared_progress >= 0.0:
			craft_timer_minutes = shared_progress
		else:
			craft_timer_minutes += added_minutes
	else:
		craft_timer_minutes += added_minutes
	if craft_timer_minutes < float(recipe.get("time_minutes", 30.0)):
		return

	_drop_crafted_tool(target_recipe_id, int(recipe.get("output_amount", 1)))
	EventBus.alert_message.emit("%s 完成合成：%s" % [name, str(recipe.get("name", target_recipe_id))])
	_finish_crafting(true)

func _drop_crafted_tool(tool_id: String, amount: int = 1) -> void:
	var tilemap = _get_tilemap_layer()
	if not tilemap:
		return
	var item_scene = load("res://scenes/ItemDrop.tscn")
	if not item_scene:
		return
	var drop = item_scene.instantiate()
	if "item_id" in drop:
		drop.item_id = tool_id
	if "type" in drop:
		drop.type = -1
	if "amount" in drop:
		drop.amount = max(1, amount)
	var origin = target_workbench.global_position if is_instance_valid(target_workbench) else global_position
	var cell = tilemap.local_to_map(tilemap.to_local(origin))
	if "grid_coord" in drop:
		drop.grid_coord = cell
	tilemap.add_child(drop)
	drop.global_position = tilemap.to_global(tilemap.map_to_local(cell)) + Vector2(12, 10)
	# 注册到搬运系统，使物品可以自动搬运回仓库
	if _haul_manager and _haul_manager.has_method("register_item"):
		_haul_manager.register_item(drop)
	_event_bus.item_dropped.emit(drop, -1, max(1, amount))

func _finish_crafting(completed: bool) -> void:
	var job_mgr = get_node_or_null("/root/JobManager")
	var was_temp = is_instance_valid(target_workbench) and target_workbench.has_meta("is_temp_craft_spot")
	if job_mgr and target_workbench:
		if completed:
			job_mgr.remove_job(target_workbench)
		else:
			job_mgr.abandon_job(target_workbench)
	# 清理临时制作点
	if was_temp and is_instance_valid(target_workbench):
		target_workbench.queue_free()
	target_workbench = null
	target_recipe_id = ""
	craft_timer_minutes = 0.0
	if tool_sprite:
		tool_sprite.visible = false
	current_task = Task.IDLE
	_event_bus.villager_task_completed.emit(self)
	_event_bus.villager_idle.emit(self)

func _get_recipe(recipe_id: String) -> Dictionary:
	var job_mgr = get_node_or_null("/root/JobManager")
	if job_mgr and job_mgr.has_method("get_craft_recipe"):
		return job_mgr.get_craft_recipe(recipe_id)
	return {}

func _handle_fishing(delta: float) -> void:
	var tilemap = _get_tilemap_layer()
	if not tilemap or target_fishing_cell.x == -99999 or target_water_cell.x == -99999:
		_finish_fishing(false)
		return

	var shore_pos = tilemap.to_global(tilemap.map_to_local(target_fishing_cell))
	if global_position.distance_to(shore_pos) > FISHING_RANGE:
		if tool_sprite:
			tool_sprite.visible = false
		return

	velocity = Vector2.ZERO
	path.clear()
	current_target_pos = global_position

	if tool_sprite:
		tool_sprite.texture = load("res://art/tools/fishing_rod.svg")
		tool_sprite.scale = Vector2(0.55, 0.55)
		tool_sprite.visible = true
		var water_pos = tilemap.to_global(tilemap.map_to_local(target_water_cell))
		tool_sprite.rotation = (water_pos - global_position).angle()
		tool_sprite.position = Vector2(10, -6)

	var time_mgr = get_node_or_null("/root/TimeManager")
	var hours_per_second = time_mgr.hours_per_real_second if time_mgr and "hours_per_real_second" in time_mgr else 0.05
	fishing_timer_minutes += delta * hours_per_second * 60.0
	if fishing_timer_minutes < FISHING_MINUTES:
		return

	var inv = get_node_or_null("/root/InventoryManager")
	if inv and inv.has_method("add_resource"):
		inv.add_resource(2, 1)
	else:
		EventBus.resource_collected.emit(2, 1)
	EventBus.alert_message.emit("%s 钓到了一份食物" % name)
	_finish_fishing(true)

func _finish_fishing(_completed: bool) -> void:
	target_fishing_cell = Vector2i(-99999, -99999)
	target_water_cell = Vector2i(-99999, -99999)
	fishing_timer_minutes = 0.0
	if tool_sprite:
		tool_sprite.visible = false
	current_task = Task.IDLE
	_event_bus.villager_task_completed.emit(self)
	_event_bus.villager_idle.emit(self)

func _handle_sleeping(delta: float) -> void:
	if not is_instance_valid(target_bed):
		_finish_sleeping()
		return

	var dist = global_position.distance_to(target_bed.global_position)
	if dist > SLEEP_RANGE:
		_restore_sleep_pose()
		return

	velocity = Vector2.ZERO
	path.clear()
	current_target_pos = global_position
	global_position = target_bed.global_position + Vector2(0, 2)
	_apply_sleep_pose()

	var time_mgr = get_node_or_null("/root/TimeManager")
	var hours_per_second = time_mgr.hours_per_real_second if time_mgr and "hours_per_real_second" in time_mgr else 0.05
	var game_hours = delta * hours_per_second
	energy = min(max_energy, energy + (max_energy / ENERGY_RECOVER_HOURS) * game_hours)

	if energy >= max_energy:
		_finish_sleeping()

func _apply_sleep_pose() -> void:
	if not _sleep_sprite:
		_sleep_sprite = get_node_or_null("Sprite2D") as Sprite2D
	if _sleep_sprite:
		_sleep_sprite.rotation_degrees = 90.0
		_sleep_sprite.position = Vector2(0, 2)

func _restore_sleep_pose() -> void:
	if is_unconscious:
		return
	var sprite = _get_body_sprite()
	if sprite:
		sprite.rotation_degrees = 0.0
		sprite.position = Vector2.ZERO

func set_unconscious(value: bool = true) -> void:
	is_unconscious = value
	if is_unconscious:
		unconscious_elapsed_hours = 0.0
		_clear_targets()
		current_task = Task.IDLE
		velocity = Vector2.ZERO
		mood = 50
		_apply_unconscious_pose()
	else:
		unconscious_elapsed_hours = 0.0
		health = max(health, max_health * 0.35)
		_restore_sleep_pose()

func _update_unconscious_recovery(delta: float) -> void:
	var time_mgr = get_node_or_null("/root/TimeManager")
	var hours_per_second = time_mgr.hours_per_real_second if time_mgr and "hours_per_real_second" in time_mgr else 0.05
	unconscious_elapsed_hours += delta * hours_per_second
	if unconscious_elapsed_hours >= UNCONSCIOUS_RECOVER_HOURS:
		set_unconscious(false)
		EventBus.alert_message.emit("%s 从昏迷中恢复了。" % name)

func receive_wolf_attack() -> void:
	if is_unconscious:
		return
	_play_wolf_hit_flash()
	health = max(0.0, health - 22.0)
	wolf_hit_count += 1
	if health <= 0.0 or wolf_hit_count >= 5:
		wolf_hit_count = 0
		set_unconscious(true)
		EventBus.alert_message.emit("%s 被狼袭击后昏迷了！" % name)

func _play_wolf_hit_flash() -> void:
	var tween = create_tween()
	modulate = Color(1.0, 0.15, 0.15, 1.0)
	tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.18)

func _apply_unconscious_pose() -> void:
	var sprite = _get_body_sprite()
	if sprite:
		sprite.rotation_degrees = 90.0
		sprite.position = Vector2(0, 2)

func _get_body_sprite() -> Sprite2D:
	if is_instance_valid(_body_sprite):
		return _body_sprite
	_body_sprite = _find_body_sprite()
	return _body_sprite

func _find_body_sprite() -> Sprite2D:
	for child in get_children():
		if child is Sprite2D and child != tool_sprite and child.name != "SelectionRing":
			return child as Sprite2D
	return get_node_or_null("Sprite2D") as Sprite2D

func _finish_sleeping() -> void:
	_restore_sleep_pose()
	target_bed = null
	current_task = Task.IDLE
	path.clear()
	current_target_pos = Vector2.ZERO
	_event_bus.villager_idle.emit(self)

func _handle_combat(delta: float) -> void:
	if not is_instance_valid(target_animal):
		current_task = Task.IDLE
		if tool_sprite: tool_sprite.visible = false
		_event_bus.villager_task_completed.emit(self)
		_event_bus.villager_idle.emit(self)
		return

	if not _can_current_weapon_attack():
		if tool_sprite: tool_sprite.visible = false
		return
	
	var dist_to_ani = global_position.distance_to(target_animal.global_position)
	if dist_to_ani <= _get_attack_range():
		# 在攻击范围内 —— 停下来攻击
		velocity = Vector2.ZERO
		path.clear()
		current_target_pos = global_position
		
		if tool_sprite:
			var weapon_path = _get_weapon_texture_path()
			tool_sprite.texture = load(weapon_path) if weapon_path != "" else null
			tool_sprite.scale = _get_weapon_sprite_scale()
			tool_sprite.visible = weapon_path != ""
		
		if tool_sprite and tool_sprite.visible and equipped_tool_id != "bow":
			tool_sprite.rotation = sin(Time.get_ticks_msec() * 0.02) * 0.5
		elif tool_sprite and equipped_tool_id == "bow":
			var bow_dir = target_animal.global_position - global_position
			if bow_dir.length() > 0.001:
				tool_sprite.rotation = bow_dir.angle()
		
		var weapon_bonus = 0.0
		if equipped_tool_id == "wood_sword" and int(inventory.get("wood_sword", 0)) > 0:
			weapon_bonus = 0.35
		elif equipped_tool_id == "stone_sword" and int(inventory.get("stone_sword", 0)) > 0:
			weapon_bonus = 0.75
		elif equipped_tool_id == "bow" and int(inventory.get("bow", 0)) > 0 and int(inventory.get("arrow", 0)) > 0:
			weapon_bonus = 0.55
		var effective_speed = 0.22 + weapon_bonus + (skill_melee * 0.04)
		gather_timer += delta * effective_speed
		
		if gather_timer >= gather_speed:
			gather_timer = 0.0
			if target_animal.has_method("take_damage"):
				if equipped_tool_id == "bow":
					if int(inventory.get("arrow", 0)) <= 0:
						return
					remove_tool_from_inventory("arrow", 1)
					_fire_arrow_at(target_animal)
				else:
					target_animal.take_damage(_get_melee_attack_damage())
	else:
		if tool_sprite: tool_sprite.visible = false
		_follow_attack_target(delta)
		return
		# 目标超出攻击范围 —— 持续追击
		if tool_sprite: tool_sprite.visible = false
		# 动态更新路径：每0.5秒重新寻路到动物当前位置
		_stuck_timer += delta
		if _stuck_timer >= 0.5 or (current_target_pos == Vector2.ZERO and path.is_empty()):
			_stuck_timer = 0.0
			var tilemap = _get_tilemap_layer()
			if tilemap and is_instance_valid(target_animal):
				var start_c = tilemap.local_to_map(tilemap.to_local(global_position))
				var end_c = tilemap.local_to_map(tilemap.to_local(target_animal.global_position))
				var id_path = tilemap.get_path_coords(start_c, end_c, true)
				if id_path.size() > 0:
					var world_path: Array[Vector2] = []
					for c in id_path:
						world_path.append(tilemap.to_global(tilemap.map_to_local(c)))
					if world_path.size() > 1:
						world_path.remove_at(0)
					_set_path(world_path)
				else:
					# 无法到达目标，放弃任务
					var job_mgr = get_node_or_null("/root/JobManager")
					if job_mgr: job_mgr.abandon_job(target_animal)
					_clear_targets()
					current_task = Task.IDLE
					_event_bus.villager_idle.emit(self)

func _can_current_weapon_attack() -> bool:
	if equipped_tool_id == "bow":
		return int(inventory.get("bow", 0)) > 0 and int(inventory.get("arrow", 0)) > 0
	return true

func _follow_attack_target(delta: float) -> void:
	if not is_instance_valid(target_animal):
		return

	var tilemap = _get_tilemap_layer()
	if tilemap and (_stuck_timer >= 0.35 or current_target_pos == Vector2.ZERO or path.is_empty()):
		_stuck_timer = 0.0
		var start_c = tilemap.local_to_map(tilemap.to_local(global_position))
		var end_c = tilemap.local_to_map(tilemap.to_local(target_animal.global_position))
		var id_path = tilemap.get_path_coords(start_c, end_c, true)
		if id_path.size() > 0:
			var world_path: Array[Vector2] = []
			for c in id_path:
				world_path.append(tilemap.to_global(tilemap.map_to_local(c)))
			if world_path.size() > 1:
				world_path.remove_at(0)
			if not world_path.is_empty():
				_set_path(world_path)
				return

	_stuck_timer += delta
	var chase_dir = target_animal.global_position - global_position
	var chase_dist = chase_dir.length()
	if chase_dist <= 0.001:
		velocity = Vector2.ZERO
		return
	var step_speed = min(move_speed * ATTACK_CHASE_SPEED_MULTIPLIER, chase_dist / max(delta, 0.001))
	velocity = chase_dir.normalized() * step_speed
	move_and_slide()

func _handle_gathering(delta: float) -> void:
	if not is_instance_valid(target_resource):
		if DEBUG_VILLAGER_LOGS:
			print("村民: 目标资源无效，任务完成")
		current_task = Task.IDLE
		if tool_sprite: tool_sprite.visible = false
		_event_bus.villager_task_completed.emit(self)
		_event_bus.villager_idle.emit(self)
		return
	
	var dist_to_res = global_position.distance_to(target_resource.global_position)
	if dist_to_res <= GATHER_RANGE:
		var tool_level = _get_tool_level_for_resource(target_resource)
		if tool_sprite:
			var tool_path = _get_tool_texture_path(target_resource, tool_level)
			tool_sprite.texture = load(tool_path) if tool_path != "" else null
			tool_sprite.scale = Vector2(2.0, 2.0)
			tool_sprite.visible = tool_level > 0 and tool_sprite.texture != null
		
		if tool_sprite and tool_sprite.visible:
			tool_sprite.rotation = sin(Time.get_ticks_msec() * 0.02) * 0.5
		
		var is_rock = target_resource.get("type") == 1
		var effective_skill = skill_mining if is_rock else skill_woodcut
		var tool_bonus = 0.0
		if tool_level == 1:
			tool_bonus = 0.25
		elif tool_level >= 2:
			tool_bonus = 0.48
		var effective_speed = 0.22 + tool_bonus + (effective_skill * 0.035)
		gather_timer += delta * effective_speed
		
		if gather_timer >= gather_speed:
			gather_timer = 0.0
			if target_resource.has_method("gather"):
				if DEBUG_VILLAGER_LOGS:
					print("村民: 采集资源 - 剩余生命值: ", target_resource.current_health)
				var done = target_resource.gather(30.0, self)
				if done:
					if DEBUG_VILLAGER_LOGS:
						print("村民: 资源已被采集完毕")
					var job_mgr = get_node_or_null("/root/JobManager")
					if job_mgr: job_mgr.remove_job(target_resource)
					current_task = Task.IDLE
					path.clear()
					if tool_sprite: tool_sprite.visible = false
					_event_bus.villager_task_completed.emit(self)
					_event_bus.villager_idle.emit(self)
	else:
		if DEBUG_VILLAGER_LOGS:
			print("村民: 距离资源太远，无法采集 - 距离: ", dist_to_res)

func _get_tool_level_for_resource(resource: Node2D) -> int:
	if not is_instance_valid(resource):
		return 0
	var inv = get_node_or_null("/root/InventoryManager")
	if not inv and inventory.is_empty():
		return 0
	var resource_type = int(resource.get("type") if "type" in resource else 0)
	# 纤维（草）使用空手采集
	if resource_type == 3:
		return 0
	if resource_type == 1:
		if equipped_tool_id == "stone_pickaxe" and int(inventory.get("stone_pickaxe", 0)) > 0:
			return 2
		if equipped_tool_id == "wood_pickaxe" and int(inventory.get("wood_pickaxe", 0)) > 0:
			return 1
	else:
		if equipped_tool_id == "stone_axe" and int(inventory.get("stone_axe", 0)) > 0:
			return 2
		if equipped_tool_id == "wood_axe" and int(inventory.get("wood_axe", 0)) > 0:
			return 1
	return 0

func add_tool_to_inventory(tool_id: String, amount: int = 1, auto_equip: bool = true) -> void:
	if tool_id == "":
		return
	if not can_add_tool(tool_id):
		return
	inventory[tool_id] = int(inventory.get(tool_id, 0)) + amount
	if auto_equip:
		equip_tool(tool_id)

func can_add_tool(tool_id: String) -> bool:
	var group = _get_exclusive_tool_group(tool_id)
	if group == "":
		return true
	for id in inventory.keys():
		if int(inventory[id]) > 0 and _get_exclusive_tool_group(str(id)) == group:
			return false
	return true

func equip_tool(tool_id: String) -> bool:
	if tool_id == "" or tool_id == "bandage" or tool_id == "arrow":
		return false
	if int(inventory.get(tool_id, 0)) <= 0:
		return false
	equipped_tool_id = tool_id
	return true

func _get_exclusive_tool_group(tool_id: String) -> String:
	match tool_id:
		"wood_sword", "stone_sword", "bow":
			return "weapon"
		"wood_axe", "stone_axe":
			return "axe"
		"wood_pickaxe", "stone_pickaxe":
			return "pickaxe"
		"fishing_rod":
			return "fishing_rod"
		_:
			return ""

func remove_tool_from_inventory(tool_id: String, amount: int = 1) -> bool:
	if int(inventory.get(tool_id, 0)) < amount:
		return false
	inventory[tool_id] = int(inventory.get(tool_id, 0)) - amount
	if int(inventory[tool_id]) <= 0:
		inventory.erase(tool_id)
		if equipped_tool_id == tool_id:
			equipped_tool_id = ""
	return true

func get_inventory_tools() -> Dictionary:
	return inventory.duplicate()

func use_bandage_on(target: Node) -> bool:
	if int(inventory.get("bandage", 0)) <= 0:
		return false
	if not is_instance_valid(target) or not ("is_unconscious" in target) or not bool(target.get("is_unconscious")):
		return false
	if not remove_tool_from_inventory("bandage", 1):
		return false
	if target.has_method("set_unconscious"):
		target.set_unconscious(false)
	else:
		target.set("is_unconscious", false)
	return true

func _get_tool_texture_path(resource: Node2D, level: int) -> String:
	if level <= 0 or not is_instance_valid(resource):
		return ""
	var resource_type = int(resource.get("type") if "type" in resource else 0)
	if resource_type == 1:
		return "res://art/a/tools/pickaxe2.png" if level >= 2 else "res://art/a/tools/pickaxe1.png"
	return "res://art/a/tools/axe2.png" if level >= 2 else "res://art/a/tools/axe1.png"

func _get_weapon_texture_path() -> String:
	if equipped_tool_id == "bow" and int(inventory.get("bow", 0)) > 0 and int(inventory.get("arrow", 0)) > 0:
		return "res://art/tools/bow.svg"
	if equipped_tool_id == "stone_sword" and int(inventory.get("stone_sword", 0)) > 0:
		return "res://art/a/tools/spear2.png"
	if equipped_tool_id == "wood_sword" and int(inventory.get("wood_sword", 0)) > 0:
		return "res://art/a/tools/spear1.png"
	return ""

func _get_weapon_sprite_scale() -> Vector2:
	if equipped_tool_id == "bow" and int(inventory.get("bow", 0)) > 0:
		return Vector2(0.55, 0.55)
	if equipped_tool_id == "stone_sword" and int(inventory.get("stone_sword", 0)) > 0:
		return Vector2(3.2, 3.2)
	if equipped_tool_id == "wood_sword" and int(inventory.get("wood_sword", 0)) > 0:
		return Vector2(1.8, 1.8)
	return Vector2(2.0, 2.0)

func _get_attack_range() -> float:
	if equipped_tool_id == "bow" and int(inventory.get("bow", 0)) > 0 and int(inventory.get("arrow", 0)) > 0:
		return BOW_ATTACK_RANGE
	return ATTACK_RANGE

func _get_melee_attack_damage() -> float:
	if equipped_tool_id == "stone_sword" and int(inventory.get("stone_sword", 0)) > 0:
		return STONE_SWORD_ATTACK_DAMAGE
	if equipped_tool_id == "wood_sword" and int(inventory.get("wood_sword", 0)) > 0:
		return WOOD_SWORD_ATTACK_DAMAGE
	return UNARMED_ATTACK_DAMAGE

func _fire_arrow_at(target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	var parent = get_parent()
	if not parent:
		return

	var arrow = Sprite2D.new()
	arrow.texture = load("res://art/tools/arrow.svg")
	arrow.scale = Vector2(0.28, 0.28)
	arrow.z_index = 120
	arrow.global_position = global_position + Vector2(0, -8)
	var direction = target.global_position - arrow.global_position
	if direction.length() > 0.001:
		arrow.rotation = direction.angle()
	parent.add_child(arrow)
	_animate_arrow_projectile(arrow, target)

func _animate_arrow_projectile(arrow: Sprite2D, target: Node2D) -> void:
	var start_pos = arrow.global_position
	var target_pos = target.global_position
	var hit_pos = _get_arrow_hit_position(start_pos, target_pos)
	var blocked = hit_pos.distance_squared_to(target_pos) > 4.0
	var duration = start_pos.distance_to(hit_pos) / ARROW_FLIGHT_SPEED

	var tween = create_tween()
	tween.tween_property(arrow, "global_position", hit_pos, max(0.05, duration))
	tween.tween_callback(func():
		if is_instance_valid(arrow):
			arrow.queue_free()
		if not blocked and is_instance_valid(target) and target.has_method("take_damage"):
			target.take_damage(BOW_ATTACK_DAMAGE)
	)

func _get_arrow_hit_position(start_pos: Vector2, target_pos: Vector2) -> Vector2:
	var tilemap = _get_tilemap_layer()
	if not tilemap or not ("astar_grid" in tilemap) or not tilemap.astar_grid:
		return target_pos

	var delta = target_pos - start_pos
	var distance = delta.length()
	if distance <= 0.001:
		return target_pos

	var steps = max(1, int(ceil(distance / 6.0)))
	var last_pos = start_pos
	for i in range(1, steps + 1):
		var t = float(i) / float(steps)
		var pos = start_pos.lerp(target_pos, t)
		var cell = tilemap.local_to_map(tilemap.to_local(pos))
		if not tilemap.astar_grid.is_in_boundsv(cell):
			return last_pos
		if _is_arrow_blocked_cell(tilemap, cell):
			var target_cell = tilemap.local_to_map(tilemap.to_local(target_pos))
			if cell != target_cell:
				return last_pos
		last_pos = pos

	return target_pos

func _is_arrow_blocked_cell(tilemap: Node, cell: Vector2i) -> bool:
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building):
			continue
		if not ("grid_coord" in building) or building.grid_coord != cell:
			continue
		if not bool(building.get("blocks_arrows") if "blocks_arrows" in building else true):
			return false
		if "is_open" in building and bool(building.get("is_open")):
			return false
		return true
	return tilemap.astar_grid.is_point_solid(cell)

func _cell_has_arrow_blocking_building(cell: Vector2i) -> bool:
	for building in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(building):
			continue
		if not ("grid_coord" in building) or building.grid_coord != cell:
			continue
		if not bool(building.get("blocks_arrows") if "blocks_arrows" in building else true):
			return false
		if "is_open" in building and bool(building.get("is_open")):
			return false
		return true
	return false

func _process_haul_step() -> void:
	if carried_item == null:
		if not is_instance_valid(target_resource): 
			current_task = Task.IDLE
			_event_bus.villager_task_completed.emit(self)
			_event_bus.villager_idle.emit(self)
			return
			
		carried_item = target_resource
		var parent = carried_item.get_parent()
		if parent: parent.remove_child(carried_item)
		add_child(carried_item)
		carried_item.position = Vector2(0, -12)
		carried_item.scale = Vector2(1.0, 1.0)
		
		var tilemap = _get_tilemap_layer()
		if tilemap:
			var start_coord = tilemap.local_to_map(global_position)
			var id_path = tilemap.get_path_coords(start_coord, haul_target_cell, true)
			if id_path.size() > 0:
				var world_path: Array[Vector2] = []
				for coord in id_path:
					world_path.append(tilemap.map_to_local(coord))
				if world_path.size() > 1:
					world_path.remove_at(0)
				_set_path(world_path)
			else:
				_drop_item_at(start_coord)
	else:
		_drop_item_at(haul_target_cell)

func _search_for_job() -> void:
	if energy <= SLEEP_THRESHOLD:
		var bed = _find_nearest_bed()
		if bed:
			var tilemap = _get_tilemap_layer()
			if tilemap:
				var start_c = tilemap.local_to_map(global_position)
				var end_c = tilemap.local_to_map(tilemap.to_local(bed.global_position))
				var id_path = tilemap.get_path_coords(start_c, end_c, true)
				if id_path.size() > 0:
					var world_path: Array[Vector2] = []
					for c in id_path:
						world_path.append(tilemap.map_to_local(c))
					if world_path.size() > 1:
						world_path.remove_at(0)
					command_sleep(world_path, bed)
					return

	if hunger <= 35.0:
		var food = _find_nearest_food()
		if food:
			var tilemap = _get_tilemap_layer()
			if tilemap:
				var start_c = tilemap.local_to_map(global_position)
				var end_c = food.grid_coord if "grid_coord" in food else tilemap.local_to_map(food.global_position)
				var id_path = tilemap.get_path_coords(start_c, end_c, true)
				if id_path.size() > 0:
					var world_path: Array[Vector2] = []
					for c in id_path: world_path.append(tilemap.map_to_local(c))
					if world_path.size() > 1: world_path.remove_at(0)
					command_eat(world_path, food)
					return

	var job_mgr = get_node_or_null("/root/JobManager")
	if job_mgr:
		var job = job_mgr.get_best_job(global_position, self)
		if not job.is_empty():
			var type = job["type"]
			var target = job["target"]
			
			var tilemap = _get_tilemap_layer()
			if tilemap and is_instance_valid(target):
				var start_c = tilemap.local_to_map(global_position)
				var end_c = tilemap.local_to_map(target.global_position)
				if type == "GATHER" and "grid_coord" in target:
					end_c = target.grid_coord
				var id_path = tilemap.get_path_coords(start_c, end_c, true)
				if id_path.size() > 0:
					var world_path: Array[Vector2] = []
					for c in id_path: world_path.append(tilemap.map_to_local(c))
					if world_path.size() > 1: world_path.remove_at(0)
					
					if type == "GATHER":
						command_gather(world_path, target)
					elif type == "HUNT":
						command_attack(world_path, target)
					elif type == "CRAFT":
						command_craft(world_path, target, str(job.get("recipe_id", "")))
					return
				else:
					job_mgr.remove_job(target)
					EventBus.alert_message.emit(" %s 发现目标无法抵达，系统已撤销该任务。" % name)

	var farm_mgr = get_node_or_null("/root/FarmManager")
	if farm_mgr:
		var tilemap = _get_tilemap_layer()
		if tilemap:
			var plot = farm_mgr.find_best_work_plot(global_position, tilemap)
			if not plot.is_empty():
				var work_cell: Vector2i = farm_mgr.get_best_work_cell(plot, global_position, tilemap) if farm_mgr.has_method("get_best_work_cell") else Vector2i(-99999, -99999)
				var cells: Array = [work_cell] if work_cell.x != -99999 else []
				var start_c = tilemap.local_to_map(tilemap.to_local(global_position))
				var best_cell = Vector2i(-99999, -99999)
				var best_path: Array = []
				for cell in cells:
					var id_path = tilemap.get_path_coords(start_c, cell, true)
					if id_path.size() > 0 and (best_path.is_empty() or id_path.size() < best_path.size()):
						best_path = id_path
						best_cell = cell
				if not best_path.is_empty():
					var plot_id = int(plot.get("id", -1))
					if farm_mgr.has_method("reserve_plot") and not farm_mgr.reserve_plot(plot_id, name, best_cell):
						return
					var world_path: Array[Vector2] = []
					for c in best_path:
						world_path.append(tilemap.map_to_local(c))
					if world_path.size() > 1:
						world_path.remove_at(0)
					command_work(world_path, plot_id, best_cell)
					return

	if int(inventory.get("fishing_rod", 0)) > 0:
		var fishing_spot = _find_nearest_fishing_spot()
		if not fishing_spot.is_empty():
			command_fish(fishing_spot.get("path", []), fishing_spot.get("shore", Vector2i(-99999, -99999)), fishing_spot.get("water", Vector2i(-99999, -99999)))
			return

	if not _haul_manager: return

	var best_item = _haul_manager.find_best_haul_job(global_position)

	if best_item:
		var empty_cell = _haul_manager.get_empty_stockpile_cell()
		if empty_cell.x != -99999:
			best_item.set("is_reserved", true)
			command_haul(best_item, empty_cell)

func _clear_targets() -> void:
	if carried_item: _drop_current_item()
	_release_target_farm()
	_restore_sleep_pose()
	if current_task == Task.HAUL and target_resource and carried_item == null:
		target_resource.set("is_reserved", false)
	
	var job_mgr = get_node_or_null("/root/JobManager")
	if job_mgr:
		if current_task == Task.GATHER and target_resource:
			job_mgr.abandon_job(target_resource)
		elif current_task == Task.ATTACK and target_animal:
			job_mgr.abandon_job(target_animal)
		elif current_task == Task.CRAFT and target_workbench:
			job_mgr.abandon_job(target_workbench)
			
	target_resource = null
	target_animal = null
	target_food = null
	target_fishing_cell = Vector2i(-99999, -99999)
	target_water_cell = Vector2i(-99999, -99999)
	fishing_timer_minutes = 0.0
	target_bed = null
	target_farm_plot_id = -1
	target_farm_cell = Vector2i(-99999, -99999)
	target_workbench = null
	target_recipe_id = ""
	craft_timer_minutes = 0.0
	if tool_sprite: tool_sprite.visible = false
	path.clear()

func _find_nearest_bed() -> Node2D:
	var best: Node2D = null
	var min_dist = INF
	var room_mgr = get_node_or_null("/root/RoomManager")
	for bed in get_tree().get_nodes_in_group("beds"):
		if not is_instance_valid(bed):
			continue
		if room_mgr and room_mgr.has_method("can_use_bed") and not room_mgr.can_use_bed(bed, name):
			continue
		var d = global_position.distance_to(bed.global_position)
		if d < min_dist:
			min_dist = d
			best = bed
	return best

func _find_nearest_fishing_spot() -> Dictionary:
	var tilemap = _get_tilemap_layer()
	if not tilemap or not ("astar_grid" in tilemap) or not tilemap.astar_grid:
		return {}
	var start_c = tilemap.local_to_map(tilemap.to_local(global_position))
	var best: Dictionary = {}
	var best_len = INF
	for radius in range(1, 18):
		for x in range(start_c.x - radius, start_c.x + radius + 1):
			for y in range(start_c.y - radius, start_c.y + radius + 1):
				if abs(x - start_c.x) != radius and abs(y - start_c.y) != radius:
					continue
				var shore = Vector2i(x, y)
				if not tilemap.astar_grid.is_in_boundsv(shore) or tilemap.astar_grid.is_point_solid(shore):
					continue
				var water = _get_adjacent_water_cell(tilemap, shore)
				if water.x == -99999:
					continue
				var id_path = tilemap.get_path_coords(start_c, shore, false)
				if id_path.is_empty() or id_path.size() >= best_len:
					continue
				var world_path: Array[Vector2] = []
				for c in id_path:
					world_path.append(tilemap.map_to_local(c))
				if world_path.size() > 1:
					world_path.remove_at(0)
				best = {"shore": shore, "water": water, "path": world_path}
				best_len = id_path.size()
		if not best.is_empty():
			return best
	return best

func _get_adjacent_water_cell(tilemap: Node, shore: Vector2i) -> Vector2i:
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var cell = shore + d
		if _is_water_cell(tilemap, cell):
			return cell
	return Vector2i(-99999, -99999)

func _is_water_cell(tilemap: Node, cell: Vector2i) -> bool:
	if tilemap.has_method("is_water_cell"):
		return tilemap.is_water_cell(cell)
	if tilemap.has_method("get_cell_atlas_coords"):
		return tilemap.get_cell_atlas_coords(cell) == Vector2i(1, 1)
	return false

func command_eat(new_path: Array[Vector2], food: Node2D) -> void:
	if is_unconscious:
		return
	_clear_targets()
	current_task = Task.EAT
	_set_path(new_path)
	target_food = food
	if "is_reserved" in food: food.is_reserved = true
	gather_timer = 0.0

func _handle_eating(delta: float) -> void:
	if not is_instance_valid(target_food) or (target_food.amount if "amount" in target_food else 1) <= 0:
		current_task = Task.IDLE
		_event_bus.villager_idle.emit(self)
		return
		
	var dist = global_position.distance_to(target_food.global_position)
	if dist <= EAT_RANGE:
		gather_timer += delta
		if gather_timer >= 2.0:
			gather_timer = 0.0
			hunger = min(max_hunger, hunger + 60.0)
			
			if "amount" in target_food: target_food.amount -= 1
			EventBus.alert_message.emit(" %s 吃了一份食物" % name)
			
			var is_in_stockpile = target_food in _haul_manager.get_stockpile_items() if _haul_manager else false
			if is_in_stockpile:
				_event_bus.resource_consumed.emit(2, 1)
			
			if ("amount" in target_food and target_food.amount <= 0) or not "amount" in target_food:
				if _haul_manager: _haul_manager.unregister_item(target_food)
				target_food.queue_free()
			else:
				if "is_reserved" in target_food: target_food.is_reserved = false
				
			current_task = Task.IDLE
			_event_bus.villager_idle.emit(self)

func _find_nearest_food() -> Node2D:
	if not _haul_manager: return null
	var best = null
	var min_dist = INF
	
	for item in _haul_manager.get_stockpile_items():
		if is_instance_valid(item) and item.get("type") == 2:
			var d = global_position.distance_to(item.global_position)
			if d < min_dist:
				min_dist = d
				best = item
				
	for item in _haul_manager.get_unhauled_items():
		if is_instance_valid(item) and ("type" in item and item.type == 2) and not ("is_reserved" in item and item.is_reserved):
			var d = global_position.distance_to(item.global_position)
			if d < min_dist:
				min_dist = d
				best = item
				
	return best

func _drop_current_item() -> void:
	var tilemap = _get_tilemap_layer()
	if tilemap:
		var cur_cell = tilemap.local_to_map(global_position)
		_drop_item_at(cur_cell)

func _drop_item_at(drop_cell: Vector2i) -> void:
	if carried_item and is_instance_valid(carried_item):
		var tilemap = _get_tilemap_layer()
		remove_child(carried_item)
		if tilemap:
			tilemap.add_child(carried_item)
			carried_item.scale = Vector2(1,1)
			carried_item.global_position = tilemap.map_to_local(drop_cell)
		carried_item.set("is_reserved", false)

		if _haul_manager and _haul_manager.is_stockpile_cell(drop_cell):
			_haul_manager.store_item(carried_item, drop_cell)
		else:
			carried_item.set("grid_coord", drop_cell)
			if _haul_manager:
				_haul_manager.register_item(carried_item)

	carried_item = null
	current_task = Task.IDLE
	_event_bus.villager_task_completed.emit(self)
	_event_bus.villager_idle.emit(self)

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var map_node = get_tree().current_scene
		if map_node.has_method("select_villager"):
			map_node.select_villager(self)
		get_viewport().set_input_as_handled()
