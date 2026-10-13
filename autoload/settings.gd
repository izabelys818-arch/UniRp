extends Node

const PATH := "user://settings.cfg"
var storage_path := PATH
signal camera_changed
const CAMERA_KEYS := [KEY_V, KEY_F6, KEY_F7]

var api_key: String = ""
var model: String = ""
var temperature: float = 0.9
var local_dialogue: bool = true
# calendário: dias de jogo em cada mês e se as pessoas envelhecem com os aniversários
var days_per_month: int = 7
var aging: bool = true
# qualidade gráfica: 0 desempenho, 1 alto, 2 ultra (iluminação global, neblina e relevo)
var graphics: int = 1
var camera_mode: int = 0
var camera_key: int = KEY_V
var camera_sensitivity: float = 0.003
var camera_invert_y: bool = false


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(storage_path) == OK:
		api_key = cfg.get_value("ai", "api_key", "")
		model = cfg.get_value("ai", "model", "")
		temperature = cfg.get_value("ai", "temperature", 0.9)
		local_dialogue = cfg.get_value("ai", "local_dialogue", true)
		days_per_month = int(cfg.get_value("jogo", "dias_por_mes", 7))
		aging = bool(cfg.get_value("jogo", "envelhecer", true))
		graphics = clampi(int(cfg.get_value("video", "qualidade", 1)), 0, 2)
		camera_mode = clampi(int(cfg.get_value("camera", "modo", 0)), 0, 1)
		camera_key = int(cfg.get_value("camera", "tecla", KEY_V))
		camera_sensitivity = clampf(float(cfg.get_value("camera", "sensibilidade", 0.003)), 0.001, 0.008)
		camera_invert_y = bool(cfg.get_value("camera", "inverter_y", false))
	apply_camera_inputs()


func apply_camera_inputs() -> void:
	if not camera_key in CAMERA_KEYS:
		camera_key = KEY_V
	for action in ["camera_toggle", "interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	InputMap.action_erase_events("camera_toggle")
	var toggle := InputEventKey.new()
	toggle.physical_keycode = camera_key
	InputMap.action_add_event("camera_toggle", toggle)
	if InputMap.action_get_events("interact").is_empty():
		var interact := InputEventKey.new()
		interact.physical_keycode = KEY_E
		InputMap.action_add_event("interact", interact)


func set_camera_mode(value: int, persist: bool = true) -> void:
	camera_mode = clampi(value, 0, 1)
	if persist:
		save_settings()
	camera_changed.emit()


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
	cfg.set_value("video", "qualidade", graphics)
	cfg.set_value("camera", "modo", camera_mode)
	cfg.set_value("camera", "tecla", camera_key)
	cfg.set_value("camera", "sensibilidade", camera_sensitivity)
	cfg.set_value("camera", "inverter_y", camera_invert_y)
	cfg.save(storage_path)


# Aplica o ritmo do calendário ao jogo em andamento sem pular a data de hoje.
func apply_calendar() -> void:
	TimeManager.set_days_per_month(days_per_month)
	TimeManager.aging = aging


func is_ready() -> bool:
	return api_key != "" and model != ""
