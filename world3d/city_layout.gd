extends RefCounted

# Traçado da cidade: grade de quarteirões separados por ruas com nome. Cada local do jogo ocupa
# um quarteirão; os quarteirões residenciais são divididos em lotes com casas voltadas para a rua.
# Também calcula rotas a pé pelas ruas (A* sobre os cruzamentos).

const Art = preload("res://world3d/art_style.gd")

const GRID := 8
const BLOCK := 30.0
const STREET := 10.0
const PITCH := BLOCK + STREET
const SIZE := GRID * PITCH + STREET
const CHUNK_SIZE := 80.0
const CENTER := Vector2(SIZE * 0.5, SIZE * 0.5)
const LANDMARK_CELLS := {
	"prefeitura": Vector2i(9, 4), "boate": Vector2i(-2, 3),
	"shopping": Vector2i(4, -3), "universidade": Vector2i(20, 8),
	"estadio": Vector2i(9, 18), "cemiterio": Vector2i(-30, 3),
	"aeroporto": Vector2i(65, 10),
}
const LANDMARK_NAMES := {"prefeitura": "Prefeitura — Palácio Municipal", "boate": "Boate Aurora",
	"shopping": "Shopping Central", "universidade": "Universidade Municipal",
	"estadio": "Estádio Municipal", "cemiterio": "Cemitério Municipal", "aeroporto": "Aeroporto Regional"}
const SIDEWALK := 2.2
const SETBACK := 3.2

# Um único quarteirão de avaliação. Sem alterar grade, marcos ou IDs antigos.
static var urban_prototype_enabled := true
var prototype_cell := Vector2i(-1, -1)
var prototype_house_ids: Array[String] = []

const STREETS_V := ["Av. Brasil", "Rua das Acácias", "Rua XV de Novembro", "Rua das Flores", "Av. Central", "Rua do Comércio", "Rua das Palmeiras", "Rua Sete de Setembro", "Rua da Estação"]
const STREETS_H := ["Rua Augusta", "Rua Marechal Deodoro", "Rua São José", "Av. Getúlio Vargas", "Rua da Paz", "Rua Santa Rita", "Rua dos Ipês", "Rua Tiradentes", "Rua Pernambuco"]

# Tamanho do prédio (largura x, profundidade z) por tipo/local. Vazio = local aberto.
const FOOTPRINT := {
	"bar": Vector2(14, 11), "loja": Vector2(20, 15), "comida": Vector2(14, 11),
	"hospital": Vector2(24, 18), "delegacia": Vector2(18, 13), "casa": Vector2(12, 10),
	"hospedagem": Vector2(17, 14), "igreja": Vector2(12, 18), "servico": Vector2(18, 13),
}

var blocks: Dictionary = {}      # Vector2i -> {"loc": id or "", "kind": ..., "lots": [ids]}
var lots: Dictionary = {}        # id -> lote
var rng := RandomNumberGenerator.new()
var house_ids: Array = []
var world_seed := 7741
var chunk_cells: Dictionary = {}
var street_graph := AStar2D.new()
var street_nodes: Dictionary = {}
var street_refs: Dictionary = {}
var region_nodes: Dictionary = {}
var _next_node := 0


func _init() -> void:
	for id in World.locations.keys():
		if World.locations[id].get("generated_building", false) or World.locations[id].get("streamed", false):
			World.locations.erase(id)
	rng.seed = 7741
	_assign()
	if urban_prototype_enabled:
		_make_market_houses()
	_register_houses()
	var state := stream_state()
	world_seed = int(state["seed"])
	_add_street_region("central", Vector2i.ZERO, Vector2i(GRID, GRID))
	for id in ["hospital", "delegacia", "rodoviaria", "parque"]:
		if lots.has(id):
			state["landmarks"][id] = [lots[id]["cell"].x, lots[id]["cell"].y]
	for id in LANDMARK_CELLS:
		var cell: Vector2i = LANDMARK_CELLS[id]
		state["landmarks"][id] = [cell.x, cell.y]
		_register_landmark(id)
	_restore_saved_places()


