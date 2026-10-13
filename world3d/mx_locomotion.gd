extends RefCounted

# Locomoção por captura de movimento (Mixamo) com casamento por distância:
# - ciclos andar/trotar/correr em fase única; a fase avança pela distância física real,
#   então o pé de apoio não escorrega em nenhuma velocidade;
# - arrancada: o clipe avança conforme a distância já percorrida;
# - parada: entra no quadro cuja distância restante e posição dos pés casam com o momento;
# - giro parado: o clipe de giro avança conforme o ângulo girado (passinhos no lugar).
# Só visual: cápsula, navegação, IA e save não mudam.

const MixamoBank = preload("res://world3d/mixamo_bank.gd")

var mocap := true
var prototype := false
var tree: AnimationTree
var active := false
var phase := 0.0
var pace := 0.0
var move_weight := 0.0
var run_weight := 0.0
var current_rate := 1.0
var walk_clip := "mx/walk"
var run_clip := "mx/run"
var walk_distance := 1.68
var run_distance := 2.7
var state := "idle"
var cycle_length := 1.68
var _idle_offset := 0.0

var _gaits: Array = []        # [{name, cycle(m), speed(m/s)}] em ordem de velocidade
var _tr: Dictionary = {}
var _start := "start"
var _stop := "stop"
var _clip := ""
var _clip_t := 0.0
var _clip_len := 1.0
var _trans_w := 0.0
var _trans_goal := 0.0
var _move_goal := 0.0
var _travel := 0.0
var _speed_s := 0.0
var _prev_s := 0.0
var _accel := 0.0
var _prev_yaw := INF
var _yaw_rate := 0.0
var _turn_acc := 0.0
var _turn_quiet := 0.0
var _ground_y := 0.0
var _bank := 0.0
var _blend := 0.0
var _feet: Array[int] = []
# folga dos braços: o Mixamo é magro; no corpo largo (peito, quadril, braço grosso) o braço
# da captura entrava no tronco. Medida por quadro e corrigida abrindo o ombro.
var _chest_half := 0.18
var _hip_half := 0.18
var _arm_r := 0.045
var _forearm_r := 0.035
var _arms: Array = []
var _soles: Array[Vector3] = [Vector3(0, -0.067, 0.137), Vector3(0, -0.067, 0.137)]
var _shoe_points: Array = []


static func load_library(body_path: String, skel: Skeleton3D) -> AnimationLibrary:
	return MixamoBank.library_for(body_path, skel)


