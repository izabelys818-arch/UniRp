extends Node

# Ferramenta de captura: usa os personagens reais e não lê a partida do dono.
const Person = preload("res://world3d/person.gd")
const Looks = preload("res://ui/face/look_builder.gd")
var views: Array = []
var people: Array = []
var output := "C:/Users/glznc/Documents/Codex/2026-10-10/humans"


func figure(spec: Dictionary, age: int, gender: String, face: bool = false, emotion_name: String = "neutro", animation: String = "Idle") -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(480, 680) if not face else Vector2i(480, 540)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	views.append(viewport)
	var root := Node3D.new()
	viewport.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#5c6269")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#e3e8ed")
	env.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)
	for config in [[Vector3(-28, -35, 0), 0.9, Color("#fff2df")], [Vector3(-15, 135, 0), 0.55, Color("#d3e2f5")]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = config[0]
		light.light_energy = config[1]
		light.light_color = config[2]
		root.add_child(light)
	var fig := Person.new()
	root.add_child(fig)
	fig.set_look(Looks.build(spec, age, gender))
	fig.set_emotion(emotion_name)
	fig.rotation.y = -0.12
	fig.set_process(false)
	people.append(fig)
	print("FIGURE ", gender, " ", age, " skeleton: ", fig.skel, " body: ", fig.body_mi)
	if fig.ap != null:
		fig.ap.play(animation)
		for frame in 65:
			fig.ap.advance(0.016)
			fig._apply_posture(0.016)
			if animation == "Idle":
				fig._apply_hands(0.016)
			fig._apply_face(0.016)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	if face:
		cam.size = 0.43 * fig.scale.y
		cam.position = Vector3(0.015, 1.665 * fig.scale.y, 3)
		cam.look_at(Vector3(0, 1.65 * fig.scale.y, 0))
	else:
		cam.size = 2.03 * fig.scale.y
		cam.position = Vector3(0.2, 1.03 * fig.scale.y, 5)
		cam.look_at(Vector3(0, 0.9 * fig.scale.y, 0))


func sheet(name: String) -> void:
	for frame in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var size: Vector2i = views[0].size
	var image := Image.create(size.x * views.size(), size.y, false, Image.FORMAT_RGBA8)
	for i in views.size():
		var shot: Image = views[i].get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		image.blit_rect(shot, Rect2i(Vector2i.ZERO, size), Vector2i(i * size.x, 0))
	DirAccess.make_dir_recursive_absolute(output)
	image.save_png(output + "/" + name + ".png")
	print("CAPTURE ", output + "/" + name + ".png")
	for vp in views:
		vp.queue_free()
	views.clear()
	people.clear()
	await get_tree().process_frame


func _ready() -> void:
	var male := {"pele": 2, "cabelo": 0, "barba": 7, "roupa": 1, "corpo": 1, "rosto": 1, "olhos": 2}
	var female := {"pele": 1, "cabelo": 4, "roupa": 0, "corpo": 1, "rosto": 0, "olhos": 0}
	figure(male, 34, "homem")
	figure(female, 28, "mulher")
	await sheet("corpos")
	figure(male, 34, "homem", true)
	figure(female, 28, "mulher", true)
	await sheet("rostos")
	for e in ["neutro", "triste", "furioso", "exausto"]:
		figure(male, 34, "homem", true, e)
	await sheet("expressoes")
	for a in ["Walk", "Sitting_Idle", "Idle_Talking"]:
		figure(male, 34, "homem", false, "neutro", a)
	await sheet("movimentos")
	for body in 7:
		figure({"pele": 2, "cabelo": 0, "barba": 1, "roupa": 0, "corpo": body, "rosto": 0}, 35, "homem")
	await sheet("tipos_fisicos")
	for entry in [[{"pele": 4, "cabelo": 5, "roupa": 0, "rosto": 2}, 32, "mulher"],
		[{"pele": 1, "cabelo": 13, "barba": 1, "roupa": 4, "rosto": 0}, 46, "homem"],
		[{"pele": 0, "cabelo": 1, "barba": 3, "roupa": 0, "rosto": 4}, 72, "homem"],
		[{"pele": 2, "cabelo": 3, "roupa": 8, "rosto": 0}, 65, "mulher"]]:
		figure(entry[0], entry[1], entry[2], true)
	await sheet("idades_e_rostos")
	figure({"pele": 2, "cabelo": 0, "roupa": 0, "corpo": 1}, 10, "homem")
	figure({"pele": 1, "cabelo": 4, "roupa": 0, "corpo": 1}, 12, "mulher")
	figure({"pele": 3, "cabelo": 13, "roupa": 0, "corpo": 0}, 16, "homem")
	await sheet("jovens")
	Person.cleanup()
	Person.AnimBank.cleanup()
	get_tree().quit()
