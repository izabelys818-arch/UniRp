extends Node

# Captura e medição reais, partida somente em memória, sem acesso à partida do dono.
const View = preload("res://world3d/world_view.gd")
var view
var sample := false
var times: Array[float] = []
var draws: Array[int] = []
var output := "C:/Users/glznc/Documents/Codex/2026-10-11/urban"
var phase := "before"
var build_times: Array[float] = []
var focus := Vector3(105, 1.5, 106)
var direction := View.CAM_DIR
var framing := 48.0

func _process(delta: float) -> void:
	var cpu_start := Time.get_ticks_usec()
	if is_instance_valid(view) and not view._built:
		build_times.append(delta * 1000.0)
	if is_instance_valid(view) and view._built and not view.is_queued_for_deletion():
		view._process(delta)
		view.camera.position = focus + direction.normalized() * 150.0
		view.camera.look_at(focus)
		view.camera.size = framing
	if sample:
		if delta > 0.033:
			print("URBAN LONG FRAME delta_ms=", snappedf(delta * 1000.0, 0.1), " view_cpu_ms=", snappedf((Time.get_ticks_usec() - cpu_start) / 1000.0, 0.1))
		times.append(delta * 1000.0)
		draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))

func _ready() -> void:
	if OS.get_environment("URBAN_OUTPUT") != "":
		output = OS.get_environment("URBAN_OUTPUT")
	phase = OS.get_environment("URBAN_PHASE") if OS.get_environment("URBAN_PHASE") != "" else "before"
	DirAccess.make_dir_recursive_absolute(output + "/" + phase)
	get_window().content_scale_size = Vector2i(1280, 800)
	get_window().size = Vector2i(1280, 800)
	get_viewport().gui_disable_input = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(OS.get_environment("URBAN_FPS_CAP"))
	View.realtime = false
	View.trace = true
	preload("res://world3d/city_layout.gd").urban_prototype_enabled = phase != "before"
	WorldEvents.random_enabled = false
	SaveManager.path = "user://urban_review_unused.json"
	for scenario in ["porto_cinza", "vale_sereno", "nova_aurora", "colapso"]:
		if OS.get_environment("URBAN_ONLY_SCENE") != "" and scenario != OS.get_environment("URBAN_ONLY_SCENE"):
			continue
		var origin := World.get_origin("morador_antigo")
		GameState.new_game({"name": "Auditoria", "age": 30, "gender": "homem", "cenario": scenario,
			"origin": origin["id"], "money": 400, "location": "rua", "home": "apartamento", "inventory": {}, "alive": true,
			"look": {"pele": 2, "cabelo": 0, "barba": 1, "roupa": 1, "corpo": 1}})
		NPCManager.reset_state(origin)
		NeedsSystem.reset({})
		WorldEvents.stop("tempestade")
		TimeManager.total_minutes = 1440 + 660
		var started := Time.get_ticks_msec()
		build_times.clear()
		view = View.new()
		view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(view)
		while not view._built:
			await get_tree().process_frame
		print("URBAN READY ", phase, " ", scenario, " ms=", Time.get_ticks_msec() - started)
		build_times.sort()
		print("URBAN BUILD FRAMES p99_ms=", snappedf(build_times[int(build_times.size() * 0.99)], 0.1), " worst_ms=", snappedf(build_times.back(), 0.1))
		view.set_process(false)
		view.rng.seed = 31415
		view.player.position = Vector3(105, 0.25, 122)
		view.zoom = 48.0
		view.path.clear()
		for mode in [["dia", 11.0, false], ["tarde", 17.0, false], ["noite", 21.5, false], ["chuva", 14.0, true]]:
			if OS.get_environment("URBAN_ONLY_MODE") != "" and str(mode[0]) != OS.get_environment("URBAN_ONLY_MODE"):
				continue
			TimeManager.total_minutes = 1440 + int(float(mode[1]) * 60)
			if mode[2]:
				WorldEvents.start("tempestade", 5)
			else:
				WorldEvents.stop("tempestade")
			view._update_environment()
			view._sync_npcs()
			for frame in 150:
				await get_tree().process_frame
			times.clear()
			draws.clear()
			sample = true
			var sample_frames := int(OS.get_environment("URBAN_SAMPLE_FRAMES")) if OS.get_environment("URBAN_SAMPLE_FRAMES") != "" else 600
			for frame in sample_frames:
				await get_tree().process_frame
			sample = false
			var total := 0.0
			var dc := 0.0
			for ms in times:
				total += ms
			for draw in draws:
				dc += draw
			times.sort()
			var visible_peds := 0
			for ped in view.life.peds:
				if ped["fig"].visible:
					visible_peds += 1
			print("URBAN SAMPLE ", phase, " ", scenario, " ", mode[0], " fps=", snappedf(times.size() * 1000.0 / total, 0.1),
				" p99_ms=", snappedf(times[int(times.size() * 0.99)], 0.1), " worst_ms=", snappedf(times.back(), 0.1),
				" draws=", snappedf(dc / draws.size(), 1), " visible_peds=", visible_peds)
			await RenderingServer.frame_post_draw
			view.viewport.get_texture().get_image().save_png(output + "/" + phase + "/" + scenario + "_" + str(mode[0]) + ".png")
		view.queue_free()
		await get_tree().process_frame
		view = null
	get_tree().quit()
