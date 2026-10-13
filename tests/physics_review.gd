extends Node

# Exercita os corpos de produção dentro da GameScreen real, com IA mock,
# save separado e capturas nativas. Não altera a partida do dono.
const Layers = preload("res://world3d/physics_layers.gd")
const LightObject = preload("res://world3d/light_object.gd")
const Vehicle = preload("res://world3d/physical_vehicle.gd")
const State = preload("res://world3d/physics_state.gd")
var wv
var failures: Array[String] = []
var checks := 0
var results: Array = []

func check(ok: bool, name: String, detail: Variant = null) -> void:
	checks += 1
	results.append({"check": name, "ok": ok, "detail": detail})
	print("OK " if ok else "FALHOU ", name, " ", detail if detail != null else "")
	if not ok: failures.append(name)

func frames(count: int) -> void:
	for i in count: await get_tree().physics_frame

func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://evidencias_fisica/" + name + ".png")

func place_player(point: Vector3) -> void:
	wv.path.clear()
	wv._floor_segments.clear()
	wv.player.position = point
	wv.player.velocity = Vector3.ZERO
	wv.player_physics.restore({})
	wv._p_heading = 0.0
	wv.player_fig.rotation = Vector3.ZERO

func tick_player(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		wv._move_player(1.0 / 60)

func _ready() -> void:
	AIService.mock = func(_messages: Array): return {"ok": true, "text": "{\"fala\":\"Tudo bem.\",\"emocao\":\"neutro\"}"}
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "res://evidencias_fisica/physics_save.json"
	get_window().size = Vector2i(1280, 800)
	get_window().content_scale_size = Vector2i(1280, 800)
	Engine.max_fps = 60
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x", "look": {"pele": 2, "cabelo": 0, "roupa": 2}, "traits": [], "cenario": "porto_cinza", "origin": origin["id"], "money": 400, "location": "lanchonete", "home": "apartamento", "inventory": {}, "alive": true})
	NeedsSystem.reset()
	TimeManager.total_minutes = 1440 + 11 * 60
	NPCManager.reset_state(origin)
	var screen = preload("res://ui/game_screen.gd").new()
	screen.theme = preload("res://ui/ui_theme.gd").build()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	wv = screen.world_view
	while not wv._built: await get_tree().process_frame
	await frames(90)
	wv.set_physics_process(false)
	check(wv.player.collision_layer == Layers.PLAYER, "jogador na camada nomeada")
	for index in 10:
		check(ProjectSettings.has_setting("layer_names/3d_physics/layer_%d" % (index + 1)), "camada %d nomeada" % (index + 1))
	check(wv.player is CharacterBody3D and wv.player.get_child(0).shape is CapsuleShape3D, "cápsula original do jogador preservada")
	var kinds := {}
	for body in get_tree().get_nodes_in_group("physical_props"):
		for shape in body.get_children():
			kinds[str(shape.get_meta("kind", ""))] = int(kinds.get(str(shape.get_meta("kind", "")), 0)) + 1
	for kind in ["carro", "arvore", "poste", "banco", "lixeira", "placa", "correio", "abrigo", "hidrante", "vaso", "portao"]:
		check(int(kinds.get(kind, 0)) > 0, "colisor gerado " + kind, kinds.get(kind, 0))
	# Cada volume gerado recebe um sweep real; a classificação da forma atingida
	# evita declarar sucesso quando o probe bateu em outro objeto do bairro.
	var probe := CharacterBody3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.6
	Layers.shape(probe, cap, Vector3(0, 0.8, 0))
	probe.collision_layer = 0
	probe.collision_mask = Layers.WORLD
	wv.viewport.add_child(probe)
	var swept := {}
	for body in get_tree().get_nodes_in_group("physical_props"):
		var previous: int = body.collision_layer
		body.collision_layer = int(body.get_meta("physical_layer"))
		for shape in body.get_children():
			var kind := str(shape.get_meta("kind", ""))
			if swept.has(kind): continue
			var xf: Transform3D = shape.global_transform
			var half: float = shape.shape.size.x / 2 if shape.shape is BoxShape3D else shape.shape.radius
			for sign_dir in [-1, 1]:
				var direction: Vector3 = xf.basis.x.normalized() * sign_dir
				var start := xf.origin - direction * (half + 0.85) - Vector3(0, 0.8, 0)
				var hit := KinematicCollision3D.new()
				if probe.test_move(Transform3D(Basis.IDENTITY, start), direction * 1.6, hit) and hit.get_collider() == body:
					var owner = hit.get_collider_shape()
					if owner == shape:
						swept[kind] = true
						break
		body.collision_layer = previous
	for kind in ["carro", "arvore", "poste", "banco", "lixeira", "placa", "correio", "abrigo", "hidrante", "vaso", "portao"]:
		check(swept.has(kind), "sweep real bloqueado por " + kind)
	probe.queue_free()
	# Casos controlados na própria rua do mundo carregado; a fixture reposiciona
	# os corpos uma vez antes de cada caso, nunca durante o movimento testado.
	var base := Vector3(145, 0.12, 122)
	place_player(base)
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.WALL
	Layers.box(wall, Vector3(4, 3, 0.3), Vector3(0, 1.5, 0))
	wv.viewport.add_child(wall)
	wall.position = base + Vector3(0, 0, 2)
	wv.path = PackedVector2Array([Vector2(145, 128)])
	await tick_player(180)
	check(wv.player.position.z < 123.65 and wv.player_physics.state == "normal", "parede bloqueia sem derrubar", wv.player.position.z)
	wall.queue_free()
	await frames(2)
	place_player(base + Vector3(0, 4, 0))
	var hp := NeedsSystem.get_value("saude")
	await tick_player(50)
	check(NeedsSystem.get_value("saude") < hp and wv.player_physics.blocked(), "queda de 4m aplica dano e bloqueia entrada", wv.player_physics.to_dict())
	await tick_player(45)
	await shot("queda_caido")
	check(wv.player_physics.state == "caido", "queda chega a caido")
	check(SaveManager.save_game(), "save v1 com estado caido")
	var data = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.path))
	check(int(data["version"]) == 1 and data["game"]["player"]["physical"]["state"] == "caido", "serializador v1 conserva caido")
	wv.player_physics.restore({})
	check(SaveManager.load_game(), "reload com campos físicos opcionais")
	wv.player_physics.restore(GameState.player.get("physical", {}))
	check(wv.player_physics.state == "caido", "estado restaurado após reload")
	await tick_player(370)
	check(wv.player_physics.state == "normal", "levanta sozinho após queda")
	# NPC sólido usando o modelo e a rotina de produção já criados.
	var entry: Dictionary = wv.npcs.values()[0]
	var physical = entry["physical"]
	var figure: Node3D = entry["fig"]
	figure.position = base + Vector3(0, 0, 1.2)
	physical.body.position = figure.position
	physical.restore({})
	place_player(base)
	wv.path = PackedVector2Array([Vector2(145, 127)])
	var minimum := INF
	for i in 150:
		await get_tree().physics_frame
		wv._move_player(1.0 / 60)
		figure.position.z -= 0.004
		physical.resolve(1.0 / 60, true)
		minimum = minf(minimum, Vector2(figure.position.x - wv.player.position.x, figure.position.z - wv.player.position.z).length())
	check(minimum >= 0.50, "jogador e NPC se empurram sem sobreposição", minimum)
	check(physical.impact(Vector3(0, 0, 1), 2.2) and physical.state == "tropecando", "empurrão social ativa tropeço")
	for i in 50:
		await get_tree().physics_frame
		physical.resolve(1.0 / 60, true)
	check(physical.state == "normal", "NPC recupera do tropeço")
	# Carro percorre o contato de verdade; velocidade, Area3D e sweep são os reais.
	var car := Vehicle.new()
	car.configure()
	var mesh := MeshInstance3D.new()
	var kit := preload("res://world3d/mesh_kit.gd").new()
	preload("res://world3d/car_mesh.gd").draw(kit, Vector3.ZERO, 0, Color("#9a3430"))
	mesh.mesh = kit.commit(wv.city.prop_mat)
	car.add_child(mesh)
	wv.viewport.add_child(car)
	place_player(base)
	car.position = base + Vector3(0, 0.02, -4)
	hp = NeedsSystem.get_value("saude")
	for i in 40:
		await get_tree().physics_frame
		car.drive(Vector3(0, 0, 8.0 / 60), 0, 8, true)
		wv._move_player(1.0 / 60)
	check(NeedsSystem.get_value("saude") < hp and wv.player_physics.blocked(), "carro em movimento atropela jogador com dano")
	await shot("atropelamento")
	car.position = base + Vector3(0, 0.02, -4)
	physical.restore({})
	figure.position = base
	physical.body.position = base
	place_player(base + Vector3(3, 0, 0))
	var id := str(entry["id"])
	var npc_hp: int = NPCManager.state[id]["saude"]
	for i in 35:
		await get_tree().physics_frame
		car.drive(Vector3(0, 0, 8.0 / 60), 0, 8, true)
		physical.resolve(1.0 / 60, true)
	check(int(NPCManager.state[id]["saude"]) < npc_hp and physical.blocked(), "atropelamento do NPC usa saúde existente")
	car.queue_free()
	# Mesa de produção e utensílios reais: quebra por contato após gravidade.
	place_player(base)
	var cup := LightObject.tableware(wv.viewport, base + Vector3(1.5, 1.8, 0), "copo", "fixture/copo")
	cup.shattered.connect(wv.physical_world._shatter)
	cup.wake()
	await frames(65)
	check(cup.broken and not cup.visible and cup.collision_layer == 0, "copo de cerâmica quebra ao cair 1.8m")
	var plate := LightObject.tableware(wv.viewport, base + Vector3(2.0, 1.8, 0), "prato", "fixture/prato")
	plate.shattered.connect(wv.physical_world._shatter)
	plate.wake()
	await frames(65)
	check(plate.broken, "prato quebra por queda")
	var chair = preload("res://world3d/furn_lib.gd").place(wv.viewport, preload("res://world3d/furn_lib.gd").K % "chair", base + Vector3(2.8, 1.8, 0), 0, 0.2, Vector3.ZERO, true)
	chair.bind_id("fixture/cadeira")
	chair.wake()
	await frames(80)
	check(not chair.broken and chair.has_meta("scuffed"), "cadeira sofre impacto e continua inteira")
	await shot("objetos_apos_queda")
	wv.physical_world.flush()
	check(SaveManager.save_game() and SaveManager.load_game(), "save/reload após quebra")
	var restored := LightObject.tableware(wv.viewport, base + Vector3(1.5, 1.8, 0), "copo", "fixture/copo")
	check(restored.broken and not restored.visible, "objeto quebrado continua consumido após reload")
	await frames(260)
	var live_shards := 0
	for ref in wv.physical_world.shards:
		if is_instance_valid(ref.get_ref()): live_shards += 1
	check(live_shards == 0, "cacos desaparecem em até 4s", live_shards)
	check(wv.physical_world.shards.size() <= 40, "teto global de cacos")
	data["game"]["player"].erase("physical")
	data["game"]["player"].erase("physical_objects")
	var file := FileAccess.open(SaveManager.path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	check(SaveManager.load_game(), "save antigo sem campos físicos carrega")
	wv.player_physics.restore(GameState.player.get("physical", {}))
	check(wv.player_physics.state == "normal", "migração default físico normal")
	var report := FileAccess.open("res://evidencias_fisica/physics_results.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures, "results": results}, "\t"))
	report.close()
	SaveManager.delete_save()
	print("RESULTADO FISICA: ", "OK" if failures.is_empty() else "%d falha(s)" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
