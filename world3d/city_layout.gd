extends RefCounted

# Traçado da cidade: grade de quarteirões separados por ruas. Cada local do jogo ocupa um
# quarteirão (posição tirada das coordenadas do mapa); o resto vira casas, prédios e terrenos.
# Também calcula rotas a pé pelas ruas (A* sobre os cruzamentos).

const GRID := 8
const BLOCK := 30.0
const STREET := 10.0
const PITCH := BLOCK + STREET
const SIZE := GRID * PITCH + STREET

# Tamanho do prédio (largura x, profundidade z) por tipo/local. Vazio = local aberto.
const FOOTPRINT := {
	"bar": Vector2(14, 11), "loja": Vector2(20, 15), "comida": Vector2(14, 11),
	"hospital": Vector2(24, 18), "delegacia": Vector2(18, 13), "casa": Vector2(12, 10),
	"hospedagem": Vector2(17, 14), "igreja": Vector2(12, 18), "servico": Vector2(18, 13),
}

var blocks: Dictionary = {}      # Vector2i -> {"loc": id or "", "kind": ...}
var lots: Dictionary = {}        # loc_id -> lot dictionary
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 7741
	_assign()


static func block_origin(c: Vector2i) -> Vector2:
	return Vector2(STREET + c.x * PITCH, STREET + c.y * PITCH)


static func block_rect(c: Vector2i) -> Rect2:
	return Rect2(block_origin(c), Vector2(BLOCK, BLOCK))


func _assign() -> void:
	var ids: Array = []
	for id in World.locations:
		var loc: Dictionary = World.locations[id]
		if loc.get("interior", false) or loc.get("via", false):
			continue
		ids.append(id)
	ids.sort()
	for id in ids:
		var loc: Dictionary = World.locations[id]
		var want := Vector2i(clampi(int(float(loc.get("x", 50)) / 12.5), 0, GRID - 1), clampi(int(float(loc.get("y", 50)) / 12.5), 0, GRID - 1))
		var c := _free_near(want)
		blocks[c] = {"loc": id}
		lots[id] = _make_lot(id, c)
	for x in GRID:
		for y in GRID:
			var c := Vector2i(x, y)
			if blocks.has(c):
				continue
			var r := rng.randf()
			var kind := "casas"
			if r < 0.22:
				kind = "predio"
			elif r < 0.3:
				kind = "terreno"
			elif r < 0.36:
				kind = "estacionamento"
			elif r < 0.44:
				kind = "verde"
			blocks[c] = {"loc": "", "kind": kind, "seed": rng.randi()}


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
	var lot := {"id": id, "cell": c, "rect": r, "building": Rect2(), "door_x": r.get_center().x}
	if fp != Vector2.ZERO:
		var bx := r.get_center().x - fp.x / 2.0
		var bz := r.end.y - 5.0 - fp.y
		lot["building"] = Rect2(bx, bz, fp.x, fp.y)
	return lot


# ---------- consultas ----------

func lot_at(p: Vector2) -> String:
	var c := Vector2i(int(floor((p.x - STREET) / PITCH)), int(floor((p.y - STREET) / PITCH)))
	if not blocks.has(c):
		return ""
	if not block_rect(c).grow(0.6).has_point(p):
		return ""
	return str(blocks[c]["loc"])


func in_building(id: String, p: Vector2) -> bool:
	if not lots.has(id):
		return false
	var b: Rect2 = lots[id]["building"]
	return b.size != Vector2.ZERO and b.has_point(p)


func door_out(id: String) -> Vector2:
	var lot: Dictionary = lots[id]
	var b: Rect2 = lot["building"]
	if b.size == Vector2.ZERO:
		return Vector2(lot["door_x"], (lot["rect"] as Rect2).end.y - 2.0)
	return Vector2(lot["door_x"], b.end.y + 1.6)


func door_in(id: String) -> Vector2:
	var lot: Dictionary = lots[id]
	var b: Rect2 = lot["building"]
	if b.size == Vector2.ZERO:
		return (lot["rect"] as Rect2).get_center()
	return Vector2(lot["door_x"], b.end.y - 1.8)


# Um ponto livre dentro do local (para NPCs ficarem e o jogador aparecer).
func spot_in(id: String, r: RandomNumberGenerator) -> Vector2:
	var lot: Dictionary = lots[id]
	var b: Rect2 = lot["building"]
	if b.size != Vector2.ZERO:
		var inner := b.grow(-2.0)
		return Vector2(r.randf_range(inner.position.x, inner.end.x), r.randf_range(inner.position.y + inner.size.y * 0.35, inner.end.y))
	var rr: Rect2 = (lot["rect"] as Rect2).grow(-4.0)
	return Vector2(r.randf_range(rr.position.x, rr.end.x), r.randf_range(rr.position.y, rr.end.y))


