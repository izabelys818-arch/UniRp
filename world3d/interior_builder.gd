extends RefCounted

# Arquitetura e mobiliário compartilhados por casas, prédios e futuras construções.
# Não contém economia/IA: registra os mesmos pontos de uso de CityBuilder.
const Kit = preload("res://world3d/mesh_kit.gd")
const Furn = preload("res://world3d/furn_lib.gd")
const KM := "res://assets/furniture_k/Models/%s.fbx"
const BASE := 0.245
const WALL := 0.13
var city: Node3D
var structure: Dictionary
var level := 0
var height := 3.0
var floor_node: Node3D
var fixtures: Node3D
var body: StaticBody3D
var full := Kit.new()
var cut := Kit.new()
var core := Kit.new()
var ceiling := Kit.new()
var occupied: Array[Rect2] = []
var circulation: Array[Rect2] = []
var walk_targets: Array[Vector2] = []
var placements: Array = []
var rejected: Array = []
var points := {}
var guide_keys := {}
var room_routes := {}
var trial_routes := {}
var xf := Transform3D.IDENTITY

# Recorta a parede por retângulos reais. O mesmo contrato é usado pela fachada
# e pelo revestimento interno; vidro/moldura nunca cobrem uma parede maciça.
static func wall_openings(put: Callable, a: Vector3, b: Vector3, paint: Color, holes: Array, checkpoint: Callable = Callable()) -> void:
	var along_x := b.x - a.x > b.z - a.z
	var start := a.x if along_x else a.z
	var end := b.x if along_x else b.z
	var cuts: Array[Rect2] = []
	var columns: Array[float] = [start, end]
	var rows: Array[float] = [a.y, b.y]
	for hole in holes:
		if bool(hole["along_x"]) != along_x:
			continue
		var c: Vector3 = hole["center"]
		var plane := c.z if along_x else c.x
		if plane < (a.z if along_x else a.x) - 0.5 or plane > (b.z if along_x else b.x) + 0.5:
			continue
		var size: Vector2 = hole["size"]
		var mid := c.x if along_x else c.z
		var cutout := Rect2(mid - size.x / 2, c.y - size.y / 2, size.x, size.y).intersection(Rect2(start, a.y, end - start, b.y - a.y))
		if not cutout.has_area():
			continue
		cuts.append(cutout)
		columns.append(cutout.position.x)
		columns.append(cutout.end.x)
		rows.append(cutout.position.y)
		rows.append(cutout.end.y)
	columns.sort()
	rows.sort()
	# Coordenadas idênticas são repetidas por janela/andar. Removê-las evita
	# percorrer milhares de células de tamanho zero; os vãos são os mesmos.
	for values in [columns, rows]:
		for index in range(values.size() - 1, 0, -1):
			if values[index] == values[index - 1]:
				values.remove_at(index)
	for x in columns.size() - 1:
		if checkpoint.is_valid():
			await checkpoint.call()
		for y in rows.size() - 1:
			if columns[x + 1] - columns[x] < 0.001 or rows[y + 1] - rows[y] < 0.001:
				continue
			var mid := Vector2((columns[x] + columns[x + 1]) / 2, (rows[y] + rows[y + 1]) / 2)
			var open := false
			for cutout in cuts:
				if cutout.has_point(mid):
					open = true
					break
			if not open:
				var lo := Vector3(columns[x], rows[y], a.z) if along_x else Vector3(a.x, rows[y], columns[x])
				var hi := Vector3(columns[x + 1], rows[y + 1], b.z) if along_x else Vector3(b.x, rows[y + 1], columns[x + 1])
				put.call(lo, hi, paint)

static func glass_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.69, 0.82, 0.87, 0.12)
	material.roughness = 0.18
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

static func window_frame(kit, hole: Dictionary, trim: Color) -> void:
	var p: Vector3 = hole["center"]
	var size: Vector2 = hole["size"]
	var along_x: bool = hole["along_x"]
	var axis := Vector3.RIGHT if along_x else Vector3.BACK
	var depth := Vector3(0.08, 0, 0.36) if along_x else Vector3(0.36, 0, 0.08)
	for sign in [-1, 1]:
		kit.box(p + axis * sign * (size.x / 2 + 0.045), depth + Vector3.UP * (size.y + 0.18), trim)
		kit.box(p + Vector3.UP * sign * (size.y / 2 + 0.045), axis * (size.x + 0.18) + Vector3(0, 0.08, 0) + (Vector3.BACK if along_x else Vector3.RIGHT) * 0.36, trim)

static func install_glass(s: Dictionary, city: Node = null) -> void:
	var kit := Kit.new()
	kit.registers_ground = false
	for hole in s.get("window_holes", []):
		if city != null:
			await city.generation_checkpoint()
		var size: Vector2 = hole["size"]
		kit.box(hole["center"], Vector3(size.x, size.y, 0.015) if hole["along_x"] else Vector3(0.015, size.y, size.x), Color.WHITE)
	var node: MeshInstance3D
	if city != null:
		node = city._mesh(kit, s["full"], glass_material())
	else:
		var mesh := kit.commit(glass_material())
		if mesh == null:
			return
		node = MeshInstance3D.new()
		node.mesh = mesh
		(s["full"] as Node3D).add_child(node)
	node.name = "VidrosTransparentes"
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s["clear_windows"] = node
	node.visible = false

static func create(c: Node3D, s: Dictionary, parent: Node3D, number: int) -> Node3D:
	var builder = load("res://world3d/interior_builder.gd").new()
	return builder.build(c, s, parent, number)