func setup(person, lib: AnimationLibrary, body_path: String) -> void:
	person.ap.add_animation_library("mx", lib)
	var female := body_path.get_file().begins_with("Human_female")
	var s: float = person.scale.z
	var gaits: Dictionary = lib.get_meta("gaits")
	_tr = lib.get_meta("transitions")
	var walk_name := "walk_f" if female else "walk"
	_start = "start_f" if female else "start"
	_stop = "stop_f" if female else "stop"
	for name in [walk_name, "jog", "run"]:
		var g: Dictionary = gaits[name]
		_gaits.append({"name": name, "cycle": float(g["cycle"]) * s, "speed": float(g["cycle"]) * s / float(g["duration"])})
	walk_clip = "mx/" + walk_name
	walk_distance = _gaits[0]["cycle"]
	run_distance = _gaits[2]["cycle"]
	phase = fposmod(person.seed_n * 0.017, 1.0)
	for side in ["l", "r"]:
		_feet.append(person.skel.find_bone("foot_" + side))
	_measure_soles(person)
	var sk: Skeleton3D = person.skel
	var bt: Dictionary = person.BODY_TYPES[clampi(int(person.look.get("body_type", 1)), 0, person.BODY_TYPES.size() - 1)]
	var shoulder_x := absf(sk.get_bone_global_rest(sk.find_bone("upperarm_l")).origin.x)
	var thigh_x := absf(sk.get_bone_global_rest(sk.find_bone("thigh_l")).origin.x)
	_chest_half = shoulder_x * 0.8 * float(bt.get("chest_x", 1.0))
	_hip_half = thigh_x * 1.75 * float(bt.get("hip_x", 1.0)) * maxf(1.0, float(bt.get("waist_x", 1.0)))
	_arm_r = 0.045 * float(bt.get("arm", 1.0))
	_forearm_r = 0.035 * float(bt.get("forearm", 1.0))
	for side in [["l", 1.0], ["r", -1.0]]:
		_arms.append([sk.find_bone("upperarm_" + side[0]), sk.find_bone("lowerarm_" + side[0]), sk.find_bone("hand_" + side[0]), float(side[1])])

	var space := AnimationNodeBlendSpace1D.new()
	space.min_space = 0.0
	space.max_space = 2.0
	space.sync = true
	for i in 3:
		var node := AnimationNodeAnimation.new()
		node.animation = "mx/" + str(_gaits[i]["name"])
		space.add_blend_point(node, float(i), -1, str(_gaits[i]["name"]))
	var graph := AnimationNodeBlendTree.new()
	graph.add_node("Gait", space)
	graph.add_node("GaitScale", AnimationNodeTimeScale.new())
	graph.add_node("GaitSeek", AnimationNodeTimeSeek.new())
	graph.connect_node("GaitScale", 0, "Gait")
	graph.connect_node("GaitSeek", 0, "GaitScale")
	var trans := AnimationNodeAnimation.new()
	trans.animation = "mx/" + _stop
	graph.add_node("Trans", trans)
	graph.add_node("TransScale", AnimationNodeTimeScale.new())
	graph.add_node("TransSeek", AnimationNodeTimeSeek.new())
	graph.connect_node("TransScale", 0, "Trans")
	graph.connect_node("TransSeek", 0, "TransScale")
	var idle := AnimationNodeAnimation.new()
	idle.animation = "mx/idle"
	graph.add_node("IdleClip", idle)
	graph.add_node("Idle", AnimationNodeTimeSeek.new())
	graph.connect_node("Idle", 0, "IdleClip")
	_idle_offset = fposmod(person.seed_n * 0.37, 9.0)
	graph.add_node("Mix", AnimationNodeBlend2.new())
	graph.connect_node("Mix", 0, "GaitSeek")
	graph.connect_node("Mix", 1, "TransSeek")
	graph.add_node("Body", AnimationNodeBlend2.new())
	graph.connect_node("Body", 0, "Idle")
	graph.connect_node("Body", 1, "Mix")
	graph.connect_node("output", 0, "Body")
	tree = AnimationTree.new()
	tree.name = "Locomotion"
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
	_trans_w = 0.0
	state = "idle"
	_ground_y = 0.0
	_speed_s = 0.0
	_prev_s = 0.0
	_prev_yaw = INF
	person.model.position.y = 0.0


# ---------------------------------------------------------------- utilidades das curvas

static func _time_at(values: Array, value: float, length: float) -> float:
	var last := values.size() - 1
	if last <= 0:
		return 0.0
	for i in last:
		var a: float = values[i]
		var b: float = values[i + 1]
		if (value >= a and value <= b) or (value <= a and value >= b):
			var u := 0.0 if is_equal_approx(a, b) else (value - a) / (b - a)
			return (i + u) * length / last
	return length if absf(value) >= absf(float(values[last])) else 0.0


static func _value_at(values: Array, time: float, length: float) -> float:
	var last := values.size() - 1
	var x := clampf(time / maxf(length, 0.001), 0.0, 1.0) * last
	var i := mini(int(x), last - 1)
	return lerpf(float(values[i]), float(values[i + 1]), x - i)


static func _phase_gap(a: float, b: float) -> float:
	var d := absf(fposmod(a - b, 1.0))
	return minf(d, 1.0 - d)


func _play(name: String, time: float) -> void:
	if _clip != name:
		_clip = name
		(tree.tree_root.get_node("Trans") as AnimationNodeAnimation).animation = "mx/" + name
		_clip_len = float(_tr[name]["length"])
	_clip_t = clampf(time, 0.0, _clip_len)


# ---------------------------------------------------------------- quadro a quadro

