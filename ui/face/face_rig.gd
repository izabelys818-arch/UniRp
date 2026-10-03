extends "res://ui/face/face_base.gd"

# Cabeça: contorno anatômico, olhos amendoados, nariz, lábios, sobrancelhas e cabelo em mechas.

const BROW_SHAPES := [
	# [inner_dy, peak_t, peak_dy, outer_dy, espessura, angular]
	[0.0, 0.6, -4.0, 2.0, 1.0, false],
	[0.0, 0.5, -1.0, 1.0, 1.0, false],
	[1.0, 0.55, -8.0, 4.0, 0.9, false],
	[0.0, 0.66, -7.0, 6.0, 1.0, true],
	[0.0, 0.5, -3.0, 2.0, 1.6, false],
	[0.0, 0.6, -5.0, 3.0, 0.55, false],
	[0.0, 0.6, -4.0, 2.0, 1.25, false],
]


func _W() -> float:
	return 70.0 * float(_l("face_w", 1.0))


func _H() -> float:
	return 108.0 * float(_l("face_len", 1.0))


func _rel(x: float, y: float) -> Vector2:
	return C + Vector2(x * _W(), y * _H())


func _catmull(pts: Array, samples: int = 6) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var p0: Vector2 = pts[(i - 1 + n) % n]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % n]
		var p3: Vector2 = pts[(i + 2) % n]
		for s in samples:
			var u := float(s) / samples
			var u2 := u * u
			var u3 := u2 * u
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3))
	return out


func _head_pts(grow: float = 0.0) -> PackedVector2Array:
	var cheek := float(_l("cheek", 1.0))
	var jaw := float(_l("jaw", 0.78))
	var chin_w := float(_l("chin_w", 0.34))
	var right := [
		Vector2(0.0, -0.97), Vector2(0.56, -0.9), Vector2(0.88, -0.62), Vector2(0.97, -0.3),
		Vector2(0.99 * cheek, 0.02), Vector2(0.97 * (cheek * 0.5 + jaw * 0.5), 0.3), Vector2(jaw, 0.6),
		Vector2(chin_w * 1.3, 0.87), Vector2(chin_w * 0.85, 0.975),
	]
	var pts: Array = []
	for p in right:
		pts.append(p)
	pts.append(Vector2(0.0, 1.0))
	for i in range(right.size() - 1, 0, -1):
		pts.append(Vector2(-right[i].x, right[i].y))
	var w := _W() + grow
	var h := _H() + grow
	var abs_pts: Array = pts.map(func(p): return C + Vector2(p.x * w, p.y * h))
	return _catmull(abs_pts)


func _head_shadow_mask() -> PackedVector2Array:
	return PackedVector2Array([_rel(0.36, -1.3), _rel(0.55, -0.55), _rel(0.5, -0.18), _rel(0.72, 0.08), _rel(0.64, 0.42), _rel(0.42, 0.76), _rel(0.12, 1.3), _rel(3.0, 1.3), _rel(3.0, -1.3)])


func _eye_center(side: int) -> Vector2:
	return C + Vector2(side * _W() * 0.42, -_H() * 0.04)


func _nose_tip() -> Vector2:
	var bend := 4.0 if 16 in _l("marks", []) else 0.0
	return C + Vector2(bend, _H() * 0.37 * float(_l("nose_len", 1.0)))


func _mouth_y() -> float:
	return C.y + _H() * 0.6


func _hair_color() -> Color:
	return _l("hair_color", Color("#2a1d16"))


