extends Node2D

# 当场景加载完成时执行
func _ready() -> void:
	$BackRect/Start_Button.pressed.connect(_on_start_button_pressed)
	
	$BackRect/Exit_Button.pressed.connect(_on_exit_button_pressed)


func _on_start_button_pressed() -> void:
	print("弹出地图数据配置层...")
	
	# 1. 加载并实例化
	var map_data_scene = load("res://MapData.tscn")
	if map_data_scene:
		var overlay = map_data_scene.instantiate()
		
		# 2. 【核心】添加到当前场景
		# 这样它就会作为子节点显示在当前菜单的“前方”
		add_child(overlay)
		
		# 3. 传递数据
		# 假设 MapData 脚本里有变量 var difficulty = 0
		if overlay.has_method("set_data"):
			overlay.set_data("Hard Mode") 
	else:
		print("错误：找不到场景文件")

func _on_exit_button_pressed() -> void:
	print("游戏退出中...")
	get_tree().quit()

func _process(delta: float) -> void:
	pass
