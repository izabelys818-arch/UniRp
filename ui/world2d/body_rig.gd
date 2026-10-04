extends Control

# Personagem de corpo inteiro, desenhado por código no mesmo traço de tinta dos retratos:
# contornos suaves, sombras em blocos, roupas com costuras e dobras. A cabeça é o mesmo
# rosto animado do retrato (HeadRig). Origem do desenho nos pés; altura total ~206 unidades.

const HeadRig = preload("res://ui/world2d/head_rig.gd")
const INK := Color(0.07, 0.05, 0.05)
const UNITS := 206.0
const HEAD_K := 0.2

var look: Dictionary = {}
var walking: bool = false
var facing: float = 1.0
var highlight: float = 0.0
var phase: float = 0.0
var t: float = 0.0
var seed_n: float = 0.0
var head: Control
var _gaze: float = 0.0


func _ready() -> void:
	head = HeadRig.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.actor_mode = true
	add_child(head)
	if not look.is_empty():
		head.set_look(look)


func set_look(l: Dictionary) -> void:
	look = l
	if head:
		head.set_look(l)
	queue_redraw()


func set_emotion(e: String) -> void:
	if head and head.emotion != e:
		head.set_emotion(e)


func talk(seconds: float) -> void:
	if head:
		head.talk(seconds)


func _process(delta: float) -> void:
	t += delta
	if walking:
		phase += delta * 7.5
	else:
		phase = lerpf(phase, roundf(phase / PI) * PI, minf(delta * 8.0, 1.0))
	_gaze = lerpf(_gaze, facing * 0.8 if walking else 0.0, minf(delta * 5.0, 1.0))
	if head:
		head.target["gaze_x"] = _gaze
		var s := size.y / UNITS
		var hs := 190.0 * HEAD_K * s
		head.size = Vector2(hs, hs)
		head.position = Vector2(size.x / 2.0 - hs / 2.0 + facing * (1.5 if walking else 0.0) * s, size.y + (-182.0 + _bob()) * s - hs / 2.0)
	queue_redraw()


func _bob() -> float:
	return (absf(sin(phase)) * -2.2) if walking else sin(t * 1.6 + seed_n) * 0.7


# ---------- primitivas ----------

func _catmull(pts: Array, closed: bool, samples: int = 5) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	var segs := n if closed else n - 1
	for i in segs:
		var p0: Vector2 = pts[(i - 1 + n) % n] if (closed or i > 0) else pts[0]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % n]
		var p3: Vector2 = pts[(i + 2) % n] if (closed or i + 2 < n) else pts[n - 1]
		for j in samples:
			var u := float(j) / samples
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u))
	if not closed:
		out.append(pts[n - 1])
	return out


func _ok(poly: PackedVector2Array) -> bool:
	return poly.size() >= 3 and not Geometry2D.triangulate_polygon(poly).is_empty()


func _fill(poly: PackedVector2Array, c: Color, w: float = 1.7) -> void:
	if not _ok(poly):
		return
	draw_colored_polygon(poly, c)
	if w > 0.0:
		var closed := poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, INK, w, true)


func _shade(poly: PackedVector2Array, mask: PackedVector2Array, c: Color) -> void:
	if not _ok(poly):
		return
	for piece in Geometry2D.intersect_polygons(poly, mask):
		if _ok(piece):
			draw_colored_polygon(piece, c)


func _rmask(cx: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(cx, -230), Vector2(cx + 80, -230), Vector2(cx + 80, 20), Vector2(cx, 20)])


