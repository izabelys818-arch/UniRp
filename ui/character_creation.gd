extends Control

signal navigate(screen: String, args: Dictionary)

const UI = preload("res://ui/ui_theme.gd")
const PortraitView = preload("res://ui/portrait_view.gd")
const MAX_TRAITS := 3
const GENDERS := ["homem", "mulher", "pessoa não-binária"]
const GENDERS_EN := ["man", "woman", "androgynous non-binary person"]
const DRAFT := "player_draft"

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
var extra_edit: TextEdit
var portrait: PortraitView
var face_status: Label
var refine_edit: LineEdit
var face_buttons: Array = []
var file_dialog: FileDialog
var error_label: Label
var busy: bool = false


func _ready() -> void:
	PortraitService.clear_id(DRAFT)
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
	face_buttons.append(start)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Imagens"])
	file_dialog.file_selected.connect(_on_photo_selected)
	add_child(file_dialog)
	_update_face_buttons()


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
	box.add_child(_row("Idade", age_spin))
	gender_opt = _option("Gênero", GENDERS)
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
		look_opts[cat["id"]] = opt
		box.add_child(_row(cat["nome"], opt))
	box.add_child(UI.label("Marcas e acessórios", 14, UI.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for m in World.appearance["marcas"]:
		var cb := CheckBox.new()
		cb.text = m[0]
		grid.add_child(cb)
		mark_boxes.append(cb)
	box.add_child(UI.label("Detalhes extras (qualquer coisa: estilo, idade aparente, expressão, objetos...)", 14, UI.MUTED))
	extra_edit = TextEdit.new()
	extra_edit.placeholder_text = "Ex: parece mais velho do que é, sobrancelha cortada, sorriso torto, brinco de argola só na esquerda"
	extra_edit.custom_minimum_size = Vector2(0, 80)
	extra_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(extra_edit)
	return box


func _build_face() -> Control:
	var box := UI.vbox(8)
	box.add_child(UI.label("Seu rosto", 18, UI.ACCENT))
	portrait = PortraitView.new()
	portrait.min_size = Vector2(250, 310)
	box.add_child(portrait)
	face_status = UI.label("", 13, UI.MUTED)
	box.add_child(face_status)
	var b1 := UI.button("Gerar rosto", _generate_face)
	box.add_child(b1)
	var b2 := UI.button("Usar foto do meu PC", func(): file_dialog.popup_centered_ratio(0.7))
	box.add_child(b2)
	refine_edit = LineEdit.new()
	refine_edit.placeholder_text = "Ajuste: ex. cabelo mais curto, mais velho..."
	refine_edit.text_submitted.connect(_refine_face.unbind(1))
	box.add_child(refine_edit)
	var b3 := UI.button("Aplicar ajuste no rosto", _refine_face)
	box.add_child(b3)
	face_buttons.append_array([b1, b2, b3])
	if not Settings.images_ready():
		face_status.text = "Escolha um modelo de imagem em Configurações para gerar seu rosto. Você ainda pode usar uma foto do PC."
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
		cb.button_pressed = randf() < 0.12


func _pick(cat_id: String) -> Array:
	for cat in World.appearance["categorias"]:
		if cat["id"] == cat_id:
			return cat["opcoes"][look_opts[cat_id].selected]
	return ["", ""]


func describe(lang: int) -> String:
	# lang 0 = português (para NPCs), 1 = inglês (para a IA de imagem)
	var parts: Array = []
	for id in ["pele", "tracos", "corpo", "altura", "rosto", "olhos"]:
		parts.append(_pick(id)[lang])
	var hair := _pick("cabelo")
	if look_opts["cabelo"].selected == 1:
		parts.append(hair[lang])
	elif lang == 0:
		parts.append("%s %s" % [hair[0], _pick("cor_cabelo")[0]])
	else:
		parts.append("%s %s" % [_pick("cor_cabelo")[1], hair[1]])
	if look_opts["barba"].selected != 0:
		parts.append(_pick("barba")[lang])
	for i in mark_boxes.size():
		if mark_boxes[i].button_pressed:
			parts.append(World.appearance["marcas"][i][lang])
	parts.append(_pick("roupa")[lang])
	var text := ", ".join(parts)
	var extra := extra_edit.text.strip_edges()
	if lang == 1:
		var origin: Dictionary = World.origins[origin_opt.selected]
		text = "a %d-year-old %s with %s." % [int(age_spin.value), GENDERS_EN[gender_opt.selected], text]
		if extra != "":
			text += " Additional details (in Portuguese): " + extra + "."
		if str(origin.get("aparencia_extra", "")) != "":
			text += " Current state (in Portuguese): " + origin["aparencia_extra"] + "."
		return text
	return text + ("; " + extra if extra != "" else "")


func _update_face_buttons() -> void:
	for b in face_buttons:
		b.disabled = busy
	portrait.show_npc(DRAFT, "neutro", UI.PANEL_LIGHT, name_edit.text.substr(0, 1).to_upper() if name_edit.text != "" else "?")


func _generate_face() -> void:
	if busy:
		return
	busy = true
	face_status.text = "Gerando seu rosto... (pode levar até 1 minuto)"
	_update_face_buttons()
	var res: Dictionary = await PortraitService.generate_base(DRAFT, describe(1))
	busy = false
	face_status.text = "Gostou? Gere de novo ou aplique ajustes." if res["ok"] else str(res["error"])
	_update_face_buttons()


func _refine_face() -> void:
	var instr := refine_edit.text.strip_edges()
	if busy or instr == "":
		return
	busy = true
	face_status.text = "Aplicando ajuste..."
	_update_face_buttons()
	var res: Dictionary = await PortraitService.refine(DRAFT, instr)
	busy = false
	if res["ok"]:
		refine_edit.text = ""
		face_status.text = "Ajuste aplicado."
	else:
		face_status.text = str(res["error"])
	_update_face_buttons()


func _on_photo_selected(path: String) -> void:
	if PortraitService.import_photo(DRAFT, path):
		face_status.text = "Foto carregada. As expressões serão geradas a partir dela."
	else:
		face_status.text = "Não consegui abrir essa imagem."
	_update_face_buttons()


func _start() -> void:
	var pname := name_edit.text.strip_edges()
	if pname == "":
		error_label.text = "Seu personagem precisa de um nome."
		return
	if busy:
		return
	var origin: Dictionary = World.origins[origin_opt.selected]
	var inventory := {}
	for k in origin["itens"]:
		inventory[k] = int(origin["itens"][k])
	var player := {
		"name": pname,
		"age": int(age_spin.value),
		"gender": GENDERS[gender_opt.selected],
		"appearance": describe(0),
		"appearance_en": describe(1),
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
	PortraitService.promote_draft()
	GameState.new_game(player)
	TimeManager.total_minutes = int(origin["hora"]) * 60
	NeedsSystem.reset(origin["necessidades"])
	NPCManager.reset_state(origin)
	navigate.emit("game", {"new_origin": origin})
