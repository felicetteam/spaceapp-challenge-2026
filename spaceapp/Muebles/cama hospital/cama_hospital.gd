class_name CamaHospital
extends Node2D
## Cama genérica: la usan cama_hospital.tscn y cama_habitacion.tscn.
## Cuando un Personaje se queda quieto encima (sin ninguna orden), lo acuesta en el centro
## y muestra la sábana. Mientras está acostado recupera sueño (y comida, si se configura).
## Cuando no hay nadie, la sábana está siempre oculta.
##
## Cama de hospital: solo_desmayados = true (solo acepta astronautas con salud 0, que trae la
## roomba), recupera sueño y comida despacio y consume energía mientras se usa.
## Funciona con raíz StaticBody2D, Area2D o Node2D.

signal personaje_acostado(personaje: Personaje)
signal personaje_levantado(personaje: Personaje)

## true: lo acuesta cuando el personaje se detiene arriba de la cama.
## false: lo acuesta apenas toca la cama, aunque siga caminando.
@export var acostar_al_detenerse := true
## Corrimiento del personaje respecto del centro de la cama, para acomodar la cabeza en la almohada.
@export var offset_personaje := Vector2.ZERO
## Rotación que se le aplica al personaje mientras está acostado, en grados.
## Negativo = antihorario.
@export var rotacion_personaje_grados := 0.0

@export_group("Uso")
## Solo acepta astronautas inconscientes (salud 0). Para la cama de hospital.
@export var solo_desmayados := false
## Sueño que recupera por segundo mientras está acostado.
@export var recupera_sueno := 6.0
## Comida que recupera por segundo mientras está acostado.
@export var recupera_comida := 0.0
## Energía por segundo mientras está ocupada. Si es mayor a 0, sin energía no recupera nada.
@export var consumo_energia_uso := 0.0

@export_group("Nodos")
## Sprite de la sábana. Si queda vacío, busca un hijo llamado "sabana".
@export var sprite_sabana: CanvasItem
## Zona que detecta al personaje. Si queda vacía, busca un hijo llamado "Deteccion".
@export var zona: Area2D

var ocupante: Personaje = null
## Lo marca la roomba mientras trae a alguien, para que nadie más la ocupe.
var reservada_por: Node = null
var _z_cabeza_original := 0
var _encima: Array[Personaje] = []
var _sprite_cama: Node2D


func _ready() -> void:
	add_to_group("camas")
	add_to_group("consumidores_energia")
	if sprite_sabana == null:
		sprite_sabana = get_node_or_null("sabana")
	if zona == null:
		zona = get_node_or_null("Deteccion")
	_sprite_cama = get_node_or_null("cama")
	sprite_sabana.visible = false
	zona.body_entered.connect(_on_body_entered)
	zona.body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	if ocupante != null or not acostar_al_detenerse:
		return
	for p in _encima:
		if p.velocity == Vector2.ZERO and _puede_acostarse(p):
			acostar(p)
			return


func _process(delta: float) -> void:
	if ocupante == null:
		return
	var recuperando := consumo_energia_uso <= 0.0 or _hay_energia()
	ocupante.durmiendo = recuperando
	if recuperando:
		var aj := Ajustes.actual()
		var mult := aj.velocidad_hospital if solo_desmayados else aj.velocidad_dormir
		ocupante.sueno = maxf(0.0, ocupante.sueno - recupera_sueno * mult * delta)
		ocupante.hambre = maxf(0.0, ocupante.hambre - recupera_comida * aj.velocidad_hospital * delta)
	# Recuperado (y despierto): se levanta y vuelve al idle
	var p := ocupante
	if not p.desmayado and p.sueno <= 0.0 and (recupera_comida <= 0.0 or p.hambre <= 0.0):
		levantar()
		p.terminar_tarea("Descansado")


func consumo_energia() -> float:
	return consumo_energia_uso if ocupante != null else 0.0


func esta_libre() -> bool:
	return ocupante == null and reservada_por == null


func acostar(p: Personaje) -> void:
	if ocupante != null or (solo_desmayados and not p.desmayado):
		return
	ocupante = p
	p.en_cama = true
	p.quiere_acostarse = false
	p.global_position = global_position + offset_personaje
	p.rotation = deg_to_rad(rotacion_personaje_grados)
	# La cabeza queda por encima de la sábana mientras está acostado
	_z_cabeza_original = p.sprite_cabeza.z_index
	p.sprite_cabeza.z_index = sprite_sabana.z_index + 1
	sprite_sabana.visible = true
	personaje_acostado.emit(p)


func levantar() -> void:
	if ocupante == null:
		return
	var p := ocupante
	ocupante = null
	p.en_cama = false
	p.durmiendo = false
	p.rotation = -PI / 2.0 if p.desmayado else 0.0
	p.sprite_cabeza.z_index = _z_cabeza_original
	sprite_sabana.visible = false
	personaje_levantado.emit(p)


func contiene_punto(punto: Vector2) -> bool:
	if _sprite_cama is AnimatedSprite2D:
		var a := _sprite_cama as AnimatedSprite2D
		if a.sprite_frames != null and a.sprite_frames.get_frame_count(a.animation) > 0:
			var tam := a.sprite_frames.get_frame_texture(a.animation, a.frame).get_size()
			return (a.get_global_transform() * Rect2(-tam * 0.5, tam)).has_point(punto)
	return Rect2(global_position - Vector2(8, 16), Vector2(16, 32)).has_point(punto)


## Se acuesta quien está libre (sin órdenes ni desvíos) y quiere acostarse, o el inconsciente.
## Nunca mientras la roomba lo lleva, ni en una cama reservada para otro.
func _puede_acostarse(p: Personaje) -> bool:
	if p.siendo_llevado or (reservada_por != null and p.reservado_por != reservada_por):
		return false
	if solo_desmayados:
		return p.desmayado
	# Solo si el jugador lo mandó a acostarse (clic en la cama o caminando con el teclado):
	# paseando solo nunca se mete en una cama.
	return p.desmayado or (p.esta_libre() and p.quiere_acostarse)


func _hay_energia() -> bool:
	var r := Recursos.de(self)
	return r != null and r.hay_energia()


func _on_body_entered(body: Node2D) -> void:
	if body is Personaje and not _encima.has(body):
		_encima.append(body)
		if not acostar_al_detenerse and _puede_acostarse(body):
			acostar(body)


func _on_body_exited(body: Node2D) -> void:
	if body is Personaje:
		_encima.erase(body)
		if body == ocupante:
			levantar()
