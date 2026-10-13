extends SceneTree

func _initialize() -> void:
	for name in ["loungeSofa", "bedDouble", "rugRectangle", "kitchenFridge", "pottedPlant", "bookcaseClosed"]:
		var node = load("res://assets/furniture_k/Models/%s.fbx" % name).instantiate()
		print("MODEL ROOT ", name, " ", node.transform)
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			print("MODEL PART ", name, " ", mesh.name, " ", mesh.transform, " ", mesh.get_aabb())
			for surface in mesh.mesh.get_surface_count():
				var material = mesh.mesh.surface_get_material(surface)
				print("MATERIAL ", name, " ", material.resource_name, " texture=", material.albedo_texture, " color=", material.albedo_color)
		node.free()
	quit()
