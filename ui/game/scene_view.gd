extends Control

# Cenário do local em tela cheia (espaço virtual 1600x900), com luz, hora do dia e partículas.

const UI = preload("res://ui/ui_theme.gd")
const V := Vector2(1600, 900)
const INK := Color(0.05, 0.04, 0.04)

var scene: String = "rua"
var loc_id: String = ""
var t: float = 0.0
var force_night: bool = false
var _motes: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 60:
		_motes.append([rng.randf() * V.x, rng.randf() * V.y, rng.randf_range(0.3, 1.0), rng.randf() * TAU])


func set_place(id: String, scene_kind: String) -> void:
	loc_id = id
	scene = scene_kind
	queue_redraw()


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


# ---------- helpers ----------

func _r(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(x, y, w, h), c)


func _p(pts: Array, c: Color) -> void:
	var arr := PackedVector2Array(pts)
	if arr.size() >= 3 and not Geometry2D.triangulate_polygon(arr).is_empty():
		draw_colored_polygon(arr, c)


func _grad(x: float, y: float, w: float, h: float, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]), PackedColorArray([top, top, bottom, bottom]))


func _quad_grad(pts: Array, cols: Array) -> void:
	draw_polygon(PackedVector2Array(pts), PackedColorArray(cols))


func _glow(c: Vector2, radius: float, col: Color, steps: int = 10) -> void:
	for i in steps:
		var k := 1.0 - float(i) / steps
		draw_circle(c, radius * k, Color(col, col.a * 0.16))


func _cone(top: Vector2, top_w: float, bottom_y: float, bottom_w: float, col: Color) -> void:
	_quad_grad([top + Vector2(-top_w, 0), top + Vector2(top_w, 0), Vector2(top.x + bottom_w, bottom_y), Vector2(top.x - bottom_w, bottom_y)],
		[col, col, Color(col, 0.0), Color(col, 0.0)])


func _ln(a: Vector2, b: Vector2, c: Color, w: float = 2.0) -> void:
	draw_line(a, b, c, w, true)


func _text(pos: Vector2, s: String, size: int, c: Color, bold: bool = true) -> void:
	draw_string(UI.font(bold), pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)


func _daylight() -> float:
	if force_night:
		return 0.0
	var h := TimeManager.hour() + TimeManager.minute() / 60.0
	if h < 5.5 or h > 19.5:
		return 0.0
	if h < 7.5:
		return (h - 5.5) / 2.0
	if h > 17.5:
		return (19.5 - h) / 2.0
	return 1.0


func _sky(y0: float, y1: float) -> void:
	var d := _daylight()
	var dusk := 1.0 - absf(d - 0.5) * 2.0 if d > 0.0 and d < 1.0 else 0.0
	var top := Color("#0a0f1e").lerp(Color("#5f97cf"), d).lerp(Color("#3b2a55"), dusk * 0.6)
	var bottom := Color("#1b2440").lerp(Color("#c9dcec"), d).lerp(Color("#e08a4f"), dusk * 0.8)
	_grad(0, y0, V.x, y1 - y0, top, bottom)
	if d < 0.3:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 90:
			var p := Vector2(rng.randf() * V.x, y0 + rng.randf() * (y1 - y0) * 0.7)
			draw_circle(p, rng.randf_range(0.6, 1.6), Color(1, 1, 1, (0.3 - d) * rng.randf_range(0.8, 2.4) * (0.6 + 0.4 * sin(t * 2 + i))))


func _raining() -> bool:
	return WorldEvents.raining()