func step(person, delta: float) -> void:
	if not active:
		person.ap.stop()
		tree.active = true
		active = true
		state = "idle"
		tree.set("parameters/GaitSeek/seek_request", phase)
		# cada pessoa respira no seu próprio tempo
		tree.set("parameters/Idle/seek_request", _idle_offset)
	var dt := maxf(delta, 0.0001)
	var raw: float = person._speed
	_speed_s = lerpf(_speed_s, raw, 1.0 - exp(-14.0 * dt))
	if raw <= 0.001 and _speed_s < 0.03:
		_speed_s = 0.0
	var speed := _speed_s
	_accel = lerpf(_accel, (speed - _prev_s) / dt, 1.0 - exp(-10.0 * dt))
	_prev_s = speed
	var yaw: float = person.rotation.y
	# Girar a prévia no criador é uma rotação de apresentação, não uma ordem de marcha.
	var rate := 0.0 if _prev_yaw == INF or not person.locomotion_turns else angle_difference(_prev_yaw, yaw) / dt
	_prev_yaw = yaw
	_yaw_rate = lerpf(_yaw_rate, clampf(rate, -12.0, 12.0), 1.0 - exp(-16.0 * dt))

	# mistura de marcha pela velocidade real (0 = andar, 1 = trotar, 2 = correr)
	# A caminhada cobre até 35% acima do ritmo natural (só cadência); depois entra o trote.
	var target_blend := 0.0
	var v0: float = float(_gaits[0]["speed"]) * 1.35
	if speed > v0:
		var v1: float = maxf(float(_gaits[1]["speed"]) * 1.2, v0 + 0.35)
		var v2: float = float(_gaits[2]["speed"]) * 0.85
		target_blend = clampf((speed - v0) / (v1 - v0), 0.0, 1.0) if speed < v1 else 1.0 + clampf((speed - v1) / (v2 - v1), 0.0, 1.0)
	_blend = move_toward(_blend, target_blend, dt * 3.0)
	run_weight = clampf(_blend - 1.0, 0.0, 1.0)
	var lo := mini(int(floor(_blend)), 1)
	var u := _blend - lo
	var cycle: float = lerpf(float(_gaits[lo]["cycle"]), float(_gaits[lo + 1]["cycle"]), u)
	pace = speed / maxf(cycle, 0.1)
	cycle_length = cycle

	match state:
		"idle":
			_move_goal = 0.0
			_trans_goal = 0.0
			if raw > 0.05:
				if speed < 2.4 and not person.running and _tr.has(_start):
					state = "start"
					_travel = 0.0
					_play(_start, 0.0)
					_trans_w = 1.0
				else:
					state = "move"
			elif absf(_yaw_rate) > 1.4 and move_weight < 0.5:
				state = "turn"
				_turn_acc = 0.0
				_turn_quiet = 0.0
				_play("turn_l" if _yaw_rate > 0.0 else "turn_r", 0.0)
				_trans_w = 1.0
		"start":
			_move_goal = 1.0
			_trans_goal = 1.0
			_travel += raw * dt
			var dist: Array = _tr[_start]["dist"]
			_play(_start, _time_at(dist, _travel / maxf(person.scale.z, 0.1), _clip_len))
			phase = _value_at(_tr[_start]["phase"], _clip_t, _clip_len)
			if _clip_t >= _clip_len - 0.4 or speed > 2.4 or person.running:
				state = "move"
			elif raw <= 0.01:
				_enter_stop(person, speed, true)
		"move":
			_move_goal = 1.0
			_trans_goal = 0.0
			phase = fposmod(phase + dt * pace, 1.0)
			var braking := _accel < -1.2 and speed < float(_gaits[1]["speed"]) * 1.6
			if raw <= 0.01 and speed > 0.05:
				_enter_stop(person, speed, true)
			elif braking:
				var rem := speed * speed / (2.0 * maxf(-_accel, 1.0))
				var stop_name := "run_stop" if run_weight > 0.4 else _stop
				var total: float = float(_tr[stop_name]["dist"][-1]) * person.scale.z
				if rem <= total * 0.85:
					_enter_stop(person, speed, false)
			elif speed < 0.04:
				state = "idle"
		"stop":
			_move_goal = 1.0
			_trans_goal = 1.0
			if raw > 0.08 and _accel > 0.6:
				state = "move"
			else:
				var dist: Array = _tr[_clip]["dist"]
				var total: float = float(dist[-1])
				var natural := _clip_t + dt
				if raw > 0.02:
					var rem := speed * speed / (2.0 * maxf(-_accel, 1.5)) / maxf(person.scale.z, 0.1)
					var by_distance := _time_at(dist, total - rem, _clip_len)
					natural = clampf(by_distance, _clip_t, _clip_t + dt * 2.0)
				_play(_clip, natural)
				phase = fposmod(phase + dt * pace, 1.0)
				if _clip_t >= _clip_len - 0.02:
					state = "idle"
		"turn":
			_move_goal = 1.0
			_trans_goal = 1.0
			if raw > 0.08:
				state = "move"
			else:
				var yaw_curve: Array = _tr[_clip]["yaw"]
				var total_yaw: float = absf(float(yaw_curve[-1]))
				var turning := absf(_yaw_rate) > 0.5
				if turning:
					_turn_quiet = 0.0
					_turn_acc += absf(_yaw_rate) * dt
					if _turn_acc > total_yaw * 0.92:
						_turn_acc -= total_yaw * 0.6
					var signed := _turn_acc * signf(float(yaw_curve[-1]))
					_play(_clip, maxf(_clip_t, _time_at(yaw_curve, signed, _clip_len)) if _turn_acc > 0.05 else _clip_t + dt)
				else:
					_turn_quiet += dt
					_play(_clip, _clip_t + dt * 1.4)
				if _clip_t >= _clip_len - 0.02 or _turn_quiet > 0.5:
					state = "idle"

	# pesos com transições curtas (aprox. 0,2 s)
	move_weight = move_toward(move_weight, _move_goal if speed > 0.02 or state != "idle" else 0.0, dt / 0.22)
	if state == "idle" and speed > 0.02:
		move_weight = move_toward(move_weight, 1.0, dt / 0.22)
	_trans_w = move_toward(_trans_w, _trans_goal, dt / 0.22)
	tree.set("parameters/Gait/blend_position", _blend)
	tree.set("parameters/GaitScale/scale", 0.0)
	tree.set("parameters/GaitSeek/seek_request", phase)
	tree.set("parameters/TransScale/scale", 0.0)
	tree.set("parameters/TransSeek/seek_request", _clip_t)
	tree.set("parameters/Mix/blend_amount", _trans_w)
	tree.set("parameters/Body/blend_amount", move_weight)
	tree.advance(delta)
	var gait_clip := walk_clip if _blend < 0.5 else ("mx/jog" if _blend < 1.5 else run_clip)
	person._cur_anim = (gait_clip if _trans_w < 0.5 else "mx/" + _clip) if move_weight > 0.01 else "Idle"
	current_rate = pace
	person.ap.speed_scale = 1.0


