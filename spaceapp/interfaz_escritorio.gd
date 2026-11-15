class_name InterfazEscritorio
extends Control

signal cerrada

@onready var boton_apagar: Button = $ContenedorProporcion/FondoCompu/BotonApagado
@onready var titulo_terminal: Label = $ContenedorProporcion/FondoCompu/AreaPantalla/MarginContainer/VBoxContainer/TituloTerminal
@onready var barra_investigacion: ProgressBar = $ContenedorProporcion/FondoCompu/AreaPantalla/MarginContainer/VBoxContainer/BarraInvestigacion

var escritorio_actual: Escritorio = null
var personaje_actual: Personaje = null


func _ready() -> void:
	visible = false
	boton_apagar.pressed.connect(cerrar)


func abrir(escritorio: Escritorio, personaje: Personaje) -> void:
	escritorio_actual = escritorio
	personaje_actual = personaje
	visible = true

	if not escritorio_actual.investigacion_avanzo.is_connected(_on_investigacion_avanzo):
		escritorio_actual.investigacion_avanzo.connect(_on_investigacion_avanzo)

	_actualizar_datos()


func cerrar() -> void:
	if escritorio_actual and escritorio_actual.investigacion_avanzo.is_connected(_on_investigacion_avanzo):
		escritorio_actual.investigacion_avanzo.disconnect(_on_investigacion_avanzo)

	visible = false
	escritorio_actual = null
	personaje_actual = null
	cerrada.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		cerrar()
		get_viewport().set_input_as_handled()


func _on_investigacion_avanzo(_escritorio: Escritorio, nuevo_progreso: float) -> void:
	barra_investigacion.value = nuevo_progreso


func _actualizar_datos() -> void:
	if not escritorio_actual:
		return

	if personaje_actual:
		titulo_terminal.text = "> OPERADOR: " + personaje_actual.name.to_upper()

	barra_investigacion.value = escritorio_actual.progreso_investigacion
