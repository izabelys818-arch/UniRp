extends Control

# Capturas e amostra de renderização, sem ler ou escrever a partida do jogador.
const Looks = preload("res://ui/face/look_builder.gd")
const OLD = preload("res://ui/face/face_paint.gd")
var portrait_script: Script
var output := "C:/Users/glznc/Documents/Codex/2026-10-10/portraits"
var portraits: Array = []
var cells: Array = []
var mode := ""


func _ready() -> void:
	get_viewport().gui_disable_input = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	mode = OS.get_environment("PORTRAIT_MODE")
	portrait_script = OLD if mode == "old" else load("res://ui/face/face_portrait.gd")
	DirAccess.make_dir_recursive_absolute(output)
	if OS.get_environment("PORTRAIT_SECTION") == "details":
		await details_gallery()
		get_tree().quit()
		return
	if OS.get_environment("PORTRAIT_SECTION") == "ui":
		await interface_shots()
		await dialogue_shot()
		get_tree().quit()
		return
	await gallery()
	if mode != "old" and OS.get_environment("PORTRAIT_GALLERY_ONLY") != "1":
		await expressions("homem")
		await expressions("mulher")
		await hair_gallery()
		await details_gallery()
		await interface_shots()
		await dialogue_shot()
	get_tree().quit()


func add_portrait(spec: Dictionary, age: int, gender: String, emotion_name: String, index: int, cols: int = 3, cell := Vector2i(360, 440)) -> void:
	var frame := SubViewport.new()
	frame.size = cell
	frame.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(frame)
	cells.append(frame)
	var f = portrait_script.new()
	f.size = Vector2(cell)
	f.scene = "casa"
	frame.add_child(f)
	f.set_look(Looks.build(spec, age, gender))
	f.set_emotion(emotion_name, true)
	portraits.append(f)
	var texture := TextureRect.new()
	texture.texture = frame.get_texture()
	texture.position = Vector2((index % cols) * cell.x, (index / cols) * cell.y)
	texture.size = Vector2(cell)
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(texture)
	var label := Label.new()
	label.text = emotion_name.capitalize()
	label.position = Vector2(12, cell.y - 28)
	label.add_theme_font_size_override("font_size", 17)
	frame.add_child(label)


func settle() -> void:
	for frame in 100:
		await get_tree().process_frame
	await get_tree().create_timer(1.3).timeout


func capture(name: String, cols: int, cell := Vector2i(360, 440)) -> void:
	await RenderingServer.frame_post_draw
	var rows := ceili(float(cells.size()) / cols)
	var sheet := Image.create(cols * cell.x, rows * cell.y, false, Image.FORMAT_RGBA8)
	for i in cells.size():
		var shot: Image = cells[i].get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, cell), Vector2i((i % cols) * cell.x, (i / cols) * cell.y))
	sheet.save_png(output + "/" + name + ".png")
	if name == "retratos":
		var pair := Image.create(cell.x * 2, cell.y, false, Image.FORMAT_RGBA8)
		pair.blit_rect(sheet, Rect2i(0, 0, cell.x * 2, cell.y), Vector2i.ZERO)
		pair.save_png(output + "/rostos.png")
	print("PORTRAIT CAPTURE ", name)


func clear_gallery() -> void:
	for child in get_children():
		child.queue_free()
	cells.clear()
	portraits.clear()
	await get_tree().process_frame


func gallery() -> void:
	var entries := [
		[{"pele": 2, "cabelo": 0, "cor_cabelo": 1, "barba": 0, "roupa": 1, "rosto": 1}, 34, "homem", "neutro"],
		[{"pele": 1, "cabelo": 4, "roupa": 0}, 28, "mulher", "triste"],
		[{"pele": 4, "cabelo": 6, "roupa": 0}, 32, "mulher", "desconfiado"],
		[{"pele": 1, "cabelo": 1, "barba": 3, "rosto": 4}, 72, "homem", "exausto"],
		[{"pele": 2, "cabelo": 3, "roupa": 8}, 65, "mulher", "carinhoso"],
		[{"pele": 3, "cabelo": 12, "roupa": 0}, 10, "mulher", "feliz"],
	]
	for i in entries.size():
		var e: Array = entries[i]
		add_portrait(e[0], e[1], e[2], e[3], i)
	await settle()
	var ms := 0.0
	var frames := 0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 4000:
		await get_tree().process_frame
		ms += get_process_delta_time() * 1000
		frames += 1
	print("PORTRAIT SAMPLE ", mode, " six visible portraits FPS ", snappedf(frames * 1000.0 / ms, 0.1), " time_s ", ms / 1000.0)
	await capture("antes" if mode == "old" else "retratos", 3)
	await clear_gallery()


