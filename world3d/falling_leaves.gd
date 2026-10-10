extends MultiMeshInstance3D

const COUNT := 32
var sources: Array = []
var nearby: Array[Vector3] = []
var leaves: Array = []
var rng := RandomNumberGenerator.new()
var timer := 0.0
var elapsed := 0.0

func _ready() -> void:
	rng.seed = 94731
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	var blade := QuadMesh.new()
	blade.size = Vector2(0.075, 0.13)
	var material := StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	blade.material = material
	multimesh.mesh = blade
	multimesh.instance_count = COUNT
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in COUNT:
		leaves.append({"p": Vector3.ZERO, "time": rng.randf_range(0.0, 7.0), "phase": rng.randf() * TAU, "alive": false})
		multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))


func update(delta: float, player: Vector3, indoors: bool, storm: bool) -> void:
	elapsed += delta
	timer -= delta
	if timer <= 0.0:
		timer = 1.0
		nearby.clear()
		for source in sources:
			var p: Vector3 = source
			if Vector2(p.x - player.x, p.z - player.z).length_squared() < 625.0:
				nearby.append(p)
	visible = not nearby.is_empty() and not indoors
	if not visible:
		return
	var month: int = int(TimeManager.date().get("m", 2)) + 1
	var autumn := month in [3, 4, 5]
	var palette := [Color("#a18743"), Color("#7b6437"), Color("#af8b52")] if autumn else [Color("#70824a"), Color("#918258"), Color("#677544")]
	for i in COUNT:
		var leaf: Dictionary = leaves[i]
		leaf["time"] = float(leaf["time"]) + delta
		if not bool(leaf["alive"]) or float(leaf["time"]) > 8.0:
			leaf["p"] = nearby[rng.randi() % nearby.size()] + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 0.5), rng.randf_range(-1.0, 1.0))
			leaf["time"] = rng.randf_range(-2.0, 0.0)
			leaf["alive"] = true
			multimesh.set_instance_color(i, palette[i % palette.size()])
		var p: Vector3 = leaf["p"]
		var phase: float = float(leaf["phase"]) + elapsed * 2.4
		if float(leaf["time"]) >= 0.0 and p.y > 0.19:
			p += Vector3((0.16 if not storm else 0.8) + sin(phase) * 0.13, -0.48 - float(i % 3) * 0.04, cos(phase * 0.7) * 0.12) * delta
			p.y = maxf(p.y, 0.19)
		leaf["p"] = p
		var rotation := Vector3(PI / 2.0, float(leaf["phase"]), 0) if p.y <= 0.19 else Vector3(sin(phase), phase, cos(phase) * 0.4)
		var size := 0.0 if float(leaf["time"]) < 0.0 else clampf(8.0 - float(leaf["time"]), 0.0, 1.0)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_euler(rotation).scaled(Vector3.ONE * size), p))
