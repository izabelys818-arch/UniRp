extends RefCounted

# Atmosfera no Forward+: oclusão de ambiente (SSAO), luz rebatida (SSIL), sombra suave com
# penumbra, AgX, brilho das luzes (glow), reflexo no chão molhado (SSR), névoa e curvas de cor
# por momento do dia (dia, pôr do sol, noite, chuva). Os quadros-chave de luz continuam no
# Art.light_at; aqui entra só o "filme": como a câmera revela essa luz.

static var _grad: Gradient
static var _cc: GradientTexture1D
static var _sky_mat: ProceduralSkyMaterial
static var _last := Vector4(-1, -1, -1, -1)
static var _mist: FogVolume
static var _mist_mat: FogMaterial
static var _bolt: DirectionalLight3D
static var _splash: CPUParticles3D
static var _flash := 0.0
static var _next_flash := 6.0
static var _storm := false
static var _env: Environment
static var _viewport: SubViewport
static var _compat := false
static var wind := Vector3(0.32, 0.0, 0.24)

# Curvas por canal (entrada 0, 0.5, 1 -> cor de saída). Sombras azuladas e altas quentes à noite
# e no pôr do sol; chuva fria e lavada; dia limpo com leve calor nas altas.
const MOODS := {
	"dia": [Color(0.012, 0.016, 0.03), Color(0.505, 0.5, 0.485), Color(1.0, 0.985, 0.95)],
	"por": [Color(0.012, 0.016, 0.04), Color(0.515, 0.495, 0.475), Color(1.0, 0.96, 0.88)],
	"noite": [Color(0.0, 0.022, 0.05), Color(0.43, 0.48, 0.57), Color(1.0, 0.9, 0.74)],
	"chuva": [Color(0.022, 0.028, 0.04), Color(0.455, 0.48, 0.515), Color(0.9, 0.93, 0.97)],
}


static func setup(env: Environment, sun: DirectionalLight3D, viewport: SubViewport) -> void:
	_compat = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	# ACES: contraste e cor de cinema (o AgX lavava a paleta da direção de arte)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	# oclusão de contato e de cantos (pés das paredes, sob carros e móveis)
	env.ssao_enabled = not _compat
	env.ssao_radius = 1.3
	env.ssao_intensity = 2.4
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.08
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.12
	# luz que rebate: parede ao sol tinge o chão, grama tinge a parede
	env.ssil_enabled = not _compat
	env.ssil_radius = 4.0
	env.ssil_intensity = 0.85
	env.ssil_sharpness = 0.98
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.025
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 0.95
	env.glow_hdr_scale = 2.0
	for i in range(1, 8):
		env.set("glow_levels/%d" % i, 1.0 if i in [2, 3, 4, 5] else 0.0)
	env.adjustment_enabled = true
	_grad = Gradient.new()
	_cc = GradientTexture1D.new()
	_cc.width = 256
	_cc.gradient = _grad
	env.adjustment_color_correction = _cc
	# Céu compartilhado: reflexos e terceira pessoa. A vista isométrica conserva BG_COLOR.
	var sky := Sky.new()
	_sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = _sky_mat
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 1.6
	env.ssr_depth_tolerance = 0.35
	# iluminação global em tempo real: a luz rebate entre parede, chão e grama (cor sangra)
	_env = env
	_viewport = viewport
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.2
	env.sdfgi_energy = 0.85
	# suavização temporal: grama e folhas param de cintilar
	viewport.use_taa = not _compat
	sun.light_angular_distance = 0.9
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.0
	# neblina volumétrica só numa camada rente ao chão (a câmera fica a 150 m: névoa global
	# apagaria a cidade). Pega a luz dos postes e faróis e faz halos.
	env.volumetric_fog_enabled = not _compat
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_length = 260.0
	env.volumetric_fog_detail_spread = 1.5
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	env.volumetric_fog_anisotropy = 0.35
	if not _compat:
		_mist = FogVolume.new()
		_mist.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		_mist.size = Vector3(110, 3.2, 110)
		_mist_mat = FogMaterial.new()
		_mist_mat.density = 0.0
		_mist_mat.height_falloff = 0.6
		_mist_mat.edge_fade = 0.35
		_mist.material = _mist_mat
		viewport.add_child(_mist)
	# relâmpago: luz fria e dura que pisca na tempestade
	_bolt = DirectionalLight3D.new()
	_bolt.light_color = Color(0.78, 0.86, 1.0)
	_bolt.light_energy = 0.0
	_bolt.rotation = Vector3(deg_to_rad(-62), deg_to_rad(28), 0)
	_bolt.shadow_enabled = true
	_bolt.visible = false
	viewport.add_child(_bolt)
	# respingos de chuva no chão
	_splash = CPUParticles3D.new()
	_splash.amount = 700
	_splash.lifetime = 0.28
	_splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_splash.emission_box_extents = Vector3(26, 0.02, 26)
	_splash.direction = Vector3.UP
	_splash.spread = 60.0
	_splash.initial_velocity_min = 0.6
	_splash.initial_velocity_max = 1.4
	_splash.gravity = Vector3(0, -9.8, 0)
	_splash.scale_amount_min = 0.5
	_splash.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.2))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.0))
	_splash.scale_amount_curve = curve
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.05)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(0.8, 0.86, 0.95, 0.35)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = sm
	_splash.mesh = quad
	_splash.emitting = false
	viewport.add_child(_splash)
	apply_quality(Settings.graphics)
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)


