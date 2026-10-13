extends Node3D
# Todas as espécies de árvore lado a lado (inclui os ipês de cada cor), na luz do dia.
const Kit = preload("res://world3d/mesh_kit.gd")
const Flora = preload("res://world3d/flora.gd")
const Foliage = preload("res://world3d/foliage.gd")
const Surfaces = preload("res://world3d/surfaces.gd")
func _ready() -> void:
	get_window().size = Vector2i(1600, 800)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#9fb3c8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b0b8c4")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	add_child(sun)
	Foliage.reset()
	var k := Kit.new()
	k.cat = "veg"
	k.box_ab(Vector3(-20, -0.05, -8), Vector3(20, 0.0, 8), Color("#55683f"))
	var rng := RandomNumberGenerator.new()
	var species := ["copa", "oiti", "ipe", "ipe", "ipe", "ipe", "mangueira", "palmeira", "conica", "seca"]
	for i in species.size():
		rng.seed = 100 + i
		Flora.tree(k, Vector3(-16 + i * 3.6, 0, 0), 0.95, rng, species[i], i == 0)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(Surfaces.material("veg"))
	add_child(mi)
	RenderingServer.global_shader_parameter_set("player_pos", Vector3(0, 0, 60))
	var fol := Foliage.new()
	add_child(fol)
	for i in 120:
		fol.update_view(Vector3(0, 0, 40))
		await get_tree().process_frame
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 20
	cam.position = Vector3(30, 40, 30)
	add_child(cam)
	cam.look_at(Vector3(0, 2, 0))
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/arvores.png")
	print("SHOT arvores")
	get_tree().quit()
