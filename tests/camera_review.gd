extends Node

const View = preload("res://world3d/world_view.gd")
var view
var failures: Array[String] = []
var out := "C:/Users/glznc/Documents/Codex/2026-10-12/camera_dupla"
var data := {}

func check(ok: bool, label: String) -> void:
	print("CAMERA CHECK ", "OK " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func _ready() -> void:
	seed(72451)
	Settings.local_dialogue = true
	Settings.graphics = 1
	Settings.camera_mode = 0
	Settings.storage_path = out + "/fixture_settings.cfg"
	Settings.api_key = ""
	Settings.model = ""
	WorldEvents.random_enabled = false
	View.realtime = false
	SaveManager.path = out + "/camera_fixture.json"
	get_window().size = Vector2i(1280, 800)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({"name": "Revisão câmera", "age": 30, "gender": "homem", "cenario": "porto_cinza", "origin": origin["id"], "money": 500, "home": "apartamento", "location": "rua", "look": {"pele": 2, "cabelo": 0, "roupa": 1}, "inventory": {"agua": 1}, "alive": true})
	NPCManager.reset_state(origin)
	NeedsSystem.reset({})
	TimeManager.total_minutes = 1440 + 11 * 60
	if OS.get_environment("CAMERA_INPUT_ONLY") == "1":
		await settings_overlay()
		var result := FileAccess.open(out + "/camera_input.json", FileAccess.WRITE)
		result.store_string(JSON.stringify({"failures": failures}, "\t"))
		print("CAMERA INPUT RESULT ", failures)
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	view = View.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.world_ready.connect(func(): view.rng.seed = 5121)
	add_child(view)
	while not view._built:
		await get_tree().process_frame
	var location: Vector2 = view.layout.door_out("mercado")
	view.player.position = Vector3(location.x, 0.25, location.y)
	view.player.velocity = Vector3.ZERO
	view.path.clear()
	view.cam_target = view.player.position + Vector3.UP
	view.zoom = 16
	await wait_frames(120)
	data["iso"] = await measure()
	if OS.get_environment("CAMERA_BEFORE") != "1":
		await exercise()
	DirAccess.make_dir_recursive_absolute(out)
	var filename := "before.json" if OS.get_environment("CAMERA_BEFORE") == "1" else "after.json"
	var file := FileAccess.open(out + "/" + filename, FileAccess.WRITE)
	data["failures"] = failures
	file.store_string(JSON.stringify(data, "\t"))
	print("CAMERA RESULT ", data)
	get_tree().quit(0 if failures.is_empty() else 1)

func wait_frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame

func measure() -> Dictionary:
	var frames: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in 360:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now
	var total := 0.0
	for ms in frames:
		total += ms
	frames.sort()
	return {"fps": 360000.0 / total, "p99_ms": frames[356], "worst_ms": frames.back()}

func exercise() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	var player_id: int = view.player.get_instance_id()
	var city_id: int = view.city.get_instance_id()
	var skeleton_id: int = view.player_fig.skel.get_instance_id()
	var needs: Dictionary = NeedsSystem.to_dict()
	var money := GameState.money()
	var inventory: Dictionary = GameState.player.get("inventory", {}).duplicate(true)
	var position: Vector3 = view.player.global_position
	view.path = PackedVector2Array([view._p2() + Vector2(3, 0)])
	var path_before: PackedVector2Array = view.path.duplicate()
	view.set_camera_mode(1, false, false)
	check(view.is_third_person() and view.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "perspectiva ativa")
	check(view.player.get_instance_id() == player_id and view.city.get_instance_id() == city_id and view.player_fig.skel.get_instance_id() == skeleton_id, "mesmo corpo, cidade e esqueleto")
	check(view.player.global_position.is_equal_approx(position) and view.path == path_before, "troca preserva posição e rota")
	check(GameState.money() == money and NeedsSystem.to_dict() == needs and GameState.player.get("inventory", {}) == inventory, "troca preserva necessidades e economia")
	view.path.clear()
	await wait_frames(120)
	data["third"] = await measure()
	check(not view.layout.in_building("mercado", Vector2(view.camera.global_position.x, view.camera.global_position.z)), "câmera externa não recua pela porta do mercado")
	check(view.env.fog_sky_affect < 0.2, "céu diurno não é coberto pela névoa")
	var sk: Skeleton3D = view.player_fig.skel
	var head: Vector3 = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin + Vector3.UP * 0.18
	check(view.camera.unproject_position(head).y > 0 and view.camera.unproject_position(view.player.global_position).y < view.viewport.size.y, "corpo inteiro no enquadramento padrão junto à fachada")
	await capture("terceira_pessoa")
	for angle in [0.0, PI / 2, PI, -PI / 2]:
		view.camera_rig._yaw = angle
		var direction: Vector3 = view.movement_direction(Vector2(0, -1))
		check(direction.distance_to(-Basis(Vector3.UP, angle).z) < 0.001, "W acompanha câmera %.2f" % angle)
		check(absf(view.movement_direction(Vector2(1, -1)).length() - 1) < 0.001, "diagonal normalizada")
	view.camera_rig.rotate_view(Vector2(0, 100000), 0.003, false)
	check(is_equal_approx(view.camera_rig.pitch, -1.05), "limite vertical inferior")
	view.camera_rig.rotate_view(Vector2(0, -100000), 0.003, false)
	check(is_equal_approx(view.camera_rig.pitch, 0.48), "olha para cima com limite")
	view.camera_rig.pitch = -0.14
	view.camera_rig.yaw = view.player_fig.rotation.y + PI
	view.camera_rig.zoom_view(0.0001)
	check(is_equal_approx(view.camera_rig.distance, 1.8), "zoom mínimo")
	view.camera_rig.zoom_view(10000)
	check(is_equal_approx(view.camera_rig.distance, 8.0), "zoom máximo")
	view.camera_rig.distance = 4.6
	await wait_frames(60)
	await camera_collision()
	await actions_and_inputs()
	await nearby_and_interior()
	view.set_camera_mode(0, false, false)
	check(view.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and view.camera.near == 70, "retorno isométrico com recorte original")
	check(view.movement_direction(Vector2(0, -1)).distance_to(Vector3(-1, 0, -1).normalized()) < 0.001, "W isométrico preservado")
	await wait_frames(30)
	await capture("isometrica")
	Settings.set_camera_mode(1, false)
	Settings.camera_key = KEY_F6
	Settings.apply_camera_inputs()
	Settings.save_settings()
	var config := ConfigFile.new()
	check(config.load(Settings.storage_path) == OK and config.get_value("camera", "modo") == 1, "preferência salva fora do save da partida")
	var toggle := InputEventKey.new()
	toggle.physical_keycode = KEY_F6
	toggle.pressed = true
	check(toggle.is_action_pressed("camera_toggle"), "atalho remapeado no InputMap")
	check(SaveManager.VERSION == 1 and SaveManager.save_game() and SaveManager.load_game(), "save v1 continua carregando")
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.path))
	legacy.erase("calendar")
	SaveManager.path = out + "/camera_legacy_fixture.json"
	var legacy_file := FileAccess.open(SaveManager.path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.close()
	check(SaveManager.load_game(), "save anterior sem calendário continua carregando")
	Settings.camera_key = KEY_V
	Settings.apply_camera_inputs()
	view.set_camera_mode(0, false, false)
	await settings_overlay()

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	view.get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")

func camera_collision() -> void:
	var rig = view.camera_rig
	var clear_length: float = rig.third.global_position.distance_to(rig._focus)
	var wall_length := minf(2.4, clear_length * 0.65)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 4, 0.3)
	shape.shape = box
	body.add_child(shape)
	view.viewport.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.UP, rig._yaw), view._third_focus() + Basis.from_euler(Vector3(rig._pitch, rig._yaw, 0)).z * wall_length)
	await wait_frames(30)
	var length: float = rig.third.global_position.distance_to(rig._focus)
	check(length < wall_length - 0.15 and length < clear_length - 0.25, "câmera recua antes da parede")
	data["wall_distance"] = length
	body.queue_free()
	await wait_frames(90)
	check(rig.third.global_position.distance_to(rig._focus) >= clear_length - 0.1, "câmera volta suavemente ao liberar espaço respeitando fachada")

