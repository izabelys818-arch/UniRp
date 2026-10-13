extends RefCounted

# Gera uma casa de bairro completa: fachada com janelas, porta, varanda, telhado, quintal com
# cerca e árvores; e (sob demanda, quando o jogador chega perto) o interior com cômodos,
# paredes internas, portas e móveis. Tudo no espaço local da casa: x = largura, z = profundidade,
# a frente fica em +z. O nó raiz é girado em 180° quando a casa olha para o norte.

const Kit = preload("res://world3d/mesh_kit.gd")
const Flora = preload("res://world3d/flora.gd")
const Furn = preload("res://world3d/furn_lib.gd")
const Art = preload("res://world3d/art_style.gd")
const Interiors = preload("res://world3d/interior_builder.gd")

const Y0 := 0.17
const H := 2.9
const T := 0.28
const CUT_H := 0.75

const WALLS := ["#d9c9a8", "#e8e2d0", "#b7c4b0", "#c9a68a", "#a7b6c4", "#d4b483", "#c98f7a", "#e8d7a8", "#b5b0a0", "#9fb5a8", "#d8c0b0", "#c4cdd6"]
const ROOFS := ["#8a3b2c", "#6b4a3a", "#4a4f55", "#7a5b3a", "#5c6b5a", "#3f4650"]
const DOORS := ["#5b3b25", "#2f4f6f", "#7a2e2e", "#3f6b4a", "#d8d2c0", "#6b5a2e"]
const SOFAS := ["#6a4a3a", "#3f5a78", "#7a3a3a", "#4f6b4a", "#8a7a5a", "#55555e"]

var city: Node3D
var rng := RandomNumberGenerator.new()


func _c(h: String) -> Color:
	return Color(h)


func _jit(c: Color, a: float = 0.05) -> Color:
	return Color(clampf(c.r + rng.randf_range(-a, a), 0, 1), clampf(c.g + rng.randf_range(-a, a), 0, 1), clampf(c.b + rng.randf_range(-a, a), 0, 1))


func _style(lot: Dictionary) -> Dictionary:
	var state: Dictionary = Houses.preview_state(lot["id"]) if World.locations[lot["id"]].get("streamed", false) else Houses.st(lot["id"])
	var abandoned: bool = str(state["tipo"]) == "abandonada"
	var w: float = (lot["building"] as Rect2).size.x
	var wall := Art.pick("walls", rng) if rng.randf() < 0.82 else Art.pick("accent_walls", rng)
	var st := {
		"wall": _jit(wall, 0.03),
		"roof": _jit(Art.pick("roofs", rng), 0.025),
		"door": Art.pick("doors", rng),
		"kind": ["gable_x", "gable_z", "hip", "hip"][rng.randi() % 4],
		"porch": rng.randf() < 0.55,
		"garage": w >= 8.6 and rng.randf() < 0.55,
		"chimney": rng.randf() < 0.12,
		"fence": Art.fence_kind(rng),
		"shutters": rng.randf() < 0.3,
		"abandoned": abandoned,
		"wear": Art.wear(rng),
		"tank": rng.randf() < Art.num("tank"),
		"bars": rng.randf() < Art.num("bars"),
		"porch_life": rng.randi() % 4,
	}
	st["trim"] = Art.pick("trims", rng)
	if lot.get("urban", false):
		st["urban"] = true
		st["porch"] = false
		st["garage"] = false
		st["fence"] = "none"
		st["chimney"] = false
		st["tank"] = false
		st["kind"] = "flat" if int(lot.get("floors", 1)) == 3 or absi(int(lot["seed"])) % 2 == 0 else "gable_x"
	if abandoned:
		st["wear"] = maxf(float(st["wear"]), 0.85)
	if abandoned:
		st["wall"] = (st["wall"] as Color).darkened(0.28).lerp(Color("#6e6a5e"), 0.35)
		st["roof"] = (st["roof"] as Color).darkened(0.25)
		st["fence"] = "wood" if rng.randf() < 0.5 else "none"
	return st


# ---------- primitivas locais ----------

func _fb(k: Kit, c: Vector3, size: Vector3, color: Color, yaw: float = 0.0) -> void:
	k.add("box", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(size), c), color)


func _sb(body: StaticBody3D, rect: Rect2, h: float, y: float = 0.0) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(rect.size.x, h, rect.size.y)
	cs.shape = bs
	cs.position = Vector3(rect.get_center().x, y + h / 2.0, rect.get_center().y)
	body.add_child(cs)
	return cs


func _mesh(k: Kit, parent: Node3D, m: Material = null) -> MeshInstance3D:
	k.install_colliders(parent)
	var mesh := k.commit(m if m else city.mat)
	city._add_shadow(k, parent)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)
	return mi


func _tree(k: Kit, p: Vector3, scale: float, kind: int) -> void:
	# copa de folhas reais (Flora + Foliage): 0 frondosa, 1 pinheiro em camadas, 2 palmeira
	var sp: String = ["copa", "conica", "palmeira"][clampi(kind, 0, 2)]
	Flora.tree(k, p, scale, rng, sp, kind == 0)


func _bush(k: Kit, p: Vector3, s: float) -> void:
	var g := Color("#3f6b35").lerp(Color("#6b8f3a"), rng.randf())
	k.sphere(p + Vector3(0, 0.35 * s, 0), Vector3(1.0, 0.8, 1.0) * s, g)
	k.sphere(p + Vector3(0.35 * s, 0.3 * s, 0.1), Vector3(0.8, 0.65, 0.8) * s, g.lightened(0.08))


# ---------- construção ----------

