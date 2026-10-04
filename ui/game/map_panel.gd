extends "res://ui/game/overlay.gd"

const MapView = preload("res://ui/game/map_view.gd")
const Icons = preload("res://ui/game/icons.gd")

var map_view: MapView
var info: VBoxContainer


func _ready() -> void:
	_build_overlay("Mapa da cidade", Vector2(1240, 680))
	var row := UI.hbox(16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)
	map_view = MapView.new()
	map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.place_selected.connect(_on_selected)
	var map_frame := PanelContainer.new()
	map_frame.add_theme_stylebox_override("panel", UI._box(Color(0, 0, 0, 0.3), 16, 0))
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.clip_contents = true
	map_frame.add_child(map_view)
	row.add_child(map_frame)
	info = UI.vbox(10)
	var ip := PanelContainer.new()
	ip.add_theme_stylebox_override("panel", UI._box(Color(1, 1, 1, 0.04), 16, 16))
	ip.custom_minimum_size = Vector2(320, 0)
	ip.add_child(info)
	row.add_child(ip)


func open() -> void:
	map_view.selected = ""
	_fill_info("")
	open_overlay()


func _on_selected(id: String) -> void:
	_fill_info(id)


func _fill_info(id: String) -> void:
	for c in info.get_children():
		c.queue_free()
	if id == "":
		info.add_child(UI.label("Você está em", 14, UI.MUTED))
		info.add_child(UI.title(World.current().get("nome", ""), 22))
		info.add_child(UI.label("Clique num lugar do mapa para ver como chegar.", 15, UI.MUTED))
		return
	var loc: Dictionary = World.locations[id]
	info.add_child(UI.title(loc["nome"], 22))
	var open := World.is_open(id)
	var hours := "Aberto 24h" if int(loc["abre"]) == 0 and int(loc["fecha"]) == 24 else "Abre %02dh • Fecha %02dh" % [int(loc["abre"]), int(loc["fecha"]) % 24]
	info.add_child(UI.chip(("Aberto agora" if open else "Fechado agora") + "  •  " + hours, UI.TEAL if open else UI.DANGER, 13))
	var desc := UI.label(loc["descricao"], 14, UI.MUTED)
	info.add_child(desc)
	if id == World.current_id():
		info.add_child(UI.label("Você já está aqui.", 15, UI.ACCENT))
		return
	info.add_child(UI.label("Como ir", 16, UI.ACCENT))
	for o in World.travel_options(id):
		var b := Button.new()
		var icon: String = {"ape": "walk", "uber": "uber", "carro": "car"}.get(o["mode"], "walk")
		var cost := "" if int(o["cost"]) == 0 else "  •  R$ %d" % int(o["cost"])
		b.text = "      %s  •  %d min%s" % [o["label"], int(o["minutes"]), cost]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 50)
		b.disabled = not o["ok"]
		if not o["ok"]:
			b.text += "  (%s)" % o["note"]
		b.draw.connect(func(): Icons.draw(b, icon, Rect2(12, 13, 24, 24), UI.ACCENT if not b.disabled else UI.MUTED, 2.0))
		b.pressed.connect(_travel.bind(id, o["mode"]))
		info.add_child(b)


func _travel(id: String, mode: String) -> void:
	close()
	World.request_travel(id, mode)
