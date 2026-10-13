extends Node

# Revisão reproduzível das correções de postura, rosto, terminal e alcance.
# REVIEW_OUT aponta para a pasta externa; nenhum save do jogador é lido/escrito.
const Person = preload("res://world3d/person.gd")
const Looks = preload("res://ui/face/look_builder.gd")
const Portrait = preload("res://ui/face/face_portrait.gd")
const Bank = preload("res://world3d/mixamo_bank.gd")
var out: String
var metrics: Dictionary = {}
var external_input_frames := 0
var input_guard: LineEdit

func _process(_delta: float) -> void:
	# O teclado físico pode cancelar a rota se a janela da revisão receber foco.
	# Isola apenas esta fixture; locomoção, física e entrada do jogo não são alteradas.
	for key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_SHIFT]:
		if Input.is_physical_key_pressed(key):
			external_input_frames += 1
			break
	if is_instance_valid(input_guard) and not input_guard.has_focus():
		input_guard.grab_focus()

func _ready() -> void:
	SaveManager.path = "user://repair_review_only.json"
	Settings.local_dialogue = true
	Settings.graphics = 1
	WorldEvents.random_enabled = false
	out = OS.get_environment("REVIEW_OUT")
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1440, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if OS.get_environment("REVIEW_WORLD_ONLY") != "1":
		await _bodies()
		await _portraits()
	if OS.get_environment("REVIEW_STUDIO_ONLY") != "1":
		await _world()
	var file := FileAccess.open(out + "/metrics.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(metrics, "\t"))
	var ok := true
	if OS.get_environment("REVIEW_STUDIO_ONLY") != "1":
		ok = bool(metrics.get("terminal_navigation", {}).get("ok", false))
		if OS.get_environment("REVIEW_TERMINAL_ONLY") != "1":
			ok = ok and bool(metrics.get("cancel", false)) and bool(metrics.get("save_v1", false)) and bool(metrics.get("legacy_no_calendar", false))
		for key in ([] if OS.get_environment("REVIEW_TERMINAL_ONLY") == "1" else ["market_pickup", "reach_height_0.2", "reach_height_0.85", "reach_height_1.35", "reach_age_9", "reach_age_76"]):
			var result: Dictionary = metrics.get(key, {})
			ok = ok and bool(result.get("started", false)) and bool(result.get("ended", false)) and bool(result.get("no_snap_back", false)) and float(result.get("min_hand_error_m", 1)) >= 0 and float(result.get("min_hand_error_m", 1)) < 0.035
			if key == "market_pickup":
				ok = ok and bool(result.get("paid_once", false)) and bool(result.get("item_once", false))
			else:
				ok = ok and int(result.get("calls", 0)) == 1
	metrics["passed"] = ok
	metrics["external_input_frames"] = external_input_frames
	file.seek(0)
	file.store_string(JSON.stringify(metrics, "\t"))
	print("REPAIR REVIEW DONE ", out)
	get_tree().quit(0 if ok else 1)

func _wait(n: int = 30) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("SHOT ", name)

func _video_frame(index: int) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(out + "/coleta_frame_%02d.jpg" % index, 0.88)

func _bodies() -> void:
	var studio := Node3D.new()
	add_child(studio)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#30343a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("#c5cbd3")
	env.environment.ambient_light_energy = 0.5
	studio.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, -35, 0)
	sun.shadow_enabled = true
	studio.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.3
	studio.add_child(cam)
	cam.position = Vector3(0, 1.1, 7)
	cam.look_at(Vector3(0, 1.05, 0))
	var figs: Array = []
	for i in 4:
		var fig := Person.new()
		fig.locomotion_turns = false
		studio.add_child(fig)
		fig.set_look(Looks.build({"pele": 2, "cabelo": 0, "corpo": [1, 3, 5, 0][i], "roupa": 1}, 30, "homem"))
		fig.position.x = -1.8 + i * 1.2
		fig.seed_n = 1.0
		figs.append(fig)
	await _wait(90)
	for i in figs.size():
		var fig: Node3D = figs[i]
		metrics["body%d" % i] = _pose(fig)
	await _shot("corpo_frente")
	for fig in figs:
		fig.rotation.y = PI / 2
	await _wait(30)
	await _shot("corpo_lado")
	var f: Node3D = figs[0]
	var source := Bank.Source.new(Bank.DIR + "idle.fbx")
	var source_walk := Bank.Source.new(Bank.DIR + "walk.fbx")
	var diagnostic := {}
	for name in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftArm", "LeftUpLeg"]:
		var b := source.bone(name)
		var w := source_walk.bone(name)
		diagnostic[name] = {"rest_idle": str(source.rest_g[b]), "rest_walk": str(source_walk.rest_g[w]), "pose_idle": str(source.pose(0.0)[b])}
	metrics["source"] = diagnostic
	metrics["blend_mode"] = f._face_mi.mesh.blend_shape_mode
	metrics["blend_normalized"] = Mesh.BLEND_SHAPE_MODE_NORMALIZED
	metrics["preview_turn_disabled"] = f.player_motion.state == "idle"
	source.free_scene()
	source_walk.free_scene()
	studio.queue_free()
	await _wait(2)

