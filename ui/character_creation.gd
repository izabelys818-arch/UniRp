extends Control

signal navigate(screen: String, args: Dictionary)

# Criação de personagem: categorias numa coluna, controles de verdade à direita e prévia ao vivo
# (retrato da própria pessoa ou corpo 3D girando, com as expressões). A linha "Editando" mostra o que está
# sendo mexido e o rodapé da prévia diz o que mudou. Idade em faixas (criança, adolescente,
# adulto, idoso) com data de aniversário no calendário do jogo.

const UI = preload("res://ui/ui_theme.gd")
const FaceRig = preload("res://ui/face/face_portrait.gd")  # retrato da própria pessoa 3D
const LookBuilder = preload("res://ui/face/look_builder.gd")
const Person = preload("res://world3d/person.gd")
const MAX_TRAITS := 3
const GENDERS := ["homem", "mulher", "pessoa não-binária"]
const PREVIEW_EMOTIONS := ["neutro", "feliz", "rindo", "triste", "chorando", "furioso", "assustado", "exausto"]
const CLOTHES_SWATCHES := ["#2a2a2e", "#4a5260", "#3d5a80", "#1d4f91", "#2f5a3a", "#6b5a3a", "#7a2040", "#8a2b2b", "#b5838d", "#c97a5a", "#d8d2c4", "#f0f0f0"]
const CATEGORIES := [
	["identidade", "Identidade"], ["idade", "Idade e aniversário"], ["rosto", "Rosto"], ["olhos", "Olhos"],
	["sobrancelhas", "Sobrancelhas"], ["nariz_boca", "Nariz e boca"], ["orelhas", "Orelhas"], ["pele", "Pele e marcas"],
	["cabelo", "Cabelo"], ["barba", "Barba e bigode"], ["corpo", "Corpo"], ["roupa", "Roupa e acessórios"], ["historia", "História"],
]
# [id, nome, idade mínima, idade máxima, idade sugerida]
const STAGES := [["crianca", "Criança", 6, 12, 9], ["adolescente", "Adolescente", 13, 17, 15], ["adulto", "Adulto", 18, 59, 28], ["idoso", "Idoso", 60, 90, 68]]
# [nome, ajuste de abertura, ajuste de inclinação]
const EYE_SHAPES := [["Amendoados", 0.0, 0.0], ["Redondos", 0.7, -0.2], ["Caídos", -0.1, -0.85], ["Puxados", -0.55, 0.8], ["Fundos e estreitos", -0.6, 0.0], ["Grandes e abertos", 0.9, 0.1]]
const CLOTHES_MATERIAL := {
	"camiseta": "algodão leve", "moletom": "moletom felpado com capuz", "couro": "couro com brilho", "jeans": "jeans grosso",
	"social": "camisa de tricoline", "terno": "lã fria, gravata", "regata": "malha fina", "vestido": "tecido fluido",
	"blusa": "seda com decote", "time": "poliéster de time", "uniforme": "brim de trabalho", "academia": "tecido esportivo",
	"rasgada": "pano gasto e rasgado", "sobretudo": "lã pesada",
}
const STAGE_INFO := {
	"crianca": "Corpo menor, cabeça proporcionalmente maior, traços suaves e olhos grandes. Menor de idade: sem bebida, cigarro, drogas, crime, trabalho, carro, contratos nem romance.",
	"adolescente": "Quase adulto: rosto ainda arredondado e ombros estreitos. Menor de idade: sem bebida, cigarro, drogas, crime, trabalho de adulto, carro, contratos nem romance. Bicos a partir dos 14.",
	"adulto": "Corpo e rosto completos. Rugas e fios brancos começam a aparecer com o passar dos anos.",
	"idoso": "Rugas, cabelo grisalho ou ralo, postura um pouco curvada. A idade aparece no retrato e no corpo 3D.",
}

var args: Dictionary = {}
var spec: Dictionary = {
	"pele": 2, "tracos": 0, "corpo": 1, "altura": 0, "rosto": 0, "cabelo": 0, "cor_cabelo": 1,
	"olhos": 0, "sobrancelha": -1, "barba": 0, "roupa": 0, "marcas": [], "ajustes": {},
}
var player_name: String = ""
var age: int = 28
var gender: int = 0
var origin_idx: int = 0
var traits: Array = []
var backstory: String = ""
var extra: String = ""
var hair_touched: bool = false
var scen_idx: int = 0
var birth_m: int = 0
var birth_d: int = 1

var portrait: FaceRig
var content: VBoxContainer
var cat_buttons: Array = []
var cat: int = 0
var cat_title: Label
var edit_label: Label
var change_label: Label
var error_label: Label
var _focus_row: PanelContainer
var _emotion: String = "neutro"
var _emotion_picker: OptionButton

var preview_stack: Control
var view3d: SubViewportContainer
var _vp: SubViewport
var _turn: Node3D
var _fig: Node3D
var _dirty3d: bool = true
var _rebuild_t: float = 0.0
var _drag: bool = false
var _auto_spin: bool = true
var _view_btns: Array = []


