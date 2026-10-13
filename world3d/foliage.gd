extends Node3D

# Copas de árvores e arbustos feitas de cartões de folhas recortadas (foto CC0), em vez de
# esferas lisas. O Kit registra cada esfera de folhagem (cor e volume) enquanto a cidade é
# montada e desenha só um miolo menor e escuro, que vira a sombra interna da copa. Aqui os
# cartões nascem em volta desse miolo, virados para fora (a copa ganha luz de volume),
# em pedaços montados aos poucos perto da câmera. Projetam sombra rendilhada.

const SHADER := preload("res://world3d/foliage.gdshader")
const CELL := 10.0
const RADIUS := 52.0
const CARD := 0.46
const CORE := 0.86

static var spheres: Array = []          # [centro, tamanho (Vector3), cor]
static var _grid: Dictionary = {}       # Vector2i -> Array de índices
static var enabled := true
static var registration_owner := ""
static var _owners: Dictionary = {}
static var _free: Array[int] = []

var _cells: Dictionary = {}
var _queue: Array = []
var _material: ShaderMaterial
var _mesh: ArrayMesh


static func reset() -> void:
	spheres.clear()
	_grid.clear()
	_owners.clear()
	_free.clear()
	registration_owner = ""


static func is_foliage(color: Color, category: String) -> bool:
	var h := color.h * 360.0
	if h > 55.0 and h < 175.0 and color.s > 0.14 and color.v > 0.1:
		return true
	# vegetação de qualquer cor (ipê branco, roxo, rosa, amarelo; flores): a esfera lisa com a
	# foto de folhas por cima virava "bolinhas" — sempre vira copa de pétalas/folhas
	return category == "veg" and color.v > 0.1


# Registra a copa (em coordenadas do mundo) e devolve o miolo que o Kit deve desenhar.
static func register_sphere(world: Transform3D, local: Transform3D, color: Color) -> Array:
	var size := Vector3(world.basis.x.length(), world.basis.y.length(), world.basis.z.length())
	if size.x < 0.35 and size.z < 0.35:
		return [local, color]
	var idx: int = spheres.size() if _free.is_empty() else _free.pop_back()
	if idx == spheres.size():
		spheres.append([])
	spheres[idx] = [world.origin, size, color]
	if registration_owner != "":
		if not _owners.has(registration_owner):
			_owners[registration_owner] = []
		_owners[registration_owner].append(idx)
	var key := Vector2i(floori(world.origin.x / CELL), floori(world.origin.z / CELL))
	if not _grid.has(key):
		_grid[key] = []
	(_grid[key] as Array).append(idx)
	# miolo escuro só em copas grandes (fecha o fundo); em tufos pequenos ele aparecia
	# como uma bola lisa no meio das folhas
	# sem miolo sólido: ele aparecia como uma bola lisa (e não some quando a copa fica rendada
	# na frente do jogador); o volume vem das camadas internas de folhas, mais escuras
	var core := 0.02
	# o miolo é a sombra dentro da copa: mesmo tom, mais escuro (antes, em flores claras,
	# virava pintas pretas entre as pétalas)
	return [Transform3D(local.basis.scaled_local(Vector3.ONE * core), local.origin), color.darkened(0.32 if color.v > 0.6 else 0.45)]


static func release_owner(key: String) -> void:
	for index in _owners.get(key, []):
		var point: Vector3 = spheres[index][0]
		var cell := Vector2i(floori(point.x / CELL), floori(point.z / CELL))
		_grid.get(cell, []).erase(index)
		if _grid.get(cell, []).is_empty():
			_grid.erase(cell)
		spheres[index] = []
		_free.append(index)
	_owners.erase(key)


func invalidate_region(rect: Rect2) -> void:
	for cell in _cells.keys():
		if rect.grow(CELL).has_point(Vector2(cell) * CELL):
			if is_instance_valid(_cells[cell]):
				_cells[cell].queue_free()
			_cells.erase(cell)


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("leaves", load("res://assets/textures/foliage/leaves.png"))
	_material.set_shader_parameter("leaves_n", load("res://assets/textures/foliage/leaves_n.jpg"))
	var n := FastNoiseLite.new()
	n.frequency = 0.03
	var gust := NoiseTexture2D.new()
	gust.width = 128
	gust.height = 128
	gust.seamless = true
	gust.noise = n
	_material.set_shader_parameter("gust_noise", gust)
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, q.get_mesh_arrays())


