extends RefCounted

# Junta formas como o Kit, mas reparte por pedaço do mapa e por tipo de superfície.
# - Pedaços menores: no renderizador de compatibilidade cada objeto recebe no máximo 8 luzes;
#   um chão único do tamanho da cidade fazia os postes "piscarem" quando mudavam de lugar.
# - Tipos de superfície: asfalto, calçada, metal pintado e vegetação reagem à chuva cada um do seu jeito.
# Use como um Kit comum: mude `cat` antes de desenhar cada grupo de peças.

const Kit = preload("res://world3d/mesh_kit.gd")
# chão rente: não projeta sombra (economiza o passe de sombra e evita serrilhado no asfalto)
const FLAT := ["asphalt", "walk"]

var size: float
var cat := "walk"
var count := 0
var kits: Dictionary = {}    # Vector2i -> {cat: Kit}


func _init(chunk: float = 80.0) -> void:
	size = chunk


func _k(p: Vector3) -> Kit:
	var cell := Vector2i.ZERO
	if size > 0.0:
		cell = Vector2i(floori(p.x / size), floori(p.z / size))
	var d: Dictionary = kits.get(cell, {})
	if d.is_empty():
		kits[cell] = d
	var k: Kit = d.get(cat)
	if k == null:
		k = Kit.new()
		k.cat = cat
		d[cat] = k
	count += 1
	return k


func add(kind: String, xf: Transform3D, color: Color) -> void:
	_k(xf.origin).add(kind, xf, color)


func box(center: Vector3, sz: Vector3, color: Color, rot_y: float = 0.0) -> void:
	_k(center).box(center, sz, color, rot_y)


func box_ab(a: Vector3, b: Vector3, color: Color) -> void:
	_k((a + b) / 2.0).box_ab(a, b, color)


func cyl(base: Vector3, radius: float, height: float, color: Color) -> void:
	_k(base).cyl(base, radius, height, color)


func cone(base: Vector3, radius: float, height: float, color: Color) -> void:
	_k(base).cone(base, radius, height, color)


func sphere(center: Vector3, sz: Vector3, color: Color) -> void:
	_k(center).sphere(center, sz, color)


func gable(center: Vector3, sz: Vector3, color: Color, ridge_x: bool = true) -> void:
	_k(center).gable(center, sz, color, ridge_x)


func disc(c: Vector3, rx: float, rz: float, col: Color, rot: float = 0.0, segs: int = 14, wobble: float = 0.0, inner_f: float = 0.55, mid_f: float = 0.55) -> void:
	_k(c).disc(c, rx, rz, col, rot, segs, wobble, inner_f, mid_f)


func soft_shadow(c: Vector3, rx: float, rz: float, alpha: float = 0.34, rot: float = 0.0, inner_f: float = 0.55, mid_f: float = 0.55) -> void:
	var keep := cat
	cat = "walk"
	_k(c).soft_shadow(c, rx, rz, alpha, rot, inner_f, mid_f)
	cat = keep


# Cria as malhas: por pedaço, uma rente ao chão (sem sombra) e outra com os objetos (com sombra).
func build(parent: Node3D, mats: Dictionary, fallback: Material) -> MeshInstance3D:
	var first: MeshInstance3D = null
	for cell in kits:
		var d: Dictionary = kits[cell]
		var flat: ArrayMesh = null
		var solid: ArrayMesh = null
		for c in d:
			var k: Kit = d[c]
			var m: Material = mats.get(c, fallback)
			if c in FLAT:
				flat = k.commit(m, flat)
			else:
				solid = k.commit(m, solid)
		# sombras de contato saem em malha própria, sempre sem projetar sombra
		for c in d:
			var shade: ArrayMesh = (d[c] as Kit).shadow_mesh()
			if shade != null:
				var sm := MeshInstance3D.new()
				sm.mesh = shade
				sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				parent.add_child(sm)
		for pair in [[flat, false], [solid, true]]:
			if pair[0] == null:
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = pair[0]
			if not pair[1]:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)
			if first == null:
				first = mi
	return first
