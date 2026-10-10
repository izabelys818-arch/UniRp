extends RefCounted

# Anatomia e materiais de pessoas comuns. O corpo continua usando o rig da UAL;
# só a cabeça compacta é individualizada, sem duplicar o corpo em cada morador.
static var _parts: Dictionary = {}
static var _eyes: Dictionary = {}


static func cleanup() -> void:
	_parts.clear()
	_eyes.clear()


static func eye_texture(color: Color) -> Texture2D:
	var key := color.to_html()
	if _eyes.has(key):
		return _eyes[key]
	var source: Texture2D = load("res://assets/humans/eyes.png")
	var img := source.get_image()
	if img.is_compressed():
		img.decompress()
	img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			# Preserve sclera, limbal ring and pupil; tint the photographed iris.
			var iris := clampf((c.r - c.b) * 8.0, 0.0, 1.0) * smoothstep(0.03, 0.18, c.get_luminance())
			var tinted := color * clampf(c.get_luminance() / 0.25, 0.25, 1.8)
			img.set_pixel(x, y, c.lerp(tinted, iris))
	var tex := ImageTexture.create_from_image(img)
	_eyes[key] = tex
	return tex


static func beard_arrays(src: Array, head_bind: int, f: Dictionary, style: String) -> Array:
	var input: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var normals_in: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var vertices := PackedVector3Array()
	var ns := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	var uv := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9137
	var my: float = f["mouth_y"]
	var nose: Vector3 = f["nose"]
	for i in input.size():
		var p := input[i]
		if p.y < my - 0.073 or p.y > my + 0.026 or p.z < nose.z - 0.075 or absf(p.x) > 0.071:
			continue
		if normals_in[i].z < 0.1:
			continue
		var upper_lip := p.y > my + 0.003 and p.y < my + 0.022 and absf(p.x) < 0.032
		if style in ["mustache", "mustache_thin"] and not upper_lip:
			continue
		if style == "mustache_thin" and p.y < my + 0.013:
			continue
		if style == "goatee" and absf(p.x) > 0.026:
			continue
		if style == "sideburns" and absf(p.x) < 0.052:
			continue
		if not upper_lip and p.y > my + 0.001 and absf(p.x) < 0.043:
			continue
		if absf(p.y - my) < 0.005 and absf(p.x) < float(f["mouth_x"]) * 1.15:
			continue
		for strand in 3:
			var n := normals_in[i]
			var root := p + Vector3(rng.randf_range(-0.0015, 0.0015), rng.randf_range(-0.0015, 0.0015), 0) + n * 0.0008
			var length := rng.randf_range(0.004, 0.009) * (2.4 if style == "long" else (0.65 if style in ["short", "mustache_thin"] else 1.0))
			var tip := root + (n * 0.6 + Vector3(0, -0.8, 0)).normalized() * length
			var width := Vector3(0.00035, 0, 0)
			var start := vertices.size()
			for q in [root - width, root + width, tip]:
				vertices.append(q)
				ns.append(n)
				uv.append(Vector2.ZERO)
				bones.append_array(PackedInt32Array([head_bind, 0, 0, 0]))
				weights.append_array(PackedFloat32Array([1, 0, 0, 0]))
			indices.append_array(PackedInt32Array([start, start + 1, start + 2]))
	if vertices.is_empty():
		return []
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vertices
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	arr[Mesh.ARRAY_INDEX] = indices
	return arr


static func muted(c: Color, amount: float = 0.16) -> Color:
	var gray := Color(c.get_luminance(), c.get_luminance(), c.get_luminance(), c.a)
	return c.lerp(gray, amount)


static func normals(verts: PackedVector3Array, idx: PackedInt32Array, old: PackedVector3Array) -> PackedVector3Array:
	var sums := {}
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var n := (c - a).cross(b - a)
		for j in 3:
			var vi: int = idx[t + j]
			var key := Vector3i((verts[vi] * 10000.0).round())
			sums[key] = (sums.get(key, Vector3.ZERO) as Vector3) + n
	var out := old.duplicate()
	for v in verts.size():
		var n: Vector3 = sums.get(Vector3i((verts[v] * 10000.0).round()), Vector3.ZERO)
		if n.length_squared() > 0.00000001:
			n = n.normalized()
			if n.dot(old[v]) < 0.0:
				n = -n
			out[v] = n
	return out


