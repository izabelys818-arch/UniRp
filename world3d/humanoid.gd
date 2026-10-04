extends Node3D

# Personagem 3D montado por código (sem modelos prontos): quadril, tronco, braços e pernas
# articulados, cabeça com rosto, cabelo e barba. Contorno de tinta igual ao dos retratos.

const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform float grow = 0.018;
uniform vec4 ink : source_color = vec4(0.07, 0.05, 0.05, 1.0);
void vertex() { VERTEX += NORMAL * grow; }
void fragment() { ALBEDO = ink.rgb; }
"""

const EMOTE_TEXT := {
	"feliz": ["♪", Color("#ffe08a")], "rindo": ["haha", Color("#ffe08a")], "triste": ["...", Color("#a9c8ff")],
	"chorando": ["T_T", Color("#a9c8ff")], "irritado": ["#", Color("#ff8a7a")], "furioso": ["!!", Color("#ff5a4a")],
	"desconfiado": ["?", Color("#f1ece0")], "assustado": ["!", Color("#ffffff")], "nervoso": ["~", Color("#bfe3ff")],
	"sarcastico": ["hm", Color("#f1ece0")], "ameacador": ["...", Color("#ff5a4a")], "carinhoso": ["♥", Color("#ff8fb3")],
	"surpreso": ["!?", Color("#fff1b0")], "envergonhado": ["//", Color("#ffb3c8")], "entediado": ["zz", Color("#d0d0d0")],
	"exausto": ["zZ", Color("#c8d0e0")], "machucado": ["ai", Color("#ffd28a")],
}

static var _mats: Dictionary = {}
static var _outline_shader: Shader
static var _shapes: Dictionary = {}

var look: Dictionary = {}
var walking: bool = false
var running: bool = false
var highlight: float = 0.0
var t: float = 0.0
var phase: float = 0.0
var talk_left: float = 0.0
var emotion: String = "neutro"
var lying: bool = false

var hips: Node3D
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var fore_l: Node3D
var fore_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var bubble: Label3D
var _outlines: Array = []


static func mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if _outline_shader == null:
		_outline_shader = Shader.new()
		_outline_shader.code = OUTLINE_SHADER
	var o := ShaderMaterial.new()
	o.shader = _outline_shader
	m.next_pass = o
	_mats[key] = m
	return m


static func _shape(kind: String) -> Mesh:
	if _shapes.has(kind):
		return _shapes[kind]
	var m: Mesh
	match kind:
		"box":
			m = BoxMesh.new()
		"sphere":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			s.radial_segments = 14
			s.rings = 8
			m = s
		"capsule":
			var c := CapsuleMesh.new()
			c.radius = 0.5
			c.height = 2.0
			c.radial_segments = 10
			c.rings = 3
			m = c
		"cyl":
			var c := CylinderMesh.new()
			c.top_radius = 0.5
			c.bottom_radius = 0.5
			c.height = 1.0
			c.radial_segments = 10
			m = c
	_shapes[kind] = m
	return m


func _part(parent: Node3D, kind: String, pos: Vector3, scale: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _shape(kind)
	mi.material_override = mat(color)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func set_look(l: Dictionary) -> void:
	look = l
	for c in get_children():
		c.queue_free()
	_build()


func _pants_color(style: String, c1: Color, c2: Color) -> Color:
	match style:
		"jeans": return Color("#2f4768")
		"social", "terno", "farda": return c1.darkened(0.1)
		"couro", "sobretudo", "batina": return Color("#1b1b1f")
		"academia": return Color("#26262c")
		"havaiana": return Color("#d9c9a2")
		"macacao": return c1
		"uniforme", "jaleco", "avental": return Color("#2b2f38")
		"rasgada": return Color("#4d493f")
		"time": return Color("#222831")
	var p := c2.darkened(0.55) if c2.get_luminance() > 0.5 else c2.lightened(0.15)
	if p.get_luminance() > 0.45:
		p = Color("#3a4a63")
	return p


func _build() -> void:
	var female: bool = str(look.get("gender", "")) == "mulher"
	var age: int = int(look.get("age", 30))
	var skin: Color = look.get("skin", Color("#e8bf9c"))
	var c1: Color = look.get("clothes_color", Color("#4a5260"))
	var c2: Color = look.get("clothes_color2", Color("#dddddd"))
	var style: String = str(look.get("clothes", "camiseta"))
	var hair_c: Color = look.get("hair_color", Color("#2b1d14"))
	if age >= 62:
		hair_c = hair_c.lerp(Color("#d8d6d0"), 0.8)
	var wide: float = clampf(float(look.get("face_w", 1.0)), 0.88, 1.22)
	var sh: float = float(look.get("shoulders", 1.0)) * (0.86 if female else 1.0)
	var k: float = 0.88 if female else 0.94
	if age < 16:
		k *= 0.82
	scale = Vector3(k, k, k)
	var pants := _pants_color(style, c1, c2)
	var shoe := Color("#1d1b1a")
	if style in ["academia", "time"]:
		shoe = Color("#e9e6e0")
	elif style == "havaiana":
		shoe = Color("#c9712c")
	var long_sleeve: bool = style in ["moletom", "couro", "social", "terno", "sobretudo", "farda", "jaleco", "batina"]
	var sleeveless: bool = style in ["regata", "vestido"]
	var top_c: Color = c1
	var jacket: bool = style in ["couro", "sobretudo", "jaleco", "terno", "jeans"]
	var jacket_c: Color = c2 if style == "jaleco" else c1
	if style == "jaleco":
		top_c = c1

	hips = _pivot(self, Vector3(0, 0.95, 0))
	# pernas
	for side in [-1, 1]:
		var leg := _pivot(hips, Vector3(0.1 * side * wide, 0, 0))
		_part(leg, "capsule", Vector3(0, -0.22, 0), Vector3(0.16 * wide, 0.23, 0.16 * wide), pants if style != "vestido" else skin)
		var shin := _pivot(leg, Vector3(0, -0.44, 0))
		_part(shin, "capsule", Vector3(0, -0.21, 0), Vector3(0.12, 0.22, 0.12), pants if style != "vestido" else skin)
		_part(shin, "box", Vector3(0, -0.45, 0.05), Vector3(0.13, 0.08, 0.27), shoe)
		if side < 0:
			leg_l = leg
			shin_l = shin
		else:
			leg_r = leg
			shin_r = shin
	_part(hips, "box", Vector3(0, 0.02, 0), Vector3(0.36 * wide * (1.08 if female else 1.0), 0.18, 0.22), pants)
	if style != "vestido" and style != "macacao":
		_part(hips, "box", Vector3(0, 0.1, 0), Vector3(0.37 * wide, 0.05, 0.23), Color("#2a1d14"))
	# tronco
	torso = _pivot(hips, Vector3(0, 0.1, 0))
	var waist_w: float = (0.3 if female else 0.34) * wide
	_part(torso, "box", Vector3(0, 0.14, 0), Vector3(waist_w, 0.26, 0.21), top_c if not sleeveless or style == "vestido" else c1)
	_part(torso, "box", Vector3(0, 0.38, 0), Vector3(0.42 * sh * wide, 0.26, 0.24), top_c)
	_part(torso, "sphere", Vector3(0, 0.5, 0), Vector3(0.46 * sh * wide, 0.12, 0.25), top_c)
	if female:
		_part(torso, "sphere", Vector3(0, 0.36, 0.08), Vector3(0.3, 0.13, 0.12), top_c)
	if style == "vestido":
		_part(hips, "cyl", Vector3(0, -0.2, 0), Vector3(0.48, 0.45, 0.34), c1)
	if jacket:
		_part(torso, "box", Vector3(-0.11 * sh, 0.27, 0.115), Vector3(0.14, 0.5, 0.02), jacket_c.darkened(0.08))
		_part(torso, "box", Vector3(0.11 * sh, 0.27, 0.115), Vector3(0.14, 0.5, 0.02), jacket_c.darkened(0.08))
		_part(torso, "box", Vector3(0, 0.3, 0.112), Vector3(0.09, 0.42, 0.02), c2 if style != "jaleco" else c1)
	if style == "terno":
		_part(torso, "box", Vector3(0, 0.3, 0.125), Vector3(0.04, 0.32, 0.02), Color("#7a1b26"))
	if style == "time":
		_part(torso, "box", Vector3(0, 0.3, 0.121), Vector3(0.43 * sh, 0.06, 0.01), c2)
	if style in ["avental", "macacao"]:
		_part(torso, "box", Vector3(0, 0.15, 0.115), Vector3(0.3, 0.42, 0.02), c2 if style == "avental" else c1.darkened(0.15))
	if style == "farda":
		_part(torso, "box", Vector3(0.1, 0.42, 0.125), Vector3(0.05, 0.06, 0.01), Color("#d4a72c"))
	if style == "moletom":
		_part(torso, "sphere", Vector3(0, 0.52, -0.1), Vector3(0.3, 0.14, 0.16), c1.darkened(0.15))
	# braços
	for side in [-1, 1]:
		var arm := _pivot(torso, Vector3(0.24 * side * sh * wide, 0.47, 0))
		var upper_c: Color = skin if sleeveless else (jacket_c if jacket else top_c)
		_part(arm, "capsule", Vector3(0, -0.15, 0), Vector3(0.1 * wide, 0.15, 0.1 * wide), upper_c)
		var fore := _pivot(arm, Vector3(0, -0.29, 0))
		_part(fore, "capsule", Vector3(0, -0.13, 0), Vector3(0.085, 0.14, 0.085), (jacket_c if jacket else top_c) if long_sleeve else skin)
		_part(fore, "sphere", Vector3(0, -0.3, 0.01), Vector3(0.09, 0.11, 0.07), skin)
		if side < 0:
			arm_l = arm
			fore_l = fore
		else:
			arm_r = arm
			fore_r = fore
	# pescoço e cabeça
	_part(torso, "cyl", Vector3(0, 0.6, 0), Vector3(0.1 * float(look.get("neck", 1.0)), 0.12, 0.1), skin)
	head = _pivot(torso, Vector3(0, 0.76, 0))
	var hw: float = 0.21 * clampf(float(look.get("face_w", 1.0)), 0.9, 1.15)
	var hl: float = 0.26 * clampf(float(look.get("face_len", 1.0)), 0.9, 1.12)
	_part(head, "sphere", Vector3.ZERO, Vector3(hw, hl, 0.24), skin)
	_part(head, "sphere", Vector3(0, -0.08, 0.02), Vector3(hw * 0.85 * clampf(float(look.get("jaw", 0.8)) + 0.2, 0.8, 1.2), hl * 0.5, 0.2), skin)
	for side in [-1, 1]:
		_part(head, "sphere", Vector3(side * hw * 0.5, 0, 0), Vector3(0.05, 0.08, 0.05), skin.darkened(0.05))
	var eye_c: Color = look.get("eye_color", Color("#3a2a20"))
	for side in [-1, 1]:
		_part(head, "sphere", Vector3(side * 0.05, 0.02, 0.112), Vector3(0.045, 0.03, 0.02), Color("#f2eee6"))
		_part(head, "sphere", Vector3(side * 0.05, 0.02, 0.12), Vector3(0.024, 0.026, 0.012), eye_c.darkened(0.4))
		_part(head, "box", Vector3(side * 0.055, 0.065, 0.115), Vector3(0.06, 0.014 if female else 0.02, 0.012), hair_c.darkened(0.2), Vector3(0, 0, side * (-0.12 if female else 0.08)))
	_part(head, "box", Vector3(0, -0.015, 0.125), Vector3(0.03, 0.06, 0.04), skin.darkened(0.08), Vector3(-0.3, 0, 0))
	var lip: Color = look.get("lip_color", skin.darkened(0.25))
	_part(head, "box", Vector3(0, -0.075, 0.112), Vector3(0.06, 0.012, 0.01), lip.darkened(0.15))
	var beard: String = str(look.get("beard", "none"))
	if beard != "none" and not female:
		var bc: Color = hair_c.darkened(0.1) if beard != "stubble" else skin.darkened(0.3)
		match beard:
			"mustache":
				_part(head, "box", Vector3(0, -0.05, 0.115), Vector3(0.08, 0.02, 0.02), bc)
			"goatee":
				_part(head, "sphere", Vector3(0, -0.12, 0.08), Vector3(0.07, 0.07, 0.06), bc)
			_:
				var bl: float = 0.16 if beard == "long" else 0.11
				_part(head, "sphere", Vector3(0, -0.1 - (0.03 if beard == "long" else 0.0), 0.05), Vector3(hw * 0.95, bl, 0.18), bc)
				_part(head, "box", Vector3(0, -0.075, 0.118), Vector3(0.06, 0.012, 0.01), lip.darkened(0.15))
	_hair(str(look.get("hair", "curto")), hair_c, hw, hl, female)
	for ex in look.get("extras", []):
		var e := str(ex)
		if "culos" in e:
			for side in [-1, 1]:
				_part(head, "box", Vector3(side * 0.05, 0.02, 0.13), Vector3(0.055, 0.04, 0.01), Color(0.1, 0.1, 0.1))
			_part(head, "box", Vector3(0, 0.03, 0.13), Vector3(0.04, 0.01, 0.01), Color(0.1, 0.1, 0.1))
		if "bon" in e:
			_part(head, "sphere", Vector3(0, 0.08, -0.01), Vector3(hw * 1.08, hl * 0.6, 0.255), c1.darkened(0.2))
			_part(head, "box", Vector3(0, 0.07, 0.15), Vector3(0.18, 0.015, 0.12), c1.darkened(0.3))
	bubble = Label3D.new()
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.font_size = 64
	bubble.pixel_size = 0.006
	bubble.outline_size = 16
	bubble.outline_modulate = Color(0.07, 0.05, 0.05)
	bubble.position = Vector3(0, 2.15, 0)
	bubble.visible = false
	add_child(bubble)
	set_emotion(emotion)


func _hair(style: String, c: Color, hw: float, hl: float, female: bool) -> void:
	if style == "careca":
		return
	var cap := Vector3(hw * 1.07, hl * 0.66, 0.255)
	match style:
		"raspado":
			_part(head, "sphere", Vector3(0, 0.035, -0.005), Vector3(hw * 1.03, hl * 0.62, 0.247), c.lerp(Color(look.get("skin", Color.WHITE)), 0.45))
		"moicano":
			_part(head, "sphere", Vector3(0, 0.035, -0.005), Vector3(hw * 1.03, hl * 0.62, 0.247), c.lerp(Color(look.get("skin", Color.WHITE)), 0.6))
			_part(head, "box", Vector3(0, 0.14, -0.02), Vector3(0.05, 0.1, 0.24), c)
		"black_power", "cacheado":
			var big: float = 1.55 if style == "black_power" else 1.25
			_part(head, "sphere", Vector3(0, 0.07, -0.03), Vector3(hw * big * 1.1, hl * big * 0.85, 0.24 * big), c)
		_:
			_part(head, "sphere", Vector3(0, 0.055, -0.012), cap, c)
			if style in ["franja", "desgrenhado"]:
				_part(head, "box", Vector3(0, 0.07, 0.1), Vector3(hw * 0.9, 0.05, 0.05), c, Vector3(0.3, 0, 0))
			if style in ["medio", "longo", "trancas", "dreads"]:
				var drop: float = 0.42 if style in ["longo", "trancas", "dreads"] else 0.2
				_part(head, "box", Vector3(0, -drop / 2.0 + 0.04, -0.07), Vector3(hw * 1.05, drop, 0.13), c)
				if style == "longo" and female:
					for side in [-1, 1]:
						_part(head, "box", Vector3(side * hw * 0.48, -0.08, 0.02), Vector3(0.05, 0.3, 0.12), c)
			if style in ["trancas", "dreads"]:
				for i in 5:
					_part(head, "cyl", Vector3(-0.08 + i * 0.04, -0.28, -0.11), Vector3(0.03, 0.3, 0.03), c.darkened(0.1))
			if style == "coque":
				_part(head, "sphere", Vector3(0, 0.15, -0.12), Vector3(0.12, 0.11, 0.12), c)
			if style == "rabo":
				_part(head, "cyl", Vector3(0, -0.05, -0.17), Vector3(0.06, 0.32, 0.06), c, Vector3(0.35, 0, 0))


func set_emotion(e: String) -> void:
	emotion = e
	if bubble == null:
		return
	if EMOTE_TEXT.has(e):
		bubble.text = str(EMOTE_TEXT[e][0])
		bubble.modulate = EMOTE_TEXT[e][1]
		bubble.visible = true
	else:
		bubble.visible = false


func set_highlight(on: bool) -> void:
	highlight = 1.0 if on else 0.0


func _process(delta: float) -> void:
	if hips == null:
		return
	t += delta
	talk_left = maxf(0.0, talk_left - delta)
	if lying:
		rotation.x = lerp_angle(rotation.x, -PI / 2.0, minf(delta * 4.0, 1.0))
		return
	var amp: float = 0.75 if running else 0.5
	if walking:
		phase += delta * (11.0 if running else 7.5)
	else:
		phase = lerpf(phase, roundf(phase / PI) * PI, minf(delta * 8.0, 1.0))
	var s := sin(phase)
	var move_k: float = 1.0 if walking else 0.0
	leg_l.rotation.x = s * amp * move_k
	leg_r.rotation.x = -s * amp * move_k
	shin_l.rotation.x = -maxf(0.0, -s) * amp * 1.3 * move_k - (0.0 if walking else 0.02)
	shin_r.rotation.x = -maxf(0.0, s) * amp * 1.3 * move_k
	arm_l.rotation.x = -s * amp * 0.8 * move_k
	arm_r.rotation.x = s * amp * 0.8 * move_k
	fore_l.rotation.x = -0.25 - (0.35 if running else 0.0) * move_k
	fore_r.rotation.x = -0.25 - (0.35 if running else 0.0) * move_k
	arm_l.rotation.z = -0.08
	arm_r.rotation.z = 0.08
	var breath := sin(t * 1.7) * 0.012
	hips.position.y = 0.95 + (absf(s) * 0.04 * move_k) + (0.0 if walking else breath * 0.3)
	torso.rotation.x = (0.12 if running else 0.03) * move_k
	torso.scale = Vector3(1.0 + breath * 0.5, 1.0, 1.0 + breath)
	head.rotation.y = 0.0 if walking else sin(t * 0.4 + position.x) * 0.25
	if talk_left > 0.0:
		head.rotation.x = sin(t * 9.0) * 0.06
		arm_r.rotation.x = -0.35 + sin(t * 3.0) * 0.2
		fore_r.rotation.x = -0.9
	else:
		head.rotation.x = lerpf(head.rotation.x, 0.0, minf(delta * 5.0, 1.0))
	if bubble and bubble.visible:
		bubble.position.y = 2.15 + sin(t * 2.4) * 0.04
