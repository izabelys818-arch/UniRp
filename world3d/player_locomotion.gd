extends RefCounted

# Camada visual compartilhada. Reusa os clips hm08; IA/colisão/ações intactas.
# Distâncias de apoio medidas offline; não usa os metadados antigos do bake.
const STRIDES := {
	"Human_male": {"Walk": 1.468542, "Walk_Formal": 1.417658, "Jog_Fwd": 5.837971, "Sprint": 6.129481},
	"Human_female": {"Walk": 1.411253, "Walk_Formal": 1.368545, "Jog_Fwd": 5.596610, "Sprint": 5.944090},
	"Human_male_child": {"Walk": 1.386455, "Walk_Formal": 1.377268, "Jog_Fwd": 5.619779, "Sprint": 5.902047},
	"Human_female_child": {"Walk": 1.422168, "Walk_Formal": 1.412838, "Jog_Fwd": 5.757439, "Sprint": 6.282656},
}
const SOLES := {
	"Human_male": [Vector3(0.010049, -0.066812, 0.136728), Vector3(-0.010049, -0.066812, 0.136728)],
	"Human_female": [Vector3(0.014028, -0.069849, 0.135152), Vector3(-0.014028, -0.069849, 0.135152)],
	"Human_male_child": [Vector3(0.011669, -0.064467, 0.124562), Vector3(-0.011669, -0.064467, 0.124562)],
	"Human_female_child": [Vector3(0.010289, -0.070894, 0.140479), Vector3(-0.010289, -0.070894, 0.140479)],
}

var tree: AnimationTree
var walk_clip := "Walk"
var run_clip := "Sprint"
var walk_distance := 1.0
var run_distance := 3.0
var phase := 0.0
var pace := 0.0
var move_weight := 0.0
var run_weight := 0.0
var current_rate := 1.0
var active := false
var _feet: Array[int] = []
var _sole_offsets: Array[Vector3] = []
var _ground_y := 0.0
var prototype := false
var planted := [false, false]
var anchor_world := [Vector3.ZERO, Vector3.ZERO]
var reach_errors := [0.0, 0.0]
var contact_offsets: Array[Vector3] = []
var _toe_in_foot: Array[Vector3] = []
var _sole_hulls: Array = []
var _last_soles := [Vector3.INF, Vector3.INF]
var _heel_offsets: Array[Vector3] = []
var _toe_offsets: Array[Vector3] = []
var _toe_bones: Array[int] = []
var _hips: Array[int] = []
var _knees: Array[int] = []
var _strike_right := 0.5
var _walk_right := 0.5
var _run_right := 0.5
var _pelvis_mean := 0.0
var _pelvis := -1
var _last_position := Vector3.INF
var _velocity := Vector3.ZERO
var _last_speed := 0.0
var _last_pace := 0.0
var _stop_left := 0.0
var _stop_from := [Vector3.ZERO, Vector3.ZERO]
var _stop_basis_from := [Basis.IDENTITY,Basis.IDENTITY]
var _start_left := 0.0
var _start_from := [Vector3.ZERO, Vector3.ZERO]
var _start_phase := 0.0
var _start_blend := 1.0
var _start_recovering := [false,false]
var _swing_from := [Vector3.ZERO, Vector3.ZERO]
var _swing_basis_from := [Basis.IDENTITY,Basis.IDENTITY]
var _was_support := [false, false]
var _anchor_basis := [Basis.IDENTITY, Basis.IDENTITY]
var _plant_basis := [Basis.IDENTITY, Basis.IDENTITY]
var _released := [false, false]
var _release_q := [0.0, 0.0]
var _swing_shape := [0.0, 0.0]
var _knee_poles := [Vector3(0,0,1),Vector3(0,0,1)]
var _frame_delta := 1.0/60.0
var _dyn_prev_speed := 0.0
var _smooth_speed := 0.0
var _posture := 0.0
var _dyn_prev_yaw := INF
var _dyn_accel := 0.0
var _dyn_yaw_rate := 0.0
var _dyn_lean := 0.0
var _dyn_bank := 0.0
var _floor_height := 0.0
var _floor_normal := Vector3.UP
var _idle_time := 0.0
var _gait_means: Dictionary = {}
var calibration: Dictionary = {}

# Read-only visual grounding against existing city meshes. Physics is unchanged.
const VF_CELL := 2.0
const VF_RADIUS := 6.0
var _vf_city: WeakRef
var _vf_resolved := false
var _vf_meshes: Dictionary = {} # resource id -> weakref + local triangles
var _vf_instances: Dictionary = {} # instance id -> weakref + mesh/transform
var _vf_cells: Dictionary = {} # Vector2i -> local-region world triangles
var _vf_center := Vector3.INF
var _vf_next_ms := 0

var _vf_last_hit: Dictionary = {}
var _vf_refresh_count := 0
var _vf_refresh_max_us := 0




func setup(person, body_path: String) -> void:
	# O IK de pés do protótipo travava a pose e deixava a marcha robótica; jogador e
	# NPCs agora usam a mesma marcha em árvore (fase presa à velocidade real).
	prototype = false
	var name := body_path.get_file().get_basename()
	var measured: Dictionary = STRIDES[name]
	walk_clip = "Walk_Formal" if int(person.look.get("age", 30)) >= 60 else "Walk"
	run_clip = "Jog_Fwd"
	# Medido no corpo correspondente. A escala longitudinal já reduz a passada
	# infantil; multiplicar novamente pelo perfil de idade era uma redução dupla.
	walk_distance = float(measured[walk_clip]) * person.scale.z
	run_distance = float(measured[run_clip]) * person.scale.z
	phase = fposmod(person.seed_n * 0.017, 1.0)
	for side in ["l", "r"]:
		_feet.append(person.skel.find_bone("foot_" + side))
		_toe_bones.append(person.skel.find_bone("ball_" + side))
		_hips.append(person.skel.find_bone("thigh_" + side))
		_knees.append(person.skel.find_bone("calf_" + side))
	for p in SOLES[name]:
		_sole_offsets.append(p)
	if prototype:
		_prepare_prototype(person)
	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = 1.0
	space.sync_mode = AnimationNodeBlendSpace1D.SYNC_MODE_CYCLIC_CONSTANT
	space.cyclic_length = 1.0
	for entry in [[walk_clip, 0.0], [run_clip, 1.0]]:
		var node := AnimationNodeAnimation.new()
		node.animation = ("prototype/" if prototype else "") + entry[0]
		node.use_custom_timeline = true
		node.timeline_length = 1.0
		node.stretch_time_scale = true
		node.loop_mode = Animation.LOOP_LINEAR
		space.add_blend_point(node, entry[1], -1, entry[0])
	var graph := AnimationNodeBlendTree.new()
	graph.add_node("Gait", space)
	graph.add_node("Pace", AnimationNodeTimeScale.new())
	graph.add_node("Phase", AnimationNodeTimeSeek.new())
	var idle := AnimationNodeAnimation.new()
	idle.animation = "Idle"
	graph.add_node("Idle", idle)
	graph.add_node("Body", AnimationNodeBlend2.new())
	graph.connect_node("Pace", 0, "Gait")
	graph.connect_node("Phase", 0, "Pace")
	graph.connect_node("Body", 0, "Idle")
	graph.connect_node("Body", 1, "Phase")
	graph.connect_node("output", 0, "Body")
	tree = AnimationTree.new()
	tree.name = "PlayerLocomotion"
	tree.tree_root = graph
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	person.model.add_child(tree)
	tree.anim_player = tree.get_path_to(person.ap)
	tree.root_node = NodePath("..")
	tree.active = false


