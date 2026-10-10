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
	# off = folga (afastamento do corpo); loose = caimento extra que cresce para baixo da peça
	"camiseta": {"bones": ["spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r", "pelvis"], "ymin": 0.97, "ymax": 1.66, "xmax": 0.47, "off": 0.016, "loose": 0.014},
	"manga_longa": {"bones": ["spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "pelvis"], "ymin": 0.96, "ymax": 1.66, "xmax": 0.7, "off": 0.018, "loose": 0.016},
	"jaqueta": {"bones": ["spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "pelvis"], "ymin": 0.8, "ymax": 1.66, "xmax": 0.7, "off": 0.028, "loose": 0.024},
	"regata": {"bones": ["spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "pelvis"], "ymin": 0.97, "ymax": 1.6, "xmax": 0.3, "off": 0.013, "loose": 0.01},
	"calca": {"bones": ["pelvis", "spine_01", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r"], "ymin": 0.1, "ymax": 1.06, "xmax": 9.0, "off": 0.014, "loose": 0.008},
	"bermuda": {"bones": ["pelvis", "spine_01", "thigh_l", "thigh_r"], "ymin": 0.55, "ymax": 1.06, "xmax": 9.0, "off": 0.014, "loose": 0.012},
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
static var _blob_mesh: ArrayMesh
static var _shaped: Dictionary = {}

# Forma do corpo sobre a malha base "Superhero" (esqueleto, pesos e animações não mudam; só as
# posições dos vértices). O modelo original é um super-herói esculpido; aqui cada gênero e cada
# faixa de idade ganha proporções de gente comum e cada tipo físico (magro, médio, atlético,
# forte, acima do peso, obeso, esquelético) muda braços, pernas, tronco, barriga e pescoço.
# Chaves: arm/forearm/thigh/calf/hand/neck = escala em volta do eixo do osso (1 = igual ao modelo);
# chest_x/chest_z/waist_x/hip_x = largura e profundidade do tronco; belly = barriga (metros);
# shoulder_in = ombros mais estreitos (metros); smooth = quanto aplainar os músculos esculpidos.
const SHAPE := {
	"homem": {"arm": 0.66, "forearm": 0.78, "thigh": 0.78, "calf": 0.84, "hand": 0.95, "neck": 0.88, "chest_x": 0.84, "chest_z": 0.84, "waist_x": 1.0, "hip_x": 0.96, "belly": 0.0, "shoulder_in": 0.03, "smooth": 0.65},
	"mulher": {"arm": 0.7, "forearm": 0.8, "thigh": 0.84, "calf": 0.84, "hand": 0.9, "neck": 0.82, "chest_x": 0.82, "chest_z": 0.8, "waist_x": 0.88, "hip_x": 1.06, "belly": 0.0, "shoulder_in": 0.05, "smooth": 0.65},
	# criança e adolescente: peito reto, braços finos, quadril estreito (o modelo base é de adulto)
	"homem_crianca": {"arm": 0.66, "forearm": 0.76, "thigh": 0.78, "calf": 0.84, "hand": 0.9, "neck": 0.88, "chest_x": 0.84, "chest_z": 0.76, "waist_x": 1.0, "hip_x": 0.92, "belly": 0.0, "shoulder_in": 0.035, "smooth": 0.9},
	"mulher_crianca": {"arm": 0.68, "forearm": 0.78, "thigh": 0.8, "calf": 0.84, "hand": 0.88, "neck": 0.85, "chest_x": 0.84, "chest_z": 0.6, "waist_x": 1.02, "hip_x": 0.9, "belly": 0.0, "shoulder_in": 0.04, "smooth": 0.95},
	"homem_adolescente": {"arm": 0.7, "forearm": 0.8, "thigh": 0.84, "calf": 0.88, "hand": 0.93, "neck": 0.88, "chest_x": 0.86, "chest_z": 0.84, "waist_x": 1.0, "hip_x": 0.95, "belly": 0.0, "shoulder_in": 0.03, "smooth": 0.7},
	"mulher_adolescente": {"arm": 0.72, "forearm": 0.82, "thigh": 0.86, "calf": 0.88, "hand": 0.9, "neck": 0.84, "chest_x": 0.86, "chest_z": 0.72, "waist_x": 0.94, "hip_x": 1.0, "belly": 0.0, "shoulder_in": 0.04, "smooth": 0.7},
}
# Tipo físico (índice "corpo" da criação): multiplicadores sobre a forma do gênero e da idade.
const BODY_TYPES := [
	{"nome": "magro", "arm": 0.86, "forearm": 0.9, "thigh": 0.86, "calf": 0.9, "neck": 0.92, "chest_x": 0.93, "chest_z": 0.92, "waist_x": 0.92, "hip_x": 0.95, "belly": 0.0, "sh": 1.1, "smooth": 0.1},
	{"nome": "médio", "arm": 1.0, "forearm": 1.0, "thigh": 1.0, "calf": 1.0, "neck": 1.0, "chest_x": 1.0, "chest_z": 1.0, "waist_x": 1.0, "hip_x": 1.0, "belly": 0.012, "sh": 1.0, "smooth": 0.0},
	{"nome": "atlético", "arm": 1.12, "forearm": 1.06, "thigh": 1.08, "calf": 1.05, "neck": 1.04, "chest_x": 1.05, "chest_z": 1.04, "waist_x": 0.95, "hip_x": 1.0, "belly": 0.0, "sh": 0.9, "smooth": -0.15},
	{"nome": "forte", "arm": 1.32, "forearm": 1.16, "thigh": 1.2, "calf": 1.1, "neck": 1.14, "chest_x": 1.12, "chest_z": 1.14, "waist_x": 1.02, "hip_x": 1.02, "belly": 0.0, "sh": 0.6, "smooth": -0.4},
	{"nome": "acima do peso", "arm": 1.28, "forearm": 1.08, "thigh": 1.18, "calf": 1.08, "neck": 1.12, "chest_x": 1.12, "chest_z": 1.16, "waist_x": 1.1, "hip_x": 1.07, "belly": 0.05, "sh": 0.8, "smooth": 0.3},
	{"nome": "obeso", "arm": 1.5, "forearm": 1.14, "thigh": 1.3, "calf": 1.14, "neck": 1.22, "chest_x": 1.2, "chest_z": 1.28, "waist_x": 1.16, "hip_x": 1.06, "belly": 0.095, "sh": 0.55, "smooth": 0.5},
	{"nome": "esquelético", "arm": 0.72, "forearm": 0.78, "thigh": 0.74, "calf": 0.8, "neck": 0.84, "chest_x": 0.88, "chest_z": 0.8, "waist_x": 0.84, "hip_x": 0.9, "belly": 0.0, "sh": 1.3, "smooth": 0.0},
]


# Forma final = base do gênero/idade × tipo físico (criança e adolescente sentem menos o tipo).
static func _shape_for(gender: String, stage: String, btype: int) -> Dictionary:
	var key := gender if stage == "" else gender + "_" + stage
	var base: Dictionary = SHAPE.get(key, SHAPE["homem"])
	var t: Dictionary = BODY_TYPES[clampi(btype, 0, BODY_TYPES.size() - 1)]
	var strength := 1.0 if stage == "" else (0.45 if stage == "crianca" else 0.75)
	var out := base.duplicate()
	for k in ["arm", "forearm", "thigh", "calf", "neck", "chest_x", "chest_z", "waist_x", "hip_x"]:
		# tipos finos e fortes se afastam mais do médio (1,6× e 1,25×) para a diferença aparecer de longe
		var dev := (float(t[k]) - 1.0) * (1.6 if float(t[k]) < 1.0 else 1.0)
		out[k] = float(base[k]) * (1.0 + dev * strength)
	out["belly"] = float(base["belly"]) + float(t["belly"]) * strength
	out["shoulder_in"] = float(base["shoulder_in"]) * lerpf(1.0, float(t["sh"]), strength)
	out["smooth"] = clampf(float(base["smooth"]) + float(t["smooth"]), 0.0, 1.0)
	return out


# Aplica a forma a todos os vértices do corpo: cada parte se aproxima (ou se afasta) do eixo do
# seu osso pelo peso de pele daquele osso, o tronco ganha barriga e largura, os ombros fecham.
static func _reshape(verts: PackedVector3Array, bones: PackedInt32Array, weights: PackedFloat32Array, per: int, names: Array, joint: Dictionary, sh: Dictionary, axis_z: float) -> void:
	var finger := ["index", "middle", "ring", "pinky", "thumb"]
	var belly: float = float(sh["belly"])
	var yc: float = (float(joint["pelvis"].y) + float(joint["spine_01"].y)) * 0.5 + 0.05
	for v in verts.size():
		var p := verts[v]
		var w := {}
		var arm_w := 0.0
		var hand_w := 0.0
		for kk in per:
			var bn: String = names[bones[v * per + kk]]
			var wt: float = weights[v * per + kk]
			w[bn] = float(w.get(bn, 0.0)) + wt
			if bn.begins_with("clavicle") or bn.begins_with("upperarm") or bn.begins_with("lowerarm") or bn.begins_with("hand"):
				arm_w += wt
			elif bn.get_slice("_", 0) in finger:
				arm_w += wt
				hand_w += wt
			if bn.begins_with("hand"):
				hand_w += wt
		var q := p
		for side in ["l", "r"]:
			var wu: float = w.get("upperarm_" + side, 0.0)
			var wl: float = w.get("lowerarm_" + side, 0.0)
			if wu > 0.0:
				q = _toward_axis(q, joint["upperarm_" + side], joint["lowerarm_" + side], lerpf(1.0, float(sh["arm"]), wu))
			if wl > 0.0:
				q = _toward_axis(q, joint["lowerarm_" + side], joint["hand_" + side], lerpf(1.0, float(sh["forearm"]), wl))
			var wth: float = w.get("thigh_" + side, 0.0)
			var wca: float = w.get("calf_" + side, 0.0)
			if wth > 0.0:
				q = _toward_axis(q, joint["thigh_" + side], joint["calf_" + side], lerpf(1.0, float(sh["thigh"]), wth))
			if wca > 0.0:
				q = _toward_axis(q, joint["calf_" + side], joint["foot_" + side], lerpf(1.0, float(sh["calf"]), wca))
			if hand_w > 0.0 and absf(p.x) > 0.5 and (p.x > 0.0) == (side == "l"):
				var hc: Vector3 = joint["hand_" + side]
				q = hc + (q - hc) * lerpf(1.0, float(sh["hand"]), minf(hand_w, 1.0))
		# pescoço: fino e comprido em vez de pescoço de touro
		var wn: float = w.get("neck_01", 0.0)
		if wn > 0.0:
			var nk: float = lerpf(1.0, float(sh["neck"]), minf(wn, 1.0))
			var nz: float = float(joint["neck_01"].z)
			q = Vector3(q.x * nk, q.y, nz + (q.z - nz) * nk)
		# tronco: largura e profundidade em volta do eixo da coluna
		var wc: float = float(w.get("spine_03", 0.0)) + float(w.get("spine_02", 0.0)) * 0.6
		if wc > 0.0:
			var cw := minf(wc, 1.0)
			q.x *= lerpf(1.0, float(sh["chest_x"]), cw)
			q.z = axis_z + (q.z - axis_z) * lerpf(1.0, float(sh["chest_z"]), cw)
		var ww: float = float(w.get("spine_01", 0.0)) + float(w.get("pelvis", 0.0)) * 0.5
		if ww > 0.0 and p.y > 0.85:
			var wwk := minf(ww, 1.0)
			q.x *= lerpf(1.0, float(sh["waist_x"]), wwk)
		var wh: float = float(w.get("pelvis", 0.0)) + float(w.get("thigh_l", 0.0)) + float(w.get("thigh_r", 0.0))
		if wh > 0.0 and p.y > 0.7:
			q.x *= lerpf(1.0, float(sh["hip_x"]), minf(wh, 1.0))
		# barriga: o abdome vai para a frente e para os lados, mais embaixo do que em cima
		if belly > 0.0:
			var wb: float = minf(1.0, float(w.get("spine_01", 0.0)) + float(w.get("pelvis", 0.0)) * 0.7 + float(w.get("spine_02", 0.0)) * 0.6)
			var dy := (q.y - yc) / 0.2
			var bump := exp(-dy * dy)
			if wb > 0.0 and bump > 0.01:
				var front := clampf((q.z - axis_z) / 0.09, 0.0, 1.0)
				q.x *= 1.0 + belly * 2.0 * bump * wb
				q.z += belly * bump * wb * (0.25 + 0.75 * front)
		# ombros mais estreitos: o braço inteiro desliza para dentro (a articulação quase não sente)
		# só o ombro (clavícula e começo do braço): o deslocamento some antes do cotovelo para os
		# pivôs do antebraço, da mão e dos dedos continuarem no lugar
		var sh_w: float = 0.0
		for side2 in ["l", "r"]:
			sh_w += float(w.get("clavicle_" + side2, 0.0)) + float(w.get("upperarm_" + side2, 0.0))
		if sh_w > 0.0 and float(sh["shoulder_in"]) > 0.0:
			var fall := 1.0 - clampf((absf(p.x) - 0.18) / 0.22, 0.0, 1.0)
			var shift: float = float(sh["shoulder_in"]) * minf(sh_w, 1.0) * fall
			q.x -= signf(q.x) * minf(shift, absf(q.x))
		verts[v] = q


static var _xray_mat: ShaderMaterial
static var _brow_meshes: Dictionary = {}
# Rosto 3D (deformações) e postura por emoção/idade; desligável para medir desempenho
static var face_fx: bool = true

# Rosto 3D: deformações geradas por código sobre a própria malha (o modelo não tem blendshapes).
# Boca: sorriso, boca triste e queixo (fala); olhos: piscar; sobrancelhas: erguer, bravas, tristes.
const FACE_SHAPES := ["sorriso", "boca_triste", "queixo", "piscar"]
const BROW_SHAPES := ["sobr_cima", "sobr_brava", "sobr_triste"]
const FACE_EXPR := {
	"neutro": {},
	"feliz": {"sorriso": 0.8, "sobr_cima": 0.2},
	"rindo": {"sorriso": 1.0, "queixo": 0.55, "sobr_cima": 0.35, "piscar": 0.3},
	"triste": {"boca_triste": 0.8, "sobr_triste": 0.9},
	"chorando": {"boca_triste": 1.0, "sobr_triste": 1.0, "piscar": 0.45, "queixo": 0.2},
	"irritado": {"sobr_brava": 0.8, "boca_triste": 0.35},
	"furioso": {"sobr_brava": 1.0, "boca_triste": 0.5, "queixo": 0.35},
	"desconfiado": {"sobr_brava": 0.45, "piscar": 0.3, "sorriso": 0.1},
	"assustado": {"sobr_cima": 1.0, "sobr_triste": 0.4, "queixo": 0.45},
	"nervoso": {"sobr_triste": 0.6, "boca_triste": 0.3},
	"sarcastico": {"sorriso": 0.45, "sobr_brava": 0.2},
	"ameacador": {"sobr_brava": 0.75, "piscar": 0.2},
	"carinhoso": {"sorriso": 0.6, "sobr_triste": 0.2},
	"surpreso": {"sobr_cima": 1.0, "queixo": 0.6},
	"envergonhado": {"sorriso": 0.3, "sobr_triste": 0.45},
	"entediado": {"piscar": 0.35, "boca_triste": 0.2},
	"exausto": {"piscar": 0.55, "sobr_triste": 0.3, "boca_triste": 0.25},
	"machucado": {"boca_triste": 0.6, "sobr_brava": 0.3, "piscar": 0.25},
}
# Postura por emoção, em graus para a frente: [coluna, pescoço, cabeça]
const POSTURE := {
	"triste": [3.0, 6.0, 8.0], "chorando": [5.0, 8.0, 10.0], "exausto": [7.0, 6.0, 6.0], "entediado": [3.0, 3.0, 4.0],
	"envergonhado": [2.0, 6.0, 12.0], "assustado": [-4.0, -2.0, -2.0], "nervoso": [2.0, 2.0, 3.0], "furioso": [5.0, 2.0, -6.0],
	"irritado": [3.0, 1.0, -3.0], "ameacador": [4.0, 0.0, -5.0], "feliz": [-2.0, -1.0, -3.0], "rindo": [-3.0, -2.0, -6.0],
	"surpreso": [-3.0, -2.0, -4.0], "machucado": [6.0, 4.0, 4.0],
}

# Silhueta vista através das paredes: só desenha onde o corpo está encoberto (teste de
# profundidade invertido), com borda mais forte. Assim nenhum prédio precisa sumir.
const XRAY_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_inverted, depth_draw_never, blend_mix, cull_back, shadows_disabled;
uniform float strength = 1.0;
void fragment() {
	// aproxima ~70 cm da câmera (ortográfica 70–250 m): a roupa por cima da pele e um braço na frente do tronco
	// não acionam a silhueta (antes, com 18 cm, o jogador virava um "fantasma" manchado); só paredes de verdade
	DEPTH = FRAGCOORD.z + 0.004;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = vec3(1.0, 0.86, 0.58);
	ALPHA = (0.22 + 0.5 * rim) * strength;
}
"""

var look: Dictionary = {}
var walking: bool = false
var running: bool = false
var move_speed: float = 0.0
var highlight: float = 0.0
var talk_left: float = 0.0
var emotion: String = "neutro"
var lying: bool = false
var look_target: Vector3 = Vector3.INF
# o que a pessoa está fazendo parada: sentar, conversar, celular, olhar, mexer, pegar, agachar, consertar
var activity: String = ""
# andar mais contido (pessoas mais velhas)
var formal: bool = false
# transição em curso (sentando, levantando): enquanto > 0 a pessoa não sai andando
var busy_t: float = 0.0
var _act_prev: String = ""
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
var _spine: int = -1
var _head_scale: float = 1.0
var _head_vec: Vector3 = Vector3.ONE
var _old: float = 0.0
var _pose_cur: Vector3 = Vector3.ZERO
var _brow_mi: MeshInstance3D
var _face_t: Dictionary = {}
var _face_w: Dictionary = {}
var _blink: float = 0.0
var _next_blink: float = 2.5
var _body_key: String = ""
var _show_bubble: bool = true


static func cleanup() -> void:
	_scenes.clear()
	_cloth_cache.clear()
	_avg.clear()
	_hair_cache.clear()
	_blob_mesh = null
	_xray_mat = null
	_shaped.clear()
	_brow_meshes.clear()
	_umb_canopy = null
	_umb_shaft = null
	_umb_meshes.clear()


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
		if _scenes[path] == null:
			push_warning("Modelo de personagem não encontrado: " + path)
	return _scenes[path]


static func _avg_color(path: String) -> Color:
	if _avg.has(path):
		return _avg[path]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		_avg[path] = Color(0.6, 0.48, 0.4)
		return _avg[path]
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
	var had_umbrella := umbrella_on
	var had_stroller := stroller_on
	umbrella_on = false
	stroller_on = false
	_umbrella = null
	_stroller = null
	_arm_side = 0.0
	_arm_bones = PackedInt32Array()
	seed_n = float(hash(str(l.get("hair", "")) + str(l.get("age", 0)) + str(l.get("skin", "")))) / 1000.0
	_idle_t = fmod(seed_n, 5.0)
	_cur_anim = ""
	_build()
	if had_umbrella:
		set_umbrella(true)
	if had_stroller:
		set_stroller(true)


func _build() -> void:
	var gender: String = "mulher" if str(look.get("gender", "")) == "mulher" else "homem"
	var female: bool = gender == "mulher"
	var age: int = int(look.get("age", 30))
	var skin: Color = look.get("skin", Color("#e8bf9c"))
	var style: String = str(look.get("clothes", "camiseta"))
	var c1: Color = look.get("clothes_color", Color("#4a5260"))
	var c2: Color = look.get("clothes_color2", Color("#dddddd"))
	var hair_c: Color = look.get("hair_color", Color("#2b1d14"))
	# grisalho aos poucos, como no retrato
	hair_c = hair_c.lerp(Color("#cdc8c0"), clampf((float(age) - 50.0) / 32.0, 0.0, 1.0) * 0.75)
	# base de idade: criança bem menor e de cabeça proporcionalmente maior, adolescente quase
	# adulto, idoso um pouco menor e curvado (a curvatura vem em _apply_posture)
	var kid := clampf((14.0 - float(age)) / 8.0, 0.0, 1.0)
	var teen := clampf((19.0 - float(age)) / 6.0, 0.0, 1.0) * (1.0 - kid)
	_old = clampf((float(age) - 55.0) / 30.0, 0.0, 1.0)
	_head_scale = 1.0 + 0.38 * kid + 0.08 * teen
	var k: float = (0.95 if female else 1.0) * lerpf(1.0, 0.64, kid) * lerpf(1.0, 0.93, teen) * (1.0 - 0.03 * _old)
	k *= lerpf(1.0, float(look.get("height", 1.0)), 1.0 - kid * 0.7)
	var h1 := float(absi(hash(str(look.get("hair", "")) + str(look.get("skin", "")) + str(look.get("face_len", 0)))) % 1000) / 1000.0
	var h2 := float(absi(hash(str(look.get("face_w", 0)) + str(look.get("hair_color", "")) + "x")) % 1000) / 1000.0
	var wk: float = lerpf(0.96, 1.04, h1) * lerpf(1.0, 0.9, kid)
	k *= lerpf(0.98, 1.02, h2)
	scale = Vector3(k * wk, k, k * (0.5 + wk * 0.5))
	var body_path: String = BODY[gender]
	var ps := _scene(body_path)
	if ps == null:
		_fallback_body(c1)
		return
	model = ps.instantiate()
	add_child(model)
	skel = model.get_node_or_null("Armature/Skeleton3D") as Skeleton3D
	if skel != null:
		for c in skel.get_children():
			if c is MeshInstance3D and str(c.name).to_lower().begins_with("superhero"):
				body_mi = c
	if skel == null or body_mi == null or body_mi.mesh == null:
		_fallback_body(c1)
		return
	# corpo com proporções de gente comum (mesma malha e esqueleto, ver _shape_body); criança e
	# adolescente têm forma própria
	_body_key = gender + ("_crianca" if age < 13 else ("_adolescente" if age < 18 else "")) + "_t" + str(clampi(int(look.get("body_type", 1)), 0, BODY_TYPES.size() - 1))
	body_mi.mesh = _shaped_body(_body_key)
	_head = skel.find_bone("Head")
	_neck = skel.find_bone("neck_01")
	_spine = skel.find_bone("spine_03")
	# a cabeça ganha a largura e o comprimento do rosto desenhado (mesmos dados do retrato)
	var fw: float = clampf(float(look.get("face_w", 1.0)), 0.8, 1.25)
	var fl: float = clampf(float(look.get("face_len", 1.0)), 0.85, 1.2)
	_head_vec = Vector3(_head_scale * lerpf(1.0, fw, 0.75), _head_scale * lerpf(1.0, fl, 0.7), _head_scale * lerpf(1.0, fw, 0.4))
	if _head >= 0:
		skel.set_bone_pose_scale(_head, _head_vec)
	# pele
	var tone_path: String = SKIN_TEX[gender][0] if skin.get_luminance() > 0.36 else SKIN_TEX[gender][1]
	var avg := _avg_color(tone_path)
	var base := body_mi.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	base.albedo_texture = load(tone_path)
	base.albedo_color = Color(clampf(skin.r / maxf(avg.r, 0.05), 0.3, 1.5), clampf(skin.g / maxf(avg.g, 0.05), 0.3, 1.5), clampf(skin.b / maxf(avg.b, 0.05), 0.3, 1.5))
	base.roughness = 0.75
	_rim(base, 0.36)
	base.emission_enabled = true
	# brilho próprio mínimo: o corpo recebe a luz do mundo (antes 16% achatava o volume)
	base.emission = skin * 0.05
	body_mi.material_override = base
	# sobrancelhas
	var brow := skel.get_node_or_null("Eyebrows") as MeshInstance3D
	if brow != null:
		brow.mesh = _brow_mesh(gender, brow.mesh)
		_brow_mi = brow
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
	var beard_c: Color = look.get("beard_color", hair_c)
	# a malha de barba é cheia: bigodes e costeletas não aparecem de longe e ficam sem malha
	if beard in ["stubble", "goatee", "full", "long", "short"] and not female and age >= 15:
		_attach_hair("Hair_Beard", beard_c.darkened(0.1) if beard != "stubble" else skin.darkened(0.3))
	# roupas
	_dress(style, c1, c2, female, skin)
	_add_blob()
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
	set_emotion(emotion, _show_bubble)
	_play("Idle", 0.0)
	ap.advance(randf() * 2.0)


# Remodela a malha do corpo uma vez por gênero: cada vértice dos braços se aproxima do eixo do
# osso (pelo peso de pele daquele osso), o peito estreita e a cintura alarga um pouco. Como só
# as posições mudam, o esqueleto, os pesos e todas as animações continuam valendo.
func _shaped_body(key: String) -> Mesh:
	var gender := key
	if _shaped.has(key):
		return _shaped[key]
	var src: Mesh = body_mi.mesh
	var sk: Skin = body_mi.skin
	var names := _bind_names()
	var joint := {}
	for i in sk.get_bind_count():
		joint[names[i]] = sk.get_bind_pose(i).affine_inverse().origin
	var need := ["upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r", "thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r", "pelvis", "spine_01", "neck_01"]
	for n in need:
		if not joint.has(n):
			_shaped[key] = src
			return src
	var parts := key.split("_")
	var btype := int(parts[parts.size() - 1].substr(1))
	var stage := "" if parts.size() < 3 else parts[1]
	var sh: Dictionary = _shape_for(parts[0], stage, btype)
	var out := ArrayMesh.new()
	var face := _face_marks(src, names) if face_fx else {}
	if face_fx:
		for fs in FACE_SHAPES:
			out.add_blend_shape(fs)
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		if s == 0:
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(verts.size(), 1)
			var axis_z := (float(joint.get("spine_01", Vector3.ZERO).z) + float(joint.get("spine_02", Vector3.ZERO).z) + float(joint.get("spine_03", Vector3.ZERO).z)) / 3.0
			_reshape(verts, bones, weights, per, names, joint, sh, axis_z)
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			_smooth_torso(verts, bones, weights, per, names, float(sh.get("smooth", 0.0)), axis_z, norms, arr[Mesh.ARRAY_INDEX])
			arr[Mesh.ARRAY_VERTEX] = verts
			arr[Mesh.ARRAY_NORMAL] = norms
		var bs: Array = []
		if face_fx:
			for fs in FACE_SHAPES:
				var shaped: PackedVector3Array = _face_shape(fs, arr, face, names) if s == 0 and not face.is_empty() else arr[Mesh.ARRAY_VERTEX]
				bs.append(_shape_delta(arr, shaped))
		# mesmo formato da superfície original (8 pesos de osso, canais extras), sem compressão
		# para as deformações do rosto
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, bs, {}, src.surface_get_format(s) & ~Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		out.surface_set_material(s, src.surface_get_material(s))
	_shaped[key] = out
	return out


# O modelo base é de super-herói: peitoral, abdome e costas esculpidos. Aqui o relevo do tronco
# é aplainado: em cada faixa de altura e setor ao redor do tronco, o raio do vértice se aproxima
# da média dos vizinhos de cima e de baixo (sem músculos marcados; criança quase lisa).
static func _smooth_torso(verts: PackedVector3Array, bones: PackedInt32Array, weights: PackedFloat32Array, per: int, names: Array, amount: float, axis_z: float, norms: PackedVector3Array, idx: PackedInt32Array) -> void:
	if amount <= 0.0:
		return
	const BAND := 0.02
	const SECT := 24
	var torso := PackedInt32Array()
	var tw := PackedFloat32Array()
	for v in verts.size():
		var wt := 0.0
		var arm := 0.0
		for kk in per:
			var bn: String = names[bones[v * per + kk]]
			var w: float = weights[v * per + kk]
			if bn in ["spine_01", "spine_02", "spine_03"]:
				wt += w
			elif bn == "pelvis":
				wt += w * 0.6
			elif bn.begins_with("upperarm") or bn.begins_with("clavicle") or bn == "neck_01" or bn == "Head":
				arm += w
		if wt > 0.5 and arm < 0.15 and verts[v].y > 0.9:
			torso.append(v)
			tw.append(clampf((wt - 0.5) * 2.5, 0.0, 1.0) * (1.0 - arm * 6.0))
	var wb := 3 + int(amount * 4.0)
	var ws := 1 + int(amount * 1.5)
	var rad := {}
	var polar := []
	for i in torso.size():
		var p := verts[torso[i]]
		var b := int(p.y / BAND)
		var cx := 0.0
		var cz := axis_z
		var a := atan2(p.z - cz, p.x - cx)
		var s := posmod(int(floor((a + PI) / TAU * SECT)), SECT)
		var r := Vector2(p.x - cx, p.z - cz).length()
		var key := b * 100 + s
		var acc: Vector2 = rad.get(key, Vector2.ZERO)
		rad[key] = acc + Vector2(r, 1.0)
		polar.append([b, s, r, cx, cz, a])
	for i in torso.size():
		var pr: Array = polar[i]
		var sum := 0.0
		var n := 0.0
		for db in range(-wb, wb + 1):
			for ds in range(-ws, ws + 1):
				var key: int = (int(pr[0]) + db) * 100 + posmod(int(pr[1]) + ds, SECT)
				if rad.has(key):
					var acc2: Vector2 = rad[key]
					sum += acc2.x
					n += acc2.y
		if n <= 0.0:
			continue
		var target := sum / n
		var r2: float = lerpf(float(pr[2]), target, amount * float(tw[i]))
		var a2: float = pr[5]
		var p2 := verts[torso[i]]
		verts[torso[i]] = Vector3(float(pr[3]) + cos(a2) * r2, p2.y, float(pr[4]) + sin(a2) * r2)
	# normais refeitas pela forma nova (soldando vértices na mesma posição), senão a luz continua
	# desenhando os músculos que a geometria já não tem
	var acc := {}
	for t in range(0, idx.size(), 3):
		var a3 := verts[idx[t]]
		var b3 := verts[idx[t + 1]]
		var c3 := verts[idx[t + 2]]
		var fn := (b3 - a3).cross(c3 - a3)
		for k in 3:
			var key2 := Vector3i((verts[idx[t + k]] * 2000.0).round())
			acc[key2] = acc.get(key2, Vector3.ZERO) + fn
	for i in torso.size():
		var v := torso[i]
		var nn: Vector3 = acc.get(Vector3i((verts[v] * 2000.0).round()), Vector3.ZERO)
		if nn.length_squared() < 1e-12:
			continue
		nn = nn.normalized()
		if nn.dot(norms[v]) < 0.0:
			nn = -nn
		norms[v] = norms[v].lerp(nn, clampf(amount * 1.3, 0.0, 1.0) * float(tw[i])).normalized()


# Blendshape relativo: a posição vai como diferença em relação à base.
static func _shape_delta(arr: Array, shaped: PackedVector3Array) -> Array:
	var base: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var dv := PackedVector3Array()
	dv.resize(base.size())
	for v in base.size():
		dv[v] = shaped[v] - base[v]
	var a: Array = []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = dv
	# normais e tangentes iguais às da base: com elas o relevo da pele continua certo
	a[Mesh.ARRAY_NORMAL] = arr[Mesh.ARRAY_NORMAL]
	if arr[Mesh.ARRAY_TANGENT] != null:
		a[Mesh.ARRAY_TANGENT] = arr[Mesh.ARRAY_TANGENT]
	return a


# Pontos de referência do rosto, medidos na própria malha: ponta do nariz (vértice da cabeça
# mais à frente), centro de cada olho (malha dos olhos), altura da boca e largura dela.
func _face_marks(src: Mesh, names: Array) -> Dictionary:
	var arr := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / maxi(verts.size(), 1)
	var nose := Vector3(0, 0, -99)
	var head_w := PackedFloat32Array()
	head_w.resize(verts.size())
	for v in verts.size():
		var hw := 0.0
		for kk in per:
			if names[bones[v * per + kk]] == "Head":
				hw += weights[v * per + kk]
		head_w[v] = hw
		if hw > 0.5 and verts[v].z > nose.z and absf(verts[v].x) < 0.01:
			nose = verts[v]
	var eyes := skel.get_node_or_null("Eyes") as MeshInstance3D
	if nose.z < -1.0 or eyes == null:
		return {}
	var ev: PackedVector3Array = eyes.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var el := Vector3.ZERO
	var er := Vector3.ZERO
	var nl := 0
	var nr := 0
	var ez := -99.0
	for p in ev:
		if p.x < 0.0:
			el += p
			nl += 1
		else:
			er += p
			nr += 1
		ez = maxf(ez, p.z)
	if nl == 0 or nr == 0:
		return {}
	el /= nl
	er /= nr
	var eye_dx := (er.x - el.x) * 0.5
	return {"nose": nose, "eye_l": Vector3(el.x, el.y, ez), "eye_r": Vector3(er.x, er.y, ez), "mouth_y": nose.y - 0.037,
		"mouth_x": eye_dx * 0.68, "head_w": head_w}


static func _bump(d: Vector2) -> float:
	var r2 := d.length_squared()
	if r2 >= 1.0:
		return 0.0
	return (1.0 - r2) * (1.0 - r2)


func _face_shape(name: String, arr: Array, f: Dictionary, _names: Array) -> PackedVector3Array:
	var verts: PackedVector3Array = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var head_w: PackedFloat32Array = f["head_w"]
	var my: float = f["mouth_y"]
	var mx: float = f["mouth_x"]
	var nose: Vector3 = f["nose"]
	for v in verts.size():
		if head_w[v] < 0.5:
			continue
		var p := verts[v]
		if p.z < nose.z - 0.075:
			continue
		var d := Vector3.ZERO
		match name:
			"sorriso", "boca_triste":
				for side in [-1.0, 1.0]:
					var w := _bump(Vector2((p.x - side * mx) / 0.017, (p.y - my) / 0.013))
					if name == "sorriso":
						d += Vector3(side * 0.003, 0.0062, -0.0014) * w
						d += Vector3(0, 0.0018, 0.0008) * _bump(Vector2((p.x - side * (mx + 0.009)) / 0.016, (p.y - my - 0.017) / 0.014))
					else:
						d += Vector3(-side * 0.0008, -0.004, -0.0005) * w
			"queixo":
				var below := smoothstep(my + 0.001, my - 0.01, p.y)
				var mid := 1.0 - smoothstep(0.022, 0.045, absf(p.x))
				var keep_neck := 1.0 - smoothstep(my - 0.05, my - 0.07, p.y)
				d = Vector3(0, -0.006, -0.0012) * below * mid * keep_neck * smoothstep(nose.z - 0.07, nose.z - 0.03, p.z)
			"piscar":
				for e in [f["eye_l"], f["eye_r"]]:
					var ec: Vector3 = e
					var dx := absf(p.x - ec.x) / 0.02
					if dx >= 1.0 or p.z < ec.z - 0.014:
						continue
					var fall := 1.0 - dx * dx
					if p.y >= ec.y and p.y < ec.y + 0.016:
						var up := 1.0 - smoothstep(ec.y + 0.006, ec.y + 0.016, p.y)
						d += Vector3(0, (ec.y - 0.0015 - p.y) * up * fall, 0.0018 * up * fall)
					elif p.y < ec.y and p.y > ec.y - 0.012:
						var lo := 1.0 - smoothstep(ec.y - 0.004, ec.y - 0.012, p.y)
						d += Vector3(0, (ec.y - 0.003 - p.y) * 0.35 * lo * fall, 0.0008 * lo * fall)
		verts[v] = p + d
	return verts


# Sobrancelhas (malha própria): erguer, franzir (bravas) e de tristeza (ponta de dentro sobe).
func _brow_mesh(gender: String, src: Mesh) -> Mesh:
	if _brow_meshes.has(gender):
		return _brow_meshes[gender]
	if src == null or src.get_blend_shape_count() > 0 or not face_fx:
		return src
	var out := ArrayMesh.new()
	for bsn in BROW_SHAPES:
		out.add_blend_shape(bsn)
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var base: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bs: Array = []
		for bsn in BROW_SHAPES:
			var nv := base.duplicate()
			for v in nv.size():
				var p := nv[v]
				var inner := 1.0 - smoothstep(0.012, 0.04, absf(p.x))
				var outer := smoothstep(0.03, 0.06, absf(p.x))
				match bsn:
					"sobr_cima":
						nv[v] = p + Vector3(0, 0.004 + 0.001 * inner, 0.0005)
					"sobr_brava":
						nv[v] = p + Vector3(-signf(p.x) * 0.0015 * inner, -0.0035 * inner + 0.0008 * outer, 0.0004 * inner)
					"sobr_triste":
						nv[v] = p + Vector3(0, 0.004 * inner - 0.0012 * outer, 0)
			bs.append(_shape_delta(arr, nv))
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, bs, {}, src.surface_get_format(s) & ~Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		out.surface_set_material(s, src.surface_get_material(s))
	_brow_meshes[gender] = out
	return out


static func _toward_axis(p: Vector3, a: Vector3, b: Vector3, k: float) -> Vector3:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	var c := a + ab * t
	return c + (p - c) * k


# Contorno de luz (rim): separa a pessoa do fundo à noite e na chuva, sem mudar o modelo.
static func _rim(m: StandardMaterial3D, amount: float) -> void:
	m.rim_enabled = true
	m.rim = amount
	m.rim_tint = 0.6


# Liga a silhueta através das paredes neste personagem (usado no jogador).
# Duplica os materiais para não afetar outras pessoas que compartilham o mesmo material.
func enable_xray() -> void:
	if _xray_mat == null:
		var sh := Shader.new()
		sh.code = XRAY_SHADER
		_xray_mat = ShaderMaterial.new()
		_xray_mat.shader = sh
		_xray_mat.render_priority = 10
	if skel == null:
		return
	for c in skel.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var m: Material = mi.material_override
		if m == null:
			m = mi.mesh.surface_get_material(0)
		if m == null or not (m is BaseMaterial3D):
			continue
		var dup := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
		dup.next_pass = _xray_mat
		mi.material_override = dup


# Desliga a silhueta quando algo cobre o corpo de propósito (coberta na cama, mesa, box do banho).
static func set_xray_strength(v: float) -> void:
	if _xray_mat != null:
		_xray_mat.set_shader_parameter("strength", v)


# Sombra de contato macia sob os pés (centro escuro, borda que some): a pessoa pisa no chão.
func _add_blob() -> void:
	if _blob_mesh == null:
		var k := preload("res://world3d/mesh_kit.gd").new()
		k.disc(Vector3.ZERO, 0.46, 0.4, Color(0.02, 0.02, 0.04, 0.42), 0.0, 18)
		_blob_mesh = k.commit(preload("res://world3d/mesh_kit.gd").shadow_material())
	var blob := MeshInstance3D.new()
	blob.mesh = _blob_mesh
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position = Vector3(0, 0.012, 0)
	add_child(blob)


# Corpo simples caso o modelo 3D não carregue: o jogo segue sem erro.
func _fallback_body(c1: Color) -> void:
	if model != null:
		model.queue_free()
		model = null
	skel = null
	body_mi = null
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.24
	cap.height = 1.7
	var m := StandardMaterial3D.new()
	m.albedo_color = c1
	m.roughness = 0.8
	cap.material = m
	mi.mesh = cap
	mi.position = Vector3(0, 0.85, 0)
	add_child(mi)
	_add_blob()


func _attach_hair(key: String, color: Color) -> void:
	var path := "res://assets/chars/hair/%s.gltf" % key
	var hs := _scene(path)
	if hs == null:
		return
	var inst: Node = hs.instantiate()
	var mi: Node = null
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		mi = c
	if mi == null or (mi as MeshInstance3D).mesh == null:
		inst.queue_free()
		return
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
	_rim(m, 0.35)
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
	var key := _body_key + "_" + recipe_id
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
	m.emission = color * 0.05
	# a malha da roupa traz barras, costuras e dobras na cor do vértice (tom × cor do tecido)
	m.vertex_color_use_as_albedo = true
	if recipe_id == "jaqueta" and str(look.get("clothes", "")) in ["couro", "jeans"]:
		m.roughness = 0.45 if str(look.get("clothes", "")) == "couro" else 0.8
		m.metallic_specular = 0.6 if str(look.get("clothes", "")) == "couro" else 0.3
	else:
		m.metallic_specular = 0.25
	_rim(m, 0.42)
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
	# triângulo de borda (2 dos 3 vértices dentro) entra se o vértice de fora estiver colado no
	# recorte: fecha frestas e entalhes sem esfiapar a barra
	var legs: bool = "thigh_l" in rc["bones"]
	var near := func(v: int) -> bool:
		var q := verts[v]
		if not legs and absf(q.x) > 0.05:
			return false
		return q.y >= ymin - 0.025 and q.y <= ymax + 0.025 and absf(q.x) <= xmax + 0.03
	for ti in range(0, idx.size(), 3):
		var inside := ok[idx[ti]] + ok[idx[ti + 1]] + ok[idx[ti + 2]]
		var take := inside == 3
		if inside == 2:
			for k in 3:
				if ok[idx[ti + k]] == 0:
					take = near.call(idx[ti + k])
		if take:
			new_idx.append(idx[ti])
			new_idx.append(idx[ti + 1])
			new_idx.append(idx[ti + 2])
	if new_idx.is_empty():
		return null
	# Volume: a peça fica afastada do corpo (folga) e solta mais embaixo (caimento), em vez de
	# colada na pele. Cor do vértice: barra e gola mais escuras, dobras suaves nas áreas soltas.
	var off: float = rc["off"]
	var loose: float = rc.get("loose", 0.0)
	# vértices duplicados na costura da malha (mesma posição, normais diferentes) andam juntos;
	# sem isso a roupa abre uma fenda na costura do meio
	var weld := {}
	var weld_p := {}
	for v in verts.size():
		if ok[v] == 0:
			continue
		var key := Vector3i((verts[v] * 450.0).round())
		weld[key] = weld.get(key, Vector3.ZERO) + norms[v]
		weld_p[key] = weld_p.get(key, Vector4.ZERO) + Vector4(verts[v].x, verts[v].y, verts[v].z, 1.0)
	var nv := PackedVector3Array()
	nv.resize(verts.size())
	var cols := PackedColorArray()
	cols.resize(verts.size())
	for v in verts.size():
		var p := verts[v]
		var hang := 0.0
		if loose > 0.0:
			hang = loose * clampf((ymax - p.y) / maxf(ymax - ymin, 0.01), 0.0, 1.0)
		var wk := Vector3i((p * 450.0).round())
		var wn: Vector3 = weld.get(wk, norms[v])
		wn = wn.normalized() if wn.length_squared() > 0.0001 else norms[v]
		var wp: Vector4 = weld_p.get(wk, Vector4(p.x, p.y, p.z, 1.0))
		var base := Vector3(wp.x, wp.y, wp.z) / maxf(wp.w, 1.0)
		var extra := 0.0
		if "thigh_l" in rc["bones"]:
			# virilha: a dobra é côncava e a pele atravessaria o tecido
			extra = 0.016 * smoothstep(0.11, 0.0, absf(base.x)) * smoothstep(0.66, 0.78, base.y) * smoothstep(1.02, 0.92, base.y)
		nv[v] = base + wn * (off + hang + extra)
	# barra e gola mais escuras, pintadas depois de alinhar a borda (senão a faixa segue o zigue-zague)
	var hem := _straighten_hems(nv, new_idx, ymin, ymax, xmax)
	for v in verts.size():
		var p := nv[v]
		var f := 1.0
		var edge := 9.0
		if not is_nan(hem.x):
			edge = p.y - hem.x
		if not is_nan(hem.y):
			edge = minf(edge, hem.y - p.y)
		if edge < 0.03:
			f = 0.76
		elif edge < 0.05:
			f = 0.89
		if loose > 0.0 and p.y < ymax - 0.15:
			# dobras caindo na vertical (faixas horizontais pareciam músculos sob o tecido)
			f *= 0.95 + 0.05 * sin(p.x * 46.0 + p.y * 9.0)
		cols[v] = Color(f, f, f)
	var na: Array = []
	na.resize(Mesh.ARRAY_MAX)
	na[Mesh.ARRAY_VERTEX] = nv
	na[Mesh.ARRAY_NORMAL] = norms
	na[Mesh.ARRAY_COLOR] = cols
	na[Mesh.ARRAY_TEX_UV] = arr[Mesh.ARRAY_TEX_UV]
	na[Mesh.ARRAY_BONES] = bones
	na[Mesh.ARRAY_WEIGHTS] = weights
	na[Mesh.ARRAY_INDEX] = new_idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na)
	return out


# A peça é recortada da malha do corpo triângulo a triângulo, e a borda sai em zigue-zague.
# Aqui as bordas (barra embaixo, gola em cima, punhos nas mangas) viram uma linha reta.
static func _straighten_hems(nv: PackedVector3Array, idx: PackedInt32Array, ymin: float, ymax: float, xmax: float) -> Vector2:
	var count := {}
	for t in range(0, idx.size(), 3):
		for k in 3:
			var a := idx[t + k]
			var b := idx[t + (k + 1) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			count[key] = int(count.get(key, 0)) + 1
	var border := {}
	for key in count:
		if int(count[key]) == 1:
			border[key.x] = true
			border[key.y] = true
	# vizinhos de borda: suaviza o contorno (tira o zigue-zague mantendo a curva da gola e da cava)
	# vértices da costura (mesma posição) são o mesmo ponto: a borda continua sem entalhe
	var same := {}
	for v in border:
		var pk := Vector3i((nv[v] * 450.0).round())
		if not same.has(pk):
			same[pk] = []
		same[pk].append(v)
	var rep_of := {}
	for pk in same:
		for v in same[pk]:
			rep_of[v] = same[pk][0]
	var nbr := {}
	for key in count:
		if int(count[key]) == 1:
			var ra: int = rep_of.get(key.x, key.x)
			var rb: int = rep_of.get(key.y, key.y)
			if ra == rb:
				continue
			if not nbr.has(ra):
				nbr[ra] = []
			if not nbr.has(rb):
				nbr[rb] = []
			if not rb in nbr[ra]:
				nbr[ra].append(rb)
			if not ra in nbr[rb]:
				nbr[rb].append(ra)
	for it in 5:
		var moved := {}
		for v in nbr:
			var ns: Array = nbr[v]
			if ns.size() < 2:
				continue
			var acc := Vector3.ZERO
			for o in ns:
				acc += nv[o]
			moved[v] = nv[v].lerp(acc / ns.size(), 0.5)
		for v in moved:
			nv[v] = moved[v]
	for pk in same:
		var r0: int = same[pk][0]
		for v in same[pk]:
			nv[v] = nv[r0]
	var groups := {"baixo": [], "cima": [], "punho_l": [], "punho_r": []}
	for v in border:
		var p := nv[v]
		if p.y < ymin + 0.12:
			groups["baixo"].append(v)
		elif p.y > ymax - 0.07 and absf(p.x) < 0.16:
			groups["cima"].append(v)
		elif xmax < 5.0 and absf(p.x) > xmax - 0.07:
			groups["punho_r" if p.x > 0.0 else "punho_l"].append(v)
	var hem := Vector2(NAN, NAN)
	for g in ["baixo", "cima"]:
		var vs: Array = groups[g]
		if vs.size() < 4:
			continue
		var avg := 0.0
		for v in vs:
			avg += nv[v].y
		avg /= vs.size()
		for v in vs:
			var p2 := nv[v]
			nv[v] = Vector3(p2.x, lerpf(p2.y, avg, 0.95 if g == "baixo" else 0.6), p2.z)
		if g == "baixo":
			hem.x = avg
		else:
			hem.y = avg
	for g in ["punho_l", "punho_r"]:
		var vs2: Array = groups[g]
		if vs2.size() < 4:
			continue
		var ax := 0.0
		for v in vs2:
			ax += absf(nv[v].x)
		ax /= vs2.size()
		for v in vs2:
			var p3 := nv[v]
			nv[v] = Vector3(signf(p3.x) * lerpf(absf(p3.x), ax, 0.85), p3.y, p3.z)
	return hem


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

func set_emotion(e: String, show_bubble: bool = true) -> void:
	emotion = e
	_show_bubble = show_bubble
	_face_t = FACE_EXPR.get(e, {})
	if bubble == null:
		return
	if EMOTE_TEXT.has(e) and show_bubble:
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


# Animação de transição tocada até o fim (sentar, levantar); trava o andar durante ela.
func _play_once(name: String) -> void:
	if ap == null or not ap.has_animation(name):
		return
	_cur_anim = name
	ap.play(name, 0.2)
	busy_t = ap.get_animation(name).length * 0.92


const ACT_ANIM := {"dancar": "Dance", "conversar": "Idle", "celular": "Idle", "olhar": "Idle", "mexer": "Interact", "pegar": "PickUp_Table", "agachar": "Crouch_Idle", "consertar": "Fixing_Kneeling"}


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
	# sentar e levantar têm animação de transição própria
	busy_t = maxf(0.0, busy_t - delta)
	if activity != _act_prev:
		if _act_prev == "sentar":
			_play_once("Sitting_Exit")
		elif activity == "sentar":
			_play_once("Sitting_Enter")
		_act_prev = activity
	if busy_t > 0.0:
		ap.speed_scale = 1.0
		ap.advance(delta)
		_apply_posture(delta)
		_apply_hands(delta)
		_apply_look(delta)
		_apply_face(delta)
		return
	var spd := _speed
	var anim := "Idle"
	var scale_k := 1.0
	if activity == "sentar":
		anim = "Sitting_Talking" if talk_left > 0.0 else "Sitting_Idle"
		spd = 0.0
	if spd > 0.35:
		var walk_name := "Walk_Formal" if formal and ap.has_animation("Walk_Formal") else "Walk"
		# a passada encolhe com o corpo (criança dá mais passos para a mesma velocidade)
		var leg := clampf(scale.y, 0.4, 1.2)
		var walk_v: float = float(speeds.get(walk_name, 1.4)) * leg
		var jog_v: float = float(speeds.get("Jog_Fwd", 3.0)) * leg
		var run_v: float = float(speeds.get("Sprint", 5.0)) * leg
		if spd < (walk_v + jog_v) * 0.55:
			anim = walk_name
			scale_k = spd / walk_v
		elif spd < (jog_v + run_v) * 0.55:
			anim = "Jog_Fwd"
			scale_k = spd / jog_v
		else:
			anim = "Sprint"
			scale_k = spd / run_v
		scale_k = clampf(scale_k, 0.55, 1.7)
	elif activity == "sentar":
		pass
	elif talk_left > 0.0:
		anim = "Idle_Talking"
	elif ACT_ANIM.has(activity):
		anim = ACT_ANIM[activity]
	_play(anim, 0.22 if activity != "agachar" else 0.35)
	ap.speed_scale = scale_k
	ap.advance(delta)
	_apply_posture(delta)
	_apply_hands(delta)
	_apply_look(delta)
	_apply_face(delta)
	if bubble and bubble.visible:
		bubble.position.y = 2.2 + sin(t * 2.4) * 0.04


# Postura por cima da animação: idoso curvado com a cabeça erguida para olhar à frente; tristeza
# e cansaço baixam a cabeça; medo e alegria endireitam. A cabeça da criança fica maior.
func _apply_posture(delta: float) -> void:
	if not face_fx:
		return
	if _head >= 0 and _head_vec != Vector3.ONE:
		skel.set_bone_pose_scale(_head, _head_vec)
	var p: Array = POSTURE.get(emotion, [0.0, 0.0, 0.0])
	var want := Vector3(p[0], p[1], p[2]) + Vector3(14.0, 10.0, -12.0) * _old
	if hunched and not umbrella_on:
		want += Vector3(7.0, 6.0, 6.0)
	if activity == "sentar":
		want *= 0.4
	_pose_cur = _pose_cur.lerp(want, minf(delta * 3.0, 1.0))
	if _pose_cur.length_squared() < 0.01:
		return
	for pair in [[_spine, _pose_cur.x], [_neck, _pose_cur.y], [_head, _pose_cur.z]]:
		var bi: int = pair[0]
		if bi < 0:
			continue
		var par := skel.get_bone_parent(bi)
		if par < 0:
			continue
		var pg: Transform3D = skel.get_bone_global_pose(par)
		var cg: Transform3D = skel.get_bone_global_pose(bi)
		var local := pg.basis.inverse() * Basis(Vector3.RIGHT, deg_to_rad(float(pair[1]))) * cg.basis
		skel.set_bone_pose_rotation(bi, local.get_rotation_quaternion())


# Expressão do rosto 3D: pesos das deformações seguem a emoção; pisca de vez em quando e mexe o
# queixo ao falar. Longe da câmera (LOD) o rosto fica parado e não custa nada.
func _apply_face(delta: float) -> void:
	if body_mi == null or not _lod_near or not face_fx:
		return
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink = 1.0
		_next_blink = randf_range(2.2, 5.5)
	_blink = maxf(0.0, _blink - delta * 7.0)
	var k := minf(delta * 8.0, 1.0)
	for i in FACE_SHAPES.size():
		var n: String = FACE_SHAPES[i]
		var want: float = float(_face_t.get(n, 0.0))
		if n == "piscar":
			want = maxf(want, _blink)
		elif n == "queixo" and talk_left > 0.0:
			want = maxf(want, absf(sin(t * 14.0)) * 0.6 + absf(sin(t * 5.3)) * 0.25)
		var cur: float = float(_face_w.get(n, 0.0))
		var nw := lerpf(cur, want, k if n != "piscar" else 1.0)
		if absf(nw - cur) > 0.002 or (want == 0.0 and cur != 0.0 and nw < 0.004):
			if want == 0.0 and nw < 0.004:
				nw = 0.0
			_face_w[n] = nw
			body_mi.set_blend_shape_value(i, nw)
	if _brow_mi != null:
		for i in BROW_SHAPES.size():
			var n2: String = BROW_SHAPES[i]
			var want2: float = float(_face_t.get(n2, 0.0))
			var cur2: float = float(_face_w.get(n2, 0.0))
			var nw2 := lerpf(cur2, want2, k)
			if absf(nw2 - cur2) > 0.002 or (want2 == 0.0 and cur2 != 0.0):
				if want2 == 0.0 and nw2 < 0.004:
					nw2 = 0.0
				_face_w[n2] = nw2
				_brow_mi.set_blend_shape_value(i, nw2)


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
		if bi < 0:
			continue
		var par := skel.get_bone_parent(bi)
		if par < 0:
			continue
		var pg: Transform3D = skel.get_bone_global_pose(par)
		var cg: Transform3D = skel.get_bone_global_pose(bi)
		var rot := Basis(Vector3.UP, _yaw * w) * Basis(Vector3.RIGHT, _pitch * w)
		var local := pg.basis.inverse() * rot * cg.basis
		skel.set_bone_pose_rotation(bi, local.get_rotation_quaternion())


# ---------- coisas na mão e gestos (guarda-chuva, carrinho de bebê, aceno) ----------
# Os braços são postos por cima da animação (como a postura): o braço que segura o guarda-chuva
# fica dobrado na frente do peito, os dois seguram o carrinho, o aceno levanta o braço e balança
# a mão. O guarda-chuva fica sempre de pé, preso à mão.

const UMBRELLA_COLORS := [Color("#1d1f24"), Color("#20304a"), Color("#6a1f24"), Color("#2f4a33"), Color("#4a3a5a"), Color("#c9a227"), Color("#b3443a"), Color("#3a6f9a")]
static var _umb_canopy: Mesh
static var _umb_shaft: Mesh
static var _umb_meshes: Dictionary = {}
static var _umb_frame: int = -1
static var _umb_made: int = 0
static var _stroller_meshes: Dictionary = {}

var umbrella_on: bool = false
var stroller_on: bool = false
var hunched: bool = false
var _umbrella: Node3D
var _stroller: Node3D
var _wave_t: float = 0.0
var _arm_side: float = 0.0
var _arm_bones: PackedInt32Array = PackedInt32Array()


static func _umbrella_meshes() -> void:
	if _umb_canopy != null:
		return
	var c := CylinderMesh.new()
	c.top_radius = 0.035
	c.bottom_radius = 0.56
	c.height = 0.2
	c.radial_segments = 8
	c.rings = 1
	c.cap_bottom = false
	_umb_canopy = c
	var s := CylinderMesh.new()
	s.top_radius = 0.011
	s.bottom_radius = 0.011
	s.height = 0.86
	s.radial_segments = 6
	_umb_shaft = s


# Uma malha só por cor (copa e haste em duas superfícies), compartilhada por todo mundo.
static func _umbrella_mesh(ci: int) -> Mesh:
	if _umb_meshes.has(ci):
		return _umb_meshes[ci]
	_umbrella_meshes()
	var am := ArrayMesh.new()
	var cm := StandardMaterial3D.new()
	cm.albedo_color = UMBRELLA_COLORS[ci]
	cm.roughness = 0.35
	cm.metallic_specular = 0.7
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rim(cm, 0.25)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color("#2a2622")
	var st := SurfaceTool.new()
	st.append_from(_umb_canopy, 0, Transform3D(Basis(), Vector3(0, 0.86, 0)))
	st.set_material(cm)
	st.commit(am)
	var st2 := SurfaceTool.new()
	st2.append_from(_umb_shaft, 0, Transform3D(Basis(), Vector3(0, 0.42, 0)))
	st2.append_from(_umb_shaft, 0, Transform3D(Basis().scaled(Vector3(1.0, 0.12, 1.0)), Vector3(0, 1.0, 0)))
	st2.set_material(sm)
	st2.commit(am)
	_umb_meshes[ci] = am
	return am


func set_umbrella(on: bool) -> void:
	if on == umbrella_on:
		return
	if on:
		# quando a chuva começa, no máximo 3 guarda-chuvas abrem por quadro (sem engasgo)
		var fr := Engine.get_process_frames()
		if fr != _umb_frame:
			_umb_frame = fr
			_umb_made = 0
		if _umb_made >= 3:
			return
		_umb_made += 1
	umbrella_on = on
	if not on:
		if _umbrella != null:
			_umbrella.queue_free()
			_umbrella = null
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _umbrella_mesh(absi(int(seed_n * 1000.0)) % UMBRELLA_COLORS.size())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	_umbrella = mi
	add_child(_umbrella)


static func _box_mesh(size: Vector3) -> Mesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func set_stroller(on: bool, baby_skin: Color = Color("#e8bf9c")) -> void:
	if on == stroller_on:
		return
	stroller_on = on
	if not on:
		if _stroller != null:
			_stroller.queue_free()
			_stroller = null
		return
	_stroller = Node3D.new()
	_stroller.position = Vector3(0, 0, 0.62)
	add_child(_stroller)
	var body_col: Color = [Color("#2f3a4a"), Color("#4a2f3a"), Color("#3a4a3a"), Color("#5a5048")][absi(int(seed_n * 100.0)) % 4]
	var bm := StandardMaterial3D.new()
	bm.albedo_color = body_col
	bm.roughness = 0.7
	_rim(bm, 0.25)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("#18181a")
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("#9a9ca0")
	metal.metallic = 0.6
	metal.roughness = 0.35
	var parts := [
		[_box_mesh(Vector3(0.42, 0.22, 0.62)), bm, Vector3(0, 0.56, 0)],
		[_box_mesh(Vector3(0.44, 0.06, 0.66)), dark, Vector3(0, 0.44, 0)],
		[_box_mesh(Vector3(0.4, 0.26, 0.05)), bm, Vector3(0, 0.74, 0.29)],
		[_box_mesh(Vector3(0.42, 0.05, 0.05)), metal, Vector3(0, 0.98, -0.42)],
		[_box_mesh(Vector3(0.03, 0.03, 0.4)), metal, Vector3(0.18, 0.8, -0.3)],
		[_box_mesh(Vector3(0.03, 0.03, 0.4)), metal, Vector3(-0.18, 0.8, -0.3)],
	]
	# capota
	var hood := CylinderMesh.new()
	hood.top_radius = 0.22
	hood.bottom_radius = 0.22
	hood.height = 0.42
	hood.radial_segments = 12
	parts.append([hood, bm, Vector3(0, 0.68, 0.16)])
	for pr in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = pr[0]
		mi.material_override = pr[1]
		mi.position = pr[2]
		if pr[0] == hood:
			mi.rotation = Vector3(0, 0, PI / 2.0)
			mi.scale = Vector3(1, 1, 0.9)
		_stroller.add_child(mi)
	for w in [Vector3(0.2, 0.1, 0.24), Vector3(-0.2, 0.1, 0.24), Vector3(0.2, 0.1, -0.24), Vector3(-0.2, 0.1, -0.24)]:
		var wheel := MeshInstance3D.new()
		var wm := CylinderMesh.new()
		wm.top_radius = 0.1
		wm.bottom_radius = 0.1
		wm.height = 0.04
		wheel.mesh = wm
		wheel.material_override = dark
		wheel.position = w
		wheel.rotation = Vector3(0, 0, PI / 2.0)
		_stroller.add_child(wheel)
		var leg := MeshInstance3D.new()
		leg.mesh = _box_mesh(Vector3(0.025, 0.36, 0.025))
		leg.material_override = metal
		leg.position = w + Vector3(0, 0.2, 0)
		_stroller.add_child(leg)
	# o bebê: cabecinha e mantinha
	var skin := StandardMaterial3D.new()
	skin.albedo_color = baby_skin
	skin.roughness = 0.6
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.07
	hs.height = 0.14
	head.mesh = hs
	head.material_override = skin
	head.position = Vector3(0, 0.71, 0.12)
	_stroller.add_child(head)
	var blanket := StandardMaterial3D.new()
	blanket.albedo_color = [Color("#e8d8c8"), Color("#c8d8e8"), Color("#e8c8d4"), Color("#d8e8c8")][absi(int(seed_n * 10.0)) % 4]
	var bl := MeshInstance3D.new()
	bl.mesh = _box_mesh(Vector3(0.3, 0.06, 0.32))
	bl.material_override = blanket
	bl.position = Vector3(0, 0.69, -0.06)
	_stroller.add_child(bl)


# Aceno de cumprimento (braço direito levantado, mão balançando).
func wave(seconds: float = 1.6) -> void:
	_wave_t = seconds


# Aponta um osso (no espaço do esqueleto) para uma direção, a partir da pose atual da animação.
func _aim_bone(bi: int, child: int, dir: Vector3, weight: float = 1.0) -> void:
	if bi < 0 or child < 0:
		return
	var par := skel.get_bone_parent(bi)
	if par < 0:
		return
	var g: Transform3D = skel.get_bone_global_pose(bi)
	var cg: Transform3D = skel.get_bone_global_pose(child)
	var cur := (cg.origin - g.origin).normalized()
	var want := dir.normalized()
	if cur.dot(want) > 0.9999:
		return
	var q := Quaternion(cur, want)
	if weight < 1.0:
		q = Quaternion.IDENTITY.slerp(q, weight)
	var pg: Transform3D = skel.get_bone_global_pose(par)
	var local := pg.basis.inverse() * Basis(q) * g.basis
	skel.set_bone_pose_rotation(bi, local.get_rotation_quaternion())


func _apply_hands(delta: float) -> void:
	if skel == null:
		return
	_wave_t = maxf(0.0, _wave_t - delta)
	if not umbrella_on and not stroller_on and _wave_t <= 0.0:
		return
	if _arm_bones.is_empty():
		for bn in ["upperarm_r", "lowerarm_r", "hand_r", "upperarm_l", "lowerarm_l", "hand_l"]:
			_arm_bones.append(skel.find_bone(bn))
	var ua_r := _arm_bones[0]
	var la_r := _arm_bones[1]
	var ha_r := _arm_bones[2]
	var ua_l := _arm_bones[3]
	var la_l := _arm_bones[4]
	var ha_l := _arm_bones[5]
	if _arm_side == 0.0 and ua_r >= 0:
		_arm_side = signf(skel.get_bone_global_pose(ua_r).origin.x)
		if _arm_side == 0.0:
			_arm_side = -1.0
	var s := _arm_side
	var sitting := activity == "sentar" or lying
	if _lod_near and not sitting:
		if stroller_on:
			_aim_bone(ua_r, la_r, Vector3(s * 0.1, -0.78, 0.6))
			_aim_bone(la_r, ha_r, Vector3(s * -0.06, -0.12, 1.0))
			_aim_bone(ua_l, la_l, Vector3(-s * 0.1, -0.78, 0.6))
			_aim_bone(la_l, ha_l, Vector3(-s * -0.06, -0.12, 1.0))
		elif _wave_t > 0.0:
			var k := minf(1.0, minf(_wave_t * 4.0, (1.6 - _wave_t + 0.25) * 4.0))
			_aim_bone(ua_r, la_r, Vector3(s * 0.75, 0.45, 0.25), k)
			_aim_bone(la_r, ha_r, Vector3(s * (0.15 + sin(t * 11.0) * 0.45), 1.0, 0.15), k)
		elif umbrella_on:
			_aim_bone(ua_r, la_r, Vector3(s * 0.2, -0.82, 0.42))
			_aim_bone(la_r, ha_r, Vector3(s * -0.22, 0.72, 0.6))
	if _umbrella != null:
		var hb := ha_r if ha_r >= 0 else _head
		var hp: Vector3 = (skel.global_transform * skel.get_bone_global_pose(hb)).origin
		var k2 := global_transform.basis.get_scale().y
		_umbrella.global_transform = Transform3D(Basis().scaled(Vector3.ONE * k2), hp)
		_umbrella.visible = visible and not lying
