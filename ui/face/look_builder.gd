extends RefCounted

# A ordem de cada lista segue data/appearance.json.
const SKIN := ["#f3d9c6", "#e8bf9c", "#cf9f74", "#a8744c", "#6f4a32", "#4a2f22"]
const HAIR_COLORS := ["#1a1412", "#3b2516", "#7a5434", "#d8b56a", "#a8432a", "#8a8a88", "#e8e6e0", "#2f5fb3", "#d46aa0", "#3f9a5a", "#ebe4cc"]
const EYE_COLORS := ["#5a3a22", "#1e1410", "#4f7a3a", "#4a78a8", "#a07a3a", "#7a8288", "#5a3a22"]
const HAIR := ["curto", "careca", "raspado", "medio", "longo", "cacheado", "black_power", "trancas", "dreads", "moicano", "coque", "rabo", "franja", "desgrenhado"]
const BEARD := ["none", "stubble", "goatee", "mustache", "full", "long", "mustache_thin", "short", "sideburns"]
# Tons de pele do criador (do mais claro ao mais escuro). O índice "pele" (6 opções, usado na
# descrição para a IA) fica no tom mais próximo; a cor exata vai em "pele_cor".
const SKIN_TONES := ["#f6e1d3", "#f0d2bb", "#e8bf9c", "#dcab84", "#cf9f74", "#bb8659", "#a8744c", "#8d5e3c", "#6f4a32", "#5a3a28", "#4a2f22", "#3a241b"]
const HEIGHTS := [1.0, 0.94, 1.05, 1.1]
const CLOTHES := ["camiseta", "moletom", "couro", "jeans", "social", "terno", "regata", "vestido", "blusa", "time", "uniforme", "academia", "rasgada", "sobretudo"]
const CLOTHES_COLORS := {
	"camiseta": ["#4a5260", "#dddddd"], "moletom": ["#3a3f4a", "#dddddd"], "couro": ["#18181a", "#2e2e33"],
	"jeans": ["#3d5a80", "#e6e6e6"], "social": ["#e6e6e6", "#f4f4f4"], "terno": ["#222630", "#f0f0f0"],
	"regata": ["#e0e0e0", "#e0e0e0"], "vestido": ["#7a2040", "#7a2040"], "blusa": ["#b5838d", "#b5838d"],
	"time": ["#1d4f91", "#f1f1f1"], "uniforme": ["#8a2b2b", "#2b2b2b"], "academia": ["#222222", "#444444"],
	"rasgada": ["#6b6355", "#6b6355"], "sobretudo": ["#2b2620", "#3a3a3a"],
	"jaleco": ["#2a3540", "#f2f2f2"], "farda": ["#1f2f4f", "#2b3d63"], "batina": ["#111111", "#111111"],
	"avental": ["#e8e4da", "#4a3428"], "macacao": ["#2d4f7a", "#2d4f7a"], "havaiana": ["#2a8a7a", "#f4a261"],
	"cobertor": ["#5a5a50", "#5a5a50"],
}
# [face_w, face_len, cheek, jaw, chin_w, weathered]
const FACE := [
	[1.0, 1.0, 1.0, 0.76, 0.34, false],
	[1.05, 0.97, 1.0, 0.9, 0.44, false],
	[1.06, 0.92, 1.03, 0.84, 0.4, false],
	[0.92, 1.06, 0.96, 0.66, 0.28, false],
	[0.98, 1.03, 1.04, 0.78, 0.36, true],
]
# [face_w mult, neck, double_chin, hollow, jaw add, chin add]
const BODY := [
	[0.95, 0.85, false, false, -0.03, -0.02],
	[1.0, 1.0, false, false, 0.0, 0.0],
	[1.0, 1.08, false, false, 0.03, 0.02],
	[1.04, 1.35, false, false, 0.07, 0.04],
	[1.08, 1.12, false, false, 0.08, 0.06],
	[1.14, 1.22, true, false, 0.12, 0.1],
	[0.9, 0.78, false, true, -0.06, -0.03],
]
# [eye_h, eye_tilt, nose_w, lips]
const TRAITS := [[1.0, 0.0, 1.05, 1.05], [1.0, 0.0, 0.92, 0.9], [1.05, 0.0, 1.3, 1.35], [0.72, 0.35, 0.98, 1.0], [0.85, 0.15, 1.15, 1.1], [1.0, 0.0, 1.08, 1.05], [0.95, 0.0, 1.12, 1.05]]
# Quanto cada controle deslizante do criador (-1..1) muda o parâmetro.
const RANGES := {
	"face_w": 0.14, "face_len": 0.12, "cheek": 0.1, "jaw": 0.14, "chin_w": 0.12,
	"nose_w": 0.35, "nose_len": 0.25, "lips": 0.4, "eye_size": 0.2, "eye_tilt": 0.4,
	"brow_w": 0.5, "brow_y": 1.0, "eye_h": 0.25, "mouth_w": 0.2, "ear_size": 0.3, "ear_out": 0.5, "rugas": 1.0, "eye_spacing": 0.16, "nose_bridge": 0.018, "chin_length": 0.014, "forehead": 0.018, "asymmetry": 0.004,
	"chest": 0.16, "waist": 0.2, "hips": 0.16, "limbs": 0.18, "abdomen": 0.055, "stature": 0.1,
}
# Ajustes que somam direto (sem multiplicar pelo valor base)
const ADDITIVE := ["eye_tilt", "brow_y", "rugas", "nose_bridge", "chin_length", "forehead", "asymmetry", "abdomen"]


static func _idx(spec: Dictionary, key: String, n: int) -> int:
	return clampi(int(spec.get(key, 0)), 0, n - 1)


