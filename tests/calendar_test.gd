extends Control

# Calendário, aniversários e envelhecimento: data na UI, aniversário do jogador e de um contato,
# troca de faixa de idade, troca de ritmo sem pular a data, save/load e save antigo sem calendário.
# Uso: godot --path . res://tests/calendar_test.tscn

const UITheme = preload("res://ui/ui_theme.gd")
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("OK     " if ok else "FALHOU ") + what)
	if not ok:
		fails += 1


func _new_game(age: int) -> void:
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Lia", "age": age, "gender": "mulher", "appearance": "x",
		"look": {"pele": 2, "cabelo": 4, "cor_cabelo": 1, "barba": 0, "roupa": 8, "marcas": []},
		"appearance_extra": "", "backstory": "", "traits": [], "cenario": "porto_cinza",
		"origin": origin["id"], "money": 300, "location": "apartamento", "home": "apartamento", "inventory": {}, "alive": true,
	})
	TimeManager.total_minutes = 8 * 60
	TimeManager.days_per_month = 7
	TimeManager.aging = true
	TimeManager.new_calendar()
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	AgingSystem.reset()


# avança dia a dia mantendo o personagem alimentado (o teste é do calendário, não da fome)
func _skip(minutes: int) -> void:
	while minutes > 0:
		var step := mini(minutes, 360)
		NeedsSystem.reset({})
		TimeManager.advance(step)
		minutes -= step


