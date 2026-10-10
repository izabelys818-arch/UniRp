extends Node

# Abertura dos prédios (cutaway): casa virada para a câmera, casa virada para trás, lugar fixo e
# jogador atrás de uma torre (silhueta). Confere que só o prédio onde o jogador está fica aberto.
# Uso: GALLERY_SCEN=porto_cinza godot --path . res://tests/cut_shots.tscn

const UITheme = preload("res://ui/ui_theme.gd")
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("OK     " if ok else "FALHOU ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "user://cut_save.json"
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
	TimeManager.total_minutes = 1440 + int(float(OS.get_environment("CUT_HOUR") if OS.get_environment("CUT_HOUR") != "" else "10") * 60.0)
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
	for i in 40:
		await get_tree().process_frame
	var south := ""
	var north := ""
	for id in wv.layout.house_ids:
		var n: bool = wv.layout.lots[id]["north"]
		if n and north == "":
			north = id
		elif not n and south == "":
			south = id
	var tower := Rect2()
	for s in wv.city.structures:
		if not s.has("lot") and not s.get("enterable", false) and (s["rect"] as Rect2).size.x > 15.0:
			tower = s["rect"]
			break
	var shots := [
		["casa_frente", (wv.layout.lots[south]["building"] as Rect2).get_center(), south],
		["casa_fundo", (wv.layout.lots[north]["building"] as Rect2).get_center(), north],
		["bar_dentro", (wv.layout.lots["bar"]["building"] as Rect2).get_center() + Vector2(0, 2), "bar"],
	]
	if tower.size != Vector2.ZERO:
		# atrás da torre = do lado oposto à câmera (câmera fica em +x/+z)
		shots.append(["atras_torre", tower.position + Vector2(tower.size.x * 0.5, -2.5), ""])
	for sh in shots:
		var p: Vector2 = sh[1]
		wv.player.position = Vector3(p.x, 0.25, p.y)
		wv.cam_target = wv.player.position
		wv.zoom = 16.0
		wv.camera.size = wv.zoom
		for i in 40:
			await get_tree().process_frame
		var cut_count := 0
		var mine_cut := false
		for s in wv.city.structures:
			if bool(s["cut_now"]):
				cut_count += 1
				if str(s.get("loc", "")) == str(sh[2]):
					mine_cut = true
		if str(sh[2]) != "":
			check(mine_cut and cut_count == 1, "%s: só o prédio onde o jogador está fica aberto (abertos=%d)" % [sh[0], cut_count])
			for s in wv.city.structures:
				if str(s.get("loc", "")) == str(sh[2]) and s.has("lot"):
					check(s.get("interior") != null, "%s: interior montado junto com a abertura" % sh[0])
		else:
			check(cut_count == 0, "%s: nenhum prédio some atrás do jogador (abertos=%d)" % [sh[0], cut_count])
		await RenderingServer.frame_post_draw
		var path := OS.get_user_data_dir() + "/corte_%s_%s.png" % [scen, sh[0]]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
	print("RESULTADO CORTE: ", "OK" if fails == 0 else "%d falha(s)" % fails)
	SaveManager.delete_save()
	get_tree().quit()
