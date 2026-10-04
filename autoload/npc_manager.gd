extends Node

signal conversation_changed(npc_id: String)
signal npc_thinking(npc_id: String, thinking: bool)
signal npc_replied(npc_id: String, data: Dictionary)

const Prompts = preload("res://ai/prompts.gd")
const ActionCheck = preload("res://ai/action_check.gd")
const MAX_HISTORY := 24
const MAX_MEMORIES := 25
const REL_KEYS := ["confianca", "afeto", "medo", "suspeita"]
const PRESENCIAL := "presencial"
const LIGACAO := "ligacao"
const MENSAGEM := "mensagem"

var npcs: Dictionary = {}
var state: Dictionary = {}
var talking_to: String = ""
var channel: String = PRESENCIAL
var busy: bool = false


func _ready() -> void:
	npcs = World._load_json("res://data/npcs.json")
	TimeManager.time_advanced.connect(_on_time_advanced)


func reset_state(origin: Dictionary) -> void:
	state.clear()
	talking_to = ""
	channel = PRESENCIAL
	busy = false
	var known: Array = origin.get("conhecidos", [])
	for id in npcs:
		var is_known: bool = id in known
		state[id] = {
			"confianca": 15 if is_known else 0,
			"afeto": 15 if is_known else 0,
			"medo": 0,
			"suspeita": 0 if is_known else 15,
			"memorias": ["O jogador é um rosto conhecido do bairro há anos; vocês se cumprimentam, mas nunca foram próximos."] if is_known else [],
			"historico": [],
			"vivo": true,
			"conheceu": is_known,
			"conhece_nome": false,
			"sabe_nome_jogador": is_known,
			"dinheiro": int(npcs[id]["dinheiro"]),
			"evita_ate": 0,
			"emocao": "neutro",
			"namoro": false,
			"bloqueado": false,
			"saude": 100,
			"pago": 0,
			"fora_ate": 0,
			"hospital_ate": 0,
			"preso_ate": 0,
		}


func location_of(npc_id: String, h: int = -1) -> String:
	var st: Dictionary = state.get(npc_id, {})
	var now := TimeManager.total_minutes
	if not st.is_empty():
		if not st.get("vivo", true) or now < int(st.get("preso_ate", 0)) or now < int(st.get("fora_ate", 0)):
			return ""
		if now < int(st.get("hospital_ate", 0)):
			return "hospital"
	if h < 0:
		h = TimeManager.hour()
	for slot in npcs[npc_id]["rotina"]:
		if World.hour_in_range(h, int(slot["de"]), int(slot["ate"])):
			return slot["local"]
	return ""


func is_asleep(npc_id: String) -> bool:
	var h := TimeManager.hour()
	var st: Dictionary = state[npc_id]
	if TimeManager.total_minutes < int(st.get("fora_ate", 0)):
		return false
	return location_of(npc_id) == "" and (h < 7 or h >= 23)


func is_home(npc_id: String) -> bool:
	var st: Dictionary = state[npc_id]
	return st.get("vivo", true) and location_of(npc_id) == "" and TimeManager.total_minutes >= int(st.get("preso_ate", 0)) and TimeManager.total_minutes >= int(st.get("fora_ate", 0))


# Uma "rodada" provocada pelo jogo (não é fala do jogador): ataques noturnos, reação a agressões etc.
func event_turn(id: String, narration: String, instruction: String) -> void:
	if busy or not GameState.active:
		return
	if talking_to != id:
		talking_to = id
		channel = PRESENCIAL
		state[id]["conheceu"] = true
		conversation_changed.emit(id)
	busy = true
	if narration != "":
		GameState.add_log(narration, "narration")
	var st: Dictionary = state[id]
	st["historico"].append({"role": "user", "content": "[EVENTO DO JOGO] " + instruction})
	npc_thinking.emit(id, true)
	var res := await _request(id, PRESENCIAL)
	npc_thinking.emit(id, false)
	busy = false
	if not res["ok"]:
		st["historico"].pop_back()
		GameState.add_log(res["error"], "error")
		return
	_apply_reply(id, Prompts.parse_npc_reply(res["text"]), PRESENCIAL)


func npcs_here() -> Array:
	var here := World.current_id()
	var out: Array = []
	for id in npcs:
		if state[id]["vivo"] and location_of(id) == here:
			out.append(id)
	return out


func display_name(npc_id: String) -> String:
	var n: Dictionary = npcs[npc_id]
	return n["nome"] if state[npc_id]["conhece_nome"] else n["apelido_visual"]


