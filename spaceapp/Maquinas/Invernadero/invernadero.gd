class_name Invernadero
extends Maquina
## Mientras tiene mantenimiento, el comedor rinde al máximo. Cuanto más desgastado está,
## menos comida recuperan los astronautas (ver Recursos.efectividad_comida()).


func _ready() -> void:
	super._ready()
	add_to_group("invernaderos")


func obtener_estado() -> String:
	var estado := super.obtener_estado()
	if funcionando():
		return "%s · comida %d%%" % [estado, roundi(mantenimiento)]
	return estado
