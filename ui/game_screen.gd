extends Control

signal navigate(screen: String, args: Dictionary)

const UI = preload("res://ui/ui_theme.gd")
const FaceRig = preload("res://ui/face/face_rig.gd")
const LookBuilder = preload("res://ui/face/look_builder.gd")
const PhonePanel = preload("res://ui/phone/phone_panel.gd")
const SceneView = preload("res://ui/game/scene_view.gd")
const IconButton = preload("res://ui/game/icon_button.gd")
const Icons = preload("res://ui/game/icons.gd")
const DialogueBox = preload("res://ui/game/dialogue_box.gd")
const Meter = preload("res://ui/game/meter.gd")
const BagPanel = preload("res://ui/game/bag_panel.gd")
const ShopPanel = preload("res://ui/game/shop_panel.gd")
const MapPanel = preload("res://ui/game/map_panel.gd")
const HistoryPanel = preload("res://ui/game/history_panel.gd")
const MoneyPanel = preload("res://ui/game/money_panel.gd")
const ChoicePanel = preload("res://ui/game/choice_panel.gd")
const BusinessPanel = preload("res://ui/game/business_panel.gd")
const WantedStars = preload("res://ui/game/wanted_stars.gd")
const PoliceLights = preload("res://ui/game/police_lights.gd")

const MENU_TALK := 0
const MENU_ACTIONS := {
	1: "Desculpa, qual é o seu nome?",
	2: "Me passa seu número de celular?",
	3: "*faz um elogio sincero*",
	4: "*flerta, com um meio sorriso*",
	5: "*provoca, em tom de deboche*",
	6: "*chega bem perto e ameaça em voz baixa*",
	7: "*empurra com força*",
}
const MENU_MONEY := 20
const MENU_ITEM := 21
const MENU_END := 22
const MENU_PUNCH := 30
const MENU_WEAPON := 31
const MENU_PICKPOCKET := 32

var args: Dictionary = {}

var scene_view: SceneView
var stage: Control
var actors: Dictionary = {}
var place_title: Label
var place_sub: Label
var money_chip: PanelContainer
var meters: Dictionary = {}
var player_portrait: FaceRig
var player_state: Label
var side_box: VBoxContainer
var dialogue: DialogueBox
var buttons: Dictionary = {}
var context_menu: PopupMenu
var context_target: String = ""

var phone: PhonePanel
var choice_panel: ChoicePanel
var business_panel: BusinessPanel
var job_chip: PanelContainer
var events_box: VBoxContainer
var stars_view: WantedStars
var bag: BagPanel
var shop: ShopPanel
var map_panel: MapPanel
var history: HistoryPanel
var money_panel: MoneyPanel

var toast_label: Label
var toast_panel: PanelContainer
var toast_tween: Tween
var refresh_queued := false
var narrating := false
var shown_scene := ""


func _ready() -> void:
	_build()
	GameState.log_added.connect(_on_log)
	GameState.player_changed.connect(_queue_refresh)
	GameState.game_over.connect(_on_game_over)
	NeedsSystem.needs_changed.connect(_queue_refresh)
	TimeManager.time_advanced.connect(_queue_refresh.unbind(2))
	World.location_changed.connect(_queue_refresh.unbind(1))
	World.narrator_busy.connect(_on_narrator_busy)
	NPCManager.conversation_changed.connect(_queue_refresh.unbind(1))
	NPCManager.npc_thinking.connect(_on_npc_thinking)
	NPCManager.npc_replied.connect(_on_npc_replied)
	PhoneSystem.changed.connect(_queue_refresh)
	PhoneSystem.notify.connect(_toast)
	CrimeSystem.choice.connect(choice_panel.show_choice)
	Economy.ui_request.connect(_on_ui_request)
	JobSystem.changed.connect(_queue_refresh)
	WorldEvents.changed.connect(_queue_refresh)
	HomeSystem.changed.connect(_queue_refresh)
	CrimeSystem.wanted_changed.connect(_queue_refresh.unbind(1))
	if not GameState.log_entries.is_empty():
		_on_log(GameState.log_entries[-1])
	_refresh()
	if args.has("new_origin"):
		World.start_story(args["new_origin"])


