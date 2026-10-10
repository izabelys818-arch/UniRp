extends Node

# Moradores novos: gerados pela IA (OpenRouter) quando disponível, ou por sorteio coerente quando não.

signal resident_added(id: String)

const MAX_RESIDENTS := 14
const LOCAIS := ["praca", "bar", "mercado", "lanchonete", "hospital", "delegacia", "parque", "rodoviaria", "beco", "igreja", "pensao"]
const NOMES_M := ["Anderson", "Bruno", "Caio", "Davi", "Eduardo", "Fábio", "Gustavo", "Heitor", "Igor", "João", "Kleber", "Leandro", "Marcos", "Nelson", "Paulo", "Rafael", "Sérgio", "Vitor", "Wesley", "Edson", "Cláudio", "Rogério"]
const NOMES_F := ["Alice", "Carla", "Daniela", "Elaine", "Fernanda", "Gabriela", "Isabela", "Juliana", "Karina", "Luciana", "Mônica", "Natália", "Patrícia", "Renata", "Sônia", "Tatiane", "Valéria", "Zuleica"]
const SOBRENOMES := ["Almeida", "Barros", "Cardoso", "Dias", "Esteves", "Ferraz", "Gomes", "Henriques", "Junqueira", "Lacerda", "Macedo", "Nogueira", "Pacheco", "Queiroz", "Ramos", "Siqueira", "Teixeira", "Vidal", "Xavier"]
const CABELOS_F := [0, 3, 4, 5, 6, 7, 10, 11, 12]
const CABELOS_M := [0, 0, 1, 2, 3, 5, 6, 7, 8, 13]
const BARBAS_M := [0, 0, 1, 1, 2, 3, 4, 5]

# [rótulo masculino, rótulo feminino, idade min, idade max, rotina, dinheiro min, dinheiro max, roupas]
const PROFISSOES := [
	["motoboy", "motogirl", 20, 35, [[9, 13, "praca"], [18, 23, "lanchonete"]], 40, 160, [10, 0, 1]],
	["estudante", "estudante", 18, 24, [[9, 12, "parque"], [14, 18, "praca"]], 10, 80, [1, 0, 3]],
	["aposentado", "aposentada", 62, 78, [[7, 10, "praca"], [15, 18, "igreja"]], 150, 600, [0, 4, 8]],
	["pedreiro", "ajudante de obras", 28, 55, [[7, 12, "mercado"], [18, 22, "bar"]], 60, 300, [0, 6, 12]],
	["enfermeiro", "enfermeira", 24, 48, [[7, 19, "hospital"]], 150, 700, [10, 8, 0]],
	["guarda municipal", "guarda municipal", 26, 52, [[8, 17, "delegacia"]], 200, 800, [10, 0, 3]],
	["grafiteiro", "grafiteira", 19, 32, [[12, 18, "beco"], [20, 24, "bar"]], 20, 120, [1, 12, 0]],
	["vendedor de seguros", "vendedora de seguros", 30, 55, [[9, 17, "praca"]], 250, 1200, [4, 5, 8]],
	["diarista", "diarista", 28, 58, [[8, 15, "hospital"]], 60, 260, [0, 8, 7]],
	["mecânico", "mecânica", 26, 54, [[8, 18, "rodoviaria"]], 100, 500, [10, 0, 12]],
	["pescador", "pescadora", 30, 64, [[5, 10, "parque"], [18, 22, "bar"]], 30, 220, [0, 6, 12]],
	["apostador", "apostadora", 28, 60, [[14, 23, "bar"]], 40, 600, [0, 2, 9]],
	["barbeiro", "cabeleireira", 22, 50, [[9, 19, "beco"]], 100, 450, [3, 8, 0]],
	["vendedor ambulante", "vendedora ambulante", 22, 62, [[8, 18, "praca"]], 30, 200, [0, 3, 6]],
]
const PERSONALIDADES := [
	["tímido e observador; responde com poucas palavras, mas lembra de tudo", "frases curtas, olha para o chão"],
	["extrovertido e fofoqueiro, adora saber da vida dos outros", "fala rápido, interrompe, chama todo mundo de 'querido(a)'"],
	["azedo e desconfiado, acha que toda ajuda tem um preço", "seco, ironiza, resmunga"],
	["gentil demais, não sabe dizer não e se endivida para ajudar", "voz mansa, pede desculpa por tudo"],
	["ambicioso e calculista, sempre medindo o que pode ganhar", "polido, pergunta o que você faz da vida"],
	["nostálgico e sentimental, vive contando casos antigos", "cita 'no meu tempo', suspira muito"],
	["briguento, pavio curto, orgulhoso", "grosso, aponta o dedo, eleva a voz"],
	["paranoico, acha que está sendo seguido", "sussurra, olha para os lados"],
	["sonhador e artista, fala por metáforas", "poético, cheio de divagações"],
	["religioso fervoroso, vê pecado em tudo", "cita versículos, faz o sinal da cruz"],
]
const SEGREDOS := [
	["jogador compulsivo", "Deve R$ 4 mil a agiotas por causa de apostas e já vendeu o relógio da avó para pagar juros.", "Juntar dinheiro para quitar a dívida antes que cobrem à força."],
	["foragido", "Foge de outro estado por causa de um acidente em que alguém morreu. Usa nome falso.", "Passar despercebido e arrumar um documento novo."],
	["informante", "Passa informações sobre quem anda pela cidade para o Sargento Otávio, em troca de não ser incomodado.", "Manter o policial satisfeito para não ser preso."],
	["amante", "Tem um caso com uma pessoa casada da cidade e vive com medo de ser descoberto.", "Esconder o caso e escapar de um escândalo."],
	["ex-detento", "Cumpriu pena por roubo e esconde o passado de todo mundo.", "Recomeçar a vida sem que descubram a ficha."],
	["golpista", "Aplica golpes em idosos fingindo ser cobrador de seguro.", "Juntar o suficiente para sumir da cidade."],
	["cuidador", "Cuida sozinho de um parente doente em casa e gasta tudo em remédio.", "Conseguir dinheiro para o tratamento."],
	["testemunha", "Viu quem fez uma pessoa desaparecer no bairro e morre de medo de falar.", "Criar coragem para contar a alguém de confiança."],
	["em recuperação", "Está há 60 dias sem beber, e qualquer recaída destrói a chance de reaver a filha.", "Segurar a sobriedade e reconquistar a filha."],
	["herdeiro disfarçado", "Tem muito dinheiro de família, mas finge ser pobre para ver quem se aproxima por interesse.", "Descobrir em quem pode confiar de verdade."],
]

