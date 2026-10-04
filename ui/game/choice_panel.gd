extends Control

# Janela de decisão dramática (abordagem da polícia, incêndio, soltura). Não fecha sem escolher.

const UI = preload("res://ui/ui_theme.gd")

var card: PanelContainer
var box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	card = PanelContainer.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -300
	card.offset_right = 300
	card.offset_top = -190
	card.offset_bottom = 190
	add_child(card)
	box = UI.vbox(14)
	card.add_child(box)
	hide()


func show_choice(data: Dictionary) -> void:
	for c in box.get_children():
		c.queue_free()
	var kind := str(data.get("kind", "info"))
	var accent: Color = {"police": Color("#4f8bff"), "fire": Color("#ff7a2e"), "info": UI.ACCENT}.get(kind, UI.ACCENT)
	var sb := UI.glass(22, 26, Color(0.05, 0.06, 0.08, 0.97))
	sb.set_border_width_all(2)
	sb.border_color = Color(accent, 0.8)
	card.add_theme_stylebox_override("panel", sb)
	var title := UI.title(str(data.get("title", "")), 40)
	title.add_theme_color_override("font_color", accent)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var text := UI.label(str(data.get("text", "")), 17)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(text)
	box.add_child(Control.new())
	for opt in data.get("options", []):
		var b := UI.button(str(opt["label"]), _pick.bind(opt["callback"]))
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_font_size_override("font_size", 18)
		box.add_child(b)
	show()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)


func _pick(callback: Callable) -> void:
	hide()
	callback.call()
