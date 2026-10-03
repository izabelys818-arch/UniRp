extends Node

const UITheme = preload("res://ui/ui_theme.gd")


func _ready() -> void:
	SaveManager.path = "user://test_save.json"
	PortraitService.dir = "user://test_portraits"
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "jaqueta jeans",
		"appearance_extra": "", "backstory": "", "traits": [],
		"origin": origin["id"], "money": 1200, "location": "lanchonete",
		"home": "apartamento", "inventory": {"pao": 1, "agua": 2}, "alive": true,
	})
	TimeManager.total_minutes = 9 * 60
	NeedsSystem.reset({"saciedade": 18})
	NPCManager.reset_state(origin)
	var img := Image.create(600, 800, false, Image.FORMAT_RGB8)
	img.fill(Color("#5a4a42"))
	PortraitService.store("marina", "neutro", img)
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
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/screenshot.png")
	print("SHOT: ", OS.get_user_data_dir() + "/screenshot.png")
	screen.queue_free()
	var creator = preload("res://ui/character_creation.gd").new()
	creator.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(creator)
	creator.name_edit.text = "Rafa"
	var img2 := Image.create(600, 800, false, Image.FORMAT_RGB8)
	img2.fill(Color("#3d4a5a"))
	PortraitService.store("player_draft", "neutro", img2)
	creator._update_face_buttons()
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/screenshot_creator.png")
	PortraitService.clear_all()
	get_tree().quit()