static func stream_state() -> Dictionary:
	# Campo opcional dentro do player do save v1; o envelope/versão são preservados.
	var state: Dictionary = GameState.player.get("world_stream", {})
	for pair in [["seed", 7741], ["chunks", {}], ["landmarks", {}], ["npc_positions", {}]]:
		if not state.has(pair[0]):
			state[pair[0]] = pair[1]
	GameState.player["world_stream"] = state
	return state


static func chunk_key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]


static func chunk_at(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CHUNK_SIZE), floori(point.y / CHUNK_SIZE))


static func central_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID and cell.y < GRID


func seed_chunk(coord: Vector2i, salt: String = "") -> int:
	# Hash explícito de inteiros/texto, independente de ordem de carga e arquitetura.
	var result := world_seed & 0x7fffffff
	for byte in (chunk_key(coord) + ":" + salt).to_utf8_buffer():
		result = ((result ^ int(byte)) * 16777619) & 0x7fffffff
	return result


static func density_ring(point: Vector2) -> int:
	var distance := point.distance_to(CENTER)
	return 0 if distance < 400.0 else (1 if distance < 1000.0 else (2 if distance < 2000.0 else (3 if distance < 3500.0 else 4)))


static func street_name(index: int, vertical: bool = false) -> String:
	var names: Array = STREETS_V if vertical else STREETS_H
	if index >= 0 and index < names.size():
		return str(names[index])
	return "%s %s %d" % ["Estrada" if absi(index) > 50 else "Rua", "Leste/Oeste" if vertical else "Norte/Sul", index]


func _restore_saved_places() -> void:
	var ids: Array = GameState.player.get("houses", {}).keys()
	ids.append_array(GameState.player.get("housing", {}).get("contracts", {}).keys())
	ids.append(str(GameState.player.get("home", "")))
	ids.append(str(GameState.player.get("location", "")))
	for id in ids:
		var parts := str(id).split("_")
		if parts.size() == 4 and parts[0] == "casa" and parts[1].is_valid_int() and parts[2].is_valid_int():
			var cell := Vector2i(int(parts[1]), int(parts[2]))
			if not central_cell(cell):
				ensure_chunk(Vector2i(floori(cell.x / 2.0), floori(cell.y / 2.0)))
	var saved: Array = GameState.player.get("pos", [])
	if saved.size() >= 2:
		ensure_chunk(chunk_at(Vector2(float(saved[0]), float(saved[1]))))


func _register_landmark(id: String) -> void:
	var cell: Vector2i = LANDMARK_CELLS[id]
	var point := to_map(block_rect(cell).get_center())
	World.locations[id] = {"nome": LANDMARK_NAMES[id], "tipo": "publico", "abre": 0, "fecha": 24,
		"x": point.x, "y": point.y, "loja": [], "servicos": [], "streamed": true,
		"descricao": "Um marco da cidade, integrado às ruas e aos bairros."}
	if id == "boate":
		World.locations[id].merge({"tipo": "bar", "idade_minima": 18, "abre": 18, "fecha": 6}, true)


func ensure_place(id: String) -> bool:
	if lots.has(id):
		return true
	if LANDMARK_CELLS.has(id):
		var cell: Vector2i = LANDMARK_CELLS[id]
		ensure_chunk(Vector2i(floori(cell.x / 2.0), floori(cell.y / 2.0)))
	else:
		var parts := id.split("_")
		if parts.size() == 4 and parts[0] == "casa" and parts[1].is_valid_int() and parts[2].is_valid_int():
			ensure_chunk(Vector2i(floori(int(parts[1]) / 2.0), floori(int(parts[2]) / 2.0)))
	return lots.has(id)


