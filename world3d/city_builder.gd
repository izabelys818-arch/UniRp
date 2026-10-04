extends Node3D

# Monta a cidade em 3D a partir do traçado. Cada construção tem duas versões:
# inteira (paredes + telhado) e cortada (paredes baixas), como no Project Zomboid,
# para que dê para ver o personagem dentro dos prédios ou atrás deles.

const Kit = preload("res://world3d/mesh_kit.gd")
const Layout = preload("res://world3d/city_layout.gd")

const WALL_H := 3.2
const CUT_H := 0.75
const WALL_T := 0.3

const ASPHALT := Color("#3a3c3f")
const SIDEWALK := Color("#77746d")
const CURB := Color("#a9a59b")
const GRASS := Color("#56703f")
const GRASS2 := Color("#4a6438")
const DIRT := Color("#6e5d45")
const LINE := Color("#d8d3c4")

var layout: Layout
var mat: StandardMaterial3D
var glass_mat: StandardMaterial3D
var lit_mat: StandardMaterial3D
var water_mat: StandardMaterial3D
var festa_mat: StandardMaterial3D
var body: StaticBody3D
var structures: Array = []          # {"rect": Rect2, "full": Node3D, "cut": Node3D, "loc": String, "cut_now": bool}
var loc_info: Dictionary = {}       # loc_id -> {"door": CollisionShape3D, "door_mesh": Node3D, "light": OmniLight3D, "sign": Label3D}
var lamp_spots: Array = []          # Vector3
var festa_node: Node3D
var fire_nodes: Dictionary = {}
var rng := RandomNumberGenerator.new()


func build(l: Layout) -> void:
	layout = l
	rng.seed = 90210
	mat = Kit.vertex_material()
	glass_mat = StandardMaterial3D.new()
	glass_mat.albedo_color = Color("#1d2a36")
	glass_mat.roughness = 0.15
	glass_mat.metallic = 0.3
	lit_mat = StandardMaterial3D.new()
	lit_mat.albedo_color = Color("#ffd98a")
	lit_mat.emission_enabled = true
	lit_mat.emission = Color("#ffcf73")
	lit_mat.emission_energy_multiplier = 1.4
	festa_mat = Kit.vertex_material()
	festa_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_mat = StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.22, 0.42, 0.55, 0.85)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.roughness = 0.05
	water_mat.metallic = 0.2
	body = StaticBody3D.new()
	add_child(body)
	var floor_cs := CollisionShape3D.new()
	floor_cs.shape = WorldBoundaryShape3D.new()
	floor_cs.position = Vector3(0, 0.17, 0)
	body.add_child(floor_cs)
	_ground()
	for c in layout.blocks:
		var info: Dictionary = layout.blocks[c]
		if str(info["loc"]) != "":
			_build_location(str(info["loc"]), c)
		else:
			_build_filler(c, info)


# ---------- utilidades ----------

func _mesh(kit: Kit, parent: Node3D, m: Material = null) -> MeshInstance3D:
	var mesh := kit.commit(m if m else mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)
	return mi


func _collider(rect: Rect2, h: float = WALL_H) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(rect.size.x, h, rect.size.y)
	cs.shape = bs
	cs.position = Vector3(rect.get_center().x, h / 2.0, rect.get_center().y)
	body.add_child(cs)
	return cs


func _structure(rect: Rect2, loc: String = "") -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var full := Node3D.new()
	var cut := Node3D.new()
	cut.visible = false
	root.add_child(full)
	root.add_child(cut)
	var s := {"rect": rect, "full": full, "cut": cut, "loc": loc, "cut_now": false, "root": root}
	structures.append(s)
	return s


func set_cut(s: Dictionary, on: bool) -> void:
	if bool(s["cut_now"]) == on:
		return
	s["cut_now"] = on
	(s["full"] as Node3D).visible = not on
	(s["cut"] as Node3D).visible = on


func _tree(k: Kit, p: Vector3, scale: float = 1.0) -> void:
	var h := rng.randf_range(2.2, 3.2) * scale
	k.cyl(p, 0.18 * scale, h, Color("#5a4330"))
	var g := Color("#3f6b35").lerp(Color("#6b8f3a"), rng.randf())
	k.sphere(p + Vector3(0, h + 0.6 * scale, 0), Vector3(3.0, 2.4, 3.0) * scale, g)
	k.sphere(p + Vector3(0.6, h + 1.4 * scale, 0.3), Vector3(2.2, 1.8, 2.2) * scale, g.lightened(0.08))
	k.sphere(p + Vector3(-0.5, h + 1.1 * scale, -0.4), Vector3(2.0, 1.6, 2.0) * scale, g.darkened(0.08))


func _car(k: Kit, p: Vector3, rot: float, col: Color) -> void:
	var b := Basis(Vector3.UP, rot)
	var xf := Transform3D(b, p)
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(1.8, 0.7, 4.2)), Vector3(0, 0.65, 0)), col)
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(1.6, 0.6, 2.2)), Vector3(0, 1.25, -0.2)), col.lightened(0.1))
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(1.64, 0.45, 2.0)), Vector3(0, 1.25, -0.2)), Color("#1d2630"))
	for wx in [-0.85, 0.85]:
		for wz in [-1.35, 1.35]:
			k.add("cyl", xf * Transform3D(Basis(Vector3.FORWARD, PI / 2.0).scaled(Vector3(0.7, 0.3, 0.7)), Vector3(wx, 0.35, wz)), Color("#141414"))
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(1.5, 0.18, 0.05)), Vector3(0, 0.75, 2.11)), Color("#f2eccc"))
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(1.5, 0.16, 0.05)), Vector3(0, 0.8, -2.11)), Color("#8c1c1c"))


func _bench(k: Kit, p: Vector3, rot: float) -> void:
	var b := Basis(Vector3.UP, rot)
	k.add("box", Transform3D(b.scaled(Vector3(1.8, 0.08, 0.5)), p + Vector3(0, 0.45, 0)), Color("#7a5534"))
	k.add("box", Transform3D(b.scaled(Vector3(1.8, 0.4, 0.08)), p + b * Vector3(0, 0.75, -0.22)), Color("#7a5534"))
	for dx in [-0.75, 0.75]:
		k.add("box", Transform3D(b.scaled(Vector3(0.08, 0.45, 0.45)), p + b * Vector3(dx, 0.22, 0)), Color("#2b2b2b"))


func _lamp(k: Kit, p: Vector3) -> void:
	k.cyl(p, 0.09, 5.2, Color("#2c2f33"))
	k.box(p + Vector3(0.6, 5.15, 0), Vector3(1.4, 0.12, 0.14), Color("#2c2f33"))
	k.box(p + Vector3(1.2, 5.0, 0), Vector3(0.5, 0.2, 0.3), Color("#e9e1c4"))
	lamp_spots.append(p + Vector3(1.2, 4.7, 0))


# ---------- chão, ruas e calçadas ----------

