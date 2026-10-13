extends Control

# Caixa de conversa no espírito dos jogos de vida (Stardew Valley, The Sims): papel com moldura de
# madeira na parte de baixo da tela, retrato de quem fala à direita com a plaquinha do nome,
# texto que aparece letra a letra (clique completa; outro clique avança) e atalhos de conversa.
#
# Só aparece quando há interação:
#   • conversa  — falando com alguém (texto, atalhos e campo para escrever);
#   • mensagem  — algo da história para ler (narração, acontecimento); some ao terminar.
# Sem nada disso ela fica escondida e não ocupa nem bloqueia a tela.

signal submitted(text: String)
signal end_pressed
signal expression(emotion: String)
signal speaking_pulse
signal speech_finished
signal action_chosen(action_id: int)
signal more_pressed

const UI = preload("res://ui/ui_theme.gd")
const ExpressionEngine = preload("res://ai/expression_engine.gd")

const CPS := 52.0                      # letras por segundo do efeito de digitação
const H_TALK := 262.0
const H_MSG := 184.0
# atalhos de conversa (os mesmos do menu do botão direito)
const QUICK := [[1, "Perguntar o nome"], [2, "Pedir o número"], [3, "Elogiar"], [4, "Flertar"], [5, "Provocar"]]

var mode: String = ""                  # "", "conversa", "mensagem"
var frame: PanelContainer
var text_view: RichTextLabel
var thinking: Label
var hint: Label
var quick_row: HBoxContainer
var talk_row: HBoxContainer
var input: LineEdit
var send_btn: Button
var end_btn: Button
var side: VBoxContainer
var portrait_slot: PanelContainer
var name_plate: PanelContainer
var name_label: Label
var rel_label: Label
var star_re := RegEx.new()

var _queue: Array = []                 # mensagens esperando a vez: [entrada, quem fala]
var _anim: Tween
var _closing := false
var _typing := false
var _vis := 0.0
var _total_chars := 0
var _last_chars := 0
var _segs: Array = []
var _seg_next := 0
var _pulse_t := 0.0
var _plain := ""
var _settle_t := -1.0
var _read_t := -1.0                    # mensagem: tempo de leitura antes de seguir sozinha
var _thinking_who := ""
var _dots := 0.0
var _hint_t := 0.0
var _portrait: Control


