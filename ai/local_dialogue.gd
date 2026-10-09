extends RefCounted

# Respostas rápidas dos NPCs sem usar a IA. Reconhece a intenção da frase (cumprimento, preço,
# direção, elogio, ameaça...), escolhe o tom pela relação com o jogador e a personalidade do NPC
# e monta a fala com condições de hora, clima, lugar e se já se conhecem. O jogo continua mandando:
# nome só sai se a relação deixar, número do celular só com afeto, preços vêm da loja real.
# O que não for reconhecido (ou for complexo) devolve {} e quem decide é a IA.

const Data = preload("res://ai/dialogue_lines.gd")
const Expr = preload("res://ai/expression_engine.gd")
const Prompts = preload("res://ai/prompts.gd")

# ordem de prioridade (mais específico primeiro)
const ORDER := ["ameaca", "insulto", "meu_nome", "nome", "numero", "preco", "cardapio", "tem_item", "onde_fica", "quem_e", "hora", "clima", "profissao", "idade", "flerte", "elogio",
	"agradecimento", "desculpa", "piada", "fofoca", "perigo", "cidade", "fome_sede", "cansaco", "dinheiro", "trabalho", "quarto", "vicio", "crime", "segredo", "saude", "humor_jogador",
	"lembranca", "religiao", "politica", "hobby", "familia", "passado", "opiniao", "ajuda", "prazer", "pedido_silencio", "pedir_espera", "mudar_assunto", "confirmar_info",
	"saudacao", "despedida", "como_vai", "sim_nao", "gesto"]

const ITEM_ALIAS := {
	"cafe": ["cafe", "cafezinho"], "pao": ["pao de forma", "pao"], "pao_queijo": ["pao de queijo"], "coxinha": ["coxinha"], "prato_feito": ["prato feito", "pf", "almoco", "marmita", "refeicao"],
	"miojo": ["miojo", "macarrao instantaneo"], "frutas": ["fruta", "frutas"], "pipoca": ["pipoca"], "agua": ["agua"], "refrigerante": ["refrigerante", "refri", "coca", "guarana"],
	"energetico": ["energetico"], "cerveja": ["cerveja", "gelada", "breja"], "cachaca": ["cachaca", "pinga", "dose"], "cigarro": ["cigarro", "maco"], "lenco_umedecido": ["lenco"],
	"analgesico": ["analgesico", "remedio", "dipirona", "comprimido"], "faca": ["faca"], "pe_de_cabra": ["pe de cabra", "pe-de-cabra"], "mixa": ["mixa", "mixas"], "curativo": ["curativo", "band aid", "bandaid"],
}
const PLACE_ALIAS := {
	"hospital": ["hospital", "pronto socorro", "upa", "sao lucas", "medico"], "delegacia": ["delegacia", "policia", "dp"], "mercado": ["mercado", "supermercado", "bom preco"],
	"bar": ["bar", "bar do ze", "boteco"], "lanchonete": ["lanchonete", "estrela", "lanche"], "praca": ["praca", "centro"], "parque": ["parque", "lago", "parque das aguas"],
	"rodoviaria": ["rodoviaria", "onibus", "estacao"], "beco": ["beco", "rua 7", "rua sete"], "igreja": ["igreja", "santa rita", "capela"], "pensao": ["pensao", "dona cida"],
	"rua_acacias": ["acacias", "rua das acacias"],
}
const RISKY := ["dou ", "entrego", "pego", "tiro ", "ataco", "bato", "empurro", "soco", "chuto", "mato", "roubo", "furto", "ofereco", "mostro", "compro", "pago", "jogo ", "arremesso", "seguro", "agarro", "puxo", "beijo", "toco", "acendo", "fumo", "bebo", "como ", "entro", "saio", "abro", "fecho", "pulo", "saco ", "aponto", "ameaco", "estrangulo", "esfaqueio", "atiro"]
const FEM_PLACES := ["praca", "lanchonete", "pensao", "igreja", "delegacia", "rodoviaria", "rua"]

static var _pat: Dictionary = {}
static var _ready: bool = false
static var _name_re: RegEx
static var _star_re: RegEx
static var _clean_re: RegEx


