extends Control

signal navigate(screen: String, args: Dictionary)

const UI = preload("res://ui/ui_theme.gd")
const FaceRig = preload("res://ui/face/face_portrait.gd")  # retrato da própria pessoa 3D
const LookBuilder = preload("res://ui/face/look_builder.gd")
const PhonePanel = preload("res://ui/phone/phone_panel.gd")
const SceneView = preload("res://ui/game/scene_view.gd")
const WorldView = preload("res://world3d/world_view.gd")
const FilmFx = preload("res://ui/menu/film_fx.gd")
const ArtStyle = preload("res://world3d/art_style.gd")
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
	8: "Feliz aniversário! Parabéns!",
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
var world_view: WorldView
var dim: ColorRect
var grade: FilmFx
var help_panel: PanelContainer
var _side_sig: String = ""
var speech_emotion: Dictionary = {}
var _ev_sig: String = ""
var actors: Dictionary = {}
var place_title: Label
var place_sub: Label
var money_chip: PanelContainer
var meters: Dictionary = {}
var player_portrait: FaceRig
var player_state: Label
var player_age_label: Label
var side_box: VBoxContainer
var dialogue: DialogueBox
var buttons: Dictionary = {}
var context_menu: PopupMenu
var object_menu: PopupMenu
var object_target: Dictionary = {}
var object_options: Array = []
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
# menu de pausa (Esc)
var pause_layer: Control
var settings_overlay: Control
var pause_box: PanelContainer
var pause_sub: Label
var pause_status: Label
var pause_confirm: VBoxContainer
var pause_confirm_text: Label
var pause_buttons: VBoxContainer
var pause_confirm_yes: Button
var pause_confirm_no: Button
var _pause_tween: Tween
var _confirm_action: Callable
var _realtime_before_pause := true
var _realtime_before_settings := true
var refresh_queued := false
var narrating := false
var shown_scene := ""


func _ready() -> void:
	_build()
	GameState.log_added.connect(_on_log)
	GameState.player_changed.connect(_queue_refresh)
	AgingSystem.birthday.connect(_on_birthday)
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
	Houses.changed.connect(_queue_refresh)
	HomeSystem.changed.connect(_queue_refresh)
	CrimeSystem.wanted_changed.connect(_queue_refresh.unbind(1))
	if not GameState.log_entries.is_empty():
		_on_log(GameState.log_entries[-1])
	_refresh()
	get_tree().create_timer(1.2).timeout.connect(func() -> void: _toast("WASD anda • %s alterna câmera • E interage em terceira pessoa • F1 ajuda" % OS.get_keycode_string(Settings.camera_key)))
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
	scene_view.hide()
	world_view = WorldView.new()
	world_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world_view.npc_chosen.connect(_on_walk_npc)
	world_view.npc_menu.connect(_open_context)
	world_view.object_chosen.connect(_open_object)
	world_view.toast.connect(_toast)
	world_view.world_ready.connect(_queue_refresh)
	world_view.pause_check = func() -> bool:
		for panel in [phone, bag, map_panel, shop, history, money_panel, choice_panel, business_panel, pause_layer, context_menu, object_menu, help_panel, settings_overlay]:
			if is_instance_valid(panel) and panel.visible:
				return true
		return false
	add_child(world_view)
	grade = FilmFx.new()
	grade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(grade)
	grade.setup_game(ArtStyle.p()["grade"])
	dim = ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.04, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.hide()
	add_child(dim)
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
	for spec in [["map", "Mapa (M)", _open_map], ["bag", "Bolsa (B)", _open_bag], ["phone", "Celular (C)", _open_phone], ["book", "Histórico (H)", _open_history], ["save", "Salvar", _save], ["gear", "Configurações", _settings], ["close", "Menu do jogo (Esc)", open_pause]]:
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
	player_age_label = UI.label("%d anos" % int(p.get("age", 0)), 13, UI.MUTED)
	nv.add_child(player_age_label)
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

	# Caixa de conversa: escondida até haver interação (ver dialogue_box.gd)
	dialogue = DialogueBox.new()
	_anchor(dialogue, 0.5, 1, 0.5, 1)
	dialogue.offset_left = -400
	dialogue.offset_right = 400
	dialogue.offset_bottom = -16
	dialogue.offset_top = -260
	add_child(dialogue)
	dialogue.submitted.connect(_on_submit)
	dialogue.end_pressed.connect(NPCManager.end_conversation)
	dialogue.expression.connect(_on_speech_expression)
	dialogue.speaking_pulse.connect(_on_speaking_pulse)
	dialogue.speech_finished.connect(_on_speech_finished)
	dialogue.action_chosen.connect(func(mid: int) -> void:
		context_target = NPCManager.talking_to
		_on_context(mid))
	dialogue.more_pressed.connect(func() -> void:
		if NPCManager.talking_to != "":
			_open_context(NPCManager.talking_to))
	resized.connect(_layout_dialogue)

	context_menu = PopupMenu.new()
	context_menu.id_pressed.connect(_on_context)
	add_child(context_menu)
	object_menu = PopupMenu.new()
	object_menu.id_pressed.connect(_on_object)
	add_child(object_menu)

	toast_panel = PanelContainer.new()
	var tsb := UI.glass(12, 12)
	tsb.border_color = Color(UI.ACCENT, 0.7)
	toast_panel.add_theme_stylebox_override("panel", tsb)
	toast_label = UI.label("", 16, UI.TEXT)
	toast_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	toast_panel.add_child(toast_label)
	_anchor(toast_panel, 0.5, 0, 0.5, 0)
	toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_panel.offset_top = 22
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.hide()
	add_child(toast_panel)

	bag = BagPanel.new()
	bag.use_hook = _use_item_animated
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
	_build_pause()