func actions_and_inputs() -> void:
	var position: Vector3 = view.player.global_position
	for pose in ["sentar", "comer", "deitado"]:
		view.player_fig.activity = "sentar" if pose == "sentar" else ""
		view.player_fig.lying = pose == "deitado"
		view._act = {"stage": "manter", "kind": pose, "plan": {"pose": pose}, "t": 0.0, "effect": func(): pass, "applied": true}
		view.set_camera_mode(0, false, false)
		view.set_camera_mode(1, false, false)
		check(not view._act.is_empty() and view.player.global_position.is_equal_approx(position), "troca durante " + pose)
		view._act.clear()
	view.player_fig.lying = false
	view.player_fig.activity = ""
	view._rmb_down = true
	view._orbit_drag = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	view.pause_check = func(): return true
	view._input(InputEventMouseMotion.new())
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not view._rmb_down, "menu recupera cursor")
	var mode: int = view.camera_rig.mode
	var key := InputEventKey.new()
	key.physical_keycode = KEY_V
	key.pressed = true
	view._unhandled_key_input(key)
	check(view.camera_rig.mode == mode, "menu bloqueia alternância por tecla")
	view.pause_check = Callable()
	var line := LineEdit.new()
	add_child(line)
	line.grab_focus()
	view._unhandled_key_input(key)
	check(view.camera_rig.mode == mode, "digitar V não muda câmera")
	line.release_focus()
	line.queue_free()
	var button := InputEventMouseButton.new()
	button.position = Vector2(40, 40)
	button.pressed = true
	button.button_index = MOUSE_BUTTON_LEFT
	view.path.clear()
	view._gui_input(button)
	check(view.path.is_empty(), "clique vazio em terceira pessoa não cria rota")
	view.set_camera_mode(0, false, false)
	view._gui_input(button)
	check(not view.path.is_empty(), "clique para andar preservado no isométrico")
	view.path.clear()
	view.set_camera_mode(1, false, false)
	var moving_goal: Vector2 = view._p2() + Vector2(2, 0)
	view._go_to(moving_goal)
	var saved_path: PackedVector2Array = view.path.duplicate()
	view.set_camera_mode(0, true, false)
	check(view.path == saved_path, "transição curta não cancela navegação")
	await wait_frames(40)
	check(view.camera_rig.mode == 0 and view._camera_dim.color.a < 0.01, "transição finaliza sem tela preta")
	view.path.clear()
	view.set_camera_mode(1, false, false)

