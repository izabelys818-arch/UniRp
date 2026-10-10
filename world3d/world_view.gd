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
const Art = preload("res://world3d/art_style.gd")
const LookBuilder = preload("res://ui/face/look_builder.gd")
const HumanMotion = preload("res://world3d/human_motion.gd")
const Leaves = preload("res://world3d/falling_leaves.gd")

signal npc_chosen(id: String)
signal npc_menu(id: String)
signal toast(text: String)

static var realtime: bool = true
# Diagnóstico de desempenho: imprime qualquer etapa do quadro que passe de 6 ms.
static var trace: bool = false

const WALK_SPEED := 2.2
const RUN_SPEED := 5.0
const NPC_SPEED := 1.55
const MINUTES_PER_SECOND := 1.0
const CAM_DIR := Vector3(1.0, 1.15, 1.0)

var layout: Layout
var city: CityBuilder
var viewport: SubViewport
var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var player: CharacterBody3D
var player_fig: Humanoid
var marker: MeshInstance3D
var hover_ring: MeshInstance3D
var rain: CPUParticles3D
var lamp_pool: Array = []
# cada luz do conjunto guarda o poste que ilumina e acende/apaga devagar (sem saltos)
var lamp_spot: Array = []
var lamp_goal: Array = []
# lugares para sentar por lote e quem está em cada um
var seats_by_lot: Dictionary = {}
var seat_used: Dictionary = {}
const LAMPS_LIT := 11
const LAMP_E := 1.3
const LAMP_COLORS := {"porto_cinza": "#ffc583", "vale_sereno": "#ffd49c", "nova_aurora": "#f1ebdf", "colapso": "#ffb46e"}
# chuva: o chão molha aos poucos e seca devagar depois
var wet_level := 0.0
var _wet_min := -1
var npcs: Dictionary = {}           # id -> {"fig", "loc", "path", "wait"}
var life: Life
var falling_leaves: Leaves
var path: PackedVector2Array = PackedVector2Array()
var pending_npc: String = ""
# ação com o corpo em andamento (dormir, banho, comer, beber) — ver start_action
var _act: Dictionary = {}
var _fade: ColorRect
var _act_props: Array = []
var hover_id: String = ""
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
var _t_env: float = 0.0
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
	_last_minutes = TimeManager.total_minutes
	_update_environment()
	_built = true
	_loading.queue_free()
	world_ready.emit()


func _exit_tree() -> void:
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
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = zoom
	camera.near = 70.0
	camera.far = 250.0
	viewport.add_child(camera)
	camera.current = true
	var t0 := Time.get_ticks_msec()
	layout = Layout.new()
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
	player.add_child(player_fig)
	_loading_text.text = "Preparando os moradores…"
	await _prewarm_bodies()
	refresh_player_look()
	# marcadores
	marker = _ring(Color("#ffd166"), 0.45)
	hover_ring = _ring(Color("#ffffff"), 0.6)
	# postes acesos (um conjunto pequeno que acompanha o jogador)
	var lamp_c := Color(LAMP_COLORS.get(Art.id(), "#ffcf86"))
	for i in 14:
		var l := OmniLight3D.new()
		l.light_color = lamp_c
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
	viewport.add_child(life)
	_loading_text.text = "Preparando a vida nas ruas…"
	await life.setup(layout, city, true, true, func(message: String): _loading_text.text = message)
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
	rain.amount = 1400
	rain.lifetime = 0.9
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(34, 1, 34)
	rain.direction = Vector3(0.15, -1, 0.1)
	rain.spread = 2.0
	rain.gravity = Vector3(0, -30, 0)
	rain.initial_velocity_min = 18.0
	rain.initial_velocity_max = 22.0
	var qm := QuadMesh.new()
	qm.size = Vector2(0.03, 0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.75, 0.82, 0.95, 0.45)
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
	var seen := {}
	var prepared := 0
	for id in NPCManager.npcs:
		var n: Dictionary = NPCManager.npcs[id]
		var lk := LookBuilder.build(LookBuilder.individual_spec(World.npc_looks.get(id, {}), id), int(n["idade"]), str(n["genero"]))
		var key := str(lk) # inclui a anatomia individual, preparada junto do corpo
		if seen.has(key):
			continue
		seen[key] = true
		var f := Humanoid.new()
		viewport.add_child(f)
		f.set_look(lk)
		f.free()
		prepared += 1
		_loading_text.text = "Preparando os moradores… %d de %d" % [prepared, NPCManager.npcs.size()]
		await get_tree().process_frame


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
	var p := Vector2.ZERO
	var lot := _lot_id(loc_id)
	if World.locations.has(loc_id) and World.locations[loc_id].get("interior", false):
		p = _room_rect(loc_id).get_center()
	elif layout.lots.has(lot):
		var b: Rect2 = layout.lots[lot]["building"]
		if b.size != Vector2.ZERO and World.is_accessible(lot) and World.is_open(lot):
			p = layout.door_in(lot) + Vector2(rng.randf_range(-1.5, 1.5), -rng.randf_range(0.5, 2.5))
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
	var here := layout.lot_at(_p2())
	if World.locations.has(loc_id) and World.locations[loc_id].get("interior", false):
		if not _room_rect(loc_id).has_point(_p2()):
			_place_player(loc_id)
		return
	if here != _lot_id(loc_id):
		_place_player(loc_id)