func _pose(fig) -> Dictionary:
	var sk: Skeleton3D = fig.skel
	var data := {}
	for name in ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head", "upperarm_l", "lowerarm_l", "hand_l", "thigh_l", "calf_l", "foot_l"]:
		data[name] = str(sk.get_bone_global_pose(sk.find_bone(name)))
	return data

func _portraits() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var names := ["neutro", "feliz", "rindo", "surpreso", "chorando", "sarcastico"]
	for sex in 2:
		for i in names.size():
			var f := Portrait.new()
			f.size = Vector2(240, 420)
			f.position = Vector2(i * 240, sex * 450)
			f.scene = "casa"
			root.add_child(f)
			f.set_look(Looks.build({"pele": 2, "cabelo": 4 if sex == 1 else 0, "cor_cabelo": 1, "roupa": 1, "marcas": []}, 30, "mulher" if sex == 1 else "homem"))
			f.set_emotion(names[i], true)
			var title := Label.new()
			title.text = names[i]
			title.position = f.position + Vector2(4, 421)
			root.add_child(title)
	for i in 350:
		await get_tree().process_frame
		await get_tree().create_timer(0.01).timeout
	for child in root.get_children():
		if child is Portrait:
			print("PORTRAIT ready=", child._person != null, " size=", child.size)
	await _shot("expressoes")
	root.queue_free()
	await _wait(3)

func _world() -> void:
	# O foco de texto já impede WASD no jogo; aproveita esse mecanismo na fixture.
	input_guard = LineEdit.new()
	input_guard.editable = false
	input_guard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_guard.modulate.a = 0.0
	input_guard.size = Vector2(1, 1)
	add_child(input_guard)
	input_guard.grab_focus()
	preload("res://world3d/world_view.gd").realtime = false
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({"name": "Revisão", "age": 30, "gender": "homem", "appearance": "x", "look": {"pele": 2, "cabelo": 0, "roupa": 1, "marcas": []}, "appearance_extra": "", "backstory": "", "traits": [], "cenario": "porto_cinza", "origin": origin["id"], "money": 400, "location": "rua", "home": "apartamento", "inventory": {}, "alive": true})
	TimeManager.total_minutes = 2040
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	var wv = preload("res://world3d/world_view.gd").new()
	wv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(wv)
	while not wv._built:
		await _wait(1)
	var r: Rect2 = wv.layout.lots["rodoviaria"]["rect"]
	metrics["terminal_rect"] = str(r)
	var center := r.get_center()
	wv.player.position = Vector3(center.x, 0.25, center.y + 5)
	wv.cam_target = wv.player.position + Vector3(0, 1, 0)
	wv.zoom = 33
	wv.camera.size = 33
	await _wait(120)
	await _shot("rodoviaria_dia")
	var frames: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in 360:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append(float(now - last) / 1000.0)
		last = now
	var sum := 0.0
	for ms in frames:
		sum += ms
	frames.sort()
	metrics["terminal_performance"] = {"fps": 1000.0 / (sum / frames.size()), "p99_ms": frames[int(frames.size() * 0.99)], "max_ms": frames.back()}
	TimeManager.total_minutes = 1440 + 21 * 60
	wv._update_environment()
	await _wait(40)
	await _shot("rodoviaria_noite")
	await _terminal_navigation(wv, r)
	if OS.get_environment("REVIEW_TERMINAL_ONLY") != "1":
		await _pickups(wv)
	wv.queue_free()
	await _wait(3)

