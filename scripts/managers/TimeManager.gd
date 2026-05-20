extends Node

signal time_updated(day: int, hour: float, minute: int)
signal day_passed(day: int)

# 时间系统参数
# 一天 24 小时，设定 1 秒现实时间 = x 游戏小时
@export var hours_per_real_second: float = 0.05 # 1现实秒 = 0.05游戏小时，即 1游戏小时 = 20现实秒。一天480秒（8分钟）

var current_day: int = 1
var current_hour: float = 8.0 # 从早上8点开始
var _is_night: bool = false

var active_time_scale: int = 1 # 0: 暂停, 1: 原速, 2: 2倍, 3: 4倍
var engine_time_scales = [0.0, 1.0, 2.0, 4.0]

func _ready() -> void:
	set_process(true)
	_apply_time_scale()
	# 初始状态检测
	_is_night = (current_hour < 6.0 or current_hour >= 18.0)

func set_time_scale(level: int) -> void:
	if level < 0 or level >= engine_time_scales.size(): return
	active_time_scale = level
	_apply_time_scale()

func _apply_time_scale() -> void:
	Engine.time_scale = engine_time_scales[active_time_scale]

func _process(delta: float) -> void:
	if active_time_scale == 0:
		return
	
	current_hour += delta * hours_per_real_second
	
	if current_hour >= 24.0:
		current_hour -= 24.0
		current_day += 1
		day_passed.emit(current_day)
		EventBus.day_changed.emit(current_day)
		
	# 昼夜更替检测
	var new_is_night = (current_hour < 6.0 or current_hour >= 18.0)
	if new_is_night != _is_night:
		_is_night = new_is_night
		if _is_night:
			EventBus.night_started.emit()
		else:
			EventBus.day_started.emit()

	var minute = int(fmod(current_hour * 60, 60))
	time_updated.emit(current_day, current_hour, minute)

func get_sun_color() -> Color:
	# 根据当前小时返回环境光照颜色
	if current_hour >= 6.0 and current_hour <= 18.0:
		# 白天
		var is_morning = current_hour < 12.0
		var t = (current_hour - 6.0) / 6.0 if is_morning else (18.0 - current_hour) / 6.0
		return Color(0.3, 0.3, 0.4).lerp(Color(1.0, 1.0, 1.0), t)
	else:
		# 黑夜
		var is_evening = current_hour > 18.0
		var t = 0.0
		if is_evening:
			t = (24.0 - current_hour) / 6.0
		else:
			t = (current_hour - 0.0) / 6.0
		return Color(0.1, 0.1, 0.2).lerp(Color(0.3, 0.3, 0.4), t)
