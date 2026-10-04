extends "res://ui/game/overlay.gd"

var amount: SpinBox


func _ready() -> void:
	_build_overlay("Dar dinheiro", Vector2(420, 260))
	amount = SpinBox.new()
	amount.min_value = 1
	amount.max_value = 100000
	amount.value = 20
	amount.prefix = "R$"
	content.add_child(amount)
	var row := UI.hbox(10)
	content.add_child(row)
	for v in [5, 20, 50, 100]:
		row.add_child(UI.button("R$ %d" % v, func(): amount.value = v))
	content.add_child(UI.accent_button("Entregar", _give))


func open() -> void:
	amount.max_value = maxi(1, GameState.money())
	title_label.text = "Dar dinheiro para %s" % NPCManager.display_name(NPCManager.talking_to)
	open_overlay()


func _give() -> void:
	close()
	NPCManager.give_money(int(amount.value))
