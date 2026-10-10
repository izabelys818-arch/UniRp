extends "res://ui/face/face_rig.gd"

# Retrato pintado (protótipo B). Usa o mesmo rosto paramétrico do FaceRig (mesmos dados do
# criador, mesmas 18 expressões), mas sem o contorno preto: pele, cabelo e roupa são malhas 2D
# com cor por vértice. A luz vem do alto à esquerda, o volume segue um "normal" de elipsoide e
# as feições (órbitas, nariz, maçãs, queixo, mandíbula) entram como sombras e luzes suaves.
# As bordas ganham um traço fino antisserrilhado no tom da própria cor, nunca preto.
# A idade muda a base do rosto (criança, adolescente, adulto, idoso) sem mudar os dados salvos.

const LIGHT_DIR := Vector3(-0.52, -0.5, 0.69)
const RIM_COL := Color(0.58, 0.68, 0.95)
const LASH := Color(0.12, 0.075, 0.07)
const SCLERA := Color(0.93, 0.9, 0.86)
const MOUTH_IN := Color(0.2, 0.06, 0.07)

var _L: Vector3 = LIGHT_DIR.normalized()
var _pal: Dictionary = {}
var _feats: Array = []
var _cache: Dictionary = {}
var _hs: Dictionary = {}
var _recording = null  # Array enquanto grava uma camada estática; null fora disso


# ---------- camadas estáticas gravadas ----------
# O que não muda com a expressão (fundo, corpo, cabelo, barba, rugas) é calculado uma vez por
# aparência: as chamadas de desenho ficam gravadas e nos quadros seguintes só são repetidas.

func _emit(fn: StringName, args: Array) -> void:
	if _recording != null:
		(_recording as Array).append([fn, args])
	callv(fn, args)


func _cached(key: String, fn: Callable) -> void:
	var k := "rec:" + key
	if _cache.has(k):
		for op in _cache[k]:
			callv(op[0], op[1])
		return
	var prev = _recording
	var ops: Array = []
	_recording = ops
	fn.call()
	_recording = prev
	if prev != null:
		(prev as Array).append_array(ops)
	_cache[k] = ops


func _tri_raw(idx: PackedInt32Array, pts: PackedVector2Array, cols: PackedColorArray) -> void:
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, pts, cols)


func _dtri(idx: PackedInt32Array, pts: PackedVector2Array, cols: PackedColorArray) -> void:
	_emit(&"_tri_raw", [idx, pts, cols])


func _dpl(pts: PackedVector2Array, col: Color, w: float = -1.0, aa: bool = false) -> void:
	_emit(&"draw_polyline", [pts, col, w, aa])


func _dplc(pts: PackedVector2Array, cols: PackedColorArray, w: float = -1.0, aa: bool = false) -> void:
	_emit(&"draw_polyline_colors", [pts, cols, w, aa])


func _dpg(pts: PackedVector2Array, cols: PackedColorArray) -> void:
	_emit(&"draw_polygon", [pts, cols])


func _dci(c: Vector2, r: float, col: Color, filled: bool = true, w: float = -1.0, aa: bool = false) -> void:
	_emit(&"draw_circle", [c, r, col, filled, w, aa])


func _dar(c: Vector2, r: float, a0: float, a1: float, n: int, col: Color, w: float = -1.0, aa: bool = false) -> void:
	_emit(&"draw_arc", [c, r, a0, a1, n, col, w, aa])


func _dre(r: Rect2, col: Color) -> void:
	_emit(&"draw_rect", [r, col])


func _dli(a: Vector2, b: Vector2, col: Color, w: float = -1.0, aa: bool = false) -> void:
	_emit(&"draw_line", [a, b, col, w, aa])


func _dcp(pts: PackedVector2Array, col: Color) -> void:
	_emit(&"draw_colored_polygon", [pts, col])


func _poly(pts: PackedVector2Array, color: Color) -> void:
	if pts.size() < 3 or color.a <= 0.01:
		return
	if Geometry2D.triangulate_polygon(pts).is_empty():
		return
	_dcp(pts, color)


func _line(pts: PackedVector2Array, color: Color, w: float) -> void:
	if pts.size() >= 2 and color.a > 0.01:
		_dpl(pts, color, w, true)


# ---------- dados ----------

static func age_stage(age: int) -> String:
	if age < 13:
		return "crianca"
	if age < 18:
		return "adolescente"
	if age < 60:
		return "adulto"
	return "idoso"


func set_look(l: Dictionary) -> void:
	look = _age_adjusted(l)
	body_lift = 22.0 * float(look["_kid"]) + 8.0 * float(look["_teen"])
	_cache.clear()
	_pal.clear()
	queue_redraw()


# A base de proporção de cada faixa de idade: criança com rosto mais curto e redondo, olhos
# maiores e mais baixos, nariz e queixo pequenos, pescoço e ombros estreitos; idoso com a
# mandíbula caída, maçãs murchas e cabelo grisalho.
func _age_adjusted(l: Dictionary) -> Dictionary:
	var o := l.duplicate()
	var age := int(o.get("age", 30))
	var kid := clampf((14.0 - float(age)) / 8.0, 0.0, 1.0)
	var teen := clampf((19.0 - float(age)) / 6.0, 0.0, 1.0) * (1.0 - kid)
	var old := clampf((float(age) - 42.0) / 38.0, 0.0, 1.0)
	var young := maxf(kid, teen * 0.45)
	if young > 0.0:
		o["face_len"] = float(o.get("face_len", 1.0)) * (1.0 - 0.17 * young)
		o["face_w"] = float(o.get("face_w", 1.0)) * (1.0 + 0.03 * young)
		o["cheek"] = float(o.get("cheek", 1.0)) * (1.0 + 0.07 * young)
		o["jaw"] = lerpf(float(o.get("jaw", 0.78)), 0.8, young)
		o["chin_w"] = lerpf(float(o.get("chin_w", 0.34)), 0.48, young)
		o["eye_size"] = float(o.get("eye_size", 1.0)) * (1.0 + 0.3 * young)
		o["face_w"] = float(o.get("face_w", 1.0)) * (1.0 + 0.04 * young)
		o["nose_len"] = float(o.get("nose_len", 1.0)) * (1.0 - 0.32 * young)
		o["nose_w"] = float(o.get("nose_w", 1.0)) * (1.0 - 0.16 * young)
		o["lips"] = float(o.get("lips", 1.0)) * (1.0 - 0.1 * young)
		o["neck"] = float(o.get("neck", 1.0)) * (1.0 - 0.12 * young)
		o["shoulders"] = float(o.get("shoulders", 1.0)) * (1.0 - 0.3 * young)
		if kid > 0.0 or teen > 0.6:
			o["shadow_beard"] = false
			o["adams_apple"] = false
		if kid > 0.0:
			o["beard"] = "none"
			o["lashes"] = false
	if old > 0.0:
		o["jaw"] = float(o.get("jaw", 0.78)) + 0.05 * old
		o["chin_w"] = float(o.get("chin_w", 0.34)) + 0.03 * old
		o["cheek"] = float(o.get("cheek", 1.0)) * (1.0 - 0.03 * old)
		o["lips"] = float(o.get("lips", 1.0)) * (1.0 - 0.18 * old)
	# rosto menos em "V": mandíbula e queixo um pouco mais cheios no retrato pintado
	o["jaw"] = lerpf(float(o.get("jaw", 0.78)), 0.88, 0.28)
	o["chin_w"] = maxf(float(o.get("chin_w", 0.34)) * 1.12, 0.36)
	o["_kid"] = kid
	o["_teen"] = teen
	o["_old"] = old
	return o


func _W() -> float:
	return 72.0 * float(_l("face_w", 1.0))


func _H() -> float:
	return 102.0 * float(_l("face_len", 1.0))


func _eye_center(side: int) -> Vector2:
	var kid := float(_l("_kid", 0.0))
	return C + Vector2(side * _W() * (0.42 - 0.03 * kid), _H() * (-0.04 + 0.06 * kid))


func _hair_color() -> Color:
	var hc: Color = _l("hair_color", Color("#2a1d16"))
	var grey := clampf((float(_l("age", 30)) - 50.0) / 32.0, 0.0, 1.0) * 0.65
	return hc.lerp(Color("#cdc8c0"), grey)


# ---------- paleta e feições (uma vez por aparência) ----------

func _prep() -> void:
	if not _pal.is_empty():
		return
	var skin: Color = _l("skin", Color("#e8bf9c"))
	skin = Color.from_hsv(skin.h, minf(1.0, skin.s * 1.1), skin.v)
	var lum := skin.get_luminance()
	var shadow := skin.darkened(0.42 - lum * 0.12).lerp(Color(0.36, 0.15, 0.18), 0.2).lerp(Color(0.14, 0.18, 0.32), 0.05)
	_pal["base"] = skin
	_pal["shadow"] = shadow
	_pal["sss"] = skin.lerp(Color(0.9, 0.34, 0.24), 0.36)
	_pal["hi"] = skin.lightened(0.17 + (0.12 if lum < 0.3 else 0.0)).lerp(Color(1.0, 0.96, 0.9), 0.14)
	_pal["line"] = shadow.darkened(0.42)
	_pal["blush"] = skin.lerp(Color(0.86, 0.34, 0.36), 0.42)
	_pal["lid"] = skin.lerp(shadow, 0.28).lerp(Color(0.6, 0.35, 0.4), 0.08)
	var hc := _hair_color()
	var hl := hc.get_luminance()
	_pal["hair"] = hc
	_pal["hair_dark"] = hc.darkened(0.55).lerp(Color(0.08, 0.08, 0.14), 0.25)
	_pal["hair_hi"] = hc.lightened(0.32 if hl > 0.15 else 0.22).lerp(Color(0.72, 0.76, 0.86), 0.18 if hl < 0.2 else 0.05)
	var beard := str(_l("beard", "none"))
	var bk := 0.0
	if beard == "stubble":
		bk = 0.5
	elif beard in ["full", "long", "goatee", "mustache", "short", "mustache_thin"]:
		bk = 0.3
	elif _l("shadow_beard", false):
		bk = 0.2
	_pal["beard_k"] = bk
	var bc: Color = _l("beard_color", hc)
	_pal["beard"] = bc
	_pal["beard_dark"] = bc.darkened(0.55).lerp(Color(0.08, 0.08, 0.14), 0.25)
	_pal["beard_hi"] = bc.lightened(0.3 if bc.get_luminance() > 0.15 else 0.2)
	_pal["beard_col"] = bc.darkened(0.25).lerp(shadow, 0.35)
	_hs = _hair_spec()
	_build_feats()


func _build_feats() -> void:
	var sh: Color = _pal["shadow"]
	var hi: Color = _pal["hi"]
	var w := _W()
	var h := _H()
	var old := float(_l("_old", 0.0))
	var kid := float(_l("_kid", 0.0))
	var hollow := 0.25 if _l("hollow", false) else 0.0
	var circles := 0.35 if 9 in _l("marks", []) else 0.0
	var f: Array = []
	for side in [-1, 1]:
		var lit: bool = side == -1
		var e := _eye_center(side)
		f.append([e + Vector2(side * 2, -3), Vector2(w * 0.35, h * 0.155), sh, 0.4 + 0.15 * old - 0.15 * kid])
		f.append([e + Vector2(0, h * 0.1), Vector2(w * 0.21, h * 0.05), sh.lerp(Color(0.3, 0.16, 0.3), 0.3), 0.14 + 0.32 * old + circles])
		f.append([e + Vector2(side * w * 0.04, -h * 0.17), Vector2(w * 0.27, h * 0.05), hi, 0.3 if lit else 0.1])
		f.append([_rel(side * 0.52, 0.15), Vector2(w * 0.25, h * 0.085), hi, 0.34 if lit else 0.08])
		f.append([_rel(side * 0.5, 0.28), Vector2(w * 0.25, h * 0.11), _pal["blush"], 0.16 + 0.12 * kid])
		f.append([_rel(side * 0.64, 0.45), Vector2(w * 0.21, h * 0.15), sh, 0.12 + 0.2 * old + hollow])
		f.append([_rel(side * 0.86, -0.42), Vector2(w * 0.18, h * 0.22), sh, 0.14 + 0.1 * old])
	var tip := _nose_tip()
	var nw := 9.0 * float(_l("nose_w", 1.0))
	var top_y := _eye_center(1).y
	var nl := tip.y - top_y
	f.append([Vector2(C.x + nw * 0.8, top_y + nl * 0.55), Vector2(nw * 0.62, nl * 0.55), sh, 0.5 - 0.2 * kid])
	f.append([Vector2(C.x - nw * 0.3, top_y + nl * 0.5), Vector2(nw * 0.32, nl * 0.45), hi, 0.34])
	f.append([tip + Vector2(-1, -2), Vector2(nw * 0.95, 6.5), _pal["blush"], 0.24])
	f.append([tip + Vector2(1, 9), Vector2(nw * 1.5, 5.5), sh, 0.48])
	var my := _mouth_y()
	f.append([Vector2(C.x, my + 11), Vector2(w * 0.23, 5.5), sh, 0.42])
	f.append([Vector2(C.x, my - 8), Vector2(w * 0.07, 6), sh, 0.14])
	f.append([_rel(-0.06, 0.88), Vector2(w * 0.23, h * 0.07), hi, 0.26])
	f.append([_rel(0.56, 0.72), Vector2(w * 0.42, h * 0.28), sh, 0.24])
	f.append([_rel(-0.28, -0.58), Vector2(w * 0.42, h * 0.18), hi, 0.24])
	if _hs.get("cap", false):
		f.append([_rel(-0.05, -float(_hs["height"]) + 0.05), Vector2(w * 0.95, h * 0.09), sh, 0.3])
	_feats = f


