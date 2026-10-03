extends Control

signal navigate(screen: String, args: Dictionary)

const UI = preload("res://ui/ui_theme.gd")
const FaceRig = preload("res://ui/face/face_rig.gd")
const LookBuilder = preload("res://ui/face/look_builder.gd")
const MAX_TRAITS := 3
const GENDERS := ["homem", "mulher", "pessoa não-binária"]
const TABS := ["Identidade", "Rosto", "Olhos e sobrancelhas", "Cabelo e barba", "Corpo e roupa", "Detalhes"]
const PREVIEW_EMOTIONS := ["neutro", "feliz", "rindo", "triste", "chorando", "furioso", "assustado", "desconfiado"]
const CLOTHES_SWATCHES := ["#2a2a2e", "#4a5260", "#3d5a80", "#1d4f91", "#2f5a3a", "#6b5a3a", "#7a2040", "#8a2b2b", "#b5838d", "#c97a5a", "#d8d2c4", "#f0f0f0"]

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

var portrait: FaceRig
var content: VBoxContainer
var tab_buttons: Array = []
var error_label: Label


func _ready() -> void:
	var root := UI.vbox(10)
	var outer := UI.margin(root, 18)
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(outer)

	var main := UI.hbox(16)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main)

	# Retrato
	var left := UI.vbox(8)
	var left_panel := UI.panel(left)
	left_panel.custom_minimum_size = Vector2(430, 0)
	main.add_child(left_panel)
	left.add_child(UI.title("Crie seu personagem", 26))
	portrait = FaceRig.new()
	portrait.scene = "casa"
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.custom_minimum_size = Vector2(400, 420)
	left.add_child(portrait)
	var emo_grid := GridContainer.new()
	emo_grid.columns = 4
	emo_grid.add_theme_constant_override("h_separation", 4)
	emo_grid.add_theme_constant_override("v_separation", 4)
	left.add_child(emo_grid)
	for emo in PREVIEW_EMOTIONS:
		var b := UI.button(World.emotions[emo]["pt"].capitalize(), portrait.set_emotion.bind(emo, false))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		emo_grid.add_child(b)
	left.add_child(UI.button("Testar fala", func(): portrait.talk(2.5)))

	# Abas
	var right := UI.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(right)
	var tabs := UI.hbox(6)
	right.add_child(tabs)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var tb := Button.new()
		tb.text = TABS[i]
		tb.toggle_mode = true
		tb.button_group = group
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.add_theme_stylebox_override("pressed", UI._box(UI.ACCENT.darkened(0.35), 5, 8))
		tb.add_theme_color_override("font_pressed_color", Color.WHITE)
		tb.pressed.connect(_show_tab.bind(i))
		tabs.add_child(tb)
		tab_buttons.append(tb)
	content = UI.vbox(12)
	var content_panel := UI.panel(UI.margin(UI.scroll(content), 6))
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(content_panel)

	error_label = UI.label("", 15, UI.DANGER)
	right.add_child(error_label)
	var bottom := UI.hbox(10)
	right.add_child(bottom)
	bottom.add_child(UI.button("Voltar", func(): navigate.emit("menu", {})))
	bottom.add_child(UI.button("Aparência aleatória", _randomize_look))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var start := UI.button("Começar a viver", _start)
	start.custom_minimum_size = Vector2(240, 44)
	start.add_theme_stylebox_override("normal", UI._box(UI.ACCENT.darkened(0.25), 6, 10))
	start.add_theme_stylebox_override("hover", UI._box(UI.ACCENT, 6, 10))
	start.add_theme_color_override("font_color", Color.WHITE)
	start.add_theme_color_override("font_hover_color", Color.BLACK)
	bottom.add_child(start)

	tab_buttons[0].button_pressed = true
	_show_tab(0)
	_update_preview()


# ---------- montagem das abas ----------

func _show_tab(i: int) -> void:
	for c in content.get_children():
		c.queue_free()
	match i:
		0: _tab_identity()
		1: _tab_face()
		2: _tab_eyes()
		3: _tab_hair()
		4: _tab_body()
		5: _tab_details()


func _section(title: String) -> void:
	var l := UI.label(title, 17, UI.ACCENT)
	content.add_child(l)


