extends Node

const PATH := "user://settings.cfg"

var api_key: String = ""
var model: String = ""
var temperature: float = 0.9
var image_model: String = ""
var image_model_refs: bool = false


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		api_key = cfg.get_value("ai", "api_key", "")
		model = cfg.get_value("ai", "model", "")
		temperature = cfg.get_value("ai", "temperature", 0.9)
		image_model = cfg.get_value("ai", "image_model", "")
		image_model_refs = cfg.get_value("ai", "image_model_refs", false)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ai", "api_key", api_key)
	cfg.set_value("ai", "model", model)
	cfg.set_value("ai", "temperature", temperature)
	cfg.set_value("ai", "image_model", image_model)
	cfg.set_value("ai", "image_model_refs", image_model_refs)
	cfg.save(PATH)


func is_ready() -> bool:
	return api_key != "" and model != ""


func images_ready() -> bool:
	return api_key != "" and image_model != ""
