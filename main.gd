extends Control

const UITheme = preload("res://ui/ui_theme.gd")
const SCREENS := {
	"menu": preload("res://ui/main_menu.gd"),
	"settings": preload("res://ui/settings_screen.gd"),
	"creation": preload("res://ui/character_creation.gd"),
	"game": preload("res://ui/game_screen.gd"),
}

var current: Control


func _ready() -> void:
	theme = UITheme.build()
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	show_screen("menu")


func show_screen(screen: String, args: Dictionary = {}) -> void:
	if current:
		current.queue_free()
	current = SCREENS[screen].new()
	current.set("args", args)
	current.set_anchors_preset(Control.PRESET_FULL_RECT)
	current.connect("navigate", show_screen)
	add_child(current)
