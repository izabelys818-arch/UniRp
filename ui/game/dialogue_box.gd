extends PanelContainer

signal submitted(text: String)
signal end_pressed

const UI = preload("res://ui/ui_theme.gd")
const IconButton = preload("res://ui/game/icon_button.gd")
const HistoryPanel = preload("res://ui/game/history_panel.gd")

var name_chip: PanelContainer
var name_label: Label
var rel_chip: PanelContainer
var rel_label: Label
var text_view: RichTextLabel
var thinking: Label
var input: LineEdit
var send_btn: IconButton
var end_btn: Button
var star_re := RegEx.new()
var _type_tween: Tween
var _dots: float = 0.0
var _thinking_who: String = ""


func _ready() -> void:
	star_re.compile("\\*([^*]+)\\*")
	add_theme_stylebox_override("panel", UI.glass(18, 18, Color(0.04, 0.05, 0.07, 0.86)))
	var v := UI.vbox(10)
	add_child(v)
	var top := UI.hbox(10)
	v.add_child(top)
	name_chip = PanelContainer.new()
	var sb := UI._box(Color(UI.ACCENT, 0.9), 8, 6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	name_chip.add_theme_stylebox_override("panel", sb)
	name_label = Label.new()
	name_label.add_theme_font_override("font", UI.font(true))
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color("#1a1206"))
	name_chip.add_child(name_label)
	top.add_child(name_chip)
	rel_chip = UI.chip("", UI.TEAL, 13)
	rel_label = rel_chip.get_child(0)
	top.add_child(rel_chip)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	thinking = UI.label("", 14, UI.ACCENT)
	top.add_child(thinking)
	end_btn = UI.button("Encerrar", func(): end_pressed.emit())
	end_btn.add_theme_font_size_override("font_size", 14)
	top.add_child(end_btn)

	text_view = RichTextLabel.new()
	text_view.bbcode_enabled = true
	text_view.fit_content = false
	text_view.scroll_active = true
	text_view.custom_minimum_size = Vector2(0, 92)
	text_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_view.add_theme_font_size_override("normal_font_size", 20)
	text_view.add_theme_font_size_override("italics_font_size", 20)
	text_view.add_theme_font_size_override("bold_font_size", 20)
	text_view.add_theme_constant_override("line_separation", 4)
	v.add_child(text_view)

	var row := UI.hbox(8)
	v.add_child(row)
	input = LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 44)
	input.add_theme_font_size_override("font_size", 17)
	input.text_submitted.connect(func(_t): _submit())
	row.add_child(input)
	send_btn = IconButton.new("send", "Falar (Enter)", 44)
	send_btn.icon_color = UI.ACCENT
	send_btn.pressed.connect(_submit)
	row.add_child(send_btn)


func _process(delta: float) -> void:
	if _thinking_who != "":
		_dots += delta * 3.0
		thinking.text = _thinking_who + ".".repeat(1 + int(_dots) % 3)


func set_thinking(who: String) -> void:
	_thinking_who = who
	if who == "":
		thinking.text = ""


func set_speaker(speaker: String, relation: String = "") -> void:
	name_chip.visible = speaker != ""
	name_label.text = speaker
	rel_chip.visible = relation != ""
	rel_label.text = relation


func set_input(enabled: bool, placeholder: String, show_end: bool, end_text: String = "Encerrar") -> void:
	input.editable = enabled
	input.placeholder_text = placeholder
	send_btn.disabled = not enabled
	end_btn.visible = show_end
	end_btn.text = end_text


func show_entry(e: Dictionary) -> void:
	var kind := str(e.get("kind", "info"))
	if kind == "system":
		return
	var body := HistoryPanel.format_entry(e, star_re)
	if kind == "npc":
		var raw := star_re.sub(UI.escape_bbcode(str(e.get("text", ""))), "[i][color=#a39f95]$1[/color][/i]", true)
		body = "[color=%s]%s[/color]" % [UI.KIND_COLORS["npc"], raw]
	text_view.clear()
	text_view.append_text(body)
	text_view.visible_ratio = 0.0
	if _type_tween:
		_type_tween.kill()
	var length := str(e.get("text", "")).length()
	_type_tween = create_tween()
	_type_tween.tween_property(text_view, "visible_ratio", 1.0, clampf(length * 0.022, 0.15, 2.8))


func _submit() -> void:
	var text := input.text.strip_edges()
	if text == "" or not input.editable:
		return
	input.text = ""
	submitted.emit(text)
