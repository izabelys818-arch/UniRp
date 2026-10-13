extends SceneTree

func _initialize() -> void:
	call_deferred("measure")

func measure() -> void:
	root.get_node("Settings").api_key = ""
	print("Medição offline do apoio dos pés; biblioteca e rig preservados.")
	var records := {}
	for file_name in ["Human_male", "Human_female", "Human_male_child", "Human_female_child"]:
		var model := (load("res://assets/humans/" + file_name + ".gltf") as PackedScene).instantiate()
		root.add_child(model)
		var sk: Skeleton3D = model.get_node("Armature/Skeleton3D")
		var mesh: MeshInstance3D = sk.get_node("HumanBody")
		var arr := mesh.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var skin: Skin = mesh.skin
		var foot_points: Array = []
		var foot_bones: Array = []
		for side in ["l", "r"]:
			var candidates: Array = []
			var low := INF
			var foot := sk.find_bone("foot_" + side)
			for v in verts.size():
				var weight := 0.0
				for k in bones.size() / verts.size():
					var bind := bones[v * (bones.size() / verts.size()) + k]
					if String(skin.get_bind_name(bind)) in ["foot_" + side, "ball_" + side]:
						weight += weights[v * (bones.size() / verts.size()) + k]
				if weight > 0.75:
					low = minf(low, verts[v].y)
					candidates.append(verts[v])
			var sole := Vector3.ZERO
			var count := 0
			for p in candidates:
				if p.y < low + 0.012:
					sole += p
					count += 1
			sole /= maxf(count, 1)
			foot_points.append(sk.get_bone_global_rest(foot).affine_inverse() * sole)
			foot_bones.append(foot)
		var bank: Dictionary = load("res://world3d/anim_bank.gd").bank_for("res://assets/humans/" + file_name + ".gltf", sk)
		var ap := AnimationPlayer.new()
		model.add_child(ap)
		ap.root_node = NodePath("..")
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		ap.add_animation_library("", bank["lib"])
		var subject := {"sole_offsets": [], "clips": {}}
		for p in foot_points:
			subject["sole_offsets"].append([p.x,p.y,p.z])
		for name in ["Idle", "Walk", "Walk_Formal", "Jog_Fwd", "Sprint"]:
			var clip: Animation = ap.get_animation(name)
			ap.play(name, 0)
			ap.advance(0)
			var samples: Array = []
			var low := [INF, INF]
			for f in 241:
				ap.seek(clip.length * f / 240.0, true)
				var row: Array = []
				for side in 2:
					var p: Vector3 = sk.get_bone_global_pose(foot_bones[side]) * foot_points[side]
					row.append(p)
					low[side] = minf(low[side], p.y)
				samples.append(row)
			var velocities: Array = []
			for f in range(1, samples.size()):
				for side in 2:
					var a: Vector3 = samples[f-1][side]
					var b: Vector3 = samples[f][side]
					if a.y < low[side] + 0.025 and b.y < low[side] + 0.025 and b.z < a.z:
						velocities.append(-(b.z-a.z) * 240.0 / clip.length)
			velocities.sort()
			var median: float = velocities[velocities.size()/2] if not velocities.is_empty() else 0.0
			var entry := {"mps": median, "cycle_m": median * clip.length, "length": clip.length, "support_samples": velocities.size(), "min_sole_y": low, "old_mps": bank["speed"].get(name, 0.0)}
			subject["clips"][name] = entry
			print("SOLE ", file_name, " ", name, " ", JSON.stringify(entry))
		records[file_name] = subject
		model.free()
	var file := FileAccess.open(OS.get_environment("LOCOMOTION_CALIBRATION") if OS.get_environment("LOCOMOTION_CALIBRATION") != "" else "user://player_stride_measurement.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	file.close()
	print("PROBE OK")
	quit()
