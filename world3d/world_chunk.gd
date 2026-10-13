extends "res://world3d/city_builder.gd"

const Grass = preload("res://world3d/grass_field.gd")
const LeavesMesh = preload("res://world3d/foliage.gd")
static var templates: Dictionary = {}
var coord := Vector2i.ZERO
var detailed := false
var jobs: Array = []
var next_job := 0
var defaults: Dictionary = {}
var parked: Dictionary = {}
var finished := false
var owner_key := ""
var deferred_meshes: Array = []
var last_operation := ""
var in_progress := false
var slice_start := 0
var fade_materials: Array[ShaderMaterial] = []
var initial_parked: Dictionary = {}


func cost_hint() -> int:
	if not deferred_meshes.is_empty():
		return 1200
	if next_job >= jobs.size():
		return 100
	return 4000 if str(jobs[next_job]["kind"]) in ["house", "content"] else 2000


func prepare(source: Node3D, chunk_coord: Vector2i, full_detail: bool) -> void:
	layout = source.layout
	coord = chunk_coord
	detailed = full_detail
	owner_key = "chunk:" + Layout.chunk_key(coord)
	for key in ["mat", "interior_mat", "glass_mat", "lit_mat", "window_mat", "window_lit_mat", "water_mat", "festa_mat",
		"ground_mat", "asphalt_mat", "walk_mat", "prop_mat", "veg_mat", "roof_mat", "shadow_mat", "cat_mats", "neon_mat",
		"ASPHALT", "SIDEWALK", "CURB", "GRASS", "GRASS2", "DIRT", "wear_city"]:
		set(key, source.get(key))
	var copied := {}
	for key in ["mat", "asphalt_mat", "walk_mat", "prop_mat", "veg_mat", "roof_mat", "window_mat", "window_lit_mat", "water_mat"]:
		var original: Material = get(key)
		if original is ShaderMaterial:
			if not copied.has(original.get_instance_id()):
				var copy: ShaderMaterial = original.duplicate()
				copied[original.get_instance_id()] = copy
				fade_materials.append(copy)
			set(key, copied[original.get_instance_id()])
	cat_mats = {"asphalt": asphalt_mat, "walk": walk_mat, "props": prop_mat, "veg": veg_mat}
	if get_parent().active.has(coord):
		visible = false
	house_gen = HouseGen.new()
	generation_pause = _checkpoint
	body = StaticBody3D.new()
	add_child(body)
	rng.seed = layout.seed_chunk(coord)
	jobs.append({"kind": "floor"})
	for cell in layout.ensure_chunk(coord):
		var info: Dictionary = layout.blocks[cell]
		jobs.append({"kind": "ground", "cell": cell})
		if detailed and str(info["kind"]) in ["casas", "chacara"] and str(info["loc"]) == "":
			for id in info["lots"]:
				jobs.append({"kind": "house", "cell": cell, "id": id})
		else:
			jobs.append({"kind": "content", "cell": cell})


func step() -> void:
	if not deferred_meshes.is_empty():
		last_operation = "mesh"
		var task: Dictionary = deferred_meshes.pop_front()
		if is_instance_valid(task["node"]):
			task["surface"].set_material(task["material"])
			task["node"].mesh = task["surface"].commit()
		finished = next_job >= jobs.size() and deferred_meshes.is_empty()
		return
	if next_job >= jobs.size():
		finished = true
		return
	in_progress = true
	slice_start = Time.get_ticks_usec()
	var job: Dictionary = jobs[next_job]
	last_operation = str(job["kind"])
	next_job += 1
	var cell: Vector2i = job.get("cell", coord * 2)
	rng.seed = layout.seed_chunk(coord, "%d:%d:%s" % [cell.x, cell.y, job.get("id", job["kind"])])
	Kit.generation_seed = rng.seed
	Kit.generation_serial = 0
	Grass.registration_owner = owner_key
	LeavesMesh.registration_owner = owner_key
	match str(job["kind"]):
		"floor": _floor_tile()
		"ground": await _street_tile(cell)
		"house":
			var id := str(job["id"])
			await house_gen.build(self, layout.lots[id])
			defaults[id] = Houses.initial_state(id)
		"content": await _content_tile(cell)
	in_progress = false
	get_parent().consume_budget(Time.get_ticks_usec() - slice_start)
	Grass.registration_owner = ""
	LeavesMesh.registration_owner = ""
	Kit.generation_seed = -1
	finished = next_job >= jobs.size() and deferred_meshes.is_empty()


