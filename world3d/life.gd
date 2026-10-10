extends Node3D

# Vida da cidade: carros que seguem as ruas e viram nas esquinas (freiam para pessoas e outros
# carros), pedestres de vários tipos, cachorros e pássaros. Só decoração viva: não altera a
# simulação do jogo.

const Layout = preload("res://world3d/city_layout.gd")
const Humanoid = preload("res://world3d/person.gd")
const Toon = preload("res://world3d/humanoid.gd")
const Kit = preload("res://world3d/mesh_kit.gd")
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


func setup(l: Layout, c: Node3D, with_people: bool = true, staged: bool = false, progress: Callable = Callable()) -> void:
	layout = l
	city = c
	rng.seed = 5511
	_make_cars()
	if with_people:
		await _make_peds(staged, progress)
		_make_dogs()
	_make_birds()
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
		3:   # táxi
			k.box(Vector3(0, 0.65, 0), Vector3(1.8, 0.7, 4.2), Color("#e8c21c"))
			k.box(Vector3(0, 1.25, -0.2), Vector3(1.6, 0.6, 2.2), Color("#e8c21c").lightened(0.06))
			k.box(Vector3(0, 1.25, -0.2), Vector3(1.64, 0.45, 2.0), dark)
			k.box(Vector3(0, 1.65, -0.2), Vector3(0.6, 0.18, 0.28), Color("#f4f0d0"))
		_:   # sedã
			k.box(Vector3(0, 0.65, 0), Vector3(1.8, 0.7, 4.2), col)
			k.box(Vector3(0, 1.25, -0.2), Vector3(1.6, 0.6, 2.2), col.lightened(0.1))
			k.box(Vector3(0, 1.25, -0.2), Vector3(1.64, 0.45, 2.0), dark)
	var wl: float = 1.35 if kind != 2 else 1.5
	for wx in [-0.88, 0.88]:
		for wz in [-wl, wl]:
			k.add("cyl", Transform3D(Basis(Vector3.FORWARD, PI / 2.0).scaled(Vector3(0.7, 0.3, 0.7)), Vector3(wx, 0.35, wz)), tire)
	k.box(Vector3(0, 0.55, 2.12 if kind != 2 else 2.22), Vector3(1.7, 0.1, 0.08), Color("#2a2a2a"))
	return k


func _make_cars() -> void:
	var mat := Kit.vertex_material(0.5)
	var colors := [Color("#b9bcc0"), Color("#8b1e1e"), Color("#1f3d6b"), Color("#e8e6df"), Color("#2b2d31"), Color("#3b6b3a"), Color("#6b4a2e"), Color("#7a7d80")]
	for i in 18:
		var kind: int = [0, 0, 0, 1, 1, 2, 3, 3][rng.randi() % 8]
		var col: Color = colors[rng.randi() % colors.size()]
		var car := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = _car_kit(kind, col).commit(mat)
		car.add_child(mi)
		var lights := Kit.new()
		lights.box(Vector3(-0.58, 0.78, 2.12), Vector3(0.4, 0.18, 0.06), Color.WHITE)
		lights.box(Vector3(0.58, 0.78, 2.12), Vector3(0.4, 0.18, 0.06), Color.WHITE)
		var li := MeshInstance3D.new()
		li.mesh = lights.commit(city.lit_mat)
		car.add_child(li)
		var tail := Kit.new()
		tail.box(Vector3(-0.6, 0.8, -2.12), Vector3(0.4, 0.16, 0.06), Color("#c01c1c"))
		tail.box(Vector3(0.6, 0.8, -2.12), Vector3(0.4, 0.16, 0.06), Color("#c01c1c"))
		var ti := MeshInstance3D.new()
		ti.mesh = tail.commit(Kit.vertex_material())
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
		if nn.x >= 0 and nn.y >= 0 and nn.x <= Layout.GRID and nn.y <= Layout.GRID:
			options.append(nd)
			if nd == d:
				options.append(nd)
				options.append(nd)
	if options.is_empty():
		return Vector2i(-d.x, -d.y)
	return options[rng.randi() % options.size()]


func _update_cars(delta: float, night: bool) -> void:
	for e in cars:
		var car: Node3D = e["node"]
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
		if dist > 0.01:
			var dirv := to / dist
			pos += dirv * step
			e["yaw"] = lerp_angle(float(e["yaw"]), atan2(dirv.x, dirv.y), minf(delta * (3.0 + float(e["speed"]) * 0.35), 1.0))
		e["pos"] = pos
		car.position = Vector3(pos.x, 0.14, pos.y)
		car.rotation.y = float(e["yaw"])
		if dist < 0.6:
			tgts.pop_front()
			if tgts.is_empty():
				var d: Vector2i = e["dir"]
				var node: Vector2i = e["next"]
				var d2 := _pick_dir(node, d)
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
			l.global_rotation = car.global_rotation + Vector3(-0.12, 0, 0)


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
		if staged:
			if progress.is_valid():
				progress.call("Preparando a vida nas ruas… %d de 30" % (i + 1))
			await get_tree().process_frame


