extends RefCounted

# Converte os clipes de captura de movimento (Mixamo) para o esqueleto hm08 de cada corpo.
# Ciclos (andar/trotar/correr) viram exatamente UM ciclo de marcha, alinhado no apoio do pé
# esquerdo, com 1 s de duração: todos ficam em fase e podem ser misturados sem desencontro.
# O deslocamento da raiz é retirado e guardado como metadado (distância por ciclo, curva de
# distância das arrancadas/paradas e curva de ângulo dos giros), para casar animação com o
# deslocamento físico (distance matching) sem o pé escorregar.

const DIR := "res://assets/anim/mixamo/"
const FPS := 30.0
const SKEL_PATH := "Armature/Skeleton3D"
const LOOPS := {"walk": "walk.fbx", "walk_f": "walk_f.fbx", "jog": "jog.fbx", "run": "run.fbx"}
const STARTS := {"start": "walk_start.fbx", "start_f": "walk_start_f.fbx"}
const STOPS := {"stop": "walk_stop.fbx", "stop_f": "walk_stop_f.fbx", "run_stop": "run_stop.fbx"}
const TURNS := {"turn_l": "turn_l.fbx", "turn_r": "turn_r.fbx"}
const IDLES := {"idle": "idle.fbx"}
const VERSION := 6

const MAP := {
	"Hips": "pelvis", "Spine": "spine_01", "Spine1": "spine_02", "Spine2": "spine_03", "Neck": "neck_01", "Head": "Head",
	"LeftShoulder": "clavicle_l", "LeftArm": "upperarm_l", "LeftForeArm": "lowerarm_l", "LeftHand": "hand_l",
	"RightShoulder": "clavicle_r", "RightArm": "upperarm_r", "RightForeArm": "lowerarm_r", "RightHand": "hand_r",
	"LeftUpLeg": "thigh_l", "LeftLeg": "calf_l", "LeftFoot": "foot_l", "LeftToeBase": "ball_l",
	"RightUpLeg": "thigh_r", "RightLeg": "calf_r", "RightFoot": "foot_r", "RightToeBase": "ball_r",
}

static var _cache: Dictionary = {}


static func available() -> bool:
	return ResourceLoader.exists(DIR + "walk.fbx")


static func library_for(body_path: String, cs: Skeleton3D) -> AnimationLibrary:
	if _cache.has(body_path):
		return _cache[body_path]
	# O convertido (*_mx.res) basta; os .fbx crus do Mixamo não vão para o git (licença).
	var prepared := body_path.get_basename() + "_mx.res"
	if ResourceLoader.exists(prepared):
		var ready := load(prepared) as AnimationLibrary
		if ready != null and (int(ready.get_meta("version", 0)) == VERSION or not available()):
			_cache[body_path] = ready
			return ready
	if not available():
		return null
	var lib := bake(cs)
	_cache[body_path] = lib
	return lib


static func cleanup() -> void:
	_cache.clear()


# ---------------------------------------------------------------- amostragem da fonte

class Source:
	var sk: Skeleton3D
	var anim: Animation
	var rot := {}
	var pos := {}
	var rest: Array = []
	var rest_g: Array = []
	var root: Node

	func _init(file: String) -> void:
		root = (load(file) as PackedScene).instantiate()
		for node in root.find_children("*", "Skeleton3D", true, false):
			sk = node
		var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
		anim = ap.get_animation(ap.get_animation_list()[0])
		for t in anim.get_track_count():
			var bone := sk.find_bone(String(anim.track_get_path(t).get_concatenated_subnames()))
			if bone < 0:
				continue
			if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				rot[bone] = t
			elif anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
				pos[bone] = t
		for i in sk.get_bone_count():
			rest.append(sk.get_bone_rest(i))
			rest_g.append(sk.get_bone_global_rest(i))

	func bone(name: String) -> int:
		return sk.find_bone("mixamorig_" + name)

	func pose(time: float) -> Array:
		var out: Array = []
		out.resize(sk.get_bone_count())
		time = clampf(time, 0.0, anim.length)
		for i in sk.get_bone_count():
			var r: Transform3D = rest[i]
			var q: Quaternion = anim.rotation_track_interpolate(rot[i], time) if rot.has(i) else r.basis.get_rotation_quaternion()
			var p: Vector3 = anim.position_track_interpolate(pos[i], time) if pos.has(i) else r.origin
			var local := Transform3D(Basis(q), p)
			var parent := sk.get_bone_parent(i)
			out[i] = (out[parent] as Transform3D) * local if parent >= 0 else local
		return out

	func free_scene() -> void:
		root.free()