# A caixa de conversa fica entre o cartão do jogador (esquerda) e o painel do lugar (direita).
func _layout_dialogue() -> void:
	var free_w := size.x - 292.0 - 286.0
	var half := clampf(free_w / 2.0, 300.0, 500.0)
	var cx := (292.0 + size.x - 286.0) / 2.0 - size.x / 2.0
	dialogue.offset_left = cx - half
	dialogue.offset_right = cx + half


# ---------- atores (pessoas no cenário) ----------

func _actor_ids() -> Array:
	var t := NPCManager.talking_to
	return [t] if t != "" and GameState.active else []


# Quem fala aparece como retrato dentro da caixa de conversa (como em Stardew Valley),
# não mais como um rosto gigante sobre a cidade escurecida.
func _sync_actors() -> void:
	var ids := _actor_ids()
	for id in actors.keys():
		if not id in ids:
			actors[id].queue_free()
			actors.erase(id)
	if ids.is_empty():
		dialogue.end_conversation()
		return
	for id in ids:
		if actors.has(id):
			continue
		var n: Dictionary = NPCManager.npcs[id]
		var a := FaceRig.new()
		a.show_emote = true
		a.scene = FaceRig.scene_for_location(World.current_id(), str(World.current().get("tipo", "")))
		a.mouse_filter = Control.MOUSE_FILTER_STOP
		a.tooltip_text = "Botão direito: mais ações"
		a.set_look(LookBuilder.build(LookBuilder.individual_spec(World.npc_looks.get(id, {}), id), int(n["idade"]), n["genero"]))
		a.set_emotion(str(NPCManager.state[id]["emocao"]), true)
		a.gui_input.connect(_on_actor_input.bind(id))
		actors[id] = a
		dialogue.begin_conversation(_speaker_name(id), NPCManager.relation_label(id), a)
	_layout_actors()


func _speaker_name(id: String) -> String:
	return NPCManager.display_name(id) + ("  •  ligação" if NPCManager.channel == NPCManager.LIGACAO else "")


func _layout_actors() -> void:
	var focus := NPCManager.talking_to
	if focus == "" or not actors.has(focus):
		return
	var a: FaceRig = actors[focus]
	a.modulate = Color(0.78, 0.9, 1.0) if NPCManager.channel == NPCManager.LIGACAO else Color.WHITE
	var st: Dictionary = NPCManager.state[focus]
	var want_emo: String = str(speech_emotion.get(focus, st["emocao"]))
	if want_emo != a.emotion:
		a.set_emotion(want_emo)


func _update_mode() -> void:
	# a cidade continua visível durante a conversa; nada de escurecer a tela inteira
	stage.visible = false
	dim.visible = false


func _on_walk_npc(id: String) -> void:
	if NPCManager.talking_to != id and not NPCManager.busy:
		NPCManager.start_conversation(id)
		dialogue.input.grab_focus.call_deferred()


