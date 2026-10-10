extends RefCounted

# Móveis prontos (Kenney Furniture Kit e Quaternius Furniture Pack, CC0). Centraliza cada modelo
# no chão, converte para metros e permite girar. Escala do Kenney: ~0,2 m por unidade.

const K := "res://assets/furniture_k/Models/%s.fbx"
const Q := "res://assets/furniture_q/FBX/%s.fbx"
const K_SCALE := 0.2

static var _scenes: Dictionary = {}
static var _info: Dictionary = {}
static var _shadow_mesh: ArrayMesh


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


static func place(parent: Node3D, path: String, pos: Vector3, yaw: float = 0.0, scale_k: float = K_SCALE, fit: Vector3 = Vector3.ZERO) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var ps: PackedScene = _scenes[path]
	if ps == null:
		return null
	if not _info.has(path):
		var probe: Node = ps.instantiate()
		var acc: Array = []
		_collect(probe, Transform3D.IDENTITY, acc)
		if acc.is_empty():
			# modelo sem malha (arquivo corrompido ou vazio): não coloca nada, sem travar o jogo
			probe.free()
			_scenes[path] = null
			push_warning("Móvel sem malha: " + path)
			return null
		var b: AABB = acc[0]
		for a in acc:
			b = b.merge(a)
		_info[path] = b
		probe.free()
	var box: AABB = _info[path]
	var s := scale_k
	if fit != Vector3.ZERO:
		var sx: float = fit.x / box.size.x if fit.x > 0.0 else 0.0
		var sy: float = fit.y / box.size.y if fit.y > 0.0 else 0.0
		var sz: float = fit.z / box.size.z if fit.z > 0.0 else 0.0
		for v in [sx, sy, sz]:
			if v > 0.0:
				s = v
				break
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	var m: Node3D = ps.instantiate()
	m.scale = Vector3.ONE * s
	var c := box.get_center()
	m.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)
	_tone(m)
	holder.add_child(m)
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
		sh.position = Vector3(0, 0.012, 0)
		sh.scale = Vector3(foot.x * 1.15, 1.0, foot.y * 1.15)
		holder.add_child(sh)
	parent.add_child(holder)
	return holder


# Os materiais do pacote são muito claros sob a luz do sol; escurece e tira o brilho.
static func _tone(n: Node) -> void:
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src is BaseMaterial3D:
				var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				m.albedo_color = Color(m.albedo_color.r * 0.58, m.albedo_color.g * 0.56, m.albedo_color.b * 0.54)
				m.roughness = 0.9
				m.metallic = 0.0
				m.metallic_specular = 0.2
				mi.set_surface_override_material(i, m)


static func size_of(path: String, scale_k: float = K_SCALE) -> Vector3:
	return (_info[path] as AABB).size * scale_k if _info.has(path) else Vector3.ZERO