func relation_label(npc_id: String) -> String:
	var st: Dictionary = state[npc_id]
	if not st.get("vivo", true):
		return "Morto(a)"
	if st.get("namoro", false):
		return "Namorando"
	if st.get("bloqueado", false):
		return "Te bloqueou"
	var trust := int(st["confianca"])
	var love := int(st["afeto"])
	if trust <= -40 or love <= -40:
		return "Inimigo(a)"
	if love >= 65 and trust >= 45:
		return "Melhor amigo(a)"
	if love >= 35 and trust >= 25:
		return "Amigo(a)"
	if love <= -15 or trust <= -15:
		return "Não gosta de você"
	if st.get("conheceu", false):
		return "Conhecido(a)"
	return "Desconhecido(a)"


func start_conversation(npc_id: String) -> void:
	if busy or not GameState.active:
		return
	var st: Dictionary = state[npc_id]
	if TimeManager.total_minutes < int(st["evita_ate"]):
		GameState.add_log("%s vira o rosto e te ignora." % display_name(npc_id), "info")
		return
	talking_to = npc_id
	channel = PRESENCIAL
	st["conheceu"] = true
	GameState.add_log("Você se aproxima de %s (%s)." % [display_name(npc_id), npcs[npc_id]["aparencia"]], "info")
	conversation_changed.emit(npc_id)


func start_call(npc_id: String) -> void:
	talking_to = npc_id
	channel = LIGACAO
	GameState.add_log("Você está em ligação com %s." % display_name(npc_id), "phone")
	conversation_changed.emit(npc_id)


func end_conversation() -> void:
	if talking_to == "":
		return
	if channel == LIGACAO:
		GameState.add_log("Ligação encerrada.", "phone")
	talking_to = ""
	channel = PRESENCIAL
	conversation_changed.emit("")


func _request(id: String, chan: String, extra_user: String = "") -> Dictionary:
	var st: Dictionary = state[id]
	var messages: Array = [{"role": "system", "content": Prompts.npc_system(id, chan)}]
	messages.append_array(st["historico"].slice(-MAX_HISTORY))
	if extra_user != "":
		messages.append({"role": "user", "content": extra_user})
	var res: Dictionary = await AIService.chat(messages, 700)
	if res["ok"]:
		st["historico"].append({"role": "assistant", "content": res["text"]})
		if st["historico"].size() > MAX_HISTORY * 2:
			st["historico"] = st["historico"].slice(-MAX_HISTORY)
	return res


func talk(text: String, raw: bool = false) -> void:
	var id := talking_to
	text = text.strip_edges()
	if id == "" or busy or text == "" or not GameState.active:
		return
	var chan := channel
	var st: Dictionary = state[id]
	if not raw and chan == PRESENCIAL:
		var chk := ActionCheck.run(text)
		if chk["blocked"]:
			GameState.add_log(text, "player", GameState.player["name"])
			GameState.add_log(" ".join(chk["logs"]), "narration")
			TimeManager.advance(1)
			return
		for line in chk["logs"]:
			GameState.add_log(line, "info")
		text = chk["text"]
		if int(chk["pay"]) > 0:
			GameState.add_money(-int(chk["pay"]))
			st["dinheiro"] = int(st["dinheiro"]) + int(chk["pay"])
			st["pago"] = int(st.get("pago", 0)) + int(chk["pay"])
		for item_id in chk["consume"]:
			Economy.use_item(item_id)
	busy = true
	GameState.add_log(text, "player", GameState.player["name"])
	st["historico"].append({"role": "user", "content": ("[ao telefone] " if chan == LIGACAO else "") + text})
	TimeManager.advance(3)
	npc_thinking.emit(id, true)
	var res := await _request(id, chan)
	npc_thinking.emit(id, false)
	busy = false
	if not res["ok"]:
		st["historico"].pop_back()
		GameState.add_log(res["error"], "error")
		return
	_apply_reply(id, Prompts.parse_npc_reply(res["text"]), chan)


func text_reply(id: String, player_text: String) -> Dictionary:
	var st: Dictionary = state[id]
	st["historico"].append({"role": "user", "content": "[mensagem de celular] " + player_text})
	var res := await _request(id, MENSAGEM)
	if not res["ok"]:
		st["historico"].pop_back()
		return res
	var data := Prompts.parse_npc_reply(res["text"])
	_apply_reply(id, data, MENSAGEM)
	return {"ok": true, "data": data}


