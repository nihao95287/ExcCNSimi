class_name ResourceNode
extends StaticBody2D

enum ResourceType { TREE, ROCK, MEAT, FIBER }

@export var type: ResourceType = ResourceType.TREE
@export var max_health: float = 100.0
@export var gather_yield: int = 15

var current_health: float
var grid_coord: Vector2i

const ITEM_DROP_SCENE = preload("res://scenes/ItemDrop.tscn")
var DEBUG_RESOURCE_NODE_LOGS: bool:
	get: return SettingsManager.settings.get("debug_logs", false)

func _ready() -> void:
	current_health = max_health
	input_pickable = true

	var tex_path = ""
	var fallback_color = Color()
	
	match type:
		ResourceType.TREE:
			tex_path = "res://art/objects/tree.png"
			fallback_color = Color(0.2, 0.6, 0.2)
			add_to_group("trees")
			name = "Tree"
		ResourceType.ROCK:
			tex_path = "res://art/objects/rock.png"
			fallback_color = Color(0.5, 0.5, 0.5)
			add_to_group("rocks")
			name = "Rock"
		ResourceType.MEAT:
			tex_path = "res://art/animals/pig.png"
			fallback_color = Color(0.9, 0.2, 0.2)
			name = "MeatSource"
		ResourceType.FIBER:
			tex_path = "res://art/objects/grass.png"
			fallback_color = Color(0.45, 0.85, 0.35)  # 亮黄绿
			add_to_group("fibers")
			add_to_group("trees")  # 和树共用相同的采集逻辑
			name = "Fiber"
	
	if FileAccess.file_exists(tex_path) or FileAccess.file_exists(tex_path + ".import"):
		var sprite = Sprite2D.new()
		sprite.texture = load(tex_path)
		sprite.scale = Vector2(0.5, 0.5)
		add_child(sprite)
	else:
		var visual = ColorRect.new()
		visual.size = Vector2(16, 16)
		visual.position = Vector2(-8, -8)
		visual.color = fallback_color
		visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(visual)
	
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(16, 16)
	collision.shape = shape
	add_child(collision)

func gather(amount: float, gatherer: Node2D) -> bool:
	if DEBUG_RESOURCE_NODE_LOGS:
		print("ResourceNode.gather() 被调用! current_health=", current_health, " amount=", amount, " name=", name)
	current_health -= amount
	
	# 触发采集音效信号
	EventBus.resource_hit.emit(type)

	var tween = create_tween().set_trans(Tween.TRANS_SPRING)
	scale = Vector2(0.9, 0.9)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)

	if DEBUG_RESOURCE_NODE_LOGS:
		print("  扣除后 current_health=", current_health)
	if current_health <= 0:
		if DEBUG_RESOURCE_NODE_LOGS:
			print("  生命值 <= 0，调用 _on_destroyed()")
		_on_destroyed()
		if DEBUG_RESOURCE_NODE_LOGS:
			print("  _on_destroyed() 执行完毕，当前节点是否有效: ", is_instance_valid(self))
		return true

	return false

func _on_destroyed() -> void:
	if DEBUG_RESOURCE_NODE_LOGS:
		print("ResourceNode: _on_destroyed() 被调用!")
		print("  - type: ", type)
		print("  - gather_yield: ", gather_yield)
		print("  - grid_coord: ", grid_coord)
		print("  - global_position: ", global_position)

	var parent = get_parent()
	if DEBUG_RESOURCE_NODE_LOGS:
		print("  - parent: ", parent)
	if parent and parent.has_method("remove_solid"):
		parent.remove_solid(grid_coord)

	# 生成物品掉落
	if DEBUG_RESOURCE_NODE_LOGS:
		print("  - 尝试生成物品掉落...")
	if gather_yield > 0:
		if DEBUG_RESOURCE_NODE_LOGS:
			print("  - ITEM_DROP_SCENE: ", ITEM_DROP_SCENE)
		var drop = ITEM_DROP_SCENE.instantiate()
		if DEBUG_RESOURCE_NODE_LOGS:
			print("  - drop: ", drop)
		if drop:
			drop.type = type
			drop.amount = gather_yield
			drop.grid_coord = grid_coord
			drop.z_index = 100
			drop.global_position = global_position + Vector2(16, 16)
			if parent:
				parent.add_child(drop)
				if DEBUG_RESOURCE_NODE_LOGS:
					print("  - ItemDrop已添加，位置: ", drop.global_position)
					print("  - ItemDrop子节点数: ", drop.get_child_count())
					for i in range(drop.get_child_count()):
						var child = drop.get_child(i)
						print("    子节点", i, ": ", child.name, " type=", child.get_class())
				EventBus.item_dropped.emit(drop, type, gather_yield)
				if DEBUG_RESOURCE_NODE_LOGS:
					print("  - 物品掉落已生成并添加到场景")

	EventBus.resource_destroyed.emit(type)
	EventBus.resource_node_removed.emit(type, grid_coord.x, grid_coord.y)
	if DEBUG_RESOURCE_NODE_LOGS:
		print("  - 调用 queue_free()，资源节点将被释放")
		print("  - 资源节点名称: ", name, " 类型: ", get_class())
		print("  - 资源节点父节点: ", get_parent())
		print("  - 调用 queue_free() 之前，is_inside_tree(): ", is_inside_tree())
	queue_free()
	if DEBUG_RESOURCE_NODE_LOGS:
		print("  - queue_free() 已调用")