func build(c: Node3D, s: Dictionary, parent: Node3D, number: int) -> Node3D:
	city = c
	structure = s
	level = number
	height = float(s.get("floor_height", 2.9))
	var w: float = s.get("w", (s["rect"] as Rect2).size.x)
	var d: float = s.get("d", (s["rect"] as Rect2).size.y)
	floor_node = Node3D.new()
	floor_node.name = "Andar_%d" % level
	floor_node.position = s.get("interior_offset", Vector3.ZERO) + Vector3.UP * (height * level)
	parent.add_child(floor_node)
	xf = floor_node.global_transform
	fixtures = Node3D.new()
	fixtures.name = "Moveis"
	floor_node.add_child(fixtures)
	body = StaticBody3D.new()
	floor_node.add_child(body)
	for kit in [full, cut, core, ceiling]:
		kit.registers_ground = false
		kit.world_xf = xf
	points = {"_root": floor_node, "_rooms": [], "_floor": level, "_portals": []}
	var interior := Rect2(-w / 2.0 + 0.31, -d / 2.0 + 0.31, w - 0.62, d - 0.62)
	var shaft := Rect2()
	var stair_kit := Kit.new()
	stair_kit.registers_ground = false
	stair_kit.world_xf = xf
	if int(s.get("floor_count", 1)) > 1:
		# Deixar um hall que comporte a cápsula e o patamar. Em prédios
		# pouco profundos o antigo recuo de 25 cm encerrava a escada na parede.
		shaft = Rect2(interior.position, Vector2(2.6, minf(3.5, interior.size.y - 1.1)))
		occupied.append(shaft.grow(0.1))
		s["stair_rect"] = shaft
		var finishes = core
		core = stair_kit
		_stairs(shaft)
		core = finishes
	var room_area := interior
	if shaft.size != Vector2.ZERO:
		room_area.position.x += 2.75
		room_area.size.x -= 2.75
	var back_depth := minf(4.5 if str(s.get("profile", "")) in ["hospital", "servico"] else 3.5, room_area.size.y * (0.51 if str(s.get("profile", "")) in ["hospital", "servico"] else 0.46))
	var split_x := room_area.position.x + room_area.size.x * 0.6
	var split_z := room_area.position.y + back_depth
	var rooms := [
		["quarto", Rect2(room_area.position, Vector2(split_x - room_area.position.x, back_depth))],
		["banheiro", Rect2(split_x, room_area.position.y, room_area.end.x - split_x, back_depth)],
		["sala", Rect2(room_area.position.x, split_z, split_x - room_area.position.x, room_area.end.y - split_z)],
		["cozinha", Rect2(split_x, split_z, room_area.end.x - split_x, room_area.end.y - split_z)]
	]
	var compact := room_area.size.x < 4.4 or room_area.size.y < 4.7
	if compact:
		rooms = [["estudio", room_area]]
	elif str(s.get("family", "")) == "office":
		rooms[0][0] = "escritorio"
		rooms[2][0] = "reuniao"
		rooms[3][0] = "copa"
	var profile := str(s.get("profile", "casa"))
	if compact and str(s.get("family", "")) == "office":
		profile = "servico"
	if compact and profile in ["servico", "hospital"]:
		rooms = [["recepcao", room_area]]
	if str(s.get("family", "")) == "shop":
		profile = "varejo"
	if profile in ["bar", "comida", "loja", "varejo", "igreja"]:
		compact = true
		rooms = [[profile, room_area]]
	elif profile in ["hospital", "servico"] and not compact:
		rooms[0][0] = "enfermaria" if profile == "hospital" else "escritorio"
		rooms[1][0] = "consultorio" if profile == "hospital" else "arquivo"
		rooms[2][0] = "espera"
		rooms[3][0] = "recepcao"
	elif profile == "hospedagem" and not compact:
		rooms[0][0] = "quarto"
		rooms[2][0] = "espera"
		rooms[3][0] = "recepcao"
	var paint := Color(["#d6cfbf", "#c7ceca", "#d4c9bb", "#cbd0d4"][absi(hash(str(s["loc"]))) % 4])
	full.use_surface("plaster")
	cut.use_surface("plaster")
	# Revestimento interno das paredes externas; geometria separada do teto e do piso.
	_wall(interior.position, Vector2(interior.end.x, interior.position.y), paint)
	_wall(interior.position, Vector2(interior.position.x, interior.end.y), paint)
	_wall(Vector2(interior.end.x, interior.position.y), interior.end, paint)
	var door_x := clampf(float(s.get("dx", 0.0)), interior.position.x + 0.65, interior.end.x - 0.65)
	if level == 0:
		# Entrada até o ponto de chegada usado por CityLayout, sempre livre.
		circulation.append(Rect2(door_x - 0.43, interior.end.y - 2.2, 0.86, 2.3))
	if level == 0:
		_wall(Vector2(interior.position.x, interior.end.y), Vector2(door_x - 0.58, interior.end.y), paint)
		_wall(Vector2(door_x + 0.58, interior.end.y), interior.end, paint)
	else:
		_wall(Vector2(interior.position.x, interior.end.y), interior.end, paint)
	# Portas dos fundos e passagem entre sala/cozinha; 1,1 m livres e hall junto à entrada.
	var left_door := split_x - 0.7 if split_x - room_area.position.x < 3.2 else (room_area.position.x + split_x) * 0.5
	var right_door := split_x + 0.68 if room_area.end.x - split_x < 2.8 else (split_x + room_area.end.x) * 0.5
	if not compact:
		# Vão e aproximações dos dois lados são reservados antes dos móveis.
		# Uma cama/balcão cabia no cômodo, mas podia fechar a esquina da porta.
		for opening in [left_door, right_door]:
			var width := 0.62 if opening == right_door and room_area.end.x - split_x < 2.2 else (0.82 if opening == right_door and room_area.end.x - split_x < 2.8 else 1.2)
			circulation.append(Rect2(opening - width / 2, split_z - 1.1, width, 2.2))
			for z in [-1.0, -0.5, 0.0, 0.5, 1.0]:
				for x in [-0.2, 0.0, 0.2]:
					_guide(Vector2(opening + x, split_z + z))
		_wall(Vector2(room_area.position.x, split_z), Vector2(left_door - 0.65, split_z), paint)
		_wall(Vector2(left_door + 0.65, split_z), Vector2(right_door - 0.65, split_z), paint)
		_wall(Vector2(right_door + 0.65, split_z), Vector2(room_area.end.x, split_z), paint)
		for opening in [left_door, right_door]:
			var lintel := Rect2(opening - 0.65, split_z - WALL / 2, 1.3, WALL)
			var cap_height := height - 0.2 - 2.12
			if cap_height > 0.01:
				full.box_ab(Vector3(lintel.position.x, BASE + 2.12, lintel.position.y), Vector3(lintel.end.x, BASE + height - 0.2, lintel.end.y), paint)
				_box_collision(lintel, BASE + 2.12, cap_height)
			full.use_surface("paintedwood")
			for side in [-1, 1]:
				full.box(Vector3(opening + side * 0.63, BASE + 1.05, split_z), Vector3(0.045, 2.1, 0.17), Color("#b4a591"))
			full.box(Vector3(opening, BASE + 2.12, split_z), Vector3(1.3, 0.045, 0.17), Color("#b4a591"))
			full.use_surface("plaster")
		_wall(Vector2(split_x, room_area.position.y), Vector2(split_x, split_z), paint)
		if room_area.end.y - 2.0 > split_z + 0.1:
			_wall(Vector2(split_x, split_z), Vector2(split_x, room_area.end.y - 2.0), paint)
	if shaft.size != Vector2.ZERO:
		# DoorIn fica 1,8 m para dentro da fachada. O separador da escada
		# precisa terminar antes desse hall; senão algumas portas chegam
		# exatamente dentro da divisória e só permitem sair num sentido.
		_wall(Vector2(room_area.position.x - 0.1, interior.position.y), Vector2(room_area.position.x - 0.1, interior.end.y - 2.2), paint)
		# Corredor contínuo entre patamar e hall frontal, também em lotes
		# profundos. Sem esses portais a busca caía na grade densa nos andares.
		var hall_z := shaft.end.y + 0.35
		_guide(Vector2(shaft.position.x + 0.62, hall_z))
		while hall_z < interior.end.y - 0.43:
			_guide(Vector2(shaft.end.x - 0.62, hall_z))
			hall_z += 0.8
		_guide(Vector2(shaft.end.x - 0.62, interior.end.y - 0.43))
	# Liga a entrada/hall às duas áreas da frente. Reservar só cada cômodo
	# deixava um rack ou mesa fechar a passagem entre sala e cozinha.
	if not compact or shaft.size != Vector2.ZERO:
		var source_x := door_x if level == 0 else shaft.end.x - 0.62
		var left_entry := left_door if not compact else clampf(door_x, room_area.position.x + 0.43, room_area.end.x - 0.43)
		var right_entry := right_door if not compact else left_entry
		# A porta do banheiro também precisa continuar acessível pelo cômodo
		# da frente. Validar apenas os pontos de uso da cozinha permitia que
		# geladeira/pia separassem essa porta do hall comum.
		if not compact:
			for entry_x in [left_entry, right_entry]:
				circulation.append(Rect2(entry_x - 0.31, split_z, 0.62, interior.end.y - split_z - 0.43))
		var first := minf(source_x, minf(left_entry, right_entry))
		if shaft.size != Vector2.ZERO:
			first = minf(first, shaft.position.x + 0.62)
		var last := maxf(source_x, maxf(left_entry, right_entry))
		circulation.append(Rect2(first - 0.30, interior.end.y - 0.77, last - first + 0.60, 0.68))
		_guide(Vector2(source_x, interior.end.y - 1.49 if level == 0 else shaft.end.y + 0.35))
		var guide_x := first
		while guide_x < last:
			_guide(Vector2(guide_x, interior.end.y - 0.43))
			guide_x += 0.4
		_guide(Vector2(last, interior.end.y - 0.43))
	for entry in rooms:
		var rect: Rect2 = entry[1]
		var kind: String = entry[0]
		_floor(rect, "tiles" if kind in ["banheiro", "cozinha", "copa", "loja", "enfermaria", "consultorio", "recepcao"] else "woodfloor")
		var entry_point := Vector2(rect.get_center().x, rect.end.y - 0.43) if rect.end.y <= split_z + 0.01 else Vector2(clampf(door_x, rect.position.x + 0.43, rect.end.x - 0.43), rect.end.y - 0.43)
		if not compact and rect.position.y >= split_z - 0.01:
			entry_point.x = left_door if rect.position.x < split_x - 0.01 else right_door
		if not compact and rect.end.y <= split_z + 0.01:
			entry_point.x = left_door if rect.position.x < split_x - 0.01 else right_door
		points["_rooms"].append({"rect": rect, "exit": [], "entry": entry_point})
		_guide(entry_point)
		if not bool(s.get("legacy_furnish", false)):
			_room(kind, rect)
	# O hall é intencionalmente livre, não preenchido com vasos/caixas.
	if shaft.size != Vector2.ZERO:
		_floor(Rect2(interior.position.x, shaft.end.y, room_area.position.x - interior.position.x, interior.end.y - shaft.end.y), "paving")
		if level == 0:
			_floor(shaft, "paving")
		elif level > 0:
			_floor(Rect2(shaft.position.x, shaft.end.y - 0.15, shaft.size.x, 0.15), "paving")
	_ceiling(interior, shaft, paint)
	for item in placements:
		if not bool(item["solid"]) or float(item["height"]) > 0.2:
			continue
		var boundary: Rect2 = (item["rect"] as Rect2).grow(0.34)
		for point in [boundary.position, boundary.end, Vector2(boundary.position.x, boundary.end.y), Vector2(boundary.end.x, boundary.position.y)]:
			if interior.grow(-0.36).has_point(point):
				_guide(point)
	_mesh(core, floor_node, "Acabamentos")
	var whole := _mesh(full, floor_node, "ParedesInteiras")
	var low := _mesh(cut, floor_node, "ParedesRecortadas")
	var top := _mesh(ceiling, floor_node, "Teto")
	floor_node.set_meta("walls_full", whole)
	floor_node.set_meta("walls_cut", low)
	floor_node.set_meta("ceiling", top)
	floor_node.set_meta("stairs_node", _mesh(stair_kit, floor_node, "Escadas"))
	floor_node.set_meta("use_points", points)
	floor_node.set_meta("placements", placements)
	floor_node.set_meta("rejected", rejected)
	floor_node.set_meta("rooms", rooms)
	var lamps := Node3D.new()
	lamps.name = "Lampadas"
	lamps.visible = false
	floor_node.add_child(lamps)
	var daylight := Node3D.new()
	daylight.name = "LuzDasJanelas"
	daylight.visible = false
	floor_node.add_child(daylight)
	var fittings := Node3D.new()
	fittings.name = "Plafons"
	floor_node.add_child(fittings)
	floor_node.set_meta("fittings", fittings)
	var fitting := Kit.new()
	fitting.registers_ground = false
	for entry in rooms:
		var rect: Rect2 = entry[1]
		var center := rect.get_center()
		# Salas maiores precisam de luminárias distribuídas: uma única luz
		# central deixava entrada, recepção e cantos fora do alcance à noite.
		var columns := clampi(ceili(rect.size.x / 5.0), 1, 3)
		var rows := clampi(ceili(rect.size.y / 5.0), 1, 3)
		for column in columns:
			for row in rows:
				var p := rect.position + rect.size * Vector2((column + 0.5) / columns, (row + 0.5) / rows)
				var lamp := OmniLight3D.new()
				lamp.position = Vector3(p.x, BASE + minf(height - 0.5, 2.5), p.y)
				lamp.omni_range = 6.0
				lamp.light_color = Color("#e5e8e7") if profile == "hospital" else Color("#ffe6cb")
				lamp.light_energy = 1.15
				lamps.add_child(lamp)
				# Todos os plafons compartilham uma malha e um material.
				fitting.cyl(Vector3(p.x, BASE + height - 0.2, p.y), 0.19, 0.03, Color("#e8e3d8"))
		var fill := OmniLight3D.new()
		fill.position = Vector3(center.x, BASE + 1.7, center.y)
		fill.omni_range = minf(7.0, rect.size.length() * 0.8)
		fill.light_color = Color("#dce6ee")
		fill.light_energy = 0.65
		daylight.add_child(fill)
	_mesh(fitting, fittings, "Plafons")
	floor_node.set_meta("light", lamps)
	floor_node.set_meta("daylight", daylight)
	return floor_node

