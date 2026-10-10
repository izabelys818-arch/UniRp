extends Node

# Fluxo completo da interface: novo jogo → menu de pausa → "Salvar e sair" → tela inicial →
# continuar (carregar o save) → o jogo volta igual. Fotografa cada etapa.
# Variáveis de ambiente:
#   MAKE_SAVE=1          só cria um save e sai (usado para gerar um save com a versão antiga)
#   COMPAT_SAVE=caminho  só carrega esse save (feito por outra versão) e confere se abriu
# Uso: godot --path . res://tests/ui_flow.tscn

var main: Control
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("OK     " if ok else "FALHOU ") + what)
	if not ok:
		fails += 1


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OS.get_user_data_dir() + "/fluxo_%s.png" % name
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _new_game() -> void:
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x",
		"look": {"pele": 2, "cabelo": 0, "cor_cabelo": 0, "barba": 1, "roupa": 2, "marcas": []},
		"appearance_extra": "", "backstory": "", "traits": [], "cenario": "porto_cinza",
		"origin": origin["id"], "money": 400, "location": "lanchonete", "home": "apartamento", "inventory": {}, "alive": true,
	})
	TimeManager.total_minutes = 1440 + 10 * 60 + 17
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	var compat := OS.get_environment("COMPAT_SAVE")
	SaveManager.path = compat if compat != "" else "user://flow_save.json"
	if OS.get_environment("MAKE_SAVE") == "1":
		_new_game()
		GameState.add_money(55)
		SaveManager.save_game()
		print("SAVE_FEITO ", SaveManager.path, " existe=", SaveManager.has_save())
		get_tree().quit()
		return
	main = preload("res://main.gd").new()
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main)
	await _wait(1.0)
	if compat != "":
		check(SaveManager.load_game(), "save de outra versão carrega")
		check(GameState.active and str(GameState.player.get("name", "")) == "Rafa", "jogador do save antigo restaurado")
		check(GameState.money() == 455, "dinheiro do save antigo (R$ 455)")
		main.show_screen("game", {})
		await _wait(4.0)
		check(main.current.get_script().resource_path.ends_with("game_screen.gd"), "jogo abre com o save antigo")
		await _shot("save_antigo")
		print("RESULTADO FLUXO: ", "OK" if fails == 0 else "%d falha(s)" % fails)
		get_tree().quit()
		return
	var nodes_menu := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	SaveManager.delete_save()
	_new_game()
	GameState.add_money(123)
	main.show_screen("game", {})
	await _wait(4.0)
	var game = main.current
	check(game.get_script().resource_path.ends_with("game_screen.gd"), "jogo aberto")
	check(not game.dialogue.visible, "sem interação: caixa de conversa escondida")
	await _shot("ocioso")
	var money_before := GameState.money()
	var minutes_before := TimeManager.total_minutes
	game.open_pause()
	await _wait(0.6)
	check(game.pause_layer.visible, "menu de pausa aberto")
	await _shot("pausa")
	game._save_and_exit()
	await _wait(0.3)
	await _shot("salvando")
	await _wait(1.2)
	check(main.current.get_script().resource_path.ends_with("main_menu.gd"), "voltou para a tela inicial")
	check(not is_instance_valid(game) or game.is_queued_for_deletion(), "tela do jogo liberada")
	check(SaveManager.has_save(), "save gravado")
	var pv := SaveManager.preview()
	check(int(pv.get("money", -1)) == money_before, "save tem o dinheiro certo (R$ %d)" % money_before)
	await _wait(5.0)
	await _shot("inicio")
	var nodes_back := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	print("NOS  menu_antes=%d  menu_depois=%d" % [nodes_menu, nodes_back])
	check(nodes_back < nodes_menu + 400, "sem nós órfãos do jogo depois de sair")
	# "Continuar" na tela inicial: carrega e abre o jogo
	GameState.active = false
	GameState.player = {}
	check(SaveManager.load_game(), "continuar: save carrega")
	main.show_screen("game", {})
	await _wait(4.0)
	check(GameState.money() == money_before, "dinheiro igual ao salvo")
	check(TimeManager.total_minutes == minutes_before, "hora igual à salva")
	check(str(GameState.player.get("name", "")) == "Rafa", "jogador igual ao salvo")
	await _shot("carregado")
	SaveManager.delete_save()
	print("RESULTADO FLUXO: ", "OK" if fails == 0 else "%d falha(s)" % fails)
	get_tree().quit()
