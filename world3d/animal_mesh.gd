extends RefCounted

# Bichos com forma de bicho: cachorro (vira-lata) e pombo montados por anéis ao longo de um
# eixo (tubos suaves com tampas), em vez de bolinhas. Mantém a hierarquia que a animação de
# life.gd já usa: body / head / tail / leg0..3 (cachorro) e pl/pr com as asas (pombo).

const FUR := preload("res://world3d/fur.gdshader")

const BREEDS := [
	# nome, pelo, barriga, dorso, manchas
	["caramelo", "#b07a42", "#e1c9a0", "#8a5a2c", 0.0],
	["preto", "#262220", "#4a4440", "#141210", 0.0],
	["malhado", "#ece4d6", "#f6f2ea", "#3a2e26", 1.0],
	["cinza", "#6e6a66", "#a9a39b", "#4a4643", 0.0],
	["bege", "#c9ae86", "#e8dcc6", "#a8875e", 0.0],
]

static var _meshes: Dictionary = {}
static var _noise: Texture2D


static func cleanup() -> void:
	_meshes.clear()
	_noise = null


static func _fur_noise() -> Texture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.03
		n.fractal_octaves = 3
		var t := NoiseTexture2D.new()
		t.width = 256
		t.height = 256
		t.seamless = true
		t.noise = n
		_noise = t
	return _noise


# Tubo suave: estações [centro, raio x, raio y] ao longo do caminho; tampas nas pontas.
static func _tube(stations: Array, segs: int = 14) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i in stations.size():
		var c: Vector3 = stations[i][0]
		var nxt: Vector3 = stations[mini(i + 1, stations.size() - 1)][0]
		var prv: Vector3 = stations[maxi(i - 1, 0)][0]
		var fwd := (nxt - prv).normalized()
		if fwd.length() < 0.01:
			fwd = Vector3.BACK
		var side := fwd.cross(Vector3.UP).normalized()
		if side.length() < 0.01:
			side = Vector3.RIGHT
		var up := side.cross(fwd).normalized()
		var ring: Array = []
		for j in segs:
			var a := TAU * j / segs
			ring.append(c + side * cos(a) * float(stations[i][1]) + up * sin(a) * float(stations[i][2]))
		rings.append(ring)
	for i in rings.size() - 1:
		for j in segs:
			var j2 := (j + 1) % segs
			var a: Vector3 = rings[i][j]
			var b: Vector3 = rings[i][j2]
			var c: Vector3 = rings[i + 1][j]
			var d: Vector3 = rings[i + 1][j2]
			for v in [a, c, b, b, c, d]:
				st.add_vertex(v)
	for end in [0, rings.size() - 1]:
		var center: Vector3 = stations[end][0]
		for j in segs:
			var j2 := (j + 1) % segs
			if end == 0:
				st.add_vertex(center); st.add_vertex(rings[end][j]); st.add_vertex(rings[end][j2])
			else:
				st.add_vertex(center); st.add_vertex(rings[end][j2]); st.add_vertex(rings[end][j])
	st.generate_normals()
	return st.commit()


