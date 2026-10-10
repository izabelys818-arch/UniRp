extends Node

# Mede desempenho andando de verdade por uma rota fixa da cidade (bairro → praça → rodoviária → beco).
# Uso: PERF_HOUR=21 PERF_RAIN=1 godot --path . res://tests/perf_walk.tscn
# Imprime FPS médio, 1% pior, pior quadro e quantos engasgos passaram de 33 ms e 50 ms.

const UITheme = preload("res://ui/ui_theme.gd")

var frames: Array = []
var draws: Array = []
var prims: Array = []
var spikes: Array = []
var recording := false
var wv
var label := ""


func _process(delta: float) -> void:
	if recording:
		frames.append(delta * 1000.0)
		draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		if delta * 1000.0 > 33.0:
			print("SPIKE %.1fms em %s" % [delta * 1000.0, label])
			spikes.append([snappedf(delta * 1000.0, 0.1), label, Vector2(wv.player.position.x, wv.player.position.z).round()])


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	preload("res://world3d/world_view.gd").realtime = false
	# PERF_SEM_ROSTO=1: personagens sem deformações do rosto nem postura (para comparar o custo)
	preload("res://world3d/person.gd").face_fx = OS.get_environment("PERF_SEM_ROSTO") != "1"
	preload("res://world3d/world_view.gd").trace = OS.get_environment("PERF_TRACE") == "1"
	WorldEvents.random_enabled = false
	SaveManager.path = "user://perf_save.json"
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x",
		"look": {"pele": 2, "cabelo": 0, "cor_cabelo": 0, "barba": 1, "roupa": 2, "marcas": []},
		"appearance_extra": "", "backstory": "", "traits": [], "cenario": OS.get_environment("PERF_SCEN") if OS.get_environment("PERF_SCEN") != "" else "porto_cinza",
		"origin": origin["id"], "money": 400, "location": "lanchonete", "home": "apartamento", "inventory": {}, "alive": true,
	})
	var hour := float(OS.get_environment("PERF_HOUR")) if OS.get_environment("PERF_HOUR") != "" else 11.0
	TimeManager.total_minutes = 1440 + int(hour * 60.0)
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	if OS.get_environment("PERF_RAIN") == "1":
		WorldEvents.start("tempestade", 10.0)
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var screen = preload("res://ui/game_screen.gd").new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	wv = screen.world_view
	for i in 90:
		await get_tree().process_frame
	recording = true
	var legs := [
		["bairro", wv.layout.door_out(wv.layout.house_ids[20])],
		["praca", wv.layout.door_out("praca")],
		["rodoviaria", wv.layout.door_out("rodoviaria") + Vector2(0, -8)],
		["beco", wv.layout.door_out("beco")],
		["lanchonete", wv.layout.door_in("lanchonete")],
	]
	for leg in legs:
		label = str(leg[0])
		wv._go_to(leg[1])
		var t0 := Time.get_ticks_msec()
		while not wv.path.is_empty() and Time.get_ticks_msec() - t0 < 28000:
			await get_tree().process_frame
		for i in 30:
			await get_tree().process_frame
	recording = false
	var sorted: Array = frames.duplicate()
	sorted.sort()
	var total := 0.0
	for f in frames:
		total += float(f)
	var avg_ms := total / maxf(frames.size(), 1)
	var p99: float = sorted[int(sorted.size() * 0.99)] if not sorted.is_empty() else 0.0
	var worst: float = sorted[sorted.size() - 1] if not sorted.is_empty() else 0.0
	var over50 := sorted.filter(func(x): return x > 50.0).size()
	print("PERF quadros=%d  fps_medio=%.1f  1%%pior=%.1fms  pior=%.1fms  >33ms=%d  >50ms=%d" % [frames.size(), 1000.0 / avg_ms, p99, worst, spikes.size(), over50])
	var by_leg := {}
	for s in spikes:
		by_leg[s[1]] = int(by_leg.get(s[1], 0)) + 1
	print("PERF draw_calls=%.0f primitivas=%.0f" % [_avg_of(draws), _avg_of(prims)])
	print("PERF engasgos por trecho: ", by_leg)
	print("PERF piores: ", spikes.slice(0, 12))
	SaveManager.delete_save()
	get_tree().quit()


func _avg_of(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += float(v)
	return t / maxf(a.size(), 1)
