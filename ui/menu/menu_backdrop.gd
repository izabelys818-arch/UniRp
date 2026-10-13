extends SubViewportContainer

# Fundo da tela inicial: a cidade do jogo em 3D no fim de tarde, com névoa, poeira no ar e a
# câmera passeando devagar sobre os telhados, como um plano de abertura.

const Layout = preload("res://world3d/city_layout.gd")
const CityBuilder = preload("res://world3d/city_builder.gd")
const Life = preload("res://world3d/life.gd")

var vp: SubViewport
var cam: Camera3D
var city: CityBuilder
var life: Life
var sun: DirectionalLight3D
var t: float = 0.0
var ready_city: bool = false
var motes: CPUParticles3D
var lamps: Array = []
var _shake: float = 0.0
# sombras de nuvens atravessando a cidade e fumaça de chaminés: o plano de abertura respira
var clouds: Array = []
var sun_base := Vector3.ZERO


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.handle_input_locally = false
	add_child(vp)
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.near = 0.6
	cam.far = 900.0
	vp.add_child(cam)
	cam.current = true
	cam.position = Vector3(40, 30, 40)
	cam.look_at(Vector3(165, 6, 165))
	# a cidade é montada depois do primeiro quadro, com a tela ainda preta
	_build_later.call_deferred()


func _environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#1c2a45")
	sky_mat.sky_horizon_color = Color("#c08068")
	sky_mat.ground_horizon_color = Color("#6b4a45")
	sky_mat.ground_bottom_color = Color("#1a1618")
	sky_mat.sky_curve = 0.18
	sky_mat.sun_angle_max = 18.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#3b4a68")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color("#7e6c74")
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.25
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(-deg_to_rad(11.0), deg_to_rad(-58.0), 0.0)
	sun.light_color = Color("#ffbd88")
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_blur = 1.2
	vp.add_child(sun)


func _build_later() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_queued_for_deletion() or not is_inside_tree():
		return
	# O céu só é criado quando a tela realmente permanece aberta. Cancelar o
	# menu antes do primeiro quadro deixava duas texturas pendentes no GLES3.
	_environment()
	var layout := Layout.new()
	city = CityBuilder.new()
	vp.add_child(city)
	city.build(layout)
	city.lit_mat.albedo_color = Color(1.0, 0.97, 0.92)
	# chão até o horizonte, para a cidade não terminar numa borda
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("#3a3d2c")
	gm.roughness = 1.0
	pm.material = gm
	ground.mesh = pm
	ground.position = Vector3(Layout.SIZE * 0.5, -0.25, Layout.SIZE * 0.5)
	vp.add_child(ground)
	life = Life.new()
	vp.add_child(life)
	life.setup(layout, city, false)
	# postes acesos ao longo do percurso
	var spots: Array = city.lamp_spots.duplicate()
	spots.shuffle()
	for i in mini(14, spots.size()):
		var l := OmniLight3D.new()
		l.position = spots[i]
		l.light_color = Color("#ffc785")
		l.light_energy = 2.2
		l.omni_range = 16.0
		l.omni_attenuation = 1.3
		vp.add_child(l)
		lamps.append(l)
	# poeira e cinzas no ar
	motes = CPUParticles3D.new()
	motes.amount = 260
	motes.lifetime = 9.0
	motes.preprocess = 9.0
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(40, 10, 40)
	motes.direction = Vector3(1, 0.1, 0.2)
	motes.spread = 40.0
	motes.gravity = Vector3(0.1, -0.05, 0)
	motes.initial_velocity_min = 0.4
	motes.initial_velocity_max = 1.4
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.09)
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(1.0, 0.85, 0.65, 0.55)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.material = mm
	motes.mesh = qm
	vp.add_child(motes)
	_add_clouds()
	_add_smoke()
	sun_base = sun.rotation
	ready_city = true


