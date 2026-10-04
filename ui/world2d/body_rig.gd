extends Control

# Personagem de corpo inteiro desenhado por código (traço de tinta, sem imagens).
# A origem do desenho fica nos pés; a altura total é de 180 unidades.

const INK := Color("#14110f")

var look: Dictionary = {}
var walking: bool = false
var facing: float = 1.0
var highlight: float = 0.0
var phase: float = 0.0
var t: float = 0.0
var seed_n: float = 0.0


func set_look(l: Dictionary) -> void:
	look = l
	queue_redraw()


func _process(delta: float) -> void:
	t += delta
	if walking:
		phase += delta * 8.0
	else:
		phase = lerpf(phase, roundf(phase / PI) * PI, minf(delta * 8.0, 1.0))
	queue_redraw()


func _poly(pts: PackedVector2Array, c: Color, outline: bool = true) -> void:
	if Geometry2D.triangulate_polygon(pts).is_empty():
		return
	draw_colored_polygon(pts, c)
	if outline:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, INK, 2.0, true)


func _limb(a: Vector2, b: Vector2, w: float, c: Color) -> void:
	draw_line(a, b, INK, w + 4.0, true)
	draw_line(a, b, c, w, true)


# Cadeia de dois segmentos (coxa+canela, braço+antebraço) com contorno só por fora.
func _chain(a: Vector2, b: Vector2, c: Vector2, w1: float, w2: float, col1: Color, col2: Color) -> void:
	draw_line(a, b, INK, w1 + 4.0, true)
	draw_line(b, c, INK, w2 + 4.0, true)
	draw_circle(a, w1 / 2.0 + 2.0, INK)
	draw_circle(b, maxf(w1, w2) / 2.0 + 2.0, INK)
	draw_circle(c, w2 / 2.0 + 2.0, INK)
	draw_line(a, b, col1, w1, true)
	draw_circle(a, w1 / 2.0, col1)
	draw_line(b, c, col2, w2, true)
	draw_circle(b, w2 / 2.0, col2 if col1 == col2 else col1)
	draw_circle(c, w2 / 2.0, col2)

