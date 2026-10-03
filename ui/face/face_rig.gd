extends Control

# Retrato ilustrado no estilo "I'm Not Human": contorno grosso, sombras em blocos chapados,
# personagem de meio corpo na frente do cenário, vinheta de olho mágico.

const BASE := Vector2(300, 400)
const C := Vector2(150, 185)          # centro da cabeça no espaço da cabeça
const HEAD_POS := Vector2(150, 146)   # onde o centro da cabeça fica na tela
const HS := 0.8                       # escala da cabeça em relação ao corpo
const INK := Color(0.07, 0.05, 0.05)

const NEUTRAL := {
	"brow_raise": 0.0, "brow_angle": 0.0, "brow_asym": 0.0,
	"eye_open": 1.0, "squint": 0.0, "pupil": 1.0, "gaze_x": 0.0, "gaze_y": 0.0,
	"mouth_curve": 0.0, "mouth_open": 0.0, "mouth_width": 1.0, "smirk": 0.0, "teeth": 0.0,
	"tears": 0.0, "blush": 0.0, "sweat": 0.0, "bruise": 0.0, "dark_circles": 0.0,
	"pale": 0.0, "shadow_eyes": 0.0, "tremble": 0.0, "tilt": 0.0,
}

const EXPRESSIONS := {
	"neutro": {},
	"feliz": {"mouth_curve": 0.8, "eye_open": 0.85, "brow_raise": 0.2, "blush": 0.15, "squint": 0.25},
	"rindo": {"mouth_curve": 1.0, "mouth_open": 0.75, "teeth": 1.0, "eye_open": 0.2, "squint": 0.7, "brow_raise": 0.45, "tilt": -0.06, "blush": 0.3},
	"triste": {"brow_angle": -0.9, "brow_raise": 0.2, "mouth_curve": -0.6, "eye_open": 0.75, "gaze_y": 0.6},
	"chorando": {"brow_angle": -1.0, "brow_raise": 0.3, "mouth_curve": -0.9, "mouth_open": 0.35, "eye_open": 0.45, "squint": 0.35, "tears": 1.0, "blush": 0.5, "tremble": 0.4},
	"irritado": {"brow_angle": 0.85, "brow_raise": -0.3, "mouth_curve": -0.35, "eye_open": 0.8, "squint": 0.25},
	"furioso": {"brow_angle": 1.15, "brow_raise": -0.5, "mouth_curve": -0.5, "mouth_open": 0.75, "teeth": 1.0, "eye_open": 1.15, "pupil": 0.7, "blush": 0.55, "tremble": 0.5},
	"desconfiado": {"squint": 0.6, "brow_asym": 0.8, "gaze_x": 0.7, "mouth_curve": -0.15, "mouth_width": 0.85},
	"assustado": {"eye_open": 1.45, "pupil": 0.55, "brow_raise": 1.0, "brow_angle": -0.5, "mouth_open": 0.5, "mouth_width": 0.75, "pale": 0.7, "tremble": 1.0},
	"nervoso": {"brow_angle": -0.5, "brow_raise": 0.3, "sweat": 1.0, "mouth_curve": -0.2, "mouth_width": 0.8, "tremble": 0.35},
	"sarcastico": {"smirk": 1.0, "brow_asym": 0.9, "squint": 0.35, "gaze_x": -0.3},
	"ameacador": {"brow_angle": 0.9, "squint": 0.45, "smirk": 0.6, "shadow_eyes": 1.0, "tilt": 0.06, "gaze_y": -0.3},
	"carinhoso": {"mouth_curve": 0.6, "eye_open": 0.8, "blush": 0.4, "brow_raise": 0.2, "brow_angle": -0.25, "squint": 0.2},
	"surpreso": {"eye_open": 1.45, "brow_raise": 1.25, "mouth_open": 0.7, "mouth_width": 0.55},
	"envergonhado": {"blush": 1.0, "gaze_x": 0.8, "gaze_y": 0.5, "mouth_curve": 0.2, "smirk": 0.3, "brow_angle": -0.35},
	"entediado": {"eye_open": 0.55, "mouth_curve": -0.15, "brow_raise": -0.1, "gaze_y": 0.2},
	"exausto": {"eye_open": 0.5, "dark_circles": 1.0, "mouth_open": 0.08, "pale": 0.4, "brow_angle": -0.3},
	"machucado": {"bruise": 1.0, "eye_open": 0.8, "mouth_curve": -0.4, "brow_angle": -0.4, "dark_circles": 0.4},
}

const SCENE_COLORS := {
	"bar": [Color("#3a2a20"), Color("#5c3d24"), Color("#e0a050")],
	"loja": [Color("#b9b49a"), Color("#8f8a74"), Color("#e8f0e0")],
	"comida": [Color("#c9b98f"), Color("#7a5a3a"), Color("#f0d890")],
	"casa": [Color("#5a5040"), Color("#3a3228"), Color("#e8c890")],
	"rua": [Color("#1c2433"), Color("#2a2a30"), Color("#e8c060")],
	"parque": [Color("#16241c"), Color("#1e2a1e"), Color("#c8d8e8")],
	"beco": [Color("#3a2620"), Color("#222024"), Color("#c89050")],
	"servico": [Color("#9fb3a6"), Color("#6c7a70"), Color("#eef4f0")],
	"hospedagem": [Color("#6a5838"), Color("#3e3324"), Color("#e8c080")],
	"igreja": [Color("#4a443c"), Color("#2e2a26"), Color("#f0c070")],
	"vazio": [Color("#202326"), Color("#16181a"), Color("#888888")],
}

var look: Dictionary = {}
var emotion: String = "neutro"
var scene: String = "vazio"
var cur: Dictionary = NEUTRAL.duplicate()
var target: Dictionary = NEUTRAL.duplicate()
var bg_color: Color = Color("#1b1e23")
var t: float = 0.0
var blink: float = 0.0
var next_blink: float = 2.0
var talk_left: float = 0.0
var dart: Vector2 = Vector2.ZERO
var next_dart: float = 1.0
var vignette_tex: GradientTexture2D


func _ready() -> void:
	clip_contents = true


func set_look(l: Dictionary) -> void:
	look = l
	queue_redraw()


func set_emotion(e: String, instant: bool = false) -> void:
	emotion = e if EXPRESSIONS.has(e) else "neutro"
	target = NEUTRAL.duplicate()
	for k in EXPRESSIONS[emotion]:
		target[k] = EXPRESSIONS[emotion][k]
	if instant:
		cur = target.duplicate()


func talk(seconds: float) -> void:
	talk_left = seconds


static func scene_for_location(loc_id: String, tipo: String) -> String:
	match loc_id:
		"parque":
			return "parque"
		"beco":
			return "beco"
		"igreja":
			return "igreja"
		"praca", "rodoviaria":
			return "rua"
	match tipo:
		"bar", "loja", "comida", "casa", "servico", "hospedagem":
			return tipo
	return "rua"


func _process(delta: float) -> void:
	t += delta
	var k := 1.0 - exp(-delta * 7.0)
	for p in cur:
		cur[p] = lerpf(cur[p], target[p], k)
	next_blink -= delta
	if next_blink <= 0.0:
		blink = 1.0
		next_blink = randf_range(2.0, 5.5)
	blink = maxf(0.0, blink - delta * 7.0)
	next_dart -= delta
	if next_dart <= 0.0:
		var nervous := emotion in ["nervoso", "assustado", "desconfiado"]
		dart = Vector2(randf_range(-0.5, 0.5), randf_range(-0.2, 0.2)) * (1.6 if nervous else 0.6)
		next_dart = randf_range(0.3, 0.9) if nervous else randf_range(1.5, 4.0)
	talk_left = maxf(0.0, talk_left - delta)
	queue_redraw()


