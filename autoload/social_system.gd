extends Node

# Vida social com os NPCs, por cima das relações que já existem (confiança, afeto, medo, suspeita):
# - repetir a mesma coisa irrita: primeiro avisam, depois se irritam, xingam e vão embora;
# - quando a relação muda de patamar (amigo, inimigo...), o jogo avisa;
# - flertar com alguém estando namorando vira fofoca: quem viu conta para outros, a fofoca anda
#   pela cidade a cada hora e, se chega no parceiro, ele cobra, desconfia e pode terminar;
# - aniversários: dar parabéns (pessoalmente ou no celular) e presente; amigos convidam para a
#   comemoração no bar; no aniversário do jogador os amigos mandam mensagem;
# - Dia dos Namorados: o parceiro espera um carinho no dia.
# O estado fica no próprio save (jogador e estado de cada NPC); nada roda por quadro.

signal relation_changed(id: String, before: String, after: String)

const Local = preload("res://ai/local_dialogue.gd")

const REPEAT_LINES := {
	2: [["Você já falou isso.", "desconfiado"], ["De novo? Eu ouvi da primeira vez.", "entediado"], ["Hã... você acabou de dizer isso.", "desconfiado"]],
	3: [["Tá repetindo por quê? Tá me testando?", "irritado"], ["Para de repetir, tá ficando chato.", "irritado"], ["Escuta, eu já respondi. Muda o disco.", "irritado"]],
	4: [["Caralho, para de repetir essa merda!", "furioso"], ["Porra, você é surdo ou o quê? Já ouvi!", "furioso"], ["Vai repetir mais quantas vezes, seu chato do inferno?", "furioso"]],
	5: [["Chega. Vai encher o saco de outro. Tô indo.", "furioso"], ["Quer saber? Vai pro inferno. Fui.", "furioso"]],
}
const REPEAT_LINES_KID := {
	4: [["Para! Você é muito chato!", "irritado"], ["Para com isso, que coisa chata!", "irritado"]],
	5: [["Vou embora. Você é chato demais!", "irritado"]],
}
const REPEAT_LINES_TO_MINOR := {
	4: [["Ô, garoto, chega. Vai brincar e para de repetir.", "irritado"], ["Já ouvi, criança. Para com isso.", "irritado"]],
	5: [["Vai pra casa, menino. Chega.", "irritado"]],
}
const REL_MSG := {
	"Amigo(a)": "Você e %s agora são amigos.",
	"Melhor amigo(a)": "%s agora te considera um dos melhores amigos.",
	"Não gosta de você": "%s passou a não gostar de você.",
	"Inimigo(a)": "%s agora é seu inimigo.",
	"Desconfia de você": "%s está desconfiando de você.",
}


func _ready() -> void:
	TimeManager.time_advanced.connect(_on_time_advanced)
	AgingSystem.birthday.connect(_on_birthday)


func data() -> Dictionary:
	if not GameState.player.has("social"):
		GameState.player["social"] = {"rumores": [], "ultima_hora": TimeManager.total_minutes / 60, "ultimo_dia": TimeManager.day()}
	return GameState.player["social"]


# ---------- repetição ----------

static func _key(text: String) -> String:
	Local._compile()
	return Local._norm(text).strip_edges().replace(" ?", "").replace(" !", "")


# Quantas vezes seguidas o jogador disse (praticamente) a mesma coisa a esta pessoa.
func repeat_count(id: String, text: String) -> int:
	var st: Dictionary = NPCManager.state[id]
	if text.strip_edges().begins_with("*"):
		return 1
	var k := _key(text)
	if k.length() < 2 or k.begins_with("*"):
		return 1
	var last: Array = st.get("ultimas_falas", [])
	var n := 1
	for i in range(last.size() - 1, -1, -1):
		if str(last[i]) == k:
			n += 1
		else:
			break
	last.append(k)
	if last.size() > 8:
		last.pop_front()
	st["ultimas_falas"] = last
	return n


