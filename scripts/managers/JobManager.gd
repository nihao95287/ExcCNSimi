extends Node

signal job_added(type, target)
signal job_completed(target)

# job object: { "type": "GATHER"|"ATTACK", "target": Node2D, "assigned_to": Villager (or null) }
var jobs_queue: Array[Dictionary] = []

const BASIC_RECIPES := {
	"bandage": {
		"name": "绷带",
		"desc": "对昏迷村民使用后，可以立刻让其恢复行动。",
		"time_minutes": 14.0,
		"cost": {"fiber": 8},
		"icon": "res://art/tools/bandage.svg",
		"tier": "basic",
	},
	"wood_sword": {
		"name": "木剑",
		"desc": "提高捕猎速度，适合早期狩猎。",
		"time_minutes": 24.0,
		"cost": {"wood": 14, "fiber": 3},
		"icon": "res://art/a/tools/spear1.png",
		"tier": "basic",
	},
	"bow": {
		"name": "弓",
		"desc": "远距离捕猎武器，需要箭才能攻击。",
		"time_minutes": 28.0,
		"cost": {"wood": 12, "fiber": 6},
		"icon": "res://art/tools/bow.svg",
		"tier": "basic",
	},
	"arrow": {
		"name": "箭 x10",
		"desc": "弓的弹药。每 2 根箭消耗 1 木头和 1 纤维。",
		"time_minutes": 16.0,
		"cost": {"wood": 5, "fiber": 5},
		"icon": "res://art/tools/arrow.svg",
		"tier": "basic",
		"output_amount": 10,
	},
	"fishing_rod": {
		"name": "钓鱼竿",
		"desc": "携带后，村民可以在水边自动钓鱼并获得食物。",
		"time_minutes": 22.0,
		"cost": {"wood": 8, "fiber": 6},
		"icon": "res://art/tools/fishing_rod.svg",
		"tier": "basic",
	},
}

const WORKBENCH_RECIPES := {
	"wood_axe": {
		"name": "木斧头",
		"desc": "砍树和采集纤维更快，采集时显示斧头动画。",
		"time_minutes": 18.0,
		"cost": {"wood": 10, "fiber": 2},
		"icon": "res://art/a/tools/axe1.png",
		"tier": "workbench",
	},
	"wood_pickaxe": {
		"name": "木稿子",
		"desc": "采集石头更快，采集时显示稿子动画。",
		"time_minutes": 22.0,
		"cost": {"wood": 12, "fiber": 2},
		"icon": "res://art/a/tools/pickaxe1.png",
		"tier": "workbench",
	},
	"stone_axe": {
		"name": "石斧头",
		"desc": "比木斧头更快地砍树和采集纤维。",
		"time_minutes": 34.0,
		"cost": {"wood": 10, "stone": 15, "fiber": 3},
		"icon": "res://art/a/tools/axe2.png",
		"tier": "workbench",
	},
	"stone_pickaxe": {
		"name": "石稿子",
		"desc": "比木稿子更快地采集石头。",
		"time_minutes": 38.0,
		"cost": {"wood": 10, "stone": 18, "fiber": 3},
		"icon": "res://art/a/tools/pickaxe2.png",
		"tier": "workbench",
	},
	"stone_sword": {
		"name": "石剑",
		"desc": "比木剑更适合捕猎，能明显缩短战斗时间。",
		"time_minutes": 36.0,
		"cost": {"wood": 10, "stone": 16, "fiber": 4},
		"icon": "res://art/a/tools/spear2.png",
		"tier": "workbench",
	},
}

# 合并后的完整配方表（兼容旧代码）
var CRAFT_RECIPES: Dictionary = {}

func _ready() -> void:
	CRAFT_RECIPES = BASIC_RECIPES.duplicate()
	CRAFT_RECIPES.merge(WORKBENCH_RECIPES)

func get_recipe_ids() -> Array:
	return CRAFT_RECIPES.keys()

func get_basic_recipe_ids() -> Array:
	return BASIC_RECIPES.keys()

func get_workbench_recipe_ids() -> Array:
	return WORKBENCH_RECIPES.keys()

func is_basic_recipe(recipe_id: String) -> bool:
	return BASIC_RECIPES.has(recipe_id)

func has_workbench_in_world() -> bool:
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and bool(b.get("is_workbench") if "is_workbench" in b else false):
			return true
	return false

func find_nearest_workbench(world_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist = INF
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b):
			continue
		if not bool(b.get("is_workbench") if "is_workbench" in b else false):
			continue
		var d = world_pos.distance_to(b.global_position)
		if d < best_dist:
			best_dist = d
			best = b
	return best

func get_craft_recipe(recipe_id: String) -> Dictionary:
	return CRAFT_RECIPES.get(recipe_id, {})

func add_job(type: String, target: Node2D) -> void:
	# 检查是否重复
	for j in jobs_queue:
		if j["target"] == target:
			return # 已经有任务了
			
	jobs_queue.append({
		"type": type,
		"target": target,
		"assigned_to": null
	})
	
	if not target.has_node("JobMarker"):
		var marker = Label.new()
		marker.name = "JobMarker"
		marker.text = "⛏️" if (type == "GATHER" and target.get("type") == 1) else "🪓" if type == "GATHER" else "⚔️"
		if type == "HUNT":
			marker.position = Vector2(-5, -18)
			marker.scale = Vector2(0.45, 0.45)
		else:
			marker.position = Vector2(-20, -40)
			marker.scale = Vector2(2, 2)
		target.add_child(marker)
		
	job_added.emit(type, target)

