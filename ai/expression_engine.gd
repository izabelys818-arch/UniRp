extends RefCounted

# Lê o que o personagem está dizendo (fala e ações entre *asteriscos*) e decide, frase por frase,
# qual expressão o rosto deve fazer enquanto o texto aparece na caixa de diálogo.

# emoção -> [trecho, peso]; os trechos são procurados no texto sem acentos e em minúsculas
const LEX := {
	"rindo": [["kkk", 3], ["haha", 3], ["rsrs", 2], ["rs rs", 2], ["gargalh", 3], ["ri alto", 3], ["cai na risada", 3], ["engracad", 1.5], ["piada", 1], ["morrendo de rir", 3], ["ri ", 1.2], ["risada", 2], ["risos", 1.5]],
	"feliz": [["que bom", 2], ["legal", 1], ["adorei", 2], ["obrigad", 1.2], ["com prazer", 2], ["bem-vind", 2], ["bem vind", 2], ["otimo", 1.5], ["maravilh", 2], ["feliz", 2], ["parabens", 2], ["sorri", 2], ["sorriso", 1.5], ["alegri", 1.5], ["adoro", 1.5], ["perfeito", 1.5], ["claro que sim", 1.5], ["fico feliz", 2], ["que otimo", 2], ["animad", 1.5], ["acena", 1], ["brilham", 1.5]],
	"triste": [["sinto muito", 2], ["infelizmente", 1.5], ["saudade", 2], ["perdi", 1.5], ["morreu", 2], ["triste", 2], ["que pena", 2], ["lamento", 2], ["sozinh", 1.5], ["nao tem mais jeito", 2], ["desanim", 1.5], ["olhos marejad", 2.5], ["abaixa a cabeca", 1.5], ["olha para o chao", 1.2], ["voz embargada", 2.5], ["engole o choro", 2.5], ["perdeu", 1], ["falta dele", 1.5], ["falta dela", 1.5]],
	"chorando": [["chora", 3], ["lagrimas", 3], ["solu", 3], ["soluca", 3], ["desabafa chorando", 3], ["enxuga os olhos", 2.5], ["enxuga uma lagrima", 3]],
	"irritado": [["droga", 2], ["saco", 1.5], ["chato", 1.5], ["cala a boca", 3], ["vai embora", 2], ["some daqui", 2.5], ["raiva", 2], ["irrita", 2], ["absurdo", 2], ["ridicul", 2], ["chega", 1.2], ["nao aguento", 2], ["fora daqui", 2.5], ["nao enche", 2.5], ["que saco", 2.5], ["perdeu a paciencia", 3], ["bufa", 2.5], ["revira os olhos", 1], ["aperta os labios", 1.5], ["rosna", 2.5], ["impaciente", 2], ["que ousadia", 2]],
	"furioso": [["maldito", 3], ["desgracad", 3], ["vou te matar", 3], ["filho da", 3], ["lixo", 2], ["vou quebrar", 3], ["grita", 2.5], ["urra", 3], ["explode", 3], ["bate na mesa", 3], ["soca", 2.5], ["cego de raiva", 3], ["fora!", 3]],
	"desconfiado": [["quem e voce", 2.5], ["o que voce quer", 2.5], ["nao confio", 3], ["estranho", 1.5], ["por que", 1], ["desconfi", 2.5], ["nao te conheco", 2.5], ["de onde voce", 2], ["suspeit", 2], ["olha de lado", 2.5], ["aperta os olhos", 2.5], ["franze", 2], ["encara", 1.5], ["sera que", 1.2], ["tem algo", 1], ["duvido", 1.5], ["sei", 0.2], ["cruza os bracos", 1.5], ["olha de cima a baixo", 2.5], ["examina", 1.5], ["hm.", 1]],
	"assustado": [["socorro", 3], ["nao me machuque", 3], ["por favor nao", 3], ["tenho medo", 3], ["medo", 2], ["assust", 2], ["tremendo", 2.5], ["treme", 2], ["pelo amor", 2.5], ["recua", 2], ["da um passo para tras", 2.5], ["arregala os olhos", 1.5], ["palido", 2], ["gelad", 1.5], ["petrificad", 3], ["me deixa em paz", 2], ["nao faca isso", 3], ["pavor", 3]],
	"nervoso": [["bem... e que", 2], ["eu... eu", 2.5], ["gagu", 2.5], ["suor", 2], ["nervos", 2.5], ["ansios", 2.5], ["calma", 1.2], ["hesit", 2], ["engole seco", 2.5], ["mexe nas maos", 2], ["olha em volta", 1.5], ["torce as maos", 2.5], ["roi as unhas", 2.5], ["inquiet", 2], ["tenso", 2], ["olha para os lados", 2], ["pigarreia", 1.5], ["voz trem", 2.5], ["nao sei...", 1], ["e que...", 1.2]],
	"sarcastico": [["claro, claro", 2.5], ["ah, sim", 1.5], ["que surpresa", 2.5], ["genial", 2], ["imagino", 1.2], ["brilhante", 2], ["aham", 1.5], ["nossa, que", 1.5], ["sei...", 1.5], ["sorriso de canto", 2.5], ["ergue uma sobrancelha", 2.5], ["levanta uma sobrancelha", 2.5], ["que original", 2.5], ["como nao", 1.5], ["parabens, hein", 2], ["que coisa", 1], ["ironic", 3], ["debochad", 3], ["seca", 0.8], ["ah, e", 0.5]],
	"ameacador": [["vou te", 1.5], ["cuidado", 1.5], ["ultima vez", 2.5], ["sabe o que acontece", 3], ["ou entao", 1.5], ["mexer comigo", 3], ["arrisca", 2.5], ["voce vai se arrepender", 3], ["nao me teste", 3], ["se voce", 0.8], ["voz baixa e firme", 2.5], ["dentes cerrados", 2.5], ["olhar frio", 2.5], ["se aproxima devagar", 2.5], ["estala os dedos", 2.5], ["mao no cinto", 2]],
	"carinhoso": [["querido", 2.5], ["querida", 2.5], ["meu bem", 3], ["amor", 1.5], ["docinho", 3], ["com carinho", 2.5], ["abraco", 2], ["gosto de voce", 2.5], ["cuida", 1], ["fofo", 2], ["fofa", 2], ["toca seu ombro", 2.5], ["abraca", 2.5], ["acaricia", 3], ["meu anjo", 3], ["voz suave", 2], ["com ternura", 3], ["lindo", 1], ["linda", 1], ["saudade de voce", 2.5], ["beijo", 2]],
	"surpreso": [["o que?", 2], ["serio?", 2], ["nossa", 1.5], ["uau", 2.5], ["nao acredito", 2.5], ["como assim", 2], ["?!", 2.5], ["arregala", 2], ["espanta", 2.5], ["puxa", 1.5], ["caramba", 2], ["meu deus", 2], ["que isso", 1.5], ["pisca varias vezes", 2.5], ["boquiaberto", 3], ["boquiaberta", 3], ["sem acreditar", 2.5]],
	"envergonhado": [["ah...", 1], ["vergonha", 3], ["cora", 2.5], ["sem graca", 3], ["timid", 2.5], ["desvia o olhar", 2.5], ["bochecha", 2], ["fica vermelh", 3], ["abaixa os olhos", 2], ["encabulad", 3], ["gaguejando", 1.5], ["mexe no cabelo", 1.5], ["ai, para", 2.5], ["para com isso", 1.5]],
	"entediado": [["tanto faz", 2.5], ["que seja", 2.5], ["sei la", 2], ["entedia", 2.5], ["bocej", 2.5], ["sem paciencia pra isso", 2], ["e so isso", 1.5], ["tanto fez", 2], ["olha o relogio", 2], ["suspira", 1], ["que tedio", 3], ["faz careta", 1]],
	"exausto": [["cansad", 2.5], ["exaust", 3], ["dia longo", 2.5], ["sem dormir", 2.5], ["esgotad", 3], ["olheiras", 2.5], ["suspira fundo", 2], ["passa a mao no rosto", 2], ["esfrega os olhos", 2], ["pes doem", 2], ["dia puxado", 2.5], ["virei a noite", 2.5], ["morto de cansaco", 3]],
	"machucado": [["ai!", 2.5], ["doi", 2.5], ["ferid", 2.5], ["sangr", 3], ["gem", 1.5], ["machuc", 3], ["geme", 3], ["segura o ombro", 2], ["segura o braco", 2], ["curvado de dor", 3], ["esta sangrando", 3], ["hematoma", 2], ["manca", 2]],
}

