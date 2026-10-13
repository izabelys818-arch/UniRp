extends Control

signal navigate(screen: String, args: Dictionary)

const UI = preload("res://ui/ui_theme.gd")

var pace_opt: OptionButton
var aging_check: CheckBox
var quality_opt: OptionButton
var camera_opt: OptionButton
var camera_key_opt: OptionButton
var camera_sensitivity_slider: HSlider
var camera_sensitivity_value: Label
var camera_invert_check: CheckBox
var args: Dictionary = {}
var key_edit: LineEdit
var reveal_key_button: Button
var filter_edit: LineEdit
var free_only: CheckBox
var model_list: ItemList
var model_empty: Label
var model_label: Label
var temp_slider: HSlider
var local_check: CheckBox
var temp_label: Label
var temp_value: Label
var status: Label
var panel: PanelContainer
var models: Array = []


func _ready() -> void:
	var sky := preload("res://ui/menu/skyline_bg.gd").new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(sky)
	var root := UI.vbox(10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.glass(16, 24))
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_child(UI.scroll(root))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_child(panel)
	center.resized.connect(_layout_panel)
	var outer := UI.margin(center, 24)
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(outer)
	_layout_panel()

	root.add_child(UI.title("Configurações", 30))
	root.add_child(UI.label("Chave da API do OpenRouter", 17, UI.ACCENT))
	var key_row := UI.hbox(8)
	root.add_child(key_row)
	key_edit = LineEdit.new()
	key_edit.secret = true
	key_edit.placeholder_text = "sk-or-..."
	key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_edit.text = Settings.api_key
	key_row.add_child(key_edit)
	reveal_key_button = UI.button("Mostrar", _toggle_key_visibility)
	reveal_key_button.custom_minimum_size = Vector2(104, 38)
	key_row.add_child(reveal_key_button)
	root.add_child(UI.label("Obtenha a chave em openrouter.ai/keys. Nunca compartilhe sua chave.", 13, UI.MUTED))

	root.add_child(UI.label("Modelo de conversa", 17, UI.ACCENT))
	var model_row := UI.hbox(8)
	root.add_child(model_row)
	var load_button := UI.button("Carregar lista", _load_models)
	load_button.custom_minimum_size = Vector2(142, 38)
	model_row.add_child(load_button)
	filter_edit = LineEdit.new()
	filter_edit.placeholder_text = "Filtrar: llama, deepseek, mistral..."
	filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_edit.text_changed.connect(_fill_list.unbind(1))
	model_row.add_child(filter_edit)
	free_only = CheckBox.new()
	free_only.text = "Só grátis"
	free_only.button_pressed = true
	free_only.toggled.connect(_fill_list.unbind(1))
	model_row.add_child(free_only)
	var list_shell := Control.new()
	list_shell.custom_minimum_size = Vector2(0, 196)
	root.add_child(list_shell)
	model_list = ItemList.new()
	model_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	model_list.item_selected.connect(_on_model_selected)
	list_shell.add_child(model_list)
	model_empty = UI.label("Clique em Carregar lista para escolher um modelo.", 14, UI.MUTED)
	model_empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	model_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	model_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	model_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list_shell.add_child(model_empty)
	model_label = UI.label("", 14)
	root.add_child(model_label)
	_update_model_label()

	var temp_row := _field_row("Criatividade das respostas")
	root.add_child(temp_row)
	temp_label = temp_row.get_child(0)
	temp_slider = HSlider.new()
	temp_slider.min_value = 0.2
	temp_slider.max_value = 1.3
	temp_slider.step = 0.05
	temp_slider.value = Settings.temperature
	temp_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	temp_slider.value_changed.connect(_update_temp_label.unbind(1))
	temp_row.add_child(temp_slider)
	temp_value = UI.label("", 14, UI.ACCENT)
	temp_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	temp_value.custom_minimum_size.x = 48
	temp_row.add_child(temp_value)
	_update_temp_label()
	local_check = CheckBox.new()
	local_check.text = "Respostas rápidas locais (saudações, preços, direções e elogios)"
	local_check.button_pressed = Settings.local_dialogue
	root.add_child(local_check)

	root.add_child(UI.label("Calendário e idade", 17, UI.ACCENT))
	var pace_row := _field_row("Ritmo do calendário")
	root.add_child(pace_row)
	pace_opt = OptionButton.new()
	for n in TimeManager.PACES:
		pace_opt.add_item("Meses de %d dias  (1 ano = %d dias de jogo, ~%d h jogadas)" % [n, n * 12, int(round(n * 12 * 24.0 / 60.0))])
	pace_opt.select(maxi(0, TimeManager.PACES.find(Settings.days_per_month)))
	pace_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pace_row.add_child(pace_opt)
	aging_check = CheckBox.new()
	aging_check.text = "Envelhecer nos aniversários (desligado: o calendário e as festas continuam, a idade não muda)"
	aging_check.button_pressed = Settings.aging
	root.add_child(aging_check)

	root.add_child(UI.label("Gráficos", 17, UI.ACCENT))
	var quality_row := _field_row("Qualidade gráfica")
	root.add_child(quality_row)
	quality_opt = OptionButton.new()
	quality_opt.add_item("Desempenho (mais FPS: sem luz global, névoa e relevo)")
	quality_opt.add_item("Alto — recomendado (névoa por profundidade e detalhe de superfície)")
	quality_opt.add_item("Ultra (luz que rebate entre tudo; pesa e pode engasgar)")
	quality_opt.select(clampi(Settings.graphics, 0, quality_opt.item_count - 1))
	quality_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality_row.add_child(quality_opt)

	root.add_child(UI.label("Câmera e controles", 17, UI.ACCENT))
	var camera_mode_row := _field_row("Modo de câmera")
	root.add_child(camera_mode_row)
	camera_opt = OptionButton.new()
	camera_opt.add_item("Isométrica")
	camera_opt.add_item("Terceira pessoa")
	camera_opt.select(clampi(Settings.camera_mode, 0, 1))
	camera_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camera_mode_row.add_child(camera_opt)
	var camera_key_row := _field_row("Tecla para alternar")
	root.add_child(camera_key_row)
	camera_key_opt = OptionButton.new()
	for key in Settings.CAMERA_KEYS:
		camera_key_opt.add_item(OS.get_keycode_string(key))
	camera_key_opt.select(maxi(0, Settings.CAMERA_KEYS.find(Settings.camera_key)))
	camera_key_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camera_key_row.add_child(camera_key_opt)
	var sensitivity_row := _field_row("Sensibilidade do mouse")
	root.add_child(sensitivity_row)
	camera_sensitivity_slider = HSlider.new()
	camera_sensitivity_slider.min_value = 0.001
	camera_sensitivity_slider.max_value = 0.008
	camera_sensitivity_slider.step = 0.0005
	camera_sensitivity_slider.value = Settings.camera_sensitivity
	camera_sensitivity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sensitivity_row.add_child(camera_sensitivity_slider)
	camera_sensitivity_value = UI.label("", 14, UI.ACCENT)
	camera_sensitivity_value.custom_minimum_size.x = 54
	camera_sensitivity_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sensitivity_row.add_child(camera_sensitivity_value)
	camera_sensitivity_slider.value_changed.connect(func(value: float) -> void: camera_sensitivity_value.text = "%.4f" % value)
	camera_sensitivity_value.text = "%.4f" % camera_sensitivity_slider.value
	camera_invert_check = CheckBox.new()
	camera_invert_check.text = "Inverter eixo vertical"
	camera_invert_check.button_pressed = Settings.camera_invert_y
	root.add_child(camera_invert_check)
	root.add_child(UI.label("Terceira pessoa: WASD relativo à câmera • arraste o botão direito para olhar • roda ajusta distância • E interage", 12, UI.MUTED))

	status = UI.label("", 14, UI.MUTED)
	root.add_child(status)
	var footer := UI.hbox(10)
	footer.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(footer)
	for spec in [["Salvar", _save], ["Testar conversa", _test], ["Voltar", _back]]:
		var button: Button = UI.button(spec[0], spec[1])
		button.custom_minimum_size = Vector2(150, 40)
		footer.add_child(button)
	var version := UI.label("UniRp  •  v0.9 (11/out)", 12, UI.MUTED)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(version)