func _ellipse(c: Vector2, rx: float, ry: float, n: int = 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _seam(pts: Array, c: Color = Color(INK, 0.55), w: float = 1.0) -> void:
	draw_polyline(_catmull(pts, false, 4), c, w, true)


# Membro com largura variável ao longo de um caminho.
func _limb(path: Array, widths: Array) -> PackedVector2Array:
	var left: Array = []
	var right: Array = []
	var n := path.size()
	for i in n:
		var a: Vector2 = path[maxi(i - 1, 0)]
		var b: Vector2 = path[mini(i + 1, n - 1)]
		var d := (b - a).normalized()
		var nr := Vector2(-d.y, d.x)
		var p: Vector2 = path[i]
		left.append(p + nr * float(widths[i]) / 2.0)
		right.append(p - nr * float(widths[i]) / 2.0)
	right.reverse()
	var last: Vector2 = path[n - 1]
	var prev: Vector2 = path[n - 2]
	var first: Vector2 = path[0]
	var second: Vector2 = path[1]
	var cap_end: Vector2 = last + (last - prev).normalized() * float(widths[n - 1]) * 0.45
	var cap_start: Vector2 = first - (second - first).normalized() * float(widths[0]) * 0.45
	var out := PackedVector2Array()
	out.append_array(_catmull(left, false, 5))
	out.append(cap_end)
	out.append_array(_catmull(right, false, 5))
	out.append(cap_start)
	return out


func _lerp_table(tab: Array, y: float) -> float:
	if y <= float(tab[0][0]):
		return float(tab[0][1])
	for i in range(1, tab.size()):
		if y <= float(tab[i][0]):
			var u := (y - float(tab[i - 1][0])) / (float(tab[i][0]) - float(tab[i - 1][0]))
			return lerpf(float(tab[i - 1][1]), float(tab[i][1]), u)
	return float(tab[tab.size() - 1][1])


# ---------- desenho ----------

func _draw() -> void:
	if look.is_empty():
		return
	var s := size.y / UNITS
	var lean := facing * 0.025 if walking else 0.0
	var female: bool = str(look.get("gender", "")) == "mulher"
	var skin: Color = look.get("skin", Color("#e8bf9c"))
	var skin_sh: Color = skin.darkened(0.2).lerp(Color(0.35, 0.1, 0.2), 0.12)
	var c1: Color = look.get("clothes_color", Color("#4a5260"))
	var c2: Color = look.get("clothes_color2", Color("#dddddd"))
	var style: String = str(look.get("clothes", "camiseta"))
	var sh_mul: float = float(look.get("shoulders", 1.0))
	var nk: float = float(look.get("neck", 1.0))
	var age: int = int(look.get("age", 30))
	var body_k: float = clampf(float(look.get("face_w", 1.0)), 0.88, 1.2)
	var bob: float = _bob()
	var sway: float = sin(phase)

	# sombra no chão
	draw_set_transform(Vector2(size.x / 2.0, size.y), 0.0, Vector2(s, s * 0.16))
	for i in 3:
		draw_colored_polygon(_ellipse(Vector2.ZERO, 34.0 - i * 7.0, 34.0 - i * 7.0, 20), Color(0, 0, 0, 0.18))
	draw_set_transform(Vector2(size.x / 2.0, size.y), lean, Vector2(s, s))

	# ---- calças / pernas ----
	var skirt: bool = style == "vestido"
	var pants: Color = c2.darkened(0.55) if c2.get_luminance() > 0.5 else c2.lightened(0.15)
	match style:
		"jeans": pants = Color("#2f4768")
		"social", "terno", "farda": pants = c1.darkened(0.1)
		"couro", "sobretudo", "batina": pants = Color("#1b1b1f")
		"academia": pants = Color("#26262c")
		"havaiana": pants = Color("#d9c9a2")
		"macacao": pants = c1
		"uniforme", "jaleco", "avental": pants = Color("#2b2f38")
		"rasgada": pants = Color("#4d493f")
		"time": pants = Color("#222831")
	if style in ["camiseta", "moletom", "blusa", "regata"] and pants.get_luminance() > 0.45:
		pants = Color("#3a4a63")
	var hip_off: float = 7.6 if female else 7.0
	var thigh_w: float = (19.5 if female else 19.0) * body_k
	for side in [-1, 1]:
		var lp: float = phase + (0.0 if side > 0 else PI)
		var stride: float = sin(lp) * 11.0 if walking else 0.0
		var lift: float = maxf(0.0, cos(lp)) * 7.0 if walking else 0.0
		var hx: float = side * hip_off
		var hipp := Vector2(hx, -94.0 + bob * 0.5)
		var knee := Vector2(hx + stride * 0.45 + side * 0.8, -51.0 - lift * 0.55)
		var ankle := Vector2(hx + stride * 0.9 + side * 1.8, -8.5 - lift)
		var legpoly := _limb([hipp, knee, ankle], [thigh_w, 14.0 * body_k, 9.6])
		var lcol: Color = skin if skirt else pants
		_fill(legpoly, lcol)
		_shade(legpoly, _rmask(hx + 1.5), Color(lcol.darkened(0.3), 0.5))
		if not skirt:
			_seam([hipp + Vector2(side * thigh_w * 0.32, 6), knee + Vector2(side * 4.4, 0), ankle + Vector2(side * 3.4, -2)], Color(INK, 0.35), 0.9)
			draw_line(knee + Vector2(-4.5, -1.5), knee + Vector2(4.5, 1.0), Color(INK, 0.3), 1.0, true)
			if style in ["jeans", "social", "terno", "farda"]:
				_seam([hipp + Vector2(-1.2 * side, 10), knee + Vector2(-1.2 * side, 0), ankle + Vector2(-1.0 * side, -3)], Color(INK, 0.28), 0.8)
			if style == "rasgada":
				_fill(PackedVector2Array([knee + Vector2(-4, -3), knee + Vector2(3, -4), knee + Vector2(4, 4), knee + Vector2(-3, 5)]), skin, 1.0)
		var shoe_c := Color("#1d1b1a")
		if style in ["havaiana"]:
			shoe_c = Color("#c9712c")
		elif style in ["academia", "time"]:
			shoe_c = Color("#e9e6e0")
		elif style in ["couro", "social", "terno", "farda", "batina", "uniforme"]:
			shoe_c = Color("#17120f")
		var shoe_c0 := ankle + Vector2(side * 1.5 + stride * 0.15, 4.2)
		_fill(_ellipse(shoe_c0, 8.6, 4.6, 16), shoe_c)
		draw_arc(shoe_c0 + Vector2(0, -1.2), 6.0, PI * 1.1, PI * 1.9, 8, Color(1, 1, 1, 0.22), 1.2, true)
		draw_line(shoe_c0 + Vector2(-7.5, 3.6), shoe_c0 + Vector2(7.5, 3.6), Color(0.85, 0.85, 0.8), 1.4, true)
	# cintura/quadril (calça)
	var hem_y: float = -100.0
	if style in ["social", "terno", "farda", "couro", "sobretudo", "uniforme", "batina"]:
		hem_y = -108.0
	var pant_poly := PackedVector2Array([Vector2(-13.5 * body_k, -111), Vector2(13.5 * body_k, -111), Vector2(thigh_w * 0.62 + hip_off, -95), Vector2(thigh_w * 0.62 + hip_off, -86), Vector2(0, -81), Vector2(-thigh_w * 0.62 - hip_off, -86), Vector2(-thigh_w * 0.62 - hip_off, -95)])
	if not skirt:
		_fill(pant_poly, pants, 1.5)
		_shade(pant_poly, _rmask(1.0), Color(pants.darkened(0.3), 0.5))
		draw_line(Vector2(0, -81), Vector2(0, -92), Color(INK, 0.4), 1.0, true)
		if style != "macacao":
			var belt := PackedVector2Array([Vector2(-13.8 * body_k, -112), Vector2(13.8 * body_k, -112), Vector2(14.3 * body_k, -108), Vector2(-14.3 * body_k, -108)])
			_fill(belt, Color("#2a1d14") if style != "academia" else Color("#111111"), 1.2)
			if style != "academia":
				_fill(PackedVector2Array([Vector2(-2.2, -111.5), Vector2(2.2, -111.5), Vector2(2.2, -108.4), Vector2(-2.2, -108.4)]), Color("#c9a64a"), 0.8)
		if style == "jeans":
			_seam([Vector2(-11, -107), Vector2(-5, -100), Vector2(-3, -92)], Color(INK, 0.4), 0.9)
			_seam([Vector2(11, -107), Vector2(5, -100), Vector2(3, -92)], Color(INK, 0.4), 0.9)

	# ---- tronco ----
	var half: Array
	if female:
		half = [[-165.0, 7.5 * nk], [-160.0, 11.0], [-156.0, 15.5 * sh_mul], [-150.0, 16.8 * sh_mul], [-141.0, 16.2], [-133.0, 14.2], [-122.0, 11.6], [-112.0, 10.6], [-102.0, 14.5], [-92.0, 17.8]]
	else:
		half = [[-165.0, 8.5 * nk], [-160.0, 13.0], [-157.0, 19.5 * sh_mul], [-150.0, 21.2 * sh_mul], [-140.0, 19.2], [-128.0, 16.4], [-114.0, 14.6], [-102.0, 15.6], [-92.0, 16.6]]
	for hrow in half:
		hrow[1] = float(hrow[1]) * (1.0 + (body_k - 1.0) * 0.6) * 1.12
	var hem: float = hem_y if not skirt else -104.0
	var left_pts: Array = []
	for y in [-163.0, -157.0, -150.0, -140.0, -128.0, -118.0, hem]:
		left_pts.append(Vector2(-_lerp_table(half, y), y))
	var torso_pts: Array = left_pts.duplicate()
	var rv: Array = left_pts.duplicate()
	rv.reverse()
	for p in rv:
		var pv: Vector2 = p
		torso_pts.append(Vector2(-pv.x, pv.y))
	var torso := _catmull(torso_pts, true, 4)
	for i in torso.size():
		if torso[i].y < -110.0:
			torso[i].y += bob * 0.4
	# braços primeiro (ombro natural)
	_draw_arms(skin, skin_sh, c1, c2, style, female, sway, body_k, bob, half)
	if style == "regata":
		_fill(torso, skin)
		_shade(torso, _rmask(2.0), Color(skin_sh, 0.55))
	else:
		_fill(torso, c1)
		_shade(torso, _rmask(2.0), Color(c1.darkened(0.35), 0.55))
		_shade(torso, PackedVector2Array([Vector2(-40, -160), Vector2(-9, -160), Vector2(-14, -100), Vector2(-40, -100)]), Color(c1.lightened(0.12), 0.35))
	# pescoço
	var neck_w: float = 5.6 * nk
	var neck := PackedVector2Array([Vector2(-neck_w, -170.0 + bob), Vector2(neck_w, -170.0 + bob), Vector2(neck_w * 1.25, -161.0 + bob), Vector2(-neck_w * 1.25, -161.0 + bob)])
	_fill(neck, skin, 1.4)
	_shade(neck, _rmask(0.0), Color(skin_sh, 0.6))

	_clothes_detail(style, c1, c2, skin, skin_sh, bob, hem)

	if highlight > 0.01:
		draw_arc(Vector2(0, -100), 112.0, 0.0, TAU, 56, Color(1.0, 0.86, 0.45, 0.3 * highlight), 3.0, true)


func _draw_arms(skin: Color, skin_sh: Color, c1: Color, c2: Color, style: String, female: bool, sway: float, body_k: float, bob: float, half: Array) -> void:
	var long_sleeve: bool = style in ["moletom", "couro", "social", "terno", "sobretudo", "farda", "jaleco", "batina", "rasgada"]
	var short_sleeve: bool = style in ["camiseta", "time", "academia", "uniforme", "blusa", "havaiana", "avental", "jeans"]
	var sleeve_col: Color = c2 if style == "jaleco" else c1
	for side in [-1, 1]:
		var swing: float = sway * 6.0 * side if walking else 0.0
		var sx: float = side * (_lerp_table(half, -151.0) - 0.5)
		var sp := Vector2(sx, -150.0 + bob * 0.5)
		var out: float = side * 3.2
		var elbow := Vector2(sx + out + swing * 0.35, -123.0 + bob * 0.3)
		var wrist := Vector2(sx + out * 1.6 + swing * 0.9, -97.0 + bob * 0.2 + absf(swing) * 0.5)
		var aw: float = (12.0 if female else 13.5) * body_k
		var arm := _limb([sp, elbow, wrist], [aw, aw * 0.85, 8.0])
		var mask_x: float = sx - 0.5 if side > 0 else sx + 3.0
		_fill(arm, skin)
		_shade(arm, _rmask(mask_x), Color(skin_sh, 0.55))
		var hand_c := wrist + Vector2(side * 0.6, 4.6)
		_fill(_ellipse(hand_c, 4.0, 5.4, 12), skin, 1.3)
		draw_line(hand_c + Vector2(-side * 3.4, -1.5), hand_c + Vector2(-side * 2.6, 3.0), Color(INK, 0.55), 1.0, true)
		draw_line(hand_c + Vector2(1.0, 1.0), hand_c + Vector2(1.0, 5.0), Color(INK, 0.35), 0.8, true)
		if long_sleeve or short_sleeve:
			var path: Array = [sp + Vector2(0, -2.0), sp.lerp(elbow, 0.55)]
			if long_sleeve:
				path.append(elbow)
				path.append(elbow.lerp(wrist, 0.86))
			else:
				path.append(sp.lerp(elbow, 0.95))
			var ws: Array = []
			for i in path.size():
				ws.append(aw + 2.2 - 0.8 * i)
			var sl := _limb(path, ws)
			_fill(sl, sleeve_col)
			_shade(sl, _rmask(mask_x), Color(sleeve_col.darkened(0.4), 0.5))
			var endp: Vector2 = path[path.size() - 1]
			draw_line(endp + Vector2(-aw * 0.55, 0), endp + Vector2(aw * 0.55, 0), Color(INK, 0.6), 1.2, true)
			if long_sleeve:
				draw_line(elbow + Vector2(-aw * 0.4, 1.0), elbow + Vector2(aw * 0.15, 4.0), Color(INK, 0.3), 1.0, true)
				if style in ["social", "terno", "farda", "jaleco"]:
					draw_line(endp + Vector2(-aw * 0.5, -1.6), endp + Vector2(aw * 0.5, -1.6), c2.lightened(0.1), 1.6, true)


func _v(pts: Array) -> PackedVector2Array:
	return PackedVector2Array(pts)


func _clothes_detail(style: String, c1: Color, c2: Color, skin: Color, skin_sh: Color, bob: float, hem: float) -> void:
	var by: float = bob * 0.4
	match style:
		"camiseta", "time", "academia", "rasgada", "havaiana", "uniforme":
			var nl: Array = [Vector2(-8.5, -163 + by), Vector2(-5, -156 + by), Vector2(0, -154 + by), Vector2(5, -156 + by), Vector2(8.5, -163 + by)]
			_fill(_v([Vector2(-8, -164 + by), Vector2(8, -164 + by), Vector2(5, -158 + by), Vector2(0, -156 + by), Vector2(-5, -158 + by)]), skin, 0.0)
			draw_polyline(_catmull(nl, false, 4), c1.darkened(0.45), 2.4, true)
			draw_polyline(_catmull(nl, false, 4), INK, 1.1, true)
			if style == "time":
				for x in [-9.0, 0.0, 9.0]:
					draw_rect(Rect2(x - 2.2, -150, 4.4, 40), Color(c2, 0.9))
			if style == "uniforme":
				draw_rect(Rect2(5, -140, 9, 5), Color(0.95, 0.95, 0.9))
				draw_rect(Rect2(5, -140, 9, 5), Color(INK, 0.7), false, 0.9)
			if style == "havaiana":
				for p in [Vector2(-10, -138), Vector2(8, -128), Vector2(-4, -114), Vector2(12, -112), Vector2(-12, -122)]:
					_fill(_ellipse(p, 3.4, 2.4, 8), c2, 0.7)
			if style == "rasgada":
				for p in [Vector2(-9, -126), Vector2(10, -116), Vector2(0, -105)]:
					_fill(_v([p, p + Vector2(4, -3), p + Vector2(6, 1), p + Vector2(2, 4)]), skin, 0.7)
			_folds(hem, by, c1)
		"moletom":
			_fill(_v([Vector2(-11, -164 + by), Vector2(-9, -154 + by), Vector2(0, -150 + by), Vector2(9, -154 + by), Vector2(11, -164 + by), Vector2(7, -158 + by), Vector2(0, -156 + by), Vector2(-7, -158 + by)]), c1.darkened(0.2), 1.3)
			draw_line(Vector2(-3, -154 + by), Vector2(-3.4, -138 + by), c2, 1.4, true)
			draw_line(Vector2(3, -154 + by), Vector2(3.4, -138 + by), c2, 1.4, true)
			_fill(_v([Vector2(-11, -124 + by), Vector2(11, -124 + by), Vector2(13, -106), Vector2(-13, -106)]), c1.darkened(0.12), 1.2)
			draw_line(Vector2(0, -124 + by), Vector2(0, -106), Color(INK, 0.35), 1.0, true)
			draw_line(Vector2(-14, hem + 1), Vector2(14, hem + 1), c1.darkened(0.4), 2.4, true)
			_folds(hem, by, c1)
		"couro", "sobretudo", "jaleco", "farda", "social", "terno", "batina":
			var inner: Color = c2
			if style in ["couro", "sobretudo"]:
				inner = Color("#222226")
			elif style == "batina":
				inner = Color("#111111")
			elif style == "jaleco":
				inner = c1
			_fill(_v([Vector2(-9, -164 + by), Vector2(0, -126 + by), Vector2(9, -164 + by)]), inner, 1.2)
			if style != "batina":
				var col_c: Color = inner.lightened(0.08) if style in ["social", "terno"] else c1.lightened(0.15)
				_fill(_v([Vector2(-9, -164 + by), Vector2(-14, -154 + by), Vector2(-4, -148 + by), Vector2(0, -156 + by)]), col_c, 1.1)
				_fill(_v([Vector2(9, -164 + by), Vector2(14, -154 + by), Vector2(4, -148 + by), Vector2(0, -156 + by)]), col_c.darkened(0.2), 1.1)
			if style == "terno":
				_fill(_v([Vector2(-1.8, -154 + by), Vector2(1.8, -154 + by), Vector2(2.6, -118), Vector2(0, -112), Vector2(-2.6, -118)]), Color("#7a1b26"), 1.0)
			if style in ["social", "farda"]:
				for i in 5:
					draw_circle(Vector2(0, -140 + i * 7 + by), 0.9, Color(INK, 0.55))
			if style in ["couro", "sobretudo", "terno", "farda", "jaleco"]:
				draw_line(Vector2(0, -126 + by), Vector2(0, hem), Color(INK, 0.8), 1.5, true)
				draw_line(Vector2(-9, -164 + by), Vector2(-5, -140 + by), Color(INK, 0.5), 1.0, true)
				draw_line(Vector2(9, -164 + by), Vector2(5, -140 + by), Color(INK, 0.5), 1.0, true)
				for sgn in [-1, 1]:
					_fill(_v([Vector2(sgn * 5, -118), Vector2(sgn * 12, -118), Vector2(sgn * 12.5, -112), Vector2(sgn * 5, -112)]), c1.darkened(0.12), 0.9)
			if style == "couro":
				draw_line(Vector2(-10, -150 + by), Vector2(-13, -118), Color(1, 1, 1, 0.22), 1.6, true)
				for i in 4:
					draw_line(Vector2(-12, -144 + i * 9), Vector2(-9, -143 + i * 9), Color(1, 1, 1, 0.18), 1.0, true)
			if style == "farda":
				_fill(_ellipse(Vector2(8, -135 + by), 3.2, 3.8, 8), Color("#c9a227"), 0.9)
			if style == "jaleco":
				draw_line(Vector2(-12, -128), Vector2(-7, -128), Color(0.2, 0.4, 0.8, 0.7), 1.0, true)
			_folds(hem, by, c1)
		"vestido":
			var sk: Array = [Vector2(-11, -113), Vector2(11, -113), Vector2(15, -95), Vector2(24, -52), Vector2(14, -50), Vector2(0, -47), Vector2(-14, -50), Vector2(-24, -52), Vector2(-15, -95)]
			var skc := _catmull(sk, true, 3)
			_fill(skc, c1)
			_shade(skc, _rmask(1.0), Color(c1.darkened(0.4), 0.55))
			for i in 5:
				_seam([Vector2(-17 + i * 8.5, -108), Vector2(-20 + i * 10, -80), Vector2(-22 + i * 11, -52)], Color(c1.darkened(0.5), 0.6), 1.0)
			draw_rect(Rect2(-11.4, -116, 22.8, 4.5), c2 if c2 != c1 else c1.lightened(0.2))
			draw_rect(Rect2(-11.4, -116, 22.8, 4.5), Color(INK, 0.8), false, 1.0)
			var nv := _v([Vector2(-8, -164 + by), Vector2(0, -146 + by), Vector2(8, -164 + by)])
			_fill(nv, skin, 1.2)
			_shade(nv, _rmask(0.0), Color(skin_sh, 0.55))
		"blusa":
			var nv := _v([Vector2(-8, -164 + by), Vector2(0, -145 + by), Vector2(8, -164 + by)])
			_fill(nv, skin, 1.2)
			_shade(nv, _rmask(0.0), Color(skin_sh, 0.55))
			draw_line(Vector2(-12, hem - 1), Vector2(12, hem - 1), c1.darkened(0.35), 2.0, true)
			_folds(hem, by, c1)
		"regata":
			var tank: Array = [Vector2(-14, -108), Vector2(-14, -130), Vector2(-9, -152 + by), Vector2(-5.5, -152 + by), Vector2(0, -140 + by), Vector2(5.5, -152 + by), Vector2(9, -152 + by), Vector2(14, -130), Vector2(14, -108)]
			var tk := _catmull(tank, true, 3)
			_fill(tk, c1)
			_shade(tk, _rmask(2.0), Color(c1.darkened(0.4), 0.5))
		"macacao", "avental":
			var strap_c: Color = c2 if style == "avental" else c1.darkened(0.15)
			for sgn in [-1, 1]:
				_fill(_v([Vector2(sgn * 4, -158 + by), Vector2(sgn * 9, -158 + by), Vector2(sgn * 10, -118), Vector2(sgn * 5, -118)]), strap_c, 1.1)
			_fill(_v([Vector2(-10, -134), Vector2(10, -134), Vector2(12, -106), Vector2(-12, -106)]), c2 if style == "avental" else c1.darkened(0.1), 1.1)
			_fill(_v([Vector2(-5, -128), Vector2(5, -128), Vector2(5, -120), Vector2(-5, -120)]), Color(INK, 0.15), 0.8)
			draw_circle(Vector2(-8.5, -131), 1.2, Color("#c9a64a"))
			draw_circle(Vector2(8.5, -131), 1.2, Color("#c9a64a"))
		"jeans":
			_fill(_v([Vector2(-7, -164 + by), Vector2(0, -132 + by), Vector2(7, -164 + by)]), c2, 1.0)
			draw_line(Vector2(0, -132 + by), Vector2(0, hem), Color(INK, 0.6), 1.2, true)
			for sgn in [-1, 1]:
				_fill(_v([Vector2(sgn * 6, -146), Vector2(sgn * 13, -146), Vector2(sgn * 13, -139), Vector2(sgn * 6, -139)]), c1.darkened(0.1), 0.9)
				draw_circle(Vector2(sgn * 9.5, -143), 0.8, Color("#c9a64a"))
			_folds(hem, by, c1)
		_:
			_folds(hem, by, c1)


func _folds(hem: float, by: float, c: Color) -> void:
	var fc := Color(c.darkened(0.55), 0.45)
	_seam([Vector2(-12, hem - 4), Vector2(-7, hem - 10), Vector2(-9, hem - 16)], fc, 1.0)
	_seam([Vector2(10, hem - 3), Vector2(6, hem - 11), Vector2(8, hem - 18)], fc, 1.0)
	_seam([Vector2(-5, -128 + by), Vector2(-3, -120), Vector2(-6, -112)], Color(fc, 0.3), 0.9)
