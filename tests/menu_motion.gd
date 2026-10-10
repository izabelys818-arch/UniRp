extends Node

# Tela inicial em movimento: três fotos com alguns segundos de intervalo. Uso: godot --path . res://tests/menu_motion.tscn

func _ready() -> void:
	var main: Control = preload("res://main.gd").new()
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main)
	for i in 3:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < (7000 if i == 0 else 4000):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := OS.get_user_data_dir() + "/menu_mov_%d.png" % i
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
	get_tree().quit()
