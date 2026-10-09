extends Node

const Local = preload("res://ai/local_dialogue.gd")
const Expr = preload("res://ai/expression_engine.gd")
var fails: Array = []


func check(c: bool, m: String) -> void:
	if not c:
		fails.append(m)
		printerr("FALHOU: ", m)


func ask(id: String, text: String) -> Dictionary:
	return Local.try_reply(id, text, "presencial")


func _ready() -> void:
	WorldEvents.random_enabled = false
	SaveManager.path = "user://test_save.json"
	var origin := World.get_origin("morador_antigo")
	GameState.new_game({"name": "Rafa", "age": 30, "gender": "homem", "appearance": "x", "look": {}, "appearance_extra": "", "backstory": "", "traits": [],
		"origin": origin["id"], "money": 500, "location": "bar", "home": "apartamento", "inventory": {}, "alive": true})
	TimeManager.total_minutes = 18 * 60
	NeedsSystem.reset({})
	NPCManager.reset_state(origin)
	World.move_player_to("bar")
	var st: Dictionary = NPCManager.state["ze"]
	var r := ask("ze", "oi, tudo bem?")
	check(not r.is_empty() and str(r["fala"]) != "", "responde oi, tudo bem")
	check("saudacao" in r["_intents"] and "como_vai" in r["_intents"], "junta cumprimento e tudo bem (%s)" % str(r.get("_intents")))
	check(ask("ze", "").is_empty(), "frase vazia vai para a IA")
	check(ask("ze", "me explica como funciona a política de segredos dos mafiosos do porto e por que o prefeito deixa isso acontecer na cidade toda aqui").is_empty(), "frase longa vai para a IA")
	var p := ask("ze", "quanto custa a cerveja?")
	check(not p.is_empty() and ("R$ %d" % World.item_price("cerveja", "bar")) in str(p["fala"]), "preço da cerveja vem da loja: %s" % str(p.get("fala")))
	check(not ask("ze", "tem pão de forma?").is_empty(), "item que o bar não vende também é respondido")
	var menu := ask("ze", "o que vocês vendem?")
	check(not menu.is_empty() and "R$" in str(menu["fala"]), "cardápio lista preços: %s" % str(menu.get("fala")))
	var d := ask("ze", "onde fica o hospital?")
	check(not d.is_empty() and ("pro " in str(d["fala"])) and ("min" in str(d["fala"])), "direção com lado e minutos: %s" % str(d.get("fala")))
	check(not ask("ze", "como chego na delegacia").is_empty(), "delegacia")
	st["conhece_nome"] = false
	st["confianca"] = -20
	st["afeto"] = 0
	var n1 := ask("ze", "qual é o seu nome?")
	check(not n1.is_empty() and not n1["revela_nome"], "estranho hostil não revela o nome")
	st["confianca"] = 20
	st["afeto"] = 10
	st["suspeita"] = 0
	var n2 := ask("ze", "como você se chama?")
	check(not n2.is_empty() and n2["revela_nome"], "conhecido revela o nome")
	var mn := ask("ze", "meu nome é Rafa")
	check(not mn.is_empty() and mn["aprendeu_nome_jogador"], "aprende o nome do jogador")
	st["afeto"] = 2
	st["confianca"] = 5
	var nn := ask("ze", "me passa seu zap?")
	check(not nn.is_empty() and nn["acoes"].is_empty(), "sem afeto não passa o número")
	st["afeto"] = 30
	st["confianca"] = 25
	PhoneSystem.phone()["contacts"].erase("ze")
	var n3 := ask("ze", "me passa seu número?")
	check(not n3.is_empty() and not n3["acoes"].is_empty() and n3["acoes"][0]["tipo"] == "dar_numero", "com afeto passa o número")
	var ins := ask("ze", "seu idiota")
	check(not ins.is_empty() and int(ins["relacao"].get("afeto", 0)) < 0 and ins["emocao"] in ["irritado", "furioso", "assustado", "sarcastico"], "insulto irrita: %s" % ins.get("emocao"))
	var thr := ask("ze", "vou te matar")
	check(not thr.is_empty() and int(thr["relacao"].get("medo", 0)) > 0, "ameaça gera medo")
	var comp := ask("ze", "você é muito simpático")
	check(not comp.is_empty() and int(comp["relacao"].get("afeto", 0)) > 0, "elogio aproxima")
	check(ask("ze", "*pego a faca* quanto custa?").is_empty(), "ação de risco vai para a IA")
	check(not ask("ze", "*aceno* oi").is_empty(), "gesto simples é respondido")
	st["historico"].append({"role": "assistant", "content": "{\"fala\": \"Quer um quarto?\", \"emocao\": \"neutro\"}"})
	check(ask("ze", "sim").is_empty(), "sim depois de pergunta vai para a IA")
	st["historico"].clear()
	var seen := {}
	st["confianca"] = 30
	st["afeto"] = 30
	for i in 40:
		seen[str(ask("ze", "oi")["fala"])] = true
	check(seen.size() >= 12, "saudação varia (%d variações em 40 respostas)" % seen.size())
	var by_tone := {}
	for tone_case in [[-30, -30, "hostil"], [0, 0, "frio"], [20, 10, "neutro"], [30, 30, "amigavel"], [60, 50, "intimo"]]:
		st["confianca"] = tone_case[0]
		st["afeto"] = tone_case[1]
		st["suspeita"] = 0 if tone_case[2] != "frio" else 40
		check(Local.tone_of(st) == tone_case[2], "tom %s (%s)" % [tone_case[2], Local.tone_of(st)])
		by_tone[tone_case[2]] = str(ask("ze", "oi")["fala"])
	check(by_tone.size() == 5, "um tom para cada relação")
	st["confianca"] = 15
	st["afeto"] = 10
	st["suspeita"] = 0
	for id in NPCManager.npcs:
		var rr: Dictionary = Local.try_reply(id, "que horas são?", "presencial")
		check(not rr.is_empty() and str(rr["fala"]) != "" and not "{" in str(rr["fala"]), "%s responde sem sobras de modelo: %s" % [id, str(rr.get("fala"))])
	var bad := 0
	for intent in Local.Data.PATTERNS:
		var pats: Array = Local.Data.PATTERNS[intent]
		var r2: Dictionary = ask("ze", str(pats[0]).trim_suffix("*"))
		if not r2.is_empty() and ("{" in str(r2["fala"]) or "[" in str(r2["fala"])):
			bad += 1
			printerr("marcador solto: ", intent, " -> ", r2["fala"])
	check(bad == 0, "sem marcadores soltos nas respostas (%d)" % bad)
	var sts := Local.stats()
	print("BANCO LOCAL: ", sts)
	check(int(sts["condicoes"]) >= 5000 and int(sts["falas"]) >= 300 and int(sts["intencoes"]) >= 40, "banco com milhares de condições")
	var e1: String = Expr.detect("Kkk, essa foi boa! Haha!", "neutro")
	check(e1 == "rindo", "risada vira rindo (%s)" % e1)
	check(Expr.detect("Sinto muito, infelizmente morreu ontem...", "neutro") == "triste", "luto vira triste")
	check(Expr.detect("SOME DAQUI AGORA!!!", "neutro") in ["furioso", "irritado"], "gritaria vira raiva")
	check(Expr.detect("Quem é você? O que você quer aqui?", "neutro") == "desconfiado", "interrogatório vira desconfiado")
	check(Expr.detect("Por favor, não me machuque!", "neutro") == "assustado", "súplica vira medo")
	check(Expr.detect("Bom dia.", "feliz") == "feliz", "sem pista mantém a emoção base")
	var raw := "*sorri de canto* Claro, claro... genial. Vou chamar a polícia!"
	var plain := raw.replace("*", "")
	var segs := Expr.segments(raw, plain, "neutro")
	check(segs.size() >= 2 and int(segs[0]["start"]) == 0, "separa ação e frases (%d trechos)" % segs.size())
	check(str(segs[0]["emotion"]) in ["sarcastico", "feliz"], "ação sorri de canto é sarcástica (%s)" % str(segs[0]["emotion"]))
	print("RESULTADO DIALOGO: ", "OK" if fails.is_empty() else "%d falha(s)" % fails.size())
	get_tree().quit(0 if fails.is_empty() else 1)
