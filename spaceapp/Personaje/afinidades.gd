class_name Afinidades
extends RefCounted
## AFINIDADES DE LOS ASTRONAUTAS
## Editá los números de la tabla. 1.0 = normal. Se usan apenas arranca el juego.
##
##   Cada valor dice POR CUÁNTO SE DIVIDE: menos de 1 = mejor, más de 1 = peor.
##   salud          Gasto de comida y energía (0.8 = gasta 20% menos; 1.15 = 15% más).
##   trabajo        Velocidad para trabajar y reparar máquinas (0.8 = 25% más rápido).
##   investigacion  Velocidad para investigar en el escritorio (0.8 = 25% más rápido).
##
## Las claves son los nombres que se ven en el juego (Personaje.NOMBRES). Si un astronauta
## no está en la tabla, o le falta un valor, usa 1.0.

const TABLA := {
	"Feli":      { "salud": 0.8, "trabajo": 1.0, "investigacion": 1.15 },
	"Laika":     { "salud": 1.0, "trabajo": 1.15, "investigacion": 0.8 },
	"Juan":      { "salud": 1.15, "trabajo": 0.8, "investigacion": 1.0 },
	"Andy":      { "salud": 1.0, "trabajo": 1.0, "investigacion": 1.0 },
}


## El multiplicador de un astronauta: tipo es "salud", "trabajo" o "investigacion".
static func de(nombre: String, tipo: String) -> float:
	var fila: Dictionary = TABLA.get(nombre, {})
	return float(fila.get(tipo, 1.0))


## Bonos y penalidades en texto ("+25% velocidad de investigación"...), para la selección de
## tripulación y la ventana de Información. Devuelve { "bonos": [...], "penalidades": [...] }.
static func describir(nombre: String) -> Dictionary:
	var bonos := PackedStringArray()
	var penalidades := PackedStringArray()
	var salud := de(nombre, "salud")
	# La tabla dice por cuánto se divide cada cosa: menos de 1 = bono, más de 1 = penalidad.
	# Salud: el gasto de comida y energía queda multiplicado por el valor
	if salud < 1.0:
		bonos.append("Gasta %d%% menos comida y energía" % roundi((1.0 - salud) * 100.0))
	elif salud > 1.0:
		penalidades.append("Gasta %d%% más comida y energía" % roundi((salud - 1.0) * 100.0))
	# Trabajo e investigación: la velocidad queda dividida por el valor
	for datos in [["trabajo", "velocidad de trabajo y reparación"], ["investigacion", "velocidad de investigación"]]:
		var efecto: float = 1.0 / maxf(de(nombre, datos[0]), 0.01)
		if efecto > 1.0:
			bonos.append("+%d%% %s" % [roundi((efecto - 1.0) * 100.0), datos[1]])
		elif efecto < 1.0:
			penalidades.append("−%d%% %s" % [roundi((1.0 - efecto) * 100.0), datos[1]])
	return {"bonos": bonos, "penalidades": penalidades}