func _ground() -> void:
	var k := Kit.new()
	var S := Layout.SIZE
	k.box_ab(Vector3(-60, -0.2, -60), Vector3(S + 60, 0.12, S + 60), ASPHALT)
	# faixas e faixas de pedestre
	for i in Layout.GRID + 1:
		var line := i * Layout.PITCH + Layout.STREET / 2.0
		for j in Layout.GRID:
			var a := j * Layout.PITCH + Layout.STREET + 2.0
			var x := a
			while x < a + Layout.BLOCK - 4.0:
				k.box_ab(Vector3(x, 0.12, line - 0.08), Vector3(x + 1.6, 0.14, line + 0.08), LINE)
				k.box_ab(Vector3(line - 0.08, 0.12, x), Vector3(line + 0.08, 0.14, x + 1.6), LINE)
				x += 3.2
	for i in Layout.GRID + 1:
		for j in Layout.GRID + 1:
			var c := Vector2(i * Layout.PITCH + Layout.STREET / 2.0, j * Layout.PITCH + Layout.STREET / 2.0)
			for s in 6:
				var off := -3.0 + s * 1.2
				k.box_ab(Vector3(c.x + off, 0.12, c.y + 5.6), Vector3(c.x + off + 0.6, 0.14, c.y + 7.4), LINE)
				k.box_ab(Vector3(c.x + 5.6, 0.12, c.y + off), Vector3(c.x + 7.4, 0.14, c.y + off + 0.6), LINE)
			if (i + j) % 2 == 0 and i < Layout.GRID + 1:
				_lamp(k, Vector3(c.x + 5.8, 0, c.y + 5.8))
	# calçadas de cada quarteirão
	for c in layout.blocks:
		var r := Layout.block_rect(c)
		k.box_ab(Vector3(r.position.x - 0.3, 0.0, r.position.y - 0.3), Vector3(r.end.x + 0.3, 0.16, r.end.y + 0.3), CURB)
		k.box_ab(Vector3(r.position.x, 0.0, r.position.y), Vector3(r.end.x, 0.17, r.end.y), SIDEWALK)
		# carros estacionados no meio-fio
		for side in 2:
			if rng.randf() < 0.55:
				var cx := rng.randf_range(r.position.x + 4, r.end.x - 4)
				var z := r.end.y + 1.6 if side == 0 else r.position.y - 1.6
				_car(k, Vector3(cx, 0.12, z), PI / 2.0, _car_color())
	_mesh(k, self)


func _car_color() -> Color:
	var cols := [Color("#b9bcc0"), Color("#2b2d31"), Color("#8b1e1e"), Color("#e8e6df"), Color("#1f3d6b"), Color("#6b6f3a"), Color("#8a8d90"), Color("#c47a1e")]
	return cols[rng.randi() % cols.size()]


# ---------- prédios genéricos (casas, edifícios) ----------

func _simple_building(rect: Rect2, height: float, wall: Color, roof: Color, gable: bool, floors: int = 1) -> void:
	var s := _structure(rect)
	var k := Kit.new()
	var kc := Kit.new()
	var kw := Kit.new()
	var kl := Kit.new()
	var lo := Vector3(rect.position.x, 0.17, rect.position.y)
	var hi := Vector3(rect.end.x, 0.17 + height, rect.end.y)
	k.box_ab(lo, hi, wall)
	# rodapé e faixas entre andares
	k.box_ab(lo - Vector3(0.05, 0, 0.05), Vector3(hi.x + 0.05, lo.y + 0.5, hi.z + 0.05), wall.darkened(0.25))
	var fh := height / floors
	for f in range(1, floors):
		k.box_ab(Vector3(lo.x - 0.06, lo.y + f * fh - 0.1, lo.z - 0.06), Vector3(hi.x + 0.06, lo.y + f * fh + 0.05, hi.z + 0.06), wall.lightened(0.15))
	# janelas nas faces sul (+z) e leste (+x)
	for f in floors:
		var y := lo.y + f * fh + fh * 0.45
		var x := lo.x + 1.4
		while x < hi.x - 1.2:
			var target := kl if rng.randf() < 0.35 else kw
			target.box(Vector3(x, y, hi.z + 0.03), Vector3(1.0, 1.2, 0.06), Color.WHITE)
			k.box(Vector3(x, y - 0.68, hi.z + 0.08), Vector3(1.2, 0.1, 0.16), wall.lightened(0.2))
			x += 2.6
		var z := lo.z + 1.4
		while z < hi.z - 1.2:
			var target2 := kl if rng.randf() < 0.35 else kw
			target2.box(Vector3(hi.x + 0.03, y, z), Vector3(0.06, 1.2, 1.0), Color.WHITE)
			z += 2.6
	if floors == 1:
		k.box(Vector3(rect.get_center().x, lo.y + 1.05, hi.z + 0.04), Vector3(1.0, 2.1, 0.08), Color("#5b3b25"))
	if gable:
		k.gable(Vector3(rect.get_center().x, hi.y + 1.0, rect.get_center().y), Vector3(rect.size.x + 0.8, 2.0, rect.size.y + 0.8), roof)
	else:
		k.box_ab(Vector3(lo.x - 0.1, hi.y, lo.z - 0.1), Vector3(hi.x + 0.1, hi.y + 0.25, hi.z + 0.1), roof)
		k.box_ab(Vector3(lo.x, hi.y + 0.25, lo.z), Vector3(hi.x, hi.y + 0.6, lo.z + 0.25), roof.darkened(0.2))
		if floors > 2:
			k.cyl(Vector3(lo.x + 3, hi.y + 0.25, lo.z + 3), 1.2, 1.8, Color("#4c6b8a"))
	_mesh(k, s["full"])
	_mesh(kw, s["full"], glass_mat)
	_mesh(kl, s["full"], lit_mat)
	# versão cortada: piso e paredes baixas
	kc.box_ab(lo, Vector3(hi.x, lo.y + 0.05, hi.z), Color("#7b6a55"))
	kc.box_ab(lo, Vector3(hi.x, lo.y + CUT_H, lo.z + WALL_T), wall)
	kc.box_ab(lo, Vector3(lo.x + WALL_T, lo.y + CUT_H, hi.z), wall)
	kc.box_ab(Vector3(lo.x, lo.y, hi.z - WALL_T), Vector3(hi.x, lo.y + CUT_H, hi.z), wall)
	kc.box_ab(Vector3(hi.x - WALL_T, lo.y, lo.z), Vector3(hi.x, lo.y + CUT_H, hi.z), wall)
	_mesh(kc, s["cut"])
	_collider(rect, height)


func _house_colors() -> Array:
	var walls := [Color("#d9c9a8"), Color("#b7c4b0"), Color("#c9a68a"), Color("#e2ddd0"), Color("#a7b6c4"), Color("#d4b483"), Color("#c98f7a"), Color("#e8d7a8")]
	var roofs := [Color("#8a3b2c"), Color("#6b4a3a"), Color("#4a4f55"), Color("#7a5b3a")]
	return [walls[rng.randi() % walls.size()], roofs[rng.randi() % roofs.size()]]


