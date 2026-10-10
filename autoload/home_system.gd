extends Node

# Moradia estilo Sims: contratos, contas mensais, imóveis, mobília e ações dentro de casa.

signal changed

const CYCLE_DAYS := 30
const DUE_DAYS := 7
const ELECTRONICS := ["geladeira", "tv", "computador"]
const INTERNET_SETUP := 80
const INTERNET_MONTHLY := 70
const BILL_NAMES := {"aluguel": "Aluguel", "luz": "Conta de luz", "agua": "Conta de água", "internet": "Internet"}

var imoveis: Dictionary = {}
var moveis: Dictionary = {}


func _ready() -> void:
	imoveis = World._load_json("res://data/imoveis.json")
	moveis = World._load_json("res://data/moveis.json")
	TimeManager.time_advanced.connect(_on_time_advanced)


func housing() -> Dictionary:
	var p: Dictionary = GameState.player
	if not p.has("housing"):
		var h := {"contracts": {}, "bills": [], "moveis": {}, "entregas": [], "utils": {}, "next_id": 1, "last_cycle": TimeManager.day()}
		var home := str(p.get("home", ""))
		if home != "":
			var origin := World.get_origin(str(p.get("origin", "")))
			h["contracts"][home] = {"tipo": str(origin.get("moradia", "propria")), "aluguel": int(origin.get("aluguel", 0))}
			h["moveis"][home] = ["geladeira", "fogao"] if home == "apartamento" else []
			h["utils"][home] = {"luz": true, "agua": true, "internet": false}
		p["housing"] = h
	return p["housing"]


func contracts() -> Dictionary:
	return housing()["contracts"]


func has_access(loc_id: String) -> bool:
	if not GameState.active:
		return false
	return contracts().has(loc_id)


func home_id() -> String:
	return str(GameState.player.get("home", ""))


func residences() -> Array:
	return contracts().keys().filter(func(k): return str(contracts()[k]["tipo"]) != "comercial")


func status_of(loc_id: String) -> String:
	return str(contracts()[loc_id]["tipo"]) if contracts().has(loc_id) else ""


func furniture(loc_id: String) -> Array:
	return housing()["moveis"].get(loc_id, [])


func has_furn(item_id: String, loc_id: String = "") -> bool:
	if loc_id == "":
		loc_id = World.current_id()
	return item_id in furniture(loc_id)


func utils(loc_id: String) -> Dictionary:
	var u: Dictionary = housing()["utils"]
	if not u.has(loc_id):
		u[loc_id] = {"luz": true, "agua": true, "internet": false}
	return u[loc_id]


func power(loc_id: String = "") -> bool:
	return bool(utils(World.current_id() if loc_id == "" else loc_id)["luz"]) and not WorldEvents.power_out()


# ---------- contas ----------

func bills() -> Array:
	return housing()["bills"]


func unpaid() -> Array:
	var out: Array = bills().filter(func(b): return not b["pago"])
	out.sort_custom(func(a, b): return int(a["venc"]) < int(b["venc"]))
	return out


func _new_bill(kind: String, value: int, loc_id: String) -> void:
	var h := housing()
	var b := {"id": int(h["next_id"]), "tipo": kind, "valor": value, "venc": TimeManager.total_minutes + DUE_DAYS * 1440, "loc": loc_id, "pago": false, "multado": false, "cortado": false, "avisado": false}
	h["next_id"] = int(h["next_id"]) + 1
	h["bills"].append(b)


