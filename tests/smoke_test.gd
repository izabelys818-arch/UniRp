extends Node

var failures: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		printerr("FALHOU: ", msg)


var mock_reply: Dictionary = {}


func _mock(_messages: Array) -> Dictionary:
	return {"ok": true, "text": JSON.stringify(mock_reply)}


func _set_hour(h: int) -> void:
	TimeManager.total_minutes = (TimeManager.day() * 1440) + h * 60


func _travel_tests() -> void:
	World.move_player_to("lanchonete")
	_set_hour(10)
	var opts := World.travel_options("praca")
	var modes: Array = opts.map(func(o): return o["mode"])
	check("ape" in modes and "uber" in modes, "opções a pé e Uber")
	check(not "carro" in modes, "sem carro, sem opção de carro")
	GameState.player["car"] = "Gol 2008 prata"
	check(World.travel_options("praca").size() == 3, "com carro aparece a opção do carro")
	var money_before := GameState.money()
	var uber: Dictionary = World.travel_options("praca").filter(func(o): return o["mode"] == "uber")[0]
	World.move_player_to("praca", "uber")
	check(World.current_id() == "praca" and GameState.money() == money_before - int(uber["cost"]), "Uber leva e cobra a corrida")
	World.move_player_to("lanchonete", "carro")
	check(World.current_id() == "lanchonete", "carro leva até o lugar")
	GameState.player["car"] = ""
	check(not NPCManager.state["ze"]["conhece_nome"], "nomes começam desconhecidos")


func _phone_tests() -> void:
	await _travel_tests()
	AIService.mock = _mock
	var ps := PhoneSystem
	World.move_player_to("lanchonete")
	_set_hour(9)
	NPCManager.start_conversation("marina")
	mock_reply = {"fala": "Anota aí meu número.", "emocao": "feliz", "relacao": {"afeto": 10}, "acoes": [{"tipo": "dar_numero"}]}
	await NPCManager.talk("Me passa seu número?")
	check(ps.has_contact("marina"), "NPC passa o número e vira contato")
	NPCManager.end_conversation()

	mock_reply = {"fala": "oi sumido kkk", "emocao": "feliz"}
	await ps.send_message("marina", "oi")
	var th: Array = ps.thread("marina")
	check(th.size() == 2 and not th[-1]["eu"] and th[-1]["texto"] == "oi sumido kkk", "mensagem enviada e respondida")
	check(th[0]["status"] == "visualizada", "mensagem marcada como visualizada")
	check(ps.unread("marina") == 1, "contador de não lidas")
	ps.mark_read("marina")

	mock_reply = {"responder": false, "fala": ""}
	await ps.send_message("marina", "??")
	check(ps.thread("marina").size() == 3 and ps.thread("marina")[-1]["status"] == "visualizada", "NPC pode deixar no vácuo")

	_set_hour(3)
	check(NPCManager.is_asleep("marina"), "Marina dorme de madrugada")
	await ps.send_message("marina", "tá acordada?")
	check("marina" in ps.phone()["pending"], "mensagem fica pendente enquanto o NPC dorme")
	mock_reply = {"fala": "acordei agora, q foi?", "emocao": "neutro"}
	TimeManager.advance(5 * 60)
	for i in 5:
		await get_tree().process_frame
	check(ps.thread("marina")[-1]["texto"] == "acordei agora, q foi?", "NPC responde quando acorda")

	_set_hour(10)
	var answered := false
	for i in 20:
		if ps.call_contact("marina") == "atendeu":
			answered = true
			break
	check(answered and NPCManager.channel == NPCManager.LIGACAO, "ligação atendida")
	mock_reply = {"fala": "Alô? Quem é?", "emocao": "desconfiado"}
	await NPCManager.talk("Alô, Marina?")
	check(GameState.log_entries[-1]["speaker"].ends_with("(ao telefone)"), "fala na ligação aparece no registro")
	NPCManager.end_conversation()

	var before := GameState.money()
	check(ps.send_pix("marina", 10), "PIX enviado")
	for i in 5:
		await get_tree().process_frame
	check(GameState.money() == before - 10 and ps.phone()["bank_log"][-1]["valor"] == -10, "PIX sai do saldo e entra no extrato")

	NPCManager.state["marina"]["afeto"] = 50
	NPCManager._apply_action("marina", {"tipo": "comecar_namoro"}, NPCManager.MENSAGEM)
	check(NPCManager.relation_label("marina") == "Namorando", "namoro começa")
	NPCManager._apply_action("marina", {"tipo": "bloquear"}, NPCManager.MENSAGEM)
	check(not ps.can_reach("marina"), "NPC bloqueia o jogador")
	await ps.send_message("marina", "pq me bloqueou")
	check(ps.thread("marina")[-1]["status"] == "não entregue", "mensagem não entregue quando bloqueado")
	NPCManager.state["marina"]["bloqueado"] = false

	mock_reply = {"fala": "ei, vc vem hj?", "emocao": "carinhoso"}
	var n_before := ps.thread("marina").size()
	await ps._spontaneous("marina")
	check(ps.thread("marina").size() == n_before + 1, "NPC manda mensagem por conta própria")

	var panel = preload("res://ui/phone/phone_panel.gd").new()
	add_child(panel)
	for s in [["home", ""], ["threads", ""], ["thread", "marina"], ["contacts", ""], ["bank", ""]]:
		panel.open(s[0], s[1])
		await get_tree().process_frame
		check(panel.body.get_child_count() > 0, "tela do celular: " + s[0])
	panel.queue_free()
	AIService.mock = Callable()


