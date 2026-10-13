extends Node3D

# Vida da cidade: carros que seguem as ruas e viram nas esquinas (freiam para pessoas e outros
# carros), pedestres de vários tipos, cachorros e pássaros. Só decoração viva: não altera a
# simulação do jogo.

const Layout = preload("res://world3d/city_layout.gd")
const Humanoid = preload("res://world3d/person.gd")
const Toon = preload("res://world3d/humanoid.gd")
const Kit = preload("res://world3d/mesh_kit.gd")
const PhysicalVehicle = preload("res://world3d/physical_vehicle.gd")
const PhysicsLayers = preload("res://world3d/physics_layers.gd")
var physical_world: Node3D
const CarMesh = preload("res://world3d/car_mesh.gd")
const AnimalMesh = preload("res://world3d/animal_mesh.gd")
const HumanMotion = preload("res://world3d/human_motion.gd")
const LookBuilder = preload("res://ui/face/look_builder.gd")

var layout: Layout
var city: Node3D
var rng := RandomNumberGenerator.new()
var cars: Array = []
var peds: Array = []
var dogs: Array = []
var birds: Array = []
var head_lights: Array = []
var player_pos: Vector2 = Vector2.ZERO
var _stream_center := Vector2i(2147483647, 2147483647)


func setup(l: Layout, c: Node3D, with_people: bool = true, staged: bool = false, progress: Callable = Callable()) -> void:
	layout = l
	city = c
	rng.seed = 5511
	_make_cars()
	if str(GameState.player.get("cenario", "porto_cinza")) in ["porto_cinza", "nova_aurora"]:
		_make_tram()
	if with_people:
		await _make_peds(staged, progress)
		_make_dogs()
	_make_birds()
	for entry in peds:
		var figure: Node3D = entry["fig"]
		entry["physical"] = physical_world.actor(figure, PhysicsLayers.NPC, Callable(), clampf(figure.scale.y * 1.6, 0.9, 1.9), clampf(figure.scale.y * 0.28, 0.19, 0.32))
	for entry in dogs:
		entry["physical"] = physical_world.actor(entry["node"], PhysicsLayers.ANIMAL, Callable(), 0.6, 0.22)
	for entry in birds:
		entry["physical"] = physical_world.actor(entry["node"], PhysicsLayers.ANIMAL, Callable(), 0.28, 0.12)
		entry["physical"].body.collision_layer = 0
		entry["physical"].body.collision_mask = 0
	for i in 4:
		var sp := SpotLight3D.new()
		sp.spot_range = 16.0
		sp.spot_angle = 38.0
		sp.light_energy = 2.2
		sp.light_color = Color("#fff1c9")
		sp.visible = false
		add_child(sp)
		head_lights.append(sp)


# ---------- carros ----------

func _car_kit(kind: int, col: Color) -> Kit:
	var k := Kit.new()
	var dark := Color("#1d2630")
	var tire := Color("#141414")
	k.use_surface("carpaint")
	match kind:
		1:   # picape
			k.box(Vector3(0, 0.7, 0.55), Vector3(1.9, 0.75, 2.1), col)
			k.box(Vector3(0, 1.3, 0.75), Vector3(1.7, 0.6, 1.2), col.lightened(0.08))
			k.box(Vector3(0, 1.3, 0.78), Vector3(1.74, 0.45, 1.05), dark)
			k.box(Vector3(0, 0.88, -1.15), Vector3(1.9, 0.5, 1.7), col.darkened(0.1))
			k.box(Vector3(0, 1.13, -1.15), Vector3(1.7, 0.06, 1.5), col.darkened(0.35))
		2:   # van
			k.box(Vector3(0, 1.1, 0), Vector3(1.95, 1.5, 4.4), col)
			k.box(Vector3(0, 1.45, 1.55), Vector3(1.99, 0.65, 1.0), dark)
			k.box(Vector3(0, 0.45, 0), Vector3(1.95, 0.3, 4.4), col.darkened(0.2))
		3:   # táxi: carro de verdade com a placa luminosa no teto
			CarMesh.draw(k, Vector3.ZERO, 0.0, Color("#e8c21c"), "sedan")
			k.box(Vector3(0, 1.5, -0.1), Vector3(0.6, 0.18, 0.28), Color("#f4f0d0"))
			return k
		_:   # sedã ou hatch
			# sedã: os faróis de luz de verdade do tráfego ficam a 2,12 m do centro
			CarMesh.draw(k, Vector3.ZERO, 0.0, col, "sedan")
			return k
	k.use_surface("")
	var wl: float = 1.35 if kind != 2 else 1.5
	for wx in [-0.88, 0.88]:
		for wz in [-wl, wl]:
			k.add("cyl", Transform3D(Basis(Vector3.FORWARD, PI / 2.0) * Basis.from_scale(Vector3(0.7, 0.3, 0.7)), Vector3(wx, 0.35, wz)), tire)
	k.box(Vector3(0, 0.55, 2.12 if kind != 2 else 2.22), Vector3(1.7, 0.1, 0.08), Color("#2a2a2a"))
	return k


