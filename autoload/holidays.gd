extends Node

# Feriados e datas comemorativas do calendário brasileiro, encaixados no calendário do jogo
# (meses curtos: a data real é proporcional, e datas que caem no mesmo dia são empurradas).
# Feriado: comércio fechado ou em horário reduzido, como na vida real; véspera: fecha mais cedo;
# data comemorativa (Mães, Namorados...): comércio aberto, cidade movimentada.
# Nada é salvo: tudo sai do calendário do TimeManager.

signal holiday_started(h: Dictionary)

# tipo: feriado (fecha), vespera (fecha cedo), festa (festa na praça, comércio fecha cedo), data (só comemorativa)
const LIST := [
	{"id": "ano_novo", "nome": "Ano-Novo", "m": 0, "d": 1, "tipo": "feriado", "forte": true,
		"texto": "Primeiro dia do ano. Ressaca na cidade inteira: quase tudo fechado."},
	{"id": "carnaval", "nome": "Carnaval", "m": 1, "d": 16, "tipo": "festa",
		"texto": "Bloco na praça, confete na calçada. Comércio fecha cedo e a cidade vira festa."},
	{"id": "sexta_santa", "nome": "Sexta-feira Santa", "m": 3, "d": 3, "tipo": "feriado",
		"texto": "Feriado religioso. Igreja cheia, comércio de portas fechadas."},
	{"id": "tiradentes", "nome": "Tiradentes", "m": 3, "d": 21, "tipo": "feriado",
		"texto": "Feriado nacional. Mercado em horário reduzido, o resto fechado."},
	{"id": "trabalho", "nome": "Dia do Trabalho", "m": 4, "d": 1, "tipo": "feriado",
		"texto": "Feriado nacional. Quem trabalha descansa; quem não trabalha procura emprego."},
	{"id": "maes", "nome": "Dia das Mães", "m": 4, "d": 11, "tipo": "data",
		"texto": "Almoço de família e floricultura sem flor sobrando."},
	{"id": "namorados", "nome": "Dia dos Namorados", "m": 5, "d": 12, "tipo": "data", "casais": true,
		"texto": "Bar cheio de casais. Quem namora e esquece a data vai ouvir."},
	{"id": "sao_joao", "nome": "Festa de São João", "m": 5, "d": 24, "tipo": "festa",
		"texto": "Fogueira, quentão e quadrilha na praça. Comércio fecha mais cedo."},
	{"id": "pais", "nome": "Dia dos Pais", "m": 7, "d": 9, "tipo": "data",
		"texto": "Churrasco de domingo e gravata de presente."},
	{"id": "independencia", "nome": "Independência do Brasil", "m": 8, "d": 7, "tipo": "feriado",
		"texto": "Feriado nacional. Desfile de manhã e comércio fechado."},
	{"id": "aparecida", "nome": "Nossa Senhora Aparecida / Dia das Crianças", "m": 9, "d": 12, "tipo": "feriado",
		"texto": "Feriado nacional e Dia das Crianças. Praça cheia de família."},
	{"id": "finados", "nome": "Finados", "m": 10, "d": 2, "tipo": "feriado",
		"texto": "Dia de lembrar os mortos. Igreja e cemitério cheios, comércio fechado."},
	{"id": "republica", "nome": "Proclamação da República", "m": 10, "d": 15, "tipo": "feriado",
		"texto": "Feriado nacional. Mercado em horário reduzido."},
	{"id": "consciencia", "nome": "Dia da Consciência Negra", "m": 10, "d": 20, "tipo": "feriado",
		"texto": "Feriado nacional. Roda de samba e homenagens na praça."},
	{"id": "vespera_natal", "nome": "Véspera de Natal", "m": 11, "d": 24, "tipo": "vespera",
		"texto": "Correria de última hora. O comércio fecha mais cedo para a ceia."},
	{"id": "natal", "nome": "Natal", "m": 11, "d": 25, "tipo": "feriado", "forte": true,
		"texto": "Natal. Família reunida e quase tudo fechado."},
	{"id": "reveillon", "nome": "Véspera de Ano-Novo", "m": 11, "d": 31, "tipo": "vespera",
		"texto": "Réveillon. Fogos à meia-noite na praça; o comércio fecha cedo."},
]

var _cache_dpm: int = -1
var _days: Dictionary = {}  # "m:d" (dia no ritmo atual) → feriado
var _last_day: int = -1