func _skin_at(p: Vector2) -> Color:
	var w := _W()
	var h := _H()
	var q := Vector2((p.x - C.x) / (w * 1.04), (p.y - C.y + h * 0.04) / (h * 1.06))
	var r2 := minf(q.length_squared(), 1.0)
	var nz := sqrt(1.0 - r2)
	var n := Vector3(q.x * 1.15, q.y * 0.8, nz * 1.1).normalized()
	var d := n.dot(_L)
	var lit := smoothstep(0.02, 0.7, d)
	var col: Color = (_pal["shadow"] as Color).lerp(_pal["base"], lit)
	col = col.lerp(_pal["sss"], 0.3 * clampf(1.0 - absf(lit - 0.45) * 2.2, 0.0, 1.0))
	col = col.lerp(_pal["hi"], smoothstep(0.8, 0.99, d) * 0.55)
	var rim := pow(1.0 - nz, 3.0) * clampf(q.x * 1.6, 0.0, 1.0)
	col = col.lerp(RIM_COL, rim * 0.28)
	for f in _feats:
		var k := ((p - (f[0] as Vector2)) / (f[1] as Vector2)).length_squared()
		if k < 1.0:
			var a := 1.0 - k
			col = col.lerp(f[2], float(f[3]) * a * a)
	var bk: float = _pal["beard_k"]
	if bk > 0.0:
		var bw := _beard_w(p)
		if bw > 0.0:
			col = col.lerp(_pal["beard_col"], bw * bk)
	return col


# Quanto da pele é coberta pela barba (0..1): mandíbula, queixo e buço, sem os lábios.
func _beard_w(p: Vector2) -> float:
	var x := absf(p.x - C.x) / _W()
	var y := (p.y - C.y) / _H()
	var nose_b := (_nose_tip().y - C.y) / _H() + 0.07
	var line := lerpf(nose_b, -0.08, smoothstep(0.32, 0.95, x))
	var wv := smoothstep(line, line + 0.12, y)
	var my := (_mouth_y() - C.y) / _H()
	var m := Vector2(x / (0.36 * float(cur["mouth_width"])), (y - my - 0.015) / 0.055).length()
	wv *= smoothstep(0.85, 1.25, m)
	return wv


# ---------- malhas com cor por vértice ----------

func _ring_mesh(outline: PackedVector2Array, center: Vector2, rings: Array, shade: Callable) -> Dictionary:
	var pts := PackedVector2Array([center])
	var cols := PackedColorArray([shade.call(center)])
	var idx := PackedInt32Array()
	var n := outline.size()
	for r in range(1, rings.size()):
		var fr: float = rings[r]
		for i in n:
			var p := center + (outline[i] - center) * fr
			pts.append(p)
			cols.append(shade.call(p))
	for i in n:
		idx.append_array(PackedInt32Array([0, 1 + i, 1 + (i + 1) % n]))
	for r in range(1, rings.size() - 1):
		var a := 1 + (r - 1) * n
		var b := 1 + r * n
		for i in n:
			var j := (i + 1) % n
			idx.append_array(PackedInt32Array([a + i, b + i, b + j, a + i, b + j, a + j]))
	var edge := PackedColorArray()
	for i in n:
		edge.append(cols[1 + (rings.size() - 2) * n + i])
	return {"p": pts, "c": cols, "i": idx, "edge": edge, "outline": outline}


func _strip(a: PackedVector2Array, b: PackedVector2Array, rows: int, shade: Callable, fade_a: float = 0.0, fade_b: float = 0.0) -> Dictionary:
	var n := mini(a.size(), b.size())
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for r in rows + 1:
		var t := float(r) / rows
		for i in n:
			var p := a[i].lerp(b[i], t)
			pts.append(p)
			var col: Color = shade.call(p)
			if fade_a > 0.0:
				col.a *= smoothstep(0.0, fade_a, t)
			if fade_b > 0.0:
				col.a *= smoothstep(1.0, 1.0 - fade_b, t)
			cols.append(col)
	for r in rows:
		for i in n - 1:
			var k := r * n + i
			idx.append_array(PackedInt32Array([k, k + 1, k + n + 1, k, k + n + 1, k + n]))
	return {"p": pts, "c": cols, "i": idx, "n": n, "rows": rows}


func _mesh_draw(m: Dictionary, tint: Color = Color(1, 1, 1, 1)) -> void:
	if m.is_empty() or (m["i"] as PackedInt32Array).is_empty():
		return
	var cols: PackedColorArray = m["c"]
	if tint != Color(1, 1, 1, 1):
		cols = cols.duplicate()
		for i in cols.size():
			cols[i] = cols[i] * tint
	_dtri(m["i"], m["p"], cols)


func _overlay(m: Dictionary, col: Color) -> void:
	var cols := PackedColorArray()
	cols.resize((m["p"] as PackedVector2Array).size())
	cols.fill(col)
	_dtri(m["i"], m["p"], cols)


# contorno da malha em faixa: lado a, ponta, lado b e volta
func _strip_edge(m: Dictionary, dark: float, alpha: float, width: float = 1.1, sides: String = "ab") -> void:
	var n: int = m["n"]
	var rows: int = m["rows"]
	var p: PackedVector2Array = m["p"]
	var c: PackedColorArray = m["c"]
	var lines: Array = []
	if "a" in sides:
		var o: Array = []
		for i in n:
			o.append(i)
		lines.append(o)
	if "b" in sides:
		var o2: Array = []
		for i in n:
			o2.append(rows * n + i)
		lines.append(o2)
	if "e" in sides:
		var o3: Array = []
		var o4: Array = []
		for r in rows + 1:
			o3.append(r * n)
			o4.append(r * n + n - 1)
		lines.append(o3)
		lines.append(o4)
	for order in lines:
		var ep := PackedVector2Array()
		var ec := PackedColorArray()
		for k in order:
			ep.append(p[k])
			var col: Color = c[k].darkened(dark)
			col.a = alpha * c[k].a
			ec.append(col)
		_dplc(ep, ec, width, true)


# Brilho/sombra suave: leque com cor no centro e transparente na borda.
func _glow(c: Vector2, rx: float, ry: float, col: Color, segs: int = 24) -> void:
	var pts := PackedVector2Array([c])
	var cols := PackedColorArray([col])
	var clear := Color(col, 0.0)
	var idx := PackedInt32Array()
	for i in segs:
		var a := TAU * i / segs
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		cols.append(clear)
		idx.append_array(PackedInt32Array([0, 1 + i, 1 + (i + 1) % segs]))
	_dtri(idx, pts, cols)


func _fill(pts: PackedVector2Array, col: Color, edge_alpha: float = 1.0) -> void:
	if pts.size() < 3:
		return
	_poly(pts, col)
	if edge_alpha > 0.0:
		_dpl(_closed(pts), Color(col, col.a * edge_alpha), 1.0, true)


func _gfill(pts: PackedVector2Array, cols: PackedColorArray, edge_dark: float = 0.0) -> void:
	if pts.size() < 3 or Geometry2D.triangulate_polygon(pts).is_empty():
		return
	_dpg(pts, cols)
	var ep := _closed(pts)
	var ec := cols.duplicate()
	ec.append(cols[0])
	if edge_dark > 0.0:
		for i in ec.size():
			ec[i] = ec[i].darkened(edge_dark)
	_dplc(ep, ec, 1.0, true)


# traço afinando nas pontas (w0 → w1), com borda suave
func _ribbon(path: PackedVector2Array, w0: float, w1: float) -> Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in path.size():
		var a := path[maxi(i - 1, 0)]
		var b := path[mini(i + 1, path.size() - 1)]
		var nrm := (b - a).orthogonal().normalized()
		var w := lerpf(w0, w1, float(i) / maxf(1.0, path.size() - 1.0)) * 0.5
		left.append(path[i] + nrm * w)
		right.append(path[i] - nrm * w)
	return [left, right]


func _stroke(path: PackedVector2Array, w0: float, w1: float, col: Color) -> void:
	if path.size() < 2:
		return
	var rb := _ribbon(path, w0, w1)
	var m := _strip(rb[0], rb[1], 1, func(_p): return col)
	_mesh_draw(m)
	_dpl(rb[0], Color(col, col.a * 0.6), 0.8, true)
	_dpl(rb[1], Color(col, col.a * 0.6), 0.8, true)


# mecha: faixa afinando com a cor do cabelo por vértice e um fio de luz
func _mecha(path: PackedVector2Array, w0: float, w1: float, darken: float = 0.0) -> void:
	var rb := _ribbon(path, w0, w1)
	var m := _strip(rb[0], rb[1], 2, func(p): return _hair_at(p).darkened(darken))
	_mesh_draw(m)
	_strip_edge(m, 0.3, 0.55, 0.9, "ab")
	_soft_line(_offset_path(path, -w0 * 0.15, -w1 * 0.1), Color(_pal["hair_hi"], 0.28), 1.0)


func _soft_line(path: PackedVector2Array, col: Color, w: float) -> void:
	if path.size() >= 2 and col.a > 0.01:
		_dpl(path, col, w, true)


func _catmull_open(pts: Array, n: int) -> PackedVector2Array:
	# curva suave pelos pontos de controle, reamostrada em n+1 pontos
	var dense := PackedVector2Array()
	var m := pts.size()
	for i in m - 1:
		var p0: Vector2 = pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, m - 1)]
		for s in 12:
			var u := float(s) / 12.0
			var u2 := u * u
			var u3 := u2 * u
			dense.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3))
	dense.append(pts[m - 1])
	var lens := PackedFloat32Array([0.0])
	for i in range(1, dense.size()):
		lens.append(lens[i - 1] + dense[i].distance_to(dense[i - 1]))
	var total := lens[lens.size() - 1]
	var out := PackedVector2Array()
	var j := 0
	for k in n + 1:
		var target := total * float(k) / n
		while j < lens.size() - 2 and lens[j + 1] < target:
			j += 1
		var seg := maxf(lens[j + 1] - lens[j], 0.0001)
		out.append(dense[j].lerp(dense[j + 1], clampf((target - lens[j]) / seg, 0.0, 1.0)))
	return out


func _resample_closed(pts: PackedVector2Array, n: int) -> PackedVector2Array:
	var arr: Array = Array(pts)
	arr.append(pts[0])
	var out := _catmull_open(arr, n)
	out.remove_at(out.size() - 1)
	return out


# ---------- cenário (fundo desfocado) ----------

func _draw_scene() -> void:
	_cached("cena:" + scene, _scene_body)


func _scene_body() -> void:
	var pal: Array = SCENE_COLORS.get(scene, SCENE_COLORS["vazio"])
	var wall: Color = pal[0]
	var dark: Color = pal[1]
	var light: Color = pal[2]
	var rng := RandomNumberGenerator.new()
	rng.seed = scene.hash()
	var r := PackedVector2Array([Vector2(0, 0), Vector2(300, 0), Vector2(300, 400), Vector2(0, 400)])
	_dpg(r, PackedColorArray([wall.lightened(0.1), wall.darkened(0.05), dark.lerp(wall, 0.25), dark.lerp(wall, 0.45)]))
	match scene:
		"casa":
			for x in range(0, 300, 18):
				_dre(Rect2(x, 0, 8, 300), Color(wall.lightened(0.08), 0.35))
			_soft_rect(Rect2(198, 34, 80, 108), Color("#1a2a4a"), 6.0)
			_glow(Vector2(238, 88), 70, 70, Color(0.35, 0.45, 0.7, 0.18))
			_dre(Rect2(236, 34, 3, 108), Color(dark, 0.6))
			_soft_rect(Rect2(18, 56, 52, 42), Color("#6a5236"), 3.0)
			_glow(Vector2(44, 40), 90, 70, Color(light, 0.22))
			_dre(Rect2(0, 300, 300, 100), Color(dark, 0.9))
		"bar":
			for row in [62, 132]:
				_dre(Rect2(0, row, 300, 8), Color(dark.darkened(0.3), 0.8))
				for i in 15:
					var x := 6 + i * 19 + rng.randf_range(-3, 3)
					var hh := rng.randf_range(26, 44)
					var col: Color = [Color("#2f5a3a"), Color("#6b3a1e"), Color("#a8892c"), Color("#3a2a4a")][rng.randi() % 4]
					_soft_rect(Rect2(x, row - hh, 10, hh), col.darkened(0.1), 2.0)
					_glow(Vector2(x + 4, row - hh * 0.6), 5, hh * 0.3, Color(light, 0.12))
			for i in 7:
				_glow(Vector2(rng.randf_range(0, 300), rng.randf_range(10, 200)), 16, 16, Color(light, 0.12))
			_dre(Rect2(0, 296, 300, 104), Color(dark, 0.95))
			_dre(Rect2(0, 294, 300, 6), Color(light, 0.18))
		"rua", "beco":
			for i in 7:
				var x := i * 46 + rng.randf_range(-6, 6)
				var hh := rng.randf_range(120, 260)
				_dre(Rect2(x, 300 - hh, 44, hh), dark.lerp(wall, rng.randf_range(0.1, 0.4)))
				for wy in range(int(300 - hh + 12), 290, 22):
					for wx in [x + 8, x + 26]:
						if rng.randf() < 0.32:
							_glow(Vector2(wx + 4, wy + 5), 9, 9, Color(light, 0.35))
			_dre(Rect2(0, 300, 300, 100), Color("#15161a"))
			_glow(Vector2(32, 90), 70, 60, Color(light, 0.28))
			for i in 9:
				_glow(Vector2(rng.randf_range(0, 300), rng.randf_range(60, 280)), 7, 7, Color(light, 0.25))
		"parque":
			_glow(Vector2(236, 60), 60, 60, Color(light, 0.25))
			for i in 9:
				var x := rng.randf_range(-20, 320)
				var rr := rng.randf_range(40, 80)
				_glow(Vector2(x, rng.randf_range(140, 230)), rr, rr * 1.2, Color(dark.lightened(rng.randf_range(0.05, 0.15)), 0.9))
			_dre(Rect2(0, 290, 300, 110), Color("#0f160f"))
		_:
			for i in 6:
				_soft_rect(Rect2(rng.randf_range(0, 240), rng.randf_range(20, 240), rng.randf_range(30, 80), rng.randf_range(30, 90)), Color(dark, 0.45), 8.0)
			_glow(Vector2(60, 40), 110, 80, Color(light, 0.22))
			_dre(Rect2(0, 300, 300, 100), Color(dark, 0.9))
	# névoa de profundidade: empurra o fundo para trás e deixa o rosto em foco
	_dre(Rect2(0, 0, 300, 400), Color(wall.lerp(dark, 0.5), 0.28))
	_glow(Vector2(150, 190), 170, 170, Color(0, 0, 0, 0.0))