func _make_cars() -> void:
	# mesmo shader fotográfico da cidade (pintura de carro, vidro, pneus, faróis à noite)
	var mat: Material = city.prop_mat
	var colors := [Color("#b9bcc0"), Color("#8b1e1e"), Color("#1f3d6b"), Color("#e8e6df"), Color("#2b2d31"), Color("#3b6b3a"), Color("#6b4a2e"), Color("#7a7d80")]
	for i in 18:
		var kind: int = [0, 0, 0, 1, 1, 2, 3, 3][rng.randi() % 8]
		var col: Color = colors[rng.randi() % colors.size()]
		var car := PhysicalVehicle.new()
		car.configure(false, kind == 2)
		var mi := MeshInstance3D.new()
		mi.mesh = _car_kit(kind, col).commit(mat)
		car.add_child(mi)
		var lights := Kit.new()
		lights.box(Vector3(-0.58, 0.78, 2.12), Vector3(0.4, 0.18, 0.06), Color.WHITE)
		lights.box(Vector3(0.58, 0.78, 2.12), Vector3(0.4, 0.18, 0.06), Color.WHITE)
		var li := MeshInstance3D.new()
		li.mesh = lights.commit(city.lit_mat)
		li.visible = kind in [1, 2]
		car.add_child(li)
		var tail := Kit.new()
		tail.box(Vector3(-0.6, 0.8, -2.12), Vector3(0.4, 0.16, 0.06), Color("#c01c1c"))
		tail.box(Vector3(0.6, 0.8, -2.12), Vector3(0.4, 0.16, 0.06), Color("#c01c1c"))
		var ti := MeshInstance3D.new()
		ti.mesh = tail.commit(Kit.vertex_material())
		ti.visible = kind in [1, 2]
		car.add_child(ti)
		# sombra de contato: o carro roda no asfalto, não flutua (sobretudo à noite e na chuva)
		var sk := Kit.new()
		sk.disc(Vector3(0, -0.004, 0), 1.15, 2.5, Color(0.02, 0.02, 0.04, 0.6), 0.0, 18, 0.0, 0.8, 0.85)
		var si := MeshInstance3D.new()
		si.mesh = sk.commit(Kit.shadow_material())
		si.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		car.add_child(si)
		add_child(car)
		var node := Vector2i(rng.randi_range(1, Layout.GRID - 1), rng.randi_range(1, Layout.GRID - 1))
		var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		var d: Vector2i = dirs[rng.randi() % 4]
		var e := {"node": car, "dir": d, "next": node + d, "targets": [], "speed": 0.0, "top": rng.randf_range(7.5, 11.5), "wait": 0.0, "kind": kind, "pos": Vector2.ZERO, "yaw": 0.0}
		var start := Layout._node_pos(node) + _right(d) * 1.8
		e["pos"] = start
		e["yaw"] = atan2(d.x, d.y)
		car.position = Vector3(start.x, 0.14, start.y)
		car.rotation.y = e["yaw"]
		e["targets"] = [_approach(e["next"], d)]
		cars.append(e)
		_wheels(e)