func _buildings(base_y: float, seed_n: int, night: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var x := -40.0
	while x < V.x:
		var w := rng.randf_range(120, 240)
		var h := rng.randf_range(220, 520)
		var col := Color("#151a24").lerp(Color("#4a5566"), _daylight() * 0.7).darkened(rng.randf_range(0.0, 0.25))
		_r(x, base_y - h, w, h, col)
		_r(x, base_y - h, w, 6, col.lightened(0.15))
		var wy := base_y - h + 24
		while wy < base_y - 30:
			var wx := x + 16
			while wx < x + w - 24:
				var lit := rng.randf() < (0.45 if night else 0.08) and not WorldEvents.power_out()
				var wc := Color("#f2c46b") if lit else Color(0, 0, 0, 0.35)
				if lit and rng.randf() < 0.2:
					wc = Color("#9fd3ff")
				_r(wx, wy, 18, 24, Color(wc, 0.85 if lit else 0.5))
				wx += 34
			wy += 42
		x += w + rng.randf_range(4, 30)


func _street_lamp(x: float, base_y: float, h: float) -> void:
	_r(x - 4, base_y - h, 8, h, Color("#1a1c20"))
	_ln(Vector2(x, base_y - h), Vector2(x + 40, base_y - h - 10), Color("#1a1c20"), 6)
	var bulb := Vector2(x + 42, base_y - h - 4)
	var on := _daylight() < 0.6 and not WorldEvents.power_out()
	if on:
		_cone(bulb, 12, base_y + 20, 140, Color(1.0, 0.82, 0.5, 0.22))
		_glow(bulb, 70, Color(1.0, 0.8, 0.45, 0.9))
	draw_circle(bulb, 9, Color("#ffe2a8") if on else Color("#666"))


func _hanging_lamp(x: float, length: float, col: Color, flicker: bool = false) -> void:
	var on := 1.0
	if flicker and fmod(t * 7.3, 5.0) < 0.25:
		on = 0.25
	_ln(Vector2(x, 0), Vector2(x, length), Color("#111"), 3)
	_p([Vector2(x - 34, length + 30), Vector2(x + 34, length + 30), Vector2(x + 16, length), Vector2(x - 16, length)], Color("#1c1c1c"))
	_cone(Vector2(x, length + 30), 30, 760, 260, Color(col, 0.2 * on))
	_glow(Vector2(x, length + 32), 90, Color(col, 0.8 * on))
	draw_circle(Vector2(x, length + 30), 10, Color(col.lightened(0.4), on))


func _fluorescent(x: float, y: float, w: float, flicker: bool = false) -> void:
	var on := 1.0
	if flicker:
		var f := fmod(t * 3.1, 6.0)
		if f < 0.15 or (f > 0.3 and f < 0.38):
			on = 0.15
	_r(x, y, w, 10, Color(0.9, 0.97, 1.0, on))
	_cone(Vector2(x + w / 2, y + 10), w / 2, y + 420, w, Color(0.8, 0.95, 1.0, 0.12 * on))


func _floor_persp(y0: float, col: Color, lines: int, vp: Vector2) -> void:
	_grad(0, y0, V.x, V.y - y0, col.darkened(0.3), col)
	for i in lines + 1:
		var x := -400.0 + (V.x + 800.0) * i / lines
		_ln(vp.lerp(Vector2(x, V.y), (y0 - vp.y) / (V.y - vp.y)), Vector2(x, V.y), Color(0, 0, 0, 0.18), 2)
	var yy := y0
	var step := 14.0
	while yy < V.y:
		_ln(Vector2(0, yy), Vector2(V.x, yy), Color(0, 0, 0, 0.14), 2)
		step *= 1.35
		yy += step


# ---------- desenho ----------

func _draw() -> void:
	var s := maxf(size.x / V.x, size.y / V.y)
	var off := (size - V * s) / 2.0
	draw_set_transform(off, 0.0, Vector2(s, s))
	match scene:
		"bar": _bar()
		"loja": _loja()
		"comida": _lanchonete()
		"casa": _casa()
		"parque": _parque()
		"beco": _beco()
		"servico": _servico()
		"hospedagem": _pensao()
		"igreja": _igreja()
		_: _rua()
	_motes_draw()
	if CrimeSystem.fire_at(loc_id):
		_fire()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_world_overlays()
	_grad(0, size.y * 0.55, size.x, size.y * 0.45, Color(0, 0, 0, 0), Color(0, 0, 0, 0.55))
	_grad(0, 0, size.x, size.y * 0.18, Color(0, 0, 0, 0.5), Color(0, 0, 0, 0))


func _fire() -> void:
	var flick := 0.75 + 0.25 * sin(t * 13.0) * sin(t * 7.3)
	_grad(0, 0, V.x, V.y, Color(0.12, 0.08, 0.06, 0.5), Color(0.5, 0.15, 0.0, 0.28))
	for i in 16:
		var x := V.x * (float(i) + 0.5) / 16.0
		var sway := sin(t * 3.0 + i * 1.7) * 26.0
		var hgt := 520.0 + 200.0 * sin(t * 4.0 + i * 2.3) * sin(t * 1.9 + i) + (i % 3) * 80.0
		var w := 105.0
		_p([Vector2(x - w, V.y), Vector2(x - w * 0.4 + sway * 0.4, V.y - hgt * 0.55), Vector2(x + sway, V.y - hgt), Vector2(x + w * 0.4 + sway * 0.4, V.y - hgt * 0.55), Vector2(x + w, V.y)], Color(0.95, 0.25, 0.05, 0.85))
		_p([Vector2(x - w * 0.62, V.y), Vector2(x + sway * 0.8, V.y - hgt * 0.72), Vector2(x + w * 0.62, V.y)], Color(1.0, 0.6, 0.1, 0.9))
		_p([Vector2(x - w * 0.3, V.y), Vector2(x + sway * 0.5, V.y - hgt * 0.4), Vector2(x + w * 0.3, V.y)], Color(1.0, 0.93, 0.5, 0.95))
	_glow(Vector2(V.x / 2.0, V.y), 900.0, Color(1.0, 0.45, 0.1, 0.5 * flick))
	for i in 40:
		var ex := fmod(float(i) * 97.0 + t * 40.0 * (1 + i % 3), V.x)
		var ey := V.y - fmod(t * 120.0 * (0.4 + (i % 5) * 0.2) + i * 53.0, V.y)
		draw_circle(Vector2(ex, ey), 2.5, Color(1.0, 0.7, 0.2, 0.8))
	_grad(0, 0, V.x, V.y * 0.65, Color(0.04, 0.04, 0.04, 0.8), Color(0.1, 0.1, 0.1, 0.0))


func _world_overlays() -> void:
	var sc: Dictionary = World.scenario()
	var tint: Array = sc.get("tint", [0, 0, 0, 0])
	if float(tint[3]) > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(float(tint[0]), float(tint[1]), float(tint[2]), float(tint[3])))
	if WorldEvents.power_out():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.05, 0.5))
		var flick := 0.5 + 0.5 * sin(t * 2.0)
		draw_circle(Vector2(size.x * 0.82, size.y * 0.7), 12.0, Color(1.0, 0.7, 0.3, 0.5 + 0.2 * flick))
	if sc.get("cinzas", false):
		var rng := RandomNumberGenerator.new()
		rng.seed = 41
		for i in 70:
			var x := fmod(rng.randf() * size.x + t * (12.0 + rng.randf() * 20.0), size.x)
			var y := fmod(rng.randf() * size.y + t * (20.0 + rng.randf() * 30.0), size.y)
			draw_circle(Vector2(x, y), rng.randf_range(1.0, 2.6), Color(0.75, 0.72, 0.7, 0.35))