# Crianças e adolescentes (gerados por sorteio, nunca pela IA): manhã na escola (fora do mapa),
# tarde brincando na praça ou no parque. [rótulo m, rótulo f, idade mín, idade máx, rotina, dinheiro, roupas]
const JOVENS := [
	["menino", "menina", 6, 9, [[14, 18, "praca"]], 0, 10, [9, 0, 1]],
	["garoto", "garota", 9, 12, [[13, 17, "parque"], [17, 19, "praca"]], 2, 20, [9, 1, 0]],
	["adolescente", "adolescente", 13, 17, [[14, 18, "praca"], [18, 21, "lanchonete"]], 5, 60, [1, 9, 11, 0]],
]
const PERSONALIDADES_JOVENS := [
	["curioso e falador, pergunta tudo", "fala muito, pergunta 'por quê?' o tempo todo"],
	["tímido, se esconde atrás dos adultos", "fala baixinho, responde com uma palavra"],
	["bagunceiro e engraçado, vive aprontando", "ri de tudo, faz piada"],
	["sério e responsável demais para a idade", "fala como gente grande"],
	["emburrado, acha tudo chato", "responde com 'tanto faz', revira os olhos"],
]
const SEGREDOS_JOVENS := [
	["quebrou a janela", "Quebrou a janela do vizinho com a bola e ninguém sabe que foi ele.", "Juntar dinheiro para pagar a janela escondido."],
	["nota baixa", "Tirou nota vermelha e escondeu o boletim dos pais.", "Recuperar a nota antes que descubram."],
	["cachorro", "Está escondendo um cachorro de rua no quintal.", "Convencer a família a ficar com o cachorro."],
	["saudade", "Os pais se separaram e sente muita falta de um deles.", "Ver a mãe (ou o pai) de novo no fim de semana."],
	["bicicleta", "Junta moedas há meses para comprar uma bicicleta.", "Comprar a bicicleta antes do aniversário."],
]
const NOMES_BEBE := ["Miguel", "Arthur", "Theo", "Helena", "Alice", "Laura", "Davi", "Cecília", "Gael", "Maitê", "Ravi", "Liz"]
# cerca de um em cada quatro moradores novos é criança ou adolescente
const CHANCE_JOVEM := 0.28

var _busy: bool = false


func residents() -> Dictionary:
	if not GameState.player.has("residents"):
		GameState.player["residents"] = {}
	return GameState.player["residents"]


func count() -> int:
	return residents().size()


