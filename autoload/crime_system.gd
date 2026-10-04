extends Node

signal choice(data: Dictionary)
signal wanted_changed(stars: int)

const STRENGTH := {
	"ruan": 8, "otavio": 7, "silas": 7, "ze": 5, "tiago": 5, "gabriel": 4, "leo": 4, "marina": 4,
	"vanessa": 4, "irene": 4, "helena": 5, "bia": 3, "kaio": 3, "padre": 2, "dona_cida": 2,
}
const NO_SNITCH := ["ruan", "ze", "silas", "helena", "kaio", "tiago"]
const PSYCHOS := ["helena", "silas"]
const MAX_STARS := 5

var police_lights: bool = false
var _choice_open: bool = false
var _last_psycho: int = -9999


func _ready() -> void:
	TimeManager.time_advanced.connect(_on_time_advanced)


func data() -> Dictionary:
	var p: Dictionary = GameState.player
	if not p.has("crime"):
		p["crime"] = {"wanted": 0, "last_crime": -9999, "record": [], "pistas": [], "invadidos": {}, "agressor": {}, "corpos": [], "fire": {}}
	return p["crime"]


func wanted() -> int:
	if not GameState.active:
		return 0
	return int(data()["wanted"])


func set_wanted(n: int) -> void:
	data()["wanted"] = clampi(n, 0, MAX_STARS)
	wanted_changed.emit(wanted())
	GameState.player_changed.emit()


# ---------- crimes e testemunhas ----------

func commit(kind: String, label: String, severity: int, victim: String = "") -> void:
	var d := data()
	d["record"].append({"tipo": kind, "desc": label, "hora": TimeManager.clock_str()})
	d["last_crime"] = TimeManager.total_minutes
	var witnesses: Array = NPCManager.npcs_here().filter(func(w): return w != victim)
	var reporters: Array = []
	for w in witnesses:
		var st: Dictionary = NPCManager.state[w]
		st["memorias"].append("[%s] Vi o jogador %s." % [TimeManager.clock_str(), label])
		st["medo"] = mini(int(st["medo"]) + 20, 100)
		st["suspeita"] = mini(int(st["suspeita"]) + 25, 100)
		st["confianca"] = maxi(int(st["confianca"]) - 20, -100)
		if not w in NO_SNITCH:
			reporters.append(w)
	if not reporters.is_empty():
		var who := NPCManager.display_name(reporters[0])
		GameState.add_log("%s viu tudo e ligou para a polícia." % who, "danger")
		set_wanted(wanted() + _stars_for(severity))
	elif not witnesses.is_empty():
		GameState.add_log("%s viu tudo, mas ficou de boca fechada." % NPCManager.display_name(witnesses[0]), "event")


func _stars_for(severity: int) -> int:
	return clampi(int(ceil(severity * 0.8)), 1, MAX_STARS)


func npc_attacked_player(id: String) -> void:
	data()["agressor"] = {"id": id, "hora": TimeManager.total_minutes}


func npc_called_police(_id: String) -> void:
	if TimeManager.total_minutes - int(data()["last_crime"]) < 360:
		set_wanted(wanted() + 1)


# ---------- combate ----------

func best_weapon() -> String:
	for w in ["faca", "pe_de_cabra"]:
		if GameState.item_count(w) > 0:
			return w
	return ""


func player_attack(id: String, weapon: String = "") -> void:
	if NPCManager.busy or not GameState.active or NPCManager.location_of(id) != World.current_id():
		return
	if weapon != "" and GameState.item_count(weapon) <= 0:
		weapon = ""
	var st: Dictionary = NPCManager.state[id]
	var who := NPCManager.display_name(id)
	var strong := GameState.has_trait("forte")
	var hit_chance := 0.8 - int(STRENGTH.get(id, 5)) * 0.025 + (0.1 if strong else 0.0) + (NeedsSystem.get_value("energia") - 50.0) / 400.0
	var dmg := 0
	if weapon != "":
		var r: Array = World.items[weapon].get("dano", [15, 25])
		dmg = randi_range(int(r[0]), int(r[1]))
	else:
		dmg = randi_range(8, 16) + (6 if strong else 0)
	var how := ("com %s" % World.item_name(weapon).to_lower()) if weapon != "" else "com um soco"
	NeedsSystem.apply({"energia": -5})
	TimeManager.advance(1)
	if randf() > hit_chance:
		commit("agressao", "tentar agredir %s %s" % [who, how], 1, id)
		NPCManager.event_turn(id, "Você parte para cima de %s %s, mas erra." % [who, how],
			"O jogador tentou te atacar %s e errou por pouco. Reaja: revide, fuja, grite por ajuda ou chame a polícia, conforme quem você é." % how)
		return
	st["saude"] = int(st.get("saude", 100)) - dmg
	if int(st["saude"]) <= 0:
		kill_npc(id, how)
		return
	if int(st["saude"]) < 50:
		st["internar_em"] = TimeManager.total_minutes + 45
	commit("agressao" if weapon == "" else "lesao", "agredir %s %s" % [who, how], 1 if weapon == "" else 3, id)
	NPCManager.event_turn(id, "Você acerta %s %s." % [who, how],
		"O jogador te atacou %s e te acertou em cheio. Sua saúde agora é %d/100. Reaja de verdade: revide ('atacar'), fuja ('fugir'), implore, ou chame a polícia ('chamar_policia'), conforme quem você é." % [how, int(st["saude"])])