# ---------------------------------------------------------------- retarget

class Target:
	var cs: Skeleton3D
	var pairs := {}      # target bone -> source bone
	var corr := {}       # target bone -> Basis (C^-1 * T)
	var rest_g: Array = []
	var rest: Array = []
	var hip := -1
	var src_hip := -1
	var ratio := 1.0

	func _init(target: Skeleton3D, src: Source) -> void:
		cs = target
		for j in cs.get_bone_count():
			rest.append(cs.get_bone_rest(j))
			rest_g.append(cs.get_bone_global_rest(j))
		var names := MAP.duplicate()
		for side in [["Left", "l"], ["Right", "r"]]:
			for finger in [["Index", "index"], ["Middle", "middle"], ["Ring", "ring"], ["Pinky", "pinky"], ["Thumb", "thumb"]]:
				for n in [1, 2, 3]:
					names["%sHand%s%d" % [side[0], finger[0], n]] = "%s_%02d_%s" % [finger[1], n, side[1]]
		var tgt_of := {}
		for s in names:
			var si := src.bone(s)
			var tj := cs.find_bone(names[s])
			if si >= 0 and tj >= 0:
				pairs[tj] = si
				tgt_of[si] = tj
		# Transfere a rotação relativa ao repouso no espaço global comum dos rigs.
		# A correção pela direção do primeiro filho inclinava o tórax pela clavícula
		# e a pelve pela coxa: repouso da fonte já gerava peito estufado/joelhos dobrados.
		# Esta transformação garante: repouso da fonte -> repouso exato do alvo.
		for tj in pairs:
			var si: int = pairs[tj]
			var c := Basis.IDENTITY
			# Membros copiam a direção do segmento capturado; tronco/pelve/cabeça
			# preservam sua anatomia de repouso (não se orientam pela clavícula/coxa).
			if cs.get_bone_name(tj) not in ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head"]:
				for child in src.sk.get_bone_children(si):
					if tgt_of.has(child):
						var ds: Vector3 = (src.rest_g[child] as Transform3D).origin - (src.rest_g[si] as Transform3D).origin
						var dt: Vector3 = (rest_g[tgt_of[child]] as Transform3D).origin - (rest_g[tj] as Transform3D).origin
						if ds.length_squared() > 0.000001 and dt.length_squared() > 0.000001:
							c = Basis(Quaternion(ds.normalized(), dt.normalized()))
						break
			corr[tj] = (src.rest_g[si] as Transform3D).basis.orthonormalized().inverse() * c.inverse() * (rest_g[tj] as Transform3D).basis.orthonormalized()
		hip = cs.find_bone("pelvis")
		src_hip = src.bone("Hips")
		var src_leg := _leg(src.rest_g, src.bone("LeftUpLeg"), src.bone("LeftLeg"), src.bone("LeftFoot"))
		var tgt_leg := _leg(rest_g, cs.find_bone("thigh_l"), cs.find_bone("calf_l"), cs.find_bone("foot_l"))
		ratio = tgt_leg / maxf(src_leg, 0.01)

	static func _leg(g: Array, a: int, b: int, c: int) -> float:
		var pa: Vector3 = (g[a] as Transform3D).origin
		var pb: Vector3 = (g[b] as Transform3D).origin
		var pc: Vector3 = (g[c] as Transform3D).origin
		return pa.distance_to(pb) + pb.distance_to(pc)

	# Pose global da fonte -> rotações locais + posição da pelve no alvo.
	func solve(gu: Array, src_rest_hip: Vector3) -> Dictionary:
		var gc: Array = []
		gc.resize(cs.get_bone_count())
		var rots := {}
		var hip_pos := Vector3.ZERO
		for j in cs.get_bone_count():
			var parent := cs.get_bone_parent(j)
			var parent_g: Transform3D = gc[parent] if parent >= 0 else Transform3D.IDENTITY
			var r: Transform3D = rest[j]
			if pairs.has(j):
				var gb: Basis = (gu[pairs[j]] as Transform3D).basis.orthonormalized() * (corr[j] as Basis)
				var local_q: Quaternion = (parent_g.basis.orthonormalized().inverse() * gb).get_rotation_quaternion()
				var origin: Vector3 = parent_g * r.origin
				if j == hip:
					var dp: Vector3 = (gu[src_hip] as Transform3D).origin - src_rest_hip
					origin = (rest_g[j] as Transform3D).origin + dp * ratio
					hip_pos = parent_g.affine_inverse() * origin
				rots[j] = local_q
				gc[j] = Transform3D(parent_g.basis.orthonormalized() * Basis(local_q), origin)
			else:
				gc[j] = parent_g * r
		return {"rot": rots, "hip": hip_pos}


