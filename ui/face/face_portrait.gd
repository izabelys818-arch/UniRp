extends "res://ui/face/face_base.gd"

# O retrato apresenta a própria pessoa do mundo 3D em uma janela 2D.
# Nenhuma feição é redesenhada: mesma malha, textura, cabelo, roupa e idade.
const Person = preload("res://ui/face/portrait_person.gd")
const SKIN = preload("res://ui/face/portrait_skin.gdshader")
const FINISH = preload("res://ui/face/portrait_finish.gdshader")
const FPS := 24.0
static var _built_frame := -1

# Miniaturas têm uma captura única e liberam o mundo 3D logo depois.
var frozen: bool = false
var _viewport: SubViewport
var _person: Person
var _camera: Camera3D
var _image: Texture2D
var _skin_fx: ShaderMaterial
var _finish: ShaderMaterial
var _pending := false
var _rebuild_delay := 0.0
var _frame_delay := 0.0
var _warmup := 0
var _capturing := false
var _last_scene := ""
var _last_size := Vector2.ZERO
var _head_rest := Quaternion.IDENTITY
var _elapsed := 0.0


func _ready() -> void:
	super._ready()
	_finish = ShaderMaterial.new()
	_finish.shader = FINISH
	material = _finish
	resized.connect(_resize)
	visibility_changed.connect(_visibility_changed)
	_pending = not look.is_empty()
	_resize()


func _exit_tree() -> void:
	set_process(false)
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	material = null
	_image = null
	_skin_fx = null
	_finish = null
	_person = null
	_camera = null
	_viewport = null


func set_look(l: Dictionary) -> void:
	if look == l and not look.is_empty():
		return
	look = l.duplicate(true)
	_pending = true
	_rebuild_delay = 0.12
	# O modo congelado precisa voltar a trabalhar depois de uma troca de aparência.
	set_process(true)
	queue_redraw()


func set_emotion(e: String, instant: bool = false) -> void:
	super.set_emotion(e, instant)
	if _person != null:
		_person.set_emotion(emotion)
		if instant:
			for n in 24:
				_person._apply_face(1.0 / FPS)
	if frozen:
		_pending = true
		set_process(true)
	_frame_delay = 0.0


func _on_screen() -> bool:
	if not is_visible_in_tree() or size.x < 1 or size.y < 1:
		return false
	return get_global_rect().intersects(get_viewport().get_visible_rect())


func _visibility_changed() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _on_screen():
		_frame_delay = 0.0


func _resize() -> void:
	if _viewport == null or size.x <= 0 or size.y <= 0:
		return
	# Suavização e resolução extra só no retrato, mantendo o renderizador do jogo.
	var factor := clampf(600.0 / maxf(size.y, 1.0), 1.0, 2.0)
	var wanted := Vector2i(maxi(64, int(size.x * factor)), maxi(80, int(size.y * factor)))
	wanted.x = mini(wanted.x, 768)
	wanted.y = mini(wanted.y, 960)
	if _viewport.size != wanted:
		_viewport.size = wanted
		_frame_delay = 0.0
	_last_size = size


