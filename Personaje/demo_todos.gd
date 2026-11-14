extends Node2D
## Instancia un personaje por cada cabeza y los pone en fila.
## Todos responden al mismo input, así ves las animaciones de todos en simultáneo.

@export var escena_personaje: PackedScene = preload("res://Personaje/personaje.tscn")
@export var separacion := 40.0


func _ready() -> void:
	for i in Personaje.Cabeza.size():
		var instancia := escena_personaje.instantiate()
		add_child(instancia)
		instancia.position = Vector2(i * separacion, 0)
		_buscar_personaje(instancia).cabeza = i


## Funciona tanto si la raíz de personaje.tscn es el CharacterBody2D como si sigue siendo el Node2D.
func _buscar_personaje(nodo: Node) -> Personaje:
	if nodo is Personaje:
		return nodo
	for hijo in nodo.get_children():
		if hijo is Personaje:
			return hijo
	push_error("personaje.tscn no tiene un nodo con personaje.gd")
	return null
