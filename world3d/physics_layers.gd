extends RefCounted

const GROUND := 1
const WALL := 2
const FURNITURE := 4
const VEHICLE := 8
const NPC := 16
const PLAYER := 32
const ANIMAL := 64
const VEGETATION := 128
const INTERACTIVE := 256
const TRIGGER := 512
const WORLD := GROUND | WALL | FURNITURE | VEHICLE | VEGETATION | INTERACTIVE
const ACTORS := NPC | PLAYER | ANIMAL
const WALK := WORLD | ACTORS

static func shape(body: CollisionObject3D, volume: Shape3D, point: Vector3, yaw := 0.0) -> CollisionShape3D:
	var node := CollisionShape3D.new()
	node.shape = volume
	node.position = point
	node.rotation.y = yaw
	body.add_child(node)
	return node

static func box(body: CollisionObject3D, size: Vector3, point: Vector3, yaw := 0.0) -> CollisionShape3D:
	var volume := BoxShape3D.new()
	volume.size = size
	return shape(body, volume, point, yaw)

static func vehicle(body: PhysicsBody3D, bus := false, van := false) -> void:
	body.collision_layer = VEHICLE
	body.collision_mask = WALL | FURNITURE | VEHICLE | VEGETATION | INTERACTIVE | ACTORS | GROUND
	box(body, Vector3(2.6, 0.85, 10.5) if bus else Vector3(1.9, 0.65, 4.3), Vector3(0, 0.62, 0))
	box(body, Vector3(2.5, 2.4, 9.8) if bus else Vector3(1.72, 1.1 if van else 0.5, 3.5 if van else 2.1), Vector3(0, 2.15 if bus else (1.25 if van else 1.16), 0))