func build(c: Node3D, lot: Dictionary) -> Dictionary:
	city = c
	rng.seed = int(lot["seed"])
	var id: String = lot["id"]
	var b: Rect2 = lot["building"]
	preload("res://world3d/grass_field.gd").exclude_interior(b)
	var north: bool = lot["north"]
	var w := b.size.x
	var d := b.size.y
	var st := _style(lot)
	var dx: float = float(lot["door_off"]) * (-1.0 if north else 1.0)
	var root := Node3D.new()
	root.position = Vector3(b.get_center().x, 0, b.get_center().y)
	root.rotation.y = PI if north else 0.0
	city.add_child(root)
	var body := StaticBody3D.new()
	body.collision_layer = 3
	root.add_child(body)
	var full := Node3D.new()
	var cut := Node3D.new()
	cut.visible = false
	root.add_child(full)
	root.add_child(cut)
	var lit := Node3D.new()
	lit.visible = false
	full.add_child(lit)
	var lr: Rect2 = lot["rect"]
	var cen := b.get_center()
	var local_lot: Rect2
	if north:
		local_lot = Rect2(-(lr.end.x - cen.x), -(lr.end.y - cen.y), lr.size.x, lr.size.y)
	else:
		local_lot = Rect2(lr.position.x - cen.x, lr.position.y - cen.y, lr.size.x, lr.size.y)
	var s := {"rect": b, "full": full, "cut": cut, "loc": id, "cut_now": false, "root": root, "body": body, "interior": null,
		"lit": lit, "lot": lot, "style": st, "w": w, "d": d, "dx": dx, "lr": local_lot, "windows": []}
	s["floor_count"] = int(lot.get("floors", 1))
	s["floor_height"] = H
	city.structures.append(s)
	var ka := Kit.new()
	var kf := Kit.new()
	var kc := Kit.new()
	var kw := Kit.new()
	var kl := Kit.new()
	var kcw := Kit.new()       # vidro das janelas visto de dentro, na versão aberta
	await city.generation_checkpoint()
	# Paredes do fundo da versão aberta: inteiras com o jogador dentro (The Sims), baixas quando
	await city.generation_checkpoint()
	# a casa só está tapando o jogador do lado de fora (Project Zomboid).
	var kb := Kit.new()
	var kbl := Kit.new()
	for kit in [ka, kf, kc, kw, kl, kcw, kb, kbl]:
		await city.generation_checkpoint()
		(kit as Kit).world_xf = root.transform
	kw.vary_glass = true
	kl.vary_lit = true
	kcw.vary_glass = true
	await city.generation_checkpoint()
	# Janelas também dependem do lote, não da ordem global de construção.
	kw._vr.seed = int(lot["seed"]) + 19
	kl._vr.seed = int(lot["seed"]) + 23
	kcw._vr.seed = int(lot["seed"]) + 29
	var wall: Color = st["wall"]
	var trim: Color = st["trim"]
	var x0 := -w / 2.0
	var x1 := w / 2.0
	var z0 := -d / 2.0
	var z1 := d / 2.0
	var door_w := 1.05
	var gar_w: float = 3.2 if st["garage"] else 0.0
	await city.generation_checkpoint()
	# --- quintal ---
	var urban: bool = lot.get("urban", false)
	var yard_c := (Color("#5a7a3f") if not st["abandoned"] else Color("#6f7a45")).lerp(Color("#4a6438"), rng.randf() * 0.5)
	if urban:
		yard_c = Art.col("sidewalk").lerp(Color("#897d69"), 0.25)
	ka.box_ab(Vector3(local_lot.position.x, Y0, local_lot.position.y), Vector3(local_lot.end.x, Y0 + 0.02, local_lot.end.y), yard_c)
	for i in rng.randi_range(2, 5):
		await city.generation_checkpoint()
		var px := rng.randf_range(local_lot.position.x + 1, local_lot.end.x - 1)
		var pz := rng.randf_range(local_lot.position.y + 1, local_lot.end.y - 1)
		if absf(px) < w / 2.0 + 0.5 and absf(pz) < d / 2.0 + 0.5:
			continue
		ka.box_ab(Vector3(px - 0.9, Y0 + 0.02, pz - 0.7), Vector3(px + 0.9, Y0 + 0.03, pz + 0.7), Color("#6e5d45") if rng.randf() < 0.6 else yard_c.lightened(0.1))
	await city.generation_checkpoint()
	# calçada de entrada e garagem
	var front_z: float = local_lot.end.y
	ka.box_ab(Vector3(dx - 0.6, Y0 + 0.02, z1), Vector3(dx + 0.6, Y0 + 0.04, front_z), Color("#a8a397"))
	var drive_x := 0.0
	if st["garage"]:
		drive_x = x0 + gar_w / 2.0 + 0.2
		ka.box_ab(Vector3(drive_x - 1.5, Y0 + 0.02, z1), Vector3(drive_x + 1.5, Y0 + 0.04, front_z), Color("#8d8a82"))
		var drive_len := front_z - z1
		if rng.randf() < 0.55 and drive_len >= 5.2:
			# de frente para a rua, com folga até a parede e até o portão
			city._car(ka, Vector3(drive_x, Y0 + 0.04, z1 + drive_len * 0.5), 0.0, city._car_color())
	await city.generation_checkpoint()
	# --- fundação e piso ---
	var fc2 := Color("#9a968c")
	ka.box_ab(Vector3(x0 - 0.08, Y0, z0 - 0.08), Vector3(x1 + 0.08, Y0 + 0.5, z0 + T), fc2)
	ka.box_ab(Vector3(x0 - 0.08, Y0, z1 - T), Vector3(x1 + 0.08, Y0 + 0.5, z1 + 0.08), fc2)
	ka.box_ab(Vector3(x0 - 0.08, Y0, z0), Vector3(x0 + T, Y0 + 0.5, z1), fc2)
	ka.box_ab(Vector3(x1 - T, Y0, z0), Vector3(x1 + 0.08, Y0 + 0.5, z1), fc2)
	ka.box_ab(Vector3(x0, Y0, z0), Vector3(x1, Y0 + 0.06, z1), Color("#7a6248"))
	var wins: Array = []
	var wx := x0 + 1.5
	while wx < x1 - 1.0:
		var in_garage: bool = st["garage"] and wx < x0 + gar_w + 0.8
		if absf(wx - dx) > 1.7 and not in_garage:
			wins.append([Vector3(wx, 0, z1), 0.0])
		wx += 2.7
	var wz := z0 + 1.4
	while wz < z1 - 1.0:
		wins.append([Vector3(x1, 0, wz), PI / 2.0])
		wins.append([Vector3(x0, 0, wz), -PI / 2.0])
		wz += 2.8
	wx = x0 + 1.6
	while wx < x1 - 1.0:
		wins.append([Vector3(wx, 0, z0), PI])
		wx += 2.9
	var holes: Array = []
	for wn in wins:
		await city.generation_checkpoint()
		var p: Vector3 = wn[0]
		holes.append({"center": p + Vector3.UP * (Y0 + 1.55), "size": Vector2(1.12, 1.22), "along_x": absf(sin(float(wn[1]))) < 0.1})
	for floor in range(1, int(s["floor_count"])):
		await city.generation_checkpoint()
		for wn in wins:
			var p: Vector3 = wn[0]
			holes.append({"center": p + Vector3.UP * (Y0 + 1.55 + floor * H), "size": Vector2(1.12, 1.22), "along_x": absf(sin(float(wn[1]))) < 0.1})
	s["window_holes"] = holes
	await city.generation_checkpoint()
	# --- paredes (inteiras e cortadas) com vão da porta ---
	var gap0 := dx - door_w / 2.0
	var gap1 := dx + door_w / 2.0
	await city.generation_checkpoint()
	# Versão aberta (jogador dentro): como no The Sims, só as paredes viradas para a câmera e o
	await city.generation_checkpoint()
	# telhado baixam; as do fundo continuam inteiras. Câmera fica do lado +x/+z do mundo; a casa do
	await city.generation_checkpoint()
	# lado norte da rua está girada 180°, então o "fundo" dela são as paredes z1/x1 locais.
	var high := Y0 + H
	var low := Y0 + CUT_H
	await city.generation_checkpoint()
	# Na versão aberta, tudo que passa da altura baixa é parede do fundo: vai inteiro para kb e
	await city.generation_checkpoint()
	# cortado na altura baixa para kbl.
	var open_box := func(a: Vector3, b2: Vector3, c: Color) -> void:
		if b2.y <= low + 0.001:
			kc.box_ab(a, b2, c)
			return
		kb.box_ab(a, b2, c)
		if a.y < low:
			kbl.box_ab(a, Vector3(b2.x, low, b2.z), c)
	for g in [[kf, true], [kc, false]]:
		await city.generation_checkpoint()
		var k: Kit = g[0]
		var whole: bool = g[1]
		var put: Callable = Callable(k, "box_ab") if whole else open_box
		var t_z0: float = high if (whole or not north) else low
		var t_z1: float = high if (whole or north) else low
		var t_x0: float = high if (whole or not north) else low
		var t_x1: float = high if (whole or north) else low
		await Interiors.wall_openings(put, Vector3(x0, Y0, z0), Vector3(x1, t_z0, z0 + T), wall, holes, city.generation_pause)
		await Interiors.wall_openings(put, Vector3(x0, Y0, z0), Vector3(x0 + T, t_x0, z1), wall, holes, city.generation_pause)
		await Interiors.wall_openings(put, Vector3(x1 - T, Y0, z0), Vector3(x1, t_x1, z1), wall, holes, city.generation_pause)
		await Interiors.wall_openings(put, Vector3(x0, Y0, z1 - T), Vector3(gap0, t_z1, z1), wall, holes, city.generation_pause)
		await Interiors.wall_openings(put, Vector3(gap1, Y0, z1 - T), Vector3(x1, t_z1, z1), wall, holes, city.generation_pause)
		# batentes
		put.call(Vector3(gap0 - 0.07, Y0, z1 - T - 0.02), Vector3(gap0, minf(t_z1, Y0 + 2.2) if t_z1 < high else t_z1, z1 + 0.03), trim)
		put.call(Vector3(gap1, Y0, z1 - T - 0.02), Vector3(gap1 + 0.07, minf(t_z1, Y0 + 2.2) if t_z1 < high else t_z1, z1 + 0.03), trim)
		# cantos: inteiros se encostam numa parede do fundo
		for cx in [x0, x1]:
			for cz in [z0, z1]:
				var tall: bool = whole or (cx == x0 and not north) or (cx == x1 and north) or (cz == z0 and not north) or (cz == z1 and north)
				put.call(Vector3(cx - 0.09, Y0, cz - 0.09), Vector3(cx + 0.09, high if tall else low, cz + 0.09), trim)
	kf.box_ab(Vector3(gap0, Y0 + 2.15, z1 - T), Vector3(gap1, Y0 + H, z1), wall)
	if north:
		open_box.call(Vector3(gap0, Y0 + 2.15, z1 - T), Vector3(gap1, Y0 + H, z1), wall)
	await city.generation_checkpoint()
	# acabamento interno das paredes do fundo (pintura clara e rodapé), visto com a casa aberta
	var lining := wall.lerp(Color("#e6dcc8"), 0.6)
	var base_c := lining.darkened(0.35)
	if not north:
		await Interiors.wall_openings(open_box, Vector3(x0 + T, Y0, z0 + T), Vector3(x1 - T, high - 0.02, z0 + T + 0.02), lining, holes, city.generation_pause)
		open_box.call(Vector3(x0 + T, Y0, z0 + T), Vector3(x1 - T, Y0 + 0.16, z0 + T + 0.045), base_c)
		await Interiors.wall_openings(open_box, Vector3(x0 + T, Y0, z0 + T), Vector3(x0 + T + 0.02, high - 0.02, z1 - T), lining, holes, city.generation_pause)
		open_box.call(Vector3(x0 + T, Y0, z0 + T), Vector3(x0 + T + 0.045, Y0 + 0.16, z1 - T), base_c)
	else:
		for seg in [[x0 + T, gap0], [gap1, x1 - T]]:
			await Interiors.wall_openings(open_box, Vector3(seg[0], Y0, z1 - T - 0.02), Vector3(seg[1], high - 0.02, z1 - T), lining, holes, city.generation_pause)
			open_box.call(Vector3(seg[0], Y0, z1 - T - 0.045), Vector3(seg[1], Y0 + 0.16, z1 - T), base_c)
		await Interiors.wall_openings(open_box, Vector3(gap0, Y0 + 2.2, z1 - T - 0.02), Vector3(gap1, high - 0.02, z1 - T), lining, holes, city.generation_pause)
		await Interiors.wall_openings(open_box, Vector3(x1 - T - 0.02, Y0, z0 + T), Vector3(x1 - T, high - 0.02, z1 - T), lining, holes, city.generation_pause)
		open_box.call(Vector3(x1 - T - 0.045, Y0, z0 + T), Vector3(x1 - T, Y0 + 0.16, z1 - T), base_c)
	_weather(kf, st, x0, x1, z0, z1, gap0, gap1)
	kf.box_ab(Vector3(gap0 - 0.07, Y0 + 2.1, z1 - T - 0.02), Vector3(gap1 + 0.07, Y0 + 2.2, z1 + 0.03), trim)
	await city.generation_checkpoint()
	# friso de topo
	for edge in [Rect2(x0 - 0.1, z0 - 0.1, w + 0.2, 0.4), Rect2(x0 - 0.1, z1 - 0.3, w + 0.2, 0.4), Rect2(x0 - 0.1, z0, 0.4, d), Rect2(x1 - 0.3, z0, 0.4, d)]:
		await city.generation_checkpoint()
		kf.box_ab(Vector3(edge.position.x, Y0 + H - 0.2, edge.position.y), Vector3(edge.end.x, Y0 + H, edge.end.y), trim.darkened(0.05))
	await city.generation_checkpoint()
	# --- janelas ---
	var abandoned: bool = st["abandoned"]
	for wn in wins:
		await city.generation_checkpoint()
		var p: Vector3 = wn[0]
		var yaw: float = wn[1]
		var n := Vector3(sin(yaw), 0, cos(yaw))
		var wc := Vector3(p.x, Y0 + 1.55, p.z) + n * 0.02
		var cm := Basis(Vector3.UP, yaw)
		Interiors.window_frame(kf, {"center": Vector3(p.x, Y0 + 1.55, p.z), "size": Vector2(1.12, 1.22), "along_x": absf(n.x) < 0.1}, trim)
		kw.add("box", Transform3D(cm * Basis.from_scale(Vector3(1.12, 1.22, 0.05)), wc + n * 0.085), Color.WHITE)
		kl.add("box", Transform3D(cm * Basis.from_scale(Vector3(1.06, 1.16, 0.05)), wc + n * 0.1), Color.WHITE)
		kf.add("box", Transform3D(cm * Basis.from_scale(Vector3(0.05, 1.2, 0.07)), wc + n * 0.11), trim)
		kf.add("box", Transform3D(cm * Basis.from_scale(Vector3(1.4, 0.08, 0.26)), wc + n * 0.1 + Vector3(0, -0.78, 0)), trim.darkened(0.08))
		# janela das paredes do fundo vista de dentro (vidro + moldura), com a casa aberta
		var on_back: bool = (not north and (absf(yaw - PI) < 0.01 or absf(yaw + PI / 2.0) < 0.01)) or (north and (absf(yaw) < 0.01 or absf(yaw - PI / 2.0) < 0.01))
		if on_back:
			var wi := wc - n * (T + 0.03)
			kcw.add("box", Transform3D(cm * Basis.from_scale(Vector3(1.06, 1.16, 0.02)), wi), Color.WHITE)
			kb.add("box", Transform3D(cm * Basis.from_scale(Vector3(1.24, 1.34, 0.015)), wi + n * 0.006), trim)
			kb.add("box", Transform3D(cm * Basis.from_scale(Vector3(1.3, 0.06, 0.12)), wi - n * 0.05 + Vector3(0, -0.62, 0)), trim.darkened(0.06))
		if st["bars"] and absf(yaw) < 0.1:
			var bar_c := Color("#2c2d2f") if rng.randf() < 0.7 else Color("#e4e0d6")
			for bi in 6:
				kf.add("box", Transform3D(cm * Basis.from_scale(Vector3(0.025, 1.3, 0.025)), wc + n * 0.17 + cm * Vector3(-0.55 + bi * 0.22, 0, 0)), bar_c)
			for by in [-0.62, 0.62]:
				kf.add("box", Transform3D(cm * Basis.from_scale(Vector3(1.24, 0.04, 0.03)), wc + n * 0.17 + Vector3(0, by, 0)), bar_c)
		if st["shutters"] and absf(yaw) < 0.1:
			for sx in [-1, 1]:
				kf.add("box", Transform3D(cm * Basis.from_scale(Vector3(0.42, 1.45, 0.06)), wc + cm * Vector3(sx * 0.9, 0, 0.12)), (st["door"] as Color).darkened(0.1))
		if (abandoned or (Art.p().get("tarps", false) and float(st["wear"]) > 0.75)) and rng.randf() < 0.6:
			for bi in 3:
				kf.add("box", Transform3D(cm * Basis(Vector3.BACK, rng.randf_range(-0.25, 0.25)).scaled(Vector3(1.5, 0.14, 0.05)), wc + n * 0.14 + Vector3(0, -0.4 + bi * 0.4, 0)), Color("#6a5538"))
		s["windows"].append(wc)
	await city.generation_checkpoint()
	# --- porta ---
	var dc: Color = st["door"]
	var door_closed := Kit.new()
	door_closed.box(Vector3(dx, Y0 + 1.05, z1 - T / 2.0), Vector3(door_w - 0.04, 2.1, 0.07), dc)
	door_closed.box(Vector3(dx, Y0 + 1.55, z1 - T / 2.0 + 0.05), Vector3(0.5, 0.45, 0.02), dc.darkened(0.25))
	door_closed.box(Vector3(dx + door_w / 2.0 - 0.14, Y0 + 1.05, z1 - T / 2.0 + 0.06), Vector3(0.06, 0.06, 0.06), Color("#d9c27a"))
	var door_open := Kit.new()
	var hinge := Vector3(dx - door_w / 2.0 + 0.03, Y0 + 1.05, z1 - 0.1)
	door_open.add("box", Transform3D(Basis(Vector3.UP, -1.35) * Basis.from_scale(Vector3(door_w - 0.06, 2.1, 0.06)), hinge + Basis(Vector3.UP, -1.35) * Vector3((door_w - 0.06) / 2.0, 0, 0)), dc)
	await city.generation_checkpoint()
	# --- varanda ---
	if st["porch"]:
		var pw := 3.0
		ka.box_ab(Vector3(dx - pw / 2.0, Y0, z1), Vector3(dx + pw / 2.0, Y0 + 0.24, z1 + 1.6), Color("#a49f93"))
		ka.box_ab(Vector3(dx - 0.6, Y0, z1 + 1.6), Vector3(dx + 0.6, Y0 + 0.12, z1 + 2.0), Color("#a49f93"))
		for sx in [-1, 1]:
			kf.box(Vector3(dx + sx * (pw / 2.0 - 0.12), Y0 + 1.4, z1 + 1.45), Vector3(0.14, 2.3, 0.14), trim)
		kf.box_ab(Vector3(dx - pw / 2.0 - 0.15, Y0 + 2.5, z1 - 0.1), Vector3(dx + pw / 2.0 + 0.15, Y0 + 2.62, z1 + 1.75), (st["roof"] as Color).darkened(0.05))
		if rng.randf() < 0.5:
			ka.box(Vector3(dx + pw / 2.0 - 0.6, Y0 + 0.5, z1 + 0.6), Vector3(0.7, 0.5, 0.5), Color("#7a5534"))
		ka.box(Vector3(dx, Y0 + 0.26, z1 + 0.55), Vector3(0.8, 0.02, 0.5), Color("#7a3a2a"))
	else:
		ka.box_ab(Vector3(dx - 0.9, Y0, z1), Vector3(dx + 0.9, Y0 + 0.2, z1 + 0.9), Color("#a49f93"))
	var num := Label3D.new()
	num.text = str(lot.get("number", ""))
	num.font_size = 48
	num.pixel_size = 0.005
	num.outline_size = 8
	num.modulate = Color("#fff3d6")
	num.outline_modulate = Color(0.08, 0.06, 0.05)
	num.position = Vector3(dx + door_w / 2.0 + 0.45, Y0 + 1.85, z1 + 0.04)
	full.add_child(num)
	await city.generation_checkpoint()
	# --- garagem ---
	if st["garage"]:
		var gx0 := x0 + 0.5
		var gx1 := x0 + gar_w
		kf.box_ab(Vector3(gx0, Y0, z1), Vector3(gx1, Y0 + 2.3, z1 + 0.06), Color("#e4e0d4"))
		for li in 5:
			kf.box_ab(Vector3(gx0, Y0 + 0.4 + li * 0.42, z1 + 0.06), Vector3(gx1, Y0 + 0.44 + li * 0.42, z1 + 0.09), Color("#b9b5a8"))
	await city.generation_checkpoint()
	# --- telhado ---
	await city.generation_checkpoint()
	# Objetos cotidianos na entrada, com mais plantas no Vale Sereno.
	if not st["abandoned"]:
		ka.box(Vector3(dx + door_w * 0.5, Y0 + 0.01, z1 + 0.32), Vector3(0.8, 0.02, 0.45), Color("#74624b"))
		if rng.randf() < 0.55:
			for shoe in [-0.09, 0.09]:
				ka.box(Vector3(dx + door_w + 0.22 + shoe, Y0 + 0.055, z1 + 0.25), Vector3(0.12, 0.09, 0.25), Color("#4b423b"))
		if Art.id() == "vale_sereno" or rng.randf() < 0.32:
			ka.cyl(Vector3(dx - 0.35, Y0, z1 + 0.25), 0.14, 0.25, Color("#8f563c"))
			ka.sphere(Vector3(dx - 0.35, Y0 + 0.48, z1 + 0.25), Vector3(0.45, 0.55, 0.4), Color("#587343"))
	var rh := 0.85 if urban else clampf(minf(w, d) * 0.4, 1.5, 2.7)
	var roof: Color = st["roof"]
	var ov := 0.15 if urban else 0.55
	var upper := H * (int(lot.get("floors", 1)) - 1)
	if urban:
		await _urban_floors(kf, kw, kl, w, d, int(lot.get("floors", 1)), wall, trim, holes)
	var ctr := Vector3(0, Y0 + H + upper, 0)
	match str(st["kind"]):
		"flat":
			kf.box(ctr + Vector3(0, 0.1, 0), Vector3(w + 0.2, 0.2, d + 0.2), roof)
			for side in [-1, 1]:
				kf.box(ctr + Vector3(0, 0.35, side * (d / 2.0 - 0.1)), Vector3(w, 0.45, 0.2), wall)
				kf.box(ctr + Vector3(side * (w / 2.0 - 0.1), 0.35, 0), Vector3(0.2, 0.45, d), wall)
		"gable_x":
			kf.gable(ctr + Vector3(0, rh / 2.0 - 0.02, 0), Vector3(w + ov * 2.0, rh, d + ov * 2.0), roof, true)
		"gable_z":
			kf.gable(ctr + Vector3(0, rh / 2.0 - 0.02, 0), Vector3(w + ov * 2.0, rh, d + ov * 2.0), roof, false)
		_:
			kf.hip(ctr + Vector3(0, -0.02, 0), w + ov * 2.0, rh, d + ov * 2.0, roof)
	await city.generation_checkpoint()
	# calha
	kf.box_ab(Vector3(x0 - ov, ctr.y - 0.08, z1 + ov - 0.1), Vector3(x1 + ov, ctr.y + 0.06, z1 + ov), Color("#9a9a9a"))
	if st["chimney"]:
		var chx := rng.randf_range(-w * 0.28, w * 0.28)
		kf.box(Vector3(chx, Y0 + H + rh * 0.6, -d * 0.12), Vector3(0.75, rh + 1.2, 0.75), Color("#8a4a3a"))
		kf.box(Vector3(chx, Y0 + H + rh * 0.6 + rh / 2.0 + 0.7, -d * 0.12), Vector3(0.95, 0.14, 0.95), Color("#6a6a6a"))
	if st["tank"]:
		var tx2 := rng.randf_range(-w * 0.22, w * 0.22)
		var tz2 := -d * 0.18
		kf.box(Vector3(tx2, Y0 + H + rh * 0.62, tz2), Vector3(1.3, 0.12, 1.3), Color("#8a8680"))
		kf.cyl(Vector3(tx2, Y0 + H + rh * 0.62 + 0.06, tz2), 0.56, 0.62, Color("#3f6fa8") if not st["abandoned"] else Color("#5a6a7a"))
		kf.cyl(Vector3(tx2, Y0 + H + rh * 0.62 + 0.68, tz2), 0.6, 0.08, Color("#2f5a8a") if not st["abandoned"] else Color("#4a5a6a"))
	if rng.randf() < 0.3:
		kf.cyl(Vector3(w * 0.2, Y0 + H + rh * 0.55, d * 0.15), 0.18, 0.15, Color("#cfcfcf"))
		kf.box(Vector3(w * 0.2, Y0 + H + rh * 0.7, d * 0.15), Vector3(0.9, 0.04, 0.9), Color("#d8d8d8"), 0.3)
	await city.generation_checkpoint()
	# --- extras de quintal ---
	var side_x: float = x1 + 0.9 if rng.randf() < 0.5 else x0 - 0.9
	if not urban and absf(side_x) + 0.4 < local_lot.size.x / 2.0 - 0.2:
		ka.box_ab(Vector3(side_x - 0.4, Y0, z1 - 2.6), Vector3(side_x + 0.4, Y0 + 0.75, z1 - 1.8), Color("#cfd2d6"))
	for i in (0 if urban else rng.randi_range(2, 4)):
		await city.generation_checkpoint()
		_bush(ka, Vector3(rng.randf_range(x0 + 0.5, x1 - 0.5), Y0, z1 + rng.randf_range(0.5, 1.0)), rng.randf_range(0.7, 1.1))
	if not urban and rng.randf() < 0.65:
		var tx: float = local_lot.position.x + rng.randf_range(1.0, 2.0) if rng.randf() < 0.5 else local_lot.end.x - rng.randf_range(1.0, 2.0)
		_tree(ka, Vector3(tx, Y0, z1 + rng.randf_range(1.2, 2.2)), rng.randf_range(0.8, 1.1), rng.randi() % 3)
	for i in (0 if urban else rng.randi_range(1, 3)):
		await city.generation_checkpoint()
		_tree(ka, Vector3(rng.randf_range(local_lot.position.x + 1.2, local_lot.end.x - 1.2), Y0, z0 - rng.randf_range(0.8, 1.4)), rng.randf_range(0.9, 1.3), rng.randi() % 3)
	_porch_life(ka, st, dx, z1, x0, x1, gar_w > 0.0, drive_x)
	if not urban:
		_regional(ka, kf, st, local_lot, x0, x1, z0, z1, dx, rh)
		_street_tree(ka, st, local_lot, dx, drive_x, gar_w > 0.0)
	await city.generation_checkpoint()
	# caixa de correio e lixeiras na calçada
	var mbx := dx + 1.8
	ka.solid_box(Vector3(mbx, Y0 + 0.65, front_z - 0.25), Vector3(0.45, 1.3, 0.3), 4, 0, "correio")
	ka.box(Vector3(mbx, Y0 + 0.55, front_z - 0.25), Vector3(0.08, 1.1, 0.08), Color("#4a3a2a"))
	ka.box(Vector3(mbx, Y0 + 1.15, front_z - 0.25), Vector3(0.45, 0.3, 0.3), Color("#2f4f6f") if rng.randf() < 0.5 else Color("#8a2f2f"))
	if rng.randf() < 0.6:
		for i in rng.randi_range(1, 2):
			ka.solid_box(Vector3(dx - 2.2 + i * 0.6, Y0 + 0.425, front_z - 0.5), Vector3(0.52, 0.85, 0.52), 4, 0, "lixeira")
			ka.cyl(Vector3(dx - 2.2 + i * 0.6, Y0, front_z - 0.5), 0.26, 0.85, Color("#2f6b3f") if i == 0 else Color("#33363a"))
	if not urban and rng.randf() < 0.25:
		ka.box(Vector3(x1 + 0.6, Y0 + 0.35, z0 + 1.0), Vector3(0.25, 0.7, 1.4), Color("#bcbcbc"))
	if not urban and rng.randf() < 0.3:
		# varal nos fundos
		for sx in [-1, 1]:
			ka.box(Vector3(sx * (w / 2.0 - 0.6), Y0 + 0.9, z0 - 1.4), Vector3(0.06, 1.8, 0.06), Color("#6a6a6a"))
		for ci in 5:
			ka.box(Vector3(-w / 2.0 + 1.2 + ci * 0.9, Y0 + 1.5, z0 - 1.4), Vector3(0.4, 0.55, 0.04), Color.from_hsv(rng.randf(), 0.45, 0.9))
	if abandoned:
		for i in 14:
			ka.box(Vector3(rng.randf_range(local_lot.position.x + 1, local_lot.end.x - 1), Y0 + 0.05, rng.randf_range(local_lot.position.y + 1, local_lot.end.y - 1)), Vector3(rng.randf_range(0.2, 0.7), 0.12, rng.randf_range(0.2, 0.6)), Color("#5a4a3a").lerp(Color("#3a5a2a"), rng.randf()), rng.randf() * PI)
	await city.generation_checkpoint()
	# --- cerca ---
	_fence(ka, body, s, local_lot, dx, drive_x, gar_w > 0.0)
	await city.generation_checkpoint()
	# colisão das paredes
	_sb(body, Rect2(x0, z0, w, T), H)
	_sb(body, Rect2(x0, z0, T, d), H)
	_sb(body, Rect2(x1 - T, z0, T, d), H)
	_sb(body, Rect2(x0, z1 - T, gap0 - x0, T), H)
	_sb(body, Rect2(gap1, z1 - T, x1 - gap1, T), H)
	var door_cs := _sb(body, Rect2(gap0, z1 - T, gap1 - gap0, T), H)
	await city.generation_checkpoint()
	# malhas
	_mesh(ka, root)
	_mesh(kf, full)
	_mesh(kc, cut)
	var back := Node3D.new()
	var back_low := Node3D.new()
	back_low.visible = false
	cut.add_child(back)
	cut.add_child(back_low)
	_mesh(kb, back)
	_mesh(kcw, back, city.glass_mat)
	_mesh(kbl, back_low)
	s["cut_back"] = back
	s["cut_back_low"] = back_low
	var opaque := _mesh(kw, full, city.window_mat)
	var lit_mi := _mesh(kl, lit, city.window_lit_mat)
	await city.generation_checkpoint()
	# portas num nó próprio: somem junto com as paredes quando a casa abre para quem está fora
	var doors := Node3D.new()
	root.add_child(doors)
	s["doors"] = doors
	var dc_mi := _mesh(door_closed, doors)
	var do_mi := _mesh(door_open, doors)
	city.loc_info[id] = {"door": door_cs, "door_mesh": dc_mi, "door_open": do_mi, "light": null, "sign": null, "structure": s}
	do_mi.visible = false
	s["lit_mi"] = lit_mi
	s["opaque_windows"] = [opaque, lit]
	await Interiors.install_glass(s, city)
	return s


