extends Control

# Tela inicial cinematográfica: a cidade ao entardecer ao fundo, acabamento de filme,
# barras de cinema, título grande e menu navegável por teclado ou mouse.

signal navigate(screen: String, args: Dictionary)

const UI = preload("res://ui/ui_theme.gd")
const Backdrop = preload("res://ui/menu/menu_backdrop.gd")
const FilmFx = preload("res://ui/menu/film_fx.gd")

const INK := Color("#f3e9d4")
const DIM := Color("#b3a48c")
const AMBER := Color("#f0b04a")

var args: Dictionary = {}
var backdrop: Backdrop
var fx: FilmFx
var rows: Array = []
var focus: int = 0
var bars: Array = []
var title_group: Control
var black: ColorRect
var intro_started: bool = false
var intro_t: float = 0.0
var leaving: bool = false
var _flicker_t: float = 0.0
var _sub: Control
var _tag: Label
var _line: ColorRect
var _hint: Control
var _preview: Dictionary = {}


static func _font(weight: int, spacing: int, italic: bool = false, serif: bool = false) -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Sitka Text", "Georgia", "Times New Roman"] if serif else ["Bahnschrift", "Segoe UI", "Arial"])
	sf.font_weight = weight
	sf.font_italic = italic
	sf.antialiasing = TextServer.FONT_ANTIALIASING_LCD
	var fv := FontVariation.new()
	fv.base_font = sf
	fv.spacing_glyph = spacing
	return fv


func _label(text: String, size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _ready() -> void:
	set_process_unhandled_input(true)
	_preview = SaveManager.preview()
	backdrop = Backdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	fx = FilmFx.new()
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fx)
	# vinheta e grão mais suaves: a cidade de fundo respira, sem bordas pretas pesadas
	fx.mat.set_shader_parameter("vignette", 0.55)
	fx.mat.set_shader_parameter("grain", 0.05)
	_build_shade()
	_build_title()
	_build_menu()
	_build_footer()
	_build_bars()
	black = ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	_set_focus(_first_enabled(), false)
	_hide_all()


