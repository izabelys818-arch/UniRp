extends Node

# Deixa a cidade viver por alguns segundos e mostra o que as pessoas estão fazendo
# (sentadas, conversando, no celular, andando...). Uso: godot --path . res://tests/life_shots.tscn

const UITheme = preload("res://ui/ui_theme.gd")


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "user://life_save.json"
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x",
		"look": {"pele": 2, "cabelo": 0, "cor_cabelo": 0, "barba": 1, "roupa": 2, "marcas": []},
		"appearance_extra": "", "backstory": "", "traits": [], "cenario": "porto_cinza",
		"origin": origin["id"], "money": 400, "location": "praca", "home": "apartamento", "inventory": {}, "alive": true,
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
	await get_tree().process_frame
	var wv = screen.world_view
	screen.dialogue.hide()
	screen.side_box.get_parent().get_parent().hide()
	for spot in [["praca", Vector2(0, 2)], ["bar", Vector2(2, -3)]]:
		var target: Vector2 = wv.layout.door_out(str(spot[0])) + (spot[1] as Vector2)
		wv.player.position = Vector3(target.x, 0.25, target.y)
		wv.cam_target = wv.player.position
		wv.zoom = 12.0
		wv.camera.size = wv.zoom
		var acts := {}
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 40000:
			await get_tree().process_frame
		for id in wv.npcs:
			var e: Dictionary = wv.npcs[id]
			var a := str(e.get("act", ""))
			if a == "" and not (e["path"] as PackedVector2Array).is_empty():
				a = "andando"
			elif a == "":
				a = "parado"
			acts[a] = int(acts.get(a, 0)) + 1
		print("VIDA %s: %s" % [spot[0], acts])
		await RenderingServer.frame_post_draw
		var path := OS.get_user_data_dir() + "/vida_%s.png" % spot[0]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
		# de perto: alguém sentado e alguém conversando, se houver
		for want in ["sentar", "conversar"]:
			for id in wv.npcs:
				if str(wv.npcs[id].get("act", "")) == want and (wv.npcs[id]["fig"] as Node3D).visible:
					var f: Node3D = wv.npcs[id]["fig"]
					wv.cam_target = f.position + Vector3(0, 1.0, 0)
					wv.player.position = f.position + Vector3(1.1, 0.08, 1.1)
					wv.zoom = 4.5
					wv.camera.size = 4.5
					for i in 20:
						await get_tree().process_frame
					await RenderingServer.frame_post_draw
					var p2 := OS.get_user_data_dir() + "/vida_%s_%s.png" % [spot[0], want]
					get_viewport().get_texture().get_image().save_png(p2)
					print("SHOT ", p2)
					break
	SaveManager.delete_save()
	get_tree().quit()
