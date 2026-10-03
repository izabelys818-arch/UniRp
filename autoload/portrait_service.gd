extends Node

signal portrait_ready(npc_id: String, emotion: String)
signal status_changed(text: String)

const PLAYER := "player"
const DRAFT := "player_draft"
const MAX_WIDTH := 640
const STYLE := "Photorealistic close-up portrait photograph, head and shoulders, the subject looks straight into the camera. Dark moody background, dim harsh side lighting, cinematic, natural skin texture with pores and imperfections, subtle film grain, slightly unsettling atmosphere, like a real person photographed at night. No text, no watermark, no frame, no illustration."
const KEEP_IDENTITY := "Edit the reference photo. Keep EXACTLY the same person: same face and identity, same age, hair, clothes, lighting, background, camera angle and framing."
const GENDER_EN := {"homem": "man", "mulher": "woman"}

var dir: String = "user://portraits"
var cache: Dictionary = {}
var queue: Array = []
var pending: Dictionary = {}
var failed: Dictionary = {}
var working: bool = false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(dir)


func file_path(id: String, emotion: String) -> String:
	return "%s/%s/%s.png" % [dir, id, emotion]


func get_texture(id: String, emotion: String) -> Texture2D:
	var key := id + "/" + emotion
	if cache.has(key):
		return cache[key]
	var p := file_path(id, emotion)
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	cache[key] = tex
	return tex


func best_texture(id: String, emotion: String) -> Texture2D:
	var tex := get_texture(id, emotion)
	return tex if tex != null else get_texture(id, "neutro")


func request(id: String, emotion: String) -> void:
	if not World.emotions.has(emotion):
		emotion = "neutro"
	if not Settings.images_ready():
		return
	var key := id + "/" + emotion
	if pending.has(key) or failed.has(key) or get_texture(id, emotion) != null:
		return
	if emotion != "neutro":
		request(id, "neutro")
	pending[key] = true
	queue.append([id, emotion])
	if not working:
		_process_queue()


func _process_queue() -> void:
	working = true
	while not queue.is_empty():
		var job: Array = queue.pop_front()
		await _generate(job[0], job[1])
		pending.erase(job[0] + "/" + job[1])
	working = false
	status_changed.emit("")


func _display_name(id: String) -> String:
	if id == PLAYER or id == DRAFT:
		return "você"
	return NPCManager.npcs[id]["nome"]


func _person_description(id: String) -> String:
	if id == PLAYER:
		return str(GameState.player.get("appearance_en", "an ordinary Brazilian person."))
	var n: Dictionary = NPCManager.npcs[id]
	return "a %d-year-old Brazilian %s. Physical appearance: %s. Occupation: %s." % [
		int(n["idade"]), GENDER_EN.get(n["genero"], "person"), n["aparencia"], n["profissao"]]


func base_prompt(person: String, emotion: String = "neutro") -> String:
	return "%s The subject is %s Facial expression: %s." % [STYLE, person, World.emotions[emotion]["en"]]


func _generate(id: String, emotion: String) -> void:
	var key := id + "/" + emotion
	var emo: Dictionary = World.emotions[emotion]
	status_changed.emit("Gerando rosto de %s (%s)..." % [_display_name(id), emo["pt"]])
	var refs: Array = []
	var prompt := base_prompt(_person_description(id), emotion)
	if emotion != "neutro":
		if get_texture(id, "neutro") == null:
			failed[key] = true
			return
		if Settings.image_model_refs:
			refs.append(FileAccess.get_file_as_bytes(file_path(id, "neutro")))
			prompt = "%s Change ONLY the facial expression and condition to: %s. Keep it photorealistic." % [KEEP_IDENTITY, emo["en"]]
	var res: Dictionary = await AIService.generate_image(prompt, refs)
	if not res["ok"]:
		failed[key] = true
		GameState.add_log("Não foi possível gerar um rosto: " + str(res["error"]), "system")
		return
	store(id, emotion, res["image"])


func generate_base(id: String, person: String) -> Dictionary:
	var res: Dictionary = await AIService.generate_image(base_prompt(person))
	if res["ok"]:
		clear_id(id)
		store(id, "neutro", res["image"])
	return res


func refine(id: String, instruction: String) -> Dictionary:
	if get_texture(id, "neutro") == null:
		return {"ok": false, "error": "Gere ou importe um rosto primeiro."}
	if not Settings.image_model_refs:
		return {"ok": false, "error": "Esse modelo de imagem não aceita foto de referência. Escreva o ajuste em 'Detalhes extras' e gere de novo, ou troque de modelo."}
	var prompt := "%s Apply ONLY this change: %s. Keep it photorealistic." % [KEEP_IDENTITY, instruction]
	var refs := [FileAccess.get_file_as_bytes(file_path(id, "neutro"))]
	var res: Dictionary = await AIService.generate_image(prompt, refs)
	if res["ok"]:
		clear_id(id)
		store(id, "neutro", res["image"])
	return res


func import_photo(id: String, path: String) -> bool:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return false
	var w := img.get_width()
	var h := img.get_height()
	var target_w := mini(w, int(h * 0.75))
	var target_h := mini(h, int(w / 0.75))
	img = img.get_region(Rect2i((w - target_w) / 2, (h - target_h) / 2, target_w, target_h))
	clear_id(id)
	store(id, "neutro", img)
	return true


func promote_draft() -> void:
	clear_id(PLAYER)
	var from := ProjectSettings.globalize_path(dir + "/" + DRAFT)
	if DirAccess.dir_exists_absolute(from):
		DirAccess.rename_absolute(from, ProjectSettings.globalize_path(dir + "/" + PLAYER))
	_forget(DRAFT)


func store(id: String, emotion: String, img: Image) -> void:
	if img.get_width() > MAX_WIDTH:
		img.resize(MAX_WIDTH, int(img.get_height() * float(MAX_WIDTH) / img.get_width()), Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(dir + "/" + id)
	img.save_png(file_path(id, emotion))
	cache[id + "/" + emotion] = ImageTexture.create_from_image(img)
	portrait_ready.emit(id, emotion)


func _forget(id: String) -> void:
	for d in [cache, failed, pending]:
		for key in d.keys():
			if key.begins_with(id + "/"):
				d.erase(key)


func clear_id(id: String) -> void:
	_forget(id)
	var d := dir + "/" + id
	if not DirAccess.dir_exists_absolute(d):
		return
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(d + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(d))


func clear_all() -> void:
	for id in DirAccess.get_directories_at(dir):
		clear_id(id)
	cache.clear()
	failed.clear()