func _layout_panel() -> void:
	if not is_instance_valid(panel):
		return
	var viewport_size := get_viewport_rect().size
	var available := viewport_size.x - 48.0
	panel.custom_minimum_size = Vector2(clampf(available, 650.0, 980.0), maxf(320.0, viewport_size.y - 48.0))


func _field_row(caption: String) -> HBoxContainer:
	var row := UI.hbox(10)
	var label := UI.label(caption)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size.x = 220
	label.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(label)
	return row


func _toggle_key_visibility() -> void:
	key_edit.secret = not key_edit.secret
	reveal_key_button.text = "Mostrar" if key_edit.secret else "Ocultar"


func _update_model_label() -> void:
	model_label.text = "Escolhido: " + (Settings.model if Settings.model != "" else "(nenhum)")


func _update_temp_label() -> void:
	if is_instance_valid(temp_value):
		temp_value.text = "%.2f" % temp_slider.value


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
	if models.is_empty():
		model_empty.text = "Clique em Carregar lista para escolher um modelo."
		model_empty.show()
	elif model_list.item_count == 0:
		model_empty.text = "Nenhum modelo corresponde a este filtro."
		model_empty.show()
	else:
		model_empty.hide()


func _on_model_selected(idx: int) -> void:
	Settings.model = model_list.get_item_metadata(idx)
	_update_model_label()


func _apply() -> void:
	Settings.api_key = key_edit.text.strip_edges()
	Settings.temperature = temp_slider.value
	Settings.local_dialogue = local_check.button_pressed
	Settings.days_per_month = TimeManager.PACES[maxi(0, pace_opt.selected)]
	Settings.aging = aging_check.button_pressed
	Settings.graphics = maxi(0, quality_opt.selected)
	Settings.camera_mode = maxi(0, camera_opt.selected)
	Settings.camera_key = Settings.CAMERA_KEYS[maxi(0, camera_key_opt.selected)]
	Settings.camera_sensitivity = camera_sensitivity_slider.value
	Settings.camera_invert_y = camera_invert_check.button_pressed
	Settings.apply_camera_inputs()
	Settings.save_settings()
	Settings.camera_changed.emit()
	preload("res://world3d/atmosphere.gd").apply_quality(Settings.graphics)
	if GameState.active:
		Settings.apply_calendar()


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