func _ready() -> void:
	birth_m = randi() % 12
	birth_d = randi_range(1, TimeManager.days_per_month)
	var sky := preload("res://ui/menu/skyline_bg.gd").new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(sky)
	var root := UI.vbox(8)
	var outer := UI.margin(root, 14)
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(outer)

	var main := UI.hbox(12)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main)

	# --- prévia ---
	var left := UI.vbox(6)
	var left_panel := UI.panel(left)
	left_panel.custom_minimum_size = Vector2(420, 0)
	main.add_child(left_panel)
	var head := UI.hbox(6)
	left.add_child(head)
	var t := UI.title("Crie seu personagem", 22)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var vgroup := ButtonGroup.new()
	for v in [["Retrato", false], ["Corpo 3D", true]]:
		var vb := _toggle(str(v[0]), vgroup)
		vb.custom_minimum_size = Vector2(86, 30)
		vb.pressed.connect(_show_view.bind(bool(v[1])))
		head.add_child(vb)
		_view_btns.append(vb)
	preview_stack = Control.new()
	preview_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_stack.custom_minimum_size = Vector2(400, 390)
	preview_stack.clip_contents = true
	left.add_child(preview_stack)
	portrait = FaceRig.new()
	portrait.scene = "casa"
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_stack.add_child(portrait)
	_build_3d()
	change_label = UI.label("Mexa em qualquer controle: a prévia muda na hora.", 13, UI.MUTED)
	change_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	change_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	change_label.clip_text = true
	left.add_child(change_label)
	var emo_grid := GridContainer.new()
	emo_grid.columns = 4
	emo_grid.add_theme_constant_override("h_separation", 4)
	emo_grid.add_theme_constant_override("v_separation", 4)
	left.add_child(emo_grid)
	for emo in PREVIEW_EMOTIONS:
		var b := UI.button(str(World.emotions.get(emo, {"pt": emo})["pt"]).capitalize(), _set_emotion.bind(emo))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		emo_grid.add_child(b)
	var emotion_picker := OptionButton.new()
	_emotion_picker = emotion_picker
	emotion_picker.add_item("Todas as expressões…")
	emotion_picker.set_item_disabled(0, true)
	var emotions: Array = FaceRig.EXPRESSIONS.keys()
	for e in emotions:
		emotion_picker.add_item(str(World.emotions.get(e, {"pt": e})["pt"]).capitalize())
	emotion_picker.item_selected.connect(func(i: int):
		if i > 0:
			_set_emotion(str(emotions[i - 1])))
	left.add_child(emotion_picker)
	left.add_child(UI.button("Testar fala", _test_talk))

	# --- categorias ---
	var rail := UI.vbox(3)
	var rail_panel := UI.panel(UI.scroll(rail))
	rail_panel.custom_minimum_size = Vector2(196, 0)
	main.add_child(rail_panel)
	var group := ButtonGroup.new()
	for i in CATEGORIES.size():
		var cb := _toggle(str(CATEGORIES[i][1]), group)
		cb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		cb.custom_minimum_size = Vector2(0, 34)
		cb.pressed.connect(_show_cat.bind(i))
		rail.add_child(cb)
		cat_buttons.append(cb)

	# --- controles ---
	var right := UI.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(right)
	var hdr := UI.hbox(10)
	right.add_child(hdr)
	cat_title = UI.title("", 22)
	hdr.add_child(cat_title)
	edit_label = UI.label("", 14, UI.ACCENT)
	edit_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	edit_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	edit_label.clip_text = true
	hdr.add_child(edit_label)
	content = UI.vbox(8)
	var content_panel := UI.panel(UI.margin(UI.scroll(content), 6))
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(content_panel)
	error_label = UI.label("", 15, UI.DANGER)
	right.add_child(error_label)
	var bottom := UI.hbox(8)
	right.add_child(bottom)
	bottom.add_child(UI.button("Voltar", func(): navigate.emit("menu", {})))
	bottom.add_child(UI.button("Aleatorizar esta parte", _randomize_cat))
	bottom.add_child(UI.button("Aleatorizar tudo", _randomize_all))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var start := UI.button("Confirmar e começar a viver", _start)
	start.custom_minimum_size = Vector2(250, 44)
	start.add_theme_stylebox_override("normal", UI._box(UI.ACCENT.darkened(0.25), 6, 10))
	start.add_theme_stylebox_override("hover", UI._box(UI.ACCENT, 6, 10))
	start.add_theme_color_override("font_color", Color.WHITE)
	start.add_theme_color_override("font_hover_color", Color.BLACK)
	bottom.add_child(start)

	_view_btns[0].button_pressed = true
	cat_buttons[0].button_pressed = true
	_show_cat(0)
	_update_preview()


