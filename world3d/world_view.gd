extends SubViewportContainer

# Mundo aberto isométrico (estilo Project Zomboid). Mostra a cidade inteira em 3D:
# o jogador anda com WASD ou clicando, entra nos prédios (as paredes se cortam),
# os NPCs andam pelas ruas seguindo a própria rotina, carros e pedestres passam,
# o dia vira noite, chove, falta luz. A lógica do jogo continua nos autoloads.

const Layout = preload("res://world3d/city_layout.gd")
const CityBuilder = preload("res://world3d/city_builder.gd")
const Humanoid = preload("res://world3d/humanoid.gd")
const Kit = preload("res://world3d/mesh_kit.gd")
const Life = preload("res://world3d/life.gd")
const LookBuilder = preload("res://ui/face/look_builder.gd")

signal npc_chosen(id: String)
signal npc_menu(id: String)
signal toast(text: String)

static var realtime: bool = true

const WALK_SPEED := 3.6
const RUN_SPEED := 6.6
const NPC_SPEED := 2.3
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
var npcs: Dictionary = {}           # id -> {"fig", "loc", "path", "wait"}
var life: Life
var path: PackedVector2Array = PackedVector2Array()
var pending_npc: String = ""
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


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	rng.randomize()
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.handle_input_locally = false
	add_child(viewport)
	_setup_scene()
	World.open_world = true
	World.location_changed.connect(_on_location_changed)
	World.walk_requested.connect(_on_walk_requested)
	NPCManager.npc_replied.connect(func(id: String, _d: Dictionary) -> void:
		if npcs.has(id):
			(npcs[id]["fig"] as Humanoid).talk_left = 3.5)
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
	city.build(layout)
	print("CIDADE montada em %d ms (%d casas)" % [Time.get_ticks_msec() - t0, layout.house_ids.size()])
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
	refresh_player_look()
	# marcadores
	marker = _ring(Color("#ffd166"), 0.45)
	hover_ring = _ring(Color("#ffffff"), 0.6)
	# postes acesos (um conjunto pequeno que acompanha o jogador)
	for i in 14:
		var l := OmniLight3D.new()
		l.light_color = Color("#ffcf86")
		l.light_energy = 1.7
		l.omni_range = 13.0
		l.omni_attenuation = 1.4
		l.visible = false
		viewport.add_child(l)
		lamp_pool.append(l)
	_setup_rain()
	life = Life.new()
	viewport.add_child(life)
	life.setup(layout, city)


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


func refresh_player_look() -> void:
	var p: Dictionary = GameState.player
	player_fig.set_look(LookBuilder.build(p.get("look", {}), int(p.get("age", 30)), str(p.get("gender", "homem"))))


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
	if TimeManager.total_minutes - _last_minutes > 20 or TimeManager.total_minutes < _last_minutes:
		_snap_npcs = true
	_last_minutes = TimeManager.total_minutes
	if GameState.active:
		_move_player(delta)
		_t_loc -= delta
		if _t_loc <= 0.0:
			_t_loc = 0.25
			_update_location()
		_time_flow(delta)
	_camera(delta)
	_t_cut -= delta
	if _t_cut <= 0.0:
		_t_cut = 0.1
		_cutaway()
	_t_sync -= delta
	if _t_sync <= 0.0 or _snap_npcs:
		_t_sync = 0.5
		_sync_npcs()
	_update_npcs(delta)
	life.update(delta, _p2(), TimeManager.hour() >= 22 or TimeManager.hour() < 5, WorldEvents.raining())
	_t_env -= delta
	if _t_env <= 0.0:
		_t_env = 0.5
		_update_environment()
	if hover_id != "" and npcs.has(hover_id) and not _paused():
		var hf: Node3D = npcs[hover_id]["fig"]
		hover_ring.visible = true
		hover_ring.position = hf.position + Vector3(0, 0.08, 0)
		var head_px := camera.unproject_position(hf.global_position + Vector3(0, 2.0, 0))
		hint.text = "Clique para conversar   •   botão direito: opções" if NPCManager.talking_to == "" else "Em conversa"
		hint.size = hint.get_combined_minimum_size()
		hint.position = head_px - Vector2(hint.size.x / 2.0, hint.size.y + 8.0)
		hint.visible = true
	else:
		hover_ring.visible = false
		hint.visible = false


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _paused() -> bool:
	return pause_check.is_valid() and bool(pause_check.call())


