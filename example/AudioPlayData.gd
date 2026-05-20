
# 全局注册类，所有脚本都能识别
class_name AudioPlayData
extends RefCounted

@export var stream: AudioStream
@export var volume_db: float = 0.0
@export var pitch_scale: float = 1.0
@export var bus: String = "Master"

@export var is_3d: bool = false
@export var position: Vector3 = Vector3.ZERO
@export var max_distance: float = 100.0
@export var attenuation: float = 1.0

var unique_id: String = ""