func _toggle(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.add_theme_stylebox_override("pressed", UI._box(UI.ACCENT.darkened(0.35), 6, 8))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	return b


# ---------- prévia 3D ----------

func _build_3d() -> void:
	view3d = SubViewportContainer.new()
	view3d.stretch = true
	view3d.set_anchors_preset(Control.PRESET_FULL_RECT)
	view3d.visible = false
	view3d.gui_input.connect(_on_3d_input)
	preview_stack.add_child(view3d)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	view3d.add_child(_vp)
	var root := Node3D.new()
	_vp.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#2b2620")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8d8476")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#2b2620")
	env.fog_density = 0.04
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-deg_to_rad(32), deg_to_rad(-38), 0)
	key.light_energy = 1.05
	key.light_color = Color("#ffe1bd")
	key.shadow_enabled = true
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(-deg_to_rad(12), deg_to_rad(155), 0)
	rim.light_energy = 0.55
	rim.light_color = Color("#9fb8ff")
	root.add_child(rim)
	var floor_mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.6
	disc.bottom_radius = 1.6
	disc.height = 0.04
	disc.radial_segments = 48
	floor_mi.mesh = disc
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#4a4238")
	fm.roughness = 0.9
	disc.material = fm
	floor_mi.position.y = -0.02
	root.add_child(floor_mi)
	_turn = Node3D.new()
	root.add_child(_turn)
	var cam := Camera3D.new()
	cam.fov = 27
	cam.position = Vector3(0, 1.05, 4.4)
	root.add_child(cam)
	cam.look_at(Vector3(0, 0.86, 0))


func _show_view(three_d: bool) -> void:
	view3d.visible = three_d
	portrait.visible = not three_d
	if three_d:
		_dirty3d = true
		_rebuild_t = 0.0


func _on_3d_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
		_auto_spin = false
	elif e is InputEventMouseMotion and _drag:
		_turn.rotation.y += e.relative.x * 0.012


func _process(delta: float) -> void:
	if view3d == null or not view3d.visible:
		return
	if _auto_spin:
		_turn.rotation.y += delta * 0.35
	_rebuild_t -= delta
	if _dirty3d and _rebuild_t <= 0.0:
		_dirty3d = false
		_rebuild_t = 0.25
		if _fig != null:
			_fig.queue_free()
		_fig = Person.new()
		_turn.add_child(_fig)
		_fig.set_look(_look())
		_fig.set_emotion(_emotion)


func _set_emotion(emo: String) -> void:
	_emotion = emo
	if _emotion_picker != null:
		_emotion_picker.select(FaceRig.EXPRESSIONS.keys().find(emo) + 1)
	portrait.set_emotion(emo, false)
	if _fig != null:
		_fig.set_emotion(emo)
	_changed("Expressão", str(World.emotions.get(emo, {"pt": emo})["pt"]))


func _test_talk() -> void:
	portrait.talk(2.5)
	if _fig != null:
		_fig.talk_left = 2.5


# ---------- categorias ----------

func _show_cat(i: int) -> void:
	cat = i
	cat_title.text = str(CATEGORIES[i][1])
	edit_label.text = ""
	_focus_row = null
	for c in content.get_children():
		c.queue_free()
	match str(CATEGORIES[i][0]):
		"identidade": _cat_identity()
		"idade": _cat_age()
		"rosto": _cat_face()
		"olhos": _cat_eyes()
		"sobrancelhas": _cat_brows()
		"nariz_boca": _cat_nose_mouth()
		"orelhas": _cat_ears()
		"pele": _cat_skin()
		"cabelo": _cat_hair()
		"barba": _cat_beard()
		"corpo": _cat_body()
		"roupa": _cat_clothes()
		"historia": _cat_story()


func _section(title: String) -> void:
	content.add_child(UI.label(title, 17, UI.ACCENT))


