extends RefCounted

# Linguagem visual "madeira e papel": painéis de madeira escura com aro mais claro (HUD e menus),
# papel envelhecido com tinta escura (caixa de conversa), dourado quente para destaque.
# Inspirado no aconchego de Stardew Valley e na clareza de The Sims, no tom melancólico do UniRp.
const BG := Color("#0d0a08")
const PANEL := Color(0.13, 0.1, 0.075, 0.94)
const PANEL_LIGHT := Color(0.24, 0.18, 0.13, 0.95)
const ACCENT := Color("#f0b04a")
const TEAL := Color("#6cc9a8")
const TEXT := Color("#fff3dc")
const MUTED := Color("#d0bea0")
const DANGER := Color("#e8695a")
const GLASS := Color(0.12, 0.09, 0.066, 0.93)
const EDGE := Color("#6e5236")
# papel e madeira
const PAPER := Color("#f2e7cf")
const PAPER_LIGHT := Color("#fbf4e3")
const PAPER_EDGE := Color("#c9b38a")
const INK := Color("#2e2218")
const INK_SOFT := Color("#6f5a43")
const WOOD := Color("#3a2a1d")
const WOOD_DARK := Color("#22180f")
const WOOD_LIGHT := Color("#8a6542")

const KIND_COLORS := {
	"info": "#c2b59c",
	"narration": "#e6dcc6",
	"player": "#8fc9ee",
	"npc": "#f3e9d4",
	"event": "#f4b26a",
	"danger": "#f07a6c",
	"death": "#ff4b3b",
	"error": "#f07a6c",
	"system": "#8a7e6c",
	"phone": "#7fdcb8",
}
# as mesmas categorias, para texto escrito sobre o papel da caixa de conversa
const INK_COLORS := {
	"info": "#7a6650",
	"narration": "#3b2e22",
	"player": "#1f4f78",
	"npc": "#2e2218",
	"event": "#8a4a12",
	"danger": "#a32a1e",
	"death": "#8a1010",
	"error": "#a32a1e",
	"system": "#7a6650",
	"phone": "#1f6a52",
}

static var _font: Font
static var _font_bold: Font
static var _serif: Font
static var _serif_bold: Font
static var _serif_it: Font


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


# Fonte de livro para falas e títulos (dá o ar de história contada).
static func serif(bold: bool = false) -> Font:
	if _serif == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Georgia", "Cambria", "Constantia", "Times New Roman", "serif"])
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_serif = f
		var fb := SystemFont.new()
		fb.font_names = PackedStringArray(["Georgia", "Cambria", "Constantia", "Times New Roman", "serif"])
		fb.font_weight = 700
		_serif_bold = fb
	return _serif_bold if bold else _serif


static func serif_italic() -> Font:
	if _serif_it == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Georgia", "Cambria", "Constantia", "Times New Roman", "serif"])
		f.font_italic = true
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_serif_it = f
	return _serif_it


# Carrega as fontes e rasteriza as letras comuns antes de precisar delas:
# sem isso a primeira fala da conversa engasgava (~150 ms) carregando a fonte do sistema.
static func warm_fonts() -> void:
	var chars := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789áàâãéêíóôõúüçÁÀÂÃÉÊÍÓÔÕÚÇ.,;:!?…—–-\"'()*%$/•▼ "
	for f in [serif(), serif(true), serif_italic(), font(), font(true)]:
		for sz in [13, 14, 15, 16, 17, 20]:
			(f as Font).get_string_size(chars, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)


static func _box(color: Color, radius: int = 10, margin: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


# Painel de madeira escura com aro mais claro (HUD, menus, janelas).
static func glass(radius: int = 16, margin: int = 14, tint: Color = GLASS) -> StyleBoxFlat:
	var sb := _box(tint, mini(radius, 14), margin)
	sb.set_border_width_all(2)
	sb.border_color = EDGE
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 5)
	return sb


# Papel envelhecido com moldura de madeira (caixa de conversa, cartões de leitura).
static func paper(radius: int = 14, margin: int = 16) -> StyleBoxFlat:
	var sb := _box(PAPER, radius, margin)
	sb.set_border_width_all(5)
	sb.border_color = WOOD
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, 6)
	return sb