func _ready() -> void:
	star_re.compile("\\*([^*]+)\\*")
	UI.warm_fonts()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	frame = PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UI.paper(14, 16))
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.gui_input.connect(_on_frame_input)
	add_child(frame)
	var row := UI.hbox(16)
	frame.add_child(row)

	# coluna do texto
	var col := UI.vbox(8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	text_view = RichTextLabel.new()
	text_view.bbcode_enabled = true
	text_view.scroll_active = true
	text_view.scroll_following = false
	text_view.mouse_filter = Control.MOUSE_FILTER_PASS
	text_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_view.custom_minimum_size = Vector2(0, 64)
	text_view.add_theme_font_override("normal_font", UI.serif())
	text_view.add_theme_font_override("bold_font", UI.serif(true))
	text_view.add_theme_font_override("italics_font", UI.serif_italic())
	for k in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		text_view.add_theme_font_size_override(k, 20)
	text_view.add_theme_color_override("default_color", UI.INK)
	text_view.add_theme_constant_override("line_separation", 5)
	col.add_child(text_view)

	var foot := UI.hbox(8)
	col.add_child(foot)
	thinking = Label.new()
	thinking.autowrap_mode = TextServer.AUTOWRAP_OFF
	thinking.clip_text = true
	thinking.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	thinking.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thinking.add_theme_font_override("font", UI.serif())
	thinking.add_theme_font_size_override("font_size", 15)
	thinking.add_theme_color_override("font_color", UI.INK_SOFT)
	foot.add_child(thinking)
	hint = Label.new()
	hint.text = "clique / Enter para continuar  ▼"
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UI.INK_SOFT)
	foot.add_child(hint)

	quick_row = UI.hbox(6)
	col.add_child(quick_row)
	for q in QUICK:
		var qb := UI.paper_button(str(q[1]), func() -> void: action_chosen.emit(int(q[0])), 14)
		qb.focus_mode = Control.FOCUS_NONE
		quick_row.add_child(qb)
	var more := UI.paper_button("Mais…", func() -> void: more_pressed.emit(), 14)
	more.focus_mode = Control.FOCUS_NONE
	more.tooltip_text = "Todas as ações: ameaçar, dar dinheiro, dar item, roubar..."
	quick_row.add_child(more)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quick_row.add_child(gap)
	end_btn = UI.paper_button("Encerrar", func() -> void: end_pressed.emit(), 14)
	end_btn.focus_mode = Control.FOCUS_NONE
	end_btn.add_theme_color_override("font_color", Color("#8a2a1e"))
	end_btn.add_theme_color_override("font_hover_color", Color("#a32a1e"))
	end_btn.tooltip_text = "Encerrar a conversa (Esc)"
	quick_row.add_child(end_btn)

	talk_row = UI.hbox(8)
	col.add_child(talk_row)
	input = LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 42)
	input.add_theme_font_size_override("font_size", 16)
	var field := UI._box(UI.PAPER_LIGHT, 8, 10)
	field.set_border_width_all(2)
	field.border_color = UI.PAPER_EDGE
	var field_f := field.duplicate()
	field_f.border_color = UI.ACCENT.darkened(0.2)
	input.add_theme_stylebox_override("normal", field)
	input.add_theme_stylebox_override("focus", field_f)
	input.add_theme_stylebox_override("read_only", field)
	input.add_theme_color_override("font_color", UI.INK)
	input.add_theme_color_override("font_uneditable_color", UI.INK_SOFT)
	input.add_theme_color_override("font_placeholder_color", Color(UI.INK_SOFT, 0.75))
	input.add_theme_color_override("caret_color", UI.INK)
	input.text_submitted.connect(func(_t): _submit())
	talk_row.add_child(input)
	send_btn = UI.accent_button("Falar", _submit)
	send_btn.custom_minimum_size = Vector2(86, 42)
	send_btn.focus_mode = Control.FOCUS_NONE
	talk_row.add_child(send_btn)

	# coluna do retrato: moldura de madeira, plaquinha com o nome e a relação
	side = UI.vbox(6)
	side.custom_minimum_size = Vector2(146, 0)
	row.add_child(side)
	portrait_slot = PanelContainer.new()
	var pf := UI._box(Color("#cdbf9f"), 10, 0)
	pf.set_border_width_all(4)
	pf.border_color = UI.WOOD
	portrait_slot.add_theme_stylebox_override("panel", pf)
	portrait_slot.custom_minimum_size = Vector2(146, 168)
	portrait_slot.clip_contents = true
	side.add_child(portrait_slot)
	name_plate = PanelContainer.new()
	name_plate.add_theme_stylebox_override("panel", UI.plate())
	name_label = Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# nomes longos ("Garçonete de rabo de cavalo") quebram em até duas linhas em vez de serem cortados
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	name_label.custom_minimum_size = Vector2(118, 0)
	name_label.add_theme_font_override("font", UI.serif(true))
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_constant_override("line_spacing", -2)
	name_label.add_theme_color_override("font_color", UI.TEXT)
	name_plate.add_child(name_label)
	side.add_child(name_plate)
	rel_label = Label.new()
	rel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rel_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	rel_label.clip_text = true
	rel_label.add_theme_font_size_override("font_size", 13)
	rel_label.add_theme_color_override("font_color", UI.INK_SOFT)
	side.add_child(rel_label)
	_apply_mode()


# ---------- modos ----------

# Começa uma conversa: retrato de quem fala, atalhos e campo para escrever.
func begin_conversation(speaker: String, relation: String, portrait: Control) -> void:
	mode = "conversa"
	_queue.clear()
	_read_t = -1.0
	set_speaker(speaker, relation)
	set_portrait(portrait)
	_apply_mode()
	open_box()


