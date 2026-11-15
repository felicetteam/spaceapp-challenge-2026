extends Node
## Fin de la partida.
## - Victoria: las investigaciones del diario completas y con sus reportes respondidos.
##   Se guardan en el diario global (Base/diario_global.gd).
## - Derrota: los tres astronautas inconscientes por salud 0 (no por sueño) a la vez.
## Primero sale un aviso con "Continuar"; después, la pantalla de resumen sobre el fondo
## assets/sprites/Fondo Gana_pierde.png, con la tripulación, las investigaciones y el tiempo.

const DiarioGlobal := preload("res://Base/diario_global.gd")
const RUTA_FONDO := "res://assets/sprites/Fondo Gana_pierde.png"
const FUENTE_TITULO := preload("res://assets/fonts/Klaxon-Crunchy.otf")
const ESCENA_MENU := "res://Pantallas/Menu/MenuInicio.tscn"
const ESCENA_SELECCION := "res://Pantallas/Seleccion/MenuSeleccion.tscn"

var hud: Node
var diario: Node
var recursos: Recursos
var tripulacion: Array[Personaje] = []

var _terminado := false
var _t_revisar := 0.0
## Segundos reales jugados (sin contar pausas; con el tiempo acelerado cuenta lo real).
var _segundos_jugados := 0.0
var _capa: CanvasLayer


func _process(delta: float) -> void:
	if _terminado:
		return
	if Engine.time_scale > 0.0:
		_segundos_jugados += delta / Engine.time_scale
	_t_revisar -= delta
	if _t_revisar > 0.0:
		return
	_t_revisar = 0.5
	if diario != null and diario.todo_completo():
		_terminar(true)
	elif _todos_inconscientes():
		_terminar(false)


func _todos_inconscientes() -> bool:
	if tripulacion.is_empty():
		return false
	for p in tripulacion:
		if not is_instance_valid(p):
			continue
		# Dormido de cansancio no cuenta: solo la salud en 0
		if not p.desmayado or p.dormido_agotado:
			return false
	return true


func _terminar(victoria: bool) -> void:
	_terminado = true
	if victoria and diario != null:
		var ids: Array = []
		for m in diario.misiones:
			if diario.esta_completa(m):
				ids.append(String(m["id"]))
		DiarioGlobal.guardar_victoria(ids)
	if hud != null and hud.has_method("cerrar_info"):
		hud.cerrar_info()
	get_tree().paused = true
	Engine.time_scale = 1.0
	_capa = CanvasLayer.new()
	_capa.layer = 50
	_capa.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_capa)
	_mostrar_aviso(victoria)


# --- Aviso ---------------------------------------------------------------------------

