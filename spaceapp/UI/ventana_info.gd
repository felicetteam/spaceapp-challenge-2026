extends Control
const Idioma := preload("res://Base/idioma.gd")
## Ventana de Información (botón junto a pausa/play). Tiene dos carpetas:
## - Base: a la izquierda "Máquinas", "Mecánicas" y "Astronautas"; a la derecha una grilla con
##   el dibujo de cada uno (o solo el nombre). Al tocar uno se ve su explicación; los astronautas
##   muestran su historia y sus bonos y penalidades (como en la selección).
## - Diario: a la izquierda las investigaciones de la partida (??? si todavía no se
##   desbloquearon); a la derecha la elegida, con su barra de progreso, lo que ya se descubrió
##   y, al completarla, el reporte.
## El juego no se pausa (así se ve avanzar la investigación). Todas las pantallas se cierran
## con "Cerrar" (o Esc).
## Al abrirla, primero aparece la compu (assets/sprites/compu.png): la cámara se acerca despacio
## a la pantalla, se ve "Cargando..." y a los DURACION_INTRO segundos aparece la ventana.
## Un clic durante la animación la saltea.

const TextosAyuda := preload("res://Base/textos_ayuda.gd")
const RUTA_COMPU := "res://assets/sprites/compu.png"
## Parte negra (pantalla) de la compu, en fracciones de la imagen.
const PANTALLA_COMPU := Rect2(0.174, 0.109, 0.654, 0.396)
const DURACION_INTRO := 5.0
const DURACION_ZOOM := 1.8
var _intro: Control = null
var _panel: Control = null
var _t_intro := 0.0
var _lbl_cargando: Label
var _inicio_ms := Time.get_ticks_msec()
const CUADROS_PERSONAJE := preload("res://Personaje/sprite_frames_personaje.tres")

## El diario de la partida (Base/diario.gd) o el global (Base/diario_global.gd, desde el menú).
var diario = null
## Pantalla con la que abre: "" (las carpetas) o "diario" (con seleccion_inicial elegida).
var abrir_en := ""
var seleccion_inicial := -1
## Escenas de donde sacar los dibujos si no hay un mapa cargado (por ejemplo, en el menú).
const ESCENAS_DIBUJOS := [
	["fotovoltaica", "res://Maquinas/Fotovoltaica/fotovoltaica.tscn"],
	["o2", "res://Maquinas/O2/maquina_o2.tscn"],
	["escudo", "res://Maquinas/Escudo/escudo_radiacion.tscn"],
	["comunicaciones", "res://Maquinas/Comunicaciones/comunicaciones.tscn"],
	["invernadero", "res://Maquinas/Invernadero/invernadero.tscn"],
	["rover", "res://Maquinas/Rover/rover.tscn"],
	["escritorio", "res://Muebles/Escritorio/escritorio.tscn"],
	["comedor", "res://Muebles/Comedor/comedor.tscn"],
	["cama", "res://Muebles/cama habitacion/cama_habitacion.tscn"],
	["cama_hospital", "res://Muebles/cama hospital/cama_hospital.tscn"],
	["roomba", "res://Robots/Roomba/roomba.tscn"],
]

var _titulo: Label
var _boton_volver: Button
var _cuerpo: Control
var _al_volver: Callable = Callable()
# Diario: la investigación elegida y los nodos que se actualizan solos
var _sel_diario := 0
var _barra: ProgressBar
var _lbl_estado: Label
var _firma_diario := ""
var _t_refresco := 0.0
var _en_diario := false
var _texturas := {}  # clave de máquina o mueble -> Texture2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var fondo := ColorRect.new()
	fondo.color = Color(0, 0, 0, 0.6)
	fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fondo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fondo)

	var panel := PanelContainer.new()
	_panel = panel
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 70
	panel.offset_right = -70
	panel.offset_top = 40
	panel.offset_bottom = -40
	var estilo := _estilo(Color(0.35, 0.85, 1.0))
	estilo.content_margin_left = 16
	estilo.content_margin_right = 16
	estilo.content_margin_top = 12
	estilo.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", estilo)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	var cabecera := HBoxContainer.new()
	cabecera.add_theme_constant_override("separation", 8)
	vbox.add_child(cabecera)
	_titulo = _label(Idioma.t("Información"), 18, Color(0.6, 0.9, 1.0))
	_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cabecera.add_child(_titulo)
	_boton_volver = _boton(Idioma.t("Volver"), Vector2(90, 30))
	_boton_volver.pressed.connect(func():
		if _al_volver.is_valid():
			_al_volver.call())
	cabecera.add_child(_boton_volver)
	var cerrar := _boton(Idioma.t("Cerrar"), Vector2(90, 30))
	cerrar.pressed.connect(queue_free)
	cabecera.add_child(cerrar)
	vbox.add_child(HSeparator.new())

	_cuerpo = MarginContainer.new()
	_cuerpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_cuerpo)

	_juntar_texturas()
	_mostrar_carpetas()
	if abrir_en == "diario":
		_mostrar_diario(seleccion_inicial)
	_empezar_intro()


