extends RefCounted

# Junta muitas formas simples (caixas, cilindros, esferas) numa só malha com cor por vértice.
# Assim um quarteirão inteiro vira uma única chamada de desenho.

var st := SurfaceTool.new()
var count := 0
# categoria de superfície (usada pelo ChunkKit para escolher o material: asfalto, calçada, vegetação...)
var cat := ""
# sombras de contato suaves sob objetos (outra malha, transparente)
var shadows = null
# variação por janela: caixas brancas viram vidro ou luz de cores diferentes
var vary_glass := false
var vary_lit := false
var _vr := RandomNumberGenerator.new()
static var _seq := 0

const GLASS_TONES := ["#4c5a67", "#56626c", "#43505b", "#5d6a73", "#4a5560", "#525e66"]
const GLASS_COVER := ["#9c8c74", "#b8b0a0", "#8a7a6a", "#a39a88"]
const LIT_TONES := ["#ffd89a", "#ffcf86", "#f7d4a8", "#ffe0b4", "#ffc373", "#f0c890"]

static var _cache: Dictionary = {}
# Telhados (duas e quatro águas) ganham superfície própria: telha molha e brilha diferente da parede.
static var roof_material: Material = null
static var shadow_material_ref: Material = null
var roofs = null
var is_roof := false


static func cleanup() -> void:
	roof_material = null
	shadow_material_ref = null
	_cache.clear()


func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# semente fixa por ordem de criação: a cidade sai igual a cada partida, mas cada prédio varia
	_seq += 1
	_vr.seed = hash(_seq * 7919)


static func _arrays(kind: String) -> Array:
	if _cache.has(kind):
		return _cache[kind]
	var m: PrimitiveMesh
	match kind:
		"box":
			m = BoxMesh.new()
		"cyl":
			var c := CylinderMesh.new()
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 1.0
			c.radial_segments = 10
			c.rings = 1
			m = c
		"cone":
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = 0.5
			c.height = 1.0
			c.radial_segments = 8
			c.rings = 1
			m = c
		"sphere":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			s.radial_segments = 8
			s.rings = 5
			m = s
		"prism":
			m = PrismMesh.new()
		"wedge":
			# rampa: alta em -X, baixa em +X
			var w := PrismMesh.new()
			w.left_to_right = 0.0
			m = w
	var a := m.get_mesh_arrays()
	_cache[kind] = a
	return a


func _tone(color: Color) -> Color:
	if color != Color.WHITE:
		return color
	if vary_glass:
		var r := _vr.randf()
		if r < 0.16:
			return Color(GLASS_COVER[_vr.randi() % GLASS_COVER.size()])
		return Color(GLASS_TONES[_vr.randi() % GLASS_TONES.size()])
	if vary_lit:
		if _vr.randf() < 0.07:
			return Color("#9fbcf0").darkened(_vr.randf() * 0.2)
		return Color(LIT_TONES[_vr.randi() % LIT_TONES.size()]).darkened(_vr.randf() * 0.25)
	return color


# Oclusão de ambiente assada na cor (o renderizador de compatibilidade não tem SSAO):
# as laterais escurecem perto do chão e clareiam para cima, faces de baixo ficam mais escuras,
# topos e chão continuam com luz cheia. Assenta prédios, carros, postes e móveis no chão.
const AO_MIN := 0.6
const AO_H := 1.6
static var ao_enabled := true


static func _ao_k(y: float) -> float:
	var k := clampf((y - 0.12) / AO_H, 0.0, 1.0)
	return lerpf(AO_MIN, 1.0, k * k * (3.0 - 2.0 * k))


