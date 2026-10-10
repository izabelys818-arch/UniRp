extends Node

# Bloqueios por idade: jogador adolescente não compra bebida, não usa droga, não comete crime,
# não é contratado, não assina contrato, não dirige e não namora; a IA recebe as regras.
# Uso: godot --path . res://tests/age_rules_test.tscn

const Prompts = preload("res://ai/prompts.gd")
const Local = preload("res://ai/local_dialogue.gd")
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("OK     " if ok else "FALHOU ") + what)
	if not ok:
		fails += 1


func _game(age: int) -> void:
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Duda", "age": age, "gender": "mulher", "appearance": "x",
		"look": {}, "appearance_extra": "", "backstory": "", "traits": [], "cenario": "porto_cinza",
		"origin": origin["id"], "money": 2000, "location": "rua", "home": "", "car": "Gol 2009", "inventory": {"droga": 1}, "alive": true,
	})
	TimeManager.total_minutes = 2 * 1440 + 20 * 60
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)


func _shop_with(item: String) -> String:
	for id in World.locations:
		if item in World.locations[id].get("loja", []) and World.shop_open(id):
			return id
	return ""


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	_game(15)
	check(GameState.is_minor() and GameState.age_stage() == "adolescente", "15 anos: adolescente, menor de idade")
	var bar := _shop_with("cerveja")
	check(bar != "", "achou um lugar que vende cerveja aberto (%s)" % bar)
	GameState.player["location"] = bar
	var money := GameState.money()
	Economy.buy("cerveja")
	check(GameState.item_count("cerveja") == 0 and GameState.money() == money, "não compra cerveja")
	check(str(GameState.log_entries.back()["text"]).find("maior de idade") >= 0, "aviso: %s" % str(GameState.log_entries.back()["text"]))
	var agua_shop := _shop_with("agua")
	if agua_shop != "":
		GameState.player["location"] = agua_shop
		Economy.buy("agua")
		check(GameState.item_count("agua") == 1, "água continua liberada")
	Economy.use_item("droga")
	check(GameState.item_count("droga") == 1, "não usa droga")
	# ações de crime somem da lista
	var crime_spot := ""
	for id in World.locations:
		if World.locations[id].has("arrombavel") or not World.locations[id].get("casas", []).is_empty():
			crime_spot = id
			break
	GameState.player["location"] = crime_spot
	TimeManager.total_minutes = 3 * 1440 + 3 * 60
	var ids: Array = Economy.available_actions().map(func(a): return str(a["id"]))
	check(not ids.any(func(i): return i == "arrombar" or i.begins_with("invadir:")), "sem arrombar/invadir na lista em %s" % crime_spot)
	CrimeSystem.break_into_shop(crime_spot)
	check(str(GameState.log_entries.back()["text"]).find("crime bloqueado") >= 0, "arrombar direto é recusado")
	# contrato, carro, namoro
	var rentable := ""
	for id in HomeSystem.imoveis:
		rentable = id
		break
	if rentable != "":
		check(not HomeSystem.rent(rentable), "não aluga imóvel (%s)" % rentable)
	var opts: Array = World.travel_options("praca" if World.locations.has("praca") else World.locations.keys()[0])
	var car_opt: Array = opts.filter(func(o): return o["mode"] == "carro")
	check(not car_opt.is_empty() and not car_opt[0]["ok"], "carro aparece mas não pode dirigir")
	var nid: String = NPCManager.npcs.keys()[0]
	NPCManager.state[nid]["afeto"] = 90
	NPCManager._apply_action(nid, {"tipo": "comecar_namoro"}, NPCManager.PRESENCIAL)
	check(not NPCManager.state[nid].get("namoro", false), "não começa namoro com menor")
	# IA e respostas locais
	var sys := Prompts.minor_rules(GameState.age(), 40)
	check(sys.find("MENOR DE IDADE") >= 0 and sys.find("nunca flerte") >= 0, "prompt da IA leva as regras para menor")
	check(Prompts.player_visible_description(GameState.player).begins_with("adolescente"), "NPC vê uma adolescente: %s" % Prompts.player_visible_description(GameState.player).substr(0, 40))
	var line := Local._pick_line("flerte", "intimo", {"jog": "Duda"}, {})
	check(line != "" and (line.find("nov") >= 0 or line.find("criança") >= 0 or line.find("idade") >= 0), "resposta local ao flerte recusa: %s" % line)
	# adulto: tudo volta a funcionar
	_game(30)
	GameState.player["location"] = bar
	Economy.buy("cerveja")
	check(GameState.item_count("cerveja") == 1, "adulto compra cerveja normalmente")
	check(Prompts.minor_rules(30, 40) == "", "adulto: nenhuma regra extra no prompt")
	print("RESULTADO IDADE: ", "OK" if fails == 0 else "%d falha(s)" % fails)
	get_tree().quit()