# Plaquinha de madeira (nome de quem fala, abas).
static func plate(color: Color = WOOD, radius: int = 8) -> StyleBoxFlat:
	var sb := _box(color, radius, 6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.set_border_width_all(2)
	sb.border_color = WOOD_LIGHT
	return sb


# Botão claro para usar sobre o papel.
static func paper_button(text: String, callback: Callable, size: int = 15) -> Button:
	var b := button(text, callback)
	var n := _box(PAPER_LIGHT, 8, 6)
	n.content_margin_left = 12
	n.content_margin_right = 12
	n.set_border_width_all(2)
	n.border_color = PAPER_EDGE
	var h := n.duplicate()
	h.bg_color = Color("#fff8e8")
	h.border_color = ACCENT.darkened(0.15)
	var p := n.duplicate()
	p.bg_color = PAPER.darkened(0.08)
	p.border_color = WOOD_LIGHT
	var d := n.duplicate()
	d.bg_color = Color(PAPER_LIGHT, 0.5)
	d.border_color = Color(PAPER_EDGE, 0.5)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", p)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, INK)
	b.add_theme_color_override("font_disabled_color", Color(INK_SOFT, 0.5))
	b.add_theme_font_size_override("font_size", size)
	return b


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", glass())
	t.set_stylebox("panel", "Panel", glass())

	var btn := _box(Color("#3d2c1f"), 9, 9)
	btn.set_border_width_all(2)
	btn.border_color = Color("#5d4430")
	var hover := _box(Color("#55402c"), 9, 9)
	hover.set_border_width_all(2)
	hover.border_color = ACCENT
	hover.shadow_color = Color(ACCENT, 0.22)
	hover.shadow_size = 6
	var pressed := _box(Color("#2a1e14"), 9, 9)
	pressed.set_border_width_all(2)
	pressed.border_color = ACCENT
	var focused := _box(Color("#463522"), 9, 9)
	focused.set_border_width_all(2)
	focused.border_color = Color("#ffd27a")
	var disabled := _box(Color(0.2, 0.15, 0.1, 0.55), 9, 9)
	disabled.set_border_width_all(2)
	disabled.border_color = Color("#3d2c1f")
	for cls in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("disabled", cls, disabled)
		t.set_stylebox("focus", cls, focused)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_disabled_color", cls, Color(MUTED, 0.6))

	var field := _box(Color("#1c140e"), 9, 10)
	field.set_border_width_all(2)
	field.border_color = Color("#5d4430")
	var field_focus := field.duplicate()
	field_focus.border_color = Color(ACCENT, 0.8)
	field_focus.shadow_color = Color(ACCENT, 0.2)
	field_focus.shadow_size = 5
	for cls in ["LineEdit", "TextEdit", "SpinBox"]:
		t.set_stylebox("normal", cls, field)
		t.set_stylebox("focus", cls, field_focus)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_placeholder_color", cls, Color(MUTED, 0.8))
		t.set_color("caret_color", cls, ACCENT)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	# listas (modelos de IA nas configurações etc.)
	var list_bg := _box(Color("#1c140e"), 9, 8)
	list_bg.set_border_width_all(2)
	list_bg.border_color = Color("#5d4430")
	t.set_stylebox("panel", "ItemList", list_bg)
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("selected", "ItemList", _box(Color(ACCENT, 0.3), 6, 4))
	t.set_stylebox("selected_focus", "ItemList", _box(Color(ACCENT, 0.4), 6, 4))
	t.set_stylebox("hovered", "ItemList", _box(Color(1, 1, 1, 0.06), 6, 4))
	t.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_color("font_hovered_color", "ItemList", Color.WHITE)
	t.set_constant("v_separation", "ItemList", 6)
	t.set_color("default_color", "RichTextLabel", TEXT)

	t.set_stylebox("background", "ProgressBar", _box(Color(0, 0, 0, 0.5), 6, 0))
	t.set_stylebox("fill", "ProgressBar", _box(ACCENT, 6, 0))
	t.set_stylebox("separator", "HSeparator", _line(Color("#5d4430")))
	t.set_constant("separation", "HSeparator", 10)

	var popup := glass(12, 8, Color(0.11, 0.08, 0.06, 0.98))
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(Color(ACCENT, 0.28), 8, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_separator_color", "PopupMenu", ACCENT)
	t.set_constant("v_separation", "PopupMenu", 10)
	t.set_font_size("font_size", "PopupMenu", 16)
	t.set_stylebox("panel", "PopupPanel", popup)
	t.set_stylebox("panel", "TooltipPanel", glass(8, 8, Color(0.11, 0.08, 0.06, 0.97)))
	t.set_color("font_color", "TooltipLabel", TEXT)

	var grabber := _box(Color(WOOD_LIGHT, 0.7), 4, 0)
	var scroll_bg := _box(Color(0, 0, 0, 0), 4, 0)
	scroll_bg.content_margin_left = 3
	scroll_bg.content_margin_right = 3
	for cls in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", cls, scroll_bg)
		t.set_stylebox("grabber", cls, grabber)
		t.set_stylebox("grabber_highlight", cls, _box(Color(ACCENT, 0.6), 4, 0))
		t.set_stylebox("grabber_pressed", cls, _box(ACCENT, 4, 0))
	var slider := _box(Color("#3d2c1f"), 4, 0)
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", _box(Color(ACCENT, 0.7), 4, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT, 4, 0))
	return t


static func _line(c: Color) -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = c
	s.thickness = 2
	return s


static func title(text: String, size: int = 22) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", serif(true))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_y", 2)
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
	var sb := _box(ACCENT, 9, 10)
	sb.set_border_width_all(2)
	sb.border_color = Color("#9a6420")
	var sbh := _box(ACCENT.lightened(0.12), 9, 10)
	sbh.set_border_width_all(2)
	sbh.border_color = Color("#fff0c8")
	sbh.shadow_color = Color(ACCENT, 0.4)
	sbh.shadow_size = 10
	var sbp := _box(ACCENT.darkened(0.18), 9, 10)
	sbp.set_border_width_all(2)
	sbp.border_color = Color("#9a6420")
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("disabled", _box(Color(ACCENT, 0.35), 9, 10))
	b.add_theme_color_override("font_color", Color("#1a1206"))
	b.add_theme_color_override("font_hover_color", Color("#1a1206"))
	b.add_theme_font_override("font", font(true))
	return b


static func chip(text: String, color: Color = ACCENT, size: int = 13) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(Color(color.darkened(0.55), 0.85), 20, 4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.set_border_width_all(2)
	sb.border_color = Color(color, 0.6)
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