func kill_npc(id: String, how: String) -> void:
	var st: Dictionary = NPCManager.state[id]
	var who := NPCManager.display_name(id)
	st["vivo"] = false
	st["saude"] = 0
	NPCManager.end_conversation()
	GameState.add_log("Você atinge %s %s. %s cai no chão e não se levanta mais." % [who, how, who], "death")
	NeedsSystem.apply({"sanidade": -25})
	data()["corpos"].append({"id": id, "local": World.current_id(), "hora": TimeManager.total_minutes, "achado": false})
	commit("homicidio", "matar %s" % who, 5, id)


func pickpocket(id: String) -> void:
	if NPCManager.busy or not GameState.active or NPCManager.location_of(id) != World.current_id():
		return
	var st: Dictionary = NPCManager.state[id]
	var who := NPCManager.display_name(id)
	var skill := 0.45 + (0.15 if GameState.has_trait("mentiroso") else 0.0) + (0.1 if GameState.has_trait("frio") else 0.0) - int(st["suspeita"]) / 200.0
	TimeManager.advance(2)
	if randf() < skill:
		var amount := mini(int(int(st["dinheiro"]) * randf_range(0.3, 0.7)), 300)
		st["dinheiro"] = int(st["dinheiro"]) - amount
		GameState.add_money(amount)
		data()["record"].append({"tipo": "furto", "desc": "furtar %s" % who, "hora": TimeManager.clock_str()})
		GameState.add_log("Você surrupia R$ %d da carteira de %s sem ser notado." % [amount, who], "event")
		if randf() < 0.2:
			commit("furto", "furtar a carteira de %s" % who, 1, id)
		return
	st["suspeita"] = mini(int(st["suspeita"]) + 30, 100)
	commit("furto", "tentar roubar a carteira de %s" % who, 1, id)
	NPCManager.event_turn(id, "Você tenta pegar a carteira de %s... e é pego no flagra." % who,
		"O jogador tentou roubar sua carteira e você percebeu na hora, com a mão dele no seu bolso. Reaja conforme quem você é.")


# ---------- polícia ----------

func police_event() -> void:
	if _choice_open or not GameState.active:
		return
	_choice_open = true
	police_lights = true
	var stars := wanted()
	var otavio: bool = NPCManager.state["otavio"].get("vivo", true) and randf() < 0.6
	var cop := "O Sargento Otávio" if otavio else "Uma viatura da PM"
	var bribe := 150 * stars
	var bribe_chance := 0.85 if otavio else 0.3
	NPCManager.end_conversation()
	var options: Array = [
		{"label": "Se render", "callback": arrest},
		{"label": "Fugir", "callback": flee},
	]
	if GameState.money() >= bribe:
		options.append({"label": "Oferecer R$ %d por fora" % bribe, "callback": bribe_police.bind(bribe, bribe_chance)})
	GameState.add_log("Sirenes. %s encosta e te cerca." % cop, "danger")
	choice.emit({"title": "POLÍCIA!", "text": "%s te reconhece. \"Mão na cabeça! Encosta na parede!\"\nVocê está sendo procurado (%d estrela%s)." % [cop, stars, "" if stars == 1 else "s"], "options": options, "kind": "police"})


func _close_choice() -> void:
	_choice_open = false
	police_lights = false


