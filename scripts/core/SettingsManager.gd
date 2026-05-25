extends Node

const SETTINGS_PATH = "user://settings.json"

var settings: Dictionary = {
	"master_volume": 0.8,
	"bgm_volume": 0.8,
	"sfx_volume": 0.8,
	"ambient_volume": 0.8,
	"debug_logs": false
}

func _ready() -> void:
	load_settings()
	apply_settings()

func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file:
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data = json.data
			for key in data.keys():
				if settings.has(key):
					settings[key] = data[key]
		file.close()

func save_settings() -> void:
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(settings))
		file.close()

func apply_settings() -> void:
	# 通过信号通知 AudioManager，由其内部处理不同类型的音量
	EventBus.volume_changed.emit("Master", settings["master_volume"])
	EventBus.volume_changed.emit("BGM", settings["bgm_volume"])
	EventBus.volume_changed.emit("SFX", settings["sfx_volume"])
	EventBus.volume_changed.emit("Ambient", settings["ambient_volume"])

func set_setting(key: String, value) -> void:
	settings[key] = value
	save_settings()
	apply_settings()
