extends RefCounted

# Gera uma casa de bairro completa: fachada com janelas, porta, varanda, telhado, quintal com
# cerca e árvores; e (sob demanda, quando o jogador chega perto) o interior com cômodos,
# paredes internas, portas e móveis. Tudo no espaço local da casa: x = largura, z = profundidade,
# a frente fica em +z. O nó raiz é girado em 180° quando a casa olha para o norte.

const Kit = preload("res://world3d/mesh_kit.gd")
const Furn = preload("res://world3d/furn_lib.gd")

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
	var abandoned: bool = str(Houses.st(lot["id"])["tipo"]) == "abandonada"
	var w: float = (lot["building"] as Rect2).size.x
	var st := {
		"wall": _jit(_c(WALLS[rng.randi() % WALLS.size()])),
		"roof": _jit(_c(ROOFS[rng.randi() % ROOFS.size()]), 0.03),
		"door": _c(DOORS[rng.randi() % DOORS.size()]),
		"kind": ["gable_x", "gable_z", "hip"][rng.randi() % 3],
		"porch": rng.randf() < 0.62,
		"garage": w >= 8.6 and rng.randf() < 0.5,
		"chimney": rng.randf() < 0.35,
		"fence": ["wood", "chain", "hedge", "wall", "none", "wood"][rng.randi() % 6],
		"shutters": rng.randf() < 0.4,
		"abandoned": abandoned,
	}
	st["trim"] = _c("#f0ebdd") if rng.randf() < 0.75 else _c("#5a4a3a")
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
	var mesh := k.commit(m if m else city.mat)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)
	return mi


