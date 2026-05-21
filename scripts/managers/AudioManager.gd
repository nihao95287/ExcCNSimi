extends Node

## ============================================================
## AudioManager — 解耦音频系统
## ============================================================
## 所有音频播放均通过 EventBus 信号驱动，任何模块只需:
##   EventBus.play_sfx.emit("chop")
## 即可播放音效，无需 get_node 引用此管理器。
##
## 本管理器同时监听游戏事件（采集、战斗、建筑等），
## 自动触发对应音效，实现"零侵入"音频集成。
## ============================================================

var DEBUG_AUDIO_MANAGER_LOGS: bool:
	get: return SettingsManager.settings.get("debug_logs", false)

# --- 音频播放器池配置 ---
const SFX_POOL_SIZE: int = 8          # 同时可叠加的音效数
const AMBIENT_POOL_SIZE: int = 3      # 同时可叠加的环境音数

# --- BGM 播放器 ---
var bgm_player: AudioStreamPlayer
var bgm_fade_tween: Tween

# --- SFX 对象池 ---
var sfx_pool: Array[AudioStreamPlayer] = []
var sfx_pool_index: int = 0

# --- Ambient 播放器池 ---
var ambient_players: Dictionary = {}  # name -> AudioStreamPlayer

# --- 音频资源注册表 ---
# 键名 -> 资源路径，音频文件放入 res://audio/ 对应子目录后在此注册
var sfx_registry: Dictionary = {
	# 基础
	"btn_click":     "res://audio/sfx/btn_click.wav",
	"menu_open":     "res://audio/sfx/menu_open.wav",
	"alert":         "res://audio/sfx/btn_click.wav",
	
	# 采集与资源
	"chop":          "res://audio/sfx/chop.wav",
	"mine":          "res://audio/sfx/mine.wav",
	"gather_done":   "res://audio/sfx/gather_done.wav",
	"item_drop":     "res://audio/sfx/gather_done.wav",
	"item_store":    "res://audio/sfx/gather_done.wav",
	
	# 战斗与动物
	"pig_hit":       "res://audio/sfx/pig_hit.wav",
	"chicken_hit":   "res://audio/sfx/chicken_hit.wav",
	"animal_death":  "res://audio/sfx/pig_hit.wav",
	
	# 建设与村民
	"task_confirm":  "res://audio/sfx/btn_click.wav",
	"build_place":   "res://audio/sfx/build_place.wav",
	"build_destroy": "res://audio/sfx/build_destory.wav",
	"stockpile_new": "res://audio/sfx/menu_open.wav",
	
	# 环境与时间
	"day_begin":     "res://audio/sfx/menu_open.wav",
	"season_new":    "res://audio/sfx/menu_open.wav",
}

var bgm_registry: Dictionary = {
	"menu":          "res://audio/bgm/menu.mp3",
	"gameplay":      "res://audio/bgm/gameplay.wav",
}

const BGM_TRACK_VOLUME_MULTIPLIER: Dictionary = {
	"menu": 0.45,
}

var ambient_registry: Dictionary = {
	"map_0":         "res://audio/ambient/birds.mp3",
	"map_1":         "res://audio/ambient/wind.mp3",
	"map_2":         "res://audio/ambient/crickets.wav",
}

# --- 音频缓存 ---
var _stream_cache: Dictionary = {}  # path -> AudioStream

# 缓存音量倍率
var _master_vol: float = 1.0
var _bgm_vol: float = 1.0
var _sfx_vol: float = 1.0
var _ambient_vol: float = 1.0
var _current_bgm_name: String = ""


# ============================================================
#                         初始化
# ============================================================

func _ready() -> void:
	_create_bgm_player()
	_create_sfx_pool()
	_connect_eventbus_signals()
	_connect_game_event_signals()
	
	# 应用初始设置
	if get_node_or_null("/root/SettingsManager"):
		SettingsManager.apply_settings()

	# 启动时播放菜单 BGM
	play_bgm("menu")
	if DEBUG_AUDIO_MANAGER_LOGS:
		print("AudioManager: 初始化完成，播放菜单BGM")