func _enter_stop(person, speed: float, abrupt: bool) -> void:
	var name := "run_stop" if run_weight > 0.4 else _stop
	if not _tr.has(name):
		state = "idle"
		return
	var dist: Array = _tr[name]["dist"]
	var phases: Array = _tr[name]["phase"]
	var total: float = float(dist[-1])
	var rem := 0.12 if abrupt else speed * speed / (2.0 * maxf(-_accel, 1.5)) / maxf(person.scale.z, 0.1)
	# Entra no quadro cujo resto de distância e posição dos pés casam com o agora.
	var best := 0
	var best_cost := INF
	var last := dist.size() - 1
	for f in last:
		var left: float = total - float(dist[f])
		if left < 0.02 and f > 0:
			break
		var cost := absf(left - rem)
		if name != "run_stop":
			cost += _phase_gap(float(phases[f]), phase) * 2.5
		if cost < best_cost:
			best_cost = cost
			best = f
	state = "stop"
	_clip = ""
	_play(name, float(best) * float(_tr[name]["length"]) / last)


# Pelve em curvas: o corpo inclina para dentro da curva como numa caminhada real.
func dynamics(person, delta: float) -> void:
	_stand_tall(person)
	_arm_clearance(person)
	var target := clampf(-_yaw_rate * _speed_s * 0.02, -0.16, 0.16) * move_weight * (1.0 - _trans_w)
	_bank = lerpf(_bank, target, 1.0 - exp(-8.0 * maxf(delta, 0.0001)))
	if absf(_bank) < 0.002:
		return
	var sk: Skeleton3D = person.skel
	var total := Basis(Vector3.BACK, _bank)
	for entry in [["spine_01", 0.35], ["spine_02", 0.35], ["spine_03", 0.3]]:
		_rotate_global(sk, sk.find_bone(entry[0]), Basis.IDENTITY.slerp(total, entry[1]))
	_rotate_global(sk, person._head, Basis.IDENTITY.slerp(total.inverse(), 0.7))