func _festa() -> void:
	var cols := [Color("#ff5d6c"), Color("#ffd166"), Color("#4fd1b5"), Color("#5aa9e6"), Color("#c792ea")]
	for row in 2:
		var y0 := 120.0 + row * 70.0
		var prev := Vector2(0, y0)
		for i in 17:
			var x := 100.0 * i
			var sag := 38.0 * sin(PI * float(i % 4) / 3.0)
			var pt := Vector2(x, y0 + sag)
			_ln(prev, pt, Color(0.1, 0.1, 0.1), 3.0)
			if i > 0:
				_p([pt + Vector2(-14, 0), pt + Vector2(14, 0), pt + Vector2(0, 34)], cols[(i + row) % cols.size()])
			prev = pt
	for i in 24:
		var lx := 60.0 + i * 68.0
		var ly := 330.0 + 18.0 * sin(i * 1.3)
		var c: Color = cols[i % cols.size()]
		_glow(Vector2(lx, ly), 36.0, Color(c, 0.7 * (0.7 + 0.3 * sin(t * 3.0 + i))), 5)
		draw_circle(Vector2(lx, ly), 6, c.lightened(0.4))
	_r(120, 560, 280, 90, Color("#3a2418"))
	_r(120, 520, 280, 46, Color("#c0392b"))
	_text(Vector2(160, 554), "PASTEL & CALDO", 28, Color("#ffe9a8"))
	_r(1180, 560, 280, 90, Color("#243a5a"))
	_r(1180, 520, 280, 46, Color("#2980b9"))
	_text(Vector2(1220, 554), "QUENTÃO", 28, Color("#ffe9a8"))


func _motes_draw() -> void:
	if scene in ["rua", "parque", "beco"]:
		if _raining():
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			for i in 220:
				var x := fmod(rng.randf() * V.x + t * 120.0, V.x)
				var y := fmod(rng.randf() * V.y + t * (900.0 + rng.randf() * 300.0), V.y)
				_ln(Vector2(x, y), Vector2(x - 6, y + 26), Color(0.75, 0.85, 1.0, 0.25), 1.5)
		if scene == "parque" and _daylight() < 0.4:
			for m in _motes.slice(0, 25):
				var p := Vector2(m[0] + sin(t * 0.7 + m[3]) * 40, 400 + fmod(m[1], 400) + cos(t * 0.5 + m[3]) * 30)
				_glow(p, 14, Color(0.8, 1.0, 0.4, 0.6 * (0.5 + 0.5 * sin(t * 2 + m[3]))), 5)
		return
	for m in _motes:
		var p := Vector2(fmod(m[0] + t * 8.0 * m[2], V.x), fmod(m[1] - t * 5.0 * m[2] + V.y, V.y))
		draw_circle(p, 1.6 * m[2], Color(1, 0.95, 0.85, 0.18 * m[2] * (0.6 + 0.4 * sin(t + m[3]))))


