extends Control

const UI = preload("res://ui/ui_theme.gd")
const SCREEN_BG := Color("#0f1216")
const BUBBLE_ME := Color("#1f5c4a")
const BUBBLE_THEM := Color("#2a2e35")

var frame: PanelContainer
var title_label: Label
var back_btn: Button
var clock_label: Label
var body: VBoxContainer
var screen: String = "home"
var screen_arg: String = ""
var typing_label: Label
var msg_input: LineEdit


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(dim)

	frame = PanelContainer.new()
	var sb := UI._box(Color("#050607"), 34, 12)
	sb.set_border_width_all(4)
	sb.border_color = Color("#2b2f36")
	frame.add_theme_stylebox_override("panel", sb)
	frame.custom_minimum_size = Vector2(380, 690)
	frame.anchor_left = 0.5
	frame.anchor_right = 0.5
	frame.anchor_top = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -190
	frame.offset_right = 190
	frame.offset_top = -345
	frame.offset_bottom = 345
	add_child(frame)

	var screen_panel := PanelContainer.new()
	screen_panel.add_theme_stylebox_override("panel", UI._box(SCREEN_BG, 24, 10))
	frame.add_child(screen_panel)
	var v := UI.vbox(8)
	screen_panel.add_child(v)

	var status := UI.hbox()
	v.add_child(status)
	clock_label = UI.label("", 13, UI.TEXT)
	clock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(clock_label)
	var signal_label := UI.label("4G   83%", 12, UI.MUTED)
	signal_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.add_child(signal_label)

	var header := UI.hbox()
	v.add_child(header)
	back_btn = UI.button("<", _back)
	back_btn.custom_minimum_size = Vector2(36, 32)
	header.add_child(back_btn)
	title_label = UI.title("", 18)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	header.add_child(UI.button("X", close))

	body = UI.vbox(8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	PhoneSystem.thread_updated.connect(_on_thread_updated)
	PhoneSystem.typing_changed.connect(_on_typing)
	PhoneSystem.changed.connect(_on_changed)
	TimeManager.time_advanced.connect(_update_clock.unbind(2))
	visibility_changed.connect(_on_visibility)
	hide()


func open(to_screen: String = "home", arg: String = "") -> void:
	show()
	_go(to_screen, arg)


func close() -> void:
	PhoneSystem.open_thread = ""
	hide()


func _on_visibility() -> void:
	if not visible:
		PhoneSystem.open_thread = ""


func _update_clock() -> void:
	clock_label.text = "%02d:%02d" % [TimeManager.hour(), TimeManager.minute()]


func _back() -> void:
	match screen:
		"thread", "calling":
			_go("threads" if screen == "thread" else "contacts")
		_:
			_go("home")


func _go(to_screen: String, arg: String = "") -> void:
	var same_thread := screen == "thread" and to_screen == "thread" and screen_arg == arg
	screen = to_screen
	screen_arg = arg
	PhoneSystem.open_thread = arg if to_screen == "thread" else ""
	_update_clock()
	var draft := msg_input.text if same_thread and msg_input != null and is_instance_valid(msg_input) else ""
	for c in body.get_children():
		c.queue_free()
	typing_label = null
	msg_input = null
	back_btn.visible = to_screen != "home"
	match to_screen:
		"home": _home()
		"threads": _threads()
		"thread":
			_thread(arg)
			msg_input.text = draft
		"contacts": _contacts()
		"bank": _bank()
		"calling": _calling(arg)
		"emergency": _emergency()


func _app_button(label: String, color: Color, badge: int, target: String) -> Control:
	var box := UI.vbox(4)
	var b := Button.new()
	b.custom_minimum_size = Vector2(84, 84)
	b.text = str(badge) if badge > 0 else ""
	b.add_theme_font_size_override("font_size", 22)
	for st in ["normal", "hover", "pressed"]:
		var sb := UI._box(color if st != "hover" else color.lightened(0.15), 20, 0)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.pressed.connect(_go.bind(target))
	box.add_child(b)
	var l := UI.label(label, 13)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box


func _home() -> void:
	title_label.text = ""
	var big := UI.title("%02d:%02d" % [TimeManager.hour(), TimeManager.minute()], 56)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(big)
	var date := UI.label("Dia %d • %s • %s" % [TimeManager.day(), TimeManager.weekday(), GameState.CITY], 14, UI.MUTED)
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(date)
	body.add_child(Control.new())
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 14)
	var center := CenterContainer.new()
	center.add_child(grid)
	body.add_child(center)
	grid.add_child(_app_button("Mensagens", Color("#2e8b57"), PhoneSystem.unread(), "threads"))
	grid.add_child(_app_button("Contatos", Color("#3b6ea8"), 0, "contacts"))
	grid.add_child(_app_button("Banco", Color("#7a4fb0"), 0, "bank"))
	grid.add_child(_app_button("Emergência", Color("#b83a3a"), 0, "emergency"))