func _soft_rect(rc: Rect2, col: Color, blur: float) -> void:
	for i in 3:
		var g := blur * (3 - i) / 3.0
		_dre(rc.grow(g), Color(col, col.a * 0.18))
	_dre(rc, col)


func _draw_mood() -> void:
	if vignette_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0))
		g.set_color(1, Color(0, 0, 0, 0.9))
		g.add_point(0.6, Color(0, 0, 0, 0.08))
		g.add_point(0.82, Color(0, 0, 0, 0.5))
		vignette_tex = GradientTexture2D.new()
		vignette_tex.gradient = g
		vignette_tex.fill = GradientTexture2D.FILL_RADIAL
		vignette_tex.fill_from = Vector2(0.45, 0.4)
		vignette_tex.fill_to = Vector2(1.05, 1.0)
	draw_texture_rect(vignette_tex, Rect2(Vector2.ZERO, size), false)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(t * 15.0)
	for i in 240:
		var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		draw_rect(Rect2(p, Vector2(1, 1)), Color(1, 1, 1, 0.035) if i % 2 == 0 else Color(0, 0, 0, 0.08))


# ---------- corpo e roupa ----------

func _cloth_pal(c: Color) -> Array:
	var lum := c.get_luminance()
	return [c.darkened(0.5 - lum * 0.15).lerp(Color(0.12, 0.14, 0.24), 0.12), c, c.lightened(0.16 + (0.1 if lum < 0.15 else 0.0))]


func _cloth_at(p: Vector2, pal: Array) -> Color:
	var q := Vector2((p.x - 150.0) / 175.0, (p.y - 300.0) / 120.0)
	var lit := clampf(0.66 - q.x * 0.6 - maxf(q.y, 0.0) * 0.3, 0.0, 1.0)
	var col: Color = (pal[0] as Color).lerp(pal[1], smoothstep(0.0, 0.75, lit))
	var shoulder := clampf(1.0 - absf(p.y - 285.0) / 30.0, 0.0, 1.0) * clampf(0.5 - q.x, 0.0, 1.0)
	col = col.lerp(pal[2], shoulder * 0.55)
	for side in [-1, 1]:
		var k := ((p - Vector2(150 + side * 100, 345)) / Vector2(32, 60)).length_squared()
		if k < 1.0:
			col = col.lerp(pal[0], 0.35 * (1.0 - k) * (1.0 - k))
	var neck_k := ((p - Vector2(150, 268)) / Vector2(60, 26)).length_squared()
	if neck_k < 1.0:
		col = col.lerp(pal[0], 0.4 * (1.0 - neck_k))
	return col


func _skin_flat_at(p: Vector2, x0: float, x1: float) -> Color:
	var u := clampf((p.x - x0) / maxf(x1 - x0, 1.0), 0.0, 1.0)
	return (_pal["base"] as Color).lerp(_pal["shadow"], smoothstep(0.35, 1.0, u))


func _draw_body() -> void:
	_prep()
	_cached("corpo", _body_body)


func _body_body() -> void:
	var cc: Array = _clothes_colors()
	var c1: Color = cc[0]
	var c2: Color = cc[1]
	var style := str(_l("clothes", "camiseta"))
	var nk := float(_l("neck", 1.0))
	var female := str(_l("gender", "")) == "mulher"
	var nx := 70.0 * float(_l("face_w", 1.0)) * HS * 0.42 * nk * (1.22 if female else 1.38)
	var old := float(_l("_old", 0.0))
	# pescoço: lado esquerdo na luz, sombra da cabeça embaixo do queixo
	var neck := PackedVector2Array([Vector2(150 - nx, 196), Vector2(150 + nx, 196), Vector2(150 + nx * 1.15, 278), Vector2(150 - nx * 1.15, 278)])
	var ncol := PackedColorArray()
	for p in neck:
		ncol.append(_skin_flat_at(p, 150 - nx * 1.1, 150 + nx * 1.1))
	_gfill(neck, ncol, 0.2)
	var shadow_band := PackedVector2Array([Vector2(150 - nx * 1.02, 196), Vector2(150 + nx * 1.02, 196), Vector2(150 + nx * 1.05, 238), Vector2(150 - nx * 1.05, 230)])
	var sh: Color = _pal["shadow"]
	_dpg(shadow_band, PackedColorArray([Color(sh, 0.85), Color(sh, 0.9), Color(sh, 0.0), Color(sh, 0.0)]))
	for side in [-1, 1]:
		_soft_line(_quad(Vector2(150 + side * nx * 0.75, 226), Vector2(150 + side * nx * 0.45, 252), Vector2(150 + side * nx * 0.12, 274), 8), Color(_pal["line"], 0.12 + 0.2 * old), 1.4)
	if _l("adams_apple", false):
		_glow(Vector2(150, 252), 6, 5, Color(_pal["hi"], 0.5))
		_soft_line(_quad(Vector2(145, 256), Vector2(150, 259), Vector2(155, 256), 6), Color(_pal["line"], 0.3), 1.2)
	if 1 in _l("marks", []):
		var ink := Color(0.15, 0.22, 0.32, 0.75)
		_soft_line(PackedVector2Array([Vector2(158, 236), Vector2(166, 244), Vector2(160, 252), Vector2(168, 258)]), ink, 2.2)
		_dar(Vector2(140, 248), 5, 0, TAU, 16, ink, 1.6, true)
	var torso_pts: Array = [Vector2(-8, 440), Vector2(-4, 352), Vector2(10, 318), Vector2(36, 296), Vector2(76, 282), Vector2(150 - nx * 1.6, 266), Vector2(150 - nx, 258)]
	var right: Array = []
	for i in range(torso_pts.size() - 1, -1, -1):
		var q: Vector2 = torso_pts[i]
		right.append(Vector2(300.0 - q.x, q.y))
	torso_pts.append_array(right)
	var outline := _catmull_open(torso_pts, 70)
	outline.remove_at(outline.size() - 1)
	if style == "regata" or style == "cobertor":
		_body_special(style, outline, c1, nx)
		return
	var key := "torso"
	if not _cache.has(key):
		var pal := _cloth_pal(c1)
		_cache[key] = _ring_mesh(outline, Vector2(150, 355), [0.0, 0.3, 0.55, 0.75, 0.9, 1.0], func(p): return _cloth_at(p, pal))
	var tm: Dictionary = _cache[key]
	_mesh_draw(tm)
	var ec: PackedColorArray = (tm["edge"] as PackedColorArray).duplicate()
	var ep := _closed(outline)
	ec.append(ec[0])
	for i in ec.size():
		ec[i] = ec[i].darkened(0.3)
	_dplc(ep, ec, 1.3, true)
	var dk: Color = _cloth_pal(c1)[0]
	# dobras do tecido
	for side in [-1, 1]:
		_soft_line(_quad(Vector2(150 + side * 96, 300), Vector2(150 + side * 102, 350), Vector2(150 + side * 106, 400), 10), Color(dk, 0.5), 2.0)
	_soft_line(_quad(Vector2(118, 332), Vector2(130, 348), Vector2(124, 366), 8), Color(dk, 0.3), 1.6)
	_soft_line(_quad(Vector2(184, 330), Vector2(172, 350), Vector2(180, 370), 8), Color(dk, 0.35), 1.6)
	_body_details(style, c1, c2, nx)
	if 12 in _l("marks", []):
		var gold := Color("#d4a72c")
		_soft_line(_quad(Vector2(150 - nx * 1.2, 258), Vector2(150, 298), Vector2(150 + nx * 1.2, 258), 18), gold.darkened(0.3), 3.2)
		_soft_line(_quad(Vector2(150 - nx * 1.2, 257), Vector2(150, 296), Vector2(150 + nx * 1.2, 257), 18), gold.lightened(0.2), 1.2)
	if "toalha" in _l("extras", []):
		var towel := PackedVector2Array([Vector2(196, 264), Vector2(240, 276), Vector2(246, 330), Vector2(210, 334)])
		_gfill(towel, PackedColorArray([Color(0.9, 0.87, 0.78), Color(0.8, 0.77, 0.68), Color(0.62, 0.6, 0.55), Color(0.72, 0.7, 0.62)]), 0.2)
	if "fone" in _l("extras", []):
		_soft_line(_quad(Vector2(108, 246), Vector2(150, 285), Vector2(192, 246), 16), Color(0.1, 0.1, 0.12), 5.0)
		for x in [108, 192]:
			_fill(_ellipse(Vector2(x, 246), 13, 15), Color(0.17, 0.17, 0.2))
			_glow(Vector2(x - 4, 240), 6, 6, Color(1, 1, 1, 0.18))


func _body_special(style: String, outline: PackedVector2Array, c1: Color, nx: float) -> void:
	if style == "regata":
		var m := _ring_mesh(outline, Vector2(150, 355), [0.0, 0.4, 0.7, 0.9, 1.0], func(p): return _skin_flat_at(p, 0, 300).lerp(_pal["shadow"], clampf((p.y - 330.0) / 140.0, 0.0, 0.5)))
		_mesh_draw(m)
		var tank := PackedVector2Array([Vector2(85, 400), Vector2(92, 300), Vector2(110, 268), Vector2(122, 268), Vector2(150, 318), Vector2(178, 268), Vector2(190, 268), Vector2(208, 300), Vector2(215, 400)])
		var pal := _cloth_pal(c1)
		var cols := PackedColorArray()
		for p in tank:
			cols.append(_cloth_at(p, pal))
		_gfill(tank, cols, 0.25)
		return
	var bl := PackedVector2Array([Vector2(-20, 400), Vector2(-10, 300), Vector2(60, 250), Vector2(240, 250), Vector2(310, 300), Vector2(320, 400)])
	var pal2 := _cloth_pal(c1)
	var cols2 := PackedColorArray()
	for p in bl:
		cols2.append(_cloth_at(p, pal2))
	_gfill(bl, cols2, 0.25)
	for i in 6:
		_soft_line(_quad(Vector2(30 + i * 45, 270), Vector2(40 + i * 45, 330), Vector2(25 + i * 45, 400), 10), Color(pal2[0], 0.45), 2.4)


func _collar_band(nx: float, col: Color, w: float) -> void:
	var neckline := _quad(Vector2(150 - nx * 1.3, 263), Vector2(150, 292), Vector2(150 + nx * 1.3, 263), 18)
	_stroke(neckline, w, w, col)
	_soft_line(_offset_path(neckline, -w * 0.5, -w * 0.5), Color(col.lightened(0.25), 0.4), 1.0)


