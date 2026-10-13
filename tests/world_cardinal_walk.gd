extends "res://tests/world_stream_test.gd"

func _ready() -> void:
	AIService.mock = _mock
	SaveManager.path = "res://evidencias_mundo/cardinal_save.json"
	WorldEvents.random_enabled = false
	View.realtime = false
	View.trace = OS.get_environment("CARDINAL_TRACE") == "1"
	get_window().content_scale_size = Vector2i(1280, 800)
	get_window().size = Vector2i(1280, 800)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({"name": "Percurso", "age": 30, "gender": "homem", "appearance": "x", "look": {}, "appearance_extra": "", "backstory": "", "traits": [],
		"cenario": "porto_cinza", "origin": origin["id"], "money": 5000, "location": "praca", "home": "apartamento", "inventory": {}, "alive": true})
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	TimeManager.total_minutes = 11 * 60
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var screen = preload("res://ui/game_screen.gd").new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	view = screen.world_view
	while not view._built:
		await get_tree().process_frame
	view.set_camera_mode(0, false, false)
	await _settle()
	print("CARDINAL renderer=", RenderingServer.get_current_rendering_method(), " resolution=", view.viewport.size)
	var duration := float(OS.get_environment("CARDINAL_SECONDS")) if OS.get_environment("CARDINAL_SECONDS") != "" else 300.0
	var start := Vector2(165, 165)
	var actor := ""
	for id in view.npcs:
		if str(view.npcs[id]["loc"]) != "":
			actor = id
			break
	for leg in [["leste", Vector2.RIGHT], ["oeste", Vector2.LEFT], ["norte", Vector2.UP], ["sul", Vector2.DOWN]]:
		var direction: Vector2 = leg[1]
		view.player.position = Vector3(start.x, 0.25, start.y)
		view.cam_target = view.player.position
		view.chunks.update_focus(start)
		await _settle()
		NeedsSystem.reset({})
		view._go_to(start + direction * 2000.0)
		if actor != "" and leg[0] == "leste":
			var figure: Node3D = view.npcs[actor]["fig"]
			figure.position = Vector3(285, 0.17, 165)
			view.npcs[actor]["path"] = view.layout.route(Vector2(285, 165), Vector2(445, 165))
		var actor_crossed := false
		frames.clear()
		recording = true
		var t0 := Time.get_ticks_msec()
		var report_at := t0 + 15000
		var uncovered := 0
		var min_mem := INF
		var max_mem := 0.0
		while Time.get_ticks_msec() - t0 < duration * 1000.0:
			await get_tree().process_frame
			var point: Vector2 = view._p2()
			if actor != "" and view.npcs[actor]["fig"].position.x > 350.0:
				actor_crossed = true
			if Time.get_ticks_msec() >= report_at:
				report_at += 15000
				var coord := Layout.chunk_at(point)
				var central := coord.x >= 0 and coord.y >= 0 and coord.x < 4 and coord.y < 4
				if not central and not view.chunks.active.has(coord):
					uncovered += 1
				var memory := OS.get_static_memory_usage() / 1048576.0
				min_mem = minf(min_mem, memory)
				max_mem = maxf(max_mem, memory)
				print("CARDINAL PROGRESS ", leg[0], " t=", (Time.get_ticks_msec() - t0) / 1000.0, " pos=", point, " chunks=", view.chunks.active.size(), " queued=", view.chunks.queue.size(), " mem_mb=", memory)
				NeedsSystem.reset({})
		recording = false
		var finish: Vector2 = view._p2()
		var displacement := (finish - start).dot(direction)
		check(displacement > duration * 1.3, "caminhada física " + str(leg[0]))
		check(uncovered == 0, "chunk presente em todo o percurso " + str(leg[0]))
		check(view.chunks.active.size() <= 169, "memória limitada por região " + str(leg[0]))
		if leg[0] == "leste":
			check(actor_crossed, "NPC atravessou a antiga borda com a rota existente")
		frames.sort()
		var sum := 0.0
		for frame in frames:
			sum += frame
		print("CARDINAL RESULT ", leg[0], " seconds=", duration, " distance_m=", displacement, " fps=", frames.size() * 1000.0 / maxf(sum, 1), " worst_ms=", frames.back(),
			" over33=", frames.filter(func(f): return f > 33.0).size(), " mem_min_mb=", min_mem, " mem_max_mb=", max_mem)
		view.path.clear()
		view.set_camera_mode(1, false, false)
		for i in 45:
			await get_tree().process_frame
		await _shot("cardinal_" + str(leg[0]))
		view.set_camera_mode(0, false, false)
	print("CARDINAL GENERATION worst_ms=", view.chunks.generation_worst_us / 1000.0, " operation_ms=", view.chunks.operation_worst_us / 1000.0, " above6=", view.chunks.over_budget)
	print("RESULTADO CARDINAL: ", "OK" if failures.is_empty() else "FALHOU", " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
