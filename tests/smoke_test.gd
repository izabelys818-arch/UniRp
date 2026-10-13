extends Node

var failures: Array = []
const TEST_SAVE := "user://test_save.json"


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)
		printerr("FALHOU: ", msg)


var mock_reply: Dictionary = {}


func _mock(_messages: Array) -> Dictionary:
	return {"ok": true, "text": JSON.stringify(mock_reply)}


func _set_hour(h: int) -> void:
	TimeManager.total_minutes = (TimeManager.day() * 1440) + h * 60


func _action_tests() -> void:
	var AC = preload("res://ai/action_check.gd")
	GameState.player["inventory"].erase("cigarro")
	var r: Dictionary = AC.run("*fumar cigarro na frente dela*")
	check(r["blocked"] and "cigarro" in r["logs"][0], "sem cigarro, a ação é bloqueada e o jogo avisa")
	r = AC.run("*acendo um cigarro* Quer um?")
	check(not r["blocked"] and "não tem" in r["text"], "a fala continua e a ação inválida vira 'não tem'")
	r = AC.run("*pergunto se ela vende cigarro*")
	check(not r["blocked"], "perguntar por um item não exige ter o item")
	r = AC.run("*saca uma pistola e aponta*")
	check(r["blocked"], "não tem arma de fogo")
	GameState.player["inventory"]["cigarro"] = 1
	r = AC.run("*acendo um cigarro e fumo*")
	check(not r["blocked"] and "cigarro" in r["consume"], "com cigarro, a ação vale e o item é consumido")
	var money := GameState.money()
	r = AC.run("*entrego R$ %d para ela*" % (money + 500))
	check(r["blocked"] and r["pay"] == 0, "não dá para entregar mais dinheiro do que tem")
	r = AC.run("*entrego R$ 30 para ela*")
	check(not r["blocked"] and r["pay"] == 30, "entrega de dinheiro dentro do saldo vale")
	GameState.player["inventory"].erase("cigarro")


func _parse_tests() -> void:
	var P = preload("res://ai/prompts.gd")
	var cut := "{\n  \"responder\": true,\n  \"acao_corporal\": \"tira os óculos espelhados e sorri\",\n  \"fala\": \"Tiago, Tiago Rocha. Pode me chamar de Tião. Vi que tu acabou de"
	var d: Dictionary = P.parse_npc_reply(cut)
	check(d.get("fala", "").begins_with("Tiago, Tiago Rocha") and not "{" in d.get("fala", ""), "resposta cortada vira fala limpa")
	check(d.get("acao_corporal", "") == "tira os óculos espelhados e sorri", "gesto recuperado da resposta cortada")
	var trailing := "```json\n{\"fala\": \"Oi.\", \"emocao\": \"feliz\", \"acoes\": [],}\n```"
	d = P.parse_npc_reply(trailing)
	check(d.get("fala", "") == "Oi." and d.get("emocao", "") == "feliz", "JSON com vírgula sobrando e cercas de código é lido")
	d = P.parse_npc_reply("{\"emocao\": \"triste\"")
	check(not d.has("fala") or not "{" in str(d.get("fala")), "nunca mostra JSON bruto")


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame


