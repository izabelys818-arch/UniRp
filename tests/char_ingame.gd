extends Node

# O jogador na câmera real do jogo (dia, noite, chuva; parado e andando). Uso: CHAR_TAG=x godot --path . res://tests/char_ingame.tscn

const UITheme = preload("res://ui/ui_theme.gd")


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "user://char_save.json"
	var scen := OS.get_environment("GALLERY_SCEN")
	if scen == "":
		scen = "porto_cinza"
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x",
		"look": {"pele": 2, "cabelo": 0, "cor_cabelo": 0, "barba": 1, "roupa": 2, "marcas": []},
		"appearance_extra": "", "backstory": "", "traits": [], "cenario": scen,
		"origin": origin["id"], "money": 400, "location": "rua", "home": "apartamento", "inventory": {}, "alive": true,
	})
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var screen = preload("res://ui/game_screen.gd").new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	await get_tree().process_frame
	var wv = screen.world_view
	screen.side_box.get_parent().get_parent().hide()
	var tag := OS.get_environment("CHAR_TAG")
	var p: Vector2 = wv.layout.door_out("praca") + Vector2(2, 3)
	for sh in [["dia", 10.0, false, 8.0], ["noite", 21.5, false, 8.0], ["chuva", 14.0, true, 8.0], ["longe", 10.0, false, 16.0]]:
		TimeManager.total_minutes = 1440 * 2 + int(float(sh[1]) * 60.0)
		if sh[2]:
			WorldEvents.start("tempestade", 5.0)
		else:
			WorldEvents.stop("tempestade")
		wv.player.position = Vector3(p.x, 0.25, p.y)
		wv.cam_target = wv.player.position
		wv.zoom = float(sh[3])
		wv.camera.size = wv.zoom
		wv._update_environment()
		for i in 60:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := OS.get_user_data_dir() + "/charjogo_%s_%s.png" % [sh[0], tag]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
	SaveManager.delete_save()
	get_tree().quit()
