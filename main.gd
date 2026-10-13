extends Control

const UITheme = preload("res://ui/ui_theme.gd")
const SCREENS := {
	"menu": preload("res://ui/main_menu.gd"),
	"settings": preload("res://ui/settings_screen.gd"),
	"creation": preload("res://ui/character_creation.gd"),
	"game": preload("res://ui/game_screen.gd"),
}

var current: Control
var current_key := ""
var switching := false
var _pending_screen := ""
var _pending_args: Dictionary = {}

# Diagnóstico de engasgos: quadros acima de SPIKE_MS são gravados com o contexto em
# user://diagnostico.log, para investigar travadas que não se repetem sob teste.
const SPIKE_MS := 250.0
const SPIKE_LOG := "user://diagnostico.log"
const SPIKE_LOG_MAX := 200
var _spikes := 0


func _ready() -> void:
	theme = UITheme.build()
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	show_screen("menu")


func _process(delta: float) -> void:
	if delta * 1000.0 >= SPIKE_MS and _spikes < SPIKE_LOG_MAX:
		_log_spike(delta * 1000.0)


func _log_spike(ms: float) -> void:
	# a primeira gravação da sessão zera o arquivo; as seguintes acrescentam ao final
	var mode := FileAccess.WRITE if _spikes == 0 else FileAccess.READ_WRITE
	var f := FileAccess.open(SPIKE_LOG, mode)
	if f == null:
		return
	if mode == FileAccess.READ_WRITE:
		f.seek_end()
	var stamp := Time.get_datetime_string_from_system(false, true)
	var in_game := current_key == "game" and GameState.active
	var lugar := World.current_id() if in_game else "-"
	var hora := "dia %d %02d:%02d" % [TimeManager.day(), TimeManager.hour(), TimeManager.minute()] if in_game else "-"
	f.store_line("%s quadro=%.0fms fps=%.0f tela=%s lugar=%s hora_jogo=%s npcs=%d mem=%.0fMB objetos=%d" % [
		stamp, ms, Engine.get_frames_per_second(), current_key, lugar, hora,
		NPCManager.npcs.size(), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		int(Performance.get_monitor(Performance.OBJECT_COUNT))])
	f.close()
	_spikes += 1
	if _spikes == 1:
		print("DIAGNOSTICO: engasgos serao gravados em ", ProjectSettings.globalize_path(SPIKE_LOG))


func show_screen(screen: String, args: Dictionary = {}) -> void:
	if switching:
		_pending_screen = screen
		_pending_args = args.duplicate(true)
		return
	if not SCREENS.has(screen):
		push_error("Tela desconhecida: " + screen)
		return
	if screen == "game":
		switching = true
		var cover := ColorRect.new()
		cover.color = UITheme.BG
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var message := Label.new()
		message.text = "Preparando sua cidade…"
		message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		message.add_theme_font_size_override("font_size", 26)
		cover.add_child(message)
		add_child(cover)
		await get_tree().process_frame
		await get_tree().process_frame
		if current:
			_discard_current()
		await get_tree().process_frame
		cover.queue_free()
	if current:
		_discard_current()
	current = SCREENS[screen].new()
	current_key = screen
	current.set("args", args)
	current.set_anchors_preset(Control.PRESET_FULL_RECT)
	current.connect("navigate", show_screen)
	add_child(current)
	switching = false
	if _pending_screen != "":
		var next_screen := _pending_screen
		var next_args := _pending_args
		_pending_screen = ""
		_pending_args = {}
		show_screen(next_screen, next_args)


func _discard_current() -> void:
	# Stop old UI callbacks immediately; queue_free() alone leaves the node alive
	# through the end of this frame while autoload signals can still reach it.
	var old := current
	current = null
	old.hide()
	old.set_process(false)
	old.set_process_input(false)
	if old.get_parent() == self:
		remove_child(old)
	old.queue_free()