func _ready() -> void:
	Settings.api_key = ""
	Settings.model = ""
	SaveManager.path = "user://test_save.json"
	var origin := World.get_origin("recem_chegado")
	GameState.new_game({
		"name": "Teste", "age": 30, "gender": "homem", "appearance": "comum",
		"appearance_extra": origin["aparencia_extra"], "backstory": "", "traits": ["ansioso"],
		"origin": origin["id"], "money": int(origin["dinheiro"]), "location": origin["local"],
		"home": origin["casa"], "inventory": {"agua": 1}, "alive": true,
	})
	TimeManager.total_minutes = int(origin["hora"]) * 60
	NeedsSystem.reset(origin["necessidades"])
	NPCManager.reset_state(origin)

	await World.start_story(origin)
	check(GameState.log_entries.size() >= 2, "abertura narrada (fallback) registrada")

	check(NPCManager.npcs.size() == 15, "15 NPCs carregados")
	var here := NPCManager.npcs_here()
	print("NPCs na rodoviária às 7h: ", here)
	check(here.has("tiago"), "Tiago na rodoviária de manhã")

	var hunger_before := NeedsSystem.get_value("saciedade")
	World.move_player_to("lanchonete")
	check(World.current_id() == "lanchonete", "viajou para a lanchonete")
	check(NeedsSystem.get_value("saciedade") < hunger_before, "fome aumentou com o tempo")

	var money_before := GameState.money()
	Economy.buy("prato_feito")
	check(GameState.money() == money_before - 25, "comprou prato feito")
	check(GameState.item_count("prato_feito") == 1, "prato no inventário")
	var sat := NeedsSystem.get_value("saciedade")
	Economy.use_item("prato_feito")
	check(NeedsSystem.get_value("saciedade") > sat, "comer aumenta saciedade")

	World.move_player_to("apartamento")
	check(World.current_id() == "lanchonete", "não entra em apartamento que não é seu")

	NPCManager.start_conversation(here[0] if not here.is_empty() else "marina")
	await NPCManager.talk("Oi, tudo bem?")
	check(GameState.log_entries[-1]["kind"] == "error", "sem IA configurada mostra erro amigável")

	NPCManager.talking_to = "ruan"
	NPCManager._apply_reply("ruan", {"fala": "Tá olhando o quê?", "emocao": "ameacador", "relacao": {"confianca": -50, "medo": 99}, "memoria": "me encarou", "revela_nome": true, "acoes": [{"tipo": "dar_dinheiro", "valor": 99999}, {"tipo": "atacar", "dano": 999}]})
	var rst: Dictionary = NPCManager.state["ruan"]
	check(int(rst["confianca"]) == -15, "variação de relação limitada a -15")
	check(rst["conhece_nome"], "nome revelado")
	check(NeedsSystem.get_value("saude") <= 60.0 and GameState.active, "ataque limitado a 40 de dano")

	World.move_player_to("pensao")
	var t0 := TimeManager.total_minutes
	Economy.do_action("dormir_pensao")
	check(TimeManager.total_minutes - t0 == 480, "dormiu 8h")
	check(SaveManager.has_save(), "autosave ao dormir")

	var saved_money := GameState.money()
	var saved_time := TimeManager.total_minutes
	GameState.add_money(-saved_money)
	check(SaveManager.load_game(), "carregou o save")
	check(GameState.money() == saved_money and TimeManager.total_minutes == saved_time, "save restaurou dinheiro e hora")

	check(World.emotions.has("chorando"), "emoção chorando existe")
	var FaceRig = preload("res://ui/face/face_rig.gd")
	for emo in World.emotions:
		check(FaceRig.EXPRESSIONS.has(emo), "rosto tem a expressão " + emo)
	for id in NPCManager.npcs:
		check(World.npc_looks.has(id), "aparência definida para " + id)

	World.move_player_to("lanchonete")
	TimeManager.total_minutes = (TimeManager.day() * 1440) + 9 * 60
	NPCManager.start_conversation("marina")
	NPCManager._apply_reply("marina", {"fala": "...", "emocao": "CHORANDO"})
	check(NPCManager.state["marina"]["emocao"] == "chorando", "emoção normalizada")
	NPCManager._apply_reply("marina", {"fala": "...", "emocao": "inventada"})
	check(NPCManager.state["marina"]["emocao"] == "neutro", "emoção desconhecida vira neutro")
	NPCManager._apply_reply("marina", {"fala": "...", "emocao": "chorando"})

	var screen = preload("res://ui/game_screen.gd").new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	check(screen.side_box.get_child_count() > 4, "tela do jogo montou painel do local")
	check(screen.actors.has("marina"), "Marina aparece de pé no cenário")
	var actor = screen.actors.get("marina")
	check(actor != null and actor.actor_mode and actor.show_emote, "personagem em modo ator com balão de emoção")
	check(actor != null and actor.emotion == "chorando", "balão/rosto mostram a emoção da IA")
	check(screen.scene_view.scene == "comida", "cenário da lanchonete em tela cheia")
	check(not screen.player_portrait.look.is_empty(), "rosto do jogador desenhado")
	check(World.shop_open(), "lanchonete tem balcão aberto")
	screen._on_npc_replied("marina", {"fala": "Me deixa em paz, por favor."})
	check(actor != null and actor.talk_left > 0.0, "boca anima quando o NPC fala")
	screen._open_context("marina")
	check(screen.context_menu.item_count >= 10, "menu do botão direito com opções")
	screen.context_menu.hide()
	screen._open_bag()
	check(screen.bag.visible and screen.bag.grid.get_child_count() > 0, "bolsa abre com os itens")
	screen.bag.close()
	screen._open_shop()
	check(screen.shop.visible, "loja abre no balcão")
	screen.shop.close()
	screen._open_map()
	check(screen.map_panel.visible, "mapa abre")
	screen.map_panel._fill_info("praca")
	check(screen.map_panel.info.get_child_count() >= 5, "mapa mostra opções de transporte")
	screen.map_panel.close()
	screen._open_history()
	check(screen.history.log_view.get_parsed_text().length() > 10, "histórico mostra a conversa")
	screen.history.close()
	await get_tree().create_timer(0.5).timeout
	screen.queue_free()
	await get_tree().process_frame

	await _phone_tests()

	var creator = preload("res://ui/character_creation.gd").new()
	add_child(creator)
	await get_tree().process_frame
	for i in creator.TABS.size():
		creator._show_tab(i)
		await get_tree().process_frame
		check(creator.content.get_child_count() > 1, "aba %s montada" % creator.TABS[i])
	creator._randomize_look()
	creator.player_name = "Joana"
	creator.gender = 1
	creator.spec["cabelo"] = 1
	creator.spec["marcas"] = [0]
	creator.extra = "sorriso torto"
	creator.spec["ajustes"]["face_len"] = 0.0
	creator._update_preview()
	var len_before := float(creator.portrait.look["face_len"])
	creator.spec["ajustes"]["face_len"] = 1.0
	creator._update_preview()
	var pt: String = creator.describe()
	print("PT: ", pt)
	check("careca" in pt and "cicatriz no rosto" in pt and "sorriso torto" in pt, "descrição para os NPCs com careca, cicatriz e detalhes")
	check(creator.portrait.look["hair"] == "careca" and 0 in creator.portrait.look["marks"], "prévia do rosto atualiza ao vivo")
	check(float(creator.portrait.look["face_len"]) > len_before + 0.08, "controle deslizante muda o formato do rosto")
	var man: Dictionary = creator.LookBuilder.build({}, 30, "homem")
	var woman: Dictionary = creator.LookBuilder.build({}, 30, "mulher")
	check(man["jaw"] > woman["jaw"] + 0.15 and woman["eye_size"] > man["eye_size"] and woman["lashes"] and man["adams_apple"], "homem e mulher bem diferentes")
	creator.spec["sobrancelha"] = 3
	creator._update_preview()
	check(creator.portrait.look["brow_shape"] == 3, "formato da sobrancelha escolhido")
	creator.portrait.set_emotion("chorando")
	check(creator.portrait.emotion == "chorando", "botões de expressão funcionam")
	creator._start()
	check(GameState.player["name"] == "Joana" and GameState.player["look"]["cabelo"] == 1, "personagem criado com aparência")
	creator.queue_free()
	await get_tree().process_frame
	TimeManager.advance(10)

	NeedsSystem.apply({"saude": -1000}, "teste")
	check(not GameState.active, "morte encerra o jogo")

	SaveManager.delete_save()
	print("RESULTADO: ", "OK" if failures.is_empty() else "%d falha(s)" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