func _es_global() -> bool:
	return diario != null and diario.get("es_global") == true


# --- Animación de entrada (la compu) ----------------------------------------------

func _empezar_intro() -> void:
	var tex := _imagen(RUTA_COMPU)
	if tex == null:
		return  # sin la imagen, directo a la ventana
	_panel.visible = false
	_intro = Control.new()
	_intro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_intro.mouse_filter = Control.MOUSE_FILTER_STOP
	_intro.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_terminar_intro())
	add_child(_intro)
	var negro := ColorRect.new()
	negro.color = Color(0, 0, 0, 0.85)
	negro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	negro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_intro.add_child(negro)

	# La compu, entera y centrada
	var vista := get_viewport_rect().size
	var tam_img := tex.get_size()
	var escala0 := minf(vista.x * 0.8 / tam_img.x, vista.y * 0.9 / tam_img.y)
	var tam := tam_img * escala0
	var compu := TextureRect.new()
	compu.texture = tex
	compu.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	compu.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	compu.stretch_mode = TextureRect.STRETCH_SCALE
	compu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compu.size = tam
	compu.position = (vista - tam) * 0.5
	compu.modulate.a = 0.0
	_intro.add_child(compu)

	# Zoom lento hacia la pantalla negra: crece alrededor del centro de la pantalla hasta
	# llenar la vista, y ese centro se mueve al centro de la vista
	var pantalla := Rect2(PANTALLA_COMPU.position * tam, PANTALLA_COMPU.size * tam)
	var centro := pantalla.get_center()
	compu.pivot_offset = centro
	# Sin llenar del todo la vista: queda un poco del borde de la compu alrededor
	var escala_final := minf(vista.x / pantalla.size.x, vista.y / pantalla.size.y) * 0.82
	var pos_final := compu.position + (vista * 0.5 - (compu.position + centro))
	var tw := create_tween()
	tw.set_ignore_time_scale(true)  # también con el juego en pausa o acelerado
	tw.tween_property(compu, "modulate:a", 1.0, 0.4)
	tw.tween_interval(0.3)
	tw.tween_property(compu, "scale", Vector2.ONE * escala_final, DURACION_ZOOM) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(compu, "position", pos_final, DURACION_ZOOM) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# "Cargando..." en la pantalla, cuando ya está cerca
	_lbl_cargando = Label.new()
	_lbl_cargando.text = Idioma.t("Cargando")
	_lbl_cargando.add_theme_font_size_override("font_size", 28)
	_lbl_cargando.add_theme_color_override("font_color", Color(0.2, 1.0, 0.3))
	_lbl_cargando.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_cargando.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_cargando.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lbl_cargando.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl_cargando.visible = false
	_intro.add_child(_lbl_cargando)
	_inicio_ms = Time.get_ticks_msec()


func _actualizar_intro() -> void:
	if _intro == null:
		return
	_t_intro = (Time.get_ticks_msec() - _inicio_ms) / 1000.0
	if _t_intro >= 0.7 + DURACION_ZOOM * 0.85:
		_lbl_cargando.visible = true
		_lbl_cargando.text = Idioma.t("Cargando") + ".".repeat(1 + int(_t_intro * 3.0) % 3)
	if _t_intro >= DURACION_INTRO:
		_terminar_intro()