func _cranium(th: float, from_deg: float = 192.0, to_deg: float = 348.0, n: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := deg_to_rad(lerpf(from_deg, to_deg, float(i) / n))
		pts.append(C + Vector2(cos(a) * (_W() * 0.99 + th), sin(a) * (_H() * 0.97 + th)))
	return pts


func _hairline(height: float, part: float = 0.0) -> PackedVector2Array:
	var age := float(_l("age", 30))
	var recede := 0.08 if age > 50 and str(_l("gender", "")) == "homem" else 0.0
	var rt := _rel(0.97, -0.26)
	var lt := _rel(-0.97, -0.26)
	var top := _rel(part, -height)
	var a := _quad(rt, _rel(0.8, -0.62 - recede), top, 10)
	var b := _quad(top, _rel(-0.8, -0.62 - recede), lt, 10)
	b.remove_at(0)
	a.append_array(b)
	return a


func _draw_back_hair() -> void:
	var hc := _hair_color()
	var dark := _shadow_of(hc).darkened(0.12)
	var w := _W()
	var h := _H()
	match str(_l("hair", "curto")):
		"medio":
			var pts := _cranium(10, 170, 370)
			pts.append(_rel(1.12, 0.62))
			pts.append(_rel(-1.12, 0.62))
			_poly(_sorted_around(pts), dark)
		"longo":
			var pts := PackedVector2Array([_rel(-1.05, -0.5), _rel(-1.2, 0.6), _rel(-1.3, 1.75), _rel(-0.6, 1.95), _rel(0.6, 1.95), _rel(1.3, 1.75), _rel(1.2, 0.6), _rel(1.05, -0.5)])
			pts.append_array(_cranium(12))
			_poly(_sorted_around(pts), dark)
			for i in 9:
				var x := lerpf(-1.25, 1.25, i / 8.0)
				if absf(x) < 0.9:
					continue
				_line(_quad(_rel(x * 0.9, -0.3), _rel(x * 1.05, 0.7), _rel(x, 1.85)), Color(INK, 0.5), 1.4)
		"black_power":
			var cloud := PackedVector2Array()
			for i in 40:
				var a := TAU * i / 40.0
				var r := 1.0 + (0.05 if i % 2 == 0 else 0.0)
				cloud.append(C + Vector2(0, -h * 0.35) + Vector2(cos(a) * w * 1.6 * r, sin(a) * h * 1.05 * r))
			_poly(cloud, hc)
			_shade(cloud, _head_shadow_mask(), dark)
			_stipple(cloud, hc.lightened(0.2), 260, 3)
			_line(_closed(cloud), INK, 3.0)
		"dreads", "trancas":
			for i in 18:
				var x := lerpf(-1.15, 1.15, i / 17.0)
				if absf(x) < 0.7:
					continue
				var start := _rel(x * 0.95, -0.4)
				var end := _rel(x * 1.15, 1.6 + (i % 3) * 0.12)
				_line(PackedVector2Array([start, end]), INK, 12.0 if _l("hair", "") == "dreads" else 9.0)
				_line(PackedVector2Array([start, end]), hc, 8.0 if _l("hair", "") == "dreads" else 5.5)
				for k in 6:
					var p := start.lerp(end, (k + 0.5) / 6.0)
					_line(PackedVector2Array([p + Vector2(-3, -2), p + Vector2(3, 2)]), Color(INK, 0.6), 1.2)
		"rabo":
			var tail := PackedVector2Array([_rel(0.2, -1.0), _rel(0.75, -0.95), _rel(1.25, 0.1), _rel(1.15, 1.2), _rel(0.95, 0.4)])
			_poly(tail, dark)
			_line(_closed(tail), INK, 3.0)
			for i in 4:
				_line(_quad(_rel(0.7, -0.8), _rel(1.15 + i * 0.03, 0.2), _rel(1.0 + i * 0.05, 1.05)), Color(INK, 0.45), 1.3)
		"coque":
			var bun := _ellipse(_rel(0.0, -1.08), w * 0.42, h * 0.24)
			_poly(bun, hc)
			_shade(bun, _head_shadow_mask(), dark)
			for i in 4:
				_line(_quad(_rel(-0.3 + i * 0.15, -1.2), _rel(0.0, -1.0), _rel(0.35 - i * 0.12, -0.95)), Color(INK, 0.5), 1.3)
			_line(_closed(bun), INK, 3.0)


func _draw_head() -> void:
	var skin := _skin()
	var w := _W()
	var h := _H()
	var sh := _shadow_of(skin)
	for side in [-1, 1]:
		var top := C + Vector2(side * w * 0.95, -h * 0.1)
		var ear := PackedVector2Array([top, top + Vector2(side * 10, -4), top + Vector2(side * 14, 12), top + Vector2(side * 11, 34), top + Vector2(side * 4, 44), top + Vector2(0, 38)])
		_poly(ear, skin if side == -1 else sh)
		_line(_quad(top + Vector2(side * 4, 4), top + Vector2(side * 11, 14), top + Vector2(side * 5, 30), 6), Color(INK, 0.55), 1.6)
		_line(_closed(ear), INK, 2.6)
		if 4 in _l("marks", []):
			draw_circle(top + Vector2(side * 6, 40), 2.4, Color("#d9d9d9"))
			draw_circle(top + Vector2(side * 12, 8), 2.0, Color("#d9d9d9"))
		if 14 in _l("marks", []):
			_line(_closed(_ellipse(top + Vector2(side * 5, 52), 5, 8, 14)), Color("#d4a72c"), 2.2)
	var head := _head_pts()
	_poly(head, skin)
	_shade(head, _head_shadow_mask(), sh)
	_shade(head, _ellipse(_rel(0.0, 1.1), w * 1.0, h * 0.2), sh)
	_shade(head, PackedVector2Array([_rel(-1.0, 0.1), _rel(-0.68, 0.16), _rel(-0.74, 0.46), _rel(-1.0, 0.42)]), Color(sh, 0.55))
	for side in [-1, 1]:
		_poly(_ellipse(_eye_center(side) + Vector2(side * 2, -5), w * 0.3, h * 0.11), Color(sh, 0.5))
	_poly(_ellipse(_rel(-0.32, -0.56), w * 0.28, h * 0.1), _light_of(skin))
	_poly(_ellipse(_rel(-0.62, 0.08), w * 0.16, h * 0.045), _light_of(skin))
	if _l("double_chin", false):
		_line(_quad(_rel(-0.42, 0.98), _rel(0.0, 1.12), _rel(0.42, 0.98)), INK, 2.4)
	if _l("hollow", false):
		for side in [-1, 1]:
			_shade(head, _ellipse(_rel(side * 0.66, 0.36), w * 0.18, h * 0.16), sh.darkened(0.1))
	_draw_age_lines()
	_draw_cheeks()
	_draw_beard()
	for side in [-1, 1]:
		_draw_eye(side)
	_draw_nose(skin)
	_draw_mouth(skin)
	_draw_face_marks()
	_draw_fx()
	_line(_closed(head), INK, 3.4)
	_line(_quad(_rel(0.82, 0.08), _rel(0.74, 0.22), _rel(0.66, 0.36)), Color(INK, 0.4), 1.6)
	_draw_front_hair()
	_draw_headwear()


func _draw_age_lines() -> void:
	var age := float(_l("age", 30))
	var wr := clampf((age - 32.0) / 33.0, 0.0, 1.0) + (0.4 if _l("weathered", false) else 0.0)
	var tip := _nose_tip()
	var my := _mouth_y()
	for side in [-1, 1]:
		_line(_quad(tip + Vector2(side * 11, -4), tip + Vector2(side * 22, 12), C + Vector2(side * _W() * 0.4, my - C.y + 4)), Color(INK, 0.25 + wr * 0.5), 1.6)
	if wr <= 0.05:
		return
	for i in 3:
		var y := -0.6 + i * 0.07
		_line(_quad(_rel(-0.36, y), _rel(0.0, y - 0.03), _rel(0.36, y)), Color(INK, 0.35 * wr), 1.4)
	for side in [-1, 1]:
		var e := _eye_center(side) + Vector2(side * 22, 0)
		_line(PackedVector2Array([e, e + Vector2(side * 7, -4)]), Color(INK, 0.45 * wr), 1.3)
		_line(PackedVector2Array([e + Vector2(0, 4), e + Vector2(side * 7, 6)]), Color(INK, 0.45 * wr), 1.3)
		_line(_quad(_eye_center(side) + Vector2(-12, 12), _eye_center(side) + Vector2(0, 17), _eye_center(side) + Vector2(12, 12)), Color(INK, 0.35 * wr), 1.2)


func _draw_cheeks() -> void:
	if cur["blush"] > 0.02:
		for side in [-1, 1]:
			var c := _rel(side * 0.55, 0.22)
			_poly(_ellipse(c, _W() * 0.24, _H() * 0.07), Color(0.85, 0.25, 0.25, 0.45 * cur["blush"]))
			for i in 3:
				var p := c + Vector2(-8 + i * 7, -2)
				_line(PackedVector2Array([p, p + Vector2(-3, 5)]), Color(0.6, 0.1, 0.1, 0.5 * cur["blush"]), 1.2)
	var dc: float = maxf(cur["dark_circles"], 0.6 if 9 in _l("marks", []) else 0.0)
	if dc > 0.02:
		for side in [-1, 1]:
			_poly(_ellipse(_eye_center(side) + Vector2(0, 11), 17, 5), Color(0.28, 0.16, 0.3, 0.5 * dc))


func _draw_eye(side: int) -> void:
	var c := _eye_center(side)
	var es := float(_l("eye_size", 1.0))
	var open: float = cur["eye_open"] * (1.0 - blink) * (1.0 - cur["squint"] * 0.45)
	if side == 1 and cur["bruise"] > 0.1:
		open *= 1.0 - 0.65 * cur["bruise"]
	var w := 17.0 * es
	var h := 7.6 * es * open * float(_l("eye_h", 1.0))
	var tilt := float(_l("eye_tilt", 0.0))
	if side == 1 and cur["bruise"] > 0.1:
		_poly(_ellipse(c + Vector2(0, 2), 25, 17), Color(0.35, 0.15, 0.4, 0.6 * cur["bruise"]))
	if cur["shadow_eyes"] > 0.02:
		_poly(_ellipse(c + Vector2(0, -6), 28, 17), Color(0, 0, 0, 0.4 * cur["shadow_eyes"]))
	var inner := c + Vector2(-side * w, 1.5)
	var outer := c + Vector2(side * w, -tilt * 4.0)
	var top := _quad(inner, c + Vector2(side * w * 0.15, -h * 1.35), outer, 12)
	var bot := _quad(inner, c + Vector2(-side * w * 0.05, h * 0.95), outer, 12)
	if h > 1.0:
		var white := top.duplicate()
		var rb := bot.duplicate()
		rb.reverse()
		white.append_array(rb)
		_poly(white, Color(0.9, 0.87, 0.82))
		var g := Vector2(cur["gaze_x"] + dart.x, cur["gaze_y"] + dart.y)
		var ic := c + Vector2(g.x * 7.0, g.y * 2.5 - h * 0.15)
		var ir := 6.4 * es
		var iris: Color = _l("eye_color", Color("#5a3a22"))
		if _l("hetero", false) and side == 1:
			iris = Color("#4a78a8")
		_shade(_ellipse(ic, ir, ir, 22), white, iris)
		_shade(_ellipse(ic + Vector2(0, -ir * 0.5), ir, ir * 0.55, 16), white, iris.darkened(0.35))
		_shade(_ellipse(ic, 2.9 * cur["pupil"] * es, 2.9 * cur["pupil"] * es, 14), white, Color(0.03, 0.03, 0.03))
		var lid_shadow := top.duplicate()
		var lower := top.duplicate()
		lower.reverse()
		for i in lower.size():
			lower.set(i, lower[i] + Vector2(0, 3.0))
		lid_shadow.append_array(lower)
		_shade(lid_shadow, white, Color(0.2, 0.12, 0.12, 0.35))
		draw_circle(ic + Vector2(-2.0, -2.0), 1.4, Color(1, 1, 1, 0.85))
	var female := str(_l("gender", "homem")) == "mulher"
	_line(top, INK, 3.2 if female else 2.8)
	_line(PackedVector2Array([outer, outer + Vector2(side * (6 if female else 3), -3)]), INK, 2.2)
	_line(bot, Color(INK, 0.55), 1.3)
	var crease := _quad(inner + Vector2(side * 2, -5), c + Vector2(side * w * 0.15, -h * 1.35 - 6), outer + Vector2(-side * 1, -5), 10)
	_line(crease, Color(INK, 0.45), 1.4)
	_line(_quad(inner + Vector2(side * 3, 6), c + Vector2(0, h + 8), outer + Vector2(-side * 3, 5), 8), Color(INK, 0.22), 1.2)
	if 7 in _l("marks", []):
		var frame := _ellipse(c, w + 8, 15, 24)
		_line(_closed(frame), Color(0.12, 0.12, 0.14), 2.8)
		if side == -1:
			_line(PackedVector2Array([c + Vector2(w + 8, -2), c + Vector2(_W() * 0.84 - w - 8, -2)]), Color(0.12, 0.12, 0.14), 2.8)
	if 8 in _l("marks", []):
		var lens := _ellipse(c, w + 9, 15, 24)
		_poly(lens, Color(0.04, 0.04, 0.05, 0.95))
		_line(_closed(lens), INK, 2.4)
		_line(PackedVector2Array([c + Vector2(-8, -8), c + Vector2(4, -10)]), Color(1, 1, 1, 0.3), 2.0)
		if side == -1:
			_line(PackedVector2Array([c + Vector2(w + 9, -3), c + Vector2(_W() * 0.84 - w - 9, -3)]), INK, 3.0)
	_draw_brow(side, c, w)


func _draw_brow(side: int, c: Vector2, eye_w: float) -> void:
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
		path = PackedVector2Array([inner, inner.lerp(peak, 0.5) + Vector2(0, -1), peak, peak.lerp(outer, 0.5) + Vector2(0, 1), outer])
	else:
		path = _quad(inner, peak + (peak - inner.lerp(outer, float(shape[1]))) * 0.9, outer, 12)
	var col: Color = _l("brow_color", _hair_color().darkened(0.25))
	if str(_l("hair", "")) == "careca" and not look.has("brow_color"):
		col = Color(0.22, 0.16, 0.12)
	var bw := 4.6 * float(shape[4]) * float(_l("brow_w", 1.0))
	var shp := _taper(path, bw, bw * 0.35)
	_poly(shp, col)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 + side
	var strokes := 22 if shape_i == 6 else 14
	for i in strokes:
		var u := float(i) / strokes
		var idx := int(u * (path.size() - 1))
		var p := path[idx] + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-bw * 0.4, bw * 0.4))
		var dir := Vector2(side * 4.0, -2.5 if u < 0.3 else -1.0)
		if shape_i == 6:
			dir = dir.rotated(rng.randf_range(-0.8, 0.8)) * 1.4
		_line(PackedVector2Array([p, p + dir]), col.darkened(0.3), 1.1)
	_line(_closed(shp), Color(INK, 0.6), 1.0)
	if 5 in _l("marks", []) and side == 1:
		draw_circle(outer + Vector2(-6, -4), 2.0, Color("#d9d9d9"))