func _cycle() -> void:
	var made := 0
	for loc_id in contracts():
		var c: Dictionary = contracts()[loc_id]
		var tipo := str(c["tipo"])
		if tipo == "alugada" or tipo == "comercial":
			_new_bill("aluguel", int(round(int(c["aluguel"]) * World.mod("preco"))), loc_id)
			made += 1
		var eletros := furniture(loc_id).filter(func(m): return m in ELECTRONICS).size()
		_new_bill("luz", int(round(((60 if tipo == "comercial" else 45) + 12 * eletros) * World.mod("preco"))), loc_id)
		_new_bill("agua", 30, loc_id)
		made += 2
		if bool(utils(loc_id)["internet"]):
			_new_bill("internet", INTERNET_MONTHLY, loc_id)
			made += 1
	if made > 0:
		GameState.add_log("Chegaram as contas do mês no celular. Elas vencem em %d dias." % DUE_DAYS, "phone")
		PhoneSystem.notify.emit("Contas do mês chegaram")
	changed.emit()


func bill_label(b: Dictionary) -> String:
	var where: String = World.locations[b["loc"]]["nome"] if World.locations.has(b["loc"]) else ""
	return "%s • %s" % [BILL_NAMES.get(b["tipo"], b["tipo"]), where]


func pay_bill(bill_id: int) -> bool:
	for b in bills():
		if int(b["id"]) == bill_id and not b["pago"]:
			if GameState.money() < int(b["valor"]):
				return false
			GameState.add_money(-int(b["valor"]))
			PhoneSystem.log_bank(bill_label(b), -int(b["valor"]))
			b["pago"] = true
			if b["cortado"] and contracts().has(b["loc"]):
				utils(b["loc"])[b["tipo"]] = true
				GameState.add_log("%s paga: o serviço foi religado." % BILL_NAMES[b["tipo"]], "event")
			GameState.add_log("Você pagou %s (R$ %d)." % [bill_label(b), int(b["valor"])], "phone")
			changed.emit()
			return true
	return false


func _late_days(b: Dictionary) -> float:
	return (TimeManager.total_minutes - int(b["venc"])) / 1440.0


func _check_bills() -> void:
	for b in bills():
		if b["pago"] or not contracts().has(b["loc"]):
			continue
		var late := _late_days(b)
		if late > -1.0 and late <= 0.0 and not b["avisado"]:
			b["avisado"] = true
			PhoneSystem.notify.emit("Vence amanhã: %s" % BILL_NAMES[b["tipo"]])
		if late > 3.0 and not b["multado"]:
			b["multado"] = true
			b["valor"] = int(b["valor"]) + int(ceil(int(b["valor"]) * 0.1))
			GameState.add_log("%s atrasada: multa de 10%% aplicada (agora R$ %d)." % [bill_label(b), int(b["valor"])], "danger")
		var cut_after := {"luz": 10.0, "agua": 10.0, "internet": 5.0}
		if cut_after.has(b["tipo"]) and late > float(cut_after[b["tipo"]]) and not b["cortado"]:
			b["cortado"] = true
			utils(b["loc"])[b["tipo"]] = false
			GameState.add_log("CORTE: %s foi cortada por falta de pagamento." % BILL_NAMES[b["tipo"]], "danger")
			NeedsSystem.apply({"sanidade": -5})
		if b["tipo"] == "aluguel" and late > 30.0:
			evict(b["loc"])


func evict(loc_id: String) -> void:
	var name_: String = World.locations[loc_id]["nome"]
	contracts().erase(loc_id)
	housing()["moveis"].erase(loc_id)
	housing()["bills"] = bills().filter(func(b): return b["loc"] != loc_id)
	if loc_id == "minha_lanchonete":
		BusinessSystem.close_down()
	if home_id() == loc_id:
		var rest := residences()
		GameState.player["home"] = rest[0] if not rest.is_empty() else ""
	GameState.add_log("DESPEJO: por dois meses sem pagar, você perdeu %s e tudo que estava lá dentro." % name_, "danger")
	if World.current_id() == loc_id:
		GameState.player["location"] = "praca"
		World.location_changed.emit("praca")
	GameState.player_changed.emit()
	changed.emit()


# ---------- imóveis ----------