# Resposta local quando o jogador repete a mesma fala (2ª vez em diante); {} se não repetiu.
func repeat_reply(id: String, text: String) -> Dictionary:
	var n := repeat_count(id, text)
	if n < 2:
		return {}
	var lvl := mini(n, 5)
	var npc_age := int(NPCManager.npcs[id].get("idade", 30))
	var pool: Array = REPEAT_LINES[lvl]
	if npc_age < 13 and REPEAT_LINES_KID.has(lvl):
		pool = REPEAT_LINES_KID[lvl]
	elif GameState.is_minor() and REPEAT_LINES_TO_MINOR.has(lvl):
		pool = REPEAT_LINES_TO_MINOR[lvl]
	var pick: Array = pool.pick_random()
	var rel := {}
	var acts: Array = []
	match lvl:
		2:
			rel = {"suspeita": 2}
		3:
			rel = {"afeto": -4, "confianca": -2}
		4:
			rel = {"afeto": -8, "confianca": -4}
		_:
			rel = {"afeto": -10, "confianca": -5}
			acts = [{"tipo": "ir_embora"}]
	var mem := ""
	if lvl >= 4:
		mem = "O jogador ficou repetindo a mesma coisa sem parar e me tirou do sério."
	return {"fala": str(pick[0]), "emocao": str(pick[1]), "relacao": rel, "acoes": acts, "memoria": mem, "acao_corporal": "" if lvl < 4 else "bufa e fecha a cara"}


# ---------- patamar da relação ----------

func notify_relation(id: String, before: String, after: String) -> void:
	if before == after or not REL_MSG.has(after):
		return
	relation_changed.emit(id, before, after)
	GameState.add_log(REL_MSG[after] % NPCManager.display_name(id), "event")


# ---------- namoro, flerte e fofoca ----------

func partners() -> Array:
	var out: Array = []
	for id in NPCManager.state:
		if NPCManager.state[id].get("namoro", false) and NPCManager.state[id].get("vivo", true):
			out.append(id)
	return out


# Afeto cotidiano: a resposta respeita o vínculo, a idade e o espaço da outra pessoa.
func contact(id: String, kind: String) -> bool:
	if not GameState.active or NPCManager.busy or NPCManager.channel != NPCManager.PRESENCIAL or not NPCManager.state.has(id):
		return false
	var state: Dictionary = NPCManager.state[id]
	if not state.get("vivo", true) or state.get("bloqueado", false):
		return false
	if kind != "cumprimento" and (GameState.is_minor() or int(NPCManager.npcs[id].get("idade", 30)) < 18):
		return false
	var accepted := int(state.get("medo", 0)) < 25 and int(state.get("suspeita", 0)) < 60
	if kind == "abraco":
		accepted = accepted and int(state.get("confianca", 0)) >= 25 and int(state.get("afeto", 0)) >= 35
	elif kind == "beijo":
		accepted = accepted and bool(state.get("namoro", false)) and int(state.get("afeto", 0)) >= 35
	elif kind != "cumprimento":
		return false
	var phrase := "Você estende a mão para cumprimentar." if kind == "cumprimento" else ("Você pede um abraço." if kind == "abraco" else "Você se aproxima para um beijo.")
	GameState.add_log(phrase, "player")
	var repeated := TimeManager.total_minutes - int(state.get("ultimo_carinho", -10000)) < 60
	if accepted:
		state["ultimo_carinho"] = TimeManager.total_minutes
	var body := {"cumprimento": "aperta sua mão", "abraco": "corresponde ao abraço", "beijo": "corresponde ao beijo"}
	NPCManager._apply_reply(id, {"fala": "É bom ter você por perto." if accepted and kind != "cumprimento" else ("Oi, tudo bem?" if accepted else "Agora eu prefiro um pouco de espaço."),
		"acao_corporal": body[kind] if accepted else "recua com delicadeza", "emocao": "carinhoso" if accepted and kind != "cumprimento" else "neutro",
		"gesto_visual": kind if accepted else "", "relacao": {"afeto": 1 if accepted and not repeated else 0}, "acoes": []})
	if accepted:
		note_contact(id)
	return accepted


