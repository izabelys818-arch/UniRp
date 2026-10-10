extends Node3D

# Monta a cidade em 3D a partir do traçado. Cada construção tem duas versões:
# inteira (paredes + telhado) e cortada (paredes baixas), como no Project Zomboid,
# para que dê para ver o personagem dentro dos prédios ou atrás deles.

const Kit = preload("res://world3d/mesh_kit.gd")
const Layout = preload("res://world3d/city_layout.gd")
const HouseGen = preload("res://world3d/house_gen.gd")
const Art = preload("res://world3d/art_style.gd")
const ChunkKit = preload("res://world3d/chunk_kit.gd")
const Flora = preload("res://world3d/flora.gd")

const WALL_H := 3.2
const CUT_H := 0.75
const WALL_T := 0.3

var ASPHALT := Color("#3a3c3f")
var SIDEWALK := Color("#77746d")
var CURB := Color("#a9a59b")
var GRASS := Color("#56703f")
var GRASS2 := Color("#4a6438")
var DIRT := Color("#6e5d45")
const LINE := Color("#d8d3c4")
const LINE_Y := Color("#c9a64a")
const AVENUES_V := [0, 4]
const AVENUES_H := [3]
const CURTAINS := ["#c9b48a", "#a8483c", "#5f7a9a", "#d8cfc0", "#7a8a5a", "#b88a6a", "#8a5a7a"]
# Identidade de cada cenário nos detalhes da rua: pichação, lixo, janelas tapadas, floreiras,
# bicicletas e faixa exclusiva de ônibus. Mesma linguagem visual, sotaques diferentes.
const SCEN_TOUCH := {
	"porto_cinza": {"tags": 0.35, "trash": 0.35, "boards": 0.0, "planters": 0.1, "bikes": 0.12},
	"vale_sereno": {"tags": 0.05, "trash": 0.05, "boards": 0.0, "planters": 0.55, "bikes": 0.4},
	"nova_aurora": {"tags": 0.2, "trash": 0.22, "boards": 0.0, "planters": 0.25, "bikes": 0.25, "bus_lane": true},
	"colapso": {"tags": 0.85, "trash": 0.75, "boards": 0.22, "planters": 0.0, "bikes": 0.06},
}

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
var house_gen: HouseGen
var pole_spots: Array = []
var ground_mat: StandardMaterial3D
var puddles: Node3D
# materiais por superfície: cada um reage à chuva do seu jeito (ver set_wetness)
var asphalt_mat: StandardMaterial3D
var walk_mat: StandardMaterial3D
var prop_mat: StandardMaterial3D
var veg_mat: StandardMaterial3D
var roof_mat: StandardMaterial3D
var shadow_mat: StandardMaterial3D
var puddle_mat: StandardMaterial3D
var cat_mats: Dictionary = {}
var wetness := 0.0
# lugares para sentar (bancos, pontos de ônibus, cadeiras de bar): {"p": Vector2, "yaw": float}
var seats: Array = []
# leitos onde um NPC pode ficar deitado (hospital, pensão): {"p": Vector2 aproximação, "anchor": Vector3 pés, "yaw", "h"}
var beds: Array = []
# pontos de uso das ações do jogador por lugar: loc_id -> {"cama": {...}, "chuveiro": {...}}
var use_points: Dictionary = {}
var neon_mat: StandardMaterial3D
var wear_city: float = 0.35
var rng := RandomNumberGenerator.new()


func build(l: Layout) -> void:
	layout = l
	rng.seed = 90210
	ASPHALT = Art.col("asphalt")
	SIDEWALK = Art.col("sidewalk")
	CURB = Art.col("curb")
	GRASS = Art.col("grass")
	GRASS2 = Art.col("grass2")
	DIRT = Art.col("dirt")
	wear_city = Art.num("decay")
	# reboco, concreto e pintura: foscos, sem metal e com pouco brilho (nada de aspecto plástico)
	mat = Kit.vertex_material(0.9, 0.22)
	asphalt_mat = Kit.vertex_material(0.92, 0.3)
	walk_mat = Kit.vertex_material(0.95, 0.24)
	prop_mat = Kit.vertex_material(0.62, 0.32)
	veg_mat = Kit.vertex_material(0.95, 0.12)
	roof_mat = Kit.vertex_material(0.86, 0.22)
	shadow_mat = Kit.shadow_material()
	ground_mat = asphalt_mat
	Kit.roof_material = roof_mat
	Kit.shadow_material_ref = shadow_mat
	cat_mats = {"asphalt": asphalt_mat, "walk": walk_mat, "props": prop_mat, "veg": veg_mat}
	neon_mat = StandardMaterial3D.new()
	neon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	neon_mat.vertex_color_use_as_albedo = true
	neon_mat.vertex_color_is_srgb = true
	# vidro: tons variados por janela (cor do vértice), nunca preto; à noite guarda um reflexo azulado fraco
	glass_mat = Kit.vertex_material(0.24, 0.55)
	glass_mat.emission_enabled = true
	glass_mat.emission = Color("#1e2836")
	glass_mat.emission_energy_multiplier = 0.0
	# janela acesa: cor quente variada por janela, sem sombreamento; world_view escurece de dia
	lit_mat = StandardMaterial3D.new()
	lit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lit_mat.vertex_color_use_as_albedo = true
	lit_mat.vertex_color_is_srgb = true
	lit_mat.albedo_color = Color.WHITE
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
	house_gen = HouseGen.new()
	_ground()
	for c in layout.blocks:
		var info: Dictionary = layout.blocks[c]
		if str(info["loc"]) != "":
			_build_location(str(info["loc"]), c)
		else:
			_build_filler(c, info)


# ---------- utilidades ----------

func _mesh(kit, parent: Node3D, m: Material = null) -> MeshInstance3D:
	if kit is ChunkKit:
		return kit.build(parent, cat_mats, m if m else mat)
	var mesh: ArrayMesh = kit.commit(m if m else mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)
	_add_shadow(kit, parent)
	return mi


# Sombras de contato do kit (malha própria, transparente, sem projetar sombra).
func _add_shadow(kit, parent: Node3D) -> void:
	var sm: ArrayMesh = kit.shadow_mesh()
	if sm != null:
		var si := MeshInstance3D.new()
		si.mesh = sm
		si.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(si)


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
	if s.get("interior") != null:
		(s["interior"] as Node3D).visible = on


# Interior das casas: só existe enquanto o jogador está por perto.
func ensure_interior(s: Dictionary) -> void:
	if s.get("interior") != null or not s.has("lot"):
		return
	var node := house_gen.build_interior(s)
	(s["root"] as Node3D).add_child(node)
	node.visible = bool(s["cut_now"])
	s["interior"] = node


func drop_interior(s: Dictionary) -> void:
	if s.get("interior") == null:
		return
	(s["interior"] as Node3D).queue_free()
	s["interior"] = null
	s["light"] = null


func _tree(k, p: Vector3, scale: float = 1.0) -> void:
	Flora.tree(k, p, scale, rng)


func _car(k, p: Vector3, rot: float, col: Color) -> void:
	var old: String = k.cat
	k.cat = "props"
	var b := Basis(Vector3.UP, rot)
	var xf := Transform3D(b, p)
	# sombra densa até a borda da lataria e esmaecendo logo depois: o miolo fica escondido sob o carro,
	# então o que aparece é a faixa escura rente às rodas (antes só a borda já desbotada aparecia)
	k.soft_shadow(p, 1.18, 2.5, 0.6, rot, 0.8, 0.85)
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(1.8, 0.7, 4.2)), Vector3(0, 0.65, 0)), col)
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(1.6, 0.6, 2.2)), Vector3(0, 1.25, -0.2)), col.lightened(0.1))
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(1.64, 0.45, 2.0)), Vector3(0, 1.25, -0.2)), Color("#1d2630"))
	for wx in [-0.85, 0.85]:
		for wz in [-1.35, 1.35]:
			k.add("cyl", xf * Transform3D(Basis(Vector3.FORWARD, PI / 2.0).scaled(Vector3(0.7, 0.3, 0.7)), Vector3(wx, 0.35, wz)), Color("#141414"))
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(1.5, 0.18, 0.05)), Vector3(0, 0.75, 2.11)), Color("#f2eccc"))
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(1.5, 0.16, 0.05)), Vector3(0, 0.8, -2.11)), Color("#8c1c1c"))
	k.cat = old


func _bench(k, p: Vector3, rot: float) -> void:
	var old: String = k.cat
	k.cat = "props"
	var b := Basis(Vector3.UP, rot)
	k.add("box", Transform3D(b.scaled(Vector3(1.8, 0.08, 0.5)), p + Vector3(0, 0.45, 0)), Color("#7a5534"))
	k.add("box", Transform3D(b.scaled(Vector3(1.8, 0.4, 0.08)), p + b * Vector3(0, 0.75, -0.22)), Color("#7a5534"))
	for dx in [-0.75, 0.75]:
		k.add("box", Transform3D(b.scaled(Vector3(0.08, 0.45, 0.45)), p + b * Vector3(dx, 0.22, 0)), Color("#2b2b2b"))
	k.soft_shadow(p, 1.15, 0.5, 0.3, rot)
	k.cat = old
	for sx in [-0.45, 0.45]:
		var sp := p + b * Vector3(sx, 0, 0.05)
		seats.append({"p": Vector2(sp.x, sp.z), "yaw": rot})


func _lamp(k, p: Vector3) -> void:
	var old: String = k.cat
	k.cat = "props"
	k.cyl(p, 0.09, 5.2, Color("#2c2f33"))
	k.box(p + Vector3(0.6, 5.15, 0), Vector3(1.4, 0.12, 0.14), Color("#2c2f33"))
	k.box(p + Vector3(1.2, 5.0, 0), Vector3(0.5, 0.2, 0.3), Color("#e9e1c4"))
	k.soft_shadow(p, 0.3, 0.3, 0.32)
	lamp_spots.append(p + Vector3(1.2, 4.7, 0))
	k.cat = old


# ---------- chão, ruas e calçadas ----------