func _urban_floors(k: Kit, glass: Kit, lit: Kit, w: float, d: float, floors: int, wall: Color, trim: Color, holes: Array) -> void:
	for floor in range(1, floors):
		var y := Y0 + floor * H
		for edge in [Rect2(-w / 2, -d / 2, w, T), Rect2(-w / 2, -d / 2, T, d), Rect2(w / 2 - T, -d / 2, T, d), Rect2(-w / 2, d / 2 - T, w, T)]:
			await Interiors.wall_openings(Callable(k, "box_ab"), Vector3(edge.position.x, y, edge.position.y), Vector3(edge.end.x, y + H, edge.end.y), wall, holes, city.generation_pause)
		k.box(Vector3(0, y, d / 2 + 0.06), Vector3(w + 0.1, 0.14, 0.16), trim.darkened(0.1))
		for hole in holes:
			var p: Vector3 = hole["center"]
			if p.y < y or p.y >= y + H:
				continue
			Interiors.window_frame(k, hole, trim)
			glass.box(p, Vector3(1.12, 1.22, 0.02) if hole["along_x"] else Vector3(0.02, 1.22, 1.12), Color.WHITE)


func _fence(k: Kit, body: StaticBody3D, s: Dictionary, lr: Rect2, dx: float, drive_x: float, garage: bool) -> void:
	var kind: String = s["style"]["fence"]
	if kind == "none":
		return
	var inset := 0.18
	var r := lr.grow(-inset)
	var col := Color("#d8d0bc") if kind == "wood" else (Color("#7a7a7e") if kind == "chain" else (Color("#c8bfae") if kind == "wall" else Color("#3f6b35")))
	if kind == "muro":
		col = (s["style"]["wall"] as Color).lerp(Color("#bdb5a5"), 0.45).darkened(0.05)
	if s["style"]["abandoned"]:
		col = col.darkened(0.3)
	var hgt: float = 1.1 if kind in ["wood", "wall"] else (1.25 if kind == "chain" else (1.75 if kind == "muro" else 0.95))
	if kind == "muro":
		_gates(k, s, r, dx, drive_x, garage)
	# segmentos: [início, fim] em x ou z; frente com portão
	var segs: Array = []
	segs.append([Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y)])   # fundos
	segs.append([Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y)])   # esquerda
	segs.append([Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y)])             # direita
	var gate_a := dx - 0.95
	var gate_b := dx + 0.95
	var fz := r.end.y
	var front: Array = [[r.position.x, gate_a]]
	if garage:
		front = [[r.position.x, drive_x - 1.7], [drive_x + 1.7, gate_a]] if drive_x + 1.7 < gate_a else [[r.position.x, drive_x - 1.7]]
	front.append([gate_b, r.end.x])
	for f in front:
		if float(f[1]) - float(f[0]) > 0.3:
			segs.append([Vector2(f[0], fz), Vector2(f[1], fz)])
	for sg in segs:
		var a: Vector2 = sg[0]
		var b: Vector2 = sg[1]
		var len := a.distance_to(b)
		if len < 0.2:
			continue
		var dir := (b - a) / len
		var yaw := atan2(dir.x, dir.y) + PI / 2.0
		var mid := (a + b) / 2.0
		var front_seg: bool = absf(a.y - fz) < 0.01 and absf(b.y - fz) < 0.01
		match kind:
			"wood":
				k.add("box", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(len, hgt * (0.55 if front_seg else 1.0), 0.06)), Vector3(mid.x, Y0 + hgt * (0.55 if front_seg else 1.0) / 2.0, mid.y)), col)
				var n := int(len / 1.0)
				for i in n + 1:
					var pp := a + dir * (len * float(i) / maxf(n, 1))
					k.box(Vector3(pp.x, Y0 + hgt * (0.6 if front_seg else 1.0) / 2.0 + 0.05, pp.y), Vector3(0.12, hgt * (0.6 if front_seg else 1.0) + 0.1, 0.12), col.darkened(0.12))
			"chain":
				var n2 := int(len / 2.0)
				for i in n2 + 1:
					var pp2 := a + dir * (len * float(i) / maxf(n2, 1))
					k.box(Vector3(pp2.x, Y0 + hgt / 2.0, pp2.y), Vector3(0.07, hgt, 0.07), col)
				k.add("box", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(len, 0.05, 0.05)), Vector3(mid.x, Y0 + hgt, mid.y)), col)
				k.add("box", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(len, 0.04, 0.04)), Vector3(mid.x, Y0 + 0.15, mid.y)), col)
				k.add("box", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(len, hgt * 0.8, 0.015)), Vector3(mid.x, Y0 + hgt * 0.55, mid.y)), Color(col, 1.0).lightened(0.25))
			"wall":
				var wh := hgt * (0.7 if front_seg else 1.0)
				k.add("box", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(len, wh, 0.22)), Vector3(mid.x, Y0 + wh / 2.0, mid.y)), col)
				k.add("box", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(len, 0.08, 0.3)), Vector3(mid.x, Y0 + wh, mid.y)), col.darkened(0.12))
			"muro":
				var mh := 1.45 if front_seg else 1.8
				var wcol := col.darkened(0.06 * float(s["style"]["wear"]))
				k.add("box", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(len, mh, 0.18)), Vector3(mid.x, Y0 + mh / 2.0, mid.y)), wcol)
				k.add("box", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(len + 0.04, 0.07, 0.26)), Vector3(mid.x, Y0 + mh, mid.y)), wcol.lightened(0.12))
				k.add("box", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(len + 0.02, 0.32, 0.2)), Vector3(mid.x, Y0 + 0.16, mid.y)), wcol.darkened(0.22))
				var np := int(len / 3.0)
				for i in range(1, np + 1):
					var pp4 := a + dir * (len * float(i) / float(np + 1))
					k.box(Vector3(pp4.x, Y0 + mh / 2.0, pp4.y), Vector3(0.26, mh + 0.05, 0.26), wcol.lightened(0.05))
				if float(s["style"]["wear"]) > 0.55 and rng.randf() < 0.5:
					var sp := a + dir * len * rng.randf_range(0.2, 0.8)
					k.add("box", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(rng.randf_range(0.6, 1.4), rng.randf_range(0.4, 0.9), 0.2)), Vector3(sp.x, Y0 + rng.randf_range(0.4, 1.1), sp.y)), wcol.darkened(0.18))
			"hedge":
				var n3 := int(len / 0.75)
				for i in n3 + 1:
					var pp3 := a + dir * (len * float(i) / maxf(n3, 1))
					k.sphere(Vector3(pp3.x, Y0 + hgt * 0.5, pp3.y), Vector3(1.0, hgt, 1.0), col.lerp(Color("#5a8a3a"), rng.randf() * 0.5))
		# colisão
		var horiz := absf(dir.x) > 0.5
		var cr := Rect2(mid.x - (len / 2.0 if horiz else 0.1), mid.y - (0.1 if horiz else len / 2.0), len if horiz else 0.2, 0.2 if horiz else len)
		_sb(body, cr, 1.0)


