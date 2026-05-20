extends StaticBody2D
class_name ResourceNode

# 整合：保留旧版本的 MEAT 枚举类型（顺序需与 ItemDrop.gd 一致）
enum ResourceType { TREE, ROCK, MEAT }

@export var type: ResourceType = ResourceType.TREE
@export var max_health: float = 100.0
@export var gather_yield: int = 15

var current_health: float
var grid_coord: Vector2i

func _ready() -> void:
	current_health = max_health
	input_pickable = true
	
	var tex_path = ""
	var fallback_color = Color()
	
	# 整合：结合旧版本的类型配置 + 新版本的分组逻辑
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
			tex_path = "res://art/animals/meat_source.png"
			fallback_color = Color(0.8, 0.2, 0.2)
			name = "MeatSource"
	
	# 整合：保留新版本的美术素材检查逻辑
	if FileAccess.file_exists(tex_path) or FileAccess.file_exists(tex_path + ".import"):
		var sprite = Sprite2D.new()
		sprite.texture = load(tex_path)
		add_child(sprite)
	else:
		# 整合：保留新版本的 16x16 占位尺寸（与主脚本匹配）
		var visual = ColorRect.new()
		visual.size = Vector2(16, 16)
		visual.position = Vector2(-8, -8)
		visual.color = fallback_color
		visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(visual)
	
	# 整合：保留新版本的 16x16 碰撞盒尺寸
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(16, 16)
	collision.shape = shape
	add_child(collision)

# 整合：保留新版本的 gather 函数结构 + 旧版本的逻辑分离
func gather(amount: float, gatherer: Node2D) -> bool:
	current_health -= amount
	
	# 保留新版本的受击视觉反馈
	var tween = create_tween().set_trans(Tween.TRANS_SPRING)
	scale = Vector2(0.9, 0.9)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)
	
	if current_health <= 0:
		_on_depleted()
		return true
		
	return false

# 整合：保留旧版本的 _on_depleted 逻辑分离 + 新版本的掉落物生成方式
func _on_depleted() -> void:
	var tilemap = get_parent()
	
	# 1. 释放地图格子的阻挡状态
	if tilemap and tilemap.has_method("remove_solid"):
		tilemap.remove_solid(grid_coord)
	
	# 2. 产生掉落物（保留新版本的直接 new() 方式）
	var item_drop = load("res://ItemDrop.gd").new()
	item_drop.item_type = type
	item_drop.amount = gather_yield
	item_drop.grid_coord = grid_coord
	item_drop.global_position = global_position
	if tilemap:
		tilemap.add_child(item_drop)
	
	# 3. 销毁资源点节点
	queue_free()

# 整合：保留旧版本的 match 结构，更简洁
func get_interaction_name() -> String:
	match type:
		ResourceType.TREE: return "可以砍伐的树"
		ResourceType.ROCK: return "可以开采的岩石"
		ResourceType.MEAT: return "食物来源"
	return "未知资源"
