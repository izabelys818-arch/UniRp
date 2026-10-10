extends Control

# Personagem 3D: expressões do rosto (deformações por código) e bases de idade, num quadro fixo.
# Uso: CHAR3D_MODO=rosto|idade CHAR3D_TAG=nome godot --path . res://tests/char3d_shots.tscn

const Person = preload("res://world3d/person.gd")
const LookBuilder = preload("res://ui/face/look_builder.gd")

const CELL := Vector2i(300, 380)
var vps: Array = []
var mode_wide := true


func _world(vp: SubViewport) -> Node3D:
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	var root := Node3D.new()
	vp.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#3a3228")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8a8070")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-deg_to_rad(25), deg_to_rad(-35), 0)
	key.light_energy = 1.1
	key.light_color = Color("#ffe2bf")
	key.shadow_enabled = true
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(-deg_to_rad(10), deg_to_rad(150), 0)
	rim.light_energy = 0.6
	rim.light_color = Color("#9fb8ff")
	root.add_child(rim)
	return root


func _cell(look: Dictionary, emo: String, close: bool, side: bool = false) -> void:
	var vp := SubViewport.new()
	vp.size = CELL
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	vps.append(vp)
	var root := _world(vp)
	var fig := Person.new()
	root.add_child(fig)
	fig.set_look(look)
	fig.set_emotion(emo)
	if OS.get_environment("CHAR3D_SEMCORPO") != "" and fig.body_mi != null:
		fig.body_mi.visible = false
	var cam := Camera3D.new()
	root.add_child(cam)
	if close and OS.get_environment("CHAR3D_TRONCO") != "":
		cam.fov = 22
		cam.position = Vector3(0.0, 1.3 * fig.scale.y, 2.0)
		cam.look_at(Vector3(0, 1.25 * fig.scale.y, 0))
	elif close:
		cam.fov = 13
		var h := 1.66 * fig.scale.y
		cam.position = Vector3(0.0, h + 0.01, 1.25)
		cam.look_at(Vector3(0, h - 0.01, 0))
	else:
		cam.fov = 30 if mode_wide else 24
		cam.position = Vector3(4.6, 1.0, 0.3) if side else Vector3(0.0, 1.0, 4.6)
		cam.look_at(Vector3(0, 0.88, 0))
		var ground := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(8, 8)
		ground.mesh = pm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color("#6d675e")
		pm.material = gm
		root.add_child(ground)


func _ready() -> void:
	var mode := OS.get_environment("CHAR3D_MODO")
	var tag := OS.get_environment("CHAR3D_TAG")
	mode_wide = mode not in ["corpos"]
	if mode == "corpos":
		var gen := OS.get_environment("CHAR3D_GENERO")
		if gen == "":
			gen = "homem"
		for t in 7:
			var spec := {"pele": 2, "cabelo": 0 if gen == "homem" else 4, "cor_cabelo": 1, "roupa": 0 if gen == "homem" else 8, "corpo": t}
			_cell(LookBuilder.build(spec, 30, gen), "neutro", false)
	elif mode == "idade":
		for a in [[8, "mulher", {"pele": 1, "cabelo": 4, "cor_cabelo": 3, "roupa": 9}], [15, "homem", {"pele": 3, "cabelo": 13, "cor_cabelo": 0, "roupa": 1}], [32, "homem", {"pele": 2, "cabelo": 0, "cor_cabelo": 1, "barba": 1, "roupa": 0}], [74, "homem", {"pele": 0, "cabelo": 3, "cor_cabelo": 1, "barba": 4, "roupa": 13}], [30, "mulher", {"pele": 4, "cabelo": 4, "cor_cabelo": 0, "roupa": 8}]]:
			_cell(LookBuilder.build(a[2], int(a[0]), str(a[1])), "neutro", false)
		_cell(LookBuilder.build({"pele": 0, "cabelo": 3, "cor_cabelo": 1, "barba": 4, "roupa": 13}, 74, "homem"), "neutro", false, true)
		_cell(LookBuilder.build({"pele": 2, "cabelo": 0, "cor_cabelo": 1, "barba": 1, "roupa": 0}, 32, "homem"), "neutro", false, true)
	else:
		var gender := OS.get_environment("CHAR3D_GENERO")
		if gender == "":
			gender = "homem"
		var look := LookBuilder.build({"pele": 2, "cabelo": 0, "cor_cabelo": 1, "barba": 0, "roupa": 0}, 30, gender)
		if OS.get_environment("CHAR3D_TRONCO") != "":
			for a in [[30, "homem"], [30, "mulher"], [15, "homem"], [15, "mulher"], [9, "homem"], [9, "mulher"]]:
				_cell(LookBuilder.build({"pele": 2, "cabelo": 0, "cor_cabelo": 1, "roupa": 0}, int(a[0]), str(a[1])), "neutro", true)
		else:
			for e in ["neutro", "feliz", "triste", "furioso", "assustado", "exausto"]:
				_cell(look, e, true)
	for i in 60:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var cols := mini(vps.size(), 6) if mode not in ["idade", "corpos"] else vps.size()
	var sheet := Image.create(cols * (CELL.x + 6) + 6, CELL.y + 12, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#141210"))
	for i in vps.size():
		var img: Image = vps[i].get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(6 + i * (CELL.x + 6), 6))
	var path := OS.get_user_data_dir() + "/char3d_%s.png" % tag
	sheet.save_png(path)
	print("SHOT ", path)
	get_tree().quit()
