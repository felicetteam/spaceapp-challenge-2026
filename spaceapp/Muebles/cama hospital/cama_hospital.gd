class_name CamaHospital
extends Node2D
## Cuando un Personaje se para encima de la cama, lo centra en ella y muestra la sábana.
## Cuando no hay nadie, la sábana está siempre oculta.
## Va en la raíz de cama_hospital.tscn (funciona con StaticBody2D, Area2D o Node2D).

signal personaje_acostado(personaje: Personaje)
signal personaje_levantado(personaje: Personaje)

## true: lo acuesta cuando el personaje se detiene arriba de la cama.
## false: lo acuesta apenas toca la cama, aunque siga caminando.
@export var acostar_al_detenerse := true
## Corrimiento del personaje respecto del centro de la cama, para acomodar la cabeza en la almohada.
@export var offset_personaje := Vector2.ZERO
## Sprite de la sábana. Si queda vacío, busca un hijo llamado "sabana".
@export var sprite_sabana: CanvasItem
## Zona que detecta al personaje. Si queda vacía, busca un hijo llamado "Deteccion".
@export var zona: Area2D

var ocupante: Personaje = null
var _encima: Array[Personaje] = []


func _ready() -> void:
	if sprite_sabana == null:
		sprite_sabana = get_node_or_null("sabana")
	if zona == null:
		zona = get_node_or_null("Deteccion")
	sprite_sabana.visible = false
	zona.body_entered.connect(_on_body_entered)
	zona.body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	if ocupante != null or not acostar_al_detenerse:
		return
	for p in _encima:
		if p.velocity == Vector2.ZERO:
			acostar(p)
			return


func acostar(p: Personaje) -> void:
	if ocupante != null:
		return  # la cama ya está ocupada
	ocupante = p
	p.global_position = global_position + offset_personaje
	sprite_sabana.visible = true
	personaje_acostado.emit(p)


func levantar() -> void:
	if ocupante == null:
		return
	var p := ocupante
	ocupante = null
	sprite_sabana.visible = false
	personaje_levantado.emit(p)


func _on_body_entered(body: Node2D) -> void:
	if body is Personaje and not _encima.has(body):
		_encima.append(body)
		if not acostar_al_detenerse:
			acostar(body)


func _on_body_exited(body: Node2D) -> void:
	if body is Personaje:
		_encima.erase(body)
		if body == ocupante:
			levantar()
