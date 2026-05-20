# 自动加载名称：AudioManager
extends Node

@export var pool_size: int = 16
@export var default_bus: String = "Master"

var _pool_2d: Array[AudioStreamPlayer2D] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _active_players: Array = []

func _ready() -> void:
	_init_player_pool()

	# 【关键修复】等待2帧，确保 EventBus 完全加载
	await get_tree().process_frame
	await get_tree().process_frame

	_bind_event_bus()

func _init_player_pool() -> void:
	for _i in range(pool_size):
		var player = AudioStreamPlayer2D.new()
		player.bus = default_bus
		player.finished.connect(_on_player_finished.bind(player))
		add_child(player)
		_pool_2d.append(player)

	for _i in range(pool_size):
		var player = AudioStreamPlayer3D.new()
		player.bus = default_bus
		player.max_distance = 100.0
		player.finished.connect(_on_player_finished.bind(player))
		add_child(player)
		_pool_3d.append(player)

func _bind_event_bus() -> void:
	# 【最强修复】从根节点获取自动加载，永远不报错
	var event_bus = get_node("/root/EventBus")
	
	event_bus.audio_play.connect(_handle_play_audio)
	event_bus.audio_stop.connect(_handle_stop_audio)
	event_bus.audio_stop_all.connect(_handle_stop_all)
	event_bus.audio_set_bus_volume.connect(_handle_set_bus_volume)

func _handle_play_audio(data) -> void:
	if not data.stream:
		return
	
	data.unique_id = _generate_uid()
	
	if data.is_3d:
		_play_3d_audio(data)
	else:
		_play_2d_audio(data)

func _handle_stop_audio(uid: String) -> void:
	for entry in _active_players:
		if entry["uid"] == uid:
			entry["player"].stop()
			_recycle_player(entry["player"])
			_active_players.erase(entry)
			break

func _handle_stop_all() -> void:
	for entry in _active_players:
		entry["player"].stop()
		_recycle_player(entry["player"])
	_active_players.clear()

func _handle_set_bus_volume(bus_name: String, vol_db: float) -> void:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, vol_db)

func _play_2d_audio(data) -> void:
	if _pool_2d.is_empty():
		return
	
	var player = _pool_2d.pop_back()
	player.stream = data.stream
	player.volume_db = data.volume_db
	player.pitch_scale = data.pitch_scale
	player.bus = data.bus
	player.play()

	_active_players.append({"uid": data.unique_id, "player": player})

func _play_3d_audio(data) -> void:
	if _pool_3d.is_empty():
		return
	
	var player = _pool_3d.pop_back()
	player.stream = data.stream
	player.volume_db = data.volume_db
	player.pitch_scale = data.pitch_scale
	player.bus = data.bus
	player.position = data.position
	player.max_distance = data.max_distance
	player.attenuation = data.attenuation
	player.play()

	_active_players.append({"uid": data.unique_id, "player": player})

func _on_player_finished(player: Node) -> void:
	_recycle_player(player)
	for i in range(_active_players.size()):
		if _active_players[i]["player"] == player:
			_active_players.remove_at(i)
			break

func _recycle_player(player: Node) -> void:
	player.stream = null
	if player is AudioStreamPlayer2D:
		_pool_2d.append(player)
	elif player is AudioStreamPlayer3D:
		_pool_3d.append(player)

func _generate_uid() -> String:
	return "audio_" + str(Time.get_ticks_msec()) + "_" + str(randi())
