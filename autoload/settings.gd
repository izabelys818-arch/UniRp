extends Node

const PATH := "user://settings.cfg"

var api_key: String = ""
var model: String = ""
var temperature: float = 0.9
var local_dialogue: bool = true
# calendário: dias de jogo em cada mês e se as pessoas envelhecem com os aniversários
var days_per_month: int = 7
var aging: bool = true


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		api_key = cfg.get_value("ai", "api_key", "")
		model = cfg.get_value("ai", "model", "")
		temperature = cfg.get_value("ai", "temperature", 0.9)
		local_dialogue = cfg.get_value("ai", "local_dialogue", true)
		days_per_month = int(cfg.get_value("jogo", "dias_por_mes", 7))
		aging = bool(cfg.get_value("jogo", "envelhecer", true))


# Ao fechar o jogo: solta os caches estáticos (modelos, malhas, materiais, animações).
# Sem isso o Godot imprime "RID leaked at exit" no console.
func _exit_tree() -> void:
	preload("res://world3d/anim_bank.gd").cleanup()
	preload("res://world3d/person.gd").cleanup()
	preload("res://world3d/furn_lib.gd").cleanup()
	preload("res://world3d/mesh_kit.gd").cleanup()
	preload("res://world3d/humanoid.gd").cleanup()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ai", "api_key", api_key)
	cfg.set_value("ai", "model", model)
	cfg.set_value("ai", "temperature", temperature)
	cfg.set_value("ai", "local_dialogue", local_dialogue)
	cfg.set_value("jogo", "dias_por_mes", days_per_month)
	cfg.set_value("jogo", "envelhecer", aging)
	cfg.save(PATH)


# Aplica o ritmo do calendário ao jogo em andamento sem pular a data de hoje.
func apply_calendar() -> void:
	TimeManager.set_days_per_month(days_per_month)
	TimeManager.aging = aging


func is_ready() -> bool:
	return api_key != "" and model != ""