func _ground() -> void:
	# chão repartido em pedaços de 80 m e por superfície (ver chunk_kit.gd)
	var k := ChunkKit.new(80.0)
	var S := Layout.SIZE
	var P := Layout.PITCH
	k.cat = "asphalt"
	var cells := int(ceil((S + 60.0) / 80.0))
	for cx in range(-1, cells):
		for cz in range(-1, cells):
			var a := Vector3(maxf(cx * 80.0, -60.0), -0.2, maxf(cz * 80.0, -60.0))
			var b := Vector3(minf((cx + 1) * 80.0, S + 60.0), 0.12, minf((cz + 1) * 80.0, S + 60.0))
			if b.x > a.x and b.z > a.z:
				k.box_ab(a, b, ASPHALT)
	# cada trecho de rua tem sua idade: recapeado escuro, antigo claro e remendado
	for i in Layout.GRID + 1:
		var lp := i * P + Layout.STREET / 2.0
		for j in Layout.GRID:
			var a0 := j * P + Layout.STREET
			var age := rng.randf()
			if age < 0.3:
				var tone_n := ASPHALT.darkened(0.12)
				k.box_ab(Vector3(lp - 4.4, 0.12, a0 - 0.2), Vector3(lp + 4.4, 0.1205, a0 + Layout.BLOCK + 0.2), tone_n)
			elif age > 0.75:
				var tone_o := ASPHALT.lightened(0.1).lerp(Color("#6b6560"), 0.15)
				k.box_ab(Vector3(lp - 4.4, 0.12, a0 - 0.2), Vector3(lp + 4.4, 0.1205, a0 + Layout.BLOCK + 0.2), tone_o)
			age = rng.randf()
			if age < 0.3:
				k.box_ab(Vector3(a0 - 0.2, 0.12, lp - 4.4), Vector3(a0 + Layout.BLOCK + 0.2, 0.1205, lp + 4.4), ASPHALT.darkened(0.12))
			elif age > 0.75:
				k.box_ab(Vector3(a0 - 0.2, 0.12, lp - 4.4), Vector3(a0 + Layout.BLOCK + 0.2, 0.1205, lp + 4.4), ASPHALT.lightened(0.1).lerp(Color("#6b6560"), 0.15))
			# trilhas de pneu: o asfalto fica mais liso e escuro onde as rodas passam
			for off in [-3.3, -1.7, 1.7, 3.3]:
				k.box_ab(Vector3(lp + off - 0.28, 0.12, a0), Vector3(lp + off + 0.28, 0.1208, a0 + Layout.BLOCK), ASPHALT.darkened(0.08))
				k.box_ab(Vector3(a0, 0.12, lp + off - 0.28), Vector3(a0 + Layout.BLOCK, 0.1208, lp + off + 0.28), ASPHALT.darkened(0.08))
	# manchas e remendos no asfalto
	for i in 420:
		var vert := rng.randf() < 0.5
		var line := int(rng.randi_range(0, Layout.GRID)) * P + Layout.STREET / 2.0 + rng.randf_range(-3.2, 3.2)
		var along := rng.randf_range(0, S)
		var sz := Vector2(rng.randf_range(0.6, 3.4), rng.randf_range(0.5, 2.4))
		var tone := ASPHALT.lightened(rng.randf_range(-0.07, 0.09))
		if vert:
			k.box_ab(Vector3(line, 0.12, along), Vector3(line + sz.y, 0.123, along + sz.x), tone)
		else:
			k.box_ab(Vector3(along, 0.12, line), Vector3(along + sz.x, 0.123, line + sz.y), tone)
	for i in 70:
		var vert2 := rng.randf() < 0.5
		var line2 := int(rng.randi_range(0, Layout.GRID)) * P + Layout.STREET / 2.0 + rng.randf_range(-3.5, 3.5)
		var a2 := rng.randf_range(0, S)
		var pts: Array = [Vector2(a2, line2)]
		for st in 6:
			var last: Vector2 = pts[pts.size() - 1]
			pts.append(last + Vector2(rng.randf_range(0.4, 1.0), rng.randf_range(-0.4, 0.4)))
		for st in pts.size() - 1:
			var p0: Vector2 = pts[st]
			var p1: Vector2 = pts[st + 1]
			if vert2:
				p0 = Vector2(p0.y, p0.x)
				p1 = Vector2(p1.y, p1.x)
			k.box_ab(Vector3(minf(p0.x, p1.x) - 0.03, 0.12, minf(p0.y, p1.y) - 0.03), Vector3(maxf(p0.x, p1.x) + 0.03, 0.124, maxf(p0.y, p1.y) + 0.03), Color("#25272a"))
	# faixas: tinta de rua responde à chuva como a calçada (não escurece tanto quanto o asfalto)
	k.cat = "walk"
	for i in Layout.GRID + 1:
		var line3 := i * P + Layout.STREET / 2.0
		for j in Layout.GRID:
			var a := j * P + Layout.STREET + 2.0
			var x := a
			var av_h: bool = i in AVENUES_H
			var av_v: bool = i in AVENUES_V
			if av_h:
				for off2 in [-0.12, 0.12]:
					k.box_ab(Vector3(a - 2.0, 0.12, line3 + off2 - 0.05), Vector3(a + Layout.BLOCK, 0.141, line3 + off2 + 0.05), LINE_Y.darkened(rng.randf() * 0.15))
			if av_v:
				for off3 in [-0.12, 0.12]:
					k.box_ab(Vector3(line3 + off3 - 0.05, 0.12, a - 2.0), Vector3(line3 + off3 + 0.05, 0.141, a + Layout.BLOCK), LINE_Y.darkened(rng.randf() * 0.15))
			while x < a + Layout.BLOCK - 4.0:
				if not av_h:
					k.box_ab(Vector3(x, 0.12, line3 - 0.08), Vector3(x + 1.6, 0.14, line3 + 0.08), LINE.darkened(rng.randf() * 0.25))
				if not av_v:
					k.box_ab(Vector3(line3 - 0.08, 0.12, x), Vector3(line3 + 0.08, 0.14, x + 1.6), LINE.darkened(rng.randf() * 0.25))
				x += 3.2
	# Nova Aurora: faixa exclusiva de ônibus pintada junto ao meio-fio das avenidas
	if bool(SCEN_TOUCH.get(Art.id(), {}).get("bus_lane", false)):
		var bus_c := Color("#6e3a33")
		for i in AVENUES_V:
			var lx: float = i * P + Layout.STREET / 2.0
			for j in Layout.GRID:
				var b0 := j * P + Layout.STREET + 0.6
				k.box_ab(Vector3(lx + 2.6, 0.12, b0), Vector3(lx + 4.2, 0.1212, b0 + Layout.BLOCK - 1.2), bus_c)
				k.box_ab(Vector3(lx - 4.2, 0.12, b0), Vector3(lx - 2.6, 0.1212, b0 + Layout.BLOCK - 1.2), bus_c)
		for j in AVENUES_H:
			var lz2: float = j * P + Layout.STREET / 2.0
			for i in Layout.GRID:
				var b1 := i * P + Layout.STREET + 0.6
				k.box_ab(Vector3(b1, 0.12, lz2 + 2.6), Vector3(b1 + Layout.BLOCK - 1.2, 0.1212, lz2 + 4.2), bus_c)
				k.box_ab(Vector3(b1, 0.12, lz2 - 4.2), Vector3(b1 + Layout.BLOCK - 1.2, 0.1212, lz2 - 2.6), bus_c)
	# lombadas pintadas nas ruas de bairro (as avenidas não têm)
	for i in Layout.GRID + 1:
		var lb := i * P + Layout.STREET / 2.0
		for j in Layout.GRID:
			if i in AVENUES_V or i in AVENUES_H or rng.randf() > 0.2:
				continue
			var lz := j * P + Layout.STREET + Layout.BLOCK * rng.randf_range(0.3, 0.6)
			var horiz := rng.randf() < 0.5
			for sb in 9:
				var sc := LINE_Y.darkened(0.1) if sb % 2 == 0 else Color("#2e2e2c")
				if horiz:
					k.box_ab(Vector3(lz - 0.45, 0.12, lb - 4.6 + sb * 1.02), Vector3(lz + 0.45, 0.165, lb - 3.58 + sb * 1.02), sc)
				else:
					k.box_ab(Vector3(lb - 4.6 + sb * 1.02, 0.12, lz - 0.45), Vector3(lb - 3.58 + sb * 1.02, 0.165, lz + 0.45), sc)
	for i in Layout.GRID + 1:
		for j in Layout.GRID + 1:
			var c := Vector2(i * P + Layout.STREET / 2.0, j * P + Layout.STREET / 2.0)
			k.cat = "walk"
			for s in 6:
				var off := -3.0 + s * 1.2
				k.box_ab(Vector3(c.x + off, 0.12, c.y + 5.6), Vector3(c.x + off + 0.6, 0.14, c.y + 7.4), LINE)
				k.box_ab(Vector3(c.x + 5.6, 0.12, c.y + off), Vector3(c.x + 7.4, 0.14, c.y + off + 0.6), LINE)
				k.box_ab(Vector3(c.x + off, 0.12, c.y - 7.4), Vector3(c.x + off + 0.6, 0.14, c.y - 5.6), LINE)
				k.box_ab(Vector3(c.x - 7.4, 0.12, c.y + off), Vector3(c.x - 5.6, 0.14, c.y + off + 0.6), LINE)
			k.cat = "asphalt"
			k.cyl(Vector3(c.x + 1.0, 0.12, c.y - 1.0), 0.45, 0.012, Color("#2c2e30"))
			if (i + j) % 2 == 0:
				_lamp(k, Vector3(c.x + 5.8, 0.17, c.y + 5.8))
			if (i + j) % 3 == 1 and i > 0 and j > 0 and i < Layout.GRID and j < Layout.GRID:
				k.cat = "props"
				var pp := Vector3(c.x - 5.9, 0.17, c.y - 5.9)
				k.cyl(pp, 0.08, 4.6, Color("#2c2f33"))
				k.box(pp + Vector3(0.0, 4.5, 0.45), Vector3(0.9, 0.18, 0.14), Color("#2c2f33"))
				k.box(pp + Vector3(0.0, 4.2, 0.45), Vector3(0.28, 0.75, 0.2), Color("#1c1d20"))
				k.sphere(pp + Vector3(0.0, 4.43, 0.56), Vector3.ONE * 0.16, Color("#c0392b"))
				k.sphere(pp + Vector3(0.0, 4.2, 0.56), Vector3.ONE * 0.16, Color("#3a3a2a"))
				k.sphere(pp + Vector3(0.0, 3.97, 0.56), Vector3.ONE * 0.16, Color("#1f5a2f"))
				k.soft_shadow(pp, 0.3, 0.3, 0.32)
	# quarteirões: meio-fio, sarjeta, calçada com juntas, gramado
	for c in layout.blocks:
		var r := Layout.block_rect(c)
		var sw := Layout.SIDEWALK
		k.cat = "walk"
		k.box_ab(Vector3(r.position.x - 0.3, 0.0, r.position.y - 0.3), Vector3(r.end.x + 0.3, 0.15, r.end.y + 0.3), CURB)
		# sarjeta: faixa mais escura de concreto junto ao meio-fio
		var gut := ASPHALT.lerp(Color("#5d5a54"), 0.55)
		k.box_ab(Vector3(r.position.x - 0.75, 0.12, r.position.y - 0.75), Vector3(r.end.x + 0.75, 0.1225, r.position.y - 0.3), gut)
		k.box_ab(Vector3(r.position.x - 0.75, 0.12, r.end.y + 0.3), Vector3(r.end.x + 0.75, 0.1225, r.end.y + 0.75), gut)
		k.box_ab(Vector3(r.position.x - 0.75, 0.12, r.position.y - 0.3), Vector3(r.position.x - 0.3, 0.1225, r.end.y + 0.3), gut)
		k.box_ab(Vector3(r.end.x + 0.3, 0.12, r.position.y - 0.3), Vector3(r.end.x + 0.75, 0.1225, r.end.y + 0.3), gut)
		# bocas de lobo
		for bx in [r.position.x + 3.0, r.end.x - 3.0]:
			k.box_ab(Vector3(bx - 0.5, 0.06, r.end.y + 0.28), Vector3(bx + 0.5, 0.152, r.end.y + 0.34), Color("#2a2a2a"))
		k.box_ab(Vector3(r.position.x, 0.0, r.position.y), Vector3(r.end.x, 0.17, r.end.y), SIDEWALK.lightened(rng.randf_range(-0.03, 0.03)))
		var jx := r.position.x
		while jx < r.end.x:
			k.box_ab(Vector3(jx, 0.17, r.position.y), Vector3(jx + 0.04, 0.175, r.position.y + sw), SIDEWALK.darkened(0.2))
			k.box_ab(Vector3(jx, 0.17, r.end.y - sw), Vector3(jx + 0.04, 0.175, r.end.y), SIDEWALK.darkened(0.2))
			jx += 2.2
		var jz := r.position.y
		while jz < r.end.y:
			k.box_ab(Vector3(r.position.x, 0.17, jz), Vector3(r.position.x + sw, 0.175, jz + 0.04), SIDEWALK.darkened(0.2))
			k.box_ab(Vector3(r.end.x - sw, 0.17, jz), Vector3(r.end.x, 0.175, jz + 0.04), SIDEWALK.darkened(0.2))
			jz += 2.2
		# guia rebaixada diante das entradas: rampinha do asfalto até a calçada
		for d in _doors_near(c):
			if rng.randf() < 0.55:
				_curb_ramp(k, r, d)
		k.cat = "veg"
		if Art.p().get("verge", false):
			# Vale Sereno: faixa de grama entre o meio-fio e o passeio
			var vg := GRASS.lerp(GRASS2, 0.4)
			k.box_ab(Vector3(r.position.x + 0.3, 0.17, r.end.y - 1.1), Vector3(r.end.x - 0.3, 0.178, r.end.y - 0.25), vg)
			k.box_ab(Vector3(r.position.x + 0.3, 0.17, r.position.y + 0.25), Vector3(r.end.x - 0.3, 0.178, r.position.y + 1.1), vg)
		var inner := r.grow(-sw)
		k.box_ab(Vector3(inner.position.x, 0.17, inner.position.y), Vector3(inner.end.x, 0.185, inner.end.y), GRASS.lerp(GRASS2, rng.randf() * 0.6))
		for side in 2:
			if rng.randf() < 0.5:
				var cx := rng.randf_range(r.position.x + 4, r.end.x - 4)
				var z := r.end.y + 1.6 if side == 0 else r.position.y - 1.6
				_car(k, Vector3(cx, 0.12, z), PI / 2.0 + rng.randf_range(-0.03, 0.03), _car_color())
		# poste de energia com fios, hidrante, placa, banco, lixeira
		k.cat = "props"
		var pole := Vector3(r.position.x + 0.9, 0.17, r.position.y + 0.9)
		k.cyl(pole, 0.12, 7.4, Color("#6a5a48"))
		k.box(pole + Vector3(0, 6.9, 0), Vector3(1.8, 0.1, 0.1), Color("#5a4a3a"))
		for wxo in [-0.8, 0.0, 0.8]:
			k.sphere(pole + Vector3(wxo, 7.05, 0), Vector3.ONE * 0.12, Color("#cfd2d6"))
		k.soft_shadow(pole, 0.36, 0.36, 0.34)
		pole_spots.append(pole + Vector3(0, 7.05, 0))
		if c.x < Layout.GRID - 1:
			var nxt := Vector3(Layout.block_rect(c + Vector2i(1, 0)).position.x + 0.9, 7.05, r.position.y + 0.9)
			for wi in 3:
				_wire(k, Vector3(pole.x + (wi - 1) * 0.8, 7.05, pole.z), Vector3(nxt.x + (wi - 1) * 0.8, 7.05, nxt.z))
		if c.y < Layout.GRID - 1:
			var nxz := Vector3(r.position.x + 0.9, 7.05, Layout.block_rect(c + Vector2i(0, 1)).position.y + 0.9)
			_wire(k, Vector3(pole.x, 7.0, pole.z), nxz)
		if rng.randf() < 0.5:
			var hp := Vector3(r.end.x - 1.0, 0.17, r.position.y + 1.2)
			k.cyl(hp, 0.17, 0.62, Color("#c0392b"))
			k.sphere(hp + Vector3(0, 0.68, 0), Vector3(0.4, 0.28, 0.4), Color("#c0392b"))
			k.box(hp + Vector3(0.0, 0.4, 0.0), Vector3(0.5, 0.1, 0.12), Color("#c0392b"))
			k.soft_shadow(hp, 0.34, 0.34, 0.34)
		if rng.randf() < 0.35:
			_bench(k, Vector3(rng.randf_range(r.position.x + 5, r.end.x - 5), 0.17, r.position.y + 1.1), 0.0)
		if rng.randf() < 0.45:
			var gp := Vector3(rng.randf_range(r.position.x + 5, r.end.x - 5), 0.17, r.end.y - 1.0)
			k.cyl(gp, 0.3, 0.9, Color("#3a4a3a"))
			k.cyl(gp + Vector3(0, 0.9, 0), 0.32, 0.06, Color("#2a2a2a"))
			k.soft_shadow(gp, 0.48, 0.48, 0.32)
		_street_touch(k, c, r)
		k.cat = "walk"
		for sx in rng.randi_range(0, 3):
			k.box(Vector3(rng.randf_range(r.position.x + 2, r.end.x - 2), 0.18, rng.randf_range(r.position.y + 0.3, r.position.y + sw - 0.3)), Vector3(rng.randf_range(0.2, 0.5), 0.02, rng.randf_range(0.15, 0.35)), Color("#cfc9b8") if rng.randf() < 0.5 else Color("#7a8a5a"), rng.randf() * PI)
	if wear_city > 0.6:
		_collapse_streets(k)
	_avenue_furniture(k)
	_mesh(k, self)
	_make_puddles()
	# placas com o nome das ruas
	for i in range(0, Layout.GRID + 1, 2):
		for j in range(0, Layout.GRID + 1, 2):
			var c2 := Vector2(i * P + Layout.STREET / 2.0, j * P + Layout.STREET / 2.0)
			var pl := Label3D.new()
			pl.text = "%s\n%s" % [Layout.STREETS_V[i], Layout.STREETS_H[j]]
			pl.font_size = 40
			pl.pixel_size = 0.0045
			pl.outline_size = 6
			pl.modulate = Color("#e8f0e8")
			pl.outline_modulate = Color("#1f5a3a")
			pl.position = Vector3(c2.x + 5.7, 2.9, c2.y + 6.3)
			pl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			add_child(pl)


# Sotaque do cenário na calçada: sacos de lixo, floreiras e bicicletas encostadas.
func _street_touch(k, c: Vector2i, r: Rect2) -> void:
	var t: Dictionary = SCEN_TOUCH.get(Art.id(), {})
	var doors := _doors_near(c)
	if rng.randf() < float(t.get("trash", 0.0)):
		var tp := Vector3(r.position.x + rng.randf_range(1.6, 4.0), 0.17, r.position.y + 0.6)
		k.cat = "props"
		for ti in rng.randi_range(2, 5):
			k.sphere(tp + Vector3(rng.randf_range(-0.5, 0.5), 0.2, rng.randf_range(-0.22, 0.22)), Vector3(0.5, 0.42, 0.45) * rng.randf_range(0.8, 1.15), Color("#1d1f22").lerp(Color("#34445e"), rng.randf() * 0.5))
		k.soft_shadow(tp, 0.9, 0.5, 0.3)
	if rng.randf() < float(t.get("planters", 0.0)):
		var fp := Vector3(rng.randf_range(r.position.x + 6, r.end.x - 6), 0.17, r.end.y - 0.55)
		if _free_spot(Vector2(fp.x, fp.z), doors, 2.2):
			k.cat = "props"
			k.box(fp + Vector3(0, 0.25, 0), Vector3(1.2, 0.5, 0.45), Color("#9a6a4a"))
			k.soft_shadow(fp, 0.75, 0.35, 0.3)
			k.cat = "veg"
			for fi in 4:
				var flower := Color.from_hsv(rng.randf_range(0.0, 0.14) if fi % 2 == 0 else rng.randf_range(0.75, 0.95), 0.55, 0.85)
				k.sphere(fp + Vector3(-0.42 + fi * 0.28, 0.6, 0), Vector3(0.36, 0.3, 0.32), flower if rng.randf() < 0.6 else Color("#4f7a3a"))
	if rng.randf() < float(t.get("bikes", 0.0)):
		var bp := Vector3(rng.randf_range(r.position.x + 4, r.end.x - 4), 0.17, r.position.y + 0.55)
		if _free_spot(Vector2(bp.x, bp.z), doors, 2.0):
			_bike(k, bp, rng.randf_range(-0.2, 0.2))


func _bike(k, p: Vector3, rot: float) -> void:
	var old: String = k.cat
	k.cat = "props"
	var b := Basis(Vector3.UP, rot)
	var col := Color.from_hsv(rng.randf(), 0.6, 0.6)
	for wx in [-0.52, 0.52]:
		k.add("cyl", Transform3D(b * Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(0.62, 0.04, 0.62)), p + b * Vector3(wx, 0.33, 0)), Color("#1a1a1a"))
	k.add("box", Transform3D(b * Basis.from_scale(Vector3(1.0, 0.04, 0.04)), p + Vector3(0, 0.55, 0)), col)
	k.add("box", Transform3D(b * Basis(Vector3.BACK, 0.9) * Basis.from_scale(Vector3(0.62, 0.04, 0.04)), p + b * Vector3(-0.22, 0.45, 0)), col)
	k.add("box", Transform3D(b * Basis.from_scale(Vector3(0.26, 0.05, 0.1)), p + b * Vector3(-0.3, 0.72, 0)), Color("#2a2a2a"))
	k.add("box", Transform3D(b * Basis.from_scale(Vector3(0.05, 0.05, 0.5)), p + b * Vector3(0.45, 0.8, 0)), Color("#3a3a3a"))
	k.soft_shadow(p, 0.75, 0.25, 0.3, rot)
	k.cat = old


# Guia rebaixada diante de uma entrada: rampa de concreto que liga o asfalto à calçada.
func _curb_ramp(k, r: Rect2, d: Vector2) -> void:
	var dists := [absf(d.x - r.position.x), absf(d.x - r.end.x), absf(d.y - r.position.y), absf(d.y - r.end.y)]
	var side := 0
	for i in 4:
		if dists[i] < dists[side]:
			side = i
	if dists[side] > 3.5:
		return
	var out: Vector2 = [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)][side]
	var edge: Vector2 = [Vector2(r.position.x, d.y), Vector2(r.end.x, d.y), Vector2(d.x, r.position.y), Vector2(d.x, r.end.y)][side]
	var c := edge + out * 0.375
	var yaw := atan2(-out.y, out.x)
	k.add("wedge", Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(0.75, 0.053, 1.7)), Vector3(c.x, 0.1465, c.y)), CURB.lerp(SIDEWALK, 0.4))