# Portões de grade (pedestre e garagem) do muro, abertos para dentro do lote.
func _gates(k: Kit, s: Dictionary, r: Rect2, dx: float, drive_x: float, garage: bool) -> void:
	var gc := Color("#2e3033") if rng.randf() < 0.7 else Color("#5a3f2e")
	if float(s["style"]["wear"]) > 0.6:
		gc = gc.lerp(Color("#6b4a32"), 0.4)
	var fz := r.end.y
	var opens: Array = [[dx, 1.9]]
	if garage:
		opens.append([drive_x, 3.4])
	for o in opens:
		var cx: float = o[0]
		var gw: float = o[1]
		# pilares do portão
		for sx in [-1, 1]:
			k.box(Vector3(cx + sx * (gw / 2.0 + 0.1), Y0 + 0.95, fz), Vector3(0.3, 1.9, 0.3), (s["style"]["wall"] as Color).lerp(Color("#bdb5a5"), 0.4))
		# folha aberta, encostada no muro por dentro
		var leaf := gw * (0.5 if gw > 2.5 else 1.0)
		var hinge := Vector3(cx - gw / 2.0, Y0, fz - 0.12)
		var yaw := -PI / 2.0 + 0.12
		var bas := Basis(Vector3.UP, yaw)
		k.solid_box(hinge + bas * Vector3(leaf / 2, 0.82, 0), Vector3(leaf, 1.6, 0.05), 4, yaw, "portao")
		for bi in int(leaf / 0.14) + 1:
			k.add("box", Transform3D(bas * Basis.from_scale(Vector3(0.03, 1.55, 0.03)), hinge + bas * Vector3(bi * 0.14, 0.82, 0)), gc)
		for by in [0.12, 0.85, 1.58]:
			k.add("box", Transform3D(bas * Basis.from_scale(Vector3(leaf, 0.05, 0.04)), hinge + bas * Vector3(leaf / 2.0, by, 0)), gc)
		k.add("box", Transform3D(bas * Basis.from_scale(Vector3(leaf, 0.5, 0.015)), hinge + bas * Vector3(leaf / 2.0, 1.3, 0)), gc.lightened(0.05))