static func _compile() -> void:
	if _ready:
		return
	for intent in Data.PATTERNS:
		var list: Array = []
		for p in Data.PATTERNS[intent]:
			var s: String = Expr.norm(str(p)).strip_edges()
			var prefix := s.ends_with("*")
			s = s.trim_suffix("*").strip_edges()
			s = s.replace("?", "").replace(":", "").replace("  ", " ").strip_edges()
			if s != "":
				list.append([s, prefix])
		_pat[intent] = list
	_name_re = RegEx.create_from_string("(?i)(?:meu nome (?:é|e)|me chamo|pode me chamar de|me chamam de|sou (?:o|a)|eu sou (?:o|a)?)\\s+([A-Za-zÀ-ÿ]{2,})")
	_star_re = RegEx.create_from_string("\\*([^*]+)\\*")
	_clean_re = RegEx.create_from_string("[^a-z0-9? ]")
	_ready = true


static func _norm(text: String) -> String:
	var t := Expr.norm(text)
	t = _clean_re.sub(t, " ", true)
	t = t.replace("?", " ? ")
	while t.contains("  "):
		t = t.replace("  ", " ")
	return " " + t.strip_edges() + " "


static func detect(padded: String) -> Array:
	var found: Array = []
	var words := padded.strip_edges().split(" ", false).size()
	for intent in ORDER:
		for e in _pat.get(intent, []):
			var ph: String = e[0]
			var hit := padded.contains(" " + ph) if bool(e[1]) else padded.contains(" " + ph + " ")
			if hit:
				if intent == "sim_nao" and words > 4:
					break
				if intent in ["gesto"]:
					break
				found.append(intent)
				break
	return found


# ---------- contexto ----------

static func tone_of(st: Dictionary) -> String:
	if st.get("bloqueado", false):
		return "hostil"
	var t := int(st["confianca"])
	var a := int(st["afeto"])
	var s := int(st["suspeita"])
	if st.get("namoro", false) or (a >= 50 and t >= 35):
		return "intimo"
	if a >= 25 and t >= 15:
		return "amigavel"
	if t <= -15 or a <= -15 or s >= 70:
		return "hostil"
	if s >= 35 or (t < 6 and a < 6):
		return "frio"
	return "neutro"


static func archetype_of(id: String) -> String:
	var n: Dictionary = NPCManager.npcs[id]
	var table := {"ze": "ranzinza", "marina": "simpatico", "ruan": "manipulador", "helena": "frio", "otavio": "autoritario", "bia": "fofoqueiro", "padre": "religioso",
		"dona_cida": "fofoqueiro", "leo": "piadista", "kaio": "paranoico", "vanessa": "ansioso", "tiago": "simpatico", "irene": "manipulador", "gabriel": "romantico", "silas": "quieto"}
	if table.has(id):
		return table[id]
	var p := Expr.norm(str(n.get("personalidade", "")))
	var rules := [["ranzinza", "ranzinza"], ["seco", "ranzinza"], ["manipul", "manipulador"], ["paranoic", "paranoico"], ["relig", "religioso"], ["fofoc", "fofoqueiro"], ["piad", "piadista"],
		["engrac", "piadista"], ["autoritar", "autoritario"], ["ansios", "ansioso"], ["nervos", "ansioso"], ["quiet", "quieto"], ["calad", "quieto"], ["timid", "quieto"],
		["romantic", "romantico"], ["sonhad", "romantico"], ["frio", "frio"], ["reserv", "frio"], ["simpatic", "simpatico"], ["falante", "simpatico"], ["extrovert", "simpatico"], ["gentil", "simpatico"]]
	for r in rules:
		if p.contains(r[0]):
			return r[1]
	return "neutro"


static func period_tag() -> String:
	var h := TimeManager.hour()
	if h < 5:
		return "madrugada"
	if h < 12:
		return "manha"
	if h < 18:
		return "tarde"
	return "noite"


