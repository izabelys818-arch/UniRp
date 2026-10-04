extends Control

signal navigate(screen: String, args: Dictionary)

const UI = preload("res://ui/ui_theme.gd")
const SceneView = preload("res://ui/game/scene_view.gd")

var args: Dictionary = {}


func _ready() -> void:
	var bg := SceneView.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.force_night = true
	add_child(bg)
	bg.set_place("praca", "rua")

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.color = Color(0, 0, 0, 0)
	shade.draw.connect(func():
		var w := shade.size.x
		var h := shade.size.y
		shade.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.62, 0), Vector2(w * 0.62, h), Vector2(0, h)]),
			PackedColorArray([Color(0, 0, 0, 0.88), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.88)])))
	add_child(shade)

	var box := UI.vbox(14)
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = 90
	box.offset_top = -230
	box.custom_minimum_size = Vector2(360, 0)
	add_child(box)

	var title := UI.title("UNIRP", 104)
	title.add_theme_constant_override("outline_size", 0)
	box.add_child(title)
	var sub := UI.label("Porto Cinza. Ninguém aqui é o que parece.", 19, UI.TEXT)
	box.add_child(sub)
	var line := ColorRect.new()
	line.color = UI.ACCENT
	line.custom_minimum_size = Vector2(80, 3)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(line)
	box.add_child(Control.new())

	var new_btn := UI.accent_button("Novo jogo", func(): navigate.emit("creation", {}))
	new_btn.custom_minimum_size = Vector2(320, 52)
	box.add_child(new_btn)
	var cont := UI.button("Continuar", _continue)
	cont.disabled = not SaveManager.has_save()
	cont.custom_minimum_size = Vector2(320, 48)
	box.add_child(cont)
	var cfg := UI.button("Configurações", func(): navigate.emit("settings", {"back": "menu"}))
	cfg.custom_minimum_size = Vector2(320, 48)
	box.add_child(cfg)
	var quit := UI.button("Sair", func(): get_tree().quit())
	quit.custom_minimum_size = Vector2(320, 48)
	box.add_child(quit)
	for b in [new_btn, cont, cfg, quit]:
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 19)

	if not Settings.is_ready():
		box.add_child(UI.chip("IA não configurada: abra Configurações e coloque sua chave do OpenRouter", UI.DANGER, 13))

	var footer := UI.label("v0.3  •  feito em Godot", 13, Color(1, 1, 1, 0.35))
	footer.autowrap_mode = TextServer.AUTOWRAP_OFF
	footer.anchor_top = 1
	footer.anchor_bottom = 1
	footer.offset_left = 90
	footer.offset_top = -40
	add_child(footer)

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.6)


func _continue() -> void:
	if SaveManager.load_game():
		navigate.emit("game", {})