func _ready() -> void:
	TimeManager.time_advanced.connect(_on_time_advanced)


# Dia de cada data no ritmo atual: proporcional ao mês real, sem dois feriados no mesmo dia.
func _build() -> void:
	var dpm := TimeManager.days_per_month
	if dpm == _cache_dpm:
		return
	_cache_dpm = dpm
	_days.clear()
	var by_month := {}
	for h in LIST:
		var m: int = h["m"]
		if not by_month.has(m):
			by_month[m] = []
		by_month[m].append(h)
	for m in by_month:
		var hs: Array = by_month[m]
		hs.sort_custom(func(a, b): return int(a["d"]) < int(b["d"]))
		var want: Array = []
		for h in hs:
			want.append(clampi(int(floor(float(int(h["d"]) - 1) * dpm / 31.0)) + 1, 1, dpm))
		# empurra para frente o que colidir e, se passar do fim do mês, puxa tudo para trás
		for i in range(1, want.size()):
			want[i] = maxi(int(want[i]), int(want[i - 1]) + 1)
		for i in range(want.size() - 1, -1, -1):
			var limit := dpm - (want.size() - 1 - i)
			want[i] = mini(int(want[i]), limit)
		for i in hs.size():
			if int(want[i]) >= 1:
				_days["%d:%d" % [m, int(want[i])]] = hs[i]


func on_date(m: int, d: int) -> Dictionary:
	_build()
	return _days.get("%d:%d" % [m, d], {})


func of_day(game_day: int) -> Dictionary:
	var dt := TimeManager.date_of(game_day)
	return on_date(int(dt["m"]), int(dt["d"]))


func today() -> Dictionary:
	if not GameState.active:
		return {}
	return of_day(TimeManager.day())


func label_today() -> String:
	var h := today()
	return str(h.get("nome", ""))


# Data (mês, dia) de um feriado no ritmo atual.
func date_of(id: String) -> Vector2i:
	_build()
	for k in _days:
		if str(_days[k]["id"]) == id:
			var p := str(k).split(":")
			return Vector2i(int(p[0]), int(p[1]))
	return Vector2i(-1, -1)


# Horário de um local hoje: [abre, fecha] ajustado ao feriado, ou [] se fechado o dia todo.
# Hospital, delegacia, praças, casas e pensão não mudam; bar abre normalmente (fecha no Natal).
func hours_for(loc_id: String, open: int, close: int, game_day: int = -1) -> Array:
	var h := of_day(TimeManager.day() if game_day < 0 else game_day)
	if h.is_empty():
		return [open, close]
	var loc: Dictionary = World.locations.get(loc_id, {})
	var tipo := str(loc.get("tipo", ""))
	if loc_id == "minha_lanchonete" or tipo in ["servico", "publico", "casa", "hospedagem"] or loc.get("casa_generica", false):
		return [open, close]
	var kind := str(h["tipo"])
	var strong: bool = h.get("forte", false)
	match kind:
		"feriado":
			if tipo == "bar":
				return [] if strong else [open, close]
			if strong:
				return []
			if tipo == "loja":
				return [8, 14]
			if tipo == "comida":
				return [maxi(open, 8), mini(close if close > open else 24, 16)]
			return []
		"vespera", "festa":
			if tipo == "bar":
				return [open, close]
			var early := 14 if kind == "festa" else 16
			if close > open:
				return [open, mini(close, early)]
			return [open, early]
	return [open, close]


func closed_reason(loc_id: String) -> String:
	var h := today()
	if h.is_empty():
		return ""
	return "Fechado: %s" % str(h["nome"])


func _on_time_advanced(_m: int, _s: bool) -> void:
	if not GameState.active:
		return
	var d := TimeManager.day()
	if _last_day < 0 or d < _last_day:
		_last_day = d
		return
	if d == _last_day:
		return
	_last_day = d
	var h := of_day(d)
	if h.is_empty():
		return
	holiday_started.emit(h)
	NewsSystem.post(str(h["nome"]), str(h["texto"]), "cidade")
	GameState.add_log("Hoje é %s. %s" % [str(h["nome"]), str(h["texto"])], "event")
	# Carnaval, São João e réveillon: a cidade comemora na praça
	if (str(h["tipo"]) == "festa" or str(h["id"]) in ["reveillon", "consciencia"]) and not WorldEvents.active("festa"):
		WorldEvents.start("festa", 14.0)