func _row(title: String) -> HBoxContainer:
	var row := UI.hbox(10)
	var l := UI.label(title, 15, UI.MUTED)
	l.custom_minimum_size = Vector2(190, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(l)
	content.add_child(row)
	return row


func _cat_options(cat_id: String) -> Array:
	for cat in World.appearance["categorias"]:
		if cat["id"] == cat_id:
			return cat["opcoes"].map(func(o): return o[0])
	return []


func _selector(title: String, options: Array, getter: Callable, setter: Callable) -> void:
	var row := _row(title)
	var value := UI.label("", 15)
	value.custom_minimum_size = Vector2(260, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	var refresh := func(): value.text = str(options[getter.call()]).capitalize()
	var step := func(d: int):
		setter.call((int(getter.call()) + d + options.size()) % options.size())
		refresh.call()
		_update_preview()
	var prev := UI.button("<", step.bind(-1))
	var next := UI.button(">", step.bind(1))
	prev.custom_minimum_size = Vector2(40, 34)
	next.custom_minimum_size = Vector2(40, 34)
	row.add_child(prev)
	row.add_child(value)
	row.add_child(next)
	refresh.call()


func _spec_selector(title: String, key: String, options: Array) -> void:
	_selector(title, options, func(): return maxi(int(spec.get(key, 0)), 0), func(v):
		spec[key] = v
		if key == "cabelo":
			hair_touched = true)


func _slider(title: String, key: String) -> void:
	var row := _row(title)
	var s := HSlider.new()
	s.min_value = -1.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(spec["ajustes"].get(key, 0.0))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(260, 30)
	s.value_changed.connect(func(v):
		spec["ajustes"][key] = v
		_update_preview())
	row.add_child(s)
	var reset := UI.button("0", func(): s.value = 0.0)
	reset.tooltip_text = "Voltar ao padrão"
	row.add_child(reset)


func _swatches(title: String, colors: Array, index_key: String, custom_key: String) -> void:
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
			if index_key == "" and spec.has(custom_key):
				selected = Color(spec[custom_key]).is_equal_approx(Color(colors[i]))
			var sb := UI._box(Color(colors[i]), 14, 0)
			sb.set_border_width_all(3 if selected else 1)
			sb.border_color = UI.ACCENT if selected else Color(0, 0, 0, 0.6)
			for st in ["normal", "hover", "pressed"]:
				buttons[i].add_theme_stylebox_override(st, sb)
	for i in colors.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 30)
		b.pressed.connect(func():
			if index_key != "":
				spec[index_key] = i
				spec.erase(custom_key)
			else:
				spec[custom_key] = colors[i]
			paint.call()
			_update_preview())
		flow.add_child(b)
		buttons.append(b)
	var picker := ColorPickerButton.new()
	picker.text = "+"
	picker.tooltip_text = "Cor personalizada"
	picker.custom_minimum_size = Vector2(36, 30)
	picker.color = Color(spec.get(custom_key, colors[0]))
	picker.color_changed.connect(func(c: Color):
		spec[custom_key] = "#" + c.to_html(false)
		paint.call()
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
			_update_preview())
		grid.add_child(b)


func _tab_identity() -> void:
	_section("Quem é você")
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Seu nome"
	name_edit.text = player_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(t): player_name = t)
	_row("Nome").add_child(name_edit)
	var age_row := _row("Idade")
	var age_label := UI.label(str(age), 15)
	age_label.custom_minimum_size = Vector2(40, 0)
	var age_slider := HSlider.new()
	age_slider.min_value = 18
	age_slider.max_value = 85
	age_slider.value = age
	age_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	age_slider.value_changed.connect(func(v):
		age = int(v)
		age_label.text = str(age)
		_update_preview())
	age_row.add_child(age_slider)
	age_row.add_child(age_label)
	_selector("Gênero", GENDERS, func(): return gender, func(v):
		gender = v
		if not hair_touched:
			spec["cabelo"] = 4 if v == 1 else 0
		if v == 1:
			spec["barba"] = 0)
	var origin_desc := UI.label("", 14, UI.MUTED)
	var names: Array = World.origins.map(func(o): return o["nome"])
	_selector("Como chegou na cidade", names, func(): return origin_idx, func(v):
		origin_idx = v
		_fill_origin(origin_desc))
	content.add_child(origin_desc)
	_fill_origin(origin_desc)

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

	_section("Sua história (só você e o narrador sabem)")
	var story := TextEdit.new()
	story.placeholder_text = "Quem você era antes? Do que está fugindo? O que quer?"
	story.text = backstory
	story.custom_minimum_size = Vector2(0, 110)
	story.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	story.text_changed.connect(func(): backstory = story.text)
	content.add_child(story)


func _fill_origin(label: Label) -> void:
	var o: Dictionary = World.origins[origin_idx]
	label.text = "%s\nDinheiro inicial: R$ %d%s" % [o["descricao"], int(o["dinheiro"]), "" if o["casa"] != "" else " | Sem casa"]


func _tab_face() -> void:
	_section("Formato")
	_spec_selector("Formato base", "rosto", _cat_options("rosto"))
	_slider("Largura do rosto", "face_w")
	_slider("Comprimento do rosto", "face_len")
	_slider("Maçãs do rosto", "cheek")
	_slider("Mandíbula", "jaw")
	_slider("Queixo", "chin_w")
	_section("Pele")
	_swatches("Tom de pele", LookBuilder.SKIN, "pele", "pele_cor")
	_spec_selector("Traços / ascendência", "tracos", _cat_options("tracos"))
	_section("Nariz e boca")
	_slider("Largura do nariz", "nose_w")
	_slider("Comprimento do nariz", "nose_len")
	_slider("Volume dos lábios", "lips")