# Termina a conversa: some, a não ser que haja mensagem da história esperando.
func end_conversation() -> void:
	if mode != "conversa":
		return
	set_portrait(null)
	mode = ""
	if not _queue.is_empty():
		_next_message()
	else:
		close_box()


# Mensagem da história fora de conversa (narração, acontecimento). Entra na fila e aparece em ordem.
func push_message(e: Dictionary, speaker: String) -> void:
	if mode == "conversa":
		set_speaker(speaker)
		show_entry(e)
		return
	_queue.append([e, speaker])
	if mode != "mensagem" or (not _typing and _read_t < 0.0 and _thinking_who == ""):
		_next_message()


func _next_message() -> void:
	if _queue.is_empty():
		mode = ""
		close_box()
		return
	var it: Array = _queue.pop_front()
	mode = "mensagem"
	set_portrait(null)
	set_speaker(str(it[1]))
	_apply_mode()
	show_entry(it[0])
	open_box()


func _apply_mode() -> void:
	var talk := mode == "conversa"
	quick_row.visible = talk
	talk_row.visible = talk
	end_btn.visible = talk
	portrait_slot.visible = talk and _portrait != null
	rel_label.visible = talk and rel_label.text != ""
	side.custom_minimum_size.x = 146 if talk else 150
	hint.visible = false
	offset_top = offset_bottom - (H_TALK if talk else H_MSG)


func set_portrait(p: Control) -> void:
	if _portrait != null and is_instance_valid(_portrait) and _portrait.get_parent() == portrait_slot:
		portrait_slot.remove_child(_portrait)
	_portrait = p
	if p != null:
		if p.get_parent() != null:
			p.get_parent().remove_child(p)
		# mesma proporção do retrato do jogador (rosto e ombros inteiros)
		p.custom_minimum_size = Vector2(138, 160)
		portrait_slot.add_child(p)
	portrait_slot.visible = mode == "conversa" and p != null


func open_box() -> void:
	if visible and not _closing:
		return
	_closing = false
	visible = true
	if _anim:
		_anim.kill()
	modulate.a = 0.0
	frame.position.y = 22.0
	_anim = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_anim.tween_property(self, "modulate:a", 1.0, 0.18)
	_anim.tween_property(frame, "position:y", 0.0, 0.22)


func close_box() -> void:
	if not visible or _closing:
		return
	_closing = true
	_typing = false
	_read_t = -1.0
	if _anim:
		_anim.kill()
	_anim = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_anim.tween_property(self, "modulate:a", 0.0, 0.14)
	_anim.tween_property(frame, "position:y", 16.0, 0.14)
	_anim.chain().tween_callback(func() -> void:
		visible = false
		_closing = false
		frame.position.y = 0.0
		text_view.clear()
		thinking.text = "")


# ---------- conteúdo ----------

func set_thinking(who: String) -> void:
	_thinking_who = who
	if who == "":
		thinking.text = ""
		# narrador terminou sem nada para mostrar: não deixa a caixa vazia na tela
		if mode == "mensagem" and not _typing and _read_t < 0.0 and _queue.is_empty() and text_view.get_total_character_count() == 0:
			mode = ""
			close_box()
	elif mode == "":
		# alguém está escrevendo algo para o jogador (ex.: o narrador no começo da história)
		mode = "mensagem"
		set_portrait(null)
		set_speaker("Narrador")
		text_view.clear()
		_apply_mode()
		open_box()


func set_speaker(speaker: String, relation: String = "") -> void:
	name_plate.visible = speaker != ""
	name_label.text = speaker
	rel_label.text = relation
	rel_label.visible = mode == "conversa" and relation != ""


func set_input(enabled: bool, placeholder: String, show_end: bool, end_text: String = "Encerrar") -> void:
	input.editable = enabled
	input.placeholder_text = placeholder
	send_btn.disabled = not enabled
	for b in quick_row.get_children():
		if b is Button and b != end_btn:
			(b as Button).disabled = not enabled
	end_btn.visible = show_end and mode == "conversa"
	end_btn.text = end_text


