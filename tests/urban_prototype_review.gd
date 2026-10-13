extends Node

# Regressões do distrito, sem abrir/gravar a partida do jogador ou chamar IA.
const Layout = preload("res://world3d/city_layout.gd")
const View = preload("res://world3d/world_view.gd")
var output := OS.get_environment("URBAN_OUTPUT") if OS.get_environment("URBAN_OUTPUT") != "" else "C:/Users/glznc/Documents/Codex/2026-10-11/urban"
var test_save := output + "/legacy_fixture.json"
var failures: Array[String] = []
var view
var walking := false

func check(ok: bool, label: String) -> void:
	print("CHECK ", "OK " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func _physics_process(delta: float) -> void:
	if walking:
		view._move_player(delta)

func move_to(point: Vector2) -> void:
	view.path = PackedVector2Array([point])
	walking = true
	var start := Time.get_ticks_msec()
	while not view.path.is_empty() and Time.get_ticks_msec() - start < 6000:
		await get_tree().physics_frame
	walking = false
	view.player.velocity = Vector3.ZERO
	check(view._p2().distance_to(point) < 0.65, "caminhada física até " + str(point))

func _ready() -> void:
	get_window().size = Vector2i(1280, 800)
	View.realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = test_save
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 2.0
	for scenario in ["porto_cinza", "vale_sereno", "nova_aurora", "colapso"]:
		GameState.new_game({"name": "Teste", "age": 30, "gender": "homem", "cenario": scenario,
			"origin": "morador_antigo", "money": 400, "location": "rua", "home": "apartamento", "inventory": {}, "alive": true})
		NPCManager.reset_state(World.get_origin("morador_antigo"))
		NeedsSystem.reset({})
		TimeManager.total_minutes = 1440 + 660
		Layout.urban_prototype_enabled = false
		var old := Layout.new()
		Layout.urban_prototype_enabled = true
		var updated := Layout.new()
		var repeat := Layout.new()
		for id in old.lots:
			check(updated.lots.has(id) and updated.lots[id]["building"] == old.lots[id]["building"] and updated.lots[id]["door"] == old.lots[id]["door"], scenario + " preserva " + id)
		check(updated.prototype_house_ids.size() == 3, scenario + " somente três novas casas")
		for id in updated.prototype_house_ids:
			check(str(updated.lots[id]) == str(repeat.lots[id]), scenario + " lote determinístico " + id)
			check(updated.lot_at(updated.door_out(id)) == id, scenario + " endereço no acesso " + id)
		view = View.new()
		view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(view)
		while not view._built:
			await get_tree().process_frame
		view.set_process(false)
		await get_tree().physics_frame
		var space: PhysicsDirectSpaceState3D = view.player.get_world_3d().direct_space_state
		for id in updated.prototype_house_ids:
			Houses.st(id)["lock"] = "open"
			view.city.set_door(id, false)
			await get_tree().physics_frame
			var out := updated.door_out(id)
			view.player.position = Vector3(out.x, 0.17, out.y)
			await move_to(updated.door_in(id))
			view._cutaway()
			var structure: Dictionary = view.city.loc_info[id]["structure"]
			check(structure["cut"].visible and not structure["full"].visible and structure["interior"] != null, scenario + " interior real e corte " + id)
			await move_to(out)
			view._cutaway()
			# Na porta de uma casa virada de costas para a câmera o jogador fica atrás dela: a casa
			# continua aberta (Project Zomboid). Longe dela, a fachada volta inteira.
			var occluding: bool = structure.get("blocks", false)
			check(occluding or (structure["full"].visible and not structure["cut"].visible), scenario + " porta: fachada ou recorte por tapar " + id)
			var cam: Vector3 = view.CAM_DIR.normalized()
			view.player.position = Vector3(out.x, 0.17, out.y) + Vector3(cam.x, 0, cam.z).normalized() * 30.0
			# a folga contra piscar é em tempo real (o teste acelera o relógio do jogo)
			var wait_until := Time.get_ticks_msec() + 600
			while Time.get_ticks_msec() < wait_until:
				await get_tree().process_frame
			view._cutaway()
			check(structure["full"].visible and not structure["cut"].visible and is_equal_approx(structure["root"].scale.y, 1.0), scenario + " fachada reaparece " + id)
			view.player.position = Vector3(out.x, 0.17, out.y)
			var b: Rect2 = updated.lots[id]["building"]
			var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(b.position.x - 0.8, 1, b.get_center().y), Vector3(b.position.x + 0.8, 1, b.get_center().y)))
			check(not hit.is_empty(), scenario + " parede tem colisão " + id)
		view.city.set_door("mercado", false)
		await get_tree().physics_frame
		view.player.position = Vector3(105, 0.17, 121)
		await move_to(updated.door_in("mercado"))
		await move_to(Vector2(105, 121))
		view._cutaway()
		var market_structure: Dictionary = view.city.loc_info["mercado"]["structure"]
		check(market_structure["full"].visible and not market_structure["cut"].visible, scenario + " mercado não desaparece ao sair")
		for obstacle in view.city.prototype_props:
			var p: Vector2 = obstacle.get_center()
			check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, 2.8, p.y), Vector3(p.x, 0.2, p.y))).is_empty(), scenario + " mobiliário tem colisão " + str(p))
		var starts := []
		for i in 4:
			starts.append(view.life.peds[i]["fig"].position)
		for tick in 80:
			view.life.update(0.1, Vector2(105, 121), false, false)
		for i in 4:
			check(view.life.peds[i]["fig"].position.distance_to(starts[i]) > 0.5, scenario + " pedestre circula " + str(i))
		check(view.life.peds.size() == 30 and view.life.cars.size() == 18, scenario + " mantém população e tráfego")
		for ped in view.life.peds.slice(0, 4):
			var route: PackedVector2Array = ped["route"]
			var sphere := SphereShape3D.new()
			sphere.radius = 0.3
			for segment in 4:
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = sphere
				query.transform = Transform3D(Basis.IDENTITY, Vector3(route[segment].x, 0.8, route[segment].y))
				query.motion = Vector3(route[(segment + 1) % 4].x - route[segment].x, 0, route[(segment + 1) % 4].y - route[segment].y)
				var fraction := space.cast_motion(query)
				check(fraction[0] > 0.999, scenario + " calçada livre em toda a extensão " + str(segment))
			for point in route:
				for obstacle in view.city.prototype_props:
					check(not obstacle.grow(0.3).has_point(point), scenario + " canto da rota livre")
		var car_start: Vector2 = view.life.cars[0]["pos"]
		var dog_start: Vector3 = view.life.dogs[0]["node"].position
		for tick in 40:
			view.life.update(0.1, Vector2(105, 121), false, false)
		check(car_start.distance_to(view.life.cars[0]["pos"]) > 0.5, scenario + " veículo se desloca")
		check(view.life.dogs.size() == 5 and view.life.dogs[0]["node"].position.distance_to(dog_start) > 0.1, scenario + " cão existente circula sem aumentar a quantidade")
		view.city.set_wetness(1.0)
		check(view.city.prototype_cloth_material.get_shader_parameter("wind") > 1.5, scenario + " varal responde ao vento da chuva")
		view.city.set_wetness(0.0)
		check(view.npcs.has("irene"), scenario + " modelo da gerente preparado")
		var irene: Dictionary = view.npcs["irene"]
		var instance_id: int = irene["fig"].get_instance_id()
		view._snap_npcs = true
		view._sync_npcs()
		view._choose_act(irene, irene["fig"])
		check(irene["act"] == "ir_trabalho" and not irene["path"].is_empty(), scenario + " gerente segue estação de trabalho")
		view._arrive(irene, irene["fig"])
		check(irene["act"] == "mexer", scenario + " gerente executa gesto de trabalho")
		TimeManager.total_minutes = 1440 + 22 * 60
		view._sync_npcs()
		check(view.npcs["irene"]["loc"] == "" and not irene["fig"].visible, scenario + " fora do turno fica desativada")
		TimeManager.total_minutes = 1440 + 11 * 60
		view._sync_npcs()
		view._update_npcs(0.01)
		check(irene["fig"].get_instance_id() == instance_id and irene["loc"] == "mercado", scenario + " mesmo modelo reutilizado no retorno")
		view.queue_free()
		await get_tree().process_frame
		view = null
	# Fixture no formato v1 anterior, com casas existentes e sem calendário/residentes.
	var original_houses := Houses.all().duplicate(true)
	var payload := {"version": 1, "game": GameState.to_dict(), "time": TimeManager.total_minutes, "needs": NeedsSystem.to_dict(), "npcs": NPCManager.to_dict()}
	payload["game"]["player"]["houses"] = original_houses
	for id in ["casa_2_2_0", "casa_2_2_1", "casa_2_2_2"]:
		payload["game"]["player"]["houses"].erase(id)
	payload["game"]["player"].erase("residents")
	var f := FileAccess.open(test_save, FileAccess.WRITE)
	f.store_string(JSON.stringify(payload))
	f.close()
	check(SaveManager.load_game(), "carrega fixture antiga v1 sem calendário/residentes")
	var legacy := Houses.all().duplicate(true)
	Layout.new()
	for id in ["casa_2_2_0", "casa_2_2_1", "casa_2_2_2"]:
		Houses.st(id)
	for id in legacy:
		check(Houses.all()[id] == legacy[id], "preserva estado salvo de " + id)
	check(SaveManager.VERSION == 1 and SaveManager.save_game() and SaveManager.load_game(), "save/load v1 após geração")
	TimeManager.total_minutes = 1440 + 11 * 60
	GameState.player["location"] = "mercado"
	JobSystem.hire("irene")
	check(JobSystem.has_job() and JobSystem.on_shift(), "emprego existente do mercado acessível")
	var money := GameState.money()
	var energy := NeedsSystem.get_value("energia")
	JobSystem.work()
	check(GameState.money() == money + 42 and NeedsSystem.get_value("energia") < energy and TimeManager.hour() == 14, "trabalho real paga R$42, consome energia e três horas")
	print("URBAN RESULT ", "OK" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
