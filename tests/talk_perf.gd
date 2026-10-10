extends Node

# Mede o custo da conversa: tempo de quadro e de script parado (sem caixa) e durante uma conversa
# com respostas locais. Também fotografa: jogo ocioso, conversa, menu de pausa.
# Uso: godot --path . res://tests/talk_perf.tscn

const UITheme = preload("res://ui/ui_theme.gd")

var frames: Array = []
var procs: Array = []
var rec := false
var t_conv := 0
var slow: Array = []
var gs


func _process(delta: float) -> void:
	if rec:
		frames.append(delta * 1000.0)
		procs.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		if delta > 0.04 and t_conv > 0:
			slow.append("%.0fms@%.2fs proc=%.0f fis=%.0f nav=%.0f nos=%d obj=%d" % [delta * 1000.0, (Time.get_ticks_msec() - t_conv) / 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT)])


func _stats(tag: String) -> void:
	var s: Array = frames.duplicate()
	s.sort()
	var tot := 0.0
	for f in frames:
		tot += float(f)
	var ptot := 0.0
	var pmax := 0.0
	for p in procs:
		ptot += float(p)
		pmax = maxf(pmax, float(p))
	var n := maxi(frames.size(), 1)
	print("CONVERSA %s: quadros=%d fps=%.1f 1%%pior=%.1fms pior=%.1fms >33ms=%d script_medio=%.2fms script_pior=%.1fms" % [tag, frames.size(), 1000.0 / (tot / n), float(s[int(s.size() * 0.99)]) if not s.is_empty() else 0.0, float(s[-1]) if not s.is_empty() else 0.0, s.filter(func(x): return x > 33.0).size(), ptot / n, pmax])
	frames.clear()
	procs.clear()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OS.get_user_data_dir() + "/ui_%s.png" % name
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
	# a gravação do PNG leva >100 ms; não pode cair dentro da medição
	for i in 5:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().process_frame


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	preload("res://world3d/world_view.gd").realtime = false
	preload("res://world3d/world_view.gd").trace = OS.get_environment("PERF_TRACE") == "1"
	WorldEvents.random_enabled = false
	Settings.local_dialogue = true
	SaveManager.path = "user://talk_save.json"
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x",
		"look": {"pele": 2, "cabelo": 0, "cor_cabelo": 0, "barba": 1, "roupa": 2, "marcas": []},
		"appearance_extra": "", "backstory": "", "traits": [], "cenario": "porto_cinza",
		"origin": origin["id"], "money": 400, "location": "lanchonete", "home": "apartamento", "inventory": {}, "alive": true,
	})
	TimeManager.total_minutes = 1440 + 11 * 60
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var screen = preload("res://ui/game_screen.gd").new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	gs = screen
	await _wait(3.0)
	rec = true
	await _wait(5.0)
	rec = false
	_stats("ociosa")
	await _shot("ocioso")
	var here: Array = NPCManager.npcs_here()
	if here.is_empty():
		here = NPCManager.npcs.keys()
	var id := str(here[0])
	rec = true
	t_conv = Time.get_ticks_msec()
	NPCManager.start_conversation(id)
	await _wait(1.5)
	for line in ["Oi, tudo bem?", "Como está o movimento hoje?", "Qual o seu nome?"]:
		NPCManager.talk(line)
		await _wait(4.0)
	rec = false
	_stats("durante")
	print("LENTOS ", slow)
	slow.clear()
	await _shot("conversa")
	if screen.has_method("open_pause"):
		screen.open_pause()
		await _wait(0.6)
		await _shot("pausa")
		screen.close_pause()
	NPCManager.end_conversation()
	await _wait(1.0)
	await _shot("depois")
	# segunda conversa na mesma sessão: mostra se o custo era só de primeira vez
	var id2 := str(here[1]) if here.size() > 1 else id
	rec = true
	t_conv = Time.get_ticks_msec()
	NPCManager.start_conversation(id2)
	await _wait(1.5)
	for line in ["Oi!", "Tudo certo por aqui?"]:
		NPCManager.talk(line)
		await _wait(3.5)
	rec = false
	_stats("segunda")
	await _shot("conversa2")
	NPCManager.end_conversation()
	await _wait(1.0)
	# mensagem da história fora de conversa: abre, dá para ler e some sozinha
	GameState.add_log("A chuva fina volta a cair sobre Porto Cinza. Do outro lado da rua, alguém fecha a porta de aço da loja mais cedo que o normal.", "narration")
	await _wait(3.0)
	print("MENSAGEM visivel=%s modo=%s" % [gs.dialogue.visible, gs.dialogue.mode])
	await _shot("mensagem")
	await _wait(9.0)
	print("MENSAGEM depois de lida: visivel=%s" % gs.dialogue.visible)
	print("LENTOS2 ", slow)
	NPCManager.end_conversation()
	await _wait(0.5)
	SaveManager.delete_save()
	get_tree().quit()