func _format(e: Dictionary) -> String:
	var kind := str(e.get("kind", "info"))
	var col: String = UI.INK_COLORS.get(kind, "#2e2218")
	var act := "[i][color=%s]$1[/color][/i]" % UI.INK_SOFT.to_html(false)
	var text := star_re.sub(UI.escape_bbcode(str(e.get("text", ""))), act, true)
	match kind:
		"player":
			return "[color=%s][b]Você:[/b] %s[/color]" % [col, text]
		"narration":
			return "[i][color=%s]%s[/color][/i]" % [col, text]
		"death":
			return "[b][color=%s]%s[/color][/b]" % [col, text]
	return "[color=%s]%s[/color]" % [col, text]


func show_entry(e: Dictionary) -> void:
	var kind := str(e.get("kind", "info"))
	if kind == "system":
		return
	text_view.clear()
	text_view.append_text(_format(e))
	text_view.scroll_to_line(0)
	_total_chars = text_view.get_total_character_count()
	_plain = text_view.get_parsed_text()
	_vis = 0.0
	_last_chars = 0
	_settle_t = -1.0
	_read_t = -1.0
	hint.visible = false
	text_view.visible_characters = 0
	_typing = _total_chars > 0
	_segs = []
	_seg_next = 0
	if kind == "npc":
		var base := "neutro"
		if NPCManager.talking_to != "" and NPCManager.state.has(NPCManager.talking_to):
			base = str(NPCManager.state[NPCManager.talking_to].get("emocao", "neutro"))
		_segs = ExpressionEngine.segments(str(e.get("text", "")), _plain, base)
	if not _typing:
		_finish_typing()


func _finish_typing() -> void:
	_typing = false
	text_view.visible_characters = -1
	while _seg_next < _segs.size():
		expression.emit(str(_segs[_seg_next]["emotion"]))
		_seg_next += 1
	if not _segs.is_empty():
		_settle_t = 1.4
	if mode == "mensagem":
		hint.visible = true
		_hint_t = 0.0
		# tempo para ler; depois segue sozinha (o clique adianta)
		_read_t = clampf(_plain.length() * 0.055, 3.0, 9.0)


func _process(delta: float) -> void:
	if not visible:
		return
	if _thinking_who != "":
		_dots += delta * 3.0
		var t := _thinking_who + ".".repeat(1 + int(_dots) % 3)
		if thinking.text != t:
			thinking.text = t
	if _typing:
		_vis += delta * CPS
		var n := mini(int(_vis), _total_chars)
		if n != _last_chars:
			text_view.visible_characters = n
			while _seg_next < _segs.size() and int(_segs[_seg_next]["start"]) <= n:
				expression.emit(str(_segs[_seg_next]["emotion"]))
				_seg_next += 1
			_pulse_t -= delta
			if not _segs.is_empty() and _pulse_t <= 0.0 and _plain.substr(maxi(n - 1, 0), 1).strip_edges() != "":
				speaking_pulse.emit()
				_pulse_t = 0.1
			_last_chars = n
		if n >= _total_chars:
			_finish_typing()
	elif _settle_t >= 0.0:
		_settle_t -= delta
		if _settle_t < 0.0:
			speech_finished.emit()
	if hint.visible:
		_hint_t += delta
		hint.modulate.a = 0.55 + 0.45 * sin(_hint_t * 4.0)
	if _read_t >= 0.0 and mode == "mensagem":
		_read_t -= delta
		if _read_t < 0.0:
			_next_message()


# Clique na caixa: completa o texto que está aparecendo; se já está completo, avança a mensagem.
func _on_frame_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_advance()


func _advance() -> void:
	if _typing:
		_vis = float(_total_chars)
		_finish_typing()
	elif mode == "mensagem":
		_next_message()


func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey and e.pressed and not e.echo):
		return
	if mode == "mensagem" and e.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]:
		_advance()
		get_viewport().set_input_as_handled()
	elif mode == "mensagem" and e.keycode == KEY_ESCAPE:
		_queue.clear()
		mode = ""
		close_box()
		get_viewport().set_input_as_handled()


func _submit() -> void:
	var text := input.text.strip_edges()
	if text == "" or not input.editable:
		return
	input.text = ""
	submitted.emit(text)