func _tree(k: Kit, p: Vector3, scale: float, kind: int) -> void:
	var g := Color("#3f6b35").lerp(Color("#7a9a3a"), rng.randf())
	if kind == 0:
		var h := rng.randf_range(2.4, 3.4) * scale
		k.cyl(p, 0.17 * scale, h, Color("#5a4330"))
		k.sphere(p + Vector3(0, h + 0.5 * scale, 0), Vector3(3.2, 2.4, 3.2) * scale, g)
		k.sphere(p + Vector3(0.7, h + 1.3 * scale, 0.3), Vector3(2.3, 1.8, 2.3) * scale, g.lightened(0.08))
		k.sphere(p + Vector3(-0.6, h + 1.0 * scale, -0.5), Vector3(2.1, 1.7, 2.1) * scale, g.darkened(0.08))
	elif kind == 1:
		var h2 := rng.randf_range(3.2, 4.4) * scale
		k.cyl(p, 0.15 * scale, h2 * 0.35, Color("#4a3a2a"))
		k.cone(p + Vector3(0, h2 * 0.2, 0), 1.5 * scale, h2 * 0.5, g.darkened(0.2))
		k.cone(p + Vector3(0, h2 * 0.5, 0), 1.1 * scale, h2 * 0.4, g.darkened(0.12))
		k.cone(p + Vector3(0, h2 * 0.72, 0), 0.7 * scale, h2 * 0.3, g.darkened(0.05))
	else:
		var h3 := rng.randf_range(3.0, 4.2) * scale
		k.cyl(p, 0.13 * scale, h3, Color("#8a7355"))
		for i in 6:
			var a := TAU * i / 6.0
			k.box(p + Vector3(cos(a) * 0.7 * scale, h3 + 0.1, sin(a) * 0.7 * scale), Vector3(1.4 * scale, 0.1, 0.3), Color("#3f7a35"), -a)


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
	city.structures.append(s)
	var ka := Kit.new()
	var kf := Kit.new()
	var kc := Kit.new()
	var kw := Kit.new()
	var kl := Kit.new()
	var wall: Color = st["wall"]
	var trim: Color = st["trim"]
	var x0 := -w / 2.0
	var x1 := w / 2.0
	var z0 := -d / 2.0
	var z1 := d / 2.0
	var door_w := 1.05
	var gar_w: float = 3.2 if st["garage"] else 0.0
	# --- quintal ---
	var yard_c := (Color("#5a7a3f") if not st["abandoned"] else Color("#6f7a45")).lerp(Color("#4a6438"), rng.randf() * 0.5)
	ka.box_ab(Vector3(local_lot.position.x, Y0, local_lot.position.y), Vector3(local_lot.end.x, Y0 + 0.02, local_lot.end.y), yard_c)
	for i in rng.randi_range(2, 5):
		var px := rng.randf_range(local_lot.position.x + 1, local_lot.end.x - 1)
		var pz := rng.randf_range(local_lot.position.y + 1, local_lot.end.y - 1)
		if absf(px) < w / 2.0 + 0.5 and absf(pz) < d / 2.0 + 0.5:
			continue
		ka.box_ab(Vector3(px - 0.9, Y0 + 0.02, pz - 0.7), Vector3(px + 0.9, Y0 + 0.03, pz + 0.7), Color("#6e5d45") if rng.randf() < 0.6 else yard_c.lightened(0.1))
	# calçada de entrada e garagem
	var front_z: float = local_lot.end.y
	ka.box_ab(Vector3(dx - 0.6, Y0 + 0.02, z1), Vector3(dx + 0.6, Y0 + 0.04, front_z), Color("#a8a397"))
	var drive_x := 0.0
	if st["garage"]:
		drive_x = x0 + gar_w / 2.0 + 0.2
		ka.box_ab(Vector3(drive_x - 1.5, Y0 + 0.02, z1), Vector3(drive_x + 1.5, Y0 + 0.04, front_z), Color("#8d8a82"))
		if rng.randf() < 0.55:
			city._car(ka, Vector3(drive_x, Y0 + 0.04, front_z - 3.2), 0.0, city._car_color())
	# --- fundação e piso ---
	var fc2 := Color("#9a968c")
	ka.box_ab(Vector3(x0 - 0.08, Y0, z0 - 0.08), Vector3(x1 + 0.08, Y0 + 0.5, z0 + T), fc2)
	ka.box_ab(Vector3(x0 - 0.08, Y0, z1 - T), Vector3(x1 + 0.08, Y0 + 0.5, z1 + 0.08), fc2)
	ka.box_ab(Vector3(x0 - 0.08, Y0, z0), Vector3(x0 + T, Y0 + 0.5, z1), fc2)
	ka.box_ab(Vector3(x1 - T, Y0, z0), Vector3(x1 + 0.08, Y0 + 0.5, z1), fc2)
	ka.box_ab(Vector3(x0, Y0, z0), Vector3(x1, Y0 + 0.06, z1), Color("#7a6248"))
	# --- paredes (inteiras e cortadas) com vão da porta ---
	var gap0 := dx - door_w / 2.0
	var gap1 := dx + door_w / 2.0
	for g in [[kf, H], [kc, CUT_H]]:
		var k: Kit = g[0]
		var hh: float = g[1]
		var top: float = Y0 + hh
		k.box_ab(Vector3(x0, Y0, z0), Vector3(x1, top, z0 + T), wall)
		k.box_ab(Vector3(x0, Y0, z0), Vector3(x0 + T, top, z1), wall)
		k.box_ab(Vector3(x1 - T, Y0, z0), Vector3(x1, top, z1), wall)
		k.box_ab(Vector3(x0, Y0, z1 - T), Vector3(gap0, top, z1), wall)
		k.box_ab(Vector3(gap1, Y0, z1 - T), Vector3(x1, top, z1), wall)
		# batentes
		k.box_ab(Vector3(gap0 - 0.07, Y0, z1 - T - 0.02), Vector3(gap0, top if hh > 2.0 else Y0 + hh, z1 + 0.03), trim)
		k.box_ab(Vector3(gap1, Y0, z1 - T - 0.02), Vector3(gap1 + 0.07, top if hh > 2.0 else Y0 + hh, z1 + 0.03), trim)
		# cantos e rodapé externo
		for cx in [x0, x1]:
			for cz in [z0, z1]:
				k.box_ab(Vector3(cx - 0.09, Y0, cz - 0.09), Vector3(cx + 0.09, top, cz + 0.09), trim)
	kf.box_ab(Vector3(gap0, Y0 + 2.15, z1 - T), Vector3(gap1, Y0 + H, z1), wall)
	kf.box_ab(Vector3(gap0 - 0.07, Y0 + 2.1, z1 - T - 0.02), Vector3(gap1 + 0.07, Y0 + 2.2, z1 + 0.03), trim)
	# friso de topo
	kf.box_ab(Vector3(x0 - 0.1, Y0 + H - 0.2, z0 - 0.1), Vector3(x1 + 0.1, Y0 + H, z1 + 0.1), trim.darkened(0.05))
	# --- janelas ---
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
	var abandoned: bool = st["abandoned"]
	for wn in wins:
		var p: Vector3 = wn[0]
		var yaw: float = wn[1]
		var n := Vector3(sin(yaw), 0, cos(yaw))
		var wc := Vector3(p.x, Y0 + 1.55, p.z) + n * 0.02
		var cm := Basis(Vector3.UP, yaw)
		kf.add("box", Transform3D(cm * Basis.from_scale(Vector3(1.4, 1.5, 0.12)), wc + n * 0.02), trim)
		kw.add("box", Transform3D(cm * Basis.from_scale(Vector3(1.12, 1.22, 0.05)), wc + n * 0.085), Color.WHITE)
		kl.add("box", Transform3D(cm * Basis.from_scale(Vector3(1.06, 1.16, 0.05)), wc + n * 0.1), Color.WHITE)
		kf.add("box", Transform3D(cm * Basis.from_scale(Vector3(0.05, 1.2, 0.07)), wc + n * 0.11), trim)
		kf.add("box", Transform3D(cm * Basis.from_scale(Vector3(1.4, 0.08, 0.26)), wc + n * 0.1 + Vector3(0, -0.78, 0)), trim.darkened(0.08))
		if st["shutters"] and absf(yaw) < 0.1:
			for sx in [-1, 1]:
				kf.add("box", Transform3D(cm * Basis.from_scale(Vector3(0.42, 1.45, 0.06)), wc + cm * Vector3(sx * 0.9, 0, 0.12)), (st["door"] as Color).darkened(0.1))
		if abandoned and rng.randf() < 0.6:
			for bi in 3:
				kf.add("box", Transform3D(cm * Basis(Vector3.BACK, rng.randf_range(-0.25, 0.25)).scaled(Vector3(1.5, 0.14, 0.05)), wc + n * 0.14 + Vector3(0, -0.4 + bi * 0.4, 0)), Color("#6a5538"))
		s["windows"].append(wc)
	# --- porta ---
	var dc: Color = st["door"]
	var door_closed := Kit.new()
	door_closed.box(Vector3(dx, Y0 + 1.05, z1 - T / 2.0), Vector3(door_w - 0.04, 2.1, 0.07), dc)
	door_closed.box(Vector3(dx, Y0 + 1.55, z1 - T / 2.0 + 0.05), Vector3(0.5, 0.45, 0.02), dc.darkened(0.25))
	door_closed.box(Vector3(dx + door_w / 2.0 - 0.14, Y0 + 1.05, z1 - T / 2.0 + 0.06), Vector3(0.06, 0.06, 0.06), Color("#d9c27a"))
	var door_open := Kit.new()
	var hinge := Vector3(dx - door_w / 2.0 + 0.03, Y0 + 1.05, z1 - 0.1)
	door_open.add("box", Transform3D(Basis(Vector3.UP, -1.35) * Basis.from_scale(Vector3(door_w - 0.06, 2.1, 0.06)), hinge + Basis(Vector3.UP, -1.35) * Vector3((door_w - 0.06) / 2.0, 0, 0)), dc)
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
	# --- garagem ---
	if st["garage"]:
		var gx0 := x0 + 0.5
		var gx1 := x0 + gar_w
		kf.box_ab(Vector3(gx0, Y0, z1), Vector3(gx1, Y0 + 2.3, z1 + 0.06), Color("#e4e0d4"))
		for li in 5:
			kf.box_ab(Vector3(gx0, Y0 + 0.4 + li * 0.42, z1 + 0.06), Vector3(gx1, Y0 + 0.44 + li * 0.42, z1 + 0.09), Color("#b9b5a8"))
	# --- telhado ---
	var rh := clampf(minf(w, d) * 0.4, 1.5, 2.7)
	var roof: Color = st["roof"]
	var ov := 0.55
	var ctr := Vector3(0, Y0 + H, 0)
	match str(st["kind"]):
		"gable_x":
			kf.gable(ctr + Vector3(0, rh / 2.0 - 0.02, 0), Vector3(w + ov * 2.0, rh, d + ov * 2.0), roof, true)
		"gable_z":
			kf.gable(ctr + Vector3(0, rh / 2.0 - 0.02, 0), Vector3(w + ov * 2.0, rh, d + ov * 2.0), roof, false)
		_:
			kf.hip(ctr + Vector3(0, -0.02, 0), w + ov * 2.0, rh, d + ov * 2.0, roof)
	# calha
	kf.box_ab(Vector3(x0 - ov, Y0 + H - 0.08, z1 + ov - 0.1), Vector3(x1 + ov, Y0 + H + 0.06, z1 + ov), Color("#9a9a9a"))
	if st["chimney"]:
		var chx := rng.randf_range(-w * 0.28, w * 0.28)
		kf.box(Vector3(chx, Y0 + H + rh * 0.6, -d * 0.12), Vector3(0.75, rh + 1.2, 0.75), Color("#8a4a3a"))
		kf.box(Vector3(chx, Y0 + H + rh * 0.6 + rh / 2.0 + 0.7, -d * 0.12), Vector3(0.95, 0.14, 0.95), Color("#6a6a6a"))
	if rng.randf() < 0.3:
		kf.cyl(Vector3(w * 0.2, Y0 + H + rh * 0.55, d * 0.15), 0.18, 0.15, Color("#cfcfcf"))
		kf.box(Vector3(w * 0.2, Y0 + H + rh * 0.7, d * 0.15), Vector3(0.9, 0.04, 0.9), Color("#d8d8d8"), 0.3)
	# --- extras de quintal ---
	var side_x: float = x1 + 0.9 if rng.randf() < 0.5 else x0 - 0.9
	if absf(side_x) < local_lot.size.x / 2.0 - 0.2 or true:
		ka.box_ab(Vector3(side_x - 0.4, Y0, z1 - 2.6), Vector3(side_x + 0.4, Y0 + 0.75, z1 - 1.8), Color("#cfd2d6"))
	for i in rng.randi_range(2, 4):
		_bush(ka, Vector3(rng.randf_range(x0 + 0.5, x1 - 0.5), Y0, z1 + rng.randf_range(0.5, 1.0)), rng.randf_range(0.7, 1.1))
	if rng.randf() < 0.65:
		var tx: float = local_lot.position.x + rng.randf_range(1.0, 2.0) if rng.randf() < 0.5 else local_lot.end.x - rng.randf_range(1.0, 2.0)
		_tree(ka, Vector3(tx, Y0, z1 + rng.randf_range(1.2, 2.2)), rng.randf_range(0.8, 1.1), rng.randi() % 3)
	for i in rng.randi_range(1, 3):
		_tree(ka, Vector3(rng.randf_range(local_lot.position.x + 1.2, local_lot.end.x - 1.2), Y0, z0 - rng.randf_range(0.8, 1.4)), rng.randf_range(0.9, 1.3), rng.randi() % 3)
	# caixa de correio e lixeiras na calçada
	var mbx := dx + 1.8
	ka.box(Vector3(mbx, Y0 + 0.55, front_z - 0.25), Vector3(0.08, 1.1, 0.08), Color("#4a3a2a"))
	ka.box(Vector3(mbx, Y0 + 1.15, front_z - 0.25), Vector3(0.45, 0.3, 0.3), Color("#2f4f6f") if rng.randf() < 0.5 else Color("#8a2f2f"))
	if rng.randf() < 0.6:
		for i in rng.randi_range(1, 2):
			ka.cyl(Vector3(dx - 2.2 + i * 0.6, Y0, front_z - 0.5), 0.26, 0.85, Color("#2f6b3f") if i == 0 else Color("#33363a"))
	if rng.randf() < 0.25:
		ka.box(Vector3(x1 + 0.6, Y0 + 0.35, z0 + 1.0), Vector3(0.25, 0.7, 1.4), Color("#bcbcbc"))
	if rng.randf() < 0.3:
		# varal nos fundos
		for sx in [-1, 1]:
			ka.box(Vector3(sx * (w / 2.0 - 0.6), Y0 + 0.9, z0 - 1.4), Vector3(0.06, 1.8, 0.06), Color("#6a6a6a"))
		for ci in 5:
			ka.box(Vector3(-w / 2.0 + 1.2 + ci * 0.9, Y0 + 1.5, z0 - 1.4), Vector3(0.4, 0.55, 0.04), Color.from_hsv(rng.randf(), 0.45, 0.9))
	if abandoned:
		for i in 14:
			ka.box(Vector3(rng.randf_range(local_lot.position.x + 1, local_lot.end.x - 1), Y0 + 0.05, rng.randf_range(local_lot.position.y + 1, local_lot.end.y - 1)), Vector3(rng.randf_range(0.2, 0.7), 0.12, rng.randf_range(0.2, 0.6)), Color("#5a4a3a").lerp(Color("#3a5a2a"), rng.randf()), rng.randf() * PI)
	# --- cerca ---
	_fence(ka, body, s, local_lot, dx, drive_x, gar_w > 0.0)
	# colisão das paredes
	_sb(body, Rect2(x0, z0, w, T), H)
	_sb(body, Rect2(x0, z0, T, d), H)
	_sb(body, Rect2(x1 - T, z0, T, d), H)
	_sb(body, Rect2(x0, z1 - T, gap0 - x0, T), H)
	_sb(body, Rect2(gap1, z1 - T, x1 - gap1, T), H)
	var door_cs := _sb(body, Rect2(gap0, z1 - T, gap1 - gap0, T), H)
	# malhas
	_mesh(ka, root)
	_mesh(kf, full)
	_mesh(kc, cut)
	_mesh(kw, full, city.glass_mat)
	var lit_mi := _mesh(kl, lit, city.lit_mat)
	var dc_mi := _mesh(door_closed, root)
	var do_mi := _mesh(door_open, root)
	city.loc_info[id] = {"door": door_cs, "door_mesh": dc_mi, "door_open": do_mi, "light": null, "sign": null, "structure": s}
	do_mi.visible = false
	s["lit_mi"] = lit_mi
	return s