func _build_filler(c: Vector2i, info: Dictionary) -> void:
	var r := Layout.block_rect(c)
	var k := Kit.new()
	match str(info["kind"]):
		"casas":
			k.box_ab(Vector3(r.position.x + 1, 0.17, r.position.y + 1), Vector3(r.end.x - 1, 0.19, r.end.y - 1), GRASS)
			for ix in 2:
				for iz in 2:
					var cell := Rect2(r.position.x + 1 + ix * 14.0, r.position.y + 1 + iz * 14.0, 14.0, 14.0)
					var w := rng.randf_range(8.0, 10.0)
					var d := rng.randf_range(7.0, 8.5)
					var hr := Rect2(cell.get_center().x - w / 2.0, cell.position.y + 1.5, w, d)
					var cols := _house_colors()
					_simple_building(hr, 3.0, cols[0], cols[1], true)
					# muro baixo na frente
					k.box_ab(Vector3(cell.position.x + 0.3, 0.17, cell.end.y - 0.4), Vector3(cell.get_center().x - 1.0, 0.95, cell.end.y - 0.2), cols[0].darkened(0.15))
					k.box_ab(Vector3(cell.get_center().x + 1.0, 0.17, cell.end.y - 0.4), Vector3(cell.end.x - 0.3, 0.95, cell.end.y - 0.2), cols[0].darkened(0.15))
					k.box_ab(Vector3(cell.get_center().x - 0.9, 0.19, hr.end.y), Vector3(cell.get_center().x + 0.9, 0.21, cell.end.y - 0.3), Color("#9a958a"))
					if rng.randf() < 0.5:
						_tree(k, Vector3(cell.position.x + 2.0, 0.17, cell.end.y - 2.2), 0.8)
					if rng.randf() < 0.3:
						_car(k, Vector3(cell.end.x - 2.2, 0.19, cell.end.y - 3.4), 0.0, _car_color())
		"predio":
			var hr := Rect2(r.position.x + 4, r.position.y + 4, r.size.x - 8, r.size.y - 9)
			var floors := rng.randi_range(3, 6)
			var walls := [Color("#a39b8f"), Color("#7f8a8f"), Color("#b5a48a"), Color("#8f7f73"), Color("#c2b8a3")]
			_simple_building(hr, floors * 3.0, walls[rng.randi() % walls.size()], Color("#55575a"), false, floors)
			k.box_ab(Vector3(hr.get_center().x - 1.4, 0.17, hr.end.y), Vector3(hr.get_center().x + 1.4, 2.6, hr.end.y + 1.6), Color("#3d3f42"))
			for i in 3:
				_tree(k, Vector3(r.position.x + 3 + i * 12, 0.17, r.end.y - 1.8), 0.7)
		"terreno":
			k.box_ab(Vector3(r.position.x + 0.5, 0.17, r.position.y + 0.5), Vector3(r.end.x - 0.5, 0.2, r.end.y - 0.5), DIRT)
			for i in 30:
				k.sphere(Vector3(rng.randf_range(r.position.x + 2, r.end.x - 2), 0.3, rng.randf_range(r.position.y + 2, r.end.y - 2)), Vector3(0.9, 0.5, 0.9), GRASS2.darkened(rng.randf() * 0.2))
			for x in range(int(r.position.x) + 1, int(r.end.x), 3):
				k.box(Vector3(x, 0.9, r.end.y - 0.5), Vector3(0.08, 1.5, 0.08), Color("#6a6a6a"))
			k.box_ab(Vector3(r.position.x + 1, 1.5, r.end.y - 0.52), Vector3(r.end.x - 1, 1.55, r.end.y - 0.48), Color("#6a6a6a"))
			_car(k, Vector3(r.get_center().x + 4, 0.0, r.get_center().y), 0.6, Color("#6b4a2e"))
		"estacionamento":
			k.box_ab(Vector3(r.position.x + 0.5, 0.17, r.position.y + 0.5), Vector3(r.end.x - 0.5, 0.19, r.end.y - 0.5), Color("#45474a"))
			for i in 8:
				var x := r.position.x + 3.0 + i * 3.4
				k.box_ab(Vector3(x, 0.19, r.position.y + 2), Vector3(x + 0.12, 0.2, r.position.y + 8), LINE)
				k.box_ab(Vector3(x, 0.19, r.end.y - 9), Vector3(x + 0.12, 0.2, r.end.y - 3), LINE)
				if rng.randf() < 0.6:
					_car(k, Vector3(x + 1.7, 0.19, r.position.y + 5), 0.0, _car_color())
				if rng.randf() < 0.5:
					_car(k, Vector3(x + 1.7, 0.19, r.end.y - 6), PI, _car_color())
		"verde":
			k.box_ab(Vector3(r.position.x + 1, 0.17, r.position.y + 1), Vector3(r.end.x - 1, 0.2, r.end.y - 1), GRASS)
			for i in 9:
				_tree(k, Vector3(rng.randf_range(r.position.x + 3, r.end.x - 3), 0.2, rng.randf_range(r.position.y + 3, r.end.y - 3)), rng.randf_range(0.8, 1.2))
			_bench(k, Vector3(r.get_center().x, 0.2, r.end.y - 3), 0.0)
	_mesh(k, self)


# ---------- locais do jogo ----------

const INTERIOR_FLOOR := {
	"bar": Color("#6e4a2f"), "loja": Color("#d7d2c6"), "comida": Color("#c9b98f"), "casa": Color("#8a6a48"),
	"hospedagem": Color("#7a5a3c"), "servico": Color("#c8d0c8"), "igreja": Color("#9b8f80"),
}
const WALL_COLORS := {
	"bar": Color("#7c4a33"), "loja": Color("#d9d4c3"), "comida": Color("#e0c27a"), "casa": Color("#c9b08a"),
	"hospedagem": Color("#b78c6a"), "servico": Color("#dfe4df"), "igreja": Color("#e6dccb"),
}


func _build_location(id: String, c: Vector2i) -> void:
	var lot: Dictionary = layout.lots[id]
	var r: Rect2 = lot["rect"]
	var loc: Dictionary = World.locations[id]
	var b: Rect2 = lot["building"]
	var k := Kit.new()
	match id:
		"praca":
			_praca(k, r)
		"parque":
			_parque(k, r)
		"rodoviaria":
			_rodoviaria(k, r)
		"beco":
			_beco(k, r)
		"rua_acacias":
			_acacias(k, r)
		_:
			if b.size == Vector2.ZERO:
				k.box_ab(Vector3(r.position.x + 1, 0.17, r.position.y + 1), Vector3(r.end.x - 1, 0.19, r.end.y - 1), Color("#9f9a8f"))
	if b.size != Vector2.ZERO:
		var tipo := str(loc.get("tipo", "casa"))
		if id == "hospital" or id == "delegacia":
			tipo = "servico"
		if id == "igreja":
			tipo = "igreja"
		# quintal/frente
		var yard := GRASS if tipo in ["casa", "hospedagem", "igreja"] else Color("#9f9a8f")
		k.box_ab(Vector3(r.position.x + 1, 0.17, r.position.y + 1), Vector3(r.end.x - 1, 0.19, r.end.y - 1), yard)
		k.box_ab(Vector3(lot["door_x"] - 1.2, 0.19, b.end.y), Vector3(lot["door_x"] + 1.2, 0.21, r.end.y), Color("#a8a397"))
		if tipo in ["casa", "hospedagem", "igreja"]:
			for i in 3:
				_tree(k, Vector3(r.position.x + 2.5 + i * 12.5, 0.19, r.position.y + 2.5), 0.9)
		_location_building(id, tipo, b)
	_mesh(k, self)


