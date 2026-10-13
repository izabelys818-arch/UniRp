extends RefCounted

# Carros com forma de carro (antes eram duas caixas). Cada peça é uma malha suave montada
# por seções ao longo do comprimento e registrada como "forma" do Kit (car_body_sedan,
# car_cabin_hatch...): o Kit continua juntando tudo numa malha só por pedaço do mapa.
# Medidas em metros; frente do carro em +Z, chão em y = 0.

const Kit = preload("res://world3d/mesh_kit.gd")

# Perfil lateral (z, altura do topo da carroceria) e da cabine (z, altura do teto).
const BODY := {
	"sedan": [[-2.15, 0.78], [-2.05, 0.86], [-1.7, 0.9], [-1.15, 0.93], [-0.9, 0.95], [0.9, 0.96], [1.15, 0.94], [1.75, 0.86], [2.05, 0.8], [2.15, 0.7]],
	"hatch": [[-1.85, 0.86], [-1.78, 0.93], [-1.5, 0.95], [-0.9, 0.96], [0.8, 0.96], [1.05, 0.94], [1.55, 0.86], [1.8, 0.79], [1.9, 0.7]],
}
const CABIN := {
	"sedan": [[-1.22, 0.93], [-0.62, 1.36], [0.42, 1.4], [1.08, 0.95]],
	"hatch": [[-1.62, 0.95], [-1.45, 1.38], [0.36, 1.42], [1.0, 0.95]],
}
const LENGTH := {"sedan": 4.3, "hatch": 3.8}

static var _ready := false
static var _bus_ready := false


static func ensure() -> void:
	if _ready:
		return
	_ready = true
	for model in BODY:
		Kit.register_shape("car_body_" + model, _body(BODY[model]))
		var cabin := _cabin(CABIN[model])
		Kit.register_shape("car_cabin_" + model, cabin[0])
		Kit.register_shape("car_roof_" + model, cabin[1])


static func _lerp_profile(profile: Array, z: float) -> float:
	for i in profile.size() - 1:
		var a: Array = profile[i]
		var b: Array = profile[i + 1]
		if z >= float(a[0]) and z <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (z - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001))
	return float(profile[0][1]) if z < float(profile[0][0]) else float(profile[-1][1])


# Seção da carroceria: base estreita (para-choque), laterais com leve curva e ombro arredondado.
static func _section(half_w: float, bottom: float, top: float) -> Array:
	var h := top - bottom
	var pts := [
		Vector2(0.0, bottom),
		Vector2(half_w * 0.92, bottom),
		Vector2(half_w * 0.99, bottom + h * 0.18),
		Vector2(half_w, bottom + h * 0.5),
		Vector2(half_w * 0.98, bottom + h * 0.82),
		Vector2(half_w * 0.9, top - 0.015),
		Vector2(half_w * 0.6, top),
		Vector2(0.0, top + 0.01),
	]
	return pts


static func _loft(stations: Array) -> Array:
	# stations: [z, Array[Vector2] (meia seção, x >= 0)] -> malha espelhada e fechada
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for side in [1.0, -1.0]:
		for i in stations.size() - 1:
			var za: float = stations[i][0]
			var zb: float = stations[i + 1][0]
			var sa: Array = stations[i][1]
			var sb: Array = stations[i + 1][1]
			for j in sa.size() - 1:
				var a0 := Vector3(sa[j].x * side, sa[j].y, za)
				var a1 := Vector3(sa[j + 1].x * side, sa[j + 1].y, za)
				var b0 := Vector3(sb[j].x * side, sb[j].y, zb)
				var b1 := Vector3(sb[j + 1].x * side, sb[j + 1].y, zb)
				var quad := [a0, b0, b1, a0, b1, a1] if side > 0.0 else [a0, b1, b0, a0, a1, b1]
				for v in quad:
					st.add_vertex(v)
		# tampas da frente e de trás
		for end in [0, stations.size() - 1]:
			var sec: Array = stations[end][1]
			var z: float = stations[end][0]
			var front: bool = end != 0
			for j in sec.size() - 1:
				var c := Vector3(0, (sec[0].y + sec[-1].y) * 0.5, z)
				var p0 := Vector3(sec[j].x * side, sec[j].y, z)
				var p1 := Vector3(sec[j + 1].x * side, sec[j + 1].y, z)
				var flip: bool = (side > 0.0) == front
				if flip:
					st.add_vertex(c); st.add_vertex(p0); st.add_vertex(p1)
				else:
					st.add_vertex(c); st.add_vertex(p1); st.add_vertex(p0)
	st.generate_normals()
	st.index()
	return st.commit_to_arrays()


static func _body(profile: Array) -> Array:
	var z0: float = profile[0][0]
	var z1: float = profile[-1][0]
	var stations: Array = []
	var n := 22
	for i in n + 1:
		var z := lerpf(z0, z1, float(i) / n)
		var top := _lerp_profile(profile, z)
		# pontas mais estreitas e baixas (para-choques arredondados)
		var end_k := 1.0 - pow(absf((z - (z0 + z1) * 0.5) / ((z1 - z0) * 0.5)), 6.0) * 0.12
		stations.append([z, _section(0.88 * end_k, 0.3, top)])
	return _loft(stations)