func _wheels(entry: Dictionary) -> void:
	var k := Kit.new()
	k.registers_ground = false
	k.use_surface("metal")
	k.box(Vector3.ZERO, Vector3(0.028, 0.5, 0.04), Color("#7e8385"))
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = k.commit(city.prop_mat)
	multi.instance_count = 4
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	entry["node"].add_child(node)
	entry["wheels"] = node
	entry["wheel_phase"] = 0.0


func _make_tram() -> void:
	var car := PhysicalVehicle.new()
	car.configure(true)
	var k := Kit.new()
	k.registers_ground = false
	CarMesh.draw_bus(k, Vector3.ZERO, 0.0, Color("#607869"))
	k.use_surface("metal")
	k.box(Vector3(0, 3.5, 0), Vector3(0.08, 1.2, 0.08), Color("#535851"), 0.35)
	k.box(Vector3(0, 4.1, 0), Vector3(1.4, 0.08, 0.15), Color("#535851"))
	var mesh := MeshInstance3D.new()
	mesh.mesh = k.commit(city.prop_mat)
	car.add_child(mesh)
	city._add_shadow(k, car)
	add_child(car)
	var node := Vector2i(4, 2)
	var direction := Vector2i.DOWN
	var point := Layout._node_pos(node) + _right(direction) * 1.8
	var entry := {"node": car, "dir": direction, "next": node + direction, "targets": [_approach(node + direction, direction)], "speed": 0.0, "top": 6.0, "wait": 0.0,
		"kind": 4, "pos": point, "yaw": 0.0, "tram_route": [Vector2i(4, 6), Vector2i(2, 6), Vector2i(2, 2), Vector2i(4, 2)], "tram_i": 0}
	car.position = Vector3(point.x, 0.14, point.y)
	cars.append(entry)
	_wheels(entry)


static func _right(d: Vector2i) -> Vector2:
	return Vector2(-d.y, d.x)


func _approach(node: Vector2i, d: Vector2i) -> Vector2:
	return Layout._node_pos(node) + _right(d) * 1.8 - Vector2(d) * 4.0


func _exit_pt(node: Vector2i, d: Vector2i) -> Vector2:
	return Layout._node_pos(node) + _right(d) * 1.8 + Vector2(d) * 4.0


func _pick_dir(node: Vector2i, d: Vector2i) -> Vector2i:
	var options: Array = []
	for nd in [d, Vector2i(-d.y, d.x), Vector2i(d.y, -d.x)]:
		var nn: Vector2i = node + nd
		if layout.street_nodes.has(nn) and Layout.road_edge(node, nn):
			options.append(nd)
			if nd == d:
				options.append(nd)
				options.append(nd)
	if options.is_empty():
		return Vector2i(-d.x, -d.y)
	return options[rng.randi() % options.size()]