func _fence(k: Kit, body: StaticBody3D, s: Dictionary, lr: Rect2, dx: float, drive_x: float, garage: bool) -> void:
	var kind: String = s["style"]["fence"]
	if kind == "none":
		return
	var inset := 0.18
	var r := lr.grow(-inset)
	var col := Color("#d8d0bc") if kind == "wood" else (Color("#7a7a7e") if kind == "chain" else (Color("#c8bfae") if kind == "wall" else Color("#3f6b35")))
	if s["style"]["abandoned"]:
		col = col.darkened(0.3)
	var hgt: float = 1.1 if kind in ["wood", "wall"] else (1.25 if kind == "chain" else 0.95)
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
			"hedge":
				var n3 := int(len / 0.75)
				for i in n3 + 1:
					var pp3 := a + dir * (len * float(i) / maxf(n3, 1))
					k.sphere(Vector3(pp3.x, Y0 + hgt * 0.5, pp3.y), Vector3(1.0, hgt, 1.0), col.lerp(Color("#5a8a3a"), rng.randf() * 0.5))
		# colisão
		var horiz := absf(dir.x) > 0.5
		var cr := Rect2(mid.x - (len / 2.0 if horiz else 0.1), mid.y - (0.1 if horiz else len / 2.0), len if horiz else 0.2, 0.2 if horiz else len)
		_sb(body, cr, 1.0)