func _mostrar_aviso(victoria: bool) -> void:
	var fondo := _pantalla_completa(Color(0, 0, 0, 0.6))
	var centro := CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fondo.add_child(centro)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	panel.add_theme_stylebox_override("panel", _estilo(Color(0.45, 1.0, 0.55) if victoria else Color(1.0, 0.4, 0.35)))
	centro.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	var titulo := _label("¡MISIÓN CUMPLIDA!" if victoria else "MISIÓN FALLIDA", 26,
			Color(0.55, 1.0, 0.6) if victoria else Color(1.0, 0.5, 0.45))
	titulo.add_theme_font_override("font", FUENTE_TITULO)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(titulo)
	var texto := "¡Completaron todas las investigaciones! Marte ya no tiene tantos secretos." if victoria \
			else "Toda la tripulación quedó inconsciente. La misión no pudo seguir."
	vbox.add_child(_parrafo(texto, 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	var b := _boton("Continuar")
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func():
		fondo.queue_free()
		_mostrar_resumen(victoria))
	vbox.add_child(b)


# --- Resumen -------------------------------------------------------------------------

func _mostrar_resumen(victoria: bool) -> void:
	var raiz := _pantalla_completa(Color(0.03, 0.04, 0.12, 1.0))
	var tex := _imagen(RUTA_FONDO)
	if tex != null:
		var img := TextureRect.new()
		img.texture = tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		raiz.add_child(img)
	var centro := CenterContainer.new()
	centro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(centro)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	var estilo := _estilo(Color(0.45, 1.0, 0.55) if victoria else Color(1.0, 0.4, 0.35))
	estilo.bg_color = Color(0.05, 0.06, 0.12, 0.85)
	panel.add_theme_stylebox_override("panel", estilo)
	centro.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var titulo := _label("¡VICTORIA!" if victoria else "DERROTA", 34,
			Color(0.55, 1.0, 0.6) if victoria else Color(1.0, 0.5, 0.45))
	titulo.add_theme_font_override("font", FUENTE_TITULO)
	titulo.add_theme_color_override("font_outline_color", Color.BLACK)
	titulo.add_theme_constant_override("outline_size", 6)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(titulo)

	# Tripulación
	var nombres: PackedStringArray = []
	for p in tripulacion:
		if is_instance_valid(p):
			nombres.append(p.obtener_nombre())
	vbox.add_child(_seccion("Tripulación", ", ".join(nombres)))

	# Investigaciones
	var completas: PackedStringArray = []
	var desbloqueadas := 0
	var total := 0
	if diario != null:
		total = diario.misiones.size()
		for m in diario.misiones:
			if m["desbloqueada"]:
				desbloqueadas += 1
			if diario.esta_completa(m):
				completas.append("✔ " + String(m["titulo"]))
	var titulo_inv := "Investigaciones completadas (%d de %d)" % [completas.size(), total]
	var detalle := "\n".join(completas) if not completas.is_empty() else "Ninguna"
	if not victoria:
		detalle += "\nExploraciones hechas: %d de %d" % [desbloqueadas, total]
		var activa: Dictionary = diario.activa() if diario != null else {}
		if not activa.is_empty():
			detalle += "\nEn curso: %s (%d%%)" % [String(activa["titulo"]), roundi(100.0 * diario.fraccion(activa))]
	vbox.add_child(_seccion(titulo_inv, detalle))

	# Tiempo
	var s := int(_segundos_jugados)
	var tiempo := "%d:%02d minutos de juego" % [s / 60, s % 60]
	if recursos != null:
		tiempo = "%s (%s)" % [recursos.texto_reloj(), tiempo]
	vbox.add_child(_seccion("Tiempo" if victoria else "Hasta dónde llegaron", tiempo))
	if victoria:
		vbox.add_child(_parrafo("Las investigaciones quedaron guardadas en el diario global (Ver Diario, en el menú).",
				12, Color(0.6, 0.85, 1.0), HORIZONTAL_ALIGNMENT_CENTER))

	var botones := HBoxContainer.new()
	botones.alignment = BoxContainer.ALIGNMENT_CENTER
	botones.add_theme_constant_override("separation", 16)
	vbox.add_child(botones)
	var menu := _boton("Volver al menú")
	menu.pressed.connect(func(): _cambiar_escena(ESCENA_MENU))
	botones.add_child(menu)
	var otra := _boton("Jugar de nuevo")
	otra.pressed.connect(func(): _cambiar_escena(ESCENA_SELECCION))
	botones.add_child(otra)


func _cambiar_escena(ruta: String) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(ruta)


# --- Ayudas --------------------------------------------------------------------------

func _pantalla_completa(color: Color) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_capa.add_child(c)
	return c


func _seccion(titulo: String, texto: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.add_child(_label(titulo, 15, Color(1.0, 0.85, 0.45)))
	v.add_child(_parrafo(texto, 14, Color.WHITE))
	return v


func _estilo(borde: Color) -> StyleBoxFlat:
	var e := StyleBoxFlat.new()
	e.bg_color = Color(0.11, 0.13, 0.18, 0.96)
	e.set_corner_radius_all(8)
	e.set_border_width_all(3)
	e.border_color = borde
	e.content_margin_left = 24
	e.content_margin_right = 24
	e.content_margin_top = 18
	e.content_margin_bottom = 18
	return e


func _label(texto: String, tam: int, color: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	return l


func _parrafo(texto: String, tam: int, color: Color, alineacion := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := _label(texto, tam, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = alineacion
	l.custom_minimum_size = Vector2(380, 0)
	return l


func _boton(texto: String) -> Button:
	var b := Button.new()
	b.text = texto
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(200, 42)
	b.add_theme_font_size_override("font_size", 16)
	return b


func _imagen(ruta: String) -> Texture2D:
	if ResourceLoader.exists(ruta):
		return load(ruta)
	if not FileAccess.file_exists(ruta):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(ruta))
	return ImageTexture.create_from_image(img) if img != null else null
