extends "res://ui/face/face_rig.gd"

# Só a cabeça do retrato (cabelo, rosto, expressões), para colar sobre o corpo inteiro.
# O espaço da cabeça (150, 185) é mapeado para o centro do controle.


func _draw() -> void:
	if look.is_empty():
		return
	var k := size.x / 190.0
	var shake := Vector2.ZERO
	if cur["tremble"] > 0.05:
		shake = Vector2(randf_range(-1, 1), randf_range(-0.6, 0.6)) * cur["tremble"] * 1.6
	var xf := Transform2D(0.0, size / 2.0 + shake * k).scaled_local(Vector2(k, k)).rotated_local(cur["tilt"]).translated_local(-C)
	draw_set_transform_matrix(xf)
	_draw_back_hair()
	_draw_head()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
