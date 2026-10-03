extends Node

signal time_advanced(minutes: int, sleeping: bool)

const WEEKDAYS := ["Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"]

var total_minutes: int = 8 * 60


func day() -> int:
	return total_minutes / 1440 + 1


func hour() -> int:
	return (total_minutes % 1440) / 60


func minute() -> int:
	return total_minutes % 60


func weekday() -> String:
	return WEEKDAYS[(day() - 1) % 7]


func clock_str() -> String:
	return "Dia %d (%s) %02d:%02d" % [day(), weekday(), hour(), minute()]


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