func _mesh(kit, parent: Node3D, label: String) -> MeshInstance3D:
	var mesh: ArrayMesh = kit.commit(city.interior_mat)
	if mesh == null:
		return null
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	parent.add_child(node)
	return node

func _box_collision(rect: Rect2, y: float, h: float) -> void:
	if rect.size.x < 0.005 or rect.size.y < 0.005:
		return
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, h, rect.size.y)
	collider.shape = box
	collider.position = Vector3(rect.get_center().x, y + h / 2.0, rect.get_center().y)
	body.add_child(collider)

func _wall(a: Vector2, b: Vector2, paint: Color) -> void:
	if a.distance_to(b) < 0.03:
		return
	var rect := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), Vector2(absf(b.x - a.x), absf(b.y - a.y))).grow(WALL / 2.0)
	var holes: Array = []
	# Apenas as quatro paredes externas recebem vãos, nunca as divisórias.
	var outline: Rect2 = Rect2(-float(structure.get("w", structure["rect"].size.x)) / 2 + 0.31, -float(structure.get("d", structure["rect"].size.y)) / 2 + 0.31, float(structure.get("w", structure["rect"].size.x)) - 0.62, float(structure.get("d", structure["rect"].size.y)) - 0.62)
	if absf(a.x - b.x) < 0.01 and (absf(a.x - outline.position.x) < 0.01 or absf(a.x - outline.end.x) < 0.01) or absf(a.y - b.y) < 0.01 and (absf(a.y - outline.position.y) < 0.01 or absf(a.y - outline.end.y) < 0.01):
		for hole in structure.get("window_holes", []):
			var local: Dictionary = hole.duplicate()
			local["center"] = (hole["center"] as Vector3) - Vector3.UP * height * level
			holes.append(local)
	wall_openings(Callable(full, "box_ab"), Vector3(rect.position.x, BASE, rect.position.y), Vector3(rect.end.x, BASE + height - 0.2, rect.end.y), paint, holes)
	wall_openings(Callable(cut, "box_ab"), Vector3(rect.position.x, BASE, rect.position.y), Vector3(rect.end.x, BASE + 0.65, rect.end.y), paint, holes)
	_box_collision(rect, BASE, height - 0.2)
	core.use_surface("paintedwood")
	core.box_ab(Vector3(rect.position.x - 0.008, BASE, rect.position.y - 0.008), Vector3(rect.end.x + 0.008, BASE + 0.09, rect.end.y + 0.008), Color("#9b8f7d"))
	occupied.append(rect)

