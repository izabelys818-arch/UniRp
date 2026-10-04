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
		"news": _news()
		"bills": _bills()
		"homes": _homes()
		"shop": _shop()


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
	var date := UI.label("Dia %d • %s • %s" % [TimeManager.day(), TimeManager.weekday(), GameState.city()], 14, UI.MUTED)
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
	grid.add_child(_app_button("Contas", Color("#c98a1e"), HomeSystem.unpaid().size(), "bills"))
	grid.add_child(_app_button("Imóveis", Color("#2a8a9a"), 0, "homes"))
	grid.add_child(_app_button("Compras", Color("#a84a8a"), 0, "shop"))
	grid.add_child(_app_button("Jornal", Color("#6b7280"), 0, "news"))
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


func _news() -> void:
	title_label.text = "Jornal"
	if TimeManager.hour() >= 6:
		NewsSystem.ensure_columns()
	var list := UI.vbox(8)
	body.add_child(UI.scroll(list))
	var mast := UI.title("GAZETA DE %s" % GameState.city().to_upper(), 20)
	mast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(mast)
	var shown := 0
	for day in NewsSystem.days_with_news():
		if shown >= 4:
			break
		shown += 1
		list.add_child(UI.label("DIA %d • %s" % [day, TimeManager.WEEKDAYS[(day - 1) % 7].to_upper()], 12, UI.MUTED))
		var items := NewsSystem.edition(day)
		items.reverse()
		for e in items:
			var tints := {"crime": Color(UI.DANGER, 0.12), "evento": Color(1.0, 0.62, 0.26, 0.1), "coluna": Color(1, 1, 1, 0.03)}
			var c := _card(list, tints.get(e["tipo"], Color(1, 1, 1, 0.05)))
			c.add_child(UI.label(str(e["titulo"]), 15, UI.TEXT))
			c.add_child(UI.label(str(e["texto"]), 12, UI.MUTED))
	if shown == 0:
		list.add_child(UI.label("A primeira edição sai de manhã.", 13, UI.MUTED))


func _card(list: VBoxContainer, tint: Color = Color(1, 1, 1, 0.05)) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI._box(tint, 12, 10))
	var v := UI.vbox(5)
	pc.add_child(v)
	list.add_child(pc)
	return v


func _bills() -> void:
	title_label.text = "Contas e trabalho"
	var list := UI.vbox(8)
	body.add_child(UI.scroll(list))
	list.add_child(UI.label("SEU EMPREGO", 12, UI.MUTED))
	var j := JobSystem.job()
	if j.is_empty():
		list.add_child(UI.label("Desempregado. Converse com quem tem vaga: Zé (bar), Irene (mercado), Padre (igreja) ou Dona Cida (pensão).", 13, UI.MUTED))
	else:
		var jc := _card(list)
		jc.add_child(UI.title(str(j["cargo"]), 18))
		jc.add_child(UI.label("%s • %02dh às %02dh • R$ %d/h" % [World.locations[j["local"]]["nome"], int(j["turno"][0]), int(j["turno"][1]), int(j["salario_hora"])], 13))
		jc.add_child(UI.label("Faltas: %d/3  •  Ganho total: R$ %d" % [int(j["faltas"]), int(j["ganho_total"])], 13, UI.DANGER if int(j["faltas"]) > 0 else UI.MUTED))
	list.add_child(UI.label("MORADIA", 12, UI.MUTED))
	var home := HomeSystem.home_id()
	if home == "":
		list.add_child(UI.label("Sem casa. Veja o app Imóveis ou alugue um quarto na pensão.", 13, UI.MUTED))
	else:
		var hc := _card(list)
		hc.add_child(UI.title(World.locations[home]["nome"], 16))
		var kind: String = {"propria": "Casa própria", "alugada": "Alugada"}.get(HomeSystem.status_of(home), "")
		hc.add_child(UI.label("%s  •  luz %s  •  água %s  •  internet %s" % [kind, "ok" if HomeSystem.utils(home)["luz"] else "CORTADA", "ok" if HomeSystem.utils(home)["agua"] else "CORTADA", "ok" if HomeSystem.utils(home)["internet"] else "não"], 12, UI.MUTED))
	list.add_child(UI.label("CONTAS EM ABERTO", 12, UI.MUTED))
	var open_bills := HomeSystem.unpaid()
	if open_bills.is_empty():
		list.add_child(UI.label("Nenhuma conta em aberto.", 13, UI.MUTED))
	for b in open_bills:
		var late := (TimeManager.total_minutes - int(b["venc"])) / 1440.0
		var when := ("ATRASADA há %d dia(s)" % int(ceil(late))) if late > 0.0 else "vence em %d dia(s)" % int(ceil(-late))
		var bc := _card(list, Color(UI.DANGER, 0.12) if late > 0.0 else Color(1, 1, 1, 0.05))
		bc.add_child(UI.label(HomeSystem.bill_label(b), 14))
		bc.add_child(UI.label("R$ %d  •  %s" % [int(b["valor"]), when], 13, UI.DANGER if late > 0.0 else UI.MUTED))
		var pay := UI.accent_button("Pagar R$ %d" % int(b["valor"]), _pay_bill.bind(int(b["id"])))
		pay.disabled = GameState.money() < int(b["valor"])
		bc.add_child(pay)