# Imobiliária: casas vazias da cidade (das ruas do mapa 3D) entram no anúncio com preço próprio,
# sempre as mesmas para a mesma cidade. Nenhum prédio novo: são as casas que já existem.
const AGENCIES := ["Imobiliária Chave Certa", "Lar Doce Lar Imóveis", "Porto Seguro Imóveis"]
const MAX_LISTINGS := 9


func list_city_houses() -> void:
	var ids: Array = []
	for id in World.locations:
		if World.locations[id].get("casa_generica", false):
			ids.append(id)
	ids.sort()
	var listed := 0
	for id in ids:
		if listed >= MAX_LISTINGS:
			break
		if imoveis.has(id):
			listed += 1
			continue
		var st: Dictionary = Houses.st(id)
		var mine := contracts().has(id)
		if bool(st["ocupada"]) and not mine:
			continue
		var r := RandomNumberGenerator.new()
		r.seed = int(World.locations[id].get("seed", hash(id))) + 77
		var rooms := r.randi_range(1, 3)
		var agency: String = AGENCIES[r.randi() % AGENCIES.size()]
		var street := str(World.locations[id]["nome"])
		if str(st["tipo"]) == "abandonada":
			imoveis[id] = {"tipo": "compra", "compra": r.randi_range(9, 16) * 1000,
				"resumo": "%s. Casa abandonada para reformar: telhado com goteira, mas é sua por pouco. (%s)" % [street, agency]}
		else:
			var rent := 380 + rooms * 160 + r.randi_range(0, 6) * 30
			imoveis[id] = {"tipo": "aluguel_compra", "aluguel": rent, "deposito": rent * 2, "compra": rent * r.randi_range(60, 78),
				"resumo": "%s. Casa de %d quarto(s) com quintal, desocupada. Aluga ou vende. (%s)" % [street, rooms, agency]}
		listed += 1

func rent_cost(loc_id: String) -> int:
	var p: Dictionary = imoveis[loc_id]
	return int(p.get("deposito", 0)) + int(p.get("aluguel", 0)) + int(p.get("abertura", 0))


func can_rent(loc_id: String) -> bool:
	return imoveis[loc_id].has("aluguel") and not contracts().has(loc_id) and GameState.money() >= rent_cost(loc_id)


func can_buy(loc_id: String) -> bool:
	return imoveis[loc_id].has("compra") and not contracts().has(loc_id) and GameState.money() >= int(imoveis[loc_id]["compra"])


func _sign(loc_id: String, tipo: String, rent: int) -> void:
	contracts()[loc_id] = {"tipo": tipo, "aluguel": rent}
	housing()["moveis"][loc_id] = []
	housing()["utils"][loc_id] = {"luz": true, "agua": true, "internet": false}
	if tipo != "comercial" and home_id() == "":
		GameState.player["home"] = loc_id
	GameState.player_changed.emit()
	changed.emit()


func rent(loc_id: String) -> bool:
	if not can_rent(loc_id) or GameState.refuse_minor("contrato"):
		return false
	var p: Dictionary = imoveis[loc_id]
	var cost := rent_cost(loc_id)
	GameState.add_money(-cost)
	PhoneSystem.log_bank("Contrato: " + World.locations[loc_id]["nome"], -cost)
	var comercial := str(p["tipo"]) == "comercial"
	_sign(loc_id, "comercial" if comercial else "alugada", int(p["aluguel"]))
	if comercial:
		BusinessSystem.open_business()
	GameState.add_log("Contrato assinado: %s. Aluguel de R$ %d por mês; a primeira conta chega em %d dias." % [World.locations[loc_id]["nome"], int(p["aluguel"]), CYCLE_DAYS], "event")
	return true


func buy(loc_id: String) -> bool:
	if not can_buy(loc_id) or GameState.refuse_minor("contrato"):
		return false
	var price := int(imoveis[loc_id]["compra"])
	GameState.add_money(-price)
	PhoneSystem.log_bank("Compra: " + World.locations[loc_id]["nome"], -price)
	_sign(loc_id, "propria", 0)
	GameState.add_log("Escritura no seu nome: %s agora é sua, sem aluguel." % World.locations[loc_id]["nome"], "event")
	return true


