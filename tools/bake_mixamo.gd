extends SceneTree
# Pré-converte os clipes Mixamo para os quatro corpos (assets/humans/*_mx.res).
const MixamoBank = preload("res://world3d/mixamo_bank.gd")
func _init() -> void:
	for body in ["Human_male", "Human_female", "Human_male_child", "Human_female_child"]:
		var path := "res://assets/humans/%s.gltf" % body
		var n: Node = (load(path) as PackedScene).instantiate()
		var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
		var started := Time.get_ticks_msec()
		var lib := MixamoBank.bake(sk)
		var err := ResourceSaver.save(lib, path.get_basename() + "_mx.res")
		print("%s: %d ms, salvo=%s gaits=%s" % [body, Time.get_ticks_msec() - started, err == OK, lib.get_meta("gaits")])
		var tr: Dictionary = lib.get_meta("transitions")
		for k in tr:
			var d: Dictionary = tr[k]
			if d.has("dist"):
				print("  %s len=%.2f dist_end=%.2f phase0=%.2f phase_end=%.2f" % [k, d["length"], d["dist"][-1], d["phase"][0], d["phase"][-1]])
			else:
				print("  %s len=%.2f yaw_end=%.1f deg" % [k, d["length"], rad_to_deg(d["yaw"][-1])])
		n.free()
	quit()