# ---------- helpers ----------

func _ellipse(c: Vector2, rx: float, ry: float, n: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _quad(a: Vector2, ctrl: Vector2, b: Vector2, n: int = 12) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var u := float(i) / n
		pts.append(a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u))
	return pts


func _poly(pts: PackedVector2Array, color: Color) -> void:
	if pts.size() < 3 or color.a <= 0.01:
		return
	if Geometry2D.triangulate_polygon(pts).is_empty():
		pts = Geometry2D.convex_hull(pts)
		if pts.size() < 4:
			return
	draw_colored_polygon(pts, color)


func _shade(shape: PackedVector2Array, mask: PackedVector2Array, color: Color) -> void:
	for p in Geometry2D.intersect_polygons(shape, mask):
		_poly(p, color)


func _line(pts: PackedVector2Array, color: Color, w: float) -> void:
	if pts.size() >= 2 and color.a > 0.01:
		draw_polyline(pts, color, w, true)


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out


func _taper(pts: PackedVector2Array, w0: float, w1: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in pts.size():
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, pts.size() - 1)]
		var n := (b - a).orthogonal().normalized()
		var w := lerpf(w0, w1, float(i) / maxf(1.0, pts.size() - 1.0)) * 0.5
		left.append(pts[i] + n * w)
		right.append(pts[i] - n * w)
	right.reverse()
	left.append_array(right)
	return left


func _l(key: String, default: Variant) -> Variant:
	return look.get(key, default)


func _shadow_of(c: Color) -> Color:
	return c.darkened(0.3).lerp(Color(0.24, 0.28, 0.4), 0.22)


func _light_of(c: Color) -> Color:
	return c.lightened(0.14).lerp(Color(1.0, 0.95, 0.85), 0.06)


func _rx() -> float:
	return 82.0 * float(_l("face_w", 1.0))


func _head_pts(grow: float = 0.0, offset: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var jaw := float(_l("jaw", 0.72))
	var chin := float(_l("chin", 1.0))
	var rnd := float(_l("chin_round", 0.75))
	var rx := _rx() + grow
	var ry := 104.0 + grow
	var pts := PackedVector2Array()
	for i in 64:
		var a := TAU * i / 64.0
		var x := cos(a)
		var y := sin(a)
		if y > 0.0:
			x = signf(x) * pow(absf(x), rnd) * lerpf(1.0, jaw, pow(y, 2.0))
			y *= lerpf(1.0, chin, y)
		else:
			x *= 0.97
		pts.append(C + offset + Vector2(x * rx, y * ry))
	return pts


func _head_shadow_mask() -> PackedVector2Array:
	return PackedVector2Array([C + Vector2(30, -150), C + Vector2(46, -70), C + Vector2(40, -20), C + Vector2(56, 22), C + Vector2(50, 66), C + Vector2(22, 130), C + Vector2(220, 140), C + Vector2(220, -150)])


func _skin() -> Color:
	var s: Color = _l("skin", Color("#e8bf9c"))
	return s.lerp(Color(0.86, 0.86, 0.8), cur["pale"] * 0.3)


# ---------- quadro ----------

func _draw() -> void:
	var fit := size.x / BASE.x
	var s := clampf(size.y / BASE.y, fit, fit * 1.35)
	var origin := Vector2((size.x - BASE.x * s) / 2.0, size.y - BASE.y * s)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.02))
	draw_set_transform(origin, 0.0, Vector2(s, s))
	_draw_scene()
	if not look.is_empty():
		var shake := Vector2.ZERO
		if cur["tremble"] > 0.05:
			shake = Vector2(randf_range(-1, 1), randf_range(-0.6, 0.6)) * cur["tremble"] * 1.6
		var breath := sin(t * 1.8) * 1.3
		var body_off := Vector2(0, breath) + shake
		var head_xf := Transform2D(0.0, origin + (body_off + Vector2(0, breath * 0.3)) * s).scaled_local(Vector2(s, s)) \
			.translated_local(HEAD_POS).rotated_local(cur["tilt"]).scaled_local(Vector2(HS, HS)).translated_local(-C)
		draw_set_transform_matrix(head_xf)
		_draw_back_hair()
		draw_set_transform_matrix(Transform2D(0.0, origin + body_off * s).scaled_local(Vector2(s, s)))
		_draw_body()
		draw_set_transform_matrix(head_xf)
		_draw_head()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_mood()


func _draw_mood() -> void:
	if vignette_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0))
		g.set_color(1, Color(0, 0, 0, 0.97))
		g.add_point(0.62, Color(0, 0, 0, 0.12))
		g.add_point(0.8, Color(0, 0, 0, 0.6))
		vignette_tex = GradientTexture2D.new()
		vignette_tex.gradient = g
		vignette_tex.fill = GradientTexture2D.FILL_RADIAL
		vignette_tex.fill_from = Vector2(0.5, 0.45)
		vignette_tex.fill_to = Vector2(1.02, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.12, 0.1, 0.12))
	draw_texture_rect(vignette_tex, Rect2(Vector2.ZERO, size), false)
	for i in 900:
		var p := Vector2(randf() * size.x, randf() * size.y)
		draw_rect(Rect2(p, Vector2(1, 1)), Color(1, 1, 1, 0.05) if i % 2 == 0 else Color(0, 0, 0, 0.14))


# ---------- cenário ----------

