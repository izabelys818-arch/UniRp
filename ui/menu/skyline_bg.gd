extends Control

# Fundo de contexto para telas de menu (criação de personagem, configurações): céu de fim de tarde
# em degradê, duas camadas de silhuetas de prédios com algumas janelas acesas e vinheta suave.
# Desenhado uma vez (e de novo só se a tela mudar de tamanho): custo zero por quadro.

const SKY_TOP := Color("#16192a")
const SKY_MID := Color("#3a3446")
const SKY_LOW := Color("#7a5a52")
const FAR := Color("#2a2733")
const NEAR := Color("#17141a")
const WIN := Color("#f0b866")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	# céu
	var sky := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.55), Vector2(0, h * 0.55)])
	draw_polygon(sky, PackedColorArray([SKY_TOP, SKY_TOP, SKY_MID, SKY_MID]))
	var low := PackedVector2Array([Vector2(0, h * 0.55), Vector2(w, h * 0.55), Vector2(w, h), Vector2(0, h)])
	draw_polygon(low, PackedColorArray([SKY_MID, SKY_MID, SKY_LOW, SKY_LOW]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7351
	# prédios ao longe
	var x := -20.0
	while x < w:
		var bw := rng.randf_range(40, 110)
		var bh := rng.randf_range(h * 0.18, h * 0.42)
		draw_rect(Rect2(x, h - bh - h * 0.12, bw, bh + h * 0.12), FAR)
		if rng.randf() < 0.4:
			draw_rect(Rect2(x + bw * 0.3, h - bh - h * 0.12 - 14, 8, 14), FAR)
		x += bw + rng.randf_range(-6, 10)
	# prédios perto, com janelas
	x = -30.0
	while x < w:
		var bw2 := rng.randf_range(70, 170)
		var bh2 := rng.randf_range(h * 0.12, h * 0.3)
		var top := h - bh2
		draw_rect(Rect2(x, top, bw2, bh2), NEAR)
		var wy := top + 14.0
		while wy < h - 20.0:
			var wx := x + 10.0
			while wx < x + bw2 - 14.0:
				if rng.randf() < 0.16:
					draw_rect(Rect2(wx, wy, 7, 9), Color(WIN, rng.randf_range(0.35, 0.8)))
				wx += 16.0
			wy += 20.0
		x += bw2 + rng.randf_range(2, 18)
	# vinheta suave nas bordas
	for i in 6:
		var a := 0.07
		var g := float(i) * 18.0
		draw_rect(Rect2(0, 0, w, g + 18), Color(0, 0, 0, a))
		draw_rect(Rect2(0, h - g - 18, w, g + 18), Color(0, 0, 0, a))
