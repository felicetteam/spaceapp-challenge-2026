class_name Rover
extends Maquina
## Rover de exploración. En una exploración, el astronauta camina hasta el rover, se sube y el
## rover sale manejando por la izquierda del mapa. Al terminar la exploración vuelve a su lugar
## y el astronauta se baja al lado.

signal exploracion_solicitada(rover: Rover)
signal volvio(rover: Rover)

## Velocidad al manejar, en píxeles por segundo.
@export var velocidad_viaje := 60.0
## Hacia dónde mira el dibujo del rover sin voltear (false = a la izquierda).
@export var sprite_mira_derecha := false
## Dónde va sentado el astronauta, respecto del centro del rover (mirando hacia la izquierda;
## de vuelta, hacia la derecha, se espeja).
@export var asiento := Vector2(4, -12)

var en_exploracion := false
var pasajero: Personaje = null
var _casa := Vector2.ZERO
var _tween_viaje: Tween
var _mirando := -1.0
var _z_pasajero := 0


func puede_explorar() -> bool:
	return funcionando() and not en_exploracion


## Punto de entrada para cuando se definan las exploraciones.
func explorar() -> void:
	if puede_explorar():
		exploracion_solicitada.emit(self)


## Se lleva al astronauta (que ya quedó fuera de la base) y sale por la izquierda del mapa.
func partir(p: Personaje) -> void:
	if en_exploracion:
		return
	en_exploracion = true
	pasajero = p
	_casa = global_position
	# Va sentado arriba del rover, a la vista, hasta que salen del mapa
	_z_pasajero = p.z_index
	p.z_index = z_index + 1
	p.visible = true
	_mirar(-1.0)
	_acomodar_pasajero()
	var destino := Vector2(_borde_izquierdo() - 96.0, global_position.y)
	_viajar(destino, func(): visible = false)


## Vuelve a su lugar. al_llegar se llama cuando llegó (para bajar al astronauta).
func volver(al_llegar: Callable) -> void:
	if not en_exploracion:
		al_llegar.call()
		return
	visible = true
	_mirar(1.0)
	_viajar(_casa, func():
		en_exploracion = false
		if is_instance_valid(pasajero):
			pasajero.z_index = _z_pasajero
		pasajero = null
		_mirar(-1.0)  # queda estacionado como estaba
		volvio.emit(self)
		al_llegar.call())


func _process(delta: float) -> void:
	super._process(delta)
	_acomodar_pasajero()


## El astronauta hereda la posición del rover, sentado en el asiento y mirando hacia donde va.
func _acomodar_pasajero() -> void:
	if not en_exploracion or not is_instance_valid(pasajero):
		return
	pasajero.global_position = global_position + Vector2(asiento.x * -_mirando, asiento.y)
	pasajero.visible = visible
	pasajero.mirar(_mirando)


## Dónde se baja el astronauta al volver: abajo del rover.
func punto_de_bajada() -> Vector2:
	var r := rect_global()
	return Vector2(r.get_center().x, r.end.y + 6.0)


## Mientras está afuera (o yéndose con alguien) no se puede tocar ni elegir.
func contiene_punto(p: Vector2) -> bool:
	return seleccionable() and super.contiene_punto(p)


func seleccionable() -> bool:
	return not en_exploracion and pasajero == null


func _viajar(destino: Vector2, al_terminar: Callable) -> void:
	if _tween_viaje != null:
		_tween_viaje.kill()
	var tiempo := global_position.distance_to(destino) / maxf(velocidad_viaje, 1.0)
	_tween_viaje = create_tween()
	_tween_viaje.tween_property(self, "global_position", destino, tiempo) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween_viaje.tween_callback(al_terminar)


func _mirar(dir_x: float) -> void:
	_mirando = dir_x
	var mira_derecha := dir_x > 0.0
	for spr in _sprites:
		spr.set("flip_h", mira_derecha != sprite_mira_derecha)


func _borde_izquierdo() -> float:
	var escena := get_tree().current_scene
	var mapa: TileMapLayer = null
	if escena != null:
		mapa = escena.find_child("TileMapLayer", true, false) as TileMapLayer
	if mapa == null:
		return global_position.x - 600.0
	var usado := mapa.get_used_rect()
	return mapa.to_global(Vector2(usado.position) * Vector2(mapa.tile_set.tile_size)).x


## Clave de este tipo de máquina en Base/ajustes.gd (trabajo_rover).
func tipo_ajuste() -> StringName:
	return &"rover"