static func _mesh(key: String) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var m: ArrayMesh
	match key:
		"dog_body":
			# do quadril ao peito: barriga recolhida, peito fundo, cernelha alta
			m = _tube([
				[Vector3(0, 0.44, -0.36), 0.07, 0.07], [Vector3(0, 0.45, -0.3), 0.13, 0.13],
				[Vector3(0, 0.46, -0.16), 0.14, 0.12], [Vector3(0, 0.46, 0.0), 0.13, 0.11],
				[Vector3(0, 0.47, 0.14), 0.145, 0.15], [Vector3(0, 0.46, 0.27), 0.15, 0.17],
				[Vector3(0, 0.5, 0.36), 0.12, 0.14], [Vector3(0, 0.58, 0.44), 0.08, 0.09],
			])
		"dog_head":
			# crânio e focinho afinando até a trufa
			m = _tube([
				[Vector3(0, 0.02, -0.11), 0.05, 0.05], [Vector3(0, 0.03, -0.07), 0.095, 0.09],
				[Vector3(0, 0.02, 0.0), 0.1, 0.09], [Vector3(0, -0.01, 0.07), 0.07, 0.065],
				[Vector3(0, -0.03, 0.15), 0.05, 0.045], [Vector3(0, -0.035, 0.21), 0.035, 0.032],
			])
		"dog_ear":
			m = _tube([[Vector3(0, 0, 0), 0.025, 0.012], [Vector3(0, -0.06, 0.01), 0.045, 0.015], [Vector3(0, -0.12, 0.02), 0.02, 0.008]], 8)
		"dog_leg":
			# coxa, joelho, canela e pata
			m = _tube([
				[Vector3(0, 0.02, 0), 0.05, 0.055], [Vector3(0, -0.1, -0.01), 0.04, 0.045],
				[Vector3(0, -0.2, 0.01), 0.025, 0.028], [Vector3(0, -0.27, 0.015), 0.026, 0.028],
				[Vector3(0, -0.3, 0.05), 0.03, 0.02],
			], 10)
		"dog_tail":
			m = _tube([[Vector3(0, 0, 0), 0.03, 0.03], [Vector3(0, 0.07, -0.08), 0.025, 0.025], [Vector3(0, 0.16, -0.12), 0.018, 0.018], [Vector3(0, 0.24, -0.11), 0.006, 0.006]], 8)
		"bird_body":
			m = _tube([
				[Vector3(0, 0.0, -0.17), 0.01, 0.004], [Vector3(0, 0.0, -0.1), 0.04, 0.02],
				[Vector3(0, 0.005, -0.02), 0.06, 0.055], [Vector3(0, 0.015, 0.05), 0.055, 0.055],
				[Vector3(0, 0.035, 0.1), 0.03, 0.033], [Vector3(0, 0.05, 0.13), 0.02, 0.02],
			], 12)
		"bird_head":
			m = _tube([[Vector3(0, 0.0, -0.03), 0.01, 0.01], [Vector3(0, 0.0, -0.01), 0.028, 0.03], [Vector3(0, 0.0, 0.02), 0.026, 0.026], [Vector3(0, -0.006, 0.045), 0.008, 0.007], [Vector3(0, -0.008, 0.06), 0.002, 0.002]], 10)
		"bird_wing_in":
			m = _wing(0.0, 0.16, 0.11, 0.09)
		"bird_wing_out":
			m = _wing(0.0, 0.17, 0.09, 0.04)
	_meshes[key] = m
	return m


# Asa: lâmina fina afilando da raiz à ponta (comprimento em x).
static func _wing(x0: float, length: float, chord0: float, chord1: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 5
	for i in n:
		var u0 := float(i) / n
		var u1 := float(i + 1) / n
		var c0 := lerpf(chord0, chord1, u0)
		var c1 := lerpf(chord0, chord1, u1)
		var a := Vector3(x0 + length * u0, 0.004, c0 * 0.4)
		var b := Vector3(x0 + length * u1, 0.004, c1 * 0.4)
		var c := Vector3(x0 + length * u1, 0.0, -c1 * 0.6)
		var d := Vector3(x0 + length * u0, 0.0, -c0 * 0.6)
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)
		for v in [a, c, b, a, d, c]:
			st.add_vertex(v - Vector3(0, 0.006, 0))
	st.generate_normals()
	return st.commit()