func _draw_scene() -> void:
	var pal: Array = SCENE_COLORS.get(scene, SCENE_COLORS["vazio"])
	var wall: Color = pal[0]
	var dark: Color = pal[1]
	var light: Color = pal[2]
	var rng := RandomNumberGenerator.new()
	rng.seed = scene.hash()
	draw_rect(Rect2(Vector2.ZERO, BASE), wall)
	match scene:
		"bar":
			draw_rect(Rect2(0, 60, 300, 10), dark.darkened(0.3))
			draw_rect(Rect2(0, 130, 300, 10), dark.darkened(0.3))
			for row in [60, 130]:
				for i in 16:
					var x := 8 + i * 18 + rng.randf_range(-3, 3)
					var h := rng.randf_range(26, 44)
					var col: Color = [Color("#2f5a3a"), Color("#6b3a1e"), Color("#a8892c"), Color("#3a2a4a")][rng.randi() % 4]
					draw_rect(Rect2(x, row - h, 10, h), col)
					draw_rect(Rect2(x + 3, row - h - 8, 4, 9), col.darkened(0.3))
					_line(_closed(PackedVector2Array([Vector2(x, row - h), Vector2(x + 10, row - h), Vector2(x + 10, row), Vector2(x, row)])), INK, 1.2)
			draw_rect(Rect2(0, 300, 300, 100), dark)
			draw_rect(Rect2(0, 296, 300, 10), dark.lightened(0.15))
			_poly(_ellipse(Vector2(60, 20), 70, 50), Color(light.r, light.g, light.b, 0.18))
		"loja":
			for row in 4:
				var y := 40 + row * 70
				draw_rect(Rect2(0, y, 300, 6), dark)
				for i in 9:
					var x := 4 + i * 33 + rng.randf_range(-2, 2)
					var bw := rng.randf_range(24, 30)
					var bh := rng.randf_range(30, 50)
					draw_rect(Rect2(x, y - bh, bw, bh), Color(0.92, 0.9, 0.84).darkened(rng.randf_range(0.0, 0.2)))
					_line(_closed(PackedVector2Array([Vector2(x, y - bh), Vector2(x + bw, y - bh), Vector2(x + bw, y), Vector2(x, y)])), INK, 1.2)
			draw_rect(Rect2(0, 0, 300, 14), light)
		"comida":
			for x in range(0, 300, 22):
				_line(PackedVector2Array([Vector2(x, 0), Vector2(x, 240)]), dark.lightened(0.3), 1.0)
			for y in range(0, 240, 22):
				_line(PackedVector2Array([Vector2(0, y), Vector2(300, y)]), dark.lightened(0.3), 1.0)
			draw_rect(Rect2(170, 30, 110, 70), Color("#2a2a26"))
			for i in 4:
				draw_rect(Rect2(180, 42 + i * 14, rng.randf_range(40, 85), 4), Color(0.9, 0.9, 0.8, 0.7))
			draw_rect(Rect2(0, 240, 300, 160), dark)
			draw_rect(Rect2(0, 236, 300, 10), dark.lightened(0.25))
		"casa":
			for x in range(0, 300, 16):
				draw_rect(Rect2(x, 0, 7, 300), wall.lightened(0.06))
			draw_rect(Rect2(196, 40, 80, 100), Color("#14203a"))
			_line(_closed(PackedVector2Array([Vector2(196, 40), Vector2(276, 40), Vector2(276, 140), Vector2(196, 140)])), dark, 5.0)
			_line(PackedVector2Array([Vector2(236, 40), Vector2(236, 140)]), dark, 3.0)
			draw_rect(Rect2(20, 60, 50, 40), Color("#7a6040"))
			_line(_closed(PackedVector2Array([Vector2(20, 60), Vector2(70, 60), Vector2(70, 100), Vector2(20, 100)])), INK, 2.0)
			draw_rect(Rect2(0, 300, 300, 100), dark)
		"rua":
			for i in 7:
				var x := i * 46 + rng.randf_range(-6, 6)
				var h := rng.randf_range(120, 260)
				draw_rect(Rect2(x, 300 - h, 44, h), dark.lightened(rng.randf_range(0.0, 0.08)))
				for wy in range(int(300 - h + 12), 290, 22):
					for wx in [x + 8, x + 26]:
						if rng.randf() < 0.35:
							draw_rect(Rect2(wx, wy, 9, 11), Color(light.r, light.g, light.b, 0.8))
			draw_rect(Rect2(0, 300, 300, 100), Color("#1a1a1e"))
			_line(PackedVector2Array([Vector2(30, 300), Vector2(30, 90)]), INK, 5.0)
			_poly(_ellipse(Vector2(30, 86), 40, 28), Color(light.r, light.g, light.b, 0.2))
			draw_circle(Vector2(30, 88), 6, light)
		"parque":
			draw_circle(Vector2(240, 60), 22, light.darkened(0.1))
			for i in 9:
				var x := rng.randf_range(-20, 320)
				var r := rng.randf_range(40, 80)
				_poly(_ellipse(Vector2(x, rng.randf_range(120, 220)), r, r * 1.2), dark.lightened(rng.randf_range(0.0, 0.12)))
			draw_rect(Rect2(0, 290, 300, 110), Color("#101810"))
		"beco":
			for row in 20:
				var y := row * 16
				var off := 0 if row % 2 == 0 else 14
				for i in 12:
					var x := i * 28 - off
					draw_rect(Rect2(x + 1, y + 1, 26, 14), wall.darkened(rng.randf_range(0.0, 0.25)))
			draw_rect(Rect2(10, 230, 80, 90), Color("#1e3a2a"))
			_line(_closed(PackedVector2Array([Vector2(10, 230), Vector2(90, 230), Vector2(90, 320), Vector2(10, 320)])), INK, 2.5)
			draw_rect(Rect2(0, 320, 300, 80), dark)
			_poly(_ellipse(Vector2(230, 0), 80, 60), Color(light.r, light.g, light.b, 0.2))
		"servico":
			draw_rect(Rect2(0, 200, 300, 200), wall.darkened(0.15))
			_line(PackedVector2Array([Vector2(0, 200), Vector2(300, 200)]), dark, 3.0)
			draw_rect(Rect2(210, 50, 70, 250), dark.lightened(0.1))
			_line(_closed(PackedVector2Array([Vector2(210, 50), Vector2(280, 50), Vector2(280, 300), Vector2(210, 300)])), INK, 3.0)
			draw_rect(Rect2(20, 60, 60, 44), Color(0.85, 0.8, 0.65))
			for i in 3:
				draw_rect(Rect2(26, 68 + i * 10, rng.randf_range(20, 45), 4), Color(0.3, 0.3, 0.3, 0.7))
			draw_rect(Rect2(0, 0, 300, 10), light)
		"hospedagem":
			for x in range(0, 300, 30):
				for y in range(0, 300, 30):
					_poly(_ellipse(Vector2(x + 15, y + 15), 5, 7, 8), wall.darkened(0.15))
			draw_rect(Rect2(200, 70, 70, 230), Color("#4a3420"))
			_line(_closed(PackedVector2Array([Vector2(200, 70), Vector2(270, 70), Vector2(270, 300), Vector2(200, 300)])), INK, 3.0)
			draw_circle(Vector2(258, 190), 4, Color("#c9a227"))
			draw_rect(Rect2(0, 300, 300, 100), dark)
		"igreja":
			for x in [40, 150, 260]:
				_poly(_ellipse(Vector2(x, 130), 36, 70), dark)
				draw_rect(Rect2(x - 36, 130, 72, 170), dark)
			for i in 6:
				var cx := 30 + i * 48
				draw_rect(Rect2(cx, 270, 6, 24), Color(0.92, 0.9, 0.8))
				_poly(_ellipse(Vector2(cx + 3, 265), 4, 7, 10), light)
				_poly(_ellipse(Vector2(cx + 3, 265), 20, 20), Color(light.r, light.g, light.b, 0.12))
			draw_rect(Rect2(0, 300, 300, 100), dark.darkened(0.2))
	draw_rect(Rect2(Vector2.ZERO, BASE), Color(0, 0, 0, 0.18))


# ---------- corpo (espaço da tela) ----------

func _clothes_colors() -> Array:
	return [_l("clothes_color", Color("#3b4250")), _l("clothes_color2", Color("#dddddd"))]