func _location_building(id: String, tipo: String, b: Rect2) -> void:
	var s := _structure(b, id)
	var wall: Color = WALL_COLORS.get(tipo, Color("#cfc6b5"))
	if id == "delegacia":
		wall = Color("#9fb0c4")
	var floor_c: Color = INTERIOR_FLOOR.get(tipo, Color("#9a8a70"))
	var y0 := 0.17
	var door_x: float = layout.lots[id]["door_x"]
	var h := WALL_H if tipo != "igreja" else 5.0
	var always := Kit.new()    # piso e móveis: aparecem nas duas versões
	var kf := Kit.new()
	var kc := Kit.new()
	var kw := Kit.new()
	var kl := Kit.new()
	always.box_ab(Vector3(b.position.x, y0, b.position.y), Vector3(b.end.x, y0 + 0.06, b.end.y), floor_c)
	# piso em xadrez para lojas/serviços
	if tipo in ["loja", "comida", "servico"]:
		var x := b.position.x + 0.3
		var alt := false
		while x < b.end.x - 0.3:
			var z := b.position.y + 0.3
			var alt2 := alt
			while z < b.end.y - 0.3:
				if alt2:
					always.box_ab(Vector3(x, y0 + 0.06, z), Vector3(minf(x + 1.0, b.end.x - 0.3), y0 + 0.065, minf(z + 1.0, b.end.y - 0.3)), floor_c.darkened(0.12))
				alt2 = not alt2
				z += 1.0
			alt = not alt
			x += 1.0
	for kk in [kf, kc]:
		var hh: float = h if kk == kf else CUT_H
		var top: float = y0 + hh
		var kit: Kit = kk
		kit.box_ab(Vector3(b.position.x, y0, b.position.y), Vector3(b.end.x, top, b.position.y + WALL_T), wall)
		kit.box_ab(Vector3(b.position.x, y0, b.position.y), Vector3(b.position.x + WALL_T, top, b.end.y), wall)
		kit.box_ab(Vector3(b.end.x - WALL_T, y0, b.position.y), Vector3(b.end.x, top, b.end.y), wall)
		kit.box_ab(Vector3(b.position.x, y0, b.end.y - WALL_T), Vector3(door_x - 0.9, top, b.end.y), wall)
		kit.box_ab(Vector3(door_x + 0.9, y0, b.end.y - WALL_T), Vector3(b.end.x, top, b.end.y), wall)
		if kk == kf:
			kit.box_ab(Vector3(door_x - 0.9, y0 + 2.3, b.end.y - WALL_T), Vector3(door_x + 0.9, top, b.end.y), wall)
		# rodapé externo
		kit.box_ab(Vector3(b.position.x - 0.04, y0, b.end.y - 0.02), Vector3(door_x - 0.9, y0 + 0.4, b.end.y + 0.04), wall.darkened(0.3))
		kit.box_ab(Vector3(door_x + 0.9, y0, b.end.y - 0.02), Vector3(b.end.x + 0.04, y0 + 0.4, b.end.y + 0.04), wall.darkened(0.3))
	# vitrines/janelas
	var wy := y0 + 1.6
	var x2 := b.position.x + 1.6
	while x2 < b.end.x - 1.4:
		if absf(x2 - door_x) > 2.0:
			var shop := tipo in ["loja", "comida", "bar"]
			var target := kl if (shop or rng.randf() < 0.5) else kw
			target.box(Vector3(x2, wy, b.end.y + 0.02), Vector3(1.8 if shop else 1.1, 1.4 if shop else 1.1, 0.05), Color.WHITE)
		x2 += 2.8 if tipo in ["loja", "comida", "bar"] else 3.0
	var z2 := b.position.y + 1.6
	while z2 < b.end.y - 1.4:
		kw.box(Vector3(b.end.x + 0.02, wy, z2), Vector3(0.05, 1.1, 1.1), Color.WHITE)
		z2 += 3.0
	# toldo e letreiro
	var awning := {"bar": Color("#7d1f1f"), "comida": Color("#c0392b"), "loja": Color("#1f6f4a"), "servico": Color("#2c5d8f"), "hospedagem": Color("#6b4a2b")}
	if awning.has(tipo):
		var ac: Color = awning[tipo]
		if id == "hospital":
			ac = Color("#b02a2a")
		kf.box_ab(Vector3(door_x - 2.6, y0 + 2.5, b.end.y), Vector3(door_x + 2.6, y0 + 2.62, b.end.y + 1.3), ac)
		kc.box_ab(Vector3(door_x - 0.05, y0, b.end.y + 3.0), Vector3(door_x + 0.05, y0 + 0.01, b.end.y + 3.01), ac)
	# telhado
	if tipo in ["casa", "hospedagem"]:
		kf.gable(Vector3(b.get_center().x, y0 + h + 1.1, b.get_center().y), Vector3(b.size.x + 0.9, 2.2, b.size.y + 0.9), Color("#7c3a2a"))
	elif tipo == "igreja":
		kf.gable(Vector3(b.get_center().x, y0 + h + 1.6, b.get_center().y), Vector3(b.size.x + 0.8, 3.2, b.size.y + 0.6), Color("#5a4636"), false)
		kf.box_ab(Vector3(door_x - 1.6, y0, b.end.y - 3.2), Vector3(door_x + 1.6, y0 + h + 6.0, b.end.y), wall)
		kf.cone(Vector3(door_x, y0 + h + 6.0, b.end.y - 1.6), 2.1, 3.2, Color("#5a4636"))
		kf.box(Vector3(door_x, y0 + h + 10.0, b.end.y - 1.6), Vector3(0.18, 1.4, 0.18), Color("#d9c27a"))
		kf.box(Vector3(door_x, y0 + h + 10.2, b.end.y - 1.6), Vector3(0.9, 0.18, 0.18), Color("#d9c27a"))
	else:
		kf.box_ab(Vector3(b.position.x - 0.15, y0 + h, b.position.y - 0.15), Vector3(b.end.x + 0.15, y0 + h + 0.3, b.end.y + 0.15), wall.darkened(0.35))
		kf.box_ab(Vector3(b.position.x + 2, y0 + h + 0.3, b.position.y + 2), Vector3(b.position.x + 4.5, y0 + h + 1.4, b.position.y + 3.6), Color("#6d7073"))
	if id == "hospital":
		kf.box(Vector3(b.end.x - 3, y0 + h + 0.9, b.end.y - 3), Vector3(3.0, 0.1, 0.8), Color("#e8e8e8"))
		kf.box(Vector3(b.end.x - 3, y0 + h + 0.9, b.end.y - 3), Vector3(0.8, 0.1, 3.0), Color("#e8e8e8"))
		kf.box(Vector3(door_x + 3.5, y0 + 2.9, b.end.y + 0.1), Vector3(1.2, 0.35, 0.1), Color("#d03030"))
		kf.box(Vector3(door_x + 3.5, y0 + 2.9, b.end.y + 0.1), Vector3(0.35, 1.2, 0.1), Color("#d03030"))
	_furnish(always, id, tipo, b, y0)
	_mesh(always, s["root"])
	_mesh(kf, s["full"])
	_mesh(kw, s["full"], glass_mat)
	_mesh(kl, s["full"], lit_mat)
	_mesh(kc, s["cut"])
	# letreiro
	var sign := Label3D.new()
	sign.text = str(World.locations[id]["nome"]).to_upper()
	sign.font_size = 72
	sign.pixel_size = 0.006
	sign.outline_size = 14
	sign.modulate = Color("#fff3d6")
	sign.outline_modulate = Color(0.08, 0.06, 0.05)
	sign.position = Vector3(door_x, y0 + (2.85 if tipo != "igreja" else 4.3), b.end.y + 0.25)
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	s["full"].add_child(sign)
	# colisão das paredes (porta tem bloqueio próprio)
	_collider(Rect2(b.position.x, b.position.y, b.size.x, WALL_T))
	_collider(Rect2(b.position.x, b.position.y, WALL_T, b.size.y))
	_collider(Rect2(b.end.x - WALL_T, b.position.y, WALL_T, b.size.y))
	_collider(Rect2(b.position.x, b.end.y - WALL_T, door_x - 0.9 - b.position.x, WALL_T))
	_collider(Rect2(door_x + 0.9, b.end.y - WALL_T, b.end.x - door_x - 0.9, WALL_T))
	var door := _collider(Rect2(door_x - 0.9, b.end.y - WALL_T, 1.8, WALL_T))
	var dk := Kit.new()
	dk.box(Vector3(door_x, y0 + 1.15, b.end.y - WALL_T / 2.0), Vector3(1.8, 2.3, 0.12), Color("#5b3b25") if tipo in ["casa", "hospedagem", "igreja"] else Color("#7c8186"))
	dk.box(Vector3(door_x + 0.6, y0 + 1.1, b.end.y + 0.0), Vector3(0.08, 0.08, 0.1), Color("#d9c27a"))
	var door_mesh := _mesh(dk, s["root"])
	var light := OmniLight3D.new()
	light.position = Vector3(b.get_center().x, y0 + 2.7, b.get_center().y)
	light.omni_range = maxf(b.size.x, b.size.y) * 0.85
	light.light_color = Color("#ffe1ad") if tipo not in ["servico", "loja"] else Color("#e9f3ff")
	light.light_energy = 0.9
	s["root"].add_child(light)
	loc_info[id] = {"door": door, "door_mesh": door_mesh, "light": light, "sign": sign, "structure": s}