# A expressão acompanha o que está sendo dito, frase por frase.
func _on_speech_expression(e: String) -> void:
	var id := NPCManager.talking_to
	if id == "" or not actors.has(id):
		return
	speech_emotion[id] = e
	(actors[id] as FaceRig).set_emotion(e)


func _on_speaking_pulse() -> void:
	var id := NPCManager.talking_to
	if id != "" and actors.has(id):
		(actors[id] as FaceRig).talk(0.16)


func _on_speech_finished() -> void:
	var id := NPCManager.talking_to
	speech_emotion.erase(id)
	if id != "" and actors.has(id) and NPCManager.state.has(id):
		(actors[id] as FaceRig).set_emotion(str(NPCManager.state[id]["emocao"]))


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
	if SocialSystem.is_birthday(id):
		context_menu.add_item("Dar parabéns (é aniversário!)", 8)
	context_menu.add_item("Perguntar o nome", 1)
	context_menu.add_item("Pedir o número", 2)
	context_menu.add_item("Elogiar", 3)
	context_menu.add_item("Cumprimentar com a mão", 9)
	# com criança ou adolescente: nada de flerte, ameaça, empurrão nem violência
	var target_minor := int(NPCManager.npcs[id].get("idade", 30)) < 18
	if not GameState.is_minor() and not target_minor:
		context_menu.add_item("Pedir um abraço de amizade", 10)
		if bool(NPCManager.state[id].get("namoro", false)):
			context_menu.add_item("Beijar seu parceiro", 11)
		context_menu.add_item("Flertar", 4)
	context_menu.add_item("Provocar", 5)
	if not target_minor:
		context_menu.add_item("Ameaçar", 6)
		context_menu.add_item("Empurrar", 7)
	if not GameState.is_minor() and not target_minor:
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


func _object_actions(target: Dictionary) -> Array:
	var out: Array = []
	if world_view.action_busy():
		return [{"label": "Levantar / interromper atividade", "kind": "stop"}]
	if not world_view.object_access(target):
		return out
	var owner: Node3D = target.get("owner")
	if owner != null and owner.has_method("wake") and not owner.broken:
		out.append({"label": "Derrubar" if owner.held else "Pegar", "kind": "physical_hold"})
	var available: Array = Economy.available_actions()
	var ids: Array = available.map(func(a): return str(a["id"]))
	match str(target["kind"]):
		"stairs":
			return [{"label": "Subir um andar" if int(target["plan"]["destination_floor"]) > int(target["plan"]["floor"]) else "Descer um andar", "kind": "stairs"}]
		"bed":
			out.append({"label": "Deitar", "kind": "deitar"})
			for action in ["dormir_casa", "dormir_quarto", "casa_g:dormir"]:
				if action in ids:
					out.append({"label": "Deitar e dormir (8h)", "kind": "dormir", "action": action})
					break
		"seat", "tv":
			out.append({"label": "Sentar", "kind": "sentar"})
			var action := "casa:tv" if str(target["kind"]) == "tv" else "casa:sofa"
			if action in ids:
				out.append({"label": "Assistir TV (1h)" if action == "casa:tv" else "Descansar (1h)", "kind": "tv" if action == "casa:tv" else "sofa", "action": action})
		"stove":
			if "casa:cozinhar" in ids:
				out.append({"label": "Cozinhar uma refeição (R$8)", "kind": "cozinhar", "action": "casa:cozinhar"})
		"bath":
			if "banho_casa" in ids:
				out.append({"label": "Tomar banho", "kind": "banho", "action": "banho_casa"})
		"computer":
			if "casa:pc" in ids:
				out.append({"label": "Trabalhar no computador (2h)", "kind": "pc", "action": "casa:pc"})
		"storage":
			if "casa_g:vasculhar" in ids:
				out.append({"label": "Vasculhar e pegar o que encontrar (30min)", "kind": "pegar", "action": "casa_g:vasculhar"})
		"shop":
			if World.shop_open() and World.current_id() == str(target["loc"]):
				for item in target.get("items", []):
					var kind := str(GameState.MINOR_ITEMS.get(str(item), ""))
					if GameState.minor_block(kind) == "":
						out.append({"label": "Pegar e comprar %s — R$%d" % [World.item_name(str(item)), World.item_price(str(item))], "kind": "pegar", "item": str(item)})
	out.append({"label": "Examinar " + str(target["label"]).to_lower(), "kind": "examinar"})
	return out


