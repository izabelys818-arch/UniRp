extends Node

# Empregos: o chefe contrata pela conversa; o jogo confere o turno, paga e cobra presença.

signal changed

const MAX_FALTAS := 3
const TIPS := ["Ajudante de bar", "Atendente"]


func _ready() -> void:
	TimeManager.time_advanced.connect(_on_time_advanced)


func job() -> Dictionary:
	return GameState.player.get("job", {}) if GameState.active else {}


func has_job() -> bool:
	return not job().is_empty()


func offer(npc_id: String) -> Dictionary:
	return NPCManager.npcs[npc_id].get("servicos", {}).get("emprego", {})


func hire(npc_id: String) -> void:
	var svc := offer(npc_id)
	var st: Dictionary = NPCManager.state[npc_id]
	if svc.is_empty() or NPCManager.location_of(npc_id) != World.current_id():
		return
	if has_job():
		GameState.add_log("Você já trabalha como %s. Peça demissão antes de aceitar outro emprego." % str(job()["cargo"]).to_lower(), "info")
		return
	if int(st["confianca"]) < -10:
		GameState.add_log("%s não confia em você o suficiente para te contratar." % NPCManager.display_name(npc_id), "info")
		return
	var turno: Array = svc["turno"]
	GameState.player["job"] = {"npc": npc_id, "cargo": svc["cargo"], "salario_hora": int(svc["salario_hora"]), "turno": turno, "local": svc["local"],
		"faltas": 0, "trabalhou_dia": 0, "desde_dia": TimeManager.day() + 1, "ultimo_check": TimeManager.day(), "ganho_total": 0}
	st["memorias"].append("[%s] Contratei o jogador como %s." % [TimeManager.clock_str(), svc["cargo"]])
	GameState.add_log("%s te contratou: %s, R$ %d por hora, das %02dh às %02dh em %s." % [NPCManager.display_name(npc_id), svc["cargo"], int(svc["salario_hora"]), int(turno[0]), int(turno[1]), World.locations[svc["local"]]["nome"]], "event")
	GameState.add_log("Quando chegar o seu horário, aparece a opção de trabalhar no local.", "event")
	changed.emit()
	GameState.player_changed.emit()


func dismiss(npc_id: String, reason: String = "") -> void:
	if not has_job() or str(job()["npc"]) != npc_id:
		return
	var cargo := str(job()["cargo"])
	GameState.player.erase("job")
	if reason == "":
		reason = "Você não trabalha mais como %s." % cargo.to_lower()
	GameState.add_log(reason, "event")
	changed.emit()
	GameState.player_changed.emit()


func hours_left(turno: Array) -> int:
	var left := (int(turno[1]) - TimeManager.hour() + 24) % 24
	return maxi(left, 1)


func on_shift() -> bool:
	var j := job()
	return not j.is_empty() and World.current_id() == j["local"] and World.hour_in_range(TimeManager.hour(), int(j["turno"][0]), int(j["turno"][1]))


func actions() -> Array:
	if not on_shift():
		return []
	var j := job()
	var left := hours_left(j["turno"])
	return [{"id": "job:trabalhar", "label": "Trabalhar o turno (%dh, R$ %d)" % [left, left * int(j["salario_hora"])]}]


func work() -> void:
	if not on_shift() or NPCManager.busy:
		return
	var j := job()
	var hours := hours_left(j["turno"])
	var day := TimeManager.day()
	var minutes := hours * 60 - TimeManager.minute()
	NPCManager.end_conversation()
	TimeManager.advance(minutes)
	if not GameState.active:
		return
	NeedsSystem.apply({"energia": -5.0 * hours, "higiene": -3.0 * hours, "sanidade": -1.0 * hours})
	var pay := hours * int(j["salario_hora"])
	var tip := 0
	if str(j["cargo"]) in TIPS and randf() < 0.35:
		tip = randi_range(5, 30)
	GameState.add_money(pay + tip)
	PhoneSystem.log_bank("Salário: " + str(j["cargo"]), pay + tip)
	j["trabalhou_dia"] = day
	j["faltas"] = 0
	j["ganho_total"] = int(j["ganho_total"]) + pay + tip
	var boss: Dictionary = NPCManager.state[j["npc"]]
	if randf() < 0.15:
		boss["afeto"] = mini(int(boss["afeto"]) + 3, 100)
		boss["confianca"] = mini(int(boss["confianca"]) + 3, 100)
		GameState.add_log("%s elogia o seu serviço na frente de todo mundo." % NPCManager.display_name(j["npc"]), "event")
	GameState.add_log("Você trabalhou %d hora(s) como %s e recebeu R$ %d%s." % [hours, str(j["cargo"]).to_lower(), pay, (" (mais R$ %d de gorjeta)" % tip) if tip > 0 else ""], "event")
	changed.emit()


func _on_time_advanced(_minutes: int, _sleeping: bool) -> void:
	if not has_job():
		return
	var j := job()
	var today := TimeManager.day()
	var day := int(j["ultimo_check"]) + 0
	while day < today and has_job():
		var is_sunday := (day - 1) % 7 == 6
		if day >= int(j["desde_dia"]) and not is_sunday:
			if int(j["trabalhou_dia"]) == day:
				j["faltas"] = 0
			else:
				j["faltas"] = int(j["faltas"]) + 1
				var boss_name := NPCManager.display_name(j["npc"])
				if int(j["faltas"]) >= MAX_FALTAS:
					NPCManager.state[j["npc"]]["confianca"] = maxi(int(NPCManager.state[j["npc"]]["confianca"]) - 25, -100)
					NPCManager.state[j["npc"]]["memorias"].append("[%s] Demiti o jogador por faltar três dias seguidos." % TimeManager.clock_str())
					dismiss(j["npc"], "%s te demitiu por faltar %d dias seguidos." % [boss_name, MAX_FALTAS])
					return
				GameState.add_log("%s anotou a sua falta (%d/%d). Mais uma e você está na rua." % [boss_name, int(j["faltas"]), MAX_FALTAS], "danger")
		day += 1
	if has_job():
		job()["ultimo_check"] = today
