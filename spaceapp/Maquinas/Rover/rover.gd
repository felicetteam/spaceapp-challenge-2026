class_name Rover
extends Maquina
## Habilita las exploraciones (todavía sin definir).

signal exploracion_solicitada(rover: Rover)


func puede_explorar() -> bool:
	return funcionando()


## Punto de entrada para cuando se definan las exploraciones.
func explorar() -> void:
	if puede_explorar():
		exploracion_solicitada.emit(self)


## Clave de este tipo de máquina en ajustes_juego.tres (trabajo_rover).
func tipo_ajuste() -> StringName:
	return &"rover"
