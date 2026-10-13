extends RefCounted

# Materiais fotográficos do mundo (ambientCG, CC0): monta os dois arrays de textura (chão em
# 4K, superfícies em 2K) a partir das texturas já comprimidas na placa (BC7), sem
# descomprimir, e entrega um ShaderMaterial por categoria do Kit (prédio, asfalto, chão,
# objetos, vegetação, telhado). Todas compartilham o mesmo shader e as mesmas texturas.

const DIR := "res://assets/textures/surfaces/"
const SHADER := preload("res://world3d/surface.gdshader")
const KINDS := {"building": 0, "asphalt": 1, "walk": 2, "props": 3, "veg": 4, "roof": 5}
# relevo (m) do parallax por camada: pedra, tijolo, telha, brita, casca e rachaduras do asfalto
const POM := {"asphalt": 0.012, "paving": 0.04, "ground": 0.015, "brick": 0.022, "roof": 0.03,
	"woodfloor": 0.004, "gravel": 0.03, "bark": 0.025}
const POROSITY := {"building": 0.55, "asphalt": 0.75, "walk": 0.7, "props": 0.35, "veg": 0.4, "roof": 0.5}

static var layers: Array = []
static var index: Dictionary = {}       # nome -> camada (para marcar peças no Kit)
static var _arrays: Dictionary = {}
static var _noise: Texture2D
static var _materials: Dictionary = {}


static func available() -> bool:
	return FileAccess.file_exists(DIR + "layers.json")


static func cleanup() -> void:
	_arrays.clear()
	_materials.clear()
	_noise = null


static func _load_layers() -> void:
	if not layers.is_empty():
		return
	layers = JSON.parse_string(FileAccess.get_file_as_string(DIR + "layers.json"))
	for i in layers.size():
		index[str(layers[i]["name"])] = i


# Camadas virtuais: reusam a foto de outra camada com acabamento próprio no shader.
const VIRTUAL := {"carpaint": 21, "lampglow": 22}


static func layer(name: String) -> int:
	if VIRTUAL.has(name):
		return VIRTUAL[name]
	_load_layers()
	return int(index.get(name, -1))


static func _array(group: String, suffix: String) -> Texture2DArray:
	var key := group + suffix
	if _arrays.has(key):
		return _arrays[key]
	var images: Array[Image] = []
	for l in layers:
		if group != "all" and str(l["array"]) != group:
			continue
		var tex := load(DIR + str(l["name"]) + "_" + suffix + ".jpg") as Texture2D
		var img := tex.get_image()
		images.append(img)
	var arr := Texture2DArray.new()
	var err := arr.create_from_images(images)
	if err != OK:
		push_error("Superfícies: array %s falhou (%s)" % [key, err])
	_arrays[key] = arr
	return arr


static func _macro() -> Texture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.012
		n.fractal_octaves = 4
		var t := NoiseTexture2D.new()
		t.width = 512
		t.height = 512
		t.seamless = true
		t.generate_mipmaps = true
		t.noise = n
		_noise = t
	return _noise


static func material(category: String) -> ShaderMaterial:
	if _materials.has(category):
		return _materials[category]
	_load_layers()
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("ground_albedo", _array("ground", "albedo"))
	m.set_shader_parameter("ground_nr", _array("ground", "nr"))
	m.set_shader_parameter("surf_albedo", _array("surf", "albedo"))
	m.set_shader_parameter("surf_nr", _array("surf", "nr"))
	m.set_shader_parameter("macro_noise", _macro())
	m.set_shader_parameter("height_tex", _array("all", "h"))
	var tiles := PackedFloat32Array()
	var tints := PackedFloat32Array()
	var means := PackedVector3Array()
	var poms := PackedFloat32Array()
	for l in layers:
		poms.append(float(POM.get(str(l["name"]), 0.0)))
		tiles.append(float(l["tile_m"]))
		tints.append(float(l["tint"]))
		var mean: Array = l["mean"]
		means.append(Vector3(float(mean[0]), float(mean[1]), float(mean[2])))
	while tiles.size() < 24:
		tiles.append(1.0)
		tints.append(1.0)
		means.append(Vector3(0.45, 0.45, 0.45))
	m.set_shader_parameter("layer_tile", tiles)
	m.set_shader_parameter("layer_tint", tints)
	m.set_shader_parameter("layer_mean", means)
	while poms.size() < 24:
		poms.append(0.0)
	m.set_shader_parameter("layer_pom", poms)
	m.set_shader_parameter("kind", int(KINDS.get(category, 0)))
	m.set_shader_parameter("porosity", float(POROSITY.get(category, 0.55)))
	_materials[category] = m
	return m
