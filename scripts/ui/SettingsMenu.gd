extends CanvasLayer

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	# 背景遮罩
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	
	# 主面板
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 400)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.95)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.3, 0.3, 1.0)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)
	
	# 标题
	var title = Label.new()
	title.text = "乾坤再造 (设置)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# 音量设置
	_add_volume_slider(vbox, "主音量", "master_volume")
	_add_volume_slider(vbox, "背景音乐", "bgm_volume")
	_add_volume_slider(vbox, "音效", "sfx_volume")
	_add_volume_slider(vbox, "环境音", "ambient_volume")
	
	# 调试设置
	_add_debug_toggle(vbox)
	
	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "返回"
	close_btn.custom_minimum_size = Vector2(0, 40)
	close_btn.pressed.connect(queue_free)
	vbox.add_child(close_btn)

func _add_volume_slider(container: VBoxContainer, label_text: String, setting_key: String) -> void:
	var hbox = HBoxContainer.new()
	container.add_child(hbox)
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(label)
	
	var slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = SettingsManager.settings[setting_key]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value): SettingsManager.set_setting(setting_key, value))
	hbox.add_child(slider)

func _add_debug_toggle(container: VBoxContainer) -> void:
	var hbox = HBoxContainer.new()
	container.add_child(hbox)
	
	var label = Label.new()
	label.text = "显示调试日志"
	label.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(label)
	
	var toggle = CheckButton.new()
	toggle.button_pressed = SettingsManager.settings.get("debug_logs", false)
	toggle.toggled.connect(func(value): SettingsManager.set_setting("debug_logs", value))
	hbox.add_child(toggle)
