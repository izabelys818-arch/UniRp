extends RefCounted

# Árvores de rua e de praça com espécies diferentes (variedade controlada, poucas formas simples).
# O cenário decide a mistura: ipês floridos no interior, palmeiras na metrópole, árvores secas no colapso.

const Art = preload("res://world3d/art_style.gd")

const MIX := {
	"porto_cinza": {"copa": 5, "oiti": 3, "ipe": 1, "palmeira": 1, "seca": 0},
	"vale_sereno": {"copa": 4, "oiti": 2, "ipe": 3, "mangueira": 2, "palmeira": 1},
	"nova_aurora": {"copa": 2, "oiti": 4, "palmeira": 3, "conica": 1},
	"colapso": {"copa": 3, "oiti": 1, "seca": 4},
}
const IPE := ["#d77fb0", "#e5c23a", "#a070c8", "#e9e2d4"]


static func species(rng: RandomNumberGenerator) -> String:
	var mix: Dictionary = MIX.get(Art.id(), MIX["porto_cinza"])
	var total := 0
	for s in mix:
		total += int(mix[s])
	var roll := rng.randi_range(1, maxi(total, 1))
	for s in mix:
		roll -= int(mix[s])
		if roll <= 0:
			return s
	return "copa"


# Desenha uma árvore no kit (Kit ou ChunkKit). A sombra de contato assenta a árvore no chão.
static func tree(k, p: Vector3, scale: float, rng: RandomNumberGenerator, sp: String = "") -> void:
	if sp == "":
		sp = species(rng)
	var old: String = k.cat
	k.cat = "veg"
	var trunk := Color("#5a4330").lerp(Color("#6a5240"), rng.randf())
	var g := Color("#3f6b35").lerp(Color("#6b8f3a"), rng.randf())
	var shade := 1.7
	match sp:
		"oiti":
			# copa baixa, fechada e escura (a sombra de calçada mais comum do Brasil)
			var h := rng.randf_range(1.7, 2.3) * scale
			k.cyl(p, 0.2 * scale, h, trunk.darkened(0.1))
			var dg := Color("#2f4f2a").lerp(Color("#3f5f32"), rng.randf())
			k.sphere(p + Vector3(0, h + 0.7 * scale, 0), Vector3(3.4, 2.3, 3.4) * scale, dg)
			k.sphere(p + Vector3(0.3, h + 1.5 * scale, -0.2), Vector3(2.5, 1.6, 2.5) * scale, dg.lightened(0.06))
			shade = 1.9
		"ipe":
			var h2 := rng.randf_range(2.8, 3.6) * scale
			k.cyl(p, 0.14 * scale, h2, trunk)
			var fl := Color(IPE[rng.randi() % IPE.size()]).darkened(rng.randf() * 0.1)
			k.sphere(p + Vector3(0, h2 + 0.5 * scale, 0), Vector3(2.8, 1.5, 2.8) * scale, fl)
			k.sphere(p + Vector3(0.6, h2 + 1.0 * scale, 0.2), Vector3(1.9, 1.2, 1.9) * scale, fl.lightened(0.08))
			k.sphere(p + Vector3(-0.5, h2 + 0.9 * scale, -0.4), Vector3(1.7, 1.0, 1.7) * scale, fl.darkened(0.08))
			# flores caídas em volta do tronco
			for i in 7:
				var a := rng.randf() * TAU
				var r := rng.randf_range(0.4, 1.5) * scale
				k.box(p + Vector3(cos(a) * r, 0.012, sin(a) * r), Vector3(0.22, 0.012, 0.18), fl.lightened(0.05), a)
			shade = 1.5
		"palmeira":
			var h3 := rng.randf_range(4.2, 5.8) * scale
			k.cyl(p, 0.2 * scale, 0.6, Color("#7a6a52"))
			k.cyl(p, 0.13 * scale, h3, Color("#8a7a60"))
			var pg := Color("#4a7a3a").lerp(Color("#6a8a40"), rng.randf())
			k.sphere(p + Vector3(0, h3, 0), Vector3(0.5, 0.45, 0.5) * scale, pg.darkened(0.2))
			var n := 7
			var a0 := rng.randf() * TAU
			for i in n:
				var a := a0 + TAU * i / n
				var d := Vector3(cos(a), 0, sin(a))
				var b := Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, 0.42)
				k.add("box", Transform3D(b * Basis.from_scale(Vector3(2.2, 0.05, 0.42) * scale), p + Vector3(0, h3 - 0.3 * scale, 0) + d * 1.0 * scale), pg if i % 2 == 0 else pg.darkened(0.1))
			shade = 1.2
		"mangueira":
			var h4 := rng.randf_range(1.9, 2.5) * scale
			k.cyl(p, 0.24 * scale, h4, trunk.darkened(0.15))
			var mg := Color("#2c4a26").lerp(Color("#3d5a2e"), rng.randf())
			k.sphere(p + Vector3(0, h4 + 0.9 * scale, 0), Vector3(4.2, 2.8, 4.2) * scale, mg)
			k.sphere(p + Vector3(1.0, h4 + 1.4 * scale, 0.5), Vector3(2.8, 2.0, 2.8) * scale, mg.lightened(0.05))
			k.sphere(p + Vector3(-1.0, h4 + 1.2 * scale, -0.6), Vector3(2.6, 1.9, 2.6) * scale, mg.darkened(0.05))
			shade = 2.3
		"conica":
			var h5 := rng.randf_range(3.6, 4.8) * scale
			k.cyl(p, 0.12 * scale, h5 * 0.3, trunk)
			k.cone(p + Vector3(0, h5 * 0.15, 0), 0.9 * scale, h5 * 0.95, g.darkened(0.25))
			shade = 1.0
		"seca":
			# árvore seca/podada: tronco e galhos, quase sem folha
			var h6 := rng.randf_range(2.6, 3.4) * scale
			var bark := Color("#5e554c").lerp(Color("#6e6258"), rng.randf())
			k.cyl(p, 0.15 * scale, h6, bark)
			for i in 4:
				var a2 := rng.randf() * TAU
				var lean := rng.randf_range(0.5, 0.9)
				var b2 := Basis(Vector3.UP, -a2) * Basis(Vector3.FORWARD, -lean)
				var ln := rng.randf_range(1.0, 1.7) * scale
				var base := p + Vector3(0, h6 * rng.randf_range(0.65, 0.95), 0)
				k.add("box", Transform3D(b2 * Basis.from_scale(Vector3(ln, 0.08 * scale, 0.08 * scale)), base + Vector3(cos(a2), 0.35, sin(a2)) * ln * 0.45), bark.darkened(0.05))
			if rng.randf() < 0.5:
				k.sphere(p + Vector3(0.3, h6 + 0.4, 0.1), Vector3(1.3, 0.8, 1.3) * scale, Color("#6a6a3a"))
			shade = 0.9
		_:
			var h := rng.randf_range(2.2, 3.2) * scale
			k.cyl(p, 0.18 * scale, h, trunk)
			k.sphere(p + Vector3(0, h + 0.6 * scale, 0), Vector3(3.0, 2.4, 3.0) * scale, g)
			k.sphere(p + Vector3(0.6, h + 1.4 * scale, 0.3), Vector3(2.2, 1.8, 2.2) * scale, g.lightened(0.08))
			k.sphere(p + Vector3(-0.5, h + 1.1 * scale, -0.4), Vector3(2.0, 1.6, 2.0) * scale, g.darkened(0.08))
	# sombra difusa da copa + escurecido no pé do tronco
	k.soft_shadow(p, shade * scale, shade * scale, 0.2)
	k.soft_shadow(p, 0.42 * scale, 0.42 * scale, 0.32)
	k.cat = old