func _draw_body() -> void:
	var cc: Array = _clothes_colors()
	var c1: Color = cc[0]
	var c2: Color = cc[1]
	var nk := float(_l("neck", 1.0))
	var style := str(_l("clothes", "camiseta"))
	var skin := _skin()
	var nx := 22.0 * nk
	var torso := PackedVector2Array([Vector2(-20, 400), Vector2(-14, 330), Vector2(20, 292), Vector2(90, 268), Vector2(150 - nx, 258), Vector2(150 + nx, 258), Vector2(210, 268), Vector2(280, 292), Vector2(314, 330), Vector2(320, 400)])
	var right_mask := PackedVector2Array([Vector2(178, 250), Vector2(190, 300), Vector2(172, 400), Vector2(330, 400), Vector2(330, 250)])
	var neck := PackedVector2Array([Vector2(150 - nx, 200), Vector2(150 + nx, 200), Vector2(150 + nx * 1.12, 272), Vector2(150 - nx * 1.12, 272)])
	_poly(neck, skin)
	_shade(neck, PackedVector2Array([Vector2(150 + nx * 0.2, 190), Vector2(400, 190), Vector2(400, 300), Vector2(150 + nx * 0.4, 300)]), _shadow_of(skin))
	_poly(PackedVector2Array([Vector2(150 - nx, 214), Vector2(150 + nx, 214), Vector2(150 + nx, 236), Vector2(150, 244), Vector2(150 - nx, 230)]), _shadow_of(skin))
	_line(PackedVector2Array([neck[0], neck[3]]), INK, 3.0)
	_line(PackedVector2Array([neck[1], neck[2]]), INK, 3.0)
	_line(PackedVector2Array([Vector2(150 - nx * 0.5, 246), Vector2(150 - nx * 0.3, 268)]), Color(INK, 0.4), 1.4)
	if 1 in _l("marks", []):
		_line(PackedVector2Array([Vector2(158, 236), Vector2(166, 244), Vector2(160, 252), Vector2(168, 258)]), Color(0.15, 0.2, 0.3, 0.85), 2.5)
		_line(_closed(_ellipse(Vector2(140, 248), 5, 5, 10)), Color(0.15, 0.2, 0.3, 0.85), 1.6)

	if style == "regata":
		_poly(torso, skin)
		_shade(torso, right_mask, _shadow_of(skin))
		var tank := PackedVector2Array([Vector2(85, 400), Vector2(92, 300), Vector2(110, 268), Vector2(122, 268), Vector2(150, 318), Vector2(178, 268), Vector2(190, 268), Vector2(208, 300), Vector2(215, 400)])
		_poly(tank, c1)
		_shade(tank, right_mask, _shadow_of(c1))
		_line(_closed(tank), INK, 2.5)
		_line(torso, INK, 3.0)
		return
	if style == "cobertor":
		var blanket := PackedVector2Array([Vector2(-20, 400), Vector2(-10, 300), Vector2(60, 250), Vector2(240, 250), Vector2(310, 300), Vector2(320, 400)])
		_poly(blanket, c1)
		_shade(blanket, right_mask, _shadow_of(c1))
		for i in 6:
			_line(_quad(Vector2(30 + i * 45, 270), Vector2(40 + i * 45, 330), Vector2(25 + i * 45, 400)), _shadow_of(c1).darkened(0.2), 2.0)
		_line(blanket, INK, 3.0)
		return

	_poly(torso, c1)
	_shade(torso, right_mask, _shadow_of(c1))
	_poly(PackedVector2Array([Vector2(110, 360), Vector2(150, 372), Vector2(190, 360), Vector2(186, 400), Vector2(114, 400)]), Color(_shadow_of(c1), 0.5))
	for side in [-1, 1]:
		_line(_quad(Vector2(150 + side * 95, 300), Vector2(150 + side * 100, 350), Vector2(150 + side * 104, 400)), INK, 2.2)
	_line(_quad(Vector2(120, 330), Vector2(132, 345), Vector2(126, 362)), Color(INK, 0.5), 1.6)
	_line(_quad(Vector2(182, 330), Vector2(170, 348), Vector2(178, 368)), Color(INK, 0.5), 1.6)
	var neckline := _quad(Vector2(150 - nx * 1.3, 262), Vector2(150, 290), Vector2(150 + nx * 1.3, 262))
	match style:
		"camiseta", "academia", "rasgada", "time", "uniforme":
			_line(neckline, c1.darkened(0.45), 5.0)
			if style == "time":
				for x in [80, 150, 220]:
					var stripe := PackedVector2Array([Vector2(x - 12, 290), Vector2(x + 12, 290), Vector2(x + 16, 400), Vector2(x - 16, 400)])
					_poly(stripe, c2)
					_shade(stripe, right_mask, _shadow_of(c2))
			if style == "rasgada":
				for p in [Vector2(70, 350), Vector2(210, 372), Vector2(130, 390)]:
					_poly(PackedVector2Array([p, p + Vector2(12, -8), p + Vector2(18, 4), p + Vector2(6, 12)]), skin.darkened(0.25))
			if style == "uniforme":
				draw_rect(Rect2(196, 310, 30, 14), Color(0.95, 0.95, 0.9))
				_line(_closed(PackedVector2Array([Vector2(196, 310), Vector2(226, 310), Vector2(226, 324), Vector2(196, 324)])), INK, 1.4)
		"moletom":
			_poly(_quad(Vector2(150 - nx * 1.8, 262), Vector2(150, 300), Vector2(150 + nx * 1.8, 262)), c1.darkened(0.25))
			_line(neckline, c1.darkened(0.5), 6.0)
			_line(PackedVector2Array([Vector2(140, 290), Vector2(137, 340)]), c2, 2.5)
			_line(PackedVector2Array([Vector2(160, 290), Vector2(163, 340)]), c2, 2.5)
		"couro", "jeans", "sobretudo":
			var inner := PackedVector2Array([Vector2(150 - nx * 1.2, 262), Vector2(150, 330), Vector2(150 + nx * 1.2, 262)])
			_poly(inner, c2)
			_line(PackedVector2Array([Vector2(150 - nx * 1.2, 262), Vector2(112, 300), Vector2(140, 400)]), INK, 2.6)
			_line(PackedVector2Array([Vector2(150 + nx * 1.2, 262), Vector2(188, 300), Vector2(160, 400)]), INK, 2.6)
			_line(PackedVector2Array([Vector2(150 - nx * 1.2, 262), Vector2(112, 300)]), c1.lightened(0.35), 1.4)
		"social", "terno", "farda", "jaleco":
			var shirt := PackedVector2Array([Vector2(150 - nx * 1.1, 260), Vector2(150, 312), Vector2(150 + nx * 1.1, 260), Vector2(170, 400), Vector2(130, 400)])
			_poly(shirt, c2 if style != "jaleco" else c1)
			_line(PackedVector2Array([Vector2(150 - nx * 1.1, 260), Vector2(150, 290), Vector2(150 + nx * 1.1, 260)]), INK, 2.2)
			if style == "terno":
				_poly(PackedVector2Array([Vector2(146, 292), Vector2(154, 292), Vector2(158, 380), Vector2(150, 390), Vector2(142, 380)]), Color("#6b1d24"))
			if style == "jaleco":
				var coat_l := PackedVector2Array([Vector2(-20, 400), Vector2(-14, 330), Vector2(20, 292), Vector2(90, 268), Vector2(150 - nx, 258), Vector2(130, 400)])
				var coat_r := PackedVector2Array([Vector2(150 + nx, 258), Vector2(210, 268), Vector2(280, 292), Vector2(314, 330), Vector2(320, 400), Vector2(170, 400)])
				for coat in [coat_l, coat_r]:
					_poly(coat, c2)
					_shade(coat, right_mask, _shadow_of(c2))
					_line(coat, INK, 2.6)
			if style == "farda":
				_poly(_ellipse(Vector2(212, 318), 9, 11, 6), Color("#c9a227"))
				_line(_closed(_ellipse(Vector2(212, 318), 9, 11, 6)), INK, 1.4)
		"vestido", "blusa":
			var v := PackedVector2Array([Vector2(150 - nx * 1.4, 262), Vector2(150, 312), Vector2(150 + nx * 1.4, 262)])
			_poly(v, skin)
			_shade(v, right_mask, _shadow_of(skin))
			_line(v, INK, 2.4)
		"macacao", "avental":
			_line(neckline, c1.darkened(0.45), 5.0)
			for x in [104, 196]:
				var strap := PackedVector2Array([Vector2(x - 9, 272), Vector2(x + 9, 272), Vector2(x + 12, 400), Vector2(x - 12, 400)])
				_poly(strap, c2)
				_line(_closed(strap), INK, 1.8)
			if style == "avental":
				var apron := PackedVector2Array([Vector2(92, 340), Vector2(208, 340), Vector2(214, 400), Vector2(86, 400)])
				_poly(apron, c2)
				_line(apron, INK, 2.0)
		"batina":
			draw_rect(Rect2(138, 258, 24, 10), Color(0.95, 0.95, 0.95))
			_line(_closed(PackedVector2Array([Vector2(138, 258), Vector2(162, 258), Vector2(162, 268), Vector2(138, 268)])), INK, 1.4)
			for i in 5:
				draw_circle(Vector2(150, 290 + i * 22), 2.2, Color(0.3, 0.3, 0.3))
		"havaiana":
			for p in [Vector2(60, 330), Vector2(110, 370), Vector2(200, 340), Vector2(245, 380), Vector2(150, 320), Vector2(90, 300), Vector2(225, 300)]:
				_poly(_ellipse(p, 10, 7, 8), c2)
				_line(_closed(_ellipse(p, 10, 7, 8)), INK, 1.0)
			_line(neckline, c1.darkened(0.45), 4.0)
	_line(torso, INK, 3.2)
	if 12 in _l("marks", []):
		_line(_quad(Vector2(150 - nx * 1.2, 256), Vector2(150, 296), Vector2(150 + nx * 1.2, 256)), Color("#d4a72c"), 3.5)
	if "toalha" in _l("extras", []):
		var towel := PackedVector2Array([Vector2(196, 264), Vector2(240, 276), Vector2(246, 330), Vector2(210, 334)])
		_poly(towel, Color(0.85, 0.82, 0.72))
		_line(_closed(towel), INK, 2.0)
	if "fone" in _l("extras", []):
		_line(_quad(Vector2(108, 246), Vector2(150, 285), Vector2(192, 246)), Color(0.12, 0.12, 0.14), 6.0)
		for x in [108, 192]:
			_poly(_ellipse(Vector2(x, 246), 13, 15), Color(0.2, 0.2, 0.22))
			_line(_closed(_ellipse(Vector2(x, 246), 13, 15)), INK, 1.8)


