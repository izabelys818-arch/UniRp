extends SubViewportContainer

# Mundo aberto isométrico (estilo Project Zomboid). Mostra a cidade inteira em 3D:
# o jogador anda com WASD ou clicando, entra nos prédios (as paredes se cortam),
# os NPCs andam pelas ruas seguindo a própria rotina, carros e pedestres passam,
# o dia vira noite, chove, falta luz. A lógica do jogo continua nos autoloads.

const Layout = preload("res://world3d/city_layout.gd")
const CityBuilder = preload("res://world3d/city_builder.gd")
const Humanoid = preload("res://world3d/person.gd")
const Kit = preload("res://world3d/mesh_kit.gd")
const Life = preload("res://world3d/life.gd")
const Atmosphere = preload("res://world3d/atmosphere.gd")
const GrassField = preload("res://world3d/grass_field.gd")
const Foliage = preload("res://world3d/foliage.gd")
const Art = preload("res://world3d/art_style.gd")
const LookBuilder = preload("res://ui/face/look_builder.gd")
const HumanMotion = preload("res://world3d/human_motion.gd")
const Leaves = preload("res://world3d/falling_leaves.gd")
const CameraRig = preload("res://world3d/camera_rig.gd")
const WorldChunks = preload("res://world3d/world_chunks.gd")

signal npc_chosen(id: String)
signal npc_menu(id: String)
signal toast(text: String)
signal object_chosen(target: Dictionary)

static var realtime: bool = true
# Diagnóstico de desempenho: imprime qualquer etapa do quadro que passe de 6 ms.
static var trace: bool = false

const WALK_SPEED := 1.6 # passo de caminhada humano (captura: 1,5–1,7 m/s)
const RUN_SPEED := 5.0
var _p_heading := 0.0
const NPC_SPEED := 1.55
const MINUTES_PER_SECOND := 1.0
const CAM_DIR := Vector3(1.0, 1.15, 1.0)

var layout: Layout
var city: CityBuilder
var chunks: WorldChunks
var viewport: SubViewport
var camera: Camera3D
var camera_rig: CameraRig
var _camera_dim: ColorRect
var _camera_tween: Tween
var _rmb_down := false
var _orbit_drag := false
var _rmb_travel := 0.0
var _rmb_position := Vector2.ZERO
var _rmb_global := Vector2.ZERO
var _retain_move_keys := false
var _retained_move_basis := Basis.IDENTITY
var sun: DirectionalLight3D
var env: Environment
const PhysicalWorld = preload("res://world3d/physical_world.gd")
const PhysicsState = preload("res://world3d/physics_state.gd")
const PhysicsLayers = preload("res://world3d/physics_layers.gd")
var physical_world: Node3D
var player_physics: RefCounted
var player: CharacterBody3D
var player_fig: Humanoid
var marker: MeshInstance3D
var hover_ring: MeshInstance3D
var rain: CPUParticles3D
var grass: Node3D
var foliage: Node3D
var lamp_pool: Array = []
# cada luz do conjunto guarda o poste que ilumina e acende/apaga devagar (sem saltos)
var lamp_spot: Array = []
var lamp_goal: Array = []
# lugares para sentar por lote e quem está em cada um
var seats_by_lot: Dictionary = {}
var _seat_revision := -1
var seat_used: Dictionary = {}
const LAMPS_LIT := 20
const LAMP_E := 2.2
const LAMP_COLORS := {"porto_cinza": "#ffc583", "vale_sereno": "#ffd49c", "nova_aurora": "#f1ebdf", "colapso": "#ffb46e"}
# chuva: o chão molha aos poucos e seca devagar depois
var wet_level := 0.0
var _wet_min := -1
var npcs: Dictionary = {}           # id -> {"fig", "loc", "path", "wait"}
var _restored_npcs: Dictionary = {}
var life: Life
var falling_leaves: Leaves
var path: PackedVector2Array = PackedVector2Array()
var _floor_segments: Array = []
var _precise_steps := 0
var _furniture_routes: Dictionary = {}
var pending_npc: String = ""
# ação com o corpo em andamento (dormir, banho, comer, beber) — ver start_action
var _act: Dictionary = {}
var _fade: ColorRect
var _act_props: Array = []
var hover_id: String = ""
var hover_object: Dictionary = {}
var zoom: float = 14.0
var cam_target: Vector3 = Vector3.ZERO
var pause_check: Callable
var rng := RandomNumberGenerator.new()

var _time_acc: float = 0.0
var _walk_acc: float = 0.0
var _last_minutes: int = -1
var _snap_npcs: bool = true
var _t_loc: float = 0.0
var _t_cut: float = 0.0
var _t_sync: float = 0.0
var _t_env: float = 0.035
var _t_detail: float = 0.066
var _stuck: float = 0.0
var _door_locked: Dictionary = {}
var _built: bool = false
var _talk_anchor: Vector2 = Vector2.INF
var hint: Label
var _loading: CanvasLayer
var _loading_text: Label
signal world_ready


func _ready() -> void:
	AgingSystem.birthday.connect(_on_birthday)
	Settings.camera_changed.connect(_on_camera_settings)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	rng.randomize()
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.handle_input_locally = false
	add_child(viewport)
	_loading = CanvasLayer.new()
	_loading.layer = 100
	add_child(_loading)
	var backdrop := ColorRect.new()
	backdrop.color = Color("#161c20")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(backdrop)
	_loading_text = Label.new()
	_loading_text.text = "Preparando o bairro…"
	_loading_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_text.add_theme_font_size_override("font_size", 24)
	backdrop.add_child(_loading_text)
	await get_tree().process_frame
	await _setup_scene()
	World.open_world = true
	World.location_changed.connect(_on_location_changed)
	World.walk_requested.connect(_on_walk_requested)
	NPCManager.npc_replied.connect(func(id: String, data: Dictionary) -> void:
		if npcs.has(id):
			(npcs[id]["fig"] as Humanoid).talk_left = 3.5
			var gesture := str(data.get("gesto_visual", ""))
			if gesture != "" and NPCManager.channel == NPCManager.PRESENCIAL:
				(npcs[id]["fig"] as Humanoid).gesture(gesture)
				player_fig.gesture(gesture))
	hint = Label.new()
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color("#fff3d6"))
	hint.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.04))
	hint.add_theme_constant_override("outline_size", 8)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.visible = false
	add_child(hint)
	_place_player(World.current_id(), true)
	chunks = WorldChunks.new()
	viewport.add_child(chunks)
	chunks.setup(self)
	_loading_text.text = "Preparando as ruas ao redor…"
	while not chunks.near_ready():
		chunks.tick()
		await get_tree().process_frame
	# Corpos do interior entram no servidor físico antes de retomar um save.
	# Posições livres são mantidas; plantas antigas podem ter salvo o jogador
	# onde agora existe uma divisória ou móvel.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_resolve_loaded_position()
	_last_minutes = TimeManager.total_minutes
	_update_environment()
	camera_rig.bind(player)
	_camera(1.0)
	_loading_text.text = "Preparando vegetação e efeitos…"
	var smoke_probe := CityBuilder.WorldMotion.smoke(city, Vector3(0, 1, -90))
	city.ambient_emitters.append({"node": smoke_probe, "point": smoke_probe.position})
	for emitter in city.ambient_emitters:
		var node: CPUParticles3D = emitter["node"]
		var keep := node.position
		node.position = Vector3(0, 1, -90)
		node.emitting = true
		# A câmera de carga também prepara a variante de partículas da água.
		var camera_position := camera.position
		var camera_basis := camera.basis
		camera.position = Vector3.ZERO
		camera.basis = Basis.IDENTITY
		for i in 4:
			await get_tree().process_frame
		camera.position = camera_position
		camera.basis = camera_basis
		node.position = keep
		node.emitting = false
	for i in 45:
		grass.update_view(player.position)
		foliage.update_view(player.position)
		await get_tree().process_frame
	city.ambient_emitters = city.ambient_emitters.filter(func(emitter): return emitter["node"] != smoke_probe)
	smoke_probe.queue_free()
	_built = true
	camera_rig.bind(player)
	camera_rig.room_limit = _camera_room_limit
	_camera_dim = ColorRect.new()
	_camera_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_camera_dim.color = Color(0.02, 0.025, 0.03, 0)
	_camera_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_camera_dim)
	set_camera_mode(Settings.camera_mode, false, false)
	_loading.queue_free()
	world_ready.emit()


func _exit_tree() -> void:
	_release_orbit(false)
	Humanoid.set_xray_strength(1.0)
	World.open_world = false


# ---------- montagem ----------

func _setup_scene() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_blur = 1.5
	# viés um pouco maior: sem serrilhado/acne piscando no chão quando o sol está baixo
	sun.shadow_bias = 0.12
	sun.shadow_normal_bias = 2.4
	viewport.add_child(sun)
	Atmosphere.setup(env, sun, viewport)
	camera_rig = CameraRig.new()
	viewport.add_child(camera_rig)
	camera = camera_rig.active
	camera.size = zoom
	var t0 := Time.get_ticks_msec()
	layout = Layout.new()
	GrassField.reset()
	Foliage.reset()
	city = CityBuilder.new()
	viewport.add_child(city)
	await city.build(layout, true, func(message: String): _loading_text.text = message)
	print("CIDADE montada em %d ms (%d casas)" % [Time.get_ticks_msec() - t0, layout.house_ids.size()])
	for s in city.seats:
		var lid := layout.lot_at(s["p"])
		if lid != "":
			if not seats_by_lot.has(lid):
				seats_by_lot[lid] = []
			seats_by_lot[lid].append(s)
	# jogador
	player = CharacterBody3D.new()
	player.floor_snap_length = 0.4
	player.floor_max_angle = deg_to_rad(60)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.6
	cs.shape = cap
	cs.position = Vector3(0, 0.8, 0)
	player.add_child(cs)
	viewport.add_child(player)
	player_fig = Humanoid.new()
	player_fig.use_player_locomotion = true
	player.add_child(player_fig)
	physical_world = PhysicalWorld.new()
	viewport.add_child(physical_world)
	physical_world.setup(self)
	player_physics = PhysicsState.new()
	player_physics.setup(player, player_fig, PhysicsLayers.PLAYER, _physical_damage)
	player_physics.restore(GameState.player.get("physical", {}))
	_loading_text.text = "Preparando os moradores…"
	await _prewarm_bodies()
	_loading_text.text = "Arrumando as casas…"
	await preload("res://world3d/furn_lib.gd").prewarm(get_tree(), 6000, viewport)
	refresh_player_look()
	await _warm_render_person(player_fig, false)
	# marcadores
	marker = _ring(Color("#ffd166"), 0.45)
	hover_ring = _ring(Color("#ffffff"), 0.6)
	# postes acesos (um conjunto pequeno que acompanha o jogador)
	var lamp_c := Color(LAMP_COLORS.get(Art.id(), "#ffcf86"))
	for i in 24:
		var l := OmniLight3D.new()
		l.light_color = lamp_c
		# os mais próximos projetam sombra (Forward+ aguenta): postes recortam o mundo à noite
		l.shadow_enabled = i < 8
		l.shadow_blur = 1.5
		l.light_energy = 0.0
		l.omni_range = 12.5
		l.omni_attenuation = 1.55
		l.visible = false
		viewport.add_child(l)
		lamp_pool.append(l)
		lamp_spot.append(null)
		lamp_goal.append(0.0)
	_setup_rain()
	life = Life.new()
	life.physical_world = physical_world
	viewport.add_child(life)
	_loading_text.text = "Preparando a vida nas ruas…"
	await life.setup(layout, city, true, true, func(message: String): _loading_text.text = message)
	for entry in life.peds:
		await _warm_render_person(entry["fig"], false)
	grass = GrassField.new()
	viewport.add_child(grass)
	foliage = Foliage.new()
	viewport.add_child(foliage)
	falling_leaves = Leaves.new()
	viewport.add_child(falling_leaves)
	falling_leaves.sources = city.foliage_sources


func _ring(c: Color, r: float) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = r * 0.78
	tm.outer_radius = r
	tm.rings = 24
	tm.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.no_depth_test = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.scale = Vector3(1, 0.15, 1)
	mi.visible = false
	viewport.add_child(mi)
	return mi


func _setup_rain() -> void:
	rain = CPUParticles3D.new()
	rain.amount = 2600
	rain.lifetime = 0.9
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(34, 1, 34)
	rain.direction = Vector3(0.15, -1, 0.1)
	rain.spread = 2.0
	rain.gravity = Vector3(0, -30, 0)
	rain.initial_velocity_min = 18.0
	rain.initial_velocity_max = 22.0
	var qm := QuadMesh.new()
	qm.size = Vector2(0.018, 0.9)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# gota fina e translúcida: some contra o claro, aparece contra a luz dos postes
	m.albedo_color = Color(0.68, 0.76, 0.9, 0.2)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	qm.material = m
	rain.mesh = qm
	rain.emitting = false
	viewport.add_child(rain)


# Quem faz aniversário perto do jogador troca de corpo na hora (rugas, postura, faixa de idade);
# quem está longe só muda o número e aparece com a idade nova da próxima vez.
func _on_birthday(id: String, _age: int) -> void:
	if id == "":
		refresh_player_look()
	elif npcs.has(id):
		var n: Dictionary = NPCManager.npcs[id]
		(npcs[id]["fig"] as Node3D).set_look(LookBuilder.build(LookBuilder.individual_spec(World.npc_looks.get(id, {}), id), int(n["idade"]), str(n["genero"])))


# Cada combinação de gênero, idade e tipo físico gera a malha do corpo e das roupas uma vez (~150 ms).
# Fazer isso aqui, no carregamento, evita engasgo quando essa pessoa aparece na rua.
func _prewarm_bodies() -> void:
	if not GameState.active:
		return
	var prepared := 0
	for id in NPCManager.npcs:
		var n: Dictionary = NPCManager.npcs[id]
		var lk := LookBuilder.build(LookBuilder.individual_spec(World.npc_looks.get(id, {}), id), int(n["idade"]), str(n["genero"]))
		var f := Humanoid.new()
		viewport.add_child(f)
		f.set_look(lk)
		await _warm_render_person(f, true)
		npcs[id] = _npc_entry(str(id), f, n, "")
		prepared += 1
		_loading_text.text = "Preparando os moradores… %d de %d" % [prepared, NPCManager.npcs.size()]
		await get_tree().process_frame


func _warm_render_person(fig: Humanoid, hide_after: bool) -> void:
	# Preparar o modelo escondido não prepara o upload/variante da GPU.
	# Desenha durante a tela de carregamento usando a câmera existente.
	var position_before := fig.position
	fig.position = Vector3(0, 0, -90)
	fig.set_active(true)
	await get_tree().process_frame
	await get_tree().process_frame
	fig.position = position_before
	fig.set_active(not hide_after)


func refresh_player_look() -> void:
	var p: Dictionary = GameState.player
	player_fig.set_look(LookBuilder.build(p.get("look", {}), int(p.get("age", 30)), str(p.get("gender", "homem"))))
	# atrás de um prédio o jogador continua visível em silhueta
	player_fig.enable_xray()


# ---------- posição do jogador ----------

func _p2() -> Vector2:
	return Vector2(player.position.x, player.position.z)