func _bar() -> void:
	_grad(0, 0, V.x, 640, Color("#1b120d"), Color("#3a2416"))
	for x in range(0, 1600, 46):
		_ln(Vector2(x, 0), Vector2(x, 640), Color(0, 0, 0, 0.25), 2)
	_glow(Vector2(800, 330), 520, Color(1.0, 0.6, 0.25, 0.35))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for shelf_y in [250, 400]:
		_r(260, shelf_y, 1080, 16, Color("#2a1a10"))
		_r(260, shelf_y, 1080, 4, Color("#6b4a2a"))
		var x := 280.0
		while x < 1320:
			var h := rng.randf_range(70, 110)
			var col: Color = [Color("#2f6b3f"), Color("#7a3a18"), Color("#c9a02c"), Color("#3a2a5a"), Color("#8a1f1f"), Color("#d8d0b0")][rng.randi() % 6]
			_r(x, shelf_y - h, 26, h, Color(col, 0.92))
			_r(x + 9, shelf_y - h - 26, 8, 28, Color(col.darkened(0.3), 0.92))
			_r(x + 4, shelf_y - h * 0.6, 18, 26, Color(1, 1, 1, 0.25))
			_r(x + 3, shelf_y - h + 6, 4, h - 12, Color(1, 1, 1, 0.18))
			x += rng.randf_range(34, 48)
	var neon_on := 0.35 if fmod(t * 2.3, 7.0) < 0.12 else 1.0
	var neon := Color(1.0, 0.25, 0.45, neon_on)
	for i in 6:
		_text(Vector2(80 + sin(i) * 3, 150 + cos(i) * 3), "BAR DO ZÉ", 64, Color(neon, 0.08 * neon_on))
	_text(Vector2(80, 150), "BAR DO ZÉ", 64, neon)
	_r(1330, 120, 220, 130, Color("#0c0c10"))
	var tv := Color(0.4, 0.7, 1.0, 0.6 + 0.3 * sin(t * 9))
	_r(1342, 132, 196, 106, Color(tv, 0.55))
	_glow(Vector2(1440, 185), 160, Color(0.4, 0.6, 1.0, 0.4))
	for x in [480, 800, 1120]:
		_hanging_lamp(x, 70, Color(1.0, 0.72, 0.38))
	_r(0, 520, V.x, 140, Color("#2b1a10"))
	_r(0, 520, V.x, 12, Color("#7a5230"))
	_r(0, 532, V.x, 4, Color(1, 0.8, 0.5, 0.25))
	_floor_persp(660, Color("#24170f"), 12, Vector2(800, 420))


func _loja() -> void:
	var vp := Vector2(800, 400)
	_grad(0, 0, V.x, 640, Color("#c8c8b8"), Color("#a8a894"))
	_floor_persp(560, Color("#cfcfc4"), 14, vp)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for side in [-1, 1]:
		var near_x: float = 800.0 + side * 860.0
		var far_x: float = 800.0 + side * 150.0
		_p([Vector2(near_x, 120), Vector2(far_x, 300), Vector2(far_x, 520), Vector2(near_x, 900)], Color("#7f7f72"))
		for row in 5:
			var u := float(row) / 5.0
			var y_near := lerpf(150.0, 820.0, u)
			var y_far := lerpf(310.0, 510.0, u)
			_ln(Vector2(near_x, y_near), Vector2(far_x, y_far), Color("#3a3a33"), 5)
			var k := 0.0
			while k < 1.0:
				var px := lerpf(near_x, far_x, k)
				var py := lerpf(y_near, y_far, k)
				var sc := lerpf(1.0, 0.22, k)
				var col: Color = [Color("#d13b3b"), Color("#3b7bd1"), Color("#e8c13a"), Color("#4caf6b"), Color("#f08a3c"), Color("#f2f2f2")][rng.randi() % 6]
				_r(px - (0 if side == 1 else 40 * sc), py - 70 * sc, 40 * sc, 68 * sc, col)
				k += lerpf(0.035, 0.06, k)
	for i in 5:
		var u := float(i) / 5.0
		var y := lerpf(30.0, 280.0, u)
		var w := lerpf(700.0, 120.0, u)
		_fluorescent(800 - w / 2, y, w, i == 2)
	_text(Vector2(640, 380), "BOM PREÇO", 34, Color("#c02a2a"))