func _mesh(kit, parent: Node3D, m: Material = null) -> MeshInstance3D:
	var first: MeshInstance3D = null
	if kit is ChunkKit:
		for cell in kit.kits:
			for category in kit.kits[cell]:
				var piece: Kit = kit.kits[cell][category]
				var node := _mesh(piece, parent, cat_mats.get(category, m if m else mat))
				if category in ChunkKit.FLAT:
					node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if first == null:
					first = node
		return first
	kit.install_colliders(parent)
	var node := MeshInstance3D.new()
	parent.add_child(node)
	_queue_surfaces(kit, node, m if m else mat)
	if kit.roofs != null:
		var roof := MeshInstance3D.new()
		node.add_child(roof)
		_queue_surfaces(kit.roofs, roof, roof_mat)
	_add_shadow(kit, parent)
	return node


func _queue_surfaces(kit: Kit, node: MeshInstance3D, material: Material) -> void:
	var batches: Array[SurfaceTool] = kit.stream_batches.duplicate()
	if kit.count > 0:
		batches.append(kit.st)
	for index in batches.size():
		var target := node
		if index > 0:
			target = MeshInstance3D.new()
			target.cast_shadow = node.cast_shadow
			node.add_child(target)
		deferred_meshes.append({"surface": batches[index], "node": target, "material": material})


func _add_shadow(kit, parent: Node3D) -> void:
	if kit.shadows == null:
		return
	var node := MeshInstance3D.new()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	_queue_surfaces(kit.shadows, node, shadow_mat)


func _floor_tile() -> void:
	var bounds := Rect2(Vector2(coord) * Layout.CHUNK_SIZE, Vector2.ONE * Layout.CHUNK_SIZE)
	var central := Rect2(Vector2.ZERO, Vector2.ONE * Layout.SIZE)
	var pieces: Array[Rect2] = [bounds]
	if bounds.intersects(central):
		var cut := bounds.intersection(central)
		pieces = [Rect2(bounds.position, Vector2(bounds.size.x, cut.position.y - bounds.position.y)),
			Rect2(Vector2(bounds.position.x, cut.end.y), Vector2(bounds.size.x, bounds.end.y - cut.end.y)),
			Rect2(Vector2(bounds.position.x, cut.position.y), Vector2(cut.position.x - bounds.position.x, cut.size.y)),
			Rect2(Vector2(cut.end.x, cut.position.y), Vector2(bounds.end.x - cut.end.x, cut.size.y))]
	var k := ChunkKit.new(80.0)
	k.cat = "veg"
	for rect in pieces:
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			k.box_ab(Vector3(rect.position.x, -0.2, rect.position.y), Vector3(rect.end.x, 0.12, rect.end.y), GRASS.lerp(GRASS2, rng.randf() * 0.6))
	_mesh(k, self)


