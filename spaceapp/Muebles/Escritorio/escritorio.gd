class_name Escritorio
extends Maquina
## Escritorio de investigación (todavía sin definir). No se desgasta.
## Los astronautas trabajan en él como en una máquina; con energía, suman progreso.
## Solo se puede investigar después de que una exploración desbloquee una investigación.

signal investigacion_avanzo(escritorio: Escritorio, progreso: float)

## Progreso por segundo por cada astronauta investigando.
@export var progreso_por_segundo := 1.0

var progreso_investigacion := 0.0


func _init() -> void:
	tiene_desgaste = false
	mostrar_barra = false


func trabajar(delta: float) -> void:
	if funcionando() and _desbloqueada():
		progreso_investigacion += progreso_por_segundo * delta * Ajustes.actual().trabajo_de(tipo_ajuste())
		investigacion_avanzo.emit(self, progreso_investigacion)


func obtener_estado() -> String:
	if not funcionando():
		return "Sin energía"
	if not _desbloqueada():
		return "Bloqueado: falta explorar"
	return "Investigación: %d" % int(progreso_investigacion)


func _desbloqueada() -> bool:
	return recursos() != null and recursos().investigaciones_desbloqueadas > 0


## Clave de este tipo de máquina en Base/ajustes.gd (trabajo_escritorio).
func tipo_ajuste() -> StringName:
	return &"escritorio"