func _move_player(delta: float) -> void:
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
	var speed := RUN_SPEED if running else WALK_SPEED
	if NeedsSystem.get_value("energia") < 12.0:
		speed *= 0.6
		running = false
	var before := player.position
	# aceleração e frenagem: o corpo tem inércia, não liga e desliga
	var vel2 := Vector2(player.velocity.x, player.velocity.z)
	var want := Vector2(dir.x, dir.z) * speed
	vel2 = vel2.move_toward(want, (16.0 if want != Vector2.ZERO else 24.0) * delta)
	player.velocity.x = vel2.x
	player.velocity.z = vel2.y
	player.velocity.y = 0.0 if player.is_on_floor() else player.velocity.y - 20.0 * delta
	player.move_and_slide()
	var moved := Vector2(player.position.x - before.x, player.position.z - before.z).length()
	var real_speed: float = moved / maxf(delta, 0.0001)
	if dir != Vector3.ZERO and not path.is_empty() and moved < speed * delta * 0.15:
		_stuck += delta
		if _stuck > 0.6:
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
	player_fig.running = real_speed > 5.0
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


func _cutaway() -> void:
	var p := _p2()
	var toward := Vector2(1, 1).normalized()
	var probes: Array = []
	for tt in [0.6, 2.0, 3.5, 5.0, 7.0, 9.5, 12.0, 15.0, 19.0]:
		probes.append(p + toward * float(tt))
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
		if dist > 45.0:
			city.set_cut(s, false)
			continue
		var cut := r.has_point(p)
		if not cut:
			var g := r.grow(1.0)
			for q in probes:
				if g.has_point(q):
					cut = true
					break
		city.set_cut(s, cut)


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
	for id in NPCManager.npcs:
		var want := _lot_id(NPCManager.location_of(id))
		if want == "" or not layout.lots.has(want):
			if npcs.has(id):
				(npcs[id]["fig"] as Node3D).queue_free()
				npcs.erase(id)
			continue
		if not npcs.has(id):
			var n: Dictionary = NPCManager.npcs[id]
			var fig := Humanoid.new()
			fig.set_look(LookBuilder.build(World.npc_looks.get(id, {}), int(n["idade"]), str(n["genero"])))
			viewport.add_child(fig)
			var sp := layout.spot_in(want, rng)
			fig.position = Vector3(sp.x, 0.17, sp.y)
			fig.rotation.y = rng.randf() * TAU
			npcs[id] = {"fig": fig, "loc": want, "path": PackedVector2Array(), "wait": rng.randf_range(2.0, 8.0)}
			continue
		var e: Dictionary = npcs[id]
		if str(e["loc"]) != want:
			e["loc"] = want
			var fig2: Node3D = e["fig"]
			var dest := layout.spot_in(want, rng)
			if snap:
				fig2.position = Vector3(dest.x, 0.17, dest.y)
				e["path"] = PackedVector2Array()
			else:
				e["path"] = layout.route(Vector2(fig2.position.x, fig2.position.z), dest)