func _open_object(target: Dictionary) -> void:
	object_target = target
	object_options = _object_actions(target)
	if object_options.is_empty():
		return
	object_menu.clear()
	object_menu.add_separator(str(target["label"]))
	for index in object_options.size():
		object_menu.add_item(str(object_options[index]["label"]), index)
	object_menu.position = Vector2i(get_global_mouse_position())
	object_menu.reset_size()
	object_menu.popup()


func _on_object(index: int) -> void:
	if index < 0 or index >= object_options.size():
		return
	var option: Dictionary = object_options[index]
	if str(option["kind"]) == "stairs":
		object_menu.hide()
		if not world_view.use_stairs(object_target):
			_toast("Não foi possível alcançar a escada.")
		return
	if str(option["kind"]) == "stop":
		world_view._cancel_action("Você se levanta.")
		return
	# Revalida no clique e no fim da animação: não dá item/renda se a ação mudou.
	if not option in _object_actions(object_target):
		_toast("Essa ação não está disponível agora.")
		return
	var target := object_target.duplicate()
	var effect := func() -> bool:
		if str(option.get("action", "")) != "":
			var ids: Array = Economy.available_actions().map(func(a): return str(a["id"]))
			if str(option["action"]) in ids and World.current_id() == str(target["loc"]):
				Economy.do_action(str(option["action"]))
			else:
				return false
		elif str(option.get("item", "")) != "":
			if World.current_id() == str(target["loc"]):
				var before := GameState.item_count(str(option["item"]))
				Economy.buy(str(option["item"]))
				return GameState.item_count(str(option["item"])) > before
			return false
		elif str(option["kind"]) == "examinar":
			_toast(str(target["label"]) + ": " + ("mercadorias à venda" if str(target["kind"]) == "shop" else "um objeto usado no cotidiano"))
		return true
	if str(option["kind"]) == "physical_hold":
		world_view.physical_world.toggle_hold(target)
		return
	if not world_view.start_object_action(target, str(option["kind"]), effect, str(option.get("item", ""))):
		_toast("Não há espaço livre para essa atividade agora.")


func _ensure_talking(id: String) -> bool:
	if NPCManager.talking_to != id:
		NPCManager.start_conversation(id)
	return NPCManager.talking_to == id


func _on_context(menu_id: int) -> void:
	var id := context_target
	if menu_id == MENU_END:
		NPCManager.end_conversation()
		return
	if menu_id in [MENU_PUNCH, MENU_WEAPON, MENU_PICKPOCKET] and GameState.refuse_minor("crime"):
		return
	if menu_id in [MENU_PUNCH, MENU_WEAPON, MENU_PICKPOCKET, 4, 6, 7] and int(NPCManager.npcs[id].get("idade", 30)) < 18:
		GameState.add_log("Não. É uma criança. (bloqueado)", "info")
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
	if menu_id in [9, 10, 11]:
		if not world_view.npcs.has(id) or (world_view.npcs[id]["fig"] as Node3D).position.distance_to(world_view.player.position) > 2.2:
			_toast("Aproxime-se da pessoa para cumprimentar ou demonstrar carinho.")
			return
		SocialSystem.contact(id, {9: "cumprimento", 10: "abraco", 11: "beijo"}[menu_id])
		return
	if menu_id == 7 and not world_view.push_npc(id): return
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
	if World.current_id() == "rua" and world_view:
		var street := world_view.current_street()
		if street != "":
			place_title.text = street
	place_sub.text = "%s • %02d:%02d • %s" % [TimeManager.short_date_str(), TimeManager.hour(), TimeManager.minute(), TimeManager.period()]
	if int(GameState.player.get("interior_floor", 0)) > 0:
		place_sub.text += " • %dº andar" % (int(GameState.player["interior_floor"]) + 1)
	(money_chip.get_child(0) as Label).text = "R$ %d" % GameState.money()
	stars_view.set_stars(CrimeSystem.wanted())
	var hol := Holidays.label_today()
	var ev_sig := ",".join(WorldEvents.labels()) + "|" + hol
	if ev_sig != _ev_sig:
		_ev_sig = ev_sig
		for c in events_box.get_children():
			c.queue_free()
		if hol != "":
			events_box.add_child(UI.chip(hol, Color("#7fd18b"), 13))
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
	# o corpo 3D do jogador também mostra o estado (rosto e postura), sem balão por cima
	if world_view and world_view.player_fig and world_view.player_fig.emotion != pemo:
		world_view.player_fig.set_emotion(pemo, false)
	player_state.text = "" if pemo == "neutro" else World.emotions[pemo]["pt"].capitalize()
	if GameState.active:
		buttons["phone"].set_badge(PhoneSystem.unread())
		var inv: Dictionary = GameState.player.get("inventory", {})
		buttons["bag"].set_badge(inv.size())
	_sync_actors()
	_update_mode()
	_refresh_dialogue_state()
	_refresh_side()


