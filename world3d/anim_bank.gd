extends RefCounted

# Traduz (retarget) as animações da Universal Animation Library, que usa um esqueleto "DEF-*",
# para o esqueleto dos corpos base da Quaternius. Faz isso uma vez por corpo: amostra a animação
# original quadro a quadro, calcula a rotação de cada osso no espaço do esqueleto e aplica o
# mesmo movimento ao outro esqueleto. Também mede a velocidade de cada passada.

const UAL := "res://assets/anim/ual.glb"
const FPS := 30.0
const SKEL_PATH := "Armature/Skeleton3D"

const WANTED := ["Idle", "Idle_Talking", "Walk", "Walk_Formal", "Jog_Fwd", "Sprint", "Death01", "Sitting_Idle", "Sitting_Enter", "Sitting_Exit", "Sitting_Talking",
	"Hit_Chest", "Hit_Head", "Punch_Jab", "Punch_Cross", "Interact", "PickUp_Table", "Crouch_Idle", "Crouch_Fwd", "Dance", "Push", "Jump_Start", "Jump", "Jump_Land", "Roll", "Idle_Torch", "Fixing_Kneeling"]
# posturas que duram (ficar sentado, agachado, ajoelhado, andar) precisam repetir sem parar
const LOOPED := ["Idle", "Idle_Talking", "Walk", "Walk_Formal", "Jog_Fwd", "Sprint", "Sitting_Idle", "Sitting_Talking", "Crouch_Idle", "Crouch_Fwd", "Fixing_Kneeling", "Dance", "Idle_Torch"]

const BONES := {
	"root": "root", "DEF-hips": "pelvis", "DEF-spine.001": "spine_01", "DEF-spine.002": "spine_02", "DEF-spine.003": "spine_03",
	"DEF-neck": "neck_01", "DEF-head": "Head",
	"DEF-shoulder.L": "clavicle_l", "DEF-upper_arm.L": "upperarm_l", "DEF-forearm.L": "lowerarm_l", "DEF-hand.L": "hand_l",
	"DEF-shoulder.R": "clavicle_r", "DEF-upper_arm.R": "upperarm_r", "DEF-forearm.R": "lowerarm_r", "DEF-hand.R": "hand_r",
	"DEF-thigh.L": "thigh_l", "DEF-shin.L": "calf_l", "DEF-foot.L": "foot_l", "DEF-toe.L": "ball_l",
	"DEF-thigh.R": "thigh_r", "DEF-shin.R": "calf_r", "DEF-foot.R": "foot_r", "DEF-toe.R": "ball_r",
}

static var _ual: Node
static var _libs: Dictionary = {}      # caminho do corpo -> {"lib": AnimationLibrary, "speed": {nome: m/s}}


# Solta o que fica guardado em variáveis estáticas, para o Godot não acusar recurso vazado ao fechar.
static func cleanup() -> void:
	if _ual != null and is_instance_valid(_ual):
		_ual.free()
	_ual = null
	_libs.clear()


static func _ual_nodes() -> Array:
	if _ual == null:
		_ual = (load(UAL) as PackedScene).instantiate()
	return [_ual.find_child("Skeleton3D", true, false), _ual.find_child("AnimationPlayer", true, false)]


static func _bone_pairs(us: Skeleton3D, cs: Skeleton3D) -> Dictionary:
	var pairs := {}
	for ub in BONES:
		pairs[ub] = BONES[ub]
	for side in ["L", "R"]:
		var sl: String = side.to_lower()
		for finger in ["index", "middle", "pinky", "ring"]:
			for n in [1, 2, 3]:
				pairs["DEF-f_%s.%02d.%s" % [finger, n, side]] = "%s_%02d_%s" % [finger, n, sl]
		for n in [1, 2, 3]:
			pairs["DEF-thumb.%02d.%s" % [n, side]] = "thumb_%02d_%s" % [n, sl]
	# só o que existe nos dois esqueletos
	var out := {}
	for ub in pairs:
		if us.find_bone(ub) >= 0 and cs.find_bone(pairs[ub]) >= 0:
			out[us.find_bone(ub)] = cs.find_bone(pairs[ub])
	return out


# Devolve {"lib": AnimationLibrary, "speed": Dictionary} para o esqueleto dado.
static func bank_for(body_path: String, cs: Skeleton3D) -> Dictionary:
	if _libs.has(body_path):
		return _libs[body_path]
	var nodes := _ual_nodes()
	var us: Skeleton3D = nodes[0]
	var ap: AnimationPlayer = nodes[1]
	var pair := _bone_pairs(us, cs)
	var lib := AnimationLibrary.new()
	var speeds := {}
	for name in WANTED:
		if not ap.has_animation(name):
			continue
		var res := _bake(ap.get_animation(name), us, cs, pair, name in ["Walk", "Walk_Formal", "Jog_Fwd", "Sprint", "Crouch_Fwd"])
		var baked: Animation = res["anim"]
		baked.loop_mode = Animation.LOOP_LINEAR if name in LOOPED else Animation.LOOP_NONE
		lib.add_animation(name, baked)
		if res["speed"] > 0.0:
			speeds[name] = res["speed"]
	var bank := {"lib": lib, "speed": speeds}
	_libs[body_path] = bank
	return bank


