extends Control

signal navigate(screen: String, args: Dictionary)

const UI = preload("res://ui/ui_theme.gd")

var args: Dictionary = {}


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := UI.vbox(14)
	box.custom_minimum_size = Vector2(420, 0)
	center.add_child(box)

	var t := UI.title("UniRp", 64)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var sub := UI.label("Porto Cinza. Ninguém aqui é o que parece.", 16, UI.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(Control.new())

	box.add_child(UI.button("Novo jogo", func(): navigate.emit("creation", {})))
	var cont := UI.button("Continuar", _continue)
	cont.disabled = not SaveManager.has_save()
	box.add_child(cont)
	box.add_child(UI.button("Configurações", func(): navigate.emit("settings", {"back": "menu"})))
	box.add_child(UI.button("Sair", func(): get_tree().quit()))

	if not Settings.is_ready():
		var warn := UI.label("A IA ainda não está configurada. Vá em Configurações e coloque sua chave do OpenRouter.", 14, UI.DANGER)
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(warn)


func _continue() -> void:
	if SaveManager.load_game():
		navigate.emit("game", {})