# Ações de casa com o corpo: o personagem vai até a cama/chuveiro, faz a ação e só então o
# efeito real (HomeSystem/Economy, como sempre) é aplicado. Sem ponto de uso, segue direto.
func _do_action(id: String) -> void:
	if world_view.action_busy():
		_toast("Termine a atividade atual ou ande para interrompê-la.")
		return
	var kind := ""
	match id:
		"casa:cozinhar", "casa:tv", "casa:sofa", "casa:pc":
			kind = id.trim_prefix("casa:")
		"dormir_casa", "dormir_quarto", "casa_g:dormir":
			kind = "dormir"
		"banho_casa":
			if bool(HomeSystem.utils(World.current_id()).get("agua", true)):
				kind = "banho"
	if kind != "":
		if not world_view.start_action(kind, World.current_id(), func() -> void: Economy.do_action(id)):
			_toast("Não há um lugar livre para essa atividade agora.")
		return
	Economy.do_action(id)


# Comer e beber da bolsa: senta num lugar livre (ou come em pé), com o item na mão, e só no fim
# o item sai do inventário e a necessidade muda (Economy.use_item).
func _use_item_animated(item_id: String) -> bool:
	var tipo := str(World.items.get(item_id, {}).get("tipo", ""))
	var kind := ""
	if tipo == "comida":
		kind = "comer"
	elif tipo in ["bebida", "cafe", "lata", "garrafa", "dose"]:
		kind = "beber"
	if kind == "" or not GameState.player.get("inventory", {}).has(item_id):
		return false
	return world_view.start_action(kind, World.current_id(), func() -> void: Economy.use_item(item_id), item_id)


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
		return
	var on_call := NPCManager.channel == NPCManager.LIGACAO
	dialogue.set_speaker(_speaker_name(id), NPCManager.relation_label(id))
	dialogue.set_input(can_act, "Fale ao telefone..." if on_call else "Diga algo...  (use *asteriscos* para ações, ex: *ofereço um cigarro*)", true, "Desligar" if on_call else "Encerrar")


func _section(text: String) -> void:
	var l := UI.label(text.to_upper(), 12, UI.MUTED)
	l.add_theme_font_override("font", UI.font(true))
	side_box.add_child(l)


func _refresh_side() -> void:
	# O relógio anda em tempo real; só remonta o painel quando algo nele mudou.
	var can_act := not NPCManager.busy and not narrating
	var sig := "%s|%s|%s|%s|%s|%s" % [World.current_id(), can_act, World.shop_open(), Economy.available_actions().map(func(a): return a["label"]), NPCManager.npcs_here().map(func(i): return NPCManager.display_name(i)), NPCManager.talking_to]
	if sig == _side_sig and side_box.get_child_count() > 0:
		return
	_side_sig = sig
	for c in side_box.get_children():
		c.queue_free()
	if not GameState.active:
		return
	var loc := World.current()
	_section("Neste lugar")
	if World.shop_open():
		var buy := UI.accent_button("Comprar  •  " + str(loc.get("vendedor", "")), _open_shop)
		buy.disabled = not can_act
		buy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		side_box.add_child(buy)
	for a in Economy.available_actions():
		var b := UI.button(a["label"], _do_action.bind(a["id"]))
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
	var id := NPCManager.talking_to
	if id != "":
		# conversa em andamento: tudo aparece na caixa, sob o retrato de quem fala
		dialogue.set_speaker(_speaker_name(id), NPCManager.relation_label(id))
		dialogue.show_entry(e)
		return
	# fora de conversa: avisos curtos viram balão no topo; a história abre a caixa para ler
	if kind in ["info", "error", "phone"]:
		_toast(str(e.get("text", "")).replace("*", ""))
		return
	var who := {"narration": "Narrador", "event": "Na cidade", "danger": "Atenção", "death": "", "npc": str(e.get("speaker", "")), "player": "Você"}
	dialogue.push_message(e, str(who.get(kind, "")))


