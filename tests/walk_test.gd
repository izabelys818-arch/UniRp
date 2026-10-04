extends Node

# Anda de verdade pelo mundo 3D: sai de um prédio, volta a entrar, conversa com gente na rua.

const UITheme = preload("res://ui/ui_theme.gd")
var fails: Array = []


func check(c: bool, m: String) -> void:
	if not c:
		fails.append(m)
		printerr("FALHOU: ", m)


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	SaveManager.path = "user://test_save.json"
	WorldEvents.random_enabled = false
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x",
		"look": {"pele": 2, "cabelo": 0, "cor_cabelo": 0, "barba": 1, "roupa": 2, "marcas": []},
		"appearance_extra": "", "backstory": "", "traits": [],
		"origin": origin["id"], "money": 1200, "location": "lanchonete",
		"home": "apartamento", "inventory": {}, "alive": true,
	})
	TimeManager.total_minutes = 10 * 60
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var screen = preload("res://ui/game_screen.gd").new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	for i in 10:
		await get_tree().process_frame
	var wv = screen.world_view
	var lot := "lanchonete"
	check(wv.layout.in_building(lot, wv._p2()), "começa dentro da lanchonete")
	# sai
	wv._go_to(wv.layout.door_out(lot) + Vector2(0, 6))
	await _walk(wv, 400)
	check(not wv.layout.in_building(lot, wv._p2()), "saiu do prédio (%s)" % wv._p2())
	check(World.current_id() != "" , "tem local")
	# volta a entrar clicando dentro
	var inside: Vector2 = wv.layout.door_in(lot) + Vector2(0, -2)
	wv._go_to(inside)
	await _walk(wv, 600)
	print("DBG door disabled=", wv.city.loc_info[lot]["door"].disabled, " locked=", wv._door_locked.get(lot), " cur=", World.current_id(), " pos=", wv.player.position, " vel=", wv.player.velocity, " b=", wv.layout.lots[lot]["building"], " path=", wv.path)
	check(wv.layout.in_building(lot, wv._p2()), "voltou a entrar (%s, alvo %s)" % [wv._p2(), inside])
	# sai de novo e entra pelo mapa
	wv._go_to(wv.layout.door_out(lot) + Vector2(0, 6))
	await _walk(wv, 400)
	World.request_travel(lot, "ape")
	await _walk(wv, 600)
	check(wv.layout.in_building(lot, wv._p2()), "entrou pelo mapa (%s)" % wv._p2())
	print("RESULTADO WALK: ", "OK" if fails.is_empty() else "%d falha(s)" % fails.size())
	SaveManager.delete_save()
	get_tree().quit(0 if fails.is_empty() else 1)


func _walk(wv, frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
		if wv.path.is_empty():
			break
