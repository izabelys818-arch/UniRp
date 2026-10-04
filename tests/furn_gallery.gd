extends Node
const Furn = preload("res://world3d/furn_lib.gd")

func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1500, 700)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#8fb0c8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b9c6d8")
	env.ambient_light_energy = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-deg_to_rad(55), deg_to_rad(-30), 0)
	vp.add_child(sun)
	var root := Node3D.new()
	vp.add_child(root)
	var names := ["bedDouble", "loungeSofa", "cabinetTelevision", "kitchenFridge", "kitchenStove", "kitchenSink", "kitchenCabinet", "bathtub", "toilet", "bathroomSink", "bookcaseClosed", "tableCoffee", "table", "chair", "lampRoundFloor", "plantSmall1", "rugRectangle", "desk", "washer", "kitchenCabinetUpper"]
	var x := 0.0
	var z := 0.0
	var i := 0
	for nm in names:
		var h := Furn.place(root, "res://assets/furniture_k/Models/%s.fbx" % nm, Vector3((i % 10) * 2.6 - 12, 0, (i / 10) * 3.2), 0.0)
		i += 1
	var qn := ["Bed", "Sofa", "Table", "Closet", "Plant", "Lamp", "Chair", "BookCase"]
	i = 0
	for nm in qn:
		Furn.place(root, "res://assets/furniture_q/FBX/%s.fbx" % nm, Vector3(i * 2.0 - 8, 0, 7), 0.0, 1.8)
		i += 1
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 16.0
	cam.near = 1.0
	cam.far = 120.0
	vp.add_child(cam)
	cam.position = Vector3(0, 2, 3) + Vector3(0, 1.15, 1.0).normalized() * 40.0
	cam.look_at(Vector3(0, 0.5, 3), Vector3.UP)
	cam.current = true
	for k in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(OS.get_user_data_dir() + "/furn.png")
	get_tree().quit()