func _on_submit(text: String) -> void:
	NPCManager.talk(text)


func _on_npc_thinking(npc_id: String, thinking: bool) -> void:
	# só na conversa ao vivo (mensagens de celular têm o próprio painel)
	if NPCManager.talking_to == npc_id or not thinking:
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
	if is_instance_valid(settings_overlay):
		if e.keycode == KEY_ESCAPE:
			settings_overlay._back()
		get_viewport().set_input_as_handled()
		return
	if e.keycode == KEY_ESCAPE:
		if pause_layer.visible:
			close_pause()
		elif phone.visible or bag.visible or map_panel.visible or shop.visible or history.visible or money_panel.visible or choice_panel.visible or business_panel.visible:
			return
		elif help_panel != null and help_panel.visible:
			help_panel.hide()
		elif NPCManager.talking_to != "" and not NPCManager.busy:
			NPCManager.end_conversation()
		else:
			open_pause()
		get_viewport().set_input_as_handled()
		return
	if pause_layer.visible:
		return
	if phone.visible or bag.visible or map_panel.visible or shop.visible or history.visible or money_panel.visible:
		return
	if e.keycode == KEY_F1 or e.keycode == KEY_SLASH:
		_toggle_help()
		return
	match e.keycode:
		KEY_M: _open_map()
		KEY_B: _open_bag()
		KEY_C: _open_phone()
		KEY_H: _open_history()


# Ajuda rápida: controles e onde fica cada coisa, para ninguém ficar perdido.
func _toggle_help() -> void:
	if help_panel == null:
		help_panel = PanelContainer.new()
		help_panel.add_theme_stylebox_override("panel", UI.glass(18, 22, Color(0.04, 0.05, 0.07, 0.94)))
		_anchor(help_panel, 0.5, 0.5, 0.5, 0.5)
		help_panel.offset_left = -330
		help_panel.offset_right = 330
		help_panel.offset_top = -250
		help_panel.offset_bottom = 250
		var v := UI.vbox(8)
		help_panel.add_child(v)
		v.add_child(UI.title("Como jogar", 24))
		var lines := [
			["Andar", "WASD ou setas  •  Shift corre  •  clique no chão para ir até lá"],
			["Câmera", "%s alterna • roda ajusta zoom/distância • terceira pessoa: arraste o botão direito para olhar" % OS.get_keycode_string(Settings.camera_key)],
			["Conversar", "clique numa pessoa (ou na lista Pessoas aqui)  •  escreva e aperte Enter"],
			["Ações", "use *asteriscos* para gestos: *ofereço um café*  •  só funciona com o que você tem"],
			["Opções", "botão direito numa pessoa • terceira pessoa: E interage; com mensagem aberta, E continua a leitura"],
			["Lugares", "o painel da direita mostra o que dá para fazer onde você está"],
			["Portas", "chegue perto de uma porta trancada: tentar, bater ou arrombar aparecem no painel"],
			["Atalhos", "M mapa  •  B bolsa  •  C celular  •  H histórico  •  F1 esta ajuda"],
			["Tempo", "o relógio anda sozinho; para durante conversas e com o celular aberto"],
			["Sobreviver", "fome, sede, energia, higiene, saúde e sanidade ficam no canto esquerdo"],
		]
		for ln in lines:
			var row := UI.hbox(12)
			var k := UI.label(str(ln[0]), 15, UI.ACCENT)
			k.custom_minimum_size = Vector2(110, 0)
			row.add_child(k)
			var d := UI.label(str(ln[1]), 15, UI.TEXT)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(d)
			v.add_child(row)
		v.add_child(UI.label("Aperte F1 de novo para fechar.", 13, UI.MUTED))
		add_child(help_panel)
		help_panel.hide()
	help_panel.visible = not help_panel.visible


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
	if not SaveManager.save_game():
		_toast("Não foi possível salvar o jogo. Verifique o espaço em disco e tente de novo.")