# Sujeira na base, escorridos sob as janelas e remendos de reboco: mais desgaste, mais marcas.
func _weather(k: Kit, st: Dictionary, x0: float, x1: float, z0: float, z1: float, gap0: float, gap1: float) -> void:
	var wear: float = st["wear"]
	var wall: Color = st["wall"]
	var grime := wall.darkened(0.22 + wear * 0.18).lerp(Color("#4a4238"), 0.25)
	# barra encardida no pé da parede (frente e lado visível)
	k.box_ab(Vector3(x0 - 0.01, Y0, z1 - 0.01), Vector3(gap0, Y0 + 0.35 + wear * 0.35, z1 + 0.012), grime)
	k.box_ab(Vector3(gap1, Y0, z1 - 0.01), Vector3(x1 + 0.01, Y0 + 0.35 + wear * 0.35, z1 + 0.012), grime)
	k.box_ab(Vector3(x1 - 0.01, Y0, z0), Vector3(x1 + 0.012, Y0 + 0.35 + wear * 0.35, z1), grime)
	if wear < 0.25:
		return
	# escorridos verticais
	for i in int(wear * 6.0):
		var sx := rng.randf_range(x0 + 0.4, x1 - 0.4)
		if sx > gap0 - 0.3 and sx < gap1 + 0.3:
			continue
		var ln := rng.randf_range(0.5, 1.4)
		k.box(Vector3(sx, Y0 + H - 0.25 - ln / 2.0, z1 + 0.013), Vector3(rng.randf_range(0.08, 0.22), ln, 0.01), wall.darkened(0.1 + wear * 0.15))
	for i in int(wear * 4.0):
		var sz := rng.randf_range(z0 + 0.4, z1 - 0.4)
		var ln2 := rng.randf_range(0.5, 1.4)
		k.box(Vector3(x1 + 0.013, Y0 + H - 0.25 - ln2 / 2.0, sz), Vector3(0.01, ln2, rng.randf_range(0.08, 0.22)), wall.darkened(0.1 + wear * 0.15))
	# remendos de reboco e tinta descascada
	if wear > 0.5:
		for i in int(wear * 3.0):
			var px := rng.randf_range(x0 + 0.5, x1 - 0.5)
			if px > gap0 - 0.6 and px < gap1 + 0.6:
				continue
			k.box(Vector3(px, rng.randf_range(Y0 + 0.6, Y0 + H - 0.6), z1 + 0.014), Vector3(rng.randf_range(0.3, 0.9), rng.randf_range(0.2, 0.6), 0.01), wall.lerp(Color("#b8b0a0"), 0.5).darkened(rng.randf() * 0.1))


# Traços de cada cenário: flores e frutíferas no interior, lonas e arame no colapso.
func _regional(ka: Kit, kf: Kit, st: Dictionary, lr: Rect2, x0: float, x1: float, z0: float, z1: float, dx: float, rh: float) -> void:
	if rng.randf() < float(Art.p().get("flowers", 0.2)) and not st["abandoned"]:
		# primavera (buganvília) caindo sobre o muro ou a varanda
		var fx := lr.position.x + 0.6 if rng.randf() < 0.5 else lr.end.x - 0.6
		var pink := Color("#c2457a") if rng.randf() < 0.6 else Color("#d9853a")
		for i in 6:
			ka.sphere(Vector3(fx + rng.randf_range(-0.4, 0.4), Y0 + rng.randf_range(0.9, 1.9), lr.end.y - rng.randf_range(0.3, 2.4)), Vector3(0.7, 0.55, 0.7), pink.lerp(Color("#4a6a38"), rng.randf() * 0.35))
		if Art.id() == "vale_sereno" and rng.randf() < 0.6:
			# frutífera no quintal dos fundos
			var tp := Vector3(rng.randf_range(lr.position.x + 1.5, lr.end.x - 1.5), Y0, z0 - 1.3)
			ka.cyl(tp, 0.15, 1.6, Color("#5a4636"))
			ka.sphere(tp + Vector3(0, 2.3, 0), Vector3(2.4, 1.9, 2.4), Color("#4f7a38"))
			for fi in 7:
				ka.sphere(tp + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(1.8, 2.8), rng.randf_range(-0.9, 0.9)), Vector3(0.16, 0.16, 0.16), Color("#e0902a"))
	if Art.p().get("tarps", false):
		var w := x1 - x0
		var d := z1 - z0
		if rng.randf() < 0.45:
			# lona azul remendando o telhado
			kf.add("box", Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)) * Basis(Vector3.RIGHT, -0.45).scaled(Vector3(rng.randf_range(1.8, 3.2), 0.04, rng.randf_range(1.4, 2.4))), Vector3(rng.randf_range(-w * 0.2, w * 0.2), Y0 + H + rh * 0.45, d * 0.18)), Color("#2f5f9a"))
		if rng.randf() < 0.5 and not st["abandoned"]:
			# sacos de areia na porta
			for si in 5:
				ka.sphere(Vector3(dx - 0.9 + si * 0.45, Y0 + 0.18, z1 + 0.5), Vector3(0.5, 0.3, 0.38), Color("#8a7a58"))
		if st["fence"] == "muro":
			# arame farpado no alto do muro
			for side in [lr.position.y + 0.2, lr.end.y - 0.2]:
				for ai in int(lr.size.x / 0.45):
					ka.add("box", Transform3D(Basis(Vector3.RIGHT, 0.6 if ai % 2 == 0 else -0.6).scaled(Vector3(0.45, 0.02, 0.02)), Vector3(lr.position.x + 0.25 + ai * 0.45, Y0 + 1.9, side)), Color("#3a3a3a"))


