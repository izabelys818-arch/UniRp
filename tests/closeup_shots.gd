extends Node

# Fotos de perto na câmera do jogo para revisar problemas visuais: casas com garagem (e o
# carro na entrada), árvores e pessoas. CLOSE_OUT=<pasta>.

const UITheme = preload("res://ui/ui_theme.gd")


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "user://close_save.json"
	get_window().size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x",
		"look": {"pele": 2, "cabelo": 0, "cor_cabelo": 0, "roupa": 2, "marcas": []},
		"appearance_extra": "", "backstory": "", "traits": [], "cenario": "porto_cinza",
		"origin": origin["id"], "money": 400, "location": "rua", "home": "apartamento", "inventory": {}, "alive": true,
	})
	TimeManager.total_minutes = 1440 + 10 * 60
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var screen = preload("res://ui/game_screen.gd").new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	var wv = screen.world_view
	while wv == null or not wv._built:
		await get_tree().process_frame
		wv = screen.world_view
	var out := OS.get_environment("CLOSE_OUT") if OS.get_environment("CLOSE_OUT") != "" else OS.get_user_data_dir() + "/close"
	DirAccess.make_dir_recursive_absolute(out)
	var spots: Array = []
	var garages := 0
	for s in wv.city.structures:
		if s.has("lot") and bool(s["style"].get("garage", false)) and garages < 4:
			var r: Rect2 = s["lot"]["rect"]
			spots.append(["garagem%d" % garages, r.get_center() + Vector2(0, 2)])
			garages += 1
	spots.append(["praca", wv.layout.door_out("praca")])
	spots.append(["rua", wv.layout.door_out("lanchonete") + Vector2(0, 3)])
	spots.append(["pessoas", wv.layout.door_out("praca")])
	spots.append(["parque", wv.layout.door_out("parque") + Vector2(0, -10)])
	spots.append(["parque2", wv.layout.door_out("parque") + Vector2(-12, -18)])
	for spot in spots:
		var p: Vector2 = spot[1]
		wv.player.position = Vector3(p.x, 0.25, p.y)
		wv.player.velocity = Vector3.ZERO
		wv.cam_target = wv.player.position + Vector3(0, 1.0, 0)
		var z: float = 3.2 if spot[0] == "pessoas" else 8.0
		wv.zoom = z
		wv.camera.size = z
		for i in 90:
			await get_tree().process_frame
		if spot[0] == "pessoas":
			# encosta os pedestres mais próximos no jogador para a foto de perto
			var k := 0
			for e in wv.life.peds:
				var fig: Node3D = e.get("fig")
				if fig == null:
					continue
				fig.position = Vector3(p.x + 1.2 + k * 0.9, fig.position.y, p.y + (k % 2) * 0.8)
				k += 1
				if k >= 3:
					break
			for i in 3:
				await get_tree().process_frame
		for child in screen.get_children():
			if child is CanvasItem and child != wv:
				(child as CanvasItem).visible = false
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/%s.png" % spot[0])
		print("CLOSE ", spot[0])
	# faróis do trânsito à noite: a luz tem que apontar para a frente do carro
	TimeManager.total_minutes = 1440 + 22 * 60
	wv._update_environment()
	for i in 30:
		await get_tree().process_frame
	for l in wv.life.head_lights:
		if (l as SpotLight3D).visible:
			var best: Dictionary = {}
			var bd := INF
			for e in wv.life.cars:
				var d := (e["node"] as Node3D).global_position.distance_to(l.global_position)
				if d < bd:
					bd = d
					best = e
			var fwd: Vector3 = (best["node"] as Node3D).global_basis.z.normalized()
			var aim: Vector3 = -(l as SpotLight3D).global_basis.z.normalized()
			print("FAROL frente_dot=%.2f" % fwd.dot(aim))
	SaveManager.delete_save()
	get_tree().quit()