func _street_tile(cell: Vector2i) -> void:
	var r := Layout.block_rect(cell)
	var info: Dictionary = layout.blocks[cell]
	var ring := int(info["ring"])
	if str(info["kind"]) == "costa":
		Grass.exclude_interior(Rect2(r.position - Vector2(10, 10), Vector2(40, 40)))
		return
	var k := ChunkKit.new(80.0)
	k.cat = "asphalt"
	var road := ASPHALT if ring < 3 else DIRT
	# Cada bloco possui as ruas norte/oeste. As metades coincidem nas fronteiras.
	if str(info["kind"]) != "aeroporto_area":
		k.box_ab(Vector3(r.position.x - 10, 0.12, r.position.y - 10), Vector3(r.end.x, 0.125, r.position.y), road)
		k.box_ab(Vector3(r.position.x - 10, 0.12, r.position.y), Vector3(r.position.x, 0.125, r.end.y), road)
		if detailed:
			for i in 5:
				var along := r.position.x + i * 6.0
				k.box(Vector3(along, 0.128, r.position.y - 5), Vector3(2.0, 0.006, 0.13), LINE.darkened(rng.randf() * 0.3))
				k.box(Vector3(r.position.x - 5, 0.128, r.position.y + i * 6.0), Vector3(0.13, 0.006, 2.0), LINE.darkened(rng.randf() * 0.3))
			for i in 4:
				k.box(Vector3(r.position.x - rng.randf_range(1, 9), 0.127, r.position.y + rng.randf_range(0, 30)), Vector3(rng.randf_range(0.3, 1.7), 0.004, rng.randf_range(1.0, 4.0)), road.darkened(0.12))
	k.cat = "walk"
	if str(info["kind"]) != "aeroporto_area":
		k.box_ab(Vector3(r.position.x - 0.3, 0.12, r.position.y - 0.3), Vector3(r.end.x + 0.3, 0.15, r.end.y + 0.3), CURB)
		k.box_ab(Vector3(r.position.x, 0.15, r.position.y), Vector3(r.end.x, 0.17, r.end.y), SIDEWALK.lightened(rng.randf_range(-0.06, 0.06)))
	k.cat = "veg"
	var inner := r.grow(-Layout.SIDEWALK)
	k.box_ab(Vector3(inner.position.x, 0.17, inner.position.y), Vector3(inner.end.x, 0.185, inner.end.y), GRASS.lerp(GRASS2, rng.randf()))
	_mesh(k, self)
	if str(info["kind"]) == "aeroporto_area":
		return
	var pole := Vector3(r.position.x + 1.0, 0.17, r.position.y + 1.0)
	await _instances("lamp", [Transform3D(Basis.IDENTITY, pole)])
	lamp_spots.append(pole + Vector3(0, 5.8, 0))
	var amount := 2 if ring < 3 else 5
	var trees: Array[Transform3D] = []
	for i in amount:
		var point := Vector3(r.end.x - 1.2, 0.17, r.position.y + 4 + i * (22.0 / maxi(amount - 1, 1)))
		trees.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.3)), point))
		foliage_sources.append(point + Vector3(0, 4, 0))
	await _instances("tree:" + Flora.species(rng), trees)
	if detailed:
		await generation_checkpoint()
		await _instances("bin", [Transform3D(Basis.IDENTITY, Vector3(r.end.x - 4, 0.17, r.end.y - 1))])
		WorldMotion.banner(self, pole + Vector3(0, 3.5, 0.12))
		var signs := ChunkKit.new(80.0)
		signs.cat = "props"
		signs.solid_cylinder(pole + Vector3(3, 0, 0), 0.04, 2.8, 4, "placa")
		signs.cyl(pole + Vector3(3, 0, 0), 0.04, 2.8, Color("#6b6f69"))
		signs.box(pole + Vector3(3, 2.55, 0), Vector3(1.8, 0.46, 0.07), Color("#344c40"))
		_wire(signs, pole + Vector3(0, 5.5, 0), pole + Vector3(40, 5.5, 0))
		_mesh(signs, self)
		var label := Label3D.new()
		label.text = Layout.street_name(cell.y)
		label.position = pole + Vector3(3, 2.55, 0.045)
		label.font_size = 28
		label.pixel_size = 0.003
		label.visibility_range_end = 45.0
		add_child(label)
		if rng.randf() < 0.45 and ring < 3:
			var id := "%d:%d:car" % [cell.x, cell.y]
			var saved: Dictionary = Layout.stream_state()["chunks"].get(Layout.chunk_key(coord), {}).get("vehicles", {}).get(id, {})
			var point := Vector3(r.position.x + 15, 0.14, r.position.y - 2)
			if saved.has("pos"):
				point = Vector3(float(saved["pos"][0]), float(saved["pos"][1]), float(saved["pos"][2]))
			var yaw := float(saved.get("yaw", PI * 0.5))
			var xf := Transform3D(Basis(Vector3.UP, yaw), point)
			await _instances("car", [xf])
			parked[id] = {"pos": [point.x, point.y, point.z], "yaw": yaw}
			initial_parked[id] = parked[id].duplicate(true)