func suspend(person) -> void:
	if not active:
		return
	active = false
	tree.active = false
	person._cur_anim = ""
	move_weight = 0.0
	_ground_y = 0.0
	person.model.position.y = 0.0
	if prototype:
		_last_position = Vector3.INF
		_last_speed = 0.0
		run_weight = 0.0
		pace = 0.0
		_last_pace = 0.0
		_velocity = Vector3.ZERO
		_stop_left = 0.0
		_start_left = 0.0
		planted = [false, false]
		_was_support = [false, false]
		_swing_from = [Vector3.ZERO,Vector3.ZERO]
		_last_soles = [Vector3.INF,Vector3.INF]
		_released = [false,false]


func step(person, delta: float) -> void:
	if prototype:
		_step_prototype(person, delta)
		return
	if not active:
		person.ap.stop()
		tree.active = true
		tree.set("parameters/Phase/seek_request", phase)
		active = true
	# move_speed vem de deslocamento por quadro (ruidoso); filtra para a cadência não tremer.
	_smooth_speed = lerpf(_smooth_speed, person._speed, 1.0 - exp(-16.0 * delta)) if _smooth_speed > 0.0 or person._speed > 0.0 else 0.0
	if person._speed <= 0.0 and _smooth_speed < 0.02: _smooth_speed = 0.0
	var speed: float = _smooth_speed
	var profile: Dictionary = person.HumanMotion.profile(int(person.look.get("age", 30)))
	var walk_goal := 2.2 * float(profile["walk"])
	var run_goal := 5.0 * float(profile["run"])
	# O andar fica no ciclo de marcha, independentemente de metadados ruins.
	# Acima da marcha, interpola continuamente até a corrida, inclusive ao frear.
	var target_run := smoothstep(walk_goal * 1.05, run_goal * 0.9, speed)
	run_weight = move_toward(run_weight, target_run, delta / 0.16)
	var target_move := smoothstep(0.05, 0.5, speed)
	move_weight = move_toward(move_weight, target_move, delta / 0.2)
	var cycle_distance := lerpf(walk_distance, run_distance, run_weight)
	# Piso de velocidade de passada: ao frear/arrancar as pernas não congelam no meio
	# do passo antes de mesclar com o Idle.
	var gait_speed := maxf(speed, 0.75) if move_weight > 0.05 else speed
	pace = gait_speed / maxf(cycle_distance, 0.1)
	_track_dynamics(person, speed, delta)
	phase = fposmod(phase + delta * pace, 1.0)
	tree.set("parameters/Gait/blend_position", run_weight)
	tree.set("parameters/Pace/scale", pace)
	tree.set("parameters/Body/blend_amount", move_weight)
	tree.advance(delta)
	person._cur_anim = (run_clip if run_weight >= 0.5 else walk_clip) if move_weight > 0.01 else "Idle"
	current_rate = pace * person.ap.get_animation(person._cur_anim).length if person._cur_anim != "Idle" else 1.0
	# Indicador para ferramentas existentes; AnimationTree usa Pace, não este valor.
	person.ap.speed_scale = current_rate


# Aceleração e giro reais do corpo, filtrados, para inclinar o tronco como uma pessoa.
func _track_dynamics(person, speed: float, delta: float) -> void:
	var dt := maxf(delta, 0.0001)
	var yaw: float = person.rotation.y
	var accel := (speed - _dyn_prev_speed) / dt
	var rate := 0.0 if _dyn_prev_yaw == INF else angle_difference(_dyn_prev_yaw, yaw) / dt
	_dyn_prev_speed = speed
	_dyn_prev_yaw = yaw
	var k := 1.0 - exp(-9.0 * dt)
	_dyn_accel = lerpf(_dyn_accel, clampf(accel, -14.0, 14.0), k)
	_dyn_yaw_rate = lerpf(_dyn_yaw_rate, clampf(rate, -9.0, 9.0), k)
	var lean_t := clampf(_dyn_accel * 0.006, -0.06, 0.07)
	var bank_t := clampf(-_dyn_yaw_rate * speed * 0.016, -0.2, 0.2)
	var s := 1.0 - exp(-7.0 * dt)
	_dyn_lean = lerpf(_dyn_lean, lean_t * move_weight, s)
	_dyn_bank = lerpf(_dyn_bank, bank_t * move_weight, s)


# Inclina coluna (frente/lado) por cima da animação, sem tocar nas pernas, e mantém
# a cabeça olhando adiante. Eixos do esqueleto: +Z à frente, +X à esquerda do corpo.
func dynamics(person, delta: float) -> void:
	var sk: Skeleton3D = person.skel
	var pelvis := sk.find_bone("pelvis")
	var head: int = person._head
	if pelvis < 0 or head < 0:
		return
	# Os clipes de marcha/corrida vêm muito curvados para frente. Mede a inclinação
	# real pelve->cabeça e a leva a uma postura ereta (leve inclinação só ao correr).
	var dir: Vector3 = sk.get_bone_global_pose(head).origin - sk.get_bone_global_pose(pelvis).origin
	var pitch := atan2(dir.z, dir.y)
	var target := lerpf(0.02, 0.10, run_weight)
	var want := clampf(pitch - target, 0.0, 0.7) * move_weight
	_posture = lerpf(_posture, want, 1.0 - exp(-10.0 * delta))
	var total := Basis(Vector3.RIGHT, _dyn_lean - _posture) * Basis(Vector3.BACK, _dyn_bank)
	if absf(_dyn_lean) < 0.002 and absf(_dyn_bank) < 0.002 and _posture < 0.002:
		return
	for entry in [["spine_01", 0.3], ["spine_02", 0.4], ["spine_03", 0.3]]:
		_rotate_global(sk, sk.find_bone(entry[0]), Basis.IDENTITY.slerp(total, entry[1]))
	# A cabeça mantém o olhar à frente em vez de acompanhar o tronco.
	_rotate_global(sk, head, Basis.IDENTITY.slerp(total.inverse(), 0.75))


