class_name Ajustes
extends Resource
## Ajustes maestros del juego. Se editan en res://ajustes_juego.tres (abrilo en el
## inspector de Godot o como texto). Todos los multiplicadores valen 1.0 = ritmo actual:
## 2.0 lo hace el doble de rápido, 0.5 a la mitad, 0 lo frena del todo.

const RUTA := "res://ajustes_juego.tres"

@export_group("Reloj")
## Velocidad del reloj marciano (1.0 = un sol de 24:39 dura 24 min 39 s reales).
@export var velocidad_reloj := 1.0

@export_group("Recursos globales")
## Consumo de energía de la base, las máquinas, la cama de hospital y la roomba.
@export var consumo_energia := 1.0
## Energía que generan los paneles solares.
@export var generacion_energia := 1.0
## Velocidad con la que baja el oxígeno (cuando sigue a la energía o sin máquina de O2).
@export var caida_oxigeno := 1.0
## Velocidad con la que sube la radiación.
@export var subida_radiacion := 1.0

@export_group("Máquinas")
## Velocidad con la que baja el mantenimiento de las máquinas.
@export var desgaste_maquinas := 1.0
## Rango del mantenimiento con el que arranca cada máquina (al azar entre los dos).
@export_range(0.0, 100.0) var mantenimiento_inicial_min := 90.0
@export_range(0.0, 100.0) var mantenimiento_inicial_max := 100.0

@export_group("Astronautas")
## Velocidad con la que sube el hambre (baja la comida).
@export var hambre := 1.0
## Velocidad con la que sube el sueño (baja la energía del astronauta).
@export var sueno := 1.0
## Daño directo a la salud (oxígeno muy bajo, radiación alta).
@export var dano_salud := 1.0

static var _actual: Ajustes


## Los ajustes cargados del archivo (o los valores por defecto si el archivo no existe).
static func actual() -> Ajustes:
	if _actual == null:
		if ResourceLoader.exists(RUTA):
			_actual = load(RUTA) as Ajustes
		if _actual == null:
			_actual = Ajustes.new()
	return _actual
