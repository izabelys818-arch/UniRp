extends RefCounted

# Texturas pequenas e compartilhadas, geradas por código. Preservam a cor/AO
# dos vértices e usam coordenadas do mundo: a escala não muda com cada caixa.
static var textures: Dictionary = {}

static func apply(m: StandardMaterial3D, kind: String, scale_m: float) -> void:
	if not textures.has(kind):
		var image := Image.create(256, 256, false, Image.FORMAT_RGB8)
		var noise := FastNoiseLite.new()
		noise.seed = 173 + absi(kind.hash()) % 500
		noise.frequency = 0.12
		noise.fractal_octaves = 3
		for y in 256:
			for x in 256:
				var grain := noise.get_noise_2d(x, y)
				var v := 0.94 + grain * 0.07
				if kind == "asphalt":
					v = 0.89 + grain * 0.13
				elif kind == "roof":
					var joint := y % 32 < 2 or (x + (16 if (y / 32) % 2 == 0 else 0)) % 48 < 2
					v = (0.74 if joint else 0.96) + grain * 0.025
				elif kind == "stone":
					v = 0.90 + grain * 0.12
				elif kind == "wood":
					var fibers := noise.get_noise_2d(x * 0.2, y)
					v = 0.94 + sin(x * 0.22 + fibers * 1.6) * 0.035 + fibers * 0.035
				image.set_pixel(x, y, Color(v, v, v))
		image.generate_mipmaps()
		textures[kind] = ImageTexture.create_from_image(image)
	m.albedo_texture = textures[kind]
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale_m
	m.uv1_triplanar_sharpness = 8.0
