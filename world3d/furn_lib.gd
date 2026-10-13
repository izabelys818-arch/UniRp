extends RefCounted

# Móveis prontos (Kenney Furniture Kit e Quaternius Furniture Pack, CC0). Centraliza cada modelo
# no chão, converte para metros e permite girar. Escala do Kenney: ~0,2 m por unidade.

const K := "res://assets/furniture_k/Models/%s.fbx"
const Q := "res://assets/furniture_q/FBX/%s.fbx"
const K_SCALE := 0.2

static var _scenes: Dictionary = {}
static var _info: Dictionary = {}
static var _shadow_mesh: ArrayMesh
static var _tones: Dictionary = {}
static var trace := false


static func available() -> bool:
	return ResourceLoader.exists(K % "bedDouble")


static func _collect(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		acc.append(t * (n as MeshInstance3D).get_aabb())
	for c in n.get_children():
		_collect(c, t, acc)


# Devolve um nó posicionado no chão em "pos", virado "yaw", com o modelo centralizado.
# size_m: tamanho final em metros (x, y, z antes de girar). Se um eixo for 0, mantém a proporção.
static func cleanup() -> void:
	_scenes.clear()
	_info.clear()
	_shadow_mesh = null
	_tones.clear()


static func bounds_for(path: String) -> AABB:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var ps: PackedScene = _scenes[path]
	if ps == null:
		return AABB()
	if not _info.has(path):
		var probe: Node = ps.instantiate()
		var acc: Array = []
		_collect(probe, Transform3D.IDENTITY, acc)
		if acc.is_empty():
			# modelo sem malha (arquivo corrompido ou vazio): não coloca nada, sem travar o jogo
			probe.free()
			_scenes[path] = null
			push_warning("Móvel sem malha: " + path)
			return AABB()
		var b: AABB = acc[0]
		for a in acc:
			b = b.merge(a)
		_info[path] = b
		probe.free()
	return _info[path]


static func place(parent: Node3D, path: String, pos: Vector3, yaw: float = 0.0, scale_k: float = K_SCALE, fit: Vector3 = Vector3.ZERO, solid: bool = false, variant: int = -1) -> Node3D:
	var started := Time.get_ticks_usec()
	var box := bounds_for(path)
	if box.size == Vector3.ZERO:
		return null
	var ps: PackedScene = _scenes[path]
	var loaded := Time.get_ticks_usec()
	var probed := Time.get_ticks_usec()
	var s := scale_k
	if fit != Vector3.ZERO:
		var sx: float = fit.x / box.size.x if fit.x > 0.0 else 0.0
		var sy: float = fit.y / box.size.y if fit.y > 0.0 else 0.0
		var sz: float = fit.z / box.size.z if fit.z > 0.0 else 0.0
		for v in [sx, sy, sz]:
			if v > 0.0:
				s = v
				break
	var lightweight := solid and path.get_file().get_basename() in ["chair", "chairDesk", "trashcan"]
	var holder: Node3D = preload("res://world3d/light_object.gd").new() if lightweight else Node3D.new()
	if lightweight:
		holder.material_kind = "wood" if path.get_file().get_basename() == "chair" else "plastic"
		holder.mass = 4.0
	holder.name = path.get_file().get_basename()
	holder.position = pos
	holder.rotation.y = yaw
	var m: Node3D = ps.instantiate()
	m.scale = Vector3.ONE * s
	var c := box.get_center()
	m.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)
	# Camas têm tecido e madeira no mesmo asset: não aplicar veio de madeira ao lençol.
	_tone(m, path.get_file().get_basename() in ["table", "tableCoffee", "cabinetBed", "cabinetTelevision", "bookcaseOpen", "bookcaseClosed", "desk", "chair"], variant)
	var toned := Time.get_ticks_usec()
	holder.add_child(m)
	holder.set_meta("bounds", AABB(Vector3(-box.size.x * s / 2.0, 0, -box.size.z * s / 2.0), box.size * s))
	holder.set_meta("asset", path)
	if solid:
		var body: PhysicsBody3D = holder if lightweight else StaticBody3D.new()
		if not lightweight: body.collision_layer = 5
		var shape := CollisionShape3D.new()
		var volume := BoxShape3D.new()
		volume.size = box.size * s * Vector3(0.90, 0.92, 0.90)
		shape.shape = volume
		shape.position.y = box.size.y * s * 0.46
		body.add_child(shape)
		if not lightweight: holder.add_child(body)
	# sombra de contato sob o móvel (os modelos não recebem a oclusão assada do kit): assenta no piso
	if _shadow_mesh == null:
		var k := preload("res://world3d/mesh_kit.gd").new()
		k.disc(Vector3.ZERO, 0.5, 0.5, Color(0.02, 0.02, 0.04, 0.42), 0.0, 16, 0.0, 0.7, 0.75)
		_shadow_mesh = k.commit(preload("res://world3d/mesh_kit.gd").shadow_material())
	var foot := Vector2(box.size.x, box.size.z) * s
	if foot.x > 0.15 and foot.y > 0.15 and box.size.y * s > 0.12:
		var sh := MeshInstance3D.new()
		sh.mesh = _shadow_mesh
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Mantém a sombra junto ao piso, abaixo dos tapetes e das bases baixas.
		sh.position = Vector3(0, 0.003, 0)
		sh.scale = Vector3(foot.x * 1.15, 1.0, foot.y * 1.15)
		holder.add_child(sh)
	parent.add_child(holder)
	if path.get_file().get_basename() in ["kitchenFridge", "kitchenStove", "washer"]:
		var badge := Label3D.new()
		badge.text = "BRISA" if path.contains("Fridge") else "AURORA"
		badge.font_size = 28
		badge.pixel_size = 0.0013
		badge.outline_size = 0
		badge.modulate = Color("#646b72")
		badge.position = Vector3(0, box.size.y * s * 0.74, box.size.z * s / 2.0 + 0.008)
		holder.add_child(badge)
	if trace and Time.get_ticks_usec() - started > 4000:
		print("FURN SLOW ", path.get_file(), " load_ms=", (loaded - started) / 1000.0, " bounds_ms=", (probed - loaded) / 1000.0, " instance_material_ms=", (toned - probed) / 1000.0, " total_ms=", (Time.get_ticks_usec() - started) / 1000.0)
	return holder