static func place_tag(id: String) -> String:
	var loc: Dictionary = World.locations.get(NPCManager.location_of(id), {})
	var tipo := str(loc.get("tipo", "publico"))
	if str(NPCManager.location_of(id)) == "igreja":
		return "igreja"
	return tipo


static func _tags_ok(tags: Array, ctx: Dictionary) -> bool:
	for group in tags:
		var okg := false
		for tg in str(group).split("|"):
			if ctx["tags"].has(tg):
				okg = true
				break
		if not okg:
			return false
	return true


# separa "[a|b] [c] texto" em ([[a,b],[c]], texto)
static func _parse_line(line: String) -> Array:
	var tags: Array = []
	var s := line
	while s.begins_with("["):
		var e := s.find("]")
		if e < 0:
			break
		tags.append(s.substr(1, e - 1))
		s = s.substr(e + 1).strip_edges()
	return [tags, s]


static func _pick_line(intent: String, tone: String, ctx: Dictionary, st: Dictionary) -> String:
	var table: Dictionary = Data.LINES.get(intent, {})
	var chain: Array = [tone]
	match tone:
		"intimo":
			chain += ["amigavel", "neutro"]
		"amigavel":
			chain += ["neutro"]
		"hostil":
			chain += ["frio", "neutro"]
		"medo":
			chain += ["frio", "neutro"]
		"frio":
			chain += ["neutro"]
		"neutro":
			chain += ["frio"]
	var recent: Array = st.get("local_recent", [])
	for t in chain:
		var pool: Array = table.get(t, [])
		if pool.is_empty():
			continue
		var scored: Array = []
		var fresh: Array = []
		for raw in pool:
			var parsed := _parse_line(str(raw))
			if not _tags_ok(parsed[0], ctx):
				continue
			var w: float = 1.0 + 2.0 * float((parsed[0] as Array).size())
			scored.append([parsed[1], w])
			if not recent.has(hash(parsed[1])):
				fresh.append([parsed[1], w])
		var use: Array = fresh if not fresh.is_empty() else scored
		if use.is_empty():
			continue
		var total := 0.0
		for e in use:
			total += float(e[1])
		var r := randf() * total
		for e in use:
			r -= float(e[1])
			if r <= 0.0:
				return str(e[0])
		return str(use[0][0])
	return ""


# ---------- fatos do mundo ----------

static func _cardinal(from: Vector2, to: Vector2) -> String:
	var d := to - from
	if d.length() < 3.0:
		return "aqui perto"
	var ang := rad_to_deg(atan2(d.x, -d.y))
	if ang < 0.0:
		ang += 360.0
	var names := ["pro norte", "pro nordeste", "pro leste", "pro sudeste", "pro sul", "pro sudoeste", "pro oeste", "pro noroeste"]
	return names[int(round(ang / 45.0)) % 8]


static func _find_place(norm_text: String) -> String:
	var best := ""
	var best_len := 0
	for pid in PLACE_ALIAS:
		for a in PLACE_ALIAS[pid]:
			var al := Expr.norm(str(a))
			if norm_text.contains(" " + al + " ") or norm_text.contains(" " + al):
				if al.length() > best_len and World.locations.has(pid):
					best = pid
					best_len = al.length()
	return best


static func _find_item(norm_text: String) -> String:
	var best := ""
	var best_len := 0
	for iid in ITEM_ALIAS:
		for a in ITEM_ALIAS[iid]:
			var al := Expr.norm(str(a))
			if norm_text.contains(" " + al):
				if al.length() > best_len and World.items.has(iid):
					best = iid
					best_len = al.length()
	return best


static func _shop_items(id: String) -> Array:
	var loc: Dictionary = World.locations.get(NPCManager.location_of(id), {})
	return loc.get("loja", [])