# ---------- montagem ----------

func _anchor(c: Control, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = l
	c.anchor_top = t
	c.anchor_right = r
	c.anchor_bottom = b


func _build() -> void:
	scene_view = SceneView.new()
	scene_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scene_view)
	stage = Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	stage.resized.connect(_layout_actors)
	var lights := PoliceLights.new()
	lights.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lights.hide()
	add_child(lights)

	# Topo esquerdo: local, hora, dinheiro
	var place := PanelContainer.new()
	place.add_theme_stylebox_override("panel", UI.glass(16, 14))
	_anchor(place, 0, 0, 0, 0)
	place.position = Vector2(18, 16)
	add_child(place)
	var pv := UI.vbox(4)
	place.add_child(pv)
	place_title = UI.title("", 26)
	pv.add_child(place_title)
	var sub_row := UI.hbox(8)
	pv.add_child(sub_row)
	var clock_icon := Control.new()
	clock_icon.custom_minimum_size = Vector2(18, 18)
	clock_icon.draw.connect(func(): Icons.draw(clock_icon, "clock", Rect2(0, 0, 18, 18), UI.MUTED, 1.6))
	sub_row.add_child(clock_icon)
	place_sub = UI.label("", 15, UI.MUTED)
	place_sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub_row.add_child(place_sub)
	money_chip = UI.chip("", UI.TEAL, 15)
	pv.add_child(money_chip)
	stars_view = WantedStars.new()
	stars_view.hide()
	pv.add_child(stars_view)
	job_chip = UI.chip("", UI.MUTED, 13)
	job_chip.hide()
	pv.add_child(job_chip)
	events_box = UI.vbox(4)
	pv.add_child(events_box)

	# Topo direito: botões
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	var bar_panel := PanelContainer.new()
	bar_panel.add_theme_stylebox_override("panel", UI.glass(16, 6))
	bar_panel.add_child(bar)
	_anchor(bar_panel, 1, 0, 1, 0)
	bar_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar_panel.offset_right = -18
	bar_panel.offset_top = 16
	add_child(bar_panel)
	for spec in [["map", "Mapa (M)", _open_map], ["bag", "Bolsa (B)", _open_bag], ["phone", "Celular (C)", _open_phone], ["book", "Histórico (H)", _open_history], ["save", "Salvar", _save], ["gear", "Configurações", _settings], ["close", "Sair para o menu", _to_menu]]:
		var b := IconButton.new(spec[0], spec[1], 50)
		b.pressed.connect(spec[2])
		bar.add_child(b)
		buttons[spec[0]] = b

	# Baixo esquerdo: cartão do jogador
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UI.glass(18, 12))
	_anchor(card, 0, 1, 0, 1)
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.offset_left = 18
	card.offset_bottom = -16
	card.custom_minimum_size = Vector2(256, 0)
	add_child(card)
	var cv := UI.vbox(8)
	card.add_child(cv)
	var ch := UI.hbox(10)
	cv.add_child(ch)
	player_portrait = FaceRig.new()
	player_portrait.custom_minimum_size = Vector2(84, 104)
	ch.add_child(player_portrait)
	var p := GameState.player
	player_portrait.set_look(LookBuilder.build(p.get("look", {}), int(p.get("age", 30)), str(p.get("gender", "homem"))))
	var nv := UI.vbox(2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(nv)
	var pname := UI.title(str(p.get("name", "")), 19)
	nv.add_child(pname)
	nv.add_child(UI.label("%d anos" % int(p.get("age", 0)), 13, UI.MUTED))
	player_state = UI.label("", 13, UI.ACCENT)
	nv.add_child(player_state)
	var icon_for := {"saude": "saude", "saciedade": "saciedade", "hidratacao": "hidratacao", "energia": "energia", "higiene": "higiene_need", "sanidade": "sanidade"}
	for k in NeedsSystem.KEYS:
		var m := Meter.new(icon_for[k], NeedsSystem.LABELS[k])
		cv.add_child(m)
		meters[k] = m

	# Direita: ações do local
	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", UI.glass(18, 14))
	_anchor(side, 1, 0, 1, 1)
	side.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	side.offset_right = -18
	side.offset_top = 96
	side.offset_bottom = -16
	side.custom_minimum_size = Vector2(250, 0)
	add_child(side)
	side_box = UI.vbox(8)
	side.add_child(UI.scroll(side_box))

	# Caixa de diálogo
	dialogue = DialogueBox.new()
	_anchor(dialogue, 0.5, 1, 0.5, 1)
	dialogue.offset_left = -390
	dialogue.offset_right = 390
	dialogue.offset_top = -250
	dialogue.offset_bottom = -16
	add_child(dialogue)
	dialogue.submitted.connect(_on_submit)
	dialogue.end_pressed.connect(NPCManager.end_conversation)

	context_menu = PopupMenu.new()
	context_menu.id_pressed.connect(_on_context)
	add_child(context_menu)

	toast_panel = PanelContainer.new()
	toast_panel.add_theme_stylebox_override("panel", UI.glass(12, 12, Color(0.06, 0.25, 0.2, 0.95)))
	toast_label = UI.label("", 16, Color.WHITE)
	toast_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	toast_panel.add_child(toast_label)
	_anchor(toast_panel, 0.5, 0, 0.5, 0)
	toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_panel.offset_top = 22
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.hide()
	add_child(toast_panel)

	bag = BagPanel.new()
	add_child(bag)
	shop = ShopPanel.new()
	add_child(shop)
	map_panel = MapPanel.new()
	add_child(map_panel)
	history = HistoryPanel.new()
	add_child(history)
	money_panel = MoneyPanel.new()
	add_child(money_panel)
	phone = PhonePanel.new()
	add_child(phone)
	business_panel = BusinessPanel.new()
	add_child(business_panel)
	choice_panel = ChoicePanel.new()
	add_child(choice_panel)


# ---------- atores (pessoas no cenário) ----------

func _actor_ids() -> Array:
	var ids: Array = NPCManager.npcs_here() if GameState.active else []
	var t := NPCManager.talking_to
	if t != "" and not t in ids:
		ids.append(t)
	return ids


func _sync_actors() -> void:
	var ids := _actor_ids()
	for id in actors.keys():
		if not id in ids:
			actors[id].queue_free()
			actors.erase(id)
	for id in ids:
		if actors.has(id):
			continue
		var n: Dictionary = NPCManager.npcs[id]
		var a := FaceRig.new()
		a.actor_mode = true
		a.show_emote = true
		a.mouse_filter = Control.MOUSE_FILTER_STOP
		a.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		a.set_look(LookBuilder.build(World.npc_looks.get(id, {}), int(n["idade"]), n["genero"]))
		a.set_emotion(str(NPCManager.state[id]["emocao"]), true)
		a.gui_input.connect(_on_actor_input.bind(id))
		a.mouse_entered.connect(func(): a.highlight = 1.0)
		a.mouse_exited.connect(func(): a.highlight = 0.0)
		var tag := UI.chip("", UI.TEXT, 14)
		tag.name = "Tag"
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		a.add_child(tag)
		stage.add_child(a)
		actors[id] = a
		a.modulate.a = 0.0
		create_tween().tween_property(a, "modulate:a", 1.0, 0.35)
	_layout_actors()


func _layout_actors() -> void:
	var ids: Array = actors.keys()
	if ids.is_empty():
		return
	var focus := NPCManager.talking_to
	var h := size.y * 0.8
	var w := h * 0.75
	var s := h / 400.0
	var top := (size.y - 262.0) - 252.0 * s
	var x0 := 290.0 + w * 0.35
	var x1 := size.x - 290.0 - w * 0.35
	var n := ids.size()
	var ordered: Array = ids.filter(func(i): return i != focus)
	if focus in ids:
		ordered.insert(int(ordered.size() / 2.0), focus)
	for i in n:
		var id: String = ordered[i]
		var a: FaceRig = actors[id]
		var cx := (x0 + x1) / 2.0 if n == 1 else lerpf(x0, x1, float(i) / (n - 1))
		var is_focus := id == focus or focus == ""
		var sc := 1.0 if id == focus else (0.9 if focus != "" else 0.94)
		a.size = Vector2(w, h)
		a.pivot_offset = Vector2(w / 2.0, h)
		a.position = Vector2(cx - w / 2.0, top)
		a.scale = Vector2(sc, sc)
		var on_call := id == focus and NPCManager.channel == NPCManager.LIGACAO
		a.modulate = Color(0.75, 0.88, 1.0) if on_call else (Color.WHITE if is_focus else Color(0.58, 0.58, 0.64))
		var tag: PanelContainer = a.get_node("Tag")
		var label: Label = tag.get_child(0)
		label.text = NPCManager.display_name(id) + ("  •  em ligação" if on_call else "")
		tag.position = Vector2(w / 2.0 - tag.get_combined_minimum_size().x / 2.0 - 30.0 * s, 50.0 * s)
		var st: Dictionary = NPCManager.state[id]
		if str(st["emocao"]) != a.emotion:
			a.set_emotion(str(st["emocao"]))
	if focus != "" and actors.has(focus):
		stage.move_child(actors[focus], -1)


func _on_actor_input(e: InputEvent, id: String) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	if e.button_index == MOUSE_BUTTON_LEFT:
		if NPCManager.talking_to != id and not NPCManager.busy:
			NPCManager.start_conversation(id)
			dialogue.input.grab_focus.call_deferred()
	elif e.button_index == MOUSE_BUTTON_RIGHT:
		_open_context(id)


func _open_context(id: String) -> void:
	context_target = id
	context_menu.clear()
	context_menu.add_separator(NPCManager.display_name(id))
	context_menu.add_item("Conversar", MENU_TALK)
	context_menu.add_item("Perguntar o nome", 1)
	context_menu.add_item("Pedir o número", 2)
	context_menu.add_item("Elogiar", 3)
	context_menu.add_item("Flertar", 4)
	context_menu.add_item("Provocar", 5)
	context_menu.add_item("Ameaçar", 6)
	context_menu.add_item("Empurrar", 7)
	context_menu.add_separator("Violência e crime")
	context_menu.add_item("Dar um soco", MENU_PUNCH)
	var weapon := CrimeSystem.best_weapon()
	if weapon != "":
		context_menu.add_item("Atacar com %s" % World.item_name(weapon).to_lower(), MENU_WEAPON)
	context_menu.add_item("Roubar a carteira", MENU_PICKPOCKET)
	context_menu.add_separator()
	context_menu.add_item("Dar dinheiro...", MENU_MONEY)
	context_menu.add_item("Dar um item...", MENU_ITEM)
	if NPCManager.talking_to == id:
		context_menu.add_item("Encerrar conversa", MENU_END)
	var busy := NPCManager.busy or narrating or not GameState.active
	for i in context_menu.item_count:
		if busy and not context_menu.is_item_separator(i):
			context_menu.set_item_disabled(i, true)
	context_menu.position = Vector2i(get_global_mouse_position())
	context_menu.reset_size()
	context_menu.popup()


func _ensure_talking(id: String) -> bool:
	if NPCManager.talking_to != id:
		NPCManager.start_conversation(id)
	return NPCManager.talking_to == id


func _on_context(menu_id: int) -> void:
	var id := context_target
	if menu_id == MENU_END:
		NPCManager.end_conversation()
		return
	if menu_id == MENU_PUNCH:
		CrimeSystem.player_attack(id)
		return
	if menu_id == MENU_WEAPON:
		CrimeSystem.player_attack(id, CrimeSystem.best_weapon())
		return
	if menu_id == MENU_PICKPOCKET:
		CrimeSystem.pickpocket(id)
		return
	if not _ensure_talking(id):
		return
	if MENU_ACTIONS.has(menu_id):
		NPCManager.talk(MENU_ACTIONS[menu_id])
	elif menu_id == MENU_MONEY:
		money_panel.open()
	elif menu_id == MENU_ITEM:
		bag.open()
	else:
		dialogue.input.grab_focus.call_deferred()


# ---------- atualização ----------

func _queue_refresh() -> void:
	if refresh_queued:
		return
	refresh_queued = true
	_refresh.call_deferred()


func _refresh() -> void:
	refresh_queued = false
	if not is_inside_tree():
		return
	var loc := World.current()
	var scene_kind := FaceRig.scene_for_location(World.current_id(), str(loc.get("tipo", "")))
	if World.current_id() != shown_scene:
		shown_scene = World.current_id()
		scene_view.set_place(World.current_id(), scene_kind)
	player_portrait.scene = scene_kind
	place_title.text = loc.get("nome", "")
	place_sub.text = "Dia %d • %s • %02d:%02d • %s" % [TimeManager.day(), TimeManager.weekday(), TimeManager.hour(), TimeManager.minute(), TimeManager.period()]
	(money_chip.get_child(0) as Label).text = "R$ %d" % GameState.money()
	stars_view.set_stars(CrimeSystem.wanted())
	for c in events_box.get_children():
		c.queue_free()
	for label_text in WorldEvents.labels():
		events_box.add_child(UI.chip(str(label_text), Color("#ff9f43"), 13))
	var job := JobSystem.job()
	job_chip.visible = not job.is_empty()
	if not job.is_empty():
		(job_chip.get_child(0) as Label).text = "%s • %02dh-%02dh" % [str(job["cargo"]), int(job["turno"][0]), int(job["turno"][1])]
	for k in meters:
		meters[k].value = NeedsSystem.get_value(k)
	var pemo := player_emotion()
	if pemo != player_portrait.emotion:
		player_portrait.set_emotion(pemo)
	player_state.text = "" if pemo == "neutro" else World.emotions[pemo]["pt"].capitalize()
	if GameState.active:
		buttons["phone"].set_badge(PhoneSystem.unread())
		var inv: Dictionary = GameState.player.get("inventory", {})
		buttons["bag"].set_badge(inv.size())
	_sync_actors()
	_refresh_dialogue_state()
	_refresh_side()


func _on_ui_request(panel: String) -> void:
	if panel == "negocio":
		business_panel.open()


static func player_emotion() -> String:
	if NeedsSystem.get_value("saude") < 40.0:
		return "machucado"
	if AddictionSystem.worst() >= 0.6:
		return "nervoso"
	if NeedsSystem.get_value("energia") < 20.0:
		return "exausto"
	if NeedsSystem.get_value("sanidade") < 25.0:
		return "nervoso"
	if NeedsSystem.get_value("sanidade") < 45.0 or NeedsSystem.get_value("saciedade") < 15.0:
		return "triste"
	return "neutro"


func _refresh_dialogue_state() -> void:
	var id := NPCManager.talking_to
	var can_act := GameState.active and not NPCManager.busy and not narrating
	if id == "":
		dialogue.set_input(false, "Clique em alguém para conversar  •  botão direito para mais opções", false)
		return
	var on_call := NPCManager.channel == NPCManager.LIGACAO
	dialogue.set_speaker(NPCManager.display_name(id), NPCManager.relation_label(id))
	dialogue.set_input(can_act, "Fale ao telefone..." if on_call else "Diga algo...  (use *asteriscos* para ações, ex: *ofereço um cigarro*)", true, "Desligar" if on_call else "Encerrar")


func _section(text: String) -> void:
	var l := UI.label(text.to_upper(), 12, UI.MUTED)
	l.add_theme_font_override("font", UI.font(true))
	side_box.add_child(l)


func _refresh_side() -> void:
	for c in side_box.get_children():
		c.queue_free()
	if not GameState.active:
		return
	var can_act := not NPCManager.busy and not narrating
	var loc := World.current()
	_section("Neste lugar")
	if World.shop_open():
		var buy := UI.accent_button("Comprar  •  " + str(loc.get("vendedor", "")), _open_shop)
		buy.disabled = not can_act
		buy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		side_box.add_child(buy)
	for a in Economy.available_actions():
		var b := UI.button(a["label"], Economy.do_action.bind(a["id"]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = not can_act
		side_box.add_child(b)
	side_box.add_child(HSeparator.new())
	_section("Pessoas aqui")
	var here := NPCManager.npcs_here()
	if here.is_empty():
		side_box.add_child(UI.label("Ninguém por perto.", 14, UI.MUTED))
	for id in here:
		var b := UI.button(NPCManager.display_name(id), NPCManager.start_conversation.bind(id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = not can_act or id == NPCManager.talking_to
		b.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
				_open_context(id))
		side_box.add_child(b)
	side_box.add_child(HSeparator.new())
	side_box.add_child(UI.button("Abrir o mapa para ir a outro lugar", _open_map))


# ---------- eventos ----------

func _on_log(e: Dictionary) -> void:
	var kind := str(e.get("kind", ""))
	if kind == "system":
		_toast(str(e.get("text", "")))
		return
	match kind:
		"npc":
			var id := NPCManager.talking_to
			dialogue.set_speaker(str(e.get("speaker", "")), NPCManager.relation_label(id) if id != "" else "")
		"player":
			dialogue.set_speaker("Você")
		"narration":
			dialogue.set_speaker("Narrador")
		_:
			dialogue.set_speaker("")
	dialogue.show_entry(e)


func _on_submit(text: String) -> void:
	NPCManager.talk(text)


func _on_npc_thinking(npc_id: String, thinking: bool) -> void:
	dialogue.set_thinking(("%s está pensando" % NPCManager.display_name(npc_id)) if thinking else "")
	_queue_refresh()
	if not thinking:
		dialogue.input.grab_focus.call_deferred()


func _on_npc_replied(npc_id: String, data: Dictionary) -> void:
	if actors.has(npc_id) and npc_id == NPCManager.talking_to:
		actors[npc_id].talk(clampf(str(data.get("fala", "")).length() * 0.06, 0.6, 6.0))
	_queue_refresh()


func _on_narrator_busy(busy: bool) -> void:
	narrating = busy
	dialogue.set_thinking("O narrador está escrevendo" if busy else "")
	_queue_refresh()


func _toast(text: String) -> void:
	toast_label.text = text
	toast_panel.show()
	toast_panel.modulate.a = 1.0
	if toast_tween:
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(3.0)
	toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.6)
	toast_tween.tween_callback(toast_panel.hide)


func _unhandled_key_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if phone.visible or bag.visible or map_panel.visible or shop.visible or history.visible or money_panel.visible:
		return
	match e.keycode:
		KEY_M: _open_map()
		KEY_B: _open_bag()
		KEY_C: _open_phone()
		KEY_H: _open_history()


func _open_map() -> void:
	if GameState.active and not NPCManager.busy and not narrating:
		map_panel.open()


func _open_bag() -> void:
	bag.open()


func _open_phone() -> void:
	if GameState.active:
		phone.open("home")


func _open_history() -> void:
	history.open()


func _open_shop() -> void:
	shop.open()


func _save() -> void:
	SaveManager.save_game()


func _settings() -> void:
	navigate.emit("settings", {"back": "game"})


func _on_game_over(reason: String) -> void:
	SaveManager.delete_save()
	_queue_refresh()
	var overlay := ColorRect.new()
	overlay.color = Color(0.05, 0, 0, 0.0)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	create_tween().tween_property(overlay, "color:a", 0.88, 1.2)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := UI.vbox(16)
	center.add_child(box)
	var t := UI.title("VOCÊ MORREU", 64)
	t.add_theme_color_override("font_color", UI.DANGER)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var msg := UI.label("%s\nCausa: %s\nSobreviveu até %s em Porto Cinza." % [GameState.player["name"], reason, TimeManager.clock_str()], 19)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(msg)
	box.add_child(UI.accent_button("Voltar ao menu", func(): navigate.emit("menu", {})))


func _to_menu() -> void:
	SaveManager.save_game()
	navigate.emit("menu", {})
