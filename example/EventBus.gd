# 自动加载名称：EventBus
extends Node

# 音频事件
signal audio_play(data)
signal audio_stop(unique_id: String)
signal audio_stop_all()
signal audio_set_bus_volume(bus_name: String, volume_db: float)
