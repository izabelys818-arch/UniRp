extends Node

# Lanchonete própria: estoque, preço, vendas por hora, caixa, reputação e riscos.

signal changed

const LOC := "minha_lanchonete"
const PRODUTOS := ["cafe", "pao_queijo", "coxinha", "refrigerante", "agua", "prato_feito"]
const COST_RATIO := 0.55
const TRAFFIC := {7: 1.4, 8: 1.4, 9: 1.0, 10: 0.6, 11: 0.9, 12: 1.6, 13: 1.6, 14: 0.9, 15: 0.5, 16: 0.6, 17: 0.9, 18: 1.3, 19: 1.3, 20: 0.8}


func biz() -> Dictionary:
	return GameState.player.get("biz", {}) if GameState.active else {}


func owned() -> bool:
	return not biz().is_empty() and HomeSystem.contracts().has(LOC)


func open_business() -> void:
	if GameState.refuse_minor("contrato"):
		return
	GameState.player["biz"] = {"stock": {}, "preco": 1.0, "cash": 0.0, "aberto": false, "reputacao": 1.0,
		"vendas_hoje": 0.0, "ontem": 0.0, "total": 0.0, "dia": TimeManager.day(), "clientes": 0}
	changed.emit()


func close_down() -> void:
	GameState.player.erase("biz")
	changed.emit()


func cost_of(item_id: String) -> int:
	return int(ceil(float(World.items[item_id]["preco"]) * COST_RATIO * World.mod("preco")))


func price_of(item_id: String) -> int:
	return int(round(float(World.items[item_id]["preco"]) * float(biz()["preco"])))


func restock(item_id: String, qty: int) -> bool:
	if not owned() or not item_id in PRODUTOS:
		return false
	var cost := cost_of(item_id) * qty
	if GameState.money() < cost:
		return false
	GameState.add_money(-cost)
	var stock: Dictionary = biz()["stock"]
	stock[item_id] = int(stock.get(item_id, 0)) + qty
	PhoneSystem.log_bank("Atacado: %dx %s" % [qty, World.item_name(item_id)], -cost)
	changed.emit()
	return true


func set_price(mult: float) -> void:
	if owned():
		biz()["preco"] = clampf(mult, 0.7, 1.5)
		changed.emit()


func toggle_open() -> void:
	if owned():
		biz()["aberto"] = not biz()["aberto"]
		GameState.add_log("Você %s a lanchonete." % ("abre" if biz()["aberto"] else "fecha"), "info")
		changed.emit()


func collect() -> int:
	if not owned():
		return 0
	var amount := int(biz()["cash"])
	if amount > 0:
		biz()["cash"] = float(biz()["cash"]) - amount
		GameState.add_money(amount)
		PhoneSystem.log_bank("Caixa da lanchonete", amount)
		GameState.add_log("Você retira R$ %d do caixa da lanchonete." % amount, "event")
		changed.emit()
	return amount


func stars() -> int:
	return clampi(int(round(float(biz().get("reputacao", 1.0)) * 3.3)), 1, 5)


func price_factor(mult: float) -> float:
	return clampf(1.0 - (mult - 1.0) * 1.6, 0.25, 1.35)


func simulate_hour(hour: int, present: bool) -> void:
	var b := biz()
	if not b["aberto"] or not TRAFFIC.has(hour):
		return
	var expected := 6.0 * float(TRAFFIC[hour]) * float(b["reputacao"]) * (1.0 if present else 0.6) * price_factor(float(b["preco"]))
	var customers := maxi(int(round(expected + randf_range(-1.0, 1.0))), 0)
	var stock: Dictionary = b["stock"]
	for i in customers:
		var avail: Array = stock.keys().filter(func(k): return int(stock[k]) > 0)
		if avail.is_empty():
			b["reputacao"] = maxf(float(b["reputacao"]) - 0.006, 0.4)
			continue
		var item: String = avail.pick_random()
		stock[item] = int(stock[item]) - 1
		var revenue := price_of(item)
		b["cash"] = float(b["cash"]) + revenue
		b["vendas_hoje"] = float(b["vendas_hoje"]) + revenue
		b["total"] = float(b["total"]) + revenue
		b["clientes"] = int(b["clientes"]) + 1
		b["reputacao"] = minf(float(b["reputacao"]) + 0.002, 1.5)


func work_counter() -> void:
	if not owned() or NPCManager.busy:
		return
	NPCManager.end_conversation()
	if not biz()["aberto"]:
		toggle_open()
	TimeManager.advance(180)
	NeedsSystem.apply({"energia": -15, "higiene": -9, "sanidade": -3})
	GameState.add_log("Três horas atrás do balcão, atendendo fila e servindo café.", "info")


func actions() -> Array:
	if World.current_id() != LOC or not owned():
		return []
	return [{"id": "biz:gerenciar", "label": "Gerenciar a lanchonete"}, {"id": "biz:balcao", "label": "Atender no balcão (3h)"}]


func _on_time(minutes: int) -> void:
	if not owned():
		return
	var b := biz()
	var start := TimeManager.total_minutes - minutes
	# simula cada hora cheia que terminou (funciona com saltos grandes ou tempo real)
	var first_h: int = start / 60
	var steps: int = TimeManager.total_minutes / 60 - first_h
	var present := World.current_id() == LOC
	for i in steps:
		var minute_i := (first_h + i) * 60
		simulate_hour((minute_i / 60) % 24, present)
		if ((minute_i / 60) % 24) in [0, 1, 2, 3, 4] and float(b["cash"]) > 300.0 and randf() < 0.02:
			var lost := int(float(b["cash"]) * 0.6)
			b["cash"] = float(b["cash"]) - lost
			GameState.add_log("ASSALTO: arrombaram a sua lanchonete de madrugada e levaram R$ %d do caixa." % lost, "danger")
	if TimeManager.day() != int(b["dia"]):
		b["ontem"] = b["vendas_hoje"]
		b["vendas_hoje"] = 0.0
		b["dia"] = TimeManager.day()
		var empty: Array = PRODUTOS.filter(func(k): return int(b["stock"].get(k, 0)) <= 0)
		GameState.add_log("Fechamento: sua lanchonete faturou R$ %d ontem.%s" % [int(b["ontem"]), (" Acabou o estoque de: " + ", ".join(empty.map(func(k): return World.item_name(k).to_lower()))) if not empty.is_empty() and b["aberto"] else ""], "phone")
	changed.emit()


func _ready() -> void:
	TimeManager.time_advanced.connect(func(m, _s): _on_time(m))