func arrest() -> void:
	_close_choice()
	var stars := maxi(wanted(), 1)
	NewsSystem.post("Procurado é preso em flagrante", "%s foi detido pela polícia e responderá pelos crimes registrados. A fiança foi paga." % str(GameState.player.get("name", "Um homem")), "crime")
	var days := stars
	var fine := mini(GameState.money(), 100 * stars)
	var lost: Array = []
	for item in ["faca", "pe_de_cabra", "mixa"]:
		if GameState.item_count(item) > 0:
			lost.append(World.item_name(item))
			GameState.player["inventory"].erase(item)
	GameState.add_money(-fine)
	GameState.active = false
	TimeManager.advance(days * 1440, true)
	GameState.active = true
	NeedsSystem.reset({"saude": NeedsSystem.get_value("saude"), "saciedade": 45, "hidratacao": 55, "energia": 60, "higiene": 15, "sanidade": maxf(NeedsSystem.get_value("sanidade") - 20.0, 5.0)})
	GameState.player["location"] = "delegacia"
	data()["record"].append({"tipo": "prisao", "desc": "preso por %d dia(s)" % days, "hora": TimeManager.clock_str()})
	set_wanted(0)
	var text := "Você passou %d dia(s) numa cela fedida da 4ª DP. Pagou R$ %d de fiança%s." % [days, fine, (" e perdeu: " + ", ".join(lost)) if not lost.is_empty() else ""]
	GameState.add_log(text, "narration")
	World.location_changed.emit("delegacia")
	choice.emit({"title": "SOLTO", "text": text, "options": [{"label": "Sair da delegacia", "callback": func(): pass}], "kind": "info"})
	SaveManager.save_game()


func flee() -> void:
	_close_choice()
	var chance := 0.35 + (0.15 if GameState.has_trait("forte") else 0.0) + NeedsSystem.get_value("energia") / 400.0 - 0.05 * wanted()
	if randf() < chance:
		NeedsSystem.apply({"energia": -20, "sanidade": -5})
		TimeManager.advance(15)
		var escape := "beco" if World.current_id() != "beco" else "praca"
		GameState.player["location"] = escape
		GameState.add_log("Você corta por entre os carros e corre até o %s. Conseguiu despistar a polícia... por enquanto." % World.locations[escape]["nome"], "event")
		World.location_changed.emit(escape)
	else:
		NeedsSystem.apply({"saude": -10})
		GameState.add_log("Você tenta correr, mas é derrubado no chão e algemado.", "danger")
		set_wanted(wanted() + 1)
		arrest()


func bribe_police(amount: int, chance: float) -> void:
	_close_choice()
	GameState.add_money(-amount)
	if randf() < chance:
		set_wanted(0)
		GameState.add_log("O policial olha para os lados, embolsa os R$ %d e vai embora como se nada tivesse acontecido." % amount, "event")
	else:
		GameState.add_log("\"Tá querendo me comprar?\" O policial fica furioso. Agora é corrupção ativa também.", "danger")
		set_wanted(wanted() + 1)
		arrest()


# ---------- invasões ----------

func tool_for_breaking() -> String:
	for t in ["mixa", "pe_de_cabra"]:
		if GameState.item_count(t) > 0:
			return t
	return ""


func burglary_actions() -> Array:
	var out: Array = []
	var id := World.current_id()
	var loc := World.current()
	var invaded: Dictionary = data()["invadidos"]
	if loc.has("arrombavel") and not World.is_open(id) and not fire_at(id) and int(invaded.get(id, -1)) != TimeManager.day():
		out.append({"id": "arrombar", "label": "Arrombar a porta"})
	for casa in loc.get("casas", []):
		if int(invaded.get(casa["id"], -1)) != TimeManager.day():
			out.append({"id": "invadir:" + str(casa["id"]), "label": "Invadir: " + str(casa["nome"])})
	return out


func break_into_shop() -> void:
	var id := World.current_id()
	var loc := World.current()
	var info: Dictionary = loc.get("arrombavel", {})
	var tool := tool_for_breaking()
	if tool == "":
		GameState.add_log("Você não tem nada para arrombar a porta. Um pé de cabra ou umas mixas resolveriam.", "info")
		return
	TimeManager.advance(20)
	var success := randf() < float(World.items[tool]["arrombar"]) + (0.1 if GameState.has_trait("inteligente") else 0.0)
	data()["invadidos"][id] = TimeManager.day()
	var alarm := float(info.get("alarme", 0.3)) + (-0.1 if World.items[tool].get("silencioso", false) else 0.15)
	if not success:
		GameState.add_log("A fechadura não cede. Você faz barulho demais tentando.", "event")
		if randf() < alarm:
			_alarm(loc["nome"])
		return
	var cash: Array = info.get("caixa", [50, 150])
	var money := randi_range(int(cash[0]), int(cash[1]))
	GameState.add_money(money)
	var taken: Array = []
	var pool: Array = info.get("itens", [])
	for i in mini(2, pool.size()):
		var it: String = pool.pick_random()
		GameState.add_item(it)
		taken.append(World.item_name(it))
	GameState.add_log("A porta cede. Você entra no escuro, esvazia o caixa (R$ %d) e pega: %s." % [money, ", ".join(taken)], "event")
	data()["record"].append({"tipo": "arrombamento", "desc": "arrombar %s" % loc["nome"], "hora": TimeManager.clock_str()})
	data()["last_crime"] = TimeManager.total_minutes
	if randf() < alarm:
		_alarm(loc["nome"])