func _rotate_global(sk: Skeleton3D, bone: int, extra: Basis) -> void:
	if bone < 0:
		return
	var parent: int = sk.get_bone_parent(bone)
	if parent < 0:
		return
	var g: Transform3D = sk.get_bone_global_pose(bone)
	var pg: Transform3D = sk.get_bone_global_pose(parent)
	sk.set_bone_pose_rotation(bone, (pg.basis.inverse() * extra * g.basis).get_rotation_quaternion())


func ground(person, delta: float) -> void:
	if prototype:
		_finish_prototype(person, delta)
		return
	# Só aterramento visual: não altera a cápsula nem instala IK. Corrige pequenas
	# penetrações do retarget; fase aérea da corrida continua livre.
	var low := INF
	for side in 2:
		var p: Vector3 = person.skel.get_bone_global_pose(_feet[side]) * _sole_offsets[side]
		low = minf(low, p.y)
	var target := clampf(-low, -0.035 if run_weight < 0.05 else 0.0, 0.055)
	# Corrigir a penetração no mesmo quadro; suavizar somente a retirada do apoio.
	# Na marcha, o pé mais baixo acompanha o piso. A corrida mantém a fase aérea.
	_ground_y = maxf(target, move_toward(_ground_y, target, delta * 0.7))
	person.model.position.y = _ground_y


# Only the approved player prototype uses these corrections. NPCs keep the
# previous graph, cadence and posture until the prototype is visually approved.
func _prepare_prototype(person) -> void:
	_pelvis = person.skel.find_bone("pelvis")
	var meshes: Array = [person.body_mi]
	var shoes: MeshInstance3D = person._human_parts.get("HumanShoes")
	if shoes != null and shoes.visible:
		_rigid_shoe_sole(shoes)
		meshes = [shoes]
	for side in 2:
		var candidates: Array[Vector3] = []
		var low := INF
		for mesh in meshes:
			for surface in mesh.mesh.get_surface_count():
				var arrays: Array = mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var count: int = bones.size() / vertices.size()
				for vertex in vertices.size():
					var weight := 0.0
					for influence in count:
						var bind: int = bones[vertex * count + influence]
						var bind_name: String = String(mesh.skin.get_bind_name(bind))
						if bind_name in ["foot_" + ("l" if side == 0 else "r"), "ball_" + ("l" if side == 0 else "r")]:
							weight += weights[vertex * count + influence]
					if weight > 0.75:
						low = minf(low, vertices[vertex].y)
						candidates.append(vertices[vertex])
		var heel := Vector3.ZERO
		var toe := Vector3.ZERO
		var min_z := INF
		var max_z := -INF
		for point in candidates:
			if point.y <= low + 0.015:
				if point.z < min_z:
					min_z = point.z
					heel = point
				if point.z > max_z:
					max_z = point.z
					toe = point
		# Preserve the curved sole. A flattened imaginary heel/toe can remain
		# planted while the visible shoe is a centimetre above it.
		var foot_inverse: Transform3D = person.skel.get_bone_global_rest(_feet[side]).affine_inverse()
		var hull: Array[Vector3] = []
		for point in candidates:
			if point.y<=low+0.035: hull.append(foot_inverse*point)
		_sole_hulls.append(hull)
		var center: Vector3 = (heel+toe)*0.5
		center.y=low
		_sole_offsets[side] = foot_inverse*center
		_heel_offsets.append(person.skel.get_bone_global_rest(_feet[side]).affine_inverse() * heel)
		_toe_offsets.append(person.skel.get_bone_global_rest(_toe_bones[side]).affine_inverse() * toe)
		_toe_in_foot.append(person.skel.get_bone_global_rest(_feet[side]).affine_inverse()*toe)
		contact_offsets.append(_sole_offsets[side])
	var library := AnimationLibrary.new()
	for clip_name in [walk_clip, run_clip]:
		var clip: Animation = person.ap.get_animation(clip_name)
		var samples: Array = []
		var lows := [INF, INF]
		var z_min := [INF, INF]
		var z_max := [-INF, -INF]
		var pelvis_sum := 0.0
		person.ap.play(clip_name, 0)
		for frame in 120:
			person.ap.seek(clip.length * frame / 120.0, true)
			var row: Array = []
			pelvis_sum += person.skel.get_bone_pose_position(_pelvis).y
			for side in 2:
				var heel: Vector3 = person.skel.get_bone_global_pose(_feet[side]) * _heel_offsets[side]
				var toe: Vector3 = person.skel.get_bone_global_pose(_toe_bones[side]) * _toe_offsets[side]
				var center: Vector3 = (heel + toe) * 0.5
				row.append(Vector2(center.z, minf(heel.y, toe.y)))
				lows[side] = minf(lows[side], minf(heel.y, toe.y))
				z_min[side] = minf(z_min[side], center.z)
				z_max[side] = maxf(z_max[side], center.z)
			samples.append(row)
		var strikes := [0.0, 0.5]
		for side in 2:
			var forward := -INF
			for frame in 120:
				var point: Vector2 = samples[frame][side]
				if point.y <= float(lows[side]) + 0.04 and point.x > forward:
					forward = point.x
					strikes[side] = frame / 120.0
		# Full measured longitudinal excursion, not a sparse derivative at the
		# lowest point. One cycle contains one step for each leg.
		var excursion: float = ((float(z_max[0])-float(z_min[0])) + (float(z_max[1])-float(z_min[1]))) * 0.5
		var distance: float = excursion * 2.0 * person.scale.z
		# The two-leg support schedule alternates half a cycle apart. Raw lowest
		# point detection is not a reliable right strike in the retargeted clips.
		var opposite := 0.5
		_gait_means[clip_name] = pelvis_sum / 120.0
		if clip_name == walk_clip:
			walk_distance = distance
			_walk_right = opposite
			_pelvis_mean = pelvis_sum / 120.0
		else:
			run_distance = distance
			_run_right = opposite
		calibration[clip_name] = {"excursion_m":excursion*person.scale.z,"cycle_m":distance,"left_strike":strikes[0],"right_strike":strikes[1],"heel_toe_min_y":lows}
		library.add_animation(clip_name, _aligned_clip(clip, float(strikes[0])))
	person.ap.add_animation_library("prototype", library)
	person.ap.play("Idle", 0)
	person.ap.advance(0)
	phase = 0.0 if posmod(int(person.seed_n), 2) == 0 else 0.5


