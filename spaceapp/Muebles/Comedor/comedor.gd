class_name Comedor
extends Node2D
const Idioma := preload("res://Base/idioma.gd")
## Comedor con asientos. Al sentarse, el astronauta come durante `duracion_comida` segundos,
## recupera comida y se levanta. Puede comer como mucho una vez cada `intervalo_comida`
## segundos (5 minutos por defecto); si todavía no le toca, se levanta enseguida. Cuánta comida recupera depende
## de los invernaderos (Recursos.efectividad_comida()).
##
## Los asientos son los hijos cuyo nombre empieza con "Asiento": el astronauta se sienta con
## los pies en la posición de cada uno.

## Comida que recupera con los invernaderos al 100%.
@export var comida_por_turno := 40.0
## Segundos reales entre una comida y la siguiente para un mismo astronauta.
@export var intervalo_comida := 300.0
## Cuánto tarda en comer. Al terminar se levanta y vuelve al idle.
@export var duracion_comida := 3.0

var _asientos: Array[Node2D] = []
var _ocupantes := {}  # índice de asiento -> Personaje
var _mesa: Node2D
var _comiendo := {}  # Personaje -> segundos que le faltan para terminar de comer


func _ready() -> void:
	add_to_group("comedores")
	for hijo in get_children():
		if hijo is Node2D and String(hijo.name).begins_with("Asiento"):
			_asientos.append(hijo)
		elif _mesa == null and (hijo is Sprite2D or hijo is AnimatedSprite2D):
			_mesa = hijo


## Reserva un asiento libre (o devuelve el que ya tenía). Vector2.INF si está lleno.
func reservar_asiento(p: Personaje) -> Vector2:
	for i in _ocupantes:
		if _ocupantes[i] == p:
			return _asientos[i].global_position
	for i in _asientos.size():
		if not _ocupantes.has(i):
			_ocupantes[i] = p
			return _asientos[i].global_position
	return Vector2.INF


func empezar_uso(p: Personaje) -> void:
	p.mirar(global_position.x - p.global_position.x)
	if _puede_comer(p):
		_comiendo[p] = duracion_comida / maxf(Ajustes.actual().velocidad_comer, 0.01)
		p.set_laburando(true)  # come con la animación de laburo
		p.mostrar_cartel(Idioma.t("Comiendo..."))
	else:
		# Todavía no le toca: se levanta y vuelve al idle
		var falta := _intervalo() - (Time.get_ticks_msec() - p.ultima_comida_ms) / 1000.0
		p.terminar_tarea(Idioma.t("Próxima comida en %d:%02d") % [int(falta) / 60, int(falta) % 60])


func proceso_uso(p: Personaje, delta: float) -> void:
	if not _comiendo.has(p):
		return
	_comiendo[p] -= delta
	if _comiendo[p] > 0.0:
		return
	_comiendo.erase(p)
	var r := Recursos.de(self)
	var efectividad := r.efectividad_comida() if r != null else 1.0
	var cantidad := comida_por_turno * efectividad * Ajustes.actual().comida_por_turno
	p.comer(cantidad)
	p.ultima_comida_ms = Time.get_ticks_msec()
	# Comida recuperada: se levanta y vuelve al idle
	p.terminar_tarea(Idioma.t("+%d comida") % roundi(cantidad) if cantidad > 0.0 else Idioma.t("Sin comida (invernadero)"))


func terminar_uso(p: Personaje) -> void:
	_comiendo.erase(p)
	for i in _ocupantes.keys():
		if _ocupantes[i] == p:
			_ocupantes.erase(i)


func lugares_libres() -> int:
	return _asientos.size() - _ocupantes.size()


func rect_mesa() -> Rect2:
	if _mesa is Sprite2D:
		return _mesa.get_global_transform() * (_mesa as Sprite2D).get_rect()
	return Rect2(global_position - Vector2(16, 16), Vector2(32, 32))


func contiene_punto(punto: Vector2) -> bool:
	if rect_mesa().has_point(punto):
		return true
	for a in _asientos:
		if Rect2(a.global_position - Vector2(10, 14), Vector2(20, 20)).has_point(punto):
			return true
	return false


func _puede_comer(p: Personaje) -> bool:
	return Time.get_ticks_msec() - p.ultima_comida_ms >= _intervalo() * 1000.0


## Segundos entre comidas, con el multiplicador de Base/ajustes.gd.
func _intervalo() -> float:
	return intervalo_comida * Ajustes.actual().intervalo_comida
