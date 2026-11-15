class_name Escritorio
extends Maquina
## Escritorio de investigación (todavía sin definir). No se desgasta.
## Los astronautas trabajan en él como en una máquina; con energía, suman progreso.

signal investigacion_avanzo(escritorio: Escritorio, progreso: float)

## Progreso por segundo por cada astronauta investigando.
@export var progreso_por_segundo := 1.0

var progreso_investigacion := 0.0


func _init() -> void:
	tiene_desgaste = false
	mostrar_barra = false


func trabajar(delta: float) -> void:
	if funcionando():
		progreso_investigacion += progreso_por_segundo * delta
		investigacion_avanzo.emit(self, progreso_investigacion)


func obtener_estado() -> String:
	if not funcionando():
		return "Sin energía"
	return "Investigación: %d" % int(progreso_investigacion)