func _aligned_clip(source: Animation, offset: float) -> Animation:
	var clip: Animation = source.duplicate(true)
	for track in clip.get_track_count():
		var kind: int = clip.track_get_type(track)
		if kind not in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D]:
			continue
		for key in range(clip.track_get_key_count(track)-1, -1, -1):
			clip.track_remove_key(track, key)
		for frame in 121:
			var time: float = clip.length * frame / 120.0
			var original: float = fposmod(frame / 120.0 + offset, 1.0) * source.length
			if kind == Animation.TYPE_ROTATION_3D:
				clip.rotation_track_insert_key(track, time, source.rotation_track_interpolate(track, original))
			elif kind == Animation.TYPE_POSITION_3D:
				clip.position_track_insert_key(track, time, source.position_track_interpolate(track, original))
			else:
				clip.scale_track_insert_key(track, time, source.scale_track_interpolate(track, original))
	return clip


func _step_prototype(person, delta: float) -> void:
	if not active:
		person.ap.stop()
		tree.active = true
		tree.set("parameters/Phase/seek_request", phase)
		active = true
	var position: Vector3 = person.global_position
	if _last_position != Vector3.INF:
		_velocity = (position-_last_position)/maxf(delta, 0.0001)
		if position.distance_to(_last_position) > 0.75:
			_last_speed = 0.0
			planted = [false, false]
			_was_support = [false, false]
			_stop_left = 0.0
			_start_left = 0.0
			_velocity = Vector3.ZERO
			_swing_from = [Vector3.ZERO,Vector3.ZERO]
			_last_soles = [Vector3.INF,Vector3.INF]
			_released = [false,false]
	_last_position = position
	_velocity.y = 0.0
	var speed: float = person._speed
	if speed>0.03 and _last_speed<=0.03:
		# An idle foot is below the hip, late in support. Beginning at
		# heel strike would hold that foot for an entire stride behind the body.
		phase=fposmod(floor(phase*2.0)*0.5+0.36,1.0)
		tree.set("parameters/Phase/seek_request",phase)
		_start_left=0.18
		_start_phase=phase
		_start_blend=0.0
		for side in 2:
			_start_from[side]=_last_soles[side] if _last_soles[side]!=Vector3.INF else _sole_world(person,side)
			_start_recovering[side]=fposmod(phase-(0.0 if side==0 else 0.5),1.0)>=0.5
			_anchor_basis[side]=(person.skel.global_transform*person.skel.get_bone_global_pose(_feet[side])).basis.orthonormalized()
		_was_support=[false,false]
		_swing_from=[Vector3.ZERO,Vector3.ZERO]
		_released=[false,false]
	var profile: Dictionary = person.HumanMotion.profile(int(person.look.get("age",30)))
	var run_target: float = smoothstep(2.2*float(profile["walk"])*1.05, 5.0*float(profile["run"])*0.9, speed)
	run_weight = move_toward(run_weight, run_target, delta/0.18)
	if speed <= 0.03 and _last_speed > 0.03:
		_stop_left = 0.38
		for side in 2:
			_stop_from[side] = _last_soles[side] if _last_soles[side]!=Vector3.INF else _sole_world(person,side)
			_stop_basis_from[side]=_anchor_basis[side]
	if speed > 0.03:
		_stop_left = 0.0
		_idle_time = 0.0
	else:
		_idle_time += delta
		_stop_left = maxf(0.0, _stop_left-delta)
	var target_move: float = smoothstep(0.03, 0.22, speed)
	move_weight = move_toward(move_weight, target_move, delta/0.18)
	var distance: float = lerpf(walk_distance,run_distance,run_weight)
	pace = speed/maxf(distance,0.1)
	if speed > 0.4: _last_pace = pace
	var phase_rate: float = pace if speed > 0.03 else _last_pace*smoothstep(0.0,0.38,_stop_left)
	phase = fposmod(phase+delta*phase_rate,1.0)
	if _start_left>0.0:
		var progress: float=clampf(fposmod(phase-_start_phase,1.0)/0.14,0.0,1.0)
		_start_blend=smoothstep(0.0,1.0,progress)
		_start_left=0.18*(1.0-progress) if speed>0.03 else 0.0
	_strike_right = lerpf(_walk_right,_run_right,run_weight)
	tree.set("parameters/Gait/blend_position",run_weight)
	tree.set("parameters/Pace/scale",phase_rate)
	tree.set("parameters/Body/blend_amount",move_weight)
	tree.advance(delta)
	person._cur_anim = (run_clip if run_weight>=0.5 else walk_clip) if move_weight>0.01 else "Idle"
	current_rate = pace*person.ap.get_animation(person._cur_anim).length if person._cur_anim!="Idle" else 1.0
	person.ap.speed_scale = current_rate
	_last_speed = speed


func body(person, delta: float) -> void:
	var pelvis_position: Vector3 = person.skel.get_bone_pose_position(_pelvis)
	# Keep source bounce, but reduce retarget exaggeration. No added sinusoidal
	# jump; the torso and arms retain the aligned UAL motion.
	var mean: float = lerpf(float(_gait_means[walk_clip]),float(_gait_means[run_clip]),run_weight)
	pelvis_position.y = lerpf(pelvis_position.y,lerpf(mean,pelvis_position.y,lerpf(0.85,0.55,run_weight)),move_weight)
	person.skel.set_bone_pose_position(_pelvis,pelvis_position)
	if run_weight>0.001:
		# The retargeted sprint leaned the pelvis-to-head axis by 45–48 degrees
		# at a constant 5m/s. Retain its variation with half the frontal lean.
		# Preserve the source's global head compensation after rotating the body.
		var head: int = person._head
		var head_basis: Basis = person.skel.get_bone_global_pose(head).basis
		var direction: Vector3 = person.skel.get_bone_global_pose(head).origin-person.skel.get_bone_global_pose(_pelvis).origin
		var pitch: float = atan2(direction.z,direction.y)*0.5
		var length: float = Vector2(direction.y,direction.z).length()
		person._aim_bone(_pelvis,head,Vector3(direction.x,cos(pitch)*length,sin(pitch)*length),run_weight)
		var parent: int = person.skel.get_bone_parent(head)
		person.skel.set_bone_pose_rotation(head,(person.skel.get_bone_global_pose(parent).basis.inverse()*head_basis).get_rotation_quaternion())
	person.rest_weight = move_toward(person.rest_weight,1.0-move_weight,delta*3.0)
	for side in ["l","r"]:
		for finger in ["index","middle","ring","pinky","thumb"]:
			for segment in [1,2,3]:
				var bone: int = person.skel.find_bone("%s_%02d_%s" % [finger,segment,side])
				if bone>=0:
					person.skel.set_bone_pose_rotation(bone,Quaternion.IDENTITY.slerp(person.skel.get_bone_pose_rotation(bone),0.35))


func _sole_world(person, side: int) -> Vector3:
	return person.skel.global_transform*(person.skel.get_bone_global_pose(_feet[side])*_sole_offsets[side])