static func is_flirt(text: String) -> bool:
	if text.begins_with("*flerta") or text.begins_with("*pisca") or text.begins_with("*beija"):
		return true
	Local._compile()
	return "flerte" in Local.detect(Local._norm(text))


# Chamado a cada fala do jogador com alguém: se ele flerta estando namorando outra pessoa,
# quem estava perto viu; se o próprio parceiro estava perto, descobre na hora.
func on_player_speech(id: String, text: String, chan: String) -> void:
	if not is_flirt(text):
		return
	for p in partners():
		if p == id:
			continue
		var witnesses: Array = []
		if chan == NPCManager.PRESENCIAL:
			for w in NPCManager.npcs_here():
				if w != id:
					witnesses.append(w)
		if p in witnesses:
			_partner_learns(p, id, "viu com os próprios olhos")
			continue
		var knowers: Array = [id]
		knowers.append_array(witnesses)
		var r := {"tipo": "flerte", "alvo": id, "parceiro": p, "dia": TimeManager.day(), "sabem": knowers, "fim": false}
		data()["rumores"].append(r)
		for w in knowers:
			_remember(w, "[%s] O jogador, que namora %s, deu em cima de %s." % [TimeManager.clock_str(), NPCManager.npcs[p]["nome"], NPCManager.npcs[id]["nome"]])


func _remember(id: String, mem: String) -> void:
	var st: Dictionary = NPCManager.state.get(id, {})
	if st.is_empty():
		return
	st["memorias"].append(mem)
	if st["memorias"].size() > NPCManager.MAX_MEMORIES:
		st["memorias"].pop_front()


func _partner_learns(p: String, target: String, how: String) -> void:
	var st: Dictionary = NPCManager.state[p]
	var who := str(NPCManager.npcs[target]["nome"])
	st["suspeita"] = mini(int(st["suspeita"]) + 30, 100)
	st["afeto"] = maxi(int(st["afeto"]) - 22, -100)
	st["confianca"] = maxi(int(st["confianca"]) - 22, -100)
	st["emocao"] = "furioso"
	st["ciume"] = TimeManager.total_minutes
	_remember(p, "[%s] Descobri (%s) que o jogador deu em cima de %s. Estou furioso(a) e magoado(a)." % [TimeManager.clock_str(), how, who])
	for r in data()["rumores"]:
		if str(r["parceiro"]) == p and str(r["alvo"]) == target:
			r["fim"] = true
	var name := NPCManager.display_name(p)
	if int(st["afeto"]) < 15:
		st["namoro"] = false
		st["ex"] = true
		GameState.add_log("%s ficou sabendo que você deu em cima de %s e terminou com você." % [name, who], "danger")
		if PhoneSystem.has_contact(p):
			PhoneSystem.receive(p, "Me contaram de você com %s. Acabou. Não me procura mais." % who)
	else:
		GameState.add_log("%s ficou sabendo que você deu em cima de %s." % [name, who], "danger")
		if PhoneSystem.has_contact(p):
			PhoneSystem.receive(p, "A gente precisa conversar. Me contaram que você deu em cima de %s. É verdade?" % who)