# ---------- móveis ----------

func _furnish(k: Kit, id: String, tipo: String, b: Rect2, y0: float) -> void:
	var cx := b.get_center().x
	var top := b.position.y
	match tipo:
		"bar":
			k.box_ab(Vector3(b.position.x + 1.2, y0, top + 2.2), Vector3(b.end.x - 3.5, y0 + 1.1, top + 3.0), Color("#5a3520"))
			k.box_ab(Vector3(b.position.x + 1.1, y0 + 1.1, top + 2.1), Vector3(b.end.x - 3.4, y0 + 1.2, top + 3.1), Color("#3a2416"))
			k.box_ab(Vector3(b.position.x + 0.6, y0, top + 0.35), Vector3(b.end.x - 0.6, y0 + 2.2, top + 0.8), Color("#4a2e1c"))
			for i in 14:
				k.cyl(Vector3(b.position.x + 1.0 + i * 0.7, y0 + 1.2, top + 0.55), 0.09, 0.4, [Color("#3f7a3a"), Color("#8a5a20"), Color("#d8d0b0"), Color("#5a2020")][i % 4])
			for i in 5:
				k.cyl(Vector3(b.position.x + 1.8 + i * 1.6, y0, top + 3.7), 0.22, 0.75, Color("#2a2a2a"))
			for t in 3:
				var p := Vector3(b.position.x + 2.5 + t * 3.5, y0, b.end.y - 3.0)
				k.cyl(p, 0.55, 0.78, Color("#6a4a2a"))
				for a in 3:
					var ang := a * TAU / 3.0
					k.box(p + Vector3(cos(ang), 0.25, sin(ang)), Vector3(0.45, 0.5, 0.45), Color("#8a1f1f"))
			k.box_ab(Vector3(b.end.x - 2.6, y0, top + 0.6), Vector3(b.end.x - 0.6, y0 + 0.8, top + 1.6), Color("#2c5f2c"))
		"loja":
			for row in 4:
				var z := top + 2.0 + row * 2.5
				if z > b.end.y - 4.0:
					break
				k.box_ab(Vector3(b.position.x + 1.5, y0, z), Vector3(b.end.x - 5.5, y0 + 1.7, z + 0.8), Color("#cfcac0"))
				for i in 22:
					var px := b.position.x + 1.8 + i * 0.55
					if px > b.end.x - 5.8:
						break
					for lvl in 3:
						k.box(Vector3(px, y0 + 0.35 + lvl * 0.55, z + 0.4), Vector3(0.4, 0.38, 0.6), Color.from_hsv(fmod(i * 0.13 + row * 0.31 + lvl * 0.17, 1.0), 0.55, 0.8))
			k.box_ab(Vector3(b.end.x - 4.6, y0, b.end.y - 4.0), Vector3(b.end.x - 1.4, y0 + 1.0, b.end.y - 3.0), Color("#3e4a52"))
			k.box(Vector3(b.end.x - 3.0, y0 + 1.25, b.end.y - 3.5), Vector3(0.5, 0.4, 0.4), Color("#1b1b1b"))
			k.box_ab(Vector3(b.end.x - 4.6, y0, top + 1.0), Vector3(b.end.x - 1.0, y0 + 2.0, top + 2.0), Color("#e8f2f6"))
		"comida":
			k.box_ab(Vector3(b.position.x + 1.0, y0, top + 2.4), Vector3(b.end.x - 4.0, y0 + 1.05, top + 3.2), Color("#b03a2e"))
			k.box_ab(Vector3(b.position.x + 0.9, y0 + 1.05, top + 2.3), Vector3(b.end.x - 3.9, y0 + 1.15, top + 3.3), Color("#e9e4d8"))
			k.box_ab(Vector3(b.position.x + 1.6, y0 + 1.15, top + 2.5), Vector3(b.position.x + 4.0, y0 + 1.7, top + 3.0), Color(0.85, 0.9, 0.95))
			for i in 4:
				k.sphere(Vector3(b.position.x + 2.0 + i * 0.6, y0 + 1.3, top + 2.75), Vector3(0.35, 0.22, 0.25), Color("#d9902c"))
			k.box_ab(Vector3(b.position.x + 0.5, y0, top + 0.35), Vector3(b.end.x - 0.5, y0 + 0.95, top + 1.1), Color("#c9c9c9"))
			for i in 4:
				k.cyl(Vector3(b.position.x + 1.6 + i * 1.5, y0, top + 3.9), 0.22, 0.75, Color("#d8d8d8"))
			for t in 3:
				var p := Vector3(b.position.x + 2.4 + t * 3.8, y0, b.end.y - 2.6)
				k.box(p + Vector3(0, 0.72, 0), Vector3(1.4, 0.06, 1.0), Color("#efefef"))
				k.box(p + Vector3(0, 0.36, 0), Vector3(0.1, 0.72, 0.1), Color("#888888"))
				for side in [-1, 1]:
					k.box(p + Vector3(side * 1.0, 0.25, 0), Vector3(0.45, 0.5, 0.45), Color("#c0392b"))
		"casa":
			var bed := Vector3(b.position.x + 2.2, y0, top + 2.0)
			k.box_ab(bed, bed + Vector3(2.0, 0.55, 2.8), Color("#e6e1d6"))
			k.box_ab(bed + Vector3(0, 0, 0.9), bed + Vector3(2.0, 0.6, 2.8), Color("#3e5a80"))
			k.box_ab(bed + Vector3(0.2, 0.55, 0.15), bed + Vector3(1.8, 0.75, 0.7), Color.WHITE)
			k.box_ab(Vector3(b.end.x - 3.5, y0, top + 0.5), Vector3(b.end.x - 0.6, y0 + 0.95, top + 1.2), Color("#d0c8b8"))
			k.box_ab(Vector3(b.end.x - 1.5, y0, top + 0.5), Vector3(b.end.x - 0.6, y0 + 1.9, top + 1.3), Color("#e8e8e8"))
			k.box_ab(Vector3(cx - 1.4, y0, b.end.y - 3.0), Vector3(cx + 1.4, y0 + 0.75, b.end.y - 2.2), Color("#6a5240"))
			k.box_ab(Vector3(b.position.x + 1.0, y0, b.end.y - 2.6), Vector3(b.position.x + 3.6, y0 + 0.08, b.end.y - 1.0), Color("#8a3b3b"))
		"hospedagem":
			k.box_ab(Vector3(b.position.x + 1.2, y0, b.end.y - 4.0), Vector3(b.position.x + 4.5, y0 + 1.05, b.end.y - 3.2), Color("#5a3a22"))
			k.box_ab(Vector3(b.position.x + 0.5, y0, top + 5.0), Vector3(b.end.x - 0.5, y0 + WALL_H, top + 5.25), Color("#b78c6a"))
			for room in 3:
				var rx := b.position.x + 1.0 + room * (b.size.x / 3.0)
				k.box_ab(Vector3(rx, y0, top + 1.0), Vector3(rx + 1.8, y0 + 0.5, top + 3.4), Color("#d8d0c0"))
				k.box_ab(Vector3(rx, y0, top + 2.0), Vector3(rx + 1.8, y0 + 0.55, top + 3.4), Color("#6b4a7a"))
		"servico":
			if id == "hospital":
				for i in 5:
					var p := Vector3(b.position.x + 2.0 + i * 4.2, y0, top + 1.2)
					k.box_ab(p, p + Vector3(1.2, 0.7, 2.4), Color("#eef2f4"))
					k.box_ab(p + Vector3(0, 0.7, 0), p + Vector3(1.2, 0.8, 0.6), Color.WHITE)
					k.box_ab(p + Vector3(1.4, 0, 0), p + Vector3(1.5, 1.6, 2.4), Color("#9fc6c0"))
				k.box_ab(Vector3(cx - 3.0, y0, b.end.y - 5.0), Vector3(cx + 3.0, y0 + 1.1, b.end.y - 4.2), Color("#e2e6e8"))
				for i in 8:
					k.box(Vector3(b.position.x + 2.0 + i * 0.7, y0 + 0.25, b.end.y - 2.0), Vector3(0.5, 0.5, 0.5), Color("#3a6f9a"))
			else:
				for i in 3:
					var p := Vector3(b.position.x + 2.5 + i * 4.5, y0, top + 3.0)
					k.box_ab(p, p + Vector3(2.0, 0.78, 1.0), Color("#7a5a3a"))
					k.box(p + Vector3(1.0, 1.0, 0.4), Vector3(0.6, 0.4, 0.05), Color("#1a1a1a"))
				k.box_ab(Vector3(b.end.x - 4.5, y0, top + 0.4), Vector3(b.end.x - 0.4, y0 + WALL_H, top + 0.6), Color("#3a3a3a"))
				for i in 7:
					k.box_ab(Vector3(b.end.x - 4.4 + i * 0.6, y0, top + 0.6), Vector3(b.end.x - 4.32 + i * 0.6, y0 + 2.4, top + 3.0), Color("#585858"))
				k.box_ab(Vector3(cx - 2.0, y0, b.end.y - 4.0), Vector3(cx + 2.0, y0 + 1.1, b.end.y - 3.2), Color("#5b6b7c"))
		"igreja":
			for row in 6:
				for side in [-1, 1]:
					var z := top + 4.0 + row * 1.8
					k.box_ab(Vector3(cx + side * 1.0, y0, z), Vector3(cx + side * 4.6, y0 + 0.5, z + 0.5), Color("#6b4a2b"))
					k.box_ab(Vector3(cx + side * 1.0, y0, z + 0.5), Vector3(cx + side * 4.6, y0 + 1.0, z + 0.6), Color("#5a3d22"))
			k.box_ab(Vector3(cx - 2.0, y0, top + 1.0), Vector3(cx + 2.0, y0 + 1.0, top + 2.2), Color("#e8e0d0"))
			k.box(Vector3(cx, y0 + 2.6, top + 0.5), Vector3(0.2, 2.2, 0.15), Color("#d9c27a"))
			k.box(Vector3(cx, y0 + 3.1, top + 0.5), Vector3(1.2, 0.2, 0.15), Color("#d9c27a"))
			k.box_ab(Vector3(cx - 0.7, y0, top + 3.0), Vector3(cx + 0.7, y0 + 0.02, b.end.y - 0.5), Color("#8a1f2a"))


