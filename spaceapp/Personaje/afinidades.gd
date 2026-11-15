class_name Afinidades
extends RefCounted
## AFINIDADES DE LOS ASTRONAUTAS
## Editá los números de la tabla. 1.0 = normal. Se usan apenas arranca el juego.
##
##   salud          Cuánta comida y energía gasta. Menos de 1 = aguanta más
##                  (0.8 = gasta 20% menos); más de 1 = se desgasta más rápido (1.2 = 20% más).
##   trabajo        Velocidad para trabajar y reparar máquinas (1.2 = 20% más rápido).
##   investigacion  Velocidad para investigar en el escritorio (1.2 = 20% más rápido).
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