func _note(text: String) -> Label:
	var l := UI.label(text, 13, UI.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(l)
	return l


func _row_box(on: bool) -> StyleBoxFlat:
	var sb := UI._box(Color(UI.ACCENT, 0.1) if on else Color(1, 1, 1, 0.025), 8, 6)
	sb.set_border_width_all(1)
	sb.border_color = Color(UI.ACCENT, 0.7) if on else Color(0, 0, 0, 0)
	return sb


# Linha de controle com destaque: ao passar o mouse ou mexer, vira o atributo "em edição".
func _row(title: String) -> HBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _row_box(false))
	var row := UI.hbox(10)
	pc.add_child(row)
	var l := UI.label(title, 15, UI.MUTED)
	l.custom_minimum_size = Vector2(180, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(l)
	content.add_child(pc)
	pc.mouse_entered.connect(_focus.bind(pc, title))
	row.set_meta("panel", pc)
	return row


func _focus(pc: PanelContainer, title: String) -> void:
	if _focus_row != null and is_instance_valid(_focus_row) and _focus_row != pc:
		_focus_row.add_theme_stylebox_override("panel", _row_box(false))
	_focus_row = pc
	pc.add_theme_stylebox_override("panel", _row_box(true))
	edit_label.text = "Editando: %s  ›  %s" % [str(CATEGORIES[cat][1]), title]


func _changed(title: String, value: String) -> void:
	change_label.text = "%s  ▸  %s" % [title, value]
	change_label.add_theme_color_override("font_color", UI.ACCENT)
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(func(): change_label.add_theme_color_override("font_color", UI.MUTED))


func _cat_options(cat_id: String) -> Array:
	for c in World.appearance["categorias"]:
		if c["id"] == cat_id:
			return c["opcoes"].map(func(o): return o[0])
	return []


func _selector(title: String, options: Array, getter: Callable, setter: Callable) -> Label:
	var row := _row(title)
	var value := UI.label("", 15)
	value.custom_minimum_size = Vector2(250, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	var count := UI.label("", 12, UI.MUTED)
	count.custom_minimum_size = Vector2(44, 0)
	var refresh := func():
		var i := int(getter.call())
		value.text = str(options[i]).capitalize()
		count.text = "%d/%d" % [i + 1, options.size()]
	var step := func(d: int):
		setter.call((int(getter.call()) + d + options.size()) % options.size())
		refresh.call()
		_focus(row.get_meta("panel"), title)
		_changed(title, value.text)
		_update_preview()
	var prev := UI.button("<", step.bind(-1))
	var next := UI.button(">", step.bind(1))
	prev.custom_minimum_size = Vector2(40, 34)
	next.custom_minimum_size = Vector2(40, 34)
	row.add_child(prev)
	row.add_child(value)
	row.add_child(next)
	row.add_child(count)
	refresh.call()
	return value


# Grade de miniaturas: cada opção capturada com o próprio retrato (mesmo rosto, só muda a opção).
func _thumbs(title: String, key: String, options: Array, columns: int = 6) -> void:
	var row := _row(title)
	row.get_child(0).custom_minimum_size = Vector2(110, 0)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	row.add_child(grid)
	var cells: Array = []
	var paint := func():
		for i in cells.size():
			var on: bool = int(spec.get(key, 0)) == i
			var sb := UI._box(Color(1, 1, 1, 0.03), 8, 3)
			sb.set_border_width_all(3 if on else 1)
			sb.border_color = UI.ACCENT if on else Color(0, 0, 0, 0.5)
			(cells[i] as PanelContainer).add_theme_stylebox_override("panel", sb)
	for i in options.size():
		var pc := PanelContainer.new()
		pc.tooltip_text = str(options[i]).capitalize()
		pc.mouse_filter = Control.MOUSE_FILTER_STOP
		var f = FaceRig.new()
		f.frozen = true
		f.custom_minimum_size = Vector2(56, 70)
		f.scene = "vazio"
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sp := spec.duplicate(true)
		sp[key] = i
		pc.add_child(f)
		f.set_look(LookBuilder.build(sp, age, GENDERS[gender]))
		f.set_emotion(_emotion, true)
		pc.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				spec[key] = i
				if key == "cabelo":
					hair_touched = true
				paint.call()
				_focus(row.get_meta("panel"), title)
				_changed(title, str(options[i]).capitalize())
				_update_preview())
		grid.add_child(pc)
		cells.append(pc)
	paint.call()


func _spec_selector(title: String, key: String, options: Array) -> void:
	_selector(title, options, func(): return clampi(int(spec.get(key, 0)), 0, options.size() - 1), func(v):
		spec[key] = v
		if key == "cabelo":
			hair_touched = true)


func _slider(title: String, key: String, low: String = "", high: String = "") -> void:
	var row := _row(title)
	if low != "":
		var ll := UI.label(low, 12, UI.MUTED)
		ll.custom_minimum_size = Vector2(56, 0)
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(ll)
	var s := HSlider.new()
	s.min_value = -1.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(spec["ajustes"].get(key, 0.0))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(200, 30)
	s.value_changed.connect(func(v):
		spec["ajustes"][key] = v
		_focus(row.get_meta("panel"), title)
		_changed(title, "%+d%%" % int(round(v * 100.0)))
		_update_preview())
	row.add_child(s)
	if high != "":
		var hl := UI.label(high, 12, UI.MUTED)
		hl.custom_minimum_size = Vector2(56, 0)
		row.add_child(hl)
	var reset := UI.button("0", func(): s.value = 0.0)
	reset.tooltip_text = "Voltar ao padrão"
	row.add_child(reset)


func _swatches(title: String, colors: Array, index_key: String, custom_key: String, on_pick: Callable = Callable()) -> void:
	var row := _row(title)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	row.add_child(flow)
	var buttons: Array = []
	var paint := func():
		for i in buttons.size():
			var selected: bool = not spec.has(custom_key) and index_key != "" and int(spec.get(index_key, -1)) == i
			if (index_key == "" or on_pick.is_valid()) and spec.has(custom_key):
				selected = Color(spec[custom_key]).is_equal_approx(Color(colors[i]))
			var sb := UI._box(Color(colors[i]), 14, 0)
			sb.set_border_width_all(3 if selected else 1)
			sb.border_color = UI.ACCENT if selected else Color(0, 0, 0, 0.6)
			for st in ["normal", "hover", "pressed"]:
				buttons[i].add_theme_stylebox_override(st, sb)
	for i in colors.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(28, 28)
		b.pressed.connect(func():
			if on_pick.is_valid():
				on_pick.call(i)
			elif index_key != "":
				spec[index_key] = i
				spec.erase(custom_key)
			else:
				spec[custom_key] = colors[i]
			paint.call()
			_focus(row.get_meta("panel"), title)
			_changed(title, "tom %d de %d" % [i + 1, colors.size()])
			_update_preview())
		flow.add_child(b)
		buttons.append(b)
	var picker := ColorPickerButton.new()
	picker.text = "+"
	picker.tooltip_text = "Cor personalizada"
	picker.custom_minimum_size = Vector2(36, 28)
	picker.color = Color(spec.get(custom_key, colors[0]))
	picker.color_changed.connect(func(c: Color):
		spec[custom_key] = "#" + c.to_html(false)
		paint.call()
		_focus(row.get_meta("panel"), title)
		_changed(title, "cor personalizada")
		_update_preview())
	flow.add_child(picker)
	paint.call()


func _chips(options: Array, is_on: Callable, toggle: Callable, columns: int = 3) -> void:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	content.add_child(grid)
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.toggle_mode = true
		b.button_pressed = is_on.call(i)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_stylebox_override("pressed", UI._box(UI.ACCENT.darkened(0.35), 5, 8))
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.toggled.connect(func(on: bool):
			if not toggle.call(i, on):
				b.set_pressed_no_signal(not on)
			_changed(str(options[i]).capitalize(), "sim" if b.button_pressed else "não")
			_update_preview())
		grid.add_child(b)


# Marcas e acessórios (índices de data/appearance.json "marcas") como botões liga/desliga.
func _mark_chips(indices: Array, columns: int = 3) -> void:
	var names: Array = indices.map(func(i): return str(World.appearance["marcas"][i][0]).capitalize())
	var toggle := func(k: int, on: bool) -> bool:
		var m := int(indices[k])
		if on and not m in spec["marcas"]:
			spec["marcas"].append(m)
		elif not on:
			spec["marcas"].erase(m)
		return true
	_chips(names, func(k): return int(indices[k]) in spec["marcas"], toggle, columns)


# ---------- conteúdo de cada categoria ----------

func _cat_identity() -> void:
	_section("Quem é você")
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Seu nome"
	name_edit.text = player_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(t): player_name = t)
	_row("Nome").add_child(name_edit)
	_selector("Gênero", GENDERS, func(): return gender, func(v):
		gender = v
		if not hair_touched:
			spec["cabelo"] = 4 if v == 1 else 0
		if v == 1:
			spec["barba"] = 0)
	var origin_desc := UI.label("", 13, UI.MUTED)
	origin_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var names: Array = World.origins.map(func(o): return o["nome"])
	_selector("Como chegou na cidade", names, func(): return origin_idx, func(v):
		origin_idx = v
		_fill_origin(origin_desc))
	content.add_child(origin_desc)
	_fill_origin(origin_desc)
	var scen_ids: Array = World.cenarios.keys()
	var scen_desc := UI.label(str(World.cenarios[scen_ids[scen_idx]]["resumo"]), 13, UI.MUTED)
	scen_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selector("Cenário do mundo", scen_ids.map(func(k): return World.cenarios[k]["rotulo"]), func(): return scen_idx, func(v):
		scen_idx = v
		scen_desc.text = str(World.cenarios[scen_ids[v]]["resumo"]))
	content.add_child(scen_desc)
	_section("Traços de personalidade (até %d)" % MAX_TRAITS)
	var ids: Array = World.traits.map(func(t): return t["id"])
	_chips(World.traits.map(func(t): return t["nome"]), func(i): return ids[i] in traits, func(i, on):
		if on and traits.size() >= MAX_TRAITS:
			return false
		if on:
			traits.append(ids[i])
		else:
			traits.erase(ids[i])
		return true)


