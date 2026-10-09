extends RefCounted

# Direção de arte do UniRp: realismo estilizado, melancólico e brasileiro.
# Cada cenário tem um perfil próprio (paletas, densidade, desgaste e luz), mas todos usam a mesma
# linguagem: cores apagadas e terrosas, concreto, telha cerâmica, madeira gasta, verde oliva,
# luz quente nas janelas contra exterior frio. Os construtores consultam este arquivo.

const PROFILES := {
	"porto_cinza": {
		# cidade média, cinzenta, de várias épocas: casas de muro, sobrados, prédios antigos
		"walls": ["#c9bfae", "#b9b3a6", "#d2c7b2", "#a9b2ac", "#c4ad94", "#b8a58c", "#9fa7a3", "#cfc3a8", "#b3a08c", "#a8a090", "#c9b9a0", "#9aa3a8", "#bfa98f", "#d6cdbb"],
		"accent_walls": ["#b0846a", "#8e9b8a", "#a3796a", "#7f8f9a", "#c1a36e"],
		"roofs": ["#8a4a34", "#7d4433", "#6b5446", "#5d4c42", "#4b4e52", "#8f5a3f", "#6e3f30"],
		"trims": ["#e3dccb", "#d9d1bf", "#c9c0ad", "#5a4b3e"],
		"doors": ["#5b4030", "#3e4a52", "#6b3a2e", "#4a5642", "#7a6a50", "#2f3a40"],
		"comm_walls": ["#c8bda8", "#b6b0a2", "#a9a196", "#cdbfa2", "#9ea6a6", "#bba68a"],
		"tower_walls": ["#8f8a82", "#9a9389", "#7d817f", "#a59c8e", "#8a7e72"],
		"awnings": ["#7d2b26", "#2f5a48", "#3a5470", "#8a6a2a", "#5a3a52", "#6b6a64"],
		"asphalt": "#3b3d40", "sidewalk": "#7a7770", "curb": "#a39f95", "grass": "#5a6e45", "grass2": "#4b5d3a", "dirt": "#6b5b46",
		"fill": [["predio", 0.12], ["terreno", 0.05], ["estacionamento", 0.04], ["verde", 0.06], ["comercio", 0.07], ["casas", 1.0]],
		"tower_floors": [3, 6], "flowers": 0.25, "decay": 0.35, "abandon": 0.12, "bars": 0.45, "tank": 0.55, "street_trees": 0.75,
		"fence_weights": {"muro": 4, "wood": 1, "chain": 2, "hedge": 1, "none": 1},
		"grade": {"sat": 0.78, "contrast": 1.06, "shadow": [0.9, 0.97, 1.1], "high": [1.06, 1.0, 0.9], "grain": 0.03},
	},
	"vale_sereno": {
		# cidadezinha: casas baixas e coloridas de interior, quintais grandes, muita árvore, comércio de esquina
		"walls": ["#e6d8b8", "#d9c79c", "#cfdcc4", "#e8d2b0", "#c9b48a", "#dfc7a8", "#bcd0c0", "#e4dccb", "#d8b994", "#c7d3b4", "#e6c9a6", "#d1c9a0"],
		"accent_walls": ["#c98f6a", "#7ea08a", "#b98a5a", "#a9b878", "#d0a060"],
		"roofs": ["#9c4f32", "#a35b38", "#8a4a30", "#b0603c", "#7e4a33"],
		"trims": ["#f0e8d6", "#e8dfcb", "#6b4e36"],
		"doors": ["#6b4a30", "#3f6b5a", "#8a5a2e", "#4a6a8a", "#7a3a2e"],
		"comm_walls": ["#e3d3b0", "#d4c4a0", "#cbd8be", "#e2c9a2"],
		"tower_walls": ["#c7b9a0", "#bfb3a0"],
		"awnings": ["#8a3a2a", "#3e6a4a", "#a87a2a", "#5a6a8a"],
		"asphalt": "#4a4a46", "sidewalk": "#8a8478", "curb": "#aaa497", "grass": "#667e48", "grass2": "#566d3c", "dirt": "#7a6448",
		"fill": [["predio", 0.03], ["terreno", 0.09], ["estacionamento", 0.02], ["verde", 0.16], ["comercio", 0.06], ["casas", 1.0]],
		"tower_floors": [2, 3], "flowers": 0.7, "verge": true, "decay": 0.25, "abandon": 0.08, "bars": 0.2, "tank": 0.7, "street_trees": 1.0,
		"fence_weights": {"muro": 2, "wood": 3, "chain": 1, "hedge": 3, "none": 2},
		"grade": {"sat": 0.86, "contrast": 1.04, "shadow": [0.94, 0.98, 1.05], "high": [1.07, 1.02, 0.9], "grain": 0.025},
	},
	"nova_aurora": {
		# metrópole: torres de concreto e vidro, prédios residenciais com varandas, contraste entre bairro nobre e popular
		"walls": ["#c4c0b8", "#b3b0aa", "#d0cbc0", "#a7aaa8", "#bdb3a4", "#9ea3a6", "#cfc6b4", "#b5aa98"],
		"accent_walls": ["#8a8f96", "#a08a78", "#6f7f8a", "#b29a7a"],
		"roofs": ["#4b4e52", "#5d4c42", "#7d4433", "#3f4448"],
		"trims": ["#d8d4cc", "#c9c4ba", "#4a4e52"],
		"doors": ["#2f3a40", "#3e4a52", "#4a4a4a", "#5b4030"],
		"comm_walls": ["#bfbab0", "#a8a7a2", "#c9c0ae", "#8f969c", "#b8ab96"],
		"tower_walls": ["#7f8487", "#8d8a84", "#6f777c", "#a29a8d", "#5f676d", "#93897c"],
		"awnings": ["#2b3a4a", "#5a2b2b", "#2f4a3a", "#4a4a4a", "#7a5a2a"],
		"asphalt": "#333538", "sidewalk": "#83807a", "curb": "#a8a49b", "grass": "#55683f", "grass2": "#47583a", "dirt": "#5f5242",
		"fill": [["predio", 0.34], ["terreno", 0.03], ["estacionamento", 0.07], ["verde", 0.04], ["comercio", 0.17], ["casas", 1.0]],
		"tower_floors": [6, 13], "flowers": 0.15, "decay": 0.3, "abandon": 0.1, "bars": 0.55, "tank": 0.35, "street_trees": 0.6,
		"fence_weights": {"muro": 5, "wood": 0, "chain": 2, "hedge": 1, "none": 1},
		"grade": {"sat": 0.74, "contrast": 1.08, "shadow": [0.88, 0.96, 1.12], "high": [1.05, 1.0, 0.94], "grain": 0.03},
	},
	"colapso": {
		# pós-crise: a mesma Porto Cinza, mas com reparos improvisados, portas protegidas, lojas fechadas, poeira
		"walls": ["#a8a094", "#9a9488", "#b0a490", "#8f948e", "#a3907c", "#9c8c78", "#8a8a84", "#ad9f86"],
		"accent_walls": ["#8a6a58", "#6f7a6c", "#7d6050"],
		"roofs": ["#6e4232", "#5d4a40", "#4a4a4c", "#6b4a3a", "#55504a"],
		"trims": ["#bdb4a2", "#a89f8c", "#4a3f36"],
		"doors": ["#4a3a2e", "#3a4044", "#5a3a2e", "#5a5a4a"],
		"comm_walls": ["#a49c8e", "#9a948a", "#a8987e", "#8c9090"],
		"tower_walls": ["#7a766e", "#857c70", "#6c706e"],
		"awnings": ["#5a2b26", "#2f4a3e", "#4a4a44", "#6a5a3a"],
		"asphalt": "#38393a", "sidewalk": "#6f6b64", "curb": "#8f8a80", "grass": "#5d6340", "grass2": "#545a38", "dirt": "#66563f",
		"fill": [["predio", 0.12], ["terreno", 0.12], ["estacionamento", 0.04], ["verde", 0.04], ["comercio", 0.07], ["casas", 1.0]],
		"tower_floors": [3, 6], "flowers": 0.05, "tarps": true, "decay": 0.8, "abandon": 0.35, "bars": 0.8, "tank": 0.45, "street_trees": 0.55,
		"fence_weights": {"muro": 4, "wood": 2, "chain": 3, "hedge": 0, "none": 2},
		"grade": {"sat": 0.62, "contrast": 1.1, "shadow": [0.95, 0.95, 1.0], "high": [1.08, 1.0, 0.86], "grain": 0.045},
	},
}

