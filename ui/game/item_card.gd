extends Button

const UI = preload("res://ui/ui_theme.gd")
const Icons = preload("res://ui/game/icons.gd")
const TYPE_COLORS := {
	"comida": Color("#e8a65a"), "bebida": Color("#5aa9e6"), "cafe": Color("#b07a45"), "lata": Color("#4fd1b5"),
	"garrafa": Color("#4caf6b"), "dose": Color("#e8d8a0"), "cigarro": Color("#dddddd"), "higiene": Color("#9fd3ff"),
	"remedio": Color("#ff6b78"),
}

var item_id: String = ""
var qty: int = 0
var subtitle: String = ""
var selected: bool = false


func _init(id: String = "", quantity: int = 0, sub: String = "") -> void:
	item_id = id
	qty = quantity
	subtitle = sub
	custom_minimum_size = Vector2(128, 140)
	focus_mode = Control.FOCUS_NONE
	toggle_mode = false
	var sb := UI._box(Color(1, 1, 1, 0.04), 14, 8)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.08)
	add_theme_stylebox_override("normal", sb)
	var sbh := UI._box(Color(UI.ACCENT, 0.12), 14, 8)
	sbh.set_border_width_all(1)
	sbh.border_color = Color(UI.ACCENT, 0.7)
	add_theme_stylebox_override("hover", sbh)
	add_theme_stylebox_override("pressed", sbh)


static func color_for(id: String) -> Color:
	var tipo := str(World.items.get(id, {}).get("tipo", ""))
	return TYPE_COLORS.get(tipo, UI.ACCENT)


func _draw() -> void:
	var it: Dictionary = World.items.get(item_id, {})
	var col := color_for(item_id)
	if selected:
		draw_style_box(UI._box(Color(UI.ACCENT, 0.18), 14, 0), Rect2(Vector2.ZERO, size))
		draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), UI.ACCENT, false, 2.0)
	var c := Vector2(size.x / 2, 48)
	draw_circle(c, 34, Color(col, 0.14))
	Icons.draw(self, str(it.get("tipo", "")), Rect2(c - Vector2(24, 24), Vector2(48, 48)), col, 2.4)
	var f := UI.font(true)
	var name_s := str(it.get("nome", item_id))
	var fs := 14
	var w := f.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(maxf(6, (size.x - w) / 2), 104), name_s, HORIZONTAL_ALIGNMENT_LEFT, size.x - 12, fs, UI.TEXT)
	if subtitle != "":
		var f2 := UI.font()
		var w2 := f2.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(f2, Vector2((size.x - w2) / 2, 124), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.ACCENT)
	if qty > 1:
		draw_circle(Vector2(size.x - 18, 18), 13, UI.ACCENT)
		var q := "x%d" % qty
		var wq := f.get_string_size(q, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f, Vector2(size.x - 18 - wq / 2, 22), q, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#1a1206"))