# ---------- interior (sob demanda) ----------

func build_interior(s: Dictionary) -> Node3D:
	var node := Node3D.new()
	var body := StaticBody3D.new()
	node.add_child(body)
	var lot: Dictionary = s["lot"]
	rng.seed = int(lot["seed"]) + 991
	var st: Dictionary = s["style"]
	var w: float = s["w"]
	var d: float = s["d"]
	var dx: float = s["dx"]
	var x0 := -w / 2.0
	var x1 := w / 2.0
	var z0 := -d / 2.0
	var z1 := d / 2.0
	var ab: bool = st["abandoned"]
	var kk := Kit.new()
	var kf := Kit.new()
	var inner := Color("#b9ae98") if not ab else Color("#6f695a")
	var base_c := Color("#6a5a48")
	var bd := clampf(d * 0.46, 2.9, 3.5)
	var zdiv := z0 + bd
	var gar_w: float = 3.2 if st["garage"] else 0.0
	var xs := lerpf(x0 + gar_w, x1, 0.58)
	var rooms: Array = []
	var back_x: Array = []
	if w >= 8.6:
		back_x = [x0, x0 + w * 0.38, x0 + w * 0.6, x1]
		rooms.append(["quarto", Rect2(back_x[0], z0, back_x[1] - back_x[0], bd)])
		rooms.append(["banheiro", Rect2(back_x[1], z0, back_x[2] - back_x[1], bd)])
		rooms.append(["quarto2", Rect2(back_x[2], z0, back_x[3] - back_x[2], bd)])
	else:
		back_x = [x0, x0 + w * 0.62, x1]
		rooms.append(["quarto", Rect2(back_x[0], z0, back_x[1] - back_x[0], bd)])
		rooms.append(["banheiro", Rect2(back_x[1], z0, back_x[2] - back_x[1], bd)])
	if gar_w > 0.0:
		rooms.append(["garagem", Rect2(x0, zdiv, gar_w, z1 - zdiv)])
	rooms.append(["sala", Rect2(x0 + gar_w, zdiv, xs - x0 - gar_w, z1 - zdiv)])
	rooms.append(["cozinha", Rect2(xs, zdiv, x1 - xs, z1 - zdiv)])
	# pisos
	for r in rooms:
		var rr: Rect2 = r[1]
		var tipo: String = r[0]
		var fc := Color("#5e4429") if tipo.begins_with("quarto") or tipo == "sala" else (Color("#74726c") if tipo == "garagem" else Color("#8d9094"))
		if ab:
			fc = fc.darkened(0.3)
		kk.box_ab(Vector3(rr.position.x, Y0 + 0.06, rr.position.y), Vector3(rr.end.x, Y0 + 0.075, rr.end.y), fc)
		if tipo in ["cozinha", "banheiro"]:
			var tx := rr.position.x
			var flip := false
			while tx < rr.end.x - 0.01:
				var tz := rr.position.y
				var f2 := flip
				while tz < rr.end.y - 0.01:
					if f2:
						kk.box_ab(Vector3(tx, Y0 + 0.075, tz), Vector3(minf(tx + 0.6, rr.end.x), Y0 + 0.08, minf(tz + 0.6, rr.end.y)), Color("#6c7a86") if tipo == "banheiro" else Color("#7a6f60"))
					f2 = not f2
					tz += 0.6
				flip = not flip
				tx += 0.6
		elif tipo.begins_with("quarto") or tipo == "sala":
			var px := rr.position.x + 0.45
			while px < rr.end.x:
				kk.box_ab(Vector3(px, Y0 + 0.075, rr.position.y), Vector3(px + 0.02, Y0 + 0.078, rr.end.y), fc.darkened(0.25))
				px += 0.45
	# paredes internas (baixas, com vão de porta)
	var it := 0.13
	var wall_h := CUT_H
	# divisória entre fundos e frente
	var gaps: Array = []
	for i in range(0, back_x.size() - 1):
		var cxm: float = (float(back_x[i]) + float(back_x[i + 1])) / 2.0
		gaps.append([cxm - 0.55, cxm + 0.55])
	_wall_x(kk, body, x0 + 0.01, x1 - 0.01, zdiv, it, wall_h, inner, gaps)
	for i in range(1, back_x.size() - 1):
		_wall_z(kk, body, back_x[i], z0, zdiv, it, wall_h, inner, [])
	if gar_w > 0.0:
		_wall_z(kk, body, x0 + gar_w, zdiv, z1 - 0.01, it, wall_h, inner, [[zdiv + (z1 - zdiv) * 0.45 - 0.5, zdiv + (z1 - zdiv) * 0.45 + 0.5]])
	_wall_z(kk, body, xs, zdiv, z1 - 0.01, it, wall_h, inner, [[zdiv + 0.15, zdiv + 1.85]])
	# --- móveis ---
	var use_models := Furn.available()
	if use_models:
		_furnish_models(node, rooms, st, w, d, zdiv, xs, ab)
	var sofa_c := _c(SOFAS[rng.randi() % SOFAS.size()])
	var wood := Color("#7a5a3a") if not ab else Color("#4a3a2a")
	for r in (rooms if not use_models else []):
		var rr: Rect2 = r[1]
		var tipo: String = r[0]
		match tipo:
			"quarto", "quarto2":
				var bx := rr.position.x + 1.15
				if rr.size.x < 2.9:
					bx = rr.get_center().x
				_bed(kk, Vector3(bx, Y0 + 0.075, rr.position.y + 1.2), wood, _c(["#e6e1d6", "#cfd8e6", "#e6d2d2"][rng.randi() % 3]), ab)
				_fb(kk, Vector3(rr.end.x - 0.45, Y0 + 1.0, rr.position.y + 0.38), Vector3(0.8, 2.0, 0.55), wood.lightened(0.08))
				_fb(kk, Vector3(bx + 1.2, Y0 + 0.3, rr.position.y + 0.3), Vector3(0.45, 0.5, 0.4), wood)
				_fb(kk, Vector3(bx + 1.2, Y0 + 0.62, rr.position.y + 0.3), Vector3(0.12, 0.2, 0.12), Color("#e8d8a0"))
				if rr.size.x > 2.6 and rng.randf() < 0.7:
					_fb(kk, Vector3(rr.get_center().x + 0.2, Y0 + 0.08, rr.get_center().y + 0.6), Vector3(1.6, 0.012, 1.1), _jit(Color("#9a4a4a"), 0.1))
			"banheiro":
				_fb(kk, Vector3(rr.get_center().x, Y0 + 0.28, rr.position.y + 0.45), Vector3(0.4, 0.55, 0.62), Color("#e8e8e8"))
				_fb(kk, Vector3(rr.get_center().x, Y0 + 0.62, rr.position.y + 0.25), Vector3(0.38, 0.4, 0.2), Color("#e8e8e8"))
				_fb(kk, Vector3(rr.position.x + 0.5, Y0 + 0.42, rr.position.y + 1.45), Vector3(0.5, 0.84, 0.4), Color("#eeeeee"))
				_fb(kk, Vector3(rr.position.x + 0.5, Y0 + 1.5, rr.position.y + 1.66), Vector3(0.5, 0.6, 0.04), Color("#a8c4d0"))
				_fb(kk, Vector3(rr.end.x - 0.45, Y0 + 0.3, rr.position.y + 1.3), Vector3(0.78, 0.55, 1.5), Color("#f2f2f2"))
				_fb(kk, Vector3(rr.end.x - 0.45, Y0 + 0.5, rr.position.y + 1.3), Vector3(0.62, 0.1, 1.34), Color("#9fc6d8"))
			"sala":
				var wxr := rr.end.x
				_fb(kk, Vector3(rr.get_center().x, Y0 + 0.08, rr.get_center().y + 0.1), Vector3(2.4, 0.012, 1.6), _jit(Color("#4a5a7a"), 0.1))
				_sofa(kk, Vector3(rr.position.x + 0.55, Y0 + 0.075, rr.get_center().y + 0.3), -PI / 2.0, sofa_c)
				_fb(kk, Vector3(rr.get_center().x + 0.2, Y0 + 0.3, rr.get_center().y + 0.2), Vector3(0.9, 0.4, 0.55), wood)
				_fb(kk, Vector3(wxr - 0.5, Y0 + 0.28, rr.get_center().y + 0.3), Vector3(0.45, 0.55, 1.3), wood.darkened(0.1))
				_fb(kk, Vector3(wxr - 0.5, Y0 + 0.82, rr.get_center().y + 0.3), Vector3(0.08, 0.6, 1.0), Color("#15171a"))
				_fb(kk, Vector3(rr.position.x + 0.3, Y0 + 0.9, rr.position.y + 0.3), Vector3(0.9, 1.8, 0.35), wood)
				for bi in 12:
					_fb(kk, Vector3(rr.position.x + 0.05 + (bi % 6) * 0.14, Y0 + 0.55 + int(bi / 6) * 0.55, rr.position.y + 0.3), Vector3(0.1, 0.38, 0.28), Color.from_hsv(rng.randf(), 0.5, 0.7))
				kk.cyl(Vector3(rr.position.x + 0.5, Y0 + 0.075, rr.end.y - 0.45), 0.2, 0.3, Color("#8a5a3a"))
				kk.sphere(Vector3(rr.position.x + 0.5, Y0 + 0.65, rr.end.y - 0.45), Vector3(0.6, 0.7, 0.6), Color("#4f8a3f") if not ab else Color("#6a6a3a"))
			"cozinha":
				var cz := rr.position.y
				_fb(kk, Vector3(rr.end.x - 0.4, Y0 + 0.9, cz + 0.45), Vector3(0.7, 1.8, 0.7), Color("#e8eaec"))
				_fb(kk, Vector3(rr.end.x - 1.2, Y0 + 0.45, cz + 0.33), Vector3(0.7, 0.9, 0.62), Color("#cfcfd2"))
				_fb(kk, Vector3(rr.end.x - 1.2, Y0 + 0.92, cz + 0.33), Vector3(0.6, 0.04, 0.5), Color("#222"))
				_fb(kk, Vector3(rr.end.x - 2.05, Y0 + 0.45, cz + 0.33), Vector3(1.1, 0.9, 0.6), Color("#b49a78"))
				_fb(kk, Vector3(rr.end.x - 2.05, Y0 + 0.92, cz + 0.33), Vector3(1.14, 0.05, 0.64), Color("#7a7a80"))
				_fb(kk, Vector3(rr.end.x - 2.05, Y0 + 0.97, cz + 0.33), Vector3(0.5, 0.06, 0.4), Color("#9aa0a8"))
				_fb(kk, Vector3(rr.end.x - 1.6, Y0 + 1.7, cz + 0.2), Vector3(2.4, 0.6, 0.35), Color("#b49a78"))
				_fb(kk, Vector3(rr.get_center().x - 0.2, Y0 + 0.72, rr.get_center().y + 0.55), Vector3(1.2, 0.05, 0.8), wood.lightened(0.1))
				for ci in 4:
					var ang := ci * PI / 2.0
					_fb(kk, Vector3(rr.get_center().x - 0.2, Y0 + 0.24, rr.get_center().y + 0.55) + Vector3(cos(ang) * 0.85, 0, sin(ang) * 0.6), Vector3(0.36, 0.45, 0.36), wood)
			"garagem":
				_fb(kk, Vector3(rr.position.x + 0.45, Y0 + 0.45, rr.get_center().y), Vector3(0.6, 0.9, 1.9), wood.darkened(0.15))
				_fb(kk, Vector3(rr.position.x + 0.3, Y0 + 1.0, rr.get_center().y), Vector3(0.35, 1.9, 1.8), Color("#7a7a7e"))
				for bi in 4:
					_fb(kk, Vector3(rr.position.x + 1.5 + (bi % 2) * 0.6, Y0 + 0.25, rr.end.y - 0.5 - int(bi / 2) * 0.55), Vector3(0.5, 0.5, 0.5), Color("#a58a5a"), rng.randf())
				kk.cyl(Vector3(rr.end.x - 0.5, Y0 + 0.075, rr.position.y + 0.6), 0.33, 0.25, Color("#1a1a1a"))
	# quadros nas paredes e cortinas
	if ab:
		for i in 10:
			var rrr: Rect2 = (rooms[rng.randi() % rooms.size()][1] as Rect2).grow(-0.4)
			_fb(kk, Vector3(rng.randf_range(rrr.position.x, rrr.end.x), Y0 + 0.12, rng.randf_range(rrr.position.y, rrr.end.y)), Vector3(rng.randf_range(0.2, 0.6), 0.14, rng.randf_range(0.2, 0.6)), Color("#4a4034"), rng.randf() * PI)
	node.add_child(_mk(kk))
	var light := OmniLight3D.new()
	light.position = Vector3(0, Y0 + 2.4, 0)
	light.omni_range = maxf(w, d) * 0.95
	light.light_energy = 0.9
	light.light_color = Color("#ffe1ad")
	light.visible = false
	node.add_child(light)
	s["light"] = light
	return node