# Sinais de quem mora: cadeira de plástico, bicicleta, vasos, capacho.
func _porch_life(k: Kit, st: Dictionary, dx: float, z1: float, x0: float, x1: float, garage: bool, drive_x: float) -> void:
	if st["abandoned"]:
		return
	var kind: int = st["porch_life"]
	var free_x := x1 - 1.0 if dx < (x0 + x1) / 2.0 else x0 + 1.0
	if garage and absf(free_x - drive_x) < 2.0:
		free_x = dx + (1.6 if dx < 0 else -1.6)
	match kind:
		0:
			# cadeiras de plástico brancas na frente
			for i in 2:
				var cp := Vector3(free_x + (i - 0.5) * 0.7, Y0, z1 + 0.7)
				k.box(cp + Vector3(0, 0.42, 0), Vector3(0.48, 0.05, 0.46), Color("#e8e6e0"))
				k.box(cp + Vector3(0, 0.7, -0.21), Vector3(0.48, 0.55, 0.04), Color("#e8e6e0"))
				for lx in [-0.2, 0.2]:
					for lz in [-0.18, 0.18]:
						k.box(cp + Vector3(lx, 0.21, lz), Vector3(0.04, 0.42, 0.04), Color("#dedcd6"))
		1:
			# bicicleta encostada
			var bp := Vector3(free_x, Y0, z1 + 0.35)
			for wx in [-0.45, 0.45]:
				k.add("cyl", Transform3D(Basis(Vector3.FORWARD, PI / 2.0) * Basis.from_scale(Vector3(0.62, 0.04, 0.62)), bp + Vector3(wx, 0.32, 0)), Color("#1c1c1c"))
			k.box(bp + Vector3(0, 0.5, 0), Vector3(0.9, 0.04, 0.04), Color("#8a2a2a"))
			k.box(bp + Vector3(0.1, 0.42, 0), Vector3(0.04, 0.32, 0.04), Color("#8a2a2a"))
			k.box(bp + Vector3(0.38, 0.72, 0), Vector3(0.04, 0.04, 0.4), Color("#2a2a2a"))
		2:
			# vasos de planta em fila
			for i in 3:
				var vp := Vector3(free_x + (i - 1) * 0.5, Y0, z1 + 0.35)
				k.cyl(vp, 0.17, 0.32, Color("#9a5a3a"))
				k.sphere(vp + Vector3(0, 0.5, 0), Vector3(0.42, 0.45, 0.42), Color("#4f7a3a").lerp(Color("#6a8a3a"), rng.randf()))
		3:
			# vaso grande e banquinho
			k.solid_box(Vector3(free_x, Y0 + 0.225, z1 + 0.4), Vector3(0.48, 0.45, 0.48), 4, 0, "vaso")
			k.cyl(Vector3(free_x, Y0, z1 + 0.4), 0.24, 0.45, Color("#7a6a5a"))
			k.sphere(Vector3(free_x, Y0 + 0.75, z1 + 0.4), Vector3(0.7, 0.7, 0.7), Color("#4a6a38"))
			k.box(Vector3(free_x + 0.7, Y0 + 0.25, z1 + 0.4), Vector3(0.35, 0.5, 0.35), Color("#7a5534"))
	k.box(Vector3(dx, Y0 + 0.03, z1 + 0.35), Vector3(0.7, 0.02, 0.4), Color("#5a4636"))


# Árvore na calçada, com canteiro, longe da porta e da entrada da garagem.
func _street_tree(k: Kit, st: Dictionary, lot_r: Rect2, dx: float, drive_x: float, garage: bool) -> void:
	if rng.randf() > Art.num("street_trees"):
		return
	var tz := lot_r.end.y + 1.45
	var cands: Array = [lot_r.position.x + 1.4, lot_r.end.x - 1.4, (lot_r.position.x + lot_r.end.x) / 2.0]
	for tx in cands:
		var x: float = tx
		if absf(x - dx) < 1.6:
			continue
		if garage and absf(x - drive_x) < 2.2:
			continue
		k.box_ab(Vector3(x - 0.55, Y0 - 0.005, tz - 0.55), Vector3(x + 0.55, Y0 + 0.012, tz + 0.55), Color("#5a4a38"))
		k.box_ab(Vector3(x - 0.6, Y0, tz - 0.6), Vector3(x + 0.6, Y0 + 0.06, tz - 0.52), Color("#a39f95"))
		k.box_ab(Vector3(x - 0.6, Y0, tz + 0.52), Vector3(x + 0.6, Y0 + 0.06, tz + 0.6), Color("#a39f95"))
		var g := Color("#4e6a38").lerp(Color("#6f8a40"), rng.randf())
		var h := rng.randf_range(2.6, 3.4)
		k.solid_cylinder(Vector3(x, Y0, tz), 0.13, h, 128, "arvore")
		k.cyl(Vector3(x, Y0, tz), 0.13, h, Color("#5a4636"))
		k.sphere(Vector3(x, Y0 + h + 0.4, tz), Vector3(2.4, 1.9, 2.4), g)
		k.sphere(Vector3(x + 0.4, Y0 + h + 1.0, tz + 0.2), Vector3(1.7, 1.4, 1.7), g.lightened(0.07))
		return


# ---------- interior (sob demanda) ----------

func build_interior(s: Dictionary) -> Node3D:
	# Compatibilidade com chamadas antigas: toda casa usa o construtor compartilhado.
	city.ensure_interior(s)
	return s["interior"]


const KM := "res://assets/furniture_k/Models/%s.fbx"


# Móveis dos interiores entram numa fila e são colocados aos poucos (place_pending),
# porque instanciar vários modelos no mesmo quadro fazia o jogo engasgar ao chegar perto das casas.
var pending: Array = []


func _m(parent: Node3D, name: String, x: float, z: float, yaw: float, up: float = 0.0, scale_k: float = 0.2, target: Dictionary = {}) -> Node3D:
	var solid := name in ["bedDouble", "bedSingle", "loungeSofaLong", "loungeSofa", "tableCoffee", "cabinetTelevision", "bookcaseOpen", "bookcaseClosed", "kitchenFridge", "kitchenStove", "kitchenSink", "kitchenCabinet", "bathtub", "toilet", "bathroomSink", "table", "chair"]
	pending.append([parent, KM % name, Vector3(x, Y0 + 0.075 + up, z), yaw, scale_k, solid, target])
	return null


func _place_model(it: Array) -> void:
	var holder := Furn.place(it[0], it[1], it[2], it[3], it[4], Vector3.ZERO, it[5])
	if holder == null or (it[6] as Dictionary).is_empty():
		return
	var target: Dictionary = it[6]
	city.object_point(target["key"], target["loc"], target["label"], holder.global_transform * (holder.get_meta("bounds") as AABB), target["kind"], target["plan"], false, holder)


# Coloca na hora os móveis de um interior específico (o jogador acabou de entrar nele).
func place_now(node: Node) -> void:
	if node == null:
		return
	var keep: Array = []
	for it in pending:
		var par: Node = it[0]
		if is_instance_valid(par) and (par == node or node.is_ancestor_of(par)):
			_place_model(it)
		else:
			keep.append(it)
	pending = keep


# Coloca móveis da fila até gastar o orçamento de tempo do quadro (em microssegundos).
func place_pending(budget_usec: int) -> void:
	var t0 := Time.get_ticks_usec()
	while not pending.is_empty() and Time.get_ticks_usec() - t0 < budget_usec:
		var it: Array = pending.pop_front()
		if is_instance_valid(it[0]) and not (it[0] as Node).is_queued_for_deletion():
			_place_model(it)


