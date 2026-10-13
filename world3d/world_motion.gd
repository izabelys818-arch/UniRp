extends RefCounted

static var cloth_material: ShaderMaterial
static var smoke_material: ShaderMaterial

static func cloth() -> ShaderMaterial:
	if cloth_material != null:
		return cloth_material
	cloth_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
global uniform vec3 world_wind;
uniform vec4 tint : source_color = vec4(0.38, 0.43, 0.36, 1.0);
void vertex() {
	VERTEX.z += sin(TIME * 2.5 + VERTEX.x * 6.0) * UV.y * UV.y * 0.12 * length(world_wind);
}
void fragment() {
	float threads = 0.88 + 0.12 * sin(UV.x * 400.0) * sin(UV.y * 400.0);
	ALBEDO = tint.rgb * threads;
	ROUGHNESS = 0.94;
}
"""
	cloth_material.shader = shader
	return cloth_material

static func banner(parent: Node3D, point: Vector3) -> void:
	var node := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.25, 1.8)
	node.mesh = quad
	node.material_override = cloth()
	node.position = point
	node.visibility_range_end = 90.0
	node.visibility_range_end_margin = 12.0
	parent.add_child(node)

static func jet(parent: Node3D, point: Vector3, material: Material) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = 48
	particles.lifetime = 1.1
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.08
	particles.direction = Vector3.UP
	particles.spread = 15.0
	particles.initial_velocity_min = 3.5
	particles.initial_velocity_max = 4.3
	particles.gravity = Vector3(0, -9.8, 0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.09
	mesh.radial_segments = 4
	mesh.rings = 2
	mesh.material = material
	particles.mesh = mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.position = point
	particles.emitting = false
	parent.add_child(particles)
	return particles

static func smoke(parent: Node3D, point: Vector3) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = 8
	particles.lifetime = 3.5
	particles.direction = Vector3.UP
	particles.spread = 15
	particles.initial_velocity_min = 0.4
	particles.initial_velocity_max = 0.8
	particles.gravity = Vector3(0.12, 0.15, 0.07)
	particles.scale_amount_min = 0.3
	particles.scale_amount_max = 0.7
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1, 1)
	if smoke_material == null:
		smoke_material = ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void fragment() {
	float radial = 1.0 - smoothstep(0.1, 0.5, length(UV - vec2(0.5)));
	float pattern = 0.7 + 0.3 * sin(UV.x * 16.0 + TIME) * cos(UV.y * 13.0 - TIME);
	ALBEDO = vec3(0.53, 0.54, 0.52);
	ALPHA = radial * pattern * 0.18;
}
"""
		smoke_material.shader = shader
	mesh.material = smoke_material
	particles.mesh = mesh
	particles.position = point
	particles.emitting = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(particles)
	return particles