const KM := "res://assets/furniture_k/Models/%s.fbx"


func _m(parent: Node3D, name: String, x: float, z: float, yaw: float, up: float = 0.0, scale_k: float = 0.2) -> Node3D:
	return Furn.place(parent, KM % name, Vector3(x, Y0 + 0.075 + up, z), yaw, scale_k)


func _furnish_models(node: Node3D, rooms: Array, st: Dictionary, w: float, d: float, zdiv: float, xs: float, ab: bool) -> void:
	var tilt := 0.0
	for r in rooms:
		var rr: Rect2 = r[1]
		var tipo: String = r[0]
		var cx := rr.get_center().x
		var cz := rr.get_center().y
		match tipo:
			"quarto", "quarto2":
				var wide_room: bool = rr.size.x > 2.9
				var bedn := "bedDouble" if wide_room else "bedSingle"
				var bx: float = rr.position.x + (1.2 if wide_room else rr.size.x / 2.0)
				_m(node, bedn, bx, rr.position.y + 1.25, tilt)
				_m(node, "cabinetBed", bx + (1.3 if wide_room else 0.9), rr.position.y + 0.4, tilt)
				_m(node, "bookcaseClosed", rr.end.x - 0.35, rr.position.y + 1.4, -PI / 2.0)
				_m(node, "lampRoundFloor", rr.position.x + 0.3, rr.end.y - 0.3, 0.0)
				if wide_room:
					_m(node, "rugRectangle", cx + 0.3, cz + 0.5, 0.0)
			"banheiro":
				_m(node, "toilet", rr.position.x + 0.5, rr.position.y + 0.55, 0.0)
				_m(node, "bathroomSink", rr.position.x + 0.4, rr.position.y + 1.7, PI / 2.0)
				_m(node, "bathtub", rr.end.x - 0.6, rr.position.y + 1.45, -PI / 2.0)
			"sala":
				_m(node, "rugRectangle", cx, cz + 0.2, 0.0)
				_m(node, "loungeSofaLong" if rr.size.y > 3.4 else "loungeSofa", rr.position.x + 0.55, cz + 0.1, PI / 2.0)
				_m(node, "tableCoffee", cx - 0.2, cz + 0.1, PI / 2.0)
				_m(node, "cabinetTelevision", rr.end.x - 0.35, cz + 0.1, -PI / 2.0)
				_m(node, "bookcaseOpen", rr.position.x + 1.3, rr.position.y + 0.3, 0.0)
				_m(node, "lampRoundFloor", rr.end.x - 0.35, rr.position.y + 0.4, 0.0)
				_m(node, "plantSmall1", rr.position.x + 0.45, rr.end.y - 0.4, 0.0, 0.0, 0.5)
			"cozinha":
				var ex := rr.end.x - 0.5
				_m(node, "kitchenFridge", ex, rr.position.y + 0.4, 0.0)
				var items := ["kitchenStove", "kitchenSink", "kitchenCabinet", "kitchenCabinet"]
				var px := ex - 0.95
				for i in items.size():
					if px - 0.43 < rr.position.x + 0.05:
						break
					_m(node, items[i], px, rr.position.y + 0.47, 0.0)
					if i < 2:
						_m(node, "kitchenCabinetUpper", px, rr.position.y + 0.25, 0.0, 1.3)
					px -= 0.9
				_m(node, "table", cx - 0.1, rr.end.y - 1.3, 0.0)
				for ci in 4:
					var ang := ci * PI / 2.0
					_m(node, "chair", cx - 0.1 + cos(ang) * 0.85, rr.end.y - 1.3 + sin(ang) * 0.6, ang + PI / 2.0)
			"garagem":
				_m(node, "washer", rr.position.x + 0.5, rr.position.y + 0.5, 0.0)
				_m(node, "desk", rr.position.x + 0.5, cz + 0.4, PI / 2.0)
				for bi in 3:
					_m(node, "cardboardBoxClosed", rr.position.x + 1.4 + (bi % 2) * 0.5, rr.end.y - 0.5 - int(bi / 2) * 0.5, rng.randf() * 0.5)


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
