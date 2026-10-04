extends Control

signal place_selected(loc_id: String)

const UI = preload("res://ui/ui_theme.gd")
const Icons = preload("res://ui/game/icons.gd")
const TYPE_COLORS := {
	"casa": Color("#e8ad4f"), "publico": Color("#4fd1b5"), "bar": Color("#ff5d8f"), "loja": Color("#5aa9e6"),
	"comida": Color("#f4a261"), "servico": Color("#c792ea"), "hospedagem": Color("#b5838d"),
}

var hovered: String = ""
var selected: String = ""
var t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _to_screen(x: float, y: float) -> Vector2:
	var pad := Vector2(70, 60)
	return pad + Vector2(x / 100.0, y / 100.0) * (size - pad * 2)


func _pin_at(p: Vector2) -> String:
	for id in World.visible_locations():
		var loc: Dictionary = World.locations[id]
		if _to_screen(loc["x"], loc["y"]).distance_to(p) < 22:
			return id
	return ""


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _pin_at(e.position)
		if h != hovered:
			hovered = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var id := _pin_at(e.position)
		if id != "":
			selected = id
			place_selected.emit(id)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0c1118"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for i in 70:
		var r := Rect2(rng.randf() * size.x, rng.randf() * size.y, rng.randf_range(40, 120), rng.randf_range(30, 90))
		draw_rect(r, Color("#141b25"))
		draw_rect(r, Color(1, 1, 1, 0.03), false, 1.0)
	var lake := PackedVector2Array()
	var lc := _to_screen(86, 70)
	for i in 36:
		var a := TAU * i / 36.0
		lake.append(lc + Vector2(cos(a) * 90, sin(a) * 50) * (1.0 + 0.08 * sin(a * 3)))
	draw_colored_polygon(lake, Color("#12324a"))
	draw_circle(_to_screen(80, 58), 80, Color(0.12, 0.3, 0.16, 0.6))
	var grid_col := Color("#243042")
	for x in range(0, 110, 12):
		draw_line(_to_screen(x, 0), _to_screen(x, 100), grid_col, 3.0)
	for y in range(0, 110, 14):
		draw_line(_to_screen(0, y), _to_screen(100, y), grid_col, 3.0)
	draw_line(_to_screen(0, 85), _to_screen(100, 20), Color("#33415a"), 10.0)
	draw_line(_to_screen(10, 0), _to_screen(70, 100), Color("#33415a"), 8.0)
	var here := World.current_id()
	var hl: Dictionary = World.locations[here]
	var hp := _to_screen(hl["x"], hl["y"])
	if selected != "" and selected != here:
		var sl: Dictionary = World.locations[selected]
		var sp := _to_screen(sl["x"], sl["y"])
		var n := 24
		for i in n:
			if i % 2 == 0:
				draw_line(hp.lerp(sp, float(i) / n), hp.lerp(sp, float(i + 1) / n), UI.ACCENT, 3.0, true)
	for id in World.visible_locations():
		var loc: Dictionary = World.locations[id]
		var p := _to_screen(loc["x"], loc["y"])
		var col: Color = TYPE_COLORS.get(loc["tipo"], UI.TEXT)
		var open := World.is_open(id)
		if not open:
			col = col.darkened(0.55)
		var big: bool = id == hovered or id == selected
		if id == here:
			var pulse := 0.5 + 0.5 * sin(t * 3.0)
			draw_circle(p, 26 + pulse * 10, Color(UI.ACCENT, 0.18 * (1.0 - pulse)))
			draw_arc(p, 20, 0, TAU, 32, UI.ACCENT, 3.0, true)
		draw_circle(p + Vector2(0, 3), 16 if big else 13, Color(0, 0, 0, 0.5))
		draw_circle(p, 16 if big else 13, col)
		draw_circle(p, 6, Color(0, 0, 0, 0.55))
		var f := UI.font(true)
		var name_s: String = loc["nome"]
		var fs := 15 if big else 13
		var w := f.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lp := p + Vector2(-w / 2, 34)
		draw_rect(Rect2(lp + Vector2(-6, -15), Vector2(w + 12, 21)), Color(0, 0, 0, 0.6))
		draw_string(f, lp, name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if open else UI.MUTED)
	var tf := UI.font(true)
	draw_string(tf, Vector2(24, size.y - 22), "PORTO CINZA", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, 0.12))