const END_RE := "[.!?…]+"

static var _accents := {"á": "a", "à": "a", "ã": "a", "â": "a", "ä": "a", "é": "e", "è": "e", "ê": "e", "ë": "e", "í": "i", "ì": "i", "î": "i", "ï": "i", "ó": "o", "ò": "o", "õ": "o", "ô": "o", "ö": "o", "ú": "u", "ù": "u", "û": "u", "ü": "u", "ç": "c", "ñ": "n"}
static var _star := RegEx.create_from_string("\\*([^*]+)\\*")


static func norm(s: String) -> String:
	var t := s.to_lower()
	for k in _accents:
		t = t.replace(k, _accents[k])
	return t


# Emoção de um trecho. "base" é a emoção geral da fala (decidida pela IA ou pelo motor local).
static func detect(piece: String, base: String, is_action: bool = false) -> String:
	var t := norm(piece)
	if t.strip_edges() == "":
		return base
	var scores := {}
	for emo in LEX:
		var sc := 0.0
		for e in LEX[emo]:
			if t.contains(str(e[0])):
				sc += float(e[1])
		if sc > 0.0:
			scores[emo] = sc
	# pontuação
	var excl := t.count("!")
	var ques := t.count("?")
	if excl >= 1 and ques >= 1:
		scores["surpreso"] = float(scores.get("surpreso", 0.0)) + 1.5
	if excl >= 2:
		var bump := "furioso" if base in ["irritado", "furioso", "ameacador"] else ("feliz" if base in ["feliz", "rindo", "carinhoso"] else "surpreso")
		scores[bump] = float(scores.get(bump, 0.0)) + 1.2
	if t.contains("..."):
		var soft := "triste" if base in ["triste", "chorando", "exausto"] else ("nervoso" if base in ["nervoso", "assustado", "envergonhado"] else "desconfiado")
		scores[soft] = float(scores.get(soft, 0.0)) + 0.7
	var letters := 0
	var caps := 0
	for ch in piece:
		if ch.to_lower() != ch.to_upper():
			letters += 1
			if ch == ch.to_upper():
				caps += 1
	if letters >= 5 and float(caps) / float(letters) > 0.6:
		scores["furioso"] = float(scores.get("furioso", 0.0)) + 2.5
	var best := base
	var best_s := 0.9 if not is_action else 0.8
	for emo in scores:
		var s: float = float(scores[emo]) + (0.35 if emo == base else 0.0)
		if s > best_s:
			best_s = s
			best = emo
	return best


