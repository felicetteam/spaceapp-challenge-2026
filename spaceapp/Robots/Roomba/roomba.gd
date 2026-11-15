class_name Roomba
extends Node2D
## Robot que lleva a los astronautas inconscientes (salud 0) a una cama de hospital libre,
## o a una cama común si no hay ninguna de hospital disponible. A los que se durmieron de
## agotamiento (sueño al máximo) los lleva a una cama común (o a la de hospital si no hay otra). Después vuelve a su base
## (el lugar donde está puesto en la escena). Necesita energía para moverse.
## base.gd le asigna la navegación.

@export var velocidad := 45.0
## Energía por segundo mientras está en movimiento.
@export var consumo := 0.02

enum Estado { EN_BASE, YENDO, LLEVANDO, VOLVIENDO }

var navegacion: Navegacion
var estado := Estado.EN_BASE
var paciente: Personaje = null
var cama: CamaHospital = null

var _camino := PackedVector2Array()
var _idx := 0
var _base := Vector2.ZERO
var _t_busqueda := 0.0
var _sprite: Node2D


func _ready() -> void:
	add_to_group("roombas")
	add_to_group("consumidores_energia")
	_base = global_position
	for hijo in get_children():
		if hijo is Sprite2D or hijo is AnimatedSprite2D:
			_sprite = hijo
			break


func consumo_energia() -> float:
	return consumo if estado != Estado.EN_BASE else 0.0


func _process(delta: float) -> void:
	var r := Recursos.de(self)
	if r != null and not r.hay_energia():
		return  # sin energía se queda quieto donde esté

	match estado:
		Estado.EN_BASE:
			_t_busqueda -= delta
			if _t_busqueda <= 0.0:
				_t_busqueda = 0.5
				_buscar_paciente()
		Estado.YENDO:
			if not _paciente_valido():
				_volver()
			elif _avanzar(delta):
				_recoger()
		Estado.LLEVANDO:
			if not is_instance_valid(paciente):
				_volver()
				return
			var llego := _avanzar(delta)
			_cargar()
			if llego:
				_dejar()
		Estado.VOLVIENDO:
			if _avanzar(delta):
				estado = Estado.EN_BASE
				if _sprite != null:
					_sprite.rotation = 0.0


func _buscar_paciente() -> void:
	if navegacion == null or not navegacion.listo:
		return
	for nodo in get_tree().get_nodes_in_group("astronautas"):
		var p := nodo as Personaje
		if p == null or not p.desmayado or p.en_cama or p.siendo_llevado or p.reservado_por != null:
			continue
		var c := _cama_libre(p.pies(), p.dormido_agotado)
		if c == null:
			continue  # no hay camas libres: sigue esperando
		var ruta := navegacion.camino(global_position, p.pies())
		if ruta.is_empty():
			continue
		paciente = p
		cama = c
		p.reservado_por = self
		c.reservada_por = self
		_poner_camino(ruta)
		estado = Estado.YENDO
		return


## La cama de hospital libre más cercana; si no hay, la cama común libre más cercana.
## Con preferir_comun (dormido por agotamiento) es al revés.
func _cama_libre(desde: Vector2, preferir_comun := false) -> CamaHospital:
	var mejor_hospital: CamaHospital = null
	var mejor_comun: CamaHospital = null
	var d_hospital := INF
	var d_comun := INF
	for nodo in get_tree().get_nodes_in_group("camas"):
		var c := nodo as CamaHospital
		if c == null or c.ocupante != null or (c.reservada_por != null and c.reservada_por != self):
			continue
		var d := desde.distance_to(c.global_position)
		if c.solo_desmayados:
			if d < d_hospital:
				d_hospital = d
				mejor_hospital = c
		elif d < d_comun:
			d_comun = d
			mejor_comun = c
	if preferir_comun:
		return mejor_comun if mejor_comun != null else mejor_hospital
	return mejor_hospital if mejor_hospital != null else mejor_comun


func _paciente_valido() -> bool:
	return is_instance_valid(paciente) and paciente.desmayado and not paciente.en_cama


func _recoger() -> void:
	var ruta := navegacion.camino(global_position, cama.global_position)
	if ruta.is_empty():
		_volver()
		return
	paciente.siendo_llevado = true
	_poner_camino(ruta)
	estado = Estado.LLEVANDO


## El paciente viaja acostado arriba del robot.
func _cargar() -> void:
	paciente.rotation = -PI / 2.0
	paciente.global_position = global_position + Vector2(0, -6)


func _dejar() -> void:
	paciente.siendo_llevado = false
	paciente.rotation = 0.0
	var c := cama
	var p := paciente
	_liberar_reservas()
	c.acostar(p)
	_volver()


func _volver() -> void:
	if is_instance_valid(paciente) and paciente.siendo_llevado:
		# Se cortó el viaje: lo deja en el piso
		paciente.siendo_llevado = false
		paciente.rotation = -PI / 2.0
	_liberar_reservas()
	estado = Estado.VOLVIENDO
	var ruta := navegacion.camino(global_position, _base) if navegacion != null else PackedVector2Array()
	if ruta.is_empty():
		_poner_camino(PackedVector2Array([_base]))
	else:
		_poner_camino(ruta)


func _liberar_reservas() -> void:
	if is_instance_valid(paciente) and paciente.reservado_por == self:
		paciente.reservado_por = null
	if is_instance_valid(cama) and cama.reservada_por == self:
		cama.reservada_por = null
	paciente = null
	cama = null


func _poner_camino(ruta: PackedVector2Array) -> void:
	_camino = ruta
	_idx = 0


## Avanza por el camino sin física (el robot pasa por debajo de todo). true al llegar.
func _avanzar(delta: float) -> bool:
	if _idx >= _camino.size():
		return true
	var paso := velocidad * delta
	while _idx < _camino.size():
		var objetivo := _camino[_idx]
		var dif := objetivo - global_position
		if dif.length() <= paso:
			global_position = objetivo
			paso -= dif.length()
			_idx += 1
		else:
			global_position += dif.normalized() * paso
			if _sprite != null:
				_sprite.rotation = dif.angle()
			return false
	return true
