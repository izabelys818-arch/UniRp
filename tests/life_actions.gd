extends Node

# Ações com o corpo na casa do jogador e o hospital como protótipo de interior vivo.
# Confere a ordem aproximar → alinhar → animar → efeito real, o cancelamento e a ocupação.
# Uso: godot --path . res://tests/life_actions.tscn

const UITheme = preload("res://ui/ui_theme.gd")
var fails := 0
var wv
var screen


func check(ok: bool, what: String) -> void:
	print(("OK     " if ok else "FALHOU ") + what)
	if not ok:
		fails += 1


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().process_frame


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := OS.get_user_data_dir() + "/acao_%s.png" % name
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _stage() -> String:
	return "" if wv._act.is_empty() else str(wv._act["stage"])


# espera a ação chegar a um estágio (ou acabar), registrando a ordem
func _follow(order: Array, max_sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(max_sec * 1000.0):
		var st := _stage()
		if order.is_empty() or order.back() != st:
			order.append(st)
		if st == "":
			return
		await get_tree().process_frame


func _put_player(p: Vector2, loc: String) -> void:
	wv.player.position = Vector3(p.x, 0.25, p.y)
	wv.cam_target = wv.player.position
	GameState.player["location"] = loc
	World.location_changed.emit(loc)
	for i in 20:
		await get_tree().process_frame


func _ready() -> void:
	AIService.mock = _stream_mock
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "user://acoes_save.json"
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x",
		"look": {"pele": 2, "cabelo": 0, "cor_cabelo": 0, "barba": 1, "roupa": 2, "marcas": []},
		"appearance_extra": "", "backstory": "", "traits": [], "cenario": "porto_cinza",
		"origin": origin["id"], "money": 400, "location": "apartamento", "home": "apartamento", "inventory": {"pao": 1}, "alive": true,
	})
	TimeManager.total_minutes = 1440 + 21 * 60
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	screen = preload("res://ui/game_screen.gd").new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	await get_tree().process_frame
	wv = screen.world_view
	while not wv._built:
		await get_tree().process_frame
	for i in 40:
		await get_tree().process_frame
	var home := "apartamento"
	var b: Rect2 = wv.layout.lots[home]["building"]
	check(wv.city.use_points.has(home) and wv.city.use_points[home].has("cama") and wv.city.use_points[home].has("chuveiro"), "casa tem pontos de uso (cama e chuveiro)")
	await _put_player(b.get_center() + Vector2(0, 2.5), home)
	wv.zoom = 9.0
	wv.camera.size = 9.0
	# --- dormir ---
	NeedsSystem.apply({"energia": -60})
	var e0 := NeedsSystem.get_value("energia")
	var m0 := TimeManager.total_minutes
	screen._do_action("dormir_casa")
	check(not wv._act.is_empty(), "dormir: ação começou (não foi instantânea)")
	check(TimeManager.total_minutes == m0, "dormir: o tempo ainda não pulou ao começar")
	var order: Array = []
	var t0 := Time.get_ticks_msec()
	while _stage() != "animar" and Time.get_ticks_msec() - t0 < 15000:
		if order.is_empty() or order.back() != _stage():
			order.append(_stage())
		await get_tree().process_frame
	order.append("animar")
	# A aproximação mantém o gasto normal de caminhada/altura. O sono ainda
	# não pode restaurar energia nem avançar o relógio nesta etapa.
	check(NeedsSystem.get_value("energia") <= e0 + 0.001 and TimeManager.total_minutes == m0 and not bool(wv._act.get("applied", true)), "dormir: recuperação só ocorre depois da animação")
	await _wait(0.9)
	check(absf(wv.player_fig.rotation.x) > 1.0, "dormir: personagem deitado na cama")
	await _shot("dormir")
	await _follow(order, 8.0)
	print("ORDEM dormir: ", order)
	check(order.slice(0, 4) == ["ir", "alinhar", "animar", "fim"], "dormir: ordem ir → alinhar → animar → efeito/fim")
	check(NeedsSystem.get_value("energia") > e0, "dormir: energia restaurada depois (%.0f → %.0f)" % [e0, NeedsSystem.get_value("energia")])
	check(TimeManager.total_minutes >= m0 + 400, "dormir: o tempo passou (8 h)")
	check(absf(wv.player_fig.rotation.x) < 0.01 and wv.player_fig.position == Vector3.ZERO, "dormir: levantou (pose neutra)")
	# --- banho ---
	NeedsSystem.apply({"higiene": -70})
	var h0 := NeedsSystem.get_value("higiene")
	var shower: Vector2 = wv.city.use_points[home]["chuveiro"]["path"].back()
	await _put_player(shower, home)
	screen._do_action("banho_casa")
	var t1 := Time.get_ticks_msec()
	while _stage() != "animar" and Time.get_ticks_msec() - t1 < 15000:
		await get_tree().process_frame
	await _wait(1.0)
	check(NeedsSystem.get_value("higiene") == h0, "banho: higiene só muda no fim")
	await _shot("banho")
	await _follow([], 6.0)
	check(NeedsSystem.get_value("higiene") > h0 + 50.0, "banho: higiene subiu depois (%.0f → %.0f)" % [h0, NeedsSystem.get_value("higiene")])
	# --- comer sentado à mesa ---
	await _follow([], 15.0)
	var dining: Dictionary = {}
	for seat in wv.city.seats:
		if wv.layout.lot_at(seat["p"]) == home:
			dining = seat
			break
	check(not dining.is_empty(), "comer: assento real na casa")
	if not dining.is_empty():
		var front := Vector2(sin(float(dining["yaw"])), cos(float(dining["yaw"])))
		await _put_player((dining["p"] as Vector2) + front * 0.85, home)
	var s0 := NeedsSystem.get_value("saciedade")
	check(screen._use_item_animated("pao"), "comer: começou pela bolsa")
	check(GameState.player["inventory"].has("pao"), "comer: o pão ainda está na bolsa enquanto ele vai sentar")
	var t2 := Time.get_ticks_msec()
	while _stage() != "animar" and Time.get_ticks_msec() - t2 < 15000:
		await get_tree().process_frame
	await _wait(1.6)
	check(wv.player_fig.activity == "sentar", "comer: sentou para comer")
	var seat_taken := false
	for k in wv.seat_used:
		if str(wv.seat_used[k]) == "jogador":
			seat_taken = true
	check(seat_taken, "comer: cadeira marcada como ocupada (ninguém senta junto)")
	await _shot("comer")
	await _follow([], 6.0)
	check(not GameState.player["inventory"].has("pao"), "comer: o pão saiu da bolsa no fim")
	check(NeedsSystem.get_value("saciedade") > s0, "comer: saciedade subiu (%.0f → %.0f)" % [s0, NeedsSystem.get_value("saciedade")])
	var still_taken := false
	for k in wv.seat_used:
		if str(wv.seat_used[k]) == "jogador":
			still_taken = true
	check(not still_taken, "comer: cadeira liberada no fim")
	# --- interromper ---
	NeedsSystem.apply({"energia": -50})
	var e1 := NeedsSystem.get_value("energia")
	var m1 := TimeManager.total_minutes
	screen._do_action("dormir_casa")
	var t3 := Time.get_ticks_msec()
	while _stage() != "animar" and Time.get_ticks_msec() - t3 < 15000:
		await get_tree().process_frame
	await _wait(0.4)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	ev.keycode = KEY_W
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(0.3)
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await _wait(0.3)
	check(wv._act.is_empty(), "interromper: ação cancelada ao andar")
	check(absf(wv.player_fig.rotation.x) < 0.01, "interromper: não ficou preso deitado")
	check(absf(NeedsSystem.get_value("energia") - e1) < 1.0 and TimeManager.total_minutes - m1 < 60, "interromper: nenhum efeito aplicado (energia %.2f → %.2f, +%d min)" % [e1, NeedsSystem.get_value("energia"), TimeManager.total_minutes - m1])
	# --- beber e atividades adicionais ---
	GameState.player["inventory"]["agua"] = 1
	NeedsSystem.apply({"hidratacao": -40})
	var hydration := NeedsSystem.get_value("hidratacao")
	check(screen._use_item_animated("agua"), "água: iniciou gesto")
	check(GameState.player["inventory"].has("agua"), "água: item reservado até concluir")
	await _follow([], 15.0)
	check(not GameState.player["inventory"].has("agua") and NeedsSystem.get_value("hidratacao") > hydration, "água: consumo e hidratação no fim")
	HomeSystem.housing()["moveis"][home] = ["fogao", "geladeira", "sofa", "tv", "computador"]
	HomeSystem.utils(home)["internet"] = true
	HomeSystem.utils(home)["agua"] = true
	HomeSystem.utils(home)["luz"] = true
	WorldEvents.stop("apagao")
	for kind in ["cozinhar", "tv", "sofa", "pc"]:
		var action_loc := home
		if kind == "pc" and not wv.city.use_points[home].has("computador"):
			action_loc = "hospital"
			var structure: Dictionary = wv.city.loc_info[action_loc]["structure"]
			wv.city.ensure_interior(structure)
			HomeSystem.housing()["contracts"][action_loc] = {"tipo": "propria", "aluguel": 0}
			HomeSystem.housing()["moveis"][action_loc] = ["computador"]
			HomeSystem.utils(action_loc)["internet"] = true
			HomeSystem.utils(action_loc)["luz"] = true
		var point_key: String = "fogao" if kind == "cozinhar" else ("computador" if kind == "pc" else "sofa")
		check(wv.city.use_points[action_loc].has(point_key), kind + ": objeto real disponível")
		if not wv.city.use_points[action_loc].has(point_key):
			get_tree().quit(1)
			return
		var target: Vector2 = wv.city.use_points[action_loc][point_key]["path"].back()
		await _put_player(target + Vector2(0.0, 0.6), action_loc)
		var clock := TimeManager.total_minutes
		var money := GameState.money()
		screen._do_action("casa:" + kind)
		check(wv.action_busy(), kind + ": começou uma atividade com o corpo")
		screen._do_action("casa:" + kind)
		check(TimeManager.total_minutes == clock and GameState.money() == money, kind + ": duplo clique não antecipa efeito")
		var timeout := Time.get_ticks_msec()
		while _stage() != "animar" and wv.action_busy() and Time.get_ticks_msec() - timeout < 12000:
			await get_tree().process_frame
		await _wait(1.0)
		check(wv.player_fig.daily_action == kind, kind + ": gesto próprio ativo")
		await _shot(kind)
		await _follow([], 10.0)
		check(TimeManager.total_minutes > clock, kind + ": efeito real aplicado no fim")
		check(wv.player_fig.daily_action == "", kind + ": gesto e cadeira liberados")
	# --- contato social, resposta e proteção de menores ---
	NPCManager.state["ze"]["confianca"] = 50
	NPCManager.state["ze"]["afeto"] = 50
	NPCManager.state["ze"]["suspeita"] = 0
	NPCManager.channel = NPCManager.PRESENCIAL
	check(SocialSystem.contact("ze", "abraco"), "amizade: abraço correspondido com vínculo")
	var affection: int = NPCManager.state["ze"]["afeto"]
	SocialSystem.contact("ze", "abraco")
	check(NPCManager.state["ze"]["afeto"] == affection, "amizade: repetir gesto não acumula afeto")
	check(not SocialSystem.contact("ze", "beijo"), "beijo: sem namoro não é correspondido")
	NPCManager.state["ze"]["namoro"] = true
	check(SocialSystem.contact("ze", "beijo"), "casal adulto: beijo correspondido")
	GameState.player["age"] = 17
	check(not SocialSystem.contact("ze", "beijo"), "menor: beijo romântico bloqueado")
	GameState.player["age"] = 30
	# --- hospital ---
	var hb: Rect2 = wv.layout.lots["hospital"]["building"]
	var beds := 0
	for bd in wv.city.beds:
		if wv.layout.lot_at(bd["p"]) == "hospital":
			beds += 1
	check(beds >= 4, "hospital: leitos para pacientes (%d)" % beds)
	await _put_player(hb.get_center() + Vector2(0, 3.0), "hospital")
	wv.zoom = 15.0
	wv.camera.size = 15.0
	TimeManager.total_minutes = 3 * 1440 + 10 * 60
	await _wait(25.0)
	var lying := 0
	for id in wv.npcs:
		if str(wv.npcs[id].get("act", "")) == "deitado":
			lying += 1
	print("HOSPITAL pessoas deitadas: ", lying)
	await _shot("hospital")
	wv.layout.ensure_chunk(Vector2i(4, 2))
	var crossing: PackedVector2Array = wv.layout.route(Vector2(285, 165), Vector2(405, 165))
	check(not crossing.is_empty() and crossing[crossing.size() - 1] == Vector2(405, 165), "ações mantêm navegação entre regiões")
	print("RESULTADO ACOES: ", "OK" if fails == 0 else "%d falha(s)" % fails)
	SaveManager.delete_save()
	get_tree().quit()


func _stream_mock(_messages: Array) -> Dictionary:
	return {"ok": true, "text": "{\"fala\":\"Tudo bem.\",\"emocao\":\"neutro\"}"}