func _draw_nose(skin: Color) -> void:
	var nw := 9.0 * float(_l("nose_w", 1.0))
	var tip := _nose_tip()
	var top_y := _eye_center(1).y + 2
	_poly(PackedVector2Array([Vector2(C.x + 4, top_y), tip + Vector2(nw * 1.1, -4), tip + Vector2(nw * 0.6, 6), tip + Vector2(2, 7)]), _shadow_of(skin))
	_line(_quad(Vector2(C.x - 5, top_y + 6), Vector2(C.x - 6, tip.y - 18), tip + Vector2(-nw * 0.75, -8), 8), Color(INK, 0.3), 1.4)
	_line(_quad(Vector2(C.x + 5, top_y + 2), Vector2(C.x + 7, tip.y - 16), tip + Vector2(nw * 0.9, -6), 8), Color(INK, 0.55), 1.6)
	for side in [-1, 1]:
		_line(_quad(tip + Vector2(side * nw * 0.55, -6), tip + Vector2(side * nw * 1.35, 0), tip + Vector2(side * nw * 0.7, 5), 8), INK, 2.0)
		_poly(_ellipse(tip + Vector2(side * nw * 0.42, 4.5), 2.8 * float(_l("nose_w", 1.0)), 1.7, 10), Color(0.18, 0.07, 0.07, 0.85))
	_line(_quad(tip + Vector2(-nw * 0.5, 5.5), tip + Vector2(0, 9), tip + Vector2(nw * 0.5, 5.5), 8), INK, 2.2)
	_poly(_ellipse(tip + Vector2(-2, -3), 3.0, 2.2, 10), _light_of(skin))
	if 3 in _l("marks", []):
		draw_circle(tip + Vector2(-nw * 0.95, 2), 2.2, Color("#d9d9d9"))