func _body_details(style: String, c1: Color, c2: Color, nx: float) -> void:
	var pal := _cloth_pal(c1)
	var dk: Color = pal[0]
	match style:
		"camiseta", "academia", "rasgada", "time", "uniforme":
			_collar_band(nx, c1.darkened(0.28), 5.0)
			if style == "time":
				var pal2 := _cloth_pal(c2)
				for x in [80, 150, 220]:
					var stripe := PackedVector2Array([Vector2(x - 12, 294), Vector2(x + 12, 294), Vector2(x + 16, 400), Vector2(x - 16, 400)])
					var cols := PackedColorArray()
					for p in stripe:
						cols.append(_cloth_at(p, pal2))
					_gfill(stripe, cols)
			if style == "rasgada":
				for p in [Vector2(70, 350), Vector2(210, 372), Vector2(130, 390)]:
					var hole := PackedVector2Array([p, p + Vector2(12, -8), p + Vector2(18, 4), p + Vector2(6, 12)])
					_fill(hole, (_pal["shadow"] as Color).darkened(0.1))
					_soft_line(_closed(hole), Color(c1.lightened(0.2), 0.6), 1.2)
			if style == "uniforme":
				_fill(PackedVector2Array([Vector2(196, 310), Vector2(226, 310), Vector2(226, 324), Vector2(196, 324)]), Color(0.92, 0.92, 0.87))
		"moletom":
			var hood := _quad(Vector2(150 - nx * 1.9, 264), Vector2(150, 306), Vector2(150 + nx * 1.9, 264), 20)
			_stroke(hood, 11.0, 11.0, c1.darkened(0.2))
			_soft_line(_offset_path(hood, -4.0, -4.0), Color(dk, 0.5), 1.4)
			for x in [140.0, 160.0]:
				_soft_line(PackedVector2Array([Vector2(x, 292), Vector2(x - (x - 150.0) * 0.3, 342)]), c2, 2.4)
				_dci(Vector2(x - (x - 150.0) * 0.3, 344), 2.6, c2.darkened(0.2), true, -1.0, true)
		"couro", "jeans", "sobretudo":
			var inner := PackedVector2Array([Vector2(150 - nx * 1.2, 262), Vector2(150, 336), Vector2(150 + nx * 1.2, 262)])
			var pal2 := _cloth_pal(c2)
			var cols := PackedColorArray()
			for p in inner:
				cols.append(_cloth_at(p, pal2))
			_gfill(inner, cols, 0.2)
			for side in [-1, 1]:
				var lapel := PackedVector2Array([Vector2(150 + side * nx * 1.2, 262), Vector2(150 + side * 38, 300), Vector2(150 + side * 10, 400), Vector2(150 + side * 2, 400), Vector2(150 + side * 30, 302)])
				_soft_line(PackedVector2Array([lapel[0], lapel[1], lapel[2]]), Color(dk.darkened(0.2), 0.8), 2.0)
				_soft_line(PackedVector2Array([lapel[0] + Vector2(side * -1, 2), lapel[1] + Vector2(side * -2, 1)]), Color(pal[2] if side == -1 else dk, 0.7), 1.4)
			if style == "couro":
				_glow(Vector2(96, 300), 30, 46, Color(1, 1, 1, 0.12))
				_glow(Vector2(70, 360), 22, 30, Color(1, 1, 1, 0.07))
		"social", "terno", "farda", "jaleco":
			var shirt_col := c2 if style != "jaleco" else c1
			var spal := _cloth_pal(shirt_col)
			var shirt := PackedVector2Array([Vector2(150 - nx * 1.1, 260), Vector2(150, 314), Vector2(150 + nx * 1.1, 260), Vector2(170, 400), Vector2(130, 400)])
			var cols := PackedColorArray()
			for p in shirt:
				cols.append(_cloth_at(p, spal))
			_gfill(shirt, cols, 0.15)
			for side in [-1, 1]:
				var col_pt := PackedVector2Array([Vector2(150 + side * nx * 1.15, 258), Vector2(150 + side * 3, 292), Vector2(150 + side * nx * 0.9, 284)])
				_gfill(col_pt, PackedColorArray([spal[2], spal[1], spal[0]]), 0.25)
			if style == "terno":
				var tie := PackedVector2Array([Vector2(146, 292), Vector2(154, 292), Vector2(159, 380), Vector2(150, 392), Vector2(141, 380)])
				_gfill(tie, PackedColorArray([Color("#7a2028"), Color("#5a161c"), Color("#4a1218"), Color("#3a0e12"), Color("#6a1a22")]))
			if style == "jaleco":
				for side in [-1, 1]:
					var coat := PackedVector2Array([Vector2(150 + side * nx, 258), Vector2(150 + side * 60, 268), Vector2(150 + side * 130, 292), Vector2(150 + side * 164, 330), Vector2(150 + side * 170, 400), Vector2(150 + side * 20, 400)])
					var cpal := _cloth_pal(c2)
					var ccols := PackedColorArray()
					for p in coat:
						ccols.append(_cloth_at(p, cpal))
					_gfill(coat, ccols, 0.2)
			if style == "farda":
				_fill(_ellipse(Vector2(212, 318), 9, 11, 16), Color("#c9a227"))
				_glow(Vector2(209, 314), 4, 4, Color(1, 1, 0.8, 0.6))
		"vestido", "blusa":
			var v := PackedVector2Array([Vector2(150 - nx * 1.4, 262), Vector2(150, 314), Vector2(150 + nx * 1.4, 262)])
			var cols := PackedColorArray()
			for p in v:
				cols.append(_skin_flat_at(p, 150 - nx * 1.4, 150 + nx * 1.4))
			_gfill(v, cols, 0.25)
		"macacao", "avental":
			_collar_band(nx, c1.darkened(0.28), 4.0)
			var spal := _cloth_pal(c2)
			for x in [104, 196]:
				var strap := PackedVector2Array([Vector2(x - 9, 272), Vector2(x + 9, 272), Vector2(x + 12, 400), Vector2(x - 12, 400)])
				var cols := PackedColorArray()
				for p in strap:
					cols.append(_cloth_at(p, spal))
				_gfill(strap, cols, 0.25)
			if style == "avental":
				var apron := PackedVector2Array([Vector2(92, 340), Vector2(208, 340), Vector2(214, 400), Vector2(86, 400)])
				var cols2 := PackedColorArray()
				for p in apron:
					cols2.append(_cloth_at(p, spal))
				_gfill(apron, cols2, 0.25)
		"batina":
			_fill(PackedVector2Array([Vector2(138, 258), Vector2(162, 258), Vector2(162, 268), Vector2(138, 268)]), Color(0.94, 0.94, 0.92))
			for i in 5:
				_dci(Vector2(150, 290 + i * 22), 2.2, Color(0.32, 0.32, 0.34), true, -1.0, true)
		"havaiana":
			var rng := RandomNumberGenerator.new()
			rng.seed = 21
			for i in 14:
				var p := Vector2(rng.randf_range(10, 290), rng.randf_range(290, 395))
				for k in 5:
					var a := TAU * k / 5.0
					_dci(p + Vector2(cos(a), sin(a)) * 5.0, 3.6, Color(c2, 0.85), true, -1.0, true)
				_dci(p, 2.4, Color("#f4e2a0"), true, -1.0, true)
			_collar_band(nx, c1.darkened(0.25), 4.0)


# ---------- cabelo ----------

# Parâmetros de cada penteado para o desenho genérico (calota + laterais + franja + costas).
func _hair_spec() -> Dictionary:
	var style := str(_l("hair", "curto"))
	var female: bool = _l("lashes", false) or str(_l("gender", "")) == "mulher"
	var age := float(_l("age", 30))
	var recede := 0.0
	if not female and age > 35:
		recede = clampf((age - 35.0) / 30.0, 0.0, 1.0) * 0.14
	var s := {"cap": true, "height": 0.78, "vol": 10.0, "part": 0.35, "fan": 0.35, "male": not female, "recede": recede,
		"side": -1.0, "back": -1.0, "fringe": "", "tex": "liso", "tied": ""}
	match style:
		"careca":
			s["cap"] = false
		"raspado":
			s["vol"] = 1.2
			s["tex"] = "raspado"
			s["height"] = 0.8
		"curto":
			s["vol"] = 13.0
			s["height"] = 0.74
			s["fringe"] = "topete"
		"desgrenhado":
			s["vol"] = 15.0
			s["height"] = 0.76
			s["side"] = 0.2
			s["back"] = 0.35
			s["fringe"] = "baguncado"
			s["tex"] = "ondulado"
		"medio":
			s["vol"] = 13.0
			s["height"] = 0.78
			s["side"] = 0.72
			s["back"] = 0.85
			s["fringe"] = "lateral"
		"longo":
			s["vol"] = 13.0
			s["height"] = 0.78
			s["side"] = 1.85
			s["back"] = 1.95
			s["part"] = 0.5
			s["fan"] = 0.6
		"franja":
			s["vol"] = 12.0
			s["height"] = 0.78
			s["side"] = 0.58
			s["back"] = 0.65
			s["fringe"] = "reta"
			s["part"] = 0.5
		"cacheado":
			s["vol"] = 20.0
			s["height"] = 0.74
			s["side"] = 0.95
			s["back"] = 1.05
			s["tex"] = "cacheado"
			s["fringe"] = "cachos"
			s["part"] = 0.5
		"black_power":
			s["vol"] = 6.0
			s["tex"] = "crespo"
			s["height"] = 0.74
		"trancas":
			s["vol"] = 5.0
			s["tex"] = "tranca"
			s["back"] = 1.6
			s["height"] = 0.8
			s["part"] = 0.5
		"dreads":
			s["vol"] = 7.0
			s["tex"] = "dread"
			s["back"] = 1.5
			s["height"] = 0.78
			s["part"] = 0.5
		"moicano":
			s["vol"] = 1.2
			s["tex"] = "raspado"
			s["tied"] = "crista"
		"coque":
			s["vol"] = 5.0
			s["tied"] = "coque"
			s["height"] = 0.8
			s["fan"] = 0.0
			s["part"] = 0.5
		"rabo":
			s["vol"] = 5.0
			s["tied"] = "rabo"
			s["height"] = 0.8
			s["fan"] = 0.0
			s["part"] = 0.5
	if s["tex"] in ["raspado"]:
		s["recede"] = recede * 0.6
	return s


func _beard_at(p: Vector2) -> Color:
	var c := _hair_at(p)
	if not look.has("beard_color"):
		return c
	# mesma luz do cabelo, recolorida para a cor da barba
	var hl: float = (c.get_luminance() - (_pal["hair_dark"] as Color).get_luminance()) / maxf(0.02, (_pal["hair_hi"] as Color).get_luminance() - (_pal["hair_dark"] as Color).get_luminance())
	hl = clampf(hl, 0.0, 1.0)
	return (_pal["beard_dark"] as Color).lerp(_pal["beard"], smoothstep(0.0, 0.6, hl)).lerp(_pal["beard_hi"], smoothstep(0.6, 1.0, hl) * 0.6)


func _hair_at(p: Vector2) -> Color:
	var q := Vector2((p.x - C.x) / (_W() * 1.25), (p.y - C.y + _H() * 0.08) / (_H() * 1.25))
	var r2 := minf(q.length_squared(), 1.0)
	var n := Vector3(q.x, q.y, sqrt(1.0 - r2) * 1.1).normalized()
	var d := n.dot(_L)
	var col: Color = (_pal["hair_dark"] as Color).lerp(_pal["hair"], smoothstep(-0.25, 0.5, d))
	var r := sqrt(r2)
	var band := exp(-pow((r - 0.72) / 0.12, 2.0)) * clampf(-q.y * 1.6, 0.0, 1.0) * clampf(0.75 - q.x, 0.0, 1.0)
	col = col.lerp(_pal["hair_hi"], band * 0.6)
	col = col.lerp(_pal["hair_dark"], clampf((p.y - C.y - _H() * 0.2) / (_H() * 1.8), 0.0, 0.35))
	return col


func _cap_curves(n: int = 40) -> Array:
	var w := _W()
	var h := _H()
	var vol: float = _hs["vol"]
	var height: float = _hs["height"]
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in n + 1:
		var u := float(i) / n
		var a := deg_to_rad(lerpf(186.0, 354.0, u))
		var swell := vol * (0.2 + 0.8 * pow(sin(u * PI), 0.7))
		top.append(C + Vector2(cos(a) * (w * 1.0 + swell), sin(a) * (h * 0.98 + swell)))
		var x := lerpf(-1.0, 1.0, u)
		var plateau := pow(sin(u * PI), 0.5)
		var y := lerpf(-0.1, -height, plateau)
		if _hs["male"]:
			y -= float(_hs["recede"]) * exp(-pow((absf(x) - 0.55) / 0.15, 2.0))
			y += 0.05 * exp(-pow((absf(x) - 0.88) / 0.08, 2.0))
		bot.append(_rel(x * lerpf(0.99, 0.92, plateau), y))
	return [top, bot]