func _floor(person, at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at+Vector3.UP*0.6,at-Vector3.UP*1.0)
	var exclusions: Array[RID] = []
	var parent: Node = person
	while parent!=null:
		if parent is CollisionObject3D: exclusions.append(parent.get_rid())
		parent = parent.get_parent()
	query.exclude = exclusions
	var hit: Dictionary = person.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and (hit["normal"] as Vector3).y>0.95 and (hit["position"] as Vector3).y<=person.global_position.y+0.12:
		return Vector3(at.x,visual_floor_height(person,at,(hit["position"] as Vector3).y),at.z)
	return Vector3(at.x,visual_floor_height(person,at,person.global_position.y),at.z)


func _finish_prototype(person, delta: float) -> void:
	_frame_delta=delta
	var targets: Array[Vector3] = []
	var moving: bool = person._speed>0.03
	var duty: float = lerpf(0.52,0.40,run_weight)
	var distance: float = lerpf(walk_distance,run_distance,run_weight)
	var yaw: Basis = person.global_basis.orthonormalized()
	var root: Vector3 = person.global_position
	var floor_root: Vector3 = _floor(person,root)
	_floor_height = floor_root.y
	if person._contact_blob != null:
		# The original blob followed the physical plane and floated above asphalt.
		person._contact_blob.position.y=(_floor_height-root.y+0.003)/maxf(person.scale.y,0.1)
	person.model.position.y = (_floor_height-root.y)/maxf(person.scale.y,0.1)
	# A small gait baseline accommodates the leg's real reach without a large
	# collapse on every impact. Remaining reach is solved below, not clamped away.
	person.model.position.y -= lerpf(0.06,0.10,run_weight)*move_weight
	for side in 2:
		var sign_x := 1.0 if side==0 else -1.0
		var hip_x: float = absf(person.skel.get_bone_global_rest(_hips[side]).origin.x)
		var width: float = hip_x*lerpf(0.86,0.68,move_weight)
		var reach: float = distance*duty*0.5
		var sole_forward: float = _sole_offsets[side].z*person.scale.z
		var forward: Vector3 = root+yaw*Vector3(sign_x*width*person.scale.x,0,reach+sole_forward)
		var q: float = fposmod(phase-(0.0 if side==0 else _strike_right),1.0)
		var support: bool = moving and q<duty
		if _released[side] and q<float(_release_q[side]): _released[side]=false
		if support and _was_support[side] and (_plant_basis[side] as Basis).z.dot(yaw.z)<cos(deg_to_rad(35.0)):
			_released[side]=true
			_release_q[side]=q
			_swing_from[side]=_last_soles[side]
			_swing_basis_from[side]=_anchor_basis[side]
		if _released[side]: support=false
		var target: Vector3
		_swing_shape[side]=0.0
		var old_offset: Vector3 = contact_offsets[side]
		contact_offsets[side] = _sole_offsets[side]
		if not moving:
			_released[side]=false
			var neutral: Vector3 = _floor(person,root+yaw*Vector3(sign_x*hip_x*0.87*person.scale.x,0,0.025))
			_anchor_basis[side]=yaw
			if _stop_left>0.0:
				var t: float = 1.0-_stop_left/0.38
				var u: float = clampf((t-(side*0.18))/0.82,0.0,1.0)
				_anchor_basis[side]=Basis((_stop_basis_from[side] as Basis).get_rotation_quaternion().slerp(yaw.get_rotation_quaternion(),smoothstep(0.0,1.0,u)))
				target = (_stop_from[side] as Vector3).lerp(neutral,smoothstep(0.0,1.0,u))
				target.y += sin(u*PI)*0.035
				var stop_clear: float=_world_offset(person,_anchor_basis[side],_support_offset(person,side,_anchor_basis[side])-_sole_offsets[side]).y
				target.y=maxf(target.y,neutral.y-stop_clear)
				planted[side] = u>=0.999
				if planted[side]: anchor_world[side]=neutral
			else:
				if not planted[side] or _was_support[side]: anchor_world[side]=neutral
				target = anchor_world[side]
				planted[side] = true
		elif support:
			var toe_roll: float = smoothstep(duty*0.72,duty,q)*0.34
			var heel_roll: float = (1.0-smoothstep(0.0,duty*0.12,q))*(-0.12)
			var plant: Basis = _plant_basis[side] if _was_support[side] else yaw
			var orientation: Basis = plant*Basis(Vector3.RIGHT,heel_roll+toe_roll)
			contact_offsets[side] = _support_offset(person,side,orientation)
			if not _was_support[side]:
				var initial_support: bool = _start_left>0.0 and q>=0.25
				var first_plant: bool = initial_support or (move_weight<0.35 and _last_soles[side]!=Vector3.INF)
				var initial: Vector3 = _start_from[side] if initial_support else _last_soles[side]
				var landing: Vector3 = initial if first_plant else forward
				landing += _world_offset(person,orientation,contact_offsets[side]-_sole_offsets[side])
				anchor_world[side] = _floor(person,landing)
				_anchor_basis[side] = yaw
				_plant_basis[side] = yaw
				planted[side] = true
			elif old_offset!=contact_offsets[side]:
				anchor_world[side] += _world_offset(person,_anchor_basis[side],contact_offsets[side]-old_offset)
				anchor_world[side] = _floor(person,anchor_world[side])
			# Rolling about heel/toe, with the active contact point held in place.
			_anchor_basis[side] = orientation
			target = anchor_world[side]
		else:
			if _was_support[side] or _swing_from[side]==Vector3.ZERO:
				_swing_from[side] = _last_soles[side] if _last_soles[side]!=Vector3.INF else _floor(person,_sole_world(person,side))
				_swing_basis_from[side]=_anchor_basis[side]
			var release: float = float(_release_q[side]) if _released[side] else duty
			var u: float = clampf((q-release)/(1.0-release),0.0,1.0)
			_swing_shape[side]=pow(sin(u*PI),2.0)
			var remaining: float = minf((1.0-q)/maxf(pace,0.1),0.65)
			var destination: Vector3 = _floor(person,forward+_velocity*remaining)
			target = (_swing_from[side] as Vector3).lerp(destination,smoothstep(0.0,1.0,u))
			target.y += pow(sin(u*PI),2.0)*lerpf(0.13,0.34-0.12*u,run_weight)*person.scale.y
			var swing_basis: Basis=yaw*Basis(Vector3.RIGHT,lerpf(0.35,-0.12,u))
			# A pivot releases the foot's position and orientation together.
			# Avoid snapping its yaw as soon as the old support is released.
			_anchor_basis[side]=Basis((_swing_basis_from[side] as Basis).get_rotation_quaternion().slerp(swing_basis.get_rotation_quaternion(),smoothstep(0.0,1.0,u)))
			var sole_clear: float = _world_offset(person,_anchor_basis[side],_support_offset(person,side,_anchor_basis[side])-_sole_offsets[side]).y
			target.y = maxf(target.y,destination.y-sole_clear)
			if _start_left>0.0 and _start_recovering[side]:
				# The recovering foot starts where it was actually displayed;
				# avoid jumping directly into the middle of the first swing.
				target=(_start_from[side] as Vector3).lerp(target,_start_blend)
				target.y=maxf(target.y,destination.y-sole_clear)
			planted[side] = false
		_was_support[side] = support
		targets.append(target)
	# Settle pelvis enough to keep the supporting leg reachable. This modifies
	# visual root only; collision/physical displacement are untouched.
	var lower := 0.0
	for side in 2:
		if not planted[side]: continue
		var h: Vector3 = person.skel.global_transform*person.skel.get_bone_global_pose(_hips[side]).origin
		var k: Vector3 = person.skel.global_transform*person.skel.get_bone_global_pose(_knees[side]).origin
		var a: Vector3 = person.skel.global_transform*person.skel.get_bone_global_pose(_feet[side]).origin
		var length: float = h.distance_to(k)+k.distance_to(a)-0.012
		var ankle_target: Vector3 = targets[side]-_world_offset(person,_anchor_basis[side],contact_offsets[side])
		var horizontal: float = Vector2(h.x-ankle_target.x,h.z-ankle_target.z).length()
		var max_height: float = sqrt(maxf(0.0,length*length-horizontal*horizontal))
		lower = minf(lower,ankle_target.y+max_height-h.y)
	person.model.position.y += maxf(lower,-0.16*person.scale.y)/maxf(person.scale.y,0.1)
	for side in 2:
		_solve_foot(person,side,targets[side],_anchor_basis[side])
		_last_soles[side] = _sole_world(person,side)