func _draw_mouth(skin: Color) -> void:
	var y := _mouth_y()
	var flap := 0.0
	if talk_left > 0.0:
		flap = absf(sin(t * 15.0)) * 0.35 + absf(sin(t * 6.3)) * 0.12
	var open := clampf(cur["mouth_open"] + flap, 0.0, 1.2)
	var lips := float(_l("lips", 1.0))
	var w: float = _W() * 0.33 * cur["mouth_width"] * (1.0 + 0.2 * maxf(cur["mouth_curve"], 0.0))
	var curve: float = cur["mouth_curve"]
	var left := Vector2(C.x - w, y - curve * 7.0)
	var right := Vector2(C.x + w, y - curve * 7.0 - cur["smirk"] * 8.0)
	var up_mid := Vector2(C.x + cur["smirk"] * 3.0, y + curve * 2.0 - 1.0)
	var low_mid := Vector2(C.x, y + curve * 4.0 + open * 30.0)
	var lip_col: Color = _l("lip_color", skin.darkened(0.2).lerp(Color(0.62, 0.3, 0.28), 0.25))
	var upper := _quad(left, up_mid, right, 14)
	var lower_line := _quad(left, low_mid, right, 14)
	var u := 4.2 * lips
	var l := 5.5 * lips
	var up_lip := PackedVector2Array([left, left.lerp(up_mid, 0.5) + Vector2(0, -u * 0.8), up_mid + Vector2(-w * 0.16, -u * 1.15), up_mid + Vector2(0, -u * 0.7), up_mid + Vector2(w * 0.16, -u * 1.15), right.lerp(up_mid, 0.5) + Vector2(0, -u * 0.8), right])
	var ru := upper.duplicate()
	ru.reverse()
	up_lip.append_array(ru)
	var low_lip := lower_line.duplicate()
	var lb := _quad(left, low_mid + Vector2(0, l * 1.8), right, 14)
	lb.reverse()
	low_lip.append_array(lb)
	_poly(_ellipse(low_mid + Vector2(0, l * 2.4), w * 0.45, 3.5), Color(_shadow_of(skin), 0.9))
	if open > 0.06:
		var mouth := upper.duplicate()
		var rl := lower_line.duplicate()
		rl.reverse()
		mouth.append_array(rl)
		_poly(mouth, Color(0.16, 0.04, 0.05))
		if cur["teeth"] > 0.3 or open > 0.35:
			var tb := _quad(left.lerp(up_mid, 0.15), up_mid + Vector2(0, minf(9.0, open * 16.0)), right.lerp(up_mid, 0.15), 10)
			var tp := _quad(left.lerp(up_mid, 0.15), up_mid + Vector2(0, -1), right.lerp(up_mid, 0.15), 10)
			var tr := tb.duplicate()
			tr.reverse()
			tp.append_array(tr)
			_shade(tp, mouth, Color(0.9, 0.88, 0.8))
			for i in 4:
				var x := lerpf(left.x, right.x, 0.3 + i * 0.13)
				_line(PackedVector2Array([Vector2(x, up_mid.y), Vector2(x, up_mid.y + minf(8.0, open * 14.0))]), Color(INK, 0.35), 1.0)
			if 10 in _l("marks", []) or "dente_ouro" in _l("extras", []):
				_poly(_ellipse(up_mid + Vector2(6, 3), 3, 3, 8), Color("#d4a72c"))
		_shade(_ellipse(low_mid + Vector2(0, -3), w * 0.45, 4), mouth, Color(0.55, 0.2, 0.22, 0.7))
	_poly(up_lip, lip_col.darkened(0.12))
	_poly(low_lip, lip_col)
	_poly(_ellipse(low_mid + Vector2(-w * 0.15, l * 0.8), w * 0.22, 1.6), Color(1, 1, 1, 0.18))
	_line(upper, INK, 2.6)
	if open > 0.06:
		_line(lower_line, INK, 2.0)
	_line(PackedVector2Array([up_lip[1], up_lip[2], up_lip[3], up_lip[4], up_lip[5]]), Color(INK, 0.35), 1.2)
	_line(PackedVector2Array([left + Vector2(-4, -1), left]), INK, 1.8)
	_line(PackedVector2Array([right, right + Vector2(4, -1)]), INK, 1.8)
	_line(PackedVector2Array([_nose_tip() + Vector2(-2, 10), up_mid + Vector2(-2, -u)]), Color(INK, 0.22), 1.1)
	_line(_quad(_rel(-0.12, 0.84), _rel(0.0, 0.86), _rel(0.12, 0.84)), Color(INK, 0.3), 1.3)
	if 13 in _l("marks", []):
		_poly(up_lip, Color(0.6, 0.08, 0.15, 0.7))
		_poly(low_lip, Color(0.6, 0.08, 0.15, 0.7))


