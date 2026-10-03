extends Node

const CHAT_URL := "https://openrouter.ai/api/v1/chat/completions"
const MODELS_URL := "https://openrouter.ai/api/v1/models"
const IMAGES_URL := "https://openrouter.ai/api/v1/images"
const IMAGE_MODELS_URL := "https://openrouter.ai/api/v1/images/models"


func _auth_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + Settings.api_key,
		"X-Title: UniRp",
	])


func chat(messages: Array, max_tokens: int = 400) -> Dictionary:
	if not Settings.is_ready():
		return {"ok": false, "error": "IA não configurada: coloque sua chave e escolha um modelo em Configurações."}
	var body := {
		"model": Settings.model,
		"messages": messages,
		"temperature": Settings.temperature,
		"max_tokens": max_tokens,
	}
	var r := await _request(CHAT_URL, _auth_headers(), HTTPClient.METHOD_POST, JSON.stringify(body))
	if not r["ok"]:
		return r
	var data = r["data"]
	if typeof(data) != TYPE_DICTIONARY or not data.has("choices") or data["choices"].is_empty():
		return {"ok": false, "error": "Resposta inesperada da IA."}
	var content = data["choices"][0]["message"].get("content", "")
	return {"ok": true, "text": "" if content == null else str(content)}


func generate_image(prompt: String, refs: Array = []) -> Dictionary:
	if not Settings.images_ready():
		return {"ok": false, "error": "Modelo de imagem não configurado."}
	var body := {"model": Settings.image_model, "prompt": prompt, "aspect_ratio": "3:4", "n": 1}
	if not refs.is_empty():
		var refs_json: Array = []
		for png in refs:
			refs_json.append({"type": "image_url", "image_url": {"url": "data:image/png;base64," + Marshalls.raw_to_base64(png)}})
		body["input_references"] = refs_json
	var r := await _request(IMAGES_URL, _auth_headers(), HTTPClient.METHOD_POST, JSON.stringify(body), 240.0)
	if not r["ok"]:
		return r
	var data = r["data"]
	if typeof(data) != TYPE_DICTIONARY or data.get("data", []).is_empty():
		return {"ok": false, "error": "O modelo de imagem não devolveu nenhuma imagem."}
	var item: Dictionary = data["data"][0]
	if not item.has("b64_json"):
		return {"ok": false, "error": "Formato de imagem não suportado."}
	var img := decode_image(Marshalls.base64_to_raw(item["b64_json"]))
	if img == null:
		return {"ok": false, "error": "Não foi possível ler a imagem gerada."}
	return {"ok": true, "image": img}


static func decode_image(raw: PackedByteArray) -> Image:
	var img := Image.new()
	if img.load_png_from_buffer(raw) == OK:
		return img
	if img.load_jpg_from_buffer(raw) == OK:
		return img
	if img.load_webp_from_buffer(raw) == OK:
		return img
	return null


func fetch_models() -> Dictionary:
	var r := await _request(MODELS_URL, PackedStringArray(), HTTPClient.METHOD_GET, "")
	if not r["ok"]:
		return r
	var out: Array = []
	for m in r["data"].get("data", []):
		var pricing: Dictionary = m.get("pricing", {})
		var free := str(pricing.get("prompt", "1")) == "0" and str(pricing.get("completion", "1")) == "0"
		out.append({"id": m["id"], "name": m.get("name", m["id"]), "free": free, "refs": false})
	out.sort_custom(func(a, b): return a["id"] < b["id"])
	return {"ok": true, "models": out}


func fetch_image_models() -> Dictionary:
	var r := await _request(IMAGE_MODELS_URL, _auth_headers(), HTTPClient.METHOD_GET, "")
	if not r["ok"]:
		return r
	var out: Array = []
	for m in r["data"].get("data", []):
		var inputs: Array = m.get("architecture", {}).get("input_modalities", [])
		out.append({"id": m["id"], "name": m.get("name", m["id"]), "free": false, "refs": "image" in inputs})
	out.sort_custom(func(a, b): return a["id"] < b["id"])
	return {"ok": true, "models": out}


func _request(url: String, headers: PackedStringArray, method: int, body: String, timeout: float = 90.0) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	http.body_size_limit = 30 * 1024 * 1024
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