func spontaneous_message(id: String) -> Dictionary:
	var res := await _request(id, MENSAGEM, Prompts.spontaneous_instruction())
	if not res["ok"]:
		return res
	var data := Prompts.parse_npc_reply(res["text"])
	_apply_reply(id, data, MENSAGEM)
	return {"ok": true, "data": data}


func give_money(amount: int) -> void:
	if talking_to == "" or busy or amount <= 0 or channel != PRESENCIAL:
		return
	if GameState.money() < amount:
		GameState.add_log("Você não tem R$ %d." % amount, "info")
		return
	GameState.add_money(-amount)
	state[talking_to]["dinheiro"] = int(state[talking_to]["dinheiro"]) + amount
	state[talking_to]["pago"] = int(state[talking_to].get("pago", 0)) + amount
	talk("*entrega R$ %d em dinheiro*" % amount, true)


func give_item(item_id: String) -> void:
	if talking_to == "" or busy or channel != PRESENCIAL:
		return
	if not GameState.remove_item(item_id):
		return
	talk("*entrega %s*" % World.item_name(item_id).to_lower(), true)


func _apply_reply(id: String, data: Dictionary, chan: String = PRESENCIAL) -> void:
	var st: Dictionary = state[id]

	if data.get("revela_nome", false) and not st["conhece_nome"]:
		st["conhece_nome"] = true
		GameState.add_log("Agora você sabe o nome: %s." % npcs[id]["nome"], "event")
	if data.get("aprendeu_nome_jogador", false):
		st["sabe_nome_jogador"] = true

	var emo := str(data.get("emocao", "neutro")).to_lower().strip_edges()
	if not World.emotions.has(emo):
		emo = "neutro"
	st["emocao"] = emo

	if chan != MENSAGEM:
		var body := str(data.get("acao_corporal", "")).strip_edges()
		var speech := str(data.get("fala", "")).strip_edges()
		var line := ""
		if body != "" and chan == PRESENCIAL:
			line += "*" + body + "* "
		line += speech
		GameState.add_log(line.strip_edges(), "npc", display_name(id) + (" (ao telefone)" if chan == LIGACAO else ""))

	var rel = data.get("relacao", {})
	if typeof(rel) == TYPE_DICTIONARY:
		for k in REL_KEYS:
			if rel.has(k):
				var delta := clampi(int(rel[k]), -15, 15)
				var lo := 0 if k in ["medo", "suspeita"] else -100
				st[k] = clampi(int(st[k]) + delta, lo, 100)

	var mem := str(data.get("memoria", "")).strip_edges()
	if mem != "":
		st["memorias"].append("[%s] %s" % [TimeManager.clock_str(), mem])
		if st["memorias"].size() > MAX_MEMORIES:
			st["memorias"].pop_front()

	var acts = data.get("acoes", [])
	if typeof(acts) == TYPE_ARRAY:
		for a in acts:
			if typeof(a) == TYPE_DICTIONARY:
				_apply_action(id, a, chan)

	npc_replied.emit(id, data)