func _update_cars(delta: float, night: bool) -> void:
	for e in cars:
		var car: CharacterBody3D = e["node"]
		var pos: Vector2 = e["pos"]
		var tgts: Array = e["targets"]
		if tgts.is_empty():
			continue
		var tgt: Vector2 = tgts[0]
		var to := tgt - pos
		var dist := to.length()
		var heading := Vector2(sin(float(e["yaw"])), cos(float(e["yaw"])))
		# freia para quem está à frente
		var brake := 1.0
		for o in cars:
			if o == e:
				continue
			var op: Vector2 = o["pos"]
			var rel := op - pos
			var ahead := rel.dot(heading)
			if ahead > 0.0 and ahead < 7.5 and absf(rel.cross(heading)) < 2.0:
				brake = minf(brake, clampf((ahead - 3.0) / 4.5, 0.0, 1.0))
		var rel_p := player_pos - pos
		var pa := rel_p.dot(heading)
		if pa > 0.0 and pa < 9.0 and absf(rel_p.cross(heading)) < 2.4:
			brake = minf(brake, clampf((pa - 3.0) / 6.0, 0.0, 1.0))
		for pd in peds:
			var pf: Node3D = pd["fig"]
			var rel2 := Vector2(pf.position.x, pf.position.z) - pos
			var a2 := rel2.dot(heading)
			if a2 > 0.0 and a2 < 6.0 and absf(rel2.cross(heading)) < 1.8:
				brake = minf(brake, clampf((a2 - 2.5) / 3.5, 0.0, 1.0))
		var want: float = float(e["top"]) * brake
		if float(e["wait"]) > 0.0:
			e["wait"] = float(e["wait"]) - delta
			want = 0.0
		# desacelera em curvas
		var turn := absf(angle_difference(float(e["yaw"]), atan2(to.x, to.y)))
		want *= clampf(1.0 - turn * 0.5, 0.35, 1.0)
		e["speed"] = move_toward(float(e["speed"]), want, (9.0 if want < float(e["speed"]) else 4.0) * delta)
		var step: float = minf(float(e["speed"]) * delta, dist)
		e["wheel_phase"] = float(e.get("wheel_phase", 0.0)) + step / 0.35
		var wheels: MultiMeshInstance3D = e["wheels"]
		wheels.visible = pos.distance_to(player_pos) < 80.0
		if wheels.visible:
			for wi in 4:
				wheels.multimesh.set_instance_transform(wi, Transform3D(Basis(Vector3.RIGHT, float(e["wheel_phase"])), Vector3(-0.92 if wi % 2 == 0 else 0.92, 0.35, -1.35 if wi < 2 else 1.35)))
		if dist > 0.01:
			var dirv := to / dist
			pos += dirv * step
			e["yaw"] = lerp_angle(float(e["yaw"]), atan2(dirv.x, dirv.y), minf(delta * (3.0 + float(e["speed"]) * 0.35), 1.0))
		var displacement := Vector3(pos.x - car.position.x, 0, pos.y - car.position.z)
		if car.drive(displacement, float(e["yaw"]), float(e["speed"]), pos.distance_squared_to(player_pos) < 6400):
			e["speed"] = 0.0
		e["pos"] = Vector2(car.position.x, car.position.z)
		e["yaw"] = car.rotation.y
		if dist < 0.6:
			tgts.pop_front()
			if tgts.is_empty():
				var d: Vector2i = e["dir"]
				var node: Vector2i = e["next"]
				var d2 := _pick_dir(node, d)
				if e.has("tram_route"):
					var target: Vector2i = e["tram_route"][e["tram_i"]]
					if node == target:
						e["tram_i"] = (int(e["tram_i"]) + 1) % 4
						target = e["tram_route"][e["tram_i"]]
					var gap := target - node
					d2 = Vector2i(signi(gap.x), 0) if gap.x != 0 else Vector2i(0, signi(gap.y))
				tgts.append(_exit_pt(node, d2))
				var n2 := node + d2
				e["dir"] = d2
				e["next"] = n2
				tgts.append(_approach(n2, d2))
				if d2 != d and rng.randf() < 0.5:
					e["wait"] = rng.randf_range(0.3, 1.4)


func _assign_headlights(night: bool) -> void:
	var sorted := cars.duplicate()
	sorted.sort_custom(func(a, b): return (a["pos"] as Vector2).distance_squared_to(player_pos) < (b["pos"] as Vector2).distance_squared_to(player_pos))
	for i in head_lights.size():
		var l: SpotLight3D = head_lights[i]
		l.visible = night and i < sorted.size() and (sorted[i]["pos"] as Vector2).distance_to(player_pos) < 50.0
		if l.visible:
			var car: Node3D = sorted[i]["node"]
			l.global_position = car.global_position + car.global_transform.basis.z * 2.0 + Vector3(0, 0.9, 0)
			# a luz aponta para o -Z dela; o carro anda para o +Z: vira 180° e inclina para o chão
			l.global_basis = car.global_basis.orthonormalized() * Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -0.14)