func _on_walk_requested(loc_id: String) -> void:
	var lot := _lot_id(loc_id)
	if not layout.lots.has(lot):
		return
	var dest: Vector2 = layout.door_in(lot) if (World.is_open(lot) and World.is_accessible(lot)) else layout.door_out(lot)
	_go_to(dest)
	toast.emit("Andando até %s" % World.locations[lot]["nome"])


func _go_to(dest: Vector2) -> void:
	var lot := layout.lot_at(dest)
	if lot != "" and layout.in_building(lot, dest) and bool(_door_locked.get(lot, false)) and not layout.in_building(lot, _p2()):
		dest = layout.door_out(lot)
		toast.emit("%s está trancado." % World.locations[lot]["nome"])
	path = layout.route(_p2(), dest)
	marker.position = Vector3(dest.x, 0.25, dest.y)
	marker.visible = true


# ---------- laço principal ----------

func _process(delta: float) -> void:
	if not _built:
		return
	falling_leaves.update(delta, player.position, _inside_any(_p2()) != "", WorldEvents.raining())
	if TimeManager.total_minutes - _last_minutes > 20 or TimeManager.total_minutes < _last_minutes:
		_snap_npcs = true
	_last_minutes = TimeManager.total_minutes
	if GameState.active:
		_move_player(delta)
		if not _act.is_empty():
			_update_action(delta)
		_t_loc -= delta
		if _t_loc <= 0.0:
			_t_loc = 0.25
			_update_location()
		_time_flow(delta)
	_camera(delta)
	_animate_lowering(delta)
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
	_update_npcs(delta)
	# móveis dos interiores: no máximo ~2,5 ms por quadro
	city.house_gen.place_pending(2500)
	tq = _tr("update_npcs", tq)
	life.update(delta, _p2(), TimeManager.hour() >= 22 or TimeManager.hour() < 5, WorldEvents.raining())
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