static func build(spec: Dictionary, age: int, gender: String) -> Dictionary:
	var face: Array = FACE[_idx(spec, "rosto", FACE.size())]
	var body: Array = BODY[_idx(spec, "corpo", BODY.size())]
	var tr: Array = TRAITS[_idx(spec, "tracos", TRAITS.size())]
	var eye_i := _idx(spec, "olhos", EYE_COLORS.size())
	var clothes = spec.get("roupa", 0)
	var style: String = clothes if typeof(clothes) == TYPE_STRING else CLOTHES[clampi(int(clothes), 0, CLOTHES.size() - 1)]
	var colors: Array = CLOTHES_COLORS.get(style, ["#4a5260", "#dddddd"])
	var female := gender == "mulher"
	var male := gender == "homem"
	# Dimorfismo: [rosto largura, comprimento, mandíbula, queixo, maçãs, olhos, altura olho, nariz larg., nariz compr., lábios, pescoço, ombros]
	var dm: Array = [0.92, 0.96, 0.86, 0.82, 1.03, 1.12, 1.08, 0.82, 0.9, 1.3, 0.82, 0.86] if female else ([1.04, 1.03, 1.1, 1.2, 1.0, 0.92, 0.9, 1.08, 1.05, 0.8, 1.15, 1.06] if male else [0.97, 1.0, 0.98, 1.0, 1.01, 1.02, 1.0, 0.95, 0.98, 1.05, 0.98, 0.96])
	var hair_color := Color(spec.get("cabelo_cor", HAIR_COLORS[_idx(spec, "cor_cabelo", HAIR_COLORS.size())]))
	var skin := Color(spec.get("pele_cor", SKIN[_idx(spec, "pele", SKIN.size())]))
	var look := {
		"skin": skin,
		"face_w": float(face[0]) * float(body[0]) * dm[0],
		"face_len": float(face[1]) * dm[1],
		"cheek": float(face[2]) * dm[4],
		"jaw": minf((float(face[3]) + float(body[4])) * dm[2], 0.98),
		"chin_w": (float(face[4]) + float(body[5])) * dm[3],
		"weathered": face[5],
		"neck": float(body[1]) * dm[10],
		"shoulders": dm[11],
		"double_chin": body[2], "hollow": body[3],
		"eye_h": float(tr[0]) * dm[6], "eye_tilt": tr[1], "nose_w": float(tr[2]) * dm[7], "lips": float(tr[3]) * dm[9],
		"eye_size": dm[5], "nose_len": dm[8],
		"lashes": female,
		"adams_apple": male,
		"shadow_beard": male,
		"hair": HAIR[_idx(spec, "cabelo", HAIR.size())],
		"hair_color": hair_color,
		"eye_color": Color(spec.get("olhos_cor", EYE_COLORS[eye_i])),
		"hetero": eye_i == 6,
		"beard": BEARD[_idx(spec, "barba", BEARD.size())],
		"brow_shape": int(spec.get("sobrancelha", -1)) if int(spec.get("sobrancelha", -1)) >= 0 else (2 if female else 0),
		"brow_w": 0.7 if female else (1.3 if male else 1.0),
		"brow_y": 0.5 if female else (-0.5 if male else 0.0),
		"clothes": style,
		"clothes_color": Color(spec.get("cor_roupa", colors[0])),
		"clothes_color2": Color(spec.get("cor_roupa2", colors[1])),
		"height": float(HEIGHTS[_idx(spec, "altura", HEIGHTS.size())]),
		"eye_spacing": 1.0, "nose_bridge": 0.0, "chin_length": 0.0, "forehead": 0.0, "asymmetry": 0.0,
		"chest": 1.0, "waist": 1.0, "hips": 1.0, "limbs": 1.0, "abdomen": 0.0, "stature": 1.0,
		"mouth_w": 1.0, "ear_size": 1.0, "ear_out": 1.0, "rugas": 0.0,
		"marks": spec.get("marcas", []).map(func(m): return int(m)),
		"extras": spec.get("extras", []),
		"age": age,
		"gender": gender,
		"body_type": _idx(spec, "corpo", BODY.size()),
	}
	if spec.has("sobrancelha_cor"):
		look["brow_color"] = Color(spec["sobrancelha_cor"])
	if spec.has("barba_cor"):
		look["beard_color"] = Color(spec["barba_cor"])
	if female:
		look["lip_color"] = skin.darkened(0.15).lerp(Color(0.72, 0.24, 0.3), 0.5)
	elif male:
		look["lip_color"] = skin.darkened(0.18).lerp(Color(0.55, 0.3, 0.28), 0.15)
	var adj: Dictionary = spec.get("ajustes", {})
	for k in adj:
		if RANGES.has(k):
			look[k] = float(look.get(k, 0.0)) + float(adj[k]) * float(RANGES[k]) * (1.0 if k in ADDITIVE else float(look.get(k, 1.0)))
	return look


static func individual_spec(spec: Dictionary, identity: String) -> Dictionary:
	if spec.has("ajustes"):
		return spec
	var result := spec.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(identity.hash()) + 18271
	var adjustments := {}
	for key in ["face_w", "face_len", "cheek", "jaw", "chin_w", "nose_w", "nose_len", "lips", "eye_size", "eye_h", "eye_tilt", "eye_spacing", "mouth_w", "ear_size", "ear_out", "brow_w", "brow_y", "nose_bridge", "chin_length", "forehead", "asymmetry"]:
		adjustments[key] = snappedf(rng.randf_range(-0.85, 0.85), 0.05)
	result["ajustes"] = adjustments
	return result