func _terminal_navigation(wv, r: Rect2) -> void:
	Engine.max_fps = 60
	TimeManager.total_minutes = 1440 + 11 * 60
	wv._update_environment()
	wv.player.position = Vector3(r.get_center().x, 0.25, r.end.y + 0.7)
	wv.player.velocity = Vector3.ZERO
	wv.path.clear()
	await _wait(4)
	var result := {"ok": true, "legs": []}
	for destination in [Vector2(r.get_center().x, r.position.y + 12), Vector2(r.position.x + 6, r.position.y + 9.7), Vector2(r.get_center().x, r.end.y + 0.7)]:
		var begin := Time.get_ticks_usec()
		wv._go_to(destination)
		var leg := {"route_ms": (Time.get_ticks_usec() - begin) / 1000.0, "points": wv.path.size()}
		var limit := Time.get_ticks_msec() + 45000
		while not wv.path.is_empty() and Time.get_ticks_msec() < limit:
			await get_tree().process_frame
		leg["error_m"] = wv._p2().distance_to(destination)
		leg["path_empty"] = wv.path.is_empty()
		leg["game_active"] = GameState.active
		leg["tree_paused"] = get_tree().paused
		leg["arrived"] = leg["points"] > 0 and leg["error_m"] < 0.25 and wv.path.is_empty()
		result["ok"] = result["ok"] and leg["arrived"]
		result["legs"].append(leg)
		print("TERMINAL ROUTE ", leg)
		wv.path.clear()
		if result["legs"].size() == 2:
			var chair: Dictionary = {}
			for target in wv.city.objects.values():
				if target["kind"] == "seat" and target["loc"] == "rodoviaria" and not wv.seat_used.has(wv._seat_key(target["plan"]["seat"])):
					if chair.is_empty() or (target["plan"]["seat"]["p"] as Vector2).distance_to(wv._p2()) < (chair["plan"]["seat"]["p"] as Vector2).distance_to(wv._p2()):
						chair = target
			var seated := false
			if not chair.is_empty():
				var accepted: bool = wv.start_object_action(chair, "sentar", func(): pass)
				var deadline := Time.get_ticks_msec() + 15000
				while wv.action_busy() and str(wv._act.get("stage", "")) != "manter" and Time.get_ticks_msec() < deadline:
					await get_tree().process_frame
				seated = accepted and str(wv._act.get("stage", "")) == "manter" and wv.player_fig.activity == "sentar"
				wv._cutaway()
				var roof_open := false
				for structure in wv.city.structures:
					if bool(structure.get("shelter", false)):
						roof_open = bool(structure["cut_now"]) and not structure["full"].visible and (structure["rect"] as Rect2).has_point(wv._p2())
				seated = seated and roof_open and wv._sheltered(wv._p2())
				await _wait(10)
				await _shot("rodoviaria_banco")
				wv._cancel_action("Revisão: levantar do banco")
			result["seat"] = seated
			result["ok"] = result["ok"] and seated
			print("TERMINAL SEAT ", seated)
	wv._cutaway()
	var roof_restored := false
	for structure in wv.city.structures:
		if bool(structure.get("shelter", false)):
			roof_restored = not bool(structure["cut_now"]) and structure["full"].visible and structure["root"].scale.is_equal_approx(Vector3.ONE)
	result["roof_restored"] = roof_restored
	result["ok"] = result["ok"] and roof_restored
	metrics["terminal_navigation"] = result

