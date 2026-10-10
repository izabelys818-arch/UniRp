extends Node

# Celular com a vida social: cobrança do parceiro depois da fofoca, parabéns dos amigos no seu
# aniversário, calendário de dezembro com feriados e a imobiliária com as casas da cidade.
# Uso: godot --path . res://tests/social_shots.tscn

const UITheme = preload("res://ui/ui_theme.gd")


func _mock(_m: Array) -> Dictionary:
	return {"ok": true, "text": JSON.stringify({"fala": "Hm.", "emocao": "neutro", "relacao": {}})}


func _shot(name: String) -> void:
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := OS.get_user_data_dir() + "/social_%s.png" % name
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	AIService.mock = _mock
	SaveManager.path = "user://social_save.json"
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x",
		"look": {"pele": 2, "cabelo": 0, "cor_cabelo": 0, "barba": 1, "roupa": 2, "marcas": []},
		"appearance_extra": "", "backstory": "", "traits": [], "cenario": "porto_cinza",
		"origin": origin["id"], "money": 3000, "location": "praca", "home": "apartamento", "inventory": {}, "alive": true,
	})
	TimeManager.total_minutes = 1440 * 2 + 10 * 60
	TimeManager.days_per_month = 7
	TimeManager.new_calendar()
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	AgingSystem.reset()
	var root := Control.new()
	root.theme = UITheme.build()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var screen = preload("res://ui/game_screen.gd").new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	for i in 30:
		await get_tree().process_frame
	var ids: Array = NPCManager.npcs.keys()
	var partner: String = ids[2]
	var friend: String = ids[3]
	var target: String = ids[1]
	for k in [partner, friend]:
		PhoneSystem.add_contact(k)
		NPCManager.state[k]["conhece_nome"] = true
	NPCManager.state[partner]["namoro"] = true
	NPCManager.state[partner]["afeto"] = 70
	NPCManager.state[friend]["afeto"] = 45
	NPCManager.state[friend]["confianca"] = 30
	# flerte com outra pessoa estando namorando: a fofoca anda e chega no parceiro
	NPCManager.nearby = [friend]
	NPCManager.nearby_loc = World.current_id()
	SocialSystem.on_player_speech(target, "*flerta, com um meio sorriso*", NPCManager.PRESENCIAL)
	NPCManager.nearby = []
	var guard := 0
	while not SocialSystem.data()["rumores"][0]["fim"] and guard < 2000:
		SocialSystem._spread_hour()
		guard += 1
	# aniversário do jogador: os amigos mandam parabéns
	AgingSystem.birthday.emit("", 31)
	var phone = screen.phone
	phone.open("thread", partner)
	await _shot("cobranca_parceiro")
	phone.open("thread", friend)
	await _shot("parabens_amigo")
	# dezembro: véspera de Natal, Natal e réveillon no calendário
	var y := int(TimeManager.date()["y"])
	var natal: Vector2i = Holidays.date_of("natal")
	TimeManager.total_minutes = (TimeManager.game_day_of(y, natal.x, natal.y) - 1) * 1440 + 10 * 60
	phone.open("calendar")
	await _shot("calendario_natal")
	phone.open("homes")
	await _shot("imobiliaria")
	phone.close()
	await _shot("hud_natal")
	SaveManager.delete_save()
	get_tree().quit()