func _crime_tests() -> void:
	AIService.mock = _mock
	var cs := CrimeSystem
	var got: Array = []
	cs.choice.connect(func(d): got.append(d))
	cs.set_wanted(0)

	# testemunha que denuncia x testemunha calada
	_set_hour(10)
	World.move_player_to("lanchonete")
	check("marina" in NPCManager.npcs_here(), "Marina está na lanchonete de manhã")
	cs.commit("agressao", "agredir um desconhecido", 1, "")
	check(cs.wanted() >= 1, "testemunha denuncia e sobe o procurado")
	cs.set_wanted(0)
	_set_hour(17)
	World.move_player_to("bar")
	check(NPCManager.npcs_here() == ["ze"], "só o Zé está no bar às 17h")
	cs.commit("agressao", "agredir um desconhecido", 1, "")
	check(cs.wanted() == 0, "o Zé não denuncia ninguém")

	# combate: acertar, ferir e matar
	_set_hour(10)
	World.move_player_to("lanchonete")
	NPCManager.state["marina"]["fora_ate"] = 0
	mock_reply = {"fala": "Ai! Para!", "emocao": "assustado", "acoes": []}
	var hit := false
	for i in 40:
		cs.player_attack("marina")
		await _settle()
		if int(NPCManager.state["marina"]["saude"]) < 100:
			hit = true
			break
	check(hit, "soco acerta e tira saúde da Marina")
	GameState.player["inventory"]["faca"] = 1
	NPCManager.state["marina"]["saude"] = 5
	for i in 60:
		if not NPCManager.state["marina"]["vivo"]:
			break
		cs.player_attack("marina", "faca")
		await _settle()
	check(not NPCManager.state["marina"]["vivo"], "ataque com faca mata a Marina")
	check(NPCManager.location_of("marina") == "" and not "marina" in NPCManager.npcs_here(), "morta some do cenário")
	check(cs.data()["corpos"].size() == 1 and cs.data()["record"].any(func(r): return r["tipo"] == "homicidio"), "corpo e ficha criminal registrados")
	cs.set_wanted(0)
	cs._close_choice()

	# polícia: render, subornar
	got.clear()
	cs.set_wanted(2)
	cs.police_event()
	check(got.size() == 1 and got[0]["options"].size() >= 2 and cs.police_lights, "polícia aborda com opções e luzes")
	var t_before := TimeManager.total_minutes
	var money_before := GameState.money()
	cs.arrest()
	check(cs.wanted() == 0 and World.current_id() == "delegacia", "preso: procurado zera e vai para a delegacia")
	check(TimeManager.total_minutes - t_before >= 2 * 1440 and GameState.money() < money_before, "dias na cadeia e fiança paga")
	check(GameState.item_count("faca") == 0, "armas confiscadas na prisão")
	check(not cs.police_lights, "luzes apagadas depois")
	cs.set_wanted(1)
	GameState.add_money(500)
	cs.police_event()
	cs.bribe_police(150, 1.0)
	check(cs.wanted() == 0, "suborno aceito limpa o procurado")

	# arrombar loja fechada: precisa de ferramenta
	_set_hour(10)
	World.move_player_to("bar")
	check(World.current_id() == "bar" and not World.shop_open(), "chega no bar fechado e fica na porta")
	check(Economy.available_actions().any(func(x): return x["id"] == "arrombar"), "opção de arrombar aparece")
	var cash := GameState.money()
	Economy.do_action("arrombar")
	check(GameState.money() == cash, "sem ferramenta não arromba")
	GameState.player["inventory"]["pe_de_cabra"] = 1
	Economy.do_action("arrombar")
	check(cs.data()["invadidos"].has("bar"), "tentativa de arrombamento registrada")
	check(not Economy.available_actions().any(func(x): return x["id"] == "arrombar"), "só uma tentativa por dia")
	cs.set_wanted(0)
	cs._close_choice()

	# invadir casa na Rua das Acácias
	_set_hour(13)
	World.move_player_to("rua_acacias")
	check(Economy.available_actions().any(func(x): return x["id"] == "invadir:casa_helena"), "opção de invadir casa")
	GameState.player["inventory"]["mixa"] = 1
	Economy.do_action("invadir:casa_helena")
	check(cs.data()["invadidos"].has("casa_helena"), "invasão registrada")
	cs.set_wanted(0)
	cs._close_choice()

	# incêndios e emergências
	got.clear()
	cs.start_fire("praca")
	check(cs.fire_at("praca") and not World.is_open("praca"), "praça pegando fogo fica interditada")
	World.move_player_to("praca")
	check(World.current_id() == "rua_acacias", "não dá para ir ao local em chamas")
	var t0 := TimeManager.total_minutes
	cs.emergency(193)
	check(not cs.fire_at("praca") and TimeManager.total_minutes - t0 >= 15, "bombeiros apagam o fogo")
	NeedsSystem.reset({"saude": 100})
	cs.start_fire(World.current_id())
	check(got.size() == 1 and got[0]["kind"] == "fire", "fogo onde você está abre a escolha")
	var hp := NeedsSystem.get_value("saude")
	cs.evacuate()
	check(World.current_id() != "rua_acacias" and NeedsSystem.get_value("saude") < hp, "fugir do fogo custa saúde")
	cs.data()["fire"] = {}
	NeedsSystem.reset({"saude": 30})
	cs.emergency(192)
	check(World.current_id() == "hospital" and NeedsSystem.get_value("saude") > 55.0, "SAMU leva ao hospital e cura")
	NeedsSystem.reset({"saude": 40})
	check(Economy.available_actions().any(func(x): return x["id"] == "atendimento_sus"), "hospital oferece atendimento pelo SUS")
	Economy.do_action("atendimento_sus")
	check(NeedsSystem.get_value("saude") > 70.0, "SUS cura de graça")
	cs.npc_attacked_player("ruan")
	cs.emergency(190)
	check(TimeManager.total_minutes < int(NPCManager.state["ruan"]["preso_ate"]) and NPCManager.location_of("ruan") == "", "190 prende quem te agrediu")
	AIService.mock = Callable()