func _ready() -> void:
	AIService.mock = _stream_mock
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	SaveManager.path = "user://calendario_save.json"
	_new_game(12)
	var d := TimeManager.date()
	check(int(d["y"]) == 2026 and int(d["m"]) == 2 and int(d["d"]) == 1, "jogo novo começa em 1º de março de 2026 (%s)" % TimeManager.date_str())
	check(TimeManager.short_date_str() == "Seg, 1 de mar", "data curta do HUD: %s" % TimeManager.short_date_str())
	# meses de 7 dias: 7 dias depois é 1º de abril
	_skip(7 * 1440)
	check(TimeManager.date_str() == "1 de abril de 2026", "7 dias depois: %s" % TimeManager.date_str())
	# aniversário do jogador amanhã: 12 → 13 (vira adolescente)
	var tomorrow := TimeManager.date_of(TimeManager.day() + 1)
	GameState.player["nascimento"] = {"m": int(tomorrow["m"]), "d": AgingSystem.canonical_day(int(tomorrow["d"]), TimeManager.days_per_month)}
	check(AgingSystem.days_until_birthday("") == 1, "aniversário marcado para amanhã (%d dia)" % AgingSystem.days_until_birthday(""))
	var stages: Array = []
	AgingSystem.stage_changed.connect(func(id, st): stages.append([id, st]))
	var logs_before := GameState.log_entries.size()
	_skip(1440)
	check(GameState.age() == 13, "fez aniversário: 12 → %d" % GameState.age())
	check(GameState.age_stage() == "adolescente" and stages.size() >= 1 and stages[0] == ["", "adolescente"], "mudou de faixa: criança → adolescente")
	var texts: Array = GameState.log_entries.slice(logs_before).map(func(e): return str(e["text"]))
	check(texts.any(func(t): return "aniversário" in t), "mensagem de aniversário no jogo")
	check(GameState.is_minor(), "13 anos conta como menor de idade")
	# contato faz aniversário (idade vai para o estado salvo do NPC)
	var cid := ""
	for id in NPCManager.npcs:
		if not str(id).begins_with("g"):
			cid = id
			break
	PhoneSystem.add_contact(cid)
	var npc_age := int(NPCManager.npcs[cid]["idade"])
	var t2 := TimeManager.date_of(TimeManager.day() + 2)
	NPCManager.npcs[cid]["nascimento"] = {"m": int(t2["m"]), "d": AgingSystem.canonical_day(int(t2["d"]), 7)}
	_skip(2 * 1440)
	check(int(NPCManager.npcs[cid]["idade"]) == npc_age + 1 and int(NPCManager.state[cid].get("idade", 0)) == npc_age + 1, "contato %s fez aniversário: %d → %d" % [cid, npc_age, int(NPCManager.npcs[cid]["idade"])])
	# troca de ritmo não pula a data
	var before := TimeManager.date_str()
	TimeManager.set_days_per_month(28)
	check(TimeManager.date_str() == before, "trocar para meses de 28 dias mantém a data (%s)" % TimeManager.date_str())
	TimeManager.set_days_per_month(3)
	var d3 := TimeManager.date()
	check(int(d3["m"]) == int(TimeManager.date_of_index(TimeManager.index_of_date(int(d3["y"]), int(d3["m"]), 1))["m"]), "meses de 3 dias: mesmo mês (%s)" % TimeManager.date_str())
	TimeManager.set_days_per_month(7)
	# save / load
	var date_saved := TimeManager.date_str()
	var age_saved := GameState.age()
	var birth_saved: Dictionary = GameState.player["nascimento"].duplicate()
	check(SaveManager.save_game(), "salvou")
	TimeManager.total_minutes = 0
	TimeManager.new_calendar()
	GameState.player["age"] = 99
	check(SaveManager.load_game(), "carregou")
	check(TimeManager.date_str() == date_saved, "data preservada no save (%s)" % TimeManager.date_str())
	var nb: Dictionary = GameState.player["nascimento"]
	check(GameState.age() == age_saved and int(nb["m"]) == int(birth_saved["m"]) and int(nb["d"]) == int(birth_saved["d"]), "idade e nascimento preservados (%d)" % GameState.age())
	check(int(NPCManager.npcs[cid]["idade"]) == npc_age + 1, "idade nova do contato preservada no save (%d)" % int(NPCManager.npcs[cid]["idade"]))
	var prev := SaveManager.preview()
	check(str(prev.get("date", "")) != "", "tela inicial mostra a data do save (%s)" % str(prev.get("date", "")))
	# save antigo (sem calendário nem nascimento) carrega e começa em março de 2026
	var raw = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.path))
	raw.erase("calendar")
	raw["game"]["player"].erase("nascimento")
	var f := FileAccess.open(SaveManager.path, FileAccess.WRITE)
	f.store_string(JSON.stringify(raw))
	f.close()
	check(SaveManager.load_game(), "save antigo (sem calendário) carrega")
	var od := TimeManager.date()
	check(int(od["y"]) == 2026 and int(od["m"]) >= 2, "save antigo ganha data a partir de março de 2026 (%s)" % TimeManager.date_str())
	check(AgingSystem.birthday_str("") != "", "save antigo ganha um aniversário estável (%s)" % AgingSystem.birthday_str(""))
	# envelhecimento desligado: a festa acontece, a idade não muda
	TimeManager.aging = false
	var t3 := TimeManager.date_of(TimeManager.day() + 1)
	GameState.player["nascimento"] = {"m": int(t3["m"]), "d": AgingSystem.canonical_day(int(t3["d"]), 7)}
	var a0 := GameState.age()
	_skip(1440)
	check(GameState.age() == a0, "sem envelhecimento: idade fica em %d" % GameState.age())
	TimeManager.aging = true
	# app de calendário no celular
	var ui_root := Control.new()
	ui_root.theme = UITheme.build()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ui_root)
	var phone := preload("res://ui/phone/phone_panel.gd").new()
	ui_root.add_child(phone)
	phone.open("calendar")
	for i in 10:
		await get_tree().process_frame
	check(phone.title_label.text == "Calendário", "app Calendário abre no celular")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path := OS.get_user_data_dir() + "/calendario_celular.png"
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", path)
	phone.open("home")
	for i in 4:
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/calendario_home.png")
	print("RESULTADO CALENDARIO: ", "OK" if fails == 0 else "%d falha(s)" % fails)
	SaveManager.delete_save()
	get_tree().quit()


func _stream_mock(_messages: Array) -> Dictionary:
	return {"ok": true, "text": "{\"fala\":\"Tudo bem.\",\"emocao\":\"neutro\"}"}
