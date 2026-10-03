extends Node

var failures: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		printerr("FALHOU: ", msg)


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
	check(screen.side_box.get_child_count() > 5, "tela do jogo montou painel lateral")
	check(not screen.portrait.look.is_empty(), "rosto da Marina aparece na conversa")
	check(screen.portrait.emotion == "chorando", "rosto mostra a emoção da IA")
	check(screen.portrait.scene == "comida", "cenário da lanchonete atrás do NPC")
	check(screen.emotion_label.text == "CHORANDO", "rótulo de emoção mostrado")
	check(not screen.player_portrait.look.is_empty(), "rosto do jogador desenhado")
	screen._on_npc_replied("marina", {"fala": "Me deixa em paz, por favor."})
	check(screen.portrait.talk_left > 0.0, "boca anima quando o NPC fala")
	await get_tree().create_timer(0.5).timeout
	screen.queue_free()
	await get_tree().process_frame

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
	creator.spec["ajustes"]["face_len"] = 1.0
	creator._update_preview()
	var pt: String = creator.describe()
	print("PT: ", pt)
	check("careca" in pt and "cicatriz no rosto" in pt and "sorriso torto" in pt, "descrição para os NPCs com careca, cicatriz e detalhes")
	check(creator.portrait.look["hair"] == "careca" and 0 in creator.portrait.look["marks"], "prévia do rosto atualiza ao vivo")
	check(float(creator.portrait.look["face_len"]) > 1.05, "controle deslizante muda o formato do rosto")
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