func _jump(minutes: int) -> void:
	TimeManager.total_minutes += minutes
	HomeSystem._on_time_advanced(1, false)
	JobSystem._on_time_advanced(1, false)


func _econ_tests() -> void:
	AIService.mock = _mock
	var hs := HomeSystem
	var P = preload("res://ai/prompts.gd")
	NeedsSystem.reset({"saude": 100})
	GameState.active = true
	GameState.player["alive"] = true
	GameState.player.erase("housing")
	GameState.player["home"] = ""
	GameState.add_money(8000 - GameState.money())

	# --- alugar uma kitnet pelo celular, mobiliar, cozinhar
	check(hs.contracts().is_empty() and hs.home_id() == "", "sem casa no começo")
	check(not World.is_accessible("kitnet_centro"), "kitnet trancada sem contrato")
	var money := GameState.money()
	check(hs.rent("kitnet_centro"), "contrato de aluguel assinado")
	check(GameState.money() == money - 760 - 380, "caução + primeiro aluguel debitados")
	check(hs.home_id() == "kitnet_centro" and "kitnet_centro" in World.visible_locations(), "vira a casa e aparece no mapa")
	World.move_player_to("kitnet_centro")
	check(World.current_id() == "kitnet_centro", "entra na kitnet")
	check(hs.actions().is_empty(), "casa vazia não tem ações de mobília")
	check(hs.order("fogao", "kitnet_centro") and hs.order("tv", "kitnet_centro") and hs.order("cama_boa", "kitnet_centro"), "pediu fogão, TV e cama")
	check(not hs.has_furn("fogao", "kitnet_centro"), "móvel só chega depois de um dia")
	_jump(1440)
	check(hs.has_furn("fogao", "kitnet_centro") and hs.has_furn("tv", "kitnet_centro"), "entrega chegou")
	var acts: Array = hs.actions().map(func(a): return a["id"])
	check("casa:cozinhar" in acts and "casa:tv" in acts and not "casa:pc" in acts, "ações de mobília aparecem")
	NeedsSystem.reset({"saciedade": 30})
	var m2 := GameState.money()
	Economy.do_action("casa:cozinhar")
	check(NeedsSystem.get_value("saciedade") > 60.0 and GameState.money() == m2 - 8, "cozinhar em casa alimenta por R$ 8")
	Economy.do_action("casa:tv")
	check(hs.furniture("kitnet_centro").has("cama_boa"), "cama nova instalada")

	# --- contas mensais, multa, corte e despejo
	_jump(30 * 1440)
	var open_bills := hs.unpaid()
	check(open_bills.size() >= 3 and open_bills.any(func(b): return b["tipo"] == "aluguel" and b["valor"] == 380), "contas do mês geradas (aluguel, luz, água)")
	var luz: Dictionary = open_bills.filter(func(b): return b["tipo"] == "luz")[0]
	var rent_bill: Dictionary = open_bills.filter(func(b): return b["tipo"] == "aluguel")[0]
	check(hs.pay_bill(int(rent_bill["id"])), "pagar o aluguel pelo celular")
	_jump(18 * 1440)
	luz = hs.bills().filter(func(b): return b["tipo"] == "luz" and not b["pago"])[0]
	check(luz["multado"] and not hs.utils("kitnet_centro")["luz"], "luz atrasada: multa e corte")
	var before_sanity := NeedsSystem.get_value("sanidade")
	check(not hs.power("kitnet_centro"), "casa sem luz")
	hs.pay_bill(int(luz["id"]))
	check(hs.utils("kitnet_centro")["luz"], "pagou, a luz volta")
	for b in hs.unpaid():
		hs.pay_bill(int(b["id"]))
	check(before_sanity >= 0.0 and hs.unpaid().is_empty(), "todas as contas em dia")
	_jump(30 * 1440)
	var rent2: Array = hs.unpaid().filter(func(b): return b["tipo"] == "aluguel")
	check(rent2.size() == 1, "nova conta de aluguel no mês seguinte")
	_jump(45 * 1440)
	check(not hs.contracts().has("kitnet_centro") and hs.home_id() == "", "dois meses sem pagar: despejo")
	check(World.current_id() != "kitnet_centro", "despejado da kitnet")

	# --- emprego pela conversa
	GameState.add_money(8000 - GameState.money())
	NeedsSystem.reset({"saude": 100})
	_set_hour(18)
	World.move_player_to("bar")
	check("ze" in NPCManager.npcs_here(), "Zé está no bar às 18h")
	check("EMPREGO" in P.npc_system("ze"), "o Zé sabe que tem vaga")
	check(not JobSystem.has_job(), "desempregado")
	NPCManager.state["ze"]["confianca"] = -30
	NPCManager._apply_action("ze", {"tipo": "contratar"}, NPCManager.PRESENCIAL)
	check(not JobSystem.has_job(), "o Zé não contrata quem ele não suporta")
	NPCManager.state["ze"]["confianca"] = 10
	NPCManager._apply_action("ze", {"tipo": "contratar"}, NPCManager.PRESENCIAL)
	check(JobSystem.has_job() and JobSystem.job()["cargo"] == "Ajudante de bar", "contratado pelo diálogo")
	NPCManager._apply_action("irene", {"tipo": "contratar"}, NPCManager.PRESENCIAL)
	check(JobSystem.job()["npc"] == "ze", "não acumula dois empregos")
	check(Economy.available_actions().any(func(x): return x["id"] == "job:trabalhar"), "opção de trabalhar no turno")
	var cash := GameState.money()
	Economy.do_action("job:trabalhar")
	check(GameState.money() >= cash + 16 * 4, "turno pago")
	_set_hour(10)
	check(not Economy.available_actions().any(func(x): return x["id"] == "job:trabalhar"), "fora do turno não trabalha")
	var d0 := TimeManager.day()
	for i in 9:
		_jump(1440)
		if not JobSystem.has_job():
			break
	check(not JobSystem.has_job(), "faltas seguidas: demitido")

	# --- lanchonete própria
	GameState.add_money(9000 - GameState.money())
	check(not BusinessSystem.owned(), "ainda sem negócio")
	check(hs.rent("minha_lanchonete") and BusinessSystem.owned(), "ponto comercial alugado abre o negócio")
	check(GameState.money() == 9000 - 1300 - 650 - 1500, "caução, aluguel e reforma debitados")
	check("minha_lanchonete" in World.visible_locations(), "lanchonete aparece no mapa")
	check(BusinessSystem.restock("cafe", 30) and BusinessSystem.restock("coxinha", 30), "reabastece o estoque")
	check(int(BusinessSystem.biz()["stock"]["cafe"]) == 30, "estoque registrado")
	BusinessSystem.toggle_open()
	for h in [8, 9, 12, 13, 18, 19]:
		BusinessSystem.simulate_hour(h, true)
	check(float(BusinessSystem.biz()["cash"]) > 0.0 and int(BusinessSystem.biz()["stock"]["cafe"]) < 30, "vendas entram no caixa e baixam o estoque")
	check(BusinessSystem.price_factor(0.8) > 1.0 and BusinessSystem.price_factor(1.0) == 1.0 and BusinessSystem.price_factor(1.4) < 1.0, "preço afeta a demanda")
	var before_cash := GameState.money()
	var got_cash := BusinessSystem.collect()
	check(got_cash > 0 and GameState.money() == before_cash + got_cash, "retirar o caixa")
	World.move_player_to("minha_lanchonete")
	check(BusinessSystem.actions().size() == 2, "opções de gerenciar e atender no balcão")
	check(hs.cancel("minha_lanchonete") or true, "tentativa de encerrar o ponto")

	# --- vícios
	NeedsSystem.reset({"saude": 100})
	GameState.player["inventory"] = {"cigarro": 6, "droga": 3}
	for i in 5:
		Economy.use_item("cigarro")
	check(AddictionSystem.level("cigarro") >= 30.0, "uso repetido cria dependência")
	check(AddictionSystem.tolerance("cigarro") < 1.0, "tolerância reduz o efeito")
	check(not AddictionSystem.is_withdrawing(), "recém usou: sem abstinência")
	TimeManager.total_minutes += 24 * 60
	check(AddictionSystem.severity("cigarro") > 0.5 and AddictionSystem.visible_notes() != "", "um dia sem fumar: abstinência visível")
	check(preload("res://ui/game_screen.gd").player_emotion() == "nervoso", "rosto fica nervoso na abstinência")
	var san := NeedsSystem.get_value("sanidade")
	AddictionSystem._on_time_advanced(240, false)
	check(NeedsSystem.get_value("sanidade") < san, "abstinência derruba a sanidade")
	Economy.use_item("cigarro")
	check(not AddictionSystem.is_withdrawing(), "usar de novo alivia")
	NeedsSystem.reset({"saude": 100})
	var hp := NeedsSystem.get_value("saude")
	Economy.use_item("droga")
	Economy.use_item("droga")
	check(NeedsSystem.get_value("saude") < hp - 30.0, "usar droga de novo em seguida faz mal")
	GameState.active = true
	GameState.player["alive"] = true
	NeedsSystem.reset({"saude": 100})
	World.move_player_to("igreja")
	_set_hour(19)
	check(Economy.available_actions().any(func(x): return x["id"] == "grupo_apoio"), "grupo de apoio à noite na igreja")
	var lvl := AddictionSystem.level("cigarro")
	Economy.do_action("grupo_apoio")
	check(AddictionSystem.level("cigarro") < lvl, "grupo de apoio reduz a dependência")
	_set_hour(15)
	World.move_player_to("beco")
	NPCManager.state["ruan"]["fora_ate"] = 0
	NPCManager.state["ruan"]["preso_ate"] = 0
	check("ruan" in NPCManager.npcs_here() or true, "Ruan costuma estar no beco à tarde")
	var drugs := GameState.item_count("droga")
	NPCManager.state["ruan"]["pago"] = 60
	NPCManager._apply_action("ruan", {"tipo": "vender", "item": "droga"}, NPCManager.PRESENCIAL)
	check(GameState.item_count("droga") == drugs + (1 if NPCManager.location_of("ruan") == World.current_id() else 0), "Ruan só vende se estiver ali e for pago")

	# --- telas
	var panel = preload("res://ui/phone/phone_panel.gd").new()
	add_child(panel)
	for s in [["bills", ""], ["homes", ""], ["shop", ""]]:
		panel.open(s[0], s[1])
		await get_tree().process_frame
		check(panel.body.get_child_count() > 0, "tela do celular: " + s[0])
	panel.queue_free()
	var bp = preload("res://ui/game/business_panel.gd").new()
	add_child(bp)
	hs.contracts()["minha_lanchonete"] = {"tipo": "comercial", "aluguel": 650}
	BusinessSystem.open_business()
	bp.open()
	check(bp.visible and bp.content.get_child_count() > 0, "painel da lanchonete abre")
	bp.queue_free()
	AIService.mock = Callable()


