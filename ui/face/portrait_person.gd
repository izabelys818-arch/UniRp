extends "res://world3d/person.gd"

var oral_parts: Array[MeshInstance3D] = []

# Mesma anatomia da pessoa do mundo. A câmera próxima pede movimento mais
# legível do maxilar; o rosto neutro e os controles físicos não são alterados.
func _face_signature() -> String:
	return super._face_signature() + "_portrait_v1"


func _face_shape(name: String, arr: Array, f: Dictionary, names: Array) -> PackedVector3Array:
	var result := super._face_shape(name, arr, f, names)
	if name == "queixo":
		var original: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in result.size():
			result[i] = original[i] + (result[i] - original[i]) * 3.0
	return result


func _build() -> void:
	super._build()
	if skel == null or _anatomy.is_empty():
		return
	var anchor := BoneAttachment3D.new()
	anchor.bone_name = "Head"
	skel.add_child(anchor)
	var rest := skel.get_bone_global_rest(_head).affine_inverse()
	var nose: Vector3 = _anatomy["nose"]
	var mouth := Vector3(0, _anatomy["mouth_y"], nose.z - 0.03)
	mouth = HumanStyle.sculpt(mouth, _anatomy, look)
	var inside := MeshInstance3D.new()
	var cavity := SphereMesh.new()
	cavity.radius = 0.023 * float(look.get("mouth_w", 1.0))
	cavity.height = 0.027
	cavity.radial_segments = 24
	cavity.rings = 12
	inside.mesh = cavity
	inside.scale.z = 0.18
	inside.position = rest * (mouth - Vector3(0, 0.006, 0))
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("#30141a")
	dark.roughness = 1.0
	inside.material_override = dark
	oral_parts.append(inside)
	anchor.add_child(inside)
	var enamel := StandardMaterial3D.new()
	enamel.albedo_color = Color("#cfc9b7")
	enamel.roughness = 0.38
	for i in 8:
		var tooth := MeshInstance3D.new()
		var shape := SphereMesh.new()
		shape.radius = 0.0025
		shape.height = 0.005
		shape.radial_segments = 10
		shape.rings = 6
		tooth.mesh = shape
		var x := (i - 3.5) * 0.0045 * float(look.get("mouth_w", 1.0))
		tooth.position = rest * (mouth + Vector3(x, -0.001, 0.008 - absf(x) * 0.12))
		tooth.material_override = enamel
		if i == 3 and (10 in look.get("marks", []) or "dente_ouro" in look.get("extras", [])):
			var gold := enamel.duplicate() as StandardMaterial3D
			gold.albedo_color = Color("#b99a4c")
			gold.metallic = 0.7
			tooth.material_override = gold
		oral_parts.append(tooth)
		anchor.add_child(tooth)
