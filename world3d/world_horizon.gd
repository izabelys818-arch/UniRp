extends Node3D

const Kit = preload("res://world3d/mesh_kit.gd")
const Layout = preload("res://world3d/city_layout.gd")
const Surfaces = preload("res://world3d/surfaces.gd")
var terrain: MeshInstance3D
var base: MeshInstance3D
var material: Material
var noise := FastNoiseLite.new()
var _point := Vector2.ZERO
var _surface: SurfaceTool
var _sector := 0
var _ring := 0
var building := false


func setup(city: Node3D) -> void:
	material = city.veg_mat
	noise.seed = city.layout.world_seed
	noise.frequency = 0.0015
	noise.fractal_octaves = 3
	base = MeshInstance3D.new()
	var k := Kit.new()
	k.registers_ground = false
	k.box(Vector3.ZERO, Vector3(12000, 0.02, 12000), Color("#55683f"))
	base.mesh = k.commit(material)
	base.material_override = material
	base.position.y = -0.05
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(base)
	terrain = MeshInstance3D.new()
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(terrain)


func update_focus(point: Vector2) -> void:
	base.position.x = point.x
	base.position.z = point.y
	_point = point
	_surface = SurfaceTool.new()
	_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ring = 0
	_sector = 0
	building = true


func step() -> void:
	if not building:
		return
	var rings := [450.0, 650.0, 950.0, 1400.0, 2100.0, 3000.0]
	var started := Time.get_ticks_usec()
	while building and Time.get_ticks_usec() - started < 1200:
		var vertices: Array[Vector3] = []
		for pair in [[_ring, _sector], [_ring, _sector + 1], [_ring + 1, _sector], [_ring + 1, _sector + 1]]:
			var angle := float(pair[1]) / 64.0 * TAU
			var distance := float(rings[pair[0]])
			var point := _point + Vector2(cos(angle), sin(angle)) * distance
			var height := maxf(0.0, noise.get_noise_2d(point.x, point.y) + 0.22) * 320.0
			vertices.append(Vector3(point.x, -0.04 if _ring == 0 and pair[0] == 0 else height, point.y))
		for triangle in [[0, 2, 1], [1, 2, 3]]:
			var normal: Vector3 = (vertices[triangle[1]] - vertices[triangle[0]]).cross(vertices[triangle[2]] - vertices[triangle[0]]).normalized()
			if normal.y < 0.0:
				normal = -normal
			for index in triangle:
				var vertex: Vector3 = vertices[index]
				_surface.set_color(Color("#60715b").lerp(Color("#777c7d"), clampf(vertex.y / 200.0, 0.0, 1.0)))
				_surface.set_uv2(Vector2(Surfaces.layer("gravel" if vertex.y > 90.0 else "grass") + 1, 0))
				_surface.set_uv(Vector2(vertex.x, vertex.z) * 0.02)
				_surface.set_normal(normal)
				_surface.add_vertex(vertex)
		_sector += 1
		if _sector == 64:
			_sector = 0
			_ring += 1
		if _ring == rings.size() - 1:
			terrain.mesh = _surface.commit()
			terrain.material_override = material
			building = false