# Iluminação ao longo do dia (hora, cor do sol, força do sol, cor ambiente, força ambiente).
# Manhã nublada e azulada, meio-dia neutro e apagado, fim de tarde dourado com sombras longas,
# crepúsculo lilás, noite azul profunda (as janelas quentes fazem o contraste).
const LIGHT_KEYS := [
	[0.0, "#5a6b9a", 0.12, "#2c3b60", 0.66],
	[4.5, "#5a6b9a", 0.12, "#2d3c62", 0.66],
	[6.0, "#e8a88a", 0.32, "#56607a", 0.38],
	[7.5, "#d9dce0", 0.55, "#8e9aac", 0.34],
	[10.0, "#f1ede4", 0.72, "#aeb6c2", 0.32],
	[13.0, "#f4efe4", 0.78, "#b4bac4", 0.32],
	[16.0, "#f6dcb0", 0.74, "#a8acb4", 0.32],
	[17.6, "#ffb877", 0.80, "#9a8e8e", 0.34],
	[18.6, "#ff8f5c", 0.48, "#6a5f78", 0.36],
	[19.6, "#8a7aa8", 0.16, "#3a4266", 0.58],
	[21.0, "#5a6b9a", 0.12, "#2e3d62", 0.66],
	[24.0, "#5a6b9a", 0.12, "#2c3b60", 0.66],
]


