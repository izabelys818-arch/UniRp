extends Node

# Eventos aleatórios da cidade: apagão, greve, blitz, festa, tempestade, promoção, assaltos, gripe.

signal changed

const DEFS := {
	"apagao": {"nome": "Apagão", "horas": [6, 12], "peso": 1.0, "hora_ini": [17, 23],
		"titulo": "Apagão deixa a cidade no escuro", "texto": "Uma falha na subestação derrubou a energia em toda a cidade. Moradores usam velas e a companhia promete o retorno ainda hoje."},
	"greve": {"nome": "Greve do transporte", "horas": [24, 30], "peso": 0.8,
		"titulo": "Greve de motoristas pára o transporte", "texto": "Motoristas de aplicativo e táxi cruzaram os braços. Corridas disponíveis estão pelo dobro do preço."},
	"blitz": {"nome": "Blitz policial", "horas": [10, 14], "peso": 0.9,
		"titulo": "Polícia monta blitz pelos bairros", "texto": "Viaturas fecham ruas e revistam quem circula. Quem estiver carregando o que não deve que se cuide."},
	"festa": {"nome": "Festa na praça", "horas": [8, 8], "peso": 0.9, "hora_ini": [10, 16], "dias": [4, 5, 6],
		"titulo": "Festa de rua toma a Praça Central", "texto": "Barracas, música ao vivo e luzinhas coloridas. A prefeitura espera a cidade inteira na praça até meia-noite."},
	"tempestade": {"nome": "Tempestade", "horas": [12, 18], "peso": 0.9,
		"titulo": "Temporal castiga a cidade", "texto": "Chuva forte e ventania derrubam árvores. Defesa Civil pede que ninguém saia de casa sem necessidade."},
	"promocao": {"nome": "Promoção no mercado", "horas": [24, 24], "peso": 0.8,
		"titulo": "Mercado Bom Preço faz liquidação", "texto": "Itens com 30% de desconto durante todo o dia, enquanto durarem os estoques."},
	"assaltos": {"nome": "Onda de assaltos", "horas": [36, 48], "peso": 0.8,
		"titulo": "Onda de assaltos assusta moradores", "texto": "A polícia registrou um aumento de roubos nas ruas, principalmente à noite. Evite andar sozinho."},
	"gripe": {"nome": "Surto de gripe", "horas": [48, 72], "peso": 0.7,
		"titulo": "Surto de gripe lota o hospital", "texto": "Hospital São Lucas atende acima da capacidade. Muita gente está de cama e faltando ao trabalho."},
}
const BASE_RATE := 0.012


func _ready() -> void:
	TimeManager.time_advanced.connect(_on_time_advanced)


func state() -> Dictionary:
	if not GameState.player.has("events"):
		GameState.player["events"] = {"active": [], "next_arrival": TimeManager.day() + 4}
	return GameState.player["events"]


func active_list() -> Array:
	if not GameState.active:
		return []
	var now := TimeManager.total_minutes
	return state()["active"].filter(func(e): return now < int(e["ate"]))


func active(id: String) -> bool:
	return not active_list().filter(func(e): return e["id"] == id).is_empty()


func data_of(id: String) -> Dictionary:
	for e in active_list():
		if e["id"] == id:
			return e
	return {}


func labels() -> Array:
	return active_list().map(func(e): return DEFS[e["id"]]["nome"])


func start(id: String, hours: float = -1.0) -> void:
	if active(id):
		return
	var def: Dictionary = DEFS[id]
	if hours < 0.0:
		hours = randf_range(float(def["horas"][0]), float(def["horas"][1]))
	var ev := {"id": id, "ate": TimeManager.total_minutes + int(hours * 60.0)}
	if id == "festa":
		var guests: Array = NPCManager.npcs.keys().filter(func(k): return NPCManager.state[k].get("vivo", true) and randf() < 0.55)
		ev["convidados"] = guests
	if id == "gripe":
		for k in NPCManager.npcs:
			if NPCManager.state[k].get("vivo", true) and randf() < 0.25:
				NPCManager.state[k]["fora_ate"] = TimeManager.total_minutes + int(randf_range(1.0, 3.0) * 1440.0)
		if randf() < 0.3:
			NeedsSystem.apply({"saude": -12, "energia": -20})
			GameState.add_log("Você acorda com a garganta arranhando e o corpo pesado: pegou a gripe.", "danger")
	state()["active"].append(ev)
	NewsSystem.post(str(def["titulo"]), str(def["texto"]), "evento")
	GameState.add_log("NOTÍCIA: %s." % str(def["titulo"]), "phone")
	PhoneSystem.notify.emit(str(def["nome"]))
	changed.emit()
	GameState.player_changed.emit()