func _pickups(wv) -> void:
	Engine.max_fps = 60
	TimeManager.total_minutes = 1440 + 11 * 60
	wv._update_environment()
	var notices: Array = []
	wv.toast.connect(func(message): notices.append(message); print("REACH TOAST ", message))
	var shop: Dictionary = {}
	for target in wv.city.objects.values():
		if target["kind"] == "shop" and "agua" in target.get("items", []):
			shop = target
	var p: Vector2 = wv.layout.door_in("mercado")
	wv.player.position = Vector3(p.x, 0.25, p.y)
	wv.player.velocity = Vector3.ZERO
	wv._update_location()
	wv._cutaway()
	wv.cam_target = wv.player.position + Vector3(0, 1, 0)
	wv.zoom = 5.5
	await _wait(30)
	var before_money := GameState.money()
	var before_qty := GameState.item_count("agua")
	var result := {"started": false}
	var effect := func() -> bool:
		Economy.buy("agua")
		return GameState.item_count("agua") > before_qty
	result["started"] = wv.start_object_action(shop, "pegar", effect, "agua")
	await _wait_action(wv, "coleta_mercado", result)
	result["paid_once"] = GameState.money() == before_money - World.item_price("agua")
	result["item_once"] = GameState.item_count("agua") == before_qty + 1
	metrics["market_pickup"] = result
	# Cancelar antes do contato não pode transferir item nem dinheiro.
	before_money = GameState.money()
	before_qty = GameState.item_count("agua")
	var started: bool = wv.start_object_action(shop, "pegar", effect, "agua")
	wv._cancel_action("Revisão: cancelar antes do contato")
	metrics["cancel"] = started and GameState.money() == before_money and GameState.item_count("agua") == before_qty and wv.player_fig.reach_target == Vector3.INF
	# Três alturas no mesmo sistema de objetos, sem persistir objetos de teste no save.
	for height in [0.20, 0.85, 1.35]:
		var door: Vector2 = wv.layout.door_out("praca")
		var point := Vector3(door.x + 1.0, height + 0.17, door.y + 1.0)
		var source := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.15, 0.2, 0.12)
		source.mesh = box
		source.position = point
		wv.viewport.add_child(source)
		var key := "review/" + str(height)
		wv.city.object_point(key, "praca", "Objeto de revisão", AABB(point - Vector3.ONE * 0.1, Vector3.ONE * 0.2), "shop", {"path": []}, true, source)
		var target: Dictionary = wv.city.objects[key]
		target["products"] = {"": [source]}
		wv.player.position = point + Vector3(0.1, 0, -1.15)
		wv.player.position.y = 0.25
		wv.player.velocity = Vector3.ZERO
		wv._update_location()
		wv.cam_target = wv.player.position + Vector3(0, 0.8, 0)
		wv.zoom = 4.5
		await _wait(30)
		var data := {"started": false, "calls": 0}
		var callback := func(): data["calls"] += 1
		data["started"] = wv.start_object_action(target, "pegar", callback)
		await _wait_action(wv, "alcance_" + str(height), data)
		metrics["reach_height_" + str(height)] = data
		source.queue_free()
		wv.city.objects.erase(key)
	metrics["notices"] = notices
	for age in [9, 76]:
		GameState.player["age"] = age
		wv.refresh_player_look()
		var door: Vector2 = wv.layout.door_out("praca")
		var point := Vector3(door.x + 1, 1.02, door.y + 1)
		var source := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.12, 0.14, 0.12)
		source.mesh = box
		source.position = point
		wv.viewport.add_child(source)
		var key := "review/age" + str(age)
		wv.city.object_point(key, "praca", "Alcance por idade", AABB(point - Vector3.ONE * 0.1, Vector3.ONE * 0.2), "shop", {"path": []}, true, source)
		var target: Dictionary = wv.city.objects[key]
		target["products"] = {"": [source]}
		wv.player.position = Vector3(point.x, 0.25, point.z - 1.15)
		wv.player.velocity = Vector3.ZERO
		wv._update_location()
		wv.cam_target = wv.player.position + Vector3(0, 0.8, 0)
		await _wait(30)
		var data := {"calls": 0}
		var callback := func(): data["calls"] += 1
		data["started"] = wv.start_object_action(target, "pegar", callback)
		await _wait_action(wv, "alcance_idade_" + str(age), data)
		metrics["reach_age_" + str(age)] = data
		source.queue_free()
		wv.city.objects.erase(key)
	SaveManager.path = out + "/fixture_save.json"
	var money := GameState.money()
	var qty := GameState.item_count("agua")
	metrics["save_v1"] = SaveManager.VERSION == 1 and SaveManager.save_game() and SaveManager.load_game() and GameState.money() == money and GameState.item_count("agua") == qty
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.path))
	legacy.erase("calendar")
	SaveManager.path = out + "/fixture_legacy_v1.json"
	var old_file := FileAccess.open(SaveManager.path, FileAccess.WRITE)
	old_file.store_string(JSON.stringify(legacy))
	old_file.close()
	metrics["legacy_no_calendar"] = SaveManager.load_game() and GameState.money() == money and GameState.item_count("agua") == qty