func add(kind: String, xf: Transform3D, color: Color) -> void:
	color = _tone(color)
	var a: Array = _arrays(kind)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var nb := xf.basis.inverse().transposed()
	var shade := ao_enabled and not vary_glass and not vary_lit and not is_roof
	if not shade:
		st.set_color(color)
		if idx.is_empty():
			for i in verts.size():
				st.set_normal((nb * norms[i]).normalized())
				st.add_vertex(xf * verts[i])
		else:
			for i in idx:
				st.set_normal((nb * norms[i]).normalized())
				st.add_vertex(xf * verts[i])
		count += 1
		return
	# cor da metade de baixo e de cima da peça (calculada uma vez, não por vértice)
	var fb := _ao_k((xf * Vector3(0, -0.5, 0)).y)
	var ft := _ao_k((xf * Vector3(0, 0.5, 0)).y)
	var c_bot := Color(color.r * fb, color.g * fb, color.b * fb, color.a)
	var c_top := Color(color.r * ft, color.g * ft, color.b * ft, color.a)
	var c_under := Color(color.r * fb * 0.82, color.g * fb * 0.82, color.b * fb * 0.86, color.a)
	var n := verts.size() if idx.is_empty() else idx.size()
	for j in n:
		var i: int = j if idx.is_empty() else idx[j]
		var wn := (nb * norms[i]).normalized()
		st.set_normal(wn)
		if wn.y > 0.6:
			st.set_color(color)
		elif wn.y < -0.6:
			st.set_color(c_under)
		else:
			st.set_color(c_top if verts[i].y > 0.0 else c_bot)
		st.add_vertex(xf * verts[i])
	count += 1


func box(center: Vector3, size: Vector3, color: Color, rot_y: float = 0.0) -> void:
	add("box", Transform3D(Basis(Vector3.UP, rot_y).scaled(size), center), color)


# Caixa definida pelos cantos (mais cômodo para paredes e pisos).
func box_ab(a: Vector3, b: Vector3, color: Color) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var size := hi - lo
	if size.x <= 0.001 or size.y <= 0.001 or size.z <= 0.001:
		return
	add("box", Transform3D(Basis.from_scale(size), (lo + hi) / 2.0), color)


func cyl(base: Vector3, radius: float, height: float, color: Color) -> void:
	add("cyl", Transform3D(Basis.from_scale(Vector3(radius * 2.0, height, radius * 2.0)), base + Vector3(0, height / 2.0, 0)), color)


func cone(base: Vector3, radius: float, height: float, color: Color) -> void:
	add("cone", Transform3D(Basis.from_scale(Vector3(radius * 2.0, height, radius * 2.0)), base + Vector3(0, height / 2.0, 0)), color)


func sphere(center: Vector3, size: Vector3, color: Color) -> void:
	add("sphere", Transform3D(Basis.from_scale(size), center), color)


# Telhado de duas águas; a cumeeira corre ao longo de X (ridge_x) ou de Z.
func _roof_kit():
	if roof_material == null or is_roof:
		return self
	if roofs == null:
		roofs = get_script().new()
		roofs.is_roof = true
	return roofs


func gable(center: Vector3, size: Vector3, color: Color, ridge_x: bool = true) -> void:
	var rk = _roof_kit()
	if rk != self:
		rk.gable(center, size, color, ridge_x)
		return
	var b := Basis.from_scale(size)
	if ridge_x:
		b = Basis(Vector3.UP, PI / 2.0) * Basis.from_scale(Vector3(size.z, size.y, size.x))
	add("prism", Transform3D(b, center), color)


var _tri_center := Vector3.INF


# Triângulo solto. Se houver um centro de referência, orienta a face para fora dele
# (Godot desenha a face da frente no sentido horário) e põe a normal para fora.
func tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var n := (b - a).cross(c - a)
	if _tri_center != Vector3.INF:
		var centroid := (a + b + c) / 3.0
		if n.dot(centroid - _tri_center) > 0.0:
			var tmp := b
			b = c
			c = tmp
			n = (b - a).cross(c - a)
		n = -n
	n = n.normalized()
	st.set_color(color)
	for v in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)
	count += 1


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	tri(a, b, c, color)
	tri(a, c, d, color)


# Telhado de quatro águas sobre um retângulo (centro na base). A cumeeira corre ao longo do lado maior.
func hip(center: Vector3, w: float, h: float, d: float, color: Color) -> void:
	var rk = _roof_kit()
	if rk != self:
		rk.hip(center, w, h, d, color)
		return
	var x0 := center.x - w / 2.0
	var x1 := center.x + w / 2.0
	var z0 := center.z - d / 2.0
	var z1 := center.z + d / 2.0
	var y0 := center.y
	var y1 := center.y + h
	var a := Vector3(x0, y0, z0)
	var b := Vector3(x1, y0, z0)
	var c := Vector3(x1, y0, z1)
	var e := Vector3(x0, y0, z1)
	var r0: Vector3
	var r1: Vector3
	_tri_center = Vector3(center.x, y0 - 0.5, center.z)
	if w >= d:
		var inset := d / 2.0
		r0 = Vector3(x0 + inset, y1, center.z)
		r1 = Vector3(x1 - inset, y1, center.z)
		quad(a, r0, r1, b, color.lightened(0.04))
		quad(c, r1, r0, e, color.darkened(0.06))
		tri(e, r0, a, color.darkened(0.12))
		tri(b, r1, c, color.darkened(0.12))
	else:
		var inset2 := w / 2.0
		r0 = Vector3(center.x, y1, z0 + inset2)
		r1 = Vector3(center.x, y1, z1 - inset2)
		quad(e, r1, r0, a, color.darkened(0.06))
		quad(b, r0, r1, c, color.lightened(0.04))
		tri(a, r0, b, color.darkened(0.12))
		tri(c, r1, e, color.darkened(0.12))
	_tri_center = Vector3.INF