func _fill_origin(label: Label) -> void:
	var o: Dictionary = World.origins[origin_idx]
	var txt := "%s\nDinheiro inicial: R$ %d%s" % [o["descricao"], int(o["dinheiro"]), "" if o["casa"] != "" else " | Sem casa"]
	if age < 18 and str(o["id"]) == "ex_presidiario":
		txt += "\n(Essa origem não serve para menor de idade: escolha outra.)"
	elif age < 18 and str(o.get("carro", "")) != "":
		txt += "\n(Menor de idade: o carro fica na garagem até os 18.)"
	label.text = txt


func _stage_index() -> int:
	for i in STAGES.size():
		if age <= int(STAGES[i][3]):
			return i
	return STAGES.size() - 1


func _cat_age() -> void:
	_section("Faixa de idade")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	content.add_child(grid)
	var g := ButtonGroup.new()
	var info := UI.label("", 13, UI.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i in STAGES.size():
		var st: Array = STAGES[i]
		var b := _toggle("%s\n%d–%d anos" % [st[1], st[2], st[3]], g)
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = i == _stage_index()
		b.pressed.connect(func():
			age = int(st[4])
			_changed("Faixa de idade", "%s (%d anos)" % [st[1], age])
			_update_preview()
			_show_cat.call_deferred(cat))
		grid.add_child(b)
	var st2: Array = STAGES[_stage_index()]
	var age_row := _row("Idade exata")
	var age_label := UI.label("%d anos" % age, 15)
	age_label.custom_minimum_size = Vector2(70, 0)
	var s := HSlider.new()
	s.min_value = int(st2[2])
	s.max_value = int(st2[3])
	s.value = age
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v):
		age = int(v)
		age_label.text = "%d anos" % age
		_focus(age_row.get_meta("panel"), "Idade exata")
		_changed("Idade", "%d anos" % age)
		_update_preview())
	age_row.add_child(s)
	age_row.add_child(age_label)
	info.text = STAGE_INFO[str(st2[0])]
	content.add_child(info)
	_section("Aniversário")
	_selector("Mês", TimeManager.MONTHS, func(): return birth_m, func(v): birth_m = v)
	var days: Array = range(1, TimeManager.days_per_month + 1).map(func(d): return "dia %d" % d)
	_selector("Dia", days, func(): return clampi(birth_d - 1, 0, days.size() - 1), func(v): birth_d = v + 1)
	_note("O calendário do jogo tem meses de %d dias (ano de %d dias de jogo). No dia do aniversário você ganha um ano%s: o rosto e o corpo vão mudando, e nos marcos (13, 18 e 60 anos) muda a faixa de idade." % [TimeManager.days_per_month, TimeManager.days_per_month * 12, "" if TimeManager.aging else " (o envelhecimento está desligado em Configurações)"])