func _furnish_models(node: Node3D, rooms: Array, st: Dictionary, w: float, d: float, zdiv: float, xs: float, ab: bool, s: Dictionary) -> void:
	var tilt := 0.0
	var id := str(s["loc"])
	city.use_points[id] = {"_rooms": [], "_root": s["root"]}
	for r in rooms:
		var rr: Rect2 = r[1]
		var tipo: String = r[0]
		var cx := rr.get_center().x
		var cz := rr.get_center().y
		var exit: Array = []
		if tipo.begins_with("quarto") or tipo == "banheiro":
			exit = [Vector2(cx, zdiv - 0.4), Vector2(cx, zdiv + 0.45)]
		elif tipo == "cozinha":
			exit = [Vector2(xs + 0.4, zdiv + 1.25), Vector2(xs + 0.4, zdiv + 1.4), Vector2(xs - 0.7, zdiv + 1.4)]
		city.use_points[id]["_rooms"].append({"rect": rr, "exit": _world_path(s, exit)})
		match tipo:
			"quarto", "quarto2":
				var wide_room: bool = rr.size.x > 2.9
				var bedn := "bedDouble" if wide_room else "bedSingle"
				var bx: float = rr.position.x + (1.2 if wide_room else rr.size.x / 2.0)
				var bed_plan := _room_plan(s, rr, tipo, zdiv, xs, Vector2(bx + (1.25 if wide_room else 0.9), zdiv - 0.65), 0.0)
				bed_plan["anchor"] = (s["root"] as Node3D).to_global(Vector3(bx, 0, rr.position.y + 2.3))
				bed_plan["h"] = 0.5
				city.use_points[id]["cama"] = bed_plan
				_m(node, bedn, bx, rr.position.y + 1.25, tilt, 0, 0.2, _target(s, "cama_" + tipo, "Cama", "bed", bed_plan))
				_m(node, "cabinetBed", bx + (1.3 if wide_room else 0.9), rr.position.y + 0.4, tilt, 0, 0.2, _target(s, "criado_" + tipo, "Mesa de cabeceira", "inspect", bed_plan))
				var cupboard := _room_plan(s, rr, tipo, zdiv, xs, Vector2(rr.end.x - 1.0, rr.position.y + 1.4), PI / 2.0)
				_m(node, "bookcaseClosed", rr.end.x - 0.35, rr.position.y + 1.4, -PI / 2.0, 0, 0.2, _target(s, "armario_" + tipo, "Armário", "storage", cupboard))
				_m(node, "lampRoundFloor", rr.position.x + 0.3, rr.end.y - 0.3, 0.0)
				if wide_room:
					_m(node, "rugRectangle", cx + 0.3, cz + 0.5, 0.0)
			"banheiro":
				_m(node, "toilet", rr.position.x + 0.5, rr.position.y + 0.55, 0.0)
				_m(node, "bathroomSink", rr.position.x + 0.4, rr.position.y + 1.7, PI / 2.0)
				var bath := _room_plan(s, rr, tipo, zdiv, xs, Vector2(cx, zdiv - 0.65), PI / 2.0)
				bath["head"] = (s["root"] as Node3D).to_global(Vector3(cx, Y0 + 1.9, zdiv - 0.65))
				city.use_points[id]["chuveiro"] = bath
				_m(node, "bathtub", rr.end.x - 0.6, rr.position.y + 1.45, -PI / 2.0, 0, 0.2, _target(s, "banho", "Banheira / banho", "bath", bath))
			"sala":
				_m(node, "rugRectangle", cx, cz + 0.2, 0.0)
				var sofa := _room_plan(s, rr, tipo, zdiv, xs, Vector2(rr.position.x + 1.3, cz + 0.1), PI / 2.0)
				var seat_pos: Vector3 = (s["root"] as Node3D).to_global(Vector3(rr.position.x + 0.65, Y0, cz + 0.1))
				sofa["seat"] = {"p": Vector2(seat_pos.x, seat_pos.z), "yaw": sofa["yaw"]}
				city.use_points[id]["sofa"] = sofa
				_m(node, "loungeSofaLong" if rr.size.y > 3.4 else "loungeSofa", rr.position.x + 0.55, cz + 0.1, PI / 2.0, 0, 0.2, _target(s, "sofa", "Sofá", "seat", sofa))
				_m(node, "tableCoffee", cx - 0.2, cz + 0.1, PI / 2.0, 0, 0.2, _target(s, "mesa_sala", "Mesa de centro", "inspect", sofa))
				_m(node, "cabinetTelevision", cx - 0.35, rr.end.y - 0.6, PI, 0, 0.16, _target(s, "tv", "Televisão", "tv", sofa))
				_m(node, "bookcaseOpen", cx + 1.1, rr.position.y + 0.3, 0.0, 0, 0.16, _target(s, "estante", "Estante", "storage", sofa))
				_m(node, "lampRoundFloor", rr.end.x - 0.35, rr.position.y + 0.4, 0.0)
				_m(node, "plantSmall1", rr.position.x + 0.45, rr.end.y - 0.4, 0.0, 0.0, 0.5)
			"cozinha":
				var compact := rr.size.y < 3.4
				var ex := rr.end.x - 0.5
				var kitchen_plan := _room_plan(s, rr, tipo, zdiv, xs, Vector2(cx - 0.1, rr.position.y + 1.25), PI)
				_m(node, "kitchenFridge", ex, rr.position.y + 0.4, 0.0, 0, 0.2, _target(s, "geladeira", "Geladeira", "inspect", kitchen_plan))
				var items := ["kitchenStove", "kitchenSink", "kitchenCabinet", "kitchenCabinet"]
				var px := ex - 0.95
				for i in items.size():
					if px - 0.43 < rr.position.x + 0.05:
						break
					var appliance := Vector2(ex, rr.position.y + 1.35 + i * 0.9) if compact else Vector2(px, rr.position.y + 0.47)
					if compact and i > 1:
						break
					_m(node, items[i], appliance.x, appliance.y, PI / 2.0 if compact else 0.0)
					if i == 1:
						pending.back()[6] = _target(s, "pia", "Pia da cozinha", "inspect", kitchen_plan)
					if i == 0:
						var stove := _room_plan(s, rr, tipo, zdiv, xs, Vector2(ex - 0.9, appliance.y) if compact else Vector2(px, rr.position.y + 1.2), PI / 2.0 if compact else PI)
						stove["steam"] = (s["root"] as Node3D).to_global(Vector3(appliance.x, Y0 + 1.0, appliance.y))
						city.use_points[id]["fogao"] = stove
						pending.back()[6] = _target(s, "fogao", "Fogão", "stove", stove)
					if i < 2 and not compact:
						_m(node, "kitchenCabinetUpper", px, rr.position.y + 0.25, 0.0, 1.3)
					px -= 0.9
				var table_z := rr.end.y - (0.5 if compact else 1.3)
				_m(node, "table", cx - 0.1, table_z, 0.0, 0, 0.16 if compact else 0.2, _target(s, "mesa_cozinha", "Mesa de refeições", "inspect", kitchen_plan))
				for ci in (1 if rr.size.y < 3.4 else 4):
					var ang := PI / 2.0 if compact else ci * PI / 2.0
					var point := Vector2(cx - 0.1, rr.end.y - 0.22) if compact else Vector2(cx - 0.1 + cos(ang) * 0.85, table_z + sin(ang) * 0.6)
					var approach := Vector2(point.x, rr.position.y + 1.25) if compact else point + Vector2(0, 0.5)
					var chair := _room_plan(s, rr, tipo, zdiv, xs, approach, ang + PI / 2.0)
					var seat: Vector3 = (s["root"] as Node3D).to_global(Vector3(point.x, Y0, point.y))
					chair["seat"] = {"p": Vector2(seat.x, seat.z), "yaw": chair["yaw"]}
					_m(node, "chair", point.x, point.y, ang + PI / 2.0, 0, 0.2, _target(s, "cadeira_%d" % ci, "Cadeira", "seat", chair))
			"garagem":
				_m(node, "washer", rr.position.x + 0.5, rr.position.y + 0.5, 0.0)
				_m(node, "desk", rr.position.x + 0.5, cz + 0.4, PI / 2.0)
				for bi in 3:
					_m(node, "cardboardBoxClosed", rr.position.x + 1.4 + (bi % 2) * 0.5, rr.end.y - 0.5 - int(bi / 2) * 0.5, rng.randf() * 0.5)


# Cortinas por dentro das janelas: tecidos diferentes para cada morador.
func _world_path(s: Dictionary, points: Array) -> Array:
	var out: Array = []
	for p in points:
		var world: Vector3 = (s["root"] as Node3D).to_global(Vector3(p.x, Y0, p.y))
		out.append(Vector2(world.x, world.z))
	return out


func _room_plan(s: Dictionary, room: Rect2, kind: String, zdiv: float, xs: float, target: Vector2, yaw: float) -> Dictionary:
	var points: Array = [Vector2(xs - 0.7, zdiv + 1.4)]
	if kind.begins_with("quarto") or kind == "banheiro":
		points.append(Vector2(room.get_center().x, zdiv + 0.45))
		points.append(Vector2(room.get_center().x, zdiv - 0.4))
	elif kind == "cozinha":
		points.append(Vector2(xs + 0.4, zdiv + 1.4))
		points.append(Vector2(xs + 0.4, target.y))
	elif kind == "sala":
		points.append(Vector2(target.x, zdiv + 0.5))
	points.append(target)
	return {"path": _world_path(s, points), "yaw": yaw + (s["root"] as Node3D).rotation.y, "room": room}


func _target(s: Dictionary, slot: String, label: String, kind: String, plan: Dictionary) -> Dictionary:
	return {"key": str(s["loc"]) + "/" + slot, "loc": str(s["loc"]), "label": label, "kind": kind, "plan": plan}


func _lived_in(k: Kit, rooms: Array) -> void:
	for entry in rooms:
		var room: Rect2 = entry[1]
		if str(entry[0]) == "cozinha":
			var p := Vector3(room.get_center().x - 0.1, Y0 + (0.60 if room.size.y < 3.4 else 0.73), room.end.y - (0.5 if room.size.y < 3.4 else 1.3))
			k.cyl(p + Vector3(-0.25, 0, 0), 0.14, 0.025, Color("#bdb7a6"))
			k.cyl(p + Vector3(0.24, 0, 0.08), 0.055, 0.12, Color("#796c56"))
			k.cyl(p + Vector3(0.24, 0.12, 0.08), 0.045, 0.008, Color("#3f3427"))
			k.box(p + Vector3(0, 0.012, -0.2), Vector3(0.25, 0.02, 0.18), Color("#c6baa0"))
			k.box(p + Vector3(-0.45, 0.016, 0), Vector3(0.018, 0.015, 0.2), Color("#a1a29a"))
		elif str(entry[0]).begins_with("quarto"):
			var wide := room.size.x > 2.9
			var bx := room.position.x + (1.2 if wide else room.size.x / 2.0)
			var p := Vector3(bx + (1.3 if wide else 0.9), Y0 + 0.075 + 0.4664 + 0.01, room.position.y + 0.4)
			k.box(p, Vector3(0.13, 0.02, 0.21), Color("#3a4142"), 0.2)
			k.box(p + Vector3(0, 0.012, 0), Vector3(0.1, 0.008, 0.17), Color("#758982"), 0.2)
		elif str(entry[0]) == "banheiro":
			k.box(Vector3(room.position.x + 0.4, Y0 + 1.0, room.position.y + 1.7), Vector3(0.62, 0.045, 0.25), Color("#87725b"))
			k.box(Vector3(room.position.x + 0.23, Y0 + 1.04, room.position.y + 1.7), Vector3(0.2, 0.03, 0.14), Color("#bcb4a6"))
			k.cyl(Vector3(room.position.x + 0.52, Y0 + 1.025, room.position.y + 1.7), 0.04, 0.16, Color("#6f8a82"))