func _solve_foot(person, side: int, sole_target: Vector3, world_basis: Basis) -> void:
	var sk: Skeleton3D = person.skel
	var inverse: Transform3D = sk.global_transform.affine_inverse()
	var foot_basis: Basis = sk.global_basis.orthonormalized().inverse()*world_basis
	var target: Vector3 = inverse*sole_target-foot_basis*contact_offsets[side]
	var h: Vector3 = sk.get_bone_global_pose(_hips[side]).origin
	var k: Vector3 = sk.get_bone_global_pose(_knees[side]).origin
	var a: Vector3 = sk.get_bone_global_pose(_feet[side]).origin
	var upper: float = h.distance_to(k)
	var lower: float = k.distance_to(a)
	var direction: Vector3 = (target-h).normalized()
	var distance: float = clampf(h.distance_to(target),absf(upper-lower)+0.005,upper+lower-0.005)
	var effective: Vector3 = h+direction*distance
	reach_errors[side] = (sk.global_transform.basis*(effective-target)).length()
	var projection: float = (upper*upper-lower*lower+distance*distance)/(2.0*distance)
	# Preserve the source knee plane during recovery; supports use a forward
	# plane so a fixed foot cannot turn the knee inward or backwards.
	var source: Vector3 = (k-h)-direction*(k-h).dot(direction)
	var pole: Vector3 = Vector3(0,0,1)-direction*direction.z
	if not planted[side] and source.length_squared()>0.0001:
		var influence: float = 0.45*float(_swing_shape[side])*smoothstep(0.0,0.35,source.normalized().dot(pole.normalized()))
		pole = pole.normalized().lerp(source.normalized(),influence)
	if pole.length_squared()<0.001: pole=Vector3.RIGHT-direction*direction.x
	var previous: Vector3 = _knee_poles[side]
	pole=previous.lerp(pole.normalized(),1.0-exp(-18.0*_frame_delta))
	pole-=direction*pole.dot(direction)
	pole = pole.normalized()
	_knee_poles[side]=pole
	var joint: Vector3 = h+direction*projection+pole*sqrt(maxf(0.0,upper*upper-projection*projection))
	_aim_exact(sk,_hips[side],_knees[side],joint-h)
	k = sk.get_bone_global_pose(_knees[side]).origin
	_aim_exact(sk,_knees[side],_feet[side],effective-k)
	var parent: int = sk.get_bone_parent(_feet[side])
	sk.set_bone_pose_rotation(_feet[side],(sk.get_bone_global_pose(parent).basis.inverse()*foot_basis).get_rotation_quaternion())
	sk.set_bone_pose_rotation(_toe_bones[side],Quaternion.IDENTITY)


func _world_offset(person, orientation: Basis, offset: Vector3) -> Vector3:
	var basis: Basis = person.skel.global_basis
	return basis*(basis.orthonormalized().inverse()*orientation*offset)


func _support_offset(person, side: int, orientation: Basis) -> Vector3:
	var basis: Basis = person.skel.global_basis
	var effective: Basis = basis*basis.orthonormalized().inverse()*orientation
	var lowest := INF
	var result: Vector3 = _sole_offsets[side]
	for point in _sole_hulls[side]:
		var height: float = (effective*(point as Vector3)).y
		if height<lowest-0.0000001:
			lowest=height
			result=point
	return result


func _aim_exact(sk: Skeleton3D, bone: int, child: int, direction: Vector3) -> void:
	var pose: Transform3D = sk.get_bone_global_pose(bone)
	var current: Vector3 = (sk.get_bone_global_pose(child).origin-pose.origin).normalized()
	var wanted := direction.normalized()
	if current.distance_squared_to(wanted)<0.000000000001: return
	var parent: Transform3D = sk.get_bone_global_pose(sk.get_bone_parent(bone))
	var local: Basis = parent.basis.inverse()*Basis(Quaternion(current,wanted))*pose.basis
	sk.set_bone_pose_rotation(bone,local.get_rotation_quaternion())