func _floor(rect: Rect2, surface: String) -> void:
	core.use_surface(surface)
	var paint := Color("#8a7560") if surface == "woodfloor" else Color("#c2beb3")
	core.box_ab(Vector3(rect.position.x, BASE - 0.045, rect.position.y), Vector3(rect.end.x, BASE, rect.end.y), paint)
	_box_collision(rect, BASE - 0.065, 0.065)

func _ceiling(rect: Rect2, shaft: Rect2, paint: Color) -> void:
	ceiling.use_surface("plaster")
	var pieces := [rect]
	if shaft.size != Vector2.ZERO and level < int(structure.get("floor_count", 1)) - 1:
		pieces = [Rect2(shaft.end.x, rect.position.y, rect.end.x - shaft.end.x, rect.size.y), Rect2(rect.position.x, shaft.end.y, shaft.size.x, rect.end.y - shaft.end.y)]
	for piece in pieces:
		ceiling.box_ab(Vector3(piece.position.x, BASE + height - 0.16, piece.position.y), Vector3(piece.end.x, BASE + height - 0.08, piece.end.y), paint.lightened(0.16))
		_box_collision(piece, BASE + height - 0.16, 0.08)

func _plan(point: Vector2, yaw: float, room: Rect2) -> Dictionary:
	var world := xf * Vector3(point.x, BASE, point.y)
	return {"path": [Vector2(world.x, world.z)], "yaw": yaw + xf.basis.get_euler().y, "room": room, "floor": level, "floor_y": world.y}

func _guide(point: Vector2) -> void:
	var world := xf * Vector3(point.x, BASE, point.y)
	var key := Vector2i(roundi(world.x * 100), roundi(world.z * 100))
	if guide_keys.has(key):
		return
	guide_keys[key] = true
	points["_portals"].append(Vector2(world.x, world.z))

func _segment_free(a: Vector2, b: Vector2, obstacles: Array[Rect2]) -> bool:
	for rect in obstacles:
		if rect.has_point(a) or rect.has_point(b):
			return false
		var lo := 0.0
		var hi := 1.0
		var delta := b - a
		var intersects := true
		for axis in 2:
			if absf(delta[axis]) < 0.00001:
				if a[axis] < rect.position[axis] or a[axis] > rect.end[axis]:
					intersects = false
					break
			else:
				var first := (rect.position[axis] - a[axis]) / delta[axis]
				var last := (rect.end[axis] - a[axis]) / delta[axis]
				lo = maxf(lo, minf(first, last))
				hi = minf(hi, maxf(first, last))
				if lo > hi:
					intersects = false
					break
		if intersects:
			return false
	return true

# Validação de circulação antes de instanciar: área livre isolada atrás de
# um móvel não é um ponto de uso. Usa AStar2D e as mesmas dimensões de colisão.
func _room_connected(room: Rect2, footprint: Rect2, required: Array) -> bool:
	trial_routes = {}
	var entry := Vector2(room.get_center().x, room.end.y - 0.43)
	for info in points["_rooms"]:
		if info["rect"] == room:
			entry = info["entry"]
			break
	var obstacles: Array[Rect2] = []
	# A mesma margem é usada antes e depois da colocação; caso contrário
	# a rota nova se tornava inválida ao registrar o próprio móvel.
	for rect in occupied + [footprint.grow(0.03)]:
		var inflated: Rect2 = rect.grow(0.32)
		if inflated.intersects(room):
			obstacles.append(inflated)
	var targets: Array = required.duplicate()
	for stand in walk_targets:
		if room.has_point(stand):
			targets.append(stand)
	if targets.is_empty():
		return _segment_free(entry, entry, obstacles)
	var cached: Dictionary = room_routes.get(room, {})
	var pending: Array = []
	for stand in targets:
		var old: Array = cached.get(stand, [])
		var valid := not old.is_empty()
		for index in range(1, old.size()):
			if not _segment_free(old[index - 1], old[index], obstacles):
				valid = false
				break
		if valid:
			trial_routes[stand] = old
		else:
			# Passagens em L aproveitam corredores/aisles, em vez de cruzar
			# diagonalmente onde a próxima fila de cadeiras será colocada.
			for bend in [Vector2(entry.x, stand.y), Vector2(stand.x, entry.y)]:
				if _segment_free(entry, bend, obstacles) and _segment_free(bend, stand, obstacles):
					trial_routes[stand] = [entry, bend, stand]
					break
			if not trial_routes.has(stand):
				if _segment_free(entry, stand, obstacles):
					trial_routes[stand] = [entry, stand]
				else:
					pending.append(stand)
	if pending.is_empty():
		return true
	var graph := AStar2D.new()
	graph.add_point(0, entry)
	var ids := {entry: 0}
	var point_id := func(point: Vector2) -> int:
		if not ids.has(point):
			var key := graph.get_available_point_id()
			graph.add_point(key, point)
			ids[point] = key
		return ids[point]
	# As rotas que continuam livres formam uma base já validada. Uma nova
	# cadeira geralmente pode usar essa passagem, sem reconstruir todas
	# as ligações entre quinas para os outros assentos do cômodo.
	for route in trial_routes.values():
		for index in range(1, route.size()):
			var a: int = point_id.call(route[index - 1])
			var b: int = point_id.call(route[index])
			if a != b:
				graph.connect_points(a, b)
	var remaining: Array = []
	for target in pending:
		var key: int = point_id.call(target)
		for other in graph.get_point_ids():
			if other != key and _segment_free(target, graph.get_point_position(other), obstacles):
				graph.connect_points(key, other)
		var route := graph.get_point_path(0, key)
		if route.is_empty():
			remaining.append(target)
		else:
			trial_routes[target] = Array(route)
	if remaining.is_empty():
		return true
	for rect in obstacles:
		var corners := rect.grow(0.015)
		for point in [corners.position, corners.end, Vector2(corners.position.x, corners.end.y), Vector2(corners.end.x, corners.position.y)]:
			if room.grow(-0.37).has_point(point) and _segment_free(point, point, obstacles):
				graph.add_point(graph.get_available_point_id(), point)
	for a in graph.get_point_ids():
		for b in graph.get_point_ids():
			if a < b and _segment_free(graph.get_point_position(a), graph.get_point_position(b), obstacles):
				graph.connect_points(a, b)
	for target in remaining:
		var key: int = ids[target]
		for other in graph.get_point_ids():
			if other != key and _segment_free(target, graph.get_point_position(other), obstacles):
				graph.connect_points(key, other)
		var route := graph.get_point_path(0, key)
		if route.is_empty():
			return false
		trial_routes[target] = Array(route)
	return true

