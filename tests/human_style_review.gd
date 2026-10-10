extends Control

# Revisão visual real, em luz fria e neutra: anatomias, expressões e silhuetas.
# Não chama a IA, nem lê/grava o save do jogador.
const Person = preload("res://world3d/person.gd")
const Looks = preload("res://ui/face/look_builder.gd")
const HumanStyle = preload("res://world3d/human_style.gd")
const CELL := Vector2i(340, 410)
var out_dir: String = OS.get_user_data_dir() + "/human_style_review"
var failures := 0
var views: Array = []
var figures: Array = []
var captions: Array = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func cell(spec: Dictionary, age: int, gender: String, emotion: String, title: String, full: bool = false) -> void:
	var vp := SubViewport.new()
	vp.size = CELL
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	views.append(vp)
	captions.append(title)
	var root := Node3D.new()
	vp.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#24292c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#adb7bf")
	env.ambient_light_energy = 0.48
	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-24, -32, 0)
	light.light_color = Color("#e1ded4")
	light.light_energy = 0.82
	root.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 135, 0)
	fill.light_color = Color("#8a9eae")
	fill.light_energy = 0.36
	root.add_child(fill)
	var fig := Person.new()
	root.add_child(fig)
	fig.set_look(Looks.build(spec, age, gender))
	fig.set_emotion(emotion, false)
	fig.rotation.y = -0.10
	fig.set_process(false)
	for i in 80:
		fig.ap.advance(0.016)
		fig._apply_posture(0.016)
		fig._apply_hands(0.016)
		fig._apply_face(0.016)
	figures.append(fig)
	check(fig.skel != null and fig.ap.has_animation("Walk") and fig.ap.has_animation("Sitting_Idle"), title + ": rig e animações")
	check(fig._face_mi != null and fig._face_mi.mesh.get_blend_shape_count() == Person.FACE_SHAPES.size(), title + ": rosto animável")
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	if full:
		cam.size = 2.13 * fig.scale.y
		cam.position = Vector3(0.35, 1.03 * fig.scale.y, 4.8)
		cam.look_at(Vector3(0, 0.9 * fig.scale.y, 0))
	else:
		cam.size = 0.39 * fig.scale.y
		cam.position = Vector3(0, 1.67 * fig.scale.y, 3)
		cam.look_at(Vector3(0, 1.665 * fig.scale.y, 0))


func _sheet(name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var sheet := Image.create(CELL.x * views.size(), CELL.y, false, Image.FORMAT_RGBA8)
	for i in views.size():
		var shot: Image = views[i].get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(shot, Rect2i(Vector2i.ZERO, CELL), Vector2i(i * CELL.x, 0))
	DirAccess.make_dir_recursive_absolute(out_dir)
	sheet.save_png(out_dir + "/" + name + ".png")
	print("SHOT ", out_dir + "/" + name + ".png; ordem: ", captions)
	for vp in views:
		vp.queue_free()
	views.clear()
	figures.clear()
	captions.clear()
	await get_tree().process_frame


func _ready() -> void:
	if OS.get_environment("HUMAN_REVIEW_OUT") != "":
		out_dir = OS.get_environment("HUMAN_REVIEW_OUT")
	var specs := [
		{"pele": 2, "cabelo": 2, "barba": 1, "roupa": 1, "rosto": 3, "corpo": 0, "olhos": 5},
		{"pele": 1, "cabelo": 0, "barba": 7, "roupa": 5, "rosto": 1, "corpo": 1, "olhos": 2},
		{"pele": 4, "cabelo": 10, "roupa": 4, "rosto": 3, "corpo": 1, "olhos": 0},
		{"pele": 0, "cabelo": 1, "barba": 3, "roupa": 1, "rosto": 4, "corpo": 4, "olhos": 3},
	]
	var ages := [38, 46, 35, 72]
	var genders := ["homem", "homem", "mulher", "homem"]
	for i in specs.size():
		cell(specs[i], ages[i], genders[i], "neutro", "%s, %d anos" % [genders[i], ages[i]])
	# Os ajustes do criador realmente mudam o rosto 3D e não o rig.
	var f: Dictionary = figures[0]._anatomy
	var neutral := Looks.build(specs[0], ages[0], genders[0])
	var changed := neutral.duplicate()
	changed["nose_len"] = 1.4
	changed["nose_w"] = 1.45
	var point: Vector3 = f["nose"]
	check(HumanStyle.sculpt(point, f, neutral).distance_to(HumanStyle.sculpt(point, f, changed)) > 0.006, "comprimento do nariz altera a geometria")
	check(figures[0]._face_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() < figures[0].body_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), "anatomia individual limitada à cabeça compacta")
	await _sheet("personagens_rostos")
	for i in specs.size():
		cell(specs[i], ages[i], genders[i], "neutro", "%s, %d anos" % [genders[i], ages[i]], true)
	await _sheet("personagens_corpos")
	for e in ["neutro", "triste", "furioso", "desconfiado", "exausto", "sarcastico"]:
		cell(specs[0], 38, "homem", e, e)
		var fig: Node3D = figures.back()
		var actual := 0.0
		for i in Person.FACE_SHAPES.size():
			actual += absf(fig._face_mi.get_blend_shape_value(i))
		check(actual > 0.05, "emoção %s produz deformação facial" % e)
	await _sheet("personagens_expressoes")
	# Índices e pesos de pele permanecem válidos, inclusive os novos vértices.
	for t in 7:
		cell({"corpo": t, "cabelo": 2, "roupa": 1}, 35, "homem", "neutro", Person.BODY_TYPES[t]["nome"], true)
		var head: Array = figures.back()._face_mi.mesh.surface_get_arrays(0)
		var vv: PackedVector3Array = head[Mesh.ARRAY_VERTEX]
		var ww: PackedFloat32Array = head[Mesh.ARRAY_WEIGHTS]
		var per: int = ww.size() / vv.size()
		var valid := true
		for v in vv.size():
			var total := 0.0
			for j in per:
				total += ww[v * per + j]
			if not vv[v].is_finite() or absf(total - 1.0) > 0.02:
				valid = false
		check(valid, "pesos válidos no tipo " + str(t))
	await _sheet("personagens_tipos_fisicos")
	print("RESULTADO ESTILO HUMANO: ", "OK" if failures == 0 else "%d falha(s)" % failures)
	get_tree().quit(failures)
