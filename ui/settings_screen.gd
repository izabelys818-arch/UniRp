extends Control

signal navigate(screen: String, args: Dictionary)

const UI = preload("res://ui/ui_theme.gd")

var args: Dictionary = {}
var key_edit: LineEdit
var filter_edit: LineEdit
var free_only: CheckBox
var model_list: ItemList
var model_label: Label
var temp_slider: HSlider
var temp_label: Label
var status: Label
var models: Array = []


func _ready() -> void:
	var root := UI.vbox(10)
	var outer := UI.margin(root, 30)
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(outer)

	root.add_child(UI.title("Configurações", 30))
	root.add_child(UI.label("Chave da API do OpenRouter (pegue grátis em openrouter.ai, em Keys):"))
	key_edit = LineEdit.new()
	key_edit.secret = true
	key_edit.placeholder_text = "sk-or-..."
	key_edit.text = Settings.api_key
	root.add_child(key_edit)

	root.add_child(UI.label("Modelo de conversa (NPCs e narrador)", 17, UI.ACCENT))
	var row := UI.hbox()
	root.add_child(row)
	row.add_child(UI.button("Carregar lista", _load_models))
	filter_edit = LineEdit.new()
	filter_edit.placeholder_text = "Filtrar (ex: llama, deepseek, mistral, gemma)"
	filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_edit.text_changed.connect(_fill_list.unbind(1))
	row.add_child(filter_edit)
	free_only = CheckBox.new()
	free_only.text = "Só grátis"
	free_only.button_pressed = true
	free_only.toggled.connect(_fill_list.unbind(1))
	row.add_child(free_only)

	model_list = ItemList.new()
	model_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	model_list.item_selected.connect(_on_model_selected)
	root.add_child(model_list)
	model_label = UI.label("", 14)
	root.add_child(model_label)
	_update_model_label()

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
	brow.add_child(UI.button("Voltar", _back))


func _update_model_label() -> void:
	model_label.text = "Escolhido: " + (Settings.model if Settings.model != "" else "(nenhum)")


func _update_temp_label() -> void:
	temp_label.text = "Criatividade das respostas: %.2f" % temp_slider.value


func _load_models() -> void:
	_apply()
	status.text = "Carregando modelos..."
	var res: Dictionary = await AIService.fetch_models()
	if not res["ok"]:
		status.text = res["error"]
		return
	models = res["models"]
	status.text = "%d modelos disponíveis." % models.size()
	_fill_list()


func _fill_list() -> void:
	model_list.clear()
	var f := filter_edit.text.to_lower()
	for m in models:
		if free_only.button_pressed and not m["free"]:
			continue
		if f != "" and not (f in str(m["id"]).to_lower() or f in str(m["name"]).to_lower()):
			continue
		var idx := model_list.add_item(str(m["id"]) + ("  (grátis)" if m["free"] else ""))
		model_list.set_item_metadata(idx, m["id"])


func _on_model_selected(idx: int) -> void:
	Settings.model = model_list.get_item_metadata(idx)
	_update_model_label()


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
