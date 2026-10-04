extends "res://ui/game/overlay.gd"

const Icons = preload("res://ui/game/icons.gd")

var price_slider: HSlider


func _ready() -> void:
	_build_overlay("Sua lanchonete", Vector2(1000, 640))
	BusinessSystem.changed.connect(_refresh_if_open)


func open() -> void:
	_refresh()
	open_overlay()


func _refresh_if_open() -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	clear_content()
	if not BusinessSystem.owned():
		content.add_child(UI.label("Você ainda não tem uma lanchonete. Veja o app Imóveis no celular.", 16, UI.MUTED))
		return
	var b := BusinessSystem.biz()
	var row := UI.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)

	var left := UI.vbox(8)
	var lp := PanelContainer.new()
	lp.add_theme_stylebox_override("panel", UI._box(Color(1, 1, 1, 0.04), 16, 14))
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lp.add_child(left)
	row.add_child(lp)
	left.add_child(UI.label("ESTOQUE E ATACADO", 12, UI.MUTED))
	for item_id in BusinessSystem.PRODUTOS:
		var line := UI.hbox(10)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(34, 34)
		var kind: String = str(World.items[item_id]["tipo"])
		icon.draw.connect(func(): Icons.draw(icon, kind, Rect2(3, 3, 28, 28), UI.ACCENT, 2.0))
		line.add_child(icon)
		var name_l := UI.label("%s  (R$ %d)" % [World.item_name(item_id), BusinessSystem.price_of(item_id)], 15)
		name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		name_l.custom_minimum_size = Vector2(230, 0)
		line.add_child(name_l)
		var qty := int(b["stock"].get(item_id, 0))
		var stock_l := UI.label("estoque: %d" % qty, 14, UI.DANGER if qty <= 0 else UI.TEAL)
		stock_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		stock_l.custom_minimum_size = Vector2(110, 0)
		line.add_child(stock_l)
		for n in [10, 30]:
			var btn := UI.button("+%d  R$ %d" % [n, BusinessSystem.cost_of(item_id) * n], _restock.bind(item_id, n))
			btn.disabled = GameState.money() < BusinessSystem.cost_of(item_id) * n
			line.add_child(btn)
		left.add_child(line)

	var right := UI.vbox(10)
	var rp := PanelContainer.new()
	rp.add_theme_stylebox_override("panel", UI._box(Color(1, 1, 1, 0.04), 16, 14))
	rp.custom_minimum_size = Vector2(330, 0)
	rp.add_child(right)
	row.add_child(rp)
	right.add_child(UI.label("CAIXA", 12, UI.MUTED))
	right.add_child(UI.title("R$ %d" % int(b["cash"]), 34))
	var collect_btn := UI.accent_button("Retirar o caixa", _collect)
	collect_btn.disabled = int(b["cash"]) <= 0
	right.add_child(collect_btn)
	right.add_child(UI.label("Hoje: R$ %d  •  Ontem: R$ %d  •  Clientes: %d" % [int(b["vendas_hoje"]), int(b["ontem"]), int(b["clientes"])], 13, UI.MUTED))
	right.add_child(UI.chip("Reputação %d de 5" % BusinessSystem.stars(), UI.ACCENT, 14))
	right.add_child(HSeparator.new())
	right.add_child(UI.label("PREÇOS: %d%% da tabela" % int(round(float(b["preco"]) * 100.0)), 12, UI.MUTED))
	price_slider = HSlider.new()
	price_slider.min_value = 0.7
	price_slider.max_value = 1.5
	price_slider.step = 0.05
	price_slider.value = float(b["preco"])
	price_slider.value_changed.connect(_on_price)
	right.add_child(price_slider)
	right.add_child(UI.label("Preço baixo atrai mais gente. Preço alto afasta clientes.", 12, UI.MUTED))
	right.add_child(HSeparator.new())
	var toggle := UI.accent_button("Fechar a lanchonete" if b["aberto"] else "Abrir a lanchonete", _toggle)
	right.add_child(toggle)
	right.add_child(UI.label("Aberta das 7h às 21h. Se você não estiver lá, vende cerca de 60%.", 12, UI.MUTED))


func _restock(item_id: String, qty: int) -> void:
	BusinessSystem.restock(item_id, qty)


func _collect() -> void:
	BusinessSystem.collect()


func _toggle() -> void:
	BusinessSystem.toggle_open()


func _on_price(v: float) -> void:
	BusinessSystem.biz()["preco"] = clampf(v, 0.7, 1.5)
