extends Node

const CHAT_URL := "https://openrouter.ai/api/v1/chat/completions"
const MODELS_URL := "https://openrouter.ai/api/v1/models"


func chat(messages: Array, max_tokens: int = 400) -> Dictionary:
	if not Settings.is_ready():
		return {"ok": false, "error": "IA não configurada: coloque sua chave e escolha um modelo em Configurações."}
	var body := {
		"model": Settings.model,
		"messages": messages,
		"temperature": Settings.temperature,
		"max_tokens": max_tokens,
	}
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + Settings.api_key,
		"X-Title: UniRp",
	])
	var r := await _request(CHAT_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if not r["ok"]:
		return r
	var data = r["data"]
	if typeof(data) != TYPE_DICTIONARY or not data.has("choices") or data["choices"].is_empty():
		return {"ok": false, "error": "Resposta inesperada da IA."}
	var content = data["choices"][0]["message"].get("content", "")
	return {"ok": true, "text": "" if content == null else str(content)}


func fetch_models() -> Dictionary:
	var r := await _request(MODELS_URL, PackedStringArray(), HTTPClient.METHOD_GET, "")
	if not r["ok"]:
		return r
	var out: Array = []
	for m in r["data"].get("data", []):
		var pricing: Dictionary = m.get("pricing", {})
		var free := str(pricing.get("prompt", "1")) == "0" and str(pricing.get("completion", "1")) == "0"
		out.append({"id": m["id"], "name": m.get("name", m["id"]), "free": free})
	out.sort_custom(func(a, b): return a["id"] < b["id"])
	return {"ok": true, "models": out}


func _request(url: String, headers: PackedStringArray, method: int, body: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 90.0
	add_child(http)
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "Não foi possível iniciar a requisição (erro %d)." % err}
	var res: Array = await http.request_completed
	http.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "Falha de conexão com o OpenRouter (código %d). Verifique sua internet." % result}
	var data = JSON.parse_string(text)
	if code != 200:
		var msg := text.left(300)
		if typeof(data) == TYPE_DICTIONARY and data.has("error"):
			msg = str(data["error"].get("message", msg))
		return {"ok": false, "error": "Erro da IA (%d): %s" % [code, msg]}
	return {"ok": true, "data": data}