static func _fur_material(coat: Color, belly: Color, saddle: Color, spots: float, offset: Vector3, feathers := 0.0, iridescent := 0.0, belly_y := -10.0, sock_y := -10.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.set_shader_parameter("belly_y", belly_y)
	m.set_shader_parameter("sock_y", sock_y)
	m.shader = FUR
	m.set_shader_parameter("coat", coat)
	m.set_shader_parameter("belly", belly)
	m.set_shader_parameter("saddle", saddle)
	m.set_shader_parameter("spots", spots)
	m.set_shader_parameter("feathers", feathers)
	m.set_shader_parameter("iridescent", iridescent)
	m.set_shader_parameter("fur_noise", _fur_noise())
	m.set_shader_parameter("part_offset", offset)
	return m


static func _add(parent: Node3D, mesh: Mesh, material: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


# Cachorro de rua: mesma hierarquia de antes (body, body/head, body/tail, leg0..3).
static func dog(rng: RandomNumberGenerator) -> Node3D:
	var breed: Array = BREEDS[rng.randi() % BREEDS.size()]
	var coat := Color(str(breed[1])).darkened(rng.randf_range(-0.06, 0.1))
	var belly_c := Color(str(breed[2]))
	var saddle_c := Color(str(breed[3]))
	var spots: float = breed[4]
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "body"
	root.add_child(body)
	_add(body, _mesh("dog_body"), _fur_material(coat, belly_c, saddle_c, spots, Vector3.ZERO, 0.0, 0.0, 0.4))
	var head := Node3D.new()
	head.name = "head"
	head.position = Vector3(0, 0.62, 0.5)
	body.add_child(head)
	var head_mat := _fur_material(coat, belly_c, saddle_c, spots * 0.6, head.position)
	_add(head, _mesh("dog_head"), head_mat)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("#141210")
	dark.roughness = 0.25
	dark.metallic_specular = 0.6
	_add(head, _mesh("bird_head"), dark, Vector3(0, -0.033, 0.2), Vector3.ZERO).scale = Vector3(1.4, 1.2, 0.5)
	for sx in [-1.0, 1.0]:
		# orelhas caídas (vira-lata) e olhos úmidos
		_add(head, _mesh("dog_ear"), head_mat, Vector3(sx * 0.075, 0.08, -0.03), Vector3(0.2, 0, sx * 0.55))
		var eye := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.014
		sm.height = 0.028
		eye.mesh = sm
		eye.material_override = dark
		eye.position = Vector3(sx * 0.055, 0.035, 0.065)
		head.add_child(eye)
	var tail := Node3D.new()
	tail.name = "tail"
	tail.position = Vector3(0, 0.5, -0.36)
	body.add_child(tail)
	_add(tail, _mesh("dog_tail"), _fur_material(coat, belly_c, saddle_c, spots, tail.position))
	for i in 4:
		var leg := Node3D.new()
		leg.name = "leg%d" % i
		leg.position = Vector3((-1 if i % 2 == 0 else 1) * 0.085, 0.31, 0.27 if i < 2 else -0.27)
		root.add_child(leg)
		_add(leg, _mesh("dog_leg"), _fur_material(coat, belly_c, saddle_c, spots, leg.position, 0.0, 0.0, -10.0, -0.17))
	return root


# Pombo: corpo, cabeça com pescoço iridescente e asas em duas partes (pl/pr giram ao bater).
static func pigeon(rng: RandomNumberGenerator) -> Node3D:
	var gray := Color("#7d838c").darkened(rng.randf_range(-0.1, 0.25))
	var b := Node3D.new()
	var body_mat := _fur_material(gray, gray.lightened(0.15), gray.darkened(0.15), 0.0, Vector3.ZERO, 1.0)
	_add(b, _mesh("bird_body"), body_mat)
	var neck_mat := _fur_material(gray.darkened(0.2), gray, gray.darkened(0.3), 0.0, Vector3.ZERO, 1.0, 0.8)
	_add(b, _mesh("bird_head"), neck_mat, Vector3(0, 0.06, 0.14))
	var wing_mat := _fur_material(gray.lightened(0.05), gray.lightened(0.1), gray.darkened(0.35), 0.0, Vector3.ZERO, 1.0)
	for side in [["pl", -1.0], ["pr", 1.0]]:
		var pivot := Node3D.new()
		pivot.name = side[0]
		b.add_child(pivot)
		var inner := _add(pivot, _mesh("bird_wing_in"), wing_mat)
		inner.name = "w" + str(side[0]).substr(1)
		inner.scale = Vector3(float(side[1]), 1, 1)
		var outer := _add(inner, _mesh("bird_wing_out"), wing_mat, Vector3(0.16, 0, 0))
		outer.scale = Vector3(1, 1, 1)
	return b