func _move_player(delta: float) -> void:
	# engasgos de quadro (montagem de interiores) não podem virar teletransporte nem falso travamento
	delta = minf(delta, 0.05)
	var dir := Vector3.ZERO
	if not _typing() and not _paused():
		var fwd := Vector3(-1, 0, -1).normalized()
		var right := Vector3(1, 0, -1).normalized()
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			dir += fwd
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			dir -= fwd
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			dir += right
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			dir -= right
	if dir != Vector3.ZERO:
		path = PackedVector2Array()
		pending_npc = ""
		marker.visible = false
		dir = dir.normalized()
	elif not path.is_empty():
		var tgt: Vector2 = path[0]
		var d := tgt - _p2()
		if d.length() < 0.4:
			path.remove_at(0)
			_stuck = 0.0
			if path.is_empty():
				marker.visible = false
		else:
			dir = Vector3(d.x, 0, d.y).normalized()
	var running := Input.is_physical_key_pressed(KEY_SHIFT) and dir != Vector3.ZERO
	var age_profile := HumanMotion.profile(int(GameState.player.get("age", 30)))
	var speed := (RUN_SPEED * float(age_profile["run"])) if running else (WALK_SPEED * float(age_profile["walk"]))
	if NeedsSystem.get_value("energia") < 12.0:
		speed *= 0.6
		running = false
	var before := player.position
	# aceleração e frenagem: o corpo tem inércia, não liga e desliga
	var vel2 := Vector2(player.velocity.x, player.velocity.z)
	var want := Vector2(dir.x, dir.z) * speed
	vel2 = vel2.move_toward(want, (float(age_profile["accel"]) if want != Vector2.ZERO else 19.0) * delta)
	player.velocity.x = vel2.x
	player.velocity.z = vel2.y
	player.velocity.y = 0.0 if player.is_on_floor() else player.velocity.y - 20.0 * delta
	player.move_and_slide()
	var moved := Vector2(player.position.x - before.x, player.position.z - before.z).length()
	var real_speed: float = moved / maxf(delta, 0.0001)
	if dir != Vector3.ZERO and not path.is_empty() and moved < speed * delta * 0.15:
		_stuck += delta
		if _stuck > 1.0:
			path.remove_at(0)
			_stuck = 0.0
	player_fig.move_speed = real_speed
	var tf: Node3D = null
	if hover_id != "" and npcs.has(hover_id):
		tf = npcs[hover_id]["fig"]
	elif NPCManager.talking_to != "" and npcs.has(NPCManager.talking_to):
		tf = npcs[NPCManager.talking_to]["fig"]
	player_fig.look_target = Vector3(tf.position.x, 1.55, tf.position.z) if tf != null else Vector3.INF
	player_fig.walking = real_speed > 0.15
	var p_wet := WorldEvents.raining() and _inside_any(_p2()) == "" and _act.is_empty()
	player_fig.set_umbrella(p_wet)
	player_fig.hunched = p_wet
	player_fig.running = running and real_speed > WALK_SPEED * float(age_profile["walk"])
	if vel2.length() > 0.3:
		player_fig.rotation.y = lerp_angle(player_fig.rotation.y, atan2(vel2.x, vel2.y), minf(delta * 9.0, 1.0))
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


func _camera(delta: float) -> void:
	cam_target = cam_target.lerp(player.position + Vector3(0, 1.0, 0), minf(delta * 6.0, 1.0))
	camera.size = lerpf(camera.size, zoom, minf(delta * 8.0, 1.0))
	camera.position = cam_target + CAM_DIR.normalized() * 150.0
	camera.look_at(cam_target, Vector3.UP)
	rain.position = cam_target + Vector3(0, 22, 0)


# Abrir prédios (cutaway). Antes, qualquer prédio entre o jogador e a câmera (até 19 m) virava
# inteiro uma laje de paredes baixas — torres e lojas sem interior "sumiam" e piscavam ao passar.
# Agora: só abre o prédio em que o jogador está dentro (com folga na porta para não piscar), e só
# a frente/telhado baixam. Atrás de prédios, o jogador aparece em silhueta (person.gd, raio-x).
# Estilo Project Zomboid / Sims: o prédio ou a casa que está entre a câmera e o jogador "abaixa"
# (como se as paredes caíssem) até uma altura que deixa o boneco à vista, e sobe de novo quando
# o jogador sai da linha. Nada some: a fachada e a porta continuam no lugar.
const LOWER_MIN := 2.4
var _lowering: Array = []