func cancel(loc_id: String) -> bool:
	if not contracts().has(loc_id) or status_of(loc_id) == "propria":
		return false
	if not unpaid().filter(func(b): return b["loc"] == loc_id).is_empty():
		GameState.add_log("Não dá para encerrar o contrato com contas em aberto.", "info")
		return false
	var refund := int(imoveis.get(loc_id, {}).get("deposito", 0))
	if refund > 0:
		GameState.add_money(refund)
		PhoneSystem.log_bank("Devolução da caução", refund)
	contracts().erase(loc_id)
	housing()["moveis"].erase(loc_id)
	if loc_id == "minha_lanchonete":
		BusinessSystem.close_down()
	if home_id() == loc_id:
		var rest := residences()
		GameState.player["home"] = rest[0] if not rest.is_empty() else ""
	if World.current_id() == loc_id:
		GameState.player["location"] = "praca"
		World.location_changed.emit("praca")
	GameState.add_log("Contrato encerrado. Caução devolvida: R$ %d." % refund, "event")
	GameState.player_changed.emit()
	changed.emit()
	return true


func move_in(loc_id: String) -> void:
	if contracts().has(loc_id) and status_of(loc_id) != "comercial":
		GameState.player["home"] = loc_id
		GameState.add_log("Você passa a morar em %s." % World.locations[loc_id]["nome"], "event")
		changed.emit()


# ---------- compras e entregas ----------

func order(item_id: String, loc_id: String) -> bool:
	if not moveis.has(item_id) or not contracts().has(loc_id):
		return false
	var price := int(moveis[item_id]["preco"])
	if GameState.money() < price:
		return false
	GameState.add_money(-price)
	PhoneSystem.log_bank("Compra online: " + str(moveis[item_id]["nome"]), -price)
	housing()["entregas"].append({"item": item_id, "loc": loc_id, "chega": TimeManager.total_minutes + 1440})
	GameState.add_log("Pedido feito: %s chega em %s amanhã." % [moveis[item_id]["nome"], World.locations[loc_id]["nome"]], "phone")
	changed.emit()
	return true


func order_internet(loc_id: String) -> bool:
	if not contracts().has(loc_id) or bool(utils(loc_id)["internet"]) or GameState.money() < INTERNET_SETUP:
		return false
	GameState.add_money(-INTERNET_SETUP)
	PhoneSystem.log_bank("Instalação de internet", -INTERNET_SETUP)
	housing()["entregas"].append({"item": "_internet", "loc": loc_id, "chega": TimeManager.total_minutes + 1440})
	GameState.add_log("Instalação de internet agendada para amanhã em %s." % World.locations[loc_id]["nome"], "phone")
	changed.emit()
	return true


func _deliver() -> void:
	var left: Array = []
	for e in housing()["entregas"]:
		if TimeManager.total_minutes < int(e["chega"]):
			left.append(e)
			continue
		if not contracts().has(e["loc"]):
			continue
		if e["item"] == "_internet":
			utils(e["loc"])["internet"] = true
			GameState.add_log("A internet foi instalada em %s." % World.locations[e["loc"]]["nome"], "phone")
		else:
			var slot: String = moveis[e["item"]]["slot"]
			var list: Array = housing()["moveis"].get(e["loc"], [])
			list = list.filter(func(m): return moveis[m]["slot"] != slot)
			list.append(e["item"])
			housing()["moveis"][e["loc"]] = list
			GameState.add_log("Chegou a entrega: %s em %s." % [moveis[e["item"]]["nome"], World.locations[e["loc"]]["nome"]], "phone")
		PhoneSystem.notify.emit("Entrega chegou")
	housing()["entregas"] = left
	changed.emit()


# ---------- ações dentro de casa ----------

