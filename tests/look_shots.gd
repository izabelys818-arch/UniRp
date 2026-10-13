extends Node

# Fotos do mundo para comparar a direção visual: 3 lugares x dia/pôr do sol/noite/chuva,
# com FPS medido em cada cena. LOOK_OUT=<pasta> grava; LOOK_TAG=<prefixo> nomeia (antes/depois).

const UITheme = preload("res://ui/ui_theme.gd")

const TIMES := [["dia", 10, 0, false], ["por_do_sol", 18, 5, false], ["noite", 22, 30, false], ["chuva", 15, 0, true], ["chuva_noite", 21, 30, true]]


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "user://look_save.json"
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
	var out := OS.get_environment("LOOK_OUT") if OS.get_environment("LOOK_OUT") != "" else OS.get_user_data_dir() + "/look"
	var tag := OS.get_environment("LOOK_TAG") if OS.get_environment("LOOK_TAG") != "" else "shot"
	DirAccess.make_dir_recursive_absolute(out)
	# esconde a interface: só o mundo na foto
	for child in screen.get_children():
		if child is CanvasItem and child != wv:
			(child as CanvasItem).visible = false
	var spots := {
		"bairro": wv.layout.door_out(wv.layout.house_ids[20]) + Vector2(0, 4),
		"rua": wv.layout.door_out("lanchonete") + Vector2(0, 3),
		"praca": wv.layout.door_out("praca"),
	}
	var rows: Array = []
	for spot in spots:
		var p: Vector2 = spots[spot]
		wv.player.position = Vector3(p.x, 0.25, p.y)
		wv.player.velocity = Vector3.ZERO
		wv.cam_target = wv.player.position + Vector3(0, 1.0, 0)
		wv.zoom = 13.0
		wv.camera.size = 13.0
		for when in TIMES:
			var only := OS.get_environment("LOOK_ONLY")
			if only != "" and not only.split(",").has("%s_%s" % [spot, when[0]]):
				continue
			TimeManager.total_minutes = 1440 + int(when[1]) * 60 + int(when[2])
			if when[3]:
				WorldEvents.start("tempestade", 6.0)
			else:
				WorldEvents.stop("tempestade")
			wv._update_environment()
			for i in 60:
				await get_tree().process_frame
			var started := Time.get_ticks_usec()
			var frames := 0
			while Time.get_ticks_usec() - started < 1500000:
				await get_tree().process_frame
				frames += 1
			var fps := frames / ((Time.get_ticks_usec() - started) / 1000000.0)
			for child in screen.get_children():
				if child is CanvasItem and child != wv:
					(child as CanvasItem).visible = false
			await RenderingServer.frame_post_draw
			var name := "%s_%s_%s" % [tag, spot, when[0]]
			get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
			rows.append({"cena": name, "fps": snappedf(fps, 0.1)})
			print("LOOK ", name, " fps=", snappedf(fps, 0.1), " grama=", wv.grass.get_child_count())
	var file := FileAccess.open(out + "/" + tag + "_fps.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	SaveManager.delete_save()
	get_tree().quit()