func ensure_chunk(coord: Vector2i) -> Array:
	if chunk_cells.has(coord):
		return chunk_cells[coord]
	var cells: Array = []
	for x in range(coord.x * 2, coord.x * 2 + 2):
		for y in range(coord.y * 2, coord.y * 2 + 2):
			var cell := Vector2i(x, y)
			if central_cell(cell):
				continue
			cells.append(cell)
			if blocks.has(cell):
				continue
			var local_rng := RandomNumberGenerator.new()
			local_rng.seed = seed_chunk(coord, "%d:%d" % [x, y])
			var landmark := ""
			for id in LANDMARK_CELLS:
				if LANDMARK_CELLS[id] == cell:
					landmark = id
			var ring := density_ring(block_rect(cell).get_center())
			var kind := Art.fill_kind(local_rng.randf(), block_rect(cell).get_center().distance_to(CENTER))
			if ring == 4 and block_rect(cell).get_center().x > 4600.0:
				kind = "costa"
			if cell.x >= 65 and cell.x < 75 and cell.y >= 10 and cell.y < 14:
				kind = "aeroporto_area"
			blocks[cell] = {"loc": landmark, "kind": kind, "seed": local_rng.seed, "ring": ring, "lots": [], "chunk": coord}
			if landmark != "":
				_register_landmark(landmark)
				lots[landmark] = _make_lot(landmark, cell)
				blocks[cell]["lots"].append(landmark)
			elif kind in ["casas", "chacara"]:
				var keep := rng
				rng = local_rng
				if kind == "chacara":
					var id := "casa_%d_%d_0" % [x, y]
					lots[id] = _house_lot(id, cell, block_rect(cell).grow(-SIDEWALK), false)
					blocks[cell]["lots"].append(id)
					house_ids.append(id)
				else:
					_make_houses(cell)
				rng = keep
				for id in blocks[cell]["lots"]:
					lots[id]["seed"] = seed_chunk(coord, str(id))
					lots[id]["floors"] = local_rng.randi_range(2, 4) if ring < 2 else 1
					lots[id]["urban"] = ring < 2
					lots[id]["street"] = street_name(cell.y if lots[id]["north"] else cell.y + 1)
					lots[id]["number"] = absi(cell.x * 100 + int(str(id).get_slice("_", 3)) * 12) + 10
					Houses.register(id, "Casa %d, %s" % [lots[id]["number"], lots[id]["street"]], int(lots[id]["seed"]))
					World.locations[id]["streamed"] = true
					var map_point := to_map((lots[id]["building"] as Rect2).get_center())
					World.locations[id]["x"] = map_point.x
					World.locations[id]["y"] = map_point.y
	chunk_cells[coord] = cells
	_add_street_region(chunk_key(coord), coord * 2, coord * 2 + Vector2i(2, 2))
	return cells


func release_chunk(coord: Vector2i) -> void:
	for cell in chunk_cells.get(coord, []):
		if not blocks.has(cell):
			continue
		for id in blocks[cell]["lots"]:
			lots.erase(id)
			house_ids.erase(id)
			if not HomeSystem.has_access(id) and not LANDMARK_CELLS.has(id):
				World.locations.erase(id)
		blocks.erase(cell)
	chunk_cells.erase(coord)
	_remove_street_region(chunk_key(coord))


func _add_street_region(key: String, first: Vector2i, last: Vector2i) -> void:
	if region_nodes.has(key):
		return
	var nodes: Array = []
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			var point := Vector2i(x, y)
			nodes.append(point)
			street_refs[point] = int(street_refs.get(point, 0)) + 1
			if not street_nodes.has(point):
				street_nodes[point] = _next_node
				street_graph.add_point(_next_node, _node_pos(point))
				_next_node += 1
	for point in nodes:
		for direction in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var other: Vector2i = point + direction
			if street_nodes.has(other) and road_edge(point, other):
				street_graph.connect_points(street_nodes[point], street_nodes[other])
	region_nodes[key] = nodes


static func road_edge(a: Vector2i, b: Vector2i) -> bool:
	# A pista ocupa dez por quatro blocos; ruas seguem pelo perímetro.
	return not (a.x > 65 and a.x < 75 and b.x > 65 and b.x < 75 and a.y > 10 and a.y < 14 and b.y > 10 and b.y < 14)