# Suavização de volume dos membros: remove o bíceps/panturrilha esculpidos do
# modelo de herói, preservando punhos, dedos, joelhos e todos os pesos de pele.
static func split(src: Mesh, key: String, face: Dictionary) -> Dictionary:
	if _parts.has(key):
		return _parts[key]
	var arr := src.surface_get_arrays(0)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var hw: PackedFloat32Array = face["head_w"]
	var head_idx := PackedInt32Array()
	var body_idx := PackedInt32Array()
	for t in range(0, idx.size(), 3):
		var is_head := (hw[idx[t]] + hw[idx[t + 1]] + hw[idx[t + 2]]) / 3.0 > 0.5
		for j in 3:
			if is_head:
				head_idx.append(idx[t + j])
			else:
				body_idx.append(idx[t + j])
	var body := ArrayMesh.new()
	var ba := arr.duplicate()
	ba[Mesh.ARRAY_INDEX] = body_idx
	body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ba, [], {}, src.surface_get_format(0) & ~Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
	body.surface_set_material(0, src.surface_get_material(0))
	var remap := {}
	var ids := PackedInt32Array()
	var compact_idx := PackedInt32Array()
	for i in head_idx:
		if not remap.has(i):
			remap[i] = ids.size()
			ids.append(i)
		compact_idx.append(remap[i])
	var ha: Array = []
	ha.resize(Mesh.ARRAY_MAX)
	var vv := PackedVector3Array()
	var nn := PackedVector3Array()
	var uv := PackedVector2Array()
	var bb := PackedInt32Array()
	var ww := PackedFloat32Array()
	var hh := PackedFloat32Array()
	var per: int = (arr[Mesh.ARRAY_BONES] as PackedInt32Array).size() / maxi((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 1)
	for i in ids:
		vv.append(arr[Mesh.ARRAY_VERTEX][i])
		nn.append(arr[Mesh.ARRAY_NORMAL][i])
		uv.append(arr[Mesh.ARRAY_TEX_UV][i])
		hh.append(hw[i])
		for j in per:
			bb.append(arr[Mesh.ARRAY_BONES][i * per + j])
			ww.append(arr[Mesh.ARRAY_WEIGHTS][i * per + j])
	ha[Mesh.ARRAY_VERTEX] = vv
	ha[Mesh.ARRAY_NORMAL] = nn
	ha[Mesh.ARRAY_TEX_UV] = uv
	ha[Mesh.ARRAY_BONES] = bb
	ha[Mesh.ARRAY_WEIGHTS] = ww
	ha[Mesh.ARRAY_INDEX] = compact_idx
	var marks := face.duplicate()
	marks["head_w"] = hh
	# hm08 já tem loops de rosto suficientes; mantém a anatomia original.
	var result := {"body": body, "head": ha, "face": marks, "flags": src.surface_get_format(0) & ~Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES}
	_parts[key] = result
	return result


static func bump(p: Vector3, center: Vector3, radius: Vector3) -> float:
	var d := (p - center) / radius
	return exp(-d.length_squared() * 2.0)


# Mesma transformação contínua aplicada à pele, olhos, sobrancelhas e cabelo.
# Os olhos permanecem encaixados quando mudam nariz, maçãs e mandíbula.
static func sculpt(p: Vector3, f: Dictionary, look: Dictionary) -> Vector3:
	var nose: Vector3 = f["nose"]
	var el: Vector3 = f["eye_l"]
	var er: Vector3 = f["eye_r"]
	var eye_y := (el.y + er.y) * 0.5
	var my: float = f["mouth_y"]
	var center := Vector3(0.0, eye_y - 0.015, nose.z - 0.065)
	var q := p
	# Valores neutros relativos à anatomia de cada base humana.
	var female: bool = look.get("gender", "homem") == "mulher"
	var jaw_base := 0.6536 if female else 0.836
	var chin_base := 0.2788 if female else 0.408
	var jaw_zone := exp(-pow((p.y - my + 0.013) / 0.046, 2.0))
	# Mandíbula menos quadrada no adulto médio, mantendo a escolha de rosto.
	q.x *= 1.0 + (float(look.get("jaw", 0.76)) - jaw_base) * 0.55 * jaw_zone
	var chin_zone := bump(p, Vector3(0, my - 0.035, nose.z - 0.014), Vector3(0.05, 0.03, 0.06))
	q.x *= 1.0 + (float(look.get("chin_w", 0.34)) - chin_base) * 1.7 * chin_zone
	q.z += (float(look.get("chin_w", 0.34)) - chin_base) * 0.035 * chin_zone
	var nose_zone := bump(p, nose - Vector3(0, 0.006, 0.01), Vector3(0.033, 0.043, 0.055))
	q.x *= 1.0 + (float(look.get("nose_w", 1.0)) / (0.861 if female else 1.134) - 1.0) * nose_zone * 0.8
	q.z += (float(look.get("nose_len", 1.0)) / (0.9 if female else 1.05) - 1.0) * 0.043 * nose_zone
	q.y -= (float(look.get("nose_len", 1.0)) / (0.9 if female else 1.05) - 1.0) * 0.017 * nose_zone
	if 16 in look.get("marks", []):
		q.x += 0.006 * nose_zone
	var mouth_zone := bump(p, Vector3(0, my, nose.z - 0.016), Vector3(0.055, 0.022, 0.044))
	q.x *= 1.0 + (float(look.get("mouth_w", 1.0)) - 1.0) * mouth_zone
	q.y += (p.y - my) * (float(look.get("lips", 1.0)) / (1.365 if female else 0.84) - 1.0) * mouth_zone * 0.65
	q.z += (float(look.get("lips", 1.0)) / (1.365 if female else 0.84) - 1.0) * 0.007 * mouth_zone
	var hollow: float = 0.006 if look.get("hollow", false) else 0.0
	var age := clampf((float(look.get("age", 30)) - 35.0) / 50.0, 0.0, 1.0)
	for side in [-1.0, 1.0]:
		var cheek := bump(p, Vector3(side * 0.052, my + 0.009, nose.z - 0.029), Vector3(0.027, 0.037, 0.042))
		q.z += ((float(look.get("cheek", 1.0)) - 1.0) * 0.035 - hollow - age * 0.003) * cheek
		var ec: Vector3 = el if side < 0.0 else er
		var eye_zone := bump(p, ec, Vector3(0.03, 0.023, 0.04))
		var size := clampf(float(look.get("eye_size", 1.0)) / (1.12 if female else 0.92), 0.75, 1.25)
		q.x += (p.x - ec.x) * (size - 1.0) * eye_zone
		q.y += (p.y - ec.y) * (size * float(look.get("eye_h", 1.0)) - 1.0) * eye_zone
		q.y += (p.x - ec.x) * side * float(look.get("eye_tilt", 0.0)) * 0.28 * eye_zone
		var ear := bump(p, Vector3(side * 0.087, eye_y - 0.01, center.z), Vector3(0.025, 0.055, 0.045))
		q.x += side * (float(look.get("ear_out", 1.0)) - 1.0) * 0.023 * ear
		q.y += (p.y - eye_y + 0.01) * (float(look.get("ear_size", 1.0)) - 1.0) * ear
	# Perfil individual, aplicado também às peças do rosto para manter o encaixe.
	var spacing_zone := exp(-pow((p.y - eye_y) / 0.045, 2.0))
	q.x += p.x * (float(look.get("eye_spacing", 1.0)) - 1.0) * spacing_zone
	q.z += float(look.get("nose_bridge", 0.0)) * bump(p, nose + Vector3(0, 0.022, -0.015), Vector3(0.018, 0.037, 0.045))
	q.y -= float(look.get("chin_length", 0.0)) * chin_zone
	q.z += float(look.get("forehead", 0.0)) * bump(p, Vector3(0, eye_y + 0.055, nose.z - 0.035), Vector3(0.085, 0.046, 0.055))
	q.x += float(look.get("asymmetry", 0.0)) * (nose_zone * 0.75 + mouth_zone * 0.5)
	return q


# Pigmento do rosto: olheiras, lábios, barba por fazer, maçãs e sulcos discretos.
# Multiplicadores de cor por vértice, sem textura gerada nem custo por quadro.
static func pigment(p: Vector3, f: Dictionary, look: Dictionary) -> Color:
	var nose: Vector3 = f["nose"]
	var my: float = f["mouth_y"]
	var age := clampf((float(look.get("age", 30)) - 23.0) / 60.0, 0.0, 1.0)
	var wear: float = maxf(age, 0.7 if look.get("weathered", false) else float(look.get("rugas", 0.0)) * 0.6)
	var col := Color.WHITE
	var lips := bump(p, Vector3(0, my, nose.z - 0.014), Vector3(0.034 * float(look.get("mouth_w", 1.0)), 0.0085, 0.024))
	col = col.lerp(Color(0.82, 0.64, 0.64), lips * 0.8)
	var seam := bump(p, Vector3(0, my, nose.z - 0.012), Vector3(0.038, 0.0025, 0.025))
	col = col.lerp(Color(0.37, 0.32, 0.32), seam * 0.65)
	for e in [f["eye_l"], f["eye_r"]]:
		var ec: Vector3 = e
		var bag := bump(p, ec + Vector3(0, -0.012, -0.004), Vector3(0.029, 0.009, 0.028))
		col = col.lerp(Color(0.61, 0.57, 0.62), bag * (0.38 + wear * 0.35))
		var socket := bump(p, ec + Vector3(0, 0.009, -0.003), Vector3(0.028, 0.012, 0.029))
		col = col.lerp(Color(0.68, 0.62, 0.61), socket * 0.34)
	for side in [-1.0, 1.0]:
		var crease := bump(p, Vector3(side * 0.026, my + 0.009, nose.z - 0.02), Vector3(0.007, 0.025, 0.04))
		col = col.lerp(Color(0.67, 0.61, 0.61), crease * wear * 0.42)
		var cheek := bump(p, Vector3(side * 0.052, my + 0.024, nose.z - 0.02), Vector3(0.025, 0.03, 0.025))
		col = col.lerp(Color(0.98, 0.85, 0.83), cheek * 0.28)
	if str(look.get("beard", "none")) == "stubble" and int(look.get("age", 30)) >= 18:
		var beard := smoothstep(my + 0.018, my - 0.025, p.y) * smoothstep(nose.z - 0.08, nose.z - 0.015, p.z)
		col = col.lerp(Color(0.49, 0.49, 0.48), beard * 0.48)
	return col
