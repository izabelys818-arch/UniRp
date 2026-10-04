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
