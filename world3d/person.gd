extends Node3D

# Pessoa com modelo 3D pronto (corpos e cabelos da Quaternius, CC0), animações da Universal
# Animation Library retargetadas para o esqueleto. As roupas são geradas por código a partir da
# própria malha do corpo (camiseta, calça, sapato...), então seguem a animação sem rasgar.
# Mantém a mesma interface do antigo Humanoid (set_look, set_emotion, talk_left, look_target...).

const AnimBank = preload("res://world3d/anim_bank.gd")
const Toon = preload("res://world3d/humanoid.gd")

const BODY := {
	"homem": "res://assets/chars/body/Superhero_Male_FullBody.gltf",
	"mulher": "res://assets/chars/body/Superhero_Female_FullBody.gltf",
}
const SKIN_TEX := {
	"homem": ["res://assets/chars/body/T_Superhero_Male_Ligh.png", "res://assets/chars/body/T_Superhero_Male_Dark.png"],
	"mulher": ["res://assets/chars/body/T_Superhero_Female_Light_BaseColor.png", "res://assets/chars/body/T_Superhero_Female_Dark_BaseColor.png"],
}
const HAIR_FILES := {
	"raspado": "Hair_Buzzed", "curto": "Hair_SimpleParted", "desgrenhado": "Hair_SimpleParted", "franja": "Hair_SimpleParted",
	"medio": "Hair_SimpleParted", "longo": "Hair_Long", "trancas": "Hair_Long", "dreads": "Hair_Long", "cacheado": "Hair_Long",
	"coque": "Hair_Buns", "rabo": "Hair_Long", "moicano": "Hair_Buzzed", "black_power": "Hair_Buns",
}

const EMOTE_TEXT := {
	"feliz": ["♪", Color("#ffe08a")], "rindo": ["haha", Color("#ffe08a")], "triste": ["...", Color("#a9c8ff")],
	"chorando": ["T_T", Color("#a9c8ff")], "irritado": ["#", Color("#ff8a7a")], "furioso": ["!!", Color("#ff5a4a")],
	"desconfiado": ["?", Color("#f1ece0")], "assustado": ["!", Color("#ffffff")], "nervoso": ["~", Color("#bfe3ff")],
	"sarcastico": ["hm", Color("#f1ece0")], "ameacador": ["...", Color("#ff5a4a")], "carinhoso": ["♥", Color("#ff8fb3")],
	"surpreso": ["!?", Color("#fff1b0")], "envergonhado": ["//", Color("#ffb3c8")], "entediado": ["zz", Color("#d0d0d0")],
	"exausto": ["zZ", Color("#c8d0e0")], "machucado": ["ai", Color("#ffd28a")],
}