func _terminar_intro() -> void:
	if _intro == null:
		return
	_intro.queue_free()
	_intro = null
	_panel.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()


func _process(delta: float) -> void:
	_actualizar_intro()
	if not _en_diario or diario == null:
		return
	_t_refresco -= delta
	if _t_refresco > 0.0:
		return
	_t_refresco = 0.25
	# Si cambió lo que se ve (se desbloqueó algo, se reveló un párrafo...), se rearma;
	# si no, solo se mueve la barra
	if _firma() != _firma_diario:
		_mostrar_diario(_sel_diario)
	elif _barra != null and is_instance_valid(_barra) and _sel_diario < diario.misiones.size():
		var m: Dictionary = diario.misiones[_sel_diario]
		_barra.value = 100.0 * diario.fraccion(m)
		_lbl_estado.text = _texto_estado(m)


# --- Pantallas -------------------------------------------------------------------

func _limpiar(titulo: String, al_volver: Callable) -> void:
	for h in _cuerpo.get_children():
		h.queue_free()
	_titulo.text = titulo
	_al_volver = al_volver
	_boton_volver.visible = al_volver.is_valid()
	_en_diario = false
	_barra = null


func _mostrar_carpetas() -> void:
	_limpiar(Idioma.t("Diario global") if _es_global() else Idioma.t("Información"), Callable())
	var centro := CenterContainer.new()
	_cuerpo.add_child(centro)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 60)
	centro.add_child(fila)
	for datos in [[Idioma.t("Base"), Idioma.t("Máquinas y mecánicas"), _mostrar_base.bind("maquinas")],
			[Idioma.t("Diario"), Idioma.t("Investigaciones completadas en partidas ganadas") if _es_global()
					else Idioma.t("Investigaciones de la misión"), _mostrar_diario.bind(-1)]]:
		var b := _boton(datos[0], Vector2(230, 190))
		b.icon = _icono_carpeta()
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_font_size_override("font_size", 20)
		b.tooltip_text = datos[1]
		b.add_theme_constant_override("icon_max_width", 120)
		b.pressed.connect(datos[2])
		fila.add_child(b)


## Columna izquierda (un tercio) y contenido a la derecha (dos tercios).
func _dos_columnas() -> Array:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 14)
	_cuerpo.add_child(fila)
	var izq := VBoxContainer.new()
	izq.add_theme_constant_override("separation", 8)
	izq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	izq.size_flags_stretch_ratio = 1.0
	fila.add_child(izq)
	var der := PanelContainer.new()
	der.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	der.size_flags_stretch_ratio = 2.0
	var e := _estilo(Color(0.25, 0.28, 0.35))
	e.bg_color = Color(0.07, 0.08, 0.11, 0.9)
	e.content_margin_left = 12
	e.content_margin_right = 12
	e.content_margin_top = 10
	e.content_margin_bottom = 10
	der.add_theme_stylebox_override("panel", e)
	fila.add_child(der)
	return [izq, der]


func _mostrar_base(seccion: String) -> void:
	_limpiar(Idioma.t("Base"), _mostrar_carpetas)
	var cols := _dos_columnas()
	var izq: VBoxContainer = cols[0]
	var der: PanelContainer = cols[1]
	for datos in [["maquinas", Idioma.t("Máquinas")], ["mecanicas", Idioma.t("Mecánicas")], ["astronautas", Idioma.t("Astronautas")]]:
		var b := _boton(datos[1], Vector2(0, 54))
		b.add_theme_font_size_override("font_size", 16)
		b.toggle_mode = true
		b.button_pressed = datos[0] == seccion
		b.pressed.connect(_mostrar_base.bind(datos[0]))
		izq.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	der.add_child(scroll)
	var grilla := GridContainer.new()
	grilla.columns = 4
	grilla.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grilla.add_theme_constant_override("h_separation", 8)
	grilla.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grilla)
	var items: Array = _items_mecanicas()
	if seccion == "maquinas":
		items = _items_maquinas()
	elif seccion == "astronautas":
		items = _items_astronautas()
	for item in items:
		var b := _boton(item["titulo"], Vector2(0, 104))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 12)
		var tex: Texture2D = item.get("textura")
		if tex != null:
			b.icon = tex
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.add_theme_constant_override("icon_max_width", 56)
		b.pressed.connect(_mostrar_detalle.bind(item, seccion))
		grilla.add_child(b)


