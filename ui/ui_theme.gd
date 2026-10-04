extends RefCounted

const BG := Color("#07090c")
const PANEL := Color(0.07, 0.08, 0.1, 0.86)
const PANEL_LIGHT := Color(0.16, 0.18, 0.22, 0.9)
const ACCENT := Color("#e8ad4f")
const TEAL := Color("#4fd1b5")
const TEXT := Color("#eeece6")
const MUTED := Color("#8f949c")
const DANGER := Color("#ff5d6c")
const GLASS := Color(0.05, 0.06, 0.08, 0.78)
const EDGE := Color(1, 1, 1, 0.09)

const KIND_COLORS := {
	"info": "#a9adb4",
	"narration": "#d9d2c1",
	"player": "#7fc8f8",
	"npc": "#eeece6",
	"event": "#f4b26a",
	"danger": "#ff6b78",
	"death": "#ff3b3b",
	"error": "#ff6b78",
	"system": "#6c727c",
	"phone": "#6fe0b8",
}

static var _font: Font
static var _font_bold: Font


static func font(bold: bool = false) -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
		f.antialiasing = TextServer.FONT_ANTIALIASING_LCD
		_font = f
		var fb := SystemFont.new()
		fb.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial"])
		fb.font_weight = 700
		_font_bold = fb
	return _font_bold if bold else _font


static func _box(color: Color, radius: int = 10, margin: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


static func glass(radius: int = 16, margin: int = 14, tint: Color = GLASS) -> StyleBoxFlat:
	var sb := _box(tint, radius, margin)
	sb.set_border_width_all(1)
	sb.border_color = EDGE
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 6)
	return sb


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", glass())
	t.set_stylebox("panel", "Panel", glass())

	var btn := _box(Color(1, 1, 1, 0.06), 10, 9)
	btn.set_border_width_all(1)
	btn.border_color = Color(1, 1, 1, 0.08)
	var hover := _box(Color(ACCENT, 0.16), 10, 9)
	hover.set_border_width_all(1)
	hover.border_color = Color(ACCENT, 0.7)
	hover.shadow_color = Color(ACCENT, 0.25)
	hover.shadow_size = 8
	var pressed := _box(Color(ACCENT, 0.32), 10, 9)
	pressed.set_border_width_all(1)
	pressed.border_color = ACCENT
	var disabled := _box(Color(1, 1, 1, 0.03), 10, 9)
	for cls in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_disabled_color", cls, Color(MUTED, 0.6))

	var field := _box(Color(0, 0, 0, 0.45), 10, 10)
	field.set_border_width_all(1)
	field.border_color = Color(1, 1, 1, 0.1)
	var field_focus := field.duplicate()
	field_focus.border_color = Color(ACCENT, 0.8)
	for cls in ["LineEdit", "TextEdit", "SpinBox"]:
		t.set_stylebox("normal", cls, field)
		t.set_stylebox("focus", cls, field_focus)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_placeholder_color", cls, Color(MUTED, 0.8))
		t.set_color("caret_color", cls, ACCENT)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", TEXT)

	t.set_stylebox("background", "ProgressBar", _box(Color(0, 0, 0, 0.5), 6, 0))
	t.set_stylebox("fill", "ProgressBar", _box(ACCENT, 6, 0))

	var popup := glass(12, 8, Color(0.06, 0.07, 0.09, 0.96))
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(Color(ACCENT, 0.25), 8, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_separator_color", "PopupMenu", ACCENT)
	t.set_constant("v_separation", "PopupMenu", 10)
	t.set_font_size("font_size", "PopupMenu", 16)
	t.set_stylebox("panel", "PopupPanel", popup)
	t.set_stylebox("panel", "TooltipPanel", glass(8, 8, Color(0.05, 0.06, 0.08, 0.95)))

	var grabber := _box(Color(1, 1, 1, 0.25), 4, 0)
	var scroll_bg := _box(Color(0, 0, 0, 0), 4, 0)
	scroll_bg.content_margin_left = 3
	scroll_bg.content_margin_right = 3
	for cls in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", cls, scroll_bg)
		t.set_stylebox("grabber", cls, grabber)
		t.set_stylebox("grabber_highlight", cls, _box(Color(ACCENT, 0.6), 4, 0))
		t.set_stylebox("grabber_pressed", cls, _box(ACCENT, 4, 0))
	var slider := _box(Color(1, 1, 1, 0.12), 4, 0)
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", _box(Color(ACCENT, 0.7), 4, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT, 4, 0))
	return t


static func title(text: String, size: int = 22) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(true))
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


static func accent_button(text: String, callback: Callable) -> Button:
	var b := button(text, callback)
	var sb := _box(Color(ACCENT, 0.85), 10, 10)
	var sbh := _box(ACCENT.lightened(0.15), 10, 10)
	sbh.shadow_color = Color(ACCENT, 0.45)
	sbh.shadow_size = 12
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.2), 10, 10))
	b.add_theme_color_override("font_color", Color("#1a1206"))
	b.add_theme_color_override("font_hover_color", Color("#1a1206"))
	b.add_theme_font_override("font", font(true))
	return b


static func chip(text: String, color: Color = ACCENT, size: int = 13) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(Color(color, 0.16), 20, 4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.set_border_width_all(1)
	sb.border_color = Color(color, 0.55)
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color.lightened(0.2))
	p.add_child(l)
	return p


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
