extends Node2D
class_name ItemDrop

# 这里的枚举顺序必须与 ResourceNode 里的 ResourceType 一致
# 0: WOOD, 1: STONE, 2: MEAT
enum ItemType { WOOD, STONE, MEAT }

@export var item_type: ItemType = ItemType.WOOD
@export var amount: int = 15 # 恢复到旧版的默认初始值 15
var grid_coord: Vector2i
var is_reserved: bool = false # 防止多个小人同时去搬运同一个物品

func _ready() -> void:
	# 使用 call_deferred 确保在外部通过 set() 完成属性赋值后再进行注册逻辑
	call_deferred("_register_to_manager")
	
	# 设置视觉效果
	_setup_visuals()
	
	# 设置碰撞区域（用于拾取交互）
	_setup_collision()

func _setup_visuals() -> void:
	# 设置节点名称以便在编辑器调试
	name = "ItemDrop_" + str(ItemType.keys()[item_type])
	
	# 清理可能存在的旧视觉节点
	for child in get_children():
		if child is Sprite2D or child is ColorRect:
			child.queue_free()
	
	var tex_path = ""
	match item_type:
		ItemType.WOOD:
			tex_path = "res://art/items/wood.png"
		ItemType.STONE:
			tex_path = "res://art/items/stone.png"
		ItemType.MEAT:
			tex_path = "res://art/animals/meat.png"

	# 优先尝试加载美术贴图
	if FileAccess.file_exists(tex_path) or FileAccess.file_exists(tex_path + ".import"):
		var sprite = Sprite2D.new()
		sprite.texture = load(tex_path)
		# 如果贴图过大，可以在这里统一缩放，例如：sprite.scale = Vector2(0.5, 0.5)
		add_child(sprite)
	else:
		# 如果没有贴图，则使用旧版的 ColorRect 视觉逻辑
		var visual = ColorRect.new()
		# 综合两个版本的尺寸，肉类/物品通常比树木小
		visual.size = Vector2(10, 10) 
		visual.position = Vector2(-5, -5)
		
		match item_type:
			ItemType.WOOD:
				visual.color = Color(0.6, 0.4, 0.2) # 柔和的木材棕
			ItemType.STONE:
				visual.color = Color(0.7, 0.7, 0.7) # 石材灰
			ItemType.MEAT:
				visual.color = Color(0.9, 0.3, 0.3) # 整合旧版的肉类红色
		
		visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(visual)

func _setup_collision() -> void:
	# 检查是否已有碰撞节点，防止重复创建
	if has_node("InteractionArea"): return
	
	var area = Area2D.new()
	area.name = "InteractionArea"
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 12.0 # 拾取判定半径
	col.shape = shape
	area.add_child(col)
	add_child(area)

func _register_to_manager() -> void:
	# 注册到全局单例 GameManager
	if GameManager.has_method("register_item"):
		GameManager.register_item(self)

func _exit_tree() -> void:
	# 退出场景树时自动注销，防止内存溢出或逻辑错误
	if GameManager.has_method("unregister_item"):
		GameManager.unregister_item(self)