func _wire(k, a: Vector3, b: Vector3) -> void:
	var old: String = k.cat
	k.cat = "props"
	var mid := (a + b) / 2.0 + Vector3(0, -0.5, 0)
	var segs: Array = [[a, mid], [mid, b]]
	for sg in segs:
		var p0: Vector3 = sg[0]
		var p1: Vector3 = sg[1]
		var d := p1 - p0
		var len := d.length()
		if len < 0.1:
			continue
		var z := d.normalized()
		var x := Vector3.UP.cross(z).normalized() if absf(z.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		var y := z.cross(x).normalized()
		k.add("box", Transform3D(Basis(x, y, z) * Basis.from_scale(Vector3(0.03, 0.03, len)), (p0 + p1) / 2.0), Color("#1c1c1c"))
	k.cat = old


func _car_color() -> Color:
	var cols := [Color("#b9bcc0"), Color("#2b2d31"), Color("#8b1e1e"), Color("#e8e6df"), Color("#1f3d6b"), Color("#6b6f3a"), Color("#8a8d90"), Color("#c47a1e")]
	return cols[rng.randi() % cols.size()]


# ---------- avenidas, chuva e cenário em colapso ----------

func _lamp_dir(k, p: Vector3, dir: Vector2) -> void:
	var old: String = k.cat
	k.cat = "props"
	k.soft_shadow(p, 0.3, 0.3, 0.32)
	k.cyl(p, 0.09, 5.4, Color("#2c2f33"))
	var arm := Vector3(dir.x, 0, dir.y)
	var b := Basis(Vector3.UP, atan2(dir.x, dir.y) - PI / 2.0)
	k.add("box", Transform3D(b * Basis.from_scale(Vector3(1.5, 0.11, 0.13)), p + Vector3(0, 5.35, 0) + arm * 0.7), Color("#2c2f33"))
	k.add("box", Transform3D(b * Basis.from_scale(Vector3(0.55, 0.2, 0.32)), p + Vector3(0, 5.2, 0) + arm * 1.35), Color("#e9e1c4"))
	lamp_spots.append(p + Vector3(0, 4.9, 0) + arm * 1.35)
	k.cat = old


func _doors_near(c: Vector2i) -> Array:
	var out: Array = []
	if not layout.blocks.has(c):
		return out
	for lid in layout.blocks[c]["lots"]:
		out.append(layout.door_out(lid))
	return out


func _free_spot(p: Vector2, doors: Array, gap: float = 1.8) -> bool:
	for d in doors:
		if (d as Vector2).distance_to(p) < gap:
			return false
	return true


# Postes dos dois lados, pontos de ônibus e árvores alinhadas nas avenidas.
func _avenue_furniture(k) -> void:
	var P := Layout.PITCH
	for i in AVENUES_V:
		for cy in Layout.GRID:
			for side in [-1, 1]:
				var cx: int = i - 1 if side < 0 else i
				if cx < 0 or cx >= Layout.GRID:
					continue
				var r := Layout.block_rect(Vector2i(cx, cy))
				var sx: float = r.end.x - 0.45 if side < 0 else r.position.x + 0.45
				var doors := _doors_near(Vector2i(cx, cy))
				var z := r.position.y + 4.0
				var n := 0
				while z < r.end.y - 3.0:
					if _free_spot(Vector2(sx, z), doors):
						if n % 2 == 0:
							_lamp_dir(k, Vector3(sx, 0.17, z), Vector2(-side, 0))
						else:
							_pit_tree(k, Vector3(sx + side * 0.6, 0.17, z))
					n += 1
					z += 7.5
				if cy % 3 == 1:
					_bus_stop(k, Vector3(sx + side * 0.9, 0.17, r.get_center().y), Vector2(-side, 0))
	for j in AVENUES_H:
		for cx2 in Layout.GRID:
			for side in [-1, 1]:
				var cy2: int = j - 1 if side < 0 else j
				if cy2 < 0 or cy2 >= Layout.GRID:
					continue
				var r2 := Layout.block_rect(Vector2i(cx2, cy2))
				var sz: float = r2.end.y - 0.45 if side < 0 else r2.position.y + 0.45
				var doors2 := _doors_near(Vector2i(cx2, cy2))
				var x := r2.position.x + 4.0
				var m := 0
				while x < r2.end.x - 3.0:
					if _free_spot(Vector2(x, sz - side * 1.0), doors2, 2.2):
						if m % 2 == 0:
							_lamp_dir(k, Vector3(x, 0.17, sz), Vector2(0, -side))
					m += 1
					x += 7.5
				if cx2 % 3 == 2:
					var bp := Vector3(r2.get_center().x, 0.17, sz + side * 0.9)
					if _free_spot(Vector2(bp.x, bp.z), doors2, 3.0):
						_bus_stop(k, bp, Vector2(0, -side))


func _pit_tree(k, p: Vector3) -> void:
	var old: String = k.cat
	k.cat = "walk"
	# canteiro com terra e guia de concreto em volta
	k.box_ab(p + Vector3(-0.55, -0.005, -0.55), p + Vector3(0.55, 0.012, 0.55), Color("#5a4a38"))
	for e in [Vector3(0, 0, -0.58), Vector3(0, 0, 0.58)]:
		k.box_ab(p + e + Vector3(-0.62, 0, -0.05), p + e + Vector3(0.62, 0.05, 0.05), CURB.darkened(0.08))
	k.cat = old
	Flora.tree(k, p, 0.95, rng)


func _bus_stop(k, p: Vector3, facing: Vector2) -> void:
	var old: String = k.cat
	k.cat = "props"
	var b := Basis(Vector3.UP, atan2(facing.x, facing.y))
	var xf := Transform3D(b, p)
	k.soft_shadow(p + b * Vector3(0, 0, -0.2), 1.8, 1.0, 0.3, atan2(facing.x, facing.y))
	for sx in [-1.3, 1.3]:
		k.add("box", xf * Transform3D(Basis.from_scale(Vector3(0.08, 2.4, 0.08)), Vector3(sx, 1.2, -0.5)), Color("#3a3d40"))
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(3.0, 0.1, 1.5)), Vector3(0, 2.45, -0.15)), Color("#4a5a66"))
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(2.8, 1.6, 0.04)), Vector3(0, 1.4, -0.85)), Color("#8a9aa4"))
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(2.2, 0.06, 0.4)), Vector3(0, 0.48, -0.6)), Color("#6a6e72"))
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(0.9, 1.2, 0.05)), Vector3(1.0, 1.3, -0.82)), Color("#c9b98a"))
	k.add("cyl", xf * Transform3D(Basis.from_scale(Vector3(0.1, 2.8, 0.1)), Vector3(1.7, 1.4, 0.3)), Color("#3a3d40"))
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(0.6, 0.4, 0.04)), Vector3(1.7, 2.7, 0.3)), Color("#2b5a8a"))
	k.cat = old
	var bs := xf * Vector3(0, 0, -0.55)
	seats.append({"p": Vector2(bs.x, bs.z), "yaw": atan2(facing.x, facing.y)})


# Poças: manchas irregulares de borda suave onde a água junta de verdade — na sarjeta, encostadas
# no meio-fio, nas trilhas dos pneus e nos remendos afundados. Crescem conforme a chuva encharca o chão.
func _make_puddles() -> void:
	puddles = Node3D.new()
	puddles.visible = false
	add_child(puddles)
	puddle_mat = StandardMaterial3D.new()
	puddle_mat.vertex_color_use_as_albedo = true
	puddle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puddle_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	puddle_mat.albedo_color = Color(1, 1, 1, 0)
	puddle_mat.roughness = 0.05
	puddle_mat.metallic_specular = 0.95
	puddle_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var k := ChunkKit.new(80.0)
	k.cat = "water"
	# a água reflete o céu: um azul-acinzentado mais claro que o asfalto molhado, para a poça ser lida
	var water := Color(0.4, 0.48, 0.58, 0.72)
	for i in Layout.GRID + 1:
		var lp := i * Layout.PITCH + Layout.STREET / 2.0
		for j in Layout.GRID:
			var a0 := j * Layout.PITCH + Layout.STREET
			for vert in [false, true]:
				for n in rng.randi_range(3, 6):
					var along := rng.randf_range(a0 + 1.5, a0 + Layout.BLOCK - 1.5)
					var roll := rng.randf()
					var across := 0.0
					var len := 1.0
					var wid := 0.4
					if roll < 0.5:
						# sarjeta, encostada no meio-fio
						wid = rng.randf_range(0.3, 0.55)
						across = (4.65 - wid * 0.8) * (1.0 if rng.randf() < 0.5 else -1.0)
						len = rng.randf_range(1.2, 4.0)
					elif roll < 0.8:
						# trilha de pneu
						wid = rng.randf_range(0.25, 0.42)
						across = [-3.3, -1.7, 1.7, 3.3][rng.randi() % 4] + rng.randf_range(-0.1, 0.1)
						len = rng.randf_range(1.0, 3.2)
					else:
						# remendo afundado
						wid = rng.randf_range(0.5, 1.0)
						across = rng.randf_range(-3.6, 3.6)
						len = rng.randf_range(0.7, 1.6)
					var c := Vector3(lp + across, 0.1248, along) if vert else Vector3(along, 0.1248, lp + across)
					var rot := (PI / 2.0 if vert else 0.0) + rng.randf_range(-0.05, 0.05)
					k.disc(c, len, wid, water, rot, 16, 0.3, 0.62, 0.92)
					if rng.randf() < 0.35:
						# poça composta: um segundo lóbulo encostado no primeiro
						var sh := rng.randf_range(-0.7, 0.7) * len
						var c2 := c + (Vector3(0, 0.0002, sh) if vert else Vector3(sh, 0.0002, 0))
						k.disc(c2, len * rng.randf_range(0.4, 0.7), wid * rng.randf_range(0.7, 1.1), water, rot + rng.randf_range(-0.3, 0.3), 14, 0.35, 0.6, 0.9)
	# algumas na calçada, nas lajotas afundadas
	for cb in layout.blocks:
		var r := Layout.block_rect(cb)
		if rng.randf() < 0.45:
			var sp := Vector3(rng.randf_range(r.position.x + 2, r.end.x - 2), 0.1765, r.end.y - rng.randf_range(0.5, 1.6))
			k.disc(sp, rng.randf_range(0.4, 0.9), rng.randf_range(0.3, 0.5), water, rng.randf() * PI, 12, 0.35, 0.6, 0.85)
	k.build(puddles, {}, puddle_mat)
	for mi in puddles.get_children():
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# Chuva: cada superfície molha do seu jeito (0 = seco, 1 = encharcado).
# Asfalto escurece muito e espelha, concreto escurece pouco e fica acetinado, metal pintado brilha,
# vegetação fica mais funda, telha escurece. As poças só aparecem depois que o chão encharca.
func set_wetness(w: float) -> void:
	if puddles == null:
		return
	w = clampf(w, 0.0, 1.0)
	if absf(w - wetness) < 0.003 and w > 0.0 and w < 1.0:
		return
	wetness = w
	_wet(asphalt_mat, w, Color(0.56, 0.58, 0.63), 0.92, 0.2, 0.3, 0.7)
	_wet(walk_mat, w, Color(0.76, 0.78, 0.83), 0.95, 0.42, 0.24, 0.5)
	_wet(prop_mat, w, Color(0.9, 0.91, 0.95), 0.62, 0.26, 0.32, 0.62)
	_wet(veg_mat, w, Color(0.8, 0.88, 0.82), 0.95, 0.62, 0.12, 0.35)
	_wet(roof_mat, w, Color(0.74, 0.74, 0.79), 0.86, 0.36, 0.22, 0.6)
	var pw := clampf((w - 0.3) / 0.7, 0.0, 1.0)
	puddles.visible = pw > 0.01
	puddle_mat.albedo_color = Color(1, 1, 1, pw)


func _wet(m: StandardMaterial3D, w: float, tint: Color, rough_dry: float, rough_wet: float, spec_dry: float, spec_wet: float) -> void:
	m.albedo_color = Color.WHITE.lerp(tint, w)
	m.roughness = lerpf(rough_dry, rough_wet, w)
	m.metallic_specular = lerpf(spec_dry, spec_wet, w)


func set_wet(on: bool) -> void:
	set_wetness(1.0 if on else 0.0)


# Colapso: barreiras de concreto, sacos de areia, carros queimados, entulho e tambores.
func _collapse_streets(k) -> void:
	k.cat = "props"
	for i in Layout.GRID + 1:
		for j in Layout.GRID + 1:
			var c := Vector2(i * Layout.PITCH + Layout.STREET / 2.0, j * Layout.PITCH + Layout.STREET / 2.0)
			var roll := rng.randf()
			if roll < 0.18:
				# barreira atravessada numa faixa, deixando a outra livre
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				for bi in 3:
					k.box(Vector3(c.x + 9.0, 0.5, c.y + side * (1.0 + bi * 1.2)), Vector3(0.5, 0.75, 1.1), Color("#9d988e"))
				for si in 5:
					k.sphere(Vector3(c.x + 9.8, 0.3, c.y + side * (0.8 + si * 0.7)), Vector3(0.6, 0.35, 0.45), Color("#8a7a58"))
			elif roll < 0.32:
				_burnt_car(k, Vector3(c.x + rng.randf_range(10, 28), 0.12, c.y + (3.0 if rng.randf() < 0.5 else -3.0)), PI / 2.0 + rng.randf_range(-0.3, 0.3))
			elif roll < 0.5:
				for di in rng.randi_range(4, 9):
					k.box(Vector3(c.x + rng.randf_range(8, 30), 0.2, c.y + rng.randf_range(2.6, 4.2) * (1.0 if di % 2 == 0 else -1.0)), Vector3(rng.randf_range(0.3, 1.1), rng.randf_range(0.15, 0.5), rng.randf_range(0.3, 0.9)), Color("#6a645a").lerp(Color("#4a4038"), rng.randf()), rng.randf() * PI)
			if rng.randf() < 0.2:
				var dp := Vector3(c.x + 6.2, 0.17, c.y + 6.4)
				k.cyl(dp, 0.32, 0.9, Color("#5a3a2a"))
				k.cyl(dp + Vector3(0, 0.9, 0), 0.34, 0.05, Color("#3a2a20"))
				k.soft_shadow(dp, 0.5, 0.5, 0.32)


func _burnt_car(k, p: Vector3, rot: float) -> void:
	var b := Basis(Vector3.UP, rot)
	var xf := Transform3D(b, p)
	var charc := Color("#2a2522")
	k.soft_shadow(p, 1.3, 2.7, 0.5, rot)
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(1.8, 0.6, 4.2)), Vector3(0, 0.45, 0)), charc)
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(1.6, 0.5, 2.0)), Vector3(0, 1.0, -0.2)), Color("#3a2f2a"))
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(1.5, 0.3, 1.4)), Vector3(0, 0.82, 1.4)), Color("#5a3a26"))
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(1.0, 0.04, 0.8)), Vector3(0.2, 1.27, -0.3)), Color("#6a4a2e"))


# ---------- prédios genéricos (casas, edifícios) ----------

func _simple_building(rect: Rect2, height: float, wall: Color, roof: Color, gable: bool, floors: int = 1, family: String = "plain", wear: float = -1.0) -> void:
	if wear < 0.0:
		wear = Art.wear(rng)
	var s := _structure(rect)
	var k := Kit.new()
	var kc := Kit.new()
	var kw := Kit.new()
	var kl := Kit.new()
	kw.vary_glass = true
	kl.vary_lit = true
	var lo := Vector3(rect.position.x, 0.17, rect.position.y)
	var hi := Vector3(rect.end.x, 0.17 + height, rect.end.y)
	k.box_ab(lo, hi, wall)
	_family_details(k, kw, kl, rect, lo, hi, wall, floors, family, wear)
	# rodapé e faixas entre andares
	k.box_ab(lo - Vector3(0.05, 0, 0.05), Vector3(hi.x + 0.05, lo.y + 0.5, hi.z + 0.05), wall.darkened(0.25))
	var fh := height / floors
	for f in range(1, floors):
		k.box_ab(Vector3(lo.x - 0.06, lo.y + f * fh - 0.1, lo.z - 0.06), Vector3(hi.x + 0.06, lo.y + f * fh + 0.05, hi.z + 0.06), wall.lightened(0.15))
	# janelas nas faces sul (+z) e leste (+x): moldura, peitoril, cortina ou persiana.
	# Escritório já tem faixas de vidro; loja não tem janela no térreo da frente (porta de enrolar e toldo).
	var frame_c := wall.darkened(0.3) if wall.get_luminance() > 0.55 else wall.lightened(0.28)
	if family != "office":
		for f in floors:
			var y := lo.y + f * fh + fh * 0.45
			if not (family == "shop" and f == 0):
				var x := lo.x + 1.4
				while x < hi.x - 1.2:
					_window(k, kw, kl, Vector3(x, y, hi.z), true, frame_c, family)
					x += 2.6
			var z := lo.z + 1.4
			while z < hi.z - 1.2:
				_window(k, kw, kl, Vector3(hi.x, y, z), false, frame_c, family)
				z += 2.6
	_tags(k, lo, hi)
	if floors == 1 and family != "shop":
		k.box(Vector3(rect.get_center().x, lo.y + 1.05, hi.z + 0.04), Vector3(1.0, 2.1, 0.08), Color("#5b3b25"))
	if gable:
		k.gable(Vector3(rect.get_center().x, hi.y + 1.0, rect.get_center().y), Vector3(rect.size.x + 0.8, 2.0, rect.size.y + 0.8), roof)
	else:
		k.box_ab(Vector3(lo.x - 0.1, hi.y, lo.z - 0.1), Vector3(hi.x + 0.1, hi.y + 0.25, hi.z + 0.1), roof)
		k.box_ab(Vector3(lo.x, hi.y + 0.25, lo.z), Vector3(hi.x, hi.y + 0.6, lo.z + 0.25), roof.darkened(0.2))
		if floors > 2:
			# casa de máquinas e caixa d'água do prédio
			k.box_ab(Vector3(lo.x + 1.5, hi.y + 0.25, lo.z + 1.5), Vector3(lo.x + 5.0, hi.y + 2.4, lo.z + 4.5), wall.darkened(0.12))
			k.box_ab(Vector3(lo.x + 1.3, hi.y + 2.4, lo.z + 1.3), Vector3(lo.x + 5.2, hi.y + 2.55, lo.z + 4.7), roof)
			k.cyl(Vector3(lo.x + 7.0, hi.y + 0.25, lo.z + 3), 1.1, 1.6, Color("#5a6e80"))
			for ai in mini(floors, 4):
				k.box(Vector3(hi.x - 2.0 - ai * 1.6, hi.y + 0.55, hi.z - 1.6), Vector3(0.9, 0.6, 0.7), Color("#c9ccce"))
			k.cyl(Vector3(hi.x - 1.2, hi.y + 0.25, lo.z + 1.2), 0.04, 3.0, Color("#6a6e72"))
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
	var k := ChunkKit.new(0.0)
	k.cat = "solid"
	match str(info["kind"]):
		"casas":
			for lot_id in info["lots"]:
				house_gen.build(self, layout.lots[lot_id])
		"comercio":
			_comercio(k, r)
		"predio":
			_predio_block(k, r)
		"terreno":
			k.cat = "walk"
			k.box_ab(Vector3(r.position.x + 0.5, 0.17, r.position.y + 0.5), Vector3(r.end.x - 0.5, 0.2, r.end.y - 0.5), DIRT)
			k.cat = "veg"
			for i in 30:
				k.sphere(Vector3(rng.randf_range(r.position.x + 2, r.end.x - 2), 0.3, rng.randf_range(r.position.y + 2, r.end.y - 2)), Vector3(0.9, 0.5, 0.9), GRASS2.darkened(rng.randf() * 0.2))
			k.cat = "props"
			for x in range(int(r.position.x) + 1, int(r.end.x), 3):
				k.box(Vector3(x, 0.9, r.end.y - 0.5), Vector3(0.08, 1.5, 0.08), Color("#6a6a6a"))
			k.box_ab(Vector3(r.position.x + 1, 1.5, r.end.y - 0.52), Vector3(r.end.x - 1, 1.55, r.end.y - 0.48), Color("#6a6a6a"))
			_car(k, Vector3(r.get_center().x + 4, 0.0, r.get_center().y), 0.6, Color("#6b4a2e"))
		"estacionamento":
			k.cat = "asphalt"
			k.box_ab(Vector3(r.position.x + 0.5, 0.17, r.position.y + 0.5), Vector3(r.end.x - 0.5, 0.19, r.end.y - 0.5), Color("#45474a"))
			k.cat = "walk"
			for i in 8:
				var x := r.position.x + 3.0 + i * 3.4
				k.box_ab(Vector3(x, 0.19, r.position.y + 2), Vector3(x + 0.12, 0.2, r.position.y + 8), LINE)
				k.box_ab(Vector3(x, 0.19, r.end.y - 9), Vector3(x + 0.12, 0.2, r.end.y - 3), LINE)
				if rng.randf() < 0.6:
					_car(k, Vector3(x + 1.7, 0.19, r.position.y + 5), 0.0, _car_color())
				if rng.randf() < 0.5:
					_car(k, Vector3(x + 1.7, 0.19, r.end.y - 6), PI, _car_color())
		"verde":
			k.cat = "veg"
			k.box_ab(Vector3(r.position.x + 1, 0.17, r.position.y + 1), Vector3(r.end.x - 1, 0.2, r.end.y - 1), GRASS)
			for i in 9:
				_tree(k, Vector3(rng.randf_range(r.position.x + 3, r.end.x - 3), 0.2, rng.randf_range(r.position.y + 3, r.end.y - 3)), rng.randf_range(0.8, 1.2))
			_bench(k, Vector3(r.get_center().x, 0.2, r.end.y - 3), 0.0)
	_mesh(k, self)