# ---------- cabeça (espaço da cabeça) ----------

func _hair_color() -> Color:
	return _l("hair_color", Color("#2a1d16"))


func _draw_back_hair() -> void:
	var hc := _hair_color()
	var dark := _shadow_of(hc).darkened(0.15)
	var rx := _rx()
	match str(_l("hair", "curto")):
		"medio":
			var pts := PackedVector2Array([C + Vector2(-rx - 14, -60), C + Vector2(-rx - 16, 60), C + Vector2(-rx + 10, 78), C + Vector2(rx - 10, 78), C + Vector2(rx + 16, 60), C + Vector2(rx + 14, -60)])
			_poly(pts, dark)
			_line(pts, INK, 3.0)
		"longo":
			var pts := PackedVector2Array([C + Vector2(-rx - 14, -60), C + Vector2(-rx - 26, 160), C + Vector2(-60, 190), C + Vector2(60, 190), C + Vector2(rx + 26, 160), C + Vector2(rx + 14, -60)])
			_poly(pts, dark)
			_line(pts, INK, 3.0)
		"black_power":
			var cloud := PackedVector2Array()
			for i in 36:
				var a := TAU * i / 36.0
				var r := 1.0 + (0.06 if i % 2 == 0 else 0.0)
				cloud.append(C + Vector2(0, -40) + Vector2(cos(a) * rx * 1.55 * r, sin(a) * 125 * r))
			_poly(cloud, hc)
			_shade(cloud, _head_shadow_mask(), dark)
			_line(_closed(cloud), INK, 3.0)
		"trancas", "dreads":
			for i in 16:
				var x := -rx - 8 + (2.0 * rx + 16) * i / 15.0
				if absf(x) < rx * 0.6:
					continue
				var start := C + Vector2(x, -20)
				var end := C + Vector2(x * 1.12, 170 + (i % 3) * 10)
				_line(PackedVector2Array([start, end]), INK, 11.0)
				_line(PackedVector2Array([start, end]), hc, 7.0)
		"rabo":
			var tail := PackedVector2Array([C + Vector2(rx - 16, -60), C + Vector2(rx + 34, 30), C + Vector2(rx + 22, 160), C + Vector2(rx - 4, 70)])
			_poly(tail, dark)
			_line(_closed(tail), INK, 3.0)
		"coque":
			var bun := _ellipse(C + Vector2(0, -112), 30, 25)
			_poly(bun, hc)
			_shade(bun, _head_shadow_mask(), dark)
			_line(_closed(bun), INK, 3.0)


func _draw_head() -> void:
	var skin := _skin()
	var rx := _rx()
	var sh := _shadow_of(skin)
	for side in [-1, 1]:
		var ec := C + Vector2(side * rx * 0.97, 8)
		var ear := _ellipse(ec, 12, 21)
		_poly(ear, skin if side == -1 else sh)
		_line(_quad(ec + Vector2(-side * 2, -10), ec + Vector2(side * 6, 0), ec + Vector2(-side * 2, 10), 6), Color(INK, 0.6), 1.6)
		_line(_closed(ear), INK, 2.6)
		if 4 in _l("marks", []):
			draw_circle(ec + Vector2(side * 2, 15), 2.4, Color("#d9d9d9"))
			draw_circle(ec + Vector2(side * 7, 4), 2.0, Color("#d9d9d9"))
		if 14 in _l("marks", []):
			_line(_closed(_ellipse(ec + Vector2(0, 30), 6, 9, 14)), Color("#d4a72c"), 2.2)
	var head := _head_pts()
	_poly(head, skin)
	_shade(head, _head_shadow_mask(), sh)
	_shade(head, _ellipse(C + Vector2(0, 118), 90, 26), sh)
	for side in [-1, 1]:
		_poly(_ellipse(_eye_center(side) + Vector2(side * 2, -4), 24, 13), Color(sh, 0.55))
	_poly(_ellipse(C + Vector2(-28, -52), 22, 12), _light_of(skin))
	_poly(PackedVector2Array([C + Vector2(-4, 4), C + Vector2(2, 4), C + Vector2(0, 40), C + Vector2(-6, 40)]), _light_of(skin))
	_poly(_ellipse(C + Vector2(-46, 26), 13, 6), _light_of(skin))
	if _l("double_chin", false):
		_line(_quad(C + Vector2(-34, 106), C + Vector2(0, 124), C + Vector2(34, 106)), INK, 2.4)
	if _l("hollow", false):
		for side in [-1, 1]:
			_poly(_ellipse(C + Vector2(side * 46, 46), 13, 22), sh.darkened(0.1))
	_draw_age_lines(skin)
	_draw_cheeks()
	_draw_beard()
	for side in [-1, 1]:
		_draw_eye(side)
	_draw_nose(skin)
	_draw_mouth(skin)
	_draw_face_marks()
	_draw_fx()
	_line(_closed(head), INK, 3.6)
	_line(_quad(C + Vector2(40, 30), C + Vector2(48, 50), C + Vector2(38, 72)), Color(INK, 0.45), 1.6)
	_draw_front_hair()
	_draw_headwear()


func _draw_age_lines(skin: Color) -> void:
	var age := float(_l("age", 30))
	var wr := clampf((age - 30.0) / 35.0, 0.0, 1.0) + (0.4 if _l("weathered", false) else 0.0)
	var col := Color(INK, clampf(0.25 + wr * 0.6, 0.0, 0.85))
	for side in [-1, 1]:
		_line(_quad(C + Vector2(side * 20, 40), C + Vector2(side * 33, 56), C + Vector2(side * 31, 74)), col, 1.8)
	if wr <= 0.05:
		return
	for i in 3:
		var y := -60.0 + i * 8.0
		_line(_quad(C + Vector2(-28, y), C + Vector2(0, y - 4), C + Vector2(28, y)), Color(INK, 0.4 * wr), 1.5)
	for side in [-1, 1]:
		_line(PackedVector2Array([C + Vector2(side * 52, 2), C + Vector2(side * 60, -3)]), Color(INK, 0.5 * wr), 1.4)
		_line(PackedVector2Array([C + Vector2(side * 52, 9), C + Vector2(side * 60, 11)]), Color(INK, 0.5 * wr), 1.4)


