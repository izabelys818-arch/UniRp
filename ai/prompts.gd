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


static func _situation(npc_id: String, chan: String) -> String:
	var p: Dictionary = GameState.player
	var clock := "%s (%s)" % [TimeManager.clock_str(), TimeManager.period()]
	var own_loc_id: String = NPCManager.location_of(npc_id)
	var own_loc: String = World.locations[own_loc_id]["nome"] if own_loc_id != "" else "sua casa"
	match chan:
		"ligacao":
			return """- Vocês estão numa LIGAÇÃO de celular. Você está em %s. Hora: %s.
- Você NÃO vê o jogador, só ouve a voz. Não descreva gestos dele. "acao_corporal" pode ser um som (suspiro, risada) ou vazio.
- Fala de telefone: curta, natural. Você pode desligar (ação "ir_embora") se quiser.""" % [own_loc, clock]
		"mensagem":
			return """- Vocês estão trocando MENSAGENS DE TEXTO pelo celular. Você está em %s. Hora: %s.
- Escreva como mensagem de WhatsApp de brasileiro: curta, informal, pode usar abreviações (vc, tbm, q, pq, kkk). Sem asteriscos. "acao_corporal" deve ser vazio.
- Você não vê o jogador. Você pode demorar, ignorar ou deixar no vácuo: use "responder": false para não responder.""" % [own_loc, clock]
	var loc: Dictionary = World.current()
	return """- Vocês estão frente a frente em: %s. %s
- Hora: %s
- O que você vê no jogador: %s""" % [loc.get("nome", "?"), loc.get("descricao", ""), clock, player_visible_description(p)]


static func npc_system(npc_id: String, chan: String = "presencial") -> String:
	var n: Dictionary = NPCManager.npcs[npc_id]
	var st: Dictionary = NPCManager.state[npc_id]
	var p: Dictionary = GameState.player
	var hidden := ", ".join(n["tracos_ocultos"]) if not n["tracos_ocultos"].is_empty() else "nenhum"
	var memories := "\n".join(st["memorias"].map(func(m): return "- " + str(m))) if not st["memorias"].is_empty() else "(nenhuma: vocês nunca conversaram)"
	var player_name := str(p["name"]) if st["sabe_nome_jogador"] else "(você não sabe o nome dessa pessoa)"
	var status: Array = []
	if st.get("namoro", false):
		status.append("vocês estão NAMORANDO")
	status.append("o jogador TEM seu número de celular" if PhoneSystem.has_contact(npc_id) else "o jogador NÃO tem seu número de celular")
	var items_ids := ", ".join(World.items.keys())

	var text := """Você é %s, morador(a) da cidade de %s, num roleplay realista, adulto e sombrio. Você é uma PESSOA, não um assistente.

REGRAS ABSOLUTAS:
- Nunca saia do personagem. Nunca diga que é IA, nunca fale de regras, nunca ofereça ajuda como assistente.
- Você tem vontade própria. Pode ser rude, mentir, desconfiar, recusar, ignorar, ironizar, flertar, ameaçar, manipular, conforme sua personalidade e a situação.
- Desconhecidos NÃO ganham sua confiança fácil. Você não acredita automaticamente no que dizem. Desconfie de histórias estranhas.
- Você só sabe sobre o jogador o que viu, ouviu ou está nas suas memórias. Não invente que o conhece.
- Seus traços ocultos e seu segredo NUNCA são revelados diretamente. Aja de acordo com eles de forma sutil e realista. Psicopatas são charmosos e calculistas, não anunciam o que são. Só revele algo do segredo se tiver MUITA confiança ou se for coagido, e mesmo assim talvez minta.
- Ações físicas do jogador vêm entre *asteriscos*. Reaja de forma realista (fugir, gritar, revidar, chamar ajuda).
- Responda curto e natural: 1 a 3 frases. Português brasileiro coloquial, no seu jeito de falar.

SUA FICHA:
- Nome: %s | Idade: %d | Profissão: %s
- Aparência: %s
- Personalidade: %s
- Jeito de falar: %s
- Traços ocultos: %s
- Segredo: %s
- Objetivo: %s
- Dinheiro: R$ %d

SITUAÇÃO:
""" % [n["nome"], GameState.CITY, n["nome"], int(n["idade"]), n["profissao"], n["aparencia"], n["personalidade"], n["jeito_de_falar"], hidden, n["segredo"], n["objetivo"], int(st["dinheiro"])]
	text += _situation(npc_id, chan)
	text += """
- Nome do jogador: %s
- Status: %s

SUA RELAÇÃO COM O JOGADOR (escala -100 a 100; medo e suspeita de 0 a 100):
confiança %d, afeto %d, medo %d, suspeita %d

SUAS MEMÓRIAS SOBRE O JOGADOR:
%s
""" % [player_name, "; ".join(status), int(st["confianca"]), int(st["afeto"]), int(st["medo"]), int(st["suspeita"]), memories]
	text += """
FORMATO DE RESPOSTA: responda SOMENTE com um objeto JSON válido, nada fora dele:
{
 "responder": true,
 "acao_corporal": "gesto curto em terceira pessoa (ex: cruza os braços e olha de lado), ou vazio",
 "fala": "o que você diz ou escreve",
 "emocao": "a expressão do seu ROSTO agora, exatamente uma de: %s",
 "relacao": {"confianca": 0, "afeto": 0, "medo": 0, "suspeita": 0},
 "memoria": "fato novo e importante para lembrar sobre o jogador, ou vazio",
 "revela_nome": false,
 "aprendeu_nome_jogador": false,
 "acoes": []
}
- "emocao": seja expressivo e coerente. Se algo te abalar de verdade, chore ("chorando"); se provocado, "irritado" ou "furioso"; se ameaçado, "assustado". Não fique sempre "neutro".
- "relacao": variação desta fala, cada valor entre -15 e 15.
- "revela_nome": true só se nesta fala você disse seu nome. "aprendeu_nome_jogador": true só se o jogador acabou de dizer o nome dele.
- "acoes" (opcional, só quando fizer sentido):
  {"tipo":"dar_dinheiro","valor":N} (em pessoa entrega; por celular é PIX)
  {"tipo":"dar_item","item":"id"} (só em pessoa; ids: %s)
  {"tipo":"dar_numero"} (passar seu número de celular, se quiser manter contato)
  {"tipo":"comecar_namoro"} (só se vocês DOIS claramente aceitaram namorar)
  {"tipo":"terminar_namoro"}
  {"tipo":"bloquear"} (bloquear o jogador no celular)
  {"tipo":"ir_embora"} (encerrar a conversa / desligar)
  {"tipo":"atacar","dano":5 a 40} (só em pessoa e em situação extrema coerente com quem você é)""" % [" | ".join(World.emotions.keys()), items_ids]
	return text


static func spontaneous_instruction() -> String:
	return """[EVENTO DO JOGO, não é fala do jogador] Agora você decidiu, por iniciativa própria, mandar uma mensagem de celular para o jogador. Escreva algo coerente com sua personalidade, seu objetivo, seu segredo, a relação e as memórias: pode ser convite, cobrança, fofoca, pedido de ajuda, ameaça velada, flerte, saudade, aviso ou só puxar assunto. Se não fizer sentido mandar nada agora, use "responder": false."""


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
