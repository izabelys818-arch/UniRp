extends Node

signal time_advanced(minutes: int, sleeping: bool)
signal calendar_changed

const WEEKDAYS := ["Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"]
const WEEKDAYS_LONG := ["segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo"]
const MONTHS := ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]
const MONTHS_SHORT := ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]
# Ritmos do calendário: dias de jogo em cada mês (o ano tem 12 meses).
const PACES := [3, 7, 28]
const START_YEAR := 2026
const START_MONTH := 2  # o jogo começa em 1º de março

var total_minutes: int = 8 * 60

# Calendário do mundo, ligado ao mesmo relógio (total_minutes). Um mês tem `days_per_month` dias
# de jogo; a âncora guarda qual dia do calendário corresponde a um dia do relógio, para que
# trocar o ritmo no meio do jogo não pule a data.
var days_per_month: int = 7
var aging: bool = true
var cal_anchor_day: int = 0
var cal_anchor_index: int = -1


func _ready() -> void:
	# o ritmo escolhido em Configurações (Settings carrega antes deste autoload)
	days_per_month = Settings.days_per_month
	aging = Settings.aging


func day() -> int:
	return total_minutes / 1440 + 1


func hour() -> int:
	return (total_minutes % 1440) / 60


func minute() -> int:
	return total_minutes % 60


func weekday() -> String:
	return WEEKDAYS[(day() - 1) % 7]


func weekday_of(game_day: int) -> int:
	return (game_day - 1) % 7


func clock_str() -> String:
	var d := date()
	return "Dia %d (%s, %d de %s de %d) %02d:%02d" % [day(), weekday(), d["d"], MONTHS[d["m"]], d["y"], hour(), minute()]


func period() -> String:
	var h := hour()
	if h < 5:
		return "madrugada"
	if h < 12:
		return "manhã"
	if h < 18:
		return "tarde"
	return "noite"


func is_night() -> bool:
	var h := hour()
	return h >= 20 or h < 5


func advance(minutes: int, sleeping: bool = false) -> void:
	if minutes <= 0:
		return
	total_minutes += minutes
	time_advanced.emit(minutes, sleeping)


# ---------- calendário ----------

func year_len() -> int:
	return 12 * days_per_month


func _start_index() -> int:
	return START_YEAR * 12 * days_per_month + START_MONTH * days_per_month


# Índice do dia no calendário (dias desde o ano 0) para um dia do relógio.
func cal_index_of(game_day: int) -> int:
	if cal_anchor_index < 0:
		cal_anchor_index = _start_index()
		cal_anchor_day = 1
	return cal_anchor_index + (game_day - cal_anchor_day)


func date_of_index(idx: int) -> Dictionary:
	var yl := year_len()
	var r := posmod(idx, yl)
	return {"y": floori(float(idx) / yl), "m": r / days_per_month, "d": r % days_per_month + 1}


func date_of(game_day: int) -> Dictionary:
	return date_of_index(cal_index_of(game_day))


func date() -> Dictionary:
	return date_of(day())


func index_of_date(y: int, m: int, d: int) -> int:
	return y * year_len() + m * days_per_month + clampi(d, 1, days_per_month) - 1


# Dia do relógio em que cai uma data do calendário (pode ser no passado ou no futuro).
func game_day_of(y: int, m: int, d: int) -> int:
	return cal_anchor_day + (index_of_date(y, m, d) - cal_index_of(cal_anchor_day))


func date_str(d: Dictionary = {}, with_year: bool = true) -> String:
	if d.is_empty():
		d = date()
	if with_year:
		return "%d de %s de %d" % [d["d"], MONTHS[d["m"]], d["y"]]
	return "%d de %s" % [d["d"], MONTHS[d["m"]]]


func short_date_str() -> String:
	var d := date()
	return "%s, %d de %s" % [weekday(), d["d"], MONTHS_SHORT[d["m"]]]


# Troca o ritmo sem mudar a data de hoje (os aniversários continuam no mesmo mês).
func set_days_per_month(n: int) -> void:
	n = clampi(n, 1, 31)
	if n == days_per_month:
		return
	var today := date()
	days_per_month = n
	cal_anchor_day = day()
	cal_anchor_index = index_of_date(int(today["y"]), int(today["m"]), int(today["d"]))
	calendar_changed.emit()


func new_calendar() -> void:
	cal_anchor_day = 1
	cal_anchor_index = _start_index()
	calendar_changed.emit()


func cal_to_dict() -> Dictionary:
	return {"dias_por_mes": days_per_month, "envelhecer": aging, "ancora_dia": cal_anchor_day, "ancora_indice": cal_index_of(cal_anchor_day)}


# Saves antigos (sem calendário) começam em 1º de março de 2026 no dia 1 do relógio.
func cal_from_dict(d: Dictionary) -> void:
	days_per_month = clampi(int(d.get("dias_por_mes", days_per_month)), 1, 31)
	aging = bool(d.get("envelhecer", aging))
	if d.has("ancora_indice"):
		cal_anchor_day = int(d.get("ancora_dia", 1))
		cal_anchor_index = int(d["ancora_indice"])
	else:
		cal_anchor_day = 1
		cal_anchor_index = _start_index()
	calendar_changed.emit()


# Data a partir de dados crus de um save (para a tela inicial, sem carregar o jogo).
static func date_from_save(minutes: int, cal: Dictionary) -> Dictionary:
	var dpm := clampi(int(cal.get("dias_por_mes", 7)), 1, 31)
	var game_day := minutes / 1440 + 1
	var anchor_day := int(cal.get("ancora_dia", 1))
	var anchor_idx := int(cal.get("ancora_indice", START_YEAR * 12 * dpm + START_MONTH * dpm))
	var idx := anchor_idx + game_day - anchor_day
	var yl := 12 * dpm
	var r := posmod(idx, yl)
	return {"y": floori(float(idx) / yl), "m": r / dpm, "d": r % dpm + 1}