func _candidate(room: Rect2, size: Vector3, point: Vector2, yaw: float, up: float, kind: String) -> Dictionary:
	var basis := Basis(Vector3.UP, yaw)
	var ext := basis.x.abs() * size.x / 2 + basis.z.abs() * size.z / 2
	var footprint := Rect2(point - Vector2(ext.x, ext.z), Vector2(ext.x, ext.z) * 2)
	if not room.grow(-0.1).encloses(footprint):
		return {}
	var occupies := size.y > 0.12 and up < 0.2
	if occupies:
		for other in occupied + circulation:
			if footprint.grow(0.035).intersects(other):
				return {}
	if not kind in ["bed", "seat", "stove", "bath"]:
		if occupies and not _room_connected(room, footprint, []):
			return {}
		return {"rect": footprint, "stand": room.get_center(), "routes": trial_routes.duplicate() if occupies else {}}
	var facing := Vector2(sin(yaw), cos(yaw))
	var approaches := [point + facing * (size.z / 2 + 0.43), Vector2(point.x, footprint.end.y + 0.43), Vector2(footprint.position.x - 0.43, point.y), Vector2(footprint.end.x + 0.43, point.y), Vector2(point.x, footprint.position.y - 0.43)]
	for stand in approaches:
		if not room.grow(-0.34).has_point(stand):
			continue
		var clearance := Rect2(stand - Vector2.ONE * 0.31, Vector2.ONE * 0.62)
		if clearance.intersects(footprint):
			continue
		var free := true
		for other in occupied:
			if clearance.intersects(other):
				free = false
				break
		if free and _room_connected(room, footprint, [stand]):
			return {"rect": footprint, "stand": stand, "routes": trial_routes.duplicate()}
	return {}

func _placement_options(room: Rect2, size: Vector3, point: Vector2, yaw: float, radius: float) -> Array:
	var alternatives: Array = []
	for turn in [yaw, yaw + PI / 2, yaw - PI / 2, yaw + PI]:
		var basis := Basis(Vector3.UP, turn)
		var ext := basis.x.abs() * size.x / 2 + basis.z.abs() * size.z / 2
		var minimum := room.position + Vector2(ext.x, ext.z) + Vector2.ONE * 0.105
		var maximum := room.end - Vector2(ext.x, ext.z) - Vector2.ONE * 0.105
		if minimum.x > maximum.x or minimum.y > maximum.y:
			continue
		var clamped := point.clamp(minimum, maximum)
		alternatives.append({"point": clamped, "yaw": turn, "cost": clamped.distance_squared_to(point) + (0.25 if turn != yaw else 0.0)})
		for edge_x in [minimum.x, clamped.x, maximum.x]:
			for edge_z in [minimum.y, clamped.y, maximum.y]:
				var edge := Vector2(edge_x, edge_z)
				if edge.distance_squared_to(point) <= radius * radius * 2:
					alternatives.append({"point": edge, "yaw": turn, "cost": edge.distance_squared_to(point) + (0.25 if turn != yaw else 0.0)})
		minimum = minimum.max(point - Vector2.ONE * radius)
		maximum = maximum.min(point + Vector2.ONE * radius)
		var x := minimum.x
		while x <= maximum.x + 0.001:
			var z := minimum.y
			while z <= maximum.y + 0.001:
				var position := Vector2(x, z)
				alternatives.append({"point": position, "yaw": turn, "cost": position.distance_squared_to(point) + (0.25 if turn != yaw else 0.0)})
				z += 0.25
			x += 0.25
	alternatives.sort_custom(func(a, b): return a["cost"] < b["cost"])
	return alternatives

