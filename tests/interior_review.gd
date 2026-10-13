extends Node

const View = preload("res://world3d/world_view.gd")
const Furn = preload("res://world3d/furn_lib.gd")
const OUT := "C:/Users/glznc/Documents/Codex/2026-10-12/interiores"
var view
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	print("INTERIOR CHECK ", "OK " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame

func _ready() -> void:
	seed(82711)
	Settings.api_key = ""
	Settings.model = ""
	Settings.storage_path = OUT + "/settings_fixture.cfg"
	Settings.camera_mode = 0
	Settings.graphics = 1
	SaveManager.path = OUT + "/save_fixture.json"
	View.realtime = false
	WorldEvents.random_enabled = false
	get_window().size = Vector2i(1280, 800)
	Engine.max_fps = 60
	Engine.time_scale = 3.0
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({"name": "Revisão interiores", "age": 28, "gender": "homem", "cenario": "porto_cinza", "origin": origin["id"], "money": 500, "home": "apartamento", "location": "rua", "look": {"pele": 2, "cabelo": 0, "roupa": 1}, "inventory": {}, "alive": true})
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	TimeManager.total_minutes = 1440 + 11 * 60
	view = View.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	while not view._built:
		await get_tree().process_frame
	var id := ""
	for candidate in view.layout.house_ids:
		if str(World.locations[candidate].get("nome", "")).begins_with("Casa 122, Rua Santa Rita"):
			id = candidate
			break
	if id == "":
		id = view.layout.house_ids[0]
	print("INTERIOR HOUSE ", id, " ", World.locations[id]["nome"])
	Houses.st(id)["lock"] = "open"
	var structure: Dictionary = view.city.loc_info[id]["structure"]
	view.city.ensure_interior(structure)
	view.city.house_gen.place_now(structure["interior"])
	var door: Vector2 = view.layout.door_in(id)
	view.player.position = Vector3(door.x, 0.25, door.y)
	view.player.velocity = Vector3.ZERO
	view._update_location()
	view._cutaway()
	view.set_camera_mode(1, false, false)
	var heading: float = view.layout.dir_of(id).angle() - PI / 2.0
	if OS.get_environment("INTERIOR_BEFORE") != "1":
		var floor_node: Node3D = structure["floor_nodes"][0]
		print("INTERIOR PLACEMENTS ", floor_node.get_meta("placements"))
		print("INTERIOR REJECTED ", floor_node.get_meta("rejected"))
		check((floor_node.get_meta("ceiling") as Node3D).visible and (structure["full"] as Node3D).visible, "teto e fachada completos na terceira pessoa")
		check(not (structure["cut"] as Node3D).visible, "versão isométrica não substitui interior da terceira pessoa")
		var sofa: Dictionary = (floor_node.get_meta("use_points") as Dictionary).get("sofa", {})
		heading = float(sofa.get("yaw", 0)) + PI
		var stand: Vector2 = sofa.get("path", [door]).back()
		var inside := Vector3(stand.x, 0.25, stand.y)
		view.player.position = inside
		view.player.velocity = Vector3.ZERO
	view.camera_rig.yaw = heading
	view.camera_rig._yaw = view.camera_rig.yaw
	await frames(90)
	await RenderingServer.frame_post_draw
	var suffix := "antes" if OS.get_environment("INTERIOR_BEFORE") == "1" else "depois"
	view.get_viewport().get_texture().get_image().save_png(OUT + "/casa_terceira_" + suffix + ".png")
	var rows := []
	for path in Furn._info:
		rows.append({"model": str(path).get_file(), "size_m": str((Furn._info[path] as AABB).size * 0.2)})
	var file := FileAccess.open(OUT + "/models.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	if OS.get_environment("INTERIOR_BEFORE") != "1":
		await exercise_floors()
	print("INTERIOR RESULT ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func exercise_floors() -> void:
	var building := {}
	for candidate in view.city.structures:
		if candidate.get("modern_interior", false) and int(candidate.get("floor_count", 1)) >= 3 and (candidate["rect"] as Rect2).size.x > 12:
			building = candidate
			break
	check(not building.is_empty(), "edifício com andares registrado no mundo")
	if building.is_empty():
		return
	print("INTERIOR TOWER ", building["loc"], " pisos=", building["floor_count"])
	view.city.ensure_interior(building)
	view.city.ensure_floor(building, 1)
	var bottom: Vector2 = building["stairs"][0]["bottom"]
	view.player.position = Vector3(bottom.x, 0.25, bottom.y)
	view.player.velocity = Vector3.ZERO
	view.path.clear()
	view._update_location()
	view._cutaway()
	await frames(5)
	check(view._route_floors(building, 1), "rota usa escada física até primeiro andar")
	var deadline := Time.get_ticks_msec() + 25000
	var last_size: int = view.path.size()
	while (not view.path.is_empty() or not view._floor_segments.is_empty()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if view.path.size() != last_size:
			last_size = view.path.size()
			print("INTERIOR STEP ", view.player.position, " points=", last_size)
	print("INTERIOR CLIMB position=", view.player.position, " path=", view.path, " segments=", view._floor_segments)
	for i in view.player.get_slide_collision_count():
		var collision = view.player.get_slide_collision(i)
		print("INTERIOR COLLISION ", collision.get_normal(), " ", collision.get_position())
	check(view._floor_in(building) == 1 and view.player.position.y > 2.7 and view.path.is_empty(), "subiu sem teletransporte nem salto")
	view._update_location()
	var saved_position: Vector3 = view.player.position
	check(SaveManager.save_game() and SaveManager.load_game() and absf(float(GameState.player.get("pos_height", 0)) - saved_position.y) < 0.01, "save preserva altura do andar")
	view._place_player(World.current_id(), true)
	check(view.player.position.distance_to(saved_position) < 0.15 and view._floor_in(building) == 1, "restaura posição no piso correto")
	var highest := int(building["floor_count"]) - 1
	check(view._route_floors(building, highest), "rota conecta todos os andares pela escada")
	deadline = Time.get_ticks_msec() + 90000
	while (not view.path.is_empty() or not view._floor_segments.is_empty()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(view._floor_in(building) == highest and absf(view.player.position.y - (0.245 + highest * float(building["floor_height"]))) < 0.18, "chega fisicamente ao último andar")
	view._update_location()
	saved_position = view.player.position
	check(SaveManager.save_game() and SaveManager.load_game(), "salva e carrega último andar")
	var tower_id := str(building["loc"])
	remove_child(view)
	view.queue_free()
	await frames(2)
	seed(82711)
	view = View.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	while not view._built:
		await get_tree().process_frame
	building = view.city.loc_info.get(tower_id, {}).get("structure", {})
	check(not building.is_empty() and view._floor_in(building) == highest and view.player.position.distance_to(saved_position) < 0.18, "reconstrução do mundo retoma andar e posição do save")
	view.path.clear()
	check(view._route_floors(building, 0), "rota desce pela mesma escada")
	deadline = Time.get_ticks_msec() + 90000
	while (not view.path.is_empty() or not view._floor_segments.is_empty()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	print("INTERIOR DESCEND ", view.player.position)
	check(view._floor_in(building) == 0 and view.player.position.y < 0.6, "desceu ao térreo sem teletransporte")
	GameState.player.erase("pos_height")
	GameState.player.erase("interior_floor")
	GameState.player["pos"] = [view.player.position.x, view.player.position.z]
	check(SaveManager.save_game() and SaveManager.load_game(), "save anterior sem campos de andar carrega")
	view._place_player(tower_id, true)
	check(view.player.position.y < 0.6, "save anterior mantém posição no térreo")
	var ground: Node3D = building["floor_nodes"][0]
	var fixture: Node3D = ground.get_node("Moveis").get_child(0)
	view.player.position = Vector3(fixture.global_position.x, 0.245, fixture.global_position.z)
	view._resolve_loaded_position()
	check(view.player.position.distance_to(Vector3(fixture.global_position.x, 0.245, fixture.global_position.z)) > 0.3 and view._floor_in(building) == 0, "posição antiga dentro de móvel recupera passagem no mesmo piso")