func _draw_beard() -> void:
	var b := str(_l("beard", "none"))
	if b == "none":
		return
	var hc := _hair_color()
	match b:
		"stubble":
			_stubble(hc, 0.6)
		"full", "long":
			var pts := PackedVector2Array()
			for p in _head_pts(2.0):
				if p.y > C.y + _H() * 0.12:
					pts.append(p)
			if b == "long":
				pts.append(_rel(0.0, 1.55))
				pts.append(_rel(0.45, 1.3))
				pts.append(_rel(-0.45, 1.3))
			pts.append(_rel(-0.3, 0.5))
			pts.append(_rel(0.3, 0.5))
			var beard := _sorted_around(pts)
			_poly(beard, hc)
			_shade(beard, _head_shadow_mask(), _shadow_of(hc))
			var rng := RandomNumberGenerator.new()
			rng.seed = 9
			for i in 40:
				var p := _rel(rng.randf_range(-0.85, 0.85), rng.randf_range(0.25, 1.0 if b == "full" else 1.4))
				if Geometry2D.is_point_in_polygon(p, beard):
					_line(PackedVector2Array([p, p + Vector2(rng.randf_range(-2, 2), 6)]), Color(INK, 0.4), 1.1)
			_line(_closed(beard), INK, 2.4)
			_draw_mustache(hc)
		"goatee":
			var g := PackedVector2Array([_rel(-0.22, 0.72), _rel(0.22, 0.72), _rel(0.2, 0.96), _rel(0.0, 1.04), _rel(-0.2, 0.96)])
			_poly(g, hc)
			_line(_closed(g), INK, 2.0)
			_draw_mustache(hc)
		"mustache":
			_draw_mustache(hc, 1.35)