func _alarm(place: String) -> void:
	GameState.add_log("UM ALARME DISPARA em %s! As luzes piscam e uma sirene ecoa pela rua." % place, "danger")
	set_wanted(wanted() + 2)
	police_event()


func invade_house(casa_id: String) -> void:
	var casa: Dictionary = {}
	for c in World.current().get("casas", []):
		if c["id"] == casa_id:
			casa = c
	if casa.is_empty():
		return
	var tool := tool_for_breaking()
	if tool == "":
		GameState.add_log("O portão está trancado. Sem uma ferramenta, não tem como entrar.", "info")
		return
	TimeManager.advance(25)
	data()["invadidos"][casa_id] = TimeManager.day()
	var witnesses := NPCManager.npcs_here()
	if not witnesses.is_empty() and randf() < 0.6:
		commit("invasao", "invadir uma casa", 2)
	if randf() > float(World.items[tool]["arrombar"]):
		GameState.add_log("A fechadura não cede e um cachorro começa a latir alto. Melhor sair daqui.", "event")
		if randf() < float(casa.get("alarme", 0.3)):
			_alarm(casa["nome"])
		return
	var owner: String = casa.get("dono", "")
	if owner != "" and NPCManager.is_home(owner) and (TimeManager.is_night() or randf() < 0.3):
		_house_encounter(owner, casa)
		return
	var cash: Array = casa.get("dinheiro", [100, 300])
	var money := randi_range(int(cash[0]), int(cash[1]))
	GameState.add_money(money)
	var pool: Array = casa.get("itens", [])
	if not pool.is_empty():
		GameState.add_item(pool.pick_random())
	data()["record"].append({"tipo": "invasao", "desc": "invadir %s" % casa["nome"], "hora": TimeManager.clock_str()})
	data()["last_crime"] = TimeManager.total_minutes
	GameState.add_log("Você entra na casa em silêncio e acha R$ %d escondidos numa gaveta." % money, "event")
	var pista := str(casa.get("pista", ""))
	if pista != "" and not pista in data()["pistas"]:
		data()["pistas"].append(pista)
		GameState.add_log(pista, "narration")
		GameState.add_log("Pista anotada na sua bolsa.", "event")
	if owner != "":
		NPCManager.state[owner]["memorias"].append("[%s] Alguém invadiu minha casa e mexeu nas minhas coisas." % TimeManager.clock_str())
	if randf() < float(casa.get("alarme", 0.3)):
		_alarm(casa["nome"])


func _house_encounter(owner: String, casa: Dictionary) -> void:
	var owner_name: String = NPCManager.npcs[owner]["nome"]
	NPCManager.state[owner]["memorias"].append("[%s] Peguei o jogador invadindo minha casa. Vi o rosto dele." % TimeManager.clock_str())
	NPCManager.state[owner]["suspeita"] = 100
	if owner in PSYCHOS:
		GameState.add_log("Uma luz acende. %s está parada no alto da escada, de camisola, segurando um bisturi. Ela sorri." % owner_name, "danger")
		if randf() < 0.45 + (0.15 if GameState.has_trait("forte") else 0.0):
			NeedsSystem.apply({"saude": -12, "sanidade": -20})
			GameState.add_log("Você se joga pela janela e corre sangrando até a rua.", "event")
		else:
			GameState.add_log("Ela é rápida demais. O bisturi rasga seu braço antes de você conseguir fugir.", "danger")
			NeedsSystem.apply({"saude": -35, "sanidade": -30}, "atacado por %s" % owner_name)
	else:
		GameState.add_log("%s acorda gritando e liga para a polícia na sua frente." % owner_name, "danger")
		set_wanted(wanted() + 2)
		police_event()


# ---------- noite ----------

