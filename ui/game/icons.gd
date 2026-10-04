extends RefCounted

# Ícones vetoriais desenhados num grid 24x24 e escalados para o retângulo pedido.


static func _p(r: Rect2, x: float, y: float) -> Vector2:
	return r.position + Vector2(x, y) * (r.size / 24.0)


static func _pts(r: Rect2, coords: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, coords.size(), 2):
		out.append(_p(r, coords[i], coords[i + 1]))
	return out


static func _circle(ci: CanvasItem, r: Rect2, x: float, y: float, rad: float, col: Color, filled: bool = true, w: float = 2.0) -> void:
	var s := r.size.x / 24.0
	if filled:
		ci.draw_circle(_p(r, x, y), rad * s, col)
	else:
		ci.draw_arc(_p(r, x, y), rad * s, 0, TAU, 32, col, w, true)


static func _line(ci: CanvasItem, r: Rect2, coords: Array, col: Color, w: float = 2.0) -> void:
	ci.draw_polyline(_pts(r, coords), col, w, true)


static func _fill(ci: CanvasItem, r: Rect2, coords: Array, col: Color) -> void:
	ci.draw_colored_polygon(_pts(r, coords), col)


static func draw(ci: CanvasItem, kind: String, r: Rect2, col: Color, w: float = 2.0) -> void:
	match kind:
		"map":
			_line(ci, r, [3, 6, 9, 3, 15, 6, 21, 3, 21, 18, 15, 21, 9, 18, 3, 21, 3, 6], col, w)
			_line(ci, r, [9, 3, 9, 18], col, w)
			_line(ci, r, [15, 6, 15, 21], col, w)
		"bag":
			_line(ci, r, [4, 9, 20, 9, 19, 21, 5, 21, 4, 9], col, w)
			_line(ci, r, [8, 9, 8, 6, 10, 3.5, 14, 3.5, 16, 6, 16, 9], col, w)
			_line(ci, r, [8, 13, 16, 13], Color(col, 0.6), w * 0.8)
		"phone":
			_line(ci, r, [7, 2, 17, 2, 17, 22, 7, 22, 7, 2], col, w)
			_line(ci, r, [10.5, 19, 13.5, 19], col, w)
		"book":
			_line(ci, r, [4, 4, 11, 5, 12, 6, 13, 5, 20, 4, 20, 19, 13, 20, 12, 21, 11, 20, 4, 19, 4, 4], col, w)
			_line(ci, r, [12, 6, 12, 21], col, w)
		"gear":
			_circle(ci, r, 12, 12, 3.2, col, false, w)
			for i in 8:
				var a := TAU * i / 8.0
				var c := Vector2(12, 12)
				var p1 := c + Vector2(cos(a), sin(a)) * 6.5
				var p2 := c + Vector2(cos(a), sin(a)) * 9.5
				_line(ci, r, [p1.x, p1.y, p2.x, p2.y], col, w * 1.4)
			_circle(ci, r, 12, 12, 6.8, col, false, w)
		"save":
			_line(ci, r, [4, 4, 17, 4, 20, 7, 20, 20, 4, 20, 4, 4], col, w)
			_line(ci, r, [8, 4, 8, 9, 15, 9, 15, 4], col, w)
			_line(ci, r, [7, 20, 7, 14, 17, 14, 17, 20], col, w)
		"clock":
			_circle(ci, r, 12, 12, 9, col, false, w)
			_line(ci, r, [12, 7, 12, 12, 16, 14], col, w)
		"money":
			_line(ci, r, [3, 6, 21, 6, 21, 18, 3, 18, 3, 6], col, w)
			_circle(ci, r, 12, 12, 3, col, false, w)
		"walk":
			_circle(ci, r, 13, 4, 2, col)
			_line(ci, r, [13, 7, 12, 13, 9, 21], col, w * 1.2)
			_line(ci, r, [12, 13, 15, 16, 15, 21], col, w * 1.2)
			_line(ci, r, [8, 11, 12, 8, 16, 11], col, w * 1.2)
		"car":
			_line(ci, r, [3, 15, 3, 11, 6, 6, 18, 6, 21, 11, 21, 15, 3, 15], col, w)
			_line(ci, r, [5, 11, 19, 11], col, w)
			_circle(ci, r, 7, 16, 2, col)
			_circle(ci, r, 17, 16, 2, col)
		"uber":
			_line(ci, r, [3, 15, 3, 11, 6, 6, 18, 6, 21, 11, 21, 15, 3, 15], col, w)
			_circle(ci, r, 7, 16, 2, col)
			_circle(ci, r, 17, 16, 2, col)
			_fill(ci, r, [9, 2, 15, 2, 15, 5, 9, 5], col)
		"pin":
			_fill(ci, r, [12, 22, 6, 12, 6, 8, 9, 4, 15, 4, 18, 8, 18, 12], col)
			_circle(ci, r, 12, 9, 2.5, Color(0, 0, 0, 0.6))
		"close":
			_line(ci, r, [5, 5, 19, 19], col, w)
			_line(ci, r, [19, 5, 5, 19], col, w)
		"chat":
			_line(ci, r, [3, 5, 21, 5, 21, 16, 10, 16, 5, 20, 6, 16, 3, 16, 3, 5], col, w)
		"send":
			_fill(ci, r, [3, 4, 21, 12, 3, 20, 6, 12], col)
		"cart":
			_line(ci, r, [2, 4, 5, 4, 8, 16, 19, 16, 21, 8, 6, 8], col, w)
			_circle(ci, r, 9, 20, 1.6, col)
			_circle(ci, r, 18, 20, 1.6, col)
		# itens
		"comida":
			_fill(ci, r, [4, 12, 20, 12, 18, 19, 6, 19], col)
			_line(ci, r, [6, 12, 8, 7, 12, 5, 16, 7, 18, 12], col, w)
		"bebida":
			_fill(ci, r, [9, 6, 15, 6, 16, 21, 8, 21], Color(col, 0.85))
			_fill(ci, r, [10.5, 2, 13.5, 2, 13.5, 6, 10.5, 6], col)
		"cafe":
			_fill(ci, r, [5, 9, 17, 9, 16, 19, 6, 19], col)
			_line(ci, r, [17, 11, 20, 12, 19, 15, 16.5, 16], col, w)
			_line(ci, r, [9, 3, 8, 6], Color(col, 0.6), w)
			_line(ci, r, [13, 3, 12, 6], Color(col, 0.6), w)
		"lata":
			_fill(ci, r, [7, 5, 17, 5, 17, 21, 7, 21], col)
			_line(ci, r, [7, 9, 17, 9], Color(0, 0, 0, 0.4), w)
		"garrafa":
			_fill(ci, r, [10, 2, 14, 2, 14, 8, 17, 11, 17, 22, 7, 22, 7, 11, 10, 8], col)
		"dose":
			_fill(ci, r, [7, 8, 17, 8, 15, 20, 9, 20], col)
		"cigarro":
			_fill(ci, r, [5, 6, 19, 6, 19, 21, 5, 21], col)
			_fill(ci, r, [5, 6, 19, 6, 19, 10, 5, 10], Color(1, 1, 1, 0.5))
		"higiene":
			_fill(ci, r, [5, 8, 19, 8, 19, 20, 5, 20], col)
			_circle(ci, r, 9, 5, 2, Color(col, 0.6))
			_circle(ci, r, 14, 4, 1.4, Color(col, 0.6))
		"droga":
			_fill(ci, r, [6, 8, 18, 8, 20, 20, 4, 20], col)
			_line(ci, r, [6, 8, 8, 4, 16, 4, 18, 8], col, w)
			_circle(ci, r, 12, 14, 2.5, Color(0, 0, 0, 0.55))
		"remedio":
			_fill(ci, r, [4, 9, 20, 9, 20, 15, 4, 15], col)
			_fill(ci, r, [12, 9, 20, 9, 20, 15, 12, 15], Color(1, 1, 1, 0.55))
		# necessidades
		"saude":
			_fill(ci, r, [9, 3, 15, 3, 15, 9, 21, 9, 21, 15, 15, 15, 15, 21, 9, 21, 9, 15, 3, 15, 3, 9, 9, 9], col)
		"saciedade":
			_line(ci, r, [7, 3, 7, 21], col, w)
			_line(ci, r, [4, 3, 4, 9, 10, 9, 10, 3], col, w)
			_line(ci, r, [17, 21, 17, 3, 20, 7, 20, 13, 17, 13], col, w)
		"hidratacao":
			_fill(ci, r, [12, 2, 18, 12, 18, 16, 15, 21, 9, 21, 6, 16, 6, 12], col)
		"energia":
			_fill(ci, r, [14, 2, 5, 13, 11, 13, 9, 22, 19, 9, 13, 9], col)
		"higiene_need":
			_circle(ci, r, 9, 14, 5, col, false, w)
			_circle(ci, r, 16, 8, 3.5, col, false, w)
			_circle(ci, r, 18, 16, 2, col, false, w)
		"sanidade":
			_line(ci, r, [2, 12, 6, 7, 12, 5, 18, 7, 22, 12, 18, 17, 12, 19, 6, 17, 2, 12], col, w)
			_circle(ci, r, 12, 12, 3.2, col)
		_:
			_circle(ci, r, 12, 12, 7, col, false, w)