func _update_npcs(delta: float) -> void:
	var pp := _p2()
	for id in npcs:
		var e: Dictionary = npcs[id]
		var fig: Humanoid = e["fig"]
		var fp := Vector2(fig.position.x, fig.position.z)
		var talking: bool = NPCManager.talking_to == id and NPCManager.channel == NPCManager.PRESENCIAL
		var near := fp.distance_to(pp) < 26.0
		var emo := str(NPCManager.state[id].get("emocao", "neutro")) if near else "neutro"
		if emo != fig.emotion:
			fig.set_emotion(emo)
		fig.set_active(fp.distance_to(pp) < 60.0)
		fig.set_lod(fp.distance_to(pp) < 24.0)
		fig.look_target = Vector3(pp.x, 1.55, pp.y) if (fp.distance_to(pp) < 6.5 and _inside_any(fp) == _inside_any(pp)) else Vector3.INF
		if talking:
			# a pessoa vem até o jogador para conversar
			var gap := pp - fp
			if gap.length() > 1.5:
				var st := gap.normalized() * minf(NPC_SPEED * 1.4 * delta, gap.length() - 1.5)
				fig.position.x += st.x
				fig.position.z += st.y
				fig.move_speed = NPC_SPEED * 1.4
				fig.walking = true
			else:
				fig.walking = false
				_face(player_fig, fp)
			_face(fig, pp)
			e["path"] = PackedVector2Array()
			continue
		var pth: PackedVector2Array = e["path"]
		if not pth.is_empty():
			var tgt: Vector2 = pth[0]
			var d := tgt - fp
			var spd := NPC_SPEED * (4.0 if fp.distance_to(pp) > 70.0 else 1.0)
			if d.length() < 0.3:
				pth.remove_at(0)
				e["path"] = pth
			else:
				var step := d.normalized() * minf(spd * delta, d.length())
				fig.position.x += step.x
				fig.position.z += step.y
				fig.position.y = 0.17
				fig.rotation.y = lerp_angle(fig.rotation.y, atan2(step.x, step.y), minf(delta * 7.0, 1.0))
			fig.move_speed = lerpf(fig.move_speed, spd, minf(delta * 5.0, 1.0))
			fig.walking = true
			continue
		fig.move_speed = 0.0
		fig.walking = false
		e["wait"] = float(e["wait"]) - delta
		if float(e["wait"]) <= 0.0:
			e["wait"] = rng.randf_range(5.0, 14.0)
			if rng.randf() < 0.55:
				var dest := layout.spot_in(str(e["loc"]), rng)
				e["path"] = PackedVector2Array([dest])


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
	var elev := clampf(sin((hf - 6.0) / 12.0 * PI), 0.05, 1.0)
	sun.rotation = Vector3(-deg_to_rad(18.0 + 52.0 * elev), deg_to_rad(-35.0 + (hf - 12.0) * 9.0), 0)
	var sun_c := Color("#fff4e0").lerp(Color("#ff9a55"), clampf(dusk, 0.0, 1.0) * 0.8)
	sun.light_color = sun_c.lerp(Color("#8fa6d8"), 1.0 - day)
	sun.light_energy = lerpf(0.08, 0.78, day) * (0.6 if storm else 1.0)
	sun.shadow_enabled = day > 0.2
	var amb := Color("#2a3756").lerp(Color("#b9c6d8"), day)
	if storm:
		amb = amb.darkened(0.25)
	env.ambient_light_color = amb.lerp(tint_c, tint_a)
	env.ambient_light_energy = lerpf(0.3, 0.32, day)
	env.background_color = Color("#0a0f1c").lerp(Color("#7fa3c9"), day).lerp(tint_c, tint_a)
	rain.emitting = storm
	life.update_slow(day < 0.45)
	env.fog_enabled = hf < 7.5 or hf > 23.5 or storm
	env.fog_density = 0.0025 if hf < 7.5 else 0.0015
	env.fog_light_color = Color("#9fb0c4") if hf < 12.0 else Color("#3a4358")
	var night := day < 0.45
	# postes perto do jogador
	var p := player.position
	var spots: Array = city.lamp_spots.duplicate()
	spots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(p) < b.distance_squared_to(p))
	for i in lamp_pool.size():
		var l: OmniLight3D = lamp_pool[i]
		l.visible = night and power and i < spots.size()
		if l.visible:
			l.position = spots[i]
	city.festa_mat.albedo_color = Color.WHITE if night else Color(0.85, 0.85, 0.85)
	city.lit_mat.emission_energy_multiplier = (1.6 if night else 0.25) if power else 0.0
	city.lit_mat.albedo_color = Color("#ffd98a") if power and night else Color("#3b4552")
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