# fios penteados da risca para a linha do cabelo, com comprimento, tom e espessura variados
func _strands(top: PackedVector2Array, bot: PackedVector2Array, count: int, part_u: float, fan: float, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := top.size()
	var hi: Color = _pal["hair_hi"]
	var dk: Color = _pal["hair_dark"]
	for k in count:
		var u := clampf((k + rng.randf_range(0.2, 0.8)) / count, 0.0, 1.0)
		var i := int(u * (n - 1))
		var root_i := int(lerpf(u, part_u, fan) * (n - 1))
		var root: Vector2 = top[root_i].lerp(bot[root_i], rng.randf_range(0.12, 0.3))
		var tip: Vector2 = top[i].lerp(bot[i], rng.randf_range(0.8, 1.0))
		var ctrl: Vector2 = top[i].lerp(bot[i], 0.3)
		var path := _quad(root, ctrl, tip, 12)
		var light := rng.randf() < 0.6
		var col := Color(hi, rng.randf_range(0.18, 0.36)) if light else Color(dk, rng.randf_range(0.25, 0.45))
		_soft_line(path, col, rng.randf_range(0.8, 1.6))


func _draw_cap() -> void:
	var tex: String = _hs["tex"]
	var curves := _cap_curves()
	var top: PackedVector2Array = curves[0]
	var bot: PackedVector2Array = curves[1]
	if tex == "raspado":
		# cabelo raspado: a cor do cabelo tinge o couro cabeludo, com pontinhos e borda suave
		var m := _strip(top, bot, 5, func(p): return Color(_hair_at(p), 0.6), 0.0, 0.3)
		_mesh_draw(m)
		var rng := RandomNumberGenerator.new()
		rng.seed = 6
		var area := top.duplicate()
		var rb := bot.duplicate()
		rb.reverse()
		area.append_array(rb)
		for i in 520:
			var p := Vector2(rng.randf_range(C.x - _W() * 1.05, C.x + _W() * 1.05), rng.randf_range(C.y - _H() * 1.02, C.y - _H() * 0.08))
			if Geometry2D.is_point_in_polygon(p, area):
				_dre(Rect2(p, Vector2(1.0, 1.0)), Color(_pal["hair_dark"], 0.3))
		_glow(_rel(-0.32, -0.8), _W() * 0.3, _H() * 0.08, Color(1, 1, 1, 0.1))
		return
	if not _cache.has("cap"):
		_cache["cap"] = _strip(top, bot, 6, _hair_at, 0.0, 0.14)
	var cm: Dictionary = _cache["cap"]
	_mesh_draw(cm)
	_strip_edge(cm, 0.28, 0.85, 1.1, "a")
	if tex == "cacheado" or tex == "crespo":
		_curl_texture(top, bot, 80 if tex == "cacheado" else 130, 4.0 if tex == "cacheado" else 2.2)
	elif tex == "tranca" or tex == "dread":
		# risca em fileiras puxadas para trás
		var part_u: float = _hs["part"]
		for k in 11:
			var u := (k + 0.5) / 11.0
			var i := int(u * (top.size() - 1))
			var pi := int(part_u * (top.size() - 1))
			var root := top[pi].lerp(bot[pi], 0.05)
			_soft_line(_quad(root, top[i].lerp(bot[i], 0.25), bot[i], 12), Color(_pal["hair_dark"], 0.6), 1.3)
			_soft_line(_offset_path(_quad(root, top[i].lerp(bot[i], 0.25), bot[i], 12), 2.0, 2.0), Color(_pal["hair_hi"], 0.2), 1.0)
	else:
		_strands(top, bot, 34, float(_hs["part"]), float(_hs["fan"]), 17 + str(_l("hair", "")).hash() % 50)
	# raiz: pontinhas curtas que quebram a borda do cabelo na testa
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 41
	if tex in ["liso", "ondulado"]:
		for i in range(3, bot.size() - 3):
			if rng2.randf() < 0.45:
				var p: Vector2 = bot[i]
				var nrm := (p - C).normalized()
				var col := Color(_hair_at(p), 0.35)
				_soft_line(PackedVector2Array([p - nrm * 1.0, p - nrm * rng2.randf_range(2.0, 3.8) + Vector2(rng2.randf_range(-1.0, 1.0), 0)]), col, 0.9)
	if _hs["male"] and tex in ["liso", "ondulado"] and str(_l("hair", "")) in ["curto", "desgrenhado", "medio"]:
		for side in [-1, 1]:
			var path := _quad(_rel(side * 0.97, -0.2), _rel(side * 0.99, -0.06), _rel(side * 0.95, 0.06), 8)
			_mecha(path, 6.0, 3.0, 0.1)


func _curl_texture(top: PackedVector2Array, bot: PackedVector2Array, count: int, r: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var n := top.size()
	for k in count:
		var i := rng.randi_range(0, n - 1)
		var p: Vector2 = top[i].lerp(bot[i], rng.randf_range(0.05, 0.95))
		var light := rng.randf() < 0.5
		var col := Color(_pal["hair_hi"], 0.38) if light else Color(_pal["hair_dark"], 0.5)
		var a0 := rng.randf_range(0.0, TAU)
		_dar(p, r * rng.randf_range(0.7, 1.2), a0, a0 + PI * 1.3, 8, col, 1.1, true)


# Mecha lateral (do alto da cabeça até `length`): as duas bordas nascem embaixo da calota e
# descem com volume; as pontas viram mechas separadas e irregulares.
func _curtain(side: int, length: float, vol: float, wave: float, n: int = 28) -> Array:
	var w := _W()
	var vx := vol / w
	var inner_pts: Array = [_rel(side * 0.42, -0.8), _rel(side * 0.8, -0.52), _rel(side * 0.94, -0.15)]
	var outer_pts: Array = [_rel(side * 0.68, -0.74), _rel(side * (0.93 + vx * 0.8), -0.5), _rel(side * (1.0 + vx), -0.12)]
	if length > 0.35:
		inner_pts.append(_rel(side * 0.92, minf(0.32, length * 0.6)))
		outer_pts.append(_rel(side * (1.02 + vx), minf(0.38, length * 0.62)))
	if length > 0.7:
		inner_pts.append(_rel(side * 0.8, minf(0.7, length * 0.75)))
		outer_pts.append(_rel(side * (1.04 + vx), minf(0.78, length * 0.78)))
	if length > 1.1:
		inner_pts.append(_rel(side * 0.78, 1.08))
		outer_pts.append(_rel(side * (1.2 + vx), 1.1))
		inner_pts.append(_rel(side * 0.9, length * 0.93))
		outer_pts.append(_rel(side * (1.32 + vx * 0.6), length * 0.93))
	inner_pts.append(_rel(side * (0.92 if length > 1.1 else 0.88), length))
	outer_pts.append(_rel(side * ((1.3 if length > 1.1 else 1.0) + vx * 0.5), length + 0.02))
	var inner := _catmull_open(inner_pts, n)
	var outer := _catmull_open(outer_pts, n)
	for i in n + 1:
		var t := float(i) / n
		var wv := sin(t * PI * 3.0) * wave * w * t
		inner[i] += Vector2(wv, 0)
		outer[i] += Vector2(wv, 0)
	for i in range(int(n * 0.75), n + 1):
		var k := float(i - int(n * 0.75)) / maxf(1.0, n * 0.25)
		var mid: Vector2 = inner[i].lerp(outer[i], 0.55)
		inner[i] = inner[i].lerp(mid, k * 0.4)
		outer[i] = outer[i].lerp(mid, k * 0.4)
	return [inner, outer]


func _draw_curtains() -> void:
	var length: float = _hs["side"]
	if length <= 0.0:
		return
	var vol: float = _hs["vol"]
	var wave := 0.04 if _hs["tex"] == "ondulado" else (0.06 if _hs["tex"] == "cacheado" else 0.015)
	for side in [-1, 1]:
		var key := "curtain%d" % side
		if not _cache.has(key):
			var cv := _curtain(side, length, vol, wave)
			_cache[key] = [_strip(cv[0], cv[1], 4, _hair_at), cv]
		var entry: Array = _cache[key]
		var m: Dictionary = entry[0]
		var cv2: Array = entry[1]
		var inner: PackedVector2Array = cv2[0]
		var outer: PackedVector2Array = cv2[1]
		var n := inner.size()
		# pontas: 4 a 5 mechas soltas continuando a queda, cada uma com seu comprimento
		var rng := RandomNumberGenerator.new()
		rng.seed = 90 + side
		var tips := 7 if length > 1.1 else 5
		var end_w := inner[n - 6].distance_to(outer[n - 6])
		var down := (inner[n - 1] - inner[n - 6]).normalized()
		if _hs["tex"] == "cacheado":
			for k in tips:
				var t := (k + 0.5) / tips
				var c: Vector2 = inner[n - 1].lerp(outer[n - 1], t) + down * rng.randf_range(2.0, 9.0)
				var r := rng.randf_range(5.0, 7.5)
				_dci(c, r, _hair_at(c), true, -1.0, true)
				_dar(c + Vector2(-1, 1), r * 0.6, PI, PI * 2.2, 10, Color(_pal["hair_hi"], 0.4), 1.1, true)
		else:
			for k in tips:
				var t := (k + 0.5) / tips
				var root: Vector2 = inner[n - 6].lerp(outer[n - 6], t)
				var tip := root + down * _H() * rng.randf_range(0.22, 0.42) + Vector2(side * (t - 0.4) * 10.0, 0)
				_mecha(_quad(root, root.lerp(tip, 0.5) + Vector2(side * rng.randf_range(-3, 4), 0), tip, 12), end_w / tips * 1.9, 0.6, rng.randf_range(0.0, 0.08))
		_mesh_draw(m)
		_strip_edge(m, 0.3, 0.75, 1.0, "ab")
		if _hs["tex"] == "cacheado":
			_curl_texture(inner, outer, 50, 4.5)
			continue
		for k in 12:
			var t := clampf((k + rng.randf_range(0.1, 0.9)) / 12.0, 0.04, 0.96)
			var i0 := rng.randi_range(0, n / 4)
			var i1 := rng.randi_range(n * 2 / 3, n - 1)
			var line := PackedVector2Array()
			for i in range(i0, i1 + 1):
				line.append(inner[i].lerp(outer[i], t + sin(i * 0.4 + k) * 0.02))
			var light := rng.randf() < 0.55
			_soft_line(line, Color(_pal["hair_hi"], rng.randf_range(0.15, 0.32)) if light else Color(_pal["hair_dark"], rng.randf_range(0.25, 0.42)), rng.randf_range(0.8, 1.4))


func _draw_back_mass() -> void:
	var back: float = _hs["back"]
	if back <= 0.0 or _hs["tex"] in ["tranca", "dread"]:
		return
	if not _cache.has("back"):
		var vol: float = _hs["vol"]
		var vx := vol / _W()
		var n := 30
		var l_pts: Array = [_rel(-0.02, -0.95 - vx * 0.8), _rel(-0.5, -0.86 - vx * 0.8), _rel(-0.86 - vx * 0.7, -0.55), _rel(-1.0 - vx, -0.1)]
		if back > 0.5:
			l_pts.append(_rel(-1.02 - vx * 1.05, minf(0.4, back * 0.6)))
		if back > 0.8:
			l_pts.append(_rel(-1.06 - vx, back * 0.75))
		l_pts.append(_rel(-0.85 - vx * 0.5, back))
		l_pts.append(_rel(-0.4, back + 0.14))
		l_pts.append(_rel(-0.02, back + 0.2))
		var r_pts: Array = []
		for p in l_pts:
			r_pts.append(Vector2(2.0 * C.x - (p as Vector2).x, (p as Vector2).y))
		var l := _catmull_open(l_pts, n)
		var r := _catmull_open(r_pts, n)
		var dark_shade := func(p): return _hair_at(p).lerp(_pal["hair_dark"], 0.5)
		_cache["back"] = _strip(l, r, 6, dark_shade)
	var bm: Dictionary = _cache["back"]
	_mesh_draw(bm)
	_strip_edge(bm, 0.2, 0.6, 1.0, "ab")


func _draw_ropes(kind: String) -> void:
	# tranças e dreads caindo por trás, dos lados do rosto
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var back: float = _hs["back"]
	var thick := 7.5 if kind == "dread" else 5.5
	for i in 24:
		var x := lerpf(-1.18, 1.18, i / 23.0)
		if absf(x) < 0.66:
			continue
		var start := _rel(x * 0.85, -0.6 + absf(x) * 0.1)
		var end := _rel(x * 1.12 + rng.randf_range(-0.05, 0.05), back - rng.randf_range(0.0, 0.25))
		var path := _quad(start, start.lerp(end, 0.5) + Vector2(signf(x) * 6.0, 0), end, 18)
		var base: Color = _hair_at(path[9]).lerp(_pal["hair_dark"], 0.2 + rng.randf() * 0.2)
		var rb := _ribbon(path, thick, thick * 0.75)
		var m := _strip(rb[0], rb[1], 1, func(p): return base.lerp(_pal["hair_dark"], clampf((p.y - start.y) / 300.0, 0.0, 0.4)))
		_mesh_draw(m)
		_strip_edge(m, 0.35, 0.7, 0.9, "ab")
		var segs := 10
		for k in segs:
			var p: Vector2 = path[int((k + 0.5) / segs * (path.size() - 1))]
			if kind == "tranca":
				_soft_line(PackedVector2Array([p + Vector2(-thick * 0.45, -2), p + Vector2(thick * 0.45, 2)]), Color(_pal["hair_dark"], 0.65), 1.0)
			else:
				_soft_line(PackedVector2Array([p + Vector2(-thick * 0.4, 0), p + Vector2(thick * 0.4, 1)]), Color(_pal["hair_dark"], 0.4), 1.0)
		_soft_line(_offset_path(path, -thick * 0.25, -thick * 0.2), Color(_pal["hair_hi"], 0.28), 1.0)


func _draw_back_hair() -> void:
	if look.is_empty():
		return
	_prep()
	_cached("cabelo_tras", _back_hair_body)


func _back_hair_body() -> void:
	var style := str(_l("hair", "curto"))
	if style == "black_power":
		if not _cache.has("afro"):
			var cloud := PackedVector2Array()
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			for i in 72:
				var a := TAU * i / 72.0
				var r := 1.0 + 0.035 * sin(i * 2.7) + rng.randf_range(-0.015, 0.015)
				cloud.append(C + Vector2(0, -_H() * 0.3) + Vector2(cos(a) * _W() * 1.6 * r, sin(a) * _H() * 1.08 * r))
			_cache["afro"] = _ring_mesh(cloud, C + Vector2(-_W() * 0.2, -_H() * 0.5), [0.0, 0.3, 0.55, 0.75, 0.9, 1.0], _hair_at)
		var am: Dictionary = _cache["afro"]
		_mesh_draw(am)
		var ol: PackedVector2Array = am["outline"]
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 8
		for p in ol:
			_dci(p + Vector2(rng2.randf_range(-2, 2), rng2.randf_range(-2, 2)), rng2.randf_range(3.0, 5.0), Color(_hair_at(p), 0.85), true, -1.0, true)
		for i in 300:
			var p := C + Vector2(rng2.randf_range(-1.6, 1.6) * _W(), rng2.randf_range(-1.35, 0.7) * _H())
			if Geometry2D.is_point_in_polygon(p, ol):
				var col := Color(_pal["hair_hi"], 0.28) if i % 2 == 0 else Color(_pal["hair_dark"], 0.45)
				var a0 := rng2.randf_range(0, TAU)
				_dar(p, 2.4, a0, a0 + PI, 6, col, 1.0, true)
		return
	if _hs["tex"] in ["tranca", "dread"]:
		_draw_ropes(_hs["tex"])
	match str(_hs["tied"]):
		"coque":
			var bc := _rel(0.0, -1.1)
			if not _cache.has("bun"):
				_cache["bun"] = _ring_mesh(_resample_closed(_ellipse(bc, _W() * 0.4, _H() * 0.24, 12), 40), bc + Vector2(-5, -5), [0.0, 0.4, 0.75, 1.0], _hair_at)
			var bm: Dictionary = _cache["bun"]
			_mesh_draw(bm)
			var ep := _closed(bm["outline"])
			_soft_line(ep, Color(_pal["hair_dark"], 0.6), 1.0)
			# espiral do coque
			for off in [0.0, 2.1]:
				var sp := PackedVector2Array()
				for k in 60:
					var u := k / 59.0
					var a: float = off + u * TAU * 2.2
					sp.append(bc + Vector2(cos(a) * _W() * 0.36 * (1.0 - u * 0.8), sin(a) * _H() * 0.2 * (1.0 - u * 0.8)))
				_soft_line(sp, Color(_pal["hair_dark"], 0.4) if off == 0.0 else Color(_pal["hair_hi"], 0.25), 1.1)
		"rabo":
			if not _cache.has("tail"):
				var l := _catmull_open([_rel(0.35, -0.95), _rel(0.95, -0.7), _rel(1.25, 0.2), _rel(1.15, 1.25)], 22)
				var r := _catmull_open([_rel(0.55, -1.0), _rel(1.15, -0.85), _rel(1.45, 0.15), _rel(1.2, 1.3)], 22)
				_cache["tail"] = _strip(l, r, 3, func(p): return _hair_at(p).lerp(_pal["hair_dark"], 0.35))
			var tm: Dictionary = _cache["tail"]
			_mesh_draw(tm)
			_strip_edge(tm, 0.25, 0.7)
	_draw_back_mass()


func _draw_front_hair() -> void:
	if look.is_empty():
		return
	_cached("cabelo_frente", _front_hair_body)


func _front_hair_body() -> void:
	var style := str(_l("hair", "curto"))
	if style == "careca":
		_glow(_rel(-0.3, -0.78), _W() * 0.32, _H() * 0.1, Color(1, 1, 1, 0.16))
		return
	if not _hs.get("cap", false):
		return
	if style == "black_power":
		var curves := _cap_curves()
		var bot: PackedVector2Array = curves[1]
		var rng := RandomNumberGenerator.new()
		rng.seed = 19
		for i in range(1, bot.size() - 1):
			if rng.randf() < 0.45:
				continue
			var p: Vector2 = bot[i] + (bot[i] - C).normalized() * rng.randf_range(1.0, 3.5)
			var r := rng.randf_range(2.2, 3.4)
			_dci(p, r, Color(_hair_at(p), 0.75), true, -1.0, true)
		return
	_draw_curtains()
	_draw_cap()
	if _hs["tied"] == "crista":
		var crest_l := PackedVector2Array()
		var crest_r := PackedVector2Array()
		for i in 21:
			var u := float(i) / 20.0
			var a := deg_to_rad(lerpf(212.0, 328.0, u))
			var base := C + Vector2(cos(a) * _W() * 0.97, sin(a) * _H() * 0.95)
			var up := (base - C).normalized()
			crest_l.append(base)
			crest_r.append(base + up * (24.0 + 7.0 * sin(u * PI * 7.0)) * sin(u * PI))
		var cm := _strip(crest_l, crest_r, 3, _hair_at)
		_mesh_draw(cm)
		_strip_edge(cm, 0.3, 0.8, 1.0, "b")
		return
	if _hs["tied"] in ["coque", "rabo"]:
		var curves2 := _cap_curves()
		var target := _rel(0.0 if _hs["tied"] == "coque" else 0.6, -1.06)
		var top: PackedVector2Array = curves2[0]
		var bot: PackedVector2Array = curves2[1]
		var rng := RandomNumberGenerator.new()
		rng.seed = 4
		for k in 14:
			var u := (k + rng.randf_range(0.2, 0.8)) / 14.0
			var i := int(u * (bot.size() - 1))
			_soft_line(_quad(bot[i], top[i].lerp(bot[i], 0.15), target, 14), Color(_pal["hair_hi"], 0.22) if k % 2 == 0 else Color(_pal["hair_dark"], 0.32), 1.0)
	_draw_fringe(str(_hs["fringe"]))


func _draw_fringe(kind: String) -> void:
	if kind == "":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var hl: float = _hs["height"]
	match kind:
		"topete":
			for k in 6:
				var root := _rel(-0.55 + k * 0.1, -hl - 0.16)
				var tip := _rel(0.0 + k * 0.15, -hl + 0.06 + k * 0.02)
				_mecha(_quad(root, _rel(-0.2 + k * 0.13, -hl - 0.14), tip, 12), 12.0 - k, 1.0, 0.04 * (k % 2))
		"lateral":
			for k in 4:
				var root := _rel(-0.4 + k * 0.06, -hl - 0.12)
				var tip := _rel(0.62 + k * 0.1, -0.42 + k * 0.08)
				_mecha(_quad(root, _rel(0.08 + k * 0.08, -hl - 0.02), tip, 14), 13.0 - k * 2.0, 1.2, k * 0.04)
		"reta":
			for i in 13:
				var u := (i + 0.5) / 13.0
				var x := lerpf(-0.84, 0.84, u)
				var root := _rel(x * 0.7, -hl - 0.1)
				var tip := _rel(x * 0.98 + 0.02, -0.3 + rng.randf_range(-0.04, 0.03))
				_mecha(_quad(root, root.lerp(tip, 0.5) + Vector2(2, -2), tip, 10), 14.0, 1.5, rng.randf_range(0.0, 0.1))
		"baguncado":
			for i in 9:
				var x := lerpf(-0.7, 0.75, i / 8.0)
				var root := _rel(x * 0.6, -hl - 0.12)
				var tip := _rel(x + rng.randf_range(-0.1, 0.12), -hl + 0.18 + rng.randf_range(-0.06, 0.1))
				_mecha(_quad(root, root.lerp(tip, 0.5) + Vector2(rng.randf_range(-6, 6), -4), tip, 10), 11.0, 1.0, rng.randf_range(0.0, 0.12))
			for i in 5:
				var a := deg_to_rad(rng.randf_range(215, 325))
				var p := C + Vector2(cos(a) * (_W() + 10.0), sin(a) * (_H() + 10.0))
				_soft_line(_quad(p, p + Vector2(rng.randf_range(-4, 4), -5), p + Vector2(rng.randf_range(-7, 7), -8), 6), Color(_pal["hair"], 0.45), 0.9)
		"cachos":
			for i in 9:
				var x := lerpf(-0.75, 0.75, i / 8.0)
				var c := _rel(x, -hl + 0.06 + absf(x) * 0.12 + rng.randf_range(-0.03, 0.03))
				var r := 7.0 + rng.randf() * 2.0
				var col: Color = _hair_at(c)
				_dci(c, r, col, true, -1.0, true)
				_dar(c + Vector2(-1, 1), r * 0.6, PI * 1.0, PI * 2.2, 10, Color(_pal["hair_hi"], 0.45), 1.2, true)
				_dar(c, r, 0, TAU, 18, Color(_pal["hair_dark"], 0.4), 1.0, true)


# ---------- cabeça ----------

func _head_mesh() -> Dictionary:
	if not _cache.has("head"):
		var outline := _head_pts()
		_cache["head"] = _ring_mesh(outline, C + Vector2(0, _H() * 0.05), [0.0, 0.12, 0.24, 0.36, 0.48, 0.6, 0.7, 0.79, 0.86, 0.92, 0.96, 1.0], _skin_at)
	return _cache["head"]


func _draw_head() -> void:
	_prep()
	_cached("orelhas", _draw_ears)
	var hm := _head_mesh()
	_mesh_draw(hm)
	var ep := _closed(hm["outline"])
	var ec: PackedColorArray = (hm["edge"] as PackedColorArray).duplicate()
	ec.append(ec[0])
	for i in ec.size():
		ec[i] = ec[i].darkened(0.32)
	_dplc(ep, ec, 1.3, true)
	if cur["pale"] > 0.02:
		_overlay(hm, Color(0.82, 0.86, 0.84, cur["pale"] * 0.32))
	_cached("barba_rugas", func():
		_p_beard()
		_p_age_lines()
		_p_marks_static())
	_p_cheeks()
	for side in [-1, 1]:
		_p_eye(side)
	_p_nose()
	_p_mouth()
	_p_marks()
	_p_fx()
	_draw_front_hair()
	_cached("chapeu", _draw_headwear)


func _draw_ears() -> void:
	var w := _W()
	var h := _H()
	var k := h / 100.0 * float(_l("ear_size", 1.0))
	var out := float(_l("ear_out", 1.0))
	for side in [-1, 1]:
		var top := C + Vector2(side * w * 0.95, -h * 0.14)
		var ear := PackedVector2Array([top, top + Vector2(side * 10 * out, -4) * k, top + Vector2(side * 15 * out, 12) * k, top + Vector2(side * 12 * out, 36) * k, top + Vector2(side * 4, 48) * k, top + Vector2(0, 42) * k])
		ear = _resample_closed(ear, 24)
		var cols := PackedColorArray()
		for p in ear:
			var e := clampf((p.x - top.x) * side / 14.0, 0.0, 1.0)
			var base: Color = _pal["base"] if side == -1 else _pal["shadow"]
			cols.append(base.lerp(_pal["blush"], 0.25 + 0.2 * e).lerp(_pal["shadow"], 0.25 * e))
		_gfill(ear, cols, 0.3)
		_soft_line(_quad(top + Vector2(side * 4, 5), top + Vector2(side * 11, 14), top + Vector2(side * 5, 30), 8), Color(_pal["line"], 0.45), 1.6)
		_glow(top + Vector2(side * 6, 18), 4, 8, Color(_pal["shadow"], 0.5))
		if 4 in _l("marks", []):
			for p in [top + Vector2(side * 6, 40), top + Vector2(side * 12, 8)]:
				_dci(p, 2.2, Color("#cfcfcf"), true, -1.0, true)
				_dci(p + Vector2(-0.6, -0.6), 0.8, Color(1, 1, 1, 0.9), true, -1.0, true)
		if 14 in _l("marks", []):
			_dar(top + Vector2(side * 5, 52), 7, 0, TAU, 20, Color("#d4a72c"), 2.0, true)


func _p_cheeks() -> void:
	if cur["blush"] > 0.02:
		for side in [-1, 1]:
			_glow(_rel(side * 0.52, 0.24), _W() * 0.26, _H() * 0.09, Color(0.9, 0.32, 0.36, 0.42 * cur["blush"]))
	var dc: float = cur["dark_circles"]
	if dc > 0.02:
		for side in [-1, 1]:
			_glow(_eye_center(side) + Vector2(0, 10), 17, 6, Color(0.3, 0.16, 0.32, 0.55 * dc))


func _p_eye(side: int) -> void:
	var c := _eye_center(side)
	var es := float(_l("eye_size", 1.0))
	var open: float = cur["eye_open"] * (1.0 - blink) * (1.0 - cur["squint"] * 0.45)
	if side == 1 and cur["bruise"] > 0.1:
		open *= 1.0 - 0.65 * cur["bruise"]
	var w := 17.2 * es
	var h := 7.9 * es * open * float(_l("eye_h", 1.0))
	var tilt := float(_l("eye_tilt", 0.0))
	if side == 1 and cur["bruise"] > 0.1:
		_glow(c + Vector2(0, 2), 26, 18, Color(0.35, 0.12, 0.38, 0.6 * cur["bruise"]))
	if cur["shadow_eyes"] > 0.02:
		_glow(c + Vector2(0, -6), 30, 18, Color(0, 0, 0, 0.45 * cur["shadow_eyes"]))
	var inner := c + Vector2(-side * w, 1.5)
	var outer := c + Vector2(side * w, -tilt * 4.0)
	var top := _quad(inner, c + Vector2(side * w * 0.12, -h * 1.4), outer, 16)
	var bot := _quad(inner, c + Vector2(-side * w * 0.08, h * 0.95), outer, 16)
	var female: bool = _l("lashes", false)
	var makeup: bool = 13 in _l("marks", [])
	# pálpebra móvel e vinco
	var lift := maxf(h, 2.0)
	var crease := _quad(inner + Vector2(side * 1.5, -4.5), c + Vector2(side * w * 0.12, -lift * 1.4 - 6.0), outer + Vector2(-side * 1.0, -4.0), 16)
	var lid_col: Color = _pal["lid"]
	if makeup:
		lid_col = lid_col.lerp(Color(0.35, 0.2, 0.3), 0.45)
	_mesh_draw(_strip(crease, top, 2, func(_p): return Color(lid_col, 0.7), 0.6, 0.0))
	if h > 1.0:
		var white := top.duplicate()
		var rb := bot.duplicate()
		rb.reverse()
		white.append_array(rb)
		var wcols := PackedColorArray()
		for p in white:
			var k := clampf((p.y - (c.y - h)) / maxf(h * 2.0, 1.0), 0.0, 1.0)
			wcols.append(SCLERA.darkened(0.3).lerp(SCLERA, smoothstep(0.1, 0.8, k)))
		if not Geometry2D.triangulate_polygon(white).is_empty():
			_dpg(white, wcols)
		var g := Vector2(cur["gaze_x"] + dart.x, cur["gaze_y"] + dart.y)
		var ic := c + Vector2(g.x * 6.5, g.y * 2.4 - h * 0.12)
		var ir := 6.3 * es
		var iris: Color = _l("eye_color", Color("#5a3a22"))
		if _l("hetero", false) and side == 1:
			iris = Color("#4a78a8")
		_shade(_ellipse(ic, ir, ir, 28), white, iris.darkened(0.5))
		_shade(_ellipse(ic, ir * 0.84, ir * 0.84, 28), white, iris)
		_shade(_ellipse(ic + Vector2(0, ir * 0.32), ir * 0.6, ir * 0.46, 20), white, iris.lightened(0.25))
		var pr: float = 2.6 * cur["pupil"] * es
		_shade(_ellipse(ic, pr, pr, 18), white, Color(0.03, 0.025, 0.025))
		var band := top.duplicate()
		var lower := top.duplicate()
		lower.reverse()
		for i in lower.size():
			lower.set(i, lower[i] + Vector2(0, minf(h * 0.55, 4.0)))
		band.append_array(lower)
		_shade(band, white, Color(0.18, 0.1, 0.1, 0.32))
		_dci(ic + Vector2(-ir * 0.36, -ir * 0.4), 1.5 * es, Color(1, 1, 1, 0.9), true, -1.0, true)
		_dci(ic + Vector2(ir * 0.38, ir * 0.3), 0.8 * es, Color(1, 1, 1, 0.4), true, -1.0, true)
		_soft_line(bot, Color(_pal["line"], 0.35), 1.0)
		_soft_line(_offset_path(bot, side * 0.6, side * 0.6), Color(_pal["blush"].lightened(0.2), 0.35), 0.8)
	# cílios de cima: traço que engrossa para o canto de fora
	var lw := 3.4 if (female or makeup) else 2.4
	var tp := top.duplicate()
	if side == -1:
		pass
	_stroke(tp, 1.0, lw, LASH)
	if female or makeup:
		_stroke(PackedVector2Array([outer, outer + Vector2(side * 6, -3.5)]), 2.2, 0.3, LASH)
		if h > 1.0:
			for k in 5:
				var p: Vector2 = top[9 + k]
				_stroke(PackedVector2Array([p, p + Vector2(side * (1.2 + k * 0.8), -3.6 - k * 0.3)]), 1.1, 0.2, LASH)
	_soft_line(crease, Color(_pal["line"], 0.38), 1.3)
	_soft_line(_quad(inner + Vector2(side * 3, 6), c + Vector2(0, h + 8), outer + Vector2(-side * 3, 5), 10), Color(_pal["line"], 0.14 + 0.2 * float(_l("_old", 0.0))), 1.1)
	if 7 in _l("marks", []):
		var frame := _ellipse(c, w + 8, 15, 28)
		_glow(c + Vector2(-4, -4), w, 8, Color(1, 1, 1, 0.08))
		_soft_line(_closed(frame), Color(0.14, 0.13, 0.15), 2.2)
		if side == -1:
			_soft_line(PackedVector2Array([c + Vector2(w + 8, -2), c + Vector2(_W() * 0.84 - w - 8, -2)]), Color(0.14, 0.13, 0.15), 2.2)
	if 8 in _l("marks", []):
		var lens := _ellipse(c, w + 9, 15, 28)
		_fill(lens, Color(0.05, 0.05, 0.07, 0.94))
		_soft_line(PackedVector2Array([c + Vector2(-10, -7), c + Vector2(6, -10)]), Color(1, 1, 1, 0.28), 2.0)
		_soft_line(_closed(lens), Color(0.1, 0.1, 0.12), 2.0)
		if side == -1:
			_soft_line(PackedVector2Array([c + Vector2(w + 9, -3), c + Vector2(_W() * 0.84 - w - 9, -3)]), Color(0.1, 0.1, 0.12), 2.6)
	_p_brow(side, c, w)


func _p_brow(side: int, c: Vector2, eye_w: float) -> void:
	var shape_i := clampi(int(_l("brow_shape", 0)), 0, BROW_SHAPES.size() - 1)
	var shape: Array = BROW_SHAPES[shape_i]
	var raise: float = cur["brow_raise"] + (cur["brow_asym"] * 0.5 if side == 1 else -cur["brow_asym"] * 0.3)
	var base_y: float = c.y - _H() * 0.15 - raise * 8.0 - float(_l("brow_y", 0.0)) * 6.0
	var angle: float = cur["brow_angle"]
	var inner := Vector2(c.x - side * eye_w * 0.95, base_y + angle * 8.0 + float(shape[0]))
	var outer := Vector2(c.x + side * eye_w * 1.3, base_y - angle * 2.5 + float(shape[3]))
	var peak := inner.lerp(outer, float(shape[1])) + Vector2(0, float(shape[2]) - angle * 1.5)
	var path: PackedVector2Array
	if shape[5]:
		path = _catmull_open([inner, inner.lerp(peak, 0.5) + Vector2(0, -1), peak, peak.lerp(outer, 0.5) + Vector2(0, 1), outer], 16)
	else:
		path = _quad(inner, peak + (peak - inner.lerp(outer, float(shape[1]))) * 0.9, outer, 16)
	var col: Color = _l("brow_color", _hair_color().darkened(0.2))
	if str(_l("hair", "")) == "careca" and not look.has("brow_color"):
		col = Color(0.22, 0.16, 0.12)
	var kid := float(_l("_kid", 0.0))
	var bw := 4.4 * float(shape[4]) * float(_l("brow_w", 1.0)) * (1.0 - 0.25 * kid)
	var brb := _ribbon(path, bw * 0.85, bw * 0.3)
	_mesh_draw(_strip(brb[0], brb[1], 2, func(_p): return Color(col, 0.4), 0.3, 0.3))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 + side
	var strokes := 46 if shape_i == 6 else 34
	for i in strokes:
		var u := (i + 0.5) / strokes
		var idx := mini(int(u * (path.size() - 1)), path.size() - 2)
		var tang := (path[idx + 1] - path[idx]).normalized()
		var nrm := tang.orthogonal()
		var wid := lerpf(bw * 0.85, bw * 0.3, u)
		var p := path[idx] + nrm * rng.randf_range(-wid * 0.45, wid * 0.45)
		var dir: Vector2
		if u < 0.22:
			dir = Vector2(side * 1.0, -3.4)
		else:
			dir = tang * 4.2 + Vector2(0, -0.9)
		if shape_i == 6:
			dir = dir.rotated(rng.randf_range(-0.7, 0.7)) * 1.3
		_dli(p, p + dir * rng.randf_range(0.8, 1.2), Color(col.darkened(0.12), 0.72), 1.0, true)
	if 5 in _l("marks", []) and side == 1:
		_dci(outer + Vector2(-6, -4), 2.0, Color("#d0d0d0"), true, -1.0, true)


func _p_nose() -> void:
	var nw := 9.0 * float(_l("nose_w", 1.0))
	var tip := _nose_tip()
	var top_y := _eye_center(1).y + 2
	var line: Color = _pal["line"]
	_soft_line(_quad(Vector2(C.x + 5, top_y + 4), Vector2(C.x + 7, tip.y - 16), tip + Vector2(nw * 0.9, -6), 10), Color(line, 0.2), 1.4)
	for side in [-1, 1]:
		_soft_line(_quad(tip + Vector2(side * nw * 0.55, -6), tip + Vector2(side * nw * 1.35, 0), tip + Vector2(side * nw * 0.7, 5), 10), Color(line, 0.55 if side == 1 else 0.38), 1.6)
		var nost := _ellipse(tip + Vector2(side * nw * 0.42, 4.5), 2.7 * float(_l("nose_w", 1.0)), 1.6, 14)
		_fill(nost, Color(_pal["line"].darkened(0.2), 0.75))
	_soft_line(_quad(tip + Vector2(-nw * 0.45, 6.0), tip + Vector2(0, 8.5), tip + Vector2(nw * 0.45, 6.0), 8), Color(line, 0.3), 1.2)
	_glow(tip + Vector2(-2, -3), 3.5, 2.5, Color(_pal["hi"].lightened(0.15), 0.7))
	if 16 in _l("marks", []):
		_soft_line(_quad(Vector2(C.x + 1, top_y + 14), Vector2(C.x + 6, top_y + 22), tip + Vector2(3, -8), 8), Color(line, 0.45), 1.4)
	if 3 in _l("marks", []):
		_dci(tip + Vector2(-nw * 0.95, 2), 2.0, Color("#d0d0d0"), true, -1.0, true)


func _p_mouth() -> void:
	var skin: Color = _pal["base"]
	var y := _mouth_y()
	var flap := 0.0
	if talk_left > 0.0:
		flap = absf(sin(t * 15.0)) * 0.35 + absf(sin(t * 6.3)) * 0.12
	var open := clampf(cur["mouth_open"] + flap, 0.0, 1.2)
	var lips := float(_l("lips", 1.0))
	var w: float = _W() * 0.33 * cur["mouth_width"] * float(_l("mouth_w", 1.0)) * (1.0 + 0.2 * maxf(cur["mouth_curve"], 0.0)) * (1.0 - 0.18 * float(_l("_kid", 0.0)))
	var curve: float = cur["mouth_curve"]
	var left := Vector2(C.x - w, y - curve * 7.0)
	var right := Vector2(C.x + w, y - curve * 7.0 - cur["smirk"] * 8.0)
	var up_mid := Vector2(C.x + cur["smirk"] * 3.0, y + curve * 2.0 - 1.0)
	var low_mid := Vector2(C.x, y + curve * 4.0 + open * 30.0)
	var lip_col: Color = _l("lip_color", skin.darkened(0.2).lerp(Color(0.62, 0.3, 0.28), 0.25))
	if 13 in _l("marks", []):
		lip_col = lip_col.lerp(Color(0.62, 0.08, 0.16), 0.6)
	var upper := _quad(left, up_mid, right, 16)
	var lower_line := _quad(left, low_mid, right, 16)
	var u := 4.0 * lips
	var l := 5.4 * lips
	var up_contour := _catmull_open([left, left.lerp(up_mid, 0.5) + Vector2(0, -u * 0.8), up_mid + Vector2(-w * 0.16, -u * 1.15), up_mid + Vector2(0, -u * 0.72), up_mid + Vector2(w * 0.16, -u * 1.15), right.lerp(up_mid, 0.5) + Vector2(0, -u * 0.8), right], 18)
	var up_lip := up_contour.duplicate()
	var ru := upper.duplicate()
	ru.reverse()
	up_lip.append_array(ru)
	var ucols := PackedColorArray()
	for i in up_lip.size():
		ucols.append(lip_col.darkened(0.12) if i < up_contour.size() else lip_col.darkened(0.28))
	var lb := _quad(left, low_mid + Vector2(0, l * 1.8), right, 16)
	var low_lip := lower_line.duplicate()
	var lbr := lb.duplicate()
	lbr.reverse()
	low_lip.append_array(lbr)
	var lcols := PackedColorArray()
	for i in low_lip.size():
		lcols.append(lip_col.darkened(0.12) if i < lower_line.size() else lip_col.lightened(0.04))
	if open > 0.06:
		var mouth := upper.duplicate()
		var rl := lower_line.duplicate()
		rl.reverse()
		mouth.append_array(rl)
		_fill(mouth, MOUTH_IN)
		if cur["teeth"] > 0.3 or open > 0.35:
			var tb := _quad(left.lerp(up_mid, 0.15), up_mid + Vector2(0, minf(9.0, open * 16.0)), right.lerp(up_mid, 0.15), 12)
			var tp := _quad(left.lerp(up_mid, 0.15), up_mid + Vector2(0, -1), right.lerp(up_mid, 0.15), 12)
			var tr := tb.duplicate()
			tr.reverse()
			tp.append_array(tr)
			_shade(tp, mouth, Color(0.9, 0.88, 0.82))
			_shade(_ellipse(up_mid + Vector2(0, 1), w * 0.8, 2.5), mouth, Color(0.6, 0.55, 0.52, 0.5))
			if 10 in _l("marks", []) or "dente_ouro" in _l("extras", []):
				_shade(_ellipse(up_mid + Vector2(6, 3), 3, 3, 10), mouth, Color("#d4a72c"))
		_shade(_ellipse(low_mid + Vector2(0, -3), w * 0.45, 4.5), mouth, Color(0.62, 0.24, 0.26, 0.85))
	_gfill(up_lip, ucols)
	_gfill(low_lip, lcols)
	_glow(low_mid + Vector2(-w * 0.12, l * 0.9), w * 0.28, 2.2, Color(1, 1, 1, 0.22))
	var mline := Color(MOUTH_IN, 0.85)
	_stroke(upper, 0.6, 0.6, mline)
	_soft_line(upper, Color(mline, 0.6), 1.6)
	for p in [left, right]:
		_dci(p, 1.4, Color(_pal["line"], 0.55), true, -1.0, true)
	_soft_line(_quad(_rel(-0.12, 0.84), _rel(0.0, 0.86), _rel(0.12, 0.84), 8), Color(_pal["line"], 0.18), 1.2)


func _p_beard() -> void:
	var b := str(_l("beard", "none"))
	var hc: Color = _pal["beard"]
	if b == "none":
		return
	if b == "mustache_thin":
		_p_mustache(hc, 0.8, 0.55)
		return
	if b == "sideburns":
		for side in [-1, 1]:
			var path := _quad(_rel(side * 0.98, -0.22), _rel(side * 1.0, 0.05), _rel(side * 0.93, 0.3), 10)
			var rb := _ribbon(path, 7.0, 4.0)
			var m := _strip(rb[0], rb[1], 2, _beard_at, 0.0, 0.3)
			_mesh_draw(m)
		return
	if b == "stubble":
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var col := Color(hc.darkened(0.35), 0.3)
		var head := _head_pts(-2)
		for i in 1300:
			var p := _rel(rng.randf_range(-1.0, 1.0), rng.randf_range(0.1, 1.02))
			var bw := _beard_w(p)
			if bw > 0.3 and rng.randf() < bw and Geometry2D.is_point_in_polygon(p, head):
				_dre(Rect2(p, Vector2(0.9, 0.9)), col)
		return
	if b in ["full", "long", "short"]:
		if not _cache.has("beard"):
			var n := 30
			var outline := _head_pts(3.0)
			var lower: Array = []
			for p in outline:
				if p.y > C.y - _H() * 0.08:
					lower.append(p)
			lower.sort_custom(func(a, c2): return a.x < c2.x)
			var outer := PackedVector2Array()
			for k in n + 1:
				var u := float(k) / n
				var x := lerpf(-0.99, 0.99, u)
				var best: Vector2 = lower[0]
				var bd := 99999.0
				for p in lower:
					var dd := absf((p as Vector2).x - (C.x + x * _W()))
					if dd < bd and (p as Vector2).y > C.y:
						bd = dd
						best = p
				var drop := 0.0
				if b == "long":
					drop = _H() * 0.45 * pow(sin(u * PI), 1.5)
				outer.append(best + Vector2(0, drop + 3.0 * sin(u * PI)))
			var inner := PackedVector2Array()
			var nose_b := (_nose_tip().y - C.y) / _H() + 0.08
			for k in n + 1:
				var u := float(k) / n
				var x := lerpf(-0.97, 0.97, u)
				var yy := lerpf(nose_b + 0.02, -0.06, smoothstep(0.3, 0.97, absf(x)))
				inner.append(_rel(x * 0.98, yy))
			var shade := func(p): return _beard_at(p).lerp(_pal["beard"], 0.3)
			var fade := 0.6 if b == "short" else 0.4
			_cache["beard"] = [_strip(inner, outer, 6, shade, fade, 0.0), inner, outer]
		var entry: Array = _cache["beard"]
		var bm: Dictionary = entry[0]
		_mesh_draw(bm)
		_strip_edge(bm, 0.3, 0.6, 1.0, "b")
		var inner2: PackedVector2Array = entry[1]
		var outer2: PackedVector2Array = entry[2]
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 9
		for k in 60:
			var i := rng2.randi_range(0, inner2.size() - 1)
			var p: Vector2 = inner2[i].lerp(outer2[i], rng2.randf_range(0.1, 0.95))
			var dir := (outer2[i] - inner2[i]).normalized() * rng2.randf_range(4.0, 7.0)
			_soft_line(PackedVector2Array([p, p + dir * (0.6 if b == "short" else 1.0)]), Color(_pal["beard_hi"], 0.3) if k % 2 == 0 else Color(_pal["beard_dark"], 0.45), 1.0)
		_p_mustache(hc, 0.9 if b == "short" else 1.0)
	elif b == "goatee":
		var g := _resample_closed(PackedVector2Array([_rel(-0.22, 0.72), _rel(0.22, 0.72), _rel(0.2, 0.96), _rel(0.0, 1.05), _rel(-0.2, 0.96)]), 24)
		var cols := PackedColorArray()
		for p in g:
			cols.append(_beard_at(p))
		_gfill(g, cols, 0.2)
		_p_mustache(hc, 1.0)
	elif b == "mustache":
		_p_mustache(hc, 1.3)


func _p_mustache(_hc: Color, scale: float, thick: float = 1.0) -> void:
	var y := _mouth_y() - 5.0
	var w := _W() * 0.36 * scale
	var top := 6.0 * thick
	var pts := _resample_closed(PackedVector2Array([Vector2(C.x - w, y + 6 * scale * thick), Vector2(C.x - w * 0.5, y - top), Vector2(C.x, y - top + 1), Vector2(C.x + w * 0.5, y - top), Vector2(C.x + w, y + 6 * scale * thick), Vector2(C.x, y + 2 * thick)]), 28)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(_beard_at(p))
	_gfill(pts, cols, 0.25)
	for i in 11:
		var x := lerpf(-w * 0.85, w * 0.85, i / 10.0)
		_soft_line(PackedVector2Array([Vector2(C.x + x, y - 3 * thick), Vector2(C.x + x * 1.12, y + 3.5 * thick)]), Color(_pal["beard_dark"], 0.4), 1.0)


func _p_age_lines() -> void:
	var old := float(_l("_old", 0.0))
	var kid := float(_l("_kid", 0.0))
	if _l("weathered", false):
		old = minf(1.0, old + 0.35)
	old = clampf(old + float(_l("rugas", 0.0)) * 0.5 * (1.0 - kid), 0.0, 1.0)
	var line: Color = _pal["line"]
	var hi: Color = _pal["hi"]
	var tip := _nose_tip()
	var my := _mouth_y()
	var base_a := (0.04 + 0.06 * clampf((float(_l("age", 30)) - 25.0) / 20.0, 0.0, 1.0)) * (1.0 - kid)
	for side in [-1, 1]:
		var fold := _quad(tip + Vector2(side * 11, -3), tip + Vector2(side * 23, 13), Vector2(C.x + side * _W() * 0.42, my + 5), 12)
		_soft_line(fold, Color(line, base_a + old * 0.4), 1.5)
		_soft_line(_offset_path(fold, side * -2.0, side * -2.0), Color(hi, (base_a + old * 0.3) * 0.6), 1.2)
	if old <= 0.08:
		return
	for i in 3:
		var yy := -0.6 + i * 0.075
		var path := PackedVector2Array()
		for k in 13:
			var u := k / 12.0
			path.append(_rel(lerpf(-0.38, 0.38, u), yy + sin(u * PI * 2.0 + i) * 0.008 - sin(u * PI) * 0.025))
		_soft_line(path, Color(line, 0.32 * old), 1.2)
	for side in [-1, 1]:
		var e := _eye_center(side) + Vector2(side * 21, 0)
		for k in 3:
			var a := deg_to_rad(-25.0 + k * 22.0)
			_soft_line(PackedVector2Array([e + Vector2(side * 1, 0).rotated(a * side), e + Vector2(side * 8, 0).rotated(a * side)]), Color(line, 0.38 * old), 1.0)
		_soft_line(_quad(_eye_center(side) + Vector2(-13, 13), _eye_center(side) + Vector2(0, 18), _eye_center(side) + Vector2(13, 12), 10), Color(line, 0.3 * old), 1.1)
		if old > 0.45:
			_soft_line(_quad(Vector2(C.x + side * _W() * 0.36, my + 4), Vector2(C.x + side * _W() * 0.4, my + 16), Vector2(C.x + side * _W() * 0.38, my + 26), 8), Color(line, 0.35 * (old - 0.45) * 2.0), 1.2)
	if old > 0.6:
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for i in 6:
			var p := _rel(rng.randf_range(-0.8, -0.45) if i % 2 == 0 else rng.randf_range(0.45, 0.8), rng.randf_range(-0.5, 0.1))
			_glow(p, rng.randf_range(2.0, 3.5), rng.randf_range(1.6, 3.0), Color(0.45, 0.28, 0.16, 0.35 * (old - 0.6) * 2.5))


func _p_marks() -> void:
	if cur["bruise"] > 0.1:
		_soft_line(PackedVector2Array([_rel(-0.62, 0.25), _rel(-0.44, 0.33)]), Color(0.6, 0.05, 0.05, cur["bruise"]), 2.0)
		_glow(Vector2(C.x + 9, _mouth_y() + 8), 5, 4, Color(0.6, 0.05, 0.05, cur["bruise"]))
		_glow(_rel(-0.5, -0.42), 14, 9, Color(0.4, 0.18, 0.35, 0.45 * cur["bruise"]))


func _p_marks_static() -> void:
	var m: Array = _l("marks", [])
	if 0 in m:
		var a := _rel(-0.78, -0.05)
		var b := _rel(-0.55, 0.42)
		var path := _quad(a, a.lerp(b, 0.5) + Vector2(3, 0), b, 10)
		_stroke(path, 2.6, 1.0, Color(0.78, 0.48, 0.45, 0.85))
		_soft_line(_offset_path(path, -1.6, -1.0), Color(_pal["hi"], 0.5), 0.9)
		for i in 3:
			var p := a.lerp(b, 0.2 + i * 0.3)
			_soft_line(PackedVector2Array([p + Vector2(-3.5, 2), p + Vector2(3.5, -2)]), Color(0.72, 0.42, 0.4, 0.55), 1.2)
	if 2 in m:
		var p2 := _rel(0.7, 0.12)
		_fill(PackedVector2Array([p2, p2 + Vector2(3, 6), p2 + Vector2(0, 10), p2 + Vector2(-3, 6)]), Color(0.12, 0.16, 0.28, 0.75))
	if 6 in m:
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		for i in 46:
			var side := -1 if i % 2 == 0 else 1
			var p := _rel(side * rng.randf_range(0.12, 0.7), rng.randf_range(0.02, 0.36))
			_dci(p, rng.randf_range(0.8, 1.5), Color(0.5, 0.28, 0.16, rng.randf_range(0.3, 0.6)), true, -1.0, true)
	if 15 in m:
		_dci(_rel(-0.45, 0.5), 1.8, Color(0.26, 0.15, 0.1), true, -1.0, true)
		_dci(_rel(0.4, -0.2), 1.4, Color(0.26, 0.15, 0.1), true, -1.0, true)
	if 17 in m:
		_glow(_rel(0.62, 0.25), _W() * 0.22, _H() * 0.2, Color(0.7, 0.35, 0.32, 0.45))
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = 17
		for i in 10:
			var p := _rel(0.62 + rng2.randf_range(-0.15, 0.15), 0.25 + rng2.randf_range(-0.15, 0.15))
			_glow(p, 3, 2, Color(_pal["hi"], 0.35))


func _p_fx() -> void:
	if cur["tears"] > 0.03:
		var a: float = cur["tears"]
		for side in [-1, 1]:
			var start := _eye_center(side) + Vector2(side * 4, 8)
			var stream := PackedVector2Array()
			for i in 9:
				var u := i / 8.0
				stream.append(start + Vector2(side * (4 * u + sin(u * 6 + t) * 1.5), u * 70 * a))
			_soft_line(stream, Color(0.75, 0.86, 1.0, 0.55 * a), 3.0)
			_soft_line(stream, Color(1, 1, 1, 0.5 * a), 1.0)
			var drop_y := fmod(t * 45.0 + (side + 1) * 20.0, 80.0)
			_dci(start + Vector2(side * 4, drop_y), 2.3, Color(0.82, 0.9, 1.0, 0.85 * a), true, -1.0, true)
		for side in [-1, 1]:
			_glow(_eye_center(side) + Vector2(0, 2), 18, 9, Color(0.9, 0.4, 0.45, 0.25 * a))
	if cur["sweat"] > 0.03:
		var a2: float = cur["sweat"]
		for p in [Vector2(-0.45, -0.55), Vector2(0.35, -0.62), Vector2(0.72, -0.3)]:
			var yy := fmod(t * 12.0 + p.x * 30.0, 30.0)
			var d: Vector2 = _rel(p.x, p.y) + Vector2(0, yy)
			var drop := PackedVector2Array([d + Vector2(0, -6), d + Vector2(3, 0), d + Vector2(0, 3), d + Vector2(-3, 0)])
			_fill(drop, Color(0.8, 0.9, 1.0, 0.7 * a2))
			_dci(d + Vector2(-0.8, -1.2), 0.8, Color(1, 1, 1, 0.9 * a2), true, -1.0, true)


func _draw_headwear() -> void:
	if 11 in _l("marks", []):
		var cap_col := Color("#7a1f1f")
		# copa do boné: faixa entre o alto da cabeça e a linha da aba
		var arc := _cranium(9, 188, 352, 30)
		var base := PackedVector2Array()
		for i in arc.size():
			base.append(_rel(lerpf(-1.03, 1.03, float(i) / (arc.size() - 1)), -0.5))
		var shade := func(p: Vector2) -> Color:
			var k := clampf((p.x - C.x) / _W() * 0.5 + 0.5, 0.0, 1.0)
			var top := clampf((C.y - _H() * 0.5 - p.y) / (_H() * 0.5), 0.0, 1.0)
			return cap_col.lightened(0.18 * top).lerp(cap_col.darkened(0.45), k)
		var dm := _strip(arc, base, 4, shade)
		_mesh_draw(dm)
		_strip_edge(dm, 0.35, 0.8, 1.0, "a")
		_soft_line(_quad(_rel(0.0, -1.05), _rel(0.02, -0.8), _rel(0.0, -0.52), 8), Color(cap_col.darkened(0.5), 0.6), 1.2)
		var brim := PackedVector2Array([_rel(-1.02, -0.52), _rel(1.02, -0.52), _rel(1.45, -0.38), _rel(-1.45, -0.38)])
		_gfill(brim, PackedColorArray([cap_col.darkened(0.2), cap_col.darkened(0.45), cap_col.darkened(0.6), cap_col.darkened(0.35)]), 0.2)
		_glow(_rel(0, -0.3), _W() * 0.9, _H() * 0.12, Color(_pal["shadow"], 0.5))
	if "chapeu" in _l("extras", []):
		var crown := PackedVector2Array([_rel(-0.86, -0.72), _rel(0.86, -0.72), _rel(0.7, -1.28), _rel(-0.7, -1.28)])
		_gfill(crown, PackedColorArray([Color(0.32, 0.25, 0.19), Color(0.2, 0.16, 0.12), Color(0.24, 0.19, 0.14), Color(0.36, 0.29, 0.22)]), 0.25)
		_fill(PackedVector2Array([_rel(-0.84, -0.8), _rel(0.84, -0.8), _rel(0.82, -0.9), _rel(-0.82, -0.9)]), Color(0.12, 0.1, 0.08))
		var brim2 := PackedVector2Array([_rel(-1.6, -0.66), _rel(1.6, -0.66), _rel(1.4, -0.78), _rel(-1.4, -0.78)])
		_gfill(brim2, PackedColorArray([Color(0.3, 0.24, 0.18), Color(0.18, 0.14, 0.1), Color(0.2, 0.16, 0.12), Color(0.32, 0.26, 0.2)]), 0.25)
	if "bobes" in _l("extras", []):
		for i in 5:
			var p := _rel(-0.62 + i * 0.31, -0.92 + absf(i - 2) * 0.07)
			_fill(_ellipse(p, 10, 8, 16), Color("#d56a8a"))
			_glow(p + Vector2(-3, -2), 4, 3, Color(1, 1, 1, 0.3))
	if "oculos_testa" in _l("extras", []):
		for side in [-1, 1]:
			var lens := _ellipse(_rel(side * 0.38, -0.62), 16, 8, 18)
			_fill(lens, Color(0.7, 0.78, 0.85, 0.85))
			_soft_line(_closed(lens), Color(0.15, 0.15, 0.17), 1.6)
		_soft_line(PackedVector2Array([_rel(-0.16, -0.62), _rel(0.16, -0.62)]), Color(0.15, 0.15, 0.17), 1.6)
