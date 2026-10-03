extends Control

signal navigate(screen: String, args: Dictionary)

const UI = preload("res://ui/ui_theme.gd")

var args: Dictionary = {}

var clock_label: Label
var money_label: Label
var place_label: Label
var bars: Dictionary = {}
var inventory_box: VBoxContainer
var log_view: RichTextLabel
var thinking_label: Label
var input: LineEdit
var send_btn: Button
var money_spin: SpinBox
var give_btn: Button
var portrait: ColorRect
var portrait_initials: Label
var npc_name_label: Label
var npc_info_label: Label
var end_btn: Button
var side_box: VBoxContainer
var star_re := RegEx.new()
var refresh_queued := false
var narrating := false


func _ready() -> void:
	star_re.compile("\\*([^*]+)\\*")
	_build()
	for e in GameState.log_entries:
		_append_entry(e)

	GameState.log_added.connect(_append_entry)
	GameState.player_changed.connect(_queue_refresh)
	GameState.game_over.connect(_on_game_over)
	NeedsSystem.needs_changed.connect(_queue_refresh)
	TimeManager.time_advanced.connect(_queue_refresh.unbind(2))
	World.location_changed.connect(_queue_refresh.unbind(1))
	World.narrator_busy.connect(_on_narrator_busy)
	NPCManager.conversation_changed.connect(_queue_refresh.unbind(1))
	NPCManager.npc_replied.connect(_queue_refresh.unbind(2))
	NPCManager.npc_thinking.connect(_on_npc_thinking)
	_refresh()

	if args.has("new_origin"):
		World.start_story(args["new_origin"])