func _stubble(hc: Color, alpha: float) -> void:
	var head := _head_pts(-2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var col := hc.darkened(0.2)
	col.a = alpha
	var mouth_c := Vector2(C.x, _mouth_y() + 2)
	for i in 1100:
		var p := _rel(rng.randf_range(-1.0, 1.0), rng.randf_range(0.18, 1.02))
		if not Geometry2D.is_point_in_polygon(p, head):
			continue
		var rel_y := (p.y - C.y) / _H()
		var rel_x := absf(p.x - C.x) / _W()
		if rel_y < 0.42 and not (rel_y > 0.22 and rel_x > 0.62):
			continue
		if ((p - mouth_c) / Vector2(_W() * 0.36, 9)).length() < 1.0:
			continue
		if p.y < _nose_tip().y + 8 and absf(p.x - C.x) < 16:
			continue
		draw_rect(Rect2(p, Vector2(1.3, 1.3)), col)


func _draw_mustache(hc: Color, scale: float = 1.0) -> void:
	var y := _mouth_y() - 5.0
	var w := _W() * 0.36 * scale
	var pts := PackedVector2Array([Vector2(C.x - w, y + 6 * scale), Vector2(C.x - w * 0.5, y - 6), Vector2(C.x, y - 5), Vector2(C.x + w * 0.5, y - 6), Vector2(C.x + w, y + 6 * scale), Vector2(C.x, y + 2)])
	_poly(pts, hc.darkened(0.1))
	for i in 7:
		var x := lerpf(-w * 0.8, w * 0.8, i / 6.0)
		_line(PackedVector2Array([Vector2(C.x + x, y - 3), Vector2(C.x + x * 1.1, y + 3)]), Color(INK, 0.4), 1.0)
	_line(_closed(pts), INK, 2.0)


func _sorted_around(pts: PackedVector2Array) -> PackedVector2Array:
	var center := Vector2.ZERO
	for p in pts:
		center += p
	center /= pts.size()
	var arr := Array(pts)
	arr.sort_custom(func(a, b): return (a - center).angle() < (b - center).angle())
	return PackedVector2Array(arr)


func _stipple(area: PackedVector2Array, col: Color, count: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var r := Rect2(area[0], Vector2.ZERO)
	for p in area:
		r = r.expand(p)
	for i in count:
		var p := r.position + Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y)
		if Geometry2D.is_point_in_polygon(p, area):
			draw_rect(Rect2(p, Vector2(1.6, 1.6)), col)


func _draw_face_marks() -> void:
	var m: Array = _l("marks", [])
	if 0 in m:
		var a := _rel(-0.78, -0.05)
		var b := _rel(-0.55, 0.42)
		_line(PackedVector2Array([a, a.lerp(b, 0.5) + Vector2(3, 0), b]), Color(0.5, 0.25, 0.22), 3.0)
		for i in 3:
			var p := a.lerp(b, 0.2 + i * 0.3)
			_line(PackedVector2Array([p + Vector2(-4, 2), p + Vector2(4, -2)]), Color(0.5, 0.25, 0.22), 1.6)
	if 2 in m:
		var p2 := _rel(0.7, 0.12)
		_line(PackedVector2Array([p2, p2 + Vector2(4, 8), p2 + Vector2(-2, 10)]), Color(0.1, 0.12, 0.2, 0.85), 2.2)
	if 6 in m:
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		for i in 34:
			var side := -1 if i % 2 == 0 else 1
			draw_circle(_rel(side * rng.randf_range(0.2, 0.7), rng.randf_range(0.05, 0.35)), 1.2, Color(0.45, 0.25, 0.15, 0.6))
	if 15 in m:
		draw_circle(_rel(-0.45, 0.5), 2.0, Color(0.25, 0.15, 0.1))
		draw_circle(_rel(0.4, -0.2), 1.6, Color(0.25, 0.15, 0.1))
	if 17 in m:
		_poly(_ellipse(_rel(0.62, 0.25), _W() * 0.2, _H() * 0.18), Color(0.6, 0.3, 0.3, 0.4))
	if cur["bruise"] > 0.1:
		_line(PackedVector2Array([_rel(-0.62, 0.25), _rel(-0.44, 0.33)]), Color(0.65, 0.05, 0.05, cur["bruise"]), 2.2)
		_poly(_ellipse(Vector2(C.x + 9, _mouth_y() + 8), 4, 3), Color(0.6, 0.05, 0.05, cur["bruise"]))
		_poly(_ellipse(_rel(-0.5, -0.42), 12, 8), Color(0.4, 0.2, 0.35, 0.4 * cur["bruise"]))


func _draw_fx() -> void:
	if cur["tears"] > 0.03:
		var a: float = cur["tears"]
		for side in [-1, 1]:
			var start := _eye_center(side) + Vector2(side * 4, 8)
			var stream := PackedVector2Array()
			for i in 9:
				var u := i / 8.0
				stream.append(start + Vector2(side * (4 * u + sin(u * 6 + t) * 1.5), u * 70 * a))
			_line(stream, Color(INK, 0.5 * a), 5.0)
			_line(stream, Color(0.72, 0.85, 1.0, 0.9 * a), 3.2)
			_line(stream, Color(1, 1, 1, 0.6 * a), 1.0)
			var drop_y := fmod(t * 45.0 + (side + 1) * 20.0, 80.0)
			draw_circle(start + Vector2(side * 4, drop_y), 3.0, Color(INK, 0.6 * a))
			draw_circle(start + Vector2(side * 4, drop_y), 2.3, Color(0.8, 0.9, 1.0, 0.9 * a))
	if cur["sweat"] > 0.03:
		var a2: float = cur["sweat"]
		for p in [Vector2(-0.45, -0.55), Vector2(0.35, -0.62), Vector2(0.72, -0.3)]:
			var y := fmod(t * 12.0 + p.x * 30.0, 30.0)
			var d: Vector2 = _rel(p.x, p.y) + Vector2(0, y)
			var drop := PackedVector2Array([d + Vector2(0, -7), d + Vector2(3.5, 0), d + Vector2(0, 3.5), d + Vector2(-3.5, 0)])
			_poly(drop, Color(0.78, 0.9, 1.0, 0.85 * a2))
			_line(_closed(drop), Color(INK, 0.6 * a2), 1.0)


func _lock(root: Vector2, ctrl: Vector2, tip: Vector2, width: float, col: Color) -> void:
	var path := _quad(root, ctrl, tip, 10)
	var shape := _taper(path, width, width * 0.12)
	_poly(shape, col)
	_line(_closed(shape), Color(INK, 0.55), 1.0)


func _draw_front_hair() -> void:
	var style := str(_l("hair", "curto"))
	var hc := _hair_color()
	var dark := _shadow_of(hc)
	var light := hc.lightened(0.22)
	if style == "careca":
		_poly(_ellipse(_rel(-0.3, -0.78), _W() * 0.28, _H() * 0.07), Color(1, 1, 1, 0.12))
		return
	if style == "moicano":
		var shaved := _cranium(1)
		shaved.append_array(_hairline(0.62))
		_stipple(shaved, Color(hc, 0.5), 220, 4)
		var strip := PackedVector2Array()
		for i in 11:
			var u := i / 10.0
			var a := deg_to_rad(lerpf(225, 315, u))
			var spike := 26.0 if i % 2 == 0 else 6.0
			strip.append(C + Vector2(cos(a) * _W() * 0.32, sin(a) * (_H() * 0.97 + spike)))
		strip.append(_rel(0.2, -0.64))
		strip.append(_rel(-0.2, -0.64))
		_poly(strip, hc)
		_shade(strip, _head_shadow_mask(), dark)
		_line(_closed(strip), INK, 2.6)
		return
	var height := 0.64
	var th := 9.0
	var locks := 11
	var sweep := 0.18
	var part := -0.18
	match style:
		"franja":
			height = 0.4
			locks = 13
			sweep = 0.06
			part = 0.0
		"raspado":
			th = 1.5
		"medio", "longo":
			th = 12.0
			locks = 12
		"desgrenhado":
			th = 14.0
			locks = 14
			sweep = 0.4
		"cacheado", "black_power":
			th = 14.0
		"coque", "rabo", "trancas":
			th = 4.0
			part = 0.0
	var mass := _cranium(th)
	mass.append_array(_hairline(height, part * 0.3))
	if style == "raspado":
		_poly(mass, Color(hc, 0.35))
		_stipple(mass, Color(hc.darkened(0.2), 0.55), 450, 6)
		return
	_poly(mass, hc)
	if style in ["curto", "medio", "longo", "franja", "desgrenhado"]:
		var line := _hairline(height, part * 0.3)
		var rng := RandomNumberGenerator.new()
		rng.seed = 17
		for i in locks:
			var u := (i + 0.5) / locks
			var tip: Vector2 = line[int(u * (line.size() - 1))]
			if style == "desgrenhado":
				tip += Vector2(rng.randf_range(-8, 8), rng.randf_range(0, 14))
			if style == "franja":
				tip += Vector2(0, 8)
			var root := _rel(part + lerpf(-0.25, 0.25, u), -1.0) + Vector2(0, -th * 0.5)
			var mid := root.lerp(tip, 0.55) + Vector2((u - 0.5 + sweep) * _W() * 0.5, 0)
			_lock(root, mid, tip, th * 1.6 + rng.randf_range(-2, 4), hc if i % 2 == 0 else hc.lightened(0.07))
	elif style in ["coque", "rabo", "trancas"]:
		var line2 := _hairline(height, 0.0)
		for i in 9:
			var u := (i + 0.5) / 9.0
			var tip: Vector2 = line2[int(u * (line2.size() - 1))]
			if style == "trancas":
				_line(_quad(tip, tip.lerp(_rel(0, -1.0), 0.5) + Vector2((u - 0.5) * 20, 0), _rel((u - 0.5) * 0.6, -1.0)), Color(INK, 0.8), 2.0)
			else:
				_line(_quad(tip, tip.lerp(_rel(0, -1.05), 0.5), _rel(0, -1.02)), Color(INK, 0.45), 1.3)
	elif style in ["cacheado", "black_power"]:
		var arc := _hairline(height, 0.0)
		var top_arc := _cranium(th)
		for src in [arc, top_arc]:
			for i in range(0, src.size(), 2):
				var p: Vector2 = src[i]
				var r := 7.0 + (i % 3)
				var curl := _ellipse(p, r, r, 12)
				_poly(curl, hc if p.x < C.x + 10 else dark)
				_line(_quad(p + Vector2(-r * 0.5, 0), p + Vector2(0, -r * 0.7), p + Vector2(r * 0.5, 0), 6), Color(INK, 0.6), 1.2)
				_line(_closed(curl), Color(INK, 0.7), 1.2)
	_shade(mass, _head_shadow_mask(), Color(dark, 0.6))
	_shade(mass, _ellipse(_rel(-0.4, -0.95), _W() * 0.35, _H() * 0.09), Color(light, 0.45))
	_line(_closed(mass), INK, 3.0)
	if style in ["curto", "desgrenhado", "franja", "medio"]:
		for side in [-1, 1]:
			var sb := PackedVector2Array([_rel(side * 0.97, -0.3), _rel(side * 1.0, -0.06), _rel(side * 0.93, -0.03), _rel(side * 0.9, -0.26)])
			_poly(sb, hc if side == -1 else dark)
	if style in ["medio", "longo"]:
		var length := 0.6 if style == "medio" else 1.6
		for side in [-1, 1]:
			var curtain := PackedVector2Array([_rel(side * 0.86, -0.5), _rel(side * 1.08, -0.3), _rel(side * 1.12, 0.3), _rel(side * 1.1, length), _rel(side * 0.94, length - 0.1), _rel(side * 0.92, 0.1)])
			_poly(curtain, hc if side == -1 else dark)
			for k in 3:
				var x: float = side * (0.94 + k * 0.06)
				_line(_quad(_rel(x, -0.35), _rel(x + side * 0.06, 0.2), _rel(x, length - 0.05)), Color(INK, 0.5), 1.2)
			_line(_closed(curtain), INK, 2.6)


func _draw_headwear() -> void:
	if 11 in _l("marks", []):
		var cap_col := Color("#7a1f1f")
		var dome := _cranium(8, 186, 354)
		dome.append(_rel(1.02, -0.5))
		dome.append(_rel(-1.02, -0.5))
		_poly(dome, cap_col)
		_shade(dome, _head_shadow_mask(), _shadow_of(cap_col))
		var brim := PackedVector2Array([_rel(-1.02, -0.52), _rel(1.02, -0.52), _rel(1.45, -0.38), _rel(-1.45, -0.38)])
		_poly(brim, cap_col.darkened(0.35))
		_line(_closed(brim), INK, 2.4)
		_line(_closed(dome), INK, 2.8)
	if "chapeu" in _l("extras", []):
		var crown := PackedVector2Array([_rel(-0.86, -0.72), _rel(0.86, -0.72), _rel(0.7, -1.28), _rel(-0.7, -1.28)])
		_poly(crown, Color(0.3, 0.24, 0.18))
		_shade(crown, _head_shadow_mask(), Color(0.2, 0.16, 0.12))
		_poly(PackedVector2Array([_rel(-0.84, -0.8), _rel(0.84, -0.8), _rel(0.82, -0.9), _rel(-0.82, -0.9)]), Color(0.12, 0.1, 0.08))
		_line(_closed(crown), INK, 2.6)
		var brim2 := PackedVector2Array([_rel(-1.6, -0.66), _rel(1.6, -0.66), _rel(1.4, -0.78), _rel(-1.4, -0.78)])
		_poly(brim2, Color(0.25, 0.2, 0.15))
		_line(_closed(brim2), INK, 2.6)
	if "bobes" in _l("extras", []):
		for i in 5:
			var p := _rel(-0.62 + i * 0.31, -0.92 + absf(i - 2) * 0.07)
			_poly(_ellipse(p, 10, 8, 12), Color("#d56a8a"))
			_line(_closed(_ellipse(p, 10, 8, 12)), INK, 1.8)
	if "oculos_testa" in _l("extras", []):
		for side in [-1, 1]:
			var lens := _ellipse(_rel(side * 0.38, -0.62), 16, 8, 16)
			_poly(lens, Color(0.7, 0.78, 0.85, 0.9))
			_line(_closed(lens), INK, 2.0)
		_line(PackedVector2Array([_rel(-0.16, -0.62), _rel(0.16, -0.62)]), INK, 2.0)