func _lanchonete() -> void:
	_grad(0, 0, V.x, 600, Color("#e7dcc0"), Color("#cdbf9c"))
	for x in range(0, 1600, 44):
		_ln(Vector2(x, 0), Vector2(x, 600), Color(0, 0, 0, 0.08), 2)
	for y in range(0, 600, 44):
		_ln(Vector2(0, y), Vector2(V.x, y), Color(0, 0, 0, 0.08), 2)
	_r(980, 60, 460, 250, Color("#1d1f1c"))
	_r(990, 70, 440, 230, Color("#262a26"))
	var items := ["CAFÉ ........ R$ 5", "PÃO DE QUEIJO R$ 6", "COXINHA ..... R$ 8", "REFRI ....... R$ 7", "PRATO FEITO . R$ 25"]
	for i in items.size():
		_text(Vector2(1010, 112 + i * 40), items[i], 26, Color("#f0e6c8"), false)
	draw_circle(Vector2(320, 140), 54, Color("#f4f0e6"))
	draw_arc(Vector2(320, 140), 54, 0, TAU, 40, Color("#333"), 5, true)
	var h := TimeManager.hour() % 12
	_ln(Vector2(320, 140), Vector2(320, 140) + Vector2(0, -32).rotated(TAU * h / 12.0), Color("#222"), 5)
	_ln(Vector2(320, 140), Vector2(320, 140) + Vector2(0, -44).rotated(TAU * TimeManager.minute() / 60.0), Color("#222"), 3)
	_r(0, 470, V.x, 190, Color("#8c3b2e"))
	_r(0, 460, V.x, 18, Color("#d8cfc0"))
	_r(140, 360, 520, 110, Color(0.85, 0.95, 1.0, 0.25))
	_r(140, 360, 520, 6, Color(1, 1, 1, 0.6))
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for i in 14:
		var c := Vector2(170 + (i % 7) * 70, 400 + (i / 7) * 40)
		_p([c + Vector2(-18, 14), c + Vector2(18, 14), c + Vector2(0, -16)], Color("#d98a3c").darkened(rng.randf() * 0.2))
	_glow(Vector2(400, 410), 260, Color(1.0, 0.85, 0.5, 0.35))
	for x in [400, 1200]:
		_hanging_lamp(x, 20, Color(1.0, 0.9, 0.6))
	_floor_persp(660, Color("#6b6b66"), 16, Vector2(800, 420))


func _casa() -> void:
	_grad(0, 0, V.x, 680, Color("#4a4032"), Color("#3a3226"))
	for x in range(0, 1600, 56):
		_r(x, 0, 24, 680, Color(1, 1, 1, 0.03))
	var win := Rect2(1000, 110, 420, 330)
	_sky_rect(win)
	_r(win.position.x - 14, win.position.y - 14, win.size.x + 28, 14, Color("#2a2018"))
	_r(win.position.x - 14, win.end.y, win.size.x + 28, 22, Color("#2a2018"))
	_r(win.position.x - 14, win.position.y, 14, win.size.y, Color("#2a2018"))
	_r(win.end.x, win.position.y, 14, win.size.y, Color("#2a2018"))
	_r(win.position.x + win.size.x / 2 - 5, win.position.y, 10, win.size.y, Color("#2a2018"))
	_p([Vector2(960, 80), Vector2(1030, 80), Vector2(1010, 520), Vector2(950, 520)], Color("#5a1f24"))
	_r(180, 140, 170, 130, Color("#2a2018"))
	_r(192, 152, 146, 106, Color("#6b5a3a"))
	_ln(Vector2(560, 60), Vector2(610, 190), Color(0, 0, 0, 0.35), 2)
	_ln(Vector2(610, 190), Vector2(590, 260), Color(0, 0, 0, 0.35), 2)
	_glow(Vector2(260, 430), 300, Color(1.0, 0.75, 0.4, 0.45))
	_r(240, 330, 40, 240, Color("#1e1a14"))
	_p([Vector2(190, 330), Vector2(330, 330), Vector2(300, 260), Vector2(220, 260)], Color("#e8c890"))
	_r(0, 680, V.x, 220, Color("#2d241a"))
	_r(0, 680, V.x, 8, Color("#4a3a28"))
	_furniture()


func _furniture() -> void:
	var furn: Array = HomeSystem.furniture(loc_id) if GameState.active else []
	var power := HomeSystem.power(loc_id) if GameState.active and HomeSystem.contracts().has(loc_id) else true
	if "cama_boa" in furn:
		_r(660, 560, 360, 130, Color("#3a2a1c"))
		_r(660, 470, 24, 220, Color("#2a1c12"))
		_r(684, 520, 330, 150, Color("#6b2f3a"))
		_r(684, 520, 330, 28, Color("#8a4552"))
		_r(704, 488, 100, 44, Color("#e8dfd0"))
		_r(824, 488, 100, 44, Color("#e8dfd0"))
	else:
		_r(680, 650, 320, 36, Color("#4b3a4a"))
		_r(680, 640, 320, 12, Color("#6b5a6a"))
		_r(700, 626, 80, 22, Color("#c9c0b0"))
	if "geladeira" in furn:
		_r(250, 380, 110, 310, Color("#cfd3d6"))
		_r(250, 380, 110, 12, Color("#e8ecee"))
		_ln(Vector2(250, 520), Vector2(360, 520), Color("#6a6e72"), 4)
		_r(342, 430, 8, 70, Color("#6a6e72"))
		_r(342, 560, 8, 70, Color("#6a6e72"))
		draw_rect(Rect2(250, 380, 110, 310), INK, false, 4.0)
	if "fogao" in furn:
		_r(370, 570, 120, 120, Color("#2b2d30"))
		_r(370, 558, 120, 14, Color("#8a8e92"))
		for bx in [395, 430, 465]:
			draw_circle(Vector2(bx, 565), 11, Color("#111"))
		draw_rect(Rect2(370, 558, 120, 132), INK, false, 4.0)
	if "computador" in furn:
		_r(505, 630, 150, 14, Color("#3a2a1c"))
		_r(512, 644, 10, 46, Color("#2a1c12"))
		_r(638, 644, 10, 46, Color("#2a1c12"))
		_r(535, 556, 70, 60, Color("#111"))
		if power:
			_r(540, 561, 60, 50, Color(0.5, 0.85, 1.0, 0.7 + 0.2 * sin(t * 3.0)))
		_r(560, 616, 20, 14, Color("#222"))
	if "sofa" in furn:
		_r(1030, 620, 230, 80, Color("#4a5a3a"))
		_r(1030, 556, 230, 70, Color("#586a46"))
		_r(1014, 590, 32, 110, Color("#3e4c30"))
		_r(1246, 590, 32, 110, Color("#3e4c30"))
		draw_rect(Rect2(1014, 556, 264, 144), INK, false, 4.0)
	if "tv" in furn:
		_r(1060, 440, 170, 100, Color("#0b0c0e"))
		var glow := Color(0.35, 0.6, 1.0, 0.55 + 0.25 * sin(t * 6.0)) if power else Color(0.1, 0.1, 0.12)
		_r(1068, 448, 154, 84, glow)
		if power:
			_glow(Vector2(1145, 490), 240.0, Color(0.4, 0.6, 1.0, 0.35))
		_r(1130, 540, 30, 14, Color("#1a1a1c"))
		draw_rect(Rect2(1060, 440, 170, 100), INK, false, 4.0)


