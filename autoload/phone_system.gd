extends Node

signal thread_updated(npc_id: String)
signal typing_changed(npc_id: String, typing: bool)
signal notify(text: String)
signal changed

const MAX_THREAD := 80
const SPONTANEOUS_COOLDOWN := 120
const AGENDA_NPCS := ["ruan", "silas", "bia", "dona_cida", "tiago"]

var open_thread: String = ""
var _working: bool = false
var _last_spontaneous: int = -9999


func _ready() -> void:
	TimeManager.time_advanced.connect(_on_time_advanced)


func phone() -> Dictionary:
	var p: Dictionary = GameState.player
	if not p.has("phone"):
		var contacts: Array = []
		var origin := World.get_origin(str(p.get("origin", "")))
		for id in origin.get("conhecidos", []):
			contacts.append(id)
		p["phone"] = {"contacts": contacts, "threads": {}, "unread": {}, "pending": [], "bank_log": []}
	return p["phone"]


func has_contact(id: String) -> bool:
	return GameState.active and id in phone()["contacts"]


func add_contact(id: String) -> void:
	if not has_contact(id):
		phone()["contacts"].append(id)
		changed.emit()


func thread(id: String) -> Array:
	var th: Dictionary = phone()["threads"]
	if not th.has(id):
		th[id] = []
	return th[id]


func unread(id: String = "") -> int:
	var u: Dictionary = phone()["unread"]
	if id != "":
		return int(u.get(id, 0))
	var total := 0
	for k in u:
		total += int(u[k])
	return total


func mark_read(id: String) -> void:
	phone()["unread"].erase(id)
	changed.emit()


func _push(id: String, from_player: bool, text: String, status: String = "") -> void:
	var th := thread(id)
	th.append({"eu": from_player, "texto": text, "hora": "%02d:%02d" % [TimeManager.hour(), TimeManager.minute()], "status": status})
	if th.size() > MAX_THREAD:
		th.pop_front()
	thread_updated.emit(id)
	changed.emit()


func log_bank(desc: String, value: int) -> void:
	var entries: Array = phone()["bank_log"]
	entries.append({"desc": desc, "valor": value, "hora": TimeManager.clock_str()})
	if entries.size() > 60:
		entries.pop_front()
	changed.emit()


func can_reach(id: String) -> bool:
	return NPCManager.state[id].get("vivo", true) and not NPCManager.state[id].get("bloqueado", false)


func send_message(id: String, text: String) -> void:
	text = text.strip_edges()
	if text == "" or not GameState.active or not has_contact(id):
		return
	TimeManager.advance(1)
	if not can_reach(id):
		_push(id, true, text, "não entregue")
		return
	_push(id, true, text, "enviada")
	if NPCManager.is_asleep(id) or _working:
		if not id in phone()["pending"]:
			phone()["pending"].append(id)
		return
	await _reply(id, text)


func _reply(id: String, player_text: String) -> void:
	_working = true
	typing_changed.emit(id, true)
	var res: Dictionary = await NPCManager.text_reply(id, player_text)
	typing_changed.emit(id, false)
	_working = false
	if not res["ok"]:
		GameState.add_log(res["error"], "error")
		return
	_deliver(id, res["data"])


func _deliver(id: String, data: Dictionary) -> void:
	var th := thread(id)
	if not th.is_empty() and th[-1]["eu"]:
		th[-1]["status"] = "visualizada"
	if not data.get("responder", true) or str(data.get("fala", "")).strip_edges() == "":
		thread_updated.emit(id)
		return
	_push(id, false, str(data["fala"]).strip_edges())
	if open_thread != id:
		phone()["unread"][id] = unread(id) + 1
		notify.emit("Nova mensagem de %s" % NPCManager.display_name(id))
		GameState.add_log("Nova mensagem de %s no celular." % NPCManager.display_name(id), "phone")


func send_pix(id: String, amount: int) -> bool:
	if amount <= 0 or GameState.money() < amount or not has_contact(id) or not can_reach(id):
		return false
	GameState.add_money(-amount)
	NPCManager.state[id]["dinheiro"] = int(NPCManager.state[id]["dinheiro"]) + amount
	NPCManager.state[id]["pago"] = int(NPCManager.state[id].get("pago", 0)) + amount
	log_bank("PIX enviado para %s" % NPCManager.display_name(id), -amount)
	GameState.add_log("Você mandou um PIX de R$ %d para %s." % [amount, NPCManager.display_name(id)], "phone")
	send_message(id, "[PIX de R$ %d enviado para você]" % amount)
	return true


# Retorna "atendeu", "nao_atendeu", "caixa_postal" ou "bloqueado".
func call_contact(id: String) -> String:
	if not GameState.active or not has_contact(id):
		return "nao_atendeu"
	TimeManager.advance(1)
	var st: Dictionary = NPCManager.state[id]
	if not can_reach(id):
		return "bloqueado"
	if NPCManager.is_asleep(id):
		GameState.add_log("%s não atende. Caixa postal." % NPCManager.display_name(id), "phone")
		return "caixa_postal"
	var chance := 0.85
	if int(st["confianca"]) < -30 or int(st["afeto"]) < -30:
		chance = 0.15
	elif int(st["medo"]) > 60:
		chance = 0.3
	if randf() > chance:
		GameState.add_log("%s não atendeu." % NPCManager.display_name(id), "phone")
		return "nao_atendeu"
	NPCManager.end_conversation()
	NPCManager.start_call(id)
	return "atendeu"


func _on_time_advanced(_minutes: int, _sleeping: bool) -> void:
	if not GameState.active or _working:
		return
	var pending: Array = phone()["pending"]
	for id in pending.duplicate():
		if not NPCManager.is_asleep(id):
			pending.erase(id)
			var th := thread(id)
			var last_text: String = th[-1]["texto"] if not th.is_empty() else ""
			_reply(id, last_text)
			return
	_maybe_spontaneous(_minutes)


func _maybe_spontaneous(minutes: int) -> void:
	if not Settings.is_ready() or NPCManager.busy:
		return
	if TimeManager.total_minutes - _last_spontaneous < SPONTANEOUS_COOLDOWN:
		return
	var hours := minutes / 60.0
	for id in phone()["contacts"]:
		if not can_reach(id) or NPCManager.is_asleep(id) or id == NPCManager.talking_to:
			continue
		var st: Dictionary = NPCManager.state[id]
		var chance := 0.03
		if int(st["afeto"]) > 40 or st.get("namoro", false):
			chance += 0.05
		if id in AGENDA_NPCS:
			chance += 0.04
		if randf() < chance * hours:
			_last_spontaneous = TimeManager.total_minutes
			_spontaneous(id)
			return


func _spontaneous(id: String) -> void:
	_working = true
	typing_changed.emit(id, true)
	var res: Dictionary = await NPCManager.spontaneous_message(id)
	typing_changed.emit(id, false)
	_working = false
	if res["ok"]:
		_deliver(id, res["data"])
