extends Node

# Vida social e mundo vivo: repetição irrita até xingar e ir embora; relação muda de patamar com
# aviso; flerte estando namorando vira fofoca que chega no parceiro; parabéns no aniversário;
# feriados fecham o comércio; Dia dos Namorados; crianças e bebês na cidade; violência contra
# criança bloqueada; imobiliária anuncia casas vazias da cidade.
# Uso: godot --path . res://tests/social_test.tscn

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("OK     " if ok else "FALHOU ") + what)
	if not ok:
		fails += 1


func _mock(_m: Array) -> Dictionary:
	return {"ok": true, "text": JSON.stringify({"fala": "Hm, entendi.", "emocao": "neutro", "relacao": {}})}


func _game() -> void:
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({
		"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x",
		"look": {}, "appearance_extra": "", "backstory": "", "traits": [], "cenario": "porto_cinza",
		"origin": origin["id"], "money": 5000, "location": "praca", "home": "apartamento", "inventory": {"pao": 2}, "alive": true,
	})
	TimeManager.total_minutes = 2 * 1440 + 10 * 60
	TimeManager.days_per_month = 7
	TimeManager.aging = true
	TimeManager.new_calendar()
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	AgingSystem.reset()


# o jogador vai até onde a pessoa está (conversa presencial só vale no mesmo lugar)
func _meet(id: String) -> void:
	var where := NPCManager.location_of(id)
	if where != "":
		GameState.player["location"] = where


func _talk(id: String, text: String) -> void:
	_meet(id)
	if NPCManager.talking_to != id:
		NPCManager.start_conversation(id)
	NPCManager.talk(text)
	var t0 := Time.get_ticks_msec()
	while NPCManager.busy and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame


func _last_npc_line() -> String:
	for i in range(GameState.log_entries.size() - 1, -1, -1):
		if str(GameState.log_entries[i]["kind"]) == "npc":
			return str(GameState.log_entries[i]["text"])
	return ""


func _logs_since(n: int) -> String:
	return " | ".join(GameState.log_entries.slice(n).map(func(e): return str(e["text"])))


func _skip_day() -> void:
	for i in 4:
		NeedsSystem.reset({})
		TimeManager.advance(360)