func _hide_blockers(p: Vector2) -> void:
	var d := CAM_DIR.normalized()
	var hd := Vector2(d.x, d.z) / d.y          # deslocamento horizontal por metro de altura, rumo à câmera
	for s in city.structures:
		var r: Rect2 = s["rect"]
		if not s.has("root"):
			continue
		if not s.has("h"):
			s["h"] = _structure_height(s)
		var h: float = s["h"]
		var want := 1.0
		if h > LOWER_MIN + 0.5 and not r.has_point(p) and r.grow(30.0).has_point(p):
			var lowered: bool = float(s.get("sy_t", 1.0)) < 0.99
			var t_in := _segment_hits_rect(p, p + hd * (h - 1.7), r.grow(0.6 if not lowered else 1.6))
			if t_in >= 0.0:
				# altura do raio no ponto onde ele entra no prédio: abaixo dela o boneco já aparece
				var entry := 1.7 + t_in * (h - 1.7)
				want = clampf(maxf(LOWER_MIN, entry - 0.5) / h, 0.05, 1.0)
		if absf(float(s.get("sy_t", 1.0)) - want) > 0.001:
			s["sy_t"] = want
			if not s in _lowering:
				_lowering.append(s)


# Move a altura de cada prédio até o alvo, um pouco por quadro.
func _animate_lowering(delta: float) -> void:
	if _lowering.is_empty():
		return
	var done: Array = []
	for s in _lowering:
		var root: Node3D = s["root"]
		var target: float = s["sy_t"]
		# desce rápido, sobe um pouco mais devagar
		var rate := 7.0 if target < root.scale.y else 4.0
		var y := lerpf(root.scale.y, target, minf(delta * rate, 1.0))
		if absf(y - target) < 0.004:
			y = target
			done.append(s)
		root.scale = Vector3(1.0, y, 1.0)
	for s in done:
		_lowering.erase(s)


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
	for s in city.structures:
		var r: Rect2 = s["rect"]
		var dist := r.get_center().distance_to(p)
		if s.has("lot"):
			if dist < 36.0 and s.get("interior") == null and built < 1:
				city.ensure_interior(s)
				built += 1
			elif dist > 70.0 and s.get("interior") != null:
				city.drop_interior(s)
		if not (s.has("lot") or s.get("enterable", false)) or dist > 45.0:
			city.set_cut(s, false)
			continue
		var inside: bool = r.grow(0.7).has_point(p) if bool(s["cut_now"]) else r.has_point(p)
		if inside and s.has("lot") and s.get("interior") == null:
			# o interior aparece junto com a abertura: nunca um quadro vazio
			city.ensure_interior(s)
		if inside and s.get("interior") != null and not bool(s["cut_now"]):
			city.house_gen.place_now(s["interior"])
		city.set_cut(s, inside)


# ---------- ações com o corpo (dormir, banho, comer, beber) ----------
# Padrão: aproximar → alinhar → animar → aplicar o efeito real → retorno → encerrar.
# O efeito é sempre a função que já existia (HomeSystem/Economy), chamada só no fim; se o
# jogador se mexer antes, a ação é cancelada sem efeito e sem deixar pose presa.

const ACT_TIME := {"dormir": 3.4, "banho": 3.2, "comer": 3.4, "beber": 3.5, "cozinhar": 5.8, "tv": 4.0, "sofa": 4.0, "pc": 5.0}


func action_busy() -> bool:
	return not _act.is_empty()