# ---------- pedestres ----------

func _make_peds(staged: bool = false, progress: Callable = Callable()) -> void:
	var outfits := ["camiseta", "jeans", "moletom", "social", "blusa", "regata", "couro", "vestido", "academia", "time", "sobretudo"]
	for i in 30:
		var female := rng.randf() < 0.5
		var spec: Dictionary = Population.random_look(female, [outfits[rng.randi() % outfits.size()]])
		var fig := Humanoid.new()
		var age := rng.randi_range(7, 82)
		fig.set_look(LookBuilder.build(spec, age, "mulher" if female else "homem"))
		add_child(fig)
		var node := Vector2i(rng.randi_range(0, Layout.GRID), rng.randi_range(0, Layout.GRID))
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := Layout._node_pos(node) + Vector2(5.9 * side, 5.9 * side)
		fig.position = Vector3(p.x, 0.17, p.y)
		var kind := "walk"
		var spd := rng.randf_range(1.05, 1.5) * float(HumanMotion.profile(age)["walk"])
		if i % 9 == 0:
			kind = "jog"
			spd = rng.randf_range(3.0, 3.6) * float(HumanMotion.profile(age)["run"])
		peds.append({"fig": fig, "node": node, "side": side, "target": p, "speed": spd, "kind": kind, "night": rng.randf() < 0.3, "wait": 0.0, "cur": spd})
		if Layout.urban_prototype_enabled and i < 4 and layout.prototype_cell.x >= 0:
			# Redistribui quatro dos mesmos 30 pedestres, sem população paralela.
			var r := Layout.block_rect(layout.prototype_cell)
			var route := PackedVector2Array([r.position + Vector2(1.3, 1.3), Vector2(r.end.x - 1.3, r.position.y + 1.3), r.end - Vector2(1.3, 1.3), Vector2(r.position.x + 1.3, r.end.y - 1.3)])
			var entry: Dictionary = peds.back()
			entry["route"] = route
			entry["route_i"] = i
			entry["target"] = route[(i + 1) % 4]
			entry["night"] = i < 2
			entry["kind"] = "walk"
			entry["speed"] = 1.2 * float(HumanMotion.profile(age)["walk"])
			entry["cur"] = entry["speed"]
			fig.position = Vector3(route[i].x, 0.19, route[i].y)
		if staged:
			if progress.is_valid():
				progress.call("Preparando a vida nas ruas… %d de 30" % (i + 1))
			await get_tree().process_frame


func _update_peds(delta: float, night: bool, raining: bool) -> void:
	for e in peds:
		var fig: Humanoid = e["fig"]
		if e.has("physical") and e["physical"].blocked(): continue
		var fp := Vector2(fig.position.x, fig.position.z)
		var near := fp.distance_to(player_pos) < 42.0
		fig.set_active(near and (not night or bool(e["night"])))
		fig.set_lod(fp.distance_to(player_pos) < 20.0)
		if not fig.visible:
			# longe da câmera: só segue o caminho de forma barata
			var tg: Vector2 = e["target"]
			var dd := tg - fp
			if dd.length() < 0.3:
				e["wait"] = 0.0
				_next_ped_target(e)
			else:
				var st2 := dd.normalized() * minf(float(e["speed"]) * delta, dd.length())
				fig.position.x += st2.x
				fig.position.z += st2.y
			continue
		if float(e["wait"]) > 0.0:
			e["wait"] = float(e["wait"]) - delta
			e["cur"] = 0.0
			if fp.distance_to(player_pos) < 6.0:
				fig.look_target = Vector3(player_pos.x, 1.55, player_pos.y)
			else:
				fig.look_target = Vector3.INF
			continue
		fig.look_target = Vector3.INF
		var tgt: Vector2 = e["target"]
		var d := tgt - fp
		if d.length() < 0.3:
			_next_ped_target(e)
			if rng.randf() < 0.3 and e["kind"] == "walk":
				e["wait"] = rng.randf_range(2.0, 8.0)
			continue
		var want: float = float(e["speed"]) * (1.35 if raining else 1.0)
		fig.set_umbrella(raining and e["kind"] == "walk" and (int(e.get("u", -1)) if e.has("u") else _set_u(e)) == 1)
		fig.hunched = raining
		e["cur"] = move_toward(float(e["cur"]), want, 3.5 * delta)
		var step := d.normalized() * minf(float(e["cur"]) * delta, d.length())
		fig.position.x += step.x
		fig.position.z += step.y
		fig.rotation.y = lerp_angle(fig.rotation.y, atan2(step.x, step.y), minf(delta * 6.0, 1.0))


