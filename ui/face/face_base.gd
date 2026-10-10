extends Control

# Retrato ilustrado no estilo "I'm Not Human": contorno grosso, sombras em blocos chapados,
# personagem de meio corpo na frente do cenário, vinheta de olho mágico.

const BASE := Vector2(300, 400)
const C := Vector2(150, 185)          # centro da cabeça no espaço da cabeça
const HEAD_POS := Vector2(150, 150)   # onde o centro da cabeça fica na tela
const HS := 0.88                      # escala da cabeça em relação ao corpo
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
var actor_mode: bool = false
var show_emote: bool = false
var emote_t: float = 1.0
var highlight: float = 0.0
var _redraw_t: float = 0.0
var dim: float = 0.0
var body_lift: float = 0.0  # sobe o corpo (pescoço mais curto), usado pelas idades no retrato pintado

const UI_FONT = preload("res://ui/ui_theme.gd")


func _ready() -> void:
	clip_contents = not actor_mode


func set_look(l: Dictionary) -> void:
	look = l
	queue_redraw()


func set_emotion(e: String, instant: bool = false) -> void:
	var new_emotion := e if EXPRESSIONS.has(e) else "neutro"
	if new_emotion != emotion:
		emote_t = 0.0
	emotion = new_emotion
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
	emote_t = minf(emote_t + delta, 1.0)
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
	# Redesenhar o rosto inteiro custa caro (dezenas de polígonos por script). Quando ele está
	# quieto, a respiração anda a ~15 quadros por segundo; ao falar, piscar ou mudar de expressão,
	# redesenha todo quadro. Escondido, não redesenha.
	if not is_visible_in_tree():
		return
	var settling := false
	for p in cur:
		if absf(float(cur[p]) - float(target[p])) > 0.004:
			settling = true
			break
	_redraw_t -= delta
	if settling or blink > 0.0 or talk_left > 0.0 or emote_t < 1.0 or highlight > 0.01 or _redraw_t <= 0.0:
		_redraw_t = 1.0 / 15.0
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


func _skin() -> Color:
	var s: Color = _l("skin", Color("#e8bf9c"))
	return s.lerp(Color(0.86, 0.86, 0.8), cur["pale"] * 0.3)


# ---------- quadro ----------

func _draw() -> void:
	var fit := size.x / BASE.x
	var s := clampf(size.y / BASE.y, fit, fit * 1.35)
	if actor_mode:
		s = minf(size.x / BASE.x, size.y / BASE.y)
	var origin := Vector2((size.x - BASE.x * s) / 2.0, size.y - BASE.y * s)
	if not actor_mode:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.02))
		draw_set_transform(origin, 0.0, Vector2(s, s))
		_draw_scene()
	if actor_mode and highlight > 0.01:
		draw_set_transform(origin, 0.0, Vector2(s, s))
		for i in 6:
			draw_circle(Vector2(150, 230), 150.0 - i * 20, Color(1.0, 0.8, 0.5, 0.025 * highlight))
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
		var shoulders := float(_l("shoulders", 1.0))
		draw_set_transform_matrix(Transform2D(0.0, origin + body_off * s).scaled_local(Vector2(s, s)) \
			.translated_local(Vector2(150, -body_lift)).scaled_local(Vector2(shoulders, 1.0)).translated_local(Vector2(-150, 0)))
		_draw_body()
		draw_set_transform_matrix(head_xf)
		_draw_head()
		if actor_mode and dim > 0.01:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if show_emote:
			draw_set_transform_matrix(Transform2D(0.0, origin + body_off * s).scaled_local(Vector2(s, s)))
			_draw_emote()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not actor_mode:
		_draw_mood()


const EMOTES := {
	"feliz": ["note", Color("#ffe9a8")], "rindo": ["haha", Color("#ffe9a8")], "triste": ["drop", Color("#d6e6ff")],
	"chorando": ["drops", Color("#cfe2ff")], "irritado": ["vein", Color("#ffd2c8")], "furioso": ["vein", Color("#ff8f80")],
	"desconfiado": ["q", Color("#f1ece0")], "assustado": ["exx", Color("#fff1f1")], "nervoso": ["sweat", Color("#e2f1ff")],
	"sarcastico": ["hm", Color("#f1ece0")], "ameacador": ["dark", Color("#1a1416")], "carinhoso": ["heart", Color("#ffe0ea")],
	"surpreso": ["ex", Color("#fff6d8")], "envergonhado": ["blush", Color("#ffe0ea")], "entediado": ["dots", Color("#e6e6e6")],
	"exausto": ["zz", Color("#dde3f0")], "machucado": ["pain", Color("#fff1c8")],
}