func _ready() -> void:
	preload("res://world3d/world_view.gd").realtime = false
	WorldEvents.random_enabled = false
	AIService.mock = _mock
	Settings.local_dialogue = true
	_game()
	var ids: Array = NPCManager.npcs.keys().filter(func(k): return not str(k).begins_with("g") and NPCManager.location_of(k) != "")
	var a: String = ids[0]
	var b: String = ids[1]
	var c: String = ids[2]
	var d: String = ids[3]
	# --- repetição ---
	NPCManager.state[a]["evita_ate"] = 0
	var love0 := int(NPCManager.state[a]["afeto"])
	var lines: Array = []
	for i in 5:
		await _talk(a, "você viu o jogo de ontem no bar?")
		lines.append(_last_npc_line())
	print("REPETIÇÃO: ", lines)
	check(lines[1].find("falou") >= 0 or lines[1].find("De novo") >= 0 or lines[1].find("acabou de dizer") >= 0, "2ª vez: avisa que já ouviu")
	check(NPCManager.state[a]["emocao"] != "neutro", "fica com outra cara")
	var cursed: bool = lines[3].find("orra") >= 0 or lines[3].find("aralho") >= 0 or lines[3].find("inferno") >= 0 or lines[3].find("surdo") >= 0
	check(cursed, "4ª vez: xinga (%s)" % lines[3])
	check(NPCManager.talking_to == "" and int(NPCManager.state[a]["evita_ate"]) > TimeManager.total_minutes, "5ª vez: vai embora e evita o jogador")
	check(int(NPCManager.state[a]["afeto"]) < love0 - 15, "relação piorou (afeto %d → %d)" % [love0, int(NPCManager.state[a]["afeto"])])
	# --- patamar da relação ---
	NPCManager.state[b]["afeto"] = 33
	NPCManager.state[b]["confianca"] = 24
	var n0 := GameState.log_entries.size()
	NPCManager._apply_reply(b, {"fala": "Gosto de você.", "emocao": "feliz", "relacao": {"afeto": 5, "confianca": 3}})
	check(_logs_since(n0).find("agora são amigos") >= 0, "virou amigo e o jogo avisa")
	# --- flerte namorando vira fofoca ---
	NPCManager.state[c]["namoro"] = true
	NPCManager.state[c]["afeto"] = 70
	NPCManager.state[c]["confianca"] = 60
	PhoneSystem.add_contact(c)
	NPCManager.nearby = [d]
	NPCManager.nearby_loc = World.current_id()
	SocialSystem.on_player_speech(b, "*flerta, com um meio sorriso*", NPCManager.PRESENCIAL)
	var rs: Array = SocialSystem.data()["rumores"]
	check(rs.size() == 1 and b in rs[0]["sabem"] and d in rs[0]["sabem"], "flerte virou fofoca: sabem %s" % str(rs[0]["sabem"] if rs.size() > 0 else []))
	check(NPCManager.state[d]["memorias"].back().find("deu em cima") >= 0, "a testemunha guarda na memória")
	var n1 := GameState.log_entries.size()
	var steps := 0
	while not rs[0]["fim"] and steps < 3000:
		SocialSystem._spread_hour()
		steps += 1
	print("FOFOCA chegou no parceiro depois de %d horas; sabem: %d pessoas" % [steps, rs[0]["sabem"].size()])
	check(rs[0]["fim"], "a fofoca chegou no parceiro")
	check(int(NPCManager.state[c]["suspeita"]) >= 30 and int(NPCManager.state[c]["afeto"]) < 70, "parceiro desconfia e fica magoado")
	check(_logs_since(n1).find("ficou sabendo") >= 0, "o jogo avisa que o parceiro soube")
	check(PhoneSystem.thread(c).size() > 0, "o parceiro manda mensagem cobrando: %s" % (str(PhoneSystem.thread(c).back()["texto"]) if PhoneSystem.thread(c).size() > 0 else ""))
	# parceiro presente vê na hora
	NPCManager.state[c]["afeto"] = 70
	NPCManager.state[c]["namoro"] = true
	NPCManager.nearby = [c]
	var n2 := GameState.log_entries.size()
	SocialSystem.on_player_speech(b, "quer sair comigo hoje?", NPCManager.PRESENCIAL)
	check(_logs_since(n2).find("ficou sabendo") >= 0, "parceiro que está perto vê o flerte na hora")
	NPCManager.nearby = []
	# --- aniversário ---
	var today := TimeManager.date()
	NPCManager.npcs[d]["nascimento"] = {"m": int(today["m"]), "d": AgingSystem.canonical_day(int(today["d"]), 7)}
	check(SocialSystem.is_birthday(d), "hoje é aniversário de %s" % d)
	NPCManager.state[d]["evita_ate"] = 0
	var love_d := int(NPCManager.state[d]["afeto"])
	await _talk(d, "Feliz aniversário! Parabéns!")
	check(int(NPCManager.state[d]["afeto"]) >= love_d + 8 and NPCManager.state[d]["emocao"] == "feliz", "parabéns alegra (afeto %d → %d): %s" % [love_d, int(NPCManager.state[d]["afeto"]), _last_npc_line()])
	check(SocialSystem.party_location(d, 20) in ["bar", "praca"], "comemora à noite: %s" % SocialSystem.party_location(d, 20))
	NPCManager.end_conversation()
	# --- feriados ---
	var natal := Holidays.date_of("natal")
	var tira := Holidays.date_of("tiradentes")
	var vesp := Holidays.date_of("vespera_natal")
	check(natal.x == 11 and vesp.x == 11 and natal != vesp, "Natal e véspera em dias diferentes de dezembro (%s, %s)" % [str(vesp), str(natal)])
	var y := int(TimeManager.date()["y"])
	TimeManager.total_minutes = (TimeManager.game_day_of(y, tira.x, tira.y) - 1) * 1440 + 10 * 60
	check(Holidays.label_today() == "Tiradentes", "hoje é %s" % Holidays.label_today())
	check(World.is_open("mercado", 10) and not World.is_open("mercado", 15), "Tiradentes: mercado só de manhã (8h–14h)")
	check(World.is_open("hospital", 15) and World.is_open("praca", 15), "hospital e praça não fecham")
	TimeManager.total_minutes = (TimeManager.game_day_of(y, natal.x, natal.y) - 1) * 1440 + 10 * 60
	check(not World.is_open("mercado", 10) and not World.is_open("lanchonete", 12) and not World.is_open("bar", 20), "Natal: comércio e bar fechados")
	var worker := ""
	for id in NPCManager.npcs:
		for slot in NPCManager.npcs[id]["rotina"]:
			if str(slot["local"]) == "mercado" and World.hour_in_range(10, int(slot["de"]), int(slot["ate"])):
				worker = id
	if worker != "":
		check(NPCManager.location_of(worker, 10) != "mercado", "no Natal quem ia ao mercado passeia ou fica em casa (%s → %s)" % [worker, NPCManager.location_of(worker, 10)])
	TimeManager.total_minutes = (TimeManager.game_day_of(y, vesp.x, vesp.y) - 1) * 1440 + 10 * 60
	check(World.is_open("mercado", 10) and not World.is_open("mercado", 17), "véspera de Natal: mercado fecha às 16h")
	# --- Dia dos Namorados ---
	var nam := Holidays.date_of("namorados")
	SocialSystem.data()["ultimo_dia"] = TimeManager.day()
	TimeManager.total_minutes = (TimeManager.game_day_of(y + 1, nam.x, nam.y) - 1) * 1440 + 10 * 60
	SocialSystem.data()["ultimo_dia"] = TimeManager.day()
	SocialSystem.data()["ultima_hora"] = TimeManager.total_minutes / 60
	NPCManager.state[c]["namoro"] = true
	NPCManager.state[c]["afeto"] = 60
	SocialSystem.data()["rumores"] = []
	_skip_day()
	check(int(NPCManager.state[c]["afeto"]) <= 48, "esqueceu o Dia dos Namorados: parceiro magoado (afeto 60 → %d)" % int(NPCManager.state[c]["afeto"]))
	# --- crianças e bebês ---
	var kid := Population.generate_young()
	check(int(kid["npc"]["idade"]) < 18 and (str(kid["npc"]["apelido_visual"]).begins_with("Menin") or str(kid["npc"]["apelido_visual"]).begins_with("Adolescente")), "morador criança/adolescente: %s, %d anos" % [kid["npc"]["apelido_visual"], int(kid["npc"]["idade"])])
	var kid_id := Population.add_resident(kid, false)
	TimeManager.total_minutes = (TimeManager.day() - 1) * 1440 + 15 * 60
	_meet(kid_id)
	var n3 := GameState.log_entries.size()
	var t0 := Time.get_ticks_msec()
	while NPCManager.busy and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	CrimeSystem.player_attack(kid_id)
	check(_logs_since(n3).find("criança") >= 0, "violência contra criança bloqueada")
	var before := Population.count()
	Population.populate(2)
	var new_ids: Array = Population.residents().keys().slice(before)
	var young := new_ids.filter(func(k): return int(NPCManager.npcs[k]["idade"]) < 18).size()
	var babies := new_ids.filter(func(k): return NPCManager.npcs[k].has("bebe")).size()
	check(young >= 1, "começo de jogo traz criança/adolescente na cidade")
	print("bebês no populate: ", babies)
	# --- imobiliária ---
	for i in 30:
		Houses.register("casa_teste_%d" % i, "Casa %d, Rua das Flores" % (100 + i * 2), 9000 + i * 37)
	HomeSystem.list_city_houses()
	var listed: Array = HomeSystem.imoveis.keys().filter(func(k): return str(k).begins_with("casa_teste"))
	check(listed.size() >= 2, "imobiliária anuncia casas vazias da cidade (%d)" % listed.size())
	var rentable: Array = listed.filter(func(k): return HomeSystem.imoveis[k].has("aluguel"))
	if not rentable.is_empty():
		var hid: String = rentable[0]
		check(HomeSystem.rent(hid), "alugou %s" % hid)
		check(not Houses.locked(hid) and Houses.inside_actions().size() >= 0, "a casa alugada fica aberta para o jogador")
	var region = preload("res://world3d/city_layout.gd").new()
	region.ensure_chunk(Vector2i(4, 2))
	region.ensure_chunk(Vector2i(5, 2))
	var path: Array = region._astar(Vector2i(7, 4), Vector2i(11, 4))
	check(not path.is_empty() and path.back() == Vector2i(11, 4), "grafo de rotina costurado além da grade antiga")
	print("RESULTADO SOCIAL: ", "OK" if fails == 0 else "%d falha(s)" % fails)
	get_tree().quit()