func _mostrar_detalle(item: Dictionary, seccion: String) -> void:
	_limpiar(Idioma.t("Base · %s") % Idioma.t(String(item["titulo"])), _mostrar_base.bind(seccion))
	# Con scroll por si el texto es largo (por ejemplo, la historia de un astronauta)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_cuerpo.add_child(scroll)
	var centro := CenterContainer.new()
	centro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(centro)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(620, 0)
	vbox.add_theme_constant_override("separation", 12)
	centro.add_child(vbox)
	var tex: Texture2D = item.get("textura")
	if tex != null:
		var img := TextureRect.new()
		img.texture = tex
		img.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.custom_minimum_size = Vector2(0, 130)
		vbox.add_child(img)
	var t := _label(String(item["titulo"]), 20, Color(0.6, 0.9, 1.0))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(t)
	var texto := _label(String(item["texto"]), 15, Color.WHITE)
	texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(texto)
	if item.has("dato"):
		var dato := _label(Idioma.t("Dato curioso: ") + Idioma.t(String(item["dato"])), 14, Color(0.6, 0.85, 1.0))
		dato.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(dato)
	if item.has("bonos"):
		var bonos: PackedStringArray = item["bonos"]
		var penalidades: PackedStringArray = item["penalidades"]
		if bonos.is_empty() and penalidades.is_empty():
			vbox.add_child(_parrafo(Idioma.t("Estadísticamente neutral: sin bonos ni penalidades."), Color(0.85, 0.87, 0.92)))
		else:
			vbox.add_child(_parrafo(Idioma.t("Bonos: ") + (", ".join(bonos) if not bonos.is_empty() else Idioma.t("ninguno")),
					Color(0.55, 1.0, 0.6)))
			vbox.add_child(_parrafo(Idioma.t("Penalidades: ") + (", ".join(penalidades) if not penalidades.is_empty() else Idioma.t("ninguna")),
					Color(1.0, 0.6, 0.55)))
	if item.has("fuente"):
		var fuente := _label(Idioma.t("Fuente: ") + Idioma.t(String(item["fuente"])), 11, Color(0.65, 0.68, 0.75))
		fuente.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(fuente)


