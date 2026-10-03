extends Control

signal navigate(screen: String, args: Dictionary)

const UI = preload("res://ui/ui_theme.gd")

var args: Dictionary = {}
var key_edit: LineEdit
var temp_slider: HSlider
var temp_label: Label
var status: Label
var pickers: Dictionary = {}


func _ready() -> void:
	var root := UI.vbox(10)
	var outer := UI.margin(root, 30)
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(outer)

	root.add_child(UI.title("Configurações", 30))
	root.add_child(UI.label("Chave da API do OpenRouter (pegue em openrouter.ai, em Keys):"))
	key_edit = LineEdit.new()
	key_edit.secret = true
	key_edit.placeholder_text = "sk-or-..."
	key_edit.text = Settings.api_key
	root.add_child(key_edit)

	var cols := UI.hbox(20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	cols.add_child(_build_picker("text", "Modelo de conversa (NPCs e narrador)", "Filtrar (ex: claude, llama, deepseek)", true))
	cols.add_child(_build_picker("image", "Modelo de imagem (rostos dos NPCs)", "Filtrar (ex: gemini, flux, seedream)", false))

	var trow := UI.hbox()
	root.add_child(trow)
	temp_label = UI.label("")
	temp_label.custom_minimum_size = Vector2(320, 0)
	trow.add_child(temp_label)
	temp_slider = HSlider.new()
	temp_slider.min_value = 0.2
	temp_slider.max_value = 1.3
	temp_slider.step = 0.05
	temp_slider.value = Settings.temperature
	temp_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	temp_slider.value_changed.connect(_update_temp_label.unbind(1))
	trow.add_child(temp_slider)
	_update_temp_label()

	status = UI.label("", 15, UI.MUTED)
	root.add_child(status)

	var brow := UI.hbox()
	root.add_child(brow)
	brow.add_child(UI.button("Salvar", _save))
	brow.add_child(UI.button("Testar conversa", _test))
	brow.add_child(UI.button("Testar imagem", _test_image))
	brow.add_child(UI.button("Apagar rostos gerados", _clear_portraits))
	brow.add_child(UI.button("Voltar", _back))


func _build_picker(kind: String, title: String, hint: String, with_free: bool) -> Control:
	var col := UI.vbox(6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(UI.label(title, 17, UI.ACCENT))
	var row := UI.hbox()
	col.add_child(row)
	var p := {"models": [], "kind": kind}
	row.add_child(UI.button("Carregar lista", _load_models.bind(kind)))
	var filter := LineEdit.new()
	filter.placeholder_text = hint
	filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter.text_changed.connect(_fill_list.bind(kind).unbind(1))
	row.add_child(filter)
	p["filter"] = filter
	var free_only := CheckBox.new()
	free_only.text = "Só grátis"
	free_only.visible = with_free
	free_only.toggled.connect(_fill_list.bind(kind).unbind(1))
	row.add_child(free_only)
	p["free_only"] = free_only
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(_on_model_selected.bind(kind))
	col.add_child(list)
	p["list"] = list
	var current := UI.label("", 14)
	col.add_child(current)
	p["current"] = current
	pickers[kind] = p
	_update_current(kind)
	return col


func _update_current(kind: String) -> void:
	var label: Label = pickers[kind]["current"]
	if kind == "text":
		label.text = "Escolhido: " + (Settings.model if Settings.model != "" else "(nenhum)")
	else:
		var m := Settings.image_model if Settings.image_model != "" else "(nenhum: NPCs ficam sem rosto)"
		var refs := "" if Settings.image_model == "" else ("  (mantém o mesmo rosto nas expressões)" if Settings.image_model_refs else "  (atenção: não aceita foto de referência, o rosto pode mudar entre expressões)")
		label.text = "Escolhido: " + m + refs


func _update_temp_label() -> void:
	temp_label.text = "Criatividade das respostas: %.2f" % temp_slider.value


func _load_models(kind: String) -> void:
	_apply()
	status.text = "Carregando modelos..."
	var res: Dictionary
	if kind == "text":
		res = await AIService.fetch_models()
	else:
		res = await AIService.fetch_image_models()
	if not res["ok"]:
		status.text = res["error"]
		return
	pickers[kind]["models"] = res["models"]
	status.text = "%d modelos disponíveis." % res["models"].size()
	_fill_list(kind)


func _fill_list(kind: String) -> void:
	var p: Dictionary = pickers[kind]
	var list: ItemList = p["list"]
	list.clear()
	var f: String = p["filter"].text.to_lower()
	for m in p["models"]:
		if p["free_only"].button_pressed and not m["free"]:
			continue
		if f != "" and not (f in str(m["id"]).to_lower() or f in str(m["name"]).to_lower()):
			continue
		var tag := ""
		if m["free"]:
			tag = "  (grátis)"
		elif kind == "image" and m["refs"]:
			tag = "  (aceita referência - recomendado)"
		var idx := list.add_item(str(m["id"]) + tag)
		list.set_item_metadata(idx, m)


func _on_model_selected(idx: int, kind: String) -> void:
	var m: Dictionary = pickers[kind]["list"].get_item_metadata(idx)
	if kind == "text":
		Settings.model = m["id"]
	else:
		Settings.image_model = m["id"]
		Settings.image_model_refs = m["refs"]
	_update_current(kind)


func _apply() -> void:
	Settings.api_key = key_edit.text.strip_edges()
	Settings.temperature = temp_slider.value
	Settings.save_settings()


func _save() -> void:
	_apply()
	status.text = "Configurações salvas."


func _back() -> void:
	_apply()
	navigate.emit(args.get("back", "menu"), {})


func _test() -> void:
	_apply()
	status.text = "Testando conversa..."
	var res: Dictionary = await AIService.chat([{"role": "user", "content": "Responda apenas: Porto Cinza está viva."}], 30)
	status.text = ("Conversa funcionando! Resposta: " + str(res["text"]).strip_edges()) if res["ok"] else res["error"]


func _test_image() -> void:
	_apply()
	status.text = "Gerando imagem de teste (pode levar até 1 minuto)..."
	var res: Dictionary = await AIService.generate_image("Photorealistic portrait photograph of an old Brazilian fisherman, dark moody lighting.")
	if res["ok"]:
		var img: Image = res["image"]
		status.text = "Imagem funcionando! (%dx%d)" % [img.get_width(), img.get_height()]
	else:
		status.text = res["error"]


func _clear_portraits() -> void:
	PortraitService.clear_all()
	status.text = "Rostos apagados. Serão gerados de novo quando aparecerem."