func _remove_street_region(key: String) -> void:
	for point in region_nodes.get(key, []):
		street_refs[point] = int(street_refs[point]) - 1
		if int(street_refs[point]) == 0:
			street_graph.remove_point(street_nodes[point])
			street_nodes.erase(point)
			street_refs.erase(point)
	region_nodes.erase(key)


func is_prototype(c: Vector2i) -> bool:
	return urban_prototype_enabled and c == prototype_cell


func _make_market_houses() -> void:
	if not lots.has("mercado"):
		return
	prototype_cell = lots["mercado"]["cell"]
	var block := block_rect(prototype_cell)
	lots["mercado"]["rect"] = Rect2(block.position + Vector2(0, 9.8), Vector2(BLOCK, BLOCK - 9.8))
	# Fundos do mercado: três moradias reais reutilizando Houses e HouseGen.
	# O edifício e a porta do mercado permanecem exatamente nas mesmas coordenadas.
	for i in 3:
		var id := "casa_%d_%d_%d" % [prototype_cell.x, prototype_cell.y, i]
		var lr := Rect2(block.position + Vector2(SIDEWALK + i * (BLOCK - 2 * SIDEWALK) / 3.0, 0), Vector2((BLOCK - 2 * SIDEWALK) / 3.0, 9.8))
		var b := Rect2(lr.position + Vector2(0.2, 3.2), Vector2(lr.size.x - 0.4, 5.8))
		var door := Vector2(b.get_center().x + [-1.2, 0.8, -0.4][i], b.position.y)
		lots[id] = {"id": id, "cell": prototype_cell, "rect": lr, "building": b, "dir": Vector2(0, -1),
			"door": door, "door_x": door.x, "kind": "house", "seed": hash(id), "north": true,
			"door_off": door.x - b.get_center().x, "urban": true, "floors": [2, 3, 2][i]}
		blocks[prototype_cell]["lots"].push_front(id)
		house_ids.append(id)
		prototype_house_ids.append(id)


static func block_origin(c: Vector2i) -> Vector2:
	return Vector2(STREET + c.x * PITCH, STREET + c.y * PITCH)


static func block_rect(c: Vector2i) -> Rect2:
	return Rect2(block_origin(c), Vector2(BLOCK, BLOCK))


static func _line_pos(i: int) -> float:
	return i * PITCH + STREET / 2.0


func _assign() -> void:
	var ids: Array = []
	for id in World.locations:
		var loc: Dictionary = World.locations[id]
		if loc.get("interior", false) or loc.get("via", false) or loc.get("casa_generica", false) or loc.get("generated_building", false):
			continue
		ids.append(id)
	ids.sort()
	for id in ids:
		var loc: Dictionary = World.locations[id]
		var want := Vector2i(clampi(int(round((float(loc.get("x", 50)) - 10.0) / 80.0 * (GRID - 1))), 0, GRID - 1), clampi(int(round((float(loc.get("y", 50)) - 10.0) / 80.0 * (GRID - 1))), 0, GRID - 1))
		var c := _free_near(want)
		blocks[c] = {"loc": id, "lots": [id]}
		lots[id] = _make_lot(id, c)
	for x in GRID:
		for y in GRID:
			var c := Vector2i(x, y)
			if blocks.has(c):
				continue
			var r := rng.randf()
			var kind := Art.fill_kind(r)
			blocks[c] = {"loc": "", "kind": kind, "seed": rng.randi(), "lots": []}
			if kind == "casas":
				_make_houses(c)


func _free_near(want: Vector2i) -> Vector2i:
	for r in GRID * 2:
		var best := Vector2i(-1, -1)
		var best_d := 1e9
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var c := want + Vector2i(dx, dy)
				if c.x < 0 or c.y < 0 or c.x >= GRID or c.y >= GRID or blocks.has(c):
					continue
				var d := Vector2(dx, dy).length()
				if d < best_d:
					best_d = d
					best = c
		if best.x >= 0:
			return best
	return Vector2i.ZERO


