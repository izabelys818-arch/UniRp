extends Node

const Layout = preload("res://world3d/city_layout.gd")
const View = preload("res://world3d/world_view.gd")
const UITheme = preload("res://ui/ui_theme.gd")
var failures: Array[String] = []
var view
var frames: Array[float] = []
var recording := false
var checks := 0
var generation_worst := 0
var operation_worst := 0
var generation_over_budget := 0


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("WORLD_STREAM INTERROMPIDO: janela fechada antes do resultado")
		get_tree().quit(2)


func check(ok: bool, label: String) -> void:
	checks += 1
	print("STREAM ", "OK " if ok else "FALHOU ", label)
	if not ok:
		failures.append(label)


func _mock(_messages: Array) -> Dictionary:
	return {"ok": true, "text": "{\"fala\":\"Tudo bem.\",\"emocao\":\"neutro\"}"}


func _process(delta: float) -> void:
	if recording:
		frames.append(delta * 1000.0)


func _settle() -> void:
	var started := Time.get_ticks_msec()
	while not view.chunks.settled() and Time.get_ticks_msec() - started < 120000:
		await get_tree().process_frame
	check(view.chunks.settled(), "fila terminou")
	generation_worst = maxi(generation_worst, view.chunks.generation_worst_us)
	operation_worst = maxi(operation_worst, view.chunks.operation_worst_us)
	generation_over_budget = maxi(generation_over_budget, view.chunks.over_budget)
	for i in 30:
		await get_tree().process_frame