func night_intrusion() -> bool:
	var silas: Dictionary = NPCManager.state["silas"]
	if not silas.get("vivo", true) or not silas.get("conheceu", false) or randf() > 0.12:
		return false
	var inv: Dictionary = GameState.player["inventory"]
	var stolen := ""
	if not inv.is_empty():
		stolen = inv.keys().pick_random()
		GameState.remove_item(stolen)
	NeedsSystem.apply({"sanidade": -22})
	GameState.add_log("Você acorda às 3 da manhã com um rangido. A porta está entreaberta. Tem marcas de luva na janela%s. Alguém esteve aqui enquanto você dormia." % ((" e sumiu: " + World.item_name(stolen)) if stolen != "" else ""), "danger")
	silas["memorias"].append("[%s] Entrei na casa do jogador enquanto ele dormia. Levei uma lembrança." % TimeManager.clock_str())
	return true


func _psycho_check(hours: float) -> void:
	hours *= World.mod("crime")
	if not TimeManager.is_night() or NPCManager.busy:
		return
	if TimeManager.total_minutes - _last_psycho < 360:
		return
	var here := NPCManager.npcs_here()
	if here.size() != 1 or not here[0] in PSYCHOS:
		return
	if randf() > 1.0 - pow(0.7, hours):
		return
	_last_psycho = TimeManager.total_minutes
	var id: String = here[0]
	NPCManager.event_turn(id, "%s surge do escuro bem perto de você. Não tem mais ninguém por aqui." % NPCManager.display_name(id),
		"É tarde da noite e vocês estão sozinhos aqui, sem nenhuma testemunha. Pela sua natureza, este é o momento que você esperava. Aja agora conforme quem você realmente é: aproxime-se, manipule, ameace ou ataque ('atacar').")


# ---------- incêndios ----------

func fire() -> Dictionary:
	return data().get("fire", {})


func fire_at(loc_id: String) -> bool:
	if not GameState.active:
		return false
	var f := fire()
	return not f.is_empty() and str(f["loc"]) == loc_id and TimeManager.total_minutes < int(f["ate"])


func start_fire(loc_id: String) -> void:
	data()["fire"] = {"loc": loc_id, "ate": TimeManager.total_minutes + 300}
	var place: String = World.locations[loc_id]["nome"]
	NewsSystem.post("Incêndio atinge %s" % place, "Os bombeiros isolaram a área e investigam as causas do fogo. Ninguém foi encontrado no local.", "evento")
	if World.current_id() != loc_id:
		GameState.add_log("Notícia no celular: incêndio atinge %s. Os bombeiros isolaram a área." % place, "phone")
		return
	if _choice_open:
		return
	_choice_open = true
	NPCManager.end_conversation()
	GameState.add_log("FOGO! Chamas sobem pelas paredes de %s e a fumaça já arde nos seus olhos." % place, "danger")
	World.location_changed.emit(loc_id)
	choice.emit({"title": "INCÊNDIO!", "kind": "fire", "text": "O fogo se espalha rápido. Cada minuto aqui dentro custa saúde.", "options": [
		{"label": "Tentar apagar com o que tem", "callback": fight_fire},
		{"label": "Ligar para os bombeiros (193)", "callback": call_firefighters},
		{"label": "Fugir para a rua", "callback": evacuate},
	]})


func fight_fire() -> void:
	_close_choice()
	TimeManager.advance(10)
	if randf() < 0.45 + (0.2 if GameState.has_trait("forte") else 0.0):
		data()["fire"] = {}
		NeedsSystem.apply({"saude": -8, "higiene": -30})
		GameState.add_log("Com um balde, um pano molhado e muita teimosia você abafa as chamas. Está coberto de fuligem, mas o fogo acabou.", "event")
		World.location_changed.emit(World.current_id())
	else:
		NeedsSystem.apply({"saude": -25})
		GameState.add_log("O fogo é maior que você. Queima seu braço e te força a recuar.", "danger")
		evacuate()


func call_firefighters() -> void:
	_close_choice()
	NeedsSystem.apply({"saude": -8})
	emergency(193)
	if World.current_id() == str(fire().get("loc", "")):
		evacuate()


func evacuate() -> void:
	_close_choice()
	var out: String = World.current().get("pai", "praca")
	if out == World.current_id() or fire_at(out):
		out = "praca"
	NeedsSystem.apply({"saude": -10, "sanidade": -6})
	GameState.player["location"] = out
	GameState.add_log("Você sai tossindo para %s. Atrás de você, o fogo cresce." % World.locations[out]["nome"], "event")
	World.location_changed.emit(out)


