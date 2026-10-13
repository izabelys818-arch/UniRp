extends "res://tools/urban_review.gd"

func _ready() -> void:
	if OS.get_environment("URBAN_OUTPUT") != "":
		output = OS.get_environment("URBAN_OUTPUT")
	DirAccess.make_dir_recursive_absolute(output + "/after")
	get_window().size = Vector2i(1280, 800)
	get_window().content_scale_size = Vector2i(1280, 800)
	View.realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "user://urban_detail_unused.json"
	GameState.new_game({"name": "Teste", "age": 30, "gender": "homem", "cenario": "porto_cinza", "origin": "morador_antigo", "money": 400,
		"location": "rua", "home": "apartamento", "inventory": {}, "alive": true})
	NPCManager.reset_state(World.get_origin("morador_antigo"))
	NeedsSystem.reset({})
	TimeManager.total_minutes = 1440 + 660
	view = View.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	while not view._built:
		await get_tree().process_frame
	view.set_process(false)
	view.player.position = Vector3(105, 0.17, 85)
	focus = Vector3(105, 2.0, 96)
	direction = Vector3(-1, 1.15, -1)
	framing = 24.0
	for frame in 180:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	view.viewport.get_texture().get_image().save_png(output + "/after/porto_cinza_fachadas.png")
	var entry: Dictionary = view.npcs["irene"]
	view._choose_act(entry, entry["fig"])
	view.player.position = Vector3(105, 0.17, 113.2)
	view._cutaway()
	focus = Vector3(108, 1.3, 108)
	direction = View.CAM_DIR
	framing = 17.0
	# Aguarda a chegada real ao posto; capturar enquanto anda não comprova trabalho.
	var work_deadline := Time.get_ticks_msec() + 30000
	while entry["act"] != "mexer" and Time.get_ticks_msec() < work_deadline:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	view.viewport.get_texture().get_image().save_png(output + "/after/porto_cinza_mercado_interior.png")
	print("DETAIL worker=", entry["act"], " position=", entry["fig"].position, " active=", entry["fig"].visible)
	# Pequena sequência de movimento real, sem interpolar/imitar quadros.
	view.player.position = Vector3(105, 0.17, 121)
	focus = Vector3(105, 1.5, 110)
	framing = 38.0
	DirAccess.make_dir_recursive_absolute(output + "/movement")
	for frame in 12:
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		view.viewport.get_texture().get_image().save_png(output + "/movement/%02d.png" % frame)
	get_tree().quit()