static func _bake(src: Animation, us: Skeleton3D, cs: Skeleton3D, pair: Dictionary, measure: bool) -> Dictionary:
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = src.loop_mode
	out.step = 1.0 / FPS
	# trilhas da animação original por osso
	var rot_t := {}
	var pos_t := {}
	for t in src.get_track_count():
		var bone := String(src.track_get_path(t).get_concatenated_subnames())
		var bi := us.find_bone(bone)
		if bi < 0:
			continue
		match src.track_get_type(t):
			Animation.TYPE_ROTATION_3D:
				rot_t[bi] = t
			Animation.TYPE_POSITION_3D:
				pos_t[bi] = t
	var ub_count := us.get_bone_count()
	var cb_count := cs.get_bone_count()
	var rest_u: Array = []
	var rest_g_u: Array = []
	for i in ub_count:
		rest_u.append(us.get_bone_rest(i))
		rest_g_u.append(us.get_bone_global_rest(i))
	var rest_c: Array = []
	var rest_g_c: Array = []
	for j in cb_count:
		rest_c.append(cs.get_bone_rest(j))
		rest_g_c.append(cs.get_bone_global_rest(j))
	var hip_u := us.find_bone("DEF-hips")
	var hip_c := cs.find_bone("pelvis")
	var hscale: float = float((rest_g_c[hip_c] as Transform3D).origin.y) / maxf(float((rest_g_u[hip_u] as Transform3D).origin.y), 0.01)
	# trilhas de saída
	var out_rot := {}
	for ui in pair:
		var cj: int = pair[ui]
		var ti := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(ti, NodePath("%s:%s" % [SKEL_PATH, cs.get_bone_name(cj)]))
		out_rot[cj] = ti
	var pos_track := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(pos_track, NodePath("%s:%s" % [SKEL_PATH, cs.get_bone_name(hip_c)]))
	var frames := int(ceil(src.length * FPS)) + 1
	var last_q := {}
	var foot_l := cs.find_bone("foot_l")
	var foot_r := cs.find_bone("foot_r")
	var feet_prev := [Vector3.ZERO, Vector3.ZERO]
	var dist_sum := 0.0
	var dist_n := 0
	for f in frames:
		var time := minf(float(f) / FPS, src.length)
		# pose global do esqueleto original
		var gu: Array = []
		gu.resize(ub_count)
		for i in ub_count:
			var rest: Transform3D = rest_u[i]
			var q: Quaternion = rest.basis.get_rotation_quaternion()
			var p: Vector3 = rest.origin
			if rot_t.has(i):
				q = src.rotation_track_interpolate(rot_t[i], time)
			if pos_t.has(i):
				p = src.position_track_interpolate(pos_t[i], time)
			var local := Transform3D(Basis(q), p)
			var par := us.get_bone_parent(i)
			gu[i] = (gu[par] as Transform3D) * local if par >= 0 else local
		# aplica ao esqueleto de destino
		var gc: Array = []
		gc.resize(cb_count)
		var inv_pair := {}
		for ui in pair:
			inv_pair[pair[ui]] = ui
		for j in cb_count:
			var par2 := cs.get_bone_parent(j)
			var rest2: Transform3D = rest_c[j]
			var parent_g: Transform3D = gc[par2] if par2 >= 0 else Transform3D.IDENTITY
			if inv_pair.has(j):
				var ui2: int = inv_pair[j]
				var delta: Basis = (gu[ui2] as Transform3D).basis * (rest_g_u[ui2] as Transform3D).basis.inverse()
				var gb: Basis = delta * (rest_g_c[j] as Transform3D).basis
				var local_q: Quaternion = (parent_g.basis.inverse() * gb).get_rotation_quaternion()
				if last_q.has(j) and (last_q[j] as Quaternion).dot(local_q) < 0.0:
					local_q = -local_q
				last_q[j] = local_q
				var org: Vector3 = parent_g * rest2.origin
				if j == hip_c:
					var dp: Vector3 = (gu[ui2] as Transform3D).origin - (rest_g_u[ui2] as Transform3D).origin
					org = (rest_g_c[j] as Transform3D).origin + dp * hscale
					out.position_track_insert_key(pos_track, time, parent_g.affine_inverse() * org)
				gc[j] = Transform3D(parent_g.basis * Basis(local_q), org)
				out.rotation_track_insert_key(out_rot[j], time, local_q)
			else:
				gc[j] = parent_g * rest2
		if measure:
			var fl: Vector3 = (gc[foot_l] as Transform3D).origin
			var fr: Vector3 = (gc[foot_r] as Transform3D).origin
			if f > 0:
				for k in 2:
					var cur: Vector3 = fl if k == 0 else fr
					var prev: Vector3 = feet_prev[k]
					if cur.y < 0.14 and prev.y < 0.14:
						dist_sum += -(cur.z - prev.z) * FPS
						dist_n += 1
			feet_prev = [fl, fr]
	return {"anim": out, "speed": (dist_sum / float(dist_n)) if dist_n > 0 else 0.0}