func override_location(npc_id: String) -> String:
	if not GameState.active or not residents().has(npc_id):
		return ""
	var arrived := int(residents()[npc_id]["chegou"])
	if arrived < 0 or TimeManager.total_minutes >= arrived + 1440:
		return ""
	return "rodoviaria" if World.hour_in_range(TimeManager.hour(), 8, 20) else ""


func restore() -> void:
	for id in residents():
		var r: Dictionary = residents()[id]
		NPCManager.npcs[id] = r["npc"]
		World.npc_looks[id] = r["look"]


# ---------- gerador procedural ----------

func _pick(arr: Array) -> Variant:
	return arr[randi() % arr.size()]


func random_look(female: bool, clothes: Array) -> Dictionary:
	var look := {
		"pele": randi() % 6, "tracos": randi() % 7, "corpo": [0, 1, 1, 1, 2, 3, 4, 6][randi() % 8], "rosto": randi() % 5,
		"cabelo": _pick(CABELOS_F if female else CABELOS_M), "cor_cabelo": [0, 0, 1, 1, 2, 3, 4, 5][randi() % 8],
		"olhos": randi() % 6, "barba": 0 if female else _pick(BARBAS_M), "roupa": _pick(clothes),
		"sobrancelha": randi() % 7, "marcas": [], "extras": [],
	}
	if randf() < 0.35:
		look["marcas"] = [[0, 6, 7, 9, 11, 15][randi() % 6]]
	return look


func describe_look(spec: Dictionary) -> String:
	var parts: Array = []
	for cat in World.appearance["categorias"]:
		var id: String = cat["id"]
		if id == "barba" and int(spec.get("barba", 0)) == 0:
			continue
		if id in ["sobrancelha", "altura"]:
			continue
		var idx := clampi(int(spec.get(id, 0)), 0, cat["opcoes"].size() - 1)
		var text: String = cat["opcoes"][idx][0]
		if id == "cor_cabelo":
			if int(spec.get("cabelo", 0)) == 1:
				continue
			text = "cabelo " + text
		parts.append(text)
	for m in spec.get("marcas", []):
		parts.append(World.appearance["marcas"][clampi(int(m), 0, World.appearance["marcas"].size() - 1)][0])
	return ", ".join(parts)


func nickname(female: bool, age: int, spec: Dictionary) -> String:
	var base := "Mulher" if female else "Homem"
	if age >= 60:
		base = "Senhora" if female else "Senhor"
	elif age < 13:
		base = "Menina" if female else "Menino"
	elif age < 18:
		base = "Adolescente"
	elif age <= 24:
		base = "Moça" if female else "Rapaz"
	var cats: Array = World.appearance["categorias"]
	var clothes_text := ""
	for cat in cats:
		if cat["id"] == "roupa":
			clothes_text = str(cat["opcoes"][clampi(int(spec.get("roupa", 0)), 0, cat["opcoes"].size() - 1)][0])
	var feature := ""
	if not female and int(spec.get("barba", 0)) >= 4:
		feature = " de barba " + ("longa" if int(spec.get("barba", 0)) == 5 else "cheia")
	return "%s%s, %s" % [base, feature, clothes_text]


func generate_young() -> Dictionary:
	var female := randf() < 0.5
	var prof: Array = _pick(JOVENS)
	var age := randi_range(int(prof[2]), int(prof[3]))
	var first: String = _pick(NOMES_F if female else NOMES_M)
	var surname: String = _pick(SOBRENOMES)
	var pers: Array = _pick(PERSONALIDADES_JOVENS)
	var sec: Array = _pick(SEGREDOS_JOVENS)
	var look := random_look(female, prof[7])
	look["barba"] = 0
	look["marcas"] = [6] if randf() < 0.25 else []
	var rotina: Array = []
	for slot in prof[4]:
		rotina.append({"de": int(slot[0]), "ate": int(slot[1]), "local": str(slot[2])})
	return _finalize({
		"nome": "%s %s" % [first, surname], "genero": "mulher" if female else "homem", "idade": age,
		"profissao": str(prof[1] if female else prof[0]) + " (estuda de manhã)", "personalidade": str(pers[0]), "jeito_de_falar": str(pers[1]),
		"tracos_ocultos": [str(sec[0])], "segredo": str(sec[1]), "objetivo": str(sec[2]),
		"dinheiro": randi_range(int(prof[5]), int(prof[6])), "rotina": rotina, "visual": look,
	})


