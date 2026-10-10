extends Node

# Navegação repetida entre telas: menu → continuar (save real) → jogo → sair para o início → criação → menu...
# Confere se memória, nós e VRAM voltam ao normal a cada volta (vazamento) e quanto tempo cada troca leva.
# Uso: STRESS_SAVE=<caminho do save1.json> godot --path . res://tests/stress_flow.tscn

var main_node: Control
var worst := 0.0


func _process(delta: float) -> void:
	worst = maxf(worst, delta * 1000.0)


func _stat(tag: String) -> void:
	print("FLUXO %-30s pior quadro=%5.0f ms | mem=%4.0fMB nos=%5d objetos=%6d recursos=%4d vram=%4.0fMB" % [tag, worst, float(OS.get_static_memory_usage()) / 1048576.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0])
	worst = 0.0


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().process_frame


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	SaveManager.path = "user://fluxo_save.json"
	DirAccess.copy_absolute(OS.get_environment("STRESS_SAVE"), ProjectSettings.globalize_path("user://fluxo_save.json"))
	main_node = preload("res://main.tscn").instantiate()
	add_child(main_node)
	await _wait(3.0)
	_stat("menu inicial")
	for volta in 4:
		# continuar
		var t0 := Time.get_ticks_msec()
		SaveManager.load_game()
		main_node.show_screen("game", {})
		await _wait(0.2)
		var load_ms := Time.get_ticks_msec() - t0
		await _wait(6.0)
		for i in 12:
			TimeManager.advance(60)
			NeedsSystem.reset({})
			await get_tree().process_frame
		await _wait(2.0)
		_stat("volta %d: jogo (carregou em %d ms)" % [volta + 1, load_ms])
		# sair para o início salvando
		SaveManager.save_game()
		GameState.active = false
		main_node.show_screen("menu", {})
		await _wait(3.0)
		_stat("volta %d: menu" % [volta + 1])
		# criação de personagem e volta
		main_node.show_screen("creation", {})
		await _wait(2.5)
		_stat("volta %d: criação" % [volta + 1])
		main_node.show_screen("menu", {})
		await _wait(2.0)
		_stat("volta %d: menu de novo" % [volta + 1])
	SaveManager.delete_save()
	print("FLUXO FIM")
	get_tree().quit()