# escurece o lado esquerdo para o texto ter contraste, sem perder a imagem
func _build_shade() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.color = Color(0, 0, 0, 0)
	shade.draw.connect(func() -> void:
		var w := shade.size.x
		var h := shade.size.y
		shade.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.58, 0), Vector2(w * 0.58, h), Vector2(0, h)]),
			PackedColorArray([Color(0.06, 0.04, 0.025, 0.86), Color(0.06, 0.04, 0.025, 0.0), Color(0.06, 0.04, 0.025, 0.0), Color(0.06, 0.04, 0.025, 0.86)]))
		shade.draw_polygon(PackedVector2Array([Vector2(0, h * 0.72), Vector2(w, h * 0.72), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([Color(0.05, 0.03, 0.02, 0.0), Color(0.05, 0.03, 0.02, 0.0), Color(0.05, 0.03, 0.02, 0.6), Color(0.05, 0.03, 0.02, 0.6)])))
	add_child(shade)


func _build_title() -> void:
	title_group = Control.new()
	title_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_group.anchor_top = 0.0
	title_group.anchor_bottom = 0.0
	title_group.position = Vector2(118, 0)
	add_child(title_group)
	_tag = _label("UM RPG DE VIDA, SOBREVIVÊNCIA E MENTIRAS", 13, AMBER, _font(500, 7))
	_tag.position = Vector2(4, 0)
	title_group.add_child(_tag)
	var shadow := _label("UNIRP", 138, Color(0, 0, 0, 0.55), _font(300, 22))
	shadow.position = Vector2(8, 38)
	title_group.add_child(shadow)
	var title := _label("UNIRP", 138, INK, _font(300, 22))
	title.position = Vector2(0, 30)
	title_group.add_child(title)
	_line = ColorRect.new()
	_line.color = Color(INK, 0.55)
	_line.size = Vector2(380, 1)
	_line.position = Vector2(6, 202)
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_group.add_child(_line)
	var dia := ColorRect.new()
	dia.color = AMBER
	dia.size = Vector2(7, 7)
	dia.pivot_offset = Vector2(3.5, 3.5)
	dia.rotation = PI / 4.0
	dia.position = Vector2(2, 199)
	dia.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_group.add_child(dia)
	_sub = _label("Porto Cinza. Ninguém aqui é o que parece.", 22, Color(INK, 0.82), _font(400, 1, true, true))
	_sub.position = Vector2(6, 216)
	title_group.add_child(_sub)


func _build_menu() -> void:
	var list: Array = [
		{"id": "continuar", "label": "CONTINUAR", "on": SaveManager.has_save(), "sub": _save_line()},
		{"id": "novo", "label": "NOVO JOGO", "on": true, "sub": ""},
		{"id": "config", "label": "CONFIGURAÇÕES", "on": true, "sub": ""},
		{"id": "sair", "label": "SAIR", "on": true, "sub": ""},
	]
	var col := VBoxContainer.new()
	col.name = "MenuCol"
	col.add_theme_constant_override("separation", 4)
	col.position = Vector2(112, 0)
	add_child(col)
	for it in list:
		var row := Control.new()
		row.custom_minimum_size = Vector2(430, 62 if str(it["sub"]) != "" else 54)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var bg := TextureRect.new()
		var grad := Gradient.new()
		# destaque do item escolhido: faixa de madeira dourada que se apaga para a direita
		grad.set_color(0, Color(0.94, 0.69, 0.29, 0.26))
		grad.set_color(1, Color(0.54, 0.4, 0.26, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill_from = Vector2(0, 0.5)
		gt.fill_to = Vector2(1, 0.5)
		gt.width = 256
		gt.height = 4
		bg.texture = gt
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.modulate.a = 0.0
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(bg)
		var marker := ColorRect.new()
		marker.color = AMBER
		marker.size = Vector2(3, 26)
		marker.position = Vector2(0, (row.custom_minimum_size.y - 26) / 2.0 - (6 if str(it["sub"]) != "" else 0))
		marker.scale = Vector2(1, 0)
		marker.pivot_offset = Vector2(1.5, 13)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(marker)
		var lab := _label(str(it["label"]), 25, INK if it["on"] else Color(DIM, 0.45), _font(400, 9))
		lab.position = Vector2(22, (row.custom_minimum_size.y - 36) / 2.0 - (8 if str(it["sub"]) != "" else 0))
		row.add_child(lab)
		var sub: Label = null
		if str(it["sub"]) != "":
			sub = _label(str(it["sub"]), 13, Color(DIM, 0.95), _font(400, 2))
			sub.position = Vector2(24, row.custom_minimum_size.y - 24)
			row.add_child(sub)
		col.add_child(row)
		var rec := {"id": it["id"], "on": it["on"], "row": row, "bg": bg, "marker": marker, "label": lab, "sub": sub}
		rows.append(rec)
		var idx := rows.size() - 1
		row.mouse_entered.connect(func() -> void: if rec["on"]: _set_focus(idx))
		row.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and rec["on"]:
				_set_focus(idx)
				_activate())
	if not Settings.is_ready():
		var warn := _label("●  IA não configurada. Abra Configurações para conversar livremente.", 13, Color(AMBER, 0.85), _font(400, 1))
		warn.name = "Warn"
		add_child(warn)


func _save_line() -> String:
	if _preview.is_empty():
		return ""
	var loc: String = World.locations.get(str(_preview.get("location", "")), {}).get("nome", "")
	return "%s   •   %s   •   %s   •   R$ %d" % [str(_preview.get("name", "")), str(_preview.get("date", "Dia %d" % int(_preview.get("day", 1)))), loc if loc != "" else "Porto Cinza", int(_preview.get("money", 0))]


func _build_footer() -> void:
	_hint = Control.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	var h := _label("↑ ↓   NAVEGAR          ENTER   SELECIONAR", 12, Color(DIM, 0.8), _font(400, 4))
	h.name = "Hint"
	_hint.add_child(h)
	var v := _label("v0.8 (10/out)   •   Godot 4   •   modelos 3D CC0 de Quaternius e Kenney", 12, Color(DIM, 0.6), _font(400, 2))
	v.name = "Ver"
	_hint.add_child(v)


func _build_bars() -> void:
	for i in 2:
		var b := ColorRect.new()
		b.color = Color.BLACK
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(b)
		bars.append(b)


func _hide_all() -> void:
	title_group.modulate.a = 0.0
	for r in rows:
		(r["row"] as Control).modulate.a = 0.0
	_hint.modulate.a = 0.0
	var w := get_node_or_null("Warn")
	if w:
		w.modulate.a = 0.0


func _first_enabled() -> int:
	for i in rows.size():
		if rows[i]["on"]:
			return i
	return 0


func _set_focus(i: int, animate: bool = true) -> void:
	focus = i
	for j in rows.size():
		var r: Dictionary = rows[j]
		var on: bool = j == i
		var t := create_tween().set_parallel(true)
		var dur := 0.22 if animate else 0.0
		t.tween_property(r["bg"], "modulate:a", 1.0 if on else 0.0, dur)
		t.tween_property(r["marker"], "scale:y", 1.0 if on else 0.0, dur)
		t.tween_property(r["label"], "position:x", 36.0 if on else 22.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var base: Color = INK if r["on"] else Color(DIM, 0.45)
		t.tween_property(r["label"], "theme_override_colors/font_color", (Color("#fff4dc") if on else base), dur)
		if r["sub"] != null:
			t.tween_property(r["sub"], "position:x", 38.0 if on else 24.0, dur)


func _move(dir: int) -> void:
	var n := rows.size()
	for k in n:
		var j := (focus + dir * (k + 1) + n * 4) % n
		if rows[j]["on"]:
			_set_focus(j)
			return


func _unhandled_input(e: InputEvent) -> void:
	if leaving or not intro_started:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_UP, KEY_W:
				_move(-1)
				get_viewport().set_input_as_handled()
			KEY_DOWN, KEY_S:
				_move(1)
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_activate()
				get_viewport().set_input_as_handled()


func _activate() -> void:
	if leaving or not rows[focus]["on"]:
		return
	var id: String = rows[focus]["id"]
	leaving = true
	var t := create_tween()
	t.tween_method(fx.set_fade, 0.0, 1.0, 0.55)
	t.parallel().tween_property(title_group, "modulate:a", 0.0, 0.4)
	for r in rows:
		t.parallel().tween_property(r["row"], "modulate:a", 0.0, 0.4)
	await t.finished
	match id:
		"continuar":
			if SaveManager.load_game():
				navigate.emit("game", {})
			else:
				navigate.emit("menu", {})
		"novo":
			navigate.emit("creation", {})
		"config":
			navigate.emit("settings", {"back": "menu"})
		"sair":
			get_tree().quit()


func _layout() -> void:
	var w := size.x
	var h := size.y
	var bar := h * 0.085
	bars[0].position = Vector2.ZERO
	bars[0].size = Vector2(w, bar)
	bars[1].position = Vector2(0, h - bar)
	bars[1].size = Vector2(w, bar)
	var col := get_node_or_null("MenuCol") as Control
	var menu_h := 0.0
	for r in rows:
		menu_h += (r["row"] as Control).custom_minimum_size.y + 4.0
	var top := h * 0.5 - 36.0
	title_group.position = Vector2(118, maxf(bar + 20.0, top - 290.0))
	if col:
		col.position = Vector2(112, top)
	var warn := get_node_or_null("Warn") as Control
	if warn:
		warn.position = Vector2(118, top + menu_h + 18.0)
	var hint := _hint.get_node("Hint") as Control
	hint.position = Vector2(118, h - bar - 36.0)
	var ver := _hint.get_node("Ver") as Control
	ver.position = Vector2(w - ver.get_minimum_size().x - 40.0, h - bar - 36.0)


func _process(delta: float) -> void:
	_layout()
	if not intro_started:
		if backdrop.ready_city and backdrop.t > 0.4:
			intro_started = true
			_start_intro()
		return
	_flicker_t -= delta
	if _flicker_t <= 0.0 and not leaving:
		_flicker_t = randf_range(0.05, 0.4)
		var a := 1.0 if randf() < 0.9 else randf_range(0.86, 0.97)
		title_group.modulate.a = lerpf(title_group.modulate.a, a, 0.6)


func _start_intro() -> void:
	var t := create_tween()
	t.tween_property(black, "color:a", 0.0, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var tt := create_tween()
	tt.tween_interval(1.1)
	tt.tween_property(title_group, "modulate:a", 1.0, 1.4)
	var pos0 := title_group.position
	var ln := create_tween()
	ln.tween_interval(1.5)
	_line.size.x = 0.0
	ln.tween_property(_line, "size:x", 380.0, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var mt := create_tween()
	mt.tween_interval(2.0)
	for r in rows:
		var row: Control = r["row"]
		mt.tween_property(row, "modulate:a", 1.0, 0.45)
		mt.parallel().tween_property(row, "position:x", 0.0, 0.0)
		mt.tween_interval(0.12)
	var ft := create_tween()
	ft.tween_interval(3.2)
	ft.tween_property(_hint, "modulate:a", 1.0, 0.8)
	var w := get_node_or_null("Warn")
	if w:
		ft.parallel().tween_property(w, "modulate:a", 1.0, 0.8)