func _sky_rect(r: Rect2) -> void:
	var d := _daylight()
	var top := Color("#0a0f1e").lerp(Color("#6fa8dc"), d)
	var bottom := Color("#1b2440").lerp(Color("#d4e6f3"), d)
	_grad(r.position.x, r.position.y, r.size.x, r.size.y, top, bottom)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var x := r.position.x
	while x < r.end.x:
		var w := rng.randf_range(40, 90)
		var h := rng.randf_range(60, 200)
		_r(x, r.end.y - h, minf(w, r.end.x - x), h, Color("#11151f").lerp(Color("#5a6575"), d * 0.6))
		if d < 0.5:
			for k in 4:
				if rng.randf() < 0.5:
					_r(x + 8 + (k % 2) * 20, r.end.y - h + 14 + (k / 2) * 26, 10, 14, Color("#f2c46b"))
		x += w + 6


func _rua() -> void:
	var night := _daylight() < 0.5
	_sky(0, 640)
	if _daylight() < 0.4:
		draw_circle(Vector2(1320, 120), 40, Color("#f2efe0"))
		_glow(Vector2(1320, 120), 140, Color(0.9, 0.9, 1.0, 0.3))
	_buildings(640, 4 if loc_id == "praca" else 9, night)
	_r(0, 640, V.x, 260, Color("#1d1f24").lerp(Color("#55575c"), _daylight() * 0.6))
	_r(0, 640, V.x, 14, Color("#3b3e45"))
	if loc_id == "rodoviaria":
		_p([Vector2(0, 260), Vector2(V.x, 220), Vector2(V.x, 250), Vector2(0, 290)], Color("#2a2e36"))
		for x in range(80, 1600, 260):
			_r(x, 270, 16, 380, Color("#2a2e36"))
		_r(980, 470, 560, 190, Color("#c0392b"))
		_r(980, 470, 560, 20, Color("#e74c3c"))
		for x in range(1000, 1520, 70):
			_r(x, 500, 56, 60, Color(0.6, 0.85, 1.0, 0.5))
		draw_circle(Vector2(1060, 660), 28, Color("#111"))
		draw_circle(Vector2(1460, 660), 28, Color("#111"))
		_r(200, 320, 380, 90, Color("#0b0d10"))
		_text(Vector2(220, 360), "PARTIDAS  22:40  SÃO PAULO", 24, Color("#ffb347"), false)
		_text(Vector2(220, 395), "         23:15  RIO", 24, Color("#ffb347"), false)
	else:
		_p([Vector2(560, 640), Vector2(1040, 640), Vector2(990, 560), Vector2(610, 560)], Color("#3a3d44"))
		_r(700, 470, 200, 90, Color("#4a4e57"))
		_glow(Vector2(800, 470), 120, Color(0.5, 0.7, 1.0, 0.2))
		for x in [140, 1380]:
			_r(x, 580, 180, 18, Color("#3a2a1e"))
			_r(x + 10, 598, 10, 42, Color("#222"))
			_r(x + 160, 598, 10, 42, Color("#222"))
	if loc_id == "praca" and WorldEvents.festa_on():
		_festa()
	_street_lamp(420, 640, 360)
	_street_lamp(1180, 640, 360)
	if _raining():
		for i in 6:
			var px := 200.0 + i * 240
			_p([Vector2(px, 700 + i % 2 * 60), Vector2(px + 160, 700 + i % 2 * 60), Vector2(px + 130, 720 + i % 2 * 60), Vector2(px + 20, 720 + i % 2 * 60)], Color(0.6, 0.7, 0.9, 0.18))