# ---------------------------------------------------------------- montagem dos clipes

static func bake(cs: Skeleton3D) -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.set_meta("version", VERSION)
	var target: Target = null
	var walk_ref: Array = []
	var gaits := {}
	for name in LOOPS:
		var src := Source.new(DIR + LOOPS[name])
		if target == null:
			target = Target.new(cs, src)
		var res := _bake_loop(src, target)
		lib.add_animation(name, res["anim"])
		gaits[name] = {"cycle": res["cycle"], "duration": res["duration"]}
		if name == "walk":
			walk_ref = res["feet"]
		src.free_scene()
	lib.set_meta("gaits", gaits)
	var transitions := {}
	for group in [STARTS, STOPS]:
		for name in group:
			var src := Source.new(DIR + group[name])
			var res := _bake_travel(src, target, group == STARTS, walk_ref)
			lib.add_animation(name, res["anim"])
			transitions[name] = {"dist": res["dist"], "phase": res["phase"], "length": res["anim"].length}
			src.free_scene()
	for name in TURNS:
		var src := Source.new(DIR + TURNS[name])
		var res := _bake_turn(src, target)
		lib.add_animation(name, res["anim"])
		transitions[name] = {"yaw": res["yaw"], "length": res["anim"].length}
		src.free_scene()
	for name in IDLES:
		var src := Source.new(DIR + IDLES[name])
		var frames: Array = []
		var count := int(src.anim.length * FPS)
		for f in count + 1:
			frames.append(src.pose(src.anim.length * f / count))
		var anim := _write(frames, src, target, src.anim.length, Vector3.ZERO, true)
		anim.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(name, anim)
		src.free_scene()
	lib.set_meta("transitions", transitions)
	return lib


# Posição do pé relativa à pelve (no chão), usada para fase e casamento de pose.
static func _feet(src: Source, g: Array) -> Array:
	var hips: Vector3 = (g[src.bone("Hips")] as Transform3D).origin
	var l: Vector3 = (g[src.bone("LeftFoot")] as Transform3D).origin - hips
	var r: Vector3 = (g[src.bone("RightFoot")] as Transform3D).origin - hips
	return [Vector2(l.z, l.y), Vector2(r.z, r.y)]


