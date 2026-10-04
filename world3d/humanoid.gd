extends Node3D

# Personagem 3D montado por código (sem modelos prontos). Esqueleto completo: quadril, cintura,
# tronco, pescoço, cabeça com rosto articulado (sobrancelhas, pálpebras, olhos, boca, mandíbula),
# braços com cotovelo, punho e dedos, pernas com joelho, tornozelo e pé.
# Visual de desenho: sombra em degraus, luz de contorno e traço de tinta (casco invertido).
# Animação procedural: marcha e corrida pela velocidade real, respiração, olhar, piscar,
# expressões, gestos ao falar e posturas de espera.

const FaceBase = preload("res://ui/face/face_base.gd")

const TOON_SHADER := """
shader_type spatial;
uniform vec4 albedo : source_color = vec4(0.7, 0.7, 0.7, 1.0);
uniform float shine = 0.0;
void fragment() {
	ALBEDO = albedo.rgb;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	EMISSION = albedo.rgb * 0.30 + vec3(0.18, 0.17, 0.2) * rim;
}
void light() {
	float nl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float band = smoothstep(0.02, 0.10, nl) * 0.55 + smoothstep(0.52, 0.60, nl) * 0.45;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * band * 0.9;
	float h = clamp(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0, 1.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * smoothstep(0.92, 0.94, h) * shine;
}
"""

const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform float grow = 0.011;
uniform vec4 ink : source_color = vec4(0.07, 0.05, 0.05, 1.0);
void vertex() {
	vec3 vp = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 vn = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vp += vn * grow;
	POSITION = PROJECTION_MATRIX * vec4(vp, 1.0);
}
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
static var _toon: Shader
static var _outline: ShaderMaterial
static var _meshes: Dictionary = {}
static var _shadow_mat: StandardMaterial3D

var look: Dictionary = {}
var walking: bool = false
var running: bool = false
var move_speed: float = 0.0
var highlight: float = 0.0
var t: float = 0.0
var phase: float = 0.0
var talk_left: float = 0.0
var emotion: String = "neutro"
var lying: bool = false
var gait: float = 0.0
var seed_n: float = 0.0
var look_target: Vector3 = Vector3.INF
var base_y: float = 0.93

var hips: Node3D
var torso: Node3D
var neck: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var fore_l: Node3D
var fore_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var shin_l: Node3D
var shin_r: Node3D
var foot_l: Node3D
var foot_r: Node3D
var jaw: Node3D
var brow_l: Node3D
var brow_r: Node3D
var lid_l: Node3D
var lid_r: Node3D
var iris_l: Node3D
var iris_r: Node3D
var mouth_l: Node3D
var mouth_r: Node3D
var teeth: Node3D
var cloth_lower: Node3D
var hair_back: Node3D
var bubble: Label3D
var detail: Array = []
var fingers_l: Array = []
var fingers_r: Array = []

var _prev_pos: Vector3 = Vector3.INF
var _speed: float = 0.0
var _vel_local: Vector3 = Vector3.ZERO
var _blink: float = 0.0
var _next_blink: float = 2.5
var _face: Dictionary = {}
var _face_t: Dictionary = {}
var _idle_kind: int = 0
var _idle_left: float = 0.0
var _next_idle: float = 6.0
var _idle_w: float = 0.0
var _lod_near: bool = true
var _gaze: Vector2 = Vector2.ZERO


static func mat(c: Color, shine: float = 0.0) -> ShaderMaterial:
	var key := "%s_%s" % [c.to_html(), shine]
	if _mats.has(key):
		return _mats[key]
	if _toon == null:
		_toon = Shader.new()
		_toon.code = TOON_SHADER
		var os := Shader.new()
		os.code = OUTLINE_SHADER
		_outline = ShaderMaterial.new()
		_outline.shader = os
	var m := ShaderMaterial.new()
	m.shader = _toon
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("shine", shine)
	m.next_pass = _outline
	_mats[key] = m
	return m


# Material liso sem contorno, para traços pequenos do rosto.
static func mat_plain(c: Color) -> ShaderMaterial:
	var key := "p_" + c.to_html()
	if _mats.has(key):
		return _mats[key]
	mat(c)
	var m := ShaderMaterial.new()
	m.shader = _toon
	m.set_shader_parameter("albedo", c)
	_mats[key] = m
	return m


static func _sphere_mesh() -> Mesh:
	if _meshes.has("sphere"):
		return _meshes["sphere"]
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	s.radial_segments = 20
	s.rings = 12
	_meshes["sphere"] = s
	return s


static func _box_mesh() -> Mesh:
	if _meshes.has("box"):
		return _meshes["box"]
	var b := BoxMesh.new()
	_meshes["box"] = b
	return b


static func _taper_mesh(r0: float, r1: float) -> Mesh:
	var key := "t%d_%d" % [int(r0 * 1000), int(r1 * 1000)]
	if _meshes.has(key):
		return _meshes[key]
	var c := CylinderMesh.new()
	c.top_radius = r0
	c.bottom_radius = r1
	c.height = 1.0
	c.radial_segments = 14
	c.rings = 1
	_meshes[key] = c
	return c