func _draw_cheeks() -> void:
	if cur["blush"] > 0.02:
		for side in [-1, 1]:
			_poly(_ellipse(C + Vector2(side * 42, 40), 18, 9), Color(0.85, 0.25, 0.25, 0.45 * cur["blush"]))
			for i in 3:
				var p := C + Vector2(side * 42 - 8 + i * 7, 38)
				_line(PackedVector2Array([p, p + Vector2(-3, 5)]), Color(0.6, 0.1, 0.1, 0.5 * cur["blush"]), 1.2)
	var dc: float = maxf(cur["dark_circles"], 0.6 if 9 in _l("marks", []) else 0.0)
	if dc > 0.02:
		for side in [-1, 1]:
			_poly(_ellipse(C + Vector2(side * 37, 22), 17, 6), Color(0.28, 0.16, 0.3, 0.5 * dc))


func _eye_center(side: int) -> Vector2:
	return C + Vector2(side * 37, 8)


func _draw_eye(side: int) -> void:
	var c := _eye_center(side)
	var open: float = cur["eye_open"] * (1.0 - blink) * (1.0 - cur["squint"] * 0.45)
	if side == 1 and cur["bruise"] > 0.1:
		open *= 1.0 - 0.65 * cur["bruise"]
	var w := 21.0
	var h := 9.5 * open * float(_l("eye_h", 1.0))
	var tilt := float(_l("eye_tilt", 0.0)) * -side
	if side == 1 and cur["bruise"] > 0.1:
		_poly(_ellipse(c + Vector2(0, 2), 27, 18), Color(0.35, 0.15, 0.4, 0.6 * cur["bruise"]))
	if cur["shadow_eyes"] > 0.02:
		_poly(_ellipse(c + Vector2(0, -6), 30, 18), Color(0, 0, 0, 0.4 * cur["shadow_eyes"]))
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in 13:
		var u := i / 12.0
		var x := lerpf(-w, w, u)
		var skew := x * tilt * 0.25
		var peak := sin(PI * pow(u, 0.85 if side == -1 else 1.15))
		top.append(c + Vector2(x, -h * peak + skew))
		bot.append(c + Vector2(x, h * 0.65 * sin(PI * u) + skew))
	if h > 1.2:
		var white := top.duplicate()
		var rb := bot.duplicate()
		rb.reverse()
		white.append_array(rb)
		_poly(white, Color(0.9, 0.87, 0.82))
		var g := Vector2(cur["gaze_x"] + dart.x, cur["gaze_y"] + dart.y)
		var ic := c + Vector2(g.x * 8.0, g.y * 3.0 - 1.0)
		var ir := 7.2
		var iy := minf(ir, h * 1.05)
		var iris: Color = _l("eye_color", Color("#5a3a22"))
		if _l("hetero", false) and side == 1:
			iris = Color("#4a78a8")
		_poly(_ellipse(ic, ir, iy, 20), iris)
		_poly(_ellipse(ic + Vector2(0, -iy * 0.4), ir, iy * 0.55, 16), iris.darkened(0.35))
		_poly(_ellipse(ic, 3.4 * cur["pupil"], minf(3.4 * cur["pupil"], iy), 14), Color(0.03, 0.03, 0.03))
		_line(_closed(_ellipse(ic, ir, iy, 20)), Color(INK, 0.7), 1.2)
		draw_circle(ic + Vector2(-2.4, -2.4), 1.5, Color(1, 1, 1, 0.9))
	_line(top, INK, 3.4 if str(_l("gender", "homem")) == "mulher" else 3.0)
	_line(PackedVector2Array([top[12 if side == 1 else 0], top[12 if side == 1 else 0] + Vector2(side * 5, -3)]), INK, 2.2)
	_line(bot, Color(INK, 0.6), 1.3)
	_line(_quad(c + Vector2(-w * 0.7, h * 0.7 + 5), c + Vector2(0, h * 0.7 + 9), c + Vector2(w * 0.7, h * 0.7 + 4), 8), Color(INK, 0.3), 1.2)
	_line(_quad(c + Vector2(-w * 0.85, -h - 5), c + Vector2(0, -h - 10), c + Vector2(w * 0.85, -h - 5), 8), Color(INK, 0.45), 1.4)
	if 7 in _l("marks", []):
		_line(_closed(_ellipse(c, 27, 19, 24)), Color(0.12, 0.12, 0.14), 3.0)
		if side == -1:
			_line(PackedVector2Array([c + Vector2(27, -2), c + Vector2(47, -2)]), Color(0.12, 0.12, 0.14), 3.0)
	if 8 in _l("marks", []):
		_poly(_ellipse(c, 28, 18, 24), Color(0.04, 0.04, 0.05, 0.95))
		_line(PackedVector2Array([c + Vector2(-8, -10), c + Vector2(4, -12)]), Color(1, 1, 1, 0.3), 2.0)
		if side == -1:
			_line(PackedVector2Array([c + Vector2(28, -4), c + Vector2(46, -4)]), Color(0.1, 0.1, 0.1), 3.0)
	_draw_brow(side, c)


func _draw_brow(side: int, c: Vector2) -> void:
	var raise: float = cur["brow_raise"] + (cur["brow_asym"] * 0.5 if side == 1 else -cur["brow_asym"] * 0.3)
	var base_y: float = c.y - 23.0 - raise * 9.0
	var inner := Vector2(c.x - side * 16.0, base_y + cur["brow_angle"] * 9.0)
	var outer := Vector2(c.x + side * 26.0, base_y - cur["brow_angle"] * 2.5 + 3.0)
	var mid := inner.lerp(outer, 0.4) + Vector2(0, -6)
	var col := _hair_color().darkened(0.25)
	if str(_l("hair", "")) == "careca":
		col = Color(0.2, 0.15, 0.12)
	var bw := float(_l("brow_w", 5.0)) * 1.3
	var shape := _taper(_quad(inner, mid, outer, 10), bw, bw * 0.4)
	_poly(shape, col)
	_line(_closed(shape), INK, 1.2)
	if 5 in _l("marks", []) and side == 1:
		draw_circle(outer + Vector2(-6, -4), 2.0, Color("#d9d9d9"))


func _draw_nose(skin: Color) -> void:
	var nw := float(_l("nose_w", 1.0))
	var bend := 4.0 if 16 in _l("marks", []) else 0.0
	var tip := C + Vector2(bend, 48)
	_poly(PackedVector2Array([C + Vector2(5, 8), tip + Vector2(12 * nw, -4), tip + Vector2(10 * nw, 6), tip + Vector2(2, 8)]), _shadow_of(skin))
	_line(PackedVector2Array([C + Vector2(5, 8), C + Vector2(6 + bend * 0.5, 30), tip + Vector2(10 * nw, -2)]), Color(INK, 0.7), 1.8)
	_line(_quad(tip + Vector2(-13 * nw, 2), tip + Vector2(0, 11), tip + Vector2(13 * nw, 2), 10), INK, 2.6)
	for side in [-1, 1]:
		_poly(_ellipse(tip + Vector2(side * 6 * nw, 4), 3.2 * nw, 2, 10), Color(0.2, 0.08, 0.08, 0.8))
	draw_circle(tip + Vector2(-3, -4), 2.2, _light_of(skin))
	if 3 in _l("marks", []):
		draw_circle(tip + Vector2(-10 * nw, 3), 2.2, Color("#d9d9d9"))


