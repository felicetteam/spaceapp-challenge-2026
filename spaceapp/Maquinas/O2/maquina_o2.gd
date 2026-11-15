class_name MaquinaO2
extends Maquina
## Mientras funciona (con mantenimiento y energía), mantiene el oxígeno igualado a la energía
## según las reglas de Recursos. Si se rompe o no hay energía, el oxígeno baja.
## Con desgaste no da abasto: en amarillo (debajo de umbral_borde) el oxígeno baja muy
## despacio hasta tope_amarillo, y en rojo (umbral_critico o menos) hasta tope_rojo.
## Con mantenimiento 0 deja de funcionar y el oxígeno cae hasta 0.

## Oxígeno máximo que sostiene con el borde amarillo.
@export var tope_amarillo := 75.0
## Oxígeno máximo que sostiene con el borde rojo.
@export var tope_rojo := 50.0


func _funcion(_delta: float) -> void:
	recursos().regular_oxigeno(tope_oxigeno())


func tope_oxigeno() -> float:
	if not tiene_desgaste or mantenimiento >= umbral_borde:
		return 100.0
	if mantenimiento > umbral_critico:
		return tope_amarillo
	return tope_rojo


## Clave de este tipo de máquina en ajustes_juego.tres (trabajo_o2).
func tipo_ajuste() -> StringName:
	return &"o2"
