extends Node3D

# Grama de verdade: lâminas instanciadas só onde o chão pintado é grama, em pedaços de 12 m
# montados aos poucos em volta da câmera. O Kit registra cada pedaço de chão fino (caixa rasa
# virada para cima) com a cor e a altura; a lâmina só nasce onde o pedaço mais alto é verde,
# então caminhos, garagens, pisos de casa e canteiros de terra bloqueiam a grama sozinhos.

const SHADER := preload("res://world3d/grass.gdshader")
const CELL := 8.0
const RADIUS := 44.0
const PER_M2 := 150.0

# registro de chão (preenchido pelo Kit enquanto a cidade é montada)
static var patches: Array = []          # [Rect2 xz, top_y, Color, is_grass]
static var _grid: Dictionary = {}       # Vector2i (célula) -> Array de índices em patches
static var enabled := true
static var registration_owner := ""
static var _owners: Dictionary = {}
static var _free: Array[int] = []
static var _owned_exclusions: Dictionary = {}

var _cells: Dictionary = {}             # Vector2i -> MultiMeshInstance3D (ou null se vazia)
var _queue: Array = []
var _material: ShaderMaterial
var _mesh: ArrayMesh


static func reset() -> void:
	patches.clear()
	_grid.clear()
	_exclusions.clear()
	_exclusion_grid.clear()
	_owners.clear()
	_free.clear()
	_owned_exclusions.clear()
	registration_owner = ""


static var _exclusions: Array[Rect2] = []
static var _exclusion_grid: Dictionary = {}

static func exclude_interior(rect: Rect2) -> void:
	_exclusions.append(rect)
	if registration_owner != "":
		if not _owned_exclusions.has(registration_owner):
			_owned_exclusions[registration_owner] = []
		_owned_exclusions[registration_owner].append(rect)
	for x in range(floori(rect.position.x / CELL), floori(rect.end.x / CELL) + 1):
		for z in range(floori(rect.position.y / CELL), floori(rect.end.y / CELL) + 1):
			var key := Vector2i(x, z)
			if not _exclusion_grid.has(key):
				_exclusion_grid[key] = []
			_exclusion_grid[key].append(rect)

static func inside_interior(point: Vector2) -> bool:
	var key := Vector2i(floori(point.x / CELL), floori(point.y / CELL))
	for rect in _exclusion_grid.get(key, []):
		if (rect as Rect2).has_point(point):
			return true
	return false


static func _is_green(c: Color) -> bool:
	var h := c.h * 360.0
	return h > 55.0 and h < 170.0 and c.s > 0.16 and c.v > 0.12


# Chamado pelo Kit para toda caixa: só guarda chão raso perto do nível da rua.
static func register_box(xf: Transform3D, color: Color) -> void:
	if not enabled:
		return
	# o que importa é a face de cima: lajes de chão descem abaixo da rua e ainda contam
	var sy := xf.basis.y.length()
	if sy > 0.9:
		return
	var top := xf.origin.y + sy * 0.5
	if top > 0.75 or top < -0.2:
		return
	var ex := xf.basis.x.abs() * 0.5 + xf.basis.z.abs() * 0.5
	if ex.x * ex.z < 0.06:
		return
	var r := Rect2(xf.origin.x - ex.x, xf.origin.z - ex.z, ex.x * 2.0, ex.z * 2.0)
	var idx: int = patches.size() if _free.is_empty() else _free.pop_back()
	if idx == patches.size():
		patches.append([])
	patches[idx] = [r, top, color, _is_green(color)]
	if registration_owner != "":
		if not _owners.has(registration_owner):
			_owners[registration_owner] = []
		_owners[registration_owner].append(idx)
	for gx in range(floori(r.position.x / CELL), floori(r.end.x / CELL) + 1):
		for gz in range(floori(r.position.y / CELL), floori(r.end.y / CELL) + 1):
			var key := Vector2i(gx, gz)
			if not _grid.has(key):
				_grid[key] = []
			(_grid[key] as Array).append(idx)


static func release_owner(key: String) -> void:
	for index in _owners.get(key, []):
		var rect: Rect2 = patches[index][0]
		for x in range(floori(rect.position.x / CELL), floori(rect.end.x / CELL) + 1):
			for z in range(floori(rect.position.y / CELL), floori(rect.end.y / CELL) + 1):
				var cell := Vector2i(x, z)
				_grid.get(cell, []).erase(index)
				if _grid.get(cell, []).is_empty():
					_grid.erase(cell)
		patches[index] = []
		_free.append(index)
	_owners.erase(key)
	for rect in _owned_exclusions.get(key, []):
		_exclusions.erase(rect)
		for x in range(floori(rect.position.x / CELL), floori(rect.end.x / CELL) + 1):
			for z in range(floori(rect.position.y / CELL), floori(rect.end.y / CELL) + 1):
				var cell := Vector2i(x, z)
				_exclusion_grid.get(cell, []).erase(rect)
				if _exclusion_grid.get(cell, []).is_empty():
					_exclusion_grid.erase(cell)
	_owned_exclusions.erase(key)


func invalidate_region(rect: Rect2) -> void:
	for cell in _cells.keys():
		if rect.grow(CELL).has_point(Vector2(cell) * CELL):
			if is_instance_valid(_cells[cell]):
				_cells[cell].queue_free()
			_cells.erase(cell)


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	var n := FastNoiseLite.new()
	n.frequency = 0.02
	var gust := NoiseTexture2D.new()
	gust.width = 256
	gust.height = 256
	gust.seamless = true
	gust.noise = n
	_material.set_shader_parameter("gust_noise", gust)
	_mesh = _blade_mesh()


