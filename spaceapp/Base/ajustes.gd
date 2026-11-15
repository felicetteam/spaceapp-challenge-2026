class_name Ajustes
extends Resource
## Ajustes maestros del juego. ESTE ARCHIVO es el que manda: cambiá los números de abajo
## y listo. (Ya no se usa ajustes_juego.tres, que pisaba estos valores y hacía parecer que
## los multiplicadores no funcionaban.)
##
## Con el juego abierto: guardá este archivo en el editor y apretá F6 en el juego para aplicar
## los valores nuevos sin reiniciar.
##
## Todos los multiplicadores valen 1.0 = ritmo original: 2.0 lo hace el doble de rápido,
## 0.5 a la mitad, 0 lo frena del todo.

@export_group("Reloj")
## Velocidad del reloj marciano (1.0 = un sol de 24:39 dura 24 min 39 s reales).
@export var velocidad_reloj := 4.0

@export_group("Recursos globales")
## Consumo de energía de la base, las máquinas, la cama de hospital y la roomba.
@export var consumo_energia := 0.4
## Energía que generan los paneles solares.
@export var generacion_energia := 1.3
## Velocidad con la que baja el oxígeno (cuando sigue a la energía o sin máquina de O2).
@export var caida_oxigeno := 1.0
## Velocidad con la que sube la radiación.
@export var subida_radiacion := 1.0

@export_group("Máquinas")
## Velocidad con la que baja el mantenimiento de las máquinas.
@export var desgaste_maquinas := 0.6
## Desgaste de cada tipo de máquina (se combina con desgaste_maquinas).
@export var desgaste_fotovoltaica := 1.0
@export var desgaste_comunicaciones := 1.0
@export var desgaste_o2 := 1.0
@export var desgaste_invernadero := 1.0
@export var desgaste_escudo := 1.0
@export var desgaste_rover := 1.0
## Cualquier otra máquina que no sea de los tipos de arriba.
@export var desgaste_otras := 1.0
## Rango del mantenimiento con el que arranca cada máquina (al azar entre los dos).
@export_range(0.0, 100.0) var mantenimiento_inicial_min := 70.0
@export_range(0.0, 100.0) var mantenimiento_inicial_max := 80.0

@export_group("Velocidad de trabajo")
## Multiplica el trabajo en todas las máquinas (se combina con el de cada una).
@export var velocidad_trabajo := 0.1
## Reparación de cada tipo de máquina.
@export var trabajo_fotovoltaica := 1.0
@export var trabajo_comunicaciones := 1.0
@export var trabajo_o2 := 1.0
@export var trabajo_invernadero := 1.0
@export var trabajo_escudo := 1.0
@export var trabajo_rover := 1.0
## Progreso de investigación en el escritorio.
@export var trabajo_escritorio := 1.0
## Cualquier otra máquina que no sea de los tipos de arriba.
@export var trabajo_otras := 1.0

@export_group("Comer")
## Qué tan rápido come: acorta el tiempo sentado en el comedor (1.0 = 3 s; 10.0 = 0,3 s).
## No cambia cuánta comida recupera: para eso está comida_por_turno.
@export var velocidad_comer := 0.1
## Cuánta comida recupera en cada turno.
@export var comida_por_turno := 1.5
## Multiplica la espera entre comidas (1.0 = 5 minutos; 0.5 = cada 2 min 30 s).
@export var intervalo_comida := 0.5

@export_group("Dormir")
## Qué tan rápido recupera sueño en la cama de habitación.
@export var velocidad_dormir := 0.15
## Qué tan rápido recupera sueño y comida en la cama de hospital.
@export var velocidad_hospital := 0.15

@export_group("Eventos críticos")
## Si es false, no aparecen eventos (con F7 se puede forzar uno igual, para probar).
@export var eventos_activados := true
## Segundos de juego hasta el primer evento.
@export var primer_evento := 180.0
## Segundos de juego entre un evento y el siguiente (al azar entre los dos).
@export var intervalo_eventos_min := 300.0
@export var intervalo_eventos_max := 600.0

@export_group("Astronautas")
## Velocidad con la que sube el hambre (baja la comida).
@export var hambre := 1.0
## Velocidad con la que sube el sueño (baja la energía del astronauta).
@export var sueno := 1.0
## Daño directo a la salud (oxígeno muy bajo, radiación alta).
@export var dano_salud := 1.0

static var _actual: Ajustes


## Los ajustes con los valores escritos en este archivo.
static func actual() -> Ajustes:
	if _actual == null:
		recargar()
	return _actual


## Vuelve a crear los ajustes (toma los valores actuales del script, por ejemplo después de
## guardarlo en el editor con el juego abierto).
static func recargar() -> void:
	_actual = Ajustes.new()


## Multiplicador de trabajo para un tipo de máquina ("fotovoltaica", "o2", "escritorio", ...).
func trabajo_de(tipo: StringName) -> float:
	var valor = get("trabajo_" + String(tipo))
	if valor == null:
		valor = trabajo_otras
	return velocidad_trabajo * float(valor)


## Multiplicador de desgaste para un tipo de máquina ("fotovoltaica", "o2", ...).
func desgaste_de(tipo: StringName) -> float:
	var valor = get("desgaste_" + String(tipo))
	if valor == null:
		valor = desgaste_otras
	return desgaste_maquinas * float(valor)


## Lista de los valores que no están en 1.0 (para confirmar que el archivo se leyó).
func resumen() -> String:
	var partes: PackedStringArray = []
	for prop in get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or prop.type != TYPE_FLOAT:
			continue
		var nombre: String = prop.name
		if nombre.begins_with("mantenimiento_inicial"):
			continue
		var v: float = get(nombre)
		if not is_equal_approx(v, 1.0):
			partes.append("%s x%s" % [nombre, str(snappedf(v, 0.01))])
	return "todo x1" if partes.is_empty() else ", ".join(partes)