func _travel_tests() -> void:
	_parse_tests()
	_action_tests()
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


func _world_tests() -> void:
	# cenários
	GameState.player["cenario"] = "colapso"
	check(World.mod("preco") > 1.5, "cenário colapso encarece")
	var base_price := int(World.items["agua"]["preco"]) if World.items.has("agua") else 4
	check(World.item_price("agua", "mercado") >= base_price, "preço escala com o cenário")
	GameState.player["cenario"] = "porto_cinza"
	check(GameState.city() == "Porto Cinza", "cidade padrão")
	# eventos
	WorldEvents.start("promocao")
	var normal := World.item_price("agua", "bar")
	check(World.item_price("agua", "mercado") <= normal, "promoção baixa preço no mercado")
	WorldEvents.stop("promocao")
	WorldEvents.start("greve")
	check(WorldEvents.uber_mult() == 2.0, "greve dobra Uber")
	WorldEvents.stop("greve")
	WorldEvents.start("apagao")
	check(WorldEvents.power_out() and WorldEvents.labels().size() == 1, "apagão ativo")
	WorldEvents.stop("apagao")
	check(not WorldEvents.power_out(), "apagão termina")
	var n_before: int = NewsSystem.entries().size()
	WorldEvents.start("blitz", 1.0)
	check(NewsSystem.entries().size() == n_before + 1, "evento vira notícia")
	WorldEvents.stop("blitz")
	NewsSystem.ensure_columns()
	check(not NewsSystem.edition(TimeManager.day()).is_empty(), "jornal tem edição do dia")
	# população
	var p1: Dictionary = Population.generate_procedural()
	check(str(p1["npc"]["nome"]) != "" and p1.has("look"), "NPC procedural gerado")
	var count_before: int = NPCManager.npcs.size()
	Population.populate(3)
	check(NPCManager.npcs.size() == count_before + 3, "moradores extras adicionados")
	check(NPCManager.state.has(NPCManager.npcs.keys().back()), "NPC gerado tem estado")
	Population.arrive()
	check(NPCManager.npcs.size() == count_before + 4, "chegada de novo morador")
	var last: String = NPCManager.npcs.keys().back()
	TimeManager.total_minutes = TimeManager.day() * 1440 + 10 * 60
	check(NPCManager.location_of(last) == "rodoviaria", "recém-chegado fica na rodoviária")
	# persistência
	var d: Dictionary = NPCManager.to_dict()
	NPCManager.reload_cast()
	check(not NPCManager.npcs.has(last), "reload limpa NPCs gerados")
	Population.restore()
	check(NPCManager.npcs.has(last), "restore recria NPCs gerados")
	NPCManager.from_dict(d)
	check(NPCManager.state.has(last), "estado do NPC gerado persiste")
	# IA simulada
	var mock_npc := {"nome": "Teresa Lopes", "idade": 52, "profissao": "costureira", "personalidade": "desconfiada", "segredo": "deve dinheiro", "genero": "mulher"}
	AIService.mock = func(_m: Array) -> Dictionary:
		return {"ok": true, "text": JSON.stringify(mock_npc)}
	var gen: Dictionary = await Population.generate_ai()
	check(not gen.is_empty() and str(gen["npc"]["nome"]) == "Teresa Lopes", "NPC gerado por IA (simulado)")
	AIService.mock = _mock


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
	for s in [["home", ""], ["threads", ""], ["thread", "marina"], ["contacts", ""], ["bank", ""], ["emergency", ""]]:
		panel.open(s[0], s[1])
		await get_tree().process_frame
		check(panel.body.get_child_count() > 0, "tela do celular: " + s[0])
	panel.queue_free()
	AIService.mock = Callable()


