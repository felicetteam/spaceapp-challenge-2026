extends Control
## Pantalla de selección de tripulación (entre el menú de inicio y el juego).
## - Arriba, los 4 astronautas con sus bonos y penalidades (de Personaje/afinidades.gd).
##   Clic en uno lo pone en el primer lugar libre de abajo; clic de nuevo lo saca.
## - Abajo, los 3 lugares de la tripulación: clic en un lugar ocupado lo vacía.
## - Con los 3 lugares llenos se habilita "Empezar partida". "Volver" vuelve al menú.

const ESCENA_JUEGO := "res://Base/base.tscn"
const ESCENA_MENU := "res://Pantallas/Menu/MenuInicio.tscn"
const TripulacionElegida := preload("res://Personaje/tripulacion_elegida.gd")
const CUADROS := preload("res://Personaje/sprite_frames_personaje.tres")
const FUENTE_TITULO := preload("res://assets/fonts/Klaxon-Crunchy.otf")
const FUENTE_NOMBRE := preload("res://assets/fonts/squares.ttf")
const LUGARES := 3
const ORDEN := [Personaje.Cabeza.JUAN, Personaje.Cabeza.LAIKA, Personaje.Cabeza.FELI, Personaje.Cabeza.ANDY]

const COLOR_BRILLO := Color(0.45, 0.95, 1.0)
const COLOR_BORDE := Color(0.3, 0.33, 0.42)

var _elegidos: Array[int] = []   # cabezas, en el orden de los lugares (-1 = vacío)
var _cuadros := {}               # cabeza -> { "panel", "estilo" }
var _lugares: Array[Dictionary] = []  # { "boton", "img", "lbl" }
var _boton_empezar: Button
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for _i in LUGARES:
		_elegidos.append(-1)
	# Si vuelve desde el juego, arranca con la tripulación anterior
	for i in mini(TripulacionElegida.cabezas.size(), LUGARES):
		_elegidos[i] = TripulacionElegida.cabezas[i]

	var raiz := VBoxContainer.new()
	raiz.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.offset_left = 40
	raiz.offset_right = -40
	raiz.offset_top = 24
	raiz.offset_bottom = -24
	raiz.add_theme_constant_override("separation", 16)
	add_child(raiz)

	var titulo := Label.new()
	titulo.text = "Elegí tres astronautas para la misión"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_override("font", FUENTE_TITULO)
	titulo.add_theme_font_size_override("font_size", 30)
	titulo.add_theme_color_override("font_outline_color", Color.BLACK)
	titulo.add_theme_constant_override("outline_size", 6)
	raiz.add_child(titulo)

	# Los 4 astronautas
	var fila := HBoxContainer.new()
	fila.alignment = BoxContainer.ALIGNMENT_CENTER
	fila.add_theme_constant_override("separation", 16)
	raiz.add_child(fila)
	for c in ORDEN:
		fila.add_child(_crear_cuadro(c))

	var sub := _label("Tu tripulación", 18, Color.WHITE)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_override("font", FUENTE_NOMBRE)
	sub.add_theme_color_override("font_outline_color", Color.BLACK)
	sub.add_theme_constant_override("outline_size", 4)
	raiz.add_child(sub)

	# Los 3 lugares
	var fila_lugares := HBoxContainer.new()
	fila_lugares.alignment = BoxContainer.ALIGNMENT_CENTER
	fila_lugares.add_theme_constant_override("separation", 16)
	raiz.add_child(fila_lugares)
	for i in LUGARES:
		fila_lugares.add_child(_crear_lugar(i))

	var espacio := Control.new()
	espacio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	raiz.add_child(espacio)

	# Volver / Empezar
	var botones := HBoxContainer.new()
	botones.add_theme_constant_override("separation", 16)
	raiz.add_child(botones)
	var volver := _boton_grande("Volver al menú")
	volver.pressed.connect(func(): get_tree().change_scene_to_file(ESCENA_MENU))
	botones.add_child(volver)
	var relleno := Control.new()
	relleno.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	botones.add_child(relleno)
	_boton_empezar = _boton_grande("Empezar partida")
	_boton_empezar.pressed.connect(_empezar)
	botones.add_child(_boton_empezar)

	_actualizar()


