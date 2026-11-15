class_name EscudoRadiacion
extends Maquina
## Mientras dura (con mantenimiento y energía), la radiación de la base deja de crecer.


func _funcion(_delta: float) -> void:
	recursos().activar_escudo()


## Clave de este tipo de máquina en ajustes_juego.tres (trabajo_escudo).
func tipo_ajuste() -> StringName:
	return &"escudo"
