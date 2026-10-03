extends Control

const UI = preload("res://ui/ui_theme.gd")
const JOLT := ["furioso", "irritado", "ameacador", "surpreso", "assustado"]
const TREMBLE := {"assustado": 1.6, "nervoso": 0.8, "chorando": 1.0, "furioso": 0.9}
const CROSSFADE := 0.35

var min_size: Vector2 = Vector2(300, 400)
var npc_id: String = ""
var emotion: String = "neutro"
var back: TextureRect
var front: TextureRect
var fallback: ColorRect
var initials: Label
var vignette: TextureRect
var t: float = 0.0
var jolt: float = 0.0


func _ready() -> void:
	clip_contents = true
	custom_minimum_size = min_size

	fallback = ColorRect.new()
	fallback.color = UI.PANEL_LIGHT
	fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fallback)
	initials = UI.title("?", int(min_size.y * 0.24))
	initials.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initials.set_anchors_preset(Control.PRESET_FULL_RECT)
	fallback.add_child(initials)

	back = _make_rect()
	front = _make_rect()
	vignette = TextureRect.new()
	vignette.texture = _vignette_texture()
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	PortraitService.portrait_ready.connect(_on_portrait_ready)


func _make_rect() -> TextureRect:
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _vignette_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0.75))
	g.add_point(0.55, Color(0, 0, 0, 0.05))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.42)
	tex.fill_to = Vector2(1.05, 1.05)
	return tex


func show_npc(id: String, emo: String, color: Color, letter: String) -> void:
	var emotion_changed := emo != emotion and id == npc_id
	npc_id = id
	emotion = emo
	fallback.color = color
	initials.text = letter
	var tex: Texture2D = PortraitService.best_texture(id, emo) if id != "" else null
	if tex != front.texture:
		_crossfade(tex)
	fallback.visible = tex == null
	if emotion_changed and emo in JOLT:
		jolt = 0.3


func _crossfade(tex: Texture2D) -> void:
	back.texture = front.texture
	back.modulate.a = 1.0
	front.texture = tex
	front.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(front, "modulate:a", 1.0, CROSSFADE)


func _on_portrait_ready(id: String, emo: String) -> void:
	if id == npc_id and (emo == emotion or emo == "neutro"):
		show_npc(npc_id, emotion, fallback.color, initials.text)


func _process(delta: float) -> void:
	t += delta
	var breath := 1.03 + sin(t * 1.7) * 0.006
	var offset := Vector2(0, sin(t * 1.7) * 1.2)
	if jolt > 0.0:
		jolt -= delta
		offset += Vector2(randf_range(-6, 6), randf_range(-4, 4)) * (jolt / 0.3)
	elif TREMBLE.has(emotion):
		var a: float = TREMBLE[emotion]
		offset += Vector2(randf_range(-a, a), randf_range(-a * 0.6, a * 0.6))
	for r in [back, front]:
		r.pivot_offset = size / 2.0
		r.scale = Vector2(breath, breath)
		r.position = offset
