extends Node

# Mundo vivo no 3D: chuva com guarda-chuva (NPCs e jogador), carrinho de bebê, criança encolhida
# na chuva, amigo acenando; depois a cidade de verdade na chuva e a festa na praça (dança).
# Uso: godot --path . res://tests/life_rain_shots.tscn

const UITheme = preload("res://ui/ui_theme.gd")
const Person = preload("res://world3d/person.gd")
const LookBuilder = preload("res://ui/face/look_builder.gd")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OS.get_user_data_dir() + "/vida_%s.png" % name
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "user://vida_save.json"
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x",
		"look": {"pele": 2, "cabelo": 0, "cor_cabelo": 0, "barba": 1, "roupa": 2, "marcas": []},
		"appearance_extra": "", "backstory": "", "traits": [], "cenario": "porto_cinza",
		"origin": origin["id"], "money": 400, "location": "praca", "home": "apartamento", "inventory": {}, "alive": true,
	})
	TimeManager.total_minutes = 1440 * 2 + 14 * 60
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	Population.populate(4)
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
	var p: Vector2 = wv.layout.door_out("praca") + Vector2(3, 4)
	wv.player.position = Vector3(p.x, 0.25, p.y)
	WorldEvents.start("tempestade", 6.0)
	# figurantes de perto: guarda-chuva, carrinho de bebê, criança sem guarda-chuva, amigo acenando
	var figs: Array = []
	var specs := [
		[{"pele": 3, "cabelo": 4, "cor_cabelo": 1, "roupa": 13}, 36, "mulher", Vector3(1.4, 0, 0.6), "guarda"],
		[{"pele": 1, "cabelo": 0, "cor_cabelo": 2, "barba": 1, "roupa": 3}, 31, "homem", Vector3(-1.6, 0, 0.2), "carrinho"],
		[{"pele": 4, "cabelo": 5, "cor_cabelo": 0, "roupa": 1}, 9, "mulher", Vector3(0.4, 0, -1.3), "crianca"],
		[{"pele": 2, "cabelo": 3, "cor_cabelo": 3, "roupa": 0}, 27, "homem", Vector3(-0.6, 0, 1.6), "aceno"],
	]
	for sp in specs:
		var f := Person.new()
		wv.viewport.add_child(f)
		f.set_look(LookBuilder.build(sp[0], int(sp[1]), str(sp[2])))
		f.position = wv.player.position + (sp[3] as Vector3) - Vector3(0, 0.08, 0)
		match str(sp[4]):
			"guarda":
				f.set_umbrella(true)
			"carrinho":
				f.set_stroller(true)
				f.rotation.y = PI * 0.5
			"crianca":
				f.hunched = true
			"aceno":
				f.rotation.y = PI
		figs.append([f, sp[4]])
	wv.zoom = 5.0
	wv.camera.size = wv.zoom
	wv.cam_target = wv.player.position
	for i in 80:
		# andam devagar pela calçada; o amigo acena para o jogador
		for fr in figs:
			if fr[1] in ["guarda", "carrinho"]:
				(fr[0] as Node3D).position.x += 0.012
			if fr[1] == "aceno" and i % 60 == 5:
				(fr[0] as Person).wave()
		wv.cam_target = wv.player.position
		await get_tree().process_frame
	await _shot("chuva_perto")
	for fr in figs:
		(fr[0] as Node3D).queue_free()
	# a cidade de verdade na chuva: quem está na rua abre o guarda-chuva
	wv.zoom = 15.0
	wv.camera.size = wv.zoom
	for i in 360:
		await get_tree().process_frame
	await _shot("chuva_cidade")
	# festa na praça à noite
	WorldEvents.stop("tempestade")
	TimeManager.total_minutes = 1440 * 3 + 19 * 60
	WorldEvents.start("festa", 6.0)
	wv._snap_npcs = true
	var plaza: Rect2 = wv.layout.lots["praca"].get("rect", Rect2())
	var pc: Vector2 = plaza.get_center() if plaza.size != Vector2.ZERO else p
	wv.player.position = Vector3(pc.x, 0.25, pc.y)
	wv.cam_target = wv.player.position
	wv.zoom = 11.0
	wv.camera.size = wv.zoom
	var dancing := 0
	for i in 1500:
		await get_tree().process_frame
		if i % 300 == 299:
			dancing = 0
			var at := 0
			for id in wv.npcs:
				if str(wv.npcs[id]["loc"]) == "praca":
					at += 1
				if str(wv.npcs[id].get("act", "")) == "dancar":
					dancing += 1
			print("festa: %d na praça, %d dançando" % [at, dancing])
			if dancing >= 2:
				break
	print("NA FESTA dançando: ", dancing)
	await _shot("festa")
	SaveManager.delete_save()
	get_tree().quit()
