extends Control

# Tela de criação nova: capturas de cada categoria, prévia 3D, variedade do "Aleatorizar tudo"
# (12 personagens diferentes) e o começo de jogo com um adolescente.
# Uso: godot --path . res://tests/creation_shots.tscn

const UITheme = preload("res://ui/ui_theme.gd")
const FacePaint = preload("res://ui/face/face_paint.gd")
const LookBuilder = preload("res://ui/face/look_builder.gd")
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("OK     " if ok else "FALHOU ") + what)
	if not ok:
		fails += 1


func _shot(name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := OS.get_user_data_dir() + "/criacao_%s.png" % name
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _ready() -> void:
	theme = UITheme.build()
	var cc = preload("res://ui/character_creation.gd").new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var navigated: Array = []
	cc.navigate.connect(func(s, a): navigated.append(s))
	await get_tree().process_frame
	await _shot("identidade")
	for name in ["idade", "rosto", "olhos", "pele", "cabelo", "roupa"]:
		var idx := -1
		for i in cc.CATEGORIES.size():
			if cc.CATEGORIES[i][0] == name:
				idx = i
		cc.cat_buttons[idx].button_pressed = true
		cc._show_cat(idx)
		await _shot(name)
	# idade: escolher criança muda a prévia e o retrato
	cc.age = 9
	cc._update_preview()
	cc._view_btns[1].button_pressed = true
	cc._show_view(true)
	for i in 30:
		await get_tree().process_frame
	check(cc._fig != null and is_instance_valid(cc._fig), "prévia 3D montou o personagem")
	await _shot("corpo3d_crianca")
	cc._set_emotion("feliz")
	await _shot("corpo3d_crianca_feliz")
	cc._view_btns[0].button_pressed = true
	cc._show_view(false)
	# variedade: 12 aleatórios, todos diferentes
	var seen := {}
	var looks: Array = []
	for i in 12:
		cc._randomize_all()
		var key := JSON.stringify(cc.spec)
		seen[key] = true
		looks.append([cc.spec.duplicate(true), [9, 15, 22, 30, 41, 55, 67, 80, 12, 17, 26, 35][i], ["homem", "mulher", "homem", "mulher", "pessoa não-binária", "homem", "mulher", "homem", "mulher", "homem", "mulher", "homem"][i]])
	check(seen.size() == 12, "12 aparências aleatórias diferentes (%d únicas)" % seen.size())
	var cell := Vector2i(220, 275)
	var sheet := Image.create(6 * (cell.x + 6) + 6, 2 * (cell.y + 6) + 6, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#141210"))
	var vps: Array = []
	for i in looks.size():
		var vp := SubViewport.new()
		vp.size = cell
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var f = FacePaint.new()
		f.scene = ["casa", "rua", "bar", "parque", "beco", "loja"][i % 6]
		f.size = Vector2(cell)
		vp.add_child(f)
		f.set_look(LookBuilder.build(looks[i][0], int(looks[i][1]), str(looks[i][2])))
		vps.append(vp)
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	for i in vps.size():
		var img: Image = vps[i].get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, cell), Vector2i(6 + (i % 6) * (cell.x + 6), 6 + (i / 6) * (cell.y + 6)))
	sheet.save_png(OS.get_user_data_dir() + "/criacao_variedade.png")
	print("SHOT variedade")
	for vp in vps:
		vp.queue_free()
	# começar como adolescente com a origem que tem carro: sem carro, com nascimento e calendário
	cc.player_name = "Kaio"
	cc.age = 16
	cc.origin_idx = 4
	cc.birth_m = 5
	cc.birth_d = 3
	cc._start()
	check(navigated == ["game"], "confirmar leva ao jogo")
	check(GameState.age() == 16 and GameState.is_minor(), "jogador começa com 16 anos")
	check(str(GameState.player.get("car", "x")) == "", "menor começa sem carro")
	check(AgingSystem.birthday_md("") == Vector2i(5, 3), "aniversário escolhido: %s" % AgingSystem.birthday_str(""))
	check(TimeManager.date_str() == "1 de março de 2026", "calendário novo: %s" % TimeManager.date_str())
	print("RESULTADO CRIACAO: ", "OK" if fails == 0 else "%d falha(s)" % fails)
	get_tree().quit()
