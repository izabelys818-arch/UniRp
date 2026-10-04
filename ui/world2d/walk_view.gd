extends Control

# Vista 2D do mundo: o jogador anda pela cena e chega até as pessoas.

const BodyRig = preload("res://ui/world2d/body_rig.gd")
const LookBuilder = preload("res://ui/face/look_builder.gd")
const UI = preload("res://ui/ui_theme.gd")

signal npc_chosen(id: String)
signal npc_menu(id: String)

var player: Control
var npcs: Dictionary = {}
var targets: Dictionary = {}
var player_target: float = -1.0
var pending_npc: String = ""
var hover_id: String = ""
var tag: Label
var left_bound: float = 300.0
var right_bound: float = 1000.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tag = UI.label("", 15, UI.TEXT)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 6)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.hide()
	add_child(tag)
	player = _make_body(GameState.player.get("look", {}), int(GameState.player.get("age", 30)), str(GameState.player.get("gender", "homem")))
	player.position.x = 360.0
	resized.connect(_relayout)


func _make_body(spec: Dictionary, age: int, gender: String) -> Control:
	var b := BodyRig.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.set_look(LookBuilder.build(spec, age, gender))
	add_child(b)
	return b


func ground_y() -> float:
	return size.y - 250.0


func body_h() -> float:
	return size.y * 0.4


func _relayout() -> void:
	left_bound = 300.0
	right_bound = maxf(size.x - 300.0, left_bound + 200.0)
	var h := body_h()
	for b in [player] + npcs.values():
		b.size = Vector2(h * 0.7, h)
		b.position.y = ground_y() - h
	for id in npcs:
		npcs[id].position.x = clampf(npcs[id].position.x, left_bound - h * 0.35, right_bound - h * 0.35)


func _feet_x(b: Control) -> float:
	return b.position.x + b.size.x / 2.0


func _set_feet(b: Control, x: float) -> void:
	b.position.x = x - b.size.x / 2.0


func sync(ids: Array) -> void:
	for id in npcs.keys():
		if not id in ids:
			npcs[id].queue_free()
			npcs.erase(id)
			targets.erase(id)
	var slot := 0
	for id in ids:
		if npcs.has(id):
			continue
		var n: Dictionary = NPCManager.npcs[id]
		var b: Control = _make_body(World.npc_looks.get(id, {}), int(n["idade"]), n["genero"])
		b.seed_n = float(hash(id) % 100)
		var span := right_bound - left_bound
		var x := left_bound + span * (0.2 + 0.75 * (float(slot) + 0.5 + (float(hash(id) % 100) / 100.0 - 0.5) * 0.4) / float(maxi(ids.size(), 1)))
		npcs[id] = b
		slot += 1
		_relayout()
		_set_feet(b, x)
		targets[id] = {"x": x, "wait": randf_range(1.0, 5.0)}
		b.modulate.a = 0.0
		create_tween().tween_property(b, "modulate:a", 1.0, 0.4)
	_relayout()


func _process(delta: float) -> void:
	if not visible:
		return
	var speed := body_h() * 0.85
	# jogador
	var px := _feet_x(player)
	if player_target >= 0.0 and absf(player_target - px) > 4.0:
		var dir := signf(player_target - px)
		_set_feet(player, px + dir * minf(speed * delta, absf(player_target - px)))
		player.facing = dir
		player.walking = true
	else:
		if pending_npc != "":
			var id := pending_npc
			pending_npc = ""
			if npcs.has(id):
				player.facing = signf(_feet_x(npcs[id]) - _feet_x(player))
				npc_chosen.emit(id)
		player.walking = false
		player_target = -1.0
	# NPCs passeiam devagar
	for id in npcs:
		var b: Control = npcs[id]
		var tg: Dictionary = targets[id]
		var x := _feet_x(b)
		if absf(float(tg["x"]) - x) > 3.0:
			var dir := signf(float(tg["x"]) - x)
			_set_feet(b, x + dir * minf(speed * 0.25 * delta, absf(float(tg["x"]) - x)))
			b.facing = dir
			b.walking = true
		else:
			b.walking = false
			tg["wait"] = float(tg["wait"]) - delta
			if float(tg["wait"]) <= 0.0:
				tg["wait"] = randf_range(3.0, 9.0)
				if randf() < 0.45:
					tg["x"] = clampf(x + randf_range(-120.0, 120.0), left_bound, right_bound)
		b.highlight = move_toward(b.highlight, 1.0 if id == hover_id else 0.0, delta * 6.0)
		if id == pending_npc or id == hover_id:
			pass
	# ordem de profundidade: quem está mais abaixo aparece na frente (todos no mesmo chão, então por x)
	var order: Array = [player] + npcs.values()
	order.sort_custom(func(a, b): return a.position.x < b.position.x)
	for i in order.size():
		move_child(order[i], i)
	move_child(tag, -1)
	_update_tag()


func _update_tag() -> void:
	if hover_id == "" or not npcs.has(hover_id):
		tag.hide()
		return
	var b: Control = npcs[hover_id]
	tag.text = NPCManager.display_name(hover_id)
	tag.size = tag.get_combined_minimum_size()
	tag.position = Vector2(_feet_x(b) - tag.size.x / 2.0, b.position.y - 6.0)
	tag.show()


func _npc_at(p: Vector2) -> String:
	var best := ""
	var best_d := 1e9
	for id in npcs:
		var b: Control = npcs[id]
		var r := Rect2(_feet_x(b) - body_h() * 0.17, b.position.y, body_h() * 0.34, body_h())
		if r.has_point(p):
			var d := absf(p.x - _feet_x(b))
			if d < best_d:
				best = id
				best_d = d
	return best


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hover_id = _npc_at(e.position)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hover_id != "" else Control.CURSOR_ARROW
	elif e is InputEventMouseButton and e.pressed:
		var id := _npc_at(e.position)
		if e.button_index == MOUSE_BUTTON_LEFT:
			if id != "":
				pending_npc = id
				var nx := _feet_x(npcs[id])
				var side := -1.0 if _feet_x(player) < nx else 1.0
				player_target = clampf(nx + side * body_h() * 0.42, left_bound, right_bound)
			else:
				pending_npc = ""
				player_target = clampf(e.position.x, left_bound, right_bound)
		elif e.button_index == MOUSE_BUTTON_RIGHT and id != "":
			npc_menu.emit(id)