static func _other_npc(id: String, norm_text: String) -> String:
	var best := ""
	var best_len := 0
	for oid in NPCManager.npcs:
		if oid == id:
			continue
		var n: Dictionary = NPCManager.npcs[oid]
		var keys: Array = [Expr.norm(oid.replace("_", " ")), Expr.norm(str(n["nome"]).split(" ")[0])]
		var role: String = Expr.norm(str(n["profissao"]))
		for rk in ["padre", "medica", "sargento", "enfermeira", "taxista", "musico", "faz-tudo", "gerente", "caixa", "estudante", "agiota"]:
			if role.contains(rk):
				keys.append(rk)
		for k in keys:
			var ks := str(k).strip_edges()
			if ks.length() >= 3 and (norm_text.contains(" " + ks + " ") or norm_text.contains(" " + ks)):
				if ks.length() > best_len:
					best = oid
					best_len = ks.length()
	return best


static func _article_place(name: String) -> String:
	var first := Expr.norm(name.split(" ")[0])
	var fem := first in ["praca", "lanchonete", "pensao", "igreja", "delegacia", "rodoviaria", "rua", "casa", "sua"]
	return ("na " if fem else "no ") + name


static func _clima_text() -> String:
	if WorldEvents.active("tempestade"):
		return "Temporal forte lá fora, não saia sem necessidade."
	if WorldEvents.raining():
		return "Tá chovendo, sim."
	if str(World.scenario().get("nome", "")) == "Colapso Cinza" or World.scenario().get("cinzas", false):
		return "O ar tá pesado, cheio de cinza."
	var h := TimeManager.hour()
	if h < 6 or h >= 22:
		return "Madrugada fria e céu limpo."
	if h < 12:
		return "Manhã de céu aberto e sol fraco."
	if h < 17:
		return "Sol forte e ar seco."
	return "Fim de tarde abafado."


static func _fill(line: String, ctx: Dictionary) -> String:
	var out := line
	for k in ctx["vars"]:
		out = out.replace("{" + str(k) + "}", str(ctx["vars"][k]))
	return out


static func _gender(text: String, npc_female: bool, player_female: bool) -> String:
	var t := text
	t = t.replace("homem/mulher", "mulher" if player_female else "homem")
	var re := RegEx.create_from_string("([a-záéíóúâêôãõç]+)o\\(a\\)")
	var parts := re.search_all(t)
	for i in range(parts.size() - 1, -1, -1):
		var m: RegExMatch = parts[i]
		var rep: String = m.get_string(1) + ("a" if npc_female else "o")
		t = t.substr(0, m.get_start()) + rep + t.substr(m.get_end())
	t = t.replace("(a)", "a" if npc_female else "")
	return t


# ---------- API principal ----------

