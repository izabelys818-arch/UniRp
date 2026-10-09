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
const SIDEWALK := 2.2
const SETBACK := 3.2

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


func _init() -> void:
	rng.seed = 7741
	_assign()
	_register_houses()


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
		if loc.get("interior", false) or loc.get("via", false) or loc.get("casa_generica", false):
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
		var i0 := clampi(int(floor(gx)), 0, GRID)
		return {"pt": Vector2(clampf(p.x, _line_pos(0), _line_pos(GRID)), zl), "a": Vector2i(i0, idx), "b": Vector2i(mini(i0 + 1, GRID), idx)}
	var nx := int(round(gx))
	var ny := int(round(gy))
	var dx := absf(p.x - _line_pos(nx))
	var dy := absf(p.y - _line_pos(ny))
	if dy <= dx:
		var i1 := clampi(int(floor(gx)), 0, GRID)
		var row := clampi(ny, 0, GRID)
		return {"pt": Vector2(clampf(p.x, _line_pos(0), _line_pos(GRID)), _line_pos(row)), "a": Vector2i(i1, row), "b": Vector2i(mini(i1 + 1, GRID), row)}
	var j0 := clampi(int(floor(gy)), 0, GRID)
	var col := clampi(nx, 0, GRID)
	return {"pt": Vector2(_line_pos(col), clampf(p.y, _line_pos(0), _line_pos(GRID))), "a": Vector2i(col, j0), "b": Vector2i(col, mini(j0 + 1, GRID))}


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
				var length: float = (_node_pos(na) - sa["pt"]).length() + (_node_pos(nb) - sb["pt"]).length() + (p.size() - 1) * PITCH
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
