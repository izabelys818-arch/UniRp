extends Node3D

const Layout = preload("res://world3d/city_layout.gd")
const ChunkScene = preload("res://world3d/world_chunk.tscn")
const Grass = preload("res://world3d/grass_field.gd")
const Foliage = preload("res://world3d/foliage.gd")
const Horizon = preload("res://world3d/world_horizon.gd")
const BUDGET_US := 6000
const DETAIL_RADIUS := 1
const OUTER_RADIUS := 5
var layout: Layout
var city: Node3D
var view: Node
var active: Dictionary = {}
var queue: Array = []
var focus := Vector2.ZERO
var last_coord := Vector2i(2147483647, 2147483647)
var working: Dictionary = {}
var generation_worst_us := 0
var operation_worst_us := 0
var over_budget := 0
var revision := 0
var horizon: Node3D
var _budget_frame := -1
var _frame_us := 0
var _fades: Array = []
var _unloads: Array[Vector2i] = []


func remaining_budget() -> int:
	var frame := Engine.get_process_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_frame_us = 0
	return BUDGET_US - _frame_us


func consume_budget(cost: int) -> void:
	remaining_budget()
	_frame_us += cost
	generation_worst_us = maxi(generation_worst_us, _frame_us)
	if _frame_us > BUDGET_US:
		over_budget += 1


func setup(world_view: Node) -> void:
	add_to_group("world_stream")
	add_to_group("world_chunks")
	view = world_view
	layout = view.layout
	city = view.city
	horizon = Horizon.new()
	add_child(horizon)
	horizon.setup(city)
	update_focus(view._p2())


func update_focus(point: Vector2) -> void:
	focus = point
	var center := Layout.chunk_at(point)
	if center == last_coord:
		return
	last_coord = center
	horizon.update_focus(point)
	var wanted := {}
	for x in range(center.x - OUTER_RADIUS, center.x + OUTER_RADIUS + 1):
		for y in range(center.y - OUTER_RADIUS, center.y + OUTER_RADIUS + 1):
			var coord := Vector2i(x, y)
			# El distrito preservado já possui seus chunks geométricos.
			if coord.x >= 0 and coord.y >= 0 and coord.x < 4 and coord.y < 4:
				continue
			var distance := maxi(absi(x - center.x), absi(y - center.y))
			var detail := distance <= DETAIL_RADIUS
			wanted[coord] = detail
			if not active.has(coord) or (detail and not bool(active[coord].get("detailed", false))):
				queue.append({"coord": coord, "detailed": detail})
	for coord in active.keys():
		var distance := maxi(absi(coord.x - center.x), absi(coord.y - center.y))
		if distance > OUTER_RADIUS + 1:
			if not coord in _unloads:
				_unloads.append(coord)
			active[coord]["node"].visible = false
		elif distance > DETAIL_RADIUS + 1 and bool(active[coord].get("detailed", false)):
			queue.append({"coord": coord, "detailed": false})
	queue = queue.filter(func(job): return wanted.has(job["coord"]) and (not active.has(job["coord"]) or bool(active[job["coord"]]["detailed"]) != bool(job["detailed"])))
	var seen := {}
	var unique: Array = []
	for job in queue:
		var key := Layout.chunk_key(job["coord"])
		if not seen.has(key):
			seen[key] = true
			unique.append(job)
	queue = unique
	queue.sort_custom(func(a, b): return (a["coord"] as Vector2i).distance_squared_to(center) < (b["coord"] as Vector2i).distance_squared_to(center))