func stop(id: String) -> void:
	state()["active"] = state()["active"].filter(func(e): return e["id"] != id)
	changed.emit()


# ---------- efeitos consultados por outros sistemas ----------

func price_mult(loc_id: String) -> float:
	var m := 1.0
	if active("promocao") and loc_id == "mercado":
		m *= 0.7
	return m


func uber_mult() -> float:
	var m := 1.0
	if active("greve"):
		m *= 2.0
	if active("tempestade"):
		m *= 1.5
	return m


func power_out() -> bool:
	return active("apagao")


func raining() -> bool:
	if not GameState.active:
		return false
	if active("tempestade"):
		return true
	return (TimeManager.day() * 7 + 3) % 3 == 0 and (TimeManager.hour() >= 18 or TimeManager.hour() < 6)


func festa_on() -> bool:
	return active("festa") and TimeManager.hour() >= 17


func npc_override(npc_id: String) -> String:
	if festa_on() and npc_id in data_of("festa").get("convidados", []):
		return "praca"
	return ""


func actions() -> Array:
	if festa_on() and World.current_id() == "praca":
		return [{"id": "evt:festa", "label": "Curtir a festa (2h, R$ 20)"}]
	return []


func do(id: String) -> void:
	if id == "festa":
		if GameState.money() < 20:
			GameState.add_log("Você não tem R$ 20 para curtir a festa.", "info")
			return
		GameState.add_money(-20)
		TimeManager.advance(120)
		NeedsSystem.apply({"sanidade": 14, "saciedade": 10, "energia": -6})
		GameState.add_log("Dois pastéis, uma cerveja e muita música. Por duas horas a cidade parece outra.", "event")


# ---------- jogadas no caminho ----------

func travel_stop(mode: String = "ape") -> void:
	if not GameState.active:
		return
	if active("blitz") and randf() < 0.3 * World.mod("policia"):
		var tools := ["faca", "pe_de_cabra", "mixa", "droga"].filter(func(k): return GameState.item_count(k) > 0)
		if tools.is_empty():
			GameState.add_log("Numa blitz, um policial revista sua mochila e te libera depois de conferir os documentos.", "info")
			TimeManager.advance(10)
		else:
			GameState.add_log("Numa blitz, a revista encontra %s na sua mochila." % World.item_name(tools[0]).to_lower(), "danger")
			CrimeSystem.set_wanted(CrimeSystem.wanted() + 1)
			CrimeSystem.police_event()
	var night := TimeManager.hour() >= 21 or TimeManager.hour() < 5
	if mode == "ape" and night and GameState.money() > 30 and randf() < (0.35 if active("assaltos") else 0.04) * World.mod("crime"):
		var armed: bool = GameState.item_count("faca") > 0
		if armed and randf() < 0.5:
			GameState.add_log("Dois caras te encurralam, mas veem a faca na sua mão e recuam. Hoje você não perdeu nada.", "event")
			return
		var lost := int(GameState.money() * randf_range(0.25, 0.6))
		GameState.add_money(-lost)
		NeedsSystem.apply({"saude": -10, "sanidade": -12})
		GameState.add_log("ASSALTO: um homem puxa um revólver, leva R$ %d e some no escuro." % lost, "danger")
		NewsSystem.post("Assaltante ataca pedestre à noite", "Um morador foi rendido e levou o prejuízo de R$ %d. A polícia ainda não identificou o autor." % lost, "crime")


# ---------- tempo ----------

func _on_time_advanced(minutes: int, _sleeping: bool) -> void:
	if not GameState.active:
		return
	var st := state()
	var now := TimeManager.total_minutes
	st["active"] = st["active"].filter(func(e): return now < int(e["ate"]) + 1440)
	var steps := mini(int(minutes / 60.0), 72)
	var rate := BASE_RATE * World.mod("eventos")
	for i in steps:
		if active_list().size() >= 2 or randf() > rate:
			continue
		var pool: Array = []
		for id in DEFS:
			var def: Dictionary = DEFS[id]
			if active(id):
				continue
			if def.has("hora_ini") and not World.hour_in_range(TimeManager.hour(), int(def["hora_ini"][0]), int(def["hora_ini"][1])):
				continue
			if def.has("dias") and not ((TimeManager.day() - 1) % 7) in def["dias"]:
				continue
			for k in int(round(float(def["peso"]) * 10.0)):
				pool.append(id)
		if not pool.is_empty():
			start(pool.pick_random())
	if TimeManager.day() >= int(st["next_arrival"]):
		st["next_arrival"] = TimeManager.day() + int(randf_range(5.0, 9.0) / maxf(World.mod("eventos"), 0.5))
		Population.arrive()
	changed.emit()