func _cat_face() -> void:
	_section("Formato")
	_spec_selector("Formato base", "rosto", _cat_options("rosto"))
	_thumbs("Formatos", "rosto", _cat_options("rosto"), 5)
	_slider("Largura do rosto", "face_w", "fino", "largo")
	_slider("Comprimento", "face_len", "curto", "longo")
	_slider("Maçãs do rosto", "cheek", "suaves", "marcadas")
	_slider("Mandíbula", "jaw", "estreita", "forte")
	_slider("Queixo", "chin_w", "pontudo", "largo")
	_slider("Altura do queixo", "chin_length", "curto", "longo")
	_slider("Perfil da testa", "forehead", "recuada", "saliente")
	_slider("Assimetria natural", "asymmetry", "esquerda", "direita")
	_section("Marcas do tempo")
	_slider("Rugas e vincos", "rugas", "lisa", "marcada")
	_note("As rugas também chegam sozinhas com a idade; este controle só adianta ou atrasa.")


func _cat_eyes() -> void:
	_section("Cor")
	_swatches("Cor dos olhos", LookBuilder.EYE_COLORS.slice(0, 6), "olhos", "olhos_cor")
	var hetero := func(_i: int, on: bool) -> bool:
		spec["olhos"] = 6 if on else 0
		spec.erase("olhos_cor")
		return true
	_chips(["Olhos de cores diferentes"], func(_i): return int(spec.get("olhos", 0)) == 6, hetero, 1)
	_section("Formato")
	var names: Array = EYE_SHAPES.map(func(e): return e[0])
	_selector("Formato dos olhos", names, func(): return int(spec.get("olhos_forma", 0)), func(v):
		spec["olhos_forma"] = v
		spec["ajustes"]["eye_h"] = float(EYE_SHAPES[v][1])
		spec["ajustes"]["eye_tilt"] = float(EYE_SHAPES[v][2])
		_show_cat.call_deferred(cat))
	_slider("Distância entre os olhos", "eye_spacing", "próximos", "afastados")
	_slider("Tamanho", "eye_size", "pequenos", "grandes")
	_slider("Abertura", "eye_h", "fechados", "abertos")
	_slider("Inclinação", "eye_tilt", "caídos", "puxados")
	_section("Óculos")
	_mark_chips([7, 8], 2)


func _cat_brows() -> void:
	_section("Sobrancelhas")
	var shapes := _cat_options("sobrancelha")
	_selector("Formato", shapes, func(): return int(spec["sobrancelha"]) if int(spec["sobrancelha"]) >= 0 else (2 if gender == 1 else 0), func(v): spec["sobrancelha"] = v)
	_slider("Espessura", "brow_w", "finas", "grossas")
	_slider("Altura", "brow_y", "baixas", "altas")
	_swatches("Cor", LookBuilder.HAIR_COLORS, "", "sobrancelha_cor")
	content.add_child(UI.button("Sobrancelha da cor do cabelo", func():
		spec.erase("sobrancelha_cor")
		_update_preview()
		_show_cat(cat)))
	_mark_chips([5], 2)


func _cat_nose_mouth() -> void:
	_section("Nariz")
	_slider("Largura do nariz", "nose_w", "fino", "largo")
	_slider("Comprimento do nariz", "nose_len", "curto", "comprido")
	_slider("Ponte do nariz", "nose_bridge", "suave", "marcada")
	_mark_chips([16, 3], 2)
	_section("Boca")
	_slider("Volume dos lábios", "lips", "finos", "carnudos")
	_slider("Largura da boca", "mouth_w", "pequena", "larga")
	_mark_chips([10, 13], 2)


func _cat_ears() -> void:
	_section("Orelhas")
	_slider("Tamanho", "ear_size", "pequenas", "grandes")
	_slider("Abertura", "ear_out", "coladas", "de abano")
	_mark_chips([4, 14], 2)


func _skin_pick(i: int) -> void:
	spec["pele_cor"] = LookBuilder.SKIN_TONES[i]
	spec["pele"] = clampi(i * 6 / LookBuilder.SKIN_TONES.size(), 0, 5)


func _cat_skin() -> void:
	_section("Tom de pele")
	_swatches("Tom de pele", LookBuilder.SKIN_TONES, "", "pele_cor", _skin_pick)
	_note("A transição de luz e sombra do rosto acompanha o tom escolhido.")
	_spec_selector("Traços / ascendência", "tracos", _cat_options("tracos"))
	_section("Marcas na pele")
	_mark_chips([6, 15, 0, 17, 9, 2], 3)