func tick() -> void:
	var started := Time.get_ticks_usec()
	if horizon.building and remaining_budget() > 1500:
		horizon.step()
		consume_budget(Time.get_ticks_usec() - started)
	if not _unloads.is_empty():
		var unload_started := Time.get_ticks_usec()
		var coord: Vector2i = _unloads.pop_front()
		if active.has(coord) and maxi(absi(coord.x - last_coord.x), absi(coord.y - last_coord.y)) > OUTER_RADIUS + 1:
			_unload(coord)
		consume_budget(Time.get_ticks_usec() - unload_started)
	var fade_started := Time.get_ticks_usec()
	for entry in _fades.duplicate():
		if not is_instance_valid(entry["node"]):
			_dispose(entry["old"])
			_fades.erase(entry)
			continue
		var amount := clampf((Time.get_ticks_msec() - int(entry["started"])) / 850.0, 0.0, 1.0)
		entry["node"].set_stream_fade(amount)
		entry["old"].set_stream_fade(1.0 - amount, true)
		if amount >= 1.0:
			_dispose(entry["old"])
			_fades.erase(entry)
	consume_budget(Time.get_ticks_usec() - fade_started)
	while Time.get_ticks_usec() - started < BUDGET_US and remaining_budget() > 1500:
		if working.is_empty():
			if queue.is_empty():
				break
			var job: Dictionary = queue.pop_front()
			var coord: Vector2i = job["coord"]
			if coord.distance_to(last_coord) > (OUTER_RADIUS + 1) * 1.42:
				continue
			var node: Node3D = ChunkScene.instantiate()
			add_child(node)
			var prepare_started := Time.get_ticks_usec()
			node.prepare(city, coord, bool(job["detailed"]))
			consume_budget(Time.get_ticks_usec() - prepare_started)
			node.owner_key += ":" + str(node.get_instance_id())
			working = {"node": node, "coord": coord, "detailed": bool(job["detailed"])}
		var node: Node3D = working["node"]
		if node.in_progress:
			break
		if remaining_budget() < node.cost_hint():
			break
		var before := Time.get_ticks_usec()
		node.step.call()
		var cost := Time.get_ticks_usec() - before
		if cost > operation_worst_us and cost > BUDGET_US:
			print("CHUNK COST coord=", working["coord"], " op=", node.last_operation, " us=", cost)
		operation_worst_us = maxi(operation_worst_us, cost)
		if node.last_operation == "mesh":
			consume_budget(cost)
		if node.finished:
			var attach_started := Time.get_ticks_usec()
			var coord: Vector2i = working["coord"]
			if active.has(coord):
				var old: Node3D = active[coord]["node"]
				_detach(old)
				node.set_stream_fade(0.0)
				_fades.append({"node": node, "old": old, "started": Time.get_ticks_msec()})
			node.visible = true
			active[coord] = working
			_attach(node)
			working = {}
			consume_budget(Time.get_ticks_usec() - attach_started)
	var elapsed := Time.get_ticks_usec() - started
	generation_worst_us = maxi(generation_worst_us, elapsed)
	if elapsed > BUDGET_US:
		over_budget += 1


func _attach(node: Node3D) -> void:
	city.structures.append_array(node.structures)
	city.loc_info.merge(node.loc_info, true)
	city.objects.merge(node.objects, true)
	city.lamp_spots.append_array(node.lamp_spots)
	city.foliage_sources.append_array(node.foliage_sources)
	city.seats.append_array(node.seats)
	city.beds.append_array(node.beds)
	city.ambient_emitters.append_array(node.ambient_emitters)
	city.interior_revision += 1
	revision += 1
	var saved: Dictionary = Layout.stream_state()["chunks"].get(Layout.chunk_key(node.coord), {})
	for child in node.find_children("*", "Node3D", true, false):
		if child.has_meta("persistent_id"):
			var id := str(child.get_meta("persistent_id"))
			if saved.get("objects", {}).has(id):
				child.set_meta("persistent_state", saved["objects"][id])
	var rect := Rect2(Vector2(node.coord) * 80.0, Vector2.ONE * 80.0)
	view.grass.invalidate_region(rect)
	view.foliage.invalidate_region(rect)


