extends Node

# Fotografa as telas de menu com o tema atual (configurações e criação de personagem).
# Uso: godot --path . res://tests/menu_shots.tscn

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OS.get_user_data_dir() + "/menu_%s.png" % name
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _ready() -> void:
	var main: Control = preload("res://main.gd").new()
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main)
	for scr in ["settings", "creation"]:
		main.show_screen(scr, {"back": "menu"})
		for i in 90:
			await get_tree().process_frame
		await _shot(scr)
	get_tree().quit()
