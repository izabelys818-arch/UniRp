extends Node

# Estresse de jogo de verdade: relógio do jogo andando (acelerado), eventos aleatórios ligados,
# moradores novos chegando, o jogador andando pela cidade em loop; a cada 5 s mede FPS, pior
# quadro, memória, nós, objetos e recursos para achar vazamento ou travada.
# Uso: STRESS_SEG=240 STRESS_VEL=20 STRESS_CHUVA=1 godot --path . res://tests/stress_real.tscn

const UITheme = preload("res://ui/ui_theme.gd")

var frames: Array = []
var wv
var t_start := 0.0
var last_report := 0.0
var worst_ever := 0.0
var over60 := 0
var over100 := 0


func _process(delta: float) -> void:
	var ms := delta * 1000.0
	frames.append(ms)
	worst_ever = maxf(worst_ever, ms)
	if t_start > 0.0:
		if ms > 60.0:
			over60 += 1
		if ms > 100.0:
			over100 += 1
	if ms > 250.0:
		print("TRAVADA %.0f ms (hora do jogo %s, pos %s)" % [ms, TimeManager.clock_str(), Vector2(wv.player.position.x, wv.player.position.z).round()])


func _report(tag: String) -> void:
	var s: Array = frames.duplicate()
	s.sort()
	var tot := 0.0
	for f in s:
		tot += float(f)
	var avg := tot / maxf(s.size(), 1)
	var p99: float = s[int(s.size() * 0.99)] if not s.is_empty() else 0.0
	print("%s t=%3ds fps=%5.1f 1%%pior=%5.1fms pior=%6.1fms | mem=%4.0fMB nos=%d objetos=%d recursos=%d orfaos=%d vram=%4.0fMB | %s" % [
		tag, int((Time.get_ticks_msec() / 1000.0) - t_start), 1000.0 / maxf(avg, 0.001), p99, float(s[s.size() - 1]) if not s.is_empty() else 0.0,
		float(OS.get_static_memory_usage()) / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0, TimeManager.clock_str()])
	frames.clear()


func _ready() -> void:
	preload("res://world3d/world_view.gd").trace = OS.get_environment("STRESS_TRACE") == "1"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	SaveManager.path = "user://estresse_save.json"
	var origin := World.get_origin("morador_antigo")
	if OS.get_environment("STRESS_SAVE") != "":
		# carrega uma cópia do save de verdade (o original não é tocado)
		DirAccess.copy_absolute(OS.get_environment("STRESS_SAVE"), ProjectSettings.globalize_path("user://estresse_save.json"))
		var t_load := Time.get_ticks_msec()
		print("ESTRESSE carregou o save: ", SaveManager.load_game(), " em ", Time.get_ticks_msec() - t_load, " ms; ", TimeManager.clock_str(), "; residentes=", Population.count())
		var root0 := Control.new()
		root0.theme = UITheme.build()
		root0.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(root0)
		var screen0 = preload("res://ui/game_screen.gd").new()
		screen0.set_anchors_preset(Control.PRESET_FULL_RECT)
		root0.add_child(screen0)
		wv = screen0.world_view
		await _run_loop()
		return
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x",
		"look": {"pele": 2, "cabelo": 0, "cor_cabelo": 0, "barba": 1, "roupa": 2, "marcas": [], "corpo": 4},
		"appearance_extra": "", "backstory": "", "traits": [], "cenario": "porto_cinza",
		"origin": origin["id"], "money": 4000, "location": "praca", "home": "apartamento", "inventory": {"pao": 3}, "alive": true,
	})
	TimeManager.new_calendar()
	TimeManager.total_minutes = 7 * 60
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	Population.populate(4)
	AgingSystem.reset()
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var screen = preload("res://ui/game_screen.gd").new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	wv = screen.world_view
	await _run_loop()


func _run_loop() -> void:
	for i in 90:
		await get_tree().process_frame
	t_start = Time.get_ticks_msec() / 1000.0
	frames.clear()
	var secs := float(OS.get_environment("STRESS_SEG")) if OS.get_environment("STRESS_SEG") != "" else 240.0
	var vel := int(OS.get_environment("STRESS_VEL")) if OS.get_environment("STRESS_VEL") != "" else 20
	if OS.get_environment("STRESS_CHUVA") == "1":
		WorldEvents.start("tempestade", 48.0)
	var spots: Array = [wv.layout.door_out(wv.layout.house_ids[20]), wv.layout.door_out("praca"), wv.layout.door_out("rodoviaria") + Vector2(0, -8), wv.layout.door_out("beco"), wv.layout.door_in("lanchonete"), wv.layout.door_out("hospital"), wv.layout.door_out("igreja"), wv.layout.door_out("parque")]
	var spot := 0
	var next_spot := 0.0
	var next_fix := 0.0
	var next_arrive := 40.0
	while Time.get_ticks_msec() / 1000.0 - t_start < secs:
		await get_tree().process_frame
		var now := Time.get_ticks_msec() / 1000.0 - t_start
		if now >= next_spot:
			next_spot = now + 14.0
			wv._go_to(spots[spot % spots.size()])
			spot += 1
		# tempo acelerado (além do relógio normal): mantém o personagem vivo
		if now >= next_fix:
			next_fix = now + 1.0
			NeedsSystem.reset({})
			TimeManager.advance(vel)
		if now >= next_arrive:
			next_arrive = now + 60.0
			Population.arrive()
		if now - last_report >= 5.0:
			last_report = now
			_report("ESTRESSE")
	_report("FINAL")
	print("ESTRESSE pior quadro de todos: %.0f ms; quadros >60ms: %d; >100ms: %d" % [worst_ever, over60, over100])
	SaveManager.delete_save()
	get_tree().quit()