func update_view(center: Vector3) -> void:
	if not enabled or spheres.is_empty():
		return
	var c := Vector2i(floori(center.x / CELL), floori(center.z / CELL))
	var reach := int(ceil(RADIUS / CELL))
	var wanted := {}
	for gx in range(c.x - reach, c.x + reach + 1):
		for gz in range(c.y - reach, c.y + reach + 1):
			var key := Vector2i(gx, gz)
			if Vector2((gx + 0.5) * CELL, (gz + 0.5) * CELL).distance_to(Vector2(center.x, center.z)) > RADIUS + CELL * 0.7:
				continue
			wanted[key] = true
			if not _cells.has(key) and not _queue.has(key):
				_queue.append(key)
	for key in _cells.keys():
		if not wanted.has(key):
			if _cells[key] != null:
				(_cells[key] as Node).queue_free()
			_cells.erase(key)
	_queue = _queue.filter(func(k): return wanted.has(k))
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.distance_squared_to(c) < b.distance_squared_to(c))
	var started := Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - started < 1500:
		var key: Vector2i = _queue.pop_front()
		_cells[key] = _build_cell(key)


func _build_cell(key: Vector2i) -> MultiMeshInstance3D:
	var list: Array = _grid.get(key, [])
	if list.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) + 17
	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	for i in list:
		var sp: Array = spheres[i]
		var center: Vector3 = sp[0]
		var size: Vector3 = sp[1]
		var col: Color = sp[2]
		var half := size * 0.5
		# área aproximada do elipsoide -> cartões suficientes para fechar a copa
		var area := 4.0 * PI * pow((pow(half.x * half.y, 1.6) + pow(half.x * half.z, 1.6) + pow(half.y * half.z, 1.6)) / 3.0, 1.0 / 1.6)
		# cobertura fechada: a copa é uma massa de folhas, não uma bola com folhas soltas
		var count := clampi(int(area * 17.0), 20, 2000)
		for n in count:
			# ponto na casca (mais denso por fora), direção para fora
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 1), rng.randf_range(-1, 1)).normalized()
			var r := pow(rng.randf(), 0.3)
			var p := center + dir * half * lerpf(0.45, 1.04, r)
			var card := CARD * rng.randf_range(0.75, 1.25) * clampf(half.length() / 1.2, 0.55, 1.1)
			var outward := (dir * half.normalized() * 1.0).normalized()
			var basis := Basis.looking_at(-outward.lerp(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), 0.35), Vector3.UP if absf(outward.y) < 0.95 else Vector3.RIGHT)
			basis = basis * Basis(Vector3.BACK, rng.randf() * TAU)
			xforms.append(Transform3D(basis.scaled(Vector3(card, card, card)), p))
			var tone := col.darkened(rng.randf_range(0.0, 0.22)).lerp(Color("#6f7d36"), rng.randf() * 0.18).lerp(Color("#2c4a28"), rng.randf() * 0.2)
			if dir.y < -0.2:
				tone = tone.darkened(0.25)
			# folhas de dentro da copa ficam na sombra das de fora
			tone = tone.darkened((1.0 - r) * 0.5)
			var lin := tone.srgb_to_linear()
			customs.append(Color(lin.r, lin.g, lin.b, rng.randf()))
	var buffer := PackedFloat32Array()
	buffer.resize(xforms.size() * 16)
	for i in xforms.size():
		var x: Transform3D = xforms[i]
		var c: Color = customs[i]
		var o := i * 16
		buffer[o] = x.basis.x.x; buffer[o + 1] = x.basis.y.x; buffer[o + 2] = x.basis.z.x; buffer[o + 3] = x.origin.x
		buffer[o + 4] = x.basis.x.y; buffer[o + 5] = x.basis.y.y; buffer[o + 6] = x.basis.z.y; buffer[o + 7] = x.origin.y
		buffer[o + 8] = x.basis.x.z; buffer[o + 9] = x.basis.y.z; buffer[o + 10] = x.basis.z.z; buffer[o + 11] = x.origin.z
		buffer[o + 12] = c.r; buffer[o + 13] = c.g; buffer[o + 14] = c.b; buffer[o + 15] = c.a
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh
	mm.instance_count = xforms.size()
	mm.buffer = buffer
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	return mi