func _threads() -> void:
	title_label.text = "Mensagens"
	var list := UI.vbox(6)
	body.add_child(UI.scroll(list))
	var ids: Array = PhoneSystem.phone()["contacts"].duplicate()
	ids.sort_custom(func(a, b): return PhoneSystem.thread(a).size() > PhoneSystem.thread(b).size())
	if ids.is_empty():
		list.add_child(UI.label("Nenhum contato ainda. Converse com as pessoas da cidade: se confiarem em você, elas te passam o número.", 14, UI.MUTED))
	for id in ids:
		var th := PhoneSystem.thread(id)
		var last: String = th[-1]["texto"] if not th.is_empty() else "Toque para conversar"
		var n := PhoneSystem.unread(id)
		var b := Button.new()
		b.text = "%s%s\n%s" % [NPCManager.display_name(id), "  (%d)" % n if n > 0 else "", last.left(38)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 58)
		b.pressed.connect(_go.bind("thread", id))
		if n > 0:
			b.add_theme_color_override("font_color", UI.ACCENT)
		list.add_child(b)


func _bubble(text: String, mine: bool, time: String, status: String) -> Control:
	var row := UI.hbox(0)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI._box(BUBBLE_ME if mine else BUBBLE_THEM, 12, 8))
	var v := UI.vbox(2)
	pc.add_child(v)
	var l := UI.label(text, 15)
	l.custom_minimum_size = Vector2(minf(250, 30 + text.length() * 8.0), 0)
	v.add_child(l)
	var meta := UI.label(time + ("  " + status if mine and status != "" else ""), 11, UI.MUTED)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(meta)
	if mine:
		row.add_child(spacer)
		row.add_child(pc)
	else:
		row.add_child(pc)
		row.add_child(spacer)
	return row


func _thread(id: String) -> void:
	PhoneSystem.mark_read(id)
	title_label.text = NPCManager.display_name(id)
	var top := UI.hbox()
	body.add_child(top)
	var rel := UI.label(NPCManager.relation_label(id), 13, UI.MUTED)
	rel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(rel)
	top.add_child(UI.button("Ligar", _go.bind("calling", id)))
	var list := UI.vbox(6)
	var sc := UI.scroll(list)
	body.add_child(sc)
	for m in PhoneSystem.thread(id):
		list.add_child(_bubble(m["texto"], m["eu"], m["hora"], m.get("status", "")))
	if not PhoneSystem.can_reach(id):
		list.add_child(UI.label("Não é possível mandar mensagens para este contato.", 13, UI.DANGER))
	typing_label = UI.label("", 13, UI.ACCENT)
	body.add_child(typing_label)
	var row := UI.hbox(6)
	body.add_child(row)
	msg_input = LineEdit.new()
	msg_input.placeholder_text = "Mensagem"
	msg_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_input.text_submitted.connect(func(_t): _send(id))
	row.add_child(msg_input)
	row.add_child(UI.button("Enviar", _send.bind(id)))
	_scroll_to_end.call_deferred(sc)
	msg_input.grab_focus.call_deferred()


func _scroll_to_end(sc: ScrollContainer) -> void:
	await get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)


func _send(id: String) -> void:
	if msg_input == null or msg_input.text.strip_edges() == "":
		return
	var text := msg_input.text
	msg_input.text = ""
	PhoneSystem.send_message(id, text)


func _contacts() -> void:
	title_label.text = "Contatos"
	var list := UI.vbox(8)
	body.add_child(UI.scroll(list))
	var ids: Array = PhoneSystem.phone()["contacts"]
	if ids.is_empty():
		list.add_child(UI.label("Ninguém te passou o número ainda.\nConverse, ganhe confiança e peça o contato das pessoas.", 14, UI.MUTED))
	for id in ids:
		var card := UI.vbox(4)
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI._box(BUBBLE_THEM, 10, 10))
		pc.add_child(card)
		list.add_child(pc)
		card.add_child(UI.label(NPCManager.display_name(id), 16, UI.TEXT))
		card.add_child(UI.label(NPCManager.relation_label(id), 13, UI.ACCENT))
		var row := UI.hbox(6)
		card.add_child(row)
		row.add_child(UI.button("Mensagem", _go.bind("thread", id)))
		row.add_child(UI.button("Ligar", _go.bind("calling", id)))