func _wait_action(wv, name: String, data: Dictionary) -> void:
	var deadline := Time.get_ticks_msec() + (45000 if name == "coleta_mercado" else 18000)
	var min_error := INF
	var captured := false
	var next_frame := 0.0
	var video_frame := 0
	var settled := Vector3.INF
	while wv.action_busy() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if wv._act.is_empty():
			break
		if wv._act["stage"] == "animar":
			if settled == Vector3.INF:
				settled = wv.player.position
			var hand: int = wv.player_fig.skel.find_bone("hand_r")
			var pos: Vector3 = wv.player_fig.grasp_position()
			if not captured:
				data["player_y"] = wv.player.position.y
				data["model_y"] = wv.player_fig.model.position.y
				data["arm_length"] = wv.player_fig.skel.get_bone_global_pose(wv.player_fig.skel.find_bone("upperarm_r")).origin.distance_to(wv.player_fig.skel.get_bone_global_pose(wv.player_fig.skel.find_bone("lowerarm_r")).origin) + wv.player_fig.skel.get_bone_global_pose(wv.player_fig.skel.find_bone("lowerarm_r")).origin.distance_to(wv.player_fig.skel.get_bone_global_pose(hand).origin)
				data["arm_to_target"] = (wv.player_fig.skel.global_transform * wv.player_fig.skel.get_bone_global_pose(wv.player_fig.skel.find_bone("upperarm_r"))).origin.distance_to(wv._act["plan"]["reach"])
			min_error = minf(min_error, pos.distance_to(wv._act["plan"]["reach"]))
			if name == "coleta_mercado" and float(wv._act["t"]) >= next_frame:
				next_frame += 0.1
				await _video_frame(video_frame)
				video_frame += 1
			if float(wv._act["t"]) > 0.75 and not captured:
				captured = true
				var sole := INF
				var fig = wv.player_fig
				for side in 2:
					for point in fig.player_motion._shoe_points[side]:
						var contact: Vector3 = fig.skel.global_transform * (fig.skel.get_bone_global_pose(fig.player_motion._feet[side]) * (point as Vector3))
						sole = minf(sole, contact.y)
				data["sole_clearance_m"] = sole - wv.player.position.y
				await _shot(name)
	data["min_hand_error_m"] = min_error if min_error != INF else -1.0
	data["ended"] = not wv.action_busy()
	data["no_snap_back"] = settled == Vector3.INF or wv.player.position.distance_to(settled) < 0.01
	if wv.action_busy():
		wv._cancel_action("Revisão: timeout")
	print("REACH RESULT ", name, " ", data)
