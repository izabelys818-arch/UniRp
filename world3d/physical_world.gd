extends Node3D

const Layers = preload("res://world3d/physics_layers.gd")
const State = preload("res://world3d/physics_state.gd")
const LightObject = preload("res://world3d/light_object.gd")
const ACTIVE_RADIUS := 48.0
const MAX_SHARDS := 40
var view: Node
var shards: Array[WeakRef] = []
var held: RigidBody3D
var timer := 0.0

func setup(world_view: Node) -> void:
	view = world_view
	add_to_group("world_stream")

func actor(figure: Node3D, layer: int, on_damage := Callable(), height := 1.6, radius := 0.28) -> RefCounted:
	var body := CharacterBody3D.new()
	body.name = "PhysicalActor"
	figure.get_parent().add_child(body)
	var state := State.new()
	state.setup(body, figure, layer, on_damage, true, height, radius)
	figure.tree_exiting.connect(body.queue_free)
	return state

func tick(delta: float) -> void:
	if is_instance_valid(held):
		var target: Vector3 = view.player.global_position + Vector3(0, 1.15, 0) + Basis(Vector3.UP, view.player_fig.rotation.y) * Vector3(0, 0, 0.8)
		held.move_and_collide(target - held.global_position)
		held.top = maxf(held.top, held.global_position.y)
	timer -= delta
	if timer > 0: return
	timer = 0.2
	var center: Vector3 = view.player.global_position
	for body in get_tree().get_nodes_in_group("physical_props"):
		var bounds: AABB = body.get_meta("physical_bounds")
		var world_bounds: AABB = body.global_transform * bounds
		var point := center.clamp(world_bounds.position, world_bounds.end)
		body.collision_layer = int(body.get_meta("physical_layer")) if body.is_visible_in_tree() and center.distance_squared_to(point) < ACTIVE_RADIUS * ACTIVE_RADIUS else 0
	for item in get_tree().get_nodes_in_group("light_objects"):
		if not item.is_connected("shattered", _shatter): item.shattered.connect(_shatter)
		var near: bool = item.global_position.distance_squared_to(center) < ACTIVE_RADIUS * ACTIVE_RADIUS
		item.collision_layer = Layers.INTERACTIVE if near and not item.broken else 0
		if not near and not item.held:
			item.freeze = true
			item.set_physics_process(item.shard)
		elif near and item.disturbed and not item.broken and not item.shard and item.freeze and item.resting < 0.8:
			item.wake()
	for target in view.city.objects.values():
		var owner: Node3D = target.get("owner")
		if owner is LightObject:
			target["bounds"] = owner.global_transform * owner.get_meta("bounds", AABB(Vector3(-0.15, 0, -0.15), Vector3(0.3, 0.3, 0.3)))

func toggle_hold(target: Dictionary) -> bool:
	var object: Node3D = target.get("owner")
	if object is not LightObject or object.broken or view.player_physics.blocked(): return false
	if held == object:
		object.held = false
		object.remove_collision_exception_with(view.player)
		held = null
		object.wake(Basis(Vector3.UP, view.player_fig.rotation.y) * Vector3(0, 0, 0.7))
		return true
	if is_instance_valid(held) or not view.object_access(target): return false
	object.held = true
	object.disturbed = true
	object.freeze = true
	object.add_collision_exception_with(view.player)
	held = object
	return true

func release() -> void:
	if is_instance_valid(held):
		held.held = false
		held.remove_collision_exception_with(view.player)
		held.wake()
	held = null

func _shatter(object: RigidBody3D) -> void:
	object.save_state()
	for key in view.city.objects.keys():
		if view.city.objects[key].get("owner") == object: view.city.objects.erase(key)
	for i in 5:
		while shards.size() >= MAX_SHARDS:
			var old: Object = shards.pop_front().get_ref()
			if is_instance_valid(old): old.queue_free()
		var piece := LightObject.new()
		piece.shard = true
		piece.expires = 2.5 + i * 0.15
		piece.mass = 0.03
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.06, 0.018, 0.05)
		Layers.shape(piece, shape, Vector3.ZERO)
		var mesh := MeshInstance3D.new()
		var block := BoxMesh.new()
		block.size = shape.size
		mesh.mesh = block
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#b7c2c2") if object.material_kind == "glass" else Color("#d2c8b4")
		mesh.material_override = material
		piece.add_child(mesh)
		add_child(piece)
		piece.global_position = object.global_position + Vector3(cos(i * TAU / 5) * 0.08, 0.04, sin(i * TAU / 5) * 0.08)
		piece.collision_mask = Layers.GROUND | Layers.WALL | Layers.FURNITURE | Layers.VEGETATION
		piece.wake(Vector3(cos(i * TAU / 5) * 0.7, 0.65, sin(i * TAU / 5) * 0.7))
		shards.append(weakref(piece))
	var dust := CPUParticles3D.new()
	dust.amount = 8
	dust.lifetime = 0.35
	dust.one_shot = true
	dust.initial_velocity_min = 0.2
	dust.initial_velocity_max = 0.5
	dust.gravity = Vector3(0, -3, 0)
	var mote := BoxMesh.new()
	mote.size = Vector3.ONE * 0.02
	dust.mesh = mote
	add_child(dust)
	dust.global_position = object.global_position
	dust.finished.connect(dust.queue_free)
	dust.emitting = true

func flush() -> void:
	if view.player_physics == null: return
	GameState.player["physical"] = view.player_physics.to_dict()
	for id in view.npcs:
		if view.npcs[id].has("physical") and NPCManager.state.has(id):
			NPCManager.state[id]["physical"] = view.npcs[id]["physical"].to_dict()
	for object in get_tree().get_nodes_in_group("light_objects"):
		object.save_state()