func _add_clouds() -> void:
	var k := preload("res://world3d/mesh_kit.gd").new()
	k.disc(Vector3.ZERO, 0.5, 0.5, Color(0.04, 0.03, 0.06, 0.32), 0.0, 24, 0.25, 0.45, 0.6)
	var mesh := k.commit(preload("res://world3d/mesh_kit.gd").shadow_material())
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for i in 7:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sz := rng.randf_range(38.0, 70.0)
		mi.scale = Vector3(sz * rng.randf_range(1.2, 1.8), 1.0, sz)
		mi.rotation.y = rng.randf() * PI
		mi.position = Vector3(rng.randf_range(-60.0, Layout.SIZE + 60.0), 9.0, rng.randf_range(-60.0, Layout.SIZE + 60.0))
		vp.add_child(mi)
		clouds.append(mi)


func _add_smoke() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var houses: Array = city.structures.filter(func(s): return s.has("lot"))
	for i in mini(9, houses.size()):
		var s: Dictionary = houses[rng.randi() % houses.size()]
		var c: Vector2 = (s["rect"] as Rect2).get_center()
		var sm := CPUParticles3D.new()
		sm.amount = 18
		sm.lifetime = 5.0
		sm.preprocess = 5.0
		sm.direction = Vector3(0.3, 1, 0.1)
		sm.spread = 12.0
		sm.gravity = Vector3(0.25, 0.15, 0.05)
		sm.initial_velocity_min = 0.5
		sm.initial_velocity_max = 0.9
		sm.scale_amount_min = 1.0
		sm.scale_amount_max = 2.6
		var qm := QuadMesh.new()
		qm.size = Vector2(0.9, 0.9)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.72, 0.68, 0.7, 0.16)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		qm.material = m
		sm.mesh = qm
		sm.position = Vector3(c.x + rng.randf_range(-2, 2), 6.2, c.y + rng.randf_range(-2, 2))
		vp.add_child(sm)


func _process(delta: float) -> void:
	t += delta
	if not ready_city:
		return
	# órbita lenta sobre a cidade, com leve balanço de câmera na mão
	var center := Vector3(Layout.SIZE * 0.5, 0.0, Layout.SIZE * 0.5)
	var a := 0.6 + t * 0.018
	var radius := 96.0 + sin(t * 0.05) * 14.0
	var h := 21.0 + sin(t * 0.09) * 5.0
	var p := center + Vector3(cos(a) * radius, h, sin(a) * radius)
	_shake = lerpf(_shake, randf() - 0.5, delta * 3.0)
	p += Vector3(sin(t * 0.7) * 0.25, sin(t * 1.1) * 0.18, cos(t * 0.6) * 0.25)
	cam.position = p
	var look := center + Vector3(sin(t * 0.04) * 22.0, 7.0 + sin(t * 0.07) * 2.0, cos(t * 0.05) * 22.0)
	cam.look_at(look, Vector3.UP)
	cam.rotation.z += sin(t * 0.5) * 0.006 + _shake * 0.002
	motes.position = p + Vector3(0, -2, 0)
	# nuvens passando (as sombras andam com o vento) e o sol descendo devagar
	for c in clouds:
		var cl: Node3D = c
		cl.position.x += delta * 3.2
		cl.position.z += delta * 1.1
		if cl.position.x > Layout.SIZE + 120.0:
			cl.position.x = -120.0
		if cl.position.z > Layout.SIZE + 120.0:
			cl.position.z = -120.0
	sun.rotation = sun_base + Vector3(sin(t * 0.02) * 0.04, t * 0.004, 0.0)
	# as janelas vão acendendo conforme o céu escurece
	city.lit_mat.albedo_color = Color(0.55, 0.52, 0.5).lerp(Color(1.0, 0.97, 0.92), clampf(t / 20.0, 0.0, 1.0))
	life.update(delta, Vector2(p.x, p.z), false, false)
	life.update_slow(true)