func _cat_hair() -> void:
	_section("Cabelo")
	_spec_selector("Estilo", "cabelo", _cat_options("cabelo"))
	_thumbs("Todos os estilos", "cabelo", _cat_options("cabelo"))
	_swatches("Cor do cabelo", LookBuilder.HAIR_COLORS, "cor_cabelo", "cabelo_cor")
	_note("Com a idade o cabelo vai ficando grisalho aos poucos, mesmo pintado.")
	_mark_chips([11], 2)


func _cat_beard() -> void:
	_section("Barba e bigode")
	if age < 13:
		_note("Criança não tem barba: os pelos aparecem na adolescência.")
	_spec_selector("Estilo", "barba", _cat_options("barba"))
	_thumbs("Todos os estilos", "barba", _cat_options("barba"), 5)
	_swatches("Cor da barba", LookBuilder.HAIR_COLORS, "", "barba_cor")
	content.add_child(UI.button("Barba da cor do cabelo", func():
		spec.erase("barba_cor")
		_update_preview()
		_show_cat(cat)))


func _cat_body() -> void:
	_section("Corpo")
	_spec_selector("Tipo físico", "corpo", _cat_options("corpo"))
	_spec_selector("Altura", "altura", _cat_options("altura"))
	_slider("Ajuste de altura", "stature", "menor", "maior")
	_slider("Tórax", "chest", "estreito", "largo")
	_slider("Cintura", "waist", "fina", "larga")
	_slider("Quadril", "hips", "estreito", "largo")
	_slider("Braços e pernas", "limbs", "delgados", "volumosos")
	_slider("Abdome", "abdomen", "plano", "volumoso")
	_note("A altura e o tipo físico aparecem no corpo 3D (botão Corpo 3D, em cima da prévia). Criança e adolescente usam proporções próprias.")
	_mark_chips([1], 2)


func _cat_clothes() -> void:
	_section("Roupa")
	var styles: Array = _cat_options("roupa")
	var mat := UI.label("", 13, UI.MUTED)
	_selector("Peça principal", styles, func(): return clampi(int(spec.get("roupa", 0)), 0, styles.size() - 1), func(v):
		spec["roupa"] = v
		mat.text = "Material: " + str(CLOTHES_MATERIAL.get(LookBuilder.CLOTHES[v], "")))
	mat.text = "Material: " + str(CLOTHES_MATERIAL.get(LookBuilder.CLOTHES[clampi(int(spec.get("roupa", 0)), 0, LookBuilder.CLOTHES.size() - 1)], ""))
	content.add_child(mat)
	_thumbs("Todas as peças", "roupa", styles)
	_swatches("Cor principal", CLOTHES_SWATCHES, "", "cor_roupa")
	_swatches("Cor secundária", CLOTHES_SWATCHES, "", "cor_roupa2")
	_section("Acessórios")
	_mark_chips([12, 13, 11], 3)


func _cat_story() -> void:
	_section("Sua história (só você e o narrador sabem)")
	var story := TextEdit.new()
	story.placeholder_text = "Quem você era antes? Do que está fugindo? O que quer?"
	story.text = backstory
	story.custom_minimum_size = Vector2(0, 120)
	story.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	story.text_changed.connect(func(): backstory = story.text)
	content.add_child(story)
	_section("Detalhes que os outros notam")
	var ex := TextEdit.new()
	ex.placeholder_text = "Ex: parece mais velho do que é, sorriso torto, cheiro de cigarro"
	ex.text = extra
	ex.custom_minimum_size = Vector2(0, 90)
	ex.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	ex.text_changed.connect(func(): extra = ex.text)
	content.add_child(ex)


# ---------- lógica ----------

func _look() -> Dictionary:
	return LookBuilder.build(spec, age, GENDERS[gender])


func _update_preview() -> void:
	if portrait:
		portrait.set_look(_look())
	_dirty3d = true


func _rand_adj(keys: Array, spread: float = 0.6) -> void:
	for k in keys:
		spec["ajustes"][k] = snappedf(randf_range(-spread, spread), 0.05)


func _rand_marks(pool: Array, chance: float) -> void:
	for m in pool:
		spec["marcas"].erase(m)
		if randf() < chance:
			spec["marcas"].append(m)