func _lot_id(loc_id: String) -> String:
	if loc_id == "" or not World.locations.has(loc_id):
		return ""
	var loc: Dictionary = World.locations[loc_id]
	if loc.get("interior", false):
		return str(loc.get("pai", ""))
	return loc_id


func _room_rect(interior_id: String) -> Rect2:
	var parent := _lot_id(interior_id)
	if not layout.lots.has(parent):
		return Rect2()
	var b: Rect2 = layout.lots[parent]["building"]
	return Rect2(b.position.x + 0.3, b.position.y + 0.3, b.size.x - 0.6, 4.7)


func _place_player(loc_id: String, initial: bool = false) -> void:
	# Campo opcional aprovado pelo dono; saves anteriores continuam no térreo.
	if initial and GameState.player.has("pos"):
		var saved: Array = GameState.player["pos"]
		player.position = Vector3(float(saved[0]), clampf(float(GameState.player.get("pos_height", 0.25)), 0.17, 200.0), float(saved[1]))
		player.velocity = Vector3.ZERO
		cam_target = player.position
		_cutaway()
		return
	var p := Vector2.ZERO
	var lot := _lot_id(loc_id)
	if World.locations.has(loc_id) and World.locations[loc_id].get("interior", false):
		p = _room_rect(loc_id).get_center()
	elif layout.lots.has(lot):
		var b: Rect2 = layout.lots[lot]["building"]
		if b.size != Vector2.ZERO and World.is_accessible(lot) and World.is_open(lot):
			# O hall é reservado pela planta; espalhar o jogador aleatoriamente
			# para dentro podia colocá-lo em uma divisória ou dentro de um móvel.
			p = layout.door_in(lot)
		else:
			p = layout.door_out(lot)
	elif initial and GameState.player.has("pos"):
		var sp: Array = GameState.player["pos"]
		p = Vector2(float(sp[0]), float(sp[1]))
	else:
		return
	player.position = Vector3(p.x, 0.25, p.y)
	player.velocity = Vector3.ZERO
	path = PackedVector2Array()
	pending_npc = ""
	cam_target = player.position
	_snap_npcs = true


func _on_location_changed(loc_id: String) -> void:
	if not _built or loc_id == "rua":
		return
	var target := _lot_id(loc_id)
	if not layout.ensure_place(target):
		return
	var coord := Layout.chunk_at((layout.lots[target]["rect"] as Rect2).get_center())
	if not Layout.central_cell(layout.lots[target]["cell"]) and (not chunks.active.has(coord) or not chunks.active[coord]["detailed"]):
		var cover := ColorRect.new()
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cover.color = Color("#282e2d")
		var label := Label.new()
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.text = "Preparando o bairro…"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cover.add_child(label)
		add_child(cover)
		_built = false
		chunks.update_focus((layout.lots[target]["rect"] as Rect2).get_center())
		while not chunks.near_ready():
			chunks.tick()
			await get_tree().process_frame
		_built = true
		cover.queue_free()
	var here := layout.lot_at(_p2())
	if World.locations.has(loc_id) and World.locations[loc_id].get("interior", false):
		if not _room_rect(loc_id).has_point(_p2()):
			_place_player(loc_id)
		return
	if here != _lot_id(loc_id):
		_place_player(loc_id)


func _resolve_loaded_position() -> void:
	var id := _inside_any(_p2())
	var structure: Dictionary = city.loc_info.get(id, {}).get("structure", {})
	if structure.is_empty():
		return
	var number := _floor_in(structure)
	var node: Node3D = structure.get("floor_nodes", {}).get(number)
	if not is_instance_valid(node):
		return
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.exclude = [player.get_rid()]
	query.collision_mask = PhysicsLayers.WORLD
	var feet_y := maxf(player.position.y, 0.245 + number * float(structure.get("floor_height", 3.0)))
	query.transform.origin = Vector3(player.position.x, feet_y + 0.82, player.position.z)
	var space := player.get_world_3d().direct_space_state
	if space.intersect_shape(query, 1).is_empty():
		return
	var options: Array = node.get_meta("use_points").get("_portals", []).duplicate()
	options.sort_custom(func(a, b): return (a as Vector2).distance_squared_to(_p2()) < (b as Vector2).distance_squared_to(_p2()))
	for point in options:
		query.transform.origin = Vector3(point.x, feet_y + 0.82, point.y)
		if space.intersect_shape(query, 1).is_empty():
			player.position = Vector3(point.x, feet_y, point.y)
			player.velocity = Vector3.ZERO
			cam_target = player.position
			GameState.add_log("A posição da partida foi ajustada para uma passagem livre após a atualização do interior.", "system")
			return


func _on_walk_requested(loc_id: String) -> void:
	var lot := _lot_id(loc_id)
	if not layout.ensure_place(lot):
		return
	var dest: Vector2 = layout.door_in(lot) if (World.is_open(lot) and World.is_accessible(lot)) else layout.door_out(lot)
	_go_to(dest)
	toast.emit("Andando até %s" % World.locations[lot]["nome"])


func _go_to(dest: Vector2) -> void:
	_floor_segments.clear()
	if not _act.is_empty():
		_cancel_action("Atividade interrompida.")
	var start_id := _inside_any(_p2())
	if city.loc_info.has(start_id):
		var start_structure: Dictionary = city.loc_info[start_id]["structure"]
		if _floor_in(start_structure) > 0 and not (start_structure["rect"] as Rect2).has_point(dest):
			if _route_floors(start_structure, 0):
				_floor_segments.append({"resume": dest})
				return
	var lot := layout.lot_at(dest)
	if lot != "" and layout.in_building(lot, dest) and bool(_door_locked.get(lot, false)) and not layout.in_building(lot, _p2()):
		dest = layout.door_out(lot)
		toast.emit("%s está trancado." % World.locations[lot]["nome"])
	path = layout.route(_p2(), dest)
	_precise_steps = 0
	var current := layout.lot_at(_p2())
	if current == "rodoviaria" or lot == "rodoviaria":
		path = _terminal_path(dest)
		_precise_steps = path.size()
		if path.is_empty():
			marker.visible = false
			toast.emit("Não há passagem livre até esse ponto.")
			return
	elif current != "" and layout.in_building(current, _p2()) and (city.use_points.get(current, {}).has("_root") or current == "mercado"):
		var same_room := current == lot and layout.in_building(current, dest)
		var approach := dest if same_room else layout.door_in(current)
		var local_path := _furnished_path(current, approach)
		if local_path.is_empty():
			path.clear()
			marker.visible = false
			toast.emit("Não há passagem livre até esse ponto.")
			return
		path = PackedVector2Array(local_path)
		_precise_steps = path.size()
		if not same_room:
			path.append_array(layout.route(approach, dest))
	marker.position = Vector3(dest.x, player.position.y + 0.04, dest.y)
	marker.visible = true


func _terminal_path(destination: Vector2) -> PackedVector2Array:
	var rect: Rect2 = layout.lots["rodoviaria"]["rect"]
	# Entrada na faixa livre entre os táxis. A malha de ruas continua sendo
	# usada fora do lote; dentro, o AStar existente consulta os obstáculos físicos.
	var gate := Vector2(rect.get_center().x, rect.end.y - 0.5)
	var from_here := layout.lot_at(_p2()) == "rodoviaria"
	var to_here := layout.lot_at(destination) == "rodoviaria"
	var local_path := _furnished_path("rodoviaria", destination if to_here else gate, _p2() if from_here else gate)
	if local_path.is_empty():
		return PackedVector2Array()
	var result := PackedVector2Array()
	if not from_here:
		result.append_array(layout.route(_p2(), gate))
	result.append_array(PackedVector2Array(local_path))
	if not to_here:
		result.append_array(layout.route(gate, destination))
	return result


# ---------- laço principal ----------

func _process(delta: float) -> void:
	if not _built:
		return
	if _paused() or _typing():
		_release_orbit()
	chunks.update_focus(_p2())
	chunks.tick()
	for emitter in city.ambient_emitters:
		(emitter["node"] as CPUParticles3D).emitting = (emitter["point"] as Vector3).distance_squared_to(player.position) < 2025.0
	falling_leaves.wind = Atmosphere.wind
	falling_leaves.update(delta, player.position, _inside_any(_p2()) != "", WorldEvents.raining())
	if TimeManager.total_minutes - _last_minutes > 20 or TimeManager.total_minutes < _last_minutes:
		_snap_npcs = true
	_last_minutes = TimeManager.total_minutes
	if GameState.active:
		if not _act.is_empty():
			_update_action(delta)
		_t_loc -= delta
		if _t_loc <= 0.0:
			_t_loc = 0.25
			_update_location()
		_time_flow(delta)
	_camera(delta)
	if grass != null:
		Atmosphere.tick(delta, player.position, rain.emitting)
		# Vegetation chunks are built incrementally; doing two full queue scans every
		# rendered frame consumed several milliseconds even when the player stood still.
		_t_detail -= delta
		if _t_detail <= 0.0:
			_t_detail = 0.1
			grass.update_view(player.position)
			foliage.update_view(player.position)
	RenderingServer.global_shader_parameter_set("rain_time", Time.get_ticks_msec() / 1000.0)
	var tq := Time.get_ticks_usec()
	_t_cut -= delta
	if _t_cut <= 0.0:
		_t_cut = 0.1
		_cutaway()
	tq = _tr("cutaway", tq)
	_t_sync -= delta
	if _t_sync <= 0.0 or _snap_npcs:
		_t_sync = 0.5
		_sync_npcs()
	tq = _tr("sync_npcs", tq)
	tq = _tr("update_npcs", tq)
	# Alvo de 2,5 ms entre operações; uma instanciação indivisível pode exceder.
	city.house_gen.place_pending(2500)
	tq = _tr("furniture", tq)

	tq = _tr("life", tq)
	_t_env -= delta
	if _t_env <= 0.0:
		_t_env = 0.5
		_update_environment()
	_fade_lamps(delta)
	tq = _tr("environment", tq)
	if hover_id != "" and npcs.has(hover_id) and not _paused():
		var hf: Node3D = npcs[hover_id]["fig"]
		hover_ring.visible = true
		hover_ring.position = hf.position + Vector3(0, 0.08, 0)
		var head_px := camera.unproject_position(hf.global_position + Vector3(0, 2.0, 0))
		hint.text = "Clique para conversar   â€¢   botão direito: opções" if NPCManager.talking_to == "" else "Em conversa"
		hint.size = hint.get_combined_minimum_size()
		hint.position = head_px - Vector2(hint.size.x / 2.0, hint.size.y + 8.0)
		hint.visible = true
	elif not hover_object.is_empty() and not _paused():
		hover_ring.visible = false
		hint.text = str(hover_object["label"]) + "  •  clique para interagir"
		hint.size = hint.get_combined_minimum_size()
		hint.position = camera.unproject_position((hover_object["bounds"] as AABB).get_center()) - Vector2(hint.size.x / 2.0, hint.size.y + 12.0)
		hint.visible = true
	else:
		hover_ring.visible = false
		hint.visible = false