static func _cabin(profile: Array) -> Array:
	var z0: float = profile[0][0]
	var z1: float = profile[-1][0]
	var glass: Array = []
	var roof: Array = []
	var n := 14
	for i in n + 1:
		var z := lerpf(z0, z1, float(i) / n)
		var top := _lerp_profile(profile, z)
		var base := 0.93
		var hw := 0.8
		# laterais da cabine inclinadas para dentro (tumblehome)
		glass.append([z, [Vector2(0, base), Vector2(hw, base), Vector2(hw * 0.86, top - 0.02), Vector2(0, top)]])
		roof.append([z, [Vector2(0, top - 0.03), Vector2(hw * 0.83, top - 0.03), Vector2(hw * 0.8, top + 0.015), Vector2(0, top + 0.03)]])
	# teto: só a parte de cima, entre os dois pilares
	var roof_part: Array = []
	for r in roof:
		var z: float = r[0]
		if z > float(profile[1][0]) - 0.05 and z < float(profile[2][0]) + 0.05:
			roof_part.append(r)
	return [_loft(glass), _loft(roof_part)]


# Desenha um carro completo no kit (Kit ou ChunkKit) em p, girado rot, na cor col.
static func draw(k, p: Vector3, rot: float, col: Color, model: String = "sedan") -> void:
	ensure()
	var xf := Transform3D(Basis(Vector3.UP, rot), p)
	var half: float = LENGTH[model] * 0.5
	k.use_surface("carpaint")
	k.add("car_body_" + model, xf, col)
	k.add("car_roof_" + model, xf, col.lightened(0.04))
	# vidro: escuro e liso (reflete o céu e as luzes)
	k.add("car_cabin_" + model, xf, Color("#141b22"))
	k.use_surface("")

	# rodas: pneu, calota e caixa de roda escura
	var axle := half - 0.75
	for wz in [-axle, axle]:
		for wx in [-0.8, 0.8]:
			var c := Vector3(wx, 0.33, wz)
			# escala no eixo do cilindro antes de deitar: 66 cm de diâmetro, 24 cm de banda
			var tire := Basis(Vector3.FORWARD, PI / 2.0) * Basis.from_scale(Vector3(0.66, 0.24, 0.66))
			var hub := Basis(Vector3.FORWARD, PI / 2.0) * Basis.from_scale(Vector3(0.4, 0.26, 0.4))
			k.add("cyl", xf * Transform3D(tire, c), Color("#141414"))
			k.add("cyl", xf * Transform3D(hub, c), Color("#8c9094"))
	# para-choques escuros
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(1.7, 0.16, 0.12)), Vector3(0, 0.42, half - 0.02)), Color("#202326"))
	k.add("box", xf * Transform3D(Basis.from_scale(Vector3(1.7, 0.16, 0.12)), Vector3(0, 0.42, -half + 0.02)), Color("#202326"))
	# faróis e lanternas acendem à noite
	k.use_surface("lampglow")
	for sx in [-0.62, 0.62]:
		k.add("box", xf * Transform3D(Basis.from_scale(Vector3(0.34, 0.11, 0.05)), Vector3(sx, 0.66, half - 0.03)), Color("#f2eccc"))
		k.add("box", xf * Transform3D(Basis.from_scale(Vector3(0.3, 0.1, 0.05)), Vector3(sx, 0.7, -half + 0.03)), Color("#a3201c"))
	k.use_surface("")


