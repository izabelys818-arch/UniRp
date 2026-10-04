extends Node

const HOSPITAL_CARE := 150


func available_actions() -> Array:
	var loc := World.current()
	var out: Array = [{"id": "esperar", "label": "Esperar 1 hora"}]
	for room in loc.get("interiores", []):
		if World.has_key(str(room["chave"])):
			out.append({"id": "entrar:" + str(room["id"]), "label": str(room["label"])})
	if loc.get("interior", false):
		out.append({"id": "sair", "label": "Sair do quarto"})
	for s in loc.get("servicos", []):
		match s:
			"dormir_casa":
				out.append({"id": s, "label": "Dormir (8h)"})
			"banho_casa":
				out.append({"id": s, "label": "Tomar banho"})
			"dormir_quarto":
				out.append({"id": s, "label": "Deitar na cama e dormir (8h)"})
			"banho_quarto":
				out.append({"id": s, "label": "Tomar banho no coletivo"})
			"dormir_rua":
				out.append({"id": s, "label": "Dormir aqui mesmo (perigoso)"})
			"bico":
				out.append({"id": s, "label": "Procurar bico (3h)"})
			"atendimento":
				out.append({"id": s, "label": "Atendimento médico (R$ %d)" % HOSPITAL_CARE})
			"rezar":
				out.append({"id": s, "label": "Sentar e rezar em silêncio"})
	return out


func do_action(id: String) -> void:
	if not GameState.active or NPCManager.busy:
		return
	NPCManager.end_conversation()
	if id.begins_with("entrar:"):
		World.enter_interior(id.substr(7))
		return
	match id:
		"sair":
			World.leave_interior()
		"esperar":
			TimeManager.advance(60)
			GameState.add_log("Você espera o tempo passar.", "info")
		"dormir_casa":
			_sleep(480, "Você dorme na sua cama.")
			NeedsSystem.apply({"sanidade": 10})
		"banho_casa":
			TimeManager.advance(20)
			NeedsSystem.apply({"higiene": 100, "sanidade": 3})
			GameState.add_log("Você toma um banho. A água é fria, mas ajuda.", "info")
		"dormir_quarto":
			_sleep(480, "Você se deita no colchão fino que range e adormece.")
			NeedsSystem.apply({"sanidade": 8})
		"banho_quarto":
			TimeManager.advance(20)
			NeedsSystem.apply({"higiene": 90})
			GameState.add_log("Você toma banho no banheiro coletivo do fim do corredor, com alguém batendo na porta.", "info")
		"dormir_rua":
			_sleep_street()
		"bico":
			_odd_job()
		"atendimento":
			if _pay(HOSPITAL_CARE):
				TimeManager.advance(120)
				NeedsSystem.apply({"saude": 45})
				GameState.add_log("Depois de horas de espera, você é atendido, medicado e liberado.", "info")
		"rezar":
			TimeManager.advance(30)
			NeedsSystem.apply({"sanidade": 8})
			GameState.add_log("O silêncio da igreja acalma um pouco a sua cabeça.", "info")


func buy(item_id: String) -> void:
	if not GameState.active or NPCManager.busy:
		return
	if not item_id in World.current().get("loja", []) or not World.shop_open():
		return
	var price := int(World.items[item_id]["preco"])
	if _pay(price):
		TimeManager.advance(2)
		GameState.add_item(item_id)
		GameState.add_log("Você comprou %s por R$ %d." % [World.item_name(item_id), price], "info")


func use_item(item_id: String) -> void:
	if not GameState.active or NPCManager.busy:
		return
	if not GameState.remove_item(item_id):
		return
	TimeManager.advance(10)
	GameState.add_log("Você usa: %s." % World.item_name(item_id), "info")
	NeedsSystem.apply(World.items[item_id]["efeitos"], "overdose")


func _pay(amount: int) -> bool:
	if GameState.money() < amount:
		GameState.add_log("Você não tem dinheiro suficiente (precisa de R$ %d)." % amount, "info")
		return false
	GameState.add_money(-amount)
	return true


func _sleep(minutes: int, text: String) -> void:
	GameState.add_log(text, "info")
	TimeManager.advance(minutes, true)
	if GameState.active:
		GameState.add_log("Você acorda. %s." % TimeManager.clock_str(), "info")
		SaveManager.save_game()


func _sleep_street() -> void:
	GameState.add_log("Você se encolhe num canto e tenta dormir.", "info")
	TimeManager.advance(360, true)
	if not GameState.active:
		return
	NeedsSystem.apply({"sanidade": -10, "higiene": -15, "saude": -3})
	if randf() < 0.3 and GameState.money() > 0:
		var lost := int(ceil(GameState.money() * randf_range(0.3, 0.8)))
		GameState.add_money(-lost)
		GameState.add_log("Você acorda com os bolsos revirados. Levaram R$ %d enquanto você dormia." % lost, "danger")
	else:
		GameState.add_log("Você acorda dolorido, com frio e o corpo moído. %s." % TimeManager.clock_str(), "info")


func _odd_job() -> void:
	TimeManager.advance(180)
	if not GameState.active:
		return
	NeedsSystem.apply({"energia": -20, "higiene": -15})
	if randf() < 0.6:
		var pay := randi_range(30, 90)
		GameState.add_money(pay)
		var jobs := ["descarregar um caminhão", "carregar entulho", "lavar a calçada de uma loja", "distribuir panfletos", "ajudar numa mudança"]
		GameState.add_log("Você conseguiu um bico para %s e ganhou R$ %d." % [jobs.pick_random(), pay], "event")
	else:
		NeedsSystem.apply({"sanidade": -5})
		GameState.add_log("Você passou horas pedindo trabalho e ninguém quis te contratar.", "info")