# A cada hora: quem sabe da fofoca conta para alguém (no mesmo lugar, de preferência).
func _spread_hour() -> void:
	var rs: Array = data()["rumores"]
	for r in rs:
		if r["fim"]:
			continue
		var knowers: Array = r["sabem"]
		var told: Array = []
		for k in knowers.duplicate():
			if not NPCManager.state.has(k) or not NPCManager.state[k].get("vivo", true):
				continue
			if randf() > 0.12:
				continue
			var here := NPCManager.location_of(k)
			var pool: Array = []
			for o in NPCManager.npcs:
				if o == k or o in knowers or not NPCManager.state[o].get("vivo", true):
					continue
				if here != "" and NPCManager.location_of(o) == here:
					pool.append(o)
			if pool.is_empty():
				for o in NPCManager.npcs:
					if o != k and not o in knowers and NPCManager.state[o].get("vivo", true) and randf() < 0.15:
						pool.append(o)
			if pool.is_empty():
				continue
			var o2: String = pool.pick_random()
			told.append(o2)
			knowers.append(o2)
			if o2 == str(r["parceiro"]):
				_partner_learns(o2, str(r["alvo"]), "por fofoca de %s" % str(NPCManager.npcs[k]["nome"]))
				break
			_remember(o2, "[%s] %s me contou que o jogador deu em cima de %s, mesmo namorando %s." % [TimeManager.clock_str(), NPCManager.npcs[k]["nome"], NPCManager.npcs[r["alvo"]]["nome"], NPCManager.npcs[r["parceiro"]]["nome"]])
		# fofoca velha esfria
		if TimeManager.day() - int(r["dia"]) > 30:
			r["fim"] = true
	data()["rumores"] = rs.filter(func(x): return not x["fim"] or TimeManager.day() - int(x["dia"]) < 40)


func rumor_count_about(partner: String) -> int:
	var n := 0
	for r in data()["rumores"]:
		if str(r["parceiro"]) == partner and not r["fim"]:
			n += 1
	return n


# ---------- aniversários ----------

func is_birthday(id: String) -> bool:
	return GameState.active and AgingSystem.days_until_birthday(id) == 0


static func is_congrats(text: String) -> bool:
	Local._compile()
	var t := Local._norm(text)
	return " parab" in t or "feliz aniversario" in t or "feliz niver" in t or " niver " in t


# Dar parabéns no dia (uma vez por ano): resposta local com alegria e relação melhor.
func congrats_reply(id: String, text: String) -> Dictionary:
	if not is_birthday(id) or not is_congrats(text):
		return {}
	var st: Dictionary = NPCManager.state[id]
	var year := int(TimeManager.date()["y"])
	if int(st.get("parabens", -1)) == year:
		return {"fala": "Obrigado(a) de novo, hein! Você não esquece mesmo.", "emocao": "feliz", "relacao": {"afeto": 1}}
	st["parabens"] = year
	var age := int(NPCManager.npcs[id].get("idade", 30))
	return {"fala": ["Ah, você lembrou! Obrigado(a), de verdade. %d anos nas costas..." % age, "Nossa, ninguém tinha me dado parabéns ainda hoje. Valeu mesmo!", "Que coisa boa! Obrigado(a). Vou comemorar mais tarde no bar, aparece!"].pick_random(),
		"emocao": "feliz", "relacao": {"afeto": 9, "confianca": 4}, "memoria": "O jogador lembrou do meu aniversário e me deu parabéns.", "acao_corporal": "abre um sorriso largo"}


# Presente no dia do aniversário vale mais.
func gift_bonus(id: String, item_id: String) -> void:
	if not is_birthday(id):
		return
	var st: Dictionary = NPCManager.state[id]
	var year := int(TimeManager.date()["y"])
	if int(st.get("presente", -1)) == year:
		return
	st["presente"] = year
	st["afeto"] = mini(int(st["afeto"]) + 10, 100)
	st["confianca"] = mini(int(st["confianca"]) + 4, 100)
	_remember(id, "[%s] O jogador me deu %s de presente de aniversário." % [TimeManager.clock_str(), World.item_name(item_id).to_lower()])
	GameState.add_log("%s ficou emocionado(a) com o presente de aniversário." % NPCManager.display_name(id), "event")


