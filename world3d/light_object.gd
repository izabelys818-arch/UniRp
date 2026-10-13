extends RigidBody3D

const Layers = preload("res://world3d/physics_layers.gd")
signal shattered(object: RigidBody3D)
var material_kind := "plastic"
var persistent_id := ""
var broken := false
var held := false
var disturbed := false
var top := -INF
var impact_cooldown := 0.0
var last_speed := 0.0
var resting := 0.0
var shard := false
var expires := 0.0
var reserved := false
static var sounds: Dictionary = {}

func _ready() -> void:
	collision_layer = Layers.INTERACTIVE
	collision_mask = Layers.WORLD | Layers.ACTORS
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	var physics := PhysicsMaterial.new()
	physics.friction = 0.65
	physics.bounce = 0.24 if material_kind == "metal" else 0.08
	physics_material_override = physics
	add_to_group("light_objects")
	set_physics_process(false)

func bind_id(key: String) -> void:
	persistent_id = key
	var saved: Dictionary = GameState.player.get("physical_objects", {}).get(key, {})
	broken = bool(saved.get("broken", false))
	disturbed = bool(saved.get("disturbed", false))
	if saved.get("position", []).size() == 3 and disturbed:
		var p: Array = saved["position"]
		global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		var r: Array = saved.get("rotation", [0, 0, 0])
		global_rotation = Vector3(float(r[0]), float(r[1]), float(r[2]))
	if broken:
		visible = false
		collision_layer = 0
		collision_mask = 0

func wake(push := Vector3.ZERO) -> void:
	if broken or held or reserved:
		return
	disturbed = true
	top = maxf(top, global_position.y)
	freeze = false
	sleeping = false
	set_physics_process(true)
	if push.length_squared() > 0:
		apply_central_impulse(push * mass)

func _physics_process(delta: float) -> void:
	impact_cooldown = maxf(0, impact_cooldown - delta)
	top = maxf(top, global_position.y)
	if shard:
		expires -= delta
		if expires <= 0: queue_free()
		return
	if not held:
		if linear_velocity.length() < 0.08 and angular_velocity.length() < 0.08:
			resting += delta
			if resting > 0.8:
				freeze = true
				top = -INF
				set_physics_process(false)
		else: resting = 0

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if broken or held or shard:
		return
	var downward := maxf(last_speed, -state.linear_velocity.y)
	last_speed = maxf(0, -state.linear_velocity.y)
	for index in state.get_contact_count():
		var normal := state.transform.basis * state.get_contact_local_normal(index)
		if normal.y > 0.45 and downward > 0.9 and impact_cooldown <= 0:
			impact_cooldown = 0.35
			var drop := maxf(top - state.transform.origin.y, downward * downward / 19.6)
			if material_kind in ["glass", "ceramic"] and drop > 1.0:
				broken = true
				call_deferred("_break")
			else:
				call_deferred("_sound", downward)
				if material_kind in ["plastic", "wood"] and downward > 4:
					set_meta("scuffed", true)
			break

func _break() -> void:
	visible = false
	freeze = true
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	_sound(4.0)
	shattered.emit(self)

func _sound(force: float) -> void:
	if not sounds.has(material_kind):
		var stream := AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = 22050
		var bytes := PackedByteArray()
		bytes.resize(4410 * 2)
		var frequency := 1550.0 if material_kind in ["glass", "ceramic"] else (420.0 if material_kind == "metal" else 110.0)
		for i in 4410:
			var t := float(i) / 22050
			var sample := (sin(t * frequency * TAU) + sin(t * frequency * 1.73 * TAU) * 0.4) * exp(-t * 35) * 11000
			bytes.encode_s16(i * 2, int(sample))
		stream.data = bytes
		sounds[material_kind] = stream
	var speaker := AudioStreamPlayer3D.new()
	speaker.stream = sounds[material_kind]
	speaker.volume_db = clampf(-22 + force * 1.5, -22, -7)
	speaker.max_distance = 25
	add_child(speaker)
	speaker.finished.connect(speaker.queue_free)
	speaker.play()

func save_state() -> void:
	if persistent_id == "" or shard or not disturbed and not broken:
		return
	if not GameState.player.has("physical_objects"):
		GameState.player["physical_objects"] = {}
	GameState.player["physical_objects"][persistent_id] = {"broken": broken, "disturbed": disturbed, "position": [global_position.x, global_position.y, global_position.z], "rotation": [global_rotation.x, global_rotation.y, global_rotation.z]}

func _exit_tree() -> void:
	if GameState.active: save_state()

static func tableware(parent: Node3D, point: Vector3, kind: String, key: String) -> RigidBody3D:
	var object = load("res://world3d/light_object.gd").new()
	object.name = kind.capitalize()
	object.material_kind = "glass" if kind == "garrafa" else "ceramic"
	object.mass = 0.2
	var radius := 0.11 if kind == "prato" else 0.045
	var height := 0.018 if kind == "prato" else (0.23 if kind == "garrafa" else 0.11)
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius * (0.45 if kind == "garrafa" else 1.0)
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 12
	cylinder.rings = 1
	mesh.mesh = cylinder
	mesh.position.y = height / 2
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#698c79") if kind == "garrafa" else Color("#c7c1ac")
	material.roughness = 0.2
	mesh.material_override = material
	object.add_child(mesh)
	Layers.box(object, Vector3(radius * 2, height, radius * 2), Vector3(0, height / 2, 0))
	object.set_meta("bounds", AABB(Vector3(-radius, 0, -radius), Vector3(radius * 2, height, radius * 2)))
	object.position = point
	parent.add_child(object)
	object.bind_id(key)
	return object