# Detalhes por tipologia: residencial (varandas com grade), escritório (faixas de vidro),
# loja com sobreloja e prédio antigo (cornija e frisos). O desgaste muda manchas e reparos.
func _family_details(k: Kit, kw: Kit, kl: Kit, rect: Rect2, lo: Vector3, hi: Vector3, wall: Color, floors: int, family: String, wear: float) -> void:
	var height := hi.y - lo.y
	var fh := height / maxf(floors, 1)
	match family:
		"res":
			# térreo com portaria e grade, varandas nos andares
			k.box_ab(Vector3(lo.x - 0.06, lo.y, hi.z - 0.02), Vector3(hi.x + 0.06, lo.y + fh, hi.z + 0.06), wall.darkened(0.12))
			var gx := rect.get_center().x
			k.box_ab(Vector3(gx - 1.6, lo.y + 2.5, hi.z), Vector3(gx + 1.6, lo.y + 2.65, hi.z + 1.6), Color("#55575a"))
			k.box_ab(Vector3(gx - 1.0, lo.y, hi.z + 0.02), Vector3(gx + 1.0, lo.y + 2.3, hi.z + 0.06), Color("#2f3336"))
			kl.box(Vector3(gx, lo.y + 1.15, hi.z + 0.07), Vector3(1.6, 1.9, 0.02), Color.WHITE)
			for f in range(1, floors):
				var y := lo.y + f * fh
				var x := lo.x + 1.4
				while x < hi.x - 1.2:
					if rng.randf() < 0.75:
						k.box_ab(Vector3(x - 0.95, y - 0.05, hi.z), Vector3(x + 0.95, y + 0.08, hi.z + 0.95), wall.lightened(0.08))
						var rail := Color("#3a3c3e") if rng.randf() < 0.6 else wall.lightened(0.18)
						k.box_ab(Vector3(x - 0.95, y + 0.08, hi.z + 0.9), Vector3(x + 0.95, y + 1.0, hi.z + 0.95), Color(rail, 1.0))
						for sx in [-0.95, 0.95]:
							k.box_ab(Vector3(x + sx - 0.025, y + 0.08, hi.z), Vector3(x + sx + 0.025, y + 1.0, hi.z + 0.95), rail)
						if rng.randf() < 0.35:
							k.sphere(Vector3(x + 0.6, y + 0.35, hi.z + 0.55), Vector3(0.45, 0.45, 0.45), Color("#4f6a3a"))
						if rng.randf() < 0.3:
							k.box(Vector3(x - 0.4, y + 0.9, hi.z + 0.5), Vector3(0.9, 0.04, 0.04), Color("#6a6a6a"))
							for ci in 3:
								k.box(Vector3(x - 0.7 + ci * 0.3, y + 0.65, hi.z + 0.5), Vector3(0.2, 0.4, 0.02), Color.from_hsv(rng.randf(), 0.4, 0.85))
						# ar-condicionado na parede
						if rng.randf() < 0.45:
							k.box(Vector3(x + 1.25, y + 1.9, hi.z + 0.2), Vector3(0.7, 0.45, 0.4), Color("#d4d6d6"))
					x += 2.6
		"office":
			# faixas contínuas de vidro e frisos de concreto
			for f in floors:
				var y0 := lo.y + f * fh
				kw.box_ab(Vector3(lo.x + 0.4, y0 + 0.9, hi.z + 0.02), Vector3(hi.x - 0.4, y0 + fh - 0.35, hi.z + 0.07), Color.WHITE)
				kw.box_ab(Vector3(hi.x + 0.02, y0 + 0.9, lo.z + 0.4), Vector3(hi.x + 0.07, y0 + fh - 0.35, hi.z - 0.4), Color.WHITE)
				if rng.randf() < 0.4:
					kl.box_ab(Vector3(lo.x + 0.4 + rng.randf() * (rect.size.x - 4.0), y0 + 0.9, hi.z + 0.075), Vector3(lo.x + 3.5 + rng.randf() * (rect.size.x - 4.0), y0 + fh - 0.35, hi.z + 0.08), Color.WHITE)
				k.box_ab(Vector3(lo.x - 0.05, y0 + fh - 0.35, hi.z), Vector3(hi.x + 0.05, y0 + fh, hi.z + 0.12), wall.lightened(0.1))
			var mx := lo.x + rect.size.x * 0.5
			for vx in range(int(rect.size.x / 3.0)):
				k.box_ab(Vector3(lo.x + vx * 3.0 - 0.06, lo.y, hi.z), Vector3(lo.x + vx * 3.0 + 0.06, hi.y, hi.z + 0.14), wall.darkened(0.1))
			k.box_ab(Vector3(mx - 2.0, lo.y, hi.z), Vector3(mx + 2.0, lo.y + 3.0, hi.z + 2.0), Color("#3a3f44"))
		"old":
			# prédio antigo: cornija, frisos e porta alta
			k.box_ab(Vector3(lo.x - 0.2, hi.y - 0.5, lo.z - 0.2), Vector3(hi.x + 0.2, hi.y - 0.2, hi.z + 0.2), wall.lightened(0.15))
			k.box_ab(Vector3(lo.x - 0.12, lo.y + fh - 0.12, hi.z), Vector3(hi.x + 0.12, lo.y + fh + 0.05, hi.z + 0.1), wall.lightened(0.1))
			k.box_ab(Vector3(lo.x - 0.05, lo.y, hi.z), Vector3(hi.x + 0.05, lo.y + 0.9, hi.z + 0.05), wall.darkened(0.22))
		"shop":
			pass
	# desgaste: escorridos de chuva, manchas e reparos de reboco
	if wear > 0.3:
		for i in int(wear * rect.size.x * 0.5):
			var sx := rng.randf_range(lo.x + 0.3, hi.x - 0.3)
			var ln := rng.randf_range(0.8, minf(height * 0.6, 4.0))
			k.box(Vector3(sx, hi.y - 0.3 - ln / 2.0, hi.z + 0.015), Vector3(rng.randf_range(0.1, 0.3), ln, 0.01), wall.darkened(0.12 + wear * 0.12))
		for i in int(wear * rect.size.y * 0.35):
			var sz := rng.randf_range(lo.z + 0.3, hi.z - 0.3)
			var ln2 := rng.randf_range(0.8, minf(height * 0.6, 4.0))
			k.box(Vector3(hi.x + 0.015, hi.y - 0.3 - ln2 / 2.0, sz), Vector3(0.01, ln2, rng.randf_range(0.1, 0.3)), wall.darkened(0.12 + wear * 0.12))
	if wear > 0.6:
		for i in int(wear * 4.0):
			k.box(Vector3(rng.randf_range(lo.x + 0.5, hi.x - 0.5), rng.randf_range(lo.y + 0.5, hi.y - 0.8), hi.z + 0.018), Vector3(rng.randf_range(0.5, 1.6), rng.randf_range(0.3, 0.8), 0.01), wall.lerp(Color("#b5ad9c"), 0.5))
	k.box_ab(Vector3(lo.x - 0.02, lo.y, hi.z - 0.01), Vector3(hi.x + 0.02, lo.y + 0.3 + wear * 0.4, hi.z + 0.024), wall.darkened(0.28 + wear * 0.12))


func _wsz(along_x: bool, a: float, up: float, d: float) -> Vector3:
	return Vector3(a, up, d) if along_x else Vector3(d, up, a)


# Janela completa: vidro (ou luz acesa), moldura saltada, peitoril e às vezes cortina, persiana ou tábuas.
func _window(k, kw, kl, c: Vector3, along_x: bool, frame_c: Color, family: String) -> void:
	var w := 1.0
	var h := 1.2
	var n := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var lit := rng.randf() < 0.35
	var boarded := rng.randf() < float(SCEN_TOUCH.get(Art.id(), {}).get("boards", 0.0))
	(kl if lit and not boarded else kw).box(c + n * 0.03, _wsz(along_x, w, h, 0.06), Color.WHITE)
	for sy in [-1.0, 1.0]:
		k.box(c + n * 0.07 + Vector3(0, sy * (h / 2.0 + 0.035), 0), _wsz(along_x, w + 0.14, 0.07, 0.08), frame_c)
	for sx in [-1.0, 1.0]:
		var side := Vector3(sx * (w / 2.0 + 0.035), 0, 0) if along_x else Vector3(0, 0, sx * (w / 2.0 + 0.035))
		k.box(c + n * 0.07 + side, _wsz(along_x, 0.07, h, 0.08), frame_c)
	k.box(c + n * 0.1 + Vector3(0, -h / 2.0 - 0.1, 0), _wsz(along_x, w + 0.3, 0.07, 0.2), frame_c.lightened(0.08))
	if family == "old":
		k.box(c + n * 0.09 + Vector3(0, h / 2.0 + 0.16, 0), _wsz(along_x, w + 0.34, 0.14, 0.14), frame_c.lightened(0.05))
	if boarded:
		for bi in 3:
			var plank := Basis(n, rng.randf_range(-0.15, 0.15)) * Basis.from_scale(_wsz(along_x, w + 0.12, 0.2, 0.03))
			k.add("box", Transform3D(plank, c + n * 0.09 + Vector3(0, -0.4 + bi * 0.4, 0)), Color("#7a6248").darkened(rng.randf() * 0.25))
		return
	var roll := rng.randf()
	if roll < 0.28:
		# cortina de um lado; numa janela acesa ela brilha quente por trás
		var cc: Color = Color(CURTAINS[rng.randi() % CURTAINS.size()])
		var off := (1.0 if rng.randf() < 0.5 else -1.0) * w * 0.27
		var cpos := c + n * 0.065 + (Vector3(off, 0, 0) if along_x else Vector3(0, 0, off))
		if lit:
			kl.box(cpos, _wsz(along_x, w * 0.44, h * 0.94, 0.02), cc.lerp(Color("#ffcf8a"), 0.4))
		else:
			k.box(cpos, _wsz(along_x, w * 0.44, h * 0.94, 0.02), cc)
	elif roll < 0.45:
		# persiana meio baixada
		for si in 5:
			k.box(c + n * 0.066 + Vector3(0, h / 2.0 - 0.06 - si * 0.12, 0), _wsz(along_x, w * 0.96, 0.07, 0.015), Color("#d8d4c8").darkened(rng.randf() * 0.1))


# Pichação na altura da mão e, às vezes, um grafite colorido (mais no Colapso, quase nada no interior).
func _tags(k, lo: Vector3, hi: Vector3) -> void:
	if rng.randf() > float(SCEN_TOUCH.get(Art.id(), {}).get("tags", 0.0)):
		return
	var x0 := rng.randf_range(lo.x + 0.4, maxf(lo.x + 0.5, hi.x - 3.0))
	var ink := Color("#1e1e22")
	for i in rng.randi_range(4, 9):
		var px := x0 + rng.randf_range(0.0, 2.6)
		var py := lo.y + rng.randf_range(1.0, 2.2)
		var stroke := Basis(Vector3.BACK, rng.randf_range(-0.5, 0.5)) * Basis.from_scale(Vector3(rng.randf_range(0.15, 0.5), 0.035, 0.01))
		k.add("box", Transform3D(stroke, Vector3(px, py, hi.z + 0.022)), ink if rng.randf() < 0.75 else Color.from_hsv(rng.randf(), 0.7, 0.75))
	if rng.randf() < 0.3:
		var gx := rng.randf_range(lo.x + 1.0, maxf(lo.x + 1.1, hi.x - 2.5))
		for b in 4:
			k.box(Vector3(gx + b * 0.42, lo.y + 1.3 + rng.randf_range(-0.15, 0.15), hi.z + 0.02), Vector3(0.5, rng.randf_range(0.5, 0.9), 0.01), Color.from_hsv(rng.randf(), 0.65, 0.85))


# Quarteirão de prédio: residencial, escritório ou antigo, com recuo, calçada interna e árvores.
func _predio_block(k, r: Rect2) -> void:
	var fr: Array = Art.p()["tower_floors"]
	var floors := rng.randi_range(int(fr[0]), int(fr[1]))
	var roll := rng.randf()
	var family := "res"
	if floors >= 7 and roll < 0.5:
		family = "office"
	elif roll > 0.75:
		family = "old"
	var wall := Art.pick("tower_walls", rng) if family == "office" else Art.pick("comm_walls", rng)
	var hr := Rect2(r.position.x + 4, r.position.y + 4, r.size.x - 8, r.size.y - 9)
	_simple_building(hr, floors * 3.0, wall, Color("#55575a"), false, floors, family)
	# recuo com piso, grade baixa e árvores
	k.cat = "walk"
	k.box_ab(Vector3(r.position.x + 2.2, 0.17, hr.end.y), Vector3(r.end.x - 2.2, 0.185, r.end.y - 2.2), SIDEWALK.lightened(0.06))
	k.cat = "props"
	var gate_c := Color("#2e3033")
	for gx in [hr.position.x, hr.end.x]:
		k.box_ab(Vector3(gx - 0.05, 0.17, hr.end.y + 0.2), Vector3(gx + 0.05, 1.3, r.end.y - 2.4), gate_c)
	for i in int((hr.size.x) / 0.3):
		var x := hr.position.x + i * 0.3
		if absf(x - hr.get_center().x) < 1.8:
			continue
		k.box_ab(Vector3(x - 0.015, 0.17, r.end.y - 2.45), Vector3(x + 0.015, 1.3, r.end.y - 2.4), gate_c)
	k.box_ab(Vector3(hr.position.x, 1.28, r.end.y - 2.47), Vector3(hr.end.x, 1.33, r.end.y - 2.38), gate_c)
	for i in 3:
		var tx := r.position.x + 3.2 + i * 11.8
		if absf(tx - hr.get_center().x) > 2.5:
			_tree(k, Vector3(tx, 0.17, r.end.y - 1.3), 0.75)
	if Art.id() == "nova_aurora" and floors >= 8:
		# pódio comercial no térreo
		k.box_ab(Vector3(hr.position.x - 0.4, 0.17, hr.end.y - 0.2), Vector3(hr.end.x + 0.4, 3.6, hr.end.y + 0.6), Color("#3a3d40"))


# ---------- locais do jogo ----------