func _update_peds(delta: float, night: bool, raining: bool) -> void:
	for e in peds:
		var fig: Humanoid = e["fig"]
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
				var node2: Vector2i = e["node"]
				var dirs2: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
				var nb2: Vector2i = node2 + dirs2[rng.randi() % 4]
				nb2 = Vector2i(clampi(nb2.x, 0, Layout.GRID), clampi(nb2.y, 0, Layout.GRID))
				e["node"] = nb2
				e["target"] = Layout._node_pos(nb2) + Vector2(5.9, 5.9) * float(e["side"])
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
			var node: Vector2i = e["node"]
			var dirs: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
			var nb: Vector2i = node + dirs[rng.randi() % 4]
			nb = Vector2i(clampi(nb.x, 0, Layout.GRID), clampi(nb.y, 0, Layout.GRID))
			e["node"] = nb
			var side: float = e["side"]
			e["target"] = Layout._node_pos(nb) + Vector2(5.9 * side, 5.9 * side)
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


func _set_u(e: Dictionary) -> int:
	e["u"] = 1 if rng.randf() < 0.75 else 0
	return int(e["u"])


# ---------- cachorros ----------

func _dog() -> Node3D:
	var root := Node3D.new()
	var col := Color(["#8a6a45", "#2b2420", "#d8cdb8", "#a8794a", "#5a5a5e"][rng.randi() % 5])
	var m := Toon.mat(col)
	var m2 := Toon.mat(col.darkened(0.25))
	var body := Node3D.new()
	body.name = "body"
	root.add_child(body)
	_part(body, "sphere", Vector3(0, 0.42, 0), Vector3(0.34, 0.3, 0.8), m)
	_part(body, "sphere", Vector3(0, 0.5, 0.33), Vector3(0.3, 0.3, 0.3), m)
	var head := Node3D.new()
	head.name = "head"
	head.position = Vector3(0, 0.62, 0.52)
	body.add_child(head)
	_part(head, "sphere", Vector3(0, 0, 0), Vector3(0.24, 0.22, 0.26), m)
	_part(head, "sphere", Vector3(0, -0.04, 0.16), Vector3(0.14, 0.11, 0.18), m2)
	_part(head, "sphere", Vector3(0, -0.02, 0.25), Vector3(0.05, 0.04, 0.04), Toon.mat(Color("#111111")))
	for sx in [-1, 1]:
		_part(head, "sphere", Vector3(sx * 0.1, 0.1, -0.03), Vector3(0.07, 0.14, 0.1), m2, Vector3(0, 0, sx * 0.4))
		_part(head, "sphere", Vector3(sx * 0.06, 0.04, 0.11), Vector3(0.035, 0.035, 0.02), Toon.mat_plain(Color("#111111")))
	var tail := Node3D.new()
	tail.name = "tail"
	tail.position = Vector3(0, 0.5, -0.38)
	body.add_child(tail)
	_part(tail, "cyl", Vector3(0, 0.1, -0.05), Vector3(0.05, 0.28, 0.05), m, Vector3(0.9, 0, 0))
	for i in 4:
		var leg := Node3D.new()
		leg.name = "leg%d" % i
		leg.position = Vector3((-1 if i % 2 == 0 else 1) * 0.11, 0.3, 0.3 if i < 2 else -0.28)
		root.add_child(leg)
		_part(leg, "cyl", Vector3(0, -0.14, 0), Vector3(0.07, 0.3, 0.07), m)
		_part(leg, "sphere", Vector3(0, -0.29, 0.02), Vector3(0.09, 0.05, 0.12), m2)
	return root


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


func _update_dogs(delta: float) -> void:
	for e in dogs:
		var d: Node3D = e["node"]
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
			var b := Node3D.new()
			var wl := MeshInstance3D.new()
			wl.name = "wl"
			var wr := MeshInstance3D.new()
			wr.name = "wr"
			var wm := BoxMesh.new()
			var bmat := StandardMaterial3D.new()
			bmat.albedo_color = Color("#2b2b2e")
			bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			wm.material = bmat
			wl.mesh = wm
			wr.mesh = wm
			wl.scale = Vector3(0.55, 0.03, 0.22)
			wr.scale = Vector3(0.55, 0.03, 0.22)
			var pl := Node3D.new()
			pl.name = "pl"
			var pr := Node3D.new()
			pr.name = "pr"
			b.add_child(pl)
			b.add_child(pr)
			pl.add_child(wl)
			pr.add_child(wr)
			wl.position = Vector3(-0.28, 0, 0)
			wr.position = Vector3(0.28, 0, 0)
			var bd := MeshInstance3D.new()
			var bs := SphereMesh.new()
			bs.radius = 0.1
			bs.height = 0.2
			bs.material = bmat
			bd.mesh = bs
			bd.scale = Vector3(0.8, 0.7, 1.6)
			b.add_child(bd)
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
	_update_cars(delta, night)
	_update_peds(delta, night, raining)
	_update_dogs(delta)
	_update_birds(delta, night)


func update_slow(night: bool) -> void:
	_assign_headlights(night)
