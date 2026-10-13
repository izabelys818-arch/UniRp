extends Node3D
# Bichos de perto: as cinco pelagens de vira-lata e um pombo. Uso: godot --path . res://tests/animal_shots.tscn
const AnimalMesh = preload("res://world3d/animal_mesh.gd")
func _ready() -> void:
	get_window().size = Vector2i(1500, 700)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#9fb3c8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#aab4c2")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -40, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.light_angular_distance = 1.0
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#8a857c")
	floor_mi.material_override = fm
	add_child(floor_mi)
	var rng := RandomNumberGenerator.new()
	for i in 5:
		rng.seed = 7
		var dog: Node3D
		# força cada raça em ordem
		var tries := 0
		while true:
			rng.seed = 1000 + i * 31 + tries
			var probe := RandomNumberGenerator.new()
			probe.seed = rng.seed
			if probe.randi() % AnimalMesh.BREEDS.size() == i:
				break
			tries += 1
		dog = AnimalMesh.dog(rng)
		dog.position = Vector3(-2.4 + i * 1.2, 0, 0)
		dog.rotation.y = -0.6
		add_child(dog)
	rng.seed = 3
	var bird := AnimalMesh.pigeon(rng)
	bird.position = Vector3(3.6, 0.6, 0.3)
	bird.rotation.y = -1.2
	bird.scale = Vector3.ONE * 2.0
	add_child(bird)
	var cam := Camera3D.new()
	cam.fov = 30
	cam.position = Vector3(0.9, 1.9, 5.6)
	add_child(cam)
	cam.look_at(Vector3(0.6, 0.35, 0))
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/animais.png")
	print("SHOT animais")
	get_tree().quit()