func actions() -> Array:
	var loc_id := World.current_id()
	var out: Array = []
	if not contracts().has(loc_id) or status_of(loc_id) == "comercial":
		return out
	var u := utils(loc_id)
	if has_furn("fogao", loc_id) and bool(u["agua"]):
		out.append({"id": "casa:cozinhar", "label": "Preparar uma refeição (R$ 8)"})
	if has_furn("tv", loc_id) and bool(u["luz"]):
		out.append({"id": "casa:tv", "label": "Assistir TV (1h)"})
	if has_furn("sofa", loc_id):
		out.append({"id": "casa:sofa", "label": "Descansar no sofá (1h)"})
	if has_furn("computador", loc_id) and bool(u["luz"]) and bool(u["internet"]):
		out.append({"id": "casa:pc", "label": "Trabalhar online no computador (2h)"})
	return out


func do(id: String) -> void:
	match id:
		"cozinhar":
			if GameState.money() < 8:
				GameState.add_log("Você não tem R$ 8 para os ingredientes.", "info")
				return
			GameState.add_money(-8)
			TimeManager.advance(45)
			NeedsSystem.apply({"saciedade": 55, "sanidade": 3, "hidratacao": 5})
			GameState.add_log("Você faz arroz, ovo e um bife na frigideira. Comida de casa, a melhor coisa do dia.", "info")
		"tv":
			TimeManager.advance(60)
			NeedsSystem.apply({"sanidade": 8, "energia": -2})
			GameState.add_log("Uma hora de TV vendo qualquer coisa. A cabeça desliga um pouco.", "info")
		"sofa":
			TimeManager.advance(60)
			NeedsSystem.apply({"energia": 10, "sanidade": 2})
			GameState.add_log("Você se joga no sofá e fecha os olhos por uma hora.", "info")
		"pc":
			TimeManager.advance(120)
			NeedsSystem.apply({"energia": -8, "sanidade": -2})
			var pay := randi_range(25, 70)
			GameState.add_money(pay)
			GameState.add_log("Duas horas de bicos online: transcrições e pequenos serviços. Entram R$ %d." % pay, "event")


func sleep_home() -> void:
	var loc_id := World.current_id()
	if not contracts().has(loc_id) and home_id() != "":
		loc_id = home_id()
	GameState.add_log("Você deita na cama e apaga a luz.", "info")
	var bonus := {"sanidade": 10}
	if has_furn("cama_boa", loc_id):
		bonus = {"sanidade": 18, "saude": 6}
	if not power(loc_id):
		bonus["sanidade"] = int(bonus["sanidade"]) - 6
		GameState.add_log("Sem luz elétrica, o calor e o silêncio da casa escura pesam.", "info")
	TimeManager.advance(480, true)
	if GameState.active:
		NeedsSystem.apply(bonus)
		GameState.add_log("Você acorda. %s." % TimeManager.clock_str(), "info")
		SaveManager.save_game()


func shower() -> void:
	var loc_id := World.current_id()
	if not bool(utils(loc_id)["agua"]):
		GameState.add_log("Sem água: o registro só dá um ronco.", "info")
		return
	TimeManager.advance(20)
	if has_furn("chuveiro", loc_id):
		NeedsSystem.apply({"higiene": 100, "sanidade": 5})
		GameState.add_log("Você toma um banho quente e demorado.", "info")
	else:
		NeedsSystem.apply({"higiene": 85, "sanidade": 1})
		GameState.add_log("Você toma um banho frio, rápido e tremendo.", "info")


# ---------- tempo ----------

func _on_time_advanced(_minutes: int, _sleeping: bool) -> void:
	if not GameState.active:
		return
	var h := housing()
	while TimeManager.day() >= int(h["last_cycle"]) + CYCLE_DAYS:
		h["last_cycle"] = int(h["last_cycle"]) + CYCLE_DAYS
		_cycle()
	_deliver()
	_check_bills()
