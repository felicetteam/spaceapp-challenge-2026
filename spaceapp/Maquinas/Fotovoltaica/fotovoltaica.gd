class_name Fotovoltaica
extends Maquina
## Panel solar: genera energía de día. Rinde al máximo hasta el mediodía y pierde
## efectividad de a poco hasta que anochece (ver Recursos.factor_solar()).
## No necesita energía para funcionar, pero sí mantenimiento.

## Energía por segundo a pleno rendimiento.
@export var generacion_maxima := 0.25


func _init() -> void:
	requiere_energia = false
	consumo = 0.0


func _ready() -> void:
	super._ready()
	add_to_group("generadores_energia")


func generacion_energia() -> float:
	if not funcionando() or recursos() == null:
		return 0.0
	return generacion_maxima * recursos().factor_solar()


func obtener_estado() -> String:
	var estado := super.obtener_estado()
	if estado == Idioma.t("Operativa") and recursos() != null:
		return Idioma.t("Generando %d%%") % roundi(recursos().factor_solar() * 100.0) if recursos().es_de_dia() else Idioma.t("Noche")
	return estado


## Clave de este tipo de máquina en Base/ajustes.gd (trabajo_fotovoltaica).
func tipo_ajuste() -> StringName:
	return &"fotovoltaica"