func _settings() -> void:
	if is_instance_valid(settings_overlay):
		return
	world_view._release_orbit()
	_realtime_before_settings = WorldView.realtime
	WorldView.realtime = false
	settings_overlay = preload("res://ui/settings_screen.gd").new()
	settings_overlay.set("args", {"back": "game"})
	settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_overlay.navigate.connect(func(_screen: String, _args: Dictionary):
		var overlay := settings_overlay
		settings_overlay = null
		overlay.hide()
		overlay.queue_free()
		if not pause_layer.visible:
			WorldView.realtime = _realtime_before_settings)
	add_child(settings_overlay)


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
	open_pause()


# ---------- menu de pausa ----------

func _build_pause() -> void:
	pause_layer = Control.new()
	pause_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_layer.hide()
	add_child(pause_layer)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.02, 0.015, 0.62)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_layer.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_layer.add_child(center)
	pause_box = PanelContainer.new()
	pause_box.add_theme_stylebox_override("panel", UI.glass(16, 26))
	pause_box.custom_minimum_size = Vector2(400, 0)
	center.add_child(pause_box)
	var v := UI.vbox(10)
	pause_box.add_child(v)
	var t := UI.title("Pausa", 32)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	pause_sub = UI.label("", 15, UI.MUTED)
	pause_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pause_sub)
	v.add_child(HSeparator.new())
	pause_buttons = UI.vbox(8)
	v.add_child(pause_buttons)
	var specs := [
		["Continuar", close_pause, "accent"],
		["Salvar jogo", _pause_save, ""],
		["Configurações", _settings, ""],
		["Sobre o jogo", _show_about, ""],
		["Como jogar  (F1)", func() -> void: close_pause(); _toggle_help(), ""],
		["Salvar e sair para o início", _save_and_exit, ""],
		["Sair sem salvar", _ask_exit_no_save, "danger"],
		["Sair do jogo", _ask_quit_game, "danger"],
	]
	for sp in specs:
		var b: Button = UI.accent_button(sp[0], sp[1]) if sp[2] == "accent" else UI.button(sp[0], sp[1])
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 17)
		if sp[2] == "danger":
			b.add_theme_color_override("font_color", UI.DANGER.lightened(0.15))
			b.add_theme_color_override("font_hover_color", UI.DANGER.lightened(0.3))
		pause_buttons.add_child(b)
	pause_status = UI.label("", 14, UI.TEAL)
	pause_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_status.hide()
	v.add_child(pause_status)
	# confirmação (sair sem salvar, ou sair mesmo com falha ao salvar)
	pause_confirm = UI.vbox(8)
	pause_confirm.hide()
	v.add_child(pause_confirm)
	pause_confirm_text = UI.label("", 15, UI.TEXT)
	pause_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_confirm.add_child(pause_confirm_text)
	var crow := UI.hbox(8)
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_confirm.add_child(crow)
	var yes := UI.button("Sim, sair", func() -> void: if _confirm_action.is_valid(): _confirm_action.call())
	yes.add_theme_color_override("font_color", UI.DANGER.lightened(0.15))
	yes.custom_minimum_size = Vector2(150, 40)
	crow.add_child(yes)
	var no := UI.accent_button("Voltar", _cancel_confirm)
	no.custom_minimum_size = Vector2(150, 40)
	crow.add_child(no)
	pause_confirm_yes = yes
	pause_confirm_no = no
	var version := UI.label("UniRp  •  v0.9 (11/out)", 12, UI.MUTED)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(version)


# Aniversário do jogador: retrato, idade no cartão e corpo 3D acompanham a idade nova.
func _on_birthday(id: String, _age: int) -> void:
	if id != "":
		return
	var p := GameState.player
	player_portrait.set_look(LookBuilder.build(p.get("look", {}), int(p.get("age", 30)), str(p.get("gender", "homem"))))
	player_age_label.text = "%d anos" % int(p.get("age", 0))


func open_pause() -> void:
	if pause_layer.visible:
		return
	_realtime_before_pause = WorldView.realtime
	WorldView.realtime = false
	pause_sub.text = "%s  •  %s, %s  •  %02d:%02d" % [place_title.text, TimeManager.weekday(), TimeManager.date_str(), TimeManager.hour(), TimeManager.minute()]
	pause_status.hide()
	_cancel_confirm()
	pause_layer.show()
	pause_layer.modulate.a = 0.0
	pause_box.scale = Vector2(0.96, 0.96)
	pause_box.pivot_offset = pause_box.size / 2.0
	if _pause_tween:
		_pause_tween.kill()
	_pause_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pause_tween.tween_property(pause_layer, "modulate:a", 1.0, 0.16)
	_pause_tween.tween_property(pause_box, "scale", Vector2.ONE, 0.2)