func _content_tile(cell: Vector2i) -> void:
	var info: Dictionary = layout.blocks[cell]
	var r := Layout.block_rect(cell)
	var ring := int(info["ring"])
	var kind := str(info["kind"])
	var id := str(info["loc"])
	if kind == "costa":
		var coast := Kit.new()
		coast.registers_ground = false
		coast.box(Vector3(r.get_center().x - 5, 0.21, r.get_center().y - 5), Vector3(40, 0.025, 40), Color.WHITE)
		_mesh(coast, self, water_mat)
		# Um píer espaçado na margem, em coordenadas fixas; o restante é água contínua.
		if cell.x != 115 or posmod(cell.y, 16) != 0:
			return
		var pier := ChunkKit.new(80.0)
		pier.cat = "props"
		pier.use_surface("woodfloor")
		for board in 14:
			pier.box(Vector3(r.position.x - 10 + board * 0.9, 0.28, r.get_center().y), Vector3(0.85, 0.12, 3.0), Color("#8b785a").lightened(rng.randf_range(-0.1, 0.1)))
		_mesh(pier, self)
		return
	if id != "":
		await _landmark(id, r)
		return
	if kind == "aeroporto_area":
		_airfield(r)
		return
	if detailed and kind in ["casas", "comercio", "terreno", "estacionamento", "verde"]:
		await _build_filler(cell, info, false)
		return
	if kind == "predio":
		var floors := rng.randi_range(7, 15) if ring == 0 else rng.randi_range(3, 6)
		var rect := r.grow(-rng.randf_range(3.0, 5.5))
		if detailed:
			await _simple_building(rect, floors * 3.0, Art.pick("tower_walls", rng), Art.pick("roofs", rng), false, floors, "office" if rng.randf() < 0.5 else "res")
		else:
			_silhouette(rect, floors * 3.0)
		if detailed and rng.randf() < 0.2:
			var smoke := WorldMotion.smoke(self, Vector3(rect.position.x + 2, floors * 3.0 + 1, rect.position.y + 2))
			ambient_emitters.append({"node": smoke, "point": smoke.position})
	elif kind in ["casas", "comercio", "chacara"]:
		if detailed and kind == "chacara":
			await _simple_building(Rect2(r.position + Vector2(8, 10), Vector2(13, 9)), 3.0, Art.pick("walls", rng), Art.pick("roofs", rng), true)
		elif kind == "casas":
			for house_id in info["lots"]:
				var lot: Dictionary = layout.lots[house_id]
				_silhouette(lot["building"], float(lot.get("floors", 1)) * 2.9)
		else:
			_silhouette(r.grow(-6.0), 6.0 if ring < 2 else 3.0)
		await _field(r, false)
	else:
		await _field(r, kind == "plantacao")


func _silhouette(rect: Rect2, height: float) -> void:
	var k := ChunkKit.new(80.0)
	k.cat = "solid"
	k.box_ab(Vector3(rect.position.x, 0.185, rect.position.y), Vector3(rect.end.x, height, rect.end.y), Art.pick("walls", rng))
	k.use_surface("roof")
	k.box(Vector3(rect.get_center().x, height + 0.2, rect.get_center().y), Vector3(rect.size.x + 0.3, 0.4, rect.size.y + 0.3), Art.pick("roofs", rng))
	_mesh(k, self)


func _field(r: Rect2, planted: bool) -> void:
	var k := ChunkKit.new(80.0)
	k.cat = "veg"
	if planted:
		for row in 8:
			await generation_checkpoint()
			k.box(Vector3(r.position.x + 4 + row * 3, 0.2, r.get_center().y), Vector3(0.9, 0.1, 22), DIRT.darkened(0.1))
		var crops: Array[Transform3D] = []
		for row in 8:
			await generation_checkpoint()
			for plant in 12:
				crops.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * rng.randf_range(0.8, 1.25)), Vector3(r.position.x + 4 + row * 3, 0.23, r.position.y + 4 + plant * 1.8)))
		await _instances("crop", crops)
	var transforms: Array[Transform3D] = []
	for i in (10 if int(layout.blocks[Vector2i(floori((r.position.x - 10) / 40), floori((r.position.y - 10) / 40))]["ring"]) >= 3 else 4):
		await generation_checkpoint()
		var point := Vector3(rng.randf_range(r.position.x + 3, r.end.x - 3), 0.19, rng.randf_range(r.position.y + 3, r.end.y - 3))
		transforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.6)), point))
		foliage_sources.append(point + Vector3(0, 4, 0))
	await _instances("tree:" + ("conica" if Layout.density_ring(r.get_center()) == 4 else Flora.species(rng)), transforms)
	for i in 12:
		await generation_checkpoint()
		k.sphere(Vector3(rng.randf_range(r.position.x + 3, r.end.x - 3), 0.4, rng.randf_range(r.position.y + 3, r.end.y - 3)), Vector3(1, 0.6, 1), GRASS2)
	_mesh(k, self)


