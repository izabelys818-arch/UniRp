extends CharacterBody3D

const Layers = preload("res://world3d/physics_layers.gd")
var sensor: Area3D
var actual_speed := 0.0

func configure(bus := false, van := false) -> void:
	Layers.vehicle(self, bus, van)
	safe_margin = 0.005
	sensor = Area3D.new()
	sensor.name = "ImpactFront"
	sensor.collision_layer = Layers.TRIGGER
	sensor.collision_mask = Layers.ACTORS
	Layers.box(sensor, Vector3(2.65 if bus else 1.95, 1.35, 0.55), Vector3(0, 0.75, 5.3 if bus else 2.15))
	add_child(sensor)

func drive(motion: Vector3, yaw: float, speed: float, near: bool) -> bool:
	if not near:
		collision_layer = 0
		collision_mask = 0
		sensor.monitoring = false
		position += motion
		rotation.y = yaw
		actual_speed = 0
		return false
	collision_layer = Layers.VEHICLE
	collision_mask = Layers.WALK
	sensor.monitoring = true
	actual_speed = speed
	# A curva usa os mesmos alvos do trânsito. Rejeita a rotação que colocaria
	# a carroceria dentro de um obstáculo antes de varrer a translação.
	var turn := Transform3D(Basis(Vector3.UP, yaw), global_position)
	var clear := true
	for child in get_children():
		if child is CollisionShape3D:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = child.shape
			query.transform = turn * child.transform
			query.collision_mask = Layers.WALK
			query.exclude = [get_rid()]
			if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
				clear = false
				break
	if clear: rotation.y = yaw
	for actor in sensor.get_overlapping_bodies():
		_hit(actor, motion, speed)
	var hit := move_and_collide(motion)
	if hit != null:
		_hit(hit.get_collider(), motion, speed)
		actual_speed = 0
		return true
	return false

func _hit(object: Object, direction: Vector3, speed: float) -> void:
	if object is CharacterBody3D and object.has_meta("physical_state"):
		object.get_meta("physical_state").impact(direction, speed, true)
	elif object is RigidBody3D and object.has_method("wake"):
		object.wake(direction.normalized() * minf(speed, 3))