func _apply_action(id: String, a: Dictionary, chan: String) -> void:
	var st: Dictionary = state[id]
	var who := display_name(id)
	match str(a.get("tipo", "")):
		"dar_dinheiro":
			var v := mini(mini(int(a.get("valor", 0)), int(st["dinheiro"])), 500)
			if v > 0:
				st["dinheiro"] = int(st["dinheiro"]) - v
				GameState.add_money(v)
				if chan == PRESENCIAL:
					GameState.add_log("%s te deu R$ %d." % [who, v], "event")
				else:
					PhoneSystem.log_bank("PIX recebido de %s" % who, v)
					GameState.add_log("PIX recebido de %s: R$ %d." % [who, v], "phone")
		"dar_item":
			var item := str(a.get("item", ""))
			if World.items.has(item) and chan == PRESENCIAL:
				GameState.add_item(item)
				GameState.add_log("%s te deu: %s." % [who, World.item_name(item)], "event")
		"alugar_quarto":
			if chan == PRESENCIAL:
				_rent_room(id)
		"vender":
			if chan == PRESENCIAL:
				_sell(id, str(a.get("item", "")))
		"dar_numero":
			if not PhoneSystem.has_contact(id):
				PhoneSystem.add_contact(id)
				GameState.add_log("%s te passou o número de celular." % display_name(id), "phone")
		"comecar_namoro":
			if not st.get("namoro", false) and int(st["afeto"]) >= 40:
				st["namoro"] = true
				GameState.add_log("Você e %s estão namorando." % who, "event")
		"terminar_namoro":
			if st.get("namoro", false):
				st["namoro"] = false
				st["afeto"] = mini(int(st["afeto"]), 10)
				GameState.add_log("%s terminou com você." % who, "danger")
		"bloquear":
			if not st.get("bloqueado", false):
				st["bloqueado"] = true
				GameState.add_log("%s te bloqueou no celular." % who, "danger")
				if chan == LIGACAO:
					end_conversation()
		"ir_embora":
			if chan == PRESENCIAL:
				st["evita_ate"] = TimeManager.total_minutes + 180
				GameState.add_log("%s encerra a conversa e se afasta." % who, "event")
				end_conversation()
			elif chan == LIGACAO:
				GameState.add_log("%s desligou na sua cara." % who, "event")
				end_conversation()
		"atacar":
			if chan == PRESENCIAL and location_of(id) == World.current_id():
				var dmg := clampi(int(a.get("dano", 10)), 5, 40)
				GameState.add_log("%s te ataca! (-%d de saúde)" % [who, dmg], "danger")
				CrimeSystem.npc_attacked_player(id)
				NeedsSystem.apply({"saude": -dmg, "sanidade": -10}, "atacado por %s" % npcs[id]["nome"])
		"fugir":
			if chan == PRESENCIAL:
				st["fora_ate"] = TimeManager.total_minutes + 240
				GameState.add_log("%s sai correndo e some de vista." % who, "event")
				end_conversation()
		"chamar_policia":
			GameState.add_log("%s chama a polícia." % who, "danger")
			CrimeSystem.npc_called_police(id)


# A pessoa entrega a chave pelo diálogo; o jogo confere se o pagamento foi feito de verdade.
func _rent_room(id: String) -> void:
	var st: Dictionary = state[id]
	var svc: Dictionary = npcs[id].get("servicos", {}).get("alugar_quarto", {})
	if svc.is_empty() or location_of(id) != World.current_id():
		return
	var price := int(svc["preco"])
	var paid := int(st.get("pago", 0))
	if paid < price:
		GameState.add_log("%s não entrega a chave: o quarto custa R$ %d por noite e você só pagou R$ %d." % [display_name(id), price, paid], "info")
		return
	var nights := mini(paid / price, int(svc.get("noites_max", 7)))
	st["pago"] = paid - nights * price
	World.grant_key(str(svc["chave"]), nights)
	st["memorias"].append("[%s] Aluguei o quarto para o jogador por %d noite(s). Recebi R$ %d." % [TimeManager.clock_str(), nights, nights * price])
	GameState.add_log("%s te entrega uma chave de ferro enferrujada. Quarto alugado por %d noite(s) (R$ %d)." % [display_name(id), nights, nights * price], "event")
	GameState.add_log("Agora aparece a opção de entrar no seu quarto aqui na pensão.", "event")


func _sell(id: String, item_id: String) -> void:
	var st: Dictionary = state[id]
	var here: Dictionary = World.locations.get(location_of(id), {})
	if not npcs[id].get("vende", false) or not World.items.has(item_id) or not item_id in here.get("loja", []):
		return
	var price := int(World.items[item_id]["preco"])
	if int(st.get("pago", 0)) < price:
		GameState.add_log("%s não entrega: %s custa R$ %d e você ainda não pagou." % [display_name(id), World.item_name(item_id), price], "info")
		return
	st["pago"] = int(st["pago"]) - price
	GameState.add_item(item_id)
	GameState.add_log("%s te entrega: %s." % [display_name(id), World.item_name(item_id)], "event")


func _on_time_advanced(_minutes: int, _sleeping: bool) -> void:
	if talking_to != "" and channel == PRESENCIAL and location_of(talking_to) != World.current_id():
		GameState.add_log("%s vai embora." % display_name(talking_to), "info")
		end_conversation()


func to_dict() -> Dictionary:
	return {"state": state}


func from_dict(d: Dictionary) -> void:
	state = d["state"]
	for id in state:
		var st: Dictionary = state[id]
		for k in ["namoro", "bloqueado"]:
			if not st.has(k):
				st[k] = false
		for k in ["fora_ate", "hospital_ate", "preso_ate"]:
			if not st.has(k):
				st[k] = 0
		if not st.has("saude"):
			st["saude"] = 100
		if not st.has("pago"):
			st["pago"] = 0
		if not st.has("conheceu"):
			st["conheceu"] = not st["historico"].is_empty()
	talking_to = ""
	channel = PRESENCIAL
	busy = false