func _place(room: Rect2, name: String, point: Vector2, yaw: float, slot := "", kind := "inspect", up := 0.0, scale_k := 0.2, solid := true) -> Node3D:
	var path := KM % name
	var size: Vector3 = Furn.bounds_for(path).size * scale_k
	var candidate := _candidate(room, size, point, yaw, up, kind)
	if candidate.is_empty():
		# Em salões, montar/sortear toda a grade criava dezenas de milhares
		# de alternativas para mover uma cadeira poucos centímetros. Procurar
		# perto primeiro; a busca completa permanece quando não há encaixe.
		for radius in ([1.25, INF] if room.get_area() > 20 else [INF]):
			for option in _placement_options(room, size, point, yaw, radius):
				candidate = _candidate(room, size, option["point"], option["yaw"], up, kind)
				if not candidate.is_empty():
					point = option["point"]
					yaw = option["yaw"]
					break
			if not candidate.is_empty():
				break
	if candidate.is_empty():
		rejected.append({"model": name, "kind": kind, "reason": "sem espaço com acesso e circulação livres"})
		return null
	var footprint: Rect2 = candidate["rect"]
	var occupies := size.y > 0.12 and up < 0.2
	var holder := Furn.place(fixtures, path, Vector3(point.x, BASE + up, point.y), yaw, scale_k, Vector3.ZERO, solid, hash(str(structure["loc"]) + ":" + name))
	if holder == null:
		return null
	if up > 0.01 and up < 0.2 and name in ["kitchenStove", "kitchenSink", "bathroomSink"]:
		core.use_surface("paintedwood")
		core.box_ab(Vector3(footprint.position.x, BASE, footprint.position.y), Vector3(footprint.end.x, BASE + up, footprint.end.y), Color("#b3afa4"))
		_box_collision(footprint, BASE, up)
	holder.set_meta("room", room)
	placements.append({"model": name, "kind": kind, "slot": slot, "rect": footprint, "room": room, "solid": solid, "height": up})
	if occupies:
		occupied.append(footprint.grow(0.03))
		room_routes[room] = candidate.get("routes", {})
	if slot == "":
		slot = "decor_%d" % placements.size()
	if slot != "":
		var stand: Vector2 = candidate["stand"]
		var face := atan2(point.x - stand.x, point.y - stand.y)
		var plan := _plan(stand, face, room)
		if kind == "bed":
			plan["anchor"] = xf * (Vector3(point.x, 0, point.y) + Basis(Vector3.UP, yaw) * Vector3(0, 0, size.z * 0.44))
			plan["yaw"] = yaw + xf.basis.get_euler().y
			plan["h"] = 0.5
			points["cama"] = plan
			city.beds.append({"p": plan["path"].back(), "anchor": plan["anchor"], "yaw": plan["yaw"], "h": plan["h"], "loc": str(structure["loc"]), "floor": level})
		elif kind == "tv" and points.has("sofa"):
			plan = (points["sofa"] as Dictionary).duplicate(true)
		elif kind == "computer":
			var nearby_seat: Dictionary = {}
			var distance := INF
			var computer_world := xf * Vector3(point.x, BASE, point.y)
			for seat in city.seats:
				if str(seat.get("loc", "")) != str(structure["loc"]) or int(seat.get("floor", 0)) != level or seat.get("room", Rect2()) != room:
					continue
				var next_distance := (seat["p"] as Vector2).distance_squared_to(Vector2(computer_world.x, computer_world.z))
				if next_distance < distance:
					distance = next_distance
					nearby_seat = seat
			if not nearby_seat.is_empty():
				plan["seat"] = nearby_seat
				plan["path"] = [nearby_seat["approach"]]
				plan["yaw"] = nearby_seat["yaw"]
			points["computador"] = plan
		elif kind == "seat":
			var seat := xf * Vector3(point.x, BASE, point.y)
			plan["seat"] = {"p": Vector2(seat.x, seat.z), "yaw": yaw + xf.basis.get_euler().y}
			if slot == "sofa":
				points["sofa"] = plan
			var seat_plan: Dictionary = plan["seat"].duplicate()
			seat_plan.merge({"loc": str(structure["loc"]), "floor": level, "approach": plan["path"].back(), "room": room}, true)
			city.seats.append(seat_plan)
		elif kind == "bath":
			plan["head"] = xf * Vector3(stand.x, BASE + 1.7, stand.y)
			points["chuveiro"] = plan
		elif kind == "stove":
			plan["steam"] = xf * Vector3(point.x, BASE + up + size.y + 0.07, point.y)
			points["fogao"] = plan
		if kind in ["bed", "seat", "stove", "bath"]:
			walk_targets.append(stand)
			circulation.append(Rect2(stand - Vector2.ONE * 0.31, Vector2.ONE * 0.62))
			_guide(stand)
			for offset in [Vector2(0.3, 0), Vector2(-0.3, 0), Vector2(0, 0.3), Vector2(0, -0.3)]:
				_guide(stand + offset)
		var key := str(structure["loc"]) + "/" + ("andar_%d/" % level if level > 0 else "") + slot
		if city.objects.has(key):
			# Dois cômodos podem ter computador/mesa com o mesmo nome de slot.
			# Cada móvel continua selecionável; o alias da atividade é separado.
			key += "_%d" % placements.size()
		var labels := {"kitchenFridge": "Geladeira Brisa", "kitchenSink": "Pia da cozinha", "bathroomSink": "Pia do banheiro", "toilet": "Vaso sanitário", "cabinetBed": "Criado-mudo", "cabinetTelevision": "Rack", "bookcaseOpen": "Estante", "bookcaseClosed": "Armário", "tableCoffee": "Mesa de centro", "table": "Mesa", "desk": "Escrivaninha", "laptop": "Computador", "rugRectangle": "Tapete", "pottedPlant": "Vaso de planta"}
		var label: String = {"bed": "Cama", "seat": "Assento", "stove": "Fogão Aurora", "bath": "Banho", "tv": "Televisão"}.get(kind, labels.get(name, "Móvel"))
		city.object_point(key, str(structure["loc"]), label, holder.global_transform * (holder.get_meta("bounds") as AABB), kind, plan, false, holder)
		if holder.has_method("bind_id"):
			holder.bind_id(key)
			if plan.has("seat"):
				plan["seat"]["physical_object"] = holder
				seat_plan_object(holder, key)
		if name in ["table", "tableCoffee"]:
			for index in 3:
				var item_kind: String = ["copo", "prato", "garrafa"][index]
				var item_key := key + "/" + item_kind
				var table_top := Vector3(point.x + (index - 1) * minf(0.25, size.x / 4), BASE + up + size.y + 0.006, point.y)
				var object := preload("res://world3d/light_object.gd").tableware(fixtures, table_top, item_kind, item_key)
				if not object.broken:
					city.object_point(item_key, str(structure["loc"]), item_kind.capitalize(), object.global_transform * object.get_meta("bounds"), "loose", plan, false, object)
	return holder

func seat_plan_object(holder: Node3D, _key: String) -> void:
	for seat in city.seats:
		var point: Vector2 = seat["p"]
		if point.distance_squared_to(Vector2(holder.global_position.x, holder.global_position.z)) < 0.01:
			seat["physical_object"] = holder

