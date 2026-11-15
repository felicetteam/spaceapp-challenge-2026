extends Control
## Menú de inicio (escena principal del juego): Jugar abre la selección de tripulación,
## Salir cierra el juego.

const ESCENA_SELECCION := "res://Pantallas/Seleccion/MenuSeleccion.tscn"
const VentanaInfo := preload("res://UI/ventana_info.gd")
const DiarioGlobal := preload("res://Base/diario_global.gd")
const MusicaMenu := preload("res://Pantallas/musica_menu.gd")

@onready var boton_jugar: Button = $CenterContainer/VBoxContainer/BotonJugar
@onready var boton_diario: Button = $CenterContainer/VBoxContainer/BotonDiario
@onready var boton_salir: Button = $CenterContainer/VBoxContainer/BotonSalir


func _ready() -> void:
	MusicaMenu.sonar(get_tree())  # sigue sin cortarse si venimos de la selección
	boton_jugar.pressed.connect(_on_jugar_pressed)
	boton_salir.pressed.connect(_on_salir_pressed)
	# "Ver Diario": la ventana de Información con el diario global (partidas ganadas)
	boton_diario.pressed.connect(_on_diario_pressed)
	boton_diario.tooltip_text = "Base y las investigaciones completadas en partidas ganadas"
	boton_jugar.grab_focus()


func _on_jugar_pressed() -> void:
	get_tree().change_scene_to_file(ESCENA_SELECCION)


func _on_diario_pressed() -> void:
	var ventana := VentanaInfo.new()
	ventana.diario = DiarioGlobal.new()
	add_child(ventana)


func _on_salir_pressed() -> void:
	get_tree().quit()