static func _bake_loop(src: Source, target: Target) -> Dictionary:
	# Clipes cíclicos do Mixamo têm um número inteiro de ciclos. Contato do pé esquerdo =
	# pé mais à frente da pelve (máximo local), procurado de forma circular.
	var length := src.anim.length
	var hip := src.bone("Hips")
	var steps := int(length * 120.0)
	var lead: Array[float] = []
	for k in steps:
		var g := src.pose(length * k / steps)
		lead.append(((g[src.bone("LeftFoot")] as Transform3D).origin - (g[hip] as Transform3D).origin).z)
	var mean := 0.0
	for v in lead:
		mean += v
	mean /= lead.size()
	var strikes: Array[int] = []
	for k in steps:
		var here := lead[k]
		if here > mean and here >= lead[(k - 1 + steps) % steps] and here > lead[(k + 1) % steps]:
			strikes.append(k)
	# descarta máximos espúrios próximos (menos de 0,25 s), inclusive na emenda do clipe
	var kept: Array[int] = []
	for k in strikes:
		if kept.is_empty() or (k - kept[-1]) * length / steps > 0.25:
			kept.append(k)
	if kept.size() > 1 and (kept[0] + steps - kept[-1]) * length / steps <= 0.25:
		kept.pop_back()
	var cycles := maxi(1, kept.size())
	var duration := length / cycles
	var t0 := (kept[0] if not kept.is_empty() else 0) * length / steps
	var travel: Vector3 = (src.pose(length)[hip] as Transform3D).origin - (src.pose(0.0)[hip] as Transform3D).origin
	travel.y = 0.0
	var p0: Vector3 = (_wrapped(src, t0, travel)[hip] as Transform3D).origin
	var p1: Vector3 = (_wrapped(src, t0 + duration, travel)[hip] as Transform3D).origin
	var frames: Array = []
	var feet: Array = []
	var count := 30
	for f in count + 1:
		var u := float(f) / count
		var g := _wrapped(src, t0 + duration * u, travel)
		# Retira o avanço linear da raiz (em x e z); mantém o balanço vertical e lateral.
		var drift := p0.lerp(p1, u) - p0
		_shift(src, g, Vector3(-drift.x, 0.0, -drift.z))
		frames.append(g)
		feet.append(_feet(src, g))
	var anim := _write(frames, src, target, 1.0, Vector3(p0.x, 0.0, p0.z), true)
	anim.loop_mode = Animation.LOOP_LINEAR
	return {"anim": anim, "cycle": (p1.z - p0.z) * target.ratio, "duration": duration, "feet": feet}


# Pose de um clipe cíclico em qualquer tempo, somando o avanço de cada volta completa.
static func _wrapped(src: Source, time: float, travel: Vector3) -> Array:
	var length := src.anim.length
	var laps := floorf(time / length)
	var g := src.pose(time - laps * length)
	if laps != 0.0:
		_shift(src, g, travel * laps)
	return g


# Desloca toda a pose (pelve e descendentes) por um vetor no espaço do esqueleto.
static func _shift(src: Source, g: Array, offset: Vector3) -> void:
	for i in g.size():
		var t: Transform3D = g[i]
		t.origin += offset
		g[i] = t


static func _bake_travel(src: Source, target: Target, is_start: bool, walk_ref: Array) -> Dictionary:
	var hip := src.bone("Hips")
	var length := src.anim.length
	var base: Vector3 = (src.pose(0.0)[hip] as Transform3D).origin
	var end_z: float = (src.pose(length)[hip] as Transform3D).origin.z - base.z
	# Corta o trecho parado antes da arrancada e depois da parada.
	var from := 0.0
	var to := length
	var k := 0.0
	while k <= length:
		var z: float = (src.pose(k)[hip] as Transform3D).origin.z - base.z
		if is_start and from == 0.0 and z > 0.02:
			from = maxf(0.0, k - 0.25)
		if not is_start and z >= end_z - 0.01:
			to = minf(length, k + 0.9)
			break
		k += 1.0 / 60.0
	var start_z: float = (src.pose(from)[hip] as Transform3D).origin.z
	var start_x: float = (src.pose(from)[hip] as Transform3D).origin.x
	var count := int(ceil((to - from) * FPS))
	var frames: Array = []
	var dist: Array[float] = []
	var phase: Array[float] = []
	for f in count + 1:
		var time := lerpf(from, to, float(f) / count)
		var g := src.pose(time)
		var hp: Vector3 = (g[hip] as Transform3D).origin
		dist.append(maxf(0.0, (hp.z - start_z) * target.ratio))
		_shift(src, g, Vector3(-(hp.x - start_x) * 0.6, 0.0, -(hp.z - start_z)))
		frames.append(g)
		phase.append(_match_phase(_feet(src, g), walk_ref))
	# distância monotônica (ruído da captura não pode andar para trás)
	for f in range(1, dist.size()):
		dist[f] = maxf(dist[f], dist[f - 1])
	var anim := _write(frames, src, target, to - from, Vector3(base.x, 0.0, start_z), false)
	return {"anim": anim, "dist": dist, "phase": phase}


