class_name Comunicaciones
extends Maquina
## Mientras funciona, habilita las alertas y las interfaces de recursos globales y desgastes.


func _funcion(_delta: float) -> void:
	recursos().reportar_comunicaciones()