func _process(delta: float) -> void:
	# Brillo que late en el borde de los elegidos
	_t += delta
	var brillo := COLOR_BRILLO.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 5.0))
	for c in _cuadros:
		if _elegidos.has(c):
			_cuadros[c]["estilo"].border_color = brillo


# --- Cuadros y lugares ----------------------------------------------------------

func _crear_cuadro(c: int) -> Control:
	var estilo := _estilo(COLOR_BORDE)
	var boton := Button.new()
	boton.focus_mode = Control.FOCUS_NONE
	boton.custom_minimum_size = Vector2(240, 290)
	for estado in ["normal", "hover", "pressed", "focus"]:
		boton.add_theme_stylebox_override(estado, estilo)
	boton.pressed.connect(_tocar_astronauta.bind(c))
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12
	vbox.offset_right = -12
	vbox.offset_top = 10
	vbox.offset_bottom = -10
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	boton.add_child(vbox)
	var img := _imagen_cabeza(c, 72)
	vbox.add_child(img)
	var nombre := _label(String(Personaje.NOMBRES[c]), 24, Color.WHITE)
	nombre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nombre.add_theme_font_override("font", FUENTE_NOMBRE)
	vbox.add_child(nombre)
	var info := _describir(String(Personaje.NOMBRES[c]))
	if info["bonos"].is_empty() and info["penalidades"].is_empty():
		vbox.add_child(_parrafo("Estadísticamente neutral: sin bonos ni penalidades.", Color(0.85, 0.87, 0.92)))
	else:
		vbox.add_child(_parrafo("Bonos", Color(0.55, 1.0, 0.6), 13))
		vbox.add_child(_parrafo("\n".join(info["bonos"]) if not info["bonos"].is_empty() else "Ninguno",
				Color(0.8, 1.0, 0.82)))
		vbox.add_child(_parrafo("Penalidades", Color(1.0, 0.55, 0.5), 13))
		vbox.add_child(_parrafo("\n".join(info["penalidades"]) if not info["penalidades"].is_empty() else "Ninguna",
				Color(1.0, 0.8, 0.78)))
	_cuadros[c] = {"panel": boton, "estilo": estilo}
	return boton