static func try_reply(id: String, text: String, chan: String = "presencial") -> Dictionary:
	_compile()
	if not NPCManager.npcs.has(id) or not NPCManager.state.has(id):
		return {}
	var st: Dictionary = NPCManager.state[id]
	var n: Dictionary = NPCManager.npcs[id]
	# separa ações e fala
	var actions := ""
	for m in _star_re.search_all(text):
		actions += " " + m.get_string(1)
	var speech := _star_re.sub(text, " ", true).strip_edges()
	var act_norm := Expr.norm(actions)
	for r in RISKY:
		if act_norm.contains(r):
			return {}
	var padded := _norm(speech)
	var words := padded.strip_edges().split(" ", false).size()
	var intents: Array = []
	if speech == "" or padded.strip_edges() == "":
		if act_norm.strip_edges() == "":
			return {}
		var safe := ["aceno", "sorrio", "cumprimento", "aperto a mao", "sento", "olho", "aceno com a cabeca", "me sento", "aguardo", "espero"]
		var ok := false
		for sfe in safe:
			if act_norm.contains(sfe):
				ok = true
		if not ok:
			return {}
		intents = ["gesto"]
	else:
		if words > 22 or padded.count("?") >= 3:
			return {}
		intents = detect(padded)
	if intents.is_empty() and padded.begins_with(" tem ") and _find_item(padded) != "":
		intents = ["tem_item"]
	if intents.is_empty():
		return {}
	# pergunta pendente do NPC: respostas curtas dependem do contexto, quem decide é a IA
	var hist: Array = st["historico"]
	var last_q := false
	for i in range(hist.size() - 1, -1, -1):
		if str(hist[i]["role"]) == "assistant":
			var parsed: Dictionary = Prompts.parse_npc_reply(str(hist[i]["content"]))
			last_q = str(parsed.get("fala", "")).strip_edges().ends_with("?")
			break
	var small := true
	for it in intents:
		if not it in ["sim_nao", "confirmar_info", "mudar_assunto", "pedir_espera", "prazer"]:
			small = false
	if last_q and small:
		return {}
	# tom, arquétipo e contexto
	var tone := tone_of(st)
	var fear := int(st["medo"])
	var arch := archetype_of(id)
	var female: bool = str(n["genero"]) == "mulher"
	var pfemale: bool = str(GameState.player.get("gender", "homem")) == "mulher"
	var period := period_tag()
	var tags := {period: true, place_tag(id): true}
	if WorldEvents.raining():
		tags["chuva"] = true
	tags["conhecido" if st.get("conheceu", false) else "desconhecido"] = true
	tags["sabe_nome" if st.get("sabe_nome_jogador", false) else "sem_nome"] = true
	var pname := str(GameState.player.get("name", ""))
	var tr := "moça" if pfemale else "moço"
	match tone:
		"amigavel":
			tr = "amiga" if pfemale else "amigo"
		"intimo":
			tr = "querida" if pfemale else "querido"
		"hostil", "frio":
			tr = "moça" if pfemale else "rapaz"
	var vars := {
		"tr": tr, "jog": pname.split(" ")[0] if st.get("sabe_nome_jogador", false) and pname != "" else tr,
		"nome": str(n["nome"]).split(" ")[0] if not str(n["nome"]).begins_with("Dona") else str(n["nome"]),
		"prof": str(n["profissao"]).to_lower(), "idade": str(n["idade"]), "hora": "%dh%02d" % [TimeManager.hour(), TimeManager.minute()],
		"clima": _clima_text(), "rumor": Data.RUMORES.pick_random(), "manchete": "", "destino": "", "dir": "", "min": "", "item": "", "preco": "", "lista": "", "outro": "", "outro_prof": "", "outro_lugar": "",
	}
	var news := NewsSystem.entries().filter(func(e): return e["tipo"] in ["crime", "evento", "cidade"])
	if not news.is_empty():
		var ne: Dictionary = news[news.size() - 1]
		vars["manchete"] = str(ne["titulo"]) + "."
		tags["manchete"] = true
	var ctx := {"tags": tags, "vars": vars}
	var loc_id := NPCManager.location_of(id)
	# fatos por intenção; devolve {} se faltar informação (a IA assume)
	var action_list: Array = []
	var reveal := false
	var learned := false
	var forced_lines: Array = []
	for it in intents:
		match it:
			"dinheiro":
				if tone in ["amigavel", "intimo"] and int(st["confianca"]) >= 30 and int(st["dinheiro"]) >= 50:
					return {}
			"trabalho", "quarto":
				var srv: Dictionary = n.get("servicos", {})
				if srv.has("emprego") or srv.has("quarto") or srv.has("aluga"):
					return {}
			"segredo":
				if int(st["confianca"]) >= 40:
					return {}
			"flerte":
				if tone == "intimo" and int(st["afeto"]) >= 40:
					return {}
			"meu_nome":
				var m := _name_re.search(speech)
				if m == null:
					intents = intents.filter(func(x): return x != "meu_nome")
				else:
					var nm := m.get_string(1)
					if nm.to_lower() in ["um", "uma", "o", "a", "novo", "nova", "aqui", "daqui", "de", "do", "da", "seu", "sua", "amigo", "amiga"]:
						intents = intents.filter(func(x): return x != "meu_nome")
					else:
						learned = true
						vars["jog"] = nm
	if intents.is_empty():
		return {}
	var shop := _shop_items(id)
	var chosen: Array = intents.slice(0, 1)
	if intents.size() > 1:
		var first: String = intents[0]
		for other in intents.slice(1):
			if Data.COMBO_OK.get(first, []).has(other) or Data.COMBO_OK.get(other, []).has(first):
				chosen.append(other)
				break
	var pieces: Array = []
	var emo := "neutro"
	var rel: Dictionary = {}
	var memory := ""
	for it in chosen:
		var line_tone := tone
		if fear >= 40 and it in ["insulto", "ameaca", "segredo", "crime"]:
			line_tone = "medo"
		var piece_tags: Dictionary = ctx["tags"].duplicate()
		match it:
			"nome":
				var allow := tone in ["neutro", "amigavel", "intimo"] or (arch in ["simpatico", "piadista", "fofoqueiro", "romantico"] and tone != "hostil")
				if arch in ["paranoico", "quieto"] and int(st["confianca"]) < 12:
					allow = false
				if st.get("conhece_nome", false):
					pieces.append(["Já te disse, sou %s." % vars["nome"], "neutro"])
					continue
				if allow:
					reveal = true
				else:
					line_tone = "frio" if tone != "hostil" else "hostil"
			"numero":
				var give: bool = int(st["afeto"]) >= 15 and int(st["confianca"]) >= 10 and tone in ["amigavel", "intimo"] or (arch in ["simpatico", "piadista", "romantico"] and int(st["afeto"]) >= 8 and tone != "hostil")
				if PhoneSystem.has_contact(id):
					pieces.append(["Já te passei, {jog}. Salva aí.", "neutro"])
					continue
				if give:
					piece_tags["passa"] = true
					action_list.append({"tipo": "dar_numero"})
					line_tone = "amigavel" if tone == "neutro" or tone == "frio" else tone
				else:
					piece_tags["nao_passa"] = true
					line_tone = "neutro" if tone in ["amigavel", "intimo"] else tone
			"preco", "tem_item":
				var item := _find_item(padded)
				if item == "":
					return {}
				vars["item"] = World.item_name(item).to_lower()
				if shop.has(item):
					vars["preco"] = str(World.item_price(item, loc_id))
					piece_tags["tem"] = true
				else:
					piece_tags["nao_tem"] = true
					if it == "preco":
						var alt := "Aqui não vendo isso."
						pieces.append([alt, "neutro"])
						continue
			"cardapio":
				if shop.is_empty():
					piece_tags["nao_tem"] = true
					var no_shop := "Aqui eu não vendo nada, {tr}."
					pieces.append([no_shop, "neutro"])
					continue
				var parts: Array = []
				for sid in shop.slice(0, 5):
					parts.append("%s (R$ %d)" % [World.item_name(str(sid)).to_lower(), World.item_price(str(sid), loc_id)])
				vars["lista"] = ", ".join(parts)
			"onde_fica":
				var dest := _find_place(padded)
				if dest == "":
					return {}
				if dest == loc_id:
					pieces.append(["É aqui mesmo, {tr}!", "neutro"])
					continue
				var a: Dictionary = World.locations.get(loc_id, World.current())
				var b: Dictionary = World.locations[dest]
				vars["destino"] = str(b["nome"])
				vars["dir"] = _cardinal(Vector2(float(a.get("x", 50)), float(a.get("y", 50))), Vector2(float(b["x"]), float(b["y"])))
				vars["min"] = str(maxi(2, World.travel_minutes(loc_id if World.locations.has(loc_id) else World.current_id(), dest)))
			"quem_e":
				var oid := _other_npc(id, padded)
				if oid == "":
					return {}
				var on: Dictionary = NPCManager.npcs[oid]
				vars["outro"] = str(on["nome"]).split(" ")[0] if not str(on["nome"]).begins_with("Dona") else str(on["nome"])
				vars["outro_prof"] = str(on["profissao"]).to_lower()
				var ol := NPCManager.location_of(oid)
				vars["outro_lugar"] = _article_place(str(World.locations[ol]["nome"])) if World.locations.has(ol) else "por aí, não sei onde agora"
		var raw := _pick_line(it, line_tone, {"tags": piece_tags, "vars": vars}, st)
		if raw == "":
			return {}
		pieces.append([raw, line_tone])
		var e := _emotion_for(it, tone, arch, fear)
		if emo == "neutro" or it in ["insulto", "ameaca", "flerte", "elogio"]:
			emo = e
		var d := _rel_delta(it, tone)
		for k in d:
			rel[k] = int(rel.get(k, 0)) + int(d[k])
		var mm := _memory(it, pname)
		if mm != "":
			memory = mm
	if pieces.is_empty():
		return {}
	var fala := ""
	var idx := 0
	for p in pieces:
		var line_text := _fill(str(p[0]), {"vars": vars})
		fala += (" " if fala != "" else "") + line_text
		idx += 1
	# sabor da personalidade e observações da situação
	var skip_flavor: bool = chosen[0] in ["sim_nao", "gesto", "pedir_espera"] or tone == "hostil" and randf() < 0.4
	var flavor: Dictionary = Data.FLAVOR.get(arch, Data.FLAVOR["neutro"])
	if not skip_flavor:
		if randf() < 0.55:
			var op := str(flavor["open"].pick_random())
			if op != "" and not fala.begins_with(op):
				fala = (op + " " + fala).strip_edges()
		if randf() < 0.5:
			var cl := str(flavor["close"].pick_random())
			if cl != "" and fala.length() < 140:
				fala = (fala + " " + cl).strip_edges()
	if tone in ["neutro", "amigavel"] and randf() < 0.18 and chosen[0] in ["saudacao", "como_vai", "cidade", "hora", "clima", "fofoca", "despedida", "agradecimento"]:
		var keys: Array = [period]
		if tags.has("chuva"):
			keys.append("chuva")
		keys.append(place_tag(id))
		var k2: String = keys.pick_random()
		if Data.SITUACIONAL.has(k2):
			fala += " " + str(Data.SITUACIONAL[k2].pick_random())
	fala = _fill(fala, {"vars": vars})
	fala = _gender(fala, female, pfemale)
	fala = fala.replace("  ", " ").strip_edges()
	# guarda para não repetir
	var recent: Array = st.get("local_recent", [])
	recent.append(hash(fala))
	if recent.size() > 14:
		recent.pop_front()
	st["local_recent"] = recent
	var body := ""
	if chan == "presencial" and randf() < 0.8:
		var pool: Array = Data.BODY.get(emo, Data.BODY["neutro"])
		body = str(pool.pick_random())
		body = _gender(body, female, pfemale)
	var out := {"responder": true, "fala": fala, "acao_corporal": body, "emocao": emo, "relacao": rel, "revela_nome": reveal, "aprendeu_nome_jogador": learned, "acoes": action_list, "_local": true, "_intents": chosen}
	if memory != "":
		out["memoria"] = memory
	return out


