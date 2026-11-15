class_name EscudoRadiacion
extends Maquina
## Mientras dura (con mantenimiento y energía), la radiación de la base deja de crecer.


func _funcion(_delta: float) -> void:
	recursos().activar_escudo()