# O clipe de repouso flexiona os joelhos ~35° no rig alvo. Mantém 14° de flexão,
# pé/tornozelo fixos e sola neutra; o tronco já vem corrigido pelo retarget axial.
func _stand_tall(person) -> void:
	var w := (1.0 - move_weight) * (1.0 - _trans_w)
	if w < 0.01:
		return
	var sk: Skeleton3D = person.skel
	var pelvis := sk.find_bone("pelvis")
	var legs: Array = []
	var lift := INF
	for side in ["l", "r"]:
		var th := sk.find_bone("thigh_" + side)
		var ca := sk.find_bone("calf_" + side)
		var ft := sk.find_bone("foot_" + side)
		var h: Vector3 = sk.get_bone_global_pose(th).origin
		var k: Vector3 = sk.get_bone_global_pose(ca).origin
		var a: Vector3 = sk.get_bone_global_pose(ft).origin
		var upper := h.distance_to(k)
		var lower := k.distance_to(a)
		var reach := sqrt(upper * upper + lower * lower - 2.0 * upper * lower * cos(deg_to_rad(166.0)))
		var flat := Vector2(h.x - a.x, h.z - a.z).length()
		var vmax := sqrt(maxf(reach * reach - flat * flat, 0.0))
		lift = minf(lift, vmax - (h.y - a.y))
		var rest_basis := sk.get_bone_global_rest(ft).basis
		var foot_delta := sk.get_bone_global_pose(ft).basis * rest_basis.inverse()
		var forward := foot_delta * Vector3.BACK
		var neutral_foot := Basis(Vector3.UP, atan2(forward.x, forward.z)) * rest_basis
		legs.append([th, ca, ft, a, k - h, sk.get_bone_global_pose(ft).basis.slerp(neutral_foot, w), upper, lower])
	if lift <= 0.002 or lift == INF:
		return
	lift = minf(lift, 0.14) * w
	var pp: Vector3 = sk.get_bone_pose_position(pelvis)
	var parent := sk.get_bone_parent(pelvis)
	var up_local := Vector3.UP if parent < 0 else sk.get_bone_global_pose(parent).basis.inverse() * Vector3.UP
	sk.set_bone_pose_position(pelvis, pp + up_local * lift)
	for leg in legs:
		var th: int = leg[0]
		var ca: int = leg[1]
		var ft: int = leg[2]
		var ankle: Vector3 = leg[3]
		var bend: Vector3 = leg[4]
		var foot_basis: Basis = leg[5]
		var a_len: float = leg[6]
		var b_len: float = leg[7]
		var h: Vector3 = sk.get_bone_global_pose(th).origin
		var to := ankle - h
		var d := clampf(to.length(), absf(a_len - b_len) + 0.001, a_len + b_len - 0.001)
		var dir := to.normalized()
		var proj := (a_len * a_len - b_len * b_len + d * d) / (2.0 * d)
		var pole := bend - dir * bend.dot(dir)
		if pole.length_squared() < 0.0001:
			pole = Vector3(0, 0, 1)
		pole = pole.normalized()
		var knee := h + dir * proj + pole * sqrt(maxf(a_len * a_len - proj * proj, 0.0))
		person._aim_bone(th, ca, knee - h)
		var kk: Vector3 = sk.get_bone_global_pose(ca).origin
		person._aim_bone(ca, ft, ankle - kk)
		sk.set_bone_pose_rotation(ft, (sk.get_bone_global_pose(ca).basis.inverse() * foot_basis).get_rotation_quaternion())