static func _emotion_for(intent: String, tone: String, arch: String, fear: int) -> String:
	match intent:
		"insulto":
			if fear >= 40 or arch in ["ansioso", "quieto", "paranoico"]:
				return "assustado"
			if arch in ["manipulador", "piadista"]:
				return "sarcastico"
			if tone == "hostil" or arch in ["autoritario", "ranzinza", "frio"]:
				return "furioso" if tone == "hostil" else "irritado"
			return "irritado" if tone != "amigavel" and tone != "intimo" else "triste"
		"ameaca":
			if fear >= 40 or arch in ["ansioso", "quieto", "paranoico", "romantico", "religioso"]:
				return "assustado"
			if arch in ["autoritario", "manipulador"] or tone == "hostil":
				return "ameacador"
			return "nervoso" if tone in ["amigavel", "intimo"] else "irritado"
		"elogio":
			if tone in ["hostil", "frio"]:
				return "desconfiado"
			return "envergonhado" if tone in ["amigavel", "intimo"] else "feliz"
		"flerte":
			if tone == "hostil":
				return "irritado"
			if tone == "frio":
				return "desconfiado"
			if tone == "neutro":
				return "surpreso"
			return "carinhoso" if tone == "intimo" else "envergonhado"
		"agradecimento", "prazer", "saudacao":
			return "feliz" if tone in ["amigavel", "intimo"] else ("neutro" if tone != "hostil" else "irritado")
		"piada":
			return "rindo" if tone in ["neutro", "amigavel", "intimo"] else "entediado"
		"desculpa":
			return "neutro" if tone != "hostil" else "irritado"
		"humor_jogador":
			return "carinhoso" if tone in ["amigavel", "intimo"] else "neutro"
		"segredo", "crime", "numero", "dinheiro":
			return "desconfiado" if tone in ["hostil", "frio"] else "neutro"
		"despedida":
			return "neutro" if tone != "intimo" else "carinhoso"
		"fofoca":
			return "feliz" if arch in ["fofoqueiro", "simpatico"] else "neutro"
		"perigo":
			return "nervoso" if arch in ["ansioso", "paranoico"] else "neutro"
		"cansaco", "fome_sede":
			return "carinhoso" if tone in ["amigavel", "intimo"] else "neutro"
	return "neutro" if tone != "hostil" else "irritado"