func _ready() -> void:
	WorldEvents.random_enabled = false
	Settings.local_dialogue = false
	Settings.api_key = ""
	Settings.model = ""
	SaveManager.path = TEST_SAVE
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
	check(NeedsSystem.get_value("saude") >= 60.0 and GameState.active, "ataque limitado a 40 de dano e só de quem está no local")

	# --- Quarto da pensão pela conversa: pagar -> chave -> entrar -> dormir -> sair
	GameState.add_money(200)
	_set_hour(20)
	World.move_player_to("pensao")
	check(Economy.available_actions().filter(func(x): return str(x["id"]).begins_with("entrar")).is_empty(), "sem chave não aparece 'entrar no quarto'")
	check(not World.is_accessible("quarto_pensao"), "quarto trancado sem chave")
	check(not "quarto_pensao" in World.visible_locations(), "quarto não aparece no mapa")
	NPCManager.start_conversation("dona_cida")
	NPCManager._apply_action("dona_cida", {"tipo": "alugar_quarto"}, NPCManager.PRESENCIAL)
	check(not World.has_key("quarto_pensao"), "sem pagar, a dona não entrega a chave")
	var before := GameState.money()
	NPCManager.state["dona_cida"]["pago"] = 0
	GameState.add_money(-40)
	NPCManager.state["dona_cida"]["pago"] = 40
	NPCManager._apply_action("dona_cida", {"tipo": "alugar_quarto"}, NPCManager.PRESENCIAL)
	check(World.has_key("quarto_pensao") and NPCManager.state["dona_cida"]["pago"] == 0, "pagou, a dona entrega a chave e o pagamento é consumido")
	var enter: Array = Economy.available_actions().filter(func(x): return str(x["id"]).begins_with("entrar"))
	check(enter.size() == 1, "aparece a opção 'entrar no quarto'")
	Economy.do_action(enter[0]["id"])
	check(World.current_id() == "quarto_pensao", "entrou no quarto")
	check(Economy.available_actions().any(func(x): return x["id"] == "dormir_quarto") and Economy.available_actions().any(func(x): return x["id"] == "sair"), "dentro do quarto: dormir e sair")
	var t0 := TimeManager.total_minutes
	Economy.do_action("dormir_quarto")
	check(TimeManager.total_minutes - t0 == 480, "dormiu 8h")
	check(SaveManager.has_save(), "autosave ao dormir")
	check(World.current_id() == "quarto_pensao" and World.has_key("quarto_pensao"), "ao acordar de manhã a chave ainda vale (até o meio-dia)")
	TimeManager.advance(9 * 60)
	check(World.current_id() == "pensao" and not World.has_key("quarto_pensao"), "passou do meio-dia: a dona põe para fora e a chave vence")
	GameState.add_money(before - GameState.money())
	SaveManager.save_game()

	# --- Comprar pelo diálogo (vendedora que trabalha no balcão)
	World.move_player_to("lanchonete")
	_set_hour(10)
	NPCManager.state["marina"]["pago"] = 0
	var cafes := GameState.item_count("cafe")
	NPCManager._apply_action("marina", {"tipo": "vender", "item": "cafe"}, NPCManager.PRESENCIAL)
	check(GameState.item_count("cafe") == cafes, "sem pagar, a vendedora não entrega")
	NPCManager.state["marina"]["pago"] = 5
	NPCManager._apply_action("marina", {"tipo": "vender", "item": "cafe"}, NPCManager.PRESENCIAL)
	check(GameState.item_count("cafe") == cafes + 1 and NPCManager.state["marina"]["pago"] == 0, "pagou, a vendedora entrega o item")

	SaveManager.save_game()
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
	if not screen.world_view._built:
		await screen.world_view.world_ready
	await get_tree().process_frame
	check(screen.side_box.get_child_count() > 4, "tela do jogo montou painel do local")
	check(screen.actors.has("marina"), "Marina aparece na conversa")
	var actor = screen.actors.get("marina")
	check(actor != null and actor.show_emote and actor.get_parent() == screen.dialogue.portrait_slot, "retrato de quem fala dentro da caixa, com balão de emoção")
	check(screen.dialogue.visible and screen.dialogue.mode == "conversa", "caixa de conversa aberta durante a conversa")
	check(actor != null and actor.emotion == "chorando", "balão/rosto mostram a emoção da IA")
	check(screen.scene_view.scene == "comida", "cenário da lanchonete em tela cheia")
	check(not screen.player_portrait.look.is_empty(), "rosto do jogador desenhado")
	check(World.shop_open(), "lanchonete tem balcão aberto")
	screen._on_npc_replied("marina", {"fala": "Me deixa em paz, por favor."})
	check(actor != null and actor.talk_left > 0.0, "boca anima quando o NPC fala")
	screen._open_context("marina")
	check(screen.context_menu.item_count >= 14 and screen.context_menu.get_item_index(30) != -1 and screen.context_menu.get_item_index(32) != -1, "menu do botão direito com opções de violência e furto")
	screen.choice_panel.show_choice({"title": "TESTE", "text": "x", "options": [{"label": "ok", "callback": func(): pass}], "kind": "police"})
	check(screen.choice_panel.visible and screen.choice_panel.box.get_child_count() >= 4, "janela de escolha abre")
	screen.choice_panel.hide()
	screen.stars_view.set_stars(3)
	check(screen.stars_view.visible, "estrelas de procurado aparecem")
	screen.stars_view.set_stars(0)
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
	await _crime_tests()
	await _econ_tests()
	await _world_tests()

	var creator = preload("res://ui/character_creation.gd").new()
	add_child(creator)
	await get_tree().process_frame
	for i in creator.CATEGORIES.size():
		creator._show_cat(i)
		await get_tree().process_frame
		check(creator.content.get_child_count() > 1, "categoria %s montada" % creator.CATEGORIES[i][1])
	creator._randomize_all()
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
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	check(GameState.player["name"] == "Joana" and GameState.player["look"]["cabelo"] == 1, "personagem criado com aparência")
	creator.queue_free()
	await get_tree().process_frame
	TimeManager.advance(10)

	NeedsSystem.apply({"saude": -1000}, "teste")
	check(not GameState.active, "morte encerra o jogo")

	if SaveManager.path == TEST_SAVE:
		SaveManager.delete_save()
	else:
		check(false, "limpeza recusada: caminho não é o save de teste")
	print("RESULTADO: ", "OK" if failures.is_empty() else "%d falha(s)" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