func _fire_tick(hours: float) -> void:
	var here := World.current_id()
	if fire_at(here) and not _choice_open:
		NeedsSystem.apply({"saude": -8.0 * hours})
		evacuate()
		return
	if fire().is_empty() or TimeManager.total_minutes >= int(fire().get("ate", 0)):
		data()["fire"] = {}
		if randf() < 1.0 - pow(1.0 - 0.004 * World.mod("eventos"), hours):
			var spots: Array = World.locations.keys().filter(func(k): return not World.locations[k].get("interior", false) and k != "apartamento")
			start_fire(spots.pick_random())


# ---------- emergências ----------

func emergency(number: int) -> void:
	if not GameState.active:
		return
	var d := data()
	match number:
		190:
			var ag: Dictionary = d.get("agressor", {})
			if not ag.is_empty() and TimeManager.total_minutes - int(ag["hora"]) < 120:
				var who: String = NPCManager.npcs[ag["id"]]["nome"]
				NewsSystem.post("Suspeito de agressão é preso", "%s foi levado(a) à delegacia depois de uma denúncia de agressão. A vítima prestou depoimento." % who, "crime")
				TimeManager.advance(20)
				NPCManager.state[ag["id"]]["preso_ate"] = TimeManager.total_minutes + 3 * 1440
				d["agressor"] = {}
				NPCManager.end_conversation()
				GameState.add_log("Uma viatura chega em vinte minutos e leva %s algemado(a). Você presta depoimento." % who, "event")
			elif wanted() > 0:
				GameState.add_log("A atendente pede seu nome e endereço. Você desliga rápido.", "info")
			else:
				TimeManager.advance(5)
				GameState.add_log("A atendente registra sua ocorrência e promete mandar uma viatura. Ninguém aparece.", "info")
		192:
			if NeedsSystem.get_value("saude") < 65.0:
				TimeManager.advance(12)
				NPCManager.end_conversation()
				Economy.sus_treatment(true)
			else:
				GameState.add_log("O atendente do SAMU pergunta se há risco de vida. Como não há, orienta procurar um posto.", "info")
		193:
			var f := fire()
			if not f.is_empty() and TimeManager.total_minutes < int(f["ate"]):
				TimeManager.advance(15)
				d["fire"] = {}
				GameState.add_log("Os bombeiros chegam em quinze minutos, controlam o fogo e isolam o local.", "event")
				World.location_changed.emit(World.current_id())
			else:
				GameState.add_log("O bombeiro pergunta onde é o incêndio. Não há nenhum registrado.", "info")


# ---------- tempo ----------

func _on_time_advanced(minutes: int, sleeping: bool) -> void:
	if not GameState.active:
		return
	var d := data()
	var now := TimeManager.total_minutes
	for id in NPCManager.state:
		var st: Dictionary = NPCManager.state[id]
		if st.has("internar_em") and now >= int(st["internar_em"]):
			st["hospital_ate"] = now + 1440
			st.erase("internar_em")
		if int(st.get("saude", 100)) < 100 and st.get("vivo", true) and now >= int(st.get("hospital_ate", 0)):
			st["saude"] = mini(int(st["saude"]) + (now / 30 - (now - minutes) / 30), 100)
	for body in d["corpos"]:
		if not body["achado"] and now - int(body["hora"]) > 360:
			body["achado"] = true
			NewsSystem.post("Corpo é encontrado em %s" % World.locations[body["local"]]["nome"], "A vítima foi identificada como %s. A polícia investiga o caso como homicídio." % NPCManager.npcs[body["id"]]["nome"], "crime")
			GameState.add_log("Notícia no celular: corpo de %s é encontrado em %s. A polícia investiga." % [NPCManager.npcs[body["id"]]["nome"], World.locations[body["local"]]["nome"]], "phone")
			if randf() < 0.4:
				set_wanted(wanted() + 2)
	if wanted() > 0 and now - int(d["last_crime"]) > 720:
		d["last_crime"] = now
		set_wanted(wanted() - 1)
	if sleeping or _choice_open:
		return
	var hours := minutes / 60.0
	if wanted() > 0:
		var p := 0.07 * wanted() * World.mod("policia") + (0.6 if World.current_id() == "delegacia" else 0.0)
		if randf() < 1.0 - pow(1.0 - minf(p, 0.95), hours):
			police_event()
			return
	_fire_tick(hours)
	_psycho_check(hours)