# Abre o ombro só o necessário para cotovelo e mão ficarem fora do tronco/quadril
# (apenas quando estão ao lado do corpo, não balançando à frente ou atrás).
func _arm_clearance(person) -> void:
	var sk: Skeleton3D = person.skel
	var spine: Vector3 = sk.get_bone_global_pose(sk.find_bone("spine_02")).origin
	for arm in _arms:
		var up: int = arm[0]
		var low: int = arm[1]
		var hand: int = arm[2]
		var side: float = arm[3]
		if up < 0 or low < 0 or hand < 0:
			continue
		var s: Vector3 = sk.get_bone_global_pose(up).origin
		var e: Vector3 = sk.get_bone_global_pose(low).origin
		var h: Vector3 = sk.get_bone_global_pose(hand).origin
		var need := 0.0
		var reach := 0.0
		if absf(e.z - spine.z) < 0.16:
			need = maxf(need, _chest_half + _arm_r - e.x * side)
			reach = s.distance_to(e)
		if absf(h.z - spine.z) < 0.14 and h.y < s.y - 0.25:
			var nh := _hip_half + _forearm_r - h.x * side
			if nh > need:
				need = nh
				reach = s.distance_to(h)
		if need <= 0.002 or reach < 0.05:
			continue
		var angle := asin(clampf(need / reach, 0.0, 0.6)) * side
		_rotate_global(sk, up, Basis(Vector3.BACK, angle))


func body(_person, _delta: float) -> void:
	pass


# Sai da parada por uma mistura suave para o repouso antes de alcançar um móvel.
func settle() -> void:
	state = "idle"
	_trans_goal = 0.0
	_move_goal = 0.0
	_speed_s = 0.0
	_prev_s = 0.0
	_clip = ""


# A sola pertence à malha equipada, não a um deslocamento fixo de outro rig.
func _measure_soles(person) -> void:
	var shoes: MeshInstance3D = person._human_parts.get("HumanShoes")
	if shoes == null:
		return
	var vertices: PackedVector3Array = shoes.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for side in 2:
		var rest: Transform3D = person.skel.get_bone_global_rest(_feet[side])
		var points: Array[Vector3] = []
		var min_y := INF
		for p in vertices:
			if (p.x > 0.0) != (side == 0):
				continue
			min_y = minf(min_y, p.y)
		var outline := PackedVector2Array()
		for p in vertices:
			if (p.x > 0.0) == (side == 0) and p.y < min_y + 0.012:
				outline.append(Vector2(p.x, p.z))
		for point in Geometry2D.convex_hull(outline):
			points.append(rest.affine_inverse() * Vector3(point.x, min_y, point.y))
		_shoe_points.append(points)


func _rotate_global(sk: Skeleton3D, bone: int, extra: Basis) -> void:
	if bone < 0:
		return
	var parent: int = sk.get_bone_parent(bone)
	if parent < 0:
		return
	var g: Transform3D = sk.get_bone_global_pose(bone)
	var pg: Transform3D = sk.get_bone_global_pose(parent)
	sk.set_bone_pose_rotation(bone, (pg.basis.inverse() * extra * g.basis).get_rotation_quaternion())


# Aterramento visual leve: corrige penetração/flutuação pequena do retarget.
func ground(person, delta: float) -> void:
	var low := INF
	for side in 2:
		var foot: Transform3D = person.skel.get_bone_global_pose(_feet[side])
		if _shoe_points.size() == 2:
			for point in _shoe_points[side]:
				low = minf(low, (foot * (point as Vector3)).y)
		else:
			low = minf(low, (foot * _soles[side]).y)
	var airborne := run_weight > 0.3 and move_weight > 0.5 and _trans_w < 0.5
	var target := clampf(-low, -0.15 if not airborne else 0.0, 0.10)
	_ground_y = maxf(target, move_toward(_ground_y, target, delta * 0.8))
	person.model.position.y = _ground_y
