extends Node

const UITheme = preload("res://ui/ui_theme.gd")


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	SaveManager.path = "user://test_save.json"
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "jaqueta de couro",
		"look": {"pele": 2, "cabelo": 0, "cor_cabelo": 0, "barba": 1, "roupa": 2, "marcas": [0]},
		"appearance_extra": "", "backstory": "", "traits": [],
		"origin": origin["id"], "money": 1200, "location": "lanchonete",
		"home": "apartamento", "inventory": {"pao": 1, "agua": 2}, "alive": true,
	})
	TimeManager.total_minutes = 9 * 60
	NeedsSystem.reset({"saciedade": 18})
	NPCManager.reset_state(origin)
	GameState.add_log(World.current()["descricao"], "narration")
	NPCManager.start_conversation("marina")
	GameState.add_log("Oi Marina, tudo bem? *sento no balcão*", "player", "Rafa")
	NPCManager._apply_reply("marina", {"acao_corporal": "enxuga os olhos com o avental", "fala": "Desculpa... dia difícil. O que vai ser?", "emocao": "chorando"})

	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var screen = preload("res://ui/game_screen.gd").new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	await _shot("screenshot.png")
	PhoneSystem.add_contact("marina")
	PhoneSystem.add_contact("bia")
	PhoneSystem._push("marina", true, "oi, tudo bem? é o Rafa da lanchonete", "visualizada")
	PhoneSystem._push("marina", false, "oi rafa kkk tô no intervalo")
	PhoneSystem._push("marina", false, "vc vai passar aqui hj?")
	PhoneSystem._push("bia", false, "vc viu o q aconteceu no parque??")
	PhoneSystem.phone()["unread"]["bia"] = 1
	screen.phone.open("thread", "marina")
	await _shot("screenshot_phone.png")
	screen.phone.open("home")
	await _shot("screenshot_phone_home.png")
	screen.queue_free()
	var creator = preload("res://ui/character_creation.gd").new()
	creator.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(creator)
	creator.player_name = "Rafa"
	creator._show_tab(1)
	creator.tab_buttons[1].button_pressed = true
	await _shot("screenshot_creator.png")
	creator.queue_free()
	var menu = preload("res://ui/main_menu.gd").new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(menu)
	await get_tree().create_timer(0.8).timeout
	await _shot("screenshot_menu.png")
	menu.queue_free()
	var game2 = preload("res://ui/game_screen.gd").new()
	game2.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(game2)
	await get_tree().process_frame
	game2.map_panel.open()
	game2.map_panel._fill_info("parque")
	await _shot("screenshot_map.png")
	game2.map_panel.close()
	game2.bag.open()
	game2.bag._select("pao")
	await _shot("screenshot_bag.png")
	game2.bag.close()
	game2._open_context("marina")
	await _shot("screenshot_context.png")
	game2.context_menu.hide()
	World.move_player_to("pensao")
	NPCManager.start_conversation("dona_cida")
	NPCManager.state["dona_cida"]["pago"] = 80
	NPCManager._apply_action("dona_cida", {"tipo": "alugar_quarto"}, NPCManager.PRESENCIAL)
	await _shot("screenshot_pensao.png")
	Economy.do_action("entrar:quarto_pensao")
	game2.bag.open()
	await _shot("screenshot_quarto.png")
	game2.bag.close()
	World.move_player_to("lanchonete")
	CrimeSystem.set_wanted(3)
	CrimeSystem.police_lights = true
	CrimeSystem._choice_open = true
	game2.choice_panel.show_choice({"title": "POLÍCIA!", "kind": "police", "text": "O Sargento Otávio te reconhece. Mão na cabeça! Encosta na parede!\nVocê está sendo procurado (3 estrelas).", "options": [{"label": "Se render", "callback": func(): pass}, {"label": "Fugir", "callback": func(): pass}, {"label": "Oferecer R$ 450 por fora", "callback": func(): pass}]})
	await _shot("screenshot_police.png")
	game2.choice_panel.hide()
	CrimeSystem.police_lights = false
	CrimeSystem._choice_open = false
	game2._open_context("marina")
	await _shot("screenshot_violence.png")
	game2.context_menu.hide()
	CrimeSystem.set_wanted(0)
	CrimeSystem.start_fire("lanchonete")
	game2.choice_panel.hide()
	CrimeSystem._choice_open = false
	await _shot("screenshot_fire.png")
	CrimeSystem.data()["fire"] = {}
	game2.phone.open("emergency")
	await _shot("screenshot_emergency.png")
	game2.phone.close()
	GameState.add_money(9000)
	GameState.player.erase("housing")
	GameState.player["home"] = ""
	HomeSystem.rent("kitnet_centro")
	for item in ["cama_boa", "fogao", "geladeira", "tv", "sofa", "computador"]:
		HomeSystem.order(item, "kitnet_centro")
	HomeSystem.order_internet("kitnet_centro")
	TimeManager.total_minutes += 1500
	HomeSystem._on_time_advanced(1, false)
	TimeManager.total_minutes += 30 * 1440
	HomeSystem._on_time_advanced(1, false)
	World.move_player_to("kitnet_centro")
	await _shot("screenshot_casa.png")
	game2.phone.open("home")
	await _shot("screenshot_phone_apps.png")
	game2.phone.open("bills")
	await _shot("screenshot_bills.png")
	game2.phone.open("homes")
	await _shot("screenshot_homes.png")
	game2.phone.open("shop")
	await _shot("screenshot_shop.png")
	game2.phone.close()
	HomeSystem.rent("minha_lanchonete")
	BusinessSystem.restock("cafe", 30)
	BusinessSystem.restock("coxinha", 30)
	BusinessSystem.toggle_open()
	for h in [8, 9, 12, 13]:
		BusinessSystem.simulate_hour(h, true)
	game2.business_panel.open()
	await _shot("screenshot_biz.png")
	game2.business_panel.hide()
	GameState.player["cenario"] = "colapso"
	World.move_player_to("praca")
	TimeManager.total_minutes = TimeManager.day() * 1440 + 20 * 60
	WorldEvents.start("festa", 6.0)
	WorldEvents.start("apagao", 6.0)
	await _shot("screenshot_festa_colapso.png")
	WorldEvents.stop("apagao")
	GameState.player["cenario"] = "porto_cinza"
	await _shot("screenshot_festa.png")
	WorldEvents.start("gripe", 20.0)
	NewsSystem.ensure_columns()
	game2.phone.open("news")
	await _shot("screenshot_jornal.png")
	game2.phone.close()
	var wv = game2.world_view
	GameState.player["cenario"] = "porto_cinza"
	WorldEvents.stop("gripe")
	WorldEvents.stop("festa")
	TimeManager.total_minutes = TimeManager.day() * 1440 + 11 * 60
	World.move_player_to("lanchonete", "uber")
	game2._refresh()
	await _shot("mundo_dia_dentro.png")
	wv.player.position = Vector3(wv.layout.door_out("lanchonete").x + 6, 0.25, wv.layout.door_out("lanchonete").y + 5)
	wv.zoom = 24.0
	await _shot("mundo_dia_rua.png")
	TimeManager.total_minutes = TimeManager.day() * 1440 + 21 * 60
	wv._update_environment()
	await _shot("mundo_noite.png")
	World.move_player_to("praca", "uber")
	WorldEvents.start("festa", 6.0)
	wv.zoom = 20.0
	wv._snap_npcs = true
	await _shot("mundo_festa.png")
	var here: Array = NPCManager.npcs_here()
	if not here.is_empty():
		NPCManager.start_conversation(here[0])
		await _shot("mundo_conversa.png")
		NPCManager.end_conversation()
	World.move_player_to("lanchonete", "uber")
	game2._refresh()
	for i in 30:
		await get_tree().process_frame
	wv.zoom = 5.0
	wv.player_fig.rotation.y = 2.4
	await _shot("mundo_zoom.png")
	wv.player_fig.walking = true
	wv.player_fig.move_speed = 3.6
	for i in 8:
		await get_tree().process_frame
	await _shot("mundo_zoom_andando.png")
	get_tree().quit()


func _shot(file: String) -> void:
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := OS.get_user_data_dir() + "/" + file
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT: ", path)
