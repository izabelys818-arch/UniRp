extends SceneTree

# Reconstrói bibliotecas quando rig/UAL mudarem. Não roda durante a partida.
func _initialize() -> void:
	var bank = load("res://world3d/anim_bank.gd")
	bank.rebuild = true
	for name in ["Human_male", "Human_female", "Human_male_child", "Human_female_child"]:
		var path: String = "res://assets/humans/" + name + ".gltf"
		var model := (load(path) as PackedScene).instantiate()
		var library: AnimationLibrary = bank.bank_for(path, model.get_node("Armature/Skeleton3D"))["lib"]
		var error := ResourceSaver.save(library, path.get_basename() + "_motion.res", ResourceSaver.FLAG_COMPRESS)
		print("MOTION BAKE ", name, " result=", error)
		model.free()
	bank.cleanup()
	quit()
