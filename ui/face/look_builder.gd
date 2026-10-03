extends RefCounted

# A ordem de cada lista segue data/appearance.json.
const SKIN := ["#f3d9c6", "#e8bf9c", "#cf9f74", "#a8744c", "#6f4a32", "#4a2f22"]
const HAIR_COLORS := ["#1a1412", "#3b2516", "#7a5434", "#d8b56a", "#a8432a", "#8a8a88", "#e8e6e0", "#2f5fb3", "#d46aa0", "#3f9a5a", "#ebe4cc"]
const EYE_COLORS := ["#5a3a22", "#1e1410", "#4f7a3a", "#4a78a8", "#a07a3a", "#7a8288", "#5a3a22"]
const HAIR := ["curto", "careca", "raspado", "medio", "longo", "cacheado", "black_power", "trancas", "dreads", "moicano", "coque", "rabo", "franja", "desgrenhado"]
const BEARD := ["none", "stubble", "goatee", "mustache", "full", "long"]
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
	"brow_w": 0.5, "brow_y": 1.0,
}


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
	var hair_color := Color(spec.get("cabelo_cor", HAIR_COLORS[_idx(spec, "cor_cabelo", HAIR_COLORS.size())]))
	var skin := Color(spec.get("pele_cor", SKIN[_idx(spec, "pele", SKIN.size())]))
	var look := {
		"skin": skin,
		"face_w": float(face[0]) * float(body[0]) * (0.95 if female else 1.0),
		"face_len": float(face[1]),
		"cheek": float(face[2]),
		"jaw": (float(face[3]) + float(body[4])) * (0.92 if female else 1.03),
		"chin_w": (float(face[4]) + float(body[5])) * (0.88 if female else 1.0),
		"weathered": face[5],
		"neck": float(body[1]) * (0.85 if female else 1.0),
		"double_chin": body[2], "hollow": body[3],
		"eye_h": tr[0], "eye_tilt": tr[1], "nose_w": float(tr[2]) * (0.88 if female else 1.0), "lips": float(tr[3]) * (1.15 if female else 0.95),
		"eye_size": 1.04 if female else 1.0, "nose_len": 1.0,
		"hair": HAIR[_idx(spec, "cabelo", HAIR.size())],
		"hair_color": hair_color,
		"eye_color": Color(spec.get("olhos_cor", EYE_COLORS[eye_i])),
		"hetero": eye_i == 6,
		"beard": BEARD[_idx(spec, "barba", BEARD.size())],
		"brow_shape": int(spec.get("sobrancelha", -1)) if int(spec.get("sobrancelha", -1)) >= 0 else (2 if female else 0),
		"brow_w": 0.8 if female else 1.15,
		"brow_y": 0.0,
		"clothes": style,
		"clothes_color": Color(spec.get("cor_roupa", colors[0])),
		"clothes_color2": Color(colors[1]),
		"marks": spec.get("marcas", []).map(func(m): return int(m)),
		"extras": spec.get("extras", []),
		"age": age,
		"gender": gender,
	}
	if spec.has("sobrancelha_cor"):
		look["brow_color"] = Color(spec["sobrancelha_cor"])
	if female:
		look["lip_color"] = skin.darkened(0.2).lerp(Color(0.7, 0.25, 0.3), 0.45)
	var adj: Dictionary = spec.get("ajustes", {})
	for k in adj:
		if RANGES.has(k):
			look[k] = float(look.get(k, 0.0)) + float(adj[k]) * float(RANGES[k]) * (1.0 if k in ["eye_tilt", "brow_y"] else float(look.get(k, 1.0)))
	return look
