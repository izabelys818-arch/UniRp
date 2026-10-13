extends Node

const View = preload("res://world3d/world_view.gd")
const OUT := "C:/Users/glznc/Documents/Codex/2026-10-12/interiores"
var view
var rows: Array = []

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	seed(82711)
	Settings.api_key = ""
	Settings.model = ""
	Settings.storage_path = OUT + "/settings_fixture.cfg"
	SaveManager.path = OUT + "/perf_fixture.json"
	Settings.camera_mode = 0
	Settings.graphics = 1
	View.realtime = false
	WorldEvents.random_enabled = false
	get_window().size = Vector2i(1280, 800)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	GameState.new_game({"name": "Medição", "age": 28, "gender": "homem", "cenario": "porto_cinza", "origin": "morador_antigo", "money": 500, "home": "apartamento", "location": "rua", "look": {"pele": 2, "cabelo": 0, "roupa": 1}, "inventory": {}, "alive": true})
	NeedsSystem.reset({})
	NPCManager.reset_state(World.get_origin("morador_antigo"))
	TimeManager.total_minutes = 1440 + 11 * 60
	view = View.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.world_ready.connect(func(): view.rng.seed = 5121)
	add_child(view)
	while not view._built:
		await get_tree().process_frame
	view.trace = OS.get_environment("INTERIOR_TRACE") == "1"
	if RenderingServer.has_method("viewport_set_measure_render_time"):
		RenderingServer.call("viewport_set_measure_render_time", view.viewport.get_viewport_rid(), true)
	var house := "casa_1_5_0"
	Houses.st(house)["lock"] = "open"
	for point in ["mercado", house]:
		var cold_start := Time.get_ticks_usec()
		var destination: Vector2 = view.layout.door_out(point) if point == "mercado" else view.layout.door_in(point)
		view.player.position = Vector3(destination.x, 0.25, destination.y)
		view.player.velocity = Vector3.ZERO
		view.path.clear()
		view._update_location()
		view._cutaway()
		view._update_environment()
		if point == house:
			view.city.house_gen.place_now(view.city.loc_info[house]["structure"]["interior"])
		print("INTERIOR COLD ", point, " setup_ms=", (Time.get_ticks_usec() - cold_start) / 1000.0)
		for mode in [0, 1]:
			view.set_camera_mode(mode, false, false)
			view.camera_rig.yaw = PI
			view.camera_rig._yaw = PI
			await frames(200)
			var times: Array[float] = []
			var gpu_ms := 0.0
			var render_cpu_ms := 0.0
			var end := Time.get_ticks_usec() + 6000000
			var before := Time.get_ticks_usec()
			while Time.get_ticks_usec() < end:
				await get_tree().process_frame
				var now := Time.get_ticks_usec()
				times.append((now - before) / 1000.0)
				if RenderingServer.has_method("viewport_get_measured_render_time_gpu"):
					gpu_ms += float(RenderingServer.call("viewport_get_measured_render_time_gpu", view.viewport.get_viewport_rid()))
					render_cpu_ms += float(RenderingServer.call("viewport_get_measured_render_time_cpu", view.viewport.get_viewport_rid()))
				before = now
			times.sort()
			var sum := 0.0
			for ms in times:
				sum += ms
			var row := {"point": point, "mode": mode, "resolution": str(view.viewport.size), "frames": times.size(), "fps": times.size() * 1000.0 / sum, "p99_ms": times[mini(times.size() - 1, floori(times.size() * 0.99))], "worst_ms": times.back()}
			row["gpu_ms"] = gpu_ms / times.size()
			row["render_cpu_ms"] = render_cpu_ms / times.size()
			rows.append(row)
			print("INTERIOR PERF ", row)
	var tag := "antes" if OS.get_environment("INTERIOR_BEFORE") == "1" else "depois"
	var file := FileAccess.open(OUT + "/fps_" + tag + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(rows, "\t"))
	get_tree().quit()