# Fase do ciclo de caminhada cuja posição dos pés mais se parece com esta pose.
static func _match_phase(feet: Array, ref: Array) -> float:
	var best := 0.0
	var best_err := INF
	for f in ref.size() - 1:
		var r: Array = ref[f]
		var err: float = (feet[0] as Vector2).distance_squared_to(r[0]) + (feet[1] as Vector2).distance_squared_to(r[1])
		if err < best_err:
			best_err = err
			best = float(f) / (ref.size() - 1)
	return best


static func _bake_turn(src: Source, target: Target) -> Dictionary:
	var hip := src.bone("Hips")
	var length := src.anim.length
	var count := int(ceil(length * FPS))
	var frames: Array = []
	var yaws: Array[float] = []
	var base: Vector3 = (src.pose(0.0)[hip] as Transform3D).origin
	var yaw0 := 0.0
	var prev := 0.0
	for f in count + 1:
		var g := src.pose(length * f / count)
		var fwd: Vector3 = ((g[hip] as Transform3D).basis * (src.rest_g[hip] as Transform3D).basis.inverse()) * Vector3.BACK
		var yaw := atan2(fwd.x, fwd.z)
		if f == 0:
			yaw0 = yaw
		var rel := prev + angle_difference(prev, yaw - yaw0) if f > 0 else 0.0
		prev = rel
		yaws.append(rel)
		# Tira o giro do corpo inteiro: o corpo fica de frente e os pés dão os passinhos.
		var hp: Vector3 = (g[hip] as Transform3D).origin
		var undo := Transform3D(Basis(Vector3.UP, -rel), Vector3.ZERO)
		for i in g.size():
			var t: Transform3D = g[i]
			t.origin -= Vector3(hp.x - base.x, 0.0, hp.z - base.z)
			t.origin = Vector3(base.x, 0.0, base.z) + Basis(Vector3.UP, -rel) * (t.origin - Vector3(base.x, 0.0, base.z))
			t.basis = undo.basis * t.basis
			g[i] = t
		frames.append(g)
	var anim := _write(frames, src, target, length, Vector3(base.x, 0.0, base.z), false)
	return {"anim": anim, "yaw": yaws}


static func _write(frames: Array, src: Source, target: Target, length: float, ground_origin: Vector3, loop: bool) -> Animation:
	var anim := Animation.new()
	anim.length = length
	anim.step = 1.0 / FPS
	var src_rest_hip: Vector3 = (src.rest_g[src.bone("Hips")] as Transform3D).origin + Vector3(ground_origin.x, 0.0, ground_origin.z)
	var tracks := {}
	for j in target.pairs:
		var ti := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(ti, NodePath("%s:%s" % [SKEL_PATH, target.cs.get_bone_name(j)]))
		tracks[j] = ti
	var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_track, NodePath("%s:%s" % [SKEL_PATH, target.cs.get_bone_name(target.hip)]))
	var solved: Array = []
	for g in frames:
		solved.append(target.solve(g, src_rest_hip))
	var last: int = solved.size() - 1
	for f in solved.size():
		var time := length * f / maxf(last, 1)
		var u := float(f) / maxf(last, 1)
		var rots: Dictionary = solved[f]["rot"]
		var hip_pos: Vector3 = solved[f]["hip"]
		if loop:
			# Fecha o laço: distribui a diferença entre o último e o primeiro quadro.
			hip_pos += ((solved[0]["hip"] as Vector3) - (solved[last]["hip"] as Vector3)) * u
		for j in rots:
			var q: Quaternion = rots[j]
			if loop:
				var first: Quaternion = solved[0]["rot"][j]
				var q_end: Quaternion = solved[last]["rot"][j]
				if first.dot(q_end) < 0.0:
					q_end = -q_end
				q = Quaternion.IDENTITY.slerp(first * q_end.inverse(), u) * q
			anim.rotation_track_insert_key(tracks[j], time, q.normalized())
		anim.position_track_insert_key(pos_track, time, hip_pos)
	return anim
