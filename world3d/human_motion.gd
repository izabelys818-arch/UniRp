extends RefCounted

const REST_POSES := ["relaxado", "peso_esquerda", "peso_direita", "olhar_ao_redor", "ajustar_manga"]

# Base estreita durante a marcha, sem apagar flexão/avanço do joelho.
# Usa rotações sobre os clipes: não desloca vértices, cápsula ou pivôs.
static func stance(person, delta: float) -> void:
	if person.player_motion != null and person.player_motion.get("mocap") == true and person.player_motion.active:
		# Captura de movimento já tem base, joelhos e peso corretos: nada de reapontar pernas.
		# Só as variações de repouso (peso numa perna, olhar ao redor) por cima da respiração.
		var still: float = 1.0 - person.player_motion.move_weight
		person.rest_weight = move_toward(person.rest_weight, still, delta * 2.0) if still > 0.98 else minf(person.rest_weight, still)
		rest_pose(person)
		return
	if person.player_motion != null and person.player_motion.prototype and person.player_motion.active:
		rest_pose(person)
		return
	if person.lying or person.busy_t > 0.0 or person.daily_action != "" or person.activity not in ["", "olhar", "conversar"]:
		person.rest_weight = 0.0
		return
	var sk: Skeleton3D = person.skel
	var moving: bool = person._speed > 0.15
	var amount: float = person.player_motion.move_weight if person.player_motion != null and person.player_motion.active else smoothstep(0.05, 0.4, person._speed)
	for side in ["l", "r"]:
		var hip := sk.find_bone("thigh_" + side)
		var knee := sk.find_bone("calf_" + side)
		var ankle := sk.find_bone("foot_" + side)
		var h: Vector3 = sk.get_bone_global_pose(hip).origin
		var k: Vector3 = sk.get_bone_global_pose(knee).origin
		var a: Vector3 = sk.get_bone_global_pose(ankle).origin
		var sign_x := signf(h.x)
		var rest_h: Vector3 = sk.get_bone_global_rest(hip).origin
		var knee_x := sign_x * absf(rest_h.x) * lerpf(0.94, 0.75, amount)
		person._aim_bone(hip, knee, Vector3(knee_x - h.x, k.y - h.y, k.z - h.z), 1.0)
		k = sk.get_bone_global_pose(knee).origin
		a = sk.get_bone_global_pose(ankle).origin
		var ankle_x := sign_x * absf(rest_h.x) * lerpf(0.87, 0.57, amount)
		person._aim_bone(knee, ankle, Vector3(ankle_x - k.x, a.y - k.y, a.z - k.z), 1.0)
	person.rest_weight = move_toward(person.rest_weight, 0.0 if moving else 1.0, delta * 3.0)
	rest_pose(person)


static func rest_pose(person) -> void:
	if person.rest_weight <= 0.001 or not person._lod_near or person.talk_left > 0.0:
		return
	# Determinístico por pessoa, com intervalos lentos e envelopes suaves.
	var time: float = person.t + fposmod(person.seed_n * 0.031, 17.0)
	var slot := int(floor(time / 12.0))
	var local: float = fposmod(time, 12.0)
	var weight: float = smoothstep(0.0, 2.0, local) * (1.0 - smoothstep(9.0, 12.0, local)) * person.rest_weight
	var pose := posmod(int(person.seed_n) + slot, REST_POSES.size())
	person.idle_pose = REST_POSES[pose]
	var sway: float = (-1.0 if pose == 1 else (1.0 if pose == 2 else 0.25 * sin(time * 0.35))) * weight
	person._rotate_local("pelvis", Vector3(0, 0, sway * 0.018))
	person._rotate_local("spine_02", Vector3(sin(time * 1.18) * 0.007 * person.rest_weight, 0, -sway * 0.012))
	person._rotate_local("Head", Vector3(sin(time * 0.42) * 0.014 * weight, sin(time * 0.31) * (0.10 if pose == 3 else 0.025) * weight, 0))
	if person.umbrella_on or person.stroller_on or person.gesture_left > 0.0 or person._wave_t > 0.0:
		return
	# captura de movimento já tem braços naturais: a mão "ajeitando a manga" cruzava o corpo
	# (o IK não desvia do tronco) e o braço atravessava o peito
	if person.player_motion != null and person.player_motion.get("mocap") == true and person.player_motion.active:
		return
	if pose == 4:
		person._reach_hand("r", Vector3(0.16, 0.99, 0.16), weight * 0.65)
		person._reach_hand("l", Vector3(0.19, 0.92, 0.12), weight * 0.30)
	else:
		person._rotate_local("clavicle_l", Vector3(0, 0, weight * 0.015))
		person._rotate_local("clavicle_r", Vector3(0, 0, -weight * 0.008))

