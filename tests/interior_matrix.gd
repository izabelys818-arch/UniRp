extends Node

const View = preload("res://world3d/world_view.gd")
const Grass = preload("res://world3d/grass_field.gd")
const OUT := "C:/Users/glznc/Documents/Codex/2026-10-12/interiores"
var view
var failures: Array = []
var rows: Array = []

func _ready() -> void:
	seed(82711)
	Settings.api_key = ""
	Settings.model = ""
	Settings.storage_path = OUT + "/settings_fixture.cfg"
	SaveManager.path = OUT + "/matrix_save.json"
	View.realtime = false
	WorldEvents.random_enabled = false
	Settings.graphics = 1
	get_window().size = Vector2i(1280, 800)
	Engine.max_fps = 60
	Engine.time_scale = 3.0
	var scenario := OS.get_environment("INTERIOR_SCENARIO")
	if scenario == "":
		scenario = "porto_cinza"
	GameState.new_game({"name": "Revisão", "age": 28, "gender": "homem", "cenario": scenario, "origin": "morador_antigo", "money": 500, "home": "apartamento", "location": "rua", "look": {"pele": 2, "cabelo": 0, "roupa": 1}, "inventory": {}, "alive": true})
	NeedsSystem.reset({})
	NPCManager.reset_state(World.get_origin("morador_antigo"))
	TimeManager.total_minutes = 1440 + 11 * 60
	view = View.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	while not view._built:
		await get_tree().process_frame
	# Mantém apenas uma construção ativa durante cada verificação.
	var structures: Array = view.city.structures.duplicate()
	for building in structures:
		if not building.has("lot") and not bool(building.get("modern_interior", false)):
			continue
		var id := str(building["loc"])
		if OS.get_environment("INTERIOR_FOCUS") != "" and not id in OS.get_environment("INTERIOR_FOCUS").split(","):
			continue
		var door: Vector2 = view.layout.door_in(id)
		view.player.position = Vector3(door.x, 0.25, door.y)
		view.player.velocity = Vector3.ZERO
		view.path.clear()
		if Houses.is_house(id):
			Houses.st(id)["lock"] = "open"
		view.city.ensure_interior(building)
		view._update_location()
		view._cutaway()
		await get_tree().physics_frame
		await get_tree().physics_frame
		var floor_node: Node3D = building["floor_nodes"][0]
		var placements: Array = floor_node.get_meta("placements")
		if OS.get_environment("INTERIOR_FOCUS") != "":
			print("DEBUG PLACEMENTS ", placements, " rooms=", floor_node.get_meta("rooms"), " door=", door)
		var issues: Array = []
		if view._inside_any(door) != id:
			issues.append("entrada reconhecida como outro imóvel: " + view._inside_any(door))
		var computers := 0
		for item in placements:
			if item["model"] == "laptop":
				computers += 1
				var supported := false
				for support in placements:
					if support["model"] == "desk" and support["room"] == item["room"] and (support["rect"] as Rect2).encloses(item["rect"]):
						supported = true
				if not supported:
					issues.append("computador sem apoio na mesa")
		if computers > 0:
			var registered := 0
			for object in view.city.objects.values():
				if object["loc"] == id and object["kind"] == "computer" and int(object["plan"].get("floor", 0)) == 0:
					registered += 1
			if registered != computers or not floor_node.get_meta("use_points").has("computador"):
				issues.append("computador perdeu identificador/ponto de uso")
		var arrival_shape := SphereShape3D.new()
		arrival_shape.radius = 0.29
		var arrival_query := PhysicsShapeQueryParameters3D.new()
		arrival_query.shape = arrival_shape
		arrival_query.exclude = [view.player.get_rid()]
		arrival_query.collision_mask = 1
		arrival_query.transform.origin = Vector3(door.x, 0.65, door.y)
		if not view.player.get_world_3d().direct_space_state.intersect_shape(arrival_query, 1).is_empty():
			issues.append("entrada chega dentro de colisão")
		if not bool(building.get("legacy_furnish", false)):
			var essentials := {"quarto": ["bed"], "sala": ["seat"], "cozinha": ["kitchenStove", "kitchenFridge", "kitchenSink"], "banheiro": ["bath", "toilet", "bathroomSink"], "escritorio": ["desk", "seat"], "recepcao": ["desk"], "enfermaria": ["bed"]}
			for room_info in floor_node.get_meta("rooms"):
				for required in essentials.get(room_info[0], []):
					var present := false
					for item in placements:
						if item["room"] == room_info[1] and (item["model"] == required or item["kind"] == required):
							present = true
					if not present:
						issues.append("essencial ausente: %s/%s" % [room_info[0], required])
		for i in placements.size():
			var item: Dictionary = placements[i]
			if not (item["room"] as Rect2).encloses(item["rect"]):
				issues.append("móvel fora do cômodo: " + str(item["model"]))
			if not bool(item["solid"]) or float(item["height"]) > 0.2:
				continue
			for j in range(i + 1, placements.size()):
				var other: Dictionary = placements[j]
				if bool(other["solid"]) and float(other["height"]) < 0.2 and (item["rect"] as Rect2).intersects(other["rect"]):
					issues.append("sobreposição: %s/%s" % [item["model"], other["model"]])
		if not Grass.inside_interior((building["rect"] as Rect2).get_center()):
			issues.append("grama não excluída")
		var tested := 0
		for target in view.city.objects.values():
			if str(target["loc"]) != id or target.get("outdoor", false) or (not target["plan"].has("room") and target["kind"] != "stairs") or int(target["plan"].get("floor", 0)) != 0 or not str(target["kind"]) in ["bed", "seat", "bath", "stove", "stairs"]:
				continue
			var path: Array = target["plan"]["path"]
			if path.is_empty() or view._furnished_path(id, path.back(), door, 0).is_empty():
				issues.append("sem acesso: " + str(target["key"]))
				if OS.get_environment("INTERIOR_FOCUS") != "":
					print("DEBUG PLAN ", target["plan"], " door=", door)
					var sphere := SphereShape3D.new()
					sphere.radius = 0.29
					var query := PhysicsShapeQueryParameters3D.new()
					query.shape = sphere
					query.collision_mask = 1
					query.exclude = [view.player.get_rid()]
					query.transform.origin = Vector3(path.back().x, 0.65, path.back().y)
					for hit in view.player.get_world_3d().direct_space_state.intersect_shape(query, 10):
						var collider: Node = hit["collider"]
						var shape: CollisionShape3D = collider.shape_owner_get_owner(collider.shape_find_owner(hit["shape"]))
						print("DEBUG COLLIDER ", collider.get_path(), " ", shape.global_position, " ", shape.shape)
					var room: Rect2 = target["plan"].get("room", floor_node.get_meta("rooms").back()[1])
					for offset in [-0.7, -0.35, 0.0, 0.35, 0.7]:
						var position: Vector3 = floor_node.global_transform * Vector3(room.get_center().x, 0.65, room.end.y + offset)
						query.transform.origin = position
						for hit in view.player.get_world_3d().direct_space_state.intersect_shape(query, 10):
							var collider: Node = hit["collider"]
							var shape: CollisionShape3D = collider.shape_owner_get_owner(collider.shape_find_owner(hit["shape"]))
							print("DEBUG DOOR ", position, " ", collider.get_path(), " ", shape.global_position, " ", shape.shape.size if shape.shape is BoxShape3D else shape.shape)
					var cache: Dictionary = view._furniture_routes[id + ":0"]
					var graph: AStar2D = cache["graph"]
					var debug := preload("res://world3d/mesh_kit.gd").new()
					debug.registers_ground = false
					var visited := {}
					var components := []
					for key in graph.get_point_ids():
						if visited.has(key):
							continue
						var open := [key]
						var count := 0
						var box := Rect2(graph.get_point_position(key), Vector2.ZERO)
						var color := Color.from_hsv(float(components.size()) * 0.27, 0.9, 1)
						while not open.is_empty():
							var next: int = open.pop_back()
							if visited.has(next):
								continue
							visited[next] = true
							count += 1
							var p := graph.get_point_position(next)
							box = box.expand(p)
							debug.sphere(Vector3(p.x, 0.29, p.y), Vector3.ONE * 0.065, color)
							open.append_array(Array(graph.get_point_connections(next)))
						components.append({"count": count, "box": box})
					print("DEBUG COMPONENTS ", components)
					var kitchen: Rect2 = (floor_node.get_meta("rooms") as Array).back()[1]
					var kitchen_entry: Vector2 = (floor_node.get_meta("use_points")["_rooms"] as Array).back()["entry"]
					var source_local: Vector3 = floor_node.to_local(Vector3(door.x, 0.65, door.y))
					var hall_a := floor_node.global_transform * Vector3(source_local.x, 0.65, kitchen_entry.y)
					var hall_b := floor_node.global_transform * Vector3(kitchen_entry.x, 0.65, kitchen_entry.y)
					query.transform.origin = hall_a
					query.motion = hall_b - hall_a
					var hall_fraction: PackedFloat32Array = view.player.get_world_3d().direct_space_state.cast_motion(query)
					print("DEBUG HALL CAST ", hall_a, " ", hall_b, " ", hall_fraction)
					print("DEBUG REGION ", view.layout.lots[id]["building"], " floor=", floor_node.global_transform)
					for waypoint in [door, Vector2(hall_a.x, hall_a.z), Vector2(hall_b.x, hall_b.z), path.back()]:
						var nearest := graph.get_closest_point(waypoint)
						print("DEBUG NEAREST ", waypoint, " nearest=", graph.get_point_position(nearest), " connected=", graph.get_point_connections(nearest))
					if hall_fraction[0] < 0.999:
						query.transform.origin = hall_a.lerp(hall_b, minf(1.0, hall_fraction[1] + 0.005))
						query.motion = Vector3.ZERO
						for hit in view.player.get_world_3d().direct_space_state.intersect_shape(query, 10):
							print("DEBUG HALL BLOCKER ", hit["collider"].get_path(), " ", hit["shape"])
					query.motion = Vector3.ZERO
					for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
						var local := Vector3(lerpf(source_local.x, kitchen_entry.x, fraction), 0.65, kitchen_entry.y)
						query.transform.origin = floor_node.global_transform * local
						for hit in view.player.get_world_3d().direct_space_state.intersect_shape(query, 10):
							var collider: Node = hit["collider"]
							var shape: CollisionShape3D = collider.shape_owner_get_owner(collider.shape_find_owner(hit["shape"]))
							print("DEBUG HALL ", local, " ", collider.get_path(), " ", shape.global_position, " ", shape.shape.size if shape.shape is BoxShape3D else shape.shape)
					var mesh := MeshInstance3D.new()
					mesh.mesh = debug.commit(view.city.mat)
					view.viewport.add_child(mesh)
			tested += 1
		if not issues.is_empty():
			failures.append({"id": id, "issues": issues})
		rows.append({"id": id, "floors": building.get("floor_count", 1), "profile": building.get("profile", "casa"), "objects": placements.size(), "functional_routes": tested, "build_ms": floor_node.get_meta("build_ms", 0.0), "rejected": floor_node.get_meta("rejected"), "issues": issues})
		print("MATRIX ", id, " props=", placements.size(), " routes=", tested, " issues=", issues)
		if int(building.get("floor_count", 1)) > 1:
			await upper_floor(building)
		if OS.get_environment("INTERIOR_CAPTURES") == "1" and (id == "casa_1_5_0" or id == "hospital"):
			await captures(building, scenario)
		if OS.get_environment("INTERIOR_FOCUS") != "":
			view.set_camera_mode(0, false, false)
			view.zoom = 12
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			view.get_viewport().get_texture().get_image().save_png(OUT + "/debug_" + id + ".png")
	var file := FileAccess.open(OUT + "/matrix_" + scenario + ".json", FileAccess.WRITE)
	if not view.city.objects.has("mercado/banco") or not view.city.objects.has("mercado/prateleira_0"):
		failures.append({"id": "mercado", "issues": ["objeto permanente perdido após descarregar interior"]})
	var bench_bounds: AABB = view.city.objects["mercado/banco"]["bounds"]
	if not view.city.seats.any(func(seat): return not seat.has("floor") and bench_bounds.has_point(Vector3(seat["p"].x, bench_bounds.get_center().y, seat["p"].y))):
		failures.append({"id": "mercado", "issues": ["banco permanente removido do sistema de assentos"]})
	file.store_string(JSON.stringify({"scenario": scenario, "buildings": rows, "failures": failures}, "\t"))
	print("MATRIX RESULT structures=", rows.size(), " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func upper_floor(building: Dictionary) -> void:
	var id := str(building["loc"])
	var number := int(building["floor_count"]) - 1
	view.city.ensure_floor(building, number)
	var node: Node3D = building["floor_nodes"][number]
	var target: Dictionary = view.city.objects[id + "/escada_descer_%d" % number]
	var origin: Vector2 = target["plan"]["path"].back()
	view.player.position = Vector3(origin.x, 0.245 + number * float(building["floor_height"]), origin.y)
	view.player.velocity = Vector3.ZERO
	view.path.clear()
	view._update_location()
	view._cutaway()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var issues: Array = []
	var tested := 0
	for object in view.city.objects.values():
		if str(object["loc"]) != id or not object["plan"].has("room") or int(object["plan"].get("floor", 0)) != number or not str(object["kind"]) in ["bed", "seat", "bath", "stove"]:
			continue
		tested += 1
		if view._furnished_path(id, object["plan"]["path"].back(), origin, number).is_empty():
			issues.append("sem acesso no andar %d: %s" % [number, object["key"]])
	var placements: Array = node.get_meta("placements")
	var essentials := {"quarto": ["bed"], "sala": ["seat"], "cozinha": ["kitchenStove", "kitchenFridge", "kitchenSink"], "banheiro": ["bath", "toilet", "bathroomSink"], "escritorio": ["desk", "seat"], "recepcao": ["desk"], "enfermaria": ["bed"]}
	for room_info in node.get_meta("rooms"):
		for required in essentials.get(room_info[0], []):
			var present := false
			for item in placements:
				if item["room"] == room_info[1] and (item["model"] == required or item["kind"] == required):
					present = true
			if not present:
				issues.append("essencial ausente no andar %d: %s/%s" % [number, room_info[0], required])
	if not issues.is_empty():
		failures.append({"id": id, "floor": number, "issues": issues})
	rows.append({"id": id, "floor": number, "objects": placements.size(), "functional_routes": tested, "issues": issues})
	print("MATRIX UPPER ", id, " floor=", number, " routes=", tested, " issues=", issues)

func captures(building: Dictionary, scenario: String) -> void:
	var id := str(building["loc"])
	var floor_node: Node3D = building["floor_nodes"][0]
	var plan: Dictionary = floor_node.get_meta("use_points").get("sofa", {})
	var stand: Vector2 = plan.get("path", [view.layout.door_in(id)]).back()
	view.player.position = Vector3(stand.x, 0.25, stand.y)
	view.player.velocity = Vector3.ZERO
	view.path.clear()
	for moment in [["dia", 11], ["tarde", 17], ["noite", 22], ["chuva", 13]]:
		TimeManager.total_minutes = 1440 + int(moment[1]) * 60
		if moment[0] == "chuva":
			WorldEvents.start("tempestade", 1)
		else:
			WorldEvents.stop("tempestade")
		view._update_environment()
		for mode in [0, 1]:
			view.set_camera_mode(mode, false, false)
			view.zoom = 13
			view.camera_rig.yaw = float(plan.get("yaw", 0.0)) + PI
			view.camera_rig._yaw = view.camera_rig.yaw
			for frame in 30:
				await get_tree().process_frame
			var lamps: Node3D = floor_node.get_meta("light")
			print("CAPTURE LIGHT ", id, " ", moment[0], " mode=", mode, " on=", lamps.visible, " tree=", lamps.is_visible_in_tree(), " expected=", view.city.loc_info[id].get("_light_on"), " power=", WorldEvents.power_out())
			await RenderingServer.frame_post_draw
			view.viewport.get_texture().get_image().save_png(OUT + "/%s_%s_%s_%s.png" % [scenario, id, moment[0], "iso" if mode == 0 else "tp"])
	WorldEvents.stop("tempestade")
	TimeManager.total_minutes = 1440 + 11 * 60
	view._update_environment()
