extends Control

var stars: int = 0
var t: float = 0.0


func _init() -> void:
	custom_minimum_size = Vector2(150, 24)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = "Nível de procurado pela polícia"


func set_stars(n: int) -> void:
	stars = n
	visible = n > 0
	queue_redraw()


func _process(delta: float) -> void:
	if stars > 0:
		t += delta
		queue_redraw()


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + TAU * i / 10.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, col)


func _draw() -> void:
	for i in 5:
		var c := Vector2(14 + i * 28, 12)
		if i < stars:
			var pulse := 0.85 + 0.15 * sin(t * 6.0 + i)
			_star(c, 11 * pulse, Color("#ff4d5e"))
		else:
			_star(c, 9, Color(1, 1, 1, 0.15))
