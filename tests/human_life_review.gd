extends Control

const Looks = preload("res://ui/face/look_builder.gd")
const Person = preload("res://world3d/person.gd")
const Motion = preload("res://world3d/human_motion.gd")
var fails := 0
var output := "C:/Users/glznc/Documents/Codex/2026-10-10/motion"
var faces: Array = []

func check(condition: bool, label: String) -> void:
	print(("OK " if condition else "FALHOU ") + label)
	if not condition:
		fails += 1


func _ready() -> void:
	get_window().content_scale_size = Vector2i(900, 700)
	DirAccess.make_dir_recursive_absolute(output)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var world := SubViewport.new()
	world.own_world_3d = true
	add_child(world)
	var actor := Person.new()
	world.add_child(actor)
	actor.set_process(false)
	var base := {"pele": 2, "cabelo": 0, "corpo": 1}
	actor.set_look(Looks.build(base, 76, "homem"))
	for frame in 600:
		actor._process(1.0 / 60.0)
	check(actor._pose_cur.length() < 1.0, "idoso neutro mantém postura ereta")
	check(actor.skel.get_bone_pose_rotation(actor._spine).get_angle() < 0.2, "coluna não acumula inclinação após 600 quadros")
	check(Motion.profile(76)["run"] < Motion.profile(30)["run"], "corrida varia com idade")
	check(Motion.profile(9)["stride"] < Motion.profile(30)["stride"], "criança tem passada menor")
	var old_body: PackedVector3Array = actor.body_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var custom := base.duplicate(true)
	custom["ajustes"] = {"waist": 1.0, "chest": 1.0, "limbs": 1.0}
	actor.set_look(Looks.build(custom, 76, "homem"))
	var new_body: PackedVector3Array = actor.body_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(old_body != new_body, "controles físicos mudam a malha")
	custom = base.duplicate(true)
	custom["sobrancelha"] = 3
	custom["sobrancelha_cor"] = "#d8b56a"
	custom["olhos"] = 3
	actor.set_look(Looks.build(custom, 30, "homem"))
	check((actor._eye_mi.material_override as ShaderMaterial).get_shader_parameter("iris_color") == Color(Looks.EYE_COLORS[3]), "azul chega ao material dos olhos")
	check((actor._brow_mi.material_override as ShaderMaterial).get_shader_parameter("brow_color") == Color("#d8b56a"), "cor da sobrancelha chega ao material")
	var shape_a: PackedVector3Array = actor._brow_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	custom["sobrancelha"] = 4
	custom["ajustes"] = {"brow_w": -1.0}
	actor.set_look(Looks.build(custom, 30, "homem"))
	check(shape_a != actor._brow_mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "formato e espessura da sobrancelha mudam geometria")
	custom["olhos"] = 6
	actor.set_look(Looks.build(custom, 30, "homem"))
	check(bool((actor._eye_mi.material_override as ShaderMaterial).get_shader_parameter("heterochromia")), "heterocromia é ativada")
	var identities := {}
	for i in 24:
		var spec := Looks.individual_spec(base, "morador_%d" % i)
		identities[str(spec["ajustes"])] = true
		check(spec == Looks.individual_spec(base, "morador_%d" % i), "identidade estável %d" % i)
	check(identities.size() == 24, "24 moradores recebem rostos individuais")
	var player_spec := base.duplicate(true)
	player_spec["ajustes"] = {"jaw": 0.3}
	check(Looks.individual_spec(player_spec, "abc") == player_spec, "aparência personalizada de save é preservada")
	actor.queue_free()
	world.queue_free()
	await get_tree().process_frame
	# Mesma pessoa, cores diferentes: captura real, seguida de identidades variadas.
	for i in 6:
		var spec := {"pele": 1, "cabelo": 0, "cor_cabelo": 1, "olhos": i, "sobrancelha": i, "sobrancelha_cor": Looks.HAIR_COLORS[i]}
		add_face(spec, "Olhos e sobrancelhas %d" % (i + 1), i)
	await get_tree().create_timer(2.0).timeout
	await shot("cores_e_sobrancelhas")
	for child in faces:
		child.queue_free()
	faces.clear()
	await get_tree().process_frame
	for i in 6:
		add_face(Looks.individual_spec({"pele": 2, "cabelo": 0, "cor_cabelo": 1, "rosto": 0}, "identidade_%d" % i), "Identidade %d" % (i + 1), i)
	await get_tree().create_timer(2.0).timeout
	await shot("identidades")
	print("RESULTADO HUMAN LIFE: ", "OK" if fails == 0 else str(fails) + " falhas")
	get_tree().quit(fails)


func add_face(spec: Dictionary, label: String, i: int) -> void:
	var f = preload("res://ui/face/face_portrait.gd").new()
	f.position = Vector2((i % 3) * 300, (i / 3) * 350)
	f.size = Vector2(300, 350)
	f.scene = "casa"
	add_child(f)
	faces.append(f)
	f.set_look(Looks.build(spec, 32, "homem"))
	var text := Label.new()
	text.text = label
	text.position = f.position + Vector2(10, 320)
	add_child(text)
	faces.append(text)


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output + "/" + name + ".png")
	print("CAPTURE ", name)
