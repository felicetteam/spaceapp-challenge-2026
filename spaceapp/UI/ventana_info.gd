extends Control
## Ventana de Información (botón junto a pausa/play). Tiene dos carpetas:
## - Base: a la izquierda "Máquinas" y "Mecánicas"; a la derecha una grilla con el dibujo de
##   cada máquina o mueble (o solo el nombre). Al tocar uno se ve su explicación del tutorial.
## - Diario: a la izquierda las investigaciones de la partida (??? si todavía no se
##   desbloquearon); a la derecha la elegida, con su barra de progreso, lo que ya se descubrió
##   y, al completarla, el reporte.
## El juego no se pausa (así se ve avanzar la investigación). Todas las pantallas se cierran
## con "Cerrar" (o Esc).

const TextosAyuda := preload("res://Base/textos_ayuda.gd")

var diario: Node = null

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
	_titulo = _label("Información", 18, Color(0.6, 0.9, 1.0))
	_titulo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cabecera.add_child(_titulo)
	_boton_volver = _boton("Volver", Vector2(90, 30))
	_boton_volver.pressed.connect(func():
		if _al_volver.is_valid():
			_al_volver.call())
	cabecera.add_child(_boton_volver)
	var cerrar := _boton("Cerrar", Vector2(90, 30))
	cerrar.pressed.connect(queue_free)
	cabecera.add_child(cerrar)
	vbox.add_child(HSeparator.new())

	_cuerpo = MarginContainer.new()
	_cuerpo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_cuerpo)

	_juntar_texturas()
	_mostrar_carpetas()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()


func _process(delta: float) -> void:
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
	_limpiar("Información", Callable())
	var centro := CenterContainer.new()
	_cuerpo.add_child(centro)
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 60)
	centro.add_child(fila)
	for datos in [["Base", "Máquinas y mecánicas", _mostrar_base.bind("maquinas")],
			["Diario", "Investigaciones de la misión", _mostrar_diario.bind(-1)]]:
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
	_limpiar("Base", _mostrar_carpetas)
	var cols := _dos_columnas()
	var izq: VBoxContainer = cols[0]
	var der: PanelContainer = cols[1]
	for datos in [["maquinas", "Máquinas"], ["mecanicas", "Mecánicas"]]:
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
	for item in (_items_maquinas() if seccion == "maquinas" else _items_mecanicas()):
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
	_limpiar("Base · " + String(item["titulo"]), _mostrar_base.bind(seccion))
	var centro := CenterContainer.new()
	_cuerpo.add_child(centro)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(560, 0)
	vbox.add_theme_constant_override("separation", 14)
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


func _mostrar_diario(seleccion: int) -> void:
	_limpiar("Diario", _mostrar_carpetas)
	if diario == null or diario.misiones.is_empty():
		_cuerpo.add_child(_label("El diario está vacío.", 15, Color.WHITE))
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
	for i in diario.misiones.size():
		var m: Dictionary = diario.misiones[i]
		var b := _boton(_texto_lista(m), Vector2(0, 58))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 13)
		b.toggle_mode = true
		b.button_pressed = i == _sel_diario
		b.pressed.connect(_mostrar_diario.bind(i))
		izq.add_child(b)

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
		var txt := "Todavía no se desbloqueó. Salí a explorar con el rover: al volver de cada exploración, su investigación aparece en el diario."
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
			vbox.add_child(_parrafo("· · · (seguí investigando para descubrirlo)", Color(0.55, 0.58, 0.65)))
	if diario.esta_completa(m):
		_agregar_reporte(vbox, m)


func _agregar_reporte(vbox: VBoxContainer, m: Dictionary) -> void:
	vbox.add_child(HSeparator.new())
	vbox.add_child(_label("Reporte", 17, Color(0.6, 0.9, 1.0)))
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
			vbox.add_child(_label("¡Correcto!" if ok else "Casi: la respuesta correcta está en verde.", 12,
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
	if diario.esta_completa(m):
		return "%s\n(completa)" % String(m["titulo"])
	if diario.activa() == m:
		return "%s\n(investigando %d%%)" % [String(m["titulo"]), roundi(100.0 * diario.fraccion(m))]
	return "%s\n(en espera)" % String(m["titulo"])


func _texto_estado(m: Dictionary) -> String:
	if diario.esta_completa(m):
		return "Investigación completa. ¡Respondé el reporte!"
	if diario.activa() == m:
		var pct := roundi(100.0 * diario.fraccion(m))
		if pct == 0:
			return "Lista para investigar: mandá a un astronauta al escritorio."
		return "Investigando en el escritorio: %d%%" % pct
	var act: Dictionary = diario.activa()
	return "En espera: primero se termina \"%s\"." % String(act.get("titulo", ""))


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
