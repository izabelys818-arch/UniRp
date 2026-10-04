extends Node

const Humanoid = preload("res://world3d/humanoid.gd")
const LookBuilder = preload("res://ui/face/look_builder.gd")


func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1366, 600)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#8fb0c8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b9c6d8")
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-deg_to_rad(55), deg_to_rad(-30), 0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	vp.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 30)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#77746d")
	pm.material = gm
	ground.position.y = 0.17
	vp.add_child(ground)
	var styles := ["camiseta", "couro", "terno", "vestido", "moletom", "jaleco", "farda", "jeans", "avental", "social"]
	var n := 0
	for st in styles:
		var female: bool = st in ["vestido", "avental"]
		var spec: Dictionary = Population.random_look(female, [st])
		var fig := Humanoid.new()
		fig.set_look(LookBuilder.build(spec, 34, "mulher" if female else "homem"))
		vp.add_child(fig)
		fig.position = Vector3(-4.5 + n * 1.0, 0.17, 0)
		fig.rotation.y = 0.5 + 0.3 * sin(n)
		fig.walking = n % 2 == 1
		fig.move_speed = 3.6 if fig.walking else 0.0
		n += 1
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(OS.get_environment("GALLERY_SIZE")) if OS.get_environment("GALLERY_SIZE") != "" else 6.0
	cam.near = 5.0
	cam.far = 80.0
	vp.add_child(cam)
	cam.position = Vector3(-0.5, 1.0, 0) + Vector3(1, 1.15, 1).normalized() * 30.0
	cam.look_at(Vector3(-0.5, 1.0, 0), Vector3.UP)
	cam.current = true
	for i in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(OS.get_user_data_dir() + "/gallery.png")
	print("SHOT gallery")
	get_tree().quit()