func _mostrar_diario(seleccion: int) -> void:
	_limpiar(Idioma.t("Diario global") if _es_global() else Idioma.t("Diario"), _mostrar_carpetas)
	if diario == null or diario.misiones.is_empty():
		_cuerpo.add_child(_label(Idioma.t("El diario está vacío."), 15, Color.WHITE))
		return
	if seleccion < 0:
		# Al abrir, la que se está investigando (o la primera)
		seleccion = maxi(0, diario.misiones.find(diario.activa()))
	_sel_diario = clampi(seleccion, 0, diario.misiones.size() - 1)
	_en_diario = true
	_firma_diario = _firma()
	var cols := _dos_columnas()
	var izq: VBoxContainer = cols[0]
	var der: PanelContainer = cols[1]
	# Con muchas investigaciones (el diario global tiene todas) la lista tiene scroll
	var lista: VBoxContainer = izq
	if diario.misiones.size() > 6:
		var scroll_izq := ScrollContainer.new()
		scroll_izq.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll_izq.size_flags_vertical = Control.SIZE_EXPAND_FILL
		izq.add_child(scroll_izq)
		lista = VBoxContainer.new()
		lista.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lista.add_theme_constant_override("separation", 8)
		scroll_izq.add_child(lista)
	if _es_global():
		var resumen := _label(Idioma.t("%d de %d investigaciones · %d partidas ganadas") % [
				diario.cantidad_desbloqueadas(), diario.misiones.size(), int(diario.partidas_ganadas)], 12,
				Color(1.0, 0.85, 0.45))
		resumen.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		izq.add_child(resumen)
		izq.move_child(resumen, 0)
	for i in diario.misiones.size():
		var m: Dictionary = diario.misiones[i]
		var b := _boton(_texto_lista(m), Vector2(0, 58))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 13)
		b.toggle_mode = true
		b.button_pressed = i == _sel_diario
		b.pressed.connect(_mostrar_diario.bind(i))
		lista.add_child(b)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	der.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)
	var m: Dictionary = diario.misiones[_sel_diario]
	if not m["desbloqueada"]:
		var t := _label("???", 28, Color(0.7, 0.72, 0.8))
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(t)
		var txt := Idioma.t("Todavía no se desbloqueó. Salí a explorar con el rover: al volver de cada exploración, su investigación aparece en el diario.")
		if _es_global():
			txt = Idioma.t("Todavía no la completaste en ninguna partida ganada. ¡Ganá una partida con esta misión para guardarla en el diario!")
		vbox.add_child(_parrafo(txt, Color(0.85, 0.87, 0.92)))
		return
	vbox.add_child(_label(String(m["titulo"]), 20, Color(0.6, 0.9, 1.0)))
	_lbl_estado = _label(_texto_estado(m), 13, Color(1.0, 0.85, 0.45))
	_lbl_estado.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_lbl_estado)
	_barra = ProgressBar.new()
	_barra.custom_minimum_size = Vector2(0, 22)
	_barra.max_value = 100.0
	_barra.value = 100.0 * diario.fraccion(m)
	var fondo_barra := StyleBoxFlat.new()
	fondo_barra.bg_color = Color(0.15, 0.17, 0.22)
	fondo_barra.set_corner_radius_all(4)
	var relleno := StyleBoxFlat.new()
	relleno.bg_color = Color(0.35, 0.8, 0.45)
	relleno.set_corner_radius_all(4)
	_barra.add_theme_stylebox_override("background", fondo_barra)
	_barra.add_theme_stylebox_override("fill", relleno)
	vbox.add_child(_barra)
	var tex := _imagen(String(m.get("imagen", "")))
	if tex != null:
		var img := TextureRect.new()
		img.texture = tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.custom_minimum_size = Vector2(0, 170)
		vbox.add_child(img)
	# Lo descubierto se va revelando a medida que avanza la investigación
	var parrafos: Array = m.get("texto", [])
	var visibles := _parrafos_visibles(m)
	for i in parrafos.size():
		if i < visibles:
			vbox.add_child(_parrafo(String(parrafos[i]), Color.WHITE))
		else:
			vbox.add_child(_parrafo(Idioma.t("· · · (seguí investigando para descubrirlo)"), Color(0.55, 0.58, 0.65)))
	if diario.esta_completa(m):
		_agregar_reporte(vbox, m)


func _agregar_reporte(vbox: VBoxContainer, m: Dictionary) -> void:
	vbox.add_child(HSeparator.new())
	vbox.add_child(_label(Idioma.t("Reporte"), 17, Color(0.6, 0.9, 1.0)))
	if not m.has("respuestas"):
		m["respuestas"] = {}
	var respuestas: Dictionary = m["respuestas"]
	var preguntas: Array = m.get("reporte", [])
	for qi in preguntas.size():
		var q: Dictionary = preguntas[qi]
		vbox.add_child(_parrafo("%d. %s" % [qi + 1, String(q["pregunta"])], Color.WHITE))
		var opciones: Array = q.get("opciones", [])
		var correcta := int(q.get("correcta", 0))
		var elegida := int(respuestas.get(qi, -1))
		for oi in opciones.size():
			var b := _boton("%s) %s" % [char(97 + oi), String(opciones[oi])], Vector2(0, 30))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.add_theme_font_size_override("font_size", 12)
			if elegida >= 0:
				b.disabled = true
				if oi == correcta:
					b.modulate = Color(0.55, 1.0, 0.6)
				elif oi == elegida:
					b.modulate = Color(1.0, 0.55, 0.5)
			b.pressed.connect(func():
				respuestas[qi] = oi
				_mostrar_diario(_sel_diario))
			vbox.add_child(b)
		if elegida >= 0:
			var ok := elegida == correcta
			vbox.add_child(_label(Idioma.t("¡Correcto!") if ok else Idioma.t("Casi: la respuesta correcta está en verde."), 12,
					Color(0.55, 1.0, 0.6) if ok else Color(1.0, 0.7, 0.5)))