# ---------- locais abertos ----------

func _praca(k: Kit, r: Rect2) -> void:
	var c := r.get_center()
	k.box_ab(Vector3(r.position.x + 0.5, 0.17, r.position.y + 0.5), Vector3(r.end.x - 0.5, 0.2, r.end.y - 0.5), Color("#b0a896"))
	for i in 8:
		for j in 8:
			if (i + j) % 2 == 0:
				k.box_ab(Vector3(r.position.x + 1 + i * 3.5, 0.2, r.position.y + 1 + j * 3.5), Vector3(r.position.x + 2.75 + i * 3.5, 0.21, r.position.y + 2.75 + j * 3.5), Color("#a39b88"))
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var gc: Vector2 = c + corner * 9.0
		k.box_ab(Vector3(gc.x - 4, 0.2, gc.y - 4), Vector3(gc.x + 4, 0.35, gc.y + 4), Color("#5a4632"))
		k.box_ab(Vector3(gc.x - 3.8, 0.35, gc.y - 3.8), Vector3(gc.x + 3.8, 0.4, gc.y + 3.8), GRASS)
		_tree(k, Vector3(gc.x, 0.4, gc.y), 1.25)
		_bench(k, Vector3(gc.x, 0.2, gc.y - corner.y * 5.0), 0.0 if corner.y > 0 else PI)
	k.cyl(Vector3(c.x, 0.2, c.y), 3.2, 0.6, Color("#c9c1ae"))
	k.cyl(Vector3(c.x, 0.2, c.y), 0.4, 2.2, Color("#c9c1ae"))
	k.sphere(Vector3(c.x, 2.4, c.y), Vector3(1.2, 0.5, 1.2), Color("#c9c1ae"))
	var water := Kit.new()
	water.cyl(Vector3(c.x, 0.5, c.y), 2.9, 0.15, Color.WHITE)
	_mesh(water, self, water_mat)
	# carrinho de pipoca
	var cart := Vector3(r.position.x + 5, 0.2, r.end.y - 4)
	k.box_ab(cart, cart + Vector3(1.6, 1.1, 1.0), Color("#c0392b"))
	k.box_ab(cart + Vector3(0.1, 1.1, 0.1), cart + Vector3(1.5, 1.8, 0.9), Color(0.95, 0.95, 0.9))
	k.box_ab(cart + Vector3(-0.2, 2.2, -0.2), cart + Vector3(1.8, 2.3, 1.2), Color("#f1c40f"))
	festa_node = Node3D.new()
	festa_node.visible = false
	add_child(festa_node)
	var fk := Kit.new()
	var cols := [Color("#ff5d6c"), Color("#ffd166"), Color("#4fd1b5"), Color("#5aa9e6"), Color("#c792ea")]
	for line in 4:
		var a := Vector3(r.position.x + 1, 4.0, r.position.y + 4 + line * 7.0)
		var bb := Vector3(r.end.x - 1, 4.0, r.position.y + 4 + line * 7.0)
		for i in 30:
			var u := i / 29.0
			var p := a.lerp(bb, u) + Vector3(0, -sin(u * PI) * 1.0, 0)
			fk.box(p - Vector3(0, 0.25, 0), Vector3(0.35, 0.45, 0.04), cols[(i + line) % cols.size()])
	for side in [0, 1]:
		var p := Vector3(r.position.x + 4 + side * 18.0, 0.2, r.position.y + 3)
		fk.box_ab(p, p + Vector3(4, 1.0, 2), Color("#3a2418"))
		fk.box_ab(p + Vector3(-0.2, 2.4, -0.2), p + Vector3(4.2, 2.55, 2.2), cols[side * 2])
		for post in [Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(0, 0, 2), Vector3(4, 0, 2)]:
			fk.box(p + post + Vector3(0, 1.2, 0), Vector3(0.1, 2.4, 0.1), Color("#3a2418"))
	_mesh(fk, festa_node, festa_mat)
	var fk2 := Kit.new()
	for line in 4:
		var a := Vector3(r.position.x + 1, 4.0, r.position.y + 4 + line * 7.0)
		var bb := Vector3(r.end.x - 1, 4.0, r.position.y + 4 + line * 7.0)
		for i in 30:
			var u := i / 29.0
			fk2.box(a.lerp(bb, u) + Vector3(0, -sin(u * PI) * 1.0, 0), Vector3(0.6, 0.03, 0.03), Color("#222222"))
	_mesh(fk2, festa_node)
	for i in 4:
		var l := OmniLight3D.new()
		l.position = Vector3(r.position.x + 4 + i * 7.5, 3.5, c.y)
		l.light_color = cols[i]
		l.omni_range = 9.0
		l.light_energy = 1.6
		festa_node.add_child(l)