func generate_procedural() -> Dictionary:
	if randf() < CHANCE_JOVEM:
		return generate_young()
	var female := randf() < 0.5
	var prof: Array = _pick(PROFISSOES)
	var age := randi_range(int(prof[2]), int(prof[3]))
	var first: String = _pick(NOMES_F if female else NOMES_M)
	var name_full := "%s %s" % [first, _pick(SOBRENOMES)]
	var pers: Array = _pick(PERSONALIDADES)
	var sec: Array = _pick(SEGREDOS)
	var look := random_look(female, prof[7])
	var rotina: Array = []
	for slot in prof[4]:
		rotina.append({"de": int(slot[0]), "ate": int(slot[1]), "local": str(slot[2])})
	var baby := {}
	if age >= 20 and age <= 42 and randf() < 0.3:
		baby = {"nome": _pick(NOMES_BEBE), "meses": randi_range(2, 20)}
	return _finalize({
		"bebe": baby,
		"nome": name_full, "genero": "mulher" if female else "homem", "idade": age,
		"profissao": str(prof[1] if female else prof[0]), "personalidade": str(pers[0]), "jeito_de_falar": str(pers[1]),
		"tracos_ocultos": [str(sec[0])], "segredo": str(sec[1]), "objetivo": str(sec[2]),
		"dinheiro": randi_range(int(prof[5]), int(prof[6])), "rotina": rotina, "visual": look,
	})


# ---------- gerador por IA ----------

func _ai_prompt() -> Array:
	var cats: Dictionary = {}
	for cat in World.appearance["categorias"]:
		cats[cat["id"]] = cat["opcoes"].map(func(o): return o[0])
	var names: Array = NPCManager.npcs.keys().map(func(k): return NPCManager.npcs[k]["nome"])
	var sys := "Você cria moradores para um RPG noir brasileiro (cidade %s; tom: %s). Responda SOMENTE com um objeto JSON válido, sem comentários." % [GameState.city(), World.scenario()["tom"]]
	var user := """Crie UM morador novo, original, com segredo e objetivo próprios. Evite estes nomes: %s.
Campos obrigatórios: nome (nome e sobrenome brasileiros), genero ("homem" ou "mulher"), idade (18 a 80), profissao, personalidade, jeito_de_falar, tracos_ocultos (lista com 1 ou 2 textos curtos), segredo (1 frase, algo que ele esconde), objetivo (1 frase), dinheiro (inteiro 10 a 2500), rotina (lista de 1 a 3 objetos {"de": hora, "ate": hora, "local": id}), visual.
Locais válidos para a rotina: %s.
visual é um objeto de ÍNDICES (números a partir de 0) que escolhe as opções: %s. Use no máximo 2 itens em marcas (índices de: %s). Escolha um visual coerente com a idade, o gênero e a profissão.""" % [", ".join(names), ", ".join(LOCAIS), JSON.stringify(cats), JSON.stringify(World.appearance["marcas"].map(func(m): return m[0]))]
	return [{"role": "system", "content": sys}, {"role": "user", "content": user}]


func _sanitize(raw: Dictionary) -> Dictionary:
	if str(raw.get("nome", "")).strip_edges() == "" or str(raw.get("profissao", "")) == "" or str(raw.get("segredo", "")) == "":
		return {}
	var female := str(raw.get("genero", "")) == "mulher"
	if not str(raw.get("genero", "")) in ["homem", "mulher"]:
		female = randf() < 0.5
	var look: Dictionary = {}
	var visual = raw.get("visual", {})
	if typeof(visual) != TYPE_DICTIONARY:
		visual = {}
	for cat in World.appearance["categorias"]:
		var limit: int = cat["opcoes"].size() - 1
		look[cat["id"]] = clampi(int(visual.get(cat["id"], randi() % (limit + 1))), 0, limit)
	if female:
		look["barba"] = 0
	var marks: Array = []
	var raw_marks = visual.get("marcas", [])
	if typeof(raw_marks) == TYPE_ARRAY:
		for m in raw_marks.slice(0, 2):
			marks.append(clampi(int(m), 0, World.appearance["marcas"].size() - 1))
	look["marcas"] = marks
	look["extras"] = []
	var rotina: Array = []
	var raw_r = raw.get("rotina", [])
	if typeof(raw_r) == TYPE_ARRAY:
		for slot in raw_r.slice(0, 3):
			if typeof(slot) == TYPE_DICTIONARY and str(slot.get("local", "")) in LOCAIS:
				rotina.append({"de": clampi(int(slot.get("de", 8)), 0, 23), "ate": clampi(int(slot.get("ate", 18)), 1, 24), "local": str(slot["local"])})
	if rotina.is_empty():
		rotina = [{"de": 9, "ate": 17, "local": "praca"}]
	var hidden: Array = []
	var raw_h = raw.get("tracos_ocultos", [])
	if typeof(raw_h) == TYPE_ARRAY:
		for h in raw_h.slice(0, 2):
			hidden.append(str(h))
	return {
		"nome": str(raw["nome"]).strip_edges(), "genero": "mulher" if female else "homem", "idade": clampi(int(raw.get("idade", 35)), 18, 80),
		"profissao": str(raw["profissao"]), "personalidade": str(raw.get("personalidade", "reservado")), "jeito_de_falar": str(raw.get("jeito_de_falar", "fala normal")),
		"tracos_ocultos": hidden, "segredo": str(raw["segredo"]), "objetivo": str(raw.get("objetivo", "viver em paz")),
		"dinheiro": clampi(int(raw.get("dinheiro", 100)), 10, 2500), "rotina": rotina, "visual": look,
	}


