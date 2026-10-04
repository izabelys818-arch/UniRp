extends Node

const UITheme = preload("res://ui/ui_theme.gd")


func _ready() -> void:
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
	get_tree().quit()


func _shot(file: String) -> void:
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := OS.get_user_data_dir() + "/" + file
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT: ", path)
