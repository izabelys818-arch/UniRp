extends Control

# Retratos lado a lado para decidir o caminho do rosto: o desenho 2D atual (FaceRig), o render
# 3D do próprio modelo (opção A) e o retrato pintado (opção B). Mesmas pessoas, mesmo quadro.
# Cada retrato é desenhado num SubViewport próprio e montado numa folha só.
# Uso: RETRATO_MODO=atual|3d|b RETRATO_TAG=nome godot --path . res://tests/portrait_shots.tscn

const FaceRig = preload("res://ui/face/face_rig.gd")
const FacePaint = preload("res://ui/face/face_paint.gd")
const LookBuilder = preload("res://ui/face/look_builder.gd")
const Person = preload("res://world3d/person.gd")

var CELL := Vector2i(400, 500)
const LOOKS := [
	[{"pele": 2, "cabelo": 0, "cor_cabelo": 1, "barba": 1, "roupa": 0, "marcas": []}, 28, "homem", "neutro"],
	[{"pele": 2, "cabelo": 4, "cor_cabelo": 1, "barba": 0, "roupa": 8, "marcas": []}, 28, "mulher", "feliz"],
	[{"pele": 4, "cabelo": 5, "cor_cabelo": 0, "barba": 0, "roupa": 1, "marcas": [6]}, 22, "mulher", "desconfiado"],
	[{"pele": 0, "cabelo": 3, "cor_cabelo": 5, "barba": 4, "roupa": 13, "rosto": 4, "marcas": [0]}, 67, "homem", "triste"],
	[{"pele": 5, "cabelo": 2, "cor_cabelo": 0, "barba": 3, "roupa": 2, "rosto": 1, "marcas": []}, 41, "homem", "irritado"],
	[{"pele": 3, "cabelo": 10, "cor_cabelo": 2, "barba": 0, "roupa": 5, "rosto": 2, "marcas": [7]}, 58, "mulher", "neutro"],
	[{"pele": 1, "cabelo": 12, "cor_cabelo": 3, "barba": 0, "roupa": 9, "marcas": [6]}, 8, "mulher", "feliz"],
	[{"pele": 3, "cabelo": 13, "cor_cabelo": 0, "barba": 0, "roupa": 1, "marcas": []}, 15, "homem", "entediado"],
	[{"pele": 4, "cabelo": 6, "cor_cabelo": 0, "barba": 0, "roupa": 3, "marcas": [14]}, 34, "mulher", "sarcastico"],
]

var vps: Array = []


func _ready() -> void:
	var mode := OS.get_environment("RETRATO_MODO")
	var tag := OS.get_environment("RETRATO_TAG")
	var only := OS.get_environment("RETRATO_SO")
	if OS.get_environment("RETRATO_CELL") != "":
		var wh := OS.get_environment("RETRATO_CELL").split("x")
		CELL = Vector2i(int(wh[0]), int(wh[1]))
	var looks: Array = LOOKS
	var expr := OS.get_environment("RETRATO_EXPR")
	if expr != "":
		# mesma pessoa em várias expressões
		looks = []
		for e in expr.split(","):
			var base: Array = LOOKS[int(OS.get_environment("RETRATO_PESSOA"))].duplicate()
			base[3] = e
			looks.append(base)
	for i in looks.size():
		if only != "" and not str(i) in only.split(","):
			continue
		var l: Array = looks[i]
		var look := LookBuilder.build(l[0], int(l[1]), str(l[2]))
		var vp := SubViewport.new()
		vp.size = CELL
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		vps.append(vp)
		if mode == "3d":
			_add_3d(vp, look)
		else:
			var f = FacePaint.new() if mode == "b" else FaceRig.new()
			f.scene = "casa"
			f.size = Vector2(CELL)
			vp.add_child(f)
			f.set_look(look)
			f.set_emotion(str(l[3]), true)
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var cols := mini(3, vps.size())
	var rows := int(ceil(vps.size() / 3.0))
	var sheet := Image.create(cols * (CELL.x + 8) + 8, rows * (CELL.y + 8) + 8, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#141210"))
	for i in vps.size():
		var img: Image = vps[i].get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(8 + (i % 3) * (CELL.x + 8), 8 + (i / 3) * (CELL.y + 8)))
	var path := OS.get_user_data_dir() + "/retrato_%s.png" % tag
	sheet.save_png(path)
	print("SHOT ", path)
	get_tree().quit()


func _add_3d(vp: SubViewport, look: Dictionary) -> void:
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
	key.rotation = Vector3(-deg_to_rad(25), deg_to_rad(-40), 0)
	key.light_energy = 1.1
	key.light_color = Color("#ffe2bf")
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(-deg_to_rad(10), deg_to_rad(150), 0)
	rim.light_energy = 0.7
	rim.light_color = Color("#9fb8ff")
	root.add_child(rim)
	var fig := Person.new()
	root.add_child(fig)
	fig.set_look(look)
	var cam := Camera3D.new()
	cam.fov = 18
	var h := 1.55 * fig.scale.y
	cam.position = Vector3(0.0, h, 1.9)
	root.add_child(cam)
	cam.look_at(Vector3(0, h - 0.05, 0))