func footprint_for(id: String) -> Vector2:
	var loc: Dictionary = World.locations[id]
	if id in ["hospital", "delegacia", "igreja"]:
		return FOOTPRINT[id]
	if str(loc.get("tipo", "")) == "publico":
		return Vector2.ZERO
	return FOOTPRINT.get(str(loc.get("tipo", "")), Vector2(12, 10))


func _make_lot(id: String, c: Vector2i) -> Dictionary:
	var r := block_rect(c)
	var fp := footprint_for(id)
	var lot := {"id": id, "cell": c, "rect": r, "building": Rect2(), "door_x": r.get_center().x, "dir": Vector2(0, 1), "kind": "loc"}
	if fp != Vector2.ZERO:
		var bx := r.get_center().x - fp.x / 2.0
		var bz := r.end.y - 5.0 - fp.y
		lot["building"] = Rect2(bx, bz, fp.x, fp.y)
		lot["door"] = Vector2(lot["door_x"], bz + fp.y)
	else:
		lot["door"] = Vector2(lot["door_x"], r.end.y - 2.0)
	return lot


# ---------- quarteirões residenciais ----------

func _make_houses(c: Vector2i) -> void:
	var r := block_rect(c)
	var inner := r.grow(-SIDEWALK)
	var mid := inner.position.y + inner.size.y / 2.0
	var n := 0
	for row in 2:
		var north: bool = row == 0
		var z0: float = inner.position.y if north else mid
		var z1: float = mid if north else inner.end.y
		var cuts: Array = [inner.position.x]
		var split_n := 2 if rng.randf() < 0.7 else 3
		var step := inner.size.x / split_n
		for i in range(1, split_n):
			cuts.append(inner.position.x + step * i + rng.randf_range(-1.2, 1.2))
		cuts.append(inner.end.x)
		for i in cuts.size() - 1:
			var lot_rect := Rect2(cuts[i], z0, cuts[i + 1] - cuts[i], z1 - z0)
			var id := "casa_%d_%d_%d" % [c.x, c.y, n]
			n += 1
			lots[id] = _house_lot(id, c, lot_rect, north)
			blocks[c]["lots"].append(id)
			house_ids.append(id)


func _house_lot(id: String, c: Vector2i, lot_rect: Rect2, north: bool) -> Dictionary:
	var s := RandomNumberGenerator.new()
	s.seed = hash(id) + 77
	var w := clampf(lot_rect.size.x - 3.0 - s.randf_range(0.0, 1.0), 5.8, 10.8)
	var d := clampf(s.randf_range(6.2, 8.2), 6.0, lot_rect.size.y - SETBACK - 1.2)
	var cx := lot_rect.get_center().x + s.randf_range(-0.4, 0.4)
	var bz: float = (lot_rect.position.y + SETBACK) if north else (lot_rect.end.y - SETBACK - d)
	var b := Rect2(cx - w / 2.0, bz, w, d)
	var door_off := s.randf_range(-w * 0.18, w * 0.18)
	var dir := Vector2(0, -1) if north else Vector2(0, 1)
	var door := Vector2(cx + door_off, b.position.y if north else b.end.y)
	return {"id": id, "cell": c, "rect": lot_rect, "building": b, "dir": dir, "door": door, "door_x": door.x, "kind": "house",
		"seed": hash(id), "north": north, "door_off": door_off}


func _street_name(cell: Vector2i, north: bool) -> String:
	return STREETS_H[cell.y if north else cell.y + 1]


func _register_houses() -> void:
	var per_street: Dictionary = {}
	for id in house_ids:
		var lot: Dictionary = lots[id]
		var name := _street_name(lot["cell"], lot["north"])
		var key := "%s_%d" % [name, lot["cell"].x]
		per_street[key] = int(per_street.get(key, 0)) + 1
		var number: int = (lot["cell"].x * 100 + per_street[key] * 12 + (0 if lot["north"] else 1)) + 10
		lot["number"] = number
		lot["street"] = name
		Houses.register(id, "Casa %d, %s" % [number, name], int(lot["seed"]))


func address_of(id: String) -> String:
	if lots.has(id) and lots[id].has("number"):
		return "%d, %s" % [lots[id]["number"], lots[id]["street"]]
	return ""