func _tab_eyes() -> void:
	_section("Olhos")
	_swatches("Cor dos olhos", LookBuilder.EYE_COLORS.slice(0, 6), "olhos", "olhos_cor")
	_slider("Tamanho dos olhos", "eye_size")
	_slider("Inclinação", "eye_tilt")
	_section("Sobrancelhas")
	var shapes := _cat_options("sobrancelha")
	_selector("Formato", shapes, func(): return int(spec["sobrancelha"]) if int(spec["sobrancelha"]) >= 0 else (2 if gender == 1 else 0), func(v): spec["sobrancelha"] = v)
	_slider("Espessura", "brow_w")
	_slider("Altura", "brow_y")
	_swatches("Cor", LookBuilder.HAIR_COLORS, "", "sobrancelha_cor")
	content.add_child(UI.button("Sobrancelha da cor do cabelo", func():
		spec.erase("sobrancelha_cor")
		_update_preview()
		_show_tab(2)))


func _tab_hair() -> void:
	_section("Cabelo")
	_spec_selector("Estilo", "cabelo", _cat_options("cabelo"))
	_swatches("Cor do cabelo", LookBuilder.HAIR_COLORS, "cor_cabelo", "cabelo_cor")
	_section("Barba")
	_spec_selector("Barba / bigode", "barba", _cat_options("barba"))


func _tab_body() -> void:
	_section("Corpo")
	_spec_selector("Tipo de corpo", "corpo", _cat_options("corpo"))
	_spec_selector("Altura", "altura", _cat_options("altura"))
	_section("Roupa")
	_spec_selector("Roupa", "roupa", _cat_options("roupa"))
	_swatches("Cor da roupa", CLOTHES_SWATCHES, "", "cor_roupa")


func _tab_details() -> void:
	_section("Marcas e acessórios")
	var marks: Array = World.appearance["marcas"].map(func(m): return m[0])
	_chips(marks, func(i): return i in spec["marcas"], func(i, on):
		if on:
			spec["marcas"].append(i)
		else:
			spec["marcas"].erase(i)
		return true)
	_section("Detalhes que os outros notam")
	var ex := TextEdit.new()
	ex.placeholder_text = "Ex: parece mais velho do que é, sorriso torto, cheiro de cigarro"
	ex.text = extra
	ex.custom_minimum_size = Vector2(0, 90)
	ex.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	ex.text_changed.connect(func(): extra = ex.text)
	content.add_child(ex)


# ---------- lógica ----------

func _update_preview() -> void:
	if portrait:
		portrait.set_look(LookBuilder.build(spec, age, GENDERS[gender]))


func _randomize_look() -> void:
	for cat in World.appearance["categorias"]:
		spec[cat["id"]] = randi() % cat["opcoes"].size()
	for k in ["pele_cor", "cabelo_cor", "olhos_cor", "sobrancelha_cor"]:
		spec.erase(k)
	spec["cor_roupa"] = CLOTHES_SWATCHES.pick_random()
	var adj := {}
	for k in LookBuilder.RANGES:
		adj[k] = snappedf(randf_range(-0.6, 0.6), 0.05)
	spec["ajustes"] = adj
	var marks: Array = []
	for i in World.appearance["marcas"].size():
		if randf() < 0.1:
			marks.append(i)
	spec["marcas"] = marks
	_update_preview()
	for i in tab_buttons.size():
		if tab_buttons[i].button_pressed:
			_show_tab(i)


func describe() -> String:
	var parts: Array = []
	for cat in World.appearance["categorias"]:
		var id: String = cat["id"]
		if id == "barba" and int(spec.get("barba", 0)) == 0:
			continue
		if id == "sobrancelha" and int(spec.get("sobrancelha", -1)) < 0:
			continue
		var idx := clampi(int(spec.get(id, 0)), 0, cat["opcoes"].size() - 1)
		var text: String = cat["opcoes"][idx][0]
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


func _start() -> void:
	var pname := player_name.strip_edges()
	if pname == "":
		error_label.text = "Seu personagem precisa de um nome (aba Identidade)."
		tab_buttons[0].button_pressed = true
		_show_tab(0)
		return
	var origin: Dictionary = World.origins[origin_idx]
	var inventory := {}
	for k in origin["itens"]:
		inventory[k] = int(origin["itens"][k])
	var player := {
		"name": pname,
		"age": age,
		"gender": GENDERS[gender],
		"appearance": describe(),
		"look": spec.duplicate(true),
		"appearance_extra": origin.get("aparencia_extra", ""),
		"backstory": backstory.strip_edges(),
		"traits": traits.duplicate(),
		"origin": origin["id"],
		"money": int(origin["dinheiro"]),
		"location": origin["local"],
		"home": origin["casa"],
		"inventory": inventory,
		"alive": true,
	}
	GameState.new_game(player)
	TimeManager.total_minutes = int(origin["hora"]) * 60
	NeedsSystem.reset(origin["necessidades"])
	NPCManager.reset_state(origin)
	navigate.emit("game", {"new_origin": origin})
