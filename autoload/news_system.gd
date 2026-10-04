extends Node

# Jornal da cidade: edição diária feita das notícias do jogo, com enchimento de colunas.

signal posted(entry: Dictionary)

const MAX_ENTRIES := 80
const WEATHER := ["Céu aberto e calor de 31 graus.", "Nublado, com pancadas de chuva à tarde.", "Frente fria chega e derruba a temperatura.", "Sol forte e ar seco, beba bastante água.", "Madrugada de neblina, manhã abafada."]
const HOROSCOPE := ["Aquário: desconfie de quem sorri demais.", "Touro: dinheiro curto pede paciência.", "Câncer: uma mensagem antiga volta a te procurar.", "Leão: hoje o orgulho custa caro.", "Escorpião: não confie em segredos alheios.", "Gêmeos: cuidado com promessas fáceis."]
const FILLER := [
	["Preço do pão sobe e consumidor reclama", "Padarias do centro reajustaram o pãozinho em 8%. A associação do comércio culpa o preço da farinha."],
	["Prefeitura promete tapar buracos da Rua 7", "O prazo, segundo o secretário de obras, é de 'algumas semanas'. Moradores já ouviram isso antes."],
	["Cachorro perdido faz sucesso na praça", "O vira-lata caramelo passeia entre os bancos e já ganhou três apelidos dos frequentadores."],
	["Igreja de Santa Rita recebe doações para a reforma", "O padre agradece e pede ajuda com os vitrais quebrados e o telhado."],
	["Taxistas reclamam da concorrência dos aplicativos", "Na rodoviária, a fila de táxis cresce enquanto as corridas diminuem."],
	["Hospital São Lucas pede doação de sangue", "Os estoques do banco de sangue estão abaixo do nível de segurança."],
]


func _ready() -> void:
	TimeManager.time_advanced.connect(_on_time_advanced)


func entries() -> Array:
	if not GameState.player.has("news"):
		GameState.player["news"] = []
	return GameState.player["news"]


func post(title: String, text: String, kind: String = "cidade") -> void:
	if not GameState.active:
		return
	var e := {"dia": TimeManager.day(), "hora": TimeManager.hour(), "titulo": title, "texto": text, "tipo": kind}
	entries().append(e)
	if entries().size() > MAX_ENTRIES:
		entries().pop_front()
	posted.emit(e)


func edition(day: int) -> Array:
	return entries().filter(func(e): return int(e["dia"]) == day)


func days_with_news() -> Array:
	var days: Array = []
	for e in entries():
		if not int(e["dia"]) in days:
			days.append(int(e["dia"]))
	days.sort()
	days.reverse()
	return days


# Garante colunas fixas (clima, horóscopo e uma nota leve) na edição do dia.
func ensure_columns() -> void:
	var day := TimeManager.day()
	for e in edition(day):
		if e["tipo"] == "coluna":
			return
	var seed_i := day * 31
	post("Tempo", WEATHER[seed_i % WEATHER.size()], "coluna")
	post("Horóscopo do dia", HOROSCOPE[seed_i % HOROSCOPE.size()], "coluna")
	var f: Array = FILLER[day % FILLER.size()]
	post(f[0], f[1], "cidade")


func _on_time_advanced(_minutes: int, _sleeping: bool) -> void:
	if not GameState.active:
		return
	if TimeManager.hour() >= 6 and not GameState.player.get("news_dia", 0) == TimeManager.day():
		GameState.player["news_dia"] = TimeManager.day()
		ensure_columns()
		PhoneSystem.notify.emit("Jornal de hoje no celular")
		_polish.call_deferred()


# Com a IA configurada, reescreve as manchetes de ontem num tom de jornal de verdade.
func _polish() -> void:
	if not Settings.is_ready() and not AIService.mock.is_valid():
		return
	var pending: Array = entries().filter(func(e): return e["tipo"] in ["crime", "evento", "cidade"] and not e.get("polido", false) and int(e["dia"]) < TimeManager.day())
	if pending.is_empty():
		return
	pending = pending.slice(0, 4)
	var raw: Array = pending.map(func(e): return {"titulo": e["titulo"], "texto": e["texto"]})
	var msgs: Array = [
		{"role": "system", "content": "Você é editor do jornal de uma cidade brasileira fictícia (%s, tom: %s). Reescreva cada notícia em português do Brasil, estilo de jornal local, com título curto e texto de até 2 frases. Responda SOMENTE com um array JSON de objetos com os campos titulo e texto, na mesma ordem." % [GameState.city(), World.scenario()["tom"]]},
		{"role": "user", "content": JSON.stringify(raw)},
	]
	var res: Dictionary = await AIService.chat(msgs, 700)
	if not res["ok"]:
		return
	var text: String = res["text"]
	var a := text.find("[")
	var b := text.rfind("]")
	if a == -1 or b <= a:
		return
	var parsed = JSON.parse_string(text.substr(a, b - a + 1))
	if typeof(parsed) != TYPE_ARRAY:
		return
	for i in mini(parsed.size(), pending.size()):
		if typeof(parsed[i]) == TYPE_DICTIONARY and str(parsed[i].get("titulo", "")) != "":
			pending[i]["titulo"] = str(parsed[i]["titulo"])
			pending[i]["texto"] = str(parsed[i].get("texto", pending[i]["texto"]))
			pending[i]["polido"] = true
