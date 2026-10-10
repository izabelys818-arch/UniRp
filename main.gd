extends Control

const UITheme = preload("res://ui/ui_theme.gd")
const SCREENS := {
	"menu": preload("res://ui/main_menu.gd"),
	"settings": preload("res://ui/settings_screen.gd"),
	"creation": preload("res://ui/character_creation.gd"),
	"game": preload("res://ui/game_screen.gd"),
}

var current: Control
var switching := false


func _ready() -> void:
	theme = UITheme.build()
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	show_screen("menu")


func show_screen(screen: String, args: Dictionary = {}) -> void:
	if switching:
		return
	if screen == "game":
		switching = true
		var cover := ColorRect.new()
		cover.color = UITheme.BG
		cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var message := Label.new()
		message.text = "Preparando sua cidade…"
		message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		message.add_theme_font_size_override("font_size", 26)
		cover.add_child(message)
		add_child(cover)
		await get_tree().process_frame
		await get_tree().process_frame
		if current:
			remove_child(current)
			current.queue_free()
			current = null
		await get_tree().process_frame
		cover.queue_free()
	if current:
		current.queue_free()
	current = SCREENS[screen].new()
	current.set("args", args)
	current.set_anchors_preset(Control.PRESET_FULL_RECT)
	current.connect("navigate", show_screen)
	add_child(current)
	switching = false
