extends Node3D

# Confere na GPU o mesmo shader usado pela cidade. A saída diagnóstica codifica
# a normal em RGB; texturas planas isolam orientação da geometria e escala.
const OUT := "C:/Users/glznc/Documents/Codex/2026-10-12/camera_dupla"
var failures: Array[String] = []

func texture_array(count: int, color: Color) -> Texture2DArray:
	var images: Array[Image] = []
	for i in count:
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(color)
		images.append(image)
	var result := Texture2DArray.new()
	result.create_from_images(images)
	return result

func _ready() -> void:
	get_window().size = Vector2i(512, 512)
	Engine.max_fps = 60
	for parameter in ["wetness", "rain_time", "night_glow", "grime", "cloud_shade", "pom_quality"]:
		RenderingServer.global_shader_parameter_set(parameter, 0.0)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	add_child(environment)
	var source := FileAccess.get_file_as_string("res://world3d/surface.gdshader")
	var before := OS.get_environment("SURFACE_BEFORE") == "1"
	if before:
		source = FileAccess.get_file_as_string(OUT + "/source_before/world3d/surface.gdshader")
	source = source.replace("render_mode blend_mix,", "render_mode unshaded, blend_mix,")
	source = source.replace("ALBEDO = alb;", "ALBEDO = world_n * 0.5 + 0.5;")
	var shader := Shader.new()
	shader.code = source
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("ground_albedo", texture_array(4, Color.WHITE))
	material.set_shader_parameter("surf_albedo", texture_array(17, Color.WHITE))
	material.set_shader_parameter("ground_nr", texture_array(4, Color(0.5, 0.5, 1)))
	material.set_shader_parameter("surf_nr", texture_array(17, Color(0.5, 0.5, 1)))
	material.set_shader_parameter("height_tex", texture_array(21, Color.WHITE))
	var noise := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	noise.fill(Color(0.5, 0.5, 0.5))
	material.set_shader_parameter("macro_noise", ImageTexture.create_from_image(noise))
	material.set_shader_parameter("layer_tile", PackedFloat32Array(Array(range(24)).map(func(_i): return 1.0)))
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.material_override = material
	add_child(box)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.4
	camera.near = 0.05
	add_child(camera)
	camera.make_current()
	var values := []
	var axes := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for basis in [Basis.IDENTITY, Basis.from_euler(Vector3(0.54, 0.4, 0.3)).scaled(Vector3(2, 0.6, 1.2))]:
		box.basis = basis
		for axis in axes:
			var expected: Vector3 = (basis.inverse().transposed() * axis).normalized()
			var center: Vector3 = basis * axis * 0.5
			camera.position = center + expected * 4.0
			camera.look_at(center, Vector3.UP if absf(expected.y) < 0.99 else Vector3.FORWARD)
			for frame in 5:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			var pixel := image.get_pixel(image.get_width() / 2, image.get_height() / 2).srgb_to_linear()
			var actual := Vector3(pixel.r, pixel.g, pixel.b) * 2.0 - Vector3.ONE
			var error := actual.distance_to(expected)
			values.append({"axis": str(axis), "expected": str(expected), "actual": str(actual), "error": error})
			print("SURFACE CHECK ", "OK " if error < 0.035 else "FAIL ", axis, " error=", error)
			if error >= 0.035:
				failures.append(str(axis))
	var file := FileAccess.open(OUT + ("/surface_before.json" if before else "/surface_after.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"values": values, "failures": failures}, "\t"))
	print("SURFACE RESULT failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
