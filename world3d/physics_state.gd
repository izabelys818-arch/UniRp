extends RefCounted

# Corpo separado do rig: a rotina solicita uma posição, a cápsula resolve o
# deslocamento em passos fixos e devolve a posição realmente alcançada ao visual.
const Layers = preload("res://world3d/physics_layers.gd")
const GRAVITY := 20.0
var body: CharacterBody3D
var visual: Node3D
var state := "normal"
var remaining := 0.0
var duration := 0.0
var impulse := Vector3.ZERO
var recovery := 2.0
var peak := -INF
var cooldown := 0.0
var damage := Callable()
var active := true
var proxy := false
var capsule: CapsuleShape3D
var collider: CollisionShape3D
var standing_height := 1.6
var seated := false
var requested_speed := 0.0

func setup(target: CharacterBody3D, figure: Node3D, layer: int, on_damage: Callable, is_proxy := false, height := 1.6, radius := 0.28) -> void:
	body = target
	visual = figure
	damage = on_damage
	proxy = is_proxy
	standing_height = height
	body.collision_layer = layer
	body.collision_mask = Layers.WALK
	body.floor_snap_length = 0.4
	body.safe_margin = 0.005
	body.set_meta("physical_state", self)
	if body.get_child_count() > 0 and body.get_child(0) is CollisionShape3D:
		collider = body.get_child(0)
		capsule = collider.shape
	else:
		capsule = CapsuleShape3D.new()
		capsule.radius = radius
		capsule.height = height
		collider = Layers.shape(body, capsule, Vector3(0, height / 2, 0))
	body.position = visual.position if proxy else body.position

func blocked() -> bool:
	return state in ["caindo", "caido", "atropelado", "levantando"]

func impact(direction: Vector3, speed: float, vehicle := false) -> bool:
	if cooldown > 0.0 or blocked():
		return false
	var flat := Vector3(direction.x, 0, direction.z).normalized()
	if flat == Vector3.ZERO:
		return false
	cooldown = 1.0
	impulse = flat * clampf(speed * (0.65 if vehicle else 0.5), 0.4, 5.5)
	if vehicle and speed >= 1.5:
		var amount := clampf(speed * speed * 0.65, 1, 85)
		recovery = clampf(2.0 + amount * 0.035, 2, 5)
		_set_state("atropelado", 0.8)
		body.velocity.y = minf(speed * 0.12, 1.2)
		if damage.is_valid():
			damage.call(amount, "atropelamento")
	else:
		_set_state("tropecando", 0.65)
	return true

func _set_state(next: String, seconds: float) -> void:
	state = next
	remaining = seconds
	duration = seconds
	if is_instance_valid(visual):
		visual.set_meta("impact_state", state)
		visual.set_meta("impact_phase", 0.0)
	_update_shape()

func _update_shape() -> void:
	var low := state in ["caido", "levantando"]
	capsule.height = maxf(capsule.radius * 2, 0.56) if low else (maxf(capsule.radius * 2, standing_height * 0.55) if seated else standing_height)
	collider.position.y = capsule.height / 2 + (standing_height * 0.35 if seated and not low else 0.0)

func begin(delta: float) -> void:
	cooldown = maxf(0, cooldown - delta)
	if state != "normal":
		remaining = maxf(0, remaining - delta)
		if remaining <= 0:
			if state in ["atropelado", "caindo"]:
				if body.is_on_floor():
					_set_state("caido", recovery)
			elif state == "caido":
				# Só cresce a cápsula se houver espaço para levantar.
				var query := PhysicsShapeQueryParameters3D.new()
				var full := CapsuleShape3D.new()
				full.radius = capsule.radius
				full.height = standing_height
				query.shape = full
				query.transform = Transform3D(Basis.IDENTITY, body.global_position + Vector3(0, standing_height / 2 + 0.025, 0))
				query.collision_mask = Layers.WALK
				query.exclude = [body.get_rid()]
				if body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
					_set_state("levantando", 1.0)
			elif state in ["levantando", "tropecando"]:
				_set_state("normal", 0)
		visual.set_meta("impact_phase", 1.0 - remaining / maxf(duration, 0.001))
	impulse = impulse.move_toward(Vector3.ZERO, delta * 5.0)

func after_move() -> void:
	if body.is_on_floor():
		if peak != -INF:
			var drop := peak - body.position.y
			peak = -INF
			if drop > 2.5 and state != "atropelado":
				var amount := clampf((drop - 2.5) * 12.0, 1, 85)
				recovery = clampf(2 + amount * 0.035, 2, 5)
				_set_state("caindo", 0.65)
				if damage.is_valid():
					damage.call(amount, "queda")
	else:
		peak = maxf(peak, body.position.y)
	for index in body.get_slide_collision_count():
		var hit := body.get_slide_collision(index)
		var other: Object = hit.get_collider()
		if other is RigidBody3D and other.has_method("wake"):
			other.wake(-hit.get_normal() * 1.2)
		elif other is CharacterBody3D and other.has_meta("physical_state") and hit.get_normal().y < 0.5:
			var physical: RefCounted = other.get_meta("physical_state")
			var speed := requested_speed
			# Deslocamento limitado e com sweep; não força posições nem se recupera
			# de sobreposição por teletransporte.
			if speed > 0.2:
				physical.impulse = (physical.impulse - hit.get_normal() * minf(speed * 0.25, 0.25)).limit_length(1.0)

func resolve(delta: float, near: bool, sitting := false) -> void:
	if not proxy:
		return
	seated = sitting
	_update_shape()
	if not near:
		body.collision_layer = 0
		body.collision_mask = 0
		body.position = visual.position
		active = false
		return
	if not active:
		body.position = visual.position
		active = true
	body.collision_layer = Layers.ANIMAL if standing_height < 0.9 else Layers.NPC
	body.collision_mask = Layers.WALK
	begin(delta)
	var previous := body.position
	var wanted := (visual.position - previous) / maxf(delta, 0.001)
	if blocked():
		wanted = Vector3.ZERO
	body.velocity.x = wanted.x + impulse.x
	body.velocity.z = wanted.z + impulse.z
	body.velocity.y = 0.0 if seated or body.is_on_floor() else body.velocity.y - GRAVITY * delta
	requested_speed = Vector2(body.velocity.x, body.velocity.z).length()
	body.move_and_slide()
	after_move()
	visual.position = body.position
	if visual.get("move_speed") != null:
		visual.set("move_speed", Vector2(body.position.x - previous.x, body.position.z - previous.z).length() / delta)

func to_dict() -> Dictionary:
	return {"state": state, "remaining": remaining, "duration": duration, "recovery": recovery, "peak": peak if peak != -INF else null, "impulse": [impulse.x, impulse.y, impulse.z], "velocity": [body.velocity.x, body.velocity.y, body.velocity.z]}

func restore(data: Dictionary) -> void:
	var saved := str(data.get("state", "normal"))
	if saved not in ["normal", "tropecando", "caindo", "caido", "atropelado", "levantando"]:
		saved = "normal"
	_set_state(saved, clampf(float(data.get("remaining", 0)), 0, 5))
	duration = maxf(remaining, float(data.get("duration", remaining)))
	recovery = clampf(float(data.get("recovery", 2)), 2, 5)
	peak = float(data["peak"]) if data.get("peak") != null else -INF
	for pair in [["impulse", "impulse"], ["velocity", "velocity"]]:
		var value: Array = data.get(pair[0], [0, 0, 0])
		if value.size() == 3:
			var vector := Vector3(float(value[0]), float(value[1]), float(value[2]))
			if pair[0] == "impulse": impulse = vector
			else: body.velocity = vector