func has_job(target: Node2D) -> bool:
	for job in jobs_queue:
		if job.get("target") == target:
			return true
	return false

func add_craft_job(recipe_id: String, target: Node2D) -> bool:
	if recipe_id == "" or not CRAFT_RECIPES.has(recipe_id) or not is_instance_valid(target):
		return false

	for j in jobs_queue:
		if j.get("type", "") == "CRAFT" and j.get("target") == target:
			return false

	jobs_queue.append({
		"type": "CRAFT",
		"target": target,
		"recipe_id": recipe_id,
		"progress_minutes": 0.0,
		"assigned_to": null
	})

	if not target.has_node("JobMarker"):
		var marker = Label.new()
		marker.name = "JobMarker"
		marker.text = "合成"
		marker.position = Vector2(-16, -36)
		marker.scale = Vector2(0.9, 0.9)
		target.add_child(marker)

	_ensure_craft_progress_bar(target)

	job_added.emit("CRAFT", target)
	return true

func get_craft_progress(target: Node2D) -> float:
	for job in jobs_queue:
		if job.get("type", "") == "CRAFT" and job.get("target") == target:
			return float(job.get("progress_minutes", 0.0))
	return 0.0

func add_craft_progress(target: Node2D, minutes: float) -> float:
	for i in range(jobs_queue.size()):
		var job = jobs_queue[i]
		if job.get("type", "") == "CRAFT" and is_instance_valid(job.get("target")) and job.get("target") == target:
			var recipe = get_craft_recipe(str(job.get("recipe_id", "")))
			var total = float(recipe.get("time_minutes", 1.0))
			var next_progress = clamp(float(job.get("progress_minutes", 0.0)) + minutes, 0.0, total)
			job["progress_minutes"] = next_progress
			jobs_queue[i] = job
			_update_craft_progress_bar(target, next_progress, total)
			return next_progress
	return -1.0

func _update_craft_progress_bar(target: Node2D, progress_minutes: float, total_minutes: float) -> void:
	if not is_instance_valid(target):
		return
	_ensure_craft_progress_bar(target)
	var fill = target.get_node_or_null("CraftProgress/Fill") as ColorRect
	if fill:
		var pct = clamp(progress_minutes / max(total_minutes, 0.001), 0.0, 1.0)
		fill.size = Vector2(46.0 * pct, 5)

func _ensure_craft_progress_bar(target: Node2D) -> void:
	if not is_instance_valid(target):
		return
	var old_bar = target.get_node_or_null("CraftProgressBar")
	if old_bar:
		old_bar.queue_free()
	if target.has_node("CraftProgress"):
		return

	var root = Node2D.new()
	root.name = "CraftProgress"
	root.position = Vector2(0, 24)
	root.z_index = 80
	target.add_child(root)

	var back = ColorRect.new()
	back.name = "Back"
	back.color = Color(0.02, 0.02, 0.025, 0.9)
	back.size = Vector2(50, 9)
	back.position = Vector2(-25, -4)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(back)

	var fill = ColorRect.new()
	fill.name = "Fill"
	fill.color = Color(0.35, 0.85, 1.0, 0.95)
	fill.size = Vector2(0, 5)
	fill.position = Vector2(-23, -2)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)

	var border = ColorRect.new()
	border.name = "Border"
	border.color = Color(1.0, 1.0, 1.0, 0.35)
	border.size = Vector2(50, 1)
	border.position = Vector2(-25, -4)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(border)

func get_best_job(villager_pos: Vector2, villager: Node) -> Dictionary:
	var best_job = {}
	var min_dist = INF
	
	var skill_woodcut = villager.get("skill_woodcut") if "skill_woodcut" in villager else 1
	var skill_mining = villager.get("skill_mining") if "skill_mining" in villager else 1
	var skill_melee = villager.get("skill_melee") if "skill_melee" in villager else 1
	
	# Cleanup invalid jobs and find best
	for i in range(jobs_queue.size() - 1, -1, -1):
		if not is_instance_valid(jobs_queue[i]["target"]):
			jobs_queue.remove_at(i)
			continue
			
		var job = jobs_queue[i]
		if job["assigned_to"] != null:
			continue
			
		var target = job["target"]
		var dist = villager_pos.distance_to(target.global_position)
		
		# Skill weighting: 
		if job["type"] == "GATHER" and target.get("type") == 1:
			dist -= skill_mining * 70.0
		elif job["type"] == "GATHER":
			dist -= skill_woodcut * 70.0
		elif job["type"] == "HUNT":
			dist -= skill_melee * 70.0
			
		if dist < min_dist:
			min_dist = dist
			best_job = job
				
	if not best_job.is_empty():
		best_job["assigned_to"] = villager
		return best_job
		
	return {}

func remove_job(target: Node2D) -> void:
	if is_instance_valid(target):
		var marker = target.get_node_or_null("JobMarker")
		if marker:
			marker.queue_free()
		var bar = target.get_node_or_null("CraftProgressBar")
		if bar:
			bar.queue_free()
		var craft_progress = target.get_node_or_null("CraftProgress")
		if craft_progress:
			craft_progress.queue_free()
			
	for i in range(jobs_queue.size() - 1, -1, -1):
		if jobs_queue[i]["target"] == target:
			jobs_queue.remove_at(i)
			job_completed.emit(target)
			break

func abandon_job(target: Node2D) -> void:
	for job in jobs_queue:
		if job["target"] == target:
			job["assigned_to"] = null
			break
