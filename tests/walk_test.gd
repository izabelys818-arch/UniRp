extends Node

# Anda de verdade pelo mundo 3D: sai de um prédio, volta a entrar, conversa com gente na rua.

const UITheme = preload("res://ui/ui_theme.gd")
var fails: Array = []


func check(c: bool, m: String) -> void:
	if not c:
		fails.append(m)
		printerr("FALHOU: ", m)


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	SaveManager.path = "user://test_save.json"
	WorldEvents.random_enabled = false
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x",
		"look": {"pele": 2, "cabelo": 0, "cor_cabelo": 0, "barba": 1, "roupa": 2, "marcas": []},
		"appearance_extra": "", "backstory": "", "traits": [],
		"origin": origin["id"], "money": 1200, "location": "lanchonete",
		"home": "apartamento", "inventory": {}, "alive": true,
	})
	TimeManager.total_minutes = 10 * 60
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var screen = preload("res://ui/game_screen.gd").new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	for i in 10:
		await get_tree().process_frame
	var wv = screen.world_view
	var lot := "lanchonete"
	check(wv.layout.in_building(lot, wv._p2()), "começa dentro da lanchonete")
	# sai
	wv._go_to(wv.layout.door_out(lot) + Vector2(0, 6))
	await _walk(wv, 400)
	check(not wv.layout.in_building(lot, wv._p2()), "saiu do prédio (%s)" % wv._p2())
	check(World.current_id() != "" , "tem local")
	# volta a entrar clicando dentro
	var inside: Vector2 = wv.layout.door_in(lot) + Vector2(0, -2)
	wv._go_to(inside)
	await _walk(wv, 600)
	print("DBG door disabled=", wv.city.loc_info[lot]["door"].disabled, " locked=", wv._door_locked.get(lot), " cur=", World.current_id(), " pos=", wv.player.position, " vel=", wv.player.velocity, " b=", wv.layout.lots[lot]["building"], " path=", wv.path)
	check(wv.layout.in_building(lot, wv._p2()), "voltou a entrar (%s, alvo %s)" % [wv._p2(), inside])
	# sai de novo e entra pelo mapa
	wv._go_to(wv.layout.door_out(lot) + Vector2(0, 6))
	await _walk(wv, 400)
	World.request_travel(lot, "ape")
	await _walk(wv, 600)
	check(wv.layout.in_building(lot, wv._p2()), "entrou pelo mapa (%s)" % wv._p2())
	# ---- casas com fechadura ----
	var hid: String = wv.layout.house_ids[5]
	Houses.st(hid)["lock"] = "locked"
	Houses.st(hid)["tipo"] = "familia"
	Houses.st(hid)["ocupada"] = false
	check(World.door_locked(hid) and not World.is_accessible(hid), "casa trancada bloqueia a porta")
	var dout: Vector2 = wv.layout.door_out(hid)
	wv.player.position = Vector3(dout.x, 0.25, dout.y)
	wv.path = PackedVector2Array()
	wv._update_environment()
	wv._update_location()
	check(Houses.near_door == hid, "perto da porta trancada (%s)" % Houses.near_door)
	var ids: Array = Economy.available_actions().map(func(a): return a["id"])
	check("porta:arrombar" in ids and "porta:tentar" in ids and "porta:bater" in ids, "ações de porta aparecem")
	# tenta entrar andando: o colisor da porta segura
	var din: Vector2 = wv.layout.door_in(hid)
	wv._go_to(din)
	await _walk(wv, 300)
	check(not wv.layout.in_building(hid, wv._p2()), "porta trancada não deixa entrar")
	# sem ferramenta não arromba
	var before: String = str(Houses.st(hid)["lock"])
	Houses.do("porta:arrombar")
	check(str(Houses.st(hid)["lock"]) == before, "sem ferramenta não arromba")
	GameState.add_item("pe_de_cabra")
	var tries := 0
	while str(Houses.st(hid)["lock"]) == "locked" and tries < 12:
		Houses.do("porta:arrombar")
		tries += 1
	check(str(Houses.st(hid)["lock"]) == "broken", "arrombar abre a porta (%d tentativas)" % tries)
	CrimeSystem.set_wanted(0)
	wv._update_environment()
	check(not World.door_locked(hid), "porta arrombada fica aberta")
	wv.player.position = Vector3(dout.x, 0.25, dout.y)
	wv._go_to(din)
	await _walk(wv, 400)
	check(wv.layout.in_building(hid, wv._p2()), "entra na casa depois de arrombar (%s)" % wv._p2())
	wv._update_location()
	check(World.current_id() == hid, "local atual é a casa")
	# interior surgiu
	for i in 40:
		await get_tree().physics_frame
	var st: Dictionary = wv.city.loc_info[hid]["structure"]
	check(st.get("interior") != null, "interior da casa foi construído")
	var items_before: int = GameState.item_count("pao") + GameState.item_count("agua") + GameState.item_count("miojo") + GameState.item_count("frutas")
	var money_before: int = GameState.money()
	Houses.st(hid)["tipo"] = "familia"
	var got := false
	for i in 8:
		Houses.st(hid)["busca"] = -1
		Houses.do("casa_g:vasculhar")
		if GameState.money() > money_before or GameState.item_count("pao") + GameState.item_count("agua") + GameState.item_count("miojo") + GameState.item_count("frutas") > items_before:
			got = true
			break
	check(got, "vasculhar rende algo")
	check(int(Houses.st(hid)["busca"]) == TimeManager.day(), "só uma busca por dia")
	CrimeSystem.set_wanted(0)
	# chave abre a porta
	var h2: String = wv.layout.house_ids[9]
	Houses.st(h2)["lock"] = "locked"
	check(Houses.locked(h2), "outra casa trancada")
	World.grant_key("casa:" + h2, 3)
	check(not Houses.locked(h2), "com a chave a porta abre")
	print("RESULTADO WALK: ", "OK" if fails.is_empty() else "%d falha(s)" % fails.size())
	SaveManager.delete_save()
	get_tree().quit(0 if fails.is_empty() else 1)


func _walk(wv, frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
		if wv.path.is_empty():
			break