# Os materiais do pacote são cor lisa (cara de plástico). Cada um ganha o material fotográfico
# certo (madeira, tecido, couro, metal, mármore, folha) pelo nome, mantendo a cor original
# como tom. Sem as texturas, cai no tom antigo (escurecido e fosco).
const SurfacesLib = preload("res://world3d/surfaces.gd")
const MATERIAL_BY_NAME := [
	["darkwood", "wood"], ["darkbrown", "wood"], ["wood", "wood"], ["top", "wood"],
	["leather", "leather"], ["sofa", "fabric"], ["cover", "fabric"], ["sheet", "fabric"],
	["carpet", "fabric"], ["fur", "carpet"], ["pillow", "fabric"], ["metal", "metal"],
	["plant", "leaf"], ["green", "leaf"], ["vase", "marble"], ["marble", "marble"],
	["white", "plaster"], ["red", "paintedwood"], ["pages", "plaster"], ["_defaultmat", "plaster"],
]


static func _surface_for(material_name: String) -> String:
	var n := material_name.to_lower()
	for pair in MATERIAL_BY_NAME:
		if n.begins_with(str(pair[0])) or n.contains(str(pair[0])):
			return str(pair[1])
	return ""


static func _tone(n: Node, wood: bool = false, variant := -1) -> void:
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src is BaseMaterial3D:
				var tone := absi(variant) % 4 if variant != -1 else -1
				var key := str(src.get_instance_id()) + ("wood" if wood else "plain") + str(tone)
				if not _tones.has(key):
					_tones[key] = _material(src as BaseMaterial3D, wood, tone)
				mi.set_surface_override_material(i, _tones[key])