# receitas de roupa: ossos que contam, limites de altura (y) e de largura (|x|), deslocamento
const RECIPES := {
	"camiseta": {"bones": ["spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r", "pelvis"], "ymin": 0.9, "ymax": 1.66, "xmax": 0.47, "off": 0.011},
	"manga_longa": {"bones": ["spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "pelvis"], "ymin": 0.88, "ymax": 1.66, "xmax": 0.7, "off": 0.013},
	"jaqueta": {"bones": ["spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "pelvis"], "ymin": 0.8, "ymax": 1.66, "xmax": 0.7, "off": 0.02},
	"regata": {"bones": ["spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "pelvis"], "ymin": 0.9, "ymax": 1.6, "xmax": 0.3, "off": 0.009},
	"calca": {"bones": ["pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r"], "ymin": 0.1, "ymax": 1.0, "xmax": 9.0, "off": 0.009},
	"bermuda": {"bones": ["pelvis", "thigh_l", "thigh_r"], "ymin": 0.55, "ymax": 1.0, "xmax": 9.0, "off": 0.009},
	"sapato": {"bones": ["foot_l", "foot_r", "ball_l", "ball_r", "calf_l", "calf_r"], "ymin": -1.0, "ymax": 0.13, "xmax": 9.0, "off": 0.014},
}
const STYLE_TOP := {
	"camiseta": "camiseta", "time": "camiseta", "academia": "camiseta", "rasgada": "camiseta", "havaiana": "camiseta", "blusa": "camiseta",
	"uniforme": "camiseta", "avental": "camiseta", "macacao": "camiseta", "moletom": "manga_longa", "social": "manga_longa",
	"farda": "manga_longa", "batina": "jaqueta", "couro": "jaqueta", "terno": "jaqueta", "sobretudo": "jaqueta", "jaleco": "jaqueta",
	"jeans": "jaqueta", "regata": "regata", "vestido": "regata",
}

static var _scenes: Dictionary = {}
static var _cloth_cache: Dictionary = {}
static var _avg: Dictionary = {}
static var _hair_cache: Dictionary = {}
static var _shadow_mat: StandardMaterial3D

var look: Dictionary = {}
var walking: bool = false
var running: bool = false
var move_speed: float = 0.0
var highlight: float = 0.0
var talk_left: float = 0.0
var emotion: String = "neutro"
var lying: bool = false
var look_target: Vector3 = Vector3.INF
var t: float = 0.0
var seed_n: float = 0.0

var model: Node3D
var skel: Skeleton3D
var ap: AnimationPlayer
var body_mi: MeshInstance3D
var bubble: Label3D
var detail: Array = []
var speeds: Dictionary = {}
var _cur_anim: String = ""
var _prev_pos: Vector3 = Vector3.INF
var _speed: float = 0.0
var _lod_near: bool = true
var _head: int = -1
var _neck: int = -1
var _yaw: float = 0.0
var _pitch: float = 0.0
var _idle_t: float = 0.0
var _dead_played: bool = false


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


static func _avg_color(path: String) -> Color:
	if _avg.has(path):
		return _avg[path]
	var tex: Texture2D = load(path)
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.resize(8, 8, Image.INTERPOLATE_BILINEAR)
	var sum := Color(0, 0, 0)
	for y in 8:
		for x in 8:
			var c := img.get_pixel(x, y)
			sum += Color(c.r, c.g, c.b)
	var c2 := sum / 64.0
	_avg[path] = c2
	return c2


func set_look(l: Dictionary) -> void:
	look = l
	for c in get_children():
		c.queue_free()
	detail.clear()
	seed_n = float(hash(str(l.get("hair", "")) + str(l.get("age", 0)) + str(l.get("skin", "")))) / 1000.0
	_idle_t = fmod(seed_n, 5.0)
	_cur_anim = ""
	_build()


func _build() -> void:
	var gender: String = "mulher" if str(look.get("gender", "")) == "mulher" else "homem"
	var female: bool = gender == "mulher"
	var age: int = int(look.get("age", 30))
	var skin: Color = look.get("skin", Color("#e8bf9c"))
	var style: String = str(look.get("clothes", "camiseta"))
	var c1: Color = look.get("clothes_color", Color("#4a5260"))
	var c2: Color = look.get("clothes_color2", Color("#dddddd"))
	var hair_c: Color = look.get("hair_color", Color("#2b1d14"))
	if age >= 62:
		hair_c = hair_c.lerp(Color("#d8d6d0"), 0.8)
	var k: float = 0.95 if female else 1.0
	if age < 16:
		k *= 0.82
	elif age > 65:
		k *= 0.97
	var heft := clampf(float(look.get("face_w", 1.0)), 0.88, 1.2)
	var wk: float = lerpf(0.84, 1.06, (heft - 0.88) / 0.32) if not female else lerpf(0.92, 1.1, (heft - 0.88) / 0.32)
	scale = Vector3(k * wk, k, k * (0.5 + wk * 0.5))
	var body_path: String = BODY[gender]
	model = _scene(body_path).instantiate()
	add_child(model)
	skel = model.get_node("Armature/Skeleton3D")
	for c in skel.get_children():
		if c is MeshInstance3D and str(c.name).to_lower().begins_with("superhero"):
			body_mi = c
	_head = skel.find_bone("Head")
	_neck = skel.find_bone("neck_01")
	# pele
	var tone_path: String = SKIN_TEX[gender][0] if skin.get_luminance() > 0.36 else SKIN_TEX[gender][1]
	var avg := _avg_color(tone_path)
	var base := body_mi.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	base.albedo_texture = load(tone_path)
	base.albedo_color = Color(clampf(skin.r / maxf(avg.r, 0.05), 0.3, 1.5), clampf(skin.g / maxf(avg.g, 0.05), 0.3, 1.5), clampf(skin.b / maxf(avg.b, 0.05), 0.3, 1.5))
	base.roughness = 0.75
	base.emission_enabled = true
	base.emission = skin * 0.16
	body_mi.material_override = base
	# sobrancelhas
	var brow := skel.get_node_or_null("Eyebrows") as MeshInstance3D
	if brow != null:
		var bm := brow.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
		bm.albedo_texture = null
		bm.albedo_color = (look.get("brow_color", hair_c) as Color).darkened(0.1)
		brow.material_override = bm
	# cabelo e barba
	var hstyle: String = str(look.get("hair", "curto"))
	if hstyle != "careca":
		var key: String = HAIR_FILES.get(hstyle, "Hair_SimpleParted")
		if female and key == "Hair_Buzzed":
			key = "Hair_BuzzedFemale"
		_attach_hair(key, hair_c)
	var beard: String = str(look.get("beard", "none"))
	if beard != "none" and not female:
		_attach_hair("Hair_Beard", hair_c.darkened(0.1) if beard != "stubble" else skin.darkened(0.3))
	# roupas
	_dress(style, c1, c2, female, skin)
	# sombra de contato
	var blob := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.27
	cm.bottom_radius = 0.27
	cm.height = 0.01
	cm.radial_segments = 20
	if _shadow_mat == null:
		_shadow_mat = StandardMaterial3D.new()
		_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_mat.albedo_color = Color(0, 0, 0, 0.18)
		_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.material = _shadow_mat
	blob.mesh = cm
	blob.position = Vector3(0, 0.01, 0)
	add_child(blob)
	# animações
	var bank := AnimBank.bank_for(body_path, skel)
	speeds = bank["speed"]
	ap = AnimationPlayer.new()
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	model.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library("", bank["lib"])
	bubble = Label3D.new()
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.no_depth_test = true
	bubble.font_size = 64
	bubble.pixel_size = 0.006
	bubble.outline_size = 16
	bubble.outline_modulate = Color(0.07, 0.05, 0.05)
	bubble.position = Vector3(0, 2.2, 0)
	bubble.visible = false
	add_child(bubble)
	set_emotion(emotion)
	_play("Idle", 0.0)
	ap.advance(randf() * 2.0)


func _attach_hair(key: String, color: Color) -> void:
	var path := "res://assets/chars/hair/%s.gltf" % key
	var inst: Node = _scene(path).instantiate()
	var mi := inst.find_child("*", true, false)
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		mi = c
	var par := mi.get_parent()
	par.remove_child(mi)
	mi.owner = null
	skel.add_child(mi)
	(mi as MeshInstance3D).skeleton = NodePath("..")
	inst.queue_free()
	var m := (mi as MeshInstance3D).mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	m.albedo_color = color
	m.albedo_texture = null
	m.roughness = 0.6
	(mi as MeshInstance3D).material_override = m


# ---------- roupas ----------

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


func _dress(style: String, c1: Color, c2: Color, female: bool, skin: Color) -> void:
	var top_id: String = STYLE_TOP.get(style, "camiseta")
	var top_col: Color = c1
	if style == "jeans":
		top_col = c1
	if style == "jaleco":
		top_col = c2
	_add_cloth(top_id, top_col, 0.85)
	if style != "vestido":
		_add_cloth("bermuda" if style in ["academia", "havaiana"] else "calca", _pants_color(style, c1, c2), 0.9)
	else:
		_add_skirt(c1)
	var shoe := Color("#252220")
	if style in ["academia", "time"]:
		shoe = Color("#e9e6e0")
	elif style == "havaiana":
		shoe = Color("#c9712c")
	elif style in ["couro", "social", "terno", "farda", "batina", "uniforme"]:
		shoe = Color("#18120f")
	_add_cloth("sapato", shoe, 0.7)


func _bind_names() -> Array:
	var out: Array = []
	var sk := body_mi.skin
	for i in sk.get_bind_count():
		var n := String(sk.get_bind_name(i))
		if n == "":
			n = skel.get_bone_name(sk.get_bind_bone(i))
		out.append(n)
	return out


func _add_cloth(recipe_id: String, color: Color, rough: float) -> void:
	var gender: String = "mulher" if str(look.get("gender", "")) == "mulher" else "homem"
	var key := gender + "_" + recipe_id
	if not _cloth_cache.has(key):
		_cloth_cache[key] = _make_cloth_mesh(RECIPES[recipe_id])
	var mesh: ArrayMesh = _cloth_cache[key]
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.emission_enabled = true
	m.emission = color * 0.16
	mi.material_override = m
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = body_mi.skin


func _make_cloth_mesh(rc: Dictionary) -> ArrayMesh:
	var src: ArrayMesh = body_mi.mesh
	var arr := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var per := bones.size() / maxi(verts.size(), 1)
	var names := _bind_names()
	var want: Dictionary = {}
	for b in rc["bones"]:
		want[b] = true
	var ok := PackedByteArray()
	ok.resize(verts.size())
	var ymin: float = rc["ymin"]
	var ymax: float = rc["ymax"]
	var xmax: float = rc["xmax"]
	for v in verts.size():
		var p := verts[v]
		if p.y < ymin or p.y > ymax or absf(p.x) > xmax:
			continue
		var sum := 0.0
		for kk in per:
			if want.has(names[bones[v * per + kk]]):
				sum += weights[v * per + kk]
		if sum >= 0.5:
			ok[v] = 1
	var new_idx := PackedInt32Array()
	for ti in range(0, idx.size(), 3):
		if ok[idx[ti]] == 1 and ok[idx[ti + 1]] == 1 and ok[idx[ti + 2]] == 1:
			new_idx.append(idx[ti])
			new_idx.append(idx[ti + 1])
			new_idx.append(idx[ti + 2])
	if new_idx.is_empty():
		return null
	var off: float = rc["off"]
	var nv := PackedVector3Array()
	nv.resize(verts.size())
	for v in verts.size():
		nv[v] = verts[v] + norms[v] * off
	var na: Array = []
	na.resize(Mesh.ARRAY_MAX)
	na[Mesh.ARRAY_VERTEX] = nv
	na[Mesh.ARRAY_NORMAL] = norms
	na[Mesh.ARRAY_TEX_UV] = arr[Mesh.ARRAY_TEX_UV]
	na[Mesh.ARRAY_BONES] = bones
	na[Mesh.ARRAY_WEIGHTS] = weights
	na[Mesh.ARRAY_INDEX] = new_idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na)
	return out


func _add_skirt(color: Color) -> void:
	var att := BoneAttachment3D.new()
	att.bone_name = "pelvis"
	skel.add_child(att)
	var sk := CylinderMesh.new()
	sk.top_radius = 0.2
	sk.bottom_radius = 0.4
	sk.height = 0.58
	sk.radial_segments = 20
	var mi := MeshInstance3D.new()
	mi.mesh = sk
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	mi.position = Vector3(0, -0.24, 0)
	mi.scale = Vector3(1.0, 1.0, 0.95)
	att.add_child(mi)


# ---------- interface ----------

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


func set_active(on: bool) -> void:
	if visible != on:
		visible = on
	set_process(on)


func set_lod(near: bool) -> void:
	_lod_near = near


func _play(name: String, blend: float = 0.25) -> void:
	if name == _cur_anim or ap == null or not ap.has_animation(name):
		return
	_cur_anim = name
	ap.play(name, blend)


func _process(delta: float) -> void:
	if skel == null or ap == null:
		return
	t += delta
	talk_left = maxf(0.0, talk_left - delta)
	var gp := global_position
	if _prev_pos == Vector3.INF:
		_prev_pos = gp
	var vel := (gp - _prev_pos) / maxf(delta, 0.0001)
	_prev_pos = gp
	if vel.length() < 14.0:
		_speed = lerpf(_speed, vel.length(), minf(delta * 8.0, 1.0))
	else:
		_speed = 0.0
	if lying:
		_play("Death01", 0.2)
		ap.speed_scale = 1.0
		ap.advance(delta)
		return
	var spd := _speed
	var anim := "Idle"
	var scale_k := 1.0
	if spd > 0.35:
		var walk_v: float = float(speeds.get("Walk", 1.4))
		var jog_v: float = float(speeds.get("Jog_Fwd", 3.0))
		var run_v: float = float(speeds.get("Sprint", 5.0))
		if spd < (walk_v + jog_v) * 0.55:
			anim = "Walk"
			scale_k = spd / walk_v
		elif spd < (jog_v + run_v) * 0.55:
			anim = "Jog_Fwd"
			scale_k = spd / jog_v
		else:
			anim = "Sprint"
			scale_k = spd / run_v
		scale_k = clampf(scale_k, 0.55, 1.7)
	elif talk_left > 0.0:
		anim = "Idle_Talking"
	_play(anim, 0.22)
	ap.speed_scale = scale_k
	ap.advance(delta)
	_apply_look(delta)
	if bubble and bubble.visible:
		bubble.position.y = 2.2 + sin(t * 2.4) * 0.04


# Cabeça e pescoço seguem o alvo do olhar por cima da animação.
func _apply_look(delta: float) -> void:
	if _head < 0 or look_target == Vector3.INF:
		_yaw = lerpf(_yaw, 0.0, minf(delta * 4.0, 1.0))
		_pitch = lerpf(_pitch, 0.0, minf(delta * 4.0, 1.0))
		if absf(_yaw) < 0.01 and absf(_pitch) < 0.01:
			return
	else:
		var lp := to_local(look_target)
		var want_y := clampf(atan2(lp.x, lp.z), -1.1, 1.1)
		var want_p := clampf(-atan2(lp.y - 1.55, maxf(Vector2(lp.x, lp.z).length(), 0.1)), -0.35, 0.35)
		_yaw = lerpf(_yaw, want_y, minf(delta * 6.0, 1.0))
		_pitch = lerpf(_pitch, want_p, minf(delta * 6.0, 1.0))
	for pair in [[_neck, 0.4], [_head, 0.6]]:
		var bi: int = pair[0]
		var w: float = pair[1]
		var par := skel.get_bone_parent(bi)
		var pg: Transform3D = skel.get_bone_global_pose(par)
		var cg: Transform3D = skel.get_bone_global_pose(bi)
		var rot := Basis(Vector3.UP, _yaw * w) * Basis(Vector3.RIGHT, _pitch * w)
		var local := pg.basis.inverse() * rot * cg.basis
		skel.set_bone_pose_rotation(bi, local.get_rotation_quaternion())
