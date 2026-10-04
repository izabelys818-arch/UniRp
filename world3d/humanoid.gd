extends Node3D

# Personagem 3D montado por código (sem modelos prontos). Esqueleto simples com quadril, tronco,
# braços e pernas articulados; membros afunilados, roupas em camadas, cabelo em volumes.
# Visual de desenho: sombra em degraus, luz de contorno e traço de tinta (casco invertido).

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
var foot_l: Node3D
var foot_r: Node3D
var bubble: Label3D
var base_y: float = 0.93


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


# Cilindro afunilado de altura 1.
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


func _blk(parent: Node3D, pos: Vector3, size: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	return _node(parent, _box_mesh(), pos, size, color, rot)


# Segmento afunilado que começa em "pos" (topo) e desce "length".
func _seg(parent: Node3D, pos: Vector3, length: float, r0: float, r1: float, color: Color) -> MeshInstance3D:
	return _node(parent, _taper_mesh(r0 * 1.16, r1 * 1.16), pos + Vector3(0, -length / 2.0, 0), Vector3(1, length, 1), color)


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func set_look(l: Dictionary) -> void:
	look = l
	for c in get_children():
		c.queue_free()
	seed_n = float(hash(str(l.get("hair", "")) + str(l.get("age", 0)) + str(l.get("skin", "")))) / 1000.0
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
		var tr0: float = 0.098 if female else 0.095
		_seg(leg, Vector3.ZERO, 0.46, tr0 * body_w, 0.066, leg_c)
		_ball(leg, Vector3(0, -0.46, 0), Vector3.ONE * 0.135, leg_c)
		var shin := _pivot(leg, Vector3(0, -0.46, 0))
		_seg(shin, Vector3.ZERO, 0.42, 0.064, 0.044, leg_c)
		if style == "jeans" or style in ["social", "terno", "farda", "uniforme"]:
			_blk(shin, Vector3(0, -0.4, 0), Vector3(0.1, 0.03, 0.1), leg_c.darkened(0.15))
		var foot := _pivot(shin, Vector3(0, -0.42, 0))
		_blk(foot, Vector3(0, -0.035, 0.05), Vector3(0.115, 0.075, 0.27), shoe)
		_ball(foot, Vector3(0, -0.035, 0.17), Vector3(0.12, 0.08, 0.1), shoe)
		_blk(foot, Vector3(0, -0.075, 0.05), Vector3(0.12, 0.018, 0.28), Color("#d9d3c4") if style in ["academia", "time"] else Color("#0f0d0c"))
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
		hips.add_child(smi)
	# ----- tronco -----
	torso = _pivot(hips, Vector3(0, 0.1, 0))
	var chest_c: Color = jacket_c if jacket else c1
	var under_c: Color = c1 if not jacket else c2
	if style == "regata":
		chest_c = skin
	_ball(torso, Vector3(0, 0.13, 0), Vector3(0.305 * body_w, 0.28, 0.2), under_c if style != "regata" else c1)
	_ball(torso, Vector3(0, 0.36, 0), Vector3(0.40 * sh * body_w, 0.34, 0.235), chest_c)
	if style == "regata":
		_ball(torso, Vector3(0, 0.34, 0.005), Vector3(0.405 * sh * body_w, 0.3, 0.24), c1)
	if female:
		for side in [-1, 1]:
			_ball(torso, Vector3(0.085 * side, 0.34, 0.095), Vector3(0.14, 0.14, 0.13), chest_c if style != "regata" else c1)
	for side in [-1, 1]:
		var sc: Color = skin if sleeveless else (jacket_c if jacket else c1)
		_ball(torso, Vector3(0.205 * side * sh * body_w, 0.46, 0), Vector3.ONE * 0.105, sc)
	if jacket:
		for side in [-1, 1]:
			_blk(torso, Vector3(0.075 * side, 0.3, 0.118), Vector3(0.1, 0.36, 0.03), jacket_c.darkened(0.06), Vector3(0, 0, -0.1 * side))
			_blk(torso, Vector3(0.1 * side, 0.46, 0.105), Vector3(0.1, 0.07, 0.07), jacket_c.lightened(0.1), Vector3(0, 0, 0.5 * side))
		_blk(torso, Vector3(0, 0.1, 0.1), Vector3(0.3 * body_w, 0.03, 0.02), jacket_c.darkened(0.25))
	if style == "terno":
		_blk(torso, Vector3(0, 0.3, 0.126), Vector3(0.04, 0.34, 0.012), Color("#8a1f2c"))
	if style == "social":
		_blk(torso, Vector3(0, 0.46, 0.118), Vector3(0.12, 0.05, 0.04), c1.lightened(0.1))
		for i in 5:
			_ball(torso, Vector3(0, 0.45 - i * 0.075, 0.122), Vector3.ONE * 0.016, Color("#cfcabb"))
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
		_seg(arm, Vector3.ZERO, 0.3, 0.06, 0.047, skin)
		var sleeve_len: float = 0.3 if long_sleeve else (0.19 if not sleeveless else 0.0)
		if sleeve_len > 0.0:
			_seg(arm, Vector3.ZERO, sleeve_len, 0.067, 0.056 if sleeve_len > 0.25 else 0.062, up_c)
		_ball(arm, Vector3(0, -0.3, 0), Vector3.ONE * 0.09, up_c if long_sleeve else skin)
		var fore := _pivot(arm, Vector3(0, -0.3, 0))
		_seg(fore, Vector3.ZERO, 0.27, 0.046, 0.034, (jacket_c if jacket else c1) if long_sleeve else skin)
		if long_sleeve:
			_blk(fore, Vector3(0, -0.25, 0), Vector3(0.075, 0.03, 0.075), (jacket_c if jacket else c1).darkened(0.2))
		_ball(fore, Vector3(0, -0.31, 0.01), Vector3(0.075, 0.1, 0.055), skin)
		_ball(fore, Vector3(0.012 * -side, -0.28, 0.035), Vector3(0.03, 0.05, 0.03), skin)
		if side < 0:
			arm_l = arm
			fore_l = fore
		else:
			arm_r = arm
			fore_r = fore
	# ----- pescoço e cabeça -----
	var nk: float = float(look.get("neck", 1.0))
	_seg(torso, Vector3(0, 0.55, 0), 0.12, 0.052 * nk, 0.056 * nk, skin.darkened(0.04))
	head = _pivot(torso, Vector3(0, 0.79, 0))
	head.scale = Vector3.ONE * 1.2
	var hw: float = 0.205 * clampf(float(look.get("face_w", 1.0)), 0.9, 1.15)
	var hl: float = 0.255 * clampf(float(look.get("face_len", 1.0)), 0.9, 1.12)
	_ball(head, Vector3.ZERO, Vector3(hw, hl, 0.235), skin)
	var jaw: float = clampf(float(look.get("jaw", 0.8)), 0.55, 0.98)
	_ball(head, Vector3(0, -0.075, 0.02), Vector3(hw * (0.78 + jaw * 0.2), hl * 0.55, 0.205), skin)
	for side in [-1, 1]:
		_ball(head, Vector3(side * hw * 0.5, 0, 0), Vector3(0.04, 0.075, 0.05), skin.darkened(0.06))
	var eye_c: Color = look.get("eye_color", Color("#3a2a20"))
	for side in [-1, 1]:
		_dot(head, Vector3(side * 0.052, 0.015, 0.108), Vector3(0.05, 0.034, 0.025), Color("#f4f0e8"))
		_dot(head, Vector3(side * 0.052, 0.015, 0.119), Vector3(0.027, 0.03, 0.014), eye_c.darkened(0.55))
		_dot(head, Vector3(side * 0.054, 0.062, 0.112), Vector3(0.062, 0.013 if female else 0.02, 0.014), hair_c.darkened(0.25), Vector3(0, 0, side * (-0.14 if female else 0.1)))
	_ball(head, Vector3(0, -0.02, 0.118), Vector3(0.036, 0.075, 0.05), skin.darkened(0.07), Vector3(-0.25, 0, 0))
	var lip: Color = look.get("lip_color", skin.darkened(0.25))
	_dot(head, Vector3(0, -0.082, 0.108), Vector3(0.07, 0.016, 0.02), lip.darkened(0.12))
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
	_hair(str(look.get("hair", "curto")), hair_c, hw, hl, female)
	for ex in look.get("extras", []):
		var e := str(ex)
		if "culos" in e:
			for side in [-1, 1]:
				_ball(head, Vector3(side * 0.052, 0.015, 0.125), Vector3(0.062, 0.05, 0.012), Color(0.1, 0.1, 0.12))
			_blk(head, Vector3(0, 0.025, 0.126), Vector3(0.05, 0.01, 0.01), Color(0.1, 0.1, 0.12))
		if "bon" in e:
			_ball(head, Vector3(0, 0.07, -0.01), Vector3(hw * 1.12, hl * 0.62, 0.26), c1.darkened(0.2))
			_blk(head, Vector3(0, 0.06, 0.15), Vector3(0.2, 0.018, 0.13), c1.darkened(0.3))
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
	set_emotion(emotion)


func _hair(style: String, c: Color, hw: float, hl: float, female: bool) -> void:
	if style == "careca":
		return
	var cap := Vector3(hw * 1.08, hl * 0.7, 0.26)
	var skin_c: Color = look.get("skin", Color.WHITE)
	match style:
		"raspado":
			_ball(head, Vector3(0, 0.04, -0.008), Vector3(hw * 1.03, hl * 0.66, 0.245), c.lerp(skin_c, 0.5))
		"moicano":
			_ball(head, Vector3(0, 0.04, -0.008), Vector3(hw * 1.03, hl * 0.66, 0.245), c.lerp(skin_c, 0.6))
			_blk(head, Vector3(0, 0.15, -0.02), Vector3(0.055, 0.11, 0.25), c)
		"black_power", "cacheado":
			var big: float = 1.55 if style == "black_power" else 1.28
			_ball(head, Vector3(0, 0.08, -0.03), Vector3(hw * big * 1.1, hl * big * 0.9, 0.25 * big), c)
		_:
			_ball(head, Vector3(0, 0.06, -0.015), cap, c)
			_ball(head, Vector3(0, 0.01, -0.07), Vector3(hw * 1.06, hl * 0.95, 0.17), c)
			if style in ["franja", "desgrenhado", "curto", "medio", "longo"]:
				_blk(head, Vector3(0.02, 0.095, 0.095), Vector3(hw * 0.95, 0.055, 0.06), c.lightened(0.04), Vector3(0.35, 0, 0.08))
			if style in ["medio", "longo", "trancas", "dreads"]:
				var drop: float = 0.46 if style in ["longo", "trancas", "dreads"] else 0.22
				_blk(head, Vector3(0, -drop / 2.0 + 0.03, -0.08), Vector3(hw * 1.06, drop, 0.13), c)
				if female or style == "longo":
					for side in [-1, 1]:
						_blk(head, Vector3(side * hw * 0.5, -0.1, 0.0), Vector3(0.06, 0.32 if style == "longo" else 0.18, 0.13), c)
			if style in ["trancas", "dreads"]:
				for i in 7:
					_seg(head, Vector3(-0.1 + i * 0.033, -0.04, -0.12), 0.34, 0.022, 0.014, c.darkened(0.08))
			if style == "coque":
				_ball(head, Vector3(0, 0.17, -0.1), Vector3(0.14, 0.12, 0.14), c)
			if style == "rabo":
				_seg(head, Vector3(0, 0.0, -0.17), 0.3, 0.05, 0.025, c)


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
	# passada proporcional à velocidade real
	var spd: float = move_speed if walking else 0.0
	gait = lerpf(gait, clampf(spd / 1.2, 0.0, 1.0), minf(delta * 8.0, 1.0))
	var amp: float = clampf(spd / 3.6, 0.35, 1.7) * 0.5
	if gait > 0.02:
		phase += delta * (3.4 + spd * 0.95)
	var p := phase
	var s := sin(p)
	var c := cos(p)
	var s2 := sin(p + PI)
	var c2 := cos(p + PI)
	# pernas: coxa vai à frente (rotação negativa), joelho dobra na fase de balanço
	leg_l.rotation.x = -s * amp * gait
	leg_r.rotation.x = -s2 * amp * gait
	shin_l.rotation.x = maxf(0.0, c) * amp * 1.5 * gait + 0.05
	shin_r.rotation.x = maxf(0.0, c2) * amp * 1.5 * gait + 0.05
	foot_l.rotation.x = -(leg_l.rotation.x + shin_l.rotation.x) * 0.85
	foot_r.rotation.x = -(leg_r.rotation.x + shin_r.rotation.x) * 0.85
	# braços balançam contra as pernas, cotovelo dobrado
	var run_k: float = clampf((spd - 3.6) / 3.0, 0.0, 1.0)
	arm_l.rotation.x = s * amp * 0.9 * gait + (1.0 - gait) * sin(t * 0.9 + seed_n) * 0.03
	arm_r.rotation.x = s2 * amp * 0.9 * gait + (1.0 - gait) * sin(t * 0.9 + seed_n + 1.0) * 0.03
	fore_l.rotation.x = -0.18 - gait * (0.25 + run_k * 0.9) - maxf(0.0, -s) * 0.3 * gait
	fore_r.rotation.x = -0.18 - gait * (0.25 + run_k * 0.9) - maxf(0.0, -s2) * 0.3 * gait
	arm_l.rotation.z = -0.07 - gait * 0.03
	arm_r.rotation.z = 0.07 + gait * 0.03
	# corpo: sobe e desce duas vezes por ciclo, torce, inclina
	var breath := sin(t * 1.7 + seed_n) * 0.012
	hips.position.y = base_y + gait * (cos(2.0 * p) * 0.022 - 0.012 - run_k * 0.03) + breath * 0.3 * (1.0 - gait)
	hips.rotation.y = -s * 0.1 * gait
	hips.rotation.z = s * 0.035 * gait + sin(t * 0.45 + seed_n) * 0.03 * (1.0 - gait)
	torso.rotation.y = s * 0.16 * gait
	torso.rotation.x = gait * (0.05 + run_k * 0.14)
	torso.rotation.z = -hips.rotation.z * 0.9
	torso.scale = Vector3(1.0 + breath * 0.5, 1.0, 1.0 + breath)
	# cabeça: olha em volta parado, firme andando
	var look_y: float = sin(t * 0.4 + seed_n) * 0.3 + sin(t * 0.9 + seed_n) * 0.1
	head.rotation.y = lerpf(look_y, -torso.rotation.y, gait)
	if talk_left > 0.0:
		head.rotation.x = sin(t * 9.0) * 0.05 + 0.02
		head.rotation.z = sin(t * 2.3) * 0.04
		arm_r.rotation.x = -0.45 + sin(t * 3.1) * 0.25
		fore_r.rotation.x = -1.0 + sin(t * 4.3) * 0.25
		arm_r.rotation.z = 0.25
	else:
		head.rotation.x = lerpf(head.rotation.x, 0.0, minf(delta * 5.0, 1.0))
		head.rotation.z = lerpf(head.rotation.z, 0.0, minf(delta * 5.0, 1.0))
	if bubble and bubble.visible:
		bubble.position.y = 2.3 + sin(t * 2.4) * 0.04