func _parque() -> void:
	_sky(0, 600)
	var d := _daylight()
	if d < 0.4:
		draw_circle(Vector2(260, 140), 46, Color("#f2efe0"))
		_glow(Vector2(260, 140), 160, Color(0.9, 0.9, 1.0, 0.3))
	var rng := RandomNumberGenerator.new()
	rng.seed = 44
	for i in 16:
		var x := rng.randf_range(-100, 1700)
		var r := rng.randf_range(90, 180)
		var c := Color("#0d1a12").lerp(Color("#2f5a33"), d * 0.8).darkened(rng.randf() * 0.3)
		_r(x - 10, 600 - r * 0.2, 20, r * 0.6, Color("#120d08"))
		draw_circle(Vector2(x, 600 - r * 0.9), r, c)
	_r(0, 600, V.x, 300, Color("#0e1710").lerp(Color("#3d6b3a"), d * 0.7))
	var lake := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		lake.append(Vector2(1100, 700) + Vector2(cos(a) * 420, sin(a) * 90))
	draw_colored_polygon(lake, Color("#0b1626").lerp(Color("#6f9fbf"), d * 0.7))
	if d < 0.4:
		for i in 6:
			_ln(Vector2(1080 + sin(t + i) * 30, 660 + i * 12), Vector2(1140 + sin(t + i) * 30, 660 + i * 12), Color(1, 1, 0.9, 0.2), 2)
	_p([Vector2(500, 900), Vector2(900, 900), Vector2(820, 620), Vector2(760, 620)], Color("#3a332a").lerp(Color("#8a7a5a"), d * 0.6))
	_street_lamp(600, 640, 300)


func _beco() -> void:
	var vp := Vector2(800, 430)
	_sky(0, 300)
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	for side in [-1, 1]:
		var near: float = 800.0 + side * 900.0
		var far: float = 800.0 + side * 120.0
		_p([Vector2(near, -50), Vector2(far, 180), Vector2(far, 600), Vector2(near, 980)], Color("#3a2018"))
		for row in 26:
			var u := float(row) / 26.0
			_ln(Vector2(near, lerpf(-50, 980, u)), Vector2(far, lerpf(180, 600, u)), Color(0, 0, 0, 0.3), 2)
		for k in 14:
			var kk := float(k) / 14.0
			var x := lerpf(near, far, kk)
			_ln(Vector2(x, lerpf(-50, 180, kk)), Vector2(x, lerpf(980, 600, kk)), Color(0, 0, 0, 0.18), 1.5)
	_r(0, 0, V.x, 0, Color.BLACK)
	_floor_persp(600, Color("#1d1a1a"), 10, vp)
	_r(230, 560, 300, 210, Color("#1f3a2a"))
	_r(230, 560, 300, 20, Color("#2c4d39"))
	_ln(Vector2(1300, 0), Vector2(1300, 700), Color("#555"), 10)
	_ln(Vector2(1300, 300), Vector2(1150, 330), Color("#555"), 10)
	var bulb := Vector2(800, 260)
	var on := 0.2 if fmod(t * 4.7, 9.0) < 0.2 else 1.0
	_cone(bulb, 10, 900, 300, Color(1.0, 0.75, 0.45, 0.2 * on))
	_glow(bulb, 90, Color(1.0, 0.75, 0.4, 0.8 * on))
	draw_circle(bulb, 8, Color(1.0, 0.85, 0.6, on))
	_text(Vector2(1050, 520), "NÃO", 46, Color(0.9, 0.2, 0.3, 0.55))
	_text(Vector2(1010, 570), "CONFIE", 40, Color(0.2, 0.7, 0.9, 0.45))
	_p([Vector2(700, 760), Vector2(980, 760), Vector2(940, 800), Vector2(740, 800)], Color(1.0, 0.75, 0.45, 0.12))