const INTERIOR_FLOOR := {
	# pisos claros um pouco mais escuros: com a luz interna + a do dia, quase-branco estourava
	"bar": Color("#6e4a2f"), "loja": Color("#bdb7ab"), "comida": Color("#b3a47e"), "casa": Color("#8a6a48"),
	"hospedagem": Color("#7a5a3c"), "servico": Color("#a8b1ac"), "igreja": Color("#9b8f80"),
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
	var k := ChunkKit.new(0.0)
	k.cat = "solid"
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
				k.cat = "walk"
				k.box_ab(Vector3(r.position.x + 1, 0.17, r.position.y + 1), Vector3(r.end.x - 1, 0.19, r.end.y - 1), Color("#9f9a8f"))
				k.cat = "solid"
	if b.size != Vector2.ZERO:
		var tipo := str(loc.get("tipo", "casa"))
		if id == "hospital" or id == "delegacia":
			tipo = "servico"
		if id == "igreja":
			tipo = "igreja"
		# quintal/frente
		var yard := GRASS if tipo in ["casa", "hospedagem", "igreja"] else Color("#8a877f")
		k.cat = "veg" if tipo in ["casa", "hospedagem", "igreja"] else "walk"
		k.box_ab(Vector3(r.position.x + 1, 0.17, r.position.y + 1), Vector3(r.end.x - 1, 0.19, r.end.y - 1), yard)
		k.cat = "walk"
		if tipo not in ["casa", "hospedagem", "igreja"]:
			for i in 6:
				var lx := r.position.x + 2.5 + i * 4.4
				k.box_ab(Vector3(lx, 0.19, b.end.y + 2.2), Vector3(lx + 0.1, 0.2, r.end.y - 0.8), LINE)
				if rng.randf() < 0.4 and absf(lx + 2.2 - lot["door_x"]) > 3.0:
					_car(k, Vector3(lx + 2.2, 0.19, b.end.y + 5.0), PI, _car_color())
			for i in 3:
				_tree(k, Vector3(r.position.x + 2.0 + i * 13.0, 0.19, r.position.y + 1.8), 0.8)
		k.box_ab(Vector3(lot["door_x"] - 1.2, 0.19, b.end.y), Vector3(lot["door_x"] + 1.2, 0.21, r.end.y), Color("#a8a397"))
		k.cat = "solid"
		if tipo in ["casa", "hospedagem", "igreja"]:
			for i in 3:
				_tree(k, Vector3(r.position.x + 2.5 + i * 12.5, 0.19, r.position.y + 2.5), 0.9)
		_location_building(id, tipo, b)
	_mesh(k, self)


func _location_building(id: String, tipo: String, b: Rect2) -> void:
	var s := _structure(b, id)
	s["enterable"] = true
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
	kw.vary_glass = true
	kl.vary_lit = true
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
		# paredes do fundo (longe da câmera) ficam inteiras também na versão aberta
		kit.box_ab(Vector3(b.position.x, y0, b.position.y), Vector3(b.end.x, y0 + h, b.position.y + WALL_T), wall)
		kit.box_ab(Vector3(b.position.x, y0, b.position.y), Vector3(b.position.x + WALL_T, y0 + h, b.end.y), wall)
		kit.box_ab(Vector3(b.end.x - WALL_T, y0, b.position.y), Vector3(b.end.x, top, b.end.y), wall)
		kit.box_ab(Vector3(b.position.x, y0, b.end.y - WALL_T), Vector3(door_x - 0.9, top, b.end.y), wall)
		kit.box_ab(Vector3(door_x + 0.9, y0, b.end.y - WALL_T), Vector3(b.end.x, top, b.end.y), wall)
		if kk == kf:
			kit.box_ab(Vector3(door_x - 0.9, y0 + 2.3, b.end.y - WALL_T), Vector3(door_x + 0.9, top, b.end.y), wall)
		# rodapé externo
		kit.box_ab(Vector3(b.position.x - 0.04, y0, b.end.y - 0.02), Vector3(door_x - 0.9, y0 + 0.4, b.end.y + 0.04), wall.darkened(0.3))
		kit.box_ab(Vector3(door_x + 0.9, y0, b.end.y - 0.02), Vector3(b.end.x + 0.04, y0 + 0.4, b.end.y + 0.04), wall.darkened(0.3))
	# acabamento interno das paredes do fundo (visto com o prédio aberto)
	var lining := WALL_COLORS.get(tipo, wall).lerp(Color("#e6dcc8"), 0.45) as Color
	kc.box_ab(Vector3(b.position.x + WALL_T, y0, b.position.y + WALL_T), Vector3(b.end.x - WALL_T, y0 + h - 0.02, b.position.y + WALL_T + 0.02), lining)
	kc.box_ab(Vector3(b.position.x + WALL_T, y0, b.position.y + WALL_T), Vector3(b.position.x + WALL_T + 0.02, y0 + h - 0.02, b.end.y - WALL_T), lining)
	kc.box_ab(Vector3(b.position.x + WALL_T, y0, b.position.y + WALL_T), Vector3(b.end.x - WALL_T, y0 + 0.16, b.position.y + WALL_T + 0.045), lining.darkened(0.35))
	kc.box_ab(Vector3(b.position.x + WALL_T, y0, b.position.y + WALL_T), Vector3(b.position.x + WALL_T + 0.045, y0 + 0.16, b.end.y - WALL_T), lining.darkened(0.35))
	# vitrines/janelas
	var wy := y0 + 1.6
	var x2 := b.position.x + 1.6
	while x2 < b.end.x - 1.4:
		if absf(x2 - door_x) > 2.0:
			var shop := tipo in ["loja", "comida", "bar"]
			var target := kl if (shop or rng.randf() < 0.5) else kw
			var ww: float = 1.8 if shop else 1.1
			var wh: float = 1.4 if shop else 1.1
			kf.box(Vector3(x2, wy, b.end.y + 0.0), Vector3(ww + 0.25, wh + 0.25, 0.1), Color("#efe9da") if tipo != "bar" else Color("#3a2a20"))
			kf.box(Vector3(x2, wy - wh / 2.0 - 0.14, b.end.y + 0.08), Vector3(ww + 0.4, 0.08, 0.22), Color("#c9c1ae"))
			if shop:
				kf.box(Vector3(x2, wy, b.end.y + 0.04), Vector3(0.05, wh, 0.05), Color("#efe9da"))
			target.box(Vector3(x2, wy, b.end.y + 0.04), Vector3(ww, wh, 0.05), Color.WHITE)
		x2 += 2.8 if tipo in ["loja", "comida", "bar"] else 3.0
	var z2 := b.position.y + 1.6
	while z2 < b.end.y - 1.4:
		kf.box(Vector3(b.end.x + 0.0, wy, z2), Vector3(0.1, 1.35, 1.35), Color("#efe9da"))
		kw.box(Vector3(b.end.x + 0.04, wy, z2), Vector3(0.05, 1.1, 1.1), Color.WHITE)
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
	_facade_extras(kf, always, b, y0, h, tipo, wall, door_x, id)
	_identity(id, tipo, b, kf, always, y0, door_x)
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


# Detalhes de fachada dos locais do jogo: cornija, pilastras, degraus, ar-condicionado, cartazes, reservatório.
func _facade_extras(kf: Kit, ka: Kit, b: Rect2, y0: float, h: float, tipo: String, wall: Color, door_x: float, id: String) -> void:
	var trim := wall.lightened(0.18)
	# cornija e platibanda
	kf.box_ab(Vector3(b.position.x - 0.18, y0 + h - 0.35, b.position.y - 0.18), Vector3(b.end.x + 0.18, y0 + h - 0.1, b.end.y + 0.18), trim)
	# pilastras nos cantos
	for cx in [b.position.x, b.end.x]:
		kf.box_ab(Vector3(cx - 0.15, y0, b.end.y - 0.15), Vector3(cx + 0.15, y0 + h, b.end.y + 0.1), trim.darkened(0.04))
	# moldura e degraus da porta
	kf.box_ab(Vector3(door_x - 1.05, y0, b.end.y - 0.05), Vector3(door_x - 0.9, y0 + 2.45, b.end.y + 0.14), trim)
	kf.box_ab(Vector3(door_x + 0.9, y0, b.end.y - 0.05), Vector3(door_x + 1.05, y0 + 2.45, b.end.y + 0.14), trim)
	kf.box_ab(Vector3(door_x - 1.05, y0 + 2.3, b.end.y - 0.05), Vector3(door_x + 1.05, y0 + 2.45, b.end.y + 0.14), trim)
	ka.box_ab(Vector3(door_x - 1.3, y0, b.end.y), Vector3(door_x + 1.3, y0 + 0.1, b.end.y + 0.7), Color("#a8a397"))
	if tipo in ["bar", "comida", "loja", "servico"]:
		# faixa de cor na base e cartazes
		kf.box_ab(Vector3(b.position.x, y0 + 0.4, b.end.y), Vector3(b.end.x, y0 + 0.9, b.end.y + 0.03), wall.darkened(0.2))
		for i in rng.randi_range(2, 4):
			var px := rng.randf_range(b.position.x + 1.0, b.end.x - 1.0)
			if absf(px - door_x) < 2.2:
				continue
			kf.box(Vector3(px, y0 + 1.6, b.end.y + 0.05), Vector3(rng.randf_range(0.5, 0.9), rng.randf_range(0.6, 1.1), 0.02), Color.from_hsv(rng.randf(), 0.5, 0.9))
	# ar-condicionado, reservatório e antena no telhado
	if tipo not in ["casa", "hospedagem", "igreja"]:
		for i in 2:
			var ax := b.position.x + 3.0 + i * 3.2
			kf.box_ab(Vector3(ax, y0 + h + 0.3, b.end.y - 4.0), Vector3(ax + 1.4, y0 + h + 1.1, b.end.y - 2.8), Color("#cfd2d6"))
			kf.cyl(Vector3(ax + 0.7, y0 + h + 1.1, b.end.y - 3.4), 0.5, 0.08, Color("#6a6e72"))
		kf.cyl(Vector3(b.end.x - 2.5, y0 + h + 0.3, b.position.y + 2.5), 1.0, 1.6, Color("#4c6b8a"))
		kf.cyl(Vector3(b.end.x - 2.5, y0 + h + 1.9, b.position.y + 2.5), 1.05, 0.15, Color("#3a4f68"))
		kf.cyl(Vector3(b.position.x + 1.5, y0 + h + 0.3, b.position.y + 1.5), 0.04, 2.4, Color("#6a6e72"))
	# vaso de plantas e lixeira na frente
	if tipo != "igreja":
		for sx in [-1, 1]:
			var vp := Vector3(door_x + sx * 2.1, y0, b.end.y + 0.6)
			ka.cyl(vp, 0.3, 0.5, Color("#9a5a3a"))
			ka.sphere(vp + Vector3(0, 0.8, 0), Vector3(0.7, 0.7, 0.7), Color("#4f8a3f"))


# Identidade dos lugares importantes: cada um conta o que é pela fachada e pela calçada.
func _identity(id: String, tipo: String, b: Rect2, kf: Kit, ka: Kit, y0: float, door_x: float) -> void:
	var front := b.end.y
	match id:
		"bar":
			# boteco: azulejo na fachada, mesas de plástico, engradados, letreiro de neon
			var tx := b.position.x + 0.2
			var row := 0
			while tx < b.end.x - 0.2:
				if absf(tx - door_x) > 1.1:
					for ty in 4:
						var cz := Color("#d8e4ea") if (row + ty) % 2 == 0 else Color("#5a8aa8")
						kf.box_ab(Vector3(tx, y0 + 0.45 + ty * 0.25, front), Vector3(minf(tx + 0.25, b.end.x - 0.2), y0 + 0.7 + ty * 0.25, front + 0.025), cz)
				tx += 0.25
				row += 1
			for ti in 3:
				var tp := Vector3(b.position.x + 1.6 + ti * 2.6, y0, front + 2.4)
				if absf(tp.x - door_x) < 1.5:
					continue
				ka.cyl(tp, 0.38, 0.72, Color("#c99a20"))
				ka.cyl(tp + Vector3(0, 0.68, 0), 0.44, 0.05, Color("#e0b030"))
				for ci in 3:
					var ang := ci * TAU / 3.0
					var cp := tp + Vector3(cos(ang) * 0.75, 0, sin(ang) * 0.75)
					ka.box(cp + Vector3(0, 0.42, 0), Vector3(0.42, 0.05, 0.42), Color("#e0b030"))
					ka.add("box", Transform3D(Basis(Vector3.UP, -ang + PI / 2.0) * Basis.from_scale(Vector3(0.42, 0.45, 0.04)), cp + Vector3(cos(ang) * 0.2, 0.66, sin(ang) * 0.2)), Color("#d4a628"))
			for ci2 in 4:
				ka.box(Vector3(b.end.x - 0.6, y0 + 0.18 + ci2 * 0.32, front + 0.6), Vector3(0.6, 0.3, 0.42), Color("#a82a22") if ci2 % 2 == 0 else Color("#c04030"))
			var nk := Kit.new()
			nk.box(Vector3(door_x - 1.9, y0 + 2.25, front + 0.16), Vector3(0.9, 0.36, 0.05), Color("#ff3a3a"))
			nk.box(Vector3(door_x - 1.9, y0 + 2.25, front + 0.19), Vector3(0.7, 0.18, 0.02), Color("#ffd0c0"))
			_mesh(nk, self, neon_mat)
		"lanchonete", "minha_lanchonete":
			# balcão para a calçada, banquetas e cardápio de cavalete
			kf.box_ab(Vector3(door_x + 1.3, y0 + 0.95, front), Vector3(b.end.x - 0.8, y0 + 1.05, front + 0.45), Color("#d8d2c4"))
			for si in 4:
				var sp := Vector3(door_x + 1.8 + si * 0.8, y0, front + 0.85)
				if sp.x > b.end.x - 0.6:
					break
				ka.cyl(sp, 0.05, 0.7, Color("#6a6e72"))
				ka.cyl(sp + Vector3(0, 0.7, 0), 0.2, 0.08, Color("#c0392b"))
			ka.box(Vector3(door_x - 1.6, y0 + 0.6, front + 0.9), Vector3(0.6, 1.0, 0.06), Color("#2a2a2a"), 0.2)
			ka.box(Vector3(door_x - 1.6, y0 + 0.7, front + 0.94), Vector3(0.5, 0.7, 0.01), Color("#e8e2d0"), 0.2)
		"mercado":
			# faixa de identidade, carrinhos e caixotes de feira na entrada
			kf.box_ab(Vector3(b.position.x - 0.1, y0 + 2.6, front), Vector3(b.end.x + 0.1, y0 + 3.15, front + 0.2), Color("#1f6f4a"))
			kf.box_ab(Vector3(b.position.x - 0.1, y0 + 2.55, front), Vector3(b.end.x + 0.1, y0 + 2.6, front + 0.21), Color("#e0b030"))
			for ci in 5:
				var cp := Vector3(door_x + 2.0 + ci * 0.45, y0, front + 0.7)
				ka.box(cp + Vector3(0, 0.55, 0), Vector3(0.4, 0.4, 0.75), Color("#9aa0a4"))
				ka.box(cp + Vector3(0, 0.3, 0), Vector3(0.36, 0.04, 0.7), Color("#6a6e72"))
			for fi in 3:
				var fp := Vector3(door_x - 2.0 - fi * 0.9, y0, front + 0.6)
				ka.box(fp + Vector3(0, 0.2, 0), Vector3(0.75, 0.4, 0.5), Color("#8a6a40"))
				for oi in 6:
					ka.sphere(fp + Vector3(-0.25 + (oi % 3) * 0.25, 0.47, -0.1 + int(oi / 3) * 0.22), Vector3(0.2, 0.18, 0.2), [Color("#e08a2a"), Color("#6aa03a"), Color("#c03a2a")][fi])
		"pensao":
			# pensão antiga: plaquinha de vagas, banco de madeira, vasos e varal no quintal
			ka.box(Vector3(door_x + 1.5, y0 + 1.7, front + 0.08), Vector3(0.7, 0.35, 0.03), Color("#f0e8d0"))
			ka.box(Vector3(door_x + 1.5, y0 + 1.7, front + 0.1), Vector3(0.55, 0.12, 0.01), Color("#8a2a22"))
			_bench(ka, Vector3(door_x - 2.0, y0, front + 0.8), 0.0)
			for vi in 4:
				ka.cyl(Vector3(b.position.x + 0.6 + vi * 0.5, y0, front + 0.4), 0.17, 0.32, Color("#9a5a3a"))
				ka.sphere(Vector3(b.position.x + 0.6 + vi * 0.5, y0 + 0.5, front + 0.4), Vector3(0.42, 0.45, 0.42), Color("#4f7a3a"))
			for sx in [-1, 1]:
				ka.box(Vector3(b.get_center().x + sx * 4.0, y0 + 0.9, b.position.y - 1.2), Vector3(0.06, 1.8, 0.06), Color("#6a6a6a"))
			for ci in 9:
				ka.box(Vector3(b.get_center().x - 3.6 + ci * 0.9, y0 + 1.5, b.position.y - 1.2), Vector3(0.45, 0.6, 0.03), Color.from_hsv(rng.randf(), 0.35, 0.9))
		"hospital":
			# marquise do pronto-socorro e ambulância
			kf.box_ab(Vector3(door_x - 3.0, y0 + 2.9, front), Vector3(door_x + 3.0, y0 + 3.05, front + 3.2), Color("#d8dcde"))
			for sx in [-2.8, 2.8]:
				kf.box(Vector3(door_x + sx, y0 + 1.45, front + 3.0), Vector3(0.18, 2.9, 0.18), Color("#c9cdd0"))
			kf.box_ab(Vector3(b.position.x - 0.05, y0 + 0.9, front), Vector3(b.end.x + 0.05, y0 + 1.15, front + 0.03), Color("#2c5d8f"))
			var amb := Vector3(door_x + 5.5, y0, front + 3.5)
			ka.box(amb + Vector3(0, 1.15, 0), Vector3(2.0, 1.9, 4.6), Color("#eceae4"))
			ka.box(amb + Vector3(0, 1.0, 0), Vector3(2.04, 0.22, 4.64), Color("#c0302a"))
			ka.box(amb + Vector3(0, 1.4, 2.0), Vector3(1.9, 0.5, 0.6), Color("#1d2630"))
			ka.box(amb + Vector3(0, 2.15, 1.6), Vector3(1.2, 0.12, 0.3), Color("#2a5aa8"))
			for wx in [-0.9, 0.9]:
				for wz in [-1.5, 1.5]:
					ka.add("cyl", Transform3D(Basis(Vector3.FORWARD, PI / 2.0).scaled(Vector3(0.7, 0.3, 0.7)), amb + Vector3(wx, 0.35, wz)), Color("#141414"))
		"delegacia":
			# faixa institucional, mastro e viaturas
			kf.box_ab(Vector3(b.position.x - 0.05, y0 + 2.4, front), Vector3(b.end.x + 0.05, y0 + 2.75, front + 0.04), Color("#1f2f4f"))
			var fp := Vector3(b.position.x + 1.2, y0, front + 2.5)
			ka.cyl(fp, 0.06, 7.0, Color("#c9cdd0"))
			ka.box(fp + Vector3(0.75, 6.4, 0), Vector3(1.4, 0.9, 0.03), Color("#2a6a3a"))
			ka.box(fp + Vector3(0.75, 6.4, 0.02), Vector3(0.9, 0.55, 0.01), Color("#e0c040"))
			for vi in 2:
				var vp := Vector3(door_x + 3.0 + vi * 3.0, y0, front + 4.0)
				_car(ka, vp, 0.0, Color("#e8e8e6"))
				ka.box(vp + Vector3(0, 0.66, 0), Vector3(1.82, 0.18, 4.22), Color("#1a1a1a"))
				ka.box(vp + Vector3(0, 1.62, -0.2), Vector3(1.0, 0.12, 0.3), Color("#c03030"))
		"igreja":
			# escadaria de pedra e jardim
			for st in 3:
				ka.box_ab(Vector3(door_x - 2.2 + st * 0.2, y0 + st * 0.15, front + 1.4 - st * 0.4), Vector3(door_x + 2.2 - st * 0.2, y0 + 0.15 + st * 0.15, front + 1.8 - st * 0.4), Color("#b8b0a0"))
			for gi in 6:
				ka.sphere(Vector3(b.position.x + 0.8 + gi * 1.8, y0 + 0.4, front + 1.2), Vector3(0.9, 0.7, 0.9), Color("#4a6a38"))


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
					seats.append({"p": Vector2(p.x + cos(ang), p.z + sin(ang)), "yaw": atan2(-cos(ang), -sin(ang))})
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
					seats.append({"p": Vector2(p.x + side * 1.0, p.z), "yaw": atan2(-side, 0.0)})
		"casa":
			_furnish_home(k, id, b, y0)
		"hospedagem":
			k.box_ab(Vector3(b.position.x + 1.2, y0, b.end.y - 4.0), Vector3(b.position.x + 4.5, y0 + 1.05, b.end.y - 3.2), Color("#5a3a22"))
			k.box_ab(Vector3(b.position.x + 0.5, y0, top + 5.0), Vector3(b.end.x - 0.5, y0 + WALL_H, top + 5.25), Color("#b78c6a"))
			for room in 3:
				var rx := b.position.x + 1.0 + room * (b.size.x / 3.0)
				_bed_furniture(k, Vector3(rx, y0, top + 1.0), 1.8, 2.4, Color("#d8d0c0"), Color("#6b4a7a"), Color("#5a3e26"))
				var bed_p := {"p": Vector2(rx + 0.9, top + 3.85), "anchor": Vector3(rx + 0.9, 0, top + 3.25), "yaw": 0.0, "h": 0.5}
				if room == 0:
					use_points["quarto_pensao"] = {"cama": {"path": [bed_p["p"]], "anchor": bed_p["anchor"], "yaw": 0.0, "h": 0.5}}
				else:
					beds.append(bed_p)
		"servico":
			if id == "hospital":
				_furnish_hospital(k, b, y0)
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


# Cama de verdade: estrutura com pés, cabeceira, colchão, lençol, coberta dobrada e travesseiro.
# A cabeceira fica no lado de z menor (fundo); quem deita tem os pés no lado de z maior.
func _bed_furniture(k, p: Vector3, w: float, l: float, sheet: Color, blanket: Color, wood: Color) -> void:
	var y := p.y
	for fx in [0.06, w - 0.06]:
		for fz in [0.06, l - 0.06]:
			k.box(p + Vector3(fx, 0.12, fz), Vector3(0.08, 0.24, 0.08), wood.darkened(0.15))
	k.box_ab(p + Vector3(0, 0.2, 0), p + Vector3(w, 0.32, l), wood)
	k.box_ab(p + Vector3(-0.02, 0, -0.06), p + Vector3(w + 0.02, 0.95, 0.04), wood.lightened(0.05))
	k.box_ab(p + Vector3(0.04, 0.32, 0.06), p + Vector3(w - 0.04, 0.5, l - 0.04), sheet)
	k.box_ab(p + Vector3(0.02, 0.48, l * 0.38), p + Vector3(w - 0.02, 0.56, l - 0.02), blanket)
	k.box_ab(p + Vector3(0.02, 0.5, l * 0.36), p + Vector3(w - 0.02, 0.6, l * 0.46), blanket.lightened(0.12))
	k.box_ab(p + Vector3(w * 0.12, 0.5, 0.12), p + Vector3(w * 0.88, 0.64, 0.55), Color("#f2efe8"))
	k.soft_shadow(p + Vector3(w / 2.0, 0.0, l / 2.0), w * 0.62, l * 0.58, 0.3, 0.0, 0.75, 0.8)


func _chair_furniture(k, p: Vector3, yaw: float, col: Color) -> void:
	var bs := Basis(Vector3.UP, yaw)
	for fx in [-0.19, 0.19]:
		for fz in [-0.19, 0.19]:
			k.add("box", Transform3D(bs * Basis.from_scale(Vector3(0.05, 0.45, 0.05)), p + bs * Vector3(fx, 0.225, fz)), col.darkened(0.2))
	k.add("box", Transform3D(bs * Basis.from_scale(Vector3(0.46, 0.06, 0.46)), p + Vector3(0, 0.46, 0)), col)
	k.add("box", Transform3D(bs * Basis.from_scale(Vector3(0.46, 0.5, 0.05)), p + bs * Vector3(0, 0.74, -0.21)), col)
	seats.append({"p": Vector2(p.x, p.z), "yaw": yaw})


# Casa do jogador (apartamento, kitnet, apto, sobrado): um vão só, mas com quarto, cozinha,
# banheiro e sala de verdade. Cada móvel útil tem ponto de uso (deitar, banho, sentar).
func _furnish_home(k, id: String, b: Rect2, y0: float) -> void:
	var o := Vector3(b.position.x, y0, b.position.y)
	var wood := Color("#6a4a30")
	var tone := Color(rng.randf_range(0.8, 1.0), rng.randf_range(0.8, 1.0), rng.randf_range(0.8, 1.0))
	# --- quarto ---
	var blanket := Color(["#3e5a80", "#7a3a3a", "#4f6a4a", "#6a5a7a"][rng.randi() % 4])
	_bed_furniture(k, o + Vector3(0.6, 0, 0.42), 2.0, 2.6, Color("#e9e4d8"), blanket, wood)
	k.box_ab(o + Vector3(2.75, 0, 0.45), o + Vector3(3.3, 0.55, 0.95), wood.lightened(0.08))
	k.box(o + Vector3(3.02, 0.37, 0.95), Vector3(0.3, 0.02, 0.02), Color("#c9b98a"))
	k.cyl(o + Vector3(3.02, 0.55, 0.7), 0.06, 0.28, Color("#3a3a3a"))
	k.cone(o + Vector3(3.02, 0.83, 0.7), 0.17, 0.2, Color("#e8d9b0"))
	k.box_ab(o + Vector3(0.32, 0, 3.6), o + Vector3(0.95, 2.1, 5.4), wood.darkened(0.08))
	k.box_ab(o + Vector3(0.95, 0.1, 4.49), o + Vector3(0.97, 2.0, 4.51), wood.darkened(0.3))
	for hz in [4.35, 4.65]:
		k.box(o + Vector3(0.98, 1.05, hz), Vector3(0.03, 0.2, 0.03), Color("#c9b98a"))
	use_points[id] = {"cama": {"path": [Vector2(o.x + 1.6, o.z + 3.45)], "anchor": Vector3(o.x + 1.6, 0, o.z + 2.95), "yaw": 0.0, "h": 0.52}}
	# --- cozinha (parede do fundo, lado direito) ---
	var counter := Color("#d8d0c0").lerp(tone, 0.2)
	k.box_ab(o + Vector3(6.4, 0, 0.35), o + Vector3(10.4, 0.88, 1.0), Color("#b8ad98"))
	k.box_ab(o + Vector3(6.38, 0.88, 0.33), o + Vector3(10.42, 0.93, 1.02), counter)
	for dx in range(4):
		k.box_ab(o + Vector3(6.5 + dx * 1.0, 0.1, 1.0), o + Vector3(7.35 + dx * 1.0, 0.8, 1.015), Color("#a89d88"))
		k.box(o + Vector3(6.92 + dx * 1.0, 0.72, 1.03), Vector3(0.2, 0.025, 0.025), Color("#7a7a7a"))
	k.box_ab(o + Vector3(8.2, 0.86, 0.45), o + Vector3(9.0, 0.935, 0.9), Color("#9aa0a4"))
	k.box_ab(o + Vector3(8.3, 0.84, 0.52), o + Vector3(8.9, 0.94, 0.83), Color("#5a6066"))
	k.cyl(o + Vector3(8.6, 0.93, 0.42), 0.025, 0.28, Color("#b0b4b8"))
	k.box_ab(o + Vector3(9.4, 0.93, 0.42), o + Vector3(10.3, 0.95, 0.95), Color("#2a2a2a"))
	for bx in [9.62, 10.08]:
		for bz in [0.56, 0.82]:
			k.cyl(o + Vector3(bx, 0.95, bz), 0.1, 0.012, Color("#141414"))
	k.box_ab(o + Vector3(6.4, 1.55, 0.35), o + Vector3(10.4, 2.15, 0.7), Color("#c8bca6"))
	k.box_ab(o + Vector3(10.75, 0, 0.35), o + Vector3(11.6, 1.95, 1.05), Color("#e6e6e2"))
	k.box_ab(o + Vector3(10.75, 1.3, 1.05), o + Vector3(11.6, 1.32, 1.06), Color("#9a9a96"))
	k.box(o + Vector3(10.85, 0.9, 1.08), Vector3(0.03, 0.5, 0.03), Color("#8a8a86"))
	k.box(o + Vector3(10.85, 1.6, 1.08), Vector3(0.03, 0.22, 0.03), Color("#8a8a86"))
	for fi in 3:
		k.sphere(o + Vector3(6.7 + fi * 0.18, 0.99, 0.6), Vector3(0.12, 0.11, 0.12), [Color("#c0392b"), Color("#e0b030"), Color("#6aa03a")][fi])
	k.box(o + Vector3(7.5, 1.02, 0.6), Vector3(0.18, 0.18, 0.12), Color("#c9883a"))
	k.cyl(o + Vector3(7.9, 0.93, 0.55), 0.05, 0.22, Color("#2a6a9a"))
	# --- banheiro (canto direito, divisórias baixas para a câmera ver dentro) ---
	var tile := Color("#c8d2d6")
	k.box_ab(o + Vector3(9.0, 0, 2.38), o + Vector3(11.65, 1.15, 2.48), tile)
	k.box_ab(o + Vector3(8.92, 0, 2.38), o + Vector3(9.02, 1.15, 4.1), tile)
	k.box_ab(o + Vector3(8.92, 0, 4.95), o + Vector3(9.02, 1.15, 5.25), tile)
	k.box_ab(o + Vector3(9.02, 0.06, 2.48), o + Vector3(11.65, 0.065, 5.25), Color("#9aa6ac"))
	# box do chuveiro
	k.box_ab(o + Vector3(10.6, 0.06, 2.5), o + Vector3(11.6, 0.12, 3.5), Color("#e8ecee"))
	k.box_ab(o + Vector3(10.55, 0.12, 3.48), o + Vector3(11.6, 1.95, 3.52), Color("#a8c4d0"))
	k.box_ab(o + Vector3(10.55, 0.12, 2.5), o + Vector3(10.59, 1.95, 3.0), Color("#a8c4d0"))
	k.cyl(o + Vector3(11.5, 0.12, 2.6), 0.02, 2.0, Color("#b0b4b8"))
	k.box_ab(o + Vector3(11.0, 2.08, 2.55), o + Vector3(11.52, 2.12, 2.63), Color("#b0b4b8"))
	k.cyl(o + Vector3(11.0, 1.98, 2.62), 0.1, 0.06, Color("#c0c4c8"))
	use_points[id]["chuveiro"] = {"path": [Vector2(o.x + 8.5, o.z + 4.55), Vector2(o.x + 9.8, o.z + 4.55), Vector2(o.x + 11.08, o.z + 3.0)], "yaw": -PI / 2.0, "head": Vector3(o.x + 11.0, y0 + 1.95, o.z + 2.95)}
	# pia com espelho e vaso
	k.box_ab(o + Vector3(9.1, 0, 3.0), o + Vector3(9.55, 0.82, 3.6), Color("#e8ecee"))
	k.box_ab(o + Vector3(9.15, 0.78, 3.08), o + Vector3(9.5, 0.84, 3.52), Color("#9aa0a4"))
	k.box_ab(o + Vector3(9.03, 1.3, 3.05), o + Vector3(9.05, 1.95, 3.55), Color("#c8d8e0"))
	k.box_ab(o + Vector3(11.1, 0, 4.3), o + Vector3(11.55, 0.42, 4.75), Color("#f2f2f0"))
	k.box_ab(o + Vector3(11.45, 0.42, 4.3), o + Vector3(11.6, 0.85, 4.75), Color("#f2f2f0"))
	k.box_ab(o + Vector3(9.3, 0.9, 4.98), o + Vector3(10.1, 0.95, 5.2), Color("#c94a3a"))
	# --- sala: sofá virado para a TV, tapete, estante e planta ---
	var sofa_c := Color(["#5a6a7a", "#7a5a4a", "#4a5a4a", "#6a4a5a"][rng.randi() % 4])
	k.box_ab(o + Vector3(0.5, 0, 5.9), o + Vector3(1.45, 0.42, 8.3), sofa_c.darkened(0.1))
	k.box_ab(o + Vector3(0.5, 0.42, 5.9), o + Vector3(0.78, 0.95, 8.3), sofa_c)
	for az in [5.9, 8.05]:
		k.box_ab(o + Vector3(0.5, 0.42, az), o + Vector3(1.45, 0.66, az + 0.25), sofa_c)
	for cz in [6.2, 7.15]:
		k.box_ab(o + Vector3(0.8, 0.42, cz), o + Vector3(1.42, 0.55, cz + 0.88), sofa_c.lightened(0.08))
	seats.append({"p": Vector2(o.x + 1.15, o.z + 6.65), "yaw": PI / 2.0})
	seats.append({"p": Vector2(o.x + 1.15, o.z + 7.6), "yaw": PI / 2.0})
	k.box_ab(o + Vector3(1.7, 0, 5.8), o + Vector3(3.5, 0.015, 8.4), Color("#8a3b3b").lerp(tone, 0.3))
	k.box_ab(o + Vector3(2.1, 0, 6.6), o + Vector3(2.9, 0.42, 7.5), wood)
	k.cyl(o + Vector3(2.5, 0.42, 7.05), 0.06, 0.12, Color("#e8e2d0"))
	k.box_ab(o + Vector3(3.7, 0, 6.2), o + Vector3(4.15, 0.5, 7.9), wood.darkened(0.1))
	k.box_ab(o + Vector3(3.8, 0.5, 6.5), o + Vector3(3.9, 1.12, 7.6), Color("#151618"))
	k.box_ab(o + Vector3(3.78, 0.54, 6.54), o + Vector3(3.79, 1.08, 7.56), Color("#2a3a4a"))
	k.box_ab(o + Vector3(11.2, 0, 6.0), o + Vector3(11.65, 1.9, 7.8), wood)
	for sh in 4:
		k.box_ab(o + Vector3(11.18, 0.4 + sh * 0.45, 6.0), o + Vector3(11.2, 0.43 + sh * 0.45, 7.8), wood.darkened(0.2))
		for bk in rng.randi_range(3, 7):
			k.box(o + Vector3(11.4, 0.6 + sh * 0.45, 6.15 + bk * 0.22), Vector3(0.22, rng.randf_range(0.26, 0.36), 0.07), Color.from_hsv(rng.randf(), 0.45, 0.6))
	k.cyl(o + Vector3(11.3, 0, 9.3), 0.22, 0.4, Color("#9a5a3a"))
	k.sphere(o + Vector3(11.3, 0.8, 9.3), Vector3(0.7, 0.8, 0.7), Color("#4f7a3a"))
	# mesa de jantar com duas cadeiras
	k.box_ab(o + Vector3(7.0, 0.72, 6.0), o + Vector3(8.4, 0.78, 7.0), wood.lightened(0.1))
	for lx in [7.08, 8.32]:
		for lz in [6.08, 6.92]:
			k.box(o + Vector3(lx, 0.36, lz), Vector3(0.06, 0.72, 0.06), wood)
	k.box_ab(o + Vector3(7.2, 0.78, 6.15), o + Vector3(8.2, 0.785, 6.85), Color("#e8e2d0"))
	_chair_furniture(k, o + Vector3(7.7, 0, 5.55), 0.0, wood.lightened(0.05))
	_chair_furniture(k, o + Vector3(7.7, 0, 7.45), PI, wood.lightened(0.05))


# Hospital (protótipo de interior completo): enfermaria com leitos e cortinas, consultório,
# recepção com balcão, espera com cadeiras, farmácia interna e posto de enfermagem.
func _furnish_hospital(k, b: Rect2, y0: float) -> void:
	var o := Vector3(b.position.x, y0, b.position.y)
	var w := b.size.x
	var d := b.size.y
	var white := Color("#eef2f4")
	var steel := Color("#b4bcc2")
	var green := Color("#7fb8a8")
	# piso: faixas-guia coloridas da porta até cada setor
	k.box_ab(o + Vector3(w / 2.0 - 0.15, 0.06, d * 0.45), o + Vector3(w / 2.0 + 0.15, 0.064, d - 0.4), Color("#4f9a7a"))
	k.box_ab(o + Vector3(w * 0.62, 0.06, d * 0.45 - 0.15), o + Vector3(w - 1.0, 0.064, d * 0.45 + 0.15), Color("#4f7aa8"))
	# --- enfermaria: 4 leitos com cortina, suporte de soro e mesinha ---
	for i in 4:
		var bp := o + Vector3(0.8 + i * 3.1, 0, 0.45)
		_bed_furniture(k, bp, 1.1, 2.2, white, Color("#9fc0d0"), steel)
		k.box_ab(bp + Vector3(-0.08, 0.32, 0.4), bp + Vector3(-0.04, 0.62, 1.8), steel)
		k.box_ab(bp + Vector3(1.14, 0.32, 0.4), bp + Vector3(1.18, 0.62, 1.8), steel)
		var iv := bp + Vector3(1.45, 0, 0.35)
		k.cyl(iv, 0.12, 0.03, steel.darkened(0.2))
		k.cyl(iv, 0.018, 1.85, steel)
		k.box(iv + Vector3(0, 1.75, 0), Vector3(0.14, 0.22, 0.06), Color("#d8eef0"))
		k.box_ab(bp + Vector3(1.3, 0, 1.3), bp + Vector3(1.75, 0.75, 1.75), Color("#d8dcde"))
		k.box_ab(bp + Vector3(1.32, 0.75, 1.32), bp + Vector3(1.73, 0.78, 1.73), Color("#c8ccce"))
		if i < 3:
			# cortina (biombo de tecido) entre um leito e outro
			k.box_ab(bp + Vector3(2.4, 0, 0.1), bp + Vector3(2.44, 1.85, 2.5), green)
			k.box_ab(bp + Vector3(2.35, 1.85, 0.1), bp + Vector3(2.49, 1.9, 2.5), steel)
		beds.append({"p": Vector2(bp.x + 0.55, bp.z + 2.7), "anchor": Vector3(bp.x + 0.55, 0, bp.z + 2.1), "yaw": 0.0, "h": 0.52})
	# monitor ao lado do primeiro leito
	k.box_ab(o + Vector3(0.2, 1.2, 0.5), o + Vector3(0.6, 1.5, 0.58), Color("#2a2e32"))
	k.box_ab(o + Vector3(0.24, 1.24, 0.581), o + Vector3(0.56, 1.46, 0.59), Color("#2a6a5a"))
	# --- consultório (canto direito do fundo, divisória baixa) ---
	var cx0 := w - 8.0
	k.box_ab(o + Vector3(cx0, 0, 0.3), o + Vector3(cx0 + 0.1, 1.2, 5.6), Color("#d8dcde"))
	k.box_ab(o + Vector3(cx0, 0, 5.5), o + Vector3(w - 3.0, 1.2, 5.6), Color("#d8dcde"))
	k.box_ab(o + Vector3(cx0 + 1.0, 0, 0.6), o + Vector3(cx0 + 2.9, 0.75, 1.4), Color("#7a5a3a"))
	k.box_ab(o + Vector3(cx0 + 1.6, 0.75, 0.7), o + Vector3(cx0 + 2.2, 1.15, 0.78), Color("#202428"))
	k.box_ab(o + Vector3(cx0 + 1.3, 0.75, 1.0), o + Vector3(cx0 + 1.8, 0.77, 1.25), Color("#f2efe8"))
	_chair_furniture(k, o + Vector3(cx0 + 1.95, 0, 0.25), 0.0, Color("#3a4a5a"))
	_chair_furniture(k, o + Vector3(cx0 + 1.95, 0, 1.95), PI, Color("#5a6a7a"))
	# maca de exame com papel
	var mx := o + Vector3(w - 2.4, 0, 1.0)
	k.box_ab(mx, mx + Vector3(0.8, 0.75, 2.0), Color("#3a5a6a"))
	k.box_ab(mx + Vector3(0.06, 0.75, 0.2), mx + Vector3(0.74, 0.77, 1.9), Color("#f2efe8"))
	k.box_ab(mx + Vector3(0, 0.75, 0), mx + Vector3(0.8, 0.95, 0.4), Color("#3a5a6a"))
	k.box_ab(o + Vector3(w - 2.2, 0, 3.8), o + Vector3(w - 0.4, 0.88, 4.4), white)
	k.box_ab(o + Vector3(w - 1.6, 0.86, 3.9), o + Vector3(w - 1.0, 0.92, 4.3), steel)
	k.box_ab(o + Vector3(w - 2.2, 1.4, 3.8), o + Vector3(w - 0.4, 2.1, 4.2), white.darkened(0.05))
	# --- recepção: balcão com computador e placa ---
	var rc := o + Vector3(w / 2.0 - 3.0, 0, d - 6.4)
	k.box_ab(rc, rc + Vector3(6.0, 1.05, 0.7), Color("#e2e6e8"))
	k.box_ab(rc + Vector3(-0.05, 1.05, -0.05), rc + Vector3(6.05, 1.1, 0.75), Color("#2c5d8f"))
	k.box_ab(rc + Vector3(0, 0.1, 0.7), rc + Vector3(6.0, 0.95, 0.72), Color("#2c5d8f").lightened(0.1))
	k.box_ab(rc + Vector3(1.0, 1.1, 0.15), rc + Vector3(1.55, 1.45, 0.22), Color("#202428"))
	k.box_ab(rc + Vector3(4.2, 1.1, 0.15), rc + Vector3(4.75, 1.45, 0.22), Color("#202428"))
	k.box_ab(rc + Vector3(2.4, 1.1, 0.2), rc + Vector3(3.4, 1.12, 0.5), Color("#f2efe8"))
	_chair_furniture(k, rc + Vector3(1.3, 0, -0.45), 0.0, Color("#3a4a5a"))
	_chair_furniture(k, rc + Vector3(4.5, 0, -0.45), 0.0, Color("#3a4a5a"))
	# --- sala de espera: fileiras de cadeiras viradas para a recepção ---
	for row in 2:
		for c in 5:
			var sp := o + Vector3(1.2 + c * 0.75, 0, d - 3.4 + row * 1.6)
			_chair_furniture(k, sp, PI, Color("#3a6f9a"))
	k.box_ab(o + Vector3(0.4, 0, d - 1.2), o + Vector3(0.9, 0.9, d - 0.6), Color("#e2e6e8"))
	k.cyl(o + Vector3(0.65, 0.9, d - 0.9), 0.12, 0.35, Color("#c8e0f0"))
	# --- farmácia interna e posto de enfermagem ---
	var ph := o + Vector3(w - 5.8, 0, d - 1.0)
	k.box_ab(ph, ph + Vector3(5.2, 2.0, 0.5), Color("#e2e6e8"))
	for sh in 4:
		k.box_ab(ph + Vector3(0, 0.4 + sh * 0.42, -0.02), ph + Vector3(5.2, 0.43 + sh * 0.42, 0.0), steel)
		for bx in 12:
			k.box(ph + Vector3(0.25 + bx * 0.42, 0.55 + sh * 0.42, -0.08), Vector3(0.3, 0.2, 0.12), Color.from_hsv(fmod(bx * 0.17 + sh * 0.31, 1.0), 0.35, 0.92))
	k.box_ab(o + Vector3(w - 5.5, 0, d - 4.2), o + Vector3(w - 1.5, 1.0, d - 3.6), Color("#d8dcde"))
	k.box_ab(o + Vector3(w - 5.5, 1.0, d - 4.2), o + Vector3(w - 1.5, 1.04, d - 3.6), green.darkened(0.2))
	k.box_ab(o + Vector3(w - 3.8, 1.04, d - 4.1), o + Vector3(w - 3.3, 1.35, d - 4.03), Color("#202428"))
	# cadeira de rodas encostada
	var wc := o + Vector3(w - 1.2, 0, d - 6.0)
	for side in [-0.32, 0.32]:
		k.add("cyl", Transform3D(Basis(Vector3.FORWARD, PI / 2.0).scaled(Vector3(0.6, 0.04, 0.6)), wc + Vector3(side, 0.3, 0)), Color("#2a2a2a"))
	k.box(wc + Vector3(0, 0.48, 0), Vector3(0.55, 0.06, 0.5), Color("#3a4a5a"))
	k.box(wc + Vector3(0, 0.8, -0.24), Vector3(0.55, 0.6, 0.05), Color("#3a4a5a"))


# ---------- locais abertos ----------

func _praca(k, r: Rect2) -> void:
	var c := r.get_center()
	k.cat = "walk"
	k.box_ab(Vector3(r.position.x + 0.5, 0.17, r.position.y + 0.5), Vector3(r.end.x - 0.5, 0.2, r.end.y - 0.5), Color("#a39b89"))
	for i in 8:
		for j in 8:
			if (i + j) % 2 == 0:
				k.box_ab(Vector3(r.position.x + 1 + i * 3.5, 0.2, r.position.y + 1 + j * 3.5), Vector3(r.position.x + 2.75 + i * 3.5, 0.21, r.position.y + 2.75 + j * 3.5), Color("#958d7b"))
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var gc: Vector2 = c + corner * 9.0
		k.cat = "solid"
		k.box_ab(Vector3(gc.x - 4, 0.2, gc.y - 4), Vector3(gc.x + 4, 0.35, gc.y + 4), Color("#5a4632"))
		k.cat = "veg"
		k.box_ab(Vector3(gc.x - 3.8, 0.35, gc.y - 3.8), Vector3(gc.x + 3.8, 0.4, gc.y + 3.8), GRASS)
		k.cat = "solid"
		_tree(k, Vector3(gc.x, 0.4, gc.y), 1.25)
		_bench(k, Vector3(gc.x, 0.2, gc.y - corner.y * 5.0), 0.0 if corner.y > 0 else PI)
	k.cyl(Vector3(c.x, 0.2, c.y), 3.2, 0.6, Color("#c9c1ae"))
	k.cyl(Vector3(c.x, 0.2, c.y), 0.4, 2.2, Color("#c9c1ae"))
	k.sphere(Vector3(c.x, 2.4, c.y), Vector3(1.2, 0.5, 1.2), Color("#c9c1ae"))
	var water := Kit.new()
	water.cyl(Vector3(c.x, 0.5, c.y), 2.9, 0.15, Color.WHITE)
	_mesh(water, self, water_mat)
	# banca de jornal
	var bj := Vector3(r.end.x - 6.0, 0.2, r.end.y - 4.5)
	k.box_ab(bj, bj + Vector3(2.6, 2.3, 1.8), Color("#2f5a3e"))
	k.box_ab(bj + Vector3(-0.2, 2.3, -0.2), bj + Vector3(2.8, 2.45, 2.2), Color("#244a32"))
	k.box_ab(bj + Vector3(0.1, 0.6, 1.8), bj + Vector3(2.5, 2.0, 1.85), Color("#1d2630"))
	for mi2 in 10:
		k.box(bj + Vector3(0.3 + (mi2 % 5) * 0.48, 1.0 + int(mi2 / 5) * 0.55, 1.86), Vector3(0.38, 0.48, 0.02), Color.from_hsv(rng.randf(), 0.55, 0.85))
	# postes ornamentais ao longo dos caminhos
	for lp in [Vector2(-4.5, -12.0), Vector2(4.5, -12.0), Vector2(-4.5, 12.0), Vector2(4.5, 12.0), Vector2(-12.0, -4.5), Vector2(12.0, 4.5)]:
		var pp := Vector3(c.x + lp.x, 0.2, c.y + lp.y)
		k.cyl(pp, 0.08, 3.4, Color("#1f2224"))
		k.cyl(pp, 0.16, 0.5, Color("#1f2224"))
		k.sphere(pp + Vector3(0, 3.6, 0), Vector3(0.45, 0.55, 0.45), Color("#f0e2b8"))
		lamp_spots.append(pp + Vector3(0, 3.4, 0))
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


func _parque(k, r: Rect2) -> void:
	var c := r.get_center()
	k.cat = "veg"
	k.box_ab(Vector3(r.position.x + 0.5, 0.17, r.position.y + 0.5), Vector3(r.end.x - 0.5, 0.2, r.end.y - 0.5), GRASS)
	k.cat = "walk"
	k.box_ab(Vector3(c.x - 1.2, 0.2, r.position.y + 0.5), Vector3(c.x + 1.2, 0.22, r.end.y - 0.5), Color("#b49d76"))
	k.box_ab(Vector3(r.position.x + 0.5, 0.2, c.y - 1.2), Vector3(r.end.x - 0.5, 0.22, c.y + 1.2), Color("#b49d76"))
	k.cat = "solid"
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
	# parquinho
	var pg := Vector3(c.x - 8.0, 0.2, c.y + 7.0)
	k.box_ab(pg + Vector3(-3.2, 0, -3.0), pg + Vector3(3.2, 0.03, 3.0), Color("#c4a878"))
	for sx in [-1.6, 1.6]:
		k.add("box", Transform3D(Basis(Vector3.FORWARD, sx * 0.12).scaled(Vector3(0.1, 2.3, 0.1)), pg + Vector3(sx, 1.15, -1.5)), Color("#c03a2a"))
	k.box(pg + Vector3(0, 2.3, -1.5), Vector3(3.6, 0.1, 0.1), Color("#c03a2a"))
	for sw in [-0.7, 0.7]:
		k.box(pg + Vector3(sw, 1.4, -1.5), Vector3(0.03, 1.8, 0.03), Color("#3a3a3a"))
		k.box(pg + Vector3(sw, 0.5, -1.5), Vector3(0.5, 0.05, 0.25), Color("#2a5a8a"))
	k.box(pg + Vector3(1.5, 0.9, 1.4), Vector3(0.9, 1.8, 0.9), Color("#d8b030"))
	k.add("box", Transform3D(Basis(Vector3.RIGHT, 0.55).scaled(Vector3(0.6, 0.06, 2.4)), pg + Vector3(1.5, 0.95, 2.8)), Color("#2a8a5a"))
	# mesas de piquenique
	for ti in 2:
		var tp := Vector3(c.x - 9.0 + ti * 4.5, 0.2, c.y - 8.5)
		k.box(tp + Vector3(0, 0.72, 0), Vector3(1.8, 0.07, 0.8), Color("#7a5534"))
		for sz in [-0.65, 0.65]:
			k.box(tp + Vector3(0, 0.42, sz), Vector3(1.8, 0.06, 0.3), Color("#6a4a2e"))
		k.box(tp + Vector3(0, 0.36, 0), Vector3(1.5, 0.72, 0.1), Color("#5a3e26"))
	# deque de madeira no lago
	var dk := Vector3(c.x + 3.4, 0.2, c.y - 7.5)
	k.box_ab(dk + Vector3(0, 0, -0.9), dk + Vector3(3.2, 0.12, 0.9), Color("#7a5a3a"))
	for pi2 in 4:
		k.cyl(dk + Vector3(pi2 * 1.0, -0.2, 0.9), 0.06, 0.6, Color("#5a3e26"))
	k.cat = "veg"
	for i in 30:
		k.sphere(Vector3(rng.randf_range(r.position.x + 1, r.end.x - 1), 0.3, rng.randf_range(r.position.y + 1, r.end.y - 1)), Vector3(0.6, 0.35, 0.6), Color.from_hsv(rng.randf(), 0.5, 0.85) if rng.randf() < 0.3 else GRASS2)
	k.cat = "solid"


func _rodoviaria(k, r: Rect2) -> void:
	k.cat = "walk"
	k.box_ab(Vector3(r.position.x + 0.5, 0.17, r.position.y + 0.5), Vector3(r.end.x - 0.5, 0.2, r.end.y - 0.5), Color("#9c9890"))
	var plat := Rect2(r.position.x + 3, r.position.y + 4, r.size.x - 6, 9)
	k.box_ab(Vector3(plat.position.x, 0.2, plat.position.y), Vector3(plat.end.x, 0.5, plat.end.y), Color("#b8b2a4"))
	# borda amarela de segurança na plataforma
	k.box_ab(Vector3(plat.position.x, 0.5, plat.end.y - 0.35), Vector3(plat.end.x, 0.505, plat.end.y - 0.05), Color("#d8b13a"))
	k.cat = "solid"
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
		k.cat = "props"
		k.soft_shadow(Vector3(bx + 5.25, 0.2, bz), 6.0, 1.75, 0.45)
		# carroceria sobre a saia escura (a saia é um pouco maior: faces nunca coincidem, sem piscar)
		k.box_ab(Vector3(bx, 0.9, bz - 1.3), Vector3(bx + 10.5, 3.4, bz + 1.3), Color("#e5e2d8") if bi == 0 else Color("#2d6a9f"))
		k.box_ab(Vector3(bx - 0.02, 0.5, bz - 1.32), Vector3(bx + 10.52, 0.9, bz + 1.32), Color("#3b3b3b"))
		# janelas dos dois lados e para-brisa
		for wz in [bz + 1.3, bz - 1.34]:
			k.box_ab(Vector3(bx + 0.4, 1.8, wz), Vector3(bx + 10.1, 2.7, wz + 0.04), Color("#2a3440"))
		k.box_ab(Vector3(bx + 10.5, 1.4, bz - 1.1), Vector3(bx + 10.54, 2.9, bz + 1.1), Color("#2a3440"))
		k.box_ab(Vector3(bx + 10.5, 0.95, bz - 1.0), Vector3(bx + 10.55, 1.15, bz - 0.6), Color("#f2eccc"))
		k.box_ab(Vector3(bx + 10.5, 0.95, bz + 0.6), Vector3(bx + 10.55, 1.15, bz + 1.0), Color("#f2eccc"))
		for wx in [1.8, 8.5]:
			k.add("cyl", Transform3D(Basis(Vector3.RIGHT, PI / 2.0).scaled(Vector3(1.0, 2.7, 1.0)), Vector3(bx + wx, 0.6, bz)), Color("#151515"))
		k.cat = "solid"
	k.box_ab(Vector3(r.position.x + 1, 0.2, r.position.y + 0.8), Vector3(r.end.x - 1, 3.2, r.position.y + 3.5), Color("#c4b59a"))
	# guichês e painel de partidas
	for gi in 3:
		var gx := r.position.x + 3.0 + gi * 3.0
		k.box_ab(Vector3(gx, 0.2, r.position.y + 3.5), Vector3(gx + 2.4, 2.4, r.position.y + 3.6), Color("#2a5a8a"))
		k.box_ab(Vector3(gx + 0.3, 1.1, r.position.y + 3.6), Vector3(gx + 2.1, 2.0, r.position.y + 3.65), Color("#1d2630"))
	var pb := Kit.new()
	pb.box_ab(Vector3(r.end.x - 9.0, 2.0, r.position.y + 3.55), Vector3(r.end.x - 3.0, 3.0, r.position.y + 3.62), Color.WHITE)
	_mesh(pb, self, lit_mat)
	# baias numeradas e malas
	k.cat = "walk"
	for bi in 4:
		var bx := plat.position.x + 1.0 + bi * 6.0
		k.box_ab(Vector3(bx, 0.2, plat.end.y + 0.6), Vector3(bx + 0.12, 0.215, plat.end.y + 8.0), Color("#e0c040"))
	k.cat = "solid"
	for li in 5:
		k.box(Vector3(plat.position.x + 4.0 + li * 3.0, 0.75, plat.position.y + 6.5), Vector3(0.5, 0.5, 0.3), [Color("#3a3a3a"), Color("#7a2a2a"), Color("#2a4a6a")][li % 3])
	# ponto de táxi
	for ti in 3:
		_car(k, Vector3(r.end.x - 2.2, 0.2, r.position.y + 7.0 + ti * 5.0), 0.0, Color("#e8c21c"))
	var rs := Label3D.new()
	rs.text = "RODOVIÁRIA"
	rs.font_size = 96
	rs.pixel_size = 0.008
	rs.outline_size = 14
	rs.modulate = Color("#f6ecd6")
	rs.outline_modulate = Color("#1f2f3f")
	rs.position = Vector3(plat.get_center().x, 5.2, plat.end.y + 0.55)
	add_child(rs)


func _beco(k, r: Rect2) -> void:
	k.cat = "asphalt"
	k.box_ab(Vector3(r.position.x + 0.5, 0.17, r.position.y + 0.5), Vector3(r.end.x - 0.5, 0.19, r.end.y - 0.5), Color("#4b4740"))
	k.cat = "solid"
	_simple_building(Rect2(r.position.x + 1, r.position.y + 1, 11, r.size.y - 3), 9.0, Color("#7a5a4a"), Color("#3e3e40"), false, 3, "old", 0.8)
	_simple_building(Rect2(r.end.x - 12, r.position.y + 1, 11, r.size.y - 3), 9.0, Color("#6a6f6a"), Color("#3e3e40"), false, 3, "old", 0.75)
	var ax := r.get_center().x
	# fios atravessando o beco, canos e caixas de ar-condicionado
	for wi in 6:
		var wz := r.position.y + 3.0 + wi * 4.2
		_wire(k, Vector3(r.position.x + 12.0, 6.5 + rng.randf() * 1.5, wz), Vector3(r.end.x - 12.0, 6.5 + rng.randf() * 1.5, wz + rng.randf_range(-1.0, 1.0)))
	for side in [r.position.x + 12.1, r.end.x - 12.1]:
		var sxx: float = side
		k.box(Vector3(sxx, 4.5, r.position.y + 6.0), Vector3(0.12, 9.0, 0.12), Color("#5a5a54"))
		for ai in 3:
			k.box(Vector3(sxx + (0.3 if sxx < ax else -0.3), 3.0 + ai * 2.6, r.position.y + 9.0 + ai * 5.0), Vector3(0.55, 0.45, 0.75), Color("#bfc2c2"))
	# luminária de parede, única luz do beco
	var wl := Kit.new()
	wl.box(Vector3(r.end.x - 12.25, 3.4, r.get_center().y), Vector3(0.18, 0.25, 0.4), Color.WHITE)
	_mesh(wl, self, lit_mat)
	lamp_spots.append(Vector3(r.end.x - 12.8, 3.2, r.get_center().y))
	# caixotes e um colchão velho
	for ci in 4:
		k.box(Vector3(ax + 3.0, 0.4 + (ci % 2) * 0.5, r.end.y - 6.0 - int(ci / 2) * 0.6), Vector3(0.6, 0.48, 0.55), Color("#8a6a40"), rng.randf() * 0.3)
	k.box(Vector3(ax - 3.0, 0.3, r.end.y - 9.0), Vector3(1.4, 0.22, 2.0), Color("#a89a7a"), 0.3)
	for i in 3:
		var p := Vector3(ax - 2.5 + i * 2.2, 0.19, r.position.y + 5 + i * 6)
		k.box_ab(p, p + Vector3(1.8, 1.3, 1.1), Color("#2f5a3a") if i != 1 else Color("#5a3a2a"))
		k.box_ab(p + Vector3(-0.05, 1.3, -0.05), p + Vector3(1.85, 1.38, 1.15), Color("#1f1f1f"))
	for i in 14:
		k.sphere(Vector3(ax + rng.randf_range(-3.5, 3.5), 0.4, rng.randf_range(r.position.y + 2, r.end.y - 3)), Vector3(0.7, 0.55, 0.6), Color("#1c1c1c"))
	for i in 5:
		k.box(Vector3(r.position.x + 12.05, rng.randf_range(1.0, 2.5), rng.randf_range(r.position.y + 3, r.end.y - 4)), Vector3(0.05, rng.randf_range(0.5, 1.2), rng.randf_range(1.0, 3.0)), Color.from_hsv(rng.randf(), 0.7, 0.8))


func _acacias(k, r: Rect2) -> void:
	k.cat = "veg"
	k.box_ab(Vector3(r.position.x + 1, 0.17, r.position.y + 1), Vector3(r.end.x - 1, 0.19, r.end.y - 1), GRASS)
	k.cat = "solid"
	for i in 3:
		var cell := Rect2(r.position.x + 1 + i * 9.3, r.position.y + 1, 9.3, r.size.y - 2)
		var cols := _house_colors()
		_simple_building(Rect2(cell.position.x + 0.8, cell.position.y + 4, 7.6, 9), 3.0, cols[0], cols[1], true)
		k.box_ab(Vector3(cell.position.x + 0.2, 0.17, cell.end.y - 0.5), Vector3(cell.position.x + 3.6, 1.8 if i == 0 else 1.0, cell.end.y - 0.2), cols[0].darkened(0.2))
		k.box_ab(Vector3(cell.position.x + 5.6, 0.17, cell.end.y - 0.5), Vector3(cell.end.x - 0.2, 1.8 if i == 0 else 1.0, cell.end.y - 0.2), cols[0].darkened(0.2))
		k.box_ab(Vector3(cell.position.x + 3.6, 0.17, cell.end.y - 0.45), Vector3(cell.position.x + 5.6, 1.6, cell.end.y - 0.3), Color("#2b2b2b"))
		_tree(k, Vector3(cell.get_center().x, 0.19, cell.end.y - 4.5), 0.8)


# ---------- estado dinâmico ----------

const SHOPS := ["Padaria Pão Quente", "Farmácia Popular", "Barbearia do Léo", "Sapataria Silva", "Armarinho Dona Rita", "Mecânica Bom Torque", "Açougue Central", "Papelaria Estudante", "Loja de Roupas Modas", "Lotérica", "Floricultura Jardim", "Material de Construção"]


func _comercio(k, r: Rect2) -> void:
	k.cat = "walk"
	k.box_ab(Vector3(r.position.x + 0.2, 0.17, r.position.y + 0.2), Vector3(r.end.x - 0.2, 0.19, r.end.y - 0.2), SIDEWALK.darkened(0.06))
	k.cat = "solid"
	var n := rng.randi_range(3, 4)
	var wdt := (r.size.x - 2.0) / n
	var collapse := wear_city > 0.6
	var depth := 11.0
	var names: Array = SHOPS.duplicate()
	names.shuffle()
	for i in n:
		var rect := Rect2(r.position.x + 1.0 + i * wdt, r.end.y - 2.2 - depth, wdt - 0.2, depth)
		var floors := rng.randi_range(1, 2)
		var wallc := _jit_c(Art.pick("comm_walls", rng))
		var h := 3.6 if floors == 1 else 6.4
		var wear := Art.wear(rng)
		_simple_building(rect, h, wallc, Color("#55575a"), false, floors, "shop", wear)
		var cx := rect.get_center().x
		var front := rect.end.y
		var ac: Color = Art.pick("awnings", rng)
		var shop_name := str(names[i % names.size()])
		# letreiro pintado sobre a porta e toldo listrado
		k.box_ab(Vector3(rect.position.x + 0.3, 0.17 + 2.85, front), Vector3(rect.end.x - 0.3, 0.17 + 3.5, front + 0.1), ac.darkened(0.25))
		k.box_ab(Vector3(rect.position.x + 0.2, 0.17 + 2.55, front), Vector3(rect.end.x - 0.2, 0.17 + 2.68, front + 1.3), ac)
		for st in int((rect.size.x - 0.6) / 0.5):
			k.box_ab(Vector3(rect.position.x + 0.3 + st * 0.5, 0.17 + 2.4, front + 1.24), Vector3(rect.position.x + 0.55 + st * 0.5, 0.17 + 2.55, front + 1.3), ac.lightened(0.18) if st % 2 == 0 else ac)
		# porta de enrolar: fechada, aberta (loja acesa) ou meia
		var state := rng.randf()
		if shop_name.begins_with("Mecânica"):
			state = 0.9
		if collapse:
			state = 0.1 if rng.randf() < 0.7 else 0.95
		var door_w := rect.size.x - 1.0
		var open_h := 0.0
		if state > 0.4:
			open_h = 2.2 if state > 0.65 else 1.0
		var shutter_c := Color("#8a9094") if not collapse else Color("#6a6a64")
		var closed_h := 2.2 - open_h
		if closed_h > 0.05:
			k.box_ab(Vector3(rect.position.x + 0.5, 0.17 + open_h, front + 0.02), Vector3(rect.end.x - 0.5, 0.17 + 2.2, front + 0.07), shutter_c)
			for sl in int(closed_h / 0.2):
				k.box_ab(Vector3(rect.position.x + 0.5, 0.17 + open_h + sl * 0.2, front + 0.07), Vector3(rect.end.x - 0.5, 0.17 + open_h + sl * 0.2 + 0.03, front + 0.09), shutter_c.darkened(0.15))
			if wear > 0.45 or collapse:
				for gi in rng.randi_range(1, 3):
					k.box(Vector3(rng.randf_range(rect.position.x + 1.0, rect.end.x - 1.0), 0.17 + open_h + rng.randf_range(0.2, closed_h - 0.2), front + 0.095), Vector3(rng.randf_range(0.5, 1.4), rng.randf_range(0.3, 0.7), 0.01), Color.from_hsv(rng.randf(), 0.6, 0.75))
		if open_h > 0.05:
			# interior aceso visto pela porta: luz quente, prateleiras e mercadoria
			# (o painel fica rente à fachada; antes ficava dentro da parede e não aparecia)
			var lk := Kit.new()
			lk.vary_lit = true
			var inner_c := Color("#b8a888") if shop_name.begins_with("Mecânica") else Color.WHITE
			lk.box_ab(Vector3(rect.position.x + 0.5, 0.17, front + 0.012), Vector3(rect.end.x - 0.5, 0.17 + open_h, front + 0.022), inner_c)
			_mesh(lk, self, lit_mat)
			# prateleiras e balcão vistos em silhueta contra a luz
			for si in 3:
				k.box_ab(Vector3(rect.position.x + 0.7, 0.17 + 0.3 + si * 0.5, front + 0.024), Vector3(rect.end.x - 0.7, 0.17 + 0.34 + si * 0.5, front + 0.03), Color("#3a3026"))
			k.box_ab(Vector3(rect.position.x + 0.8, 0.17, front + 0.024), Vector3(rect.position.x + 2.2, 0.17 + 1.0, front + 0.034), Color("#4a3a2c"))
			if rng.randf() < 0.6:
				# mesinhas de plástico na calçada
				for ti in 2:
					var tp := Vector3(rect.position.x + 1.2 + ti * 1.6, 0.17, front + 0.9)
					var tc := Color("#e0b030") if rng.randf() < 0.6 else Color("#c03a2a")
					k.cyl(tp, 0.38, 0.72, tc.darkened(0.1))
					k.cyl(tp + Vector3(0, 0.68, 0), 0.42, 0.05, tc)
					for ci in 2:
						var cp := tp + Vector3((ci - 0.5) * 0.9, 0, 0.0)
						k.box(cp + Vector3(0, 0.42, 0), Vector3(0.42, 0.05, 0.42), tc)
						k.box(cp + Vector3(0, 0.66, -0.19 if ci == 0 else 0.19), Vector3(0.42, 0.45, 0.04), tc)
		if collapse and rng.randf() < 0.5:
			for bi in 3:
				k.add("box", Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.2, 0.2)).scaled(Vector3(door_w * 0.9, 0.22, 0.05)), Vector3(cx, 0.17 + 0.5 + bi * 0.6, front + 0.12)), Color("#6a5538"))
		_shop_identity(k, rect, front, shop_name)
		var sign := Label3D.new()
		sign.text = shop_name.to_upper()
		sign.font_size = 52
		sign.pixel_size = 0.0055
		sign.outline_size = 8
		sign.modulate = Color("#f6ecd6") if not collapse else Color("#c9bfa8")
		sign.outline_modulate = ac.darkened(0.6)
		sign.position = Vector3(cx, 0.17 + 3.17, front + 0.13)
		add_child(sign)
	for i in 3:
		if rng.randf() < (0.4 if collapse else 0.85):
			_car(k, Vector3(r.position.x + 6 + i * 8.5, 0.17, r.end.y - 0.9), 0.0, _car_color())
	# moto estacionada
	if rng.randf() < 0.6:
		var mp := Vector3(r.end.x - 2.0, 0.17, r.end.y - 0.8)
		for wz in [-0.6, 0.6]:
			k.add("cyl", Transform3D(Basis(Vector3.FORWARD, PI / 2.0).scaled(Vector3(0.55, 0.12, 0.55)), mp + Vector3(0, 0.28, wz)), Color("#1a1a1a"))
		k.box(mp + Vector3(0, 0.55, 0), Vector3(0.3, 0.3, 1.1), Color("#8a1f1f") if rng.randf() < 0.5 else Color("#2a2a2a"))
		k.box(mp + Vector3(0, 0.95, 0.45), Vector3(0.7, 0.05, 0.05), Color("#2a2a2a"))


