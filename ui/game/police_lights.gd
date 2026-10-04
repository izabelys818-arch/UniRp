extends Control

var t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var on: bool = CrimeSystem.police_lights
	if on != visible:
		visible = on
	if on:
		t += delta
		queue_redraw()


func _draw() -> void:
	var red := fmod(t * 3.0, 2.0) < 1.0
	var col := Color(1.0, 0.1, 0.15) if red else Color(0.15, 0.35, 1.0)
	var w := size.x
	var h := size.y
	var left := red
	for i in 12:
		var k := 1.0 - float(i) / 12.0
		var x := 0.0 if left else w - w * 0.35
		draw_rect(Rect2(x + (w * 0.35 * (1.0 - k) if left else 0.0), 0, w * 0.35 * k, h), Color(col, 0.05))
	draw_rect(Rect2(0, 0, w, 6), Color(col, 0.7))
	draw_rect(Rect2(0, h - 6, w, 6), Color(col, 0.7))
