extends Node

# Prédio na frente do jogador some (estilo Project Zomboid). Põe o jogador atrás de um prédio
# e tira captura com e sem a regra. Uso: godot --path . res://tests/hide_shots.tscn

const UITheme = preload("res://ui/ui_theme.gd")


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "user://esconde_save.json"
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x",
		"look": {"pele": 2, "cabelo": 0, "cor_cabelo": 0, "roupa": 2, "marcas": []},
		"appearance_extra": "", "backstory": "", "traits": [], "cenario": "porto_cinza",
		"origin": origin["id"], "money": 400, "location": "rua", "home": "apartamento", "inventory": {}, "alive": true,
	})
	TimeManager.total_minutes = 1440 + 11 * 60
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var screen = preload("res://ui/game_screen.gd").new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	for i in 40:
		await get_tree().process_frame
	var wv = screen.world_view
	while not wv._built:
		await get_tree().process_frame
	for i in 60:
		await get_tree().process_frame
	var out := OS.get_environment("HIDE_OUT") if OS.get_environment("HIDE_OUT") != "" else OS.get_user_data_dir()
	# alvos: o prédio mais alto e a casa (lote) mais próxima do jogador
	var tall: Dictionary = {}
	var house: Dictionary = {}
	var shop: Dictionary = {}
	var tallest := 0.0
	var nearest := INF
	for s in wv.city.structures:
		var h: float = wv._structure_height(s)
		s["h"] = h
		if h > tallest and (s["rect"] as Rect2).size.length() > 8.0:
			tallest = h
			tall = s
		var dist := (s["rect"] as Rect2).get_center().distance_to(wv._p2())
		if s.get("enterable", false) and not s.has("lot") and str(s.get("loc", "")) in ["bar", "lanchonete", "mercado"] and shop.is_empty():
			shop = s
		if s.has("lot") and dist < nearest:
			nearest = dist
			house = s
	print("estruturas=", wv.city.structures.size(), " alto=", tallest, " casa=", nearest)
	var fails := 0
	for pair in [["predio", tall], ["casa", house], ["loja", shop]]:
		var target: Dictionary = pair[1]
		if target.is_empty():
			continue
		var r: Rect2 = target["rect"]
		var d: Vector3 = wv.CAM_DIR.normalized()
		var away := -Vector2(d.x, d.z).normalized()
		# atrás = do lado oposto à câmera, a 1,2 m da parede
		var behind := r.get_center()
		while r.grow(1.2).has_point(behind):
			behind += away * 0.2
		wv.player.position = Vector3(behind.x, 0.25, behind.y)
		wv.player.velocity = Vector3.ZERO
		wv.cam_target = wv.player.position + Vector3(0, 1.0, 0)
		wv.zoom = 11.0
		wv.camera.size = 11.0
		for i in 40:
			await get_tree().process_frame
		var cut: bool = target["cut_now"]
		var flat: bool = is_equal_approx((target["root"] as Node3D).scale.y, 1.0)
		print("%s atrás: recortado=%s escala=%.2f altura=%.1f" % [pair[0], cut, (target["root"] as Node3D).scale.y, float(target["h"])])
		if not cut or not flat:
			fails += 1
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/esconde_%s_depois.png" % pair[0])
		# sem a regra, para comparar
		wv.set_process(false)
		wv.city.set_cut(target, false)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/esconde_%s_antes.png" % pair[0])
		wv.set_process(true)
		# saindo de trás, a fachada volta
		wv.player.position = Vector3(r.get_center().x, 0.25, r.get_center().y) + Vector3(-d.x, 0, -d.z).normalized() * 0.0 + Vector3(d.x, 0, d.z).normalized() * (r.size.length() * 0.5 + 8.0)
		wv.cam_target = wv.player.position + Vector3(0, 1.0, 0)
		for i in 60:
			await get_tree().process_frame
		print("%s saindo: recortado=%s" % [pair[0], target["cut_now"]])
		if target["cut_now"]:
			fails += 1
	print("RESULTADO ESCONDE: ", "OK" if fails == 0 else str(fails) + " falhas")
	SaveManager.delete_save()
	get_tree().quit()