# Cada ramo conta o que é pela fachada e pela calçada, sem depender só do letreiro.
func _shop_identity(k, rect: Rect2, front: float, name: String) -> void:
	var y0 := 0.17
	var cx := rect.get_center().x
	k.cat = "props"
	if name.begins_with("Mecânica"):
		# pneus empilhados, caixa de ferramentas e mancha de óleo na calçada
		for st in 2:
			var tp := Vector3(rect.position.x + 0.9 + st * 0.9, y0, front + 0.7)
			for ti in rng.randi_range(3, 5):
				k.cyl(tp + Vector3(0, ti * 0.22, 0), 0.34, 0.2, Color("#1b1b1c"))
			k.soft_shadow(tp, 0.5, 0.5, 0.35)
		k.box(Vector3(rect.end.x - 1.2, y0 + 0.2, front + 0.6), Vector3(0.6, 0.4, 0.3), Color("#b02a22"))
		k.cat = "walk"
		k.box(Vector3(cx + 0.6, y0 + 0.004, front + 0.9), Vector3(1.4, 0.006, 0.9), Color("#26262a"), rng.randf() * PI)
	elif name.begins_with("Farmácia"):
		# faixa branca e cruz verde em placa saltada
		k.box_ab(Vector3(rect.position.x, y0 + 2.25, front), Vector3(rect.end.x, y0 + 2.4, front + 0.05), Color("#e8ece8"))
		var sp := Vector3(rect.end.x - 0.4, y0 + 3.2, front + 0.45)
		k.box(sp, Vector3(0.06, 0.8, 0.8), Color("#f2f2f2"))
		k.box(sp, Vector3(0.1, 0.62, 0.2), Color("#1f9a4a"))
		k.box(sp, Vector3(0.1, 0.2, 0.62), Color("#1f9a4a"))
		k.box(sp + Vector3(0, 0, -0.45), Vector3(0.05, 0.05, 0.12), Color("#5a5a5a"))
	elif name.begins_with("Padaria"):
		# cestos de pão na porta e cavalete
		for bi in 2:
			var bp := Vector3(rect.position.x + 1.0 + bi * 1.0, y0, front + 0.55)
			k.box(bp + Vector3(0, 0.4, 0), Vector3(0.7, 0.8, 0.45), Color("#8a5a32"))
			for pi in 5:
				k.sphere(bp + Vector3(-0.22 + pi * 0.11, 0.86, rng.randf_range(-0.1, 0.1)), Vector3(0.16, 0.1, 0.12), Color("#c9883a").lightened(rng.randf() * 0.15))
		k.box(Vector3(rect.end.x - 1.0, y0 + 0.5, front + 0.7), Vector3(0.55, 1.0, 0.05), Color("#2a2a2a"), 0.15)
	elif name.begins_with("Barbearia"):
		# poste listrado de barbeiro
		var bpz := Vector3(rect.position.x + 0.45, y0 + 1.2, front + 0.18)
		for si in 8:
			k.cyl(bpz + Vector3(0, si * 0.12, 0), 0.08, 0.12, [Color("#c0302a"), Color("#f2f2f2"), Color("#2a4a9a"), Color("#f2f2f2")][si % 4])
		k.sphere(bpz + Vector3(0, 1.0, 0), Vector3(0.18, 0.18, 0.18), Color("#e8e2d0"))
	elif name.begins_with("Açougue"):
		# azulejo branco na base e faixa vermelha
		var tx := rect.position.x + 0.5
		var alt := false
		while tx < rect.end.x - 0.5:
			k.box_ab(Vector3(tx, y0 + 0.4, front + 0.01), Vector3(tx + 0.28, y0 + 0.68, front + 0.035), Color("#eef0ee") if alt else Color("#dfe3e0"))
			alt = not alt
			tx += 0.3
		k.box_ab(Vector3(rect.position.x, y0 + 2.25, front), Vector3(rect.end.x, y0 + 2.4, front + 0.05), Color("#a02a24"))
	elif name.begins_with("Lotérica"):
		k.box_ab(Vector3(rect.position.x, y0 + 2.2, front), Vector3(rect.end.x, y0 + 2.42, front + 0.05), Color("#1f4f9a"))
		k.box_ab(Vector3(rect.position.x, y0 + 2.14, front), Vector3(rect.end.x, y0 + 2.2, front + 0.06), Color("#e8c21c"))
	elif name.begins_with("Material"):
		# sacos de cimento e tijolos empilhados na calçada
		for si in 6:
			k.box(Vector3(rect.position.x + 0.8 + (si % 3) * 0.62, y0 + 0.1 + int(si / 3) * 0.17, front + 0.7), Vector3(0.58, 0.16, 0.38), Color("#bdb7aa"))
		for bi in 3:
			k.box(Vector3(rect.end.x - 1.2, y0 + 0.17 + bi * 0.28, front + 0.7), Vector3(0.9, 0.26, 0.5), Color("#a84a32").darkened(rng.randf() * 0.1))
		k.soft_shadow(Vector3(rect.position.x + 1.4, y0, front + 0.7), 1.2, 0.45, 0.3)
	elif name.begins_with("Floricultura"):
		for fi in 5:
			var fp := Vector3(rect.position.x + 0.7 + fi * 0.55, y0, front + 0.55)
			k.cat = "props"
			k.cyl(fp, 0.17, 0.35, Color("#3a5a6a"))
			k.cat = "veg"
			k.sphere(fp + Vector3(0, 0.48, 0), Vector3(0.38, 0.32, 0.38), Color.from_hsv(rng.randf(), 0.55, 0.9))
	elif name.begins_with("Loja de Roupas"):
		# arara de roupas na porta
		var ap := Vector3(rect.end.x - 1.5, y0, front + 0.6)
		k.box(ap + Vector3(0, 1.4, 0), Vector3(1.2, 0.03, 0.03), Color("#8a8a8a"))
		for ci in 6:
			k.box(ap + Vector3(-0.5 + ci * 0.2, 1.0, 0), Vector3(0.16, 0.75, 0.35), Color.from_hsv(rng.randf(), 0.5, 0.75))
		for sx in [-0.6, 0.6]:
			k.box(ap + Vector3(sx, 0.7, 0), Vector3(0.03, 1.4, 0.03), Color("#8a8a8a"))
	k.cat = "solid"


