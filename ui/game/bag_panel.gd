extends "res://ui/game/overlay.gd"

const ItemCard = preload("res://ui/game/item_card.gd")

var selected: String = ""
var grid: GridContainer
var detail: VBoxContainer


func _ready() -> void:
	_build_overlay("Bolsa", Vector2(940, 600))
	GameState.player_changed.connect(_refresh_if_open)


func open() -> void:
	selected = ""
	_refresh()
	open_overlay()


func _refresh_if_open() -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	clear_content()
	var top := UI.hbox(10)
	content.add_child(top)
	top.add_child(UI.chip("Carteira: R$ %d" % GameState.money(), UI.TEAL, 15))
	var car := str(GameState.player.get("car", ""))
	if car != "":
		top.add_child(UI.chip("Chave do carro: " + car, UI.MUTED, 15))
	if str(GameState.player.get("home", "")) != "":
		top.add_child(UI.chip("Chave de casa", UI.MUTED, 15))
	for key in World.keys():
		if World.has_key(key):
			var left_min: int = World.key_expires(key) - TimeManager.total_minutes
			top.add_child(UI.chip("Chave: quarto da pensão (vence em %dh)" % int(ceil(left_min / 60.0)), UI.ACCENT, 15))
	var row := UI.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var sc := UI.scroll(grid)
	sc.custom_minimum_size = Vector2(560, 0)
	row.add_child(sc)
	var inv: Dictionary = GameState.player.get("inventory", {})
	if inv.is_empty():
		grid.add_child(UI.label("Sua bolsa está vazia.", 16, UI.MUTED))
	for id in inv:
		var card_btn := ItemCard.new(id, int(inv[id]))
		card_btn.selected = id == selected
		card_btn.pressed.connect(_select.bind(id))
		grid.add_child(card_btn)
	var clues: Array = CrimeSystem.data().get("pistas", [])
	if not clues.is_empty():
		content.add_child(UI.label("ANOTAÇÕES E PISTAS", 12, UI.MUTED))
		for clue in clues:
			var cp := PanelContainer.new()
			cp.add_theme_stylebox_override("panel", UI._box(Color(UI.ACCENT, 0.08), 10, 10))
			cp.add_child(UI.label(str(clue), 14, UI.TEXT))
			content.add_child(cp)
	detail = UI.vbox(10)
	var dp := PanelContainer.new()
	dp.add_theme_stylebox_override("panel", UI._box(Color(1, 1, 1, 0.04), 16, 16))
	dp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dp.add_child(detail)
	row.add_child(dp)
	_fill_detail()


func _select(id: String) -> void:
	selected = id
	_refresh()


func _fill_detail() -> void:
	if selected == "" or not GameState.player["inventory"].has(selected):
		detail.add_child(UI.label("Selecione um item para ver o que ele faz.", 15, UI.MUTED))
		return
	var it: Dictionary = World.items[selected]
	detail.add_child(UI.title(it["nome"], 22))
	detail.add_child(UI.label("Quantidade: %d" % GameState.item_count(selected), 14, UI.MUTED))
	for k in it["efeitos"]:
		var v := int(it["efeitos"][k])
		detail.add_child(UI.label("%s%d  %s" % ["+" if v > 0 else "", v, NeedsSystem.LABELS.get(k, k)], 15, UI.TEAL if v > 0 else UI.DANGER))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(spacer)
	detail.add_child(UI.accent_button("Usar", _use))
	var npc := NPCManager.talking_to
	if npc != "" and NPCManager.channel == NPCManager.PRESENCIAL:
		detail.add_child(UI.button("Dar para %s" % NPCManager.display_name(npc), _give))
	detail.add_child(UI.button("Jogar fora", _discard))


func _use() -> void:
	Economy.use_item(selected)
	_refresh()


func _give() -> void:
	var id := selected
	close()
	NPCManager.give_item(id)


func _discard() -> void:
	GameState.remove_item(selected)
	GameState.add_log("Você jogou fora: %s." % World.item_name(selected), "info")
	_refresh()
