extends RefCounted

# Confere o que o jogador escreve entre *asteriscos* com o que ele realmente tem.

const ITEM_WORDS := {
	"cigarro": ["cigarro", "cigarros", "tabaco", "maco"],
	"cerveja": ["cerveja", "cervejas", "breja"],
	"cachaca": ["cachaca", "pinga"],
	"agua": ["agua"],
	"refrigerante": ["refrigerante", "refri"],
	"cafe": ["cafe"],
	"energetico": ["energetico"],
	"pao": ["pao"],
	"pao_queijo": ["pao de queijo"],
	"coxinha": ["coxinha", "coxinhas"],
	"prato_feito": ["prato feito", "marmita"],
	"miojo": ["miojo"],
	"frutas": ["fruta", "frutas"],
	"pipoca": ["pipoca"],
	"analgesico": ["analgesico", "remedio", "comprimido"],
	"curativo": ["curativo"],
	"lenco_umedecido": ["lenco", "lencos"],
	"faca": ["faca", "facao", "canivete"],
	"pe_de_cabra": ["pe de cabra"],
	"mixa": ["mixa", "mixas", "gazua"],
}
const NEVER_HAVE := ["arma de fogo", "pistola", "revolver", "espingarda", "granada", "bomba", "fuzil"]
const PASS_VERBS := [" pergunto ", " pedir ", " peco ", " comprar ", " compro ", " quero ", " procuro ", " vejo ", " olho ", " aponto ", " cheiro ", " sinto ", " noto ", " reparo "]
const GIVE_VERBS := [" entreg", " dou ", " pago ", " pagar ", " pag ", " passo ", " ofere", " estico ", " largo ", " deixo ", " jogo ", " dar "]
const USE_VERBS := {
	"cigarro": [" fum", " acend", " trag"],
	"bebida": [" beb", " tom", " golej", " engol", " viro "],
	"comida": [" comer ", " como ", " comendo ", " mord", " devor", " mastig"],
	"remedio": [" tom", " engol"],
}
const TYPE_TO_USE := {"cigarro": "cigarro", "bebida": "bebida", "cafe": "bebida", "lata": "bebida", "garrafa": "bebida", "dose": "bebida", "comida": "comida", "remedio": "remedio"}


static func _norm(s: String) -> String:
	var t := s.to_lower()
	var from := "áàâãäéèêëíìîïóòôõöúùûüçñ"
	var to := "aaaaaeeeeiiiiooooouuuucn"
	for i in from.length():
		t = t.replace(from[i], to[i])
	var out := ""
	for ch in t:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else " "
	return " " + " ".join(out.split(" ", false)) + " "


static func _has_any(n: String, words: Array) -> bool:
	for w in words:
		if n.contains(w):
			return true
	return false


static func run(text: String) -> Dictionary:
	var result := {"text": text, "blocked": false, "logs": [], "consume": [], "pay": 0}
	var re := RegEx.create_from_string("\\*([^*]+)\\*")
	var matches := re.search_all(text)
	if matches.is_empty():
		return result
	var money_re := RegEx.create_from_string("(?i)r\\$\\s*(\\d+)|(\\d+)\\s*reais")
	var new_text := text
	var invalid := 0
	var valid := 0
	var spend := 0
	for i in range(matches.size() - 1, -1, -1):
		var m := matches[i]
		var seg := m.get_string(1)
		var n := _norm(seg)
		var passes := _has_any(n, PASS_VERBS)
		var missing: Array = []
		for id in ITEM_WORDS:
			for kw in ITEM_WORDS[id]:
				if n.contains(" " + kw + " ") and GameState.item_count(id) <= 0 and not passes:
					if not id in missing:
						missing.append(id)
		var never := ""
		if not passes:
			for kw in NEVER_HAVE:
				if n.contains(" " + kw + " "):
					never = kw
		var bad_money := 0
		var mm := money_re.search(seg)
		if mm and _has_any(n, GIVE_VERBS):
			var amount := int(mm.get_string(1)) if mm.get_string(1) != "" else int(mm.get_string(2))
			if amount > GameState.money() - spend:
				bad_money = amount
			else:
				spend += amount
		var replacement := ""
		if not missing.is_empty():
			var names: Array = missing.map(func(id): return World.item_name(id).to_lower())
			replacement = "*tateia os bolsos procurando %s, mas não tem*" % ", ".join(names)
			result["logs"].append("Você não tem %s." % ", ".join(names))
		elif never != "":
			replacement = "*leva a mão à cintura, mas não tem %s*" % never
			result["logs"].append("Você não tem %s." % never)
		elif bad_money > 0:
			replacement = "*abre a carteira, mas só tem R$ %d*" % GameState.money()
			result["logs"].append("Você só tem R$ %d, não dá para entregar R$ %d." % [GameState.money(), bad_money])
		if replacement != "":
			invalid += 1
			new_text = new_text.substr(0, m.get_start()) + replacement + new_text.substr(m.get_end())
			continue
		valid += 1
		for id in ITEM_WORDS:
			if GameState.item_count(id) <= 0 or id in result["consume"]:
				continue
			var kind: String = TYPE_TO_USE.get(str(World.items[id].get("tipo", "")), "")
			if kind == "":
				continue
			for kw in ITEM_WORDS[id]:
				if n.contains(" " + kw + " ") and _has_any(n, USE_VERBS[kind]):
					result["consume"].append(id)
					break
	result["pay"] = spend
	result["text"] = new_text
	var speech := re.sub(text, "", true).strip_edges()
	if invalid > 0 and valid == 0 and speech == "":
		result["blocked"] = true
	return result