func _parque(k: Kit, r: Rect2) -> void:
	var c := r.get_center()
	k.box_ab(Vector3(r.position.x + 0.5, 0.17, r.position.y + 0.5), Vector3(r.end.x - 0.5, 0.2, r.end.y - 0.5), GRASS)
	k.box_ab(Vector3(c.x - 1.2, 0.2, r.position.y + 0.5), Vector3(c.x + 1.2, 0.22, r.end.y - 0.5), Color("#b49d76"))
	k.box_ab(Vector3(r.position.x + 0.5, 0.2, c.y - 1.2), Vector3(r.end.x - 0.5, 0.22, c.y + 1.2), Color("#b49d76"))
	var lake := Kit.new()
	lake.cyl(Vector3(c.x + 7.5, 0.18, c.y - 7.5), 5.0, 0.08, Color.WHITE)
	_mesh(lake, self, water_mat)
	k.cyl(Vector3(c.x + 7.5, 0.17, c.y - 7.5), 5.4, 0.06, Color("#6b5a40"))
	for i in 22:
		var p := Vector2(rng.randf_range(r.position.x + 2, r.end.x - 2), rng.randf_range(r.position.y + 2, r.end.y - 2))
		if absf(p.x - c.x) < 2.5 or absf(p.y - c.y) < 2.5 or p.distance_to(Vector2(c.x + 7.5, c.y - 7.5)) < 6.5:
			continue
		_tree(k, Vector3(p.x, 0.2, p.y), rng.randf_range(0.9, 1.4))
	for i in 4:
		_bench(k, Vector3(c.x + 2.2, 0.2, r.position.y + 4 + i * 7.0), PI / 2.0)
	for i in 30:
		k.sphere(Vector3(rng.randf_range(r.position.x + 1, r.end.x - 1), 0.3, rng.randf_range(r.position.y + 1, r.end.y - 1)), Vector3(0.6, 0.35, 0.6), Color.from_hsv(rng.randf(), 0.5, 0.85) if rng.randf() < 0.3 else GRASS2)