# Devolve [{"start": índice do caractere no texto visível, "emotion": emoção}] em ordem.
# "plain" é o texto como aparece (sem os asteriscos); "raw" é o texto com *ações*.
static func segments(raw: String, plain: String, base: String) -> Array:
	var out: Array = []
	var cursor := 0
	var plain_pos := 0
	var matches := _star.search_all(raw)
	var pieces: Array = []
	for m in matches:
		if m.get_start() > cursor:
			pieces.append([raw.substr(cursor, m.get_start() - cursor), false])
		pieces.append([m.get_string(1), true])
		cursor = m.get_end()
	if cursor < raw.length():
		pieces.append([raw.substr(cursor), false])
	if pieces.is_empty():
		pieces.append([raw, false])
	var last := base
	for p in pieces:
		var txt: String = p[0]
		var action: bool = p[1]
		var idx := plain.find(txt.strip_edges(), plain_pos)
		if idx < 0:
			idx = plain_pos
		var start := idx
		if action:
			var e := detect(txt, base, true)
			out.append({"start": start, "emotion": e})
			last = e
			plain_pos = idx + txt.strip_edges().length()
			continue
		# fala: uma expressão por frase
		var sentences := _split(txt)
		var off := 0
		for sen in sentences:
			var s := str(sen)
			var rel := txt.find(s, off)
			if rel < 0:
				rel = off
			off = rel + s.length()
			if s.strip_edges() == "":
				continue
			var e2 := detect(s, base)
			# frases sem pista voltam à emoção geral, não ficam presas na anterior
			out.append({"start": idx + rel + (s.length() - s.lstrip(" ").length()), "emotion": e2})
			last = e2
		plain_pos = idx + txt.strip_edges().length()
	if out.is_empty():
		out.append({"start": 0, "emotion": base})
	out.sort_custom(func(a, b): return int(a["start"]) < int(b["start"]))
	return out


static func _split(txt: String) -> Array:
	var out: Array = []
	var cur := ""
	var i := 0
	while i < txt.length():
		var ch := txt[i]
		cur += ch
		if ch in [".", "!", "?", "…"]:
			while i + 1 < txt.length() and txt[i + 1] in [".", "!", "?", "…", "\""]:
				i += 1
				cur += txt[i]
			if cur.strip_edges().length() >= 3:
				out.append(cur)
				cur = ""
		i += 1
	if cur.strip_edges() != "":
		out.append(cur)
	return out