func start_action(kind: String, loc_id: String, effect: Callable, item_id: String = "") -> bool:
	if not _act.is_empty() or not GameState.active or NPCManager.busy or not _built:
		return false
	var pts: Dictionary = city.use_points.get(loc_id, {})
	var plan := {}
	match kind:
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
			if plan.has("seat"):
				var seat_key := _seat_key(plan["seat"])
				if seat_used.has(seat_key):
					return false
				seat_used[seat_key] = "jogador"
		"comer", "beber":
			var lot := layout.lot_at(_p2())
			var seat = _free_seat(lot, _p2()) if lot != "" else null
			if seat != null and (seat["p"] as Vector2).distance_to(_p2()) < 14.0:
				seat_used[_seat_key(seat)] = "jogador"
				plan = {"path": [seat["p"]], "yaw": float(seat["yaw"]), "pose": "sentar", "seat": seat}
			else:
				plan = {"path": [], "yaw": player_fig.rotation.y, "pose": "em_pe"}
		_:
			return false
	if NPCManager.talking_to != "":
		NPCManager.end_conversation()
	_act = {"kind": kind, "plan": plan, "stage": "ir", "t": 0.0, "effect": effect, "item": item_id, "applied": false}
	path = PackedVector2Array(plan.get("path", []))
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
			if _p2().distance_to(target) > 0.7 or _moving_keys():
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
			if float(a["t"]) >= float(ACT_TIME[kind]):
				a["applied"] = true
				(a["effect"] as Callable).call()
				a["stage"] = "fim"
				a["t"] = 0.0
		"fim":
			if kind == "dormir":
				_fade.color.a = maxf(0.0, 0.92 - float(a["t"]) / 0.9)
			if float(a["t"]) > (1.0 if kind == "dormir" else 0.3):
				_end_pose()
				_act = {}


func _begin_pose() -> void:
	var plan: Dictionary = _act["plan"]
	Humanoid.set_xray_strength(0.0)
	player_fig.daily_action = str(_act["kind"])
	player_fig.action_time = 0.0
	match str(_act["kind"]):
		"dormir":
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
			cover.position = Vector3(anchor.x, 0.17 + float(plan["h"]) + 0.36, anchor.z)
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
		"tv", "sofa", "pc":
			player_fig.activity = "sentar"
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
	Humanoid.set_xray_strength(1.0)
	player_fig.rotation = Vector3(0.0, player_fig.rotation.y, 0.0)
	player_fig.position = Vector3.ZERO
	player_fig.activity = ""
	player_fig.daily_action = ""
	player_fig.action_time = 0.0
	for p in _act_props:
		if is_instance_valid(p):
			p.queue_free()
	_act_props.clear()
	if _fade != null:
		_fade.color.a = 0.0
	if not _act.is_empty():
		var plan: Dictionary = _act["plan"]
		if plan.has("seat"):
			seat_used.erase(_seat_key(plan["seat"]))
		if str(_act["kind"]) == "dormir":
			# levanta e fica ao pé da cama
			var pts: Array = plan.get("path", [])
			if not pts.is_empty():
				var back: Vector2 = pts.back()
				player.position = Vector3(back.x, player.position.y, back.y)


func _cancel_action(msg: String) -> void:
	_end_pose()
	_act = {}
	toast.emit(msg)


# ---------- NPCs ----------

func _inside_any(p: Vector2) -> String:
	var lot := layout.lot_at(p)
	return lot if lot != "" and layout.in_building(lot, p) else ""


func _update_nearby() -> void:
	var pp := _p2()
	var mine := _inside_any(pp)
	var out: Array = []
	for id in npcs:
		var fig: Node3D = npcs[id]["fig"]
		var fp := Vector2(fig.position.x, fig.position.z)
		if fp.distance_to(pp) < 12.0 and _inside_any(fp) == mine:
			out.append(id)
	NPCManager.nearby = out
	NPCManager.nearby_loc = World.current_id()


