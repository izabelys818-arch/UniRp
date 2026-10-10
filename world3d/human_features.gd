extends RefCounted

# Acessórios e marcas compartilhados pelo mundo e pelo retrato.
# Primitivas pequenas acompanham os ossos; nenhuma imagem externa ou de IA.
const MARKS = preload("res://world3d/human_marks.gdshader")


static func material(color: Color, metal: bool = false) -> StandardMaterial3D:
	var out := StandardMaterial3D.new()
	out.albedo_color = color
	out.roughness = 0.3 if metal else 0.8
	out.metallic = 0.65 if metal else 0.0
	return out


static func mesh(anchor: Node3D, inverse: Transform3D, geometry: Mesh, point: Vector3, mat: Material) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = geometry
	item.material_override = mat
	item.position = inverse * point
	anchor.add_child(item)
	return item


static func ring(anchor: Node3D, inverse: Transform3D, point: Vector3, radius: float, width: float, mat: Material, stretch := Vector3.ONE) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = radius - width
	torus.outer_radius = radius
	torus.rings = 24
	torus.ring_segments = 8
	var item := mesh(anchor, inverse, torus, point, mat)
	item.rotation.x = PI * 0.5
	item.scale = stretch


static func rod(anchor: Node3D, inverse: Transform3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = a.distance_to(b)
	cylinder.radial_segments = 8
	var item := mesh(anchor, inverse, cylinder, (a + b) * 0.5, mat)
	item.quaternion = Quaternion(Vector3.UP, (b - a).normalized())


static func glasses(anchor: Node3D, inverse: Transform3D, eyes: Array, nose: Vector3, sunglasses: bool = false, lift: float = 0.0) -> void:
	var frame := material(Color("#24242b"), true)
	var lens := material(Color(0.2, 0.27, 0.32, 0.08))
	lens.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if sunglasses:
		lens.albedo_color = Color(0.035, 0.055, 0.067, 0.92)
	for eye in eyes:
		var c: Vector3 = eye + Vector3(0, lift, 0.012)
		ring(anchor, inverse, c, 0.025, 0.0017, frame, Vector3(1.0, 1.0, 0.72))
		var disc := CylinderMesh.new()
		disc.top_radius = 0.023
		disc.bottom_radius = 0.023
		disc.height = 0.0006
		disc.radial_segments = 32
		var glass := mesh(anchor, inverse, disc, c, lens)
		glass.rotation.x = PI * 0.5
		glass.scale.z = 0.72
		var side := signf(c.x)
		rod(anchor, inverse, c + Vector3(side * 0.023, 0, 0), Vector3(side * 0.078, c.y, nose.z - 0.083), 0.0013, frame)
	rod(anchor, inverse, Vector3(-0.008, eyes[0].y + lift, eyes[0].z + 0.012), Vector3(0.008, eyes[1].y + lift, eyes[1].z + 0.012), 0.0012, frame)


static func apply(person: Node3D) -> void:
	if person.skel == null or person._anatomy.is_empty():
		return
	var chosen: Array = person.look.get("marks", [])
	var extras: Array = person.look.get("extras", [])
	if chosen.is_empty() and extras.is_empty():
		return
	var anatomy: Dictionary = person._anatomy
	var nose: Vector3 = person.HumanStyle.sculpt(anatomy["nose"], anatomy, person.look)
	var eyes: Array = [person.HumanStyle.sculpt(anatomy["eye_l"], anatomy, person.look), person.HumanStyle.sculpt(anatomy["eye_r"], anatomy, person.look)]
	var eye_y: float = (eyes[0].y + eyes[1].y) * 0.5
	if not chosen.is_empty():
		var pigment := ShaderMaterial.new()
		pigment.shader = MARKS
		pigment.set_shader_parameter("nose", nose)
		pigment.set_shader_parameter("eye_y", eye_y)
		pigment.set_shader_parameter("marks_a", Vector4(float(0 in chosen), float(1 in chosen), float(2 in chosen), float(6 in chosen)))
		pigment.set_shader_parameter("marks_b", Vector4(float(9 in chosen), float(13 in chosen), float(15 in chosen), float(17 in chosen)))
		person._face_mi.material_override.next_pass = pigment
		person.body_mi.material_override.next_pass = pigment
	var anchor := BoneAttachment3D.new()
	anchor.name = "HumanAccessories"
	anchor.bone_name = "Head"
	person.skel.add_child(anchor)
	var inverse: Transform3D = person.skel.get_bone_global_rest(person._head).affine_inverse()
	var gold := material(Color("#b39548"), true)
	var silver := material(Color("#aeb8bf"), true)
	if 7 in chosen or 8 in chosen:
		glasses(anchor, inverse, eyes, nose, 8 in chosen)
	if "oculos_testa" in extras:
		glasses(anchor, inverse, eyes, nose, false, 0.052)
	if 3 in chosen:
		ring(anchor, inverse, nose + Vector3(-0.013, -0.009, 0.001), 0.004, 0.0008, silver)
	if 5 in chosen:
		ring(anchor, inverse, eyes[1] + Vector3(0.013, 0.019, -0.005), 0.0036, 0.0007, silver)
	if 4 in chosen or 14 in chosen:
		for side in [-1.0, 1.0]:
			var ear := Vector3(side * 0.079, eye_y - 0.027, nose.z - 0.071)
			if 14 in chosen:
				ring(anchor, inverse, ear - Vector3(0, 0.008, 0), 0.012, 0.0014, gold)
			if 4 in chosen:
				for offset in 3:
					ring(anchor, inverse, ear + Vector3(0, offset * 0.006, 0), 0.003, 0.0008, silver)
	if 11 in chosen or "chapeu" in extras:
		var cloth := material(Color("#353c45"))
		var cap := SphereMesh.new()
		cap.radius = 0.091
		cap.height = 0.09
		cap.is_hemisphere = true
		mesh(anchor, inverse, cap, Vector3(0, eye_y + 0.046, nose.z - 0.073), cloth)
		var brim := BoxMesh.new()
		brim.size = Vector3(0.15, 0.006, 0.067)
		mesh(anchor, inverse, brim, Vector3(0, eye_y + 0.049, nose.z + 0.006), cloth)
		for key in person._human_parts:
			if str(key).begins_with("HumanHair_"):
				person._human_parts[key].visible = false
	if 12 in chosen:
		var neck := BoneAttachment3D.new()
		neck.bone_name = "neck_01"
		person.skel.add_child(neck)
		var ni: Transform3D = person.skel.get_bone_global_rest(person._neck).affine_inverse()
		for side in [-1.0, 1.0]:
			var previous := Vector3(side * 0.047, eye_y - 0.145, nose.z - 0.07)
			for i in 8:
				var u := float(i + 1) / 8.0
				var point := Vector3(side * 0.047 * (1.0 - u), eye_y - 0.145 - 0.085 * sin(u * PI * 0.5), nose.z - 0.07 + 0.052 * u)
				rod(neck, ni, previous, point, 0.0012, gold)
				previous = point
	if "fone" in extras:
		var rubber := material(Color("#20242b"))
		for side in [-1.0, 1.0]:
			var cup := SphereMesh.new()
			cup.radius = 0.019
			cup.height = 0.047
			mesh(anchor, inverse, cup, Vector3(side * 0.089, eye_y - 0.009, nose.z - 0.06), rubber)
			rod(anchor, inverse, Vector3(side * 0.091, eye_y, nose.z - 0.06), Vector3(side * 0.073, eye_y + 0.1, nose.z - 0.06), 0.004, rubber)
		rod(anchor, inverse, Vector3(-0.073, eye_y + 0.1, nose.z - 0.06), Vector3(0.073, eye_y + 0.1, nose.z - 0.06), 0.004, rubber)
	if "bobes" in extras:
		var roller := material(Color("#8c6977"))
		for i in 5:
			rod(anchor, inverse, Vector3((i - 2) * 0.024, eye_y + 0.082, nose.z - 0.024), Vector3((i - 2) * 0.024, eye_y + 0.089, nose.z - 0.053), 0.01, roller)
	if "toalha" in extras:
		var towel := BoxMesh.new()
		towel.size = Vector3(0.18, 0.042, 0.085)
		mesh(anchor, inverse, towel, Vector3(0, eye_y - 0.23, nose.z - 0.02), material(Color("#c1bbab")))
