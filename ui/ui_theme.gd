extends RefCounted

const BG := Color("#121417")
const PANEL := Color("#1b1e23")
const PANEL_LIGHT := Color("#252931")
const ACCENT := Color("#c9a227")
const TEXT := Color("#e6e1d6")
const MUTED := Color("#8c8a85")
const DANGER := Color("#d1495b")

const KIND_COLORS := {
	"info": "#a9a59c",
	"narration": "#d8cfb8",
	"player": "#7fc8f8",
	"npc": "#e6e1d6",
	"event": "#f4a261",
	"danger": "#ff5c6c",
	"death": "#ff3b3b",
	"error": "#d1495b",
	"system": "#6c757d",
	"phone": "#6fd3a8",
}


static func _box(color: Color, radius: int = 6, margin: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", _box(PANEL))
	t.set_stylebox("panel", "Panel", _box(PANEL))

	var btn := _box(PANEL_LIGHT, 5, 8)
	var btn_hover := _box(PANEL_LIGHT.lightened(0.12), 5, 8)
	var btn_pressed := _box(ACCENT.darkened(0.4), 5, 8)
	var btn_disabled := _box(PANEL.darkened(0.2), 5, 8)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn_hover)
	t.set_stylebox("pressed", "Button", btn_pressed)
	t.set_stylebox("disabled", "Button", btn_disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", MUTED)

	var field := _box(Color("#0d0f12"), 5, 8)
	for cls in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", cls, field)
		t.set_stylebox("focus", cls, _box(Color("#0d0f12"), 5, 8))
		t.set_color("font_color", cls, TEXT)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)

	var bar_bg := _box(Color("#0d0f12"), 3, 0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", _box(ACCENT, 3, 0))
	t.set_font_size("font_size", "ProgressBar", 12)
	return t


static func title(text: String, size: int = 22) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	return l


static func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	return b


static func panel(child: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_child(child)
	return p


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func margin(child: Control, m: int) -> MarginContainer:
	var mc := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, m)
	mc.add_child(child)
	return mc


static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


static func escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")