func _draw() -> void:
	if look.is_empty():
		return
	var s := size.y / 180.0
	draw_set_transform(Vector2(size.x / 2.0, size.y), 0.0, Vector2(s * facing, s))
	var female: bool = str(look.get("gender", "")) == "mulher"
	var skin: Color = look.get("skin", Color("#e8bf9c"))
	var cloth: Color = look.get("clothes_color", Color("#4a5260"))
	var cloth2: Color = look.get("clothes_color2", Color("#dddddd"))
	var style: String = str(look.get("clothes", "camiseta"))
	var shoulders: float = float(look.get("shoulders", 1.0))
	var age: int = int(look.get("age", 30))
	var sway := sin(phase)
	var bob := (absf(sin(phase)) * 2.5) if walking else sin(t * 1.6 + seed_n) * 0.9
	var skirt := style in ["vestido"]
	var pants: Color = cloth2.darkened(0.25) if style in ["camiseta", "moletom", "regata", "blusa", "time", "academia"] else cloth.darkened(0.15)
	if style in ["social", "terno", "sobretudo", "farda"]:
		pants = cloth.darkened(0.1)
	if style in ["jeans"]:
		pants = Color("#2d4263")
	if style == "havaiana":
		pants = Color("#d8c9a3")

	# sombra
	draw_set_transform(Vector2(size.x / 2.0, size.y), 0.0, Vector2(s * facing * 1.0, s * 0.18))
	draw_circle(Vector2(0, 0), 30.0, Color(0, 0, 0, 0.35))
	draw_circle(Vector2(0, 0), 22.0, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2(size.x / 2.0, size.y), 0.0, Vector2(s * facing, s))

	var hip_y := -86.0 + bob * 0.4
	var hip_w := 9.0 if not female else 10.5
	# pernas (a de trás primeiro)
	for side in [-1, 1]:
		var swing: float = sway * 16.0 * side if walking else 0.0
		var lift: float = maxf(0.0, -sin(phase) * side) * 6.0 if walking else 0.0
		var hip := Vector2(side * hip_w * 0.5, hip_y)
		var knee := Vector2(hip.x + swing * 0.5, -46.0 - lift * 0.5)
		var foot := Vector2(hip.x + swing, -3.0 - lift)
		var leg_col := pants if not skirt else skin
		if skirt and side == 1:
			leg_col = skin
		_chain(hip, knee, foot, 12.0, 9.5, leg_col, leg_col)
		_poly(PackedVector2Array([foot + Vector2(-5, -2), foot + Vector2(10, -2), foot + Vector2(11, 3), foot + Vector2(-5, 3)]), Color("#23201e"))

	# braço de trás
	var sh_y := -150.0 + bob
	var sw := (17.0 if not female else 14.5) * shoulders
	var back_swing := -sway * 14.0 if walking else 0.0
	var sleeve := cloth if style not in ["regata", "vestido", "academia"] else skin
	_chain(Vector2(-sw * 0.8, sh_y + 4), Vector2(-sw * 0.9 + back_swing * 0.5, sh_y + 28), Vector2(-sw * 0.9 + back_swing, sh_y + 52), 9.0, 7.5, sleeve.darkened(0.15), skin.darkened(0.1))

	# tronco
	var waist := 11.0 if not female else 9.5
	var torso := PackedVector2Array([Vector2(-sw, sh_y), Vector2(sw, sh_y), Vector2(waist + 2, hip_y), Vector2(-waist - 2, hip_y)])
	if skirt:
		torso = PackedVector2Array([Vector2(-sw, sh_y), Vector2(sw, sh_y), Vector2(waist, hip_y - 10), Vector2(waist + 13, -48), Vector2(-waist - 13, -48), Vector2(-waist, hip_y - 10)])
	_poly(torso, cloth)
	match style:
		"social", "terno", "sobretudo", "farda":
			draw_line(Vector2(0, sh_y), Vector2(0, hip_y), INK, 2.0)
			_poly(PackedVector2Array([Vector2(-4, sh_y), Vector2(4, sh_y), Vector2(0, sh_y + 20)]), cloth2)
		"avental", "uniforme", "jaleco":
			_poly(PackedVector2Array([Vector2(-waist, sh_y + 8), Vector2(waist, sh_y + 8), Vector2(waist, hip_y), Vector2(-waist, hip_y)]), cloth2)
		"couro":
			draw_line(Vector2(-3, sh_y), Vector2(3, hip_y), cloth2, 3.0)
		"time":
			draw_line(Vector2(-sw, sh_y + 14), Vector2(sw, sh_y + 14), cloth2, 5.0)
	# pescoço
	var neck_w := 5.0 * float(look.get("neck", 1.0))
	_poly(PackedVector2Array([Vector2(-neck_w, sh_y - 8), Vector2(neck_w, sh_y - 8), Vector2(neck_w, sh_y + 2), Vector2(-neck_w, sh_y + 2)]), skin.darkened(0.08))

	# cabeça
	var head_c := Vector2(0, sh_y - 25.0 + bob * 0.3)
	var fw := 15.0 * float(look.get("face_w", 1.0)) * (0.95 if female else 1.0)
	var fl := 19.5 * float(look.get("face_len", 1.0))
	var hair: Color = look.get("hair_color", Color("#2b1d14"))
	if age >= 60:
		hair = hair.lerp(Color("#d8d6d0"), 0.85)
	var style_h: String = str(look.get("hair", "curto"))
	var long_h := style_h in ["longo", "cacheado", "black_power", "trancas", "dreads", "medio"]
	# cabelo de trás
	if long_h:
		var drop := 34.0 if style_h in ["longo", "trancas", "dreads"] else (14.0 if style_h == "medio" else 8.0)
		if style_h == "black_power":
			draw_circle(head_c + Vector2(-2, -4), fw + 10.0, INK)
			draw_circle(head_c + Vector2(-2, -4), fw + 8.0, hair)
		else:
			_poly(PackedVector2Array([head_c + Vector2(-fw - 3, -fl * 0.4), head_c + Vector2(fw + 3, -fl * 0.4), head_c + Vector2(fw + 5, drop), head_c + Vector2(-fw - 5, drop)]), hair)
	if style_h == "rabo":
		_limb(head_c + Vector2(-fw + 2, -fl * 0.4), head_c + Vector2(-fw - 12, fl * 0.5), 7.0, hair)
	_poly(PackedVector2Array([head_c + Vector2(-fw, -fl * 0.5), head_c + Vector2(fw, -fl * 0.5), head_c + Vector2(fw * 0.95, fl * 0.2), head_c + Vector2(fw * 0.5, fl * 0.85), head_c + Vector2(0, fl), head_c + Vector2(-fw * 0.5, fl * 0.85), head_c + Vector2(-fw * 0.95, fl * 0.2)]), skin)
	# orelha
	draw_circle(head_c + Vector2(-fw + 1, 2), 3.0, skin.darkened(0.08))
	# barba
	var beard: String = str(look.get("beard", "none"))
	if beard != "none" and not female:
		var bc := hair.darkened(0.1) if beard != "stubble" else skin.darkened(0.28)
		var top := fl * (0.35 if beard != "stubble" else 0.45)
		var bot := fl * (1.0 if beard in ["full", "goatee"] else 0.85) + (10.0 if beard == "long" else 0.0)
		_poly(PackedVector2Array([head_c + Vector2(-fw * 0.95, top), head_c + Vector2(fw * 0.95, top), head_c + Vector2(fw * 0.5, bot), head_c + Vector2(0, bot + 1), head_c + Vector2(-fw * 0.5, bot)]), bc, beard != "stubble")
	# olhos (levemente à frente, para onde olha)
	var eye_col: Color = look.get("eye_color", Color("#3a2a20"))
	for ex in [3.0, 9.0]:
		var p := head_c + Vector2(ex * 0.9 + 1.0, -fl * 0.05)
		draw_circle(p, 2.6, Color("#f4efe8"))
		draw_circle(p + Vector2(0.8, 0), 1.5, eye_col.darkened(0.3))
		draw_line(p + Vector2(-3.2, -3.4), p + Vector2(3.0, -3.8), INK, 1.6, true)
	draw_line(head_c + Vector2(10.5, 3), head_c + Vector2(12.5, 6.5), skin.darkened(0.3), 1.6, true)
	var lip: Color = look.get("lip_color", skin.darkened(0.2))
	draw_line(head_c + Vector2(4.5, fl * 0.5), head_c + Vector2(10.0, fl * 0.5), lip.darkened(0.15), 1.8, true)
	if look.get("lashes", false):
		draw_line(head_c + Vector2(8.6, -fl * 0.05 - 2.4), head_c + Vector2(12.6, -fl * 0.05 - 4.2), INK, 1.4, true)
	# cabelo da frente
	match style_h:
		"careca":
			pass
		"raspado":
			_poly(PackedVector2Array([head_c + Vector2(-fw, -fl * 0.35), head_c + Vector2(fw, -fl * 0.35), head_c + Vector2(fw, -fl * 0.62), head_c + Vector2(0, -fl * 0.75), head_c + Vector2(-fw, -fl * 0.62)]), hair.lerp(skin, 0.55), false)
		"moicano":
			_poly(PackedVector2Array([head_c + Vector2(-4, -fl * 0.5), head_c + Vector2(5, -fl * 0.5), head_c + Vector2(3, -fl - 10), head_c + Vector2(-3, -fl - 10)]), hair)
		"coque":
			draw_circle(head_c + Vector2(-3, -fl - 6), 7.0, INK)
			draw_circle(head_c + Vector2(-3, -fl - 6), 5.5, hair)
			_poly(PackedVector2Array([head_c + Vector2(-fw - 1, -fl * 0.25), head_c + Vector2(fw + 1, -fl * 0.25), head_c + Vector2(fw, -fl * 0.78), head_c + Vector2(0, -fl - 2), head_c + Vector2(-fw, -fl * 0.78)]), hair)
		"black_power":
			pass
		_:
			var low := -fl * (0.15 if style_h in ["franja", "desgrenhado"] else 0.35)
			_poly(PackedVector2Array([head_c + Vector2(-fw - 1, -fl * 0.2), head_c + Vector2(-fw - 1, -fl * 0.8), head_c + Vector2(0, -fl - 3), head_c + Vector2(fw + 1, -fl * 0.8), head_c + Vector2(fw + 1, low), head_c + Vector2(fw * 0.3, -fl * 0.55), head_c + Vector2(-fw * 0.4, -fl * 0.5)]), hair)
	if style_h == "black_power":
		_poly(PackedVector2Array([head_c + Vector2(-fw, -fl * 0.35), head_c + Vector2(fw, -fl * 0.35), head_c + Vector2(fw * 0.7, -fl * 0.8), head_c + Vector2(-fw * 0.7, -fl * 0.8)]), hair)
	for ex in look.get("extras", []):
		if str(ex) in ["oculos", "óculos"]:
			draw_circle(head_c + Vector2(6.5, -fl * 0.05), 5.0, Color(1, 1, 1, 0.12))
			draw_arc(head_c + Vector2(6.5, -fl * 0.05), 5.0, 0.0, TAU, 20, INK, 1.4, true)

	# braço da frente
	var fr_swing := sway * 14.0 if walking else 0.0
	_chain(Vector2(sw * 0.8, sh_y + 4), Vector2(sw * 0.9 + fr_swing * 0.5, sh_y + 28), Vector2(sw * 0.9 + fr_swing, sh_y + 52), 9.5, 8.0, sleeve, skin)

	if highlight > 0.01:
		draw_arc(Vector2(0, -90), 98.0, 0.0, TAU, 48, Color(1.0, 0.86, 0.45, 0.28 * highlight), 3.0, true)
