extends Node

# Faixas de idade na câmera real do jogo: jogador idoso (cansado) ao lado de uma criança, um
# adolescente e uma adulta; dia, noite, chuva e andando. Uso: GALLERY_SCEN=vale_sereno godot --path . res://tests/ages_ingame.tscn

const UITheme = preload("res://ui/ui_theme.gd")
const Person = preload("res://world3d/person.gd")
const LookBuilder = preload("res://ui/face/look_builder.gd")


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "user://idades_save.json"
	var scen := OS.get_environment("GALLERY_SCEN")
	if scen == "":
		scen = "porto_cinza"
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Seu Dito", "age": 72, "gender": "homem", "appearance": "x",
		"look": {"pele": 3, "cabelo": 3, "cor_cabelo": 1, "barba": 4, "roupa": 13, "marcas": []},
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
	var p: Vector2 = wv.layout.door_out("praca") + Vector2(2, 3)
	wv.player.position = Vector3(p.x, 0.25, p.y)
	wv.player_fig.set_emotion("exausto", false)
	var others: Array = []
	for a in [[9, "mulher", {"pele": 1, "cabelo": 11, "cor_cabelo": 3, "roupa": 9, "cor_roupa": "#c97a5a"}, Vector3(1.1, 0, 0.3), "feliz"],
			[15, "homem", {"pele": 4, "cabelo": 13, "cor_cabelo": 0, "roupa": 1}, Vector3(-1.1, 0, 0.4), "entediado"],
			[34, "mulher", {"pele": 2, "cabelo": 4, "cor_cabelo": 2, "roupa": 3}, Vector3(0.2, 0, 1.3), "neutro"]]:
		var f := Person.new()
		wv.viewport.add_child(f)
		f.set_look(LookBuilder.build(a[2], int(a[0]), str(a[1])))
		f.set_emotion(str(a[4]))
		f.position = wv.player.position + (a[3] as Vector3) - Vector3(0, 0.08, 0)
		f.rotation.y = randf_range(-0.5, 0.5)
		others.append([f, a[3]])
	for sh in [["dia", 10.0, false], ["noite", 21.5, false], ["chuva", 14.0, true], ["andando", 16.0, false]]:
		TimeManager.total_minutes = 1440 * 2 + int(float(sh[1]) * 60.0)
		if sh[2]:
			WorldEvents.start("tempestade", 5.0)
		else:
			WorldEvents.stop("tempestade")
		wv.cam_target = wv.player.position
		wv.zoom = 6.5
		wv.camera.size = wv.zoom
		wv._update_environment()
		for i in 70:
			if sh[0] == "andando":
				# todos andam juntos pela calçada
				var step := Vector3(0.025, 0, 0.0)
				wv.player.position += step
				for o in others:
					(o[0] as Node3D).position += step
				wv.cam_target = wv.player.position
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := OS.get_user_data_dir() + "/idades_%s_%s.png" % [scen, sh[0]]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
	SaveManager.delete_save()
	get_tree().quit()