# --- Contenido -------------------------------------------------------------------

func _items_maquinas() -> Array:
	var orden := ["fotovoltaica", "o2", "escudo", "comunicaciones", "invernadero", "rover",
			"escritorio", "comedor", "cama", "cama_hospital", "roomba"]
	var claves: Array = []
	for c in orden:
		if _texturas.has(c):
			claves.append(c)
	for c in _texturas.keys():
		if not claves.has(c) and TextosAyuda.MAQUINAS.has(c):
			claves.append(c)
	if claves.is_empty():
		claves = orden
	var lista: Array = []
	for c in claves:
		var datos: Array = TextosAyuda.MAQUINAS.get(c, TextosAyuda.MAQUINAS["otras"])
		lista.append({"titulo": datos[0], "texto": datos[1], "textura": _texturas.get(c)})
	return lista


func _items_mecanicas() -> Array:
	var lista: Array = []
	for m in TextosAyuda.MECANICAS:
		lista.append({"titulo": m["titulo"], "texto": m["texto"],
				"textura": _texturas.get(String(m.get("icono", "")))})
	return lista


func _items_astronautas() -> Array:
	var lista: Array = []
	for a in TextosAyuda.ASTRONAUTAS:
		var nombre := String(a["nombre"])
		var item: Dictionary = a.duplicate()
		item.merge(Afinidades.describir(nombre))
		item["textura"] = _textura_cabeza(nombre)
		lista.append(item)
	return lista


## Cabeza del astronauta (cuadro de la animación "Cabezas", en el orden de Personaje.Cabeza).
func _textura_cabeza(nombre: String) -> Texture2D:
	var indice := -1
	for c in Personaje.NOMBRES:
		if Personaje.NOMBRES[c] == nombre:
			indice = int(c)
	if indice < 0 or not CUADROS_PERSONAJE.has_animation(&"Cabezas") \
			or indice >= CUADROS_PERSONAJE.get_frame_count(&"Cabezas"):
		return null
	return CUADROS_PERSONAJE.get_frame_texture(&"Cabezas", indice)


## Busca en el mapa una máquina o mueble de cada tipo para usar su dibujo.
func _juntar_texturas() -> void:
	for m in get_tree().get_nodes_in_group("maquinas"):
		if m is Maquina:
			_guardar_textura(String(m.tipo_ajuste()), m)
	for c in get_tree().get_nodes_in_group("comedores"):
		_guardar_textura("comedor", c)
	for c in get_tree().get_nodes_in_group("camas"):
		_guardar_textura("cama_hospital" if bool(c.get("solo_desmayados")) else "cama", c)
	for r in get_tree().get_nodes_in_group("roombas"):
		_guardar_textura("roomba", r)
	# Sin mapa (por ejemplo, desde el menú): se arman las escenas un momento para sacar el dibujo
	for datos in ESCENAS_DIBUJOS:
		if _texturas.has(datos[0]) or not ResourceLoader.exists(datos[1]):
			continue
		var escena := load(datos[1]) as PackedScene
		if escena == null:
			continue
		var nodo := escena.instantiate()
		_guardar_textura(datos[0], nodo)
		nodo.free()


func _guardar_textura(clave: String, nodo: Node) -> void:
	if clave == "" or _texturas.has(clave):
		return
	var tex := _textura_de(nodo)
	if tex != null:
		_texturas[clave] = tex


## El dibujo del primer sprite visible del nodo (con su región o cuadro, si tiene).
func _textura_de(nodo: Node) -> Texture2D:
	var candidatos: Array = []
	for h in nodo.get_children():
		if h is Sprite2D or h is AnimatedSprite2D:
			candidatos.append(h)
	candidatos.sort_custom(func(a, b): return a.visible and not b.visible)
	for s in candidatos:
		if s is Sprite2D:
			var sp := s as Sprite2D
			if sp.texture == null:
				continue
			if sp.region_enabled:
				var at := AtlasTexture.new()
				at.atlas = sp.texture
				at.region = sp.region_rect
				return at
			if sp.hframes > 1 or sp.vframes > 1:
				var tam := sp.texture.get_size() / Vector2(sp.hframes, sp.vframes)
				var at := AtlasTexture.new()
				at.atlas = sp.texture
				at.region = Rect2(Vector2(sp.frame_coords) * tam, tam)
				return at
			return sp.texture
		var an := s as AnimatedSprite2D
		if an.sprite_frames != null and an.sprite_frames.has_animation(an.animation) \
				and an.sprite_frames.get_frame_count(an.animation) > 0:
			return an.sprite_frames.get_frame_texture(an.animation, 0)
	return null


