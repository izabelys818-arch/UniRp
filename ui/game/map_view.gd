extends Control

# Mapa da cidade: desenha a planta real do mundo aberto (os mesmos quarteirões do 3D),
# com a sua posição em tempo real. Coordenadas arredondadas para os traços ficarem nítidos.

signal place_selected(loc_id: String)

const UI = preload("res://ui/ui_theme.gd")
const Layout = preload("res://world3d/city_layout.gd")
const TYPE_COLORS := {
	"casa": Color("#e8ad4f"), "publico": Color("#4fd1b5"), "bar": Color("#ff5d8f"), "loja": Color("#5aa9e6"),
	"comida": Color("#f4a261"), "servico": Color("#c792ea"), "hospedagem": Color("#b5838d"),
}
const FILL_COLORS := {
	"casas": Color("#1c2532"), "predio": Color("#273245"), "verde": Color("#173222"),
	"terreno": Color("#2c271f"), "estacionamento": Color("#20242b"),
}

var hovered: String = ""
var selected: String = ""
var t: float = 0.0
var layout: Layout
var _off := Vector2.ZERO
var _s := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	layout = Layout.new()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	t += delta
	queue_redraw()


func _fit() -> void:
	var avail := size - Vector2(40, 40)
	_s = minf(avail.x, avail.y) / Layout.SIZE
	_off = ((size - Vector2(Layout.SIZE, Layout.SIZE) * _s) / 2.0).round()


func _p(v: Vector2) -> Vector2:
	return (_off + v * _s).round()


func _pin_world(id: String) -> Vector2:
	if not layout.lots.has(id):
		return Vector2.ZERO
	var lot: Dictionary = layout.lots[id]
	var b: Rect2 = lot["building"]
	return b.get_center() if b.size != Vector2.ZERO else (lot["rect"] as Rect2).get_center()


func _pin_at(p: Vector2) -> String:
	_fit()
	for id in World.visible_locations():
		if _p(_pin_world(id)).distance_to(p) < 20:
			return id
	return ""


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := _pin_at(e.position)
		if h != hovered:
			hovered = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var id := _pin_at(e.position)
		if id != "":
			selected = id
			place_selected.emit(id)


func _rect(r: Rect2, c: Color) -> void:
	var tl := _p(r.position)
	var br := _p(r.end)
	draw_rect(Rect2(tl, br - tl), c)


func _draw() -> void:
	_fit()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0a0f16"))
	_rect(Rect2(Vector2(-6, -6), Vector2(Layout.SIZE + 12, Layout.SIZE + 12)), Color("#141a24"))
	# ruas e quarteirões
	for c in layout.blocks:
		var info: Dictionary = layout.blocks[c]
		var r := Layout.block_rect(c)
		var id := str(info["loc"])
		if id == "":
			_rect(r, FILL_COLORS.get(str(info["kind"]), Color("#1c2532")))
			continue
		var tipo := str(World.locations[id].get("tipo", "publico"))
		var base: Color = TYPE_COLORS.get(tipo, UI.TEXT)
		if id in ["praca", "parque", "rodoviaria", "beco", "rua_acacias"]:
			_rect(r, Color("#1a3a2a") if id == "parque" else Color("#24303d"))
		else:
			_rect(r, Color("#202a38"))
		var b: Rect2 = layout.lots[id]["building"]
		if b.size != Vector2.ZERO:
			_rect(b, Color(base.r, base.g, base.b, 0.42))
			draw_rect(Rect2(_p(b.position), _p(b.end) - _p(b.position)), Color(base, 0.9), false, 1.0)
	# faixa central das ruas
	var line_col := Color("#2b3547")
	for i in Layout.GRID + 1:
		var lp := i * Layout.PITCH + Layout.STREET / 2.0
		draw_line(_p(Vector2(lp, 0)), _p(Vector2(lp, Layout.SIZE)), line_col, 1.0)
		draw_line(_p(Vector2(0, lp)), _p(Vector2(Layout.SIZE, lp)), line_col, 1.0)
	var here := World.current_id()
	var pos_a: Array = GameState.player.get("pos", [0, 0])
	var me := _p(Vector2(float(pos_a[0]), float(pos_a[1])))
	if selected != "" and layout.lots.has(selected):
		var sp := _p(_pin_world(selected))
		var n := 28
		for i in n:
			if i % 2 == 0:
				draw_line(me.lerp(sp, float(i) / n), me.lerp(sp, float(i + 1) / n), UI.ACCENT, 2.0, true)
	var f := UI.font(true)
	var placed: Array = []
	var order: Array = World.visible_locations()
	order.sort_custom(func(a: String, b: String) -> bool:
		return (1 if (a == hovered or a == selected or a == here) else 0) > (1 if (b == hovered or b == selected or b == here) else 0))
	for id in order:
		var loc: Dictionary = World.locations[id]
		var p := _p(_pin_world(id))
		var col: Color = TYPE_COLORS.get(loc["tipo"], UI.TEXT)
		var open := World.is_open(id)
		if not open:
			col = col.darkened(0.55)
		var big: bool = id == hovered or id == selected
		var rad := 9.0 if big else 7.0
		draw_circle(p + Vector2(0, 2), rad + 1.0, Color(0, 0, 0, 0.55))
		draw_circle(p, rad, col)
		draw_arc(p, rad, 0, TAU, 24, Color(0, 0, 0, 0.6), 1.5, true)
		var name_s: String = loc["nome"]
		var fs := 14 if big else 12
		var w := f.get_string_size(name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lp := (p + Vector2(-w / 2.0, 24.0)).round()
		var box := Rect2(lp + Vector2(-5, -13), Vector2(w + 10, 18))
		var clash := false
		for other in placed:
			if (other as Rect2).intersects(box.grow(2.0)):
				clash = true
				break
		if not clash or big:
			placed.append(box)
			draw_rect(box, Color(0, 0, 0, 0.62))
			draw_string(f, lp, name_s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if open else UI.MUTED)
	# você
	var pulse := 0.5 + 0.5 * sin(t * 3.0)
	draw_circle(me, 14.0 + pulse * 8.0, Color(UI.ACCENT, 0.2 * (1.0 - pulse)))
	draw_circle(me, 6.0, UI.ACCENT)
	draw_arc(me, 6.0, 0, TAU, 20, Color.WHITE, 2.0, true)
	draw_string(f, me + Vector2(-14, -12), "Você", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.ACCENT)
	draw_string(UI.font(true), Vector2(20, size.y - 18), GameState.city().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 1, 1, 0.12))
