class_name MaquinaO2
extends Maquina
## Mientras funciona (con mantenimiento y energía), mantiene el oxígeno igualado a la energía
## según las reglas de Recursos. Si se rompe o no hay energía, el oxígeno baja.


func _funcion(_delta: float) -> void:
	recursos().regular_oxigeno()
