extends Control
## Menú de inicio (escena principal del juego): Jugar abre la base, Salir cierra el juego.

const ESCENA_JUEGO := "res://Base/base.tscn"

@onready var boton_jugar: Button = $CenterContainer/VBoxContainer/BotonJugar
@onready var boton_diario: Button = $CenterContainer/VBoxContainer/BotonDiario
@onready var boton_salir: Button = $CenterContainer/VBoxContainer/BotonSalir


func _ready() -> void:
	boton_jugar.pressed.connect(_on_jugar_pressed)
	boton_salir.pressed.connect(_on_salir_pressed)
	# "Ver Diario" todavía no tiene pantalla
	boton_diario.disabled = true
	boton_diario.tooltip_text = "Próximamente"
	boton_jugar.grab_focus()


func _on_jugar_pressed() -> void:
	get_tree().change_scene_to_file(ESCENA_JUEGO)


func _on_salir_pressed() -> void:
	get_tree().quit()