func _instances(kind: String, transforms: Array[Transform3D]) -> void:
	var obstacles := Kit.new()
	obstacles.registers_ground = false
	for xf in transforms:
		var s := xf.basis.get_scale()
		if kind.begins_with("tree:"):
			obstacles.solid_cylinder(xf.origin, 0.18 * maxf(s.x, s.z), 3.0 * s.y, 128, "arvore")
		elif kind == "lamp": obstacles.solid_cylinder(xf.origin, 0.09, 5.6)
		elif kind == "bin": obstacles.solid_box(xf.origin + Vector3(0, 0.435, 0), Vector3(0.66, 0.87, 0.66), 4, 0, "lixeira")
		elif kind == "car":
			obstacles.solid_box(xf * Vector3(0, 0.62, 0), Vector3(1.9, 0.65, 4.3), 8, xf.basis.get_euler().y, "carro")
			obstacles.solid_box(xf * Vector3(0, 1.16, 0), Vector3(1.72, 0.5, 2.1), 8, xf.basis.get_euler().y, "carro")
	obstacles.install_colliders(self)
	var cache_key := kind + ":" + Art.id() + ((":full" if detailed else ":low") if kind.begins_with("tree:") else "")
	if not templates.has(cache_key):
		await _checkpoint(true)
		var k := Kit.new()
		k.registers_ground = false
		var random := RandomNumberGenerator.new()
		random.seed = 391 + kind.hash()
		if kind.begins_with("tree:"):
			Flora.tree(k, Vector3.ZERO, 1.0, random, kind.get_slice(":", 1), detailed)
		elif kind == "lamp":
			k.cyl(Vector3.ZERO, 0.09, 5.6, Color("#59605b"))
			k.box(Vector3(0.65, 5.6, 0), Vector3(1.4, 0.1, 0.1), Color("#4f5551"))
			k.use_surface("lampglow")
			k.box(Vector3(1.2, 5.5, 0), Vector3(0.6, 0.15, 0.3), Color("#fff0ca"))
		elif kind == "bin":
			k.cyl(Vector3.ZERO, 0.3, 0.8, Color("#405143"))
			k.cyl(Vector3(0, 0.8, 0), 0.33, 0.07, Color("#303831"))
		elif kind == "car":
			CarMesh.draw(k, Vector3.ZERO, 0.0, Art.pick("doors", random), "sedan")
		elif kind == "crop":
			k.cyl(Vector3.ZERO, 0.025, 1.3, Color("#6b8043"))
			for leaf in 4:
				k.box(Vector3(0.18 * (1 if leaf % 2 == 0 else -1), 0.4 + leaf * 0.2, 0), Vector3(0.4, 0.025, 0.15), Color("#657b3c"), leaf * 1.5)
		templates[cache_key] = k.commit(veg_mat if kind.begins_with("tree:") else prop_mat)
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = templates[cache_key]
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.position = Vector3(coord.x * 80.0, 0, coord.y * 80.0)
	for i in transforms.size():
		var local := transforms[i]
		local.origin -= node.position
		multi.set_instance_transform(i, local)
	node.multimesh = multi
	node.material_override = veg_mat if kind.begins_with("tree:") or kind == "crop" else prop_mat
	node.visibility_range_end = 520.0
	node.visibility_range_end_margin = 50.0
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(node)
	if kind.begins_with("tree:") and detailed:
		for xf in transforms:
			LeavesMesh.register_sphere(xf * Transform3D(Basis.from_scale(Vector3(4, 3.5, 4)), Vector3(0, 3.8, 0)), Transform3D.IDENTITY, GRASS)
	var shade := Kit.new()
	for xf in transforms:
		shade.soft_shadow(xf.origin + Vector3(0, 0.003, 0), 1.0 if kind == "car" else 0.65, 2.2 if kind == "car" else 0.65, 0.4)
	_add_shadow(shade, self)


