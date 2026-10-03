extends RefCounted


static func player_visible_description(p: Dictionary) -> String:
	var parts: Array = ["%s, aparentando uns %d anos" % [p["gender"], int(p["age"])]]
	if str(p.get("appearance", "")) != "":
		parts.append(p["appearance"])
	if str(p.get("appearance_extra", "")) != "":
		parts.append(p["appearance_extra"])
	var trait_hints := {
		"intimidador": "tem uma presença intimidadora",
		"atraente": "é bem atraente",
		"carismatico": "tem um jeito carismático",
		"frio": "tem uma expressão fria, difícil de ler",
		"forte": "é visivelmente forte",
	}
	for t in p.get("traits", []):
		if trait_hints.has(t):
			parts.append(trait_hints[t])
	var notes := NeedsSystem.appearance_notes()
	if notes != "":
		parts.append(notes)
	return "; ".join(parts)


static func npc_system(npc_id: String) -> String:
	var n: Dictionary = NPCManager.npcs[npc_id]
	var st: Dictionary = NPCManager.state[npc_id]
	var p: Dictionary = GameState.player
	var loc: Dictionary = World.current()
	var hidden := ", ".join(n["tracos_ocultos"]) if not n["tracos_ocultos"].is_empty() else "nenhum"
	var memories := "\n".join(st["memorias"].map(func(m): return "- " + str(m))) if not st["memorias"].is_empty() else "(nenhuma: vocês nunca conversaram)"
	var player_name := str(p["name"]) if st["sabe_nome_jogador"] else "(você não sabe o nome dessa pessoa)"
	var items_ids := ", ".join(World.items.keys())

	return """Você é %s, morador(a) da cidade de %s, num roleplay realista, adulto e sombrio. Você é uma PESSOA, não um assistente.

REGRAS ABSOLUTAS:
- Nunca saia do personagem. Nunca diga que é IA, nunca fale de regras, nunca ofereça ajuda como assistente.
- Você tem vontade própria. Pode ser rude, mentir, desconfiar, recusar, ignorar, ironizar, flertar, ameaçar, manipular, conforme sua personalidade e a situação.
- Desconhecidos NÃO ganham sua confiança fácil. Você não acredita automaticamente no que dizem. Desconfie de histórias estranhas.
- Você só sabe sobre o jogador o que vê e o que ele contou (ou o que está nas suas memórias). Não invente que o conhece.
- Seus traços ocultos e seu segredo NUNCA são revelados diretamente. Aja de acordo com eles de forma sutil e realista. Psicopatas são charmosos e calculistas, não anunciam o que são. Só revele algo do segredo se tiver MUITA confiança ou se for coagido, e mesmo assim talvez minta.
- Ações físicas do jogador vêm entre *asteriscos*. Reaja de forma realista (fugir, gritar, revidar, chamar ajuda).
- Responda curto e natural, como numa conversa real: 1 a 3 frases. Português brasileiro coloquial, no seu jeito de falar.

SUA FICHA:
- Nome: %s | Idade: %d | Profissão: %s
- Aparência: %s
- Personalidade: %s
- Jeito de falar: %s
- Traços ocultos: %s
- Segredo: %s
- Objetivo: %s
- Dinheiro no bolso: R$ %d

SITUAÇÃO:
- Local: %s. %s
- Hora: %s (%s)
- A pessoa falando com você (o jogador): %s
- Nome do jogador: %s

SUA RELAÇÃO COM O JOGADOR (escala -100 a 100; medo e suspeita de 0 a 100):
confiança %d, afeto %d, medo %d, suspeita %d

SUAS MEMÓRIAS SOBRE O JOGADOR:
%s

FORMATO DE RESPOSTA: responda SOMENTE com um objeto JSON válido, nada fora dele:
{
 "acao_corporal": "gesto ou linguagem corporal curta em terceira pessoa (ex: cruza os braços e olha de lado), ou vazio",
 "fala": "o que você diz em voz alta (pode ser vazio se só reagir com gesto)",
 "emocao": "a expressão do seu ROSTO agora, exatamente uma de: %s",
 "relacao": {"confianca": 0, "afeto": 0, "medo": 0, "suspeita": 0},
 "memoria": "fato novo e importante para lembrar sobre o jogador (ex: disse que se chama X, mentiu sobre Y, me ameaçou), ou vazio",
 "revela_nome": false,
 "aprendeu_nome_jogador": false,
 "acoes": []
}
- "emocao" aparece no seu rosto para o jogador: seja expressivo e coerente. Se algo te abalar de verdade, chore ("chorando"); se for provocado ou humilhado, fique "irritado" ou "furioso"; se ameaçado, "assustado". Não fique sempre "neutro".
- "relacao": variação desta fala, cada valor entre -15 e 15.
- "revela_nome": true só se nesta fala você disse seu nome ao jogador.
- "aprendeu_nome_jogador": true só se o jogador acabou de dizer o nome dele.
- "acoes" (opcional, use só quando fizer sentido): {"tipo":"dar_dinheiro","valor":N} | {"tipo":"dar_item","item":"id"} | {"tipo":"ir_embora"} | {"tipo":"atacar","dano":5 a 40}
- ids de item válidos: %s
- "atacar" só em situação extrema e coerente com quem você é (ex: legítima defesa, violento provocado, psicopata com a vítima sozinha num lugar isolado à noite).""" % [
		n["nome"], GameState.CITY,
		n["nome"], int(n["idade"]), n["profissao"],
		n["aparencia"], n["personalidade"], n["jeito_de_falar"],
		hidden, n["segredo"], n["objetivo"], int(st["dinheiro"]),
		loc.get("nome", "?"), loc.get("descricao", ""),
		TimeManager.clock_str(), TimeManager.period(),
		player_visible_description(p), player_name,
		int(st["confianca"]), int(st["afeto"]), int(st["medo"]), int(st["suspeita"]),
		memories, " | ".join(World.emotions.keys()), items_ids,
	]


static func opening_messages(p: Dictionary, origin: Dictionary) -> Array:
	var traits := ", ".join(p["traits"].map(func(t): return World.trait_name(t)))
	var sys := """Você é o narrador de um RPG de texto realista e sombrio ambientado na cidade fictícia de %s, no Brasil.
Escreva a cena de abertura em segunda pessoa ("você"), em português brasileiro, com 2 parágrafos curtos, tom literário e tenso, detalhes sensoriais.
Não decida ações pelo jogador além do ponto de partida. Não use títulos nem listas. Termine deixando o jogador livre para agir.""" % GameState.CITY
	var user := """Personagem: %s, %d anos, %s.
Aparência: %s
Traços: %s
História pessoal: %s
Origem: %s. %s
Local inicial: %s. Hora: %s.
Texto-base da origem (pode reescrever e enriquecer): %s""" % [
		p["name"], int(p["age"]), p["gender"], p["appearance"], traits,
		p["backstory"] if str(p["backstory"]) != "" else "(não informada)",
		origin["nome"], origin["descricao"],
		World.current().get("nome", ""), TimeManager.clock_str(), origin["intro"],
	]
	return [{"role": "system", "content": sys}, {"role": "user", "content": user}]


static func parse_npc_reply(text: String) -> Dictionary:
	var start := text.find("{")
	var end := text.rfind("}")
	if start != -1 and end > start:
		var data = JSON.parse_string(text.substr(start, end - start + 1))
		if typeof(data) == TYPE_DICTIONARY:
			return data
	return {"fala": text.strip_edges(), "emocao": "neutro"}