# ---------- consultas ----------

func lot_at(p: Vector2) -> String:
	var c := Vector2i(int(floor((p.x - STREET) / PITCH)), int(floor((p.y - STREET) / PITCH)))
	if not blocks.has(c):
		return ""
	var info: Dictionary = blocks[c]
	# Anexos acessíveis podem compartilhar o quarteirão de um marco. O lote
	# amplo do marco não pode capturar também o interior do edifício anexo.
	for id in info["lots"]:
		var footprint: Rect2 = lots[id]["building"]
		if footprint.size != Vector2.ZERO and footprint.has_point(p):
			return id
	for id in info["lots"]:
		var rr: Rect2 = lots[id]["rect"]
		if rr.grow(0.4 if info["loc"] != "" else 0.0).has_point(p):
			return id
	return ""


func in_building(id: String, p: Vector2) -> bool:
	if not lots.has(id):
		return false
	var b: Rect2 = lots[id]["building"]
	return b.size != Vector2.ZERO and b.has_point(p)


func dir_of(id: String) -> Vector2:
	return lots[id]["dir"] if lots.has(id) else Vector2(0, 1)


func door_out(id: String) -> Vector2:
	var lot: Dictionary = lots[id]
	return (lot["door"] as Vector2) + (lot["dir"] as Vector2) * (1.7 if lot["kind"] == "loc" else 1.9)


func door_in(id: String) -> Vector2:
	var lot: Dictionary = lots[id]
	var b: Rect2 = lot["building"]
	if b.size == Vector2.ZERO:
		return (lot["rect"] as Rect2).get_center()
	return (lot["door"] as Vector2) - (lot["dir"] as Vector2) * 1.8


# Um ponto livre dentro do local (para NPCs ficarem e o jogador aparecer).
func spot_in(id: String, r: RandomNumberGenerator) -> Vector2:
	var lot: Dictionary = lots[id]
	var b: Rect2 = lot["building"]
	if b.size != Vector2.ZERO:
		var inner := b.grow(-1.6)
		return Vector2(r.randf_range(inner.position.x, inner.end.x), r.randf_range(inner.position.y, inner.end.y))
	var rr: Rect2 = (lot["rect"] as Rect2).grow(-4.0)
	return Vector2(r.randf_range(rr.position.x, rr.end.x), r.randf_range(rr.position.y, rr.end.y))


# ---------- rotas ----------

# Projeta um ponto numa rua. "dir" diz para que lado está a frente do lote quando o ponto está dentro de um quarteirão.
func _to_street(p: Vector2, dir: Vector2 = Vector2(0, 1)) -> Dictionary:
	var gx := (p.x - STREET / 2.0) / PITCH
	var gy := (p.y - STREET / 2.0) / PITCH
	var cell := Vector2i(int(floor((p.x - STREET) / PITCH)), int(floor((p.y - STREET) / PITCH)))
	if blocks.has(cell) and block_rect(cell).grow(SIDEWALK * 0.4).has_point(p):
		var idx := cell.y + (1 if dir.y >= 0 else 0)
		var zl := _line_pos(idx)
		var i0 := floori(gx)
		return {"pt": Vector2(p.x, zl), "a": Vector2i(i0, idx), "b": Vector2i(i0 + 1, idx)}
	var nx := int(round(gx))
	var ny := int(round(gy))
	var dx := absf(p.x - _line_pos(nx))
	var dy := absf(p.y - _line_pos(ny))
	if dy <= dx:
		var i1 := floori(gx)
		return {"pt": Vector2(p.x, _line_pos(ny)), "a": Vector2i(i1, ny), "b": Vector2i(i1 + 1, ny)}
	var j0 := floori(gy)
	return {"pt": Vector2(_line_pos(nx), p.y), "a": Vector2i(nx, j0), "b": Vector2i(nx, j0 + 1)}


static func _node_pos(n: Vector2i) -> Vector2:
	return Vector2(_line_pos(n.x), _line_pos(n.y))