func _randomize_part(id: String) -> void:
	match id:
		"rosto":
			spec["rosto"] = randi() % 5
			_rand_adj(["face_w", "face_len", "cheek", "jaw", "chin_w", "forehead", "chin_length", "asymmetry"])
			spec["ajustes"]["rugas"] = snappedf(randf_range(-0.3, 0.5), 0.05)
		"olhos":
			spec["olhos"] = [0, 0, 1, 1, 2, 3, 4, 5][randi() % 8]
			spec.erase("olhos_cor")
			_rand_adj(["eye_size", "eye_h", "eye_tilt"], 0.5)
			_rand_marks([7, 8], 0.1)
		"sobrancelhas":
			spec["sobrancelha"] = randi() % 7
			spec.erase("sobrancelha_cor")
			_rand_adj(["brow_w", "brow_y"], 0.5)
		"nariz_boca":
			_rand_adj(["nose_w", "nose_len", "lips", "mouth_w", "nose_bridge"])
			_rand_marks([16, 3, 10], 0.06)
		"orelhas":
			_rand_adj(["ear_size", "ear_out"], 0.5)
			_rand_marks([4, 14], 0.12)
		"pele":
			_skin_pick(randi() % LookBuilder.SKIN_TONES.size())
			spec["tracos"] = randi() % 7
			_rand_marks([6, 15], 0.18)
			_rand_marks([0, 17, 9, 2], 0.05)
		"cabelo":
			spec["cabelo"] = randi() % 14
			# cores naturais quase sempre; tinta (azul, rosa, verde, platinado) é rara
			spec["cor_cabelo"] = [0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 5, 6][randi() % 13] if randf() > 0.08 else [7, 8, 9, 10][randi() % 4]
			spec.erase("cabelo_cor")
			hair_touched = true
		"barba":
			spec["barba"] = 0 if gender == 1 else randi() % 9
			spec.erase("barba_cor")
		"corpo":
			spec["corpo"] = randi() % 7
			spec["altura"] = randi() % 4
			_rand_adj(["stature", "chest", "waist", "hips", "limbs", "abdomen"], 0.55)
		"roupa":
			spec["roupa"] = randi() % LookBuilder.CLOTHES.size()
			spec["cor_roupa"] = CLOTHES_SWATCHES.pick_random()
			spec["cor_roupa2"] = CLOTHES_SWATCHES.pick_random()
			_rand_marks([12, 13, 11], 0.1)


func _randomize_cat() -> void:
	var id := str(CATEGORIES[cat][0])
	if id in ["identidade", "idade", "historia"]:
		_randomize_all()
		return
	_randomize_part(id)
	_changed(str(CATEGORIES[cat][1]), "aleatório")
	_update_preview()
	_show_cat(cat)


func _randomize_all() -> void:
	for c in CATEGORIES:
		_randomize_part(str(c[0]))
	_changed("Aparência", "tudo aleatório")
	_update_preview()
	_show_cat(cat)


func describe() -> String:
	var parts: Array = []
	for c in World.appearance["categorias"]:
		var id: String = c["id"]
		if id == "barba" and (int(spec.get("barba", 0)) == 0 or age < 15):
			continue
		if id == "sobrancelha" and int(spec.get("sobrancelha", -1)) < 0:
			continue
		var idx := clampi(int(spec.get(id, 0)), 0, c["opcoes"].size() - 1)
		var text: String = c["opcoes"][idx][0]
		if id == "cor_cabelo":
			if int(spec.get("cabelo", 0)) == 1:
				continue
			text = "cabelo " + ("de cor diferente" if spec.has("cabelo_cor") else text)
		if id == "olhos" and spec.has("olhos_cor"):
			text = "olhos de cor marcante"
		parts.append(text)
	for i in spec["marcas"]:
		parts.append(World.appearance["marcas"][int(i)][0])
	var desc := ", ".join(parts)
	var ex := extra.strip_edges()
	return desc + ("; " + ex if ex != "" else "")


var _starting := false

func _start() -> void:
	if _starting:
		return
	var pname := player_name.strip_edges()
	if pname == "":
		error_label.text = "Seu personagem precisa de um nome (categoria Identidade)."
		cat_buttons[0].button_pressed = true
		_show_cat(0)
		return
	var origin: Dictionary = World.origins[origin_idx]
	if age < 18 and str(origin["id"]) == "ex_presidiario":
		error_label.text = "\"Saiu da prisão\" não serve para menor de idade. Escolha outra origem (Identidade)."
		cat_buttons[0].button_pressed = true
		_show_cat(0)
		return
	var inventory := {}
	for k in origin["itens"]:
		if age < 18 and GameState.MINOR_ITEMS.has(k):
			continue
		inventory[k] = int(origin["itens"][k])
	var player := {
		"name": pname,
		"age": age,
		"nascimento": {"m": birth_m, "d": AgingSystem.canonical_day(birth_d, TimeManager.days_per_month)},
		"gender": GENDERS[gender],
		"appearance": describe(),
		"look": spec.duplicate(true),
		"appearance_extra": origin.get("aparencia_extra", ""),
		"backstory": backstory.strip_edges(),
		"traits": traits.duplicate(),
		"origin": origin["id"],
		"cenario": World.cenarios.keys()[scen_idx],
		"money": int(origin["dinheiro"]),
		"location": origin["local"],
		"home": origin["casa"],
		"car": origin.get("carro", "") if age >= 18 else "",
		"inventory": inventory,
		"alive": true,
	}
	_starting = true
	error_label.text = "Preparando sua nova vida…"
	await get_tree().process_frame
	await get_tree().process_frame
	GameState.new_game(player)
	TimeManager.total_minutes = int(origin["hora"]) * 60
	TimeManager.days_per_month = Settings.days_per_month
	TimeManager.aging = Settings.aging
	TimeManager.new_calendar()
	NeedsSystem.reset(origin["necessidades"])
	NPCManager.reset_state(origin)
	Population.populate(int(World.mod("extra_npcs", 2.0)) + 2)
	AgingSystem.reset()
	navigate.emit("game", {"new_origin": origin})
