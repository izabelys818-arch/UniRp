extends Node

# Auditoria de texturas: percorre tudo que é desenhado no mundo e classifica cada material
# (shader fotográfico, textura própria, cor lisa) por origem. AUDIT_OUT=<arquivo.json>.

const UITheme = preload("res://ui/ui_theme.gd")

var groups: Dictionary = {}


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "user://audit_save.json"
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x",
		"look": {"pele": 2, "cabelo": 0, "cor_cabelo": 0, "roupa": 2, "marcas": []},
		"appearance_extra": "", "backstory": "", "traits": [], "cenario": "porto_cinza",
		"origin": origin["id"], "money": 400, "location": "rua", "home": "apartamento", "inventory": {}, "alive": true,
	})
	TimeManager.total_minutes = 1440 + 11 * 60
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var screen = preload("res://ui/game_screen.gd").new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	var wv = screen.world_view
	while wv == null or not wv._built:
		await get_tree().process_frame
		wv = screen.world_view
	# abre uma casa para os móveis entrarem na conta
	for i in 120:
		await get_tree().process_frame
	for s in wv.city.structures:
		if s.has("lot"):
			wv.city.ensure_interior(s)
			wv.city.set_cut(s, true)
			break
	for i in 30:
		await get_tree().process_frame
	_walk(wv.viewport, "")
	var rows: Array = []
	for key in groups:
		rows.append(groups[key])
	rows.sort_custom(func(a, b): return int(a["instances"]) > int(b["instances"]))
	for r in rows:
		print("AUDIT ", r["origin"], " | ", r["kind"], " | inst=", r["instances"], " | ", r["sample"])
	var out := OS.get_environment("AUDIT_OUT")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(rows, "\t"))
	SaveManager.delete_save()
	get_tree().quit()


func _origin(n: Node) -> String:
	var parts: Array = []
	var node := n
	while node != null and parts.size() < 6:
		var s = node.get_script()
		if s != null:
			parts.append(str(s.resource_path).get_file())
			break
		if not str(node.name).begins_with("@"):
			parts.append(str(node.name))
		node = node.get_parent()
	parts.reverse()
	return "/".join(parts)


func _kind(m: Material) -> String:
	if m == null:
		return "sem material"
	if m is ShaderMaterial:
		var sh: Shader = (m as ShaderMaterial).shader
		return "shader " + (str(sh.resource_path).get_file() if sh != null and sh.resource_path != "" else "embutido")
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		if b.albedo_texture != null:
			return "textura " + ("+relevo" if b.normal_enabled else "sem relevo")
		if b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
			return "cor lisa (sem luz)"
		return "COR LISA"
	return m.get_class()


func _walk(n: Node, _path: String) -> void:
	if n is GeometryInstance3D and (n as GeometryInstance3D).is_visible_in_tree():
		var mats: Array = []
		var gi := n as GeometryInstance3D
		if gi.material_override != null:
			mats.append(gi.material_override)
		elif n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var m: Material = mi.get_surface_override_material(i)
				if m == null:
					m = mi.mesh.surface_get_material(i)
				mats.append(m)
		elif n is MultiMeshInstance3D:
			mats.append(gi.material_override)
		elif n is CPUParticles3D or n is GPUParticles3D:
			mats.append(null)
		for m in mats:
			var k := _kind(m)
			var detail := ""
			if k.begins_with("COR LISA") or k.begins_with("cor lisa"):
				var b := m as BaseMaterial3D
				var size := Vector3.ZERO
				if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
					size = (n as MeshInstance3D).get_aabb().size.snapped(Vector3.ONE * 0.1)
				detail = " cor=%s vc=%s alpha=%s malha=%s tam=%s" % [b.albedo_color.to_html(false), b.vertex_color_use_as_albedo, b.transparency, ((n as MeshInstance3D).mesh.get_class() if n is MeshInstance3D else "?"), size]
			var key := _origin(n) + "|" + k + detail
			if not groups.has(key):
				groups[key] = {"origin": _origin(n), "kind": k + detail, "instances": 0, "sample": str(n.name)}
			groups[key]["instances"] = int(groups[key]["instances"]) + 1
	for c in n.get_children():
		_walk(c, _path)