func _build() -> void:
	_pending = false
	if _viewport != null:
		remove_child(_viewport)
		_viewport.queue_free()
	_viewport = SubViewport.new()
	_viewport.name = "PortraitStudio"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_resize()
	var studio := Node3D.new()
	_viewport.add_child(studio)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#161c22")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#d3dce3")
	environment.ambient_light_energy = 0.3
	var world := WorldEnvironment.new()
	world.environment = environment
	studio.add_child(world)
	for config in [[Vector3(-22, -32, 0), 0.58, Color("#ffe6ce")],
		[Vector3(-10, 42, 0), 0.16, Color("#d0ddeb")],
		[Vector3(-20, 150, 0), 0.38, Color("#bdcddd")]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = config[0]
		light.light_energy = config[1]
		light.light_color = config[2]
		light.shadow_enabled = config[1] == 0.58
		studio.add_child(light)
	_person = Person.new()
	studio.add_child(_person)
	_person.set_look(look)
	_person.set_process(false)
	_person.set_emotion(emotion)
	# Pose frontal estável: o olhar permanece legível nas miniaturas e no diálogo.
	if _person.skel != null:
		_person.skel.reset_bone_poses()
		_person.skel.set_bone_pose_scale(_person._head, _person._head_vec)
		for frame in 24:
			_person._apply_hands(1.0 / FPS)
			_person._apply_face(1.0 / FPS)
		_head_rest = _person.skel.get_bone_pose_rotation(_person._head)
	_customize_skin()
	if _person._lash_mi != null:
		var lashes := _person._lash_mi.material_override as StandardMaterial3D
		lashes.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lashes.albedo_color.a = 0.75
		_person._lash_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 0.46 * _person.scale.y
	_camera.position = Vector3(0, 1.65 * _person.scale.y, 3)
	studio.add_child(_camera)
	_camera.look_at(Vector3(0, 1.65 * _person.scale.y, 0))
	_image = _viewport.get_texture()
	_warmup = 3
	_capturing = false
	_frame_delay = 0.0


func _customize_skin() -> void:
	if _person._face_mi == null or _person._anatomy.is_empty():
		return
	var base := _person._face_mi.material_override as StandardMaterial3D
	_skin_fx = ShaderMaterial.new()
	_skin_fx.shader = SKIN
	_skin_fx.next_pass = base.next_pass
	_skin_fx.set_shader_parameter("skin_texture", base.albedo_texture)
	_skin_fx.set_shader_parameter("skin_tint", base.albedo_color)
	_skin_fx.set_shader_parameter("nose", _person._anatomy["nose"])
	_skin_fx.set_shader_parameter("eye_left", _person._anatomy["eye_l"])
	_skin_fx.set_shader_parameter("eye_right", _person._anatomy["eye_r"])
	_skin_fx.set_shader_parameter("mouth_y", _person._anatomy["mouth_y"])
	_skin_fx.set_shader_parameter("mouth_width", _person._anatomy["mouth_x"] * float(look.get("mouth_w", 1.0)) * 0.9)
	_skin_fx.set_shader_parameter("gold_tooth", 10 in look.get("marks", []) or "dente_ouro" in look.get("extras", []))
	_person._face_mi.material_override = _skin_fx
	_person.body_mi.material_override = _skin_fx


func _process(delta: float) -> void:
	talk_left = maxf(0.0, talk_left - delta)
	if not _on_screen():
		if _viewport != null:
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_rebuild_delay -= delta
	if _pending and _rebuild_delay <= 0.0 and _built_frame != Engine.get_process_frames():
		_built_frame = Engine.get_process_frames()
		_build()
	if _person == null:
		return
	_frame_delay -= delta
	_elapsed += delta
	if _frame_delay > 0.0:
		return
	var step := minf(_elapsed, 0.2)
	_elapsed = 0.0
	_frame_delay = maxf(_frame_delay + 1.0 / FPS, 0.0)
	t += step
	emote_t = minf(emote_t + step, 1.0)
	var speed := 1.0 - exp(-step * 7.0)
	for key in cur:
		cur[key] = lerpf(float(cur[key]), float(target[key]), speed)
	_person.t = t
	_person.talk_left = talk_left
	_person._apply_face(step)
	if _person.skel != null:
		var tilt: float = float(cur["tilt"]) * 0.65 + sin(t * 0.6) * 0.007
		var downward := deg_to_rad(2.0) * float(cur["gaze_y"])
		var sideways := deg_to_rad(3.0) * float(cur["gaze_x"])
		_person.skel.set_bone_pose_rotation(_person._head, _head_rest * Quaternion.from_euler(Vector3(downward, sideways, tilt)))
	_update_finish()
	_update_skin()
	if size != _last_size:
		_resize()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()
	if frozen:
		_warmup -= 1
		if _warmup <= 0 and not _capturing:
			_freeze()


func _update_skin() -> void:
	if _skin_fx == null:
		return
	for pair in [["blush", "blush"], ["fatigue", "dark_circles"], ["pale", "pale"], ["bruise", "bruise"],
		["tears", "tears"], ["sweat", "sweat"], ["menace", "shadow_eyes"]]:
		_skin_fx.set_shader_parameter(pair[0], cur[pair[1]])
	_skin_fx.set_shader_parameter("phase", t)
	var jaw: float = _person._face_w.get("queixo", 0.0)
	_skin_fx.set_shader_parameter("jaw_open", jaw)
	for part in _person.oral_parts:
		part.visible = jaw > 0.3


func _update_finish() -> void:
	if _finish == null:
		return
	if _last_scene != scene:
		_last_scene = scene
		var palette: Array = SCENE_COLORS.get(scene, SCENE_COLORS["vazio"])
		_finish.set_shader_parameter("backdrop", (palette[0] as Color).darkened(0.5))
		_finish.set_shader_parameter("window_color", (palette[2] as Color).lerp(Color("#657787"), 0.6))
	_finish.set_shader_parameter("dim_amount", dim)
	_finish.set_shader_parameter("highlight_amount", highlight)
	_finish.set_shader_parameter("transparent_backdrop", actor_mode)


func _freeze() -> void:
	_capturing = true
	var source := _viewport
	# A imagem é copiada após o quadro chegar à GPU, nunca antes da primeira renderização.
	await RenderingServer.frame_post_draw
	if not is_instance_valid(source) or source != _viewport or _pending:
		_capturing = false
		return
	_image = ImageTexture.create_from_image(_viewport.get_texture().get_image())
	remove_child(_viewport)
	_viewport.queue_free()
	_viewport = null
	_person = null
	_camera = null
	_skin_fx = null
	set_process(false)
	queue_redraw()


func _draw() -> void:
	if _image != null:
		draw_texture_rect(_image, Rect2(Vector2.ZERO, size), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#192026"))
