extends Node

const PATH := "user://settings.cfg"

var api_key: String = ""
var model: String = ""
var temperature: float = 0.9
var local_dialogue: bool = true


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		api_key = cfg.get_value("ai", "api_key", "")
		model = cfg.get_value("ai", "model", "")
		temperature = cfg.get_value("ai", "temperature", 0.9)
		local_dialogue = cfg.get_value("ai", "local_dialogue", true)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ai", "api_key", api_key)
	cfg.set_value("ai", "model", model)
	cfg.set_value("ai", "temperature", temperature)
	cfg.set_value("ai", "local_dialogue", local_dialogue)
	cfg.save(PATH)


func is_ready() -> bool:
	return api_key != "" and model != ""
