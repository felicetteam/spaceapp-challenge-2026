extends Node
## Diario de investigaciones de la partida.
##
## Al empezar se eligen MISIONES_POR_PARTIDA misiones al azar de Base/investigaciones.json, en
## orden aleatorio. Cada evento de exploración es la siguiente misión de esa lista (y toma su
## título). Al volver de explorar se desbloquea su investigación en el diario y enseguida
## queda pendiente la exploración siguiente.
##
## Se pueden tener varias investigaciones desbloqueadas, pero el escritorio solo avanza la más
## vieja (la primera que se desbloqueó y no está completa).
##
## Diario global (entre partidas): todavía sin definir. global_completadas() devuelve las que
## ya se completaron en otras partidas; las misiones se eligen primero entre las que faltan.

signal cambio

const RUTA := "res://Base/investigaciones.json"
const MISIONES_POR_PARTIDA := 4
## Progreso que hay que juntar en el escritorio para completar una investigación
## (el escritorio suma progreso_por_segundo por segundo de trabajo).
const PROGRESO_TOTAL := 100.0

## Las misiones de esta partida, en orden: cada una es el diccionario del JSON más
## "desbloqueada" (bool), "orden" (en qué orden se desbloqueó) y "progreso" (0..PROGRESO_TOTAL).
var misiones: Array[Dictionary] = []
var _proxima := 0         # índice de la próxima misión a explorar
var _contador_orden := 0


## El diario de la escena (o null).
static func de(nodo: Node) -> Node:
	return nodo.get_tree().get_first_node_in_group("diario") if nodo.is_inside_tree() else null


func _ready() -> void:
	add_to_group("diario")
	_elegir_misiones()


func _elegir_misiones() -> void:
	misiones.clear()
	if not FileAccess.file_exists(RUTA):
		push_warning("No existe %s: el diario queda vacío" % RUTA)
		return
	var datos = JSON.parse_string(FileAccess.get_file_as_string(RUTA))
	if not (datos is Dictionary) or not (datos.get("investigaciones") is Array):
		push_error("%s tiene un error de formato" % RUTA)
		return
	var faltan: Array = []
	var hechas: Array = []
	var completadas := global_completadas()
	for inv in datos["investigaciones"]:
		if inv is Dictionary and inv.has("id"):
			if completadas.has(String(inv["id"])):
				hechas.append(inv)
			else:
				faltan.append(inv)
	faltan.shuffle()
	hechas.shuffle()
	for inv in faltan + hechas:
		if misiones.size() >= MISIONES_POR_PARTIDA:
			break
		var m: Dictionary = inv.duplicate(true)
		m["desbloqueada"] = false
		m["orden"] = -1
		m["progreso"] = 0.0
		misiones.append(m)


## Ids ya completados en el diario global (de otras partidas). Por ahora, ninguno.
func global_completadas() -> Array:
	return []


## La próxima misión a explorar ({} si ya no quedan). No avanza la lista.
func siguiente_mision() -> Dictionary:
	return misiones[_proxima] if _proxima < misiones.size() else {}


## Marca la próxima misión como "ya salió su exploración" y la devuelve.
func tomar_mision() -> Dictionary:
	var m := siguiente_mision()
	if not m.is_empty():
		_proxima += 1
	return m


func buscar(id: String) -> Dictionary:
	for m in misiones:
		if String(m["id"]) == id:
			return m
	return {}


## Al volver de explorar: la investigación aparece en el diario.
func desbloquear(id: String) -> Dictionary:
	var m := buscar(id)
	if m.is_empty() or m["desbloqueada"]:
		return m
	m["desbloqueada"] = true
	m["orden"] = _contador_orden
	_contador_orden += 1
	cambio.emit()
	return m


func esta_completa(m: Dictionary) -> bool:
	return float(m.get("progreso", 0.0)) >= PROGRESO_TOTAL


## La que se está investigando: la desbloqueada más vieja que no está completa ({} si ninguna).
func activa() -> Dictionary:
	var mejor: Dictionary = {}
	for m in misiones:
		if m["desbloqueada"] and not esta_completa(m) \
				and (mejor.is_empty() or int(m["orden"]) < int(mejor["orden"])):
			mejor = m
	return mejor


func hay_activa() -> bool:
	return not activa().is_empty()


func cantidad_desbloqueadas() -> int:
	var n := 0
	for m in misiones:
		if m["desbloqueada"]:
			n += 1
	return n


## Suma progreso a la investigación activa. Devuelve la misión si se acaba de completar.
func avanzar(cantidad: float) -> Dictionary:
	var m := activa()
	if m.is_empty() or cantidad <= 0.0:
		return {}
	m["progreso"] = minf(PROGRESO_TOTAL, float(m["progreso"]) + cantidad)
	cambio.emit()
	return m if esta_completa(m) else {}


## 0..1 de una misión.
func fraccion(m: Dictionary) -> float:
	return clampf(float(m.get("progreso", 0.0)) / PROGRESO_TOTAL, 0.0, 1.0)