func _crear_lugar(i: int) -> Control:
	var estilo := _estilo(COLOR_BORDE)
	var boton := Button.new()
	boton.focus_mode = Control.FOCUS_NONE
	boton.custom_minimum_size = Vector2(150, 120)
	for estado in ["normal", "hover", "pressed", "focus", "disabled"]:
		boton.add_theme_stylebox_override(estado, estilo)
	boton.tooltip_text = "Clic para sacarlo de la tripulación"
	boton.pressed.connect(_tocar_lugar.bind(i))
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_top = 8
	vbox.offset_bottom = -8
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boton.add_child(vbox)
	var img := _imagen_cabeza(-1, 56)
	vbox.add_child(img)
	var lbl := _label("", 16, Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", FUENTE_NOMBRE)
	vbox.add_child(lbl)
	_lugares.append({"boton": boton, "img": img, "lbl": lbl, "estilo": estilo})
	return boton


func _tocar_astronauta(c: int) -> void:
	var i := _elegidos.find(c)
	if i >= 0:
		_elegidos[i] = -1          # ya estaba: se lo saca
	else:
		var libre := _elegidos.find(-1)
		if libre < 0:
			return                 # los 3 lugares están llenos
		_elegidos[libre] = c
	_actualizar()


func _tocar_lugar(i: int) -> void:
	if _elegidos[i] >= 0:
		_elegidos[i] = -1
		_actualizar()


func _actualizar() -> void:
	var llenos := 0
	for c in _cuadros:
		var elegido := _elegidos.has(c)
		var e: StyleBoxFlat = _cuadros[c]["estilo"]
		e.set_border_width_all(4 if elegido else 2)
		e.border_color = COLOR_BRILLO if elegido else COLOR_BORDE
		e.shadow_color = Color(COLOR_BRILLO, 0.55) if elegido else Color(0, 0, 0, 0)
		e.shadow_size = 10 if elegido else 0
	for i in LUGARES:
		var c := _elegidos[i]
		var lugar: Dictionary = _lugares[i]
		var img: TextureRect = lugar["img"]
		var lbl: Label = lugar["lbl"]
		var e: StyleBoxFlat = lugar["estilo"]
		if c >= 0:
			llenos += 1
			img.texture = _textura_cabeza(c)
			lbl.text = String(Personaje.NOMBRES[c])
			e.border_color = COLOR_BRILLO
		else:
			img.texture = null
			lbl.text = "Lugar %d\n(vacío)" % (i + 1)
			e.border_color = COLOR_BORDE
	_boton_empezar.disabled = llenos < LUGARES
	_boton_empezar.tooltip_text = "" if llenos == LUGARES else "Elegí 3 astronautas para empezar"


func _empezar() -> void:
	if _elegidos.has(-1):
		return
	TripulacionElegida.cabezas = _elegidos.duplicate()
	get_tree().change_scene_to_file(ESCENA_JUEGO)


# --- Bonos y penalidades -------------------------------------------------------

## Lee la tabla de afinidades y la pasa a textos ("+15% velocidad de trabajo"...).
func _describir(nombre: String) -> Dictionary:
	var bonos := PackedStringArray()
	var penalidades := PackedStringArray()
	var salud := Afinidades.de(nombre, "salud")
	var trabajo := Afinidades.de(nombre, "trabajo")
	var investigacion := Afinidades.de(nombre, "investigacion")
	# La tabla dice por cuánto se divide cada cosa: menos de 1 = bono, más de 1 = penalidad.
	# Salud: el gasto de comida y energía queda multiplicado por el valor
	if salud < 1.0:
		bonos.append("Gasta %d%% menos comida y energía" % roundi((1.0 - salud) * 100.0))
	elif salud > 1.0:
		penalidades.append("Gasta %d%% más comida y energía" % roundi((salud - 1.0) * 100.0))
	# Trabajo e investigación: la velocidad queda dividida por el valor
	for datos in [[trabajo, "velocidad de trabajo y reparación"], [investigacion, "velocidad de investigación"]]:
		var efecto: float = 1.0 / maxf(float(datos[0]), 0.01)
		if efecto > 1.0:
			bonos.append("+%d%% %s" % [roundi((efecto - 1.0) * 100.0), datos[1]])
		elif efecto < 1.0:
			penalidades.append("−%d%% %s" % [roundi((1.0 - efecto) * 100.0), datos[1]])
	return {"bonos": bonos, "penalidades": penalidades}


# --- Ayudas ----------------------------------------------------------------------

func _textura_cabeza(c: int) -> Texture2D:
	if c < 0 or not CUADROS.has_animation(&"Cabezas") or c >= CUADROS.get_frame_count(&"Cabezas"):
		return null
	return CUADROS.get_frame_texture(&"Cabezas", c)


func _imagen_cabeza(c: int, alto: int) -> TextureRect:
	var img := TextureRect.new()
	img.texture = _textura_cabeza(c)
	img.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.custom_minimum_size = Vector2(0, alto)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return img


func _estilo(borde: Color) -> StyleBoxFlat:
	var e := StyleBoxFlat.new()
	e.bg_color = Color(0.09, 0.1, 0.14, 1.0)  # opaco
	e.set_corner_radius_all(8)
	e.set_border_width_all(2)
	e.border_color = borde
	return e


func _label(texto: String, tam: int, color: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _parrafo(texto: String, color: Color, tam := 12) -> Label:
	var l := _label(texto, tam, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200, 0)
	return l


func _boton_grande(texto: String) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(220, 48)
	b.add_theme_font_override("font", FUENTE_NOMBRE)
	b.add_theme_font_size_override("font_size", 20)
	return b