func _sync_npcs() -> void:
	if not GameState.active:
		return
	_update_nearby()
	var snap := _snap_npcs
	_snap_npcs = false
	# orçamento: cada personagem novo pesa (modelo + roupas); no máximo 2 por quadro para não engasgar
	var made := 0
	for id in NPCManager.npcs:
		var want := _lot_id(NPCManager.location_of(id))
		if want == "" or not layout.lots.has(want):
			if npcs.has(id):
				_end_act(npcs[id], npcs[id]["fig"])
				(npcs[id]["fig"] as Node3D).queue_free()
				npcs.erase(id)
			continue
		if not npcs.has(id):
			if made >= 2:
				continue
			made += 1
			var n: Dictionary = NPCManager.npcs[id]
			var fig := Humanoid.new()
			fig.set_look(LookBuilder.build(LookBuilder.individual_spec(World.npc_looks.get(id, {}), id), int(n["idade"]), str(n["genero"])))
			viewport.add_child(fig)
			var sp := layout.spot_in(want, rng)
			fig.position = Vector3(sp.x, 0.17, sp.y)
			fig.rotation.y = rng.randf() * TAU
			# ritmo próprio: jovem anda mais solto, idoso mais devagar e contido
			var age := int(n["idade"])
			var pace := rng.randf_range(1.32, 1.58) if age < 30 else (rng.randf_range(1.18, 1.45) if age < 60 else rng.randf_range(0.88, 1.1))
			fig.formal = age >= 58
			if age < 13:
				# criança anda solta, às vezes correndo
				pace = rng.randf_range(1.5, 1.9)
			if n.has("bebe"):
				var skin: Color = LookBuilder.build(LookBuilder.individual_spec(World.npc_looks.get(id, {}), id), age, str(n["genero"]))["skin"]
				fig.set_stroller(true, skin.lightened(0.08))
				pace = minf(pace, 1.15)
			npcs[id] = {"id": id, "fig": fig, "loc": want, "path": PackedVector2Array(), "wait": rng.randf_range(2.0, 8.0), "pace": pace, "v": 0.0, "act": "",
				"umbrella": (absi(str(id).hash()) % 100) < (40 if age < 13 else 78), "waved": -999.0}
			continue
		var e: Dictionary = npcs[id]
		if str(e["loc"]) != want:
			e["loc"] = want
			var fig2: Node3D = e["fig"]
			_end_act(e, fig2)
			var dest := layout.spot_in(want, rng)
			if snap:
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
		var fp := Vector2(fig.position.x, fig.position.z)
		var talking: bool = NPCManager.talking_to == id and NPCManager.channel == NPCManager.PRESENCIAL
		var dist := fp.distance_to(pp)
		# na chuva, quem está na rua abre o guarda-chuva (ou anda encolhido); dentro, fecha
		var wet := raining and _inside_any(fp) == ""
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
			if not far and absf(angle_difference(fig.rotation.y, ang)) > 1.7 and v < 0.35:
				# vira no lugar antes de sair andando
				want_v = 0.0
			v = want_v if far else move_toward(v, want_v, (1.9 if want_v > v else 3.2) * delta)
			e["v"] = v
			if d.length() < 0.25:
				pth.remove_at(0)
				e["path"] = pth
				if pth.is_empty():
					_arrive(e, fig)
			else:
				var step := d.normalized() * minf(v * delta, d.length())
				fig.position.x += step.x
				fig.position.z += step.y
				fig.position.y = 0.17
			fig.rotation.y = lerp_angle(fig.rotation.y, ang, minf(delta * (6.0 if v > 0.3 else 4.0), 1.0))
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
	var indoors: bool = lot.has("building") and (lot["building"] as Rect2).size != Vector2.ZERO
	e["wait"] = rng.randf_range(5.0, 14.0)
	var r := rng.randf()
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
	match str(e.get("act", "")):
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


