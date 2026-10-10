extends Node

const View = preload("res://world3d/world_view.gd")
var worst := 0.0
var watching := false
var navigations := 0

func _process(delta: float) -> void:
	if watching:
		worst = maxf(worst, delta * 1000.0)


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	View.realtime = false
	WorldEvents.random_enabled = false
	Settings.api_key = ""
	SaveManager.path = "user://human_start_unused.json"
	var main := preload("res://main.tscn").instantiate()
	add_child(main)
	main.show_screen("creation")
	await get_tree().create_timer(0.8).timeout
	var creation = main.current
	creation.player_name = "Rafa"
	creation.age = 30
	creation.navigate.connect(func(_name, _args): navigations += 1)
	var start := Time.get_ticks_msec()
	watching = true
	creation._start()
	creation._start()
	var captured := false
	while Time.get_ticks_msec() - start < 30000:
		await get_tree().process_frame
		if main.current != null and main.current.get_script() == preload("res://ui/game_screen.gd"):
			var view = main.current.world_view
			if not view._built and not captured and view.layout != null:
				captured = true
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("C:/Users/glznc/Documents/Codex/2026-10-10/motion/carregamento.png")
			if view._built:
				watching = false
				print("START REVIEW ready_ms=", Time.get_ticks_msec() - start, " worst_frame_ms=", snappedf(worst, 0.1), " navigations=", navigations)
				print("OK início: cidade pronta, clique repetido bloqueado" if navigations == 1 else "FALHOU início: navegação repetida")
				for frame in 120:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("C:/Users/glznc/Documents/Codex/2026-10-10/motion/inicio.png")
				main.show_screen("menu")
				await get_tree().create_timer(0.5).timeout
				print("OK início: retorno ao menu")
				get_tree().quit(0 if navigations == 1 else 1)
				return
	print("FALHOU início: tempo limite de 30 segundos")
	get_tree().quit(1)