func _build() -> void:
	var root := UI.vbox(10)
	var outer := UI.margin(root, 12)
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(outer)

	var top := UI.hbox(24)
	root.add_child(UI.panel(top))
	clock_label = UI.title("", 18)
	top.add_child(clock_label)
	money_label = UI.label("")
	money_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(money_label)
	place_label = UI.label("")
	place_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(place_label)
	top.add_child(UI.button("Salvar", SaveManager.save_game))
	top.add_child(UI.button("Configurações", func(): navigate.emit("settings", {"back": "game"})))
	top.add_child(UI.button("Menu", _to_menu))

	var cols := UI.hbox(10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# Coluna esquerda: status e inventário
	var left := UI.vbox(6)
	var left_panel := UI.panel(left)
	left_panel.custom_minimum_size = Vector2(250, 0)
	cols.add_child(left_panel)
	left.add_child(UI.title("Estado", 18))
	for k in NeedsSystem.KEYS:
		left.add_child(UI.label(NeedsSystem.LABELS[k], 13, UI.MUTED))
		var bar := ProgressBar.new()
		bar.max_value = 100
		bar.custom_minimum_size = Vector2(0, 16)
		bar.show_percentage = false
		left.add_child(bar)
		bars[k] = bar
	left.add_child(HSeparator.new())
	left.add_child(UI.title("Inventário", 18))
	inventory_box = UI.vbox(4)
	left.add_child(UI.scroll(inventory_box))

	# Centro: conversa e narrativa
	var center := UI.vbox(8)
	var center_panel := UI.panel(center)
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(center_panel)

	var header := UI.hbox(12)
	center.add_child(header)
	portrait = ColorRect.new()
	portrait.custom_minimum_size = Vector2(64, 64)
	header.add_child(portrait)
	portrait_initials = UI.title("", 26)
	portrait_initials.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_initials.add_theme_color_override("font_color", Color.WHITE)
	portrait.add_child(portrait_initials)
	var hv := UI.vbox(2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(hv)
	npc_name_label = UI.title("", 20)
	hv.add_child(npc_name_label)
	npc_info_label = UI.label("", 13, UI.MUTED)
	hv.add_child(npc_info_label)
	end_btn = UI.button("Encerrar conversa", NPCManager.end_conversation)
	header.add_child(end_btn)

	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.selection_enabled = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.add_theme_font_size_override("normal_font_size", 17)
	log_view.add_theme_font_size_override("italics_font_size", 17)
	log_view.add_theme_font_size_override("bold_font_size", 17)
	center.add_child(log_view)

	thinking_label = UI.label("", 14, UI.ACCENT)
	center.add_child(thinking_label)

	var input_row := UI.hbox(6)
	center.add_child(input_row)
	input = LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text_submitted.connect(func(_t): _send())
	input_row.add_child(input)
	send_btn = UI.button("Falar", _send)
	input_row.add_child(send_btn)
	money_spin = SpinBox.new()
	money_spin.min_value = 1
	money_spin.max_value = 100000
	money_spin.value = 10
	money_spin.prefix = "R$"
	input_row.add_child(money_spin)
	give_btn = UI.button("Dar dinheiro", func(): NPCManager.give_money(int(money_spin.value)))
	input_row.add_child(give_btn)

	# Coluna direita: local, pessoas, ações, lojas, viagem
	side_box = UI.vbox(6)
	var right_panel := UI.panel(UI.scroll(side_box))
	right_panel.custom_minimum_size = Vector2(320, 0)
	cols.add_child(right_panel)


func _queue_refresh() -> void:
	if refresh_queued:
		return
	refresh_queued = true
	_refresh.call_deferred()


func _refresh() -> void:
	refresh_queued = false
	if not is_inside_tree():
		return
	var p := GameState.player
	clock_label.text = TimeManager.clock_str() + " • " + TimeManager.period()
	money_label.text = "R$ %d" % GameState.money()
	place_label.text = "Local: " + World.current().get("nome", "")
	for k in bars:
		bars[k].value = NeedsSystem.get_value(k)
		var c := UI.ACCENT
		if NeedsSystem.get_value(k) < 25:
			c = UI.DANGER
		bars[k].add_theme_stylebox_override("fill", UI._box(c, 3, 0))

	for c in inventory_box.get_children():
		c.queue_free()
	var inv: Dictionary = p.get("inventory", {})
	if inv.is_empty():
		inventory_box.add_child(UI.label("(vazio)", 14, UI.MUTED))
	for id in inv:
		var row := UI.hbox(4)
		var l := UI.label("%s x%d" % [World.item_name(id), int(inv[id])], 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UI.button("Usar", Economy.use_item.bind(id)))
		inventory_box.add_child(row)

	_refresh_conversation()
	_refresh_side()


func _refresh_conversation() -> void:
	var id := NPCManager.talking_to
	var can_act := GameState.active and not NPCManager.busy and not narrating
	if id == "":
		portrait.color = UI.PANEL_LIGHT
		portrait_initials.text = "?"
		npc_name_label.text = "Ninguém"
		npc_info_label.text = "Escolha alguém na lista \"Pessoas aqui\" para conversar."
		input.placeholder_text = "Escolha alguém para conversar..."
		input.editable = false
		send_btn.disabled = true
		give_btn.disabled = true
		end_btn.visible = false
		return
	var n: Dictionary = NPCManager.npcs[id]
	var st: Dictionary = NPCManager.state[id]
	var shown := NPCManager.display_name(id)
	portrait.color = Color(n["cor"])
	portrait_initials.text = shown.substr(0, 1).to_upper()
	npc_name_label.text = shown
	npc_info_label.text = "Humor: %s  •  Confiança %d  •  Afeto %d  •  Medo %d  •  Suspeita %d" % [
		st["emocao"], int(st["confianca"]), int(st["afeto"]), int(st["medo"]), int(st["suspeita"])]
	input.placeholder_text = "Fale algo... use *asteriscos* para ações (ex: *entrego um cigarro*)"
	input.editable = can_act
	send_btn.disabled = not can_act
	give_btn.disabled = not can_act
	end_btn.visible = true


func _refresh_side() -> void:
	for c in side_box.get_children():
		c.queue_free()
	if not GameState.active:
		return
	var can_act := not NPCManager.busy and not narrating
	var loc := World.current()
	side_box.add_child(UI.title(loc.get("nome", ""), 18))

	side_box.add_child(UI.label("Pessoas aqui", 15, UI.ACCENT))
	var here := NPCManager.npcs_here()
	if here.is_empty():
		side_box.add_child(UI.label("Não há ninguém por perto.", 14, UI.MUTED))
	for id in here:
		var b := UI.button(NPCManager.display_name(id), NPCManager.start_conversation.bind(id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not can_act or id == NPCManager.talking_to
		side_box.add_child(b)

	side_box.add_child(HSeparator.new())
	side_box.add_child(UI.label("Ações", 15, UI.ACCENT))
	for a in Economy.available_actions():
		var b := UI.button(a["label"], Economy.do_action.bind(a["id"]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not can_act
		side_box.add_child(b)

	var shop: Array = loc.get("loja", [])
	if not shop.is_empty():
		side_box.add_child(HSeparator.new())
		side_box.add_child(UI.label("Comprar", 15, UI.ACCENT))
		for item_id in shop:
			var it: Dictionary = World.items[item_id]
			var b := UI.button("%s — R$ %d" % [it["nome"], int(it["preco"])], Economy.buy.bind(item_id))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.disabled = not can_act or GameState.money() < int(it["preco"])
			side_box.add_child(b)

	side_box.add_child(HSeparator.new())
	side_box.add_child(UI.label("Ir para", 15, UI.ACCENT))
	for loc_id in World.visible_locations():
		if loc_id == World.current_id():
			continue
		var other: Dictionary = World.locations[loc_id]
		var mins := World.travel_minutes(World.current_id(), loc_id)
		var closed := "" if World.is_open(loc_id) else " (fechado agora)"
		var b := UI.button("%s — %d min%s" % [other["nome"], mins, closed], World.move_player_to.bind(loc_id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not can_act
		side_box.add_child(b)


func _send() -> void:
	var text := input.text.strip_edges()
	if text == "":
		return
	input.text = ""
	NPCManager.talk(text)


func _on_npc_thinking(npc_id: String, thinking: bool) -> void:
	thinking_label.text = ("%s está pensando..." % NPCManager.display_name(npc_id)) if thinking else ""
	_queue_refresh()
	if not thinking:
		input.grab_focus.call_deferred()


func _on_narrator_busy(busy: bool) -> void:
	narrating = busy
	thinking_label.text = "O narrador está escrevendo..." if busy else ""
	_queue_refresh()


func _append_entry(e: Dictionary) -> void:
	var kind := str(e.get("kind", "info"))
	var color: String = UI.KIND_COLORS.get(kind, "#cccccc")
	var text := star_re.sub(UI.escape_bbcode(str(e.get("text", ""))), "[i][color=#9a968c]$1[/color][/i]", true)
	var line := ""
	match kind:
		"player":
			line = "[color=%s][b]Você:[/b] %s[/color]" % [color, text]
		"npc":
			line = "[color=%s][b]%s:[/b][/color] %s" % [UI.ACCENT.to_html(false), UI.escape_bbcode(str(e.get("speaker", ""))), text]
		"narration":
			line = "[i][color=%s]%s[/color][/i]" % [color, text]
		"death":
			line = "[b][color=%s]%s[/color][/b]" % [color, text]
		_:
			line = "[color=%s]%s[/color]" % [color, text]
	log_view.append_text(line + "\n\n")


func _on_game_over(reason: String) -> void:
	SaveManager.delete_save()
	_queue_refresh()
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.8)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := UI.vbox(14)
	center.add_child(box)
	var t := UI.title("VOCÊ MORREU", 48)
	t.add_theme_color_override("font_color", UI.DANGER)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var msg := UI.label("%s\nCausa: %s\nSobreviveu até %s em Porto Cinza." % [GameState.player["name"], reason, TimeManager.clock_str()], 18)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(msg)
	box.add_child(UI.button("Voltar ao menu", func(): navigate.emit("menu", {})))


func _to_menu() -> void:
	SaveManager.save_game()
	navigate.emit("menu", {})