func _next_ped_target(e: Dictionary) -> void:
	if e.has("route"):
		e["route_i"] = (int(e["route_i"]) + 1) % 4
		e["target"] = e["route"][(int(e["route_i"]) + 1) % 4]
		return
	var node: Vector2i = e["node"]
	var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var nb: Vector2i = node + dirs[rng.randi() % 4]
	if not layout.street_nodes.has(nb):
		nb = node
	e["node"] = nb
	e["target"] = Layout._node_pos(nb) + Vector2(5.9, 5.9) * float(e["side"])


func _set_u(e: Dictionary) -> int:
	e["u"] = 1 if rng.randf() < 0.75 else 0
	return int(e["u"])


# ---------- cachorros ----------

func _dog() -> Node3D:
	# vira-lata modelado (corpo contínuo, focinho, orelhas, patas) com pelagem de verdade
	return AnimalMesh.dog(rng)


func _part(parent: Node3D, kind: String, pos: Vector3, scale3: Vector3, material: Material, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	match kind:
		"sphere":
			mi.mesh = Toon._sphere_mesh()
		"cyl":
			var c := CylinderMesh.new()
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 1.0
			c.radial_segments = 8
			mi.mesh = c
		_:
			mi.mesh = Toon._box_mesh()
	mi.material_override = material
	mi.position = pos
	mi.scale = scale3
	mi.rotation = rot
	parent.add_child(mi)


func _make_dogs() -> void:
	for i in 5:
		var d := _dog()
		add_child(d)
		var node := Vector2i(rng.randi_range(0, Layout.GRID), rng.randi_range(0, Layout.GRID))
		var p := Layout._node_pos(node) + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
		d.position = Vector3(p.x, 0.17, p.y)
		var bark := Label3D.new()
		bark.text = "au!"
		bark.font_size = 48
		bark.pixel_size = 0.006
		bark.outline_size = 10
		bark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bark.no_depth_test = true
		bark.position = Vector3(0, 1.2, 0)
		bark.visible = false
		d.add_child(bark)
		dogs.append({"node": d, "target": p, "state": "idle", "wait": rng.randf_range(1.0, 5.0), "phase": 0.0, "bark": bark, "bark_t": 0.0, "t": rng.randf() * 10.0})
		if Layout.urban_prototype_enabled and i == 0 and not peds.is_empty() and peds[0].has("route"):
			var e: Dictionary = dogs.back()
			var route: PackedVector2Array = peds[0]["route"]
			e["route"] = route
			e["route_i"] = 0
			e["target"] = route[1]
			e["state"] = "go"
			d.position = Vector3(route[0].x + 2.0, 0.19, route[0].y)


func _update_dogs(delta: float) -> void:
	for e in dogs:
		var d: Node3D = e["node"]
		if e.has("physical") and e["physical"].blocked(): continue
		var fp := Vector2(d.position.x, d.position.z)
		var dist_p := fp.distance_to(player_pos)
		d.visible = dist_p < 45.0
		if not d.visible:
			continue
		e["t"] = float(e["t"]) + delta
		var tgt: Vector2 = e["target"]
		var to := tgt - fp
		var speed := 0.0
		if str(e["state"]) == "idle":
			e["wait"] = float(e["wait"]) - delta
			if float(e["wait"]) <= 0.0:
				e["state"] = "go"
				var a := rng.randf() * TAU
				var r := rng.randf_range(3.0, 10.0)
				if e.has("route"):
					_next_ped_target(e)
				else:
					e["target"] = fp + Vector2(cos(a), sin(a)) * r
		else:
			var run: bool = dist_p < 9.0 and dist_p > 2.5
			speed = 3.8 if run else 1.3
			if to.length() < 0.4:
				e["state"] = "idle"
				e["wait"] = rng.randf_range(2.0, 7.0)
				speed = 0.0
			else:
				var step := to.normalized() * speed * delta
				d.position.x += step.x
				d.position.z += step.y
				d.rotation.y = lerp_angle(d.rotation.y, atan2(to.x, to.y), minf(delta * 6.0, 1.0))
		e["phase"] = float(e["phase"]) + delta * (6.0 + speed * 2.4)
		var ph: float = float(e["phase"])
		var mv := clampf(speed / 1.2, 0.0, 1.0)
		for i in 4:
			var leg := d.get_node("leg%d" % i) as Node3D
			var sgn := 1.0 if (i == 0 or i == 3) else -1.0
			leg.rotation.x = sin(ph) * sgn * 0.7 * mv
		var body := d.get_node("body") as Node3D
		body.position.y = absf(sin(ph)) * 0.02 * mv
		var tail := body.get_node("tail") as Node3D
		tail.rotation.z = sin(float(e["t"]) * (14.0 if dist_p < 7.0 else 4.0)) * 0.6
		(body.get_node("head") as Node3D).rotation.x = (0.5 if str(e["state"]) == "idle" and int(float(e["t"]) * 0.3) % 3 == 0 else 0.0)
		var bk: Label3D = e["bark"]
		if dist_p < 7.0 and float(e["bark_t"]) <= 0.0 and rng.randf() < delta * 0.25:
			e["bark_t"] = 1.2
		e["bark_t"] = maxf(0.0, float(e["bark_t"]) - delta)
		bk.visible = float(e["bark_t"]) > 0.0


# ---------- pássaros ----------

func _make_birds() -> void:
	for f in 3:
		var center := Vector2(rng.randf_range(60, Layout.SIZE - 60), rng.randf_range(60, Layout.SIZE - 60))
		for i in 7:
			# pombo: corpo, pescoço iridescente e asas em duas partes
			var b := AnimalMesh.pigeon(rng)
			add_child(b)
			birds.append({"node": b, "c": center, "r": rng.randf_range(14, 26), "h": rng.randf_range(11, 18), "a": rng.randf() * TAU, "w": rng.randf_range(0.35, 0.6) * (1.0 if rng.randf() < 0.5 else -1.0), "t": rng.randf() * 6.0})


func _update_birds(delta: float, night: bool) -> void:
	for e in birds:
		var b: Node3D = e["node"]
		b.visible = not night
		if night:
			continue
		e["a"] = float(e["a"]) + float(e["w"]) * delta
		e["t"] = float(e["t"]) + delta * 9.0
		var a: float = e["a"]
		var c: Vector2 = e["c"]
		var r: float = e["r"]
		b.position = Vector3(c.x + cos(a) * r, float(e["h"]) + sin(a * 2.0) * 0.8, c.y + sin(a) * r)
		var tang := Vector3(-sin(a) * signf(float(e["w"])), 0, cos(a) * signf(float(e["w"])))
		b.rotation.y = atan2(tang.x, tang.z)
		(b.get_node("pl") as Node3D).rotation.z = sin(float(e["t"])) * 0.7
		(b.get_node("pr") as Node3D).rotation.z = -sin(float(e["t"])) * 0.7


func update(delta: float, pp: Vector2, night: bool, raining: bool) -> void:
	player_pos = pp
	_stream_people(pp)
	_update_cars(delta, night)
	_update_peds(delta, night, raining)
	_update_dogs(delta)
	_update_birds(delta, night)
	for entry in peds:
		entry["physical"].resolve(delta, entry["fig"].visible and entry["fig"].position.distance_squared_to(Vector3(pp.x, 0, pp.y)) < 2304)
	for entry in dogs:
		entry["physical"].resolve(delta, entry["node"].visible)
		var physical: RefCounted = entry["physical"]
		(entry["node"].get_node("body") as Node3D).rotation.z = lerpf(0, 1.3, clampf(1 - physical.remaining / maxf(physical.duration, 0.001), 0, 1)) if physical.blocked() else 0
	for entry in birds:
		# O voo permanece atravessável. Um pombo no solo participa da física.
		var grounded: bool = entry["node"].position.y < 0.45
		entry["physical"].resolve(delta, grounded)


# O mesmo conjunto de pedestres ambientes acompanha a região; a população
# persistente, os diálogos e as rotinas do NPCManager permanecem nos autoloads.
func _stream_people(pp: Vector2) -> void:
	var center := Layout.chunk_at(pp)
	if center == _stream_center:
		return
	_stream_center = center
	if Rect2(Vector2.ZERO, Vector2.ONE * Layout.SIZE).has_point(pp):
		return
	var nearest := Vector2i(floori((pp.x - 10.0) / 40.0), floori((pp.y - 10.0) / 40.0))
	var wanted: Array[Vector2i] = []
	for x in range(nearest.x - 2, nearest.x + 3):
		for y in range(nearest.y - 2, nearest.y + 3):
			var cell := Vector2i(x, y)
			if layout.blocks.has(cell) and Layout.block_rect(cell).get_center().distance_to(pp) < 95.0 and layout.blocks[cell].get("kind", "") != "aeroporto_area":
				wanted.append(cell)
	wanted.sort_custom(func(a, b): return Layout.block_rect(a).get_center().distance_squared_to(pp) < Layout.block_rect(b).get_center().distance_squared_to(pp))
	var covered := {}
	for entry in peds:
		if entry.has("stream_cell") and entry["stream_cell"] in wanted:
			covered[entry["stream_cell"]] = true
	for cell in wanted:
		if covered.has(cell):
			continue
		for entry in peds:
			if entry.get("stream_cell", Vector2i(2147483647, 0)) in wanted:
				continue
			var fig: Node3D = entry["fig"]
			if Vector2(fig.position.x, fig.position.z).distance_to(pp) < 65.0:
				continue
			var rect := Layout.block_rect(cell).grow(-1.2)
			var route := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
			var offset := absi(layout.seed_chunk(Layout.chunk_at(rect.get_center()), "ped:%d:%d" % [cell.x, cell.y])) % 4
			entry["stream_cell"] = cell
			entry["route"] = route
			entry["route_i"] = offset
			entry["target"] = route[(offset + 1) % 4]
			entry["night"] = true
			entry["kind"] = "walk"
			fig.position = Vector3(route[offset].x, 0.17, route[offset].y)
			covered[cell] = true
			break
	for index in cars.size():
		var entry: Dictionary = cars[index]
		if entry.has("tram_route"):
			continue
		var point: Vector2 = entry["pos"]
		if point.distance_to(pp) < 350.0:
			continue
		var node := Vector2i(nearest.x + index % 5 - 2, nearest.y + index / 5 - 2)
		if not layout.street_nodes.has(node):
			continue
		var dir := Vector2i.RIGHT if index % 2 == 0 else Vector2i.DOWN
		point = Layout._node_pos(node) + _right(dir) * 1.8
		entry["pos"] = point
		entry["dir"] = dir
		entry["next"] = node + dir
		entry["yaw"] = atan2(dir.x, dir.y)
		entry["targets"] = [_approach(node + dir, dir)]


func update_slow(night: bool) -> void:
	_assign_headlights(night)