func _rodoviaria(k: Kit, r: Rect2) -> void:
	k.box_ab(Vector3(r.position.x + 0.5, 0.17, r.position.y + 0.5), Vector3(r.end.x - 0.5, 0.2, r.end.y - 0.5), Color("#9c9890"))
	var plat := Rect2(r.position.x + 3, r.position.y + 4, r.size.x - 6, 9)
	k.box_ab(Vector3(plat.position.x, 0.2, plat.position.y), Vector3(plat.end.x, 0.5, plat.end.y), Color("#b8b2a4"))
	for i in 6:
		var x := plat.position.x + 0.5 + i * (plat.size.x - 1.0) / 5.0
		k.box(Vector3(x, 2.4, plat.position.y + 1), Vector3(0.25, 4.0, 0.25), Color("#3b4652"))
		k.box(Vector3(x, 2.4, plat.end.y - 1), Vector3(0.25, 4.0, 0.25), Color("#3b4652"))
	k.box_ab(Vector3(plat.position.x - 0.5, 4.4, plat.position.y - 0.5), Vector3(plat.end.x + 0.5, 4.6, plat.end.y + 0.5), Color("#5d7c8a"))
	for i in 4:
		_bench(k, Vector3(plat.position.x + 3 + i * 6, 0.5, plat.position.y + 4.5), 0.0)
	for bi in 2:
		var bx := plat.position.x + 2 + bi * 12.0
		var bz := plat.end.y + 4.5
		k.box_ab(Vector3(bx, 0.5, bz - 1.3), Vector3(bx + 10.5, 3.4, bz + 1.3), Color("#e5e2d8") if bi == 0 else Color("#2d6a9f"))
		k.box_ab(Vector3(bx + 0.4, 1.8, bz + 1.31), Vector3(bx + 10.1, 2.7, bz + 1.35), Color("#1d2630"))
		k.box_ab(Vector3(bx, 0.5, bz - 1.3), Vector3(bx + 10.5, 0.9, bz + 1.3), Color("#3b3b3b"))
		for wx in [1.8, 8.5]:
			k.add("cyl", Transform3D(Basis(Vector3.RIGHT, PI / 2.0).scaled(Vector3(1.0, 2.7, 1.0)), Vector3(bx + wx, 0.6, bz)), Color("#151515"))
	k.box_ab(Vector3(r.position.x + 1, 0.2, r.position.y + 0.8), Vector3(r.end.x - 1, 3.2, r.position.y + 3.5), Color("#c4b59a"))


func _beco(k: Kit, r: Rect2) -> void:
	k.box_ab(Vector3(r.position.x + 0.5, 0.17, r.position.y + 0.5), Vector3(r.end.x - 0.5, 0.19, r.end.y - 0.5), Color("#4b4740"))
	_simple_building(Rect2(r.position.x + 1, r.position.y + 1, 11, r.size.y - 3), 9.0, Color("#7a5a4a"), Color("#3e3e40"), false, 3)
	_simple_building(Rect2(r.end.x - 12, r.position.y + 1, 11, r.size.y - 3), 9.0, Color("#6a6f6a"), Color("#3e3e40"), false, 3)
	var ax := r.get_center().x
	for i in 3:
		var p := Vector3(ax - 2.5 + i * 2.2, 0.19, r.position.y + 5 + i * 6)
		k.box_ab(p, p + Vector3(1.8, 1.3, 1.1), Color("#2f5a3a") if i != 1 else Color("#5a3a2a"))
		k.box_ab(p + Vector3(-0.05, 1.3, -0.05), p + Vector3(1.85, 1.38, 1.15), Color("#1f1f1f"))
	for i in 14:
		k.sphere(Vector3(ax + rng.randf_range(-3.5, 3.5), 0.4, rng.randf_range(r.position.y + 2, r.end.y - 3)), Vector3(0.7, 0.55, 0.6), Color("#1c1c1c"))
	for i in 5:
		k.box(Vector3(r.position.x + 12.05, rng.randf_range(1.0, 2.5), rng.randf_range(r.position.y + 3, r.end.y - 4)), Vector3(0.05, rng.randf_range(0.5, 1.2), rng.randf_range(1.0, 3.0)), Color.from_hsv(rng.randf(), 0.7, 0.8))


func _acacias(k: Kit, r: Rect2) -> void:
	k.box_ab(Vector3(r.position.x + 1, 0.17, r.position.y + 1), Vector3(r.end.x - 1, 0.19, r.end.y - 1), GRASS)
	for i in 3:
		var cell := Rect2(r.position.x + 1 + i * 9.3, r.position.y + 1, 9.3, r.size.y - 2)
		var cols := _house_colors()
		_simple_building(Rect2(cell.position.x + 0.8, cell.position.y + 4, 7.6, 9), 3.0, cols[0], cols[1], true)
		k.box_ab(Vector3(cell.position.x + 0.2, 0.17, cell.end.y - 0.5), Vector3(cell.position.x + 3.6, 1.8 if i == 0 else 1.0, cell.end.y - 0.2), cols[0].darkened(0.2))
		k.box_ab(Vector3(cell.position.x + 5.6, 0.17, cell.end.y - 0.5), Vector3(cell.end.x - 0.2, 1.8 if i == 0 else 1.0, cell.end.y - 0.2), cols[0].darkened(0.2))
		k.box_ab(Vector3(cell.position.x + 3.6, 0.17, cell.end.y - 0.45), Vector3(cell.position.x + 5.6, 1.6, cell.end.y - 0.3), Color("#2b2b2b"))
		_tree(k, Vector3(cell.get_center().x, 0.19, cell.end.y - 4.5), 0.8)


# ---------- estado dinâmico ----------

func set_door(id: String, locked: bool) -> void:
	if not loc_info.has(id):
		return
	var info: Dictionary = loc_info[id]
	(info["door"] as CollisionShape3D).set_deferred("disabled", not locked)
	(info["door_mesh"] as Node3D).visible = locked


func set_interior_light(id: String, on: bool) -> void:
	if loc_info.has(id):
		(loc_info[id]["light"] as OmniLight3D).visible = on


func set_fire(id: String, on: bool) -> void:
	if on == fire_nodes.has(id):
		return
	if not on:
		fire_nodes[id].queue_free()
		fire_nodes.erase(id)
		return
	if not layout.lots.has(id):
		return
	var b: Rect2 = layout.lots[id]["building"]
	var center: Vector2 = b.get_center() if b.size != Vector2.ZERO else (layout.lots[id]["rect"] as Rect2).get_center()
	var n := Node3D.new()
	n.position = Vector3(center.x, 0.2, center.y)
	add_child(n)
	var p := CPUParticles3D.new()
	p.amount = 160
	p.lifetime = 1.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(maxf(b.size.x, 6.0) * 0.45, 0.5, maxf(b.size.y, 6.0) * 0.45)
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 3.5, 0)
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.4)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.vertex_color_use_as_albedo = true
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = fm
	p.mesh = qm
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.3, 0.95))
	grad.set_color(1, Color(0.3, 0.3, 0.3, 0.0))
	grad.add_point(0.45, Color(1.0, 0.35, 0.08, 0.85))
	p.color_ramp = grad
	n.add_child(p)
	var l := OmniLight3D.new()
	l.light_color = Color("#ff7a2a")
	l.light_energy = 4.0
	l.omni_range = 22.0
	l.position = Vector3(0, 3, 0)
	n.add_child(l)
	fire_nodes[id] = n
