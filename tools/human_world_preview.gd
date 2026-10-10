extends Node

# Captura do visual na cidade e amostra de custo de renderização.
# Partida temporária em memória, sem salvar/carregar a partida do jogador.
const UITheme = preload("res://ui/ui_theme.gd")
const WorldView = preload("res://world3d/world_view.gd")
var screen: Control
var output := "C:/Users/glznc/Documents/Codex/2026-10-10/humans"


func _ready() -> void:
	get_viewport().gui_disable_input = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	WorldView.realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "user://human_visual_preview_unused.json"
	var scen := OS.get_environment("HUMAN_SCENE")
	if scen == "":
		scen = "porto_cinza"
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({"name": "Rafa", "age": 34, "gender": "homem", "appearance": "",
		"look": {"pele": 2, "cabelo": 0, "barba": 1, "roupa": 1, "corpo": 1},
		"appearance_extra": "", "backstory": "", "traits": [], "cenario": scen,
		"origin": origin["id"], "money": 400, "location": "rua", "home": "apartamento", "inventory": {}, "alive": true})
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	screen = preload("res://ui/game_screen.gd").new()
	screen.theme = UITheme.build()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	await get_tree().process_frame
	var wv = screen.world_view
	while not wv._built:
		await get_tree().process_frame
	screen.side_box.get_parent().get_parent().hide()
	var point: Vector2 = wv.layout.door_out("praca") + Vector2(2, 3)
	wv.player.position = Vector3(point.x, 0.25, point.y)
	wv.cam_target = wv.player.position
	wv.zoom = 8.0
	wv.camera.size = 8.0
	for mode in [["dia", 11.0, false], ["noite", 21.5, false], ["chuva", 14.0, true]]:
		TimeManager.total_minutes = 2880 + int(float(mode[1]) * 60)
		if mode[2]:
			WorldEvents.start("tempestade", 5)
		else:
			WorldEvents.stop("tempestade")
		wv._update_environment()
		for frame in 120:
			await get_tree().process_frame
		var ms := 0.0
		var worst := 0.0
		for frame in 600:
			await get_tree().process_frame
			var elapsed: float = get_process_delta_time() * 1000
			ms += elapsed
			worst = maxf(worst, elapsed)
		print("VISUAL SAMPLE ", scen, " ", mode[0], " FPS ", snappedf(600000 / ms, 0.1), " worst_ms ", snappedf(worst, 0.1))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output + "/cidade_" + scen + "_" + str(mode[0]) + ".png")
		print("CITY CAPTURE ", scen, " ", mode[0])
	screen.queue_free()
	await get_tree().process_frame
	get_tree().quit()