func _rigid_shoe_sole(shoes: MeshInstance3D) -> void:
	# The imported sole includes calf weights (up to 68%), which folds the
	# bottom through the floor. Repair only this player's private mesh in memory.
	var private_mesh := ArrayMesh.new()
	var feet: Array[int] = [-1,-1]
	for bind in shoes.skin.get_bind_count():
		var name: String = String(shoes.skin.get_bind_name(bind))
		if name=="foot_l": feet[0]=bind
		elif name=="foot_r": feet[1]=bind
	for surface in shoes.mesh.get_surface_count():
		var arrays: Array = shoes.mesh.surface_get_arrays(surface).duplicate(true)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var count: int = bones.size()/vertices.size()
		var low := INF
		for point in vertices: low=minf(low,point.y)
		for vertex in vertices.size():
			var blend: float = 1.0-smoothstep(low+0.035,low+0.070,vertices[vertex].y)
			if blend<=0.0: continue
			var foot: int = feet[0 if vertices[vertex].x>0.0 else 1]
			if foot<0: continue
			var slot := -1
			var highest := -1.0
			var replace := 0
			for influence in count:
				var index: int = vertex*count+influence
				if bones[index]==foot: slot=index
				if weights[index]>highest:
					highest=weights[index]
					replace=index
				weights[index] *= 1.0-blend
			if slot<0:
				slot=replace
				blend+=weights[slot]
				weights[slot]=0.0
				bones[slot]=foot
			weights[slot]+=blend
		arrays[Mesh.ARRAY_BONES]=bones
		arrays[Mesh.ARRAY_WEIGHTS]=weights
		private_mesh.add_surface_from_arrays(shoes.mesh.surface_get_primitive_type(surface),arrays)
		private_mesh.surface_set_material(surface,shoes.mesh.surface_get_material(surface))
	shoes.mesh=private_mesh


func visual_floor_height(person: Node3D, at: Vector3, physical_y: float) -> float:
	if not _vf_resolved:
		_vf_resolved = true
		var node: Node = person
		while node != null:
			for property in node.get_property_list():
				if str(property["name"]) == "city":
					var city: Variant = node.get("city")
					if city is Node3D and is_instance_valid(city): _vf_city = weakref(city)
					break
			if _vf_city != null: break
			node = node.get_parent()
	if _vf_city == null or _vf_city.get_ref() == null: return physical_y
	var now := Time.get_ticks_msec()
	if now >= _vf_next_ms or _vf_center == Vector3.INF or Vector2(at.x-_vf_center.x,at.z-_vf_center.z).length() > VF_RADIUS*0.5:
		_vf_refresh(at, physical_y)
	_vf_last_hit = {"source":"physical_fallback","y":physical_y,"base_y":physical_y,"overlay_gap":0.0,"component_area":0.0}
	var base_y := -INF
	var base_record: Array = []
	var candidates: Array = []
	var ceiling: float = minf(physical_y+0.12,person.global_position.y+0.12)
	var key := Vector2i(floori(at.x/VF_CELL),floori(at.z/VF_CELL))
	for triangle in _vf_cells.get(key, []):
		var owner: MeshInstance3D = triangle[4].get_ref()
		if owner == null: continue
		if not owner.is_visible_in_tree():
			_vf_next_ms = 0
			continue
		if owner.mesh == null or owner.mesh.get_instance_id() != triangle[6] or owner.global_transform != triangle[5]:
			# Moving small props are not a floor base; they must not rebuild all
			# nearby floor geometry on every traffic/ambient animation frame.
			if float(triangle[9])>=4.0: _vf_next_ms = 0
			continue
		if not _vf_opaque(owner.get_active_material(triangle[7])): continue
		var a: Vector3 = triangle[0]; var b: Vector3 = triangle[1]; var c: Vector3 = triangle[2]
		var det: float = (b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z)
		if absf(det) < 0.00000001: continue
		var u: float = ((b.z-c.z)*(at.x-c.x)+(c.x-b.x)*(at.z-c.z))/det
		var v: float = ((c.z-a.z)*(at.x-c.x)+(a.x-c.x)*(at.z-c.z))/det
		if u < -0.00001 or v < -0.00001 or u+v > 1.00001: continue
		var y: float = u*a.y+v*b.y+(1.0-u-v)*c.y
		if y < physical_y-0.25 or y > ceiling: continue
		candidates.append([triangle,y])
		# Geometry heuristic, not a category-height table: a floor must be a
		# broad connected coplanar patch. Tiny shoes/debris cannot become its base.
		if float(triangle[9]) >= 4.0-0.00001 and y > base_y:
			base_y = y
			base_record = triangle
	if not is_finite(base_y):
		_vf_last_hit["reason"] = "no_broad_coplanar_patch"
		return physical_y
	var best: float = base_y
	var selected: Array = base_record
	for candidate in candidates:
		var y: float = candidate[1]
		# Existing tiles/boards/rugs/paint remain eligible as thin overlays on
		# an actual broad base. Relative thickness is not a world/category Y.
		if y > best and y <= base_y+0.020001:
			best = y
			selected = candidate[0]
	var owner: MeshInstance3D = selected[4].get_ref()
	_vf_last_hit = {"source":"render_floor_component","owner":str(owner.get_path()),"surface":selected[7],"component":selected[8],"component_area":selected[9],"base_component_area":base_record[9],"base_y":base_y,"overlay_gap":best-base_y,"y":best}
	return best

func _vf_opaque(material: Material) -> bool:
	if material == null: return true # default Godot material
	if material is BaseMaterial3D:
		return material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
	# Shader opacity/vertex displacement cannot be inferred safely here.
	return false