func _landmark(id: String, r: Rect2) -> void:
	var k := ChunkKit.new(80.0)
	k.cat = "walk"
	var center := r.get_center()
	var rect := r.grow(-3.5)
	if id == "aeroporto":
		_airfield(r)
		rect = Rect2(r.position + Vector2(2, 3), Vector2(26, 10))
		if detailed:
			await _simple_building(rect, 6.0, Art.pick("comm_walls", rng), Art.pick("roofs", rng), false, 2, "office")
			_adopt_landmark(id)
		else:
			_silhouette(rect, 6.0)
	elif id == "estadio":
		k.box(Vector3(center.x, 0.22, center.y), Vector3(21, 0.07, 16), GRASS)
		for side in [-1, 1]:
			for step_index in 4:
				k.box(Vector3(center.x, 0.7 + step_index * 0.6, center.y + side * (10 + step_index * 0.8)), Vector3(25, 0.7, 0.85), Color("#9a968b"))
			k.box(Vector3(center.x + side * 10, 1.5, center.y), Vector3(0.15, 2.8, 5.8), Color("#d4d1bf"))
	elif id == "cemiterio":
		for x in 5:
			for z in 4:
				k.box(Vector3(r.position.x + 5 + x * 4.2, 0.35, r.position.y + 5 + z * 5), Vector3(1.0, 0.3, 2.0), Color("#85867d"))
				k.box(Vector3(r.position.x + 5 + x * 4.2, 0.9, r.position.y + 4.1 + z * 5), Vector3(0.85, 1.4, 0.22), Color("#b6b7ab"))
	else:
		var floors := 3 if id == "shopping" else (4 if id == "universidade" else 2)
		if detailed:
			await _simple_building(rect, floors * 3.0, Color("#d5d0c0") if id == "prefeitura" else Art.pick("comm_walls", rng), Art.pick("roofs", rng), false, floors, "office")
			_adopt_landmark(id)
		else:
			_silhouette(rect, floors * 3.0)
		if id == "prefeitura":
			for x in 7:
				k.cyl(Vector3(r.position.x + 4 + x * 3.6, 0.19, r.end.y - 1.8), 0.22, 5.5, Color("#d9d5c8"))
			k.gable(Vector3(center.x, 6.2, r.end.y - 1.8), Vector3(26, 2.0, 3.6), Color("#d5d1c4"))
		if id == "boate":
			k.use_surface("lampglow")
			k.box(Vector3(center.x, 4.7, rect.end.y + 0.12), Vector3(14, 0.22, 0.12), Color("#a861af"))
	_mesh(k, self)
	var sign := Label3D.new()
	sign.text = Layout.LANDMARK_NAMES[id]
	sign.position = Vector3(center.x, 3.0, r.end.y - 2.0)
	sign.font_size = 40
	sign.pixel_size = 0.008
	sign.visibility_range_end = 160.0
	add_child(sign)


func _adopt_landmark(id: String) -> void:
	# Reutiliza a entrada/interior do construtor com o ID único do marco.
	var structure: Dictionary = structures.back()
	var generated := str(structure["loc"])
	layout.lots[id] = layout.lots[generated].duplicate(true)
	layout.lots[id]["id"] = id
	loc_info[id] = loc_info[generated]
	loc_info.erase(generated)
	layout.lots.erase(generated)
	layout.blocks[layout.lots[id]["cell"]]["lots"].erase(generated)
	World.locations.erase(generated)
	structure["loc"] = id


func _airfield(r: Rect2) -> void:
	var k := ChunkKit.new(80.0)
	k.cat = "asphalt"
	var strip_z := Layout.block_origin(Vector2i(65, 10)).y + 65.0
	var area := Rect2(r.position - Vector2(10, 10), Vector2(40, 40))
	var strip := area.intersection(Rect2(2610, strip_z - 20, 400, 40))
	if strip.has_area():
		k.box_ab(Vector3(strip.position.x, 0.185, strip.position.y), Vector3(strip.end.x, 0.195, strip.end.y), ASPHALT)
		k.cat = "walk"
		if strip_z > area.position.y and strip_z < area.end.y:
			k.box(Vector3(area.get_center().x, 0.198, strip_z), Vector3(13, 0.003, 0.5), LINE)
	_mesh(k, self)


func _checkpoint(force: bool = false) -> void:
	var elapsed := Time.get_ticks_usec() - slice_start
	if not force and elapsed < mini(3000, maxi(1000, get_parent().remaining_budget() - 500)):
		return
	get_parent().consume_budget(elapsed)
	var seed_value := Kit.generation_seed
	var serial_value := Kit.generation_serial
	Grass.registration_owner = ""
	LeavesMesh.registration_owner = ""
	Kit.generation_seed = -1
	await get_tree().process_frame
	slice_start = Time.get_ticks_usec()
	Grass.registration_owner = owner_key
	LeavesMesh.registration_owner = owner_key
	Kit.generation_seed = seed_value
	Kit.generation_serial = serial_value


func set_stream_fade(amount: float, inverse: bool = false) -> void:
	for material in fade_materials:
		material.set_shader_parameter("stream_visibility", amount)
		material.set_shader_parameter("stream_inverse", inverse)