func _astar(from: Vector2i, to: Vector2i) -> Array:
	if street_nodes.has(from) and street_nodes.has(to):
		var result: Array = []
		for point in street_graph.get_point_path(street_nodes[from], street_nodes[to]):
			result.append(Vector2i(roundi((point.x - STREET * 0.5) / PITCH), roundi((point.y - STREET * 0.5) / PITCH)))
		if not result.is_empty():
			return result
	# Viagem distante fora da região renderizada: mantém percurso nas ruas,
	# sem criar/memorizar milhares de chunks para um NPC fora da câmera.
	var corner := Vector2i(to.x, from.y)
	return [from, corner, to] if corner != from and corner != to else [from, to]


# Pontos que levam alguém de dentro do lote (casa, quintal) até a calçada em frente.
func _leave_lot(id: String, p: Vector2) -> Array:
	var out: Array = []
	var lot: Dictionary = lots[id]
	var b: Rect2 = lot["building"]
	var dir: Vector2 = lot["dir"]
	if b.size != Vector2.ZERO and b.has_point(p):
		out.append(door_in(id))
		out.append(door_out(id))
	elif b.size != Vector2.ZERO:
		var behind: bool = (p - (lot["door"] as Vector2)).dot(dir) < -0.5
		if behind:
			var side_x: float = b.position.x - 1.0 if p.x < b.get_center().x else b.end.x + 1.0
			out.append(Vector2(side_x, p.y))
			out.append(Vector2(side_x, (lot["door"] as Vector2).y + dir.y * 1.2))
		out.append(door_out(id))
	return out


func _enter_lot(id: String, p: Vector2) -> Array:
	var lot: Dictionary = lots[id]
	var b: Rect2 = lot["building"]
	var out: Array = []
	if b.size != Vector2.ZERO:
		out.append(door_out(id))
		if b.has_point(p):
			out.append(door_in(id))
	return out


func route(a: Vector2, b: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var la := lot_at(a)
	var lb := lot_at(b)
	var a_in := la != "" and in_building(la, a)
	var b_in := lb != "" and in_building(lb, b)
	if la == lb and la != "":
		if a_in != b_in:
			if a_in:
				out.append(door_in(la))
				out.append(door_out(la))
			else:
				out.append(door_out(la))
				out.append(door_in(la))
		out.append(b)
		return out
	var start := a
	var dir_a := Vector2(0, 1)
	if la != "":
		dir_a = dir_of(la)
		for p in _leave_lot(la, a):
			out.append(p)
		if not out.is_empty():
			start = out[out.size() - 1]
	var tail: Array = []
	var dir_b := Vector2(0, 1)
	var end_pt := b
	if lb != "":
		dir_b = dir_of(lb)
		tail = _enter_lot(lb, b)
		if not tail.is_empty():
			end_pt = tail[0]
	var sa := _to_street(start, dir_a)
	var sb := _to_street(end_pt, dir_b)
	out.append(sa["pt"])
	var same_seg: bool = (sa["a"] == sb["a"] and sa["b"] == sb["b"])
	if not same_seg:
		var best: Array = []
		var best_len := 1e18
		for na in [sa["a"], sa["b"]]:
			for nb in [sb["a"], sb["b"]]:
				var p := _astar(na, nb)
				var length: float = (_node_pos(na) - sa["pt"]).length() + (_node_pos(nb) - sb["pt"]).length()
				for index in range(1, p.size()):
					length += _node_pos(p[index - 1]).distance_to(_node_pos(p[index]))
				if length < best_len:
					best_len = length
					best = p
		for n in best:
			out.append(_node_pos(n))
	out.append(sb["pt"])
	if tail.is_empty():
		out.append(b)
	else:
		for p in tail:
			out.append(p)
		if b.distance_to(tail[tail.size() - 1]) > 0.5:
			out.append(b)
	return out


# Converte posição no mundo para as coordenadas 0-100 do mapa (para viagens a partir da rua).
static func to_map(p: Vector2) -> Vector2:
	return p / SIZE * 100.0