# Comemoração: no dia do aniversário, quem faz anos vai ao bar à noite (ou à praça, se o bar fechar).
func party_location(id: String, h: int) -> String:
	if not GameState.active or h < 19 or h >= 23 or not NPCManager.state.get(id, {}).get("vivo", true):
		return ""
	if int(NPCManager.npcs[id].get("idade", 30)) < 18:
		return "praca" if h < 21 else ""
	if not is_birthday(id):
		return ""
	return "bar" if World.is_open("bar", h) else "praca"


func _on_birthday(id: String, age: int) -> void:
	if id == "":
		# aniversário do jogador: os amigos lembram
		for k in NPCManager.npcs:
			var st: Dictionary = NPCManager.state[k]
			if PhoneSystem.has_contact(k) and st.get("vivo", true) and int(st["afeto"]) >= 30 and not st.get("bloqueado", false):
				var msg: String = ["Feliz aniversário! Tudo de bom pra você!", "Parabéns!! Bora comemorar?", "Feliz aniversário. Que esse ano seja melhor que o último.", "Parabéns pelos %d! Saúde e dinheiro no bolso." % age].pick_random()
				if st.get("namoro", false):
					msg = "Feliz aniversário, meu amor. Hoje é seu dia ❤"
				PhoneSystem.receive(k, msg)
		return
	var st2: Dictionary = NPCManager.state.get(id, {})
	if st2.is_empty() or not st2.get("vivo", true):
		return
	st2["emocao"] = "feliz"
	if PhoneSystem.has_contact(id) and int(st2["afeto"]) >= 35 and age >= 18:
		PhoneSystem.receive(id, "Hoje é meu aniversário! Vou comemorar no bar a partir das 20h, aparece lá.")


# ---------- passagem do tempo ----------

func _on_time_advanced(_m: int, _s: bool) -> void:
	if not GameState.active:
		return
	var d := data()
	var hour_now := TimeManager.total_minutes / 60
	var steps := mini(hour_now - int(d.get("ultima_hora", hour_now)), 48)
	if hour_now < int(d.get("ultima_hora", hour_now)):
		d["ultima_hora"] = hour_now
		steps = 0
	for i in steps:
		_spread_hour()
	d["ultima_hora"] = hour_now
	var today := TimeManager.day()
	var last := int(d.get("ultimo_dia", today))
	if today < last:
		d["ultimo_dia"] = today
		return
	for gd in range(last, mini(today, last + 10)):
		_end_of_day(gd)
	d["ultimo_dia"] = today


# Fim de um dia: no Dia dos Namorados, quem namora e foi esquecido fica magoado.
func _end_of_day(game_day: int) -> void:
	var h := Holidays.of_day(game_day)
	if h.is_empty() or not h.get("casais", false):
		return
	for p in partners():
		var st: Dictionary = NPCManager.state[p]
		if int(st.get("namorados_dia", -1)) == game_day:
			continue
		st["afeto"] = maxi(int(st["afeto"]) - 12, -100)
		_remember(p, "[%s] O jogador esqueceu o Dia dos Namorados. Fiquei esperando o dia inteiro." % TimeManager.clock_str())
		GameState.add_log("%s ficou magoado(a): você esqueceu o Dia dos Namorados." % NPCManager.display_name(p), "danger")


# Qualquer carinho no Dia dos Namorados (falar, mandar mensagem, presente) conta.
func note_contact(id: String, gift: bool = false) -> void:
	var h := Holidays.today()
	var st: Dictionary = NPCManager.state.get(id, {})
	if h.is_empty() or not h.get("casais", false) or not st.get("namoro", false):
		return
	if int(st.get("namorados_dia", -1)) == TimeManager.day() and not gift:
		return
	if int(st.get("namorados_dia", -1)) != TimeManager.day():
		st["afeto"] = mini(int(st["afeto"]) + 6, 100)
		_remember(id, "[%s] O jogador lembrou do Dia dos Namorados." % TimeManager.clock_str())
	st["namorados_dia"] = TimeManager.day()
	if gift:
		st["afeto"] = mini(int(st["afeto"]) + 8, 100)