static func _rel_delta(intent: String, tone: String) -> Dictionary:
	var table := {
		"elogio": {"neutro": {"afeto": 2, "confianca": 1}, "amigavel": {"afeto": 2}, "intimo": {"afeto": 1}, "frio": {"afeto": 1, "suspeita": 1}, "hostil": {"suspeita": 3}},
		"insulto": {"*": {"afeto": -7, "confianca": -6, "suspeita": 4}},
		"ameaca": {"*": {"medo": 8, "confianca": -8, "suspeita": 8}},
		"flerte": {"neutro": {"afeto": 1, "suspeita": 2}, "amigavel": {"afeto": 3}, "intimo": {"afeto": 3, "confianca": 1}, "frio": {"afeto": -2, "suspeita": 3}, "hostil": {"afeto": -5, "suspeita": 4}},
		"agradecimento": {"*": {"afeto": 1}},
		"desculpa": {"*": {"afeto": 2, "confianca": 1}},
		"saudacao": {"neutro": {"confianca": 1}, "amigavel": {"afeto": 1}, "frio": {"suspeita": -1}},
		"piada": {"amigavel": {"afeto": 1}, "neutro": {"afeto": 1}},
		"humor_jogador": {"amigavel": {"afeto": 2, "confianca": 1}, "neutro": {"afeto": 1}, "intimo": {"afeto": 2}},
		"meu_nome": {"*": {"confianca": 1}},
		"prazer": {"*": {"confianca": 1}},
		"segredo": {"*": {"suspeita": 3}},
		"dinheiro": {"hostil": {"afeto": -2}},
	}
	var t = table.get(intent, {})
	if t.has(tone):
		return t[tone]
	if t.has("*"):
		return t["*"]
	return {}