func _pay_bill(bill_id: int) -> void:
	HomeSystem.pay_bill(bill_id)
	_go("bills")


func _homes() -> void:
	title_label.text = "Imóveis"
	var list := UI.vbox(8)
	body.add_child(UI.scroll(list))
	for loc_id in HomeSystem.imoveis:
		var p: Dictionary = HomeSystem.imoveis[loc_id]
		var c := _card(list)
		c.add_child(UI.title(World.locations[loc_id]["nome"], 16))
		c.add_child(UI.label(str(p["resumo"]), 12, UI.MUTED))
		var price_parts: Array = []
		if p.has("aluguel"):
			price_parts.append("Aluguel R$ %d/mês" % int(p["aluguel"]))
		if p.has("deposito"):
			price_parts.append("caução R$ %d" % int(p["deposito"]))
		if p.has("compra"):
			price_parts.append("Compra R$ %d" % int(p["compra"]))
		c.add_child(UI.label("  •  ".join(price_parts), 13, UI.ACCENT))
		var st := HomeSystem.status_of(loc_id)
		if st != "":
			var tags := {"propria": "Seu imóvel", "alugada": "Alugado por você", "comercial": "Seu ponto comercial"}
			c.add_child(UI.chip(str(tags.get(st, st)), UI.TEAL, 12))
			if st != "comercial" and HomeSystem.home_id() != loc_id:
				c.add_child(UI.button("Mudar para cá", _home_act.bind("move", loc_id)))
			if st != "propria":
				c.add_child(UI.button("Encerrar contrato", _home_act.bind("cancel", loc_id)))
		else:
			if p.has("aluguel"):
				var rb := UI.accent_button("Alugar (R$ %d agora)" % HomeSystem.rent_cost(loc_id), _home_act.bind("rent", loc_id))
				rb.disabled = not HomeSystem.can_rent(loc_id)
				c.add_child(rb)
			if p.has("compra"):
				var bb := UI.button("Comprar (R$ %d)" % int(p["compra"]), _home_act.bind("buy", loc_id))
				bb.disabled = not HomeSystem.can_buy(loc_id)
				c.add_child(bb)


func _home_act(what: String, loc_id: String) -> void:
	match what:
		"rent": HomeSystem.rent(loc_id)
		"buy": HomeSystem.buy(loc_id)
		"cancel": HomeSystem.cancel(loc_id)
		"move": HomeSystem.move_in(loc_id)
	_go("homes")


func _shop() -> void:
	title_label.text = "Compras"
	var places := HomeSystem.residences()
	if places.is_empty():
		body.add_child(UI.label("Você precisa de uma casa para receber entregas. Veja o app Imóveis.", 14, UI.MUTED))
		return
	var dest := OptionButton.new()
	for loc_id in places:
		dest.add_item("Entregar em: " + World.locations[loc_id]["nome"])
		dest.set_item_metadata(dest.item_count - 1, loc_id)
	var cur := places.find(HomeSystem.home_id())
	dest.selected = maxi(cur, 0)
	body.add_child(dest)
	var list := UI.vbox(8)
	body.add_child(UI.scroll(list))
	for item_id in HomeSystem.moveis:
		var m: Dictionary = HomeSystem.moveis[item_id]
		var c := _card(list)
		c.add_child(UI.title(str(m["nome"]), 15))
		c.add_child(UI.label(str(m["desc"]), 12, UI.MUTED))
		var buy := UI.button("Comprar  R$ %d  (entrega em 1 dia)" % int(m["preco"]), _order.bind(item_id, dest))
		buy.disabled = GameState.money() < int(m["preco"])
		c.add_child(buy)
	var ic := _card(list)
	ic.add_child(UI.title("Internet", 15))
	ic.add_child(UI.label("Instalação R$ %d + R$ %d por mês. Necessária para trabalhar online." % [HomeSystem.INTERNET_SETUP, HomeSystem.INTERNET_MONTHLY], 12, UI.MUTED))
	var ib := UI.button("Contratar internet", _order_net.bind(dest))
	ib.disabled = GameState.money() < HomeSystem.INTERNET_SETUP
	ic.add_child(ib)


func _order(item_id: String, dest: OptionButton) -> void:
	HomeSystem.order(item_id, str(dest.get_item_metadata(dest.selected)))
	_go("shop")


func _order_net(dest: OptionButton) -> void:
	HomeSystem.order_internet(str(dest.get_item_metadata(dest.selected)))
	_go("shop")


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