# Ritmos cotidianos; idade não implica deformação da coluna.
static func profile(age: int) -> Dictionary:
	if age < 13:
		return {"walk": 0.72, "run": 0.67, "stride": 0.77, "gesture": 1.12, "accel": 10.0}
	if age < 18:
		return {"walk": 0.92, "run": 0.92, "stride": 0.95, "gesture": 1.04, "accel": 12.0}
	var senior := clampf((age - 55.0) / 35.0, 0.0, 1.0)
	return {"walk": lerpf(1.0, 0.67, senior), "run": lerpf(1.0, 0.51, senior),
		"stride": lerpf(1.0, 0.78, senior), "gesture": lerpf(1.0, 0.78, senior), "accel": lerpf(12.0, 7.0, senior)}


static func apply(person, delta: float) -> void:
	if person.player_motion != null and person.player_motion.prototype and person.player_motion.active:
		person.player_motion.body(person, delta)
		return
	if not person._lod_near or person.lying:
		return
	var sk: Skeleton3D = person.skel
	if person.player_motion != null and person.player_motion.active and person.activity != "sentar":
		person.player_motion.dynamics(person, delta)
	if person.player_motion != null and person.player_motion.get("mocap") == true and person.player_motion.active and person.daily_action == "" and person.activity in ["", "olhar", "conversar"]:
		return
	if person._speed > 0.35 and person.activity != "sentar" and person.player_motion != null:
		# A UAL já coordena braços e pernas. Mantém esse contrabalanço e adiciona
		# apenas um pequeno assentamento do tronco, sem apagar 80–90% da pose.
		var phase: float = person.player_motion.phase * TAU
		person._rotate_local("spine_02", Vector3(-0.012 * person.player_motion.run_weight, sin(phase) * 0.008, 0))
	if person._speed > 0.35 and person.activity != "sentar" and person.player_motion == null:
		var age_profile := profile(int(person.look.get("age", 30)))
		var running: bool = person._cur_anim in ["Jog_Fwd", "Sprint"]
		var phase: float = person.ap.current_animation_position / maxf(person.ap.current_animation_length, 0.1) * TAU
		var swing: float = sin(phase) * (0.58 if running else 0.3) * float(age_profile["gesture"])
		for name in ["spine_01", "spine_02", "spine_03", "neck_01"]:
			var i := sk.find_bone(name)
			if i >= 0:
				sk.set_bone_pose_rotation(i, Quaternion.IDENTITY.slerp(sk.get_bone_pose_rotation(i), 0.2))
		person._rotate_local("spine_02", Vector3(-0.035 if running else 0.0, sin(phase) * 0.035, 0))
		if not person.umbrella_on and not person.stroller_on:
			for side in ["l", "r"]:
				var direction := 1.0 if side == "l" else -1.0
				var upper := sk.find_bone("upperarm_" + side)
				var lower := sk.find_bone("lowerarm_" + side)
				var hand := sk.find_bone("hand_" + side)
				person._aim_bone(upper, lower, Vector3(direction * 0.1, -1.0, swing * direction), 0.9)
				person._aim_bone(lower, hand, Vector3(direction * 0.04, -0.35 if running else -0.95, (0.85 if running else 0.1) + swing * direction), 0.9)
	var quiet: bool = person._speed < 0.35 and person.activity in ["", "conversar", "olhar", "celular", "cozinhar", "banho"]
	if quiet:
		# A animação de repouso da UAL é ampla; pessoas em repouso respiram suavemente.
		for name in ["spine_01", "spine_02", "spine_03", "neck_01", "Head"]:
			var i := sk.find_bone(name)
			if i >= 0:
				sk.set_bone_pose_rotation(i, Quaternion.IDENTITY.slerp(sk.get_bone_pose_rotation(i), 0.25))
		var pelvis := sk.find_bone("pelvis")
		if pelvis >= 0:
			sk.set_bone_pose_rotation(pelvis, Quaternion(Vector3.FORWARD, sin(person.t * 0.55 + person.seed_n) * 0.006))
		person._rotate_local("spine_02", Vector3(sin(person.t * 1.15) * 0.005, 0, 0))
		person._rotate_local("Head", Vector3(0, sin(person.t * 0.34 + person.seed_n) * 0.025, 0))
		if person.daily_action == "":
			for side in ["l", "r"]:
				var sign_x := 1.0 if side == "l" else -1.0
				var speech: float = maxf(0.0, sin(person.t * 2.1 + person.seed_n)) * 0.2 if person.talk_left > 0.0 else 0.0
				person._aim_bone(sk.find_bone("upperarm_" + side), sk.find_bone("lowerarm_" + side), Vector3(sign_x * 0.08, -1.0, 0.04 + speech), 0.95)
				person._aim_bone(sk.find_bone("lowerarm_" + side), sk.find_bone("hand_" + side), Vector3(sign_x * 0.04, -0.95, 0.08 + speech * 2.0), 0.95)
	if person.daily_action == "":
		if person.activity == "celular":
			person._reach_hand("l", Vector3(0.12, 1.2, 0.26), 0.95)
			person._reach_hand("r", Vector3(0.06, 1.21, 0.3), 0.9)
		return
	person.action_time += delta
	var time: float = person.action_time * float(profile(int(person.look.get("age", 30)))["gesture"])
	var f: Dictionary = person._anatomy
	if f.is_empty():
		return
	var nose: Vector3 = f["nose"]
	var mouth: Vector3 = person.HumanStyle.sculpt(Vector3(0, f["mouth_y"], nose.z - 0.01), f, person.look)
	var head := sk.find_bone("Head")
	mouth = sk.get_bone_global_pose(head) * sk.get_bone_global_rest(head).affine_inverse() * mouth
	var pelvis := sk.find_bone("pelvis")
	var body_offset := sk.get_bone_global_pose(pelvis).origin - sk.get_bone_global_rest(pelvis).origin
	var cycle := fposmod(time, 2.1)
	var lift := smoothstep(0.15, 0.7, cycle) * (1.0 - smoothstep(1.1, 1.8, cycle))
	match person.daily_action:
		"comer", "beber":
			var hand_target := (Vector3(-0.15, 1.0, 0.32) + body_offset).lerp(mouth + Vector3(-0.035, -0.035, 0.07), lift)
			person._reach_hand("r", hand_target, 1.0)
			person._rotate_local("hand_r", Vector3(-lift * (0.45 if person.daily_action == "beber" else 0.12), 0, 0))
			if person.daily_action == "comer" and lift > 0.55:
				person._face_w["queixo"] = 0.12 + absf(sin(time * 8.0)) * 0.14
			person._rotate_local("Head", Vector3(-0.04 * lift, 0, 0))
		"banho":
			var wash := fposmod(time, 3.0)
			person._reach_hand("r", Vector3(-0.09, 1.55 if wash < 1.2 else 1.2, 0.14), 0.95)
			person._reach_hand("l", Vector3(0.09, 1.52 if wash < 1.2 else 1.16, 0.17), 0.95)
			person._rotate_local("Head", Vector3(0.04 * sin(time * 2.0), 0, 0))
		"cozinhar":
			person._reach_hand("r", Vector3(-0.12 + sin(time * 3.1) * 0.05, 0.97, 0.35 + cos(time * 3.1) * 0.04), 1.0)
			person._reach_hand("l", Vector3(0.15, 0.98, 0.32), 0.95)
			person._rotate_local("Head", Vector3(0.06, 0, 0))
		"pc":
			person._reach_hand("r", Vector3(-0.12, 0.93 + sin(time * 8.0) * 0.008, 0.32), 1.0)
			person._reach_hand("l", Vector3(0.12, 0.93 + cos(time * 7.0) * 0.008, 0.32), 1.0)
		"tv", "sofa":
			person._reach_hand("r", Vector3(-0.15, 0.72, 0.23), 0.8)
			person._reach_hand("l", Vector3(0.15, 0.72, 0.23), 0.8)
