extends "res://ui/game/overlay.gd"

const ItemCard = preload("res://ui/game/item_card.gd")


func _ready() -> void:
	_build_overlay("Comprar", Vector2(820, 560))
	GameState.player_changed.connect(_refresh_if_open)


func open() -> void:
	_refresh()
	open_overlay()


func _refresh_if_open() -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	clear_content()
	var loc := World.current()
	title_label.text = str(loc.get("vendedor", "Comprar"))
	var top := UI.hbox(10)
	content.add_child(top)
	top.add_child(UI.chip("Carteira: R$ %d" % GameState.money(), UI.TEAL, 15))
	if not World.shop_open():
		content.add_child(UI.label("Não tem ninguém vendendo agora.", 16, UI.MUTED))
		return
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	content.add_child(UI.scroll(grid))
	for id in loc.get("loja", []):
		var it: Dictionary = World.items[id]
		var box := UI.vbox(6)
		var card_btn := ItemCard.new(id, 0, "R$ %d" % World.item_price(id))
		var effects: Array = []
		for k in it["efeitos"]:
			var v := int(it["efeitos"][k])
			effects.append("%s%d %s" % ["+" if v > 0 else "", v, NeedsSystem.LABELS.get(k, k)])
		card_btn.tooltip_text = "\n".join(effects)
		card_btn.pressed.connect(_buy.bind(id))
		card_btn.disabled = GameState.money() < World.item_price(id)
		box.add_child(card_btn)
		var buy := UI.button("Comprar", _buy.bind(id))
		buy.disabled = card_btn.disabled
		box.add_child(buy)
		grid.add_child(box)


func _buy(id: String) -> void:
	Economy.buy(id)
	_refresh()