func _bank() -> void:
	title_label.text = "Banco"
	var saldo := UI.title("R$ %d" % GameState.money(), 36)
	body.add_child(UI.label("Saldo disponível", 13, UI.MUTED))
	body.add_child(saldo)
	body.add_child(UI.label("Fazer PIX", 15, UI.ACCENT))
	var ids: Array = PhoneSystem.phone()["contacts"]
	var row := UI.hbox(6)
	body.add_child(row)
	var who := OptionButton.new()
	for id in ids:
		who.add_item(NPCManager.display_name(id))
		who.set_item_metadata(who.item_count - 1, id)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(who)
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = 100000
	amount.value = 20
	amount.prefix = "R$"
	row.add_child(amount)
	var result := UI.label("", 13, UI.MUTED)
	var send := UI.button("Enviar PIX", func():
		if who.item_count == 0:
			result.text = "Você não tem contatos."
			return
		var ok := PhoneSystem.send_pix(who.get_item_metadata(who.selected), int(amount.value))
		result.text = "PIX enviado!" if ok else "Não foi possível enviar (saldo ou contato)."
		saldo.text = "R$ %d" % GameState.money())
	body.add_child(send)
	body.add_child(result)
	body.add_child(UI.label("Extrato", 15, UI.ACCENT))
	var list := UI.vbox(4)
	body.add_child(UI.scroll(list))
	var entries: Array = PhoneSystem.phone()["bank_log"].duplicate()
	entries.reverse()
	if entries.is_empty():
		list.add_child(UI.label("Nenhuma movimentação.", 13, UI.MUTED))
	for e in entries:
		var v := int(e["valor"])
		list.add_child(UI.label("%s   %s R$ %d\n%s" % [e["desc"], "+" if v > 0 else "-", absi(v), e["hora"]], 13, Color("#7fd18b") if v > 0 else Color("#e0787f")))


func _calling(id: String) -> void:
	title_label.text = ""
	var box := UI.vbox(14)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(box)
	box.add_child(Control.new())
	var who_label := UI.title(NPCManager.display_name(id), 26)
	who_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(who_label)
	var st := UI.label("Chamando...", 16, UI.MUTED)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(st)
	await get_tree().create_timer(1.6).timeout
	if not is_instance_valid(st) or screen != "calling":
		return
	match PhoneSystem.call_contact(id):
		"atendeu":
			close()
		"caixa_postal":
			st.text = "Caixa postal. Parece que está dormindo."
		"bloqueado":
			st.text = "Chamada não completada."
		_:
			st.text = "Não atendeu."


func _emergency() -> void:
	title_label.text = "Emergência"
	body.add_child(UI.label("Ligue só se for de verdade. Trotes e chamadas falsas podem te complicar.", 14, UI.MUTED))
	for spec in [[190, "Polícia", "Denunciar uma agressão ou crime. Só adianta se tiver acabado de acontecer.", Color("#4f8bff")], [192, "SAMU", "Ambulância para quem está ferido. Te leva ao hospital (SUS).", Color("#e8554e")], [193, "Bombeiros", "Incêndios e resgates.", Color("#ff7a2e")]]:
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI._box(Color(spec[3], 0.16), 14, 12))
		var v := UI.vbox(6)
		pc.add_child(v)
		v.add_child(UI.title("%d  %s" % [spec[0], spec[1]], 22))
		v.add_child(UI.label(spec[2], 13, UI.MUTED))
		v.add_child(UI.accent_button("Ligar para o %d" % spec[0], _call_emergency.bind(spec[0])))
		body.add_child(pc)


func _call_emergency(number: int) -> void:
	close()
	CrimeSystem.emergency(number)


func _on_thread_updated(id: String) -> void:
	if visible and screen == "thread" and screen_arg == id:
		_go("thread", id)


func _on_typing(id: String, typing: bool) -> void:
	if typing_label != null and is_instance_valid(typing_label) and screen_arg == id:
		typing_label.text = ("%s está digitando..." % NPCManager.display_name(id)) if typing else ""


func _on_changed() -> void:
	if visible and screen in ["home", "threads", "contacts"]:
		_go(screen, screen_arg)
