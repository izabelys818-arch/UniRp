extends Node

# Vícios: dependência cresce com o uso, a tolerância reduz o efeito e a abstinência cobra o preço.

signal changed

const SUBS := {
	"cigarro": {"nome": "Cigarro", "itens": ["cigarro"], "ganho": 7.0, "intervalo": 6.0, "limiar": 25.0},
	"alcool": {"nome": "Álcool", "itens": ["cerveja", "cachaca"], "ganho": 5.0, "intervalo": 18.0, "limiar": 35.0},
	"droga": {"nome": "Droga", "itens": ["droga"], "ganho": 20.0, "intervalo": 10.0, "limiar": 20.0},
}
const GAIN_MULT := {"cachaca": 1.4}


func _ready() -> void:
	TimeManager.time_advanced.connect(_on_time_advanced)


func vicios() -> Dictionary:
	if not GameState.player.has("vicios"):
		GameState.player["vicios"] = {}
	return GameState.player["vicios"]


func sub_for(item_id: String) -> String:
	for s in SUBS:
		if item_id in SUBS[s]["itens"]:
			return s
	return ""


func level(sub: String) -> float:
	return float(vicios().get(sub, {}).get("nivel", 0.0))


func tolerance(sub: String) -> float:
	return clampf(1.0 - level(sub) / 160.0, 0.45, 1.0)


func hours_since(sub: String) -> float:
	var v: Dictionary = vicios().get(sub, {})
	if v.is_empty():
		return 0.0
	return (TimeManager.total_minutes - int(v["ultimo"])) / 60.0


func severity(sub: String) -> float:
	var info: Dictionary = SUBS[sub]
	if level(sub) < float(info["limiar"]):
		return 0.0
	var late := hours_since(sub) - float(info["intervalo"])
	if late <= 0.0:
		return 0.0
	return clampf(level(sub) / 100.0 * (1.0 + minf(late / 24.0, 1.0)), 0.0, 2.0)


func worst() -> float:
	var w := 0.0
	for s in SUBS:
		w = maxf(w, severity(s))
	return w


func is_withdrawing() -> bool:
	return worst() > 0.0


func on_use(item_id: String) -> void:
	var sub := sub_for(item_id)
	if sub == "":
		return
	var v: Dictionary = vicios().get(sub, {"nivel": 0.0, "ultimo": 0, "avisado": false})
	var was_withdrawing := severity(sub) > 0.0 if vicios().has(sub) else false
	var recent_hours := (TimeManager.total_minutes - int(v["ultimo"])) / 60.0 if vicios().has(sub) else 99.0
	var gain := float(SUBS[sub]["ganho"]) * float(GAIN_MULT.get(item_id, 1.0)) * (0.7 if GameState.has_trait("resistente") else 1.0)
	v["nivel"] = minf(float(v["nivel"]) + gain, 100.0)
	v["ultimo"] = TimeManager.total_minutes
	v["avisado"] = false
	vicios()[sub] = v
	if was_withdrawing:
		NeedsSystem.apply({"sanidade": 6})
		GameState.add_log("O alívio é imediato: as mãos param de tremer.", "info")
	if sub == "droga" and recent_hours < 2.0:
		NeedsSystem.apply({"saude": -30, "sanidade": -20}, "overdose")
		GameState.add_log("Você usou de novo cedo demais. O coração dispara, a visão escurece e você cai de joelhos.", "danger")
	if level(sub) >= 50.0 and gain > 0.0 and not v.get("alerta50", false):
		v["alerta50"] = true
		GameState.add_log("Você percebe que está usando %s mais do que queria." % str(SUBS[sub]["nome"]).to_lower(), "event")
	changed.emit()


func visible_notes() -> String:
	if worst() < 0.4:
		return ""
	return "parece em abstinência: mãos tremendo, suor, olhar inquieto"


func support_group() -> void:
	NPCManager.end_conversation()
	TimeManager.advance(120)
	for s in vicios():
		vicios()[s]["nivel"] = maxf(float(vicios()[s]["nivel"]) - 12.0, 0.0)
	NeedsSystem.apply({"sanidade": 8})
	GameState.add_log("No grupo de apoio da igreja, gente que passou pelo mesmo ouve você contar. Sai mais leve, e um pouco mais limpo.", "event")
	changed.emit()


func group_available() -> bool:
	var any := false
	for s in vicios():
		if level(s) > 0.0:
			any = true
	return any and World.current_id() == "igreja" and TimeManager.hour() >= 19 and TimeManager.hour() < 21


func _on_time_advanced(minutes: int, _sleeping: bool) -> void:
	if not GameState.active:
		return
	var hours := minutes / 60.0
	for s in vicios().keys():
		var sev := severity(s)
		if sev > 0.0:
			NeedsSystem.apply({"sanidade": -1.2 * sev * hours, "energia": -0.8 * sev * hours})
			if s == "droga" and sev > 0.7:
				NeedsSystem.apply({"saude": -0.6 * sev * hours}, "abstinência")
			var v: Dictionary = vicios()[s]
			if not v.get("avisado", false):
				v["avisado"] = true
				GameState.add_log("A vontade de usar %s aperta. Sua cabeça não pensa em outra coisa." % str(SUBS[s]["nome"]).to_lower(), "danger")
				PhoneSystem.notify.emit("Abstinência: %s" % SUBS[s]["nome"])
		elif hours_since(s) > float(SUBS[s]["intervalo"]) * 3.0:
			vicios()[s]["nivel"] = maxf(level(s) - 0.4 * hours, 0.0)
