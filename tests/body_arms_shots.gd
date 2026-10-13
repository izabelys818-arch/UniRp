extends Node3D
# Braços x tronco em três tipos físicos (médio, forte, obeso), de frente e de três quartos.
const Person = preload("res://world3d/person.gd")
const Looks = preload("res://ui/face/look_builder.gd")
func _ready() -> void:
	get_window().size = Vector2i(1500, 700)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#30343a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#9aa0a8")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var figs: Array = []
	for i in 3:
		var f := Person.new()
		add_child(f)
		f.set_look(Looks.build({"pele": 2, "cabelo": 0, "corpo": [1, 3, 5][i], "roupa": 1}, 30, "homem"))
		f.position = Vector3(-1.3 + i * 1.3, 0, 0)
		f.rotation.y = -0.7
		figs.append(f)
	var cam := Camera3D.new()
	cam.fov = 28
	cam.position = Vector3(0, 1.1, 5.6)
	add_child(cam)
	cam.look_at(Vector3(0, 1.0, 0))
	for i in 150:
		await get_tree().process_frame
		if i % 50 == 49:
			var f: Node3D = figs[0]
			var sk: Skeleton3D = f.skel
			for side in ["l", "r"]:
				var h := sk.get_bone_global_pose(sk.find_bone("thigh_" + side)).origin
				var k := sk.get_bone_global_pose(sk.find_bone("calf_" + side)).origin
				var a := sk.get_bone_global_pose(sk.find_bone("foot_" + side)).origin
				print("JOELHO %s ang=%.1f pelvis_y=%.3f model_y=%.3f anim=%s mocap=%s ativo=%s" % [side, rad_to_deg((h - k).angle_to(a - k)), sk.get_bone_global_pose(sk.find_bone("pelvis")).origin.y, f.model.position.y, f._cur_anim, f.player_motion.get("mocap"), f.player_motion.active])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/bracos.png")
	print("SHOT bracos")
	get_tree().quit()
