class_name Escritorio
extends Maquina
## Escritorio de investigación. No se desgasta.
## Los astronautas trabajan en él como en una máquina; con energía, suman progreso a la
## investigación activa del diario (Base/diario.gd): la más vieja de las desbloqueadas.
## Solo se puede investigar después de que una exploración desbloquee una investigación.
## Tiene una silla (hijo "Silla", como los asientos del comedor): se investiga sentado ahí,
## de a uno. Una máquina puesta encima del escritorio también se trabaja desde esta silla.

signal investigacion_avanzo(escritorio: Escritorio, progreso: float)
signal interfaz_solicitada(escritorio: Escritorio, personaje: Personaje)

## Progreso por segundo por cada astronauta investigando.
@export var progreso_por_segundo := 1.0

## Progreso (0..100) de la investigación activa del diario (lo muestra la terminal).
var progreso_investigacion := 0.0
## Quién está sentado (o yendo a sentarse) en la silla.
var ocupante_silla: Personaje = null
var _silla: Node2D
var _interfaz_abierta := false


func _init() -> void:
	tiene_desgaste = false
	mostrar_barra = false


var _aviso_bloqueo: Label


func _ready() -> void:
	super._ready()
	_silla = get_node_or_null("Silla")
	# Aviso mientras no se haya explorado nada (sin investigaciones desbloqueadas)
	_aviso_bloqueo = Label.new()
	_aviso_bloqueo.text = "Explorá para desbloquear\nuna investigación"
	_aviso_bloqueo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso_bloqueo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aviso_bloqueo.add_theme_font_size_override("font_size", 7)
	_aviso_bloqueo.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_aviso_bloqueo.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.0))
	_aviso_bloqueo.add_theme_constant_override("outline_size", 3)
	_aviso_bloqueo.z_index = 20
	add_child(_aviso_bloqueo)
	_aviso_bloqueo.size = _aviso_bloqueo.get_minimum_size()
	var debajo := (_silla.position.y + 10.0) if _silla != null else 20.0
	_aviso_bloqueo.position = Vector2(-_aviso_bloqueo.size.x * 0.5, debajo)


func _process(delta: float) -> void:
	super._process(delta)
	_aviso_bloqueo.visible = not _desbloqueada()


## Posición de la silla (donde se paran los pies). Vector2.INF si el escritorio no tiene silla.
func posicion_silla() -> Vector2:
	return _silla.global_position if _silla != null else Vector2.INF


## Reserva la silla para p (o la que ya tenía). Vector2.INF si está ocupada por otro.
func reservar_silla(p: Personaje) -> Vector2:
	if _silla == null:
		return Vector2.INF
	if ocupante_silla != null and is_instance_valid(ocupante_silla) and ocupante_silla != p:
		return Vector2.INF
	ocupante_silla = p
	return _silla.global_position


func liberar_silla(p: Personaje) -> void:
	if ocupante_silla == p:
		ocupante_silla = null
		_interfaz_abierta = false


## El escritorio se trabaja desde su propia silla.
func escritorio_de_silla() -> Escritorio:
	return self if _silla != null else null


## Clic en la silla también cuenta como clic en el escritorio.
func contiene_punto(p: Vector2) -> bool:
	if super.contiene_punto(p):
		return true
	return _silla != null and Rect2(_silla.global_position - Vector2(8, 10), Vector2(16, 16)).has_point(p)


func trabajar(delta: float) -> void:
	# (La terminal ya no se abre sola al sentarse: la compu aparece al abrir Información)
	if funcionando() and _desbloqueada():
		var diario := _diario()
		var cantidad: float = progreso_por_segundo * delta * Ajustes.actual().trabajo_de(tipo_ajuste())
		var activa: Dictionary = diario.activa()
		var completa: Dictionary = diario.avanzar(cantidad)
		progreso_investigacion = 100.0 * diario.fraccion(activa)
		investigacion_avanzo.emit(self, progreso_investigacion)
		if not completa.is_empty():
			_avisar_completa(completa)


## Investigación terminada: aviso en el HUD y, si quedan otras desbloqueadas, sigue con la próxima.
func _avisar_completa(m: Dictionary) -> void:
	var hud := get_tree().current_scene.get_node_or_null("HUD")
	if hud != null and hud.has_method("agregar_alerta"):
		hud.agregar_alerta("¡Investigación completa: %s! Leela en Información > Diario" % String(m.get("titulo", "")), 0, self)
	progreso_investigacion = 0.0


func obtener_estado() -> String:
	if not funcionando():
		return "Sin energía"
	if not _desbloqueada():
		var d := _diario()
		if d != null and d.cantidad_desbloqueadas() > 0:
			return "Todo investigado: explorá para seguir"
		return "Bloqueado: falta explorar"
	var m: Dictionary = _diario().activa()
	return "Investigando %s: %d%%" % [String(m.get("titulo", "")), roundi(100.0 * _diario().fraccion(m))]


## Hay una investigación desbloqueada y sin completar en el diario.
func _desbloqueada() -> bool:
	var d := _diario()
	return d != null and d.hay_activa()


func _diario() -> Node:
	return get_tree().get_first_node_in_group("diario")


## Clave de este tipo de máquina en Base/ajustes.gd (trabajo_escritorio).
func tipo_ajuste() -> StringName:
	return &"escritorio"