func close_pause() -> void:
	if not pause_layer.visible:
		return
	WorldView.realtime = _realtime_before_pause
	if _pause_tween:
		_pause_tween.kill()
	_pause_tween = create_tween()
	_pause_tween.tween_property(pause_layer, "modulate:a", 0.0, 0.12)
	_pause_tween.tween_callback(pause_layer.hide)


func _pause_say(text: String, ok: bool) -> void:
	pause_status.text = text
	pause_status.add_theme_color_override("font_color", UI.TEAL if ok else UI.DANGER)
	pause_status.show()


func _pause_save() -> void:
	if not GameState.active:
		_pause_say("Não há jogo em andamento para salvar.", false)
	elif SaveManager.save_game():
		_pause_say("Jogo salvo  •  %s, %02d:%02d" % [TimeManager.date_str(), TimeManager.hour(), TimeManager.minute()], true)
	else:
		_pause_say("Não foi possível salvar. Verifique o espaço em disco.", false)


# Salva com o sistema de sempre e volta para a tela inicial. Se o save falhar, não sai.
func _save_and_exit() -> void:
	if not GameState.active:
		_leave_to_title()
		return
	if NPCManager.talking_to != "":
		NPCManager.end_conversation()
	if SaveManager.save_game():
		_pause_say("Jogo salvo. Voltando para o início...", true)
		for b in pause_buttons.get_children():
			(b as Button).disabled = true
		await get_tree().create_timer(0.5).timeout
		_leave_to_title()
	else:
		_pause_say("Não foi possível salvar. O jogo continua aberto.", false)
		_ask_confirm("Sair mesmo assim, sem salvar?", _leave_to_title)


func _ask_exit_no_save() -> void:
	_ask_confirm("Sair sem salvar? Tudo o que aconteceu desde o último salvamento será perdido.", _leave_to_title)


func _ask_quit_game() -> void:
	_ask_confirm("Fechar o UniRp agora? O progresso não salvo será perdido.", _quit_game)


func _quit_game() -> void:
	_clear_pending_interaction()
	get_tree().quit()


func _ask_confirm(text: String, action: Callable) -> void:
	_confirm_action = action
	pause_confirm_text.text = text
	pause_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_confirm_yes.show()
	pause_confirm_no.text = "Voltar"
	pause_buttons.hide()
	pause_confirm.show()
	pause_confirm_no.grab_focus()


func _show_about() -> void:
	_confirm_action = Callable()
	pause_confirm_text.text = "UniRp  •  v0.9\n13 de outubro de 2026\n\nUm RPG de vida ambientado em Porto Cinza e outras cidades.\n\nCréditos de conteúdo CC0\nMakeHuman hm08 • Universal Animation Library • Quaternius e Kenney"
	pause_confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	pause_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_confirm_yes.hide()
	pause_confirm_no.text = "Voltar"
	pause_buttons.hide()
	pause_confirm.show()
	pause_confirm_no.grab_focus()


func _cancel_confirm() -> void:
	pause_confirm.hide()
	pause_buttons.show()
	_confirm_action = Callable()
	for b in pause_buttons.get_children():
		(b as Button).disabled = false


func _leave_to_title() -> void:
	_clear_pending_interaction()
	if NPCManager.talking_to != "":
		NPCManager.end_conversation()
	pause_layer.hide()
	WorldView.realtime = true
	navigate.emit("menu", {})


func _clear_pending_interaction() -> void:
	if is_instance_valid(context_menu):
		context_menu.hide()
	if is_instance_valid(object_menu):
		object_menu.hide()
	context_target = ""
	object_target.clear()
	object_options.clear()
	if is_instance_valid(world_view):
		world_view.pending_npc = ""
		world_view.hover_id = ""
		world_view.hover_object.clear()
		world_view.path = PackedVector2Array()
		world_view._release_orbit(false)
		if world_view.action_busy():
			world_view._cancel_action("")