func generate_ai() -> Dictionary:
	var res: Dictionary = await AIService.chat(_ai_prompt(), 900)
	if not res["ok"]:
		return {}
	var text: String = res["text"]
	var a := text.find("{")
	var b := text.rfind("}")
	if a == -1 or b <= a:
		return {}
	var parsed = JSON.parse_string(text.substr(a, b - a + 1))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var clean := _sanitize(parsed)
	return _finalize(clean) if not clean.is_empty() else {}


func _finalize(base: Dictionary) -> Dictionary:
	var female := str(base["genero"]) == "mulher"
	var look: Dictionary = base["visual"]
	var npc := {
		"nome": base["nome"], "apelido_visual": nickname(female, int(base["idade"]), look), "idade": base["idade"], "genero": base["genero"],
		"profissao": base["profissao"], "aparencia": describe_look(look), "personalidade": base["personalidade"], "jeito_de_falar": base["jeito_de_falar"],
		"tracos_ocultos": base["tracos_ocultos"], "segredo": base["segredo"], "objetivo": base["objetivo"], "dinheiro": base["dinheiro"],
		"cor": "#" + Color.from_hsv(randf(), randf_range(0.25, 0.5), randf_range(0.45, 0.7)).to_html(false),
		"rotina": base["rotina"],
	}
	if not base.get("bebe", {}).is_empty():
		npc["bebe"] = base["bebe"]
		npc["aparencia"] += ", empurrando um carrinho de bebê"
	return {"npc": npc, "look": look}


# ---------- entrada no mundo ----------

func add_resident(entry: Dictionary, arrived: bool) -> String:
	var n: int = int(GameState.player.get("residents_next", 1))
	GameState.player["residents_next"] = n + 1
	var id := "g%d" % n
	residents()[id] = {"npc": entry["npc"], "look": entry["look"], "chegou": TimeManager.total_minutes if arrived else -1}
	NPCManager.npcs[id] = entry["npc"]
	World.npc_looks[id] = entry["look"]
	NPCManager.state[id] = NPCManager.make_state(id, false)
	resident_added.emit(id)
	return id


# Começo de jogo: o primeiro morador é criança ou adolescente e o segundo sai com o bebê,
# para a cidade ter todas as idades desde o início.
func populate(n: int) -> void:
	for i in n:
		if count() >= MAX_RESIDENTS:
			return
		var entry := generate_young() if i == 0 else generate_procedural()
		if i == 1:
			var npc: Dictionary = entry["npc"]
			if int(npc["idade"]) >= 20 and int(npc["idade"]) <= 45 and not npc.has("bebe"):
				npc["bebe"] = {"nome": _pick(NOMES_BEBE), "meses": randi_range(3, 14)}
				npc["aparencia"] += ", empurrando um carrinho de bebê"
		add_resident(entry, false)


func arrive() -> void:
	if _busy or count() >= MAX_RESIDENTS or not GameState.active:
		return
	_busy = true
	var entry: Dictionary = {}
	if Settings.is_ready() or AIService.mock.is_valid():
		entry = await generate_ai()
	if entry.is_empty():
		entry = generate_procedural()
	_busy = false
	if not GameState.active:
		return
	var id := add_resident(entry, true)
	var npc: Dictionary = entry["npc"]
	NewsSystem.post("Novo morador chega à cidade", "Um(a) %s desembarcou na rodoviária com as malas e disse que veio para ficar." % str(npc["profissao"]), "cidade")
	GameState.add_log("Alguém novo chegou à cidade: %s." % str(npc["apelido_visual"]).to_lower(), "phone")
	if World.current_id() == "rodoviaria":
		GameState.add_log("Na plataforma da rodoviária, %s desce de um ônibus e olha em volta." % str(npc["apelido_visual"]).to_lower(), "narration")
	GameState.player_changed.emit()