func _shot(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	view.viewport.get_texture().get_image().save_png("res://evidencias_mundo/" + label + ".png")
	await get_tree().process_frame
	await get_tree().process_frame


func _fingerprint(region, coords: Array) -> Dictionary:
	var result := {}
	for coord in coords:
		for cell in region.chunk_cells[coord]:
			var block: Dictionary = region.blocks[cell]
			var houses := {}
			for id in block["lots"]:
				houses[id] = region.lots[id].duplicate(true)
			result[str(cell)] = {"block": block.duplicate(true), "lots": houses}
	return result


func _check_generation_order() -> void:
	var coords := [Vector2i(-7, 11), Vector2i(14, 3), Vector2i(67, 5), Vector2i(130, -22)]
	var first := Layout.new()
	for coord in coords:
		first.ensure_chunk(coord)
	var reference := _fingerprint(first, coords)
	var second := Layout.new()
	var reversed := coords.duplicate()
	reversed.reverse()
	for coord in reversed:
		second.ensure_chunk(coord)
	check(reference == _fingerprint(second, coords), "conteúdo independe da ordem de carga")
	for coord in coords:
		second.release_chunk(coord)
	for coord in reversed:
		second.ensure_chunk(coord)
	check(reference == _fingerprint(second, coords), "conteúdo idêntico após regenerar regiões")
	GameState.player["age"] = 17
	check(not World.is_accessible("boate") and World.door_locked("boate"), "boate bloqueada para menor")
	GameState.player["age"] = 30
	check(World.is_accessible("boate"), "boate acessível ao adulto")


func _ready() -> void:
	get_tree().auto_accept_quit = false
	AIService.mock = _mock
	SaveManager.path = "res://evidencias_mundo/stream_save.json"
	WorldEvents.random_enabled = false
	View.realtime = false
	get_window().content_scale_size = Vector2i(1280, 800)
	get_window().size = Vector2i(1280, 800)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({"name": "Revisão", "age": 30, "gender": "homem", "appearance": "x", "look": {}, "appearance_extra": "", "backstory": "", "traits": [],
		"cenario": "porto_cinza", "origin": origin["id"], "money": 50000, "location": "praca", "home": "apartamento", "inventory": {}, "alive": true})
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	TimeManager.total_minutes = 11 * 60
	# Compara coordenadas com o código anterior preservado, no mesmo cenário.
	var old_script := GDScript.new()
	old_script.source_code = FileAccess.get_file_as_string("res://evidencias_mundo/source_before/world3d/city_layout.gd.txt")
	check(old_script.reload() == OK, "referência anterior compilou")
	var before = old_script.new()
	var original: Dictionary = before.lots.duplicate(true)
	_check_generation_order()
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
	var map = screen.map_panel.map_view
	var place_count := World.locations.size()
	map._share_layout()
	check(map.layout == view.layout and World.locations.size() == place_count, "mapa compartilha Layout sem recriar metadados")
	for id in original:
		check(view.layout.lots.has(id) and view.layout.lots[id]["building"] == original[id]["building"] and view.layout.lots[id]["door"] == original[id]["door"], "coordenadas antigas " + id)
	await _settle()
	await _shot("centro_iso")
	var points := [Vector2(405, 165), Vector2(845, 165), Vector2(1445, 165), Vector2(2645, 405), Vector2(4205, 165), Vector2(-245, 165), Vector2(165, -245), Vector2(165, 565), Vector2(4645, 5)]
	var peak_nodes := 0
	for index in points.size():
		view.player.position = Vector3(points[index].x, 0.25, points[index].y)
		view.path.clear()
		view.cam_target = view.player.position
		view.chunks.update_focus(points[index])
		recording = true
		await _settle()
		recording = false
		map._fit()
		check(map._bounds.has_point(points[index]), "mapa acompanha região externa")
		check(view.chunks.active.size() <= 169, "número limitado de chunks")
		check(view.layout.street_nodes.size() < 1000, "grafo limitado à região")
		var route: PackedVector2Array = view.layout.route(points[index], points[index] + Vector2(120, 0))
		check(route.size() >= 2 and route[route.size() - 1].distance_to(points[index] + Vector2(120, 0)) < 0.01, "rota atravessa chunks")
		for step_index in range(1, route.size()):
			var diff: Vector2 = route[step_index] - route[step_index - 1]
			check(absf(diff.x) < 0.01 or absf(diff.y) < 0.01, "rota segue ruas ortogonais")
		var coord := Layout.chunk_at(points[index])
		var seed_a: int = view.layout.seed_chunk(coord)
		check(seed_a == view.layout.seed_chunk(coord), "semente repetível")
		peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		print("STREAM METRICS ring=", Layout.density_ring(points[index]), " chunks=", view.chunks.active.size(), " graph=", view.layout.street_nodes.size(), " nodes=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT), " mem_mb=", OS.get_static_memory_usage() / 1048576.0,
			" registry_grass=", preload("res://world3d/grass_field.gd").patches.size(), " registry_foliage=", preload("res://world3d/foliage.gd").spheres.size())
		view.set_camera_mode(1, false, false)
		for i in 45:
			await get_tree().process_frame
		await _shot("anel_%d_terceira" % index)
		view.set_camera_mode(0, false, false)
	# Imóvel fora do centro: contrato, fechadura, mobília, posição e save v1.
	view.player.position = Vector3(845, 0.25, 165)
	view.chunks.update_focus(Vector2(845, 165))
	await _settle()
	var selected := ""
	for id in view.layout.house_ids:
		if not Layout.central_cell(view.layout.lots[id]["cell"]):
			selected = id
			break
	check(selected != "", "moradia externa existe")
	if selected != "":
		var door: Vector2 = view.layout.lots[selected]["door"]
		var state := Houses.st(selected).duplicate(true)
		Houses.st(selected)["lock"] = "broken"
		HomeSystem.housing()["contracts"][selected] = {"tipo": "propria", "aluguel": 0}
		HomeSystem.housing()["moveis"][selected] = ["cama", "tv"]
		view.player.position = Vector3(4205, 0.25, 165)
		view.chunks.update_focus(Vector2(4205, 165))
		await _settle()
		check(Houses.all()[selected]["lock"] == "broken" and HomeSystem.furniture(selected) == ["cama", "tv"], "estado persiste após descarregar")
		view.player.position = Vector3(door.x, 0.25, door.y + 2)
		view.chunks.update_focus(Vector2(door.x, door.y + 2))
		await _settle()
		check(view.layout.lots[selected]["door"] == door, "imóvel retorna na mesma posição")
		check(SaveManager.save_game() and SaveManager.load_game(), "save/reload v1")
		var saved_position: Array = GameState.player["pos"].duplicate()
		check(not Layout.stream_state()["npc_positions"].is_empty(), "posições dos NPCs persistidas no save")
		screen.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		screen = preload("res://ui/game_screen.gd").new()
		screen.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(screen)
		view = screen.world_view
		while not view._built:
			await get_tree().process_frame
		var copies := 0
		for structure in view.city.structures:
			if str(structure.get("loc", "")) == selected:
				copies += 1
		check(copies == 1, "save não duplica a construção externa")
		check(view.layout.lots.has(selected) and view.layout.lots[selected]["door"] == door, "imóvel externo reconstituído ao carregar")
		check(view._p2().distance_to(Vector2(float(saved_position[0]), float(saved_position[1]))) < 0.02, "reconstrução do jogo restaura posição salva")
		check(Houses.all()[selected]["lock"] == "broken" and HomeSystem.has_access(selected), "contrato/fechadura restaurados")
		check(GameState.player["pos"].size() == 2, "posição preservada")
		Houses.all()[selected] = state
	var old_data := {"player": GameState.player.duplicate(true), "log": []}
	old_data["player"].erase("world_stream")
	view._built = false
	GameState.from_dict(old_data)
	check(GameState.player["world_stream"]["seed"] == 7741, "save antigo recebe default")
	Layout.new()
	var landmarks: Dictionary = Layout.stream_state()["landmarks"]
	check(landmarks.size() == 11, "onze marcos únicos registrados")
	frames.sort()
	print("STREAM PERF frames=", frames.size(), " worst_ms=", frames.back() if not frames.is_empty() else 0, " generation_worst_ms=", max(generation_worst, view.chunks.generation_worst_us) / 1000.0,
		" operation_worst_ms=", max(operation_worst, view.chunks.operation_worst_us) / 1000.0, " above_6ms=", generation_over_budget + view.chunks.over_budget, " peak_nodes=", peak_nodes)
	print("RESULTADO WORLD_STREAM: ", "OK" if failures.is_empty() else "FALHOU", " checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