func _create_bgm_player() -> void:
	bgm_player = AudioStreamPlayer.new()
	bgm_player.bus = "Master"
	bgm_player.name = "BGM"
	add_child(bgm_player)


func _create_sfx_pool() -> void:
	for i in range(SFX_POOL_SIZE):
		var player = AudioStreamPlayer.new()
		player.bus = "Master"
		player.name = "SFX_%d" % i
		add_child(player)
		sfx_pool.append(player)


# ============================================================
#           连接 EventBus 音频信号（解耦入口）
# ============================================================

func _connect_eventbus_signals() -> void:
	EventBus.play_sfx.connect(_on_play_sfx)
	EventBus.play_bgm.connect(_on_play_bgm)
	EventBus.stop_bgm.connect(_on_stop_bgm)
	EventBus.play_ambient.connect(_on_play_ambient)
	EventBus.stop_ambient.connect(_on_stop_ambient)
	EventBus.volume_changed.connect(_on_volume_changed)
	EventBus.resource_hit.connect(_on_resource_hit)


# ============================================================
#        连接游戏事件信号（自动触发音效，零侵入）
# ============================================================

func _connect_game_event_signals() -> void:
	# 采集/资源 (使用 play_sfx_varied 增加自然感)
	EventBus.resource_collected.connect(_on_resource_collected)
	EventBus.resource_destroyed.connect(_on_resource_destroyed)
	EventBus.resource_consumed.connect(_on_resource_consumed)
	EventBus.item_dropped.connect(_on_item_dropped)
	EventBus.item_stored.connect(_on_item_stored)

	# 战斗/动物
	EventBus.animal_killed.connect(_on_animal_killed)
	EventBus.animal_hit.connect(_on_animal_hit)

	# 村民行为
	EventBus.villager_task_assigned.connect(_on_task_assigned)

	# 建筑与规划
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_demolished.connect(_on_building_demolished)
	EventBus.stockpile_created.connect(_on_stockpile_created)
	EventBus.build_requested.connect(_on_menu_open)
	EventBus.farm_build_requested.connect(_on_menu_open)

	# UI/系统提示
	EventBus.alert_message.connect(_on_alert_message)
	EventBus.toggle_build_menu.connect(_on_menu_open)

	# 环境与时间周期
	EventBus.day_changed.connect(_on_day_changed)
	EventBus.season_changed.connect(_on_season_changed)
	EventBus.day_started.connect(_on_day_started)
	EventBus.night_started.connect(_on_night_started)
	EventBus.map_generated.connect(_on_map_generated)


# ============================================================
#                   音频播放核心方法
# ============================================================

