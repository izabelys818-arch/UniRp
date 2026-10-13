extends Node

# Laboratório de locomoção: roteiros de movimento, folhas de quadros e medida de
# escorregamento do pé de apoio. GAIT_OUT=<pasta> grava as imagens.
const Person = preload("res://world3d/person.gd")
const Looks = preload("res://ui/face/look_builder.gd")

const W := 300
const H := 340
var out_dir := ""
var cam: Camera3D
var report: Array = []


func _ready() -> void:
	out_dir = OS.get_environment("GAIT_OUT")
	if out_dir == "":
		out_dir = OS.get_user_data_dir() + "/gait_lab"
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(W, H)
	var world := Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.66, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.75)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mi.mesh = plane
	var grid := StandardMaterial3D.new()
	grid.albedo_color = Color(0.55, 0.55, 0.55)
	floor_mi.material_override = grid
	world.add_child(floor_mi)
	# marcas no chão para ver escorregamento
	for i in range(-40, 41):
		var mark := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(4.0, 0.002, 0.02)
		mark.mesh = box
		mark.position = Vector3(0, 0.001, i * 0.5)
		world.add_child(mark)
	cam = Camera3D.new()
	cam.fov = 32
	world.add_child(cam)
	cam.current = true
	var subjects := [[30, "homem"], [28, "mulher"]]
	if OS.get_environment("GAIT_ALL") != "":
		subjects += [[9, "homem"], [9, "mulher"], [74, "homem"]]
	for subject in subjects:
		var actor := Person.new()
		actor.use_player_locomotion = true
		world.add_child(actor)
		actor.set_look(Looks.build({"pele": 2, "cabelo": 1, "corpo": 1}, subject[0], subject[1]))
		actor.set_process(false)
		var tag := "%s_%d" % [subject[1], subject[0]]
		await _scenario(actor, tag + "_andar", _walk_plan(1.6, 3.4), "side")
		await _scenario(actor, tag + "_correr", _walk_plan(5.0, 3.0), "side")
		await _scenario(actor, tag + "_girar", _turn_plan(), "front")
		await _scenario(actor, tag + "_curva", _curve_plan(), "iso")
		actor.queue_free()
		await get_tree().process_frame
	var file := FileAccess.open(out_dir + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("GAIT_LAB pronto: ", out_dir)
	get_tree().quit()


# plano: lista de [velocidade desejada, giro desejado] por quadro, com aceleração física.
func _walk_plan(top: float, seconds: float) -> Array:
	var plan: Array = []
	for f in 30:
		plan.append([0.0, 0.0])
	for f in int(seconds * 60):
		plan.append([top, 0.0])
	for f in 90:
		plan.append([0.0, 0.0])
	return plan


func _turn_plan() -> Array:
	var plan: Array = []
	for f in 20:
		plan.append([0.0, 0.0])
	for f in 70:
		plan.append([0.0, PI])
	for f in 50:
		plan.append([0.0, PI])
	return plan


func _curve_plan() -> Array:
	var plan: Array = []
	for f in 20:
		plan.append([0.0, 0.0])
	for f in 300:
		plan.append([1.6, f * 0.012])
	for f in 80:
		plan.append([0.0, 3.6])
	return plan


func _scenario(actor, name: String, plan: Array, view: String) -> void:
	actor.position = Vector3.ZERO
	actor.rotation = Vector3.ZERO
	actor.move_speed = 0.0
	if actor.player_motion != null:
		actor.player_motion.suspend(actor)
	for f in 30:
		actor._process(1.0 / 60.0)
	var speed := 0.0
	var heading := 0.0
	var frames: Array[Image] = []
	var slide_sum := 0.0
	var slide_max := 0.0
	var slide_n := 0
	var steady_sum := 0.0
	var steady_n := 0
	var steady_t := 0.0
	var prev_feet := [Vector3.INF, Vector3.INF]
	var floor_y := INF
	var states := {}
	var total := plan.size()
	var shot_every := maxi(1, total / 24)
	for f in total:
		var want_v: float = plan[f][0]
		var want_h: float = plan[f][1]
		var rate := (12.0 * lerpf(1.0, 0.55, clampf(speed / maxf(want_v, 0.1), 0.0, 1.0))) if want_v > speed else (3.6 + speed * 1.2)
		speed = move_toward(speed, want_v, rate / 60.0)
		steady_t = steady_t + 1.0 / 60.0 if (want_v > 0.0 and is_equal_approx(speed, want_v)) else 0.0
		if speed > 0.3:
			heading = lerp_angle(heading, want_h, 1.0 - exp(-6.0 / 60.0))
		else:
			heading += clampf(angle_difference(heading, want_h), -6.5 / 60.0, 6.5 / 60.0)
		actor.rotation.y = heading
		actor.position += Vector3(sin(heading), 0, cos(heading)) * speed / 60.0
		actor.move_speed = speed
		actor.walking = speed > 0.15
		actor.running = want_v > 3.0
		actor._process(1.0 / 60.0)
		states[actor.player_motion.get("state") if actor.player_motion.get("state") != null else "?"] = true
		# pé de apoio = pé mais baixo; mede o deslocamento horizontal dele no mundo
		var feet := []
		for side in ["l", "r"]:
			var bone: int = actor.skel.find_bone("foot_" + side)
			feet.append(actor.skel.global_transform * actor.skel.get_bone_global_pose(bone).origin)
		var low := 0 if (feet[0] as Vector3).y < (feet[1] as Vector3).y else 1
		floor_y = minf(floor_y, (feet[low] as Vector3).y)
		# só conta o pé realmente apoiado (tornozelo na altura mínima)
		if prev_feet[low] != Vector3.INF and f > 40 and (feet[low] as Vector3).y < floor_y + 0.02 and (prev_feet[low] as Vector3).y < floor_y + 0.02:
			var d := Vector2((feet[low] as Vector3).x - (prev_feet[low] as Vector3).x, (feet[low] as Vector3).z - (prev_feet[low] as Vector3).z).length() * 60.0
			slide_sum += d
			if steady_t > 1.0:
				steady_sum += d
				steady_n += 1
			slide_max = maxf(slide_max, d)
			slide_n += 1
		prev_feet = feet
		_place_camera(actor, view)
		if f % shot_every == 0 and frames.size() < 24:
			await RenderingServer.frame_post_draw
			frames.append(get_viewport().get_texture().get_image())
		else:
			await get_tree().process_frame
	_sheet(frames, name)
	var row := {"scenario": name, "slide_mean_mps": slide_sum / maxf(slide_n, 1), "slide_max_mps": slide_max, "steady_slide_mps": steady_sum / maxf(steady_n, 1), "states": states.keys()}
	report.append(row)
	print("GAIT ", JSON.stringify(row))


func _place_camera(actor, view: String) -> void:
	var p: Vector3 = actor.position
	match view:
		"side":
			cam.position = p + Vector3(4.6, 1.0, 0.0)
		"front":
			cam.position = p + Vector3(1.6, 1.3, 4.2)
		_:
			cam.position = p + Vector3(5.5, 6.0, 5.5)
	cam.look_at(p + Vector3(0, 0.85, 0))


func _sheet(frames: Array[Image], name: String) -> void:
	if frames.is_empty():
		return
	var cols := 8
	var rows := int(ceil(frames.size() / float(cols)))
	var sheet := Image.create(W * cols, H * rows, false, frames[0].get_format())
	for i in frames.size():
		var img: Image = frames[i]
		sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i((i % cols) * W, (i / cols) * H))
	sheet.save_png(out_dir + "/" + name + ".png")