# Qualidade gráfica (Configurações): 0 desempenho, 1 alto, 2 ultra. Vale na hora.
static func apply_quality(level: int) -> void:
	RenderingServer.global_shader_parameter_set("pom_quality", 1.0 if level >= 1 else 0.0)
	if _env == null:
		return
	_env.sdfgi_enabled = not _compat and level >= 2
	_env.volumetric_fog_enabled = not _compat and level >= 1
	if _mist != null:
		_mist.visible = level >= 1
	RenderingServer.directional_shadow_atlas_set_size(8192 if level >= 1 else 4096, true)


# Mistura os humores pelo momento e aplica curvas, saturação, névoa e reflexos.
static func grade(env: Environment, sun: DirectionalLight3D, hf: float, day: float, dusk: float, storm: bool, wet: float) -> void:
	var w_rain := 1.0 if storm else 0.0
	var w_dusk := clampf(dusk, 0.0, 1.0) * (1.0 - w_rain * 0.6)
	var w_night := clampf(1.0 - day, 0.0, 1.0) * (1.0 - w_dusk * 0.5)
	var w_day := clampf(day - w_dusk, 0.0, 1.0) * (1.0 - w_rain)
	var total := w_rain + w_dusk + w_night + w_day + 0.0001
	var key := Vector4(snappedf(w_day / total, 0.02), snappedf(w_dusk / total, 0.02), snappedf(w_night / total, 0.02), w_rain)
	if key != _last:
		_last = key
		var pts: Array = [Color.BLACK, Color.BLACK, Color.BLACK]
		for pair in [["dia", w_day], ["por", w_dusk], ["noite", w_night], ["chuva", w_rain]]:
			var curve: Array = MOODS[pair[0]]
			for i in 3:
				pts[i] = (pts[i] as Color) + (curve[i] as Color) * (float(pair[1]) / total)
		_grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		_grad.colors = PackedColorArray([pts[0], pts[1], pts[2]])
	var wn := w_night / total
	var wd := w_dusk / total
	var wr := w_rain / total
	env.adjustment_saturation = lerpf(1.08, 1.0, wn) - 0.02 * wd - 0.32 * wr
	env.adjustment_contrast = 1.06 + 0.04 * wn + 0.05 * wr
	env.tonemap_exposure = 1.05 + 0.3 * wn + 0.05 * wr
	env.glow_intensity = lerpf(0.35, 0.85, wn) + 0.15 * wr
	env.ssil_intensity = lerpf(0.85, 0.5, wn)
	# chão molhado espelha postes, faróis e janelas
	env.ssr_enabled = not _compat and wet > 0.15
	# névoa: chuva lava a cidade; madrugada e pôr do sol têm névoa baixa que pega luz
	var haze := 0.0003 + 0.0007 * wr + 0.0002 * wd + 0.0003 * wn
	env.fog_enabled = true
	env.fog_density = haze
	env.fog_sun_scatter = 0.12 * wd
	env.fog_aerial_perspective = 0.0
	env.fog_light_color = Color("#a4adb9").lerp(Color("#d8a48e"), wd * 0.6).lerp(Color("#24304a"), wn * 0.85).lerp(Color("#7e8896"), wr)
	env.fog_light_energy = lerpf(1.0, 0.6, wn)
	env.fog_height = 0.4
	env.fog_height_density = 0.015 * wr + 0.008 * wd + 0.01 * wn
	# Céu por horário/clima; a névoa não deve apagá-lo nos dias claros em terceira pessoa.
	_sky_mat.sky_top_color = Color("#3c6aa0").lerp(Color("#5a5f8a"), wd).lerp(Color("#0b1222"), wn).lerp(Color("#5b6472"), wr)
	_sky_mat.sky_horizon_color = Color("#b8c8d8").lerp(Color("#f0a070"), wd).lerp(Color("#1c2638"), wn).lerp(Color("#8a929e"), wr)
	_sky_mat.ground_horizon_color = _sky_mat.sky_horizon_color
	_sky_mat.ground_bottom_color = Color("#2a2b2e")
	update_sky_fog(env)
	sun.light_angular_distance = lerpf(0.9, 2.5, wr)
	_storm = storm
	# neblina rasteira: madrugada, noite e chuva
	if _mist_mat != null:
		var dawn := clampf(1.0 - absf(hf - 5.8) / 1.4, 0.0, 1.0)
		_mist_mat.density = 0.003 + 0.03 * wn + 0.035 * wr + 0.05 * dawn
		_mist_mat.albedo = Color(0.85, 0.88, 0.94).lerp(Color(0.95, 0.85, 0.75), wd)
	# nuvens passando: só com sol direto (dia limpo); somem no pôr do sol, à noite e na chuva
	RenderingServer.global_shader_parameter_set("cloud_shade", 0.3 * clampf(day * 1.4 - 0.4, 0.0, 1.0) * (1.0 - wr) * (1.0 - wd * 0.7))


