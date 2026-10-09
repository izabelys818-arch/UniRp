extends RefCounted

# Junta muitas formas simples (caixas, cilindros, esferas) numa só malha com cor por vértice.
# Assim um quarteirão inteiro vira uma única chamada de desenho.

var st := SurfaceTool.new()
var count := 0

static var _cache: Dictionary = {}


func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


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
	var a := m.get_mesh_arrays()
	_cache[kind] = a
	return a


func add(kind: String, xf: Transform3D, color: Color) -> void:
	var a: Array = _arrays(kind)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var nb := xf.basis.inverse().transposed()
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
func gable(center: Vector3, size: Vector3, color: Color, ridge_x: bool = true) -> void:
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


func commit(material: Material) -> ArrayMesh:
	if count == 0:
		return null
	st.set_material(material)
	return st.commit()


static func vertex_material(rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	return m