func _detach(node: Node3D) -> void:
	for structure in node.structures:
		city.drop_interior(structure)
		city.structures.erase(structure)
	for dictionary in [[city.loc_info, node.loc_info], [city.objects, node.objects], [city.use_points, node.use_points]]:
		for key in dictionary[1]:
			dictionary[0].erase(key)
	for arrays in [[city.lamp_spots, node.lamp_spots], [city.foliage_sources, node.foliage_sources], [city.seats, node.seats], [city.beds, node.beds], [city.ambient_emitters, node.ambient_emitters]]:
		for item in arrays[1]:
			arrays[0].erase(item)
	city.interior_revision += 1
	revision += 1


func _dispose(node: Node3D) -> void:
	# Casas/mobília/contratos continuam nos sistemas existentes. Descarta apenas
	# os defaults criados para desenhar fachadas, nunca uma alteração do jogador.
	for id in node.defaults:
		if Houses.all().get(id, {}) == node.defaults[id] and not HomeSystem.has_access(id):
			Houses.all().erase(id)
	Grass.release_owner(node.owner_key)
	Foliage.release_owner(node.owner_key)
	node.queue_free()


func _unload(coord: Vector2i) -> void:
	var node: Node3D = active[coord]["node"]
	_capture(node)
	_detach(node)
	_dispose(node)
	active.erase(coord)
	layout.release_chunk(coord)
	var rect := Rect2(Vector2(coord) * 80.0, Vector2.ONE * 80.0)
	view.grass.invalidate_region(rect)
	view.foliage.invalidate_region(rect)


func _capture(node: Node3D) -> void:
	var objects := {}
	var state: Dictionary = Layout.stream_state()["chunks"].get(Layout.chunk_key(node.coord), {}).duplicate(true)
	for child in node.find_children("*", "Node3D", true, false):
		if child.has_meta("persistent_id") and child.has_meta("persistent_state"):
			objects[str(child.get_meta("persistent_id"))] = child.get_meta("persistent_state")
	# Estado alterado ocupa espaço no save; geometria e carros imóveis padrão
	# são regenerados pela semente, sem acumular um histórico por chunk visitado.
	if not objects.is_empty():
		state["objects"] = objects
	for id in node.parked:
		if node.parked[id] != node.initial_parked.get(id, {}):
			if not state.has("vehicles"):
				state["vehicles"] = {}
			state["vehicles"][id] = node.parked[id].duplicate(true)
	if not state.is_empty():
		Layout.stream_state()["chunks"][Layout.chunk_key(node.coord)] = state


func flush() -> void:
	for entry in active.values():
		_capture(entry["node"])
	if is_instance_valid(view.player):
		var point: Vector2 = view._p2()
		GameState.player["pos"] = [point.x, point.y]
		GameState.player["pos_height"] = view.player.position.y
	for id in view.npcs:
		var entry: Dictionary = view.npcs[id]
		if str(entry["loc"]) == "":
			continue
		var fig: Node3D = entry["fig"]
		Layout.stream_state()["npc_positions"][id] = {"pos": [fig.position.x, fig.position.z], "loc": entry["loc"]}


func settled() -> bool:
	return queue.is_empty() and working.is_empty() and _fades.is_empty() and _unloads.is_empty()


func near_ready() -> bool:
	for x in range(last_coord.x - 1, last_coord.x + 2):
		for y in range(last_coord.y - 1, last_coord.y + 2):
			if x >= 0 and y >= 0 and x < 4 and y < 4:
				continue
			var coord := Vector2i(x, y)
			if not active.has(coord) or not bool(active[coord]["detailed"]):
				return false
	return true


func _exit_tree() -> void:
	# Não escreve save ao sair; remove registros estáticos para a próxima tela.
	for entry in active.values():
		Grass.release_owner(entry["node"].owner_key)
		Foliage.release_owner(entry["node"].owner_key)
	if not working.is_empty() and is_instance_valid(working["node"]):
		Grass.release_owner(working["node"].owner_key)
		Foliage.release_owner(working["node"].owner_key)
	for entry in _fades:
		Grass.release_owner(entry["old"].owner_key)
		Foliage.release_owner(entry["old"].owner_key)
	preload("res://world3d/world_chunk.gd").templates.clear()