# Ônibus rodoviário de 10,5 x 2,5 m; mesma malha agrupada e materiais dos veículos.
# Rodas individuais, saia com recortes, seção arredondada, portas e janelas separadas.
static func draw_bus(k, p: Vector3, rot: float, col: Color) -> void:
	if not _bus_ready:
		_bus_ready = true
		var stations: Array = []
		for z in [-5.25, -5.10, -4.90, -3.0, 0.0, 3.5, 4.8, 5.10, 5.25]:
			var narrow := 0.92 if absf(z) > 5.2 else (0.98 if absf(z) > 5.0 else 1.0)
			stations.append([z, [Vector2(0, 1.1), Vector2(1.14 * narrow, 1.1), Vector2(1.25 * narrow, 1.18), Vector2(1.25 * narrow, 2.55), Vector2(1.20 * narrow, 2.96), Vector2(1.04 * narrow, 3.14), Vector2(0, 3.19)]])
		Kit.register_shape("bus_body", _loft(stations))
		var skirt: Array = []
		for i in 106:
			var z := -5.25 + i * 0.1
			var bottom := 0.57
			for axle in [-3.35, 3.2]:
				var dz := absf(z - axle)
				if dz < 0.64:
					bottom = maxf(bottom, 0.53 + sqrt(0.64 * 0.64 - dz * dz))
			skirt.append([z, [Vector2(0, bottom), Vector2(1.225, bottom), Vector2(1.25, 1.18), Vector2(0, 1.18)]])
		Kit.register_shape("bus_skirt", _loft(skirt))
	var xf := Transform3D(Basis(Vector3.UP, rot), p)
	k.use_surface("carpaint")
	k.add("bus_body", xf, col)
	k.add("bus_skirt", xf, col.darkened(0.1))
	var box := func(c: Vector3, size: Vector3, color: Color) -> void:
		k.add("box", xf * Transform3D(Basis.from_scale(size), c), color)
	var glass := Color("#24333b")
	var trim := Color("#282d30")
	for side in [-1.0, 1.0]:
		for wi in 8:
			var z := -4.35 + wi * 1.13
			# Inclinação acompanha a seção da carroceria, sem vidro suspenso.
			var angle: float = -side * 0.058
			var basis := Basis(Vector3.BACK, angle) * Basis.from_scale(Vector3(0.027, 0.91, 1.025))
			k.add("box", xf * Transform3D(basis, Vector3(side * 1.227, 2.43, z)), glass)
			box.call(Vector3(side * 1.258, 1.90, z), Vector3(0.025, 0.05, 1.07), trim)
		box.call(Vector3(side * 1.252, 1.52, -0.25), Vector3(0.03, 0.12, 8.2), col.lightened(0.2))
		# Bagageiro: divisões, puxadores, grelha do motor atrás.
		for z in [-1.8, 0.0, 1.8]:
			box.call(Vector3(side * 1.257, 1.03, z), Vector3(0.025, 0.52, 0.018), trim)
			box.call(Vector3(side * 1.27, 1.16, z + 0.72), Vector3(0.035, 0.035, 0.14), trim)
		for i in 7:
			box.call(Vector3(side * 1.257, 0.82 + i * 0.068, -4.25), Vector3(0.025, 0.022, 0.95), trim)
	# Frente com para-brisa, para-choque, limpadores e retrovisores.
	box.call(Vector3(0, 2.34, 5.255), Vector3(2.16, 1.26, 0.035), glass)
	box.call(Vector3(0, 2.99, 5.25), Vector3(2.06, 0.18, 0.04), trim)
	box.call(Vector3(0, 0.7, 5.27), Vector3(2.20, 0.20, 0.08), trim)
	box.call(Vector3(0, 1.08, 5.27), Vector3(0.86, 0.25, 0.03), trim)
	box.call(Vector3(0, 0.75, 5.32), Vector3(0.4, 0.09, 0.02), Color("#c5c8c6"))
	for side in [-1.0, 1.0]:
		box.call(Vector3(side * 0.55, 1.78, 5.29), Vector3(0.66, 0.025, 0.025), trim)
		box.call(Vector3(side * 1.4, 2.47, 4.83), Vector3(0.32, 0.04, 0.06), trim)
		box.call(Vector3(side * 1.53, 2.34, 4.79), Vector3(0.14, 0.36, 0.23), trim)
	# Porta no lado da plataforma (lado +X antes do giro).
	box.call(Vector3(1.257, 1.8, 4.26), Vector3(0.035, 1.93, 0.75), trim)
	box.call(Vector3(1.28, 2.16, 4.26), Vector3(0.022, 0.97, 0.60), glass.lightened(0.08))
	box.call(Vector3(1.30, 1.69, 4.26), Vector3(0.025, 1.8, 0.028), Color("#b5b9b8"))
	for step in 3:
		box.call(Vector3(1.29, 0.87 + step * 0.12, 4.26), Vector3(0.035, 0.03, 0.69), Color("#8d9699"))
	box.call(Vector3(0, 3.21, -0.7), Vector3(1.44, 0.17, 2.3), Color("#a0a6a5"))
	k.use_surface("")
	box.call(Vector3(0, 0.63, 0), Vector3(1.8, 0.23, 8.6), trim)
	for wz in [-3.35, 3.2]:
		for wx in [-1.23, 1.23]:
			var c := Vector3(wx, 0.53, wz)
			var tire := Basis(Vector3.FORWARD, PI / 2) * Basis.from_scale(Vector3(1.06, 0.28, 1.06))
			k.add("cyl", xf * Transform3D(tire, c), Color("#171a1b"))
			var hub := Basis(Vector3.FORWARD, PI / 2) * Basis.from_scale(Vector3(0.60, 0.30, 0.60))
			k.add("cyl", xf * Transform3D(hub, c), Color("#879093"))
	k.use_surface("lampglow")
	for side in [-1.0, 1.0]:
		box.call(Vector3(side * 0.83, 1.10, 5.27), Vector3(0.34, 0.20, 0.04), Color("#e4dbc0"))
		box.call(Vector3(side * 1.0, 1.1, -5.28), Vector3(0.13, 0.40, 0.04), Color("#a02c25"))
	k.use_surface("")