func _draw_mouth(skin: Color) -> void:
	var y := C.y + 74.0
	var flap := 0.0
	if talk_left > 0.0:
		flap = absf(sin(t * 15.0)) * 0.35 + absf(sin(t * 6.3)) * 0.12
	var open := clampf(cur["mouth_open"] + flap, 0.0, 1.2)
	var full := float(_l("lips", 1.0))
	var w: float = 27.0 * cur["mouth_width"] * (1.0 + 0.2 * maxf(cur["mouth_curve"], 0.0))
	var curve: float = cur["mouth_curve"]
	var left := Vector2(C.x - w, y - curve * 8.0)
	var right := Vector2(C.x + w, y - curve * 8.0 - cur["smirk"] * 9.0)
	var up_mid := Vector2(C.x + cur["smirk"] * 3.0, y + curve * 2.0 - 1.0)
	var low_mid := Vector2(C.x, y + curve * 4.0 + open * 38.0 + 4.0 * full)
	var lip_col: Color = _l("lip_color", skin.darkened(0.22).lerp(Color(0.6, 0.25, 0.25), 0.3))
	var upper := _quad(left, up_mid, right, 14)
	var lower := _quad(left, low_mid, right, 14)
	var mouth := upper.duplicate()
	var rl := lower.duplicate()
	rl.reverse()
	mouth.append_array(rl)
	_poly(_ellipse(Vector2(C.x, low_mid.y + 8 + 3 * full), 14, 4), Color(_shadow_of(skin), 0.8))
	if open > 0.06:
		_poly(mouth, Color(0.16, 0.04, 0.05))
		if cur["teeth"] > 0.3 or open > 0.35:
			var tbot := _quad(left.lerp(up_mid, 0.15), up_mid + Vector2(0, minf(9.0, open * 16.0)), right.lerp(up_mid, 0.15), 10)
			var tpoly := _quad(left.lerp(up_mid, 0.15), up_mid + Vector2(0, -1), right.lerp(up_mid, 0.15), 10)
			var tr := tbot.duplicate()
			tr.reverse()
			tpoly.append_array(tr)
			_poly(tpoly, Color(0.9, 0.88, 0.8))
			for i in 4:
				var x := lerpf(left.x, right.x, 0.3 + i * 0.13)
				_line(PackedVector2Array([Vector2(x, up_mid.y), Vector2(x, up_mid.y + minf(8.0, open * 14.0))]), Color(INK, 0.4), 1.0)
			if 10 in _l("marks", []) or "dente_ouro" in _l("extras", []):
				_poly(_ellipse(up_mid + Vector2(6, 3), 3, 3, 8), Color("#d4a72c"))
		_poly(_ellipse(Vector2(C.x, low_mid.y - 4), w * 0.45, 4), Color(0.55, 0.2, 0.22, 0.7 * minf(open * 2.0, 1.0)))
		_line(_closed(mouth), INK, 2.6)
		_line(_quad(left, low_mid + Vector2(0, 3 * full), right, 14), lip_col, 2.6 * full)
	else:
		_line(_quad(left, low_mid + Vector2(0, 2 + 3 * full), right, 14), lip_col, 3.4 * full)
		_line(upper, INK, 2.8)
	_line(PackedVector2Array([left + Vector2(-4, -1), left]), INK, 1.8)
	_line(PackedVector2Array([right, right + Vector2(4, -1)]), INK, 1.8)
	_line(PackedVector2Array([C + Vector2(-3, 58), C + Vector2(-2, 68)]), Color(INK, 0.3), 1.2)
	if 13 in _l("marks", []):
		_line(upper, Color(0.6, 0.08, 0.15, 0.85), 3.4)


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
				if p.y > C.y + 30:
					pts.append(p)
			if b == "long":
				pts.append(C + Vector2(0, 160))
			pts.append(C + Vector2(-26, 60))
			pts.append(C + Vector2(26, 60))
			var beard := _sorted_around(pts)
			_poly(beard, hc)
			_shade(beard, _head_shadow_mask(), _shadow_of(hc))
			for i in 9:
				var x := -50.0 + i * 12.5
				_line(PackedVector2Array([C + Vector2(x, 70), C + Vector2(x * 0.8, 110 if b == "full" else 150)]), Color(INK, 0.35), 1.2)
			_line(_closed(beard), INK, 2.4)
			_draw_mustache(hc)
		"goatee":
			var g := _ellipse(C + Vector2(0, 100), 17, 15)
			_poly(g, hc)
			_line(_closed(g), INK, 2.0)
			_draw_mustache(hc)
		"mustache":
			_draw_mustache(hc, 1.4)