func _emote_text(c: Vector2, s: String, size_px: int, col: Color) -> void:
	var f := UI_FONT.font(true)
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	draw_string(f, c + Vector2(-w / 2.0, size_px * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)


func _draw_emote() -> void:
	if not EMOTES.has(emotion):
		return
	var e: Array = EMOTES[emotion]
	var pop := clampf(emote_t * 4.0, 0.0, 1.0)
	var sc := 1.0 + 0.25 * sin(pop * PI) - (1.0 - pop) * 0.6
	var c := Vector2(222, 46 + sin(t * 2.2) * 2.0)
	var r := 27.0 * sc
	var bg: Color = e[1]
	var tail := PackedVector2Array([c + Vector2(-16, 18) * sc, c + Vector2(-4, 24) * sc, c + Vector2(-34, 44) * sc])
	draw_colored_polygon(tail, bg)
	draw_polyline(PackedVector2Array([tail[0], tail[2], tail[1]]), INK, 3.0, true)
	draw_circle(c, r, bg)
	draw_arc(c, r, 0, TAU, 40, INK, 3.0, true)
	var k := sc
	match str(e[0]):
		"note":
			draw_circle(c + Vector2(-6, 8) * k, 6 * k, INK)
			draw_line(c + Vector2(0, 8) * k, c + Vector2(0, -12) * k, INK, 3, true)
			draw_line(c + Vector2(0, -12) * k, c + Vector2(10, -6) * k, INK, 3, true)
		"haha":
			_emote_text(c, "HA!", int(20 * k), Color("#c0392b"))
		"drop", "drops":
			var n := 1 if e[0] == "drop" else 2
			for i in n:
				var p := c + Vector2((i - (n - 1) * 0.5) * 14, 0) * k
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -14) * k, p + Vector2(7, 2) * k, p + Vector2(0, 9) * k, p + Vector2(-7, 2) * k]), Color("#3b82d6"))
		"vein":
			var vc := Color("#d62828")
			for q in 4:
				var a := q * PI / 2.0 + PI / 4.0
				var p := c + Vector2(cos(a), sin(a)) * 9 * k
				draw_arc(p, 7 * k, a + PI * 0.6, a + PI * 1.4, 10, vc, 4.0, true)
		"q":
			_emote_text(c, "?", int(30 * k), INK)
		"ex":
			_emote_text(c, "!", int(32 * k), Color("#d62828"))
		"exx":
			_emote_text(c, "!!", int(30 * k), Color("#d62828"))
		"sweat":
			var p2 := c + Vector2(4, -2) * k
			draw_colored_polygon(PackedVector2Array([p2 + Vector2(0, -14) * k, p2 + Vector2(8, 4) * k, p2 + Vector2(0, 11) * k, p2 + Vector2(-8, 4) * k]), Color("#5aa9e6"))
			for i in 3:
				draw_line(c + Vector2(-16, -8 + i * 8) * k, c + Vector2(-9, -6 + i * 8) * k, INK, 2, true)
		"hm":
			_emote_text(c, "hm.", int(18 * k), INK)
		"dark":
			for i in 3:
				var a2 := -0.6 + i * 0.6
				draw_line(c + Vector2(cos(a2), sin(a2) - 0.2) * 4 * k, c + Vector2(cos(a2), sin(a2) - 0.2) * 18 * k, Color("#e03a3a"), 3, true)
		"heart":
			var hp := PackedVector2Array()
			for i in 30:
				var a3 := TAU * i / 30.0
				hp.append(c + Vector2(16 * pow(sin(a3), 3), -(13 * cos(a3) - 5 * cos(2 * a3) - 2 * cos(3 * a3) - cos(4 * a3))) * 0.95 * k)
			draw_colored_polygon(hp, Color("#e63950"))
		"blush":
			for i in 4:
				draw_line(c + Vector2(-14 + i * 8, 6) * k, c + Vector2(-8 + i * 8, -6) * k, Color("#e8607a"), 3, true)
		"dots":
			for i in 3:
				draw_circle(c + Vector2(-10 + i * 10, 2) * k, 3.2 * k, INK)
		"zz":
			_emote_text(c, "Zz", int(20 * k), Color("#4a5a8a"))
		"pain":
			var star := PackedVector2Array()
			for i in 16:
				var a4 := TAU * i / 16.0
				star.append(c + Vector2(cos(a4), sin(a4)) * (16.0 if i % 2 == 0 else 7.0) * k)
			draw_colored_polygon(star, Color("#f4b400"))


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
	var nx := 70.0 * float(_l("face_w", 1.0)) * HS * 0.42 * nk
	var torso := PackedVector2Array([Vector2(-20, 400), Vector2(-14, 330), Vector2(20, 292), Vector2(90, 268), Vector2(150 - nx, 258), Vector2(150 + nx, 258), Vector2(210, 268), Vector2(280, 292), Vector2(314, 330), Vector2(320, 400)])
	var right_mask := PackedVector2Array([Vector2(178, 250), Vector2(190, 300), Vector2(172, 400), Vector2(330, 400), Vector2(330, 250)])
	var neck := PackedVector2Array([Vector2(150 - nx, 200), Vector2(150 + nx, 200), Vector2(150 + nx * 1.12, 272), Vector2(150 - nx * 1.12, 272)])
	_poly(neck, skin)
	_shade(neck, PackedVector2Array([Vector2(150 + nx * 0.2, 190), Vector2(400, 190), Vector2(400, 300), Vector2(150 + nx * 0.4, 300)]), _shadow_of(skin))
	_poly(PackedVector2Array([Vector2(150 - nx, 214), Vector2(150 + nx, 214), Vector2(150 + nx, 236), Vector2(150, 244), Vector2(150 - nx, 230)]), _shadow_of(skin))
	_line(PackedVector2Array([neck[0], neck[3]]), INK, 3.0)
	_line(PackedVector2Array([neck[1], neck[2]]), INK, 3.0)
	_line(PackedVector2Array([Vector2(150 - nx * 0.5, 246), Vector2(150 - nx * 0.3, 268)]), Color(INK, 0.4), 1.4)
	if _l("adams_apple", false):
		_line(_quad(Vector2(146, 250), Vector2(151, 245), Vector2(155, 251), 6), Color(INK, 0.55), 1.6)
		_poly(_ellipse(Vector2(150, 254), 5, 4, 10), Color(_shadow_of(skin), 0.6))
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



# Implementados em face_rig.gd
func _draw_back_hair() -> void:
	pass


func _draw_head() -> void:
	pass
