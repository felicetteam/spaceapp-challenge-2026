extends Node2D

# Recursos ambientales de la base (0 a 100)
@export_range(0.0, 100.0) var oxigeno: float = 100.0
@export_range(0.0, 100.0) var radiacion: float = 15.0
@export var lluvia_particulas: bool = false

@onready var hud: CanvasLayer = $HUD

var tripulacion: Array[Personaje] = []
var indice_activo: int = 0

func _ready() -> void:
	for nodo in get_tree().get_nodes_in_group("astronautas"):
		if nodo is Personaje:
			tripulacion.append(nodo)

	if tripulacion.is_empty():
		return

	hud.inicializar(tripulacion)
	hud.astronauta_clicado.connect(_seleccionar_personaje)
	_seleccionar_indice(0)

func _process(delta: float) -> void:
	for astro in tripulacion:
		astro.actualizar_salud(delta, oxigeno, radiacion, lluvia_particulas)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			_seleccionar_indice(0)
		elif event.keycode == KEY_2:
			_seleccionar_indice(1)
		elif event.keycode == KEY_3:
			_seleccionar_indice(2)

func _seleccionar_indice(idx: int) -> void:
	if idx < 0 or idx >= tripulacion.size():
		return
	indice_activo = idx
	for i in tripulacion.size():
		tripulacion[i].controlado_por_jugador = (i == idx)
	hud.marcar_activo(tripulacion[idx])

func _seleccionar_personaje(astro: Personaje) -> void:
	var idx := tripulacion.find(astro)
	if idx != -1:
		_seleccionar_indice(idx)