func _node(parent: Node3D, mesh: Mesh, pos: Vector3, scale3: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale3
	parent.add_child(mi)
	return mi


func _ball(parent: Node3D, pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	return _node(parent, _sphere_mesh(), pos, size, color, rot)


func _dot(parent: Node3D, pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := _node(parent, _sphere_mesh(), pos, size, color, rot)
	mi.material_override = mat_plain(color)
	return mi


func _pdot(parent: Node3D, pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := _node(parent, _box_mesh(), pos, size, color, rot)
	mi.material_override = mat_plain(color)
	return mi


func _blk(parent: Node3D, pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	return _node(parent, _box_mesh(), pos, size, color, rot)


func _seg(parent: Node3D, pos: Vector3, length: float, r0: float, r1: float, color: Color) -> MeshInstance3D:
	return _node(parent, _taper_mesh(r0 * 1.14, r1 * 1.14), pos + Vector3(0, -length / 2.0, 0), Vector3(1, length, 1), color)


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func set_look(l: Dictionary) -> void:
	look = l
	for c in get_children():
		c.queue_free()
	detail.clear()
	fingers_l.clear()
	fingers_r.clear()
	seed_n = float(hash(str(l.get("hair", "")) + str(l.get("age", 0)) + str(l.get("skin", "")))) / 1000.0
	_next_blink = 1.0 + fmod(seed_n, 3.0)
	_next_idle = 3.0 + fmod(seed_n * 1.7, 6.0)
	_build()


func _pants_color(style: String, c1: Color, c2: Color) -> Color:
	match style:
		"jeans": return Color("#2f4768")
		"social", "terno", "farda": return c1.darkened(0.1)
		"couro", "sobretudo", "batina": return Color("#26262c")
		"academia": return Color("#2c2c34")
		"havaiana": return Color("#d9c9a2")
		"macacao": return c1
		"uniforme", "jaleco", "avental": return Color("#323744")
		"rasgada": return Color("#524d42")
		"time": return Color("#2a3039")
	var p := c2.darkened(0.55) if c2.get_luminance() > 0.5 else c2.lightened(0.15)
	if p.get_luminance() > 0.45:
		p = Color("#3a4a63")
	return p


func _build() -> void:
	var female: bool = str(look.get("gender", "")) == "mulher"
	var age: int = int(look.get("age", 30))
	var skin: Color = look.get("skin", Color("#e8bf9c"))
	var skin_d := skin.darkened(0.12)
	var c1: Color = look.get("clothes_color", Color("#4a5260"))
	var c2: Color = look.get("clothes_color2", Color("#dddddd"))
	var style: String = str(look.get("clothes", "camiseta"))
	var hair_c: Color = look.get("hair_color", Color("#2b1d14"))
	if age >= 62:
		hair_c = hair_c.lerp(Color("#d8d6d0"), 0.8)
	var wide: float = clampf(float(look.get("face_w", 1.0)), 0.9, 1.2)
	var sh: float = float(look.get("shoulders", 1.0)) * (0.84 if female else 1.0)
	var k: float = 0.93 if female else 1.0
	if age < 16:
		k *= 0.82
	scale = Vector3(k, k, k)
	var pants := _pants_color(style, c1, c2)
	var shoe := Color("#252220")
	if style in ["academia", "time"]:
		shoe = Color("#e9e6e0")
	elif style == "havaiana":
		shoe = Color("#c9712c")
	elif style in ["couro", "social", "terno", "farda", "batina", "uniforme"]:
		shoe = Color("#18120f")
	var long_sleeve: bool = style in ["moletom", "couro", "social", "terno", "sobretudo", "farda", "jaleco", "batina"]
	var sleeveless: bool = style in ["regata", "vestido"]
	var jacket: bool = style in ["couro", "sobretudo", "jaleco", "terno", "jeans"]
	var jacket_c: Color = c2 if style == "jaleco" else c1
	var skirt: bool = style == "vestido"
	var body_w: float = wide * (0.94 if female else 1.0) * 1.08

	hips = _pivot(self, Vector3(0, base_y, 0))
	# sombra de contato
	var blob := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.32
	cm.bottom_radius = 0.32
	cm.height = 0.01
	cm.radial_segments = 20
	if _shadow_mat == null:
		_shadow_mat = StandardMaterial3D.new()
		_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_mat.albedo_color = Color(0, 0, 0, 0.22)
		_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.material = _shadow_mat
	blob.mesh = cm
	blob.position = Vector3(0, 0.01, 0)
	add_child(blob)

	# ----- pernas -----
	for side in [-1, 1]:
		var hx: float = 0.095 * side * body_w
		var leg := _pivot(hips, Vector3(hx, -0.02, 0))
		var leg_c: Color = skin if skirt else pants
		var tr0: float = 0.1 if female else 0.098
		_seg(leg, Vector3.ZERO, 0.46, tr0 * body_w, 0.068, leg_c)
		_ball(leg, Vector3(0, -0.46, 0.005), Vector3.ONE * 0.128, leg_c)
		var shin := _pivot(leg, Vector3(0, -0.46, 0))
		_seg(shin, Vector3.ZERO, 0.42, 0.066, 0.043, leg_c)
		_ball(shin, Vector3(0, -0.1, -0.025), Vector3(0.115, 0.2, 0.105), leg_c)
		if style == "jeans" or style in ["social", "terno", "farda", "uniforme"]:
			_blk(shin, Vector3(0, -0.4, 0), Vector3(0.1, 0.03, 0.1), leg_c.darkened(0.15))
		var foot := _pivot(shin, Vector3(0, -0.42, 0))
		_blk(foot, Vector3(0, -0.03, 0.05), Vector3(0.112, 0.07, 0.25), shoe)
		_ball(foot, Vector3(0, -0.032, 0.165), Vector3(0.118, 0.075, 0.11), shoe)
		_blk(foot, Vector3(0, -0.068, 0.055), Vector3(0.118, 0.016, 0.27), Color("#d9d3c4") if style in ["academia", "time"] else Color("#0f0d0c"))
		_ball(foot, Vector3(0, 0.0, -0.045), Vector3(0.1, 0.09, 0.08), shoe.darkened(0.1))
		detail.append(_pdot(foot, Vector3(0, 0.005, 0.1), Vector3(0.06, 0.02, 0.1), shoe.lightened(0.25)))
		if side < 0:
			leg_l = leg
			shin_l = shin
			foot_l = foot
		else:
			leg_r = leg
			shin_r = shin
			foot_r = foot
	# ----- quadril -----
	_ball(hips, Vector3(0, 0.02, 0), Vector3(0.34 * body_w * (1.1 if female else 1.0), 0.2, 0.22), pants if not skirt else c1)
	if not skirt and style != "macacao":
		_blk(hips, Vector3(0, 0.1, 0), Vector3(0.325 * body_w, 0.045, 0.215), Color("#2e2016"))
		_blk(hips, Vector3(0, 0.1, 0.108), Vector3(0.04, 0.035, 0.01), Color("#cfae52"))
	if skirt:
		cloth_lower = _pivot(hips, Vector3(0, 0.0, 0))
		var sk := CylinderMesh.new()
		sk.top_radius = 0.17
		sk.bottom_radius = 0.3
		sk.height = 0.5
		sk.radial_segments = 16
		var smi := MeshInstance3D.new()
		smi.mesh = sk
		smi.material_override = mat(c1)
		smi.position = Vector3(0, -0.2, 0)
		smi.scale = Vector3(1.0, 1.0, 0.85)
		cloth_lower.add_child(smi)
	elif jacket and style in ["sobretudo", "couro", "terno", "jaleco"]:
		cloth_lower = _pivot(hips, Vector3(0, 0.06, 0))
		var hem := CylinderMesh.new()
		hem.top_radius = 0.17 * body_w
		hem.bottom_radius = 0.2 * body_w
		hem.height = 0.3 if style != "sobretudo" else 0.55
		hem.radial_segments = 14
		var hmi := MeshInstance3D.new()
		hmi.mesh = hem
		hmi.material_override = mat(jacket_c)
		hmi.position = Vector3(0, -hem.height / 2.0, -0.01)
		hmi.scale = Vector3(1.05, 1.0, 0.8)
		cloth_lower.add_child(hmi)
	# ----- cintura / tronco -----
	torso = _pivot(hips, Vector3(0, 0.1, 0))
	var chest_c: Color = jacket_c if jacket else c1
	var under_c: Color = c1 if not jacket else c2
	if style == "regata":
		chest_c = skin
	_ball(torso, Vector3(0, 0.13, 0), Vector3(0.305 * body_w, 0.28, 0.2), under_c if style != "regata" else c1)
	_ball(torso, Vector3(0, 0.36, 0), Vector3(0.40 * sh * body_w, 0.34, 0.235), chest_c)
	_ball(torso, Vector3(0, 0.34, -0.07), Vector3(0.38 * sh * body_w, 0.3, 0.14), chest_c.darkened(0.04))
	if style == "regata":
		_ball(torso, Vector3(0, 0.34, 0.005), Vector3(0.405 * sh * body_w, 0.3, 0.24), c1)
	if female:
		for side in [-1, 1]:
			_ball(torso, Vector3(0.085 * side, 0.34, 0.095), Vector3(0.14, 0.14, 0.13), chest_c if style != "regata" else c1)
	else:
		for side in [-1, 1]:
			_ball(torso, Vector3(0.085 * side * sh, 0.385, 0.085), Vector3(0.15, 0.1, 0.08), chest_c)
	# trapézio e ombros
	_ball(torso, Vector3(0, 0.5, -0.02), Vector3(0.3 * sh * body_w, 0.1, 0.17), skin if sleeveless or style in ["regata"] else chest_c)
	for side in [-1, 1]:
		var sc: Color = skin if sleeveless else (jacket_c if jacket else c1)
		_ball(torso, Vector3(0.205 * side * sh * body_w, 0.46, 0), Vector3.ONE * 0.115, sc)
	if jacket:
		for side in [-1, 1]:
			_blk(torso, Vector3(0.075 * side, 0.3, 0.118), Vector3(0.1, 0.36, 0.03), jacket_c.darkened(0.06), Vector3(0, 0, -0.1 * side))
			_blk(torso, Vector3(0.1 * side, 0.46, 0.105), Vector3(0.1, 0.07, 0.07), jacket_c.lightened(0.1), Vector3(0, 0, 0.5 * side))
			detail.append(_blk(torso, Vector3(0.1 * side, 0.12, 0.12), Vector3(0.12, 0.12, 0.02), jacket_c.darkened(0.18)))
		_blk(torso, Vector3(0, 0.1, 0.1), Vector3(0.3 * body_w, 0.03, 0.02), jacket_c.darkened(0.25))
	if style == "terno":
		_blk(torso, Vector3(0, 0.3, 0.126), Vector3(0.04, 0.34, 0.012), Color("#8a1f2c"))
	if style == "social":
		_blk(torso, Vector3(0, 0.47, 0.11), Vector3(0.13, 0.05, 0.05), c1.lightened(0.1))
		for i in 5:
			detail.append(_ball(torso, Vector3(0, 0.45 - i * 0.075, 0.122), Vector3.ONE * 0.016, Color("#cfcabb")))
	if style == "time":
		_blk(torso, Vector3(0, 0.34, 0.121), Vector3(0.40 * sh * body_w, 0.06, 0.012), c2)
	if style in ["avental", "macacao"]:
		_blk(torso, Vector3(0, 0.2, 0.108), Vector3(0.28, 0.4, 0.02), c2 if style == "avental" else c1.darkened(0.12))
	if style == "farda":
		_ball(torso, Vector3(0.11, 0.38, 0.12), Vector3(0.05, 0.06, 0.02), Color("#d4a72c"))
		_blk(torso, Vector3(0, 0.12, 0.1), Vector3(0.31 * body_w, 0.04, 0.03), Color("#14141a"))
	if style == "moletom":
		_ball(torso, Vector3(0, 0.5, -0.06), Vector3(0.28, 0.12, 0.18), c1.darkened(0.12))
		_blk(torso, Vector3(0, 0.12, 0.105), Vector3(0.22, 0.12, 0.02), c1.darkened(0.1))
	if style == "couro":
		_blk(torso, Vector3(-0.11 * sh, 0.32, 0.128), Vector3(0.02, 0.28, 0.01), Color("#5a5a60"))
	# ----- braços -----
	for side in [-1, 1]:
		var arm := _pivot(torso, Vector3(0.205 * side * sh * body_w, 0.46, 0))
		var up_c: Color = skin if sleeveless else (jacket_c if jacket else c1)
		_seg(arm, Vector3.ZERO, 0.3, 0.062, 0.047, skin)
		_ball(arm, Vector3(0, -0.08, 0.012), Vector3(0.1, 0.17, 0.095), skin)
		var sleeve_len: float = 0.3 if long_sleeve else (0.19 if not sleeveless else 0.0)
		if sleeve_len > 0.0:
			_seg(arm, Vector3.ZERO, sleeve_len, 0.069, 0.058 if sleeve_len > 0.25 else 0.064, up_c)
		_ball(arm, Vector3(0, -0.3, 0), Vector3.ONE * 0.088, up_c if long_sleeve else skin)
		var fore := _pivot(arm, Vector3(0, -0.3, 0))
		_seg(fore, Vector3.ZERO, 0.27, 0.047, 0.034, (jacket_c if jacket else c1) if long_sleeve else skin)
		_ball(fore, Vector3(0, -0.06, 0.012), Vector3(0.09, 0.14, 0.085), (jacket_c if jacket else c1) if long_sleeve else skin)
		if long_sleeve:
			_blk(fore, Vector3(0, -0.25, 0), Vector3(0.075, 0.03, 0.075), (jacket_c if jacket else c1).darkened(0.2))
		var hand := _pivot(fore, Vector3(0, -0.27, 0))
		_ball(hand, Vector3(0, -0.04, 0.005), Vector3(0.078, 0.09, 0.04), skin)
		var fing: Array = []
		for fi in 4:
			var fp := _pivot(hand, Vector3((fi - 1.5) * 0.017, -0.075, 0.0))
			var f1 := _seg(fp, Vector3.ZERO, 0.04, 0.0095, 0.008, skin)
			var fp2 := _pivot(fp, Vector3(0, -0.04, 0))
			var f2 := _seg(fp2, Vector3.ZERO, 0.032, 0.0085, 0.0065, skin)
			detail.append(f1)
			detail.append(f2)
			fing.append([fp, fp2])
		var thumb := _pivot(hand, Vector3(0.036 * -side, -0.03, 0.012))
		thumb.rotation.z = 0.5 * -side
		detail.append(_seg(thumb, Vector3.ZERO, 0.045, 0.011, 0.008, skin))
		if side < 0:
			arm_l = arm
			fore_l = fore
			hand_l = hand
			fingers_l = fing
		else:
			arm_r = arm
			fore_r = fore
			hand_r = hand
			fingers_r = fing
	# ----- pescoço e cabeça -----
	var nk: float = float(look.get("neck", 1.0))
	neck = _pivot(torso, Vector3(0, 0.54, 0))
	_seg(neck, Vector3(0, 0.0, 0), 0.13, 0.054 * nk, 0.058 * nk, skin.darkened(0.04))
	if not female:
		detail.append(_ball(neck, Vector3(0, 0.06, 0.05 * nk), Vector3(0.035, 0.04, 0.035), skin.darkened(0.05)))
	head = _pivot(neck, Vector3(0, 0.25, 0))
	head.scale = Vector3.ONE * 1.2
	_build_head(skin, skin_d, hair_c, female, age, c1)
	if style in ["social", "terno", "farda", "jaleco"] or jacket:
		_blk(neck, Vector3(0, 0.0, 0.0), Vector3(0.2, 0.04, 0.17), (c2 if style == "social" else jacket_c).lightened(0.12))
	bubble = Label3D.new()
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.font_size = 64
	bubble.pixel_size = 0.006
	bubble.outline_size = 16
	bubble.outline_modulate = Color(0.07, 0.05, 0.05)
	bubble.position = Vector3(0, 2.3, 0)
	bubble.visible = false
	add_child(bubble)
	_face = FaceBase.NEUTRAL.duplicate()
	_face_t = FaceBase.NEUTRAL.duplicate()
	set_emotion(emotion)


func _build_head(skin: Color, skin_d: Color, hair_c: Color, female: bool, age: int, c1: Color) -> void:
	var hw: float = 0.205 * clampf(float(look.get("face_w", 1.0)), 0.9, 1.15)
	var hl: float = 0.255 * clampf(float(look.get("face_len", 1.0)), 0.9, 1.12)
	_ball(head, Vector3.ZERO, Vector3(hw, hl, 0.235), skin)
	var jw: float = clampf(float(look.get("jaw", 0.8)), 0.55, 0.98)
	_ball(head, Vector3(0, -0.07, 0.015), Vector3(hw * (0.8 + jw * 0.2), hl * 0.56, 0.205), skin)
	for side in [-1, 1]:
		_ball(head, Vector3(side * hw * 0.52, 0, 0), Vector3(0.042, 0.078, 0.05), skin_d)
		detail.append(_dot(head, Vector3(side * hw * 0.52 + side * 0.006, 0.0, 0.006), Vector3(0.022, 0.05, 0.03), skin_d.darkened(0.2)))
	# queixo e nariz
	_ball(head, Vector3(0, -hl * 0.46, 0.085), Vector3(0.085, 0.07, 0.07), skin)
	_ball(head, Vector3(0, 0.0, 0.112), Vector3(0.036, 0.095, 0.045), skin_d.lightened(0.04), Vector3(-0.12, 0, 0))
	_ball(head, Vector3(0, -0.03, 0.135), Vector3(0.046, 0.04, 0.045), skin_d.lightened(0.06))
	for side in [-1, 1]:
		detail.append(_dot(head, Vector3(side * 0.019, -0.042, 0.128), Vector3(0.016, 0.014, 0.02), skin_d.darkened(0.45)))
	var eye_c: Color = look.get("eye_color", Color("#3a2a20"))
	var lid_c: Color = skin.darkened(0.04)
	for side in [-1, 1]:
		var ex: float = side * 0.052
		_dot(head, Vector3(ex, 0.018, 0.1), Vector3(0.056, 0.04, 0.03), Color("#f6f2ea"))
		var ir := _pivot(head, Vector3(ex, 0.018, 0.116))
		_dot(ir, Vector3.ZERO, Vector3(0.03, 0.032, 0.012), eye_c)
		_dot(ir, Vector3(0, 0, 0.006), Vector3(0.016, 0.018, 0.008), Color("#0c0a0a"))
		detail.append(_dot(ir, Vector3(0.006, 0.007, 0.011), Vector3(0.006, 0.006, 0.004), Color.WHITE))
		var lid := _pivot(head, Vector3(ex, 0.04, 0.108))
		_dot(lid, Vector3(0, -0.012, 0.0), Vector3(0.064, 0.026, 0.034), lid_c)
		lid.scale = Vector3(1, 0.4, 1)
		var br := _pivot(head, Vector3(ex, 0.066, 0.112))
		_pdot(br, Vector3.ZERO, Vector3(0.068, 0.013 if female else 0.02, 0.016), hair_c.darkened(0.25))
		if side < 0:
			iris_l = ir
			lid_l = lid
			brow_l = br
		else:
			iris_r = ir
			lid_r = lid
			brow_r = br
		if female:
			detail.append(_pdot(head, Vector3(ex, 0.042, 0.114), Vector3(0.07, 0.006, 0.012), Color("#161212")))
	# boca: lábios, cantos, mandíbula móvel e dentes
	var lip: Color = look.get("lip_color", skin.darkened(0.25))
	_dot(head, Vector3(0, -0.075, 0.108), Vector3(0.064, 0.013, 0.02), lip.lightened(0.04))
	jaw = _pivot(head, Vector3(0, -0.07, 0.0))
	_dot(jaw, Vector3(0, -0.012, 0.108), Vector3(0.062, 0.015, 0.022), lip)
	teeth = _pivot(jaw, Vector3(0, -0.002, 0.103))
	_pdot(teeth, Vector3.ZERO, Vector3(0.05, 0.012, 0.012), Color("#f0ece2"))
	teeth.visible = false
	mouth_l = _pivot(head, Vector3(-0.034, -0.082, 0.104))
	_dot(mouth_l, Vector3.ZERO, Vector3(0.014, 0.012, 0.014), lip.darkened(0.15))
	mouth_r = _pivot(head, Vector3(0.034, -0.082, 0.104))
	_dot(mouth_r, Vector3.ZERO, Vector3(0.014, 0.012, 0.014), lip.darkened(0.15))
	var beard: String = str(look.get("beard", "none"))
	if beard != "none" and not female:
		var bc: Color = hair_c.darkened(0.1) if beard != "stubble" else skin.darkened(0.32)
		match beard:
			"mustache":
				_ball(head, Vector3(0, -0.058, 0.112), Vector3(0.09, 0.02, 0.025), bc)
			"goatee":
				_ball(head, Vector3(0, -0.13, 0.09), Vector3(0.07, 0.08, 0.06), bc)
				_ball(head, Vector3(0, -0.058, 0.112), Vector3(0.08, 0.018, 0.025), bc)
			_:
				var bl: float = 0.2 if beard == "long" else 0.14
				_ball(head, Vector3(0, -0.095 - (0.04 if beard == "long" else 0.0), 0.04), Vector3(hw * 0.97, bl, 0.2), bc)
				_ball(head, Vector3(0, -0.06, 0.112), Vector3(0.09, 0.02, 0.025), bc)
	if age >= 45:
		for side in [-1, 1]:
			detail.append(_pdot(head, Vector3(side * 0.1, -0.015, 0.1), Vector3(0.05, 0.004, 0.01), skin_d.darkened(0.25), Vector3(0, 0, side * 0.5)))
		detail.append(_pdot(head, Vector3(0, 0.1, 0.108), Vector3(0.12, 0.004, 0.01), skin_d.darkened(0.2)))
	_hair(str(look.get("hair", "curto")), hair_c, hw, hl, female)
	for ex2 in look.get("extras", []):
		var e := str(ex2)
		if "culos" in e:
			for side in [-1, 1]:
				_ball(head, Vector3(side * 0.052, 0.018, 0.128), Vector3(0.066, 0.052, 0.012), Color(0.1, 0.1, 0.12))
			_blk(head, Vector3(0, 0.03, 0.128), Vector3(0.05, 0.01, 0.01), Color(0.1, 0.1, 0.12))
		if "bon" in e:
			_ball(head, Vector3(0, 0.07, -0.01), Vector3(hw * 1.12, hl * 0.62, 0.26), c1.darkened(0.2))
			_blk(head, Vector3(0, 0.06, 0.15), Vector3(0.2, 0.018, 0.13), c1.darkened(0.3))


func _hair(style: String, c: Color, hw: float, hl: float, female: bool) -> void:
	if style == "careca":
		return
	var cap := Vector3(hw * 1.08, hl * 0.7, 0.26)
	var skin_c: Color = look.get("skin", Color.WHITE)
	hair_back = _pivot(head, Vector3.ZERO)
	match style:
		"raspado":
			_ball(head, Vector3(0, 0.04, -0.008), Vector3(hw * 1.03, hl * 0.66, 0.245), c.lerp(skin_c, 0.5))
		"moicano":
			_ball(head, Vector3(0, 0.04, -0.008), Vector3(hw * 1.03, hl * 0.66, 0.245), c.lerp(skin_c, 0.6))
			_blk(head, Vector3(0, 0.15, -0.02), Vector3(0.055, 0.11, 0.25), c)
		"black_power", "cacheado":
			var big: float = 1.55 if style == "black_power" else 1.28
			_ball(head, Vector3(0, 0.08, -0.03), Vector3(hw * big * 1.1, hl * big * 0.9, 0.25 * big), c)
			for i in 6:
				var a := TAU * i / 6.0
				detail.append(_ball(head, Vector3(cos(a) * hw * big * 0.55, 0.08 + sin(a) * hl * big * 0.4, -0.03), Vector3.ONE * 0.1 * big, c.lightened(0.04)))
		_:
			_ball(head, Vector3(0, 0.06, -0.015), cap, c)
			_ball(head, Vector3(0, 0.01, -0.07), Vector3(hw * 1.06, hl * 0.95, 0.17), c)
			for side in [-1, 1]:
				_ball(head, Vector3(side * hw * 0.46, 0.0, -0.02), Vector3(0.05, 0.13, 0.15), c.darkened(0.04))
			if style in ["franja", "desgrenhado", "curto", "medio", "longo"]:
				_blk(head, Vector3(0.02, 0.095, 0.095), Vector3(hw * 0.95, 0.055, 0.06), c.lightened(0.04), Vector3(0.35, 0, 0.08))
				detail.append(_blk(head, Vector3(-0.07, 0.085, 0.1), Vector3(0.08, 0.05, 0.04), c.darkened(0.06), Vector3(0.3, 0, -0.3)))
			if style in ["medio", "longo", "trancas", "dreads"]:
				var drop: float = 0.46 if style in ["longo", "trancas", "dreads"] else 0.22
				_blk(hair_back, Vector3(0, -drop / 2.0 + 0.03, -0.08), Vector3(hw * 1.06, drop, 0.13), c)
				if female or style == "longo":
					for side in [-1, 1]:
						_blk(head, Vector3(side * hw * 0.5, -0.1, 0.0), Vector3(0.06, 0.32 if style == "longo" else 0.18, 0.13), c)
			if style in ["trancas", "dreads"]:
				for i in 7:
					_seg(hair_back, Vector3(-0.1 + i * 0.033, -0.04, -0.12), 0.34, 0.022, 0.014, c.darkened(0.08))
			if style == "coque":
				_ball(head, Vector3(0, 0.17, -0.1), Vector3(0.14, 0.12, 0.14), c)
			if style == "rabo":
				_seg(hair_back, Vector3(0, 0.0, -0.17), 0.3, 0.05, 0.025, c)


func set_emotion(e: String) -> void:
	emotion = e
	_face_t = FaceBase.NEUTRAL.duplicate()
	var ex: Dictionary = FaceBase.EXPRESSIONS.get(e, {})
	for key in ex:
		_face_t[key] = ex[key]
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


# Fora da área visível o boneco não desenha nem anima.
func set_active(on: bool) -> void:
	if visible != on:
		visible = on
	set_process(on)


# Nível de detalhe: de longe esconde dedos, botões e minúcias do rosto.
func set_lod(near: bool) -> void:
	if near == _lod_near:
		return
	_lod_near = near
	for n in detail:
		if is_instance_valid(n):
			(n as Node3D).visible = near


func _process(delta: float) -> void:
	if hips == null:
		return
	t += delta
	talk_left = maxf(0.0, talk_left - delta)
	# velocidade real a partir do deslocamento (ignora teletransportes)
	var gp := global_position
	if _prev_pos == Vector3.INF:
		_prev_pos = gp
	var vel := (gp - _prev_pos) / maxf(delta, 0.0001)
	_prev_pos = gp
	if vel.length() < 14.0:
		_speed = lerpf(_speed, vel.length(), minf(delta * 10.0, 1.0))
		_vel_local = _vel_local.lerp(global_transform.basis.inverse() * vel, minf(delta * 8.0, 1.0))
	else:
		_speed = 0.0
	if lying:
		rotation.x = lerp_angle(rotation.x, -PI / 2.0, minf(delta * 4.0, 1.0))
		return
	var spd: float = _speed
	gait = lerpf(gait, clampf(spd / 1.0, 0.0, 1.0), minf(delta * 9.0, 1.0))
	var run_k: float = clampf((spd - 3.8) / 2.6, 0.0, 1.0)
	var amp: float = lerpf(clampf(spd / 3.4, 0.35, 1.25) * 0.46, 0.78, run_k)
	if gait > 0.02:
		phase += delta * (2.8 + spd * 1.15)
	var p := phase
	var s := sin(p)
	var s2 := sin(p + PI)
	var c := cos(p)
	var c2 := cos(p + PI)
	var g := gait
	var idle := 1.0 - g
	# ---- pernas ----
	leg_l.rotation.x = -s * amp * g + idle * (0.03 + sin(t * 0.37 + seed_n) * 0.04)
	leg_r.rotation.x = -s2 * amp * g + idle * (0.03 - sin(t * 0.37 + seed_n) * 0.04)
	var kneel: float = lerpf(1.45, 1.95, run_k)
	shin_l.rotation.x = (maxf(0.0, c) * amp * kneel + 0.09) * g + idle * (0.05 + maxf(0.0, sin(t * 0.37 + seed_n)) * 0.08)
	shin_r.rotation.x = (maxf(0.0, c2) * amp * kneel + 0.09) * g + idle * (0.05 + maxf(0.0, -sin(t * 0.37 + seed_n)) * 0.08)
	foot_l.rotation.x = (-(leg_l.rotation.x + shin_l.rotation.x) - 0.28 * maxf(0.0, s) + 0.42 * maxf(0.0, -s)) * g
	foot_r.rotation.x = (-(leg_r.rotation.x + shin_r.rotation.x) - 0.28 * maxf(0.0, s2) + 0.42 * maxf(0.0, -s2)) * g
	foot_l.rotation.x += idle * -(leg_l.rotation.x + shin_l.rotation.x)
	foot_r.rotation.x += idle * -(leg_r.rotation.x + shin_r.rotation.x)
	# ---- quadril e tronco ----
	var breath := sin(t * 1.7 + seed_n)
	hips.position.y = base_y + g * (cos(2.0 * p) * (0.026 + run_k * 0.02) - 0.016 - run_k * 0.05) + breath * 0.004 * idle
	hips.position.x = sin(p) * 0.022 * g + sin(t * 0.4 + seed_n) * 0.012 * idle
	hips.rotation.y = -s * (0.13 + run_k * 0.08) * g
	hips.rotation.z = s * 0.05 * g + sin(t * 0.4 + seed_n) * 0.035 * idle
	hips.rotation.x = g * (0.04 + run_k * 0.08)
	torso.rotation.y = s * (0.22 + run_k * 0.12) * g
	torso.rotation.x = g * (0.03 + run_k * 0.2) + breath * 0.012 * idle
	torso.rotation.z = -hips.rotation.z * 0.9
	torso.scale = Vector3(1.0 + breath * 0.012, 1.0 + breath * 0.01, 1.0 + breath * 0.02)
	# ---- braços ----
	var sw: float = lerpf(0.9, 1.15, run_k)
	arm_l.rotation.x = s * amp * sw * g + idle * sin(t * 0.8 + seed_n) * 0.035
	arm_r.rotation.x = s2 * amp * sw * g + idle * sin(t * 0.8 + seed_n + 1.7) * 0.035
	var elbow: float = 0.16 + g * (0.22 + run_k * 1.0)
	fore_l.rotation.x = -elbow - maxf(0.0, -s) * 0.28 * g
	fore_r.rotation.x = -elbow - maxf(0.0, -s2) * 0.28 * g
	arm_l.rotation.z = -0.07 - g * 0.03 - run_k * 0.1
	arm_r.rotation.z = 0.07 + g * 0.03 + run_k * 0.1
	arm_l.rotation.y = 0.0
	arm_r.rotation.y = 0.0
	hand_l.rotation.x = 0.0
	hand_r.rotation.x = 0.0
	var curl: float = 0.5 + run_k * 0.6
	for f in fingers_l:
		(f[0] as Node3D).rotation.x = -curl * 0.6
		(f[1] as Node3D).rotation.x = -curl
	for f in fingers_r:
		(f[0] as Node3D).rotation.x = -curl * 0.6
		(f[1] as Node3D).rotation.x = -curl
	# ---- posturas de espera ----
	_idle(delta, idle)
	# ---- fala: gestos de duas mãos, cabeça e mandíbula ----
	var talk := 1.0 if talk_left > 0.0 else 0.0
	if talk > 0.0:
		var gs := sin(t * 3.1)
		arm_r.rotation.x = lerpf(arm_r.rotation.x, -0.55 + gs * 0.25, 0.7)
		fore_r.rotation.x = lerpf(fore_r.rotation.x, -1.05 + sin(t * 4.3) * 0.3, 0.7)
		arm_r.rotation.z = lerpf(arm_r.rotation.z, 0.3, 0.7)
		arm_l.rotation.x = lerpf(arm_l.rotation.x, -0.35 + sin(t * 2.6 + 1.3) * 0.2, 0.5)
		fore_l.rotation.x = lerpf(fore_l.rotation.x, -0.9 + sin(t * 3.4) * 0.25, 0.5)
		torso.rotation.x += 0.04 + sin(t * 5.0) * 0.012
	# ---- cabeça, pescoço e olhar ----
	var tgt_y := 0.0
	var tgt_x := 0.0
	var gaze := Vector2.ZERO
	if look_target != Vector3.INF:
		var lp := to_local(look_target)
		tgt_y = clampf(atan2(lp.x, lp.z), -1.0, 1.0)
		tgt_x = clampf(-atan2(lp.y - 1.5, maxf(Vector2(lp.x, lp.z).length(), 0.1)), -0.4, 0.4)
	else:
		tgt_y = sin(t * 0.4 + seed_n) * 0.3 + sin(t * 0.9 + seed_n) * 0.1
	tgt_y = lerpf(tgt_y, -torso.rotation.y * 0.8, g * 0.8) if look_target == Vector3.INF else tgt_y - torso.rotation.y * 0.7
	var hy: float = tgt_y
	neck.rotation.y = lerp_angle(neck.rotation.y, hy * 0.45, minf(delta * 7.0, 1.0))
	head.rotation.y = lerp_angle(head.rotation.y, hy * 0.55, minf(delta * 9.0, 1.0))
	neck.rotation.x = lerpf(neck.rotation.x, tgt_x * 0.4 + g * 0.04, minf(delta * 6.0, 1.0))
	head.rotation.x = lerpf(head.rotation.x, tgt_x * 0.6 - g * 0.04 + (sin(t * 8.0) * 0.045 + 0.02) * talk, minf(delta * 9.0, 1.0))
	head.rotation.z = lerpf(head.rotation.z, sin(t * 2.0) * 0.035 * talk - _vel_local.x * 0.01 + float(_face["tilt"]), minf(delta * 6.0, 1.0))
	gaze = Vector2(clampf(hy * 0.3, -0.6, 0.6), clampf(tgt_x * 0.5, -0.5, 0.5)) * 0.0
	# ---- rosto ----
	_animate_face(delta, talk)
	# ---- roupa e cabelo com inércia ----
	if cloth_lower != null:
		cloth_lower.rotation.x = clampf(-_vel_local.z * 0.05, -0.35, 0.35) + sin(t * 1.2) * 0.01
		cloth_lower.rotation.z = clampf(_vel_local.x * 0.05, -0.3, 0.3)
	if hair_back != null:
		hair_back.rotation.x = clampf(_vel_local.z * 0.04, -0.3, 0.25) * 0.6 + g * sin(p * 2.0) * 0.03
		hair_back.rotation.z = clampf(-_vel_local.x * 0.04, -0.25, 0.25)
	if bubble and bubble.visible:
		bubble.position.y = 2.3 + sin(t * 2.4) * 0.04


# Posturas de espera: olhar o relógio, coçar a cabeça, cruzar os braços, trocar o peso.
func _idle(delta: float, idle: float) -> void:
	if idle < 0.9 or talk_left > 0.0:
		_idle_left = 0.0
		_idle_w = lerpf(_idle_w, 0.0, minf(delta * 6.0, 1.0))
		return
	_next_idle -= delta
	if _next_idle <= 0.0 and _idle_left <= 0.0:
		_idle_kind = 1 + int(fmod(abs(seed_n * 91.0 + t), 4.0))
		_idle_left = randf_range(2.2, 4.5)
		_next_idle = randf_range(7.0, 16.0)
	if _idle_left > 0.0:
		_idle_left -= delta
		_idle_w = lerpf(_idle_w, 1.0, minf(delta * 4.0, 1.0))
	else:
		_idle_w = lerpf(_idle_w, 0.0, minf(delta * 3.0, 1.0))
	if _idle_w < 0.02:
		return
	var w := _idle_w
	match _idle_kind:
		1:   # olhar o relógio
			arm_l.rotation.x = lerpf(arm_l.rotation.x, -0.5, w)
			fore_l.rotation.x = lerpf(fore_l.rotation.x, -1.7, w)
			head.rotation.x = lerpf(head.rotation.x, 0.3, w)
		2:   # coçar a cabeça
			arm_r.rotation.x = lerpf(arm_r.rotation.x, -2.3, w)
			arm_r.rotation.z = lerpf(arm_r.rotation.z, 0.5, w)
			fore_r.rotation.x = lerpf(fore_r.rotation.x, -1.5 + sin(t * 9.0) * 0.12, w)
			head.rotation.z = lerpf(head.rotation.z, 0.1, w)
		3:   # braços cruzados
			for a in [arm_l, arm_r]:
				a.rotation.x = lerpf(a.rotation.x, -0.5, w)
			arm_l.rotation.z = lerpf(arm_l.rotation.z, 0.5, w)
			arm_r.rotation.z = lerpf(arm_r.rotation.z, -0.5, w)
			fore_l.rotation.x = lerpf(fore_l.rotation.x, -1.9, w)
			fore_r.rotation.x = lerpf(fore_r.rotation.x, -1.9, w)
			arm_l.rotation.y = 0.9 * w
			arm_r.rotation.y = -0.9 * w
		4:   # mãos no bolso / peso numa perna
			arm_l.rotation.x = lerpf(arm_l.rotation.x, 0.15, w)
			arm_r.rotation.x = lerpf(arm_r.rotation.x, 0.15, w)
			fore_l.rotation.x = lerpf(fore_l.rotation.x, -0.6, w)
			fore_r.rotation.x = lerpf(fore_r.rotation.x, -0.6, w)
			hips.rotation.z += 0.07 * w
			leg_l.rotation.z = 0.0
			torso.rotation.z -= 0.05 * w


func _animate_face(delta: float, talk: float) -> void:
	for key in _face:
		_face[key] = lerpf(float(_face[key]), float(_face_t[key]), minf(delta * 7.0, 1.0))
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink = 1.0
		_next_blink = randf_range(2.2, 5.5)
	_blink = maxf(0.0, _blink - delta * 8.0)
	var open: float = clampf(float(_face["eye_open"]), 0.0, 1.5)
	var squint: float = float(_face["squint"])
	var lid_s: float = clampf(0.25 + (1.0 - open) * 0.9 + squint * 0.35 + sin(_blink * PI) * 0.9, 0.12, 1.2)
	for lid in [lid_l, lid_r]:
		(lid as Node3D).scale = Vector3(1, lid_s, 1)
	var ba: float = float(_face["brow_angle"])
	var braise: float = float(_face["brow_raise"])
	var asym: float = float(_face["brow_asym"])
	brow_l.rotation.z = -ba * 0.35 + asym * 0.12
	brow_r.rotation.z = ba * 0.35
	brow_l.position.y = 0.066 + braise * 0.012 + asym * 0.01
	brow_r.position.y = 0.066 + braise * 0.012
	# olhos acompanham o alvo
	var gx: float = float(_face["gaze_x"]) * 0.01
	var gy: float = -float(_face["gaze_y"]) * 0.006
	if look_target != Vector3.INF:
		var lp := head.to_local(look_target)
		gx += clampf(lp.x * 0.02, -0.011, 0.011)
		gy += clampf((lp.y) * 0.01, -0.006, 0.006)
	iris_l.position = Vector3(-0.052 + gx, 0.018 + gy, 0.116)
	iris_r.position = Vector3(0.052 + gx, 0.018 + gy, 0.116)
	# boca: abre ao falar, curva conforme a emoção
	var mo: float = clampf(float(_face["mouth_open"]) + talk * (0.35 + 0.35 * sin(t * 15.0 + seed_n)), 0.0, 1.0)
	jaw.rotation.x = mo * 0.35
	teeth.visible = (mo > 0.25 and _lod_near) or float(_face["teeth"]) > 0.5
	var curve: float = float(_face["mouth_curve"])
	var smirk: float = float(_face["smirk"])
	mouth_l.position.y = -0.082 + curve * 0.011 + smirk * 0.008
	mouth_r.position.y = -0.082 + curve * 0.011
	var mw: float = float(_face["mouth_width"])
	mouth_l.position.x = -0.034 * mw
	mouth_r.position.x = 0.034 * mw
	if bubble and bubble.visible:
		pass