func _vf_refresh(center: Vector3, physical_y: float) -> void:
	var started := Time.get_ticks_usec()
	_vf_center = center
	_vf_next_ms = Time.get_ticks_msec()+2000
	_vf_cells.clear()
	for id in _vf_meshes.keys():
		if _vf_meshes[id]["ref"].get_ref() == null: _vf_meshes.erase(id)
	for id in _vf_instances.keys():
		if _vf_instances[id]["ref"].get_ref() == null: _vf_instances.erase(id)
	var region := AABB(Vector3(center.x-VF_RADIUS,physical_y-0.25,center.z-VF_RADIUS),Vector3(VF_RADIUS*2.0,0.37,VF_RADIUS*2.0))
	var pending: Array[Node] = [_vf_city.get_ref()]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children(): pending.append(child)
		if not node is MeshInstance3D: continue
		var owner := node as MeshInstance3D
		if owner.mesh == null or owner.skin != null or not owner.is_visible_in_tree(): continue
		var xf := owner.global_transform
		if absf(xf.basis.determinant()) < 0.00000001: continue
		var mesh := owner.mesh
		var rid := mesh.get_instance_id()
		var iid := owner.get_instance_id()
		var cached: Dictionary = _vf_instances.get(iid,{})
		if cached.is_empty() or cached["rid"] != rid or cached["xf"] != xf:
			cached = {"ref":weakref(owner),"rid":rid,"xf":xf,"box":xf*owner.get_aabb()}
			_vf_instances[iid] = cached
		if not (cached["box"] as AABB).intersects(region): continue
		var local_region: AABB = xf.affine_inverse()*region
		if not _vf_meshes.has(rid):
			_vf_meshes[rid] = {"ref":weakref(mesh)}
			# Weak callback avoids keeping a freed player/helper alive.
			var helper_ref: WeakRef = weakref(self)
			mesh.changed.connect(func():
				var helper = helper_ref.get_ref()
				if helper != null: helper._vf_mesh_changed(rid)
			, CONNECT_ONE_SHOT)
		if not cached.has("triangles") or absf(float(cached["floor_y"])-physical_y)>0.04:
			# Parse only upward surfaces in the floor height band. Roofs, walls,
			# furniture tops and tree canopies used to be grouped unnecessarily.
			cached["triangles"]=_vf_extract(owner,xf,physical_y-0.29,physical_y+0.16)
			cached["floor_y"]=physical_y
			cached["component_areas"] = _vf_component_world_areas(cached["triangles"],xf)
		var component_areas: Dictionary = cached["component_areas"]
		var normal_xf := xf.basis.inverse().transposed()
		for local in cached["triangles"]:
			if not (local[4] as AABB).intersects(local_region): continue
			if not _vf_opaque(owner.get_active_material(local[5])): continue
			var normal: Vector3 = (normal_xf*(local[3] as Vector3)).normalized()
			if normal.y < 0.995: continue
			var a: Vector3 = xf*(local[0] as Vector3); var b: Vector3 = xf*(local[1] as Vector3); var c: Vector3 = xf*(local[2] as Vector3)
			var lo := Vector2(maxf(region.position.x,minf(a.x,minf(b.x,c.x))),maxf(region.position.z,minf(a.z,minf(b.z,c.z))))
			var hi := Vector2(minf(region.end.x,maxf(a.x,maxf(b.x,c.x))),minf(region.end.z,maxf(a.z,maxf(b.z,c.z))))
			var record: Array = [a,b,c,normal,cached["ref"],xf,rid,local[5],local[6],float(component_areas.get(int(local[6]),0.0))]
			for x in range(floori(lo.x/VF_CELL),floori(hi.x/VF_CELL)+1):
				for z in range(floori(lo.y/VF_CELL),floori(hi.y/VF_CELL)+1):
					var cell := Vector2i(x,z)
					if not _vf_cells.has(cell): _vf_cells[cell] = []
					_vf_cells[cell].append(record)

	_vf_refresh_count += 1
	_vf_refresh_max_us = maxi(_vf_refresh_max_us,Time.get_ticks_usec()-started)

func _vf_mesh_changed(rid: int) -> void:
	_vf_meshes.erase(rid)
	_vf_instances.clear()
	_vf_next_ms = 0

func _vf_extract(owner: MeshInstance3D, xf: Transform3D, min_y: float, max_y: float) -> Array:
	var triangles: Array = []
	var mesh: Mesh=owner.mesh
	var normal_xf: Basis=xf.basis.inverse().transposed()
	for surface in mesh.get_surface_count():
		if not _vf_opaque(owner.get_active_material(surface)): continue
		if mesh is ArrayMesh:
			if (mesh as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
		elif not mesh is PrimitiveMesh: continue
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var count: int = vertices.size() if indices.is_empty() else indices.size()
		for start in range(0,count-2,3):
			var ia: int = start if indices.is_empty() else indices[start]
			var ib: int = start+1 if indices.is_empty() else indices[start+1]
			var ic: int = start+2 if indices.is_empty() else indices[start+2]
			var a := vertices[ia]; var b := vertices[ib]; var c := vertices[ic]
			# Normals are authoritative; fallback respects Godot clockwise winding.
			var normal: Vector3 = (normals[ia]+normals[ib]+normals[ic]).normalized() if normals.size()==vertices.size() else (c-a).cross(b-a).normalized()
			if (normal_xf*normal).normalized().y<0.995: continue
			var ay: float=(xf*a).y; var by: float=(xf*b).y; var cy: float=(xf*c).y
			if minf(ay,minf(by,cy))>max_y or maxf(ay,maxf(by,cy))<min_y: continue
			var box := AABB(a,Vector3.ZERO).expand(b).expand(c).grow(0.00001)
			triangles.append([a,b,c,normal,box,surface])
	_vf_group_components(triangles)
	return triangles


# Union of coplanar triangles sharing welded vertices (including tiled corners).
# Resource-local grouping is reusable; each instance computes projected world
# area from transformed edges, so nonuniform scales are handled explicitly.
func _vf_group_components(triangles: Array) -> void:
	var parents: Array[int] = []
	var ranks: Array[int] = []
	parents.resize(triangles.size())
	ranks.resize(triangles.size())
	var joined: Dictionary = {}
	for index in triangles.size():
		parents[index] = index
		ranks[index] = 0
		var row: Array = triangles[index]
		var a: Vector3 = row[0]; var b: Vector3 = row[1]; var c: Vector3 = row[2]
		var geometric: Vector3 = (b-a).cross(c-a)
		if geometric.length_squared() < 0.000000000001: continue
		var normal: Vector3 = geometric.normalized()
		if normal.dot(row[3]) < 0.0: normal = -normal
		var normal_key := Vector3i(roundi(normal.x/0.0001),roundi(normal.y/0.0001),roundi(normal.z/0.0001))
		var plane := "%s/%d/%d" % [str(normal_key),roundi(normal.dot(a)/0.0005),int(row[5])]
		for vertex in [a,b,c]:
			var point: Vector3 = vertex
			var weld := Vector3i(roundi(point.x/0.0005),roundi(point.y/0.0005),roundi(point.z/0.0005))
			var key: String = plane+"/"+str(weld)
			if joined.has(key):
				_vf_component_union(parents,ranks,index,int(joined[key]))
			else:
				joined[key] = index
	for index in triangles.size():
		(triangles[index] as Array).append(_vf_component_find(parents,index))

func _vf_component_find(parents: Array[int], index: int) -> int:
	var root: int = index
	while parents[root] != root: root = parents[root]
	while parents[index] != index:
		var next: int = parents[index]
		parents[index] = root
		index = next
	return root

func _vf_component_union(parents: Array[int], ranks: Array[int], a: int, b: int) -> void:
	var ra: int = _vf_component_find(parents,a)
	var rb: int = _vf_component_find(parents,b)
	if ra == rb: return
	if ranks[ra] < ranks[rb]:
		parents[ra] = rb
	else:
		parents[rb] = ra
		if ranks[ra] == ranks[rb]: ranks[ra] += 1

func _vf_component_world_areas(triangles: Array, xf: Transform3D) -> Dictionary:
	var result: Dictionary = {}
	var normal_xf: Basis = xf.basis.inverse().transposed()
	for row in triangles:
		var normal: Vector3 = (normal_xf*(row[3] as Vector3)).normalized()
		if normal.y < 0.995: continue
		var ab: Vector3 = xf.basis*((row[1] as Vector3)-(row[0] as Vector3))
		var ac: Vector3 = xf.basis*((row[2] as Vector3)-(row[0] as Vector3))
		var area: float = absf(ab.cross(ac).y)*0.5
		var component: int = row[6]
		result[component] = float(result.get(component,0.0))+area
	return result