# Lâmina: tira afilada com 4 segmentos e leve curva para trás.
func _blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 4
	var pts: Array = []
	for i in segs + 1:
		var t := float(i) / segs
		var w := 0.5 * (1.0 - t * 0.92)
		var bend := t * t * 0.18
		pts.append([Vector3(-w, t, bend), Vector3(w, t, bend), t])
	for i in segs:
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		for tri in [[a[0], a[1], b[1]], [a[0], b[1], b[0]]]:
			for v in tri:
				st.set_uv(Vector2(0.5, (v as Vector3).y))
				st.set_normal(Vector3(0, 0.3, -1).normalized())
				st.add_vertex(v)
	return st.commit()


# Pedaço de chão mais alto naquele ponto: só cresce grama se for verde.
static func _ground_at(p: Vector2) -> Array:
	if inside_interior(p):
		return []
	var key := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	var list: Array = _grid.get(key, [])
	var best: Array = []
	var best_y := -INF
	for i in list:
		var patch: Array = patches[i]
		if not (patch[0] as Rect2).has_point(p):
			continue
		var top := float(patch[1])
		# empate de altura: o piso desenhado por cima (caminho, laje) vence o gramado
		if top > best_y + 0.004 or (top >= best_y - 0.004 and not bool(patch[3])):
			best_y = maxf(best_y, top)
			best = patch
	return best


func update_view(center: Vector3) -> void:
	if not enabled or patches.is_empty():
		return
	RenderingServer.global_shader_parameter_set("player_pos", center)
	var c := Vector2i(floori(center.x / CELL), floori(center.z / CELL))
	var reach := int(ceil(RADIUS / CELL))
	var wanted := {}
	for gx in range(c.x - reach, c.x + reach + 1):
		for gz in range(c.y - reach, c.y + reach + 1):
			var key := Vector2i(gx, gz)
			var mid := Vector2((gx + 0.5) * CELL, (gz + 0.5) * CELL)
			if mid.distance_to(Vector2(center.x, center.z)) > RADIUS + CELL * 0.7:
				continue
			wanted[key] = true
			if not _cells.has(key) and not _queue.has(key):
				_queue.append(key)
	for key in _cells.keys():
		if not wanted.has(key):
			var mi = _cells[key]
			if mi != null:
				(mi as Node).queue_free()
			_cells.erase(key)
	_queue = _queue.filter(func(k): return wanted.has(k))
	# mais perto primeiro
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.distance_squared_to(c) < b.distance_squared_to(c))
	# orçamento por quadro: monta enquanto couber em ~2 ms (nunca trava a caminhada)
	var started := Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - started < 2000:
		var key: Vector2i = _queue.pop_front()
		_cells[key] = _build_cell(key)


func _build_cell(key: Vector2i) -> MultiMeshInstance3D:
	var list: Array = _grid.get(key, [])
	var cell_rect := Rect2(key.x * CELL, key.y * CELL, CELL, CELL)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var buffer := PackedFloat32Array()
	var count := 0
	for i in list:
		var patch: Array = patches[i]
		if not bool(patch[3]):
			continue
		var area_rect := (patch[0] as Rect2).intersection(cell_rect)
		if area_rect.get_area() < 0.05:
			continue
		var top := float(patch[1])
		# só o que está por cima deste gramado pode tapá-lo (caminho, piso, canteiro)
		var covers: Array = []
		for j in list:
			if j == i:
				continue
			var other: Array = patches[j]
			var ot := float(other[1])
			if (ot > top + 0.004 or (ot >= top - 0.004 and not bool(other[3]) and j > i)) and (other[0] as Rect2).intersects(area_rect):
				covers.append(other[0])
		var col: Color = patch[2]
		var n := int(area_rect.get_area() * PER_M2)
		buffer.resize((count + n) * 16)
		for t in n:
			var p := Vector2(area_rect.position.x + rng.randf() * area_rect.size.x, area_rect.position.y + rng.randf() * area_rect.size.y)
			var hidden := inside_interior(p)
			for r in covers:
				if (r as Rect2).has_point(p):
					hidden = true
					break
			if hidden:
				continue
			# gramado aparado com touceiras mais altas aqui e ali; seco (menos saturado) cresce mais
			var h := rng.randf_range(0.07, 0.17) * (1.0 + (1.0 - col.s) * 0.7)
			if rng.randf() < 0.08:
				h *= 1.8
			var w := rng.randf_range(0.03, 0.06)
			var basis := (Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))).scaled(Vector3(w, h, w))
			var tone := col.lerp(Color("#8a8f3e"), rng.randf() * 0.35).lerp(Color("#2f5a26"), rng.randf() * 0.3).srgb_to_linear()
			var o := count * 16
			buffer[o] = basis.x.x; buffer[o + 1] = basis.y.x; buffer[o + 2] = basis.z.x; buffer[o + 3] = p.x
			buffer[o + 4] = basis.x.y; buffer[o + 5] = basis.y.y; buffer[o + 6] = basis.z.y; buffer[o + 7] = top + 0.005
			buffer[o + 8] = basis.x.z; buffer[o + 9] = basis.y.z; buffer[o + 10] = basis.z.z; buffer[o + 11] = p.y
			buffer[o + 12] = tone.r; buffer[o + 13] = tone.g; buffer[o + 14] = tone.b; buffer[o + 15] = rng.randf()
			count += 1
	if count == 0:
		return null
	buffer.resize(count * 16)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh
	mm.instance_count = count
	mm.buffer = buffer
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