func _free_seat(loc: String, fp: Vector2):
	var best = null
	var best_d := 25.0
	for s in seats_by_lot.get(loc, []):
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
	sun.light_color = (L["sun"] as Color).lerp(Color("#9aa4b4"), 0.5 if storm else 0.0)
	sun.light_energy = float(L["sun_e"]) * (0.45 if storm else 1.0)
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
	# piso de luz ambiente azul-frio: à noite (e no apagão) as fachadas nunca viram borrão preto
	var floor_c := Color(0.13, 0.17, 0.27) if power else Color(0.1, 0.13, 0.21)
	amb = Color(maxf(amb.r, floor_c.r), maxf(amb.g, floor_c.g), maxf(amb.b, floor_c.b))
	env.ambient_light_color = amb
	# o piso só vale conforme escurece: de dia a luz ambiente fica como na direção de arte
	env.ambient_light_energy = maxf(float(L["amb_e"]) * (1.0 + 0.15 * day if storm else 1.0), 0.5 * (1.0 - day))
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
	env.fog_enabled = (storm and day > 0.4) or (hf > 5.0 and hf < 6.8)
	env.fog_density = 0.0007 if storm else 0.0006
	env.fog_light_color = Color("#8e98a6") if storm else Color("#a8b0bc")
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
	# janelas acesas: cor quente de cada janela à noite; de dia viram vidro escuro levemente quente
	var lit_k := clampf((0.75 - day) / 0.4, 0.0, 1.0)
	if power:
		city.lit_mat.albedo_color = Color(0.3, 0.34, 0.42).lerp(Color(0.96, 0.94, 0.9), lit_k)
	else:
		city.lit_mat.albedo_color = Color(0.16, 0.18, 0.22)
	# vidro comum guarda um reflexo azulado fraco à noite (nunca um buraco preto)
	city.glass_mat.emission_energy_multiplier = 0.55 * (1.0 - day)
	city.neon_mat.albedo_color = Color.WHITE if power and night else Color(0.55, 0.5, 0.5)
	# portas, luzes internas, fogo, festa
	var pp2 := _p2()
	for id in city.loc_info:
		var inside := layout.in_building(id, pp2)
		var locked := World.door_locked(id) and not inside
		_door_locked[id] = locked
		city.set_door(id, locked)
		var is_house := Houses.is_house(id)
		var near := (layout.lots[id]["door"] as Vector2).distance_to(pp2) < 70.0
		if is_house:
			var home := near and Houses.resident_home(id)
			city.set_house_lit(id, power and night and home)
			city.set_interior_light(id, power and night and (inside or home))
		else:
			var open := not World.door_locked(id)
			city.set_interior_light(id, power and (open or inside) and (night or str(World.locations[id].get("tipo", "")) in ["loja", "servico", "comida", "bar"]))
	for id in layout.lots:
		city.set_fire(id, CrimeSystem.fire_at(id))
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
	var nx := clampi(int(round(gx)), 0, Layout.GRID)
	var ny := clampi(int(round(gy)), 0, Layout.GRID)
	var dx := absf(p.x - (nx * Layout.PITCH + Layout.STREET / 2.0))
	var dy := absf(p.y - (ny * Layout.PITCH + Layout.STREET / 2.0))
	if dx < 7.5 and dy < 7.5:
		return "%s com %s" % [Layout.STREETS_V[nx], Layout.STREETS_H[ny]]
	return Layout.STREETS_V[nx] if dx < dy else Layout.STREETS_H[ny]


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
		var feet := camera.unproject_position(fig.global_position)
		var top := camera.unproject_position(fig.global_position + Vector3(0, 1.9, 0))
		var r := Rect2(feet.x - ppm * 0.6, top.y - ppm * 0.15, ppm * 1.2, feet.y - top.y + ppm * 0.3)
		if r.has_point(pos):
			var d := absf(pos.x - feet.x)
			if d < best_d:
				best_d = d
				best = id
	if best == "":
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
	var t := -(o.y - 0.17) / d.y
	var g := o + d * t
	return Vector2(g.x, g.z)


func _gui_input(e: InputEvent) -> void:
	if not _built:
		return
	if not GameState.active:
		return
	if e is InputEventMouseMotion:
		hover_id = _pick_npc(e.position)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hover_id != "" else Control.CURSOR_ARROW
	elif e is InputEventMouseButton and e.pressed:
		match e.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom = clampf(zoom * 0.9, 12.0, 80.0)
			MOUSE_BUTTON_WHEEL_DOWN:
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
						pending_npc = id
						path = layout.route(_p2(), fp)
						marker.visible = false
				else:
					pending_npc = ""
					_go_to(_ground_at(e.position))
			MOUSE_BUTTON_RIGHT:
				var id2 := _pick_npc(e.position)
				if id2 != "" and not id2.begins_with("ped:"):
					npc_menu.emit(id2)
		accept_event()