static func id() -> String:
	var sc := str(GameState.player.get("cenario", "porto_cinza"))
	return sc if PROFILES.has(sc) else "porto_cinza"


static func p() -> Dictionary:
	return PROFILES[id()]


static func col(key: String) -> Color:
	return Color(str(p()[key]))


static func pick(key: String, r: RandomNumberGenerator) -> Color:
	var arr: Array = p()[key]
	return Color(str(arr[r.randi() % arr.size()]))


static func num(key: String) -> float:
	return float(p()[key])


static func fill_kind(roll: float) -> String:
	var acc := 0.0
	for e in p()["fill"]:
		acc += float(e[1])
		if roll < acc:
			return str(e[0])
	return "casas"


static func fence_kind(r: RandomNumberGenerator) -> String:
	var w: Dictionary = p()["fence_weights"]
	var total := 0.0
	for k in w:
		total += float(w[k])
	var x := r.randf() * total
	for k in w:
		x -= float(w[k])
		if x <= 0.0:
			return str(k)
	return "muro"


# Cor e força da luz para uma hora do dia.
static func light_at(hf: float) -> Dictionary:
	var a: Array = LIGHT_KEYS[0]
	var b: Array = LIGHT_KEYS[LIGHT_KEYS.size() - 1]
	for i in range(LIGHT_KEYS.size() - 1):
		if hf >= float(LIGHT_KEYS[i][0]) and hf <= float(LIGHT_KEYS[i + 1][0]):
			a = LIGHT_KEYS[i]
			b = LIGHT_KEYS[i + 1]
			break
	var u := 0.0
	if float(b[0]) > float(a[0]):
		u = smoothstep(0.0, 1.0, (hf - float(a[0])) / (float(b[0]) - float(a[0])))
	return {
		"sun": Color(str(a[1])).lerp(Color(str(b[1])), u), "sun_e": lerpf(float(a[2]), float(b[2]), u),
		"amb": Color(str(a[3])).lerp(Color(str(b[3])), u), "amb_e": lerpf(float(a[4]), float(b[4]), u),
	}


# Desgaste de uma construção: mistura do perfil da cidade com o acaso do lote.
static func wear(r: RandomNumberGenerator) -> float:
	return clampf(num("decay") * 0.7 + r.randf() * 0.6 - 0.15, 0.0, 1.0)
