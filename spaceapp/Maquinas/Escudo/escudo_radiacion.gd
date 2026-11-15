class_name EscudoRadiacion
extends Maquina
## Mientras funciona (con mantenimiento y energía), la radiación de la base deja de crecer.
## En amarillo o mejor (mantenimiento por encima de umbral_critico) además la hace bajar,
## bastante rápido (Recursos.descenso_radiacion). En rojo solo la frena.


func _funcion(_delta: float) -> void:
	recursos().activar_escudo(not tiene_desgaste or mantenimiento > umbral_critico)


## Clave de este tipo de máquina en ajustes_juego.tres (trabajo_escudo).
func tipo_ajuste() -> StringName:
	return &"escudo"