func _servico() -> void:
	if loc_id == "delegacia":
		_grad(0, 0, V.x, 640, Color("#3c4448"), Color("#2c3236"))
		_r(0, 380, V.x, 260, Color("#262b2e"))
		var rng := RandomNumberGenerator.new()
		rng.seed = 66
		for i in 5:
			var x := 120.0 + i * 160
			_r(x, 120, 120, 160, Color("#e8e0c8"))
			_text(Vector2(x + 14, 150), "PROCURADO", 18, Color("#8a1f1f"))
			_r(x + 30, 165, 60, 70, Color("#555").lerp(Color("#888"), rng.randf()))
		_r(1080, 90, 380, 220, Color("#11151a"))
		for x in range(1095, 1460, 36):
			_ln(Vector2(x, 90), Vector2(x, 310), Color("#555"), 6)
		_r(0, 500, V.x, 160, Color("#3b2f24"))
		_r(0, 500, V.x, 14, Color("#5a4636"))
		_fluorescent(300, 20, 400, false)
		_fluorescent(900, 20, 400, true)
		_floor_persp(660, Color("#2e3236"), 12, Vector2(800, 420))
		return
	var vp := Vector2(800, 380)
	_grad(0, 0, V.x, 640, Color("#c9d6cf"), Color("#a9bdb3"))
	for side in [-1, 1]:
		var near: float = 800.0 + side * 900.0
		var far: float = 800.0 + side * 170.0
		_p([Vector2(near, -40), Vector2(far, 230), Vector2(far, 520), Vector2(near, 940)], Color("#b8c9c0"))
		_p([Vector2(near, 520), Vector2(far, 430), Vector2(far, 520), Vector2(near, 940)], Color("#6e8f80"))
		for k in 3:
			var kk := 0.2 + k * 0.25
			var x0 := lerpf(near, far, kk)
			var x1 := lerpf(near, far, kk + 0.1)
			_p([Vector2(x0, lerpf(120, 280, kk)), Vector2(x1, lerpf(120, 280, kk + 0.1)), Vector2(x1, lerpf(940, 520, kk + 0.1)), Vector2(x0, lerpf(940, 520, kk))], Color("#5a7a8a"))
	_r(670, 230, 260, 290, Color("#8fa7b0"))
	_floor_persp(520, Color("#c0c8c4"), 14, vp)
	for i in 4:
		var u := float(i) / 4.0
		_fluorescent(800 - lerpf(320, 60, u), lerpf(20, 210, u), lerpf(640, 120, u), i == 1)
	_r(1240, 640, 300, 40, Color("#d8d8d8"))
	_r(1250, 680, 10, 100, Color("#888"))
	_r(1520, 680, 10, 100, Color("#888"))


func _pensao() -> void:
	_grad(0, 0, V.x, 660, Color("#6a5838"), Color("#4a3e28"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for x in range(20, 1600, 60):
		for y in range(20, 640, 70):
			draw_circle(Vector2(x + (y / 70 % 2) * 30, y), 7, Color(0, 0, 0, 0.12))
	for i in 3:
		var x := 160.0 + i * 480
		_r(x, 160, 230, 500, Color("#4a3420"))
		_r(x + 14, 174, 202, 220, Color("#3e2b1a"))
		_r(x + 14, 410, 202, 236, Color("#3e2b1a"))
		draw_circle(Vector2(x + 196, 430), 9, Color("#c9a227"))
		_r(x + 85, 120, 60, 34, Color("#d8c8a0"))
		_text(Vector2(x + 100, 148), str(i + 3), 28, Color("#2a1a10"))
	_hanging_lamp(800, 40, Color(1.0, 0.8, 0.5), true)
	_floor_persp(660, Color("#3a2c1c"), 12, Vector2(800, 420))


func _igreja() -> void:
	_grad(0, 0, V.x, 640, Color("#2a2622"), Color("#3a342c"))
	var colors := [Color("#c0392b"), Color("#2980b9"), Color("#f1c40f"), Color("#27ae60"), Color("#8e44ad")]
	for i in 3:
		var cx := 300.0 + i * 500
		var arch := PackedVector2Array()
		for k in 17:
			var a := PI + PI * k / 16.0
			arch.append(Vector2(cx, 210) + Vector2(cos(a) * 90, sin(a) * 90))
		arch.append(Vector2(cx + 90, 470))
		arch.append(Vector2(cx - 90, 470))
		draw_colored_polygon(arch, Color("#141210"))
		var rng := RandomNumberGenerator.new()
		rng.seed = 88 + i
		for k in 12:
			var p := Vector2(cx + rng.randf_range(-70, 70), rng.randf_range(150, 450))
			_p([p, p + Vector2(28, 8), p + Vector2(12, 34)], Color(colors[rng.randi() % colors.size()], 0.8))
		_cone(Vector2(cx, 320), 80, 900, 220, Color(1.0, 0.9, 0.7, 0.07 + 0.03 * sin(t + i)))
	for row in 6:
		var y := 620.0 + row * 50
		var w := 300.0 + row * 60
		_r(800 - w - 60, y, w, 26, Color("#3a2416"))
		_r(860, y, w, 26, Color("#3a2416"))
	for i in 7:
		var x := 560.0 + i * 80
		_r(x, 540, 10, 40, Color("#eee8d8"))
		var fl := 0.8 + 0.2 * sin(t * 9 + i * 1.7)
		_p([Vector2(x - 2, 540), Vector2(x + 12, 540), Vector2(x + 5, 520 - fl * 6)], Color(1.0, 0.75, 0.3, fl))
		_glow(Vector2(x + 5, 532), 50, Color(1.0, 0.7, 0.3, 0.5 * fl), 6)
	_r(0, 600, V.x, 300, Color("#1e1915"))