func _room(kind: String, room: Rect2) -> void:
	var a := room.position
	var b := room.end
	var center := room.get_center()
	match kind:
		"enfermaria":
			for index in maxi(1, int((room.size.x - 0.4) / 2.1)):
				_place(room, "bedSingle", Vector2(a.x + 0.75 + index * 2.1, a.y + 1.28), 0, "leito_%d" % index, "bed")
		"consultorio", "escritorio":
			var desk := _place(room, "desk", Vector2(a.x + 1.0, a.y + 0.6), 0, "mesa", "inspect")
			if desk != null:
				var desk_point := Vector2(desk.position.x, desk.position.z)
				var front := Vector2(sin(desk.rotation.y), cos(desk.rotation.y))
				_place(room, "chair", desk_point + front * 0.8, desk.rotation.y + PI, "cadeira", "seat")
				_place(room, "laptop", desk_point, desk.rotation.y, "computador", "computer", (desk.get_meta("bounds") as AABB).size.y, 0.2, false)
			if room.size.x > 3.1:
				_place(room, "bookcaseOpen", Vector2(b.x - 0.5, a.y + 0.55), 0, "estante", "storage")
		"arquivo":
			for index in maxi(1, int(room.size.x / 1.8)):
				_place(room, "bookcaseClosed", Vector2(a.x + 0.8 + index * 1.8, a.y + 0.55), 0, "arquivo_%d" % index, "storage")
		"espera":
			for index in maxi(1, int((room.size.x - 0.5) / 1.1)):
				_place(room, "chair", Vector2(a.x + 0.55 + index * 1.1, a.y + 0.7), 0, "espera_%d" % index, "seat")
			_place(room, "pottedPlant", Vector2(a.x + 0.42, b.y - 0.45), 0, "", "inspect", 0, 0.14, false)
		"recepcao":
			var desk := _place(room, "desk", Vector2(center.x, a.y + 1.0), 0, "balcao", "inspect")
			if desk != null:
				_place(room, "laptop", Vector2(desk.position.x, desk.position.z), desk.rotation.y, "computador", "computer", (desk.get_meta("bounds") as AABB).size.y, 0.2, false)
			_place(room, "bookcaseClosed", Vector2(b.x - 0.65, b.y - 0.55), PI, "arquivo", "storage")
		"bar", "comida":
			var counter_room := Rect2(a, Vector2(room.size.x, minf(3.0, room.size.y * 0.35)))
			_place(counter_room, "kitchenFridge", Vector2(b.x - 0.55, a.y + 0.6), 0, "geladeira")
			_place(counter_room, "kitchenStove", Vector2(a.x + 0.6, a.y + 0.65), 0, "fogao", "stove")
			_place(counter_room, "kitchenSink", Vector2(a.x + 1.6, a.y + 0.65), 0, "pia")
			for index in maxi(1, int((room.size.x - 1.0) / 3.0)):
				var position := Vector2(a.x + 1.5 + index * 3.0, b.y - 2.0)
				_place(room, "table", position, 0, "mesa_%d" % index, "inspect", 0, 0.16)
				for side in [-1, 1]:
					_place(room, "chair", position + Vector2(0, side * 0.85), PI if side < 0 else 0, "cadeira_%d_%d" % [index, side], "seat")
		"varejo":
			for index in maxi(1, int((room.size.x - 1) / 2.0)):
				_place(room, "bookcaseOpen", Vector2(a.x + 1 + index * 2.0, a.y + 0.65), 0, "prateleira_%d" % index, "storage")
			_place(room, "desk", Vector2(a.x + 1.1, b.y - 1.0), PI, "balcao", "inspect")
		"igreja":
			for row in mini(6, int((room.size.y - 3) / 1.6)):
				for side in [-1, 1]:
					for column in 2:
						_place(room, "chair", Vector2(center.x + side * (1.5 + column * 1.0), a.y + 2.2 + row * 1.6), PI, "assento_%d_%d_%d" % [row, side, column], "seat")
		"estudio":
			if room.size.x > 2.3:
				_place(room, "bedSingle", Vector2(a.x + 0.72, a.y + 1.28), 0, "cama_quarto", "bed")
			_place(room, "bookcaseClosed", Vector2(b.x - 0.4, a.y + 0.5), 0, "armario", "storage", 0, 0.16)
			_place(room, "chair", Vector2(center.x, b.y - 1.0), PI, "cadeira", "seat")
		"reuniao":
			_place(room, "table", Vector2(center.x, a.y + 1.0), 0, "mesa", "inspect")
			for side in [-1, 1]:
				_place(room, "chair", Vector2(center.x + side * 0.95, a.y + 1.0), side * PI / 2.0, "cadeira_%d" % side, "seat")
		"copa":
			_place(room, "kitchenFridge", Vector2(b.x - 0.56, a.y + 0.6), 0, "geladeira")
			_place(room, "kitchenSink", Vector2(a.x + 0.55, a.y + 0.6), 0, "pia")
		"quarto":
			var double := room.size.x >= 3.4
			var bx := a.x + (1.08 if double else 0.72)
			var bed := _place(room, "bedDouble" if double else "bedSingle", Vector2(bx, a.y + 1.28), 0, "cama_quarto", "bed")
			if bed == null and double:
				_place(room, "bedSingle", Vector2(a.x + 0.72, a.y + 1.28), 0, "cama_quarto", "bed")
			_place(room, "cabinetBed", Vector2(b.x - 0.38, a.y + 0.4), 0, "criado_quarto", "inspect")
			_place(room, "bookcaseClosed", Vector2(b.x - 0.36, b.y - 0.6), -PI / 2.0, "armario_quarto", "storage", 0, 0.16)
		"banheiro":
			if room.size.x >= 2.2:
				_place(room, "bathtub", Vector2(center.x, a.y + 0.58), 0, "banho", "bath", 0, 0.16)
			else:
				_place(room, "shower", Vector2(a.x + 0.62, a.y + 0.64), 0, "banho", "bath", 0, 0.16)
			if room.size.x < 2.2:
				_place(room, "toilet", Vector2(b.x - 0.36, a.y + 0.53), 0, "vaso", "inspect", 0, 0.16)
				_place(room, "bathroomSink", Vector2(b.x - 0.372, a.y + 1.23), 0, "pia_banho", "inspect", 0.08, 0.16)
			else:
				_place(room, "toilet", Vector2(a.x + 0.42, b.y - 0.62), 0)
				_place(room, "bathroomSink", Vector2(b.x - 0.48, b.y - 0.57), 0, "pia_banho", "inspect", 0, 0.16)
		"sala":
			var sofa_z := a.y + 1.12
			if _place(room, "loungeSofa", Vector2(a.x + 0.55, sofa_z), PI / 2.0, "sofa", "seat") == null:
				if _place(room, "loungeChair", Vector2(a.x + 0.55, sofa_z), PI / 2.0, "sofa", "seat", 0, 0.18) == null:
					_place(room, "chair", Vector2(a.x + 0.55, sofa_z), PI / 2.0, "sofa", "seat")
			var rack := _place(room, "cabinetTelevision", Vector2(b.x - 0.4, sofa_z), -PI / 2.0, "rack", "storage", 0, 0.16)
			if rack != null:
				var rack_size: Vector3 = (rack.get_meta("bounds") as AABB).size
				_place(room, "televisionModern", Vector2(rack.position.x, rack.position.z), rack.rotation.y, "tv", "tv", rack_size.y, 0.15, false)
			else:
				# Sala pequena: tela fixada ao trecho maciço da parede dos fundos,
				# com suporte visível. Não deixa TV suspensa sem rack nem apoio.
				var television := _place(room, "televisionModern", Vector2(a.x + 0.66, a.y + 0.205), 0, "tv", "tv", 1.15, 0.15, false)
				if television != null:
					core.use_surface("metal")
					core.box_ab(Vector3(television.position.x - 0.16, BASE + 1.35, a.y + 0.04), Vector3(television.position.x + 0.16, BASE + 1.62, television.position.z - 0.06), Color("#484d50"))
			if room.size.x > 3.5 and room.size.y > 3.3:
				_place(room, "tableCoffee", Vector2(center.x, sofa_z), PI / 2.0, "mesa_sala", "inspect", 0, 0.16)
			_place(room, "rugRectangle", Vector2(center.x, sofa_z), PI / 2.0, "", "inspect", 0.004, 0.12, false)
			_place(room, "pottedPlant", Vector2(a.x + 0.42, b.y - 0.45), 0, "", "inspect", 0, 0.14, false)
		"cozinha":
			if room.size.x < 3.6 or room.size.y < 3.5:
				# Linha compacta única; corredor junto à porta e alturas de bancada humanas.
				_place(room, "kitchenStove", Vector2(b.x - 0.465, a.y + 1.805), -PI / 2, "fogao", "stove", 0.18, 0.16)
				_place(room, "kitchenFridge", Vector2(b.x - 0.495, a.y + 0.37), 0, "geladeira", "inspect", 0, 0.18)
				_place(room, "kitchenSink", Vector2(b.x - 0.465, a.y + 1.045), -PI / 2, "pia", "inspect", 0.12, 0.16)
			elif room.size.x > 3.2:
				_place(room, "kitchenFridge", Vector2(b.x - 0.56, a.y + 0.43), 0, "geladeira")
				_place(room, "kitchenStove", Vector2(b.x - 1.5, a.y + 0.56), 0, "fogao", "stove")
				_place(room, "kitchenSink", Vector2(b.x - 2.48, a.y + 0.56), 0, "pia")
			else:
				var appliance_z := a.y + minf(2.0, room.size.y - 1.08)
				var narrow := room.size.x < 2.2
				_place(room, "kitchenStove", Vector2(b.x - 0.57, appliance_z), -PI / 2.0, "fogao", "stove", 0, 0.16 if narrow else 0.2)
				_place(room, "kitchenFridge", Vector2(b.x - 0.43, a.y + 0.55), -PI / 2.0, "geladeira", "inspect", 0, 0.18 if narrow else 0.2)
				_place(room, "kitchenSink", Vector2(a.x + 0.58, a.y + 0.6 if room.size.x < 2.7 else appliance_z), 0 if room.size.x < 2.7 else PI / 2.0, "pia", "inspect", 0, 0.16 if narrow else 0.2)
			if room.get_area() > 13:
				_place(room, "table", Vector2(center.x, b.y - 1.3), 0, "mesa_cozinha", "inspect", 0, 0.16)
				_place(room, "chair", Vector2(center.x, b.y - 0.55), 0, "cadeira_0", "seat")