static func _memory(intent: String, pname: String) -> String:
	match intent:
		"insulto":
			return "O jogador me insultou."
		"ameaca":
			return "O jogador me ameaçou."
		"elogio":
			return "O jogador me elogiou."
		"flerte":
			return "O jogador flertou comigo."
		"segredo":
			return "O jogador tentou arrancar segredos meus."
		"meu_nome":
			return "O jogador se apresentou."
	return ""


# Números para mostrar o tamanho do banco de respostas.
static func stats() -> Dictionary:
	var lines := 0
	for it in Data.LINES:
		for t in Data.LINES[it]:
			lines += (Data.LINES[it][t] as Array).size()
	var phrases := 0
	for it in Data.PATTERNS:
		phrases += (Data.PATTERNS[it] as Array).size()
	var archetypes: int = Data.FLAVOR.size()
	var flav_combos := 0
	for a in Data.FLAVOR:
		flav_combos += (Data.FLAVOR[a]["open"] as Array).size() * (Data.FLAVOR[a]["close"] as Array).size()
	var body := 0
	for e in Data.BODY:
		body += (Data.BODY[e] as Array).size()
	# células de condição: intenção x tom x personalidade x período x clima x tipo de lugar x conhece x nome
	var cells: int = Data.LINES.size() * 5 * archetypes * 4 * 2 * 7 * 2 * 2
	return {"intencoes": Data.LINES.size(), "frases_gatilho": phrases, "falas": lines, "personalidades": archetypes, "combinacoes_de_sabor": flav_combos, "gestos": body,
		"condicoes": cells, "variacoes": lines * maxi(flav_combos / maxi(archetypes, 1), 1) * 4}
