extends Control

# Base das janelas sobrepostas: fundo escurecido, cartão de vidro centralizado, animação de abrir.

const UI = preload("res://ui/ui_theme.gd")
const IconButton = preload("res://ui/game/icon_button.gd")

var card: PanelContainer
var content: VBoxContainer
var title_label: Label
var card_size: Vector2 = Vector2(900, 600)


func _build_overlay(title: String, size_px: Vector2) -> void:
	card_size = size_px
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.glass(22, 22, Color(0.06, 0.07, 0.09, 0.95)))
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -size_px.x / 2
	card.offset_right = size_px.x / 2
	card.offset_top = -size_px.y / 2
	card.offset_bottom = size_px.y / 2
	add_child(card)
	var v := UI.vbox(14)
	card.add_child(v)
	var header := UI.hbox(10)
	v.add_child(header)
	title_label = UI.title(title, 26)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	var close_btn := IconButton.new("close", "Fechar", 40)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	content = UI.vbox(12)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(content)
	hide()


func _on_dim_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		close()


func open_overlay() -> void:
	show()
	modulate.a = 0.0
	card.pivot_offset = card_size / 2.0
	card.scale = Vector2(0.96, 0.96)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	tw.tween_property(card, "scale", Vector2.ONE, 0.22)


func close() -> void:
	hide()


func clear_content() -> void:
	for c in content.get_children():
		c.queue_free()


func _unhandled_input(e: InputEvent) -> void:
	if visible and e.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