func _ramp(rect: Rect2, y: float, rise: float, reverse: bool) -> void:
	var shape := ConvexPolygonShape3D.new()
	var vertices := PackedVector3Array()
	for x in [rect.position.x, rect.end.x]:
		for z in [rect.position.y, rect.end.y]:
			var t: float = (z - rect.position.y) / rect.size.y
			var surface := y + rise * (t if reverse else 1.0 - t)
			# Laje inclinada fina, com vão abaixo. Uma cunha sólida do andar de cima
			# criava um teto horizontal baixo sobre a escada do andar de baixo.
			vertices.append(Vector3(x, surface - 0.12, z))
			vertices.append(Vector3(x, surface, z))
	shape.points = vertices
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	core.use_surface("woodfloor")
	for step in 9:
		var t := float(step + 1) / 9.0
		var z := rect.position.y + rect.size.y * (float(step) / 9.0 if reverse else 1.0 - t)
		core.box_ab(Vector3(rect.position.x, y + rise * t - 0.1, z), Vector3(rect.end.x, y + rise * t, z + rect.size.y / 9.0), Color("#9a8871"))

func _stairs(rect: Rect2) -> void:
	var bottom := Vector2(rect.position.x + 0.62, rect.end.y + 0.35)
	var top := Vector2(rect.end.x - 0.62, rect.end.y + 0.35)
	var back := rect.position.y + 0.67
	var route := [bottom, Vector2(bottom.x, rect.position.y + 0.4), Vector2(top.x, rect.position.y + 0.4), top]
	var world_route: Array = []
	for point in route:
		var world := xf * Vector3(point.x, BASE, point.y)
		world_route.append(Vector2(world.x, world.z))
	if not structure.has("stairs"):
		structure["stairs"] = {}
	structure["stairs"][level] = {"up": world_route, "bottom": world_route[0], "top": world_route.back()}
	if level > 0:
		var down_point := xf * Vector3(top.x, BASE, top.y)
		city.object_point(str(structure["loc"]) + "/escada_descer_%d" % level, str(structure["loc"]), "Escada — descer um andar", xf * AABB(Vector3(top.x - 0.4, BASE, top.y - 0.35), Vector3(0.8, 0.6, 0.7)), "stairs", {"path": [Vector2(down_point.x, down_point.z)], "floor": level, "destination_floor": level - 1}, false, floor_node)
	if level >= int(structure.get("floor_count", 1)) - 1:
		return
	_ramp(Rect2(rect.position.x + 0.08, back, 1.08, rect.end.y - back - 0.15), BASE, height / 2.0, false)
	_ramp(Rect2(rect.end.x - 1.16, back, 1.08, rect.end.y - back - 0.15), BASE + height / 2.0, height / 2.0, true)
	# O vazio da escada atravessa os andares: uma laje aqui cortava a cabeça
	# no patamar intermediário, impedindo a subida pelo corpo físico.
	# Patamar intermediário na altura das duas rampas, sem degrau de teletransporte.
	core.use_surface("woodfloor")
	core.box_ab(Vector3(rect.position.x, BASE + height / 2.0 - 0.1, rect.position.y), Vector3(rect.end.x, BASE + height / 2.0, back), Color("#9a8871"))
	_box_collision(Rect2(rect.position.x, rect.position.y, rect.size.x, 0.67), BASE + height / 2.0 - 0.12, 0.12)
	for side in [rect.position.x + 0.02, rect.end.x - 0.02]:
		var rail_start := Vector3(side, BASE + (height / 2 if side < rect.get_center().x else height) + 0.92, back)
		var rail_end := Vector3(side, BASE + (0.0 if side < rect.get_center().x else height / 2) + 0.92, rect.end.y - 0.15)
		var direction := rail_end - rail_start
		core.add("cyl", Transform3D(Basis(Quaternion(Vector3.UP, direction.normalized())) * Basis.from_scale(Vector3(0.055, direction.length(), 0.055)), (rail_start + rail_end) / 2), Color("#777b7f"))
		for step in 7:
			var t := float(step) / 6.0
			var y := BASE + height * (0.5 * (1.0 - t) if side < rect.get_center().x else 0.5 + 0.5 * t)
			core.cyl(Vector3(side, y, back + t * (rect.end.y - back - 0.15)), 0.022, 0.92, Color("#777b7f"))
	var start := xf * Vector3(bottom.x, BASE, bottom.y)
	var key := str(structure["loc"]) + "/escada_%d" % level
	city.object_point(key, str(structure["loc"]), "Escada — subir um andar", xf * AABB(Vector3(bottom.x - 0.4, BASE, bottom.y - 0.35), Vector3(0.8, 0.6, 0.7)), "stairs", {"path": [Vector2(start.x, start.z)], "floor": level, "destination_floor": level + 1}, false, floor_node)
