extends Node3D

# Close fixo do personagem para comparar versões: mesma pose, ângulo e luz.
# Uso: CHAR_TAG=depois godot --path . res://tests/char_closeup.tscn

const Humanoid = preload("res://world3d/person.gd")
const LookBuilder = preload("res://ui/face/look_builder.gd")


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#6f7f8f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#aeb6c2")
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-deg_to_rad(50), deg_to_rad(-35), 0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#77746d")
	pm.material = gm
	ground.position.y = 0.0
	add_child(ground)
	var looks := [
		[{"pele": 2, "cabelo": 0, "cor_cabelo": 0, "barba": 1, "roupa": 2, "marcas": []}, 30, "homem"],
		[{"pele": 4, "cabelo": 3, "cor_cabelo": 2, "barba": 0, "roupa": 5, "marcas": []}, 26, "mulher"],
		[{"pele": 1, "cabelo": 1, "cor_cabelo": 4, "barba": 2, "roupa": 7, "marcas": []}, 66, "homem"],
	]
	var figs: Array = []
	for i in looks.size():
		var fig := Humanoid.new()
		add_child(fig)
		fig.set_look(LookBuilder.build(looks[i][0], int(looks[i][1]), str(looks[i][2])))
		fig.position = Vector3(-1.3 + i * 1.3, 0, 0)
		figs.append(fig)
	var cam := Camera3D.new()
	add_child(cam)
	var tag := OS.get_environment("CHAR_TAG")
	for view in ["frente", "iso"]:
		if view == "frente":
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 30
			cam.position = Vector3(0, 1.1, 6.2)
			cam.look_at(Vector3(0, 0.95, 0))
		else:
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 3.6
			cam.position = Vector3(30, 30 * 1.15, 30)
			cam.look_at(Vector3(0, 0.9, 0))
		for i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := OS.get_user_data_dir() + "/char_%s_%s.png" % [view, tag]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
	get_tree().quit()