func _jit_c(c: Color) -> Color:
	return Color(clampf(c.r + rng.randf_range(-0.04, 0.04), 0, 1), clampf(c.g + rng.randf_range(-0.04, 0.04), 0, 1), clampf(c.b + rng.randf_range(-0.04, 0.04), 0, 1))


func set_door(id: String, locked: bool) -> void:
	if not loc_info.has(id):
		return
	var info: Dictionary = loc_info[id]
	(info["door"] as CollisionShape3D).set_deferred("disabled", not locked)
	(info["door_mesh"] as Node3D).visible = locked
	if info.get("door_open") != null:
		(info["door_open"] as Node3D).visible = not locked


func set_interior_light(id: String, on: bool) -> void:
	if not loc_info.has(id):
		return
	var info: Dictionary = loc_info[id]
	var l = info.get("light")
	if l == null and info.get("structure") != null:
		l = (info["structure"] as Dictionary).get("light")
	if l != null:
		(l as OmniLight3D).visible = on


# Janelas acesas de uma casa (alguém em casa à noite).
func set_house_lit(id: String, on: bool) -> void:
	if loc_info.has(id) and loc_info[id].get("structure") != null:
		var s: Dictionary = loc_info[id]["structure"]
		if s.has("lit"):
			(s["lit"] as Node3D).visible = on


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