static func _material(src: BaseMaterial3D, wood: bool, tone := -1) -> BaseMaterial3D:
	var m := src.duplicate() as BaseMaterial3D
	m.albedo_color = Color(m.albedo_color.r * 0.62, m.albedo_color.g * 0.6, m.albedo_color.b * 0.58)
	m.roughness = 0.85
	m.metallic = 0.0
	m.metallic_specular = 0.2
	var layer_name := _surface_for(str(src.resource_name))
	if layer_name == "" and wood:
		layer_name = "wood"
	var layer := SurfacesLib.layer(layer_name) if layer_name != "" else -1
	var lname := str(src.resource_name).to_lower()
	if tone >= 0 and layer_name == "fabric" and not lname.contains("white"):
		m.albedo_color = Color(["#596875", "#686956", "#8a7262", "#7c5d5c"][tone])
	if lname.begins_with("glass"):
		m.roughness = 0.05
		m.metallic_specular = 0.6
		return m
	if layer < 0 or src.albedo_texture != null or not SurfacesLib.available():
		var col := m.albedo_color
		if wood and col.r > col.b * 1.25 and col.g > col.b * 1.1:
			preload("res://world3d/surface_detail.gd").apply(m, "wood", 1.4)
		return m
	var info: Dictionary = SurfacesLib.layers[layer]
	var dir := "res://assets/textures/surfaces/" + layer_name
	m.albedo_texture = load(dir + "_albedo.jpg")
	m.normal_enabled = true
	m.normal_texture = load(dir + "_nr.jpg")
	m.normal_scale = 0.9
	m.roughness_texture = m.normal_texture
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 6.0
	m.uv1_scale = Vector3.ONE / maxf(float(info["tile_m"]) * 0.7, 0.2)
	# a foto entra normalizada pela própria média: a cor do móvel continua a do pacote
	var mean: Array = info["mean"]
	var mean_srgb := Color(float(mean[0]), float(mean[1]), float(mean[2])).linear_to_srgb()
	var tint := float(info["tint"])
	var base := m.albedo_color
	var normalized := Color(base.r / maxf(mean_srgb.r, 0.05), base.g / maxf(mean_srgb.g, 0.05), base.b / maxf(mean_srgb.b, 0.05))
	m.albedo_color = Color(1, 1, 1).lerp(normalized, tint) if tint < 0.99 else normalized
	if layer_name == "wood":
		# madeira escura dos móveis: mais fechada que a foto
		m.albedo_color = m.albedo_color * (0.8 if lname.contains("dark") else 1.0)
	if layer_name == "metal":
		m.metallic = 0.25 if lname.contains("dark") else 0.6
		m.roughness = 0.55
	if layer_name == "leaf":
		m.uv1_scale = Vector3.ONE / 0.5
	return m


# Carrega modelos e materiais no carregamento da cidade: a primeira casa aberta travava
# ~300 ms (FBX + texturas fotográficas do primeiro móvel).
const PREWARM := ["bedDouble", "bedSingle", "cabinetBed", "cabinetTelevision", "bookcaseOpen", "bookcaseClosed", "shower",
	"books", "bathroomMirror", "bathroomSink", "bathtub", "toilet", "chair", "chairDesk", "desk", "table",
	"tableCoffee", "kitchenFridge", "kitchenStove", "kitchenSink", "kitchenCabinet", "kitchenCabinetUpper",
	"kitchenCoffeeMachine", "kitchenMicrowave", "lampRoundFloor", "lampRoundTable", "laptop", "loungeChair",
	"loungeChairRelax", "loungeSofa", "loungeSofaLong", "pillow", "plantSmall1", "plantSmall2", "plantSmall3",
	"pottedPlant", "radio", "rugRectangle", "rugRound", "sideTableDrawers", "speakerSmall", "trashcan",
	"washer", "cardboardBoxClosed", "cardboardBoxOpen", "bear", "televisionModern"]


static func prewarm(tree: SceneTree, budget_us: int = 6000, render_parent: Node = null) -> void:
	var holder := Node3D.new()
	if render_parent != null:
		render_parent.add_child(holder)
		holder.position = Vector3(0, 0, -90)
	var frame := Time.get_ticks_usec()
	for name in PREWARM:
		var path := K % name
		if not ResourceLoader.exists(path):
			continue
		var n := place(holder, path, Vector3.ZERO)
		if n != null:
			if render_parent != null:
				await tree.process_frame
				await tree.process_frame
			n.queue_free()
		if Time.get_ticks_usec() - frame > budget_us:
			await tree.process_frame
			frame = Time.get_ticks_usec()
	holder.free()


static func size_of(path: String, scale_k: float = K_SCALE) -> Vector3:
	return (_info[path] as AABB).size * scale_k if _info.has(path) else Vector3.ZERO