func nearby_and_interior() -> void:
	Engine.max_fps = 60
	var received := {"object": "", "npc": ""}
	view.object_chosen.connect(func(target: Dictionary): received["object"] = target["key"])
	view.npc_menu.connect(func(id: String): received["npc"] = id)
	var target: Dictionary = view.city.objects["mercado/banco"]
	var stand: Vector2 = target["plan"]["path"].back()
	view.player.position = Vector3(stand.x, 0.25, stand.y)
	view.player.velocity = Vector3.ZERO
	view.camera_rig.yaw = PI
	await wait_frames(30)
	view.interact_nearby()
	check(received["object"] != "" or received["npc"] != "", "E usa objetos/NPCs registrados no mundo")
	var shop: Dictionary = {}
	for item in view.city.objects.values():
		if item["kind"] == "shop" and "agua" in item.get("items", []):
			shop = item
	var door: Vector2 = view.layout.door_in("mercado")
	view.player.position = Vector3(door.x, 0.25, door.y)
	view.player.velocity = Vector3.ZERO
	view._update_location()
	view._cutaway()
	view.cam_target = view.player.position + Vector3.UP
	view.camera_rig.set_mode(0, view._third_focus(), 0)
	view.set_camera_mode(1, false, false)
	await wait_frames(40)
	check(view.city.loc_info["mercado"]["structure"]["cut_now"] and view.object_access(shop), "interior e prateleira continuam acessíveis")
	await capture("interior_terceira")
	var bought := {"count": 0}
	var quantity := GameState.item_count("agua")
	var money := GameState.money()
	var started: bool = view.start_object_action(shop, "pegar", func() -> bool:
		bought["count"] += 1
		Economy.buy("agua")
		return GameState.item_count("agua") > quantity, "agua")
	check(started, "compra física inicia em terceira pessoa")
	var switched := false
	var deadline := Time.get_ticks_msec() + 35000
	while view.action_busy() and Time.get_ticks_msec() < deadline:
		if not switched and view._act.get("stage") == "animar":
			view.set_camera_mode(0, false, false)
			view.set_camera_mode(1, false, false)
			switched = true
		await get_tree().process_frame
	check(switched and not view.action_busy() and bought["count"] == 1 and GameState.item_count("agua") == quantity + 1 and GameState.money() == money - World.item_price("agua"), "trocar durante coleta preserva contato e compra única")
	if view.action_busy():
		view._cancel_action("Revisão: timeout")
	Engine.max_fps = 0
	TimeManager.total_minutes = 1440 + 21 * 60
	view._update_environment()
	await wait_frames(60)
	check(view.camera.current and view.env.background_mode == Environment.BG_SKY, "terceira pessoa mantém noite e céu")
	await capture("terceira_noite")
	WorldEvents.start("tempestade", 1)
	view._update_environment()
	await wait_frames(60)
	check(WorldEvents.raining() and view.camera.current, "chuva mantém câmera e mundo existentes")
	check(view.env.fog_sky_affect > 0.5, "chuva aumenta névoa no céu")
	await capture("terceira_chuva")
	WorldEvents.stop("tempestade")
	TimeManager.total_minutes = 1440 + 11 * 60
	view._update_environment()