func _tr(what: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	if trace and now - since > 4000:
		print("TRACE %s %.1fms" % [what, (now - since) / 1000.0])
		return Time.get_ticks_usec()
	return now


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _paused() -> bool:
	return pause_check.is_valid() and bool(pause_check.call())


func _physics_process(delta: float) -> void:
	if not _built or not GameState.active or _paused(): return
	physical_world.tick(delta)
	_move_player(delta)
	_update_npcs(delta)
	for id in npcs:
		var entry: Dictionary = npcs[id]
		if not entry.has("physical"): continue
		var fig: Node3D = entry["fig"]
		entry["physical"].resolve(delta, str(entry["loc"]) != "" and fig.position.distance_squared_to(player.position) < 2304.0, str(entry.get("act", "")) in ["sentar", "ir_sentar", "ir_refeicao", "deitado"])
	life.update(delta, _p2(), TimeManager.hour() >= 22 or TimeManager.hour() < 5, WorldEvents.raining())

func _physical_damage(amount: float, cause: String) -> void:
	if not _act.is_empty(): _cancel_action("Atividade interrompida pelo impacto.")
	physical_world.release()
	path.clear()
	_floor_segments.clear()
	pending_npc = ""
	NeedsSystem.apply({"saude": -amount}, cause)
	if NeedsSystem.get_value("saude") > 0 and NeedsSystem.get_value("saude") < 20:
		Economy.sus_treatment.call_deferred(true)

func _npc_physical_damage(id: String, amount: float, _cause: String) -> void:
	var st: Dictionary = NPCManager.state.get(id, {})
	if st.is_empty(): return
	st["saude"] = maxi(0, int(st.get("saude", 100)) - int(ceil(amount)))
	if int(st["saude"]) < 50: st["internar_em"] = TimeManager.total_minutes + 45
	if npcs.has(id): _end_act(npcs[id], npcs[id]["fig"])

func push_npc(id: String) -> bool:
	if not npcs.has(id) or GameState.is_minor() or int(NPCManager.npcs[id].get("idade", 30)) < 18: return false
	var entry: Dictionary = npcs[id]
	var fig: Node3D = entry["fig"]
	if fig.global_position.distance_to(player.global_position) > 2.2 or player_physics.blocked(): return false
	_end_act(entry, fig)
	return entry["physical"].impact(fig.global_position - player.global_position, 2.2)

func _move_player(delta: float) -> void:
	player_physics.begin(delta)
	if player_physics.blocked():
		player.velocity.x = player_physics.impulse.x
		player.velocity.z = player_physics.impulse.z
		player.velocity.y = 0.0 if player.is_on_floor() else player.velocity.y - 20 * delta
		player.move_and_slide()
		player_physics.after_move()
		player_fig.walking = false
		player_fig.move_speed = 0
		return
	if _paused():
		player.velocity = Vector3.ZERO
		player_fig.walking = false
		player_fig.move_speed = 0.0
		return
	if path.is_empty() and not _floor_segments.is_empty():
		_next_floor_segment()
	if not _act.is_empty() and str(_act["stage"]) in ["alinhar", "animar", "manter", "fim"]:
		if _moving_keys():
			_cancel_action("Atividade interrompida.")
		else:
			player.velocity = Vector3.ZERO
			player_fig.walking = false
			player_fig.move_speed = 0.0
			return
	# engasgos de quadro (montagem de interiores) não podem virar teletransporte nem falso travamento
	var frame_delta := delta
	delta = minf(delta, 0.05)
	var dir := Vector3.ZERO
	if not _typing() and not _paused():
		var keys := Vector2.ZERO
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			keys.y -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			keys.y += 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			keys.x += 1
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			keys.x -= 1
		dir = movement_direction(keys)
	if dir != Vector3.ZERO:
		_floor_segments.clear()
		path = PackedVector2Array()
		_precise_steps = 0
		pending_npc = ""
		marker.visible = false
		dir = dir.normalized()
	elif not path.is_empty():
		var tgt: Vector2 = path[0]
		var d := tgt - _p2()
		var precise_path := _precise_steps > 0 or (not _act.is_empty() and bool(_act["plan"].get("precise", false)))
		var tolerance := 0.018 if not _act.is_empty() and _act["plan"].has("reach") else (0.035 if precise_path else 0.4)
		if d.length() < tolerance:
			if precise_path and path.size() > 1:
				var next_heading := (path[1] - tgt).angle()
				var heading := Vector2(player.velocity.x, player.velocity.z).angle()
				if absf(angle_difference(heading, next_heading)) > 0.35:
					# Chega devagar à quina antes de girar; não corta o canto do móvel.
					player.velocity.x = 0.0
					player.velocity.z = 0.0
			path.remove_at(0)
			_precise_steps = maxi(0, _precise_steps - 1)
			_stuck = 0.0
			if path.is_empty():
				marker.visible = false
		else:
			dir = Vector3(d.x, 0, d.y).normalized()
	var running := Input.is_physical_key_pressed(KEY_SHIFT) and dir != Vector3.ZERO
	var age_profile := HumanMotion.profile(int(GameState.player.get("age", 30)))
	var speed := (RUN_SPEED * float(age_profile["run"])) if running else (WALK_SPEED * float(age_profile["walk"]))
	var precise := _precise_steps > 0 or (not _act.is_empty() and bool(_act["plan"].get("precise", false)))
	if precise and not path.is_empty():
		var distance := _p2().distance_to(path[0])
		speed *= clampf(distance / 0.55, 0.1, 1.0)
		if path.size() > 1:
			var incoming := (path[0] - _p2()).normalized()
			var outgoing := (path[1] - path[0]).normalized()
			if incoming.dot(outgoing) < 0.9:
				speed *= lerpf(0.15, 1.0, smoothstep(0.03, 0.7, distance))
	if NeedsSystem.get_value("energia") < 12.0:
		speed *= 0.6
		running = false
	var before := player.position
	# Inércia de verdade: direção (heading) e velocidade escalar separadas. O corpo
	# faz curvas com raio, freia antes de inverter e arranca alinhado, sem derrapar de lado.
	var vel_now := Vector2(player.velocity.x, player.velocity.z)
	var cur_speed := vel_now.length()
	var accel := float(age_profile["accel"])
	if dir != Vector3.ZERO:
		var want_h := atan2(dir.x, dir.z)
		if cur_speed < 0.4:
			_p_heading = want_h
		else:
			var turn_rate := lerpf(12.0, 5.0, clampf(cur_speed / 5.0, 0.0, 1.0))
			_p_heading += clampf(angle_difference(_p_heading, want_h), -turn_rate * delta, turn_rate * delta)
		var align := maxf(0.0, cos(angle_difference(_p_heading, want_h)))
		var target_speed := speed * lerpf(0.3, 1.0, align * align)
		if cur_speed < 2.0:
			# virado para o outro lado: gira no lugar (passinhos) antes de sair andando
			var body_align := cos(angle_difference(player_fig.rotation.y, _p_heading))
			target_speed *= smoothstep(0.35, 0.9, body_align)
		var rate := accel * lerpf(1.0, 0.55, clampf(cur_speed / maxf(speed, 0.1), 0.0, 1.0)) if target_speed > cur_speed else 15.0
		cur_speed = move_toward(cur_speed, target_speed, rate * delta)
	else:
		# frenagem de gente: cerca de um passo ao andar, dois a três ao correr
		cur_speed = move_toward(cur_speed, 0.0, (3.6 + cur_speed * 1.2) * delta)
	var vel2 := Vector2(sin(_p_heading), cos(_p_heading)) * cur_speed
	player.velocity.x = vel2.x
	player.velocity.z = vel2.y
	player.velocity += player_physics.impulse
	player.velocity.y = 0.0 if player.is_on_floor() else player.velocity.y - 20.0 * delta
	player_physics.requested_speed = Vector2(player.velocity.x, player.velocity.z).length()
	player.move_and_slide()
	player_physics.after_move()
	var slid := Vector2(player.velocity.x, player.velocity.z)
	if slid.length() < cur_speed:
		vel2 = vel2.normalized() * slid.length()
		player.velocity.x = vel2.x
		player.velocity.z = vel2.y
	var moved := Vector2(player.position.x - before.x, player.position.z - before.z).length()
	if player.position.y > before.y + 0.001:
		NeedsSystem.apply({"energia": -(player.position.y - before.y) * 0.12})
	var real_speed: float = moved / maxf(delta, 0.0001)
	if dir != Vector3.ZERO and not path.is_empty() and moved < speed * delta * 0.15:
		_stuck += delta
		if _stuck > 1.0:
			if precise:
				_cancel_action("O caminho até o objeto está bloqueado.")
				path.clear()
				_precise_steps = 0
				return
			path.remove_at(0)
			_stuck = 0.0
	player_fig.move_speed = moved / maxf(frame_delta, 0.0001)
	var tf: Node3D = null
	if hover_id != "" and npcs.has(hover_id):
		tf = npcs[hover_id]["fig"]
	elif NPCManager.talking_to != "" and npcs.has(NPCManager.talking_to):
		tf = npcs[NPCManager.talking_to]["fig"]
	player_fig.look_target = Vector3(tf.position.x, 1.55, tf.position.z) if tf != null else Vector3.INF
	player_fig.walking = real_speed > 0.15
	var p_wet := WorldEvents.raining() and not _sheltered(_p2()) and _act.is_empty()
	player_fig.set_umbrella(p_wet)
	player_fig.hunched = p_wet
	player_fig.running = running and real_speed > WALK_SPEED * float(age_profile["walk"])
	if vel2.length() > 0.3:
		player_fig.rotation.y = lerp_angle(player_fig.rotation.y, _p_heading, minf(delta * 10.0, 1.0))
	elif dir != Vector3.ZERO:
		# parado: o corpo gira num ritmo humano (a animação de giro acompanha o ângulo)
		var turn_gap := angle_difference(player_fig.rotation.y, atan2(dir.x, dir.z))
		player_fig.rotation.y += clampf(turn_gap, -6.5 * delta, 6.5 * delta)
	_walk_acc += moved
	if _walk_acc > 10.0:
		_walk_acc -= 10.0
		NeedsSystem.apply({"energia": -0.18 if running else -0.06})
	# indo falar com alguém
	if pending_npc != "" and npcs.has(pending_npc):
		var fig: Node3D = npcs[pending_npc]["fig"]
		var fp := Vector2(fig.position.x, fig.position.z)
		if fp.distance_to(_p2()) < 1.9:
			path = PackedVector2Array()
			marker.visible = false
			var id := pending_npc
			pending_npc = ""
			_face(player_fig, fp)
			_try_talk(id)
		elif path.is_empty() or (path[path.size() - 1] as Vector2).distance_to(fp) > 2.5:
			path = layout.route(_p2(), fp)
	# saiu andando no meio da conversa
	var tt := NPCManager.talking_to
	if tt != "" and NPCManager.channel == NPCManager.PRESENCIAL:
		if _talk_anchor == Vector2.INF:
			_talk_anchor = _p2()
		elif _talk_anchor.distance_to(_p2()) > 6.0:
			_talk_anchor = Vector2.INF
			NPCManager.end_conversation()
	else:
		_talk_anchor = Vector2.INF


func _face(fig: Node3D, p: Vector2) -> void:
	var d := p - Vector2(fig.global_position.x, fig.global_position.z)
	if d.length() > 0.01:
		fig.rotation.y = atan2(d.x, d.y)


func _try_talk(id: String) -> void:
	if NPCManager.busy:
		return
	npc_chosen.emit(id)


func _update_location() -> void:
	var p := _p2()
	GameState.player["pos"] = [snappedf(p.x, 0.1), snappedf(p.y, 0.1)]
	GameState.player["pos_height"] = player.position.y
	var current_structure: Dictionary = city.loc_info.get(layout.lot_at(p), {}).get("structure", {})
	var number := _floor_in(current_structure)
	if int(GameState.player.get("interior_floor", 0)) != number:
		GameState.player["interior_floor"] = number
		GameState.player_changed.emit()
	var m := Layout.to_map(p)
	World.locations["rua"]["x"] = m.x
	World.locations["rua"]["y"] = m.y
	var lot := layout.lot_at(p)
	var cur := World.current_id()
	if World.locations.has(cur) and World.locations[cur].get("interior", false):
		if _room_rect(cur).has_point(p):
			return
		World.leave_interior()
		cur = World.current_id()
	for loc_id in World.locations:
		var loc: Dictionary = World.locations[loc_id]
		if loc.get("interior", false) and str(loc.get("pai", "")) == lot and _room_rect(loc_id).has_point(p):
			if World.has_key(str(loc.get("chave", ""))):
				World.enter_interior(loc_id)
			else:
				player.position.z = _room_rect(loc_id).end.y + 0.6
				path = PackedVector2Array()
				toast.emit("A porta do quarto está trancada.")
			return
	_find_near_door(p)
	World.arrive_on_foot(lot if lot != "" else "rua")


func _find_near_door(p: Vector2) -> void:
	var best := ""
	var best_d := 3.6
	for id in city.loc_info:
		var lot: Dictionary = layout.lots[id]
		var d := (lot["door"] as Vector2).distance_to(p)
		if d < best_d and not layout.in_building(id, p) and bool(_door_locked.get(id, false)):
			best_d = d
			best = id
	if Houses.near_door != best:
		Houses.near_door = best
		Houses.changed.emit()


func _time_flow(delta: float) -> void:
	if not realtime or _paused() or NPCManager.busy or NPCManager.talking_to != "":
		return
	_time_acc += delta * MINUTES_PER_SECOND
	if _time_acc >= 1.0:
		var m := int(_time_acc)
		_time_acc -= m
		TimeManager.advance(m)
		_last_minutes = TimeManager.total_minutes


func is_third_person() -> bool:
	return camera_rig != null and camera_rig.mode == CameraRig.Mode.THIRD_PERSON


func movement_direction(keys: Vector2) -> Vector3:
	if keys == Vector2.ZERO:
		_retain_move_keys = false
		return Vector3.ZERO
	var basis := camera_rig.movement_basis() if is_third_person() else (_retained_move_basis if _retain_move_keys else Basis(Vector3.UP, atan2(CAM_DIR.x, CAM_DIR.z)))
	return (basis * Vector3(keys.x, 0, keys.y)).normalized()


func _third_focus() -> Vector3:
	var height := 1.05 * player_fig.scale.y
	if player_fig.lying:
		height = 0.55
	elif player_fig.activity == "sentar":
		height = 0.85 * player_fig.scale.y
	return player.global_position + Vector3(0, height, 0)


func _camera_room_limit(focus: Vector3, direction: Vector3, length: float) -> float:
	# Não recuar pela porta para dentro de outro imóvel: o quadro seria visto
	# através do batente, mesmo que a abertura física da porta esteja livre.
	var start := Vector2(focus.x, focus.z)
	var motion := Vector2(direction.x, direction.z)
	var limit := length
	for structure in city.structures:
		if not (structure.has("lot") or bool(structure.get("enterable", false))) or bool(structure.get("shelter", false)):
			continue
		var rect: Rect2 = structure["rect"]
		if rect.has_point(_p2()) or not rect.grow(length + 0.3).has_point(start):
			continue
		var enter := _segment_hits_rect(start, start + motion * limit, rect.grow(0.22))
		if enter >= 0:
			limit = maxf(0, enter * limit - 0.08)
	return limit


func _on_camera_settings() -> void:
	if _built:
		set_camera_mode(Settings.camera_mode, false, false)


func set_camera_mode(mode: int, smooth := true, persist := true) -> void:
	if not _built:
		return
	mode = clampi(mode, 0, 1)
	Settings.camera_mode = mode
	if persist:
		Settings.save_settings()
	_release_orbit()
	if _camera_tween:
		_camera_tween.kill()
	if smooth and camera_rig.mode != mode:
		# Mudança de projeção discreta: evita varrer 150 m atravessando prédios.
		_camera_tween = create_tween()
		_camera_tween.tween_property(_camera_dim, "color:a", 0.24, 0.08)
		_camera_tween.tween_callback(_commit_camera_mode.bind(mode))
		_camera_tween.tween_property(_camera_dim, "color:a", 0.0, 0.12)
	else:
		_camera_dim.color.a = 0.0
		_commit_camera_mode(mode)


func _commit_camera_mode(mode: int) -> void:
	var heading := player_fig.rotation.y
	if _moving_keys():
		if mode == CameraRig.Mode.ISOMETRIC and is_third_person():
			_retained_move_basis = camera_rig.movement_basis()
			_retain_move_keys = true
		elif mode == CameraRig.Mode.THIRD_PERSON and not is_third_person():
			heading = atan2(CAM_DIR.x, CAM_DIR.z) - PI
	camera_rig.set_mode(mode, _third_focus(), heading)
	camera = camera_rig.active
	env.background_mode = Environment.BG_SKY if is_third_person() else Environment.BG_COLOR
	Atmosphere.update_sky_fog(env)
	Humanoid.set_xray_strength(0.0 if is_third_person() else 1.0)
	hover_id = ""
	hover_object = {}
	_camera(0.0)
	_cutaway()


func _camera(delta: float) -> void:
	cam_target = cam_target.lerp(player.position + Vector3(0, 1.0, 0), minf(delta * 6.0, 1.0))
	camera_rig.tick(delta, cam_target, zoom, CAM_DIR, _third_focus())
	rain.position = cam_target + Vector3(0, 22, 0)


# Abrir prédios (cutaway), como no Project Zomboid: o prédio em que o jogador está, ou o que
# fica entre a câmera e o jogador, troca para a versão recortada (sem telhado, paredes baixas
# e o interior à mostra). Antes o prédio inteiro era achatado na vertical, o que espremia
# fachada, janelas e letreiro. Folga na borda e um tempo mínimo evitam piscar.
const BLOCK_HOLD_MS := 450


func _hide_blockers(p: Vector2) -> void:
	var d := CAM_DIR.normalized()
	var hd := Vector2(d.x, d.z) / d.y          # deslocamento horizontal por metro de altura, rumo à câmera
	var now := Time.get_ticks_msec()
	for s in city.structures:
		if is_third_person():
			s["blocks"] = false
			s["block_until"] = 0
			continue
		var r: Rect2 = s["rect"]
		if not s.has("root"):
			continue
		if not s.has("h"):
			s["h"] = _structure_height(s)
		var h: float = s["h"]
		if h > 2.0 and not r.has_point(p) and r.grow(30.0).has_point(p):
			var was: bool = bool(s.get("blocks", false))
			# raio do meio do corpo até a câmera: corta enquanto ainda passa dentro do prédio
			if _segment_hits_rect(p, p + hd * (h - 0.6), r.grow(0.6 if not was else 1.4)) >= 0.0:
				s["block_until"] = now + BLOCK_HOLD_MS
		s["blocks"] = now < int(s.get("block_until", 0))


func _structure_height(s: Dictionary) -> float:
	var top := 0.0
	for node in [s["full"], s["cut"]]:
		for c in (node as Node3D).get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and (c as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				top = maxf(top, (c as MeshInstance3D).get_aabb().end.y)
	return top


# Onde (0..1) o segmento a→b entra no retângulo; -1 se não cruza.
static func _segment_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> float:
	var t0 := 0.0
	var t1 := 1.0
	var dv := b - a
	for axis in 2:
		var o := a[axis]
		var dd := dv[axis]
		var lo := r.position[axis]
		var hi := r.end[axis]
		if absf(dd) < 0.00001:
			if o < lo or o > hi:
				return -1.0
		else:
			var ta := (lo - o) / dd
			var tb := (hi - o) / dd
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			t0 = maxf(t0, ta)
			t1 = minf(t1, tb)
			if t0 > t1:
				return -1.0
	return t0


func _cutaway() -> void:
	var p := _p2()
	_hide_blockers(p)
	var built := 0
	# Prioridade para o piso ocupado. Preparar um vizinho primeiro somava
	# várias construções na mesma atualização quando o jogador entrava.
	var occupied_id := _inside_any(p)
	var occupied_structure: Dictionary = city.loc_info.get(occupied_id, {}).get("structure", {})
	if not occupied_structure.is_empty() and (occupied_structure.has("lot") or bool(occupied_structure.get("modern_interior", false))) and occupied_structure.get("interior") == null:
		city.ensure_interior(occupied_structure)
		built += 1
	for s in city.structures:
		var r: Rect2 = s["rect"]
		var dist := r.get_center().distance_to(p)
		if s.has("lot") or bool(s.get("modern_interior", false)):
			if dist < 36.0 and s.get("interior") == null and built < 1:
				city.ensure_interior(s)
				built += 1
			elif dist > 70.0 and s.get("interior") != null:
				city.drop_interior(s)
		var blocks: bool = bool(s.get("blocks", false))
		if not (s.has("lot") or s.get("enterable", false)) or dist > 45.0:
			city.set_cut(s, blocks)
			if s.has("doors"):
				(s["doors"] as Node3D).visible = not blocks
			continue
		var inside: bool = r.grow(0.7).has_point(p) if bool(s["cut_now"]) else r.has_point(p)
		var open := inside or blocks
		if open and (s.has("lot") or bool(s.get("modern_interior", false))) and s.get("interior") == null:
			if not inside and built >= 1:
				# Mantém a fachada até o interior estar pronto, em vez de
				# abrir vários imóveis vazios ou montá-los todos no mesmo quadro.
				city.set_cut(s, false)
				if s.has("doors"):
					(s["doors"] as Node3D).visible = true
				continue
			# o interior aparece junto com a abertura: nunca um quadro vazio
			city.ensure_interior(s)
			built += 1
		if open and s.get("interior") != null and not bool(s["cut_now"]):
			city.house_gen.place_now(s["interior"])
		var number := _floor_in(s)
		if inside and s.get("interior") != null:
			if not s.get("floor_nodes", {}).has(number):
				city.ensure_floor(s, number)
				built += 1
			if built < 1 and number + 1 < int(s.get("floor_count", 1)) and not s.get("floor_nodes", {}).has(number + 1):
				city.ensure_floor(s, number + 1)
				built += 1
		city.set_cut(s, open, is_third_person() and inside, number)
		if s.has("cut_back"):
			# dentro: paredes do fundo inteiras; só tapando o jogador de fora: tudo baixo
			var modern: bool = s.has("lot") or bool(s.get("modern_interior", false))
			(s["cut_back"] as Node3D).visible = inside and not modern
			(s["cut_back_low"] as Node3D).visible = not inside or modern
		if s.get("curtains") != null and is_instance_valid(s["curtains"]):
			(s["curtains"] as Node3D).visible = inside
		if s.has("doors"):
			(s["doors"] as Node3D).visible = inside or not open

func _floor_in(structure: Dictionary) -> int:
	return clampi(floori((player.position.y - 0.17 + 0.12) / float(structure.get("floor_height", 3.0))), 0, int(structure.get("floor_count", 1)) - 1)

func use_stairs(target: Dictionary) -> bool:
	if not object_access(target) or _paused() or action_busy():
		return false
	var structure: Dictionary = city.loc_info[str(target["loc"])]["structure"]
	return _route_floors(structure, int(target["plan"]["destination_floor"]))

func _route_floors(structure: Dictionary, destination: int) -> bool:
	var current := _floor_in(structure)
	destination = clampi(destination, 0, int(structure.get("floor_count", 1)) - 1)
	if current == destination:
		return false
	_floor_segments.clear()
	var from := _p2()
	var step := 1 if destination > current else -1
	# Cada chegada valida a altura física antes de preparar o próximo piso.
	# Isso também permite que os corpos recém-criados entrem no PhysicsServer.
	if current != destination:
		city.ensure_floor(structure, current)
		city.ensure_floor(structure, current + step)
		var stair_number := current if step > 0 else current - 1
		var route: Array = structure["stairs"][stair_number]["up"].duplicate()
		if step < 0:
			route.reverse()
		var approach := _furnished_path(str(structure["loc"]), route[0], from, current)
		if approach.is_empty():
			_floor_segments.clear()
			toast.emit("Não há passagem livre até a escada.")
			return false
		_floor_segments.append({"points": PackedVector2Array(approach)})
		_floor_segments.append({"points": PackedVector2Array(route)})
		from = route.back()
		current += step
		_floor_segments.append({"floor_target": destination, "arrival": current, "structure": structure})
	path.clear()
	pending_npc = ""
	_next_floor_segment()
	marker.visible = false
	return true

func _next_floor_segment() -> void:
	if _floor_segments.is_empty():
		return
	var segment: Dictionary = _floor_segments.pop_front()
	if segment.has("floor_target"):
		var structure: Dictionary = segment["structure"]
		var expected := int(segment["arrival"])
		var expected_y := 0.245 + expected * float(structure.get("floor_height", 3.0))
		if _floor_in(structure) != expected or absf(player.position.y - expected_y) > 0.18:
			_floor_segments.clear()
			toast.emit("A passagem da escada foi interrompida.")
			return
		if expected != int(segment["floor_target"]):
			var followup := _floor_segments.duplicate()
			if _route_floors(structure, int(segment["floor_target"])):
				_floor_segments.append_array(followup)
		elif not _floor_segments.is_empty():
			_next_floor_segment()
	elif segment.has("resume"):
		_go_to(segment["resume"])
	else:
		path = segment["points"]
		_precise_steps = path.size()


# ---------- ações com o corpo (dormir, banho, comer, beber) ----------
# Padrão: aproximar → alinhar → animar → aplicar o efeito real → retorno → encerrar.
# O efeito é sempre a função que já existia (HomeSystem/Economy), chamada só no fim; se o
# jogador se mexer antes, a ação é cancelada sem efeito e sem deixar pose presa.

const ACT_TIME := {"dormir": 3.4, "banho": 3.2, "comer": 3.4, "beber": 3.5, "cozinhar": 5.8, "tv": 4.0, "sofa": 4.0, "pc": 5.0, "sentar": 0.6, "deitar": 0.8, "pegar": 1.8, "examinar": 1.5}


func action_busy() -> bool:
	return not _act.is_empty()


func object_access(target: Dictionary) -> bool:
	if target.is_empty() or not GameState.active or NPCManager.busy:
		return false
	var owner = target.get("owner")
	if owner != null and (not is_instance_valid(owner) or not (owner as Node3D).is_visible_in_tree()):
		return false
	if Vector2((target["bounds"] as AABB).get_center().x, (target["bounds"] as AABB).get_center().z).distance_to(_p2()) > 26.0:
		return false
	if not bool(target["outdoor"]):
		var loc := str(target["loc"])
		if target.get("plan", {}).has("floor") and city.loc_info.has(loc):
			if int(target["plan"]["floor"]) != _floor_in(city.loc_info[loc]["structure"]):
				return false
		return _inside_any(_p2()) == loc and city.loc_info.has(loc) and bool(city.loc_info[loc]["structure"]["cut_now"])
	return true


func start_object_action(target: Dictionary, kind: String, effect: Callable, item: String = "") -> bool:
	if not object_access(target):
		return false
	if kind in ["pegar", "examinar"] and player_fig.skel == null:
		return false
	var loc := str(target["loc"])
	var plan: Dictionary = target["plan"].duplicate(true)
	if kind in ["pegar", "examinar"]:
		plan = _object_reach_plan(target, item)
		if plan.is_empty():
			return false
		if item != "" and GameState.money() < World.item_price(item):
			toast.emit("Dinheiro insuficiente para comprar " + World.item_name(item) + ".")
			return false
	var points: Dictionary = city.use_points.get(loc, {})
	if loc == "rodoviaria":
		plan["path"] = Array(_terminal_path(plan["path"].back()))
		plan["precise"] = true
		if (plan["path"] as Array).is_empty():
			return false
	elif not bool(plan.get("routed", false)) and ((points.has("_root") and plan.has("room")) or (loc == "mercado" and not bool(target.get("outdoor", false)))):
		# A mesma fila de movimento passa por AStar2D dentro do imóvel. A geometria
		# física dos móveis/divisórias decide a passagem, em vez de ignorar colisões.
		plan["path"] = _furnished_path(loc, plan["path"].back())
		plan["precise"] = true
		if (plan["path"] as Array).is_empty():
			return false
	return start_action(kind, loc, effect, item, plan)


# O destino vem da superfície do móvel/produto, nunca da ponta genérica da sala.
func _object_reach_plan(target: Dictionary, item: String) -> Dictionary:
	var bounds: AABB = target["bounds"]
	var center := bounds.get_center()
	var candidates: Array = []
	var products: Dictionary = target.get("products", {})
	if products.has(item):
		for source in products[item]:
			if is_instance_valid(source):
				var point: Vector3 = source.global_position
				var forward := Vector2(0, -1) if point.z > center.z else Vector2(0, 1)
				candidates.append({"reach": point, "source": source, "forward": forward})
	else:
		# Clique conserva o ponto atingido; a face mais próxima continua sendo usada
		# se o menu foi aberto por outro controle ou por um teste.
		var hit: Vector3 = target.get("hit", center)
		var y := clampf(hit.y, bounds.position.y + 0.12, bounds.end.y - 0.08)
		y = minf(y, player.position.y + 1.2 * player_fig.scale.y)
		for side in [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]:
			var point := Vector3(clampf(hit.x, bounds.position.x + 0.1, bounds.end.x - 0.1), y, clampf(hit.z, bounds.position.z + 0.1, bounds.end.z - 0.1))
			if side.x != 0:
				point.x = bounds.end.x if side.x > 0 else bounds.position.x
			else:
				point.z = bounds.end.z if side.y > 0 else bounds.position.z
			candidates.append({"reach": point, "forward": -side})
	for c in candidates:
		var forward: Vector2 = c["forward"]
		var reach: Vector3 = c["reach"]
		var gap := maxf(0.49, 0.49 * player_fig.scale.y)
		c["stand"] = Vector2(reach.x, reach.z) - forward * gap + Vector2(forward.y, -forward.x) * 0.13 * player_fig.scale.y
	candidates.sort_custom(func(a, b): return (a["stand"] as Vector2).distance_squared_to(_p2()) < (b["stand"] as Vector2).distance_squared_to(_p2()))
	var sphere := SphereShape3D.new()
	sphere.radius = 0.29
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = PhysicsLayers.WORLD
	query.exclude = [player.get_rid()]
	for c in candidates:
		var stand: Vector2 = c["stand"]
		query.transform.origin = Vector3(stand.x, player.position.y + 0.65, stand.y)
		if not player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			continue
		var forward: Vector2 = c["forward"]
		var result: Dictionary = (target["plan"] as Dictionary).duplicate(true)
		result.merge({"path": [stand], "yaw": atan2(forward.x, forward.y), "reach": c["reach"], "source": c.get("source"), "object": target, "precise": true}, true)
		var loc := str(target["loc"])
		if city.use_points.get(loc, {}).has("_root") or loc == "mercado":
			var route := _furnished_path(loc, stand)
			if route.is_empty():
				continue
			result["path"] = route
			result["routed"] = true
		return result
	return {}


func _furnished_path(loc: String, destination: Vector2, origin := Vector2.INF, number := -1, forced_step := 0.0) -> Array:
	var started := Time.get_ticks_usec()
	if origin == Vector2.INF:
		origin = _p2()
	var space := player.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = 0.29
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.exclude = [player.get_rid()]
	query.collision_mask = PhysicsLayers.WORLD
	var building: Dictionary = city.loc_info.get(loc, {}).get("structure", {})
	if number < 0:
		number = _floor_in(building)
	var floor_y := 0.17 + float(number) * float(building.get("floor_height", 3.0))
	var cache_key := loc + ":" + str(number)
	var floor_node: Node3D = building.get("floor_nodes", {}).get(number)
	var shaft_area := Rect2()
	if is_instance_valid(floor_node) and building.has("stair_rect"):
		var shaft: Rect2 = building["stair_rect"]
		var volume := floor_node.global_transform * AABB(Vector3(shaft.position.x, 0, shaft.position.y), Vector3(shaft.size.x, 0.01, shaft.size.y))
		# Só excluir o vazio real. Inflar o poço invadia o hall sólido e
		# aprisionava entradas próximas ao patamar, apesar da varredura livre.
		shaft_area = Rect2(volume.position.x, volume.position.z, volume.size.x, volume.size.z)
	var sweep := func(a: Vector2, b: Vector2) -> bool:
		if shaft_area.size != Vector2.ZERO and _segment_hits_rect(a, b, shaft_area) >= 0:
			return false
		query.transform.origin = Vector3(a.x, floor_y + 0.48, a.y)
		query.motion = Vector3(b.x - a.x, 0, b.y - a.y)
		var fraction := space.cast_motion(query)
		return fraction[0] > 0.999
	query.motion = Vector3.ZERO
	query.transform.origin = Vector3(origin.x, floor_y + 0.48, origin.y)
	var source_free := space.intersect_shape(query, 1).is_empty()
	query.transform.origin = Vector3(destination.x, floor_y + 0.48, destination.y)
	if source_free and space.intersect_shape(query, 1).is_empty() and sweep.call(origin, destination):
		return [origin, destination]
	var graph := AStar2D.new()
	var cells: Dictionary = {}
	var region: Rect2 = layout.lots[loc]["building"]
	if region.size == Vector2.ZERO:
		region = layout.lots[loc]["rect"]
	var rect := region.grow(-0.36)
	var structure: Dictionary = city.loc_info.get(loc, {}).get("structure", {})
	var interior = structure.get("interior")
	var stamp := str(interior.get_instance_id()) + ":" + str(interior.get_child_count()) if is_instance_valid(interior) else "fixed"
	var root: Node3D = structure.get("root")
	if is_instance_valid(root):
		stamp += ":" + str(snappedf(root.scale.y, 0.01))
	stamp += ":" + str(_door_locked.get(loc, false))
	var cached: Dictionary = _furniture_routes.get(cache_key, {})
	var guides: Array = floor_node.get_meta("use_points").get("_portals", []) if is_instance_valid(floor_node) else []
	# Primeiro, portais e quinas da planta já validada. Uma grade densa em
	# todos os cômodos custava até centenas de ms na primeira interação.
	# Se essa malha não resolve a rota, a mesma busca recebe a grade física.
	var sparse := forced_step == 0.0 and not guides.is_empty()
	# Vãos estreitos precisam de amostragem menor que a folga entre móveis.
	var step := 0.7 if loc == "rodoviaria" else (0.25 if is_instance_valid(floor_node) and rect.get_area() < 110 else (0.4 if is_instance_valid(floor_node) else (0.22 if points_for_small_room(loc) else 0.4)))
	if forced_step > 0:
		step = forced_step
	elif str(cached.get("stamp", "")) == stamp:
		step = float(cached.get("step", step))
	if str(cached.get("stamp", "")) == stamp and is_equal_approx(float(cached.get("step", step)), step) and (forced_step == 0.0 or not bool(cached.get("sparse", false))):
		graph = cached["graph"]
		cells = cached["cells"]
		sparse = bool(cached.get("sparse", false))
	else:
		for y in (0 if sparse else int(ceil(rect.size.y / step))):
			for x in int(ceil(rect.size.x / step)):
				var p := rect.position + Vector2(x, y) * step
				query.transform.origin = Vector3(p.x, floor_y + 0.48, p.y)
				query.motion = Vector3.ZERO
				var free := not shaft_area.has_point(p) and space.intersect_shape(query, 1).is_empty()
				if free:
					var key := graph.get_available_point_id()
					graph.add_point(key, p)
					cells[Vector2i(x, y)] = key
		for cell in cells:
			for offset in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
				if cells.has(cell + offset):
					var a: int = cells[cell]
					var b: int = cells[cell + offset]
					if sweep.call(graph.get_point_position(a), graph.get_point_position(b)):
						graph.connect_points(a, b)
		# Portais da planta e aproximações dos móveis enriquecem o mesmo AStar2D.
		# A grade uniforme perdia corredores válidos quando a porta caía entre células.
		# Cada ligação continua sujeita à varredura física; não atravessa paredes.
		var guide_number := 0
		var guide_ids: Array[int] = []
		var hub_keys := {}
		var hub_ids: Array[int] = []
		if is_instance_valid(floor_node):
			for info in floor_node.get_meta("use_points").get("_rooms", []):
				var entry: Vector2 = info["entry"]
				var world := floor_node.global_transform * Vector3(entry.x, 0, entry.y)
				hub_keys[Vector2i(roundi(world.x * 100), roundi(world.z * 100))] = true
		for point in guides:
			if not rect.has_point(point) or shaft_area.has_point(point):
				continue
			query.transform.origin = Vector3(point.x, floor_y + 0.48, point.y)
			query.motion = Vector3.ZERO
			if not space.intersect_shape(query, 1).is_empty():
				continue
			var guide := graph.get_available_point_id()
			graph.add_point(guide, point)
			var hub := hub_keys.has(Vector2i(roundi(point.x * 100), roundi(point.y * 100)))
			for other in graph.get_point_ids():
				if other == guide:
					continue
				var next := graph.get_point_position(other)
				# Entradas dos cômodos ligam trechos abertos longos sem criar
				# milhares de células. A visibilidade continua sendo física.
				var reach := (INF if hub or other in hub_ids else 3.0) if other in guide_ids else 0.75
				if point.distance_squared_to(next) < reach * reach and sweep.call(point, next):
					graph.connect_points(guide, other)
			guide_ids.append(guide)
			if hub:
				hub_ids.append(guide)
			cells[Vector2i(-10000 - guide_number, -1)] = guide
			guide_number += 1
		_furniture_routes[cache_key] = {"stamp": stamp, "graph": graph, "cells": cells, "step": step, "sparse": sparse}
		while _furniture_routes.size() > 8:
			_furniture_routes.erase(_furniture_routes.keys()[0])
	var first := graph.get_available_point_id()
	graph.add_point(first, origin)
	var last := graph.get_available_point_id()
	graph.add_point(last, destination)
	for key in cells.values():
		var p := graph.get_point_position(key)
		if p.distance_to(origin) < 1.0 and sweep.call(origin, p):
			graph.connect_points(first, key)
		if p.distance_to(destination) < 1.0 and sweep.call(p, destination):
			graph.connect_points(key, last)
	var result := graph.get_point_path(first, last)
	graph.remove_point(first)
	graph.remove_point(last)
	if result.is_empty() and sparse:
		return _furnished_path(loc, destination, origin, number, step)
	if result.is_empty() and step > 0.15 and is_instance_valid(floor_node) and rect.get_area() < 120:
		# Refinamento local da mesma malha quando as folgas ficam entre células.
		# O resultado refinado fica em cache; todas as ligações usam colisão real.
		return _furnished_path(loc, destination, origin, number, 0.15)
	# Retira os pontos da grade que ficam na mesma passagem livre. Mantém quinas
	# reais para a frenagem, sem parar a cada célula do AStar.
	if result.size() > 2:
		var smooth := PackedVector2Array([result[0]])
		var index := 0
		while index < result.size() - 1:
			var next := result.size() - 1
			while next > index + 1 and not sweep.call(result[index], result[next]):
				next -= 1
			smooth.append(result[next])
			index = next
		result = smooth
	print("OBJECT ROUTE ", loc, " ms=", snappedf((Time.get_ticks_usec() - started) / 1000.0, 0.1), " points=", result.size())
	return Array(result)


func points_for_small_room(loc: String) -> bool:
	return city.use_points.get(loc, {}).has("_root")


func start_action(kind: String, loc_id: String, effect: Callable, item_id: String = "", override_plan: Dictionary = {}) -> bool:
	if not _act.is_empty() or not GameState.active or NPCManager.busy or not _built:
		return false
	var pts: Dictionary = city.use_points.get(loc_id, {})
	var plan := {}
	match kind:
		"sentar", "deitar", "pegar", "examinar":
			if override_plan.is_empty():
				return false
			plan = override_plan.duplicate(true)
		"dormir":
			if not pts.has("cama"):
				return false
			plan = (pts["cama"] as Dictionary).duplicate()
		"banho":
			if not pts.has("chuveiro"):
				return false
			plan = (pts["chuveiro"] as Dictionary).duplicate()
		"cozinhar", "tv", "sofa", "pc":
			var point_key := "fogao" if kind == "cozinhar" else ("computador" if kind == "pc" else "sofa")
			if not pts.has(point_key):
				return false
			plan = (pts[point_key] as Dictionary).duplicate(true)
		"comer", "beber":
			var lot := layout.lot_at(_p2())
			var floor_number := _floor_in(city.loc_info.get(lot, {}).get("structure", {}))
			var seat = _free_seat(lot, _p2(), floor_number) if lot != "" else null
			if seat != null and (seat["p"] as Vector2).distance_to(_p2()) < 14.0:
				plan = {"path": [seat.get("approach", seat["p"])], "yaw": float(seat["yaw"]), "pose": "sentar", "seat": seat}
				if seat.has("room"):
					plan["room"] = seat["room"]
			else:
				plan = {"path": [], "yaw": player_fig.rotation.y, "pose": "em_pe"}
		_:
			return false
	if not override_plan.is_empty():
		plan = override_plan.duplicate(true)
	if loc_id == "rodoviaria" and not bool(plan.get("precise", false)) and not (plan.get("path", []) as Array).is_empty():
		plan["path"] = Array(_terminal_path(plan["path"].back()))
		plan["precise"] = true
		if (plan["path"] as Array).is_empty():
			return false
	elif override_plan.is_empty() and pts.has("_root") and plan.has("room") and not (plan.get("path", []) as Array).is_empty():
		plan["path"] = _furnished_path(loc_id, plan["path"].back())
		plan["precise"] = true
		if (plan["path"] as Array).is_empty():
			return false
	if plan.has("seat") and kind in ["sentar", "tv", "sofa", "pc", "comer", "beber"]:
		var key := _seat_key(plan["seat"])
		if seat_used.has(key):
			return false
		seat_used[key] = "jogador"
	if kind in ["dormir", "deitar"] and plan.has("anchor"):
		var key := _bed_key(plan)
		if seat_used.has(key):
			return false
		seat_used[key] = "jogador"
		plan["reservation"] = key
	if NPCManager.talking_to != "":
		NPCManager.end_conversation()
	_act = {"kind": kind, "plan": plan, "stage": "ir", "t": 0.0, "effect": effect, "item": item_id, "applied": false}
	path = PackedVector2Array(plan.get("path", []))
	_precise_steps = 0
	pending_npc = ""
	marker.visible = false
	return true


func _moving_keys() -> bool:
	if _typing() or _paused():
		return false
	for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		if Input.is_physical_key_pressed(k):
			return true
	return false


func _update_action(delta: float) -> void:
	var a := _act
	var plan: Dictionary = a["plan"]
	var kind := str(a["kind"])
	a["t"] = float(a["t"]) + delta
	match str(a["stage"]):
		"ir":
			if not path.is_empty():
				if float(a["t"]) > 25.0:
					_cancel_action("Não deu para chegar lá.")
				return
			var pts: Array = plan.get("path", [])
			var target: Vector2 = pts.back() if not pts.is_empty() else _p2()
			if _p2().distance_to(target) > (0.14 if plan.has("reach") else 0.7) or _moving_keys():
				_cancel_action("Ação interrompida.")
				return
			a["stage"] = "alinhar"
			a["t"] = 0.0
		"alinhar":
			if _moving_keys():
				_cancel_action("Ação interrompida.")
				return
			player_fig.rotation.y = lerp_angle(player_fig.rotation.y, float(plan["yaw"]), minf(delta * 10.0, 1.0))
			if float(a["t"]) > 0.3:
				_begin_pose()
				a["stage"] = "animar"
				a["t"] = 0.0
		"animar":
			if _moving_keys() and not bool(a["applied"]):
				_cancel_action("Ação interrompida.")
				return
			if kind == "dormir":
				_fade.color.a = minf(0.92, float(a["t"]) / 1.6)
			if plan.has("reach"):
				_update_reach_action(a)
				if _act.is_empty():
					return
			if float(a["t"]) >= float(ACT_TIME[kind]):
				if not bool(a["applied"]):
					a["applied"] = true
					(a["effect"] as Callable).call()
				a["stage"] = "manter" if kind in ["sentar", "deitar"] else "fim"
				a["t"] = 0.0
		"fim":
			if kind == "dormir":
				_fade.color.a = maxf(0.0, 0.92 - float(a["t"]) / 0.9)
			if float(a["t"]) > (1.0 if kind == "dormir" else 0.3):
				_end_pose()
				_act = {}


func _update_reach_action(a: Dictionary) -> void:
	var plan: Dictionary = a["plan"]
	var time := float(a["t"])
	var take := str(a["kind"]) == "pegar"
	player_fig.reach_target = plan["reach"]
	player_fig.reach_weight = smoothstep(0.0, 0.62, time) * (1.0 - smoothstep(1.05, 1.75, time))
	player_fig.reach_grip = smoothstep(0.58, 0.82, time) if take else 0.0
	if time < 0.72 or bool(a["applied"]):
		return
	# Contato real antes de transferir item/efeito. Alcance impossível cancela sem pagar.
	var hand := player_fig.skel.find_bone("hand_r")
	var hand_pos: Vector3 = player_fig.grasp_position()
	if hand_pos.distance_to(plan["reach"]) > 0.035:
		if time > 1.0:
			_cancel_action("Não foi possível alcançar o objeto.")
		return
	if not object_access(plan["object"]):
		_cancel_action("Esse objeto não está mais disponível.")
		return
	a["applied"] = true
	var result: Variant = (a["effect"] as Callable).call()
	if result is bool and not result:
		_cancel_action("A ação não pôde ser concluída.")
		return
	if take and is_instance_valid(plan.get("source")):
		var source: MeshInstance3D = plan["source"]
		var att := BoneAttachment3D.new()
		att.bone_name = "hand_r"
		player_fig.skel.add_child(att)
		var held := MeshInstance3D.new()
		held.mesh = source.mesh
		held.material_override = source.material_override
		var hand_world: Transform3D = player_fig.skel.global_transform * player_fig.skel.get_bone_global_pose(hand)
		held.transform = hand_world.affine_inverse() * source.global_transform
		att.add_child(held)
		source.visible = false
		_act_props.append(att)


func _begin_pose() -> void:
	var plan: Dictionary = _act["plan"]
	_act["stand"] = player.position
	Humanoid.set_xray_strength(0.0)
	player_fig.daily_action = str(_act["kind"])
	player_fig.action_time = 0.0
	match str(_act["kind"]):
		"dormir", "deitar":
			# deita de costas: pés no pé da cama, cabeça no travesseiro, e se cobre
			var anchor: Vector3 = plan["anchor"]
			player.position = Vector3(anchor.x, player.position.y, anchor.z)
			player_fig.rotation = Vector3(-PI / 2.0, float(plan["yaw"]), 0.0)
			player_fig.position = Vector3(0, float(plan["h"]) + 0.15, 0)
			var kit := preload("res://world3d/mesh_kit.gd").new()
			kit.box(Vector3(0, 0, -0.55), Vector3(0.8, 0.08, 1.2), Color("#4a5a72"))
			kit.box(Vector3(0, 0.01, -1.15), Vector3(0.82, 0.1, 0.12), Color("#e9e4d8"))
			var cover := MeshInstance3D.new()
			cover.mesh = kit.commit(city.mat)
			# coberta logo acima do corpo deitado (frente do corpo fica ~0,3 m acima do colchão)
			cover.position = Vector3(anchor.x, player.position.y + float(plan["h"]) + 0.36, anchor.z)
			cover.rotation.y = float(plan["yaw"])
			viewport.add_child(cover)
			_act_props.append(cover)
			if _fade == null:
				_fade = ColorRect.new()
				_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_fade.color = Color(0.02, 0.02, 0.04, 0.0)
				add_child(_fade)
		"banho":
			player_fig.activity = "banho"
			# água caindo do chuveiro
			var w := CPUParticles3D.new()
			w.amount = 70
			w.lifetime = 0.6
			w.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			w.emission_sphere_radius = 0.12
			w.direction = Vector3.DOWN
			w.spread = 8.0
			w.initial_velocity_min = 2.5
			w.initial_velocity_max = 3.2
			w.gravity = Vector3(0, -6, 0)
			w.scale_amount_min = 0.5
			w.scale_amount_max = 0.8
			var qm := QuadMesh.new()
			qm.size = Vector2(0.02, 0.16)
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = Color(0.8, 0.9, 1.0, 0.55)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			qm.material = m
			w.mesh = qm
			w.position = plan["head"]
			viewport.add_child(w)
			_act_props.append(w)
		"cozinhar":
			player_fig.activity = "cozinhar"
			var steam := CPUParticles3D.new()
			steam.amount = 14
			steam.lifetime = 1.2
			steam.direction = Vector3.UP
			steam.gravity = Vector3(0, 0.2, 0)
			steam.initial_velocity_min = 0.15
			steam.initial_velocity_max = 0.3
			var quad := QuadMesh.new()
			quad.size = Vector2(0.05, 0.05)
			var vapor := StandardMaterial3D.new()
			vapor.albedo_color = Color(0.9, 0.9, 0.9, 0.18)
			vapor.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			vapor.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			quad.material = vapor
			steam.mesh = quad
			steam.position = plan["steam"]
			viewport.add_child(steam)
			_act_props.append(steam)
		"tv", "sofa", "pc", "sentar":
			if plan.has("seat"):
				var seat_pos: Vector2 = plan["seat"]["p"]
				player.position = Vector3(seat_pos.x, player.position.y, seat_pos.y)
			player_fig.activity = "sentar"
		"pegar", "examinar":
			player_fig.daily_action = ""
			player_fig.activity = ""
			if player_fig.player_motion != null and player_fig.player_motion.get("mocap") == true:
				player_fig.player_motion.settle()
			player_fig.reach_target = plan.get("reach", Vector3.INF)
			player_fig.reach_weight = 0.0
		"comer", "beber":
			if str(plan.get("pose", "")) == "sentar":
				var sp: Vector2 = plan["seat"]["p"]
				player.position = Vector3(sp.x, player.position.y, sp.y)
				player_fig.activity = "sentar"
			else:
				player_fig.activity = ""
			var held := _held_item(str(_act["item"]), str(_act["kind"]))
			if held != null:
				_act_props.append(held)


# Comida ou bebida na mão (presa no osso da mão direita).
func _held_item(item_id: String, kind: String) -> Node3D:
	return _held_for(player_fig, item_id, kind)


func _held_for(fig: Humanoid, item_id: String, kind: String) -> Node3D:
	if fig.skel == null or fig.skel.find_bone("hand_r") < 0:
		return null
	var att := BoneAttachment3D.new()
	att.bone_name = "hand_r"
	fig.skel.add_child(att)
	var kit := preload("res://world3d/mesh_kit.gd").new()
	var tipo := str(World.items.get(item_id, {}).get("tipo", ""))
	if kind == "beber":
		var col := {"agua": Color("#a8d0e8"), "refrigerante": Color("#b02a22"), "cafe": Color("#f2efe8"), "cerveja": Color("#4a6a3a"), "energetico": Color("#2a5a9a"), "cachaca": Color("#d8d0b0")}
		var c: Color = col.get(item_id, Color("#9aa0a4"))
		if tipo == "cafe":
			kit.cyl(Vector3(0, -0.04, 0.06), 0.035, 0.08, c)
		elif tipo == "garrafa":
			kit.cyl(Vector3(0, -0.1, 0.06), 0.035, 0.18, c)
			kit.cyl(Vector3(0, 0.08, 0.06), 0.014, 0.07, c)
		else:
			kit.cyl(Vector3(0, -0.07, 0.06), 0.034, 0.13, c)
			kit.cyl(Vector3(0, 0.06, 0.06), 0.03, 0.01, Color("#c8ccd0"))
	else:
		var food := {"pao": Color("#c9883a"), "pao_queijo": Color("#e0b060"), "coxinha": Color("#c97a2a"), "frutas": Color("#c0392b"), "pipoca": Color("#f2e8c8"), "miojo": Color("#e8c060"), "prato_feito": Color("#8a5a2a")}
		var c2: Color = food.get(item_id, Color("#c9883a"))
		if item_id == "prato_feito" or item_id == "miojo":
			kit.cyl(Vector3(0, -0.02, 0.1), 0.11, 0.02, Color("#f2f2f0"))
			kit.sphere(Vector3(0.03, 0.01, 0.1), Vector3(0.1, 0.05, 0.09), c2)
			kit.sphere(Vector3(-0.04, 0.01, 0.08), Vector3(0.07, 0.04, 0.07), Color("#e8e0c8"))
		else:
			kit.sphere(Vector3(0, 0, 0.06), Vector3(0.09, 0.07, 0.11), c2)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit(city.mat)
	# o corpo é escalado; o objeto mantém o tamanho real
	mi.scale = Vector3.ONE / maxf(fig.scale.y, 0.5)
	att.add_child(mi)
	return att


func _end_pose() -> void:
	Humanoid.set_xray_strength(0.0 if is_third_person() else 1.0)
	player_fig.rotation = Vector3(0.0, player_fig.rotation.y, 0.0)
	player_fig.position = Vector3.ZERO
	player_fig.activity = ""
	player_fig.daily_action = ""
	player_fig.action_time = 0.0
	player_fig.reach_target = Vector3.INF
	player_fig.reach_weight = 0.0
	player_fig.reach_grip = 0.0
	for p in _act_props:
		if is_instance_valid(p):
			p.queue_free()
	_act_props.clear()
	if _fade != null:
		_fade.color.a = 0.0
	if not _act.is_empty():
		var plan: Dictionary = _act["plan"]
		# Estoque de exposição da loja se recompõe; inventário segue só Economy.
		if is_instance_valid(plan.get("source")):
			(plan["source"] as Node3D).visible = true
		if plan.has("seat"):
			var key := _seat_key(plan["seat"])
			if str(seat_used.get(key, "")) == "jogador":
				seat_used.erase(key)
		if plan.has("reservation"):
			seat_used.erase(str(plan["reservation"]))
		if _act.has("stand") and str(_act["kind"]) in ["dormir", "deitar", "sentar", "tv", "sofa", "pc", "comer", "beber"]:
			# Só retorna se a pose começou. Cancelar durante a aproximação não teletransporta.
			player.position = _act["stand"]


func _cancel_action(msg: String) -> void:
	_end_pose()
	_act = {}
	path.clear()
	_precise_steps = 0
	_stuck = 0.0
	marker.visible = false
	toast.emit(msg)


# ---------- NPCs ----------

func _inside_any(p: Vector2) -> String:
	var lot := layout.lot_at(p)
	return lot if lot != "" and layout.in_building(lot, p) else ""


func _sheltered(p: Vector2) -> bool:
	var lot := layout.lot_at(p)
	if lot == "":
		return false
	if layout.in_building(lot, p):
		return true
	if lot != "rodoviaria":
		return false
	for structure in city.structures:
		if bool(structure.get("shelter", false)) and (structure["rect"] as Rect2).has_point(p):
			return true
	return false


func _update_nearby() -> void:
	var pp := _p2()
	var mine := _inside_any(pp)
	var out: Array = []
	for id in npcs:
		if str(npcs[id].get("loc", "")) == "":
			continue
		var fig: Node3D = npcs[id]["fig"]
		var fp := Vector2(fig.position.x, fig.position.z)
		if fp.distance_to(pp) < 12.0 and _inside_any(fp) == mine:
			out.append(id)
	NPCManager.nearby = out
	NPCManager.nearby_loc = World.current_id()


func _npc_entry(id: String, fig: Humanoid, n: Dictionary, loc: String) -> Dictionary:
	var age := int(n["idade"])
	var pace := rng.randf_range(1.32, 1.58) if age < 30 else (rng.randf_range(1.18, 1.45) if age < 60 else rng.randf_range(0.88, 1.1))
	fig.formal = age >= 58
	if age < 13:
		pace = rng.randf_range(1.5, 1.9)
	if n.has("bebe"):
		fig.set_stroller(true, (fig.look["skin"] as Color).lightened(0.08))
		pace = minf(pace, 1.15)
	var physical = physical_world.actor(fig, PhysicsLayers.NPC, Callable(), clampf(fig.scale.y * 1.6, 0.9, 1.9), clampf(fig.scale.y * 0.28, 0.19, 0.32))
	physical.damage = func(amount: float, cause: String): _npc_physical_damage(id, amount, cause)
	physical.restore(NPCManager.state.get(id, {}).get("physical", {}))
	return {"physical": physical, "id": id, "fig": fig, "loc": loc, "path": PackedVector2Array(), "wait": rng.randf_range(2.0, 8.0), "pace": pace, "v": 0.0, "act": "",
		"umbrella": (absi(id.hash()) % 100) < (40 if age < 13 else 78), "waved": -999.0}


func _sync_npcs() -> void:
	if not GameState.active:
		return
	_update_nearby()
	var snap := _snap_npcs
	_snap_npcs = false
	# Reutiliza os modelos fora da rotina. A população persistente continua no NPCManager.
	# Criação inicial: no máximo um modelo por chamada, medindo o trabalho do quadro.
	var made := 0
	var started := Time.get_ticks_usec()
	for id in NPCManager.npcs:
		var want := _lot_id(NPCManager.location_of(id))
		if want == "" or not layout.lots.has(want):
			if npcs.has(id):
				var entry: Dictionary = npcs[id]
				if str(entry["loc"]) != "":
					var fig: Node3D = entry["fig"]
					Layout.stream_state()["npc_positions"][id] = {"pos": [fig.position.x, fig.position.z], "loc": entry["loc"]}
				_end_act(npcs[id], npcs[id]["fig"])
				(npcs[id]["fig"] as Humanoid).set_active(false)
				npcs[id]["loc"] = ""
				npcs[id]["path"] = PackedVector2Array()
			continue
		if not npcs.has(id):
			if made >= 1 or Time.get_ticks_usec() - started >= 6000:
				continue
			made += 1
			var n: Dictionary = NPCManager.npcs[id]
			var fig := Humanoid.new()
			fig.set_look(LookBuilder.build(LookBuilder.individual_spec(World.npc_looks.get(id, {}), id), int(n["idade"]), str(n["genero"])))
			viewport.add_child(fig)
			var sp := layout.spot_in(want, rng)
			var saved: Dictionary = Layout.stream_state()["npc_positions"].get(id, {})
			if str(saved.get("loc", "")) == want and saved.get("pos", []).size() == 2:
				sp = Vector2(float(saved["pos"][0]), float(saved["pos"][1]))
			fig.position = Vector3(sp.x, 0.17, sp.y)
			fig.rotation.y = rng.randf() * TAU
			npcs[id] = _npc_entry(str(id), fig, n, want)
			continue
		var e: Dictionary = npcs[id]
		if str(e["loc"]) != want:
			e["loc"] = want
			var fig2: Node3D = e["fig"]
			_end_act(e, fig2)
			var dest := layout.spot_in(want, rng)
			if not _restored_npcs.has(id):
				var saved: Dictionary = Layout.stream_state()["npc_positions"].get(id, {})
				if str(saved.get("loc", "")) == want and saved.get("pos", []).size() == 2:
					dest = Vector2(float(saved["pos"][0]), float(saved["pos"][1]))
				_restored_npcs[id] = true
			if snap and fig2.position.distance_squared_to(player.position) > 2304.0:
				fig2.position = Vector3(dest.x, 0.17, dest.y)
				e["path"] = PackedVector2Array()
			else:
				e["path"] = layout.route(Vector2(fig2.position.x, fig2.position.z), dest)


# atividades em que a pessoa fica parada no lugar (um novo caminho as interrompe)
const STAY_ACTS := ["sentar", "conversar", "celular", "olhar", "mexer", "pegar", "agachar", "consertar", "deitado", "dancar"]
# atividades em que ela não vira o rosto para o jogador que passa
const ABSORBED := ["celular", "conversar", "mexer", "pegar", "consertar", "deitado"]


func _update_npcs(delta: float) -> void:
	var pp := _p2()
	var hr := TimeManager.hour()
	# à noite anda-se um pouco mais devagar; na chuva, mais depressa
	var pace_k := (0.93 if (hr >= 20 or hr < 6) else 1.0) * (1.18 if WorldEvents.raining() else 1.0)
	var raining := WorldEvents.raining()
	var now_s := Time.get_ticks_msec() / 1000.0
	for id in npcs:
		var e: Dictionary = npcs[id]
		var fig: Humanoid = e["fig"]
		if e.has("physical") and e["physical"].blocked():
			fig.walking = false
			fig.move_speed = 0
			continue
		if str(e["loc"]) == "":
			fig.set_active(false)
			continue
		var fp := Vector2(fig.position.x, fig.position.z)
		var talking: bool = NPCManager.talking_to == id and NPCManager.channel == NPCManager.PRESENCIAL
		var dist := fp.distance_to(pp)
		# na chuva, quem está na rua abre o guarda-chuva (ou anda encolhido); dentro, fecha
		var wet := raining and not _sheltered(fp)
		fig.set_umbrella(wet and bool(e.get("umbrella", true)) and not fig.stroller_on and str(e.get("act", "")) != "deitado")
		fig.hunched = wet
		# amigos acenam quando o jogador chega perto
		if dist < 7.0 and not talking and now_s - float(e.get("waved", -999.0)) > 120.0 and str(e.get("act", "")) not in ["deitado", "sentar"]:
			if NPCManager.relation_label(id) in ["Amigo(a)", "Melhor amigo(a)", "Namorando"]:
				e["waved"] = now_s
				fig.wave()
		var near := dist < 26.0
		var emo := str(NPCManager.state[id].get("emocao", "neutro")) if near else "neutro"
		if emo != fig.emotion:
			fig.set_emotion(emo)
		fig.set_active(dist < 60.0)
		fig.set_lod(dist < 24.0)
		var act := str(e.get("act", ""))
		var sees_player := dist < 6.5 and _inside_any(fp) == _inside_any(pp)
		if sees_player and (talking or act not in ABSORBED):
			fig.look_target = Vector3(pp.x, 1.55, pp.y)
		else:
			fig.look_target = e.get("look", Vector3.INF)
		if talking:
			if act != "":
				_end_act(e, fig)
			# a pessoa vem até o jogador para conversar
			var gap := pp - fp
			var spacing := 1.5
			if fig.gesture_left > 0.0:
				spacing = {"cumprimento": 1.0, "abraco": 0.74, "beijo": 0.62}.get(fig.social_gesture, 1.5)
			if gap.length() > spacing:
				var st := gap.normalized() * minf(float(e.get("pace", NPC_SPEED)) * delta, gap.length() - spacing)
				fig.position.x += st.x
				fig.position.z += st.y
				fig.move_speed = NPC_SPEED * 1.4
				fig.walking = true
			else:
				if fig.gesture_left <= 0.0 and gap.length() < 1.25:
					var back := -gap.normalized() * minf(0.65 * delta, 1.25 - gap.length())
					fig.position.x += back.x
					fig.position.z += back.y
				fig.walking = false
				_face(player_fig, fp)
			_face(fig, pp)
			e["path"] = PackedVector2Array()
			continue
		var pth: PackedVector2Array = e["path"]
		if not pth.is_empty():
			if act in STAY_ACTS:
				_end_act(e, fig)
			if fig.busy_t > 0.0:
				# ainda levantando do banco
				continue
			var tgt: Vector2 = pth[0]
			var d := tgt - fp
			var far := dist > 70.0
			var want_v: float = float(e.get("pace", NPC_SPEED)) * pace_k
			if far:
				want_v = NPC_SPEED * 4.0
			elif pth.size() == 1:
				# chega diminuindo o passo
				want_v *= clampf(d.length() / 1.3, 0.4, 1.0)
			var ang := atan2(d.x, d.y)
			var v: float = float(e.get("v", 0.0))
			var diff := absf(angle_difference(fig.rotation.y, ang))
			if not far and diff > 1.7 and v < 0.35:
				want_v = 0.0
			elif not far:
				want_v *= lerpf(1.0, 0.3, smoothstep(0.35, 1.6, diff))
			v = want_v if far else move_toward(v, want_v, (1.6 if want_v > v else 3.0) * delta)
			e["v"] = v
			if far:
				fig.rotation.y = ang
			else:
				var turn := lerpf(7.0, 3.6, clampf(v / NPC_SPEED, 0.0, 1.0))
				fig.rotation.y += clampf(angle_difference(fig.rotation.y, ang), -turn * delta, turn * delta)
			var reach := 0.25 if pth.size() == 1 else 0.34
			if d.length() < reach:
				pth.remove_at(0)
				e["path"] = pth
				if pth.is_empty():
					_arrive(e, fig)
			else:
				var facing := Vector2(sin(fig.rotation.y), cos(fig.rotation.y))
				var pull := 1.0 if (far or d.length() < 0.6) else 1.0 - smoothstep(0.2, 1.2, diff)
				var heading := facing.lerp(d.normalized(), pull).normalized()
				var step := heading * minf(v * delta, d.length())
				fig.position.x += step.x
				fig.position.z += step.y
				fig.position.y = 0.17
			fig.move_speed = v
			fig.walking = v > 0.05
			continue
		e["v"] = 0.0
		fig.move_speed = 0.0
		fig.walking = false
		_idle_life(e, fig, delta)


# Vida de quem está parado: fica sentado, conversa, mexe no celular, olha em volta... e depois escolhe outra coisa.
func _idle_life(e: Dictionary, fig: Humanoid, delta: float) -> void:
	var act := str(e.get("act", ""))
	if act == "sentar" and e.get("seat") != null:
		var seat: Dictionary = e["seat"]
		var sp: Vector2 = seat["p"]
		fig.position = fig.position.lerp(Vector3(sp.x, 0.17, sp.y), minf(delta * 6.0, 1.0))
		fig.rotation.y = lerp_angle(fig.rotation.y, float(seat["yaw"]), minf(delta * 8.0, 1.0))
	elif act == "conversar":
		var pid := str(e.get("partner", ""))
		if npcs.has(pid) and str(npcs[pid].get("partner", "")) == str(e["id"]) and str(npcs[pid].get("act", "")) in ["conversar", "ir_conversar"]:
			var o: Dictionary = npcs[pid]
			var of: Node3D = o["fig"]
			var dd := Vector2(of.position.x, of.position.z) - Vector2(fig.position.x, fig.position.z)
			fig.rotation.y = lerp_angle(fig.rotation.y, atan2(dd.x, dd.y), minf(delta * 5.0, 1.0))
			if bool(e.get("speaker", false)):
				e["turn"] = float(e.get("turn", 0.0)) - delta
				if float(e["turn"]) <= 0.0:
					# passa a vez: um fala, o outro escuta e às vezes concorda com a cabeça
					e["speaker"] = false
					o["speaker"] = true
					var t := rng.randf_range(1.8, 4.5)
					o["turn"] = t
					(of as Humanoid).talk_left = t
		else:
			e["wait"] = minf(float(e["wait"]), 0.8)
	e["wait"] = float(e["wait"]) - delta
	if float(e["wait"]) > 0.0:
		return
	_end_act(e, fig)
	_choose_act(e, fig)


func _choose_act(e: Dictionary, fig: Humanoid) -> void:
	var id := str(e["id"])
	var loc := str(e["loc"])
	var fp := Vector2(fig.position.x, fig.position.z)
	var lot: Dictionary = layout.lots.get(loc, {})
	var indoors: bool = (lot.has("building") and (lot["building"] as Rect2).size != Vector2.ZERO) or _sheltered(fp)
	e["wait"] = rng.randf_range(5.0, 14.0)
	var r := rng.randf()
	if Layout.urban_prototype_enabled and id == "irene" and loc == "mercado" and TimeManager.hour() >= 8 and TimeManager.hour() < 18:
		# Usa a gerente e a escala existentes; anima o trabalho, sem salário/IA paralelos.
		var b: Rect2 = lot["building"]
		var stock := int(e.get("work_station", 0)) % 2 == 0
		e["work_station"] = int(e.get("work_station", 0)) + 1
		e["path"] = PackedVector2Array([Vector2(b.end.x - 4.7, b.position.y + 4.9) if stock else Vector2(b.end.x - 3.0, b.end.y - 4.7)])
		e["work_yaw"] = -PI / 2.0 if stock else 0.0
		e["act"] = "ir_trabalho"
		e["wait"] = rng.randf_range(9.0, 16.0)
		return
	# Refeições e café nas mesas do bairro, com utensílio e gesto na mão.
	if r < 0.24 and loc in ["bar", "lanchonete", "minha_lanchonete", "pensao"]:
		var meal_seat = _free_seat(loc, fp)
		if meal_seat != null:
			seat_used[_seat_key(meal_seat)] = id
			e["seat"] = meal_seat
			e["act"] = "ir_refeicao"
			e["path"] = PackedVector2Array([meal_seat["p"]])
			e["meal"] = "beber" if rng.randf() < 0.5 else "comer"
			e["wait"] = rng.randf_range(8.0, 15.0)
			return
	# paciente no hospital (ou hóspede na pensão) deita num leito livre
	if r < 0.35 and str(World.locations.get(loc, {}).get("tipo", "")) in ["servico", "hospedagem"]:
		var bed = _free_bed(loc, fp)
		if bed != null:
			seat_used[_bed_key(bed)] = id
			e["bed"] = bed
			e["act"] = "ir_deitar"
			e["path"] = PackedVector2Array([bed["p"]])
			e["wait"] = rng.randf_range(30.0, 80.0)
			return
	# festa na praça (ou comemoração de aniversário no bar): o pessoal dança
	var party := (loc == "praca" and WorldEvents.festa_on()) or (loc == "bar" and _birthday_here(loc))
	if party and rng.randf() < 0.45:
		e["act"] = "dancar"
		e["wait"] = rng.randf_range(10.0, 24.0)
		fig.activity = "dancar"
		return
	if r < 0.3 and not (WorldEvents.raining() and not indoors):
		var seat = _free_seat(loc, fp)
		if seat != null:
			seat_used[_seat_key(seat)] = id
			e["seat"] = seat
			e["act"] = "ir_sentar"
			e["path"] = PackedVector2Array([seat["p"]])
			e["wait"] = rng.randf_range(20.0, 50.0)
			return
	if r < 0.52:
		var pid := _idle_partner(id, loc, fp)
		if pid != "":
			var o: Dictionary = npcs[pid]
			var of: Node3D = o["fig"]
			var op := Vector2(of.position.x, of.position.z)
			var dir := (op - fp).normalized() if op.distance_to(fp) > 0.05 else Vector2.RIGHT
			var mid := (fp + op) / 2.0
			var t := rng.randf_range(14.0, 30.0)
			e["path"] = PackedVector2Array([mid - dir * 0.6])
			o["path"] = PackedVector2Array([mid + dir * 0.6])
			e["act"] = "ir_conversar"
			o["act"] = "ir_conversar"
			e["partner"] = pid
			o["partner"] = id
			e["wait"] = t
			o["wait"] = t
			e["speaker"] = true
			e["turn"] = rng.randf_range(2.0, 4.0)
			o["speaker"] = false
			return
	var r2 := rng.randf()
	if r2 < 0.2:
		# olhando o celular: cabeça baixa, alheio a quem passa
		e["act"] = "celular"
		e["wait"] = rng.randf_range(6.0, 16.0)
		e["look"] = fig.position + Vector3(sin(fig.rotation.y), 0, cos(fig.rotation.y)) * 0.45 + Vector3(0, 0.95, 0)
	elif r2 < 0.34:
		# olha em volta, para a rua ou para uma vitrine
		e["act"] = "olhar"
		e["wait"] = rng.randf_range(3.0, 7.0)
		var a := rng.randf() * TAU
		e["look"] = fig.position + Vector3(cos(a) * 5.0, 1.5, sin(a) * 5.0)
	elif r2 < 0.46 and indoors:
		# mexe numa prateleira, balcão ou gaveta
		e["act"] = "mexer" if rng.randf() < 0.6 else "pegar"
		e["wait"] = rng.randf_range(2.2, 3.5)
	elif r2 < 0.5 and not indoors:
		# agacha para amarrar o sapato ou pegar algo do chão
		e["act"] = "agachar"
		e["wait"] = rng.randf_range(2.5, 4.5)
	elif r2 < 0.55 and str(World.locations.get(loc, {}).get("tipo", "")) == "casa":
		# conserta alguma coisa em casa
		e["act"] = "consertar"
		e["wait"] = rng.randf_range(8.0, 16.0)
	elif rng.randf() < 0.75:
		e["path"] = PackedVector2Array([layout.spot_in(loc, rng)])
	fig.activity = str(e.get("act", ""))


func _birthday_here(loc: String) -> bool:
	for id in npcs:
		if str(npcs[id]["loc"]) == loc and SocialSystem.is_birthday(str(id)):
			return true
	return false


func _arrive(e: Dictionary, fig: Humanoid) -> void:
	if str(e.get("act", "")) in ["ir_sentar", "ir_refeicao"] and e.get("seat") != null:
		fig.rotation.y = float(e["seat"]["yaw"])
	match str(e.get("act", "")):
		"ir_trabalho":
			e["act"] = "mexer"
			fig.rotation.y = float(e["work_yaw"])
			fig.activity = "mexer"
		"ir_refeicao":
			e["act"] = "sentar"
			fig.activity = "sentar"
			fig.daily_action = str(e["meal"])
			fig.action_time = 0.0
			e["held"] = _held_for(fig, "cafe" if fig.daily_action == "beber" else "pao", fig.daily_action)
		"ir_deitar":
			var bed: Dictionary = e["bed"]
			var an: Vector3 = bed["anchor"]
			e["act"] = "deitado"
			fig.position = Vector3(an.x, 0.17 + float(bed["h"]) + 0.15, an.z)
			fig.rotation = Vector3(-PI / 2.0, float(bed["yaw"]), 0.0)
		"ir_sentar":
			e["act"] = "sentar"
			fig.activity = "sentar"
		"ir_conversar":
			e["act"] = "conversar"
			fig.activity = "conversar"
			if bool(e.get("speaker", false)):
				fig.talk_left = float(e.get("turn", 3.0))
				# quem puxa conversa cumprimenta com a mão
				fig.wave(1.2)


func _end_act(e: Dictionary, fig: Node3D) -> void:
	if is_instance_valid(e.get("held")):
		e["held"].queue_free()
	e["held"] = null
	if e.get("seat") != null:
		seat_used.erase(_seat_key(e["seat"]))
		e["seat"] = null
	if e.get("bed") != null:
		seat_used.erase(_bed_key(e["bed"]))
		# levanta do leito e fica ao lado dele
		var bp: Vector2 = e["bed"]["p"]
		fig.rotation = Vector3(0.0, fig.rotation.y, 0.0)
		fig.position = Vector3(bp.x, 0.17, bp.y)
		e["bed"] = null
	var pid := str(e.get("partner", ""))
	if pid != "" and npcs.has(pid) and str(npcs[pid].get("partner", "")) == str(e.get("id", "")):
		# quem estava conversando comigo também se despede logo
		npcs[pid]["wait"] = minf(float(npcs[pid]["wait"]), rng.randf_range(0.6, 2.0))
	e["partner"] = ""
	e["speaker"] = false
	e["act"] = ""
	e["look"] = Vector3.INF
	if fig is Humanoid:
		(fig as Humanoid).activity = ""
		(fig as Humanoid).daily_action = ""
		(fig as Humanoid).action_time = 0.0


func _bed_key(b: Dictionary) -> String:
	var a: Vector3 = b["anchor"]
	return "leito_%d_%d" % [int(a.x * 10.0), int(a.z * 10.0)]


func _free_bed(loc: String, fp: Vector2):
	var best = null
	var best_d := 30.0
	for bd in city.beds:
		if int(bd.get("floor", 0)) != 0:
			continue
		var bp: Vector2 = bd["p"]
		if layout.lot_at(bp) != loc:
			continue
		var d := bp.distance_to(fp)
		if d < best_d and not seat_used.has(_bed_key(bd)):
			best = bd
			best_d = d
	return best


func _seat_key(s: Dictionary) -> String:
	var p: Vector2 = s["p"]
	return "%d_%d" % [int(p.x * 10.0), int(p.y * 10.0)]


func _free_seat(loc: String, fp: Vector2, floor_number := 0):
	if _seat_revision != city.interior_revision:
		seats_by_lot.clear()
		for seat in city.seats:
			var id := str(seat.get("loc", layout.lot_at(seat["p"])))
			if not seats_by_lot.has(id):
				seats_by_lot[id] = []
			seats_by_lot[id].append(seat)
		_seat_revision = city.interior_revision
	var best = null
	var best_d := 25.0
	for s in seats_by_lot.get(loc, []):
		if int(s.get("floor", 0)) != floor_number:
			continue
		var d := (s["p"] as Vector2).distance_to(fp)
		if d < best_d and not seat_used.has(_seat_key(s)):
			best = s
			best_d = d
	return best


func _idle_partner(id: String, loc: String, fp: Vector2) -> String:
	var cands: Array = []
	for oid in npcs:
		if oid == id or NPCManager.talking_to == oid:
			continue
		var o: Dictionary = npcs[oid]
		if str(o["loc"]) != loc or str(o.get("act", "")) != "" or not (o["path"] as PackedVector2Array).is_empty():
			continue
		var of: Node3D = o["fig"]
		if Vector2(of.position.x, of.position.z).distance_to(fp) < 9.0:
			cands.append(oid)
	return "" if cands.is_empty() else str(cands[rng.randi() % cands.size()])


# ---------- luz, clima e portas ----------

func _update_environment() -> void:
	var hf := TimeManager.hour() + TimeManager.minute() / 60.0
	var day := clampf(smoothstep(5.0, 7.0, hf) - smoothstep(18.0, 20.0, hf), 0.0, 1.0)
	var dusk := clampf(1.0 - absf(hf - 18.3) / 1.6, 0.0, 1.0) + clampf(1.0 - absf(hf - 6.0) / 1.3, 0.0, 1.0)
	var power := not WorldEvents.power_out()
	var storm := WorldEvents.raining()
	var sc: Dictionary = World.scenario()
	var tint: Array = sc.get("tint", [0, 0, 0, 0])
	var tint_c := Color(float(tint[0]), float(tint[1]), float(tint[2]))
	var tint_a := float(tint[3])
	# luz do dia pelos quadros-chave da direção de arte (manhã azulada, tarde dourada, noite azul)
	var L := Art.light_at(hf)
	var elev := clampf(sin((hf - 6.0) / 12.0 * PI), 0.05, 1.0)
	sun.rotation = Vector3(-deg_to_rad(14.0 + 50.0 * elev), deg_to_rad(-35.0 + (hf - 12.0) * 9.0), 0)
	# pôr do sol dourado (não rosa): puxa o laranja-avermelhado da paleta para o âmbar
	sun.light_color = (L["sun"] as Color).lerp(Color("#ffb46a"), 0.45 * clampf(dusk, 0.0, 1.0)).lerp(Color("#9aa4b4"), 0.5 if storm else 0.0)
	sun.light_energy = float(L["sun_e"]) * (0.45 if storm else 1.0) * 1.55
	# sombra do sol dura até o lusco-fusco; com tempo fechado vira uma sombra difusa e fraca
	# à noite a "lua" ilumina mas não projeta sombra (com o sol baixíssimo viraria riscos longos)
	sun.shadow_enabled = float(L["sun_e"]) > 0.14 and day > 0.2
	sun.shadow_opacity = (0.35 if storm else lerpf(0.7, 1.0, clampf((float(L["sun_e"]) - 0.14) / 0.4, 0.0, 1.0)))
	sun.shadow_blur = 3.0 if storm else 1.5
	var amb: Color = L["amb"]
	if storm:
		amb = amb.lerp(Color("#5a6270"), 0.45 * day).darkened(0.06 * (1.0 - day))
	if not power and day < 0.45:
		amb = amb.darkened(0.22)
	amb = amb.lerp(tint_c, tint_a * 0.7)
	# hora dourada: sol quente, sombra azulada (o contraste quente/frio é que dá volume)
	amb = amb.lerp(Color("#5d6f9c"), 0.6 * clampf(dusk, 0.0, 1.0) * (0.0 if storm else 1.0))
	# piso de luz ambiente azul-frio: à noite (e no apagão) as fachadas nunca viram borrão preto
	var floor_c := Color(0.13, 0.17, 0.27) if power else Color(0.1, 0.13, 0.21)
	amb = Color(maxf(amb.r, floor_c.r), maxf(amb.g, floor_c.g), maxf(amb.b, floor_c.b))
	env.ambient_light_color = amb
	# o piso só vale conforme escurece: de dia a luz ambiente fica como na direção de arte
	env.ambient_light_energy = maxf(float(L["amb_e"]) * (1.0 + 0.15 * day if storm else 1.0) * lerpf(1.0, 0.82, day), 0.5 * (1.0 - day))
	env.background_color = Color("#0a0f1c").lerp(Color("#7fa3c9"), day).lerp(tint_c, tint_a)
	# com o prédio aberto (sem telhado) as gotas cairiam dentro do cômodo: dentro, só se ouve a chuva
	var inside_open := false
	for st_s in city.structures:
		if bool(st_s["cut_now"]):
			inside_open = true
			break
	rain.emitting = storm and not inside_open
	# o chão encharca em ~25 s de chuva e seca em ~80 s; pulos de tempo (dormir, carregar) já chegam prontos
	var wet_target := 1.0 if storm else 0.0
	if not realtime or _wet_min < 0 or absi(TimeManager.total_minutes - _wet_min) > 20:
		wet_level = wet_target
	else:
		wet_level = move_toward(wet_level, wet_target, 0.5 / (25.0 if storm else 80.0))
	_wet_min = TimeManager.total_minutes
	city.set_wetness(wet_level)
	life.update_slow(day < 0.45)
	Atmosphere.grade(env, sun, hf, day, dusk, storm, wet_level)
	var night := day < 0.45
	# postes perto do jogador: só os mais próximos acendem, sem trocar de lugar de repente
	var want: Array = []
	if night and power:
		var p := player.position
		var near: Array = []
		for sp in city.lamp_spots:
			var d2 := (sp as Vector3).distance_squared_to(p)
			if d2 < 3600.0:
				near.append([d2, sp])
		near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		for i in mini(near.size(), LAMPS_LIT):
			want.append(near[i][1])
	_assign_lamps(want)
	city.festa_mat.albedo_color = Color.WHITE if night else Color(0.85, 0.85, 0.85)
	RenderingServer.global_shader_parameter_set("night_glow", clampf((0.6 - day) / 0.35, 0.0, 1.0) if power else 0.0)
	# janelas acesas: cor quente de cada janela à noite; de dia viram vidro escuro levemente quente
	var lit_k := clampf((0.75 - day) / 0.4, 0.0, 1.0)
	if power:
		city.lit_mat.albedo_color = Color(0.3, 0.34, 0.42).lerp(Color(1.45, 1.35, 1.18), lit_k)
	else:
		city.lit_mat.albedo_color = Color(0.16, 0.18, 0.22)
	# vidro comum guarda um reflexo azulado fraco à noite (nunca um buraco preto)
	city.glass_mat.emission_energy_multiplier = 0.55 * (1.0 - day)
	city.neon_mat.albedo_color = Color(2.6, 2.6, 2.6) if power and night else Color(0.55, 0.5, 0.5)
	# portas, luzes internas, fogo, festa
	var pp2 := _p2()
	for id in city.loc_info:
		if not layout.lots.has(id) or not World.locations.has(id):
			continue
		var inside := layout.in_building(id, pp2)
		var locked := World.door_locked(id) and not inside
		_door_locked[id] = locked
		city.set_door(id, locked)
		city.set_interior_daylight(id, day * (0.6 if storm else 1.0))
		var is_house := Houses.is_house(id)
		var near := (layout.lots[id]["door"] as Vector2).distance_to(pp2) < 70.0
		if is_house:
			var home := near and Houses.resident_home(id)
			city.set_house_lit(id, power and night and home)
			city.set_interior_light(id, power and night and (inside or home))
		else:
			var open := not World.door_locked(id)
			city.set_interior_light(id, power and (open or inside) and (night or str(World.locations[id].get("tipo", "")) in ["loja", "servico", "comida", "bar"]))
	var fire: Dictionary = CrimeSystem.fire()
	var burning_id := str(fire.get("loc", "")) if TimeManager.total_minutes < int(fire.get("ate", 0)) else ""
	for id in city.fire_nodes.keys():
		if id != burning_id:
			city.set_fire(id, false)
	if burning_id != "" and layout.lots.has(burning_id):
		city.set_fire(burning_id, true)
	if city.festa_node:
		city.festa_node.visible = WorldEvents.festa_on()


# Mantém cada luz no poste que já ilumina; as que sobram apagam devagar e depois mudam de poste.
func _assign_lamps(want: Array) -> void:
	var taken := {}
	var free: Array = []
	for i in lamp_pool.size():
		var sp = lamp_spot[i]
		if sp != null and want.has(sp) and not taken.has(sp):
			taken[sp] = true
			lamp_goal[i] = 1.0
		else:
			lamp_goal[i] = 0.0
			if (lamp_pool[i] as OmniLight3D).light_energy <= 0.01:
				free.append(i)
	for sp2 in want:
		if taken.has(sp2) or free.is_empty():
			continue
		var j: int = free.pop_back()
		lamp_spot[j] = sp2
		(lamp_pool[j] as OmniLight3D).position = sp2
		lamp_goal[j] = 1.0
		taken[sp2] = true


func _fade_lamps(delta: float) -> void:
	for i in lamp_pool.size():
		var l: OmniLight3D = lamp_pool[i]
		var goal: float = float(lamp_goal[i]) * LAMP_E
		if not realtime:
			l.light_energy = goal
		else:
			l.light_energy = move_toward(l.light_energy, goal, delta * LAMP_E * 1.6)
		l.visible = l.light_energy > 0.01


# Nome da rua onde o jogador está (quando não está dentro de um lote).
func current_street() -> String:
	if not _built:
		return ""
	var p := _p2()
	if layout.lot_at(p) != "":
		return ""
	var gx := (p.x - Layout.STREET / 2.0) / Layout.PITCH
	var gy := (p.y - Layout.STREET / 2.0) / Layout.PITCH
	var nx := roundi(gx)
	var ny := roundi(gy)
	var dx := absf(p.x - (nx * Layout.PITCH + Layout.STREET / 2.0))
	var dy := absf(p.y - (ny * Layout.PITCH + Layout.STREET / 2.0))
	if dx < 7.5 and dy < 7.5:
		return "%s com %s" % [Layout.street_name(nx, true), Layout.street_name(ny)]
	return Layout.street_name(nx, true) if dx < dy else Layout.street_name(ny)


# ---------- entrada ----------

func _hidden_by_roof(fig: Node3D) -> bool:
	var fp := Vector2(fig.position.x, fig.position.z)
	var lot := _inside_any(fp)
	if lot == "" or not city.loc_info.has(lot):
		return false
	return not bool(city.loc_info[lot]["structure"]["cut_now"])


func _pick_npc(pos: Vector2) -> String:
	var ppm := size.y / maxf(camera.size, 1.0)
	var best := ""
	var best_d := 1e9
	for id in npcs:
		var fig: Node3D = npcs[id]["fig"]
		if not fig.visible or _hidden_by_roof(fig):
			continue
		if is_third_person() and (camera.is_position_behind(fig.global_position) or fig.global_position.distance_to(player.global_position) > 3.0 or not _clear_sight(fig.global_position + Vector3.UP, AABB(fig.global_position - Vector3(0.5, 0, 0.5), Vector3(1, 2, 1)))):
			continue
		var feet := camera.unproject_position(fig.global_position)
		var top := camera.unproject_position(fig.global_position + Vector3(0, 1.9, 0))
		var r := Rect2(feet.x - ppm * 0.6, top.y - ppm * 0.15, ppm * 1.2, feet.y - top.y + ppm * 0.3)
		if is_third_person():
			var height := maxf(20.0, absf(feet.y - top.y))
			r = Rect2(minf(feet.x, top.x) - height * 0.24, minf(top.y, feet.y) - height * 0.08, absf(feet.x - top.x) + height * 0.48, height * 1.16)
		if r.has_point(pos):
			var d := absf(pos.x - feet.x)
			if d < best_d:
				best_d = d
				best = id
	if best == "" and not is_third_person():
		for i in life.peds.size():
			var pf: Node3D = life.peds[i]["fig"]
			if not pf.visible:
				continue
			var feet2 := camera.unproject_position(pf.global_position)
			var top2 := camera.unproject_position(pf.global_position + Vector3(0, 1.9, 0))
			if Rect2(feet2.x - ppm * 0.6, top2.y - ppm * 0.15, ppm * 1.2, feet2.y - top2.y + ppm * 0.3).has_point(pos):
				return "ped:%d" % i
	return best


func _ground_at(pos: Vector2) -> Vector2:
	var o := camera.project_ray_origin(pos)
	var d := camera.project_ray_normal(pos)
	if absf(d.y) < 0.0001:
		return _p2()
	var floor_y := player.position.y if _inside_any(_p2()) != "" else 0.17
	var t := -(o.y - floor_y) / d.y
	var g := o + d * t
	return Vector2(g.x, g.z)


func _pick_object(pos: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(pos)
	var direction := camera.project_ray_normal(pos)
	var found: Dictionary = {}
	var nearest := INF
	for target in city.objects.values():
		if not object_access(target):
			continue
		var hit = (target["bounds"] as AABB).intersects_ray(origin, direction)
		if hit != null:
			var distance := origin.distance_squared_to(hit)
			if is_third_person() and (not _near_object(target) or not _clear_sight(hit, target["bounds"])):
				continue
			if distance < nearest:
				nearest = distance
				found = target.duplicate()
				found["hit"] = hit
	return found


func _object_nearest(target: Dictionary) -> Vector3:
	var bounds: AABB = target["bounds"]
	var here := player.global_position + Vector3.UP
	return Vector3(clampf(here.x, bounds.position.x, bounds.end.x), clampf(here.y, bounds.position.y, bounds.end.y), clampf(here.z, bounds.position.z, bounds.end.z))


func _near_object(target: Dictionary) -> bool:
	return _object_nearest(target).distance_to(player.global_position + Vector3.UP) <= 2.5


func _clear_sight(point: Vector3, bounds: AABB, from_camera := true) -> bool:
	var start := camera.global_position if from_camera else player.global_position + Vector3.UP
	var ray := PhysicsRayQueryParameters3D.create(start, point, 1, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or bounds.grow(0.15).has_point(hit["position"]) or (hit["position"] as Vector3).distance_to(point) < 0.12


func interact_nearby() -> void:
	if not _built or _paused() or _typing() or action_busy() or NPCManager.busy or NPCManager.talking_to != "":
		return
	var best_score := -INF
	var best_npc := ""
	var best_object := {}
	var forward := camera_rig.forward()
	for id in npcs:
		var fig: Node3D = npcs[id]["fig"]
		var delta := fig.global_position - player.global_position
		var distance := delta.length()
		if not fig.visible or distance > 1.9:
			continue
		var box := AABB(fig.global_position - Vector3(0.5, 0, 0.5), Vector3(1, 2, 1))
		if not _clear_sight(fig.global_position + Vector3.UP, box, false):
			continue
		var score := forward.dot(Vector3(delta.x, 0, delta.z).normalized()) * 2.0 - distance
		if score > best_score:
			best_score = score
			best_npc = str(id)
	for target in city.objects.values():
		if not object_access(target) or not _near_object(target):
			continue
		var point := _object_nearest(target)
		if not _clear_sight(point, target["bounds"], false):
			continue
		var delta := point - (player.global_position + Vector3.UP)
		var score := forward.dot(Vector3(delta.x, 0, delta.z).normalized()) * 2.0 - delta.length()
		if score > best_score:
			best_score = score
			best_object = target
			best_npc = ""
	if not best_object.is_empty():
		object_chosen.emit(best_object)
	elif best_npc != "":
		npc_menu.emit(best_npc)
	else:
		toast.emit("Aproxime-se de uma pessoa ou objeto para interagir.")


func _unhandled_key_input(e: InputEvent) -> void:
	if not _built or _typing() or _paused() or not GameState.active or not (e is InputEventKey) or e.echo:
		return
	if e.is_action_pressed("camera_toggle"):
		set_camera_mode(1 - Settings.camera_mode)
		toast.emit("Terceira pessoa • arraste o botão direito para olhar • E interage" if Settings.camera_mode == 1 else "Câmera isométrica • clique no chão para andar")
		get_viewport().set_input_as_handled()
	elif is_third_person() and e.is_action_pressed("interact"):
		_release_orbit()
		interact_nearby()
		get_viewport().set_input_as_handled()


func _release_orbit(restore_cursor := true) -> void:
	if _orbit_drag:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if restore_cursor and is_inside_tree():
			get_viewport().warp_mouse(_rmb_global)
	_orbit_drag = false
	_rmb_down = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_orbit(false)


func _input(e: InputEvent) -> void:
	if not _built or not _rmb_down:
		return
	if _paused() or _typing() or not GameState.active:
		_release_orbit()
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		_release_orbit()
	elif e is InputEventMouseMotion:
		_rmb_travel += e.relative.length()
		if _rmb_travel >= 5.0:
			_orbit_drag = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			camera_rig.rotate_view(e.screen_relative, Settings.camera_sensitivity, Settings.camera_invert_y)
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT and not e.pressed:
		var context_click := not _orbit_drag
		_release_orbit()
		if context_click:
			_context_at(_rmb_position)
		get_viewport().set_input_as_handled()


func _context_at(position: Vector2) -> void:
	var id := _pick_npc(position)
	if id != "" and not id.begins_with("ped:"):
		npc_menu.emit(id)
	else:
		var target := _pick_object(position)
		if not target.is_empty():
			object_chosen.emit(target)


func _gui_input(e: InputEvent) -> void:
	if not _built:
		return
	if not GameState.active:
		return
	if _paused():
		return
	if _typing():
		if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			get_viewport().gui_get_focus_owner().release_focus()
		else:
			return
	if e is InputEventMouseMotion:
		hover_id = _pick_npc(e.position)
		hover_object = _pick_object(e.position) if hover_id == "" else {}
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hover_id != "" or not hover_object.is_empty() else Control.CURSOR_ARROW
	elif e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if is_third_person():
					camera_rig.zoom_view(0.9)
				else:
					zoom = clampf(zoom * 0.9, 12.0, 80.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if is_third_person():
					camera_rig.zoom_view(1.1)
				else:
					zoom = clampf(zoom * 1.1, 12.0, 80.0)
			MOUSE_BUTTON_LEFT:
				var id := _pick_npc(e.position)
				if id.begins_with("ped:"):
					toast.emit("Um desconhecido passando. Só os moradores do bairro dão papo.")
					accept_event()
					return
				if id != "":
					var fig: Node3D = npcs[id]["fig"]
					var fp := Vector2(fig.position.x, fig.position.z)
					if fp.distance_to(_p2()) < 1.9:
						_face(player_fig, fp)
						_try_talk(id)
					else:
						if is_third_person():
							toast.emit("Aproxime-se para conversar.")
						else:
							pending_npc = id
							path = layout.route(_p2(), fp)
							marker.visible = false
				else:
					var target := _pick_object(e.position)
					if not target.is_empty():
						object_chosen.emit(target)
					else:
						if not is_third_person():
							pending_npc = ""
							_go_to(_ground_at(e.position))
			MOUSE_BUTTON_RIGHT:
				if is_third_person():
					_rmb_down = true
					_rmb_travel = 0.0
					_rmb_position = e.position
					_rmb_global = get_global_mouse_position()
				else:
					_context_at(e.position)
		accept_event()
