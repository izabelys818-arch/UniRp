extends Button

const UI = preload("res://ui/ui_theme.gd")
const Icons = preload("res://ui/game/icons.gd")

var icon_kind: String = ""
var badge: int = 0
var icon_color: Color = UI.TEXT
var _hover: float = 0.0


func _init(kind: String = "", tip: String = "", size_px: float = 52.0) -> void:
	icon_kind = kind
	tooltip_text = tip
	custom_minimum_size = Vector2(size_px, size_px)
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(_set_hover.bind(1.0))
	mouse_exited.connect(_set_hover.bind(0.0))


func _set_hover(v: float) -> void:
	_hover = v
	queue_redraw()


func set_badge(n: int) -> void:
	badge = n
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size).grow(-size.x * 0.27)
	var col := icon_color.lerp(UI.ACCENT, _hover * 0.8)
	if disabled:
		col = Color(col, 0.35)
	Icons.draw(self, icon_kind, r, col, 2.0)
	if badge > 0:
		var c := Vector2(size.x - 10, 10)
		draw_circle(c, 10, UI.DANGER)
		var f := UI.font(true)
		var s := str(badge)
		var tw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f, c + Vector2(-tw / 2.0, 4.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