# Disco deitado no chão com borda suave (centro denso, borda transparente).
# wobble deixa o contorno irregular (poças); inner/mid controlam o tamanho do miolo e a opacidade do anel.
func disc(c: Vector3, rx: float, rz: float, col: Color, rot: float = 0.0, segs: int = 14, wobble: float = 0.0, inner_f: float = 0.55, mid_f: float = 0.55) -> void:
	var edge := Color(col.r, col.g, col.b, 0.0)
	var mid := Color(col.r, col.g, col.b, col.a * mid_f)
	var b := Basis(Vector3.UP, rot)
	var inner: Array = []
	var outer: Array = []
	var ph := Vector3(_vr.randf() * TAU, _vr.randf() * TAU, _vr.randf() * TAU)
	for i in segs:
		var a := TAU * i / segs
		var f := 1.0
		if wobble > 0.0:
			f += wobble * (0.5 * sin(2.0 * a + ph.x) + 0.3 * sin(3.0 * a + ph.y) + 0.2 * sin(5.0 * a + ph.z))
		var d := Vector3(cos(a), 0, sin(a)) * f
		inner.append(c + b * Vector3(d.x * rx * inner_f, 0, d.z * rz * inner_f))
		outer.append(c + b * Vector3(d.x * rx, 0, d.z * rz))
	# sentido horário visto de cima = face da frente
	st.set_normal(Vector3.UP)
	for i in segs:
		var j := (i + 1) % segs
		# miolo
		st.set_color(col)
		st.add_vertex(c)
		st.set_color(mid)
		st.add_vertex(inner[i])
		st.add_vertex(inner[j])
		# anel que esmaece
		st.add_vertex(inner[i])
		st.set_color(edge)
		st.add_vertex(outer[i])
		st.add_vertex(outer[j])
		st.set_color(mid)
		st.add_vertex(inner[i])
		st.set_color(edge)
		st.add_vertex(outer[j])
		st.set_color(mid)
		st.add_vertex(inner[j])
	count += 1


# Sombra de contato: deixa carros, árvores, bancos e postes assentados no chão.
func soft_shadow(c: Vector3, rx: float, rz: float, alpha: float = 0.34, rot: float = 0.0, inner_f: float = 0.55, mid_f: float = 0.55) -> void:
	if shadows == null:
		shadows = get_script().new()
	shadows.disc(Vector3(c.x, c.y + 0.014, c.z), rx, rz, Color(0.03, 0.03, 0.05, alpha), rot, 14, 0.0, inner_f, mid_f)


# Monta a malha. Telhados e sombras de contato entram como superfícies extras da mesma malha.
func commit(material: Material, into: ArrayMesh = null) -> ArrayMesh:
	var mesh := into
	if count > 0:
		st.set_material(material)
		mesh = st.commit(mesh)
	if roofs != null and roofs.count > 0:
		mesh = roofs.commit(roof_material, mesh)
	return mesh


# Sombras de contato em malha separada: quem monta a cena põe essa malha sem projeção de sombra
# (senão o sol desenharia manchas transparentes e pesaria à toa).
func shadow_mesh() -> ArrayMesh:
	if shadows == null or shadows.count == 0 or shadow_material_ref == null:
		return null
	return shadows.commit(shadow_material_ref)


# Material pintado por vértice, fosco: sem metal e com brilho especular baixo (nada de plástico).
static func vertex_material(rough: float = 0.9, spec: float = 0.25) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = 0.0
	m.metallic_specular = spec
	return m


# Sombra de contato: sem luz, transparente, não projeta sombra.
static func shadow_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.render_priority = -1
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
