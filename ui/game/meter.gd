extends Control

const UI = preload("res://ui/ui_theme.gd")
const Icons = preload("res://ui/game/icons.gd")

var icon_kind: String = ""
var value: float = 100.0
var shown: float = 100.0


func _init(kind: String = "", tip: String = "") -> void:
	icon_kind = kind
	tooltip_text = tip
	custom_minimum_size = Vector2(0, 24)


func _process(delta: float) -> void:
	if absf(shown - value) > 0.1:
		shown = lerpf(shown, value, 1.0 - exp(-delta * 6.0))
		queue_redraw()


func _draw() -> void:
	var low := shown < 25.0
	var col := Color("#5ad19a").lerp(UI.ACCENT, clampf((70.0 - shown) / 40.0, 0.0, 1.0))
	if low:
		col = UI.DANGER.lerp(Color.WHITE, 0.2 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)))
	Icons.draw(self, icon_kind, Rect2(0, 2, 20, 20), col, 1.8)
	var bar := Rect2(28, 8, size.x - 28, 8)
	draw_style_box(UI._box(Color(0, 0, 0, 0.55), 4, 0), bar)
	var fill := Rect2(bar.position, Vector2(bar.size.x * clampf(shown / 100.0, 0.0, 1.0), bar.size.y))
	if fill.size.x > 1:
		draw_style_box(UI._box(col, 4, 0), fill)
		draw_rect(Rect2(fill.position, Vector2(fill.size.x, 2)), Color(1, 1, 1, 0.25))
	if low:
		queue_redraw()
