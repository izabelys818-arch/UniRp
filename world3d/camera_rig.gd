extends Node3D

# Duas vistas do mesmo mundo. Não move/recria o jogador e não toca no save.
# A varredura de esfera protege a câmera e a extensão volta suavemente após obstáculos.
enum Mode { ISOMETRIC, THIRD_PERSON }
const PITCH_MIN := -1.05
const PITCH_MAX := 0.48
const MIN_DISTANCE := 1.8
const MAX_DISTANCE := 8.0
var mode := Mode.ISOMETRIC
var iso: Camera3D
var third: Camera3D
var active: Camera3D
var room_limit: Callable
var yaw := PI
var pitch := -0.14
var distance := 4.6
var _yaw := PI
var _pitch := -0.14
var _focus := Vector3.ZERO
var _length := 4.6
var _query := PhysicsShapeQueryParameters3D.new()
var _body: CharacterBody3D
var _initialized := false

func _ready() -> void:
	iso = Camera3D.new()
	iso.name = "IsometricCamera"
	iso.projection = Camera3D.PROJECTION_ORTHOGONAL
	iso.near = 70.0
	iso.far = 250.0
	add_child(iso)
	third = Camera3D.new()
	third.name = "ThirdPersonCamera"
	third.projection = Camera3D.PROJECTION_PERSPECTIVE
	third.fov = 65.0
	third.near = 0.08
	third.far = 3500.0
	add_child(third)
	var sphere := SphereShape3D.new()
	sphere.radius = 0.22
	_query.shape = sphere
	_query.collision_mask = preload("res://world3d/physics_layers.gd").WORLD
	active = iso
	iso.make_current()

func bind(body: CharacterBody3D) -> void:
	_body = body
	_query.exclude = [body.get_rid()]

func set_mode(next: int, focus: Vector3, heading: float) -> void:
	if next == Mode.THIRD_PERSON and mode != next:
		yaw = heading + PI
		_yaw = yaw
		_pitch = pitch
		_focus = focus
		_initialized = true
		_length = distance
	mode = clampi(next, 0, 1)
	active = third if mode == Mode.THIRD_PERSON else iso
	active.make_current()

func rotate_view(relative: Vector2, sensitivity: float, invert_y: bool) -> void:
	yaw -= relative.x * sensitivity
	pitch = clampf(pitch - relative.y * sensitivity * (-1.0 if invert_y else 1.0), PITCH_MIN, PITCH_MAX)

func zoom_view(factor: float) -> void:
	distance = clampf(distance * factor, MIN_DISTANCE, MAX_DISTANCE)

func tick(delta: float, iso_focus: Vector3, iso_zoom: float, iso_direction: Vector3, focus: Vector3) -> void:
	iso.size = lerpf(iso.size, iso_zoom, minf(delta * 8.0, 1.0))
	iso.position = iso_focus + iso_direction.normalized() * 150.0
	iso.look_at(iso_focus, Vector3.UP)
	if mode != Mode.THIRD_PERSON or not is_instance_valid(_body):
		return
	var blend := 1.0 - exp(-delta * 10.0)
	_focus = _focus.lerp(focus, blend) if _initialized else focus
	_initialized = true
	_yaw = lerp_angle(_yaw, yaw, blend)
	_pitch = lerpf(_pitch, pitch, blend)
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0))
	_query.transform = Transform3D(Basis.IDENTITY, _focus)
	_query.motion = Vector3.ZERO
	var space := _body.get_world_3d().direct_space_state
	if not space.intersect_shape(_query, 1).is_empty():
		# A suavização do pivô não pode cortar a quina de uma parede.
		_focus = focus
		_query.transform.origin = _focus
		if not space.intersect_shape(_query, 1).is_empty():
			return
	_query.motion = basis.z * distance
	var fractions := space.cast_motion(_query)
	var safe_length := distance
	if fractions[0] < 1.0:
		safe_length = maxf(0.0, distance * fractions[0] - 0.08)
	if room_limit.is_valid():
		safe_length = minf(safe_length, float(room_limit.call(_focus, basis.z, safe_length)))
	# Recuar na colisão é imediato; abrir espaço novamente é gradual e não atravessa a parede.
	_length = safe_length if safe_length < _length else lerpf(_length, safe_length, blend)
	# Quando a parede encurta a distância, abrir um pouco o campo evita cortar pés/cabeça.
	var target_fov := lerpf(75.0, 65.0, smoothstep(1.0, 2.6, _length))
	third.fov = lerpf(third.fov, target_fov, blend)
	third.global_transform = Transform3D(basis, _focus + basis.z * _length)

func movement_basis() -> Basis:
	return Basis(Vector3.UP, _yaw)

func forward() -> Vector3:
	return -movement_basis().z
