extends Control

signal navigate(screen: String, args: Dictionary)

const UI = preload("res://ui/ui_theme.gd")
const FaceRig = preload("res://ui/face/face_rig.gd")
const LookBuilder = preload("res://ui/face/look_builder.gd")
const MAX_TRAITS := 3
const GENDERS := ["homem", "mulher", "pessoa não-binária"]

var args: Dictionary = {}
var name_edit: LineEdit
var age_spin: SpinBox
var gender_opt: OptionButton
var backstory_edit: TextEdit
var trait_boxes: Dictionary = {}
var origin_opt: OptionButton
var origin_desc: Label
var look_opts: Dictionary = {}
var mark_boxes: Array = []
var clothes_color: ColorPickerButton
var extra_edit: TextEdit
var portrait: FaceRig
var expr_label: Label
var expr_timer: Timer
var expr_index: int = -1
var error_label: Label


func _ready() -> void:
	var root := UI.vbox(8)
	var outer := UI.margin(root, 20)
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(outer)
	root.add_child(UI.title("Crie seu personagem", 28))

	var cols := UI.hbox(16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	cols.add_child(_column(_build_identity()))
	cols.add_child(_column(_build_look()))
	var face := UI.panel(UI.scroll(_build_face()))
	face.custom_minimum_size = Vector2(320, 0)
	cols.add_child(face)

	error_label = UI.label("", 15, UI.DANGER)
	root.add_child(error_label)
	var brow := UI.hbox()
	root.add_child(brow)
	brow.add_child(UI.button("Voltar", func(): navigate.emit("menu", {})))
	var start := UI.button("Começar a viver", _start)
	start.custom_minimum_size = Vector2(240, 0)
	brow.add_child(start)

	expr_timer = Timer.new()
	expr_timer.wait_time = 1.4
	expr_timer.timeout.connect(_next_expression)
	add_child(expr_timer)
	_update_preview()


func _column(content: Control) -> Control:
	var p := UI.panel(UI.scroll(content))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p


func _option(label: String, items: Array) -> OptionButton:
	var opt := OptionButton.new()
	for it in items:
		opt.add_item(it)
	opt.tooltip_text = label
	return opt


func _row(label: String, control: Control) -> HBoxContainer:
	var row := UI.hbox(8)
	var l := UI.label(label, 14, UI.MUTED)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _build_identity() -> Control:
	var box := UI.vbox(8)
	box.add_child(UI.label("Quem é você", 18, UI.ACCENT))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Seu nome"
	box.add_child(_row("Nome", name_edit))
	age_spin = SpinBox.new()
	age_spin.min_value = 18
	age_spin.max_value = 85
	age_spin.value = 28
	age_spin.value_changed.connect(_update_preview.unbind(1))
	box.add_child(_row("Idade", age_spin))
	gender_opt = _option("Gênero", GENDERS)
	gender_opt.item_selected.connect(_update_preview.unbind(1))
	box.add_child(_row("Gênero", gender_opt))

	var names: Array = World.origins.map(func(o): return o["nome"])
	origin_opt = _option("Origem", names)
	origin_opt.item_selected.connect(_on_origin_selected)
	box.add_child(_row("Como chegou", origin_opt))
	origin_desc = UI.label("", 14, UI.MUTED)
	box.add_child(origin_desc)
	_on_origin_selected(0)

	box.add_child(UI.label("Sua história (só você e o narrador sabem)", 14, UI.MUTED))
	backstory_edit = TextEdit.new()
	backstory_edit.placeholder_text = "Quem você era antes? Do que está fugindo? O que quer?"
	backstory_edit.custom_minimum_size = Vector2(0, 90)
	backstory_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(backstory_edit)

	box.add_child(UI.label("Traços (até %d)" % MAX_TRAITS, 18, UI.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for t in World.traits:
		var cb := CheckBox.new()
		cb.text = t["nome"]
		cb.tooltip_text = t["descricao"]
		cb.toggled.connect(_on_trait_toggled.unbind(1))
		grid.add_child(cb)
		trait_boxes[t["id"]] = cb
	return box


func _build_look() -> Control:
	var box := UI.vbox(6)
	var head := UI.hbox()
	box.add_child(head)
	var t := UI.label("Aparência", 18, UI.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	head.add_child(UI.button("Aleatório", _randomize_look))
	for cat in World.appearance["categorias"]:
		var opt := _option(cat["nome"], cat["opcoes"].map(func(o): return o[0]))
		opt.item_selected.connect(_update_preview.unbind(1))
		look_opts[cat["id"]] = opt
		box.add_child(_row(cat["nome"], opt))
	clothes_color = ColorPickerButton.new()
	clothes_color.color = Color("#4a5260")
	clothes_color.custom_minimum_size = Vector2(0, 30)
	clothes_color.color_changed.connect(_update_preview.unbind(1))
	box.add_child(_row("Cor da roupa", clothes_color))
	box.add_child(UI.label("Marcas e acessórios", 14, UI.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for m in World.appearance["marcas"]:
		var cb := CheckBox.new()
		cb.text = m[0]
		cb.toggled.connect(_update_preview.unbind(1))
		grid.add_child(cb)
		mark_boxes.append(cb)
	box.add_child(UI.label("Detalhes extras (os NPCs vão notar)", 14, UI.MUTED))
	extra_edit = TextEdit.new()
	extra_edit.placeholder_text = "Ex: parece mais velho do que é, sorriso torto, cheiro de cigarro"
	extra_edit.custom_minimum_size = Vector2(0, 70)
	extra_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(extra_edit)
	return box


func _build_face() -> Control:
	var box := UI.vbox(8)
	box.add_child(UI.label("Seu rosto", 18, UI.ACCENT))
	portrait = FaceRig.new()
	portrait.custom_minimum_size = Vector2(270, 340)
	portrait.scene = "casa"
	box.add_child(portrait)
	expr_label = UI.label("", 14, UI.ACCENT)
	expr_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(expr_label)
	box.add_child(UI.button("Testar expressões", _toggle_expressions))
	box.add_child(UI.button("Testar fala", func(): portrait.talk(2.5)))
	return box


func _on_origin_selected(idx: int) -> void:
	var o: Dictionary = World.origins[idx]
	origin_desc.text = "%s\nDinheiro inicial: R$ %d%s" % [o["descricao"], int(o["dinheiro"]), "" if o["casa"] != "" else " | Sem casa"]


func _selected_traits() -> Array:
	var out: Array = []
	for id in trait_boxes:
		if trait_boxes[id].button_pressed:
			out.append(id)
	return out


func _on_trait_toggled() -> void:
	var full := _selected_traits().size() >= MAX_TRAITS
	for id in trait_boxes:
		var cb: CheckBox = trait_boxes[id]
		cb.disabled = full and not cb.button_pressed


func _randomize_look() -> void:
	for id in look_opts:
		var opt: OptionButton = look_opts[id]
		opt.select(randi() % opt.item_count)
	for cb in mark_boxes:
		cb.set_pressed_no_signal(randf() < 0.12)
	clothes_color.color = Color.from_hsv(randf(), randf_range(0.2, 0.6), randf_range(0.25, 0.7))
	_update_preview()


func look_spec() -> Dictionary:
	var spec := {}
	for id in look_opts:
		spec[id] = look_opts[id].selected
	var marks: Array = []
	for i in mark_boxes.size():
		if mark_boxes[i].button_pressed:
			marks.append(i)
	spec["marcas"] = marks
	spec["cor_roupa"] = "#" + clothes_color.color.to_html(false)
	return spec


func _update_preview() -> void:
	if portrait:
		portrait.set_look(LookBuilder.build(look_spec(), int(age_spin.value), GENDERS[gender_opt.selected]))


func _toggle_expressions() -> void:
	if expr_timer.is_stopped():
		expr_index = -1
		_next_expression()
		expr_timer.start()
	else:
		expr_timer.stop()
		portrait.set_emotion("neutro")
		expr_label.text = ""


func _next_expression() -> void:
	var keys: Array = World.emotions.keys()
	expr_index = (expr_index + 1) % keys.size()
	portrait.set_emotion(keys[expr_index])
	expr_label.text = World.emotions[keys[expr_index]]["pt"].to_upper()


func describe() -> String:
	var parts: Array = []
	for cat in World.appearance["categorias"]:
		if cat["id"] == "barba" and look_opts["barba"].selected == 0:
			continue
		var opt: String = cat["opcoes"][look_opts[cat["id"]].selected][0]
		if cat["id"] == "cor_cabelo":
			if look_opts["cabelo"].selected == 1:
				continue
			opt = "cabelo " + opt
		parts.append(opt)
	for i in mark_boxes.size():
		if mark_boxes[i].button_pressed:
			parts.append(World.appearance["marcas"][i][0])
	var text := ", ".join(parts)
	var extra := extra_edit.text.strip_edges()
	return text + ("; " + extra if extra != "" else "")


func _start() -> void:
	var pname := name_edit.text.strip_edges()
	if pname == "":
		error_label.text = "Seu personagem precisa de um nome."
		return
	var origin: Dictionary = World.origins[origin_opt.selected]
	var inventory := {}
	for k in origin["itens"]:
		inventory[k] = int(origin["itens"][k])
	var player := {
		"name": pname,
		"age": int(age_spin.value),
		"gender": GENDERS[gender_opt.selected],
		"appearance": describe(),
		"look": look_spec(),
		"appearance_extra": origin.get("aparencia_extra", ""),
		"backstory": backstory_edit.text.strip_edges(),
		"traits": _selected_traits(),
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