func settings_overlay() -> void:
	if is_instance_valid(view):
		view.queue_free()
		await wait_frames(3)
	Settings.camera_mode = 0
	var screen = preload("res://ui/game_screen.gd").new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	while not screen.world_view._built:
		await get_tree().process_frame
	var world_id: int = screen.world_view.get_instance_id()
	var player_id: int = screen.world_view.player.get_instance_id()
	view = screen.world_view
	await wait_frames(3)
	await real_orbit()
	screen._settings()
	check(screen.world_view._paused() and is_instance_valid(screen.settings_overlay), "configurações sobre a partida")
	screen.settings_overlay.camera_opt.select(1)
	screen.settings_overlay._back()
	await wait_frames(3)
	check(screen.world_view.get_instance_id() == world_id and screen.world_view.player.get_instance_id() == player_id and screen.world_view.is_third_person(), "voltar das configurações mantém mundo e aplica câmera")
	var toggle := InputEventKey.new()
	toggle.physical_keycode = KEY_V
	toggle.keycode = KEY_V
	toggle.pressed = true
	Input.parse_input_event(toggle)
	await wait_frames(1)
	toggle.pressed = false
	Input.parse_input_event(toggle)
	await wait_frames(40)
	check(not screen.world_view.is_third_person(), "V despachado pelo Godot alterna na interface real")
	screen.world_view.set_camera_mode(1, false, false)
	var bank: Dictionary = screen.world_view.city.objects["mercado/banco"]
	var stand: Vector2 = bank["plan"]["path"].back()
	screen.world_view.player.position = Vector3(stand.x, 0.25, stand.y)
	screen.world_view.player.velocity = Vector3.ZERO
	screen.world_view._update_location()
	await wait_frames(10)
	var interact := InputEventKey.new()
	interact.physical_keycode = KEY_E
	interact.keycode = KEY_E
	interact.pressed = true
	# E já avança narração no diálogo existente. Essa prioridade é preservada;
	# conferir a interação do mundo depois de concluir a leitura, como o jogador faria.
	if screen.dialogue.visible and screen.dialogue.mode == "mensagem":
		Input.parse_input_event(interact)
		await wait_frames(2)
		interact.pressed = false
		Input.parse_input_event(interact)
		check(not screen.object_menu.visible and not screen.context_menu.visible, "E preserva prioridade da mensagem narrativa")
		var advance_message := InputEventKey.new()
		advance_message.physical_keycode = KEY_ENTER
		advance_message.keycode = KEY_ENTER
		for step in 20:
			if screen.dialogue.mode != "mensagem":
				break
			advance_message.pressed = true
			Input.parse_input_event(advance_message)
			await wait_frames(2)
			advance_message.pressed = false
			Input.parse_input_event(advance_message)
			await wait_frames(2)
		await wait_frames(40)
	interact.pressed = true
	Input.parse_input_event(interact)
	await wait_frames(2)
	interact.pressed = false
	Input.parse_input_event(interact)
	check(screen.object_menu.visible or screen.context_menu.visible, "E despachado pelo Godot abre menu existente")
	screen.object_menu.hide()
	screen.context_menu.hide()
	Engine.max_fps = 60
	var sidewalk: Vector2 = screen.world_view.layout.door_out("praca")
	screen.world_view.player.position = Vector3(sidewalk.x, 0.25, sidewalk.y)
	screen.world_view.player.velocity = Vector3.ZERO
	screen.world_view.path.clear()
	screen.world_view.camera_rig.yaw = screen.world_view.player_fig.rotation.y + PI
	screen.world_view.camera_rig._yaw = screen.world_view.camera_rig.yaw
	await wait_frames(10)
	var start: Vector2 = screen.world_view._p2()
	var expected: Vector3 = screen.world_view.camera_rig.forward()
	var walking := InputEventKey.new()
	walking.physical_keycode = KEY_W
	walking.keycode = KEY_W
	walking.pressed = true
	Input.parse_input_event(walking)
	await wait_frames(40)
	var advance: Vector2 = screen.world_view._p2() - start
	check(advance.length() > 0.3 and advance.normalized().dot(Vector2(expected.x, expected.z)) > 0.95, "W real move a cápsula na direção da câmera")
	start = screen.world_view._p2()
	toggle.pressed = true
	Input.parse_input_event(toggle)
	await wait_frames(1)
	toggle.pressed = false
	Input.parse_input_event(toggle)
	await wait_frames(24)
	advance = screen.world_view._p2() - start
	check(not screen.world_view.is_third_person() and advance.length() > 0.2 and advance.normalized().dot(Vector2(expected.x, expected.z)) > 0.95, "trocar para isométrica segurando W preserva direção")
	walking.pressed = false
	Input.parse_input_event(walking)
	await wait_frames(10)
	check(not screen.world_view._retain_move_keys, "soltar a tecla devolve os eixos clássicos")
	Engine.max_fps = 0
	screen.queue_free()
	await wait_frames(3)

func real_orbit() -> void:
	view.set_camera_mode(1, false, false)
	var yaw: float = view.camera_rig.yaw
	var button := InputEventMouseButton.new()
	button.position = Vector2(380, 230)
	button.global_position = button.position
	button.button_index = MOUSE_BUTTON_RIGHT
	button.pressed = true
	Input.parse_input_event(button)
	await wait_frames(1)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(410, 230)
	motion.global_position = motion.position
	motion.relative = Vector2(30, 0)
	motion.screen_relative = motion.relative
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(motion)
	await wait_frames(1)
	check(view._orbit_drag and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and absf(angle_difference(yaw, view.camera_rig.yaw)) > 0.04, "arraste direito real gira câmera")
	button.pressed = false
	Input.parse_input_event(button)
	await wait_frames(1)
	check(not view._rmb_down and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "soltar botão direito real devolve cursor")
	view.set_camera_mode(0, false, false)