func _stubble(hc: Color, alpha: float) -> void:
	var head := _head_pts(-2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var col := hc.darkened(0.2)
	col.a = alpha
	var mouth_c := C + Vector2(0, 76)
	for i in 1000:
		var p := C + Vector2(rng.randf_range(-_rx(), _rx()), rng.randf_range(38, 112))
		if not Geometry2D.is_point_in_polygon(p, head):
			continue
		if ((p - mouth_c) / Vector2(28, 10)).length() < 1.0:
			continue
		if p.y < C.y + 62 and absf(p.x - C.x) < 18:
			continue
		draw_rect(Rect2(p, Vector2(1.4, 1.4)), col)


func _draw_mustache(hc: Color, scale: float = 1.0) -> void:
	var y := C.y + 66.0
	var pts := PackedVector2Array([Vector2(C.x - 27 * scale, y + 7 * scale), Vector2(C.x - 12, y - 5), Vector2(C.x, y - 3), Vector2(C.x + 12, y - 5), Vector2(C.x + 27 * scale, y + 7 * scale), Vector2(C.x, y + 4)])
	_poly(pts, hc.darkened(0.1))
	_line(_closed(pts), INK, 2.0)


func _sorted_around(pts: PackedVector2Array) -> PackedVector2Array:
	var center := Vector2.ZERO
	for p in pts:
		center += p
	center /= pts.size()
	var arr := Array(pts)
	arr.sort_custom(func(a, b): return (a - center).angle() < (b - center).angle())
	return PackedVector2Array(arr)


func _draw_face_marks() -> void:
	var m: Array = _l("marks", [])
	if 0 in m:
		_line(PackedVector2Array([C + Vector2(-60, 8), C + Vector2(-48, 30), C + Vector2(-42, 50)]), Color(0.5, 0.25, 0.22), 3.0)
		for i in 3:
			var p := C + Vector2(-57 + i * 7, 15 + i * 12)
			_line(PackedVector2Array([p + Vector2(-4, 2), p + Vector2(4, -2)]), Color(0.5, 0.25, 0.22), 1.6)
	if 2 in m:
		_line(PackedVector2Array([C + Vector2(52, 20), C + Vector2(56, 28), C + Vector2(50, 30)]), Color(0.1, 0.12, 0.2, 0.85), 2.2)
	if 6 in m:
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		for i in 30:
			var side := -1 if i % 2 == 0 else 1
			draw_circle(C + Vector2(side * rng.randf_range(18, 52), rng.randf_range(18, 45)), 1.3, Color(0.45, 0.25, 0.15, 0.6))
	if 15 in m:
		draw_circle(C + Vector2(-34, 52), 2.0, Color(0.25, 0.15, 0.1))
		draw_circle(C + Vector2(30, -20), 1.6, Color(0.25, 0.15, 0.1))
	if 17 in m:
		_poly(_ellipse(C + Vector2(48, 30), 16, 22), Color(0.6, 0.3, 0.3, 0.4))
	if cur["bruise"] > 0.1:
		_line(PackedVector2Array([C + Vector2(-46, 30), C + Vector2(-32, 38)]), Color(0.65, 0.05, 0.05, cur["bruise"]), 2.2)
		_poly(_ellipse(C + Vector2(10, 86), 4, 3), Color(0.6, 0.05, 0.05, cur["bruise"]))
		_poly(_ellipse(C + Vector2(-40, -40), 12, 8), Color(0.4, 0.2, 0.35, 0.4 * cur["bruise"]))


func _draw_fx() -> void:
	if cur["tears"] > 0.03:
		var a: float = cur["tears"]
		for side in [-1, 1]:
			var start := _eye_center(side) + Vector2(side * 6, 8)
			var stream := PackedVector2Array()
			for i in 9:
				var u := i / 8.0
				stream.append(start + Vector2(side * (4 * u + sin(u * 6 + t) * 1.5), u * 72 * a))
			_line(stream, Color(INK, 0.5 * a), 5.0)
			_line(stream, Color(0.72, 0.85, 1.0, 0.9 * a), 3.2)
			_line(stream, Color(1, 1, 1, 0.6 * a), 1.0)
			var drop_y := fmod(t * 45.0 + (side + 1) * 20.0, 80.0)
			draw_circle(start + Vector2(side * 4, drop_y), 3.0, Color(INK, 0.6 * a))
			draw_circle(start + Vector2(side * 4, drop_y), 2.3, Color(0.8, 0.9, 1.0, 0.9 * a))
	if cur["sweat"] > 0.03:
		var a2: float = cur["sweat"]
		for p in [Vector2(-38, -58), Vector2(30, -66), Vector2(56, -30)]:
			var y := fmod(t * 12.0 + p.x, 30.0)
			var d: Vector2 = C + p + Vector2(0, y)
			var drop := PackedVector2Array([d + Vector2(0, -7), d + Vector2(3.5, 0), d + Vector2(0, 3.5), d + Vector2(-3.5, 0)])
			_poly(drop, Color(0.78, 0.9, 1.0, 0.85 * a2))
			_line(_closed(drop), Color(INK, 0.6 * a2), 1.0)


func _draw_front_hair() -> void:
	var style := str(_l("hair", "curto"))
	var hc := _hair_color()
	var dark := _shadow_of(hc)
	var rx := _rx()
	if style == "careca":
		_poly(_ellipse(C + Vector2(-22, -76), 20, 8), Color(1, 1, 1, 0.12))
		return
	if style == "moicano":
		var strip := PackedVector2Array()
		for i in 9:
			var u := i / 8.0
			var a := deg_to_rad(lerpf(215, 325, u))
			var spike := 24.0 if i % 2 == 0 else 8.0
			strip.append(C + Vector2(cos(a) * 26, sin(a) * (104 + spike)))
		strip.append(C + Vector2(18, -62))
		strip.append(C + Vector2(-18, -62))
		_poly(strip, hc)
		_line(_closed(strip), INK, 2.6)
		return
	var hairline := -54.0
	var lock_len := 10.0
	match style:
		"franja":
			hairline = -36.0
			lock_len = 14.0
		"raspado":
			hairline = -60.0
			lock_len = 0.0
		"desgrenhado":
			lock_len = 20.0
		"black_power", "cacheado":
			lock_len = 8.0
	var grow := 2.0 if style == "raspado" else 8.0
	var cap := PackedVector2Array()
	for i in 23:
		var u := i / 22.0
		var a := deg_to_rad(lerpf(188, 352, u))
		var g := grow + (5.0 if style in ["desgrenhado", "cacheado", "black_power"] and i % 2 == 0 else 0.0)
		cap.append(C + Vector2(cos(a) * (rx + g), sin(a) * (104 + g)))
	var locks := 9
	for i in locks * 2 + 1:
		var u := float(i) / (locks * 2)
		var x := lerpf(rx * 0.98, -rx * 0.98, u)
		var edge := pow(absf(x) / rx, 2.0)
		var y := hairline + 26.0 * edge
		if i % 2 == 1:
			y += lock_len * (1.0 - edge * 0.5)
		cap.append(C + Vector2(x, y))
	if style == "raspado":
		_poly(cap, Color(hc, 0.55))
		return
	_poly(cap, hc)
	_shade(cap, _head_shadow_mask(), dark)
	_shade(cap, _ellipse(C + Vector2(-34, -86), 30, 12), hc.lightened(0.22))
	for i in 7:
		var x := -rx * 0.7 + i * rx * 0.23
		_line(_quad(C + Vector2(x * 0.6, -100), C + Vector2(x + 6, -80), C + Vector2(x, hairline + 10), 6), Color(INK, 0.55), 1.4)
	_line(_closed(cap), INK, 3.2)
	if style in ["medio", "longo", "trancas"]:
		for side in [-1, 1]:
			var lock := PackedVector2Array([C + Vector2(side * (rx - 6), -40), C + Vector2(side * (rx + 12), -30), C + Vector2(side * (rx + 14), 70 if style == "medio" else 130), C + Vector2(side * (rx - 4), 50)])
			_poly(lock, hc if side == -1 else dark)
			_line(_closed(lock), INK, 2.6)
	if style == "cacheado":
		for i in 16:
			var a := deg_to_rad(lerpf(190, 350, i / 15.0))
			var p := C + Vector2(cos(a) * (rx + 4), sin(a) * 108)
			var curl := _ellipse(p, 10, 10, 10)
			_poly(curl, hc if p.x < C.x + 15 else dark)
			_line(_closed(curl), INK, 1.6)


func _draw_headwear() -> void:
	var rx := _rx()
	if 11 in _l("marks", []):
		var cap_col := Color("#7a1f1f")
		var dome := PackedVector2Array()
		for i in 17:
			var a := deg_to_rad(lerpf(185, 355, i / 16.0))
			dome.append(C + Vector2(cos(a) * (rx + 7), sin(a) * 110))
		dome.append(C + Vector2(rx + 7, -50))
		dome.append(C + Vector2(-rx - 7, -50))
		_poly(dome, cap_col)
		_shade(dome, _head_shadow_mask(), _shadow_of(cap_col))
		var brim := PackedVector2Array([C + Vector2(-rx - 4, -52), C + Vector2(rx + 4, -52), C + Vector2(rx + 34, -38), C + Vector2(-rx - 34, -38)])
		_poly(brim, cap_col.darkened(0.35))
		_line(_closed(brim), INK, 2.4)
		_line(_closed(dome), INK, 2.8)
	if "chapeu" in _l("extras", []):
		var brim2 := PackedVector2Array([C + Vector2(-rx - 44, -74), C + Vector2(rx + 44, -74), C + Vector2(rx + 32, -86), C + Vector2(-rx - 32, -86)])
		var crown := PackedVector2Array([C + Vector2(-rx + 10, -82), C + Vector2(rx - 10, -82), C + Vector2(rx - 22, -134), C + Vector2(-rx + 22, -134)])
		_poly(crown, Color(0.3, 0.24, 0.18))
		_shade(crown, _head_shadow_mask(), Color(0.2, 0.16, 0.12))
		_poly(PackedVector2Array([C + Vector2(-rx + 12, -90), C + Vector2(rx - 12, -90), C + Vector2(rx - 13, -100), C + Vector2(-rx + 13, -100)]), Color(0.12, 0.1, 0.08))
		_line(_closed(crown), INK, 2.6)
		_poly(brim2, Color(0.25, 0.2, 0.15))
		_line(_closed(brim2), INK, 2.6)
	if "bobes" in _l("extras", []):
		for i in 5:
			var p := C + Vector2(-48 + i * 24, -96 + absf(i - 2) * 8)
			_poly(_ellipse(p, 10, 8, 12), Color("#d56a8a"))
			_line(_closed(_ellipse(p, 10, 8, 12)), INK, 1.8)
	if "oculos_testa" in _l("extras", []):
		for side in [-1, 1]:
			_poly(_ellipse(C + Vector2(side * 28, -68), 18, 9, 16), Color(0.7, 0.78, 0.85, 0.9))
			_line(_closed(_ellipse(C + Vector2(side * 28, -68), 18, 9, 16)), INK, 2.0)
		_line(PackedVector2Array([C + Vector2(-10, -68), C + Vector2(10, -68)]), INK, 2.0)
