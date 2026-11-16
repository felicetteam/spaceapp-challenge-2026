extends RefCounted
## Diario global: las investigaciones completadas en partidas GANADAS, guardadas entre
## partidas (en user://diario_global.json). Lo muestra "Ver Diario" del menú de inicio con la
## misma ventana que Información; además, el diario de cada partida elige primero misiones
## que todavía no están acá.
##
## Tiene los mismos métodos que el diario de la partida (misiones, activa, esta_completa,
## fraccion...) para que la ventana de Información lo pueda mostrar igual.

const RUTA_GUARDADO := "user://diario_global.json"
const RUTA_DATOS := "res://Base/investigaciones.json"
const Idioma := preload("res://Base/idioma.gd")

## Todas las investigaciones del juego; "desbloqueada" = completada en alguna partida ganada.
var misiones: Array[Dictionary] = []
## true: la ventana de Información sabe que está mostrando el diario global.
var es_global := true
var partidas_ganadas := 0


func _init() -> void:
	var guardado := cargar()
	partidas_ganadas = int(guardado.get("ganadas", 0))
	var ids_hechos: Array = guardado.get("completadas", [])
	if not FileAccess.file_exists(RUTA_DATOS):
		return
	var datos = JSON.parse_string(FileAccess.get_file_as_string(RUTA_DATOS))
	Idioma.traducir_datos(datos, ["titulo", "texto", "pregunta", "opciones"])  # en el idioma elegido
	if not (datos is Dictionary) or not (datos.get("investigaciones") is Array):
		return
	for inv in datos["investigaciones"]:
		if not (inv is Dictionary):
			continue
		var m: Dictionary = inv.duplicate(true)
		var hecha := ids_hechos.has(String(m.get("id", "")))
		m["desbloqueada"] = hecha
		m["orden"] = 0
		m["progreso"] = 100.0 if hecha else 0.0
		misiones.append(m)


# --- Guardado ----------------------------------------------------------------------

## { "completadas": [ids], "ganadas": partidas ganadas }
static func cargar() -> Dictionary:
	if not FileAccess.file_exists(RUTA_GUARDADO):
		return {"completadas": [], "ganadas": 0}
	var datos = JSON.parse_string(FileAccess.get_file_as_string(RUTA_GUARDADO))
	if not (datos is Dictionary):
		return {"completadas": [], "ganadas": 0}
	return datos


static func completadas() -> Array:
	return cargar().get("completadas", [])


## Al ganar una partida: suma sus investigaciones completadas al diario global.
static func guardar_victoria(ids: Array) -> void:
	var datos := cargar()
	var lista: Array = datos.get("completadas", [])
	for id in ids:
		if not lista.has(String(id)):
			lista.append(String(id))
	datos["completadas"] = lista
	datos["ganadas"] = int(datos.get("ganadas", 0)) + 1
	var f := FileAccess.open(RUTA_GUARDADO, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(datos, "\t"))
		f.close()


# --- Misma interfaz que el diario de la partida -----------------------------------

func activa() -> Dictionary:
	return {}


func hay_activa() -> bool:
	return false


func esta_completa(m: Dictionary) -> bool:
	return bool(m.get("desbloqueada", false))


func fraccion(m: Dictionary) -> float:
	return 1.0 if esta_completa(m) else 0.0


func cantidad_desbloqueadas() -> int:
	var n := 0
	for m in misiones:
		if m["desbloqueada"]:
			n += 1
	return n
