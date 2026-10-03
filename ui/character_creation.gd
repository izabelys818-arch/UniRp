extends Control

signal navigate(screen: String, args: Dictionary)

const UI = preload("res://ui/ui_theme.gd")
const MAX_TRAITS := 3
const GENDERS := ["homem", "mulher", "pessoa não-binária"]

var args: Dictionary = {}
var name_edit: LineEdit
var age_spin: SpinBox
var gender_opt: OptionButton
var appearance_edit: TextEdit
var backstory_edit: TextEdit
var trait_boxes: Dictionary = {}
var origin_opt: OptionButton
var origin_desc: Label
var error_label: Label


func _ready() -> void:
	var outer := UI.margin(UI.vbox(), 30)
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(outer)
	var root: VBoxContainer = outer.get_child(0)
	root.add_child(UI.title("Crie seu personagem", 30))

	var cols := UI.hbox(30)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var left := UI.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(UI.scroll(left))
	cols.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL

	left.add_child(UI.label("Nome"))
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Como você se chama?"
	left.add_child(name_edit)

	var row := UI.hbox(16)
	left.add_child(row)
	row.add_child(UI.label("Idade"))
	age_spin = SpinBox.new()
	age_spin.min_value = 18
	age_spin.max_value = 80
	age_spin.value = 28
	row.add_child(age_spin)
	row.add_child(UI.label("Gênero"))
	gender_opt = OptionButton.new()
	for g in GENDERS:
		gender_opt.add_item(g)
	row.add_child(gender_opt)

	left.add_child(UI.label("Aparência (o que as pessoas veem)"))
	appearance_edit = TextEdit.new()
	appearance_edit.placeholder_text = "Ex: alto, magro, cabelo cacheado, jaqueta de couro surrada, cicatriz no queixo"
	appearance_edit.custom_minimum_size = Vector2(0, 80)
	appearance_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	left.add_child(appearance_edit)

	left.add_child(UI.label("Sua história (opcional, só você e o narrador sabem)"))
	backstory_edit = TextEdit.new()
	backstory_edit.placeholder_text = "Quem você era antes? Do que está fugindo? O que quer?"
	backstory_edit.custom_minimum_size = Vector2(0, 110)
	backstory_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	left.add_child(backstory_edit)

	left.add_child(UI.label("Como você chegou em Porto Cinza?"))
	origin_opt = OptionButton.new()
	for o in World.origins:
		origin_opt.add_item(o["nome"])
	origin_opt.item_selected.connect(_on_origin_selected)
	left.add_child(origin_opt)
	origin_desc = UI.label("", 15, UI.MUTED)
	left.add_child(origin_desc)
	_on_origin_selected(0)

	var right := UI.vbox(6)
	cols.add_child(UI.scroll(right))
	cols.get_child(1).custom_minimum_size = Vector2(430, 0)
	right.add_child(UI.label("Traços (até %d)" % MAX_TRAITS))
	for t in World.traits:
		var cb := CheckBox.new()
		cb.text = t["nome"]
		cb.tooltip_text = t["descricao"]
		cb.toggled.connect(_on_trait_toggled)
		right.add_child(cb)
		right.add_child(UI.label(t["descricao"], 13, UI.MUTED))
		trait_boxes[t["id"]] = cb

	error_label = UI.label("", 15, UI.DANGER)
	root.add_child(error_label)
	var brow := UI.hbox()
	root.add_child(brow)
	brow.add_child(UI.button("Voltar", func(): navigate.emit("menu", {})))
	var start := UI.button("Começar a viver", _start)
	start.custom_minimum_size = Vector2(220, 0)
	brow.add_child(start)


func _on_origin_selected(idx: int) -> void:
	var o: Dictionary = World.origins[idx]
	origin_desc.text = "%s\nDinheiro inicial: R$ %d%s" % [o["descricao"], int(o["dinheiro"]), "" if o["casa"] != "" else " | Sem casa"]


func _selected_traits() -> Array:
	var out: Array = []
	for id in trait_boxes:
		if trait_boxes[id].button_pressed:
			out.append(id)
	return out


func _on_trait_toggled(_on: bool) -> void:
	var full := _selected_traits().size() >= MAX_TRAITS
	for id in trait_boxes:
		var cb: CheckBox = trait_boxes[id]
		cb.disabled = full and not cb.button_pressed


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
		"appearance": appearance_edit.text.strip_edges(),
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
