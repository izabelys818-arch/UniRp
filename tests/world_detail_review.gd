extends Node

const View = preload("res://world3d/world_view.gd")
const OUT := "C:/Users/glznc/Documents/Codex/2026-10-11/urban_v2"
var screen
var view
var failures: Array = []

func check(ok: bool, label: String) -> void:
	print("DETAIL CHECK ", "OK " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func _ready() -> void:
	Settings.camera_mode = 0
	Settings.api_key = ""
	Settings.model = ""
	Settings.local_dialogue = true
	get_window().size = Vector2i(1280, 800)
	get_window().content_scale_size = Vector2i(1280, 800)
	# Embute os mesmos PopupMenu na janela da fixture para capturar também a UI.
	get_viewport().gui_embed_subwindows = true
	Engine.max_fps = 60
	Engine.time_scale = 3.0
	View.realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = OUT + "/interaction_fixture.json"
	GameState.new_game({"name": "Rafa", "age": 30, "gender": "homem", "cenario": "porto_cinza", "origin": "morador_antigo", "money": 500,
		"location": "rua", "home": "apartamento", "inventory": {}, "alive": true})
	NPCManager.reset_state(World.get_origin("morador_antigo"))
	NeedsSystem.reset({})
	TimeManager.total_minutes = 1440 + 11 * 60
	screen = preload("res://ui/game_screen.gd").new()
	screen.theme = preload("res://ui/ui_theme.gd").build()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	view = screen.world_view
	view.toast.connect(func(message: String): print("DETAIL TOAST ", message))
	while not view._built:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(OUT + "/interactions")
	for id in view.layout.prototype_house_ids:
		Houses.st(id)["lock"] = "open"
		view._update_environment()
		view.player.position = Vector3(view.layout.door_in(id).x, 0.25, view.layout.door_in(id).y)
		view._update_location()
		view._cutaway()
		print("DETAIL ENTRY ", id, " door=", view.layout.door_in(id), " player=", view.player.position)
		var structure: Dictionary = view.city.loc_info[id]["structure"]
		view.city.house_gen.place_now(structure["interior"])
		for target in view.city.objects.values():
			if str(target["loc"]) == id:
				print("OBJECT ", target["key"], " bounds=", target["bounds"], " path=", target["plan"]["path"])
		view._go_to(view.layout.door_out(id))
		await wait_path()
		check(view._p2().distance_to(view.layout.door_out(id)) < 0.8, "entrada e saída física " + id)
		view._cutaway()
		await shot("fachada_" + id)
	var id: String = view.layout.prototype_house_ids[0]
	HomeSystem.housing()["contracts"][id] = {"tipo": "propria", "aluguel": 0}
	HomeSystem.housing()["moveis"][id] = ["fogao", "geladeira", "sofa", "tv", "chuveiro"]
	view.player.position = Vector3(view.layout.door_in(id).x, 0.25, view.layout.door_in(id).y)
	view._update_location()
	view._cutaway()
	view.city.house_gen.place_now(view.city.loc_info[id]["structure"]["interior"])
	await get_tree().process_frame
	var bed := find(id, "bed")
	var sofa := find(id, "seat")
	var stove := find(id, "stove")
	var bath := find(id, "bath")
	for target in [bed, sofa, stove, bath]:
		check(not target.is_empty(), "modelo clicável " + str(target.get("label", "ausente")))
	if not bed.is_empty():
		await perform(bed, "deitar")
		check(not view._act.is_empty() and view._act["stage"] == "manter" and view.player_fig.rotation.x < -1.4, "deita e permanece na cama")
		await shot("deitar")
		var picked_bed: Dictionary = view._pick_object(view.camera.unproject_position((bed["bounds"] as AABB).get_center()))
		check(not picked_bed.is_empty() and picked_bed["kind"] == "bed", "clique seleciona cama visível")
		view._cancel_action("Teste: levantar")
		check(view.seat_used.values().count("jogador") == 0, "levantar libera cama")
		var before: Vector3 = view.player.position
		check(view.start_object_action(bed, "deitar", func(): pass), "permite nova aproximação à cama")
		view._cancel_action("Teste: cancelar antes de chegar")
		check(view.path.is_empty() and view.player.position == before and view.seat_used.values().count("jogador") == 0, "cancelar aproximação para o caminho sem teletransporte")
		await menu_shot(bed, "menu_cama")
	if not sofa.is_empty():
		await perform(sofa, "sentar")
		check(not view._act.is_empty() and view._act["stage"] == "manter" and view.player_fig.activity == "sentar", "senta e permanece no sofá")
		await shot("sentar")
		view._cancel_action("Teste: levantar")
		check(view.seat_used.values().count("jogador") == 0, "levantar libera assento")
		var key: String = view._seat_key(sofa["plan"]["seat"])
		view.seat_used[key] = "npc_fixture"
		check(not view.start_object_action(sofa, "sentar", func(): pass), "não ocupa assento reservado por NPC")
		check(view.seat_used.get(key) == "npc_fixture", "reserva do NPC permanece intacta")
		view.seat_used.erase(key)
	var inspect := find(id, "inspect")
	if not inspect.is_empty():
		var money := GameState.money()
		await perform(inspect, "examinar")
		check(GameState.money() == money and view._act.is_empty(), "examinar não cobra nem inventa item")
	if not stove.is_empty():
		var money := GameState.money()
		var minutes := TimeManager.total_minutes
		await perform(stove, "cozinhar")
		check(GameState.money() == money - 8 and TimeManager.total_minutes == minutes + 45, "fogão aplica preço/tempo existentes uma vez")
	if not bath.is_empty():
		var minutes := TimeManager.total_minutes
		await perform(bath, "banho")
		check(TimeManager.total_minutes == minutes + 20, "banho usa sistema de água/necessidades existente")
	await shot("casa_interior")
	var bench: Dictionary = view.city.objects["mercado/banco"]
	view.player.position = Vector3(111.8, 0.25, 118.4)
	view._update_location()
	view._cutaway()
	await perform(bench, "sentar")
	check(view._act.get("stage", "") == "manter", "banco da calçada permite sentar")
	await shot("banco_calcada")
	view._cancel_action("Teste: levantar")
	# Caminhar até a prateleira e pagar antes de receber o item.
	TimeManager.total_minutes = 1440 + 11 * 60
	view.player.position = Vector3(105, 0.25, 113.3)
	view._update_location()
	view._cutaway()
	var shop: Dictionary = {}
	for target in view.city.objects.values():
		if str(target["kind"]) == "shop" and "agua" in target.get("items", []):
			shop = target
	check(not shop.is_empty(), "prateleira vende água do catálogo existente")
	if not shop.is_empty():
		var money := GameState.money()
		var quantity := GameState.item_count("agua")
		await perform(shop, "pegar", "agua")
		check(GameState.item_count("agua") == quantity + 1 and GameState.money() == money - World.item_price("agua"), "pegar mercadoria paga e entra no inventário uma vez")
		await shot("mercado_interior")
		await menu_shot(shop, "menu_prateleira")
		view.camera.size = 24
		view.camera.position = Vector3(105, 1, 108) + View.CAM_DIR.normalized() * 150
		view.camera.look_at(Vector3(105, 1, 108))
		var picked: Dictionary = view._pick_object(view.camera.unproject_position((shop["bounds"] as AABB).get_center()))
		check(not picked.is_empty() and str(picked["kind"]) == "shop", "raio do clique seleciona prateleira visível")
		# Cancelar a aproximação não compra nem duplica.
		quantity = GameState.item_count("agua")
		screen._open_object(shop)
		for index in screen.object_options.size():
			if str(screen.object_options[index].get("item", "")) == "agua":
				screen._on_object(index)
				break
		view._go_to(Vector2(105, 113.3))
		check(GameState.item_count("agua") == quantity and view._act.is_empty(), "cancelar não dá item nem mantém pose")
	view.player.position = Vector3(105, 0.25, 122)
	view._cutaway()
	check(not view.object_access(shop), "não interage com prateleira através do telhado/parede")
	check(SaveManager.VERSION == 1 and SaveManager.save_game() and SaveManager.load_game(), "interações preservam save/load v1")
	var stair_house: String = view.layout.prototype_house_ids[0]
	var stair_structure: Dictionary = view.city.loc_info[stair_house]["structure"]
	view.player.position = Vector3(view.layout.door_in(stair_house).x, 0.25, view.layout.door_in(stair_house).y)
	view.player.velocity = Vector3.ZERO
	view._update_location()
	view._cutaway()
	await get_tree().physics_frame
	await stair_menu(view.city.objects[stair_house + "/escada_0"])
	check(view._floor_in(stair_structure) == 1, "menu contextual sobe fisicamente um andar")
	await stair_menu(view.city.objects[stair_house + "/escada_descer_1"])
	check(view._floor_in(stair_structure) == 0, "menu contextual desce fisicamente ao térreo")
	print("DETAIL RESULT ", "OK" if failures.is_empty() else str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func find(loc: String, kind: String) -> Dictionary:
	for target in view.city.objects.values():
		if str(target["loc"]) == loc and str(target["kind"]) == kind:
			return target
	return {}

func stair_menu(target: Dictionary) -> void:
	screen._open_object(target)
	var chosen := false
	for index in screen.object_options.size():
		if str(screen.object_options[index]["kind"]) == "stairs":
			screen._on_object(index)
			chosen = true
			break
	screen.object_menu.hide()
	check(chosen, "menu oferece ação da escada")
	var deadline := Time.get_ticks_msec() + 25000
	while (not view.path.is_empty() or not view._floor_segments.is_empty()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

func wait_path() -> void:
	var deadline := Time.get_ticks_msec() + 12000
	while not view.path.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	print("WALK final=", view._p2(), " remaining=", view.path)

func perform(target: Dictionary, kind: String, item: String = "") -> void:
	print("DETAIL TARGET ", target["key"], " kind=", kind, " accessible=", view.object_access(target), " owner=", target.get("owner"))
	screen._open_object(target)
	var chosen := false
	for index in screen.object_options.size():
		var option: Dictionary = screen.object_options[index]
		if str(option["kind"]) == kind and (item == "" or str(option.get("item", "")) == item):
			screen._on_object(index)
			chosen = true
			break
	screen.object_menu.hide()
	check(chosen and not view._act.is_empty(), "menu inicia " + kind)
	var deadline := Time.get_ticks_msec() + 18000
	var captured := false
	while not view._act.is_empty() and str(view._act["stage"]) != "manter" and Time.get_ticks_msec() < deadline:
		if str(view._act["stage"]) == "animar" and not captured:
			await shot("acao_" + kind)
			captured = true
		await get_tree().process_frame
	print("ACTION ", kind, " final=", view._p2(), " stage=", view._act.get("stage", "fim"), " path=", view.path)
	if not view._act.is_empty() and str(view._act["stage"]) != "manter":
		view._cancel_action("Teste: limite de tempo")

func shot(label: String) -> void:
	view.zoom = 11.0
	view.cam_target = view.player.position + Vector3(0, 1, 0)
	view._camera(1.0)
	# A câmera normal segue o jogador; suspender um quadro preserva o enquadramento
	# de revisão sem alterar geometria, pose, iluminação ou conteúdo da captura.
	view.set_process(false)
	var focus: Vector3 = view.player.position + Vector3(0, 0.8, 0)
	view.camera.position = focus + Vector3(-1, 2.0, -1).normalized() * 150.0
	view.camera.look_at(focus)
	await RenderingServer.frame_post_draw
	view.viewport.get_texture().get_image().save_png(OUT + "/interactions/" + label + ".png")
	view.set_process(true)

func menu_shot(target: Dictionary, label: String) -> void:
	screen.toast_panel.hide()
	screen._open_object(target)
	screen.object_menu.position = Vector2i(860, 180)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "/interactions/" + label + ".png")
	screen.object_menu.hide()