## 播放一次性音效
func play_sfx(sfx_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream = _load_stream(sfx_registry.get(sfx_name, ""))
	if not stream:
		return

	var player = sfx_pool[sfx_pool_index]
	sfx_pool_index = (sfx_pool_index + 1) % SFX_POOL_SIZE

	player.stream = stream
	player.volume_db = volume_db + linear_to_db(_sfx_vol)
	player.pitch_scale = pitch
	player.play()


## 播放带随机音高变化的音效（用于采集等重复动作，避免机械感）
func play_sfx_varied(sfx_name: String, volume_db: float = 0.0) -> void:
	var pitch = randf_range(0.85, 1.15)
	play_sfx(sfx_name, volume_db, pitch)


## 切换 BGM（带淡入淡出）
func play_bgm(bgm_name: String, fade_duration: float = 1.0) -> void:
	if DEBUG_AUDIO_MANAGER_LOGS:
		print("AudioManager: 尝试播放 BGM -> ", bgm_name)
	
	# 如果切换回菜单，自动停止所有环境音
	if bgm_name == "menu":
		for ambient_name in ambient_players.keys().duplicate():
			stop_ambient(ambient_name, fade_duration)

	var stream = _load_stream(bgm_registry.get(bgm_name, ""))
	if not stream:
		push_warning("AudioManager: 找不到 BGM 资源: ", bgm_name)
		return

	# 如果已经在播放同一首，忽略
	if bgm_player.playing and bgm_player.stream == stream:
		_current_bgm_name = bgm_name
		bgm_player.volume_db = _get_bgm_volume_db()
		return

	if bgm_fade_tween and bgm_fade_tween.is_valid():
		bgm_fade_tween.kill()

	if bgm_player.playing and fade_duration > 0.0:
		# 先淡出再切换
		bgm_fade_tween = create_tween()
		bgm_fade_tween.tween_property(bgm_player, "volume_db", -40.0, fade_duration * 0.5)
		bgm_fade_tween.tween_callback(_switch_bgm_stream.bind(stream, fade_duration * 0.5, bgm_name))
	else:
		_switch_bgm_stream(stream, fade_duration, bgm_name)


func _switch_bgm_stream(stream: AudioStream, fade_in_duration: float, bgm_name: String) -> void:
	_current_bgm_name = bgm_name
	bgm_player.stream = stream
	bgm_player.volume_db = -40.0
	bgm_player.play()

	if fade_in_duration > 0.0:
		bgm_fade_tween = create_tween()
		bgm_fade_tween.tween_property(bgm_player, "volume_db", _get_bgm_volume_db(), fade_in_duration)
	else:
		bgm_player.volume_db = _get_bgm_volume_db()


func _get_bgm_volume_db() -> float:
	var track_multiplier = float(BGM_TRACK_VOLUME_MULTIPLIER.get(_current_bgm_name, 1.0))
	return linear_to_db(_bgm_vol * track_multiplier)


## 停止 BGM
func stop_bgm(fade_duration: float = 1.0) -> void:
	if not bgm_player.playing:
		return

	if bgm_fade_tween and bgm_fade_tween.is_valid():
		bgm_fade_tween.kill()

	if fade_duration > 0.0:
		bgm_fade_tween = create_tween()
		bgm_fade_tween.tween_property(bgm_player, "volume_db", -40.0, fade_duration)
		bgm_fade_tween.tween_callback(bgm_player.stop)
	else:
		bgm_player.stop()


## 播放环境音（循环）
func play_ambient(ambient_name: String) -> void:
	if ambient_players.has(ambient_name):
		return  # 已经在播放

	var stream = _load_stream(ambient_registry.get(ambient_name, ""))
	if not stream:
		return

	var player = AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "Master"
	player.volume_db = linear_to_db(_ambient_vol)
	player.name = "Ambient_%s" % ambient_name
	add_child(player)

	# 启用循环（根据文件类型）
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD

	player.play()
	ambient_players[ambient_name] = player


## 停止环境音
func stop_ambient(ambient_name: String, fade_duration: float = 0.5) -> void:
	if not ambient_players.has(ambient_name):
		return

	var player = ambient_players[ambient_name]
	ambient_players.erase(ambient_name)

	if fade_duration > 0.0:
		var tween = create_tween()
		tween.tween_property(player, "volume_db", -40.0, fade_duration)
		tween.tween_callback(player.queue_free)
	else:
		player.queue_free()


# ============================================================
#                    资源加载 & 缓存
# ============================================================

func _load_stream(path: String) -> AudioStream:
	if path.is_empty():
		return null

	if _stream_cache.has(path):
		return _stream_cache[path]

	if not ResourceLoader.exists(path):
		push_warning("AudioManager: 资源路径不存在 -> ", path)
		# 音频文件尚未放入项目时静默跳过，不报错不崩溃
		return null

	var stream = load(path)
	if stream is AudioStream:
		_stream_cache[path] = stream
		return stream

	return null


# ============================================================
#          EventBus 音频信号回调（外部模块通用入口）
# ============================================================

func _on_play_sfx(sfx_name: String) -> void:
	play_sfx(sfx_name)

func _on_play_bgm(bgm_name: String, fade_duration: float) -> void:
	play_bgm(bgm_name, fade_duration)

func _on_stop_bgm(fade_duration: float) -> void:
	stop_bgm(fade_duration)

func _on_play_ambient(ambient_name: String) -> void:
	play_ambient(ambient_name)

func _on_stop_ambient(ambient_name: String) -> void:
	stop_ambient(ambient_name)

func _on_volume_changed(bus_name: String, volume: float) -> void:
	match bus_name:
		"Master":
			_master_vol = volume
			var bus_idx = AudioServer.get_bus_index("Master")
			if bus_idx >= 0:
				AudioServer.set_bus_volume_db(bus_idx, linear_to_db(volume))
		"BGM":
			_bgm_vol = volume
			if bgm_player:
				bgm_player.volume_db = _get_bgm_volume_db()
		"SFX":
			_sfx_vol = volume
			# 存量播放器不实时调整，仅对新播放生效
		"Ambient":
			_ambient_vol = volume
			for player in ambient_players.values():
				if is_instance_valid(player):
					player.volume_db = linear_to_db(volume)


# ============================================================
#        游戏事件回调 → 自动触发音效（零侵入集成）
# ============================================================

func _on_resource_collected(resource_type: int, _amount: int) -> void:
	# 资源入库或收获时可以播放一个通用的入库音效
	pass

func _on_resource_hit(resource_type: int) -> void:
	if DEBUG_AUDIO_MANAGER_LOGS:
		print("AudioManager: 收到资源打击信号, type=", resource_type)
	match resource_type:
		0:  # WOOD
			play_sfx_varied("chop")
		1:  # STONE
			play_sfx_varied("mine")

func _on_resource_destroyed(_resource_type: int) -> void:
	play_sfx("gather_done")

func _on_resource_consumed(_resource_type: int, _amount: int) -> void:
	# 消耗资源时可以播放一个轻微的 UI 或反馈音
	play_sfx("btn_click", -10.0)

func _on_item_dropped(_item: Node2D, _item_type: int, _amount: int) -> void:
	play_sfx("item_drop")

func _on_item_stored(_item_type: int, _amount: int) -> void:
	play_sfx("item_store")

func _on_animal_killed(_species: String) -> void:
	play_sfx("animal_death")

func _on_animal_hit(species: String) -> void:
	if DEBUG_AUDIO_MANAGER_LOGS:
		print("AudioManager: 收到动物受击信号, species=", species)
	match species:
		"pig":
			play_sfx_varied("pig_hit")
		"chicken":
			play_sfx_varied("chicken_hit")
		_:
			play_sfx_varied("pig_hit") # 默认音效

func _on_task_assigned(_villager: Node2D, _task_type: String, _target: Node2D) -> void:
	play_sfx_varied("task_confirm", -5.0)

func _on_building_placed(_coord: Vector2i, _type: int) -> void:
	play_sfx("build_place")

func _on_building_demolished(_coord: Vector2i, _type: int) -> void:
	play_sfx("build_destroy")

func _on_stockpile_created() -> void:
	play_sfx("stockpile_new")

func _on_menu_open(_data = null) -> void:
	play_sfx("menu_open")

func _on_alert_message(_message: String) -> void:
	play_sfx("alert", -15.0)  # 提示音音量低一些

func _on_day_changed(_day: int) -> void:
	play_sfx("day_begin", -5.0)

func _on_season_changed(_season: int) -> void:
	play_sfx("season_new")

func _on_day_started() -> void:
	# 白天不再切换环境音
	pass

func _on_night_started() -> void:
	# 夜晚不再切换环境音
	pass

func _on_map_generated(map_type: int) -> void:
	# 停止当前所有环境音
	for ambient_name in ambient_players.keys().duplicate():
		stop_ambient(ambient_name, 2.0)
	
	# 根据地图类型播放环境音
	var ambient_key = "map_%d" % map_type
	if DEBUG_AUDIO_MANAGER_LOGS:
		print("AudioManager: 收到地图生成信号, type=", map_type, " 尝试播放环境音: ", ambient_key)
	if ambient_registry.has(ambient_key):
		play_ambient(ambient_key)
	
	play_bgm("gameplay", 2.0)
