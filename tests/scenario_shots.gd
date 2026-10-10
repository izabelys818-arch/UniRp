extends Node

# Fotografa os quatro cenários em horários e climas diferentes (uso: GALLERY_SCEN=porto_cinza).

const UITheme = preload("res://ui/ui_theme.gd")


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "user://test_save.json"
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
	screen.dialogue.hide()
	screen.side_box.get_parent().get_parent().hide()
	for i in 60:
		await get_tree().process_frame
	var shots := [
		["bar", 17.4, 22.0, false, Vector2(6, 9)],
		["casa", 9.0, 18.0, false, Vector2(0, 0)],
		["casa2", 9.0, 13.0, false, Vector2(0, 0)],
		["praca", 21.5, 26.0, false, Vector2(4, 12)],
		["comercio", 13.0, 30.0, true, Vector2(0, 0)],
	]
	for sh in shots:
		var target := Vector2.ZERO
		match str(sh[0]):
			"casa", "casa2":
				target = wv.layout.door_out(wv.layout.house_ids[12]) + (Vector2(2, 3) if str(sh[0]) == "casa" else Vector2(-6, -9))
			"comercio":
				for c in wv.layout.blocks:
					if str(wv.layout.blocks[c].get("kind", "")) == "comercio":
						target = Vector2(Layout_rect_center(c).x, Layout_rect_center(c).y + 17.0)
						break
				if target == Vector2.ZERO:
					target = wv.layout.door_out("mercado") + Vector2(0, 4)
			_:
				target = wv.layout.door_out(str(sh[0])) + (sh[4] as Vector2)
		TimeManager.total_minutes = 2 * 1440 + int(float(sh[1]) * 60.0)
		if sh[3]:
			WorldEvents.start("tempestade", 5.0)
		else:
			WorldEvents.stop("tempestade")
		wv.player.position = Vector3(target.x, 0.25, target.y)
		wv.cam_target = wv.player.position
		wv.zoom = float(sh[2])
		wv.camera.size = wv.zoom
		wv._update_environment()
		screen._refresh()
		for i in 50:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := OS.get_user_data_dir() + "/scen_%s_%s.png" % [scen, str(sh[0])]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
	SaveManager.delete_save()
	get_tree().quit()


func Layout_rect_center(c: Vector2i) -> Vector2:
	return preload("res://world3d/city_layout.gd").block_rect(c).get_center()