func expressions(gender: String) -> void:
	var keys: Array = OLD.EXPRESSIONS.keys()
	for start in [0, 9]:
		for i in 9:
			add_portrait({"pele": 2, "cabelo": 4 if gender == "mulher" else 0, "roupa": 0}, 30, gender, keys[start + i], i, 3, Vector2i(300, 350))
		await settle()
		await capture("expressoes_" + gender + "_" + str(start), 3, Vector2i(300, 350))
		await clear_gallery()


func hair_gallery() -> void:
	for start in [0, 7]:
		for i in 7:
			add_portrait({"pele": 2, "cabelo": start + i, "cor_cabelo": 2, "roupa": 0}, 28, "mulher", "neutro", i, 4, Vector2i(260, 320))
		await settle()
		await capture("cabelos_" + str(start), 4, Vector2i(260, 320))
		await clear_gallery()


func interface_shots() -> void:
	var creation = preload("res://ui/character_creation.gd").new()
	creation.theme = preload("res://ui/ui_theme.gd").build()
	creation.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(creation)
	creation._show_cat(8)
	await get_tree().create_timer(4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output + "/criacao.png")
	print("PORTRAIT CAPTURE creation")
	print("CREATION VIEWPORTS after thumbnails ", creation.find_children("*", "SubViewport", true, false).size())
	creation._test_talk()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output + "/fala.png")
	creation._show_view(true)
	await get_tree().create_timer(1).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output + "/criacao_corpo.png")
	creation._show_view(false)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output + "/criacao_volta_retrato.png")
	creation.queue_free()
	await get_tree().process_frame


func details_gallery() -> void:
	for i in 6:
		var options := [[7,6,15],[8,0],[3,4,5],[14,12],[11],[13,17,9]]
		add_portrait({"pele": 2, "cabelo": 4, "roupa": 0, "marcas": options[i]}, 30, "mulher", "neutro", i)
	await settle()
	await capture("detalhes", 3)
	await clear_gallery()


func dialogue_shot() -> void:
	var WorldView = preload("res://world3d/world_view.gd")
	WorldView.realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "user://portrait_preview_unused.json"
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({"name": "Rafa", "age": 34, "gender": "homem", "appearance": "",
		"look": {"pele": 2, "cabelo": 0, "barba": 0, "roupa": 1, "corpo": 1},
		"appearance_extra": "", "backstory": "", "traits": [], "cenario": "porto_cinza",
		"origin": origin["id"], "money": 400, "location": "rua", "home": "apartamento", "inventory": {}, "alive": true})
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	var screen = preload("res://ui/game_screen.gd").new()
	screen.theme = preload("res://ui/ui_theme.gd").build()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	while not screen.world_view._built:
		await get_tree().process_frame
	TimeManager.total_minutes = 11 * 60
	await get_tree().create_timer(3).timeout
	var face = portrait_script.new()
	face.scene = "rua"
	face.set_look(Looks.build({"pele": 2, "cabelo": 4, "roupa": 0}, 30, "mulher"))
	face.set_emotion("triste", true)
	screen.dialogue.begin_conversation("Prévia do retrato", "", face)
	screen.dialogue.show_entry({"kind": "info", "text": "Um rosto, no retrato e na cidade. A mesma pessoa."})
	await get_tree().create_timer(2.5).timeout
	screen.dialogue._finish_typing()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output + "/conversa.png")
	print("PORTRAIT CAPTURE dialogue")
	screen.queue_free()
	await get_tree().process_frame