func _curtains(k: Kit, s: Dictionary, resident: String) -> void:
	var pal := {"familia": ["#c9a06a", "#8a9a6a", "#b07a5a"], "idoso": ["#d8c8a8", "#b8a08a", "#a87a6a"], "estudante": ["#5a6a8a", "#3a3a3a", "#7a3a3a"], "casal": ["#d8d0c0", "#8a7a6a", "#6a7a8a"]}
	var cols: Array = pal.get(resident, ["#c8b8a0"])
	var c := Color(str(cols[rng.randi() % cols.size()]))
	for wc in s["windows"]:
		var p: Vector3 = wc
		var d: float = s["d"]
		var w: float = s["w"]
		# só janelas das paredes do fundo (ficam inteiras com o jogador dentro)
		var north: bool = s["lot"]["north"]
		var back_z: bool = (p.z < 0.0) != north
		var back_x: bool = (p.x < 0.0) != north
		var on_z := absf(absf(p.z) - d / 2.0) < 0.3
		var on_x := absf(absf(p.x) - w / 2.0) < 0.3
		if (on_z and not back_z) or (on_x and not on_z and not back_x):
			continue
		# janela da frente/fundos (normal em z) ou lateral (normal em x)
		if on_z:
			var nz := -signf(p.z)
			for sx in [-1, 1]:
				_fb(k, Vector3(p.x + sx * 0.5, p.y + 0.05, p.z + nz * (T + 0.05)), Vector3(0.32, 1.45, 0.04), c)
			_fb(k, Vector3(p.x, p.y + 0.78, p.z + nz * (T + 0.05)), Vector3(1.4, 0.08, 0.06), c.darkened(0.3))
		elif absf(absf(p.x) - w / 2.0) < 0.3:
			var nx := -signf(p.x)
			for sz in [-1, 1]:
				_fb(k, Vector3(p.x + nx * (T + 0.05), p.y + 0.05, p.z + sz * 0.5), Vector3(0.04, 1.45, 0.32), c)


# Objetos que contam quem mora ali.
func _personal_touch(node: Node3D, k: Kit, rooms: Array, resident: String) -> void:
	for r in rooms:
		var rr: Rect2 = r[1]
		var tipo: String = r[0]
		var cx := rr.get_center().x
		var cz := rr.get_center().y
		match resident:
			"estudante":
				if tipo.begins_with("quarto"):
					_m(node, "desk", rr.end.x - 0.6, rr.end.y - 0.45, PI)
					_m(node, "laptop", rr.end.x - 0.6, rr.end.y - 0.45, PI, 0.75)
					_m(node, "chairDesk", rr.end.x - 0.6, rr.end.y - 1.0, 0.0)
					for i in 3:
						_m(node, "cardboardBoxOpen", rr.position.x + 0.4 + i * 0.45, rr.end.y - 0.35, rng.randf())
					_fb(k, Vector3(cx, Y0 + 1.6, rr.position.y + 0.15), Vector3(0.6, 0.8, 0.02), Color.from_hsv(rng.randf(), 0.6, 0.8))
				if tipo == "sala":
					_m(node, "speakerSmall", rr.end.x - 0.35, rr.position.y + 0.6, -PI / 2.0)
					_m(node, "pillow", cx - 0.3, cz + 0.6, rng.randf())
			"idoso":
				if tipo == "sala":
					_m(node, "loungeChairRelax", rr.end.x - 0.7, rr.end.y - 0.8, -PI * 0.75)
					_m(node, "radio", rr.position.x + 0.3, rr.position.y + 0.3, 0.0, 0.0)
					_m(node, "rugRound", cx, cz, 0.0)
					for i in 2:
						_m(node, "pottedPlant", rr.position.x + 0.35 + i * 0.6, rr.end.y - 0.3, 0.0)
				if tipo.begins_with("quarto"):
					_m(node, "sideTableDrawers", rr.end.x - 0.3, rr.end.y - 0.4, PI)
					_m(node, "lampRoundTable", rr.end.x - 0.3, rr.end.y - 0.4, 0.0, 0.5)
			"familia":
				if tipo.begins_with("quarto") and rr.size.x < 3.2:
					_m(node, "bear", cx, rr.end.y - 0.4, rng.randf_range(-0.5, 0.5))
					for i in 3:
						_fb(k, Vector3(cx + rng.randf_range(-0.8, 0.8), Y0 + 0.12, cz + rng.randf_range(-0.4, 0.6)), Vector3(0.18, 0.12, 0.18), Color.from_hsv(rng.randf(), 0.7, 0.85), rng.randf())
				if tipo == "sala":
					_m(node, "loungeChair", rr.end.x - 0.6, rr.end.y - 0.6, -PI * 0.75)
					_m(node, "plantSmall2", rr.position.x + 0.4, rr.position.y + 0.4, 0.0, 0.0, 0.5)
				if tipo == "cozinha":
					_m(node, "kitchenMicrowave", rr.end.x - 1.4, rr.position.y + 0.4, 0.0, 0.92)
			"casal":
				if tipo == "sala":
					_m(node, "plantSmall3", rr.end.x - 0.4, rr.end.y - 0.4, 0.0, 0.0, 0.5)
					_m(node, "books", cx - 0.2, cz + 0.1, rng.randf(), 0.42)
				if tipo == "cozinha":
					_m(node, "kitchenCoffeeMachine", rr.end.x - 1.4, rr.position.y + 0.4, 0.0, 0.92)
		if tipo == "banheiro":
			_m(node, "bathroomMirror", rr.position.x + 0.18, rr.position.y + 1.7, PI / 2.0, 1.15)
			_m(node, "trashcan", rr.position.x + 0.85, rr.position.y + 0.3, 0.0)


func _mk(k: Kit) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(city.mat)
	return mi


func _wall_x(k: Kit, body: StaticBody3D, xa: float, xb: float, z: float, thick: float, h: float, col: Color, gaps: Array) -> void:
	var cur := xa
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for g in sorted:
		_wall_piece_x(k, body, cur, float(g[0]), z, thick, h, col)
		cur = float(g[1])
	_wall_piece_x(k, body, cur, xb, z, thick, h, col)


func _wall_piece_x(k: Kit, body: StaticBody3D, xa: float, xb: float, z: float, thick: float, h: float, col: Color) -> void:
	if xb - xa < 0.05:
		return
	k.box_ab(Vector3(xa, Y0 + 0.06, z - thick / 2.0), Vector3(xb, Y0 + h, z + thick / 2.0), col)
	k.box_ab(Vector3(xa, Y0 + 0.06, z - thick / 2.0 - 0.01), Vector3(xb, Y0 + 0.2, z + thick / 2.0 + 0.01), col.darkened(0.35))
	_sb(body, Rect2(xa, z - thick / 2.0, xb - xa, thick), 2.6)


func _wall_z(k: Kit, body: StaticBody3D, x: float, za: float, zb: float, thick: float, h: float, col: Color, gaps: Array) -> void:
	var cur := za
	for g in gaps:
		_wall_piece_z(k, body, x, cur, float(g[0]), thick, h, col)
		cur = float(g[1])
	_wall_piece_z(k, body, x, cur, zb, thick, h, col)


func _wall_piece_z(k: Kit, body: StaticBody3D, x: float, za: float, zb: float, thick: float, h: float, col: Color) -> void:
	if zb - za < 0.05:
		return
	k.box_ab(Vector3(x - thick / 2.0, Y0 + 0.06, za), Vector3(x + thick / 2.0, Y0 + h, zb), col)
	k.box_ab(Vector3(x - thick / 2.0 - 0.01, Y0 + 0.06, za), Vector3(x + thick / 2.0 + 0.01, Y0 + 0.2, zb), col.darkened(0.35))
	_sb(body, Rect2(x - thick / 2.0, za, thick, zb - za), 2.6)


func _bed(k: Kit, p: Vector3, wood: Color, sheet: Color, broken: bool) -> void:
	_fb(k, p + Vector3(0, 0.25, 0), Vector3(1.6, 0.35, 2.0), wood)
	_fb(k, p + Vector3(0, 0.5, 0.05), Vector3(1.5, 0.22, 1.85), sheet.darkened(0.25 if broken else 0.0))
	_fb(k, p + Vector3(0, 0.62, -0.5), Vector3(1.4, 0.06, 0.8), _jit(Color("#4a6a9a"), 0.15) if not broken else Color("#5a5048"))
	for sx in [-0.38, 0.38]:
		_fb(k, p + Vector3(sx, 0.66, 0.75), Vector3(0.6, 0.13, 0.36), Color("#f0ece4") if not broken else Color("#8a8478"))
	_fb(k, p + Vector3(0, 0.75, 1.02), Vector3(1.6, 0.9, 0.08), wood.darkened(0.1))


func _sofa(k: Kit, p: Vector3, yaw: float, col: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	k.add("box", Transform3D(b * Basis.from_scale(Vector3(2.0, 0.42, 0.9)), p + b * Vector3(0, 0.21, 0)), col)
	k.add("box", Transform3D(b * Basis.from_scale(Vector3(2.0, 0.55, 0.22)), p + b * Vector3(0, 0.65, -0.34)), col.darkened(0.08))
	for sx in [-1.0, 1.0]:
		k.add("box", Transform3D(b * Basis.from_scale(Vector3(0.2, 0.62, 0.9)), p + b * Vector3(sx * 1.0, 0.31, 0)), col.darkened(0.12))
	for sx in [-0.5, 0.5]:
		k.add("box", Transform3D(b * Basis.from_scale(Vector3(0.9, 0.12, 0.6)), p + b * Vector3(sx, 0.48, 0.05)), col.lightened(0.1))