func _imagen(ruta: String) -> Texture2D:
	if ruta == "":
		return null
	if ResourceLoader.exists(ruta):
		return load(ruta)
	# Si el editor todavía no la importó, se lee el archivo directo
	var img := Image.load_from_file(ProjectSettings.globalize_path(ruta))
	return ImageTexture.create_from_image(img) if img != null else null


func _texto_lista(m: Dictionary) -> String:
	if not m["desbloqueada"]:
		return "???"
	if _es_global():
		return String(m["titulo"])
	if diario.esta_completa(m):
		return Idioma.t("%s\n(completa)") % String(m["titulo"])
	if diario.activa() == m:
		return Idioma.t("%s\n(investigando %d%%)") % [String(m["titulo"]), roundi(100.0 * diario.fraccion(m))]
	return Idioma.t("%s\n(en espera)") % String(m["titulo"])


func _texto_estado(m: Dictionary) -> String:
	if _es_global():
		return Idioma.t("Completada en una partida ganada.")
	if diario.esta_completa(m):
		if diario.has_method("reporte_respondido") and diario.reporte_respondido(m):
			return Idioma.t("Investigación completa y reporte respondido.")
		return Idioma.t("Investigación completa. ¡Respondé el reporte!")
	if diario.activa() == m:
		var pct := roundi(100.0 * diario.fraccion(m))
		if pct == 0:
			return Idioma.t("Lista para investigar: mandá a un astronauta al escritorio.")
		return Idioma.t("Investigando en el escritorio: %d%%") % pct
	var act: Dictionary = diario.activa()
	return Idioma.t("En espera: primero se termina \"%s\".") % String(act.get("titulo", ""))


func _parrafos_visibles(m: Dictionary) -> int:
	var n: int = (m.get("texto", []) as Array).size()
	return ceili(diario.fraccion(m) * n - 0.0001)


## Cambia cuando hay que rearmar la pantalla del diario (no con cada décima de progreso).
func _firma() -> String:
	if diario == null:
		return ""
	var partes: PackedStringArray = []
	for m in diario.misiones:
		partes.append("%s%d%d%d" % [m["id"], int(m["desbloqueada"]), _parrafos_visibles(m),
				int(diario.esta_completa(m))])
	partes.append(String(diario.activa().get("id", "")))
	return "|".join(partes)


# --- Ayudas de interfaz ----------------------------------------------------------

func _estilo(borde: Color) -> StyleBoxFlat:
	var e := StyleBoxFlat.new()
	e.bg_color = Color(0.11, 0.13, 0.18, 0.96)
	e.set_corner_radius_all(6)
	e.set_border_width_all(2)
	e.border_color = borde
	e.content_margin_left = 8
	e.content_margin_right = 8
	e.content_margin_top = 6
	e.content_margin_bottom = 6
	return e


func _label(texto: String, tam: int, color: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tam)
	l.modulate = color
	return l


func _parrafo(texto: String, color: Color) -> Label:
	var l := _label(texto, 14, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200, 0)
	return l


func _boton(texto: String, tam: Vector2) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = tam
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # dibujos pixelados nítidos
	return b


## Carpeta amarilla dibujada por código.
func _icono_carpeta() -> ImageTexture:
	var img := Image.create(32, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var oscuro := Color(0.8, 0.6, 0.15)
	var claro := Color(1.0, 0.82, 0.35)
	img.fill_rect(Rect2i(1, 2, 12, 4), oscuro)    # pestaña
	img.fill_rect(Rect2i(1, 5, 30, 18), oscuro)   # atrás
	img.fill_rect(Rect2i(2, 8, 28, 14), claro)    # frente
	return ImageTexture.create_from_image(img)
