extends Control
const Idioma := preload("res://Base/idioma.gd")
## Menú de inicio (escena principal del juego): Jugar abre la selección de tripulación,
## Salir cierra el juego. Arriba a la derecha se elige el idioma (español / inglés): cambia
## todo el juego y queda guardado (ver Base/idioma.gd).

const ESCENA_SELECCION := "res://Pantallas/Seleccion/MenuSeleccion.tscn"
const VentanaInfo := preload("res://UI/ventana_info.gd")
const DiarioGlobal := preload("res://Base/diario_global.gd")
const MusicaMenu := preload("res://Pantallas/musica_menu.gd")
const FUENTE := preload("res://assets/fonts/squares.ttf")

@onready var boton_jugar: Button = $CenterContainer/VBoxContainer/BotonJugar
@onready var boton_diario: Button = $CenterContainer/VBoxContainer/BotonDiario
@onready var boton_salir: Button = $CenterContainer/VBoxContainer/BotonSalir


func _ready() -> void:
	Idioma.iniciar()  # el idioma guardado
	_crear_selector_idioma()
	MusicaMenu.sonar(get_tree())  # sigue sin cortarse si venimos de la selección
	boton_jugar.pressed.connect(_on_jugar_pressed)
	boton_salir.pressed.connect(_on_salir_pressed)
	# "Ver Diario": la ventana de Información con el diario global (partidas ganadas)
	boton_diario.pressed.connect(_on_diario_pressed)
	# (texto en español: se traduce solo al cambiar de idioma)
	boton_diario.tooltip_text = "Base y las investigaciones completadas en partidas ganadas"
	boton_jugar.grab_focus()


## Arriba a la derecha: "Idioma" y un desplegable Español / English.
func _crear_selector_idioma() -> void:
	var fila := HBoxContainer.new()
	fila.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	fila.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	fila.offset_right = -20
	fila.offset_top = 16
	fila.add_theme_constant_override("separation", 10)
	add_child(fila)
	var etiqueta := Label.new()
	etiqueta.text = "Idioma"  # se traduce solo ("Language")
	etiqueta.add_theme_font_override("font", FUENTE)
	etiqueta.add_theme_font_size_override("font_size", 22)
	etiqueta.add_theme_color_override("font_outline_color", Color.BLACK)
	etiqueta.add_theme_constant_override("outline_size", 4)
	etiqueta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fila.add_child(etiqueta)
	var opciones := OptionButton.new()
	opciones.focus_mode = Control.FOCUS_NONE
	opciones.add_theme_font_override("font", FUENTE)
	opciones.add_theme_font_size_override("font_size", 20)
	opciones.custom_minimum_size = Vector2(150, 40)
	opciones.tooltip_text = "Elegí el idioma del juego"
	for codigo in Idioma.IDIOMAS:
		opciones.add_item(Idioma.NOMBRES[codigo])
	opciones.select(Idioma.IDIOMAS.find(Idioma.actual()))
	opciones.item_selected.connect(func(i: int): Idioma.aplicar(Idioma.IDIOMAS[i]))
	fila.add_child(opciones)


func _on_jugar_pressed() -> void:
	get_tree().change_scene_to_file(ESCENA_SELECCION)


func _on_diario_pressed() -> void:
	var ventana := VentanaInfo.new()
	ventana.diario = DiarioGlobal.new()
	add_child(ventana)


func _on_salir_pressed() -> void:
	get_tree().quit()