# ---------- rotas ----------

static func _line_pos(i: int) -> float:
	return i * PITCH + STREET / 2.0


# Projeta um ponto na rua mais próxima: devolve o ponto na linha central e os dois cruzamentos.
func _to_street(p: Vector2) -> Dictionary:
	var gx := (p.x - STREET / 2.0) / PITCH
	var gy := (p.y - STREET / 2.0) / PITCH
	var nx := int(round(gx))
	var ny := int(round(gy))
	var dx := absf(p.x - _line_pos(nx))
	var dy := absf(p.y - _line_pos(ny))
	# Dentro de um quarteirão: sai pela rua de baixo (as portas ficam para +z).
	var cell := Vector2i(int(floor((p.x - STREET) / PITCH)), int(floor((p.y - STREET) / PITCH)))
	if blocks.has(cell) and block_rect(cell).has_point(p):
		var zl := _line_pos(cell.y + 1)
		var i0 := clampi(int(floor(gx)), 0, GRID)
		return {"pt": Vector2(clampf(p.x, _line_pos(0), _line_pos(GRID)), zl), "a": Vector2i(i0, cell.y + 1), "b": Vector2i(mini(i0 + 1, GRID), cell.y + 1)}
	if dy <= dx:
		var i0 := clampi(int(floor(gx)), 0, GRID)
		return {"pt": Vector2(clampf(p.x, _line_pos(0), _line_pos(GRID)), _line_pos(clampi(ny, 0, GRID))), "a": Vector2i(i0, clampi(ny, 0, GRID)), "b": Vector2i(mini(i0 + 1, GRID), clampi(ny, 0, GRID))}
	var j0 := clampi(int(floor(gy)), 0, GRID)
	return {"pt": Vector2(_line_pos(clampi(nx, 0, GRID)), clampf(p.y, _line_pos(0), _line_pos(GRID))), "a": Vector2i(clampi(nx, 0, GRID), j0), "b": Vector2i(clampi(nx, 0, GRID), mini(j0 + 1, GRID))}


static func _node_pos(n: Vector2i) -> Vector2:
	return Vector2(_line_pos(n.x), _line_pos(n.y))


func _astar(from: Vector2i, to: Vector2i) -> Array:
	var open: Array = [from]
	var came: Dictionary = {}
	var g: Dictionary = {from: 0.0}
	while not open.is_empty():
		var best_i := 0
		for i in open.size():
			if float(g[open[i]]) + (Vector2(open[i] - to)).length() < float(g[open[best_i]]) + (Vector2(open[best_i] - to)).length():
				best_i = i
		var cur: Vector2i = open[best_i]
		open.remove_at(best_i)
		if cur == to:
			var path: Array = [cur]
			while came.has(cur):
				cur = came[cur]
				path.push_front(cur)
			return path
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cur + d
			if nb.x < 0 or nb.y < 0 or nb.x > GRID or nb.y > GRID:
				continue
			var ng := float(g[cur]) + 1.0
			if not g.has(nb) or ng < float(g[nb]):
				g[nb] = ng
				came[nb] = cur
				if not nb in open:
					open.append(nb)
	return [from, to]


# Caminho de "a" até "b" (posições no chão), passando por portas e ruas.
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
	if a_in:
		out.append(door_in(la))
		out.append(door_out(la))
	var start := out[out.size() - 1] if not out.is_empty() else a
	var end_pre: Array = []
	if b_in:
		end_pre = [door_out(lb), door_in(lb)]
	var end_pt: Vector2 = end_pre[0] if not end_pre.is_empty() else b
	var sa := _to_street(start)
	var sb := _to_street(end_pt)
	out.append(sa["pt"])
	var same_seg: bool = (sa["a"] == sb["a"] and sa["b"] == sb["b"])
	if not same_seg:
		var best: Array = []
		var best_len := 1e18
		for na in [sa["a"], sa["b"]]:
			for nb in [sb["a"], sb["b"]]:
				var p := _astar(na, nb)
				var length: float = (_node_pos(na) - sa["pt"]).length() + (_node_pos(nb) - sb["pt"]).length() + (p.size() - 1) * PITCH
				if length < best_len:
					best_len = length
					best = p
		for n in best:
			out.append(_node_pos(n))
	out.append(sb["pt"])
	if end_pre.is_empty():
		out.append(b)
	else:
		out.append(end_pre[0])
		out.append(end_pre[1])
		if b.distance_to(end_pre[1]) > 0.5:
			out.append(b)
	return out


# Converte posição no mundo para as coordenadas 0-100 do mapa (para viagens a partir da rua).
static func to_map(p: Vector2) -> Vector2:
	return p / SIZE * 100.0