static func update_sky_fog(env: Environment) -> void:
	# O valor original 1.0 cobre o céu inteiro com a cor da névoa, mesmo com densidade
	# baixa. Mantém o horizonte velado e recupera o gradiente; chuva continua mais fechada.
	env.fog_sky_affect = 1.0 if env.background_mode != Environment.BG_SKY else clampf(0.12 + 0.16 * maxf(_last.y, 0.0) + 0.1 * maxf(_last.z, 0.0) + 0.58 * maxf(_last.w, 0.0), 0.12, 0.9)


# A cada quadro: neblina e respingos acompanham o jogador; relâmpagos na tempestade.
static func tick(delta: float, center: Vector3, rain_visible: bool) -> void:
	if _splash == null:
		return
	wind = Vector3(0.8, 0.0, 0.6) * (1.1 if _storm else 0.4)
	RenderingServer.global_shader_parameter_set("world_wind", wind)
	if _mist != null:
		_mist.position = Vector3(center.x, 1.4, center.z)
	_splash.position = Vector3(center.x, 0.22, center.z)
	_splash.emitting = rain_visible
	if not _storm:
		_bolt.visible = false
		_flash = 0.0
		return
	_next_flash -= delta
	if _next_flash <= 0.0:
		_flash = 1.0
		_next_flash = randf_range(7.0, 22.0)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.2)
		# dois pulsos: clarão, pisca e volta
		var pulse := smoothstep(0.0, 0.15, _flash) * (0.55 + 0.45 * absf(sin(_flash * 26.0)))
		_bolt.visible = pulse > 0.01
		_bolt.light_energy = pulse * 2.4
	else:
		_bolt.visible = false
