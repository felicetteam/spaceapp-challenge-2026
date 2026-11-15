extends CanvasLayer
## Columna a la izquierda: reloj y recursos globales, tarjetas de la tripulación y, debajo,
## el panel de mantenimiento. A la derecha, las alertas.
## Los recursos, los desgastes y las alertas solo se ven mientras las comunicaciones funcionan.

signal astronauta_clicado(personaje: Personaje)
signal maquina_clicada(maquina: Maquina)
## Pide centrar la cámara en algo (una máquina con problemas, el objeto de una alerta).
signal enfocar(objetivo: Node2D)

const ANCHO_TARJETA := 150

@onready var contenedor: VBoxContainer = $Columna/ContenedorTripulacion
@onready var titulo_mantenimiento: Label = $Columna/TituloMantenimiento
@onready var contenedor_maquinas: VBoxContainer = $Columna/ContenedorMaquinas

const MAX_ALERTAS := 5
const DURACION_ALERTA := 8.0

var _tarjetas := {} # Personaje -> Dictionary con referencias a sus nodos UI
var _tarjetas_maquinas := {} # Maquina -> Dictionary
var _recursos: Recursos

# Nodos que se crean por código
var _panel_recursos: PanelContainer
var _lbl_reloj: Label
var _caja_barras: VBoxContainer
var _barras_recursos := {} # nombre -> {"barra", "estilo", "lbl"}
var _aviso_comunicaciones: Label
var _scroll_maquinas: ScrollContainer
var _alertas: VBoxContainer
var _maquinas: Array[Maquina] = []
var _boton_atencion: Button
var _idx_atencion := -1

func _ready() -> void:
	var columna := $Columna as VBoxContainer

	# Panel de recursos arriba de todo
	_panel_recursos = _crear_panel(_estilo_panel(), Vector2(ANCHO_TARJETA, 0))
	_panel_recursos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vbox := _vbox(3)
	_panel_recursos.add_child(vbox)
	_lbl_reloj = _label("Sol 1 · 00:00", 11)
	vbox.add_child(_lbl_reloj)
	_caja_barras = _vbox(3)
	vbox.add_child(_caja_barras)
	_agregar_barra_recurso("energia", "Energía", Color(0.95, 0.8, 0.2))
	_agregar_barra_recurso("oxigeno", "Oxígeno", Color(0.35, 0.75, 1.0))
	_agregar_barra_recurso("radiacion", "Radiación", Color(0.75, 0.4, 0.95))
	_aviso_comunicaciones = _label("Sin comunicaciones:\nno se ven recursos ni desgastes", 9)
	_aviso_comunicaciones.modulate = Color(1.0, 0.55, 0.45)
	vbox.add_child(_aviso_comunicaciones)
	columna.add_child(_panel_recursos)
	columna.move_child(_panel_recursos, 0)

	# Mantenimiento: en lugar de una lista larga, un contador de máquinas con problemas.
	# Cada clic centra la cámara en la siguiente, de la más urgente a la menos.
	# (Los bordes amarillo/rojo y las barras flotantes muestran el detalle en el mapa.)
	_boton_atencion = Button.new()
	_boton_atencion.focus_mode = Control.FOCUS_NONE  # que no se quede con las flechas del teclado
	_boton_atencion.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_boton_atencion.custom_minimum_size = Vector2(ANCHO_TARJETA, 0)
	_boton_atencion.add_theme_font_size_override("font_size", 10)
	_boton_atencion.add_theme_stylebox_override("normal", _estilo_panel())
	_boton_atencion.add_theme_stylebox_override("hover", _estilo_panel())
	_boton_atencion.add_theme_stylebox_override("pressed", _estilo_panel())
	_boton_atencion.add_theme_stylebox_override("disabled", _estilo_panel())
	_boton_atencion.tooltip_text = "Clic: ir a la siguiente máquina con problemas"
	_boton_atencion.pressed.connect(_ir_a_siguiente_maquina)
	columna.add_child(_boton_atencion)
	columna.move_child(_boton_atencion, titulo_mantenimiento.get_index())
	titulo_mantenimiento.visible = false

	# (La lista detallada de máquinas ya no se muestra)
	_scroll_maquinas = ScrollContainer.new()
	_scroll_maquinas.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_maquinas.mouse_filter = Control.MOUSE_FILTER_PASS
	var indice := contenedor_maquinas.get_index()
	columna.remove_child(contenedor_maquinas)
	_scroll_maquinas.add_child(contenedor_maquinas)
	contenedor_maquinas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columna.add_child(_scroll_maquinas)
	columna.move_child(_scroll_maquinas, indice)

	# Alertas arriba a la derecha
	_alertas = VBoxContainer.new()
	_alertas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alertas.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_alertas.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_alertas.offset_left = -232
	_alertas.offset_right = -12
	_alertas.offset_top = 12
	_alertas.add_theme_constant_override("separation", 4)
	add_child(_alertas)

func _process(_delta: float) -> void:
	# El scroll de máquinas ocupa lo que haga falta, sin pasarse del borde de la pantalla
	if _scroll_maquinas == null:
		return
	var alto_contenido := contenedor_maquinas.get_combined_minimum_size().y
	var disponible := get_viewport().get_visible_rect().size.y - _scroll_maquinas.global_position.y - 12.0
	_scroll_maquinas.custom_minimum_size.y = clampf(alto_contenido, 0.0, maxf(disponible, 60.0))

func inicializar(tripulacion: Array[Personaje], maquinas: Array[Maquina] = [], recursos: Recursos = null) -> void:
	_recursos = recursos
	if recursos != null:
		recursos.actualizado.connect(_on_recursos_actualizados)
		recursos.alerta.connect(agregar_alerta)
		_on_recursos_actualizados(recursos)

	for hijo in contenedor.get_children():
		hijo.queue_free()
	_tarjetas.clear()

	for i in tripulacion.size():
		var astro := tripulacion[i]
		var panel := _crear_tarjeta(astro, i + 1)
		contenedor.add_child(panel)
		astro.estado_actualizado.connect(_on_estado_actualizado)
		_on_estado_actualizado(astro)

	_maquinas.clear()
	for m in maquinas:
		if m.tiene_desgaste:  # el escritorio y similares no cuentan
			_maquinas.append(m)

func marcar_activo(activo: Personaje) -> void:
	for astro in _tarjetas.keys():
		var estilo: StyleBoxFlat = _tarjetas[astro]["estilo_panel"]
		if astro == activo:
			estilo.border_color = Color(0.25, 1.0, 0.35) # Verde, igual que el borde del personaje
			estilo.set_border_width_all(2)
		else:
			estilo.border_color = Color(0.25, 0.28, 0.35)
			estilo.set_border_width_all(1)

# --- Tripulación -------------------------------------------------------------

func _crear_tarjeta(astro: Personaje, numero: int) -> PanelContainer:
	var estilo_panel := _estilo_panel()
	var panel := _crear_panel(estilo_panel, Vector2(ANCHO_TARJETA, 78))

	# Permite seleccionar al astronauta haciendo clic en su tarjeta
	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			astronauta_clicado.emit(astro)
	)

	var vbox := _vbox(3)
	panel.add_child(vbox)

	# Fila superior: Nombre + Estado
	var fila_top := _hbox(0)
	vbox.add_child(fila_top)

	var lbl_nombre := _label("[%d] %s" % [numero, astro.obtener_nombre()], 11)
	lbl_nombre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila_top.add_child(lbl_nombre)

	var lbl_estado := _label("Bien", 10)
	fila_top.add_child(lbl_estado)

	# Barra de Salud
	var bar_salud := _crear_barra(10, Color(0.2, 0.85, 0.35))
	vbox.add_child(bar_salud)

	# Mini-barras: Comida (izquierda) y Sueño/Descanso (derecha)
	var fila_sub := _hbox(6)
	vbox.add_child(fila_sub)

	var col_comida := _crear_sub_indicador("Comida", Color(0.95, 0.6, 0.2))
	var col_sueno := _crear_sub_indicador("Energía", Color(0.35, 0.7, 0.95))
	fila_sub.add_child(col_comida["box"])
	fila_sub.add_child(col_sueno["box"])

	_tarjetas[astro] = {
		"estilo_panel": estilo_panel,
		"lbl_estado": lbl_estado,
		"bar_salud": bar_salud,
		"estilo_salud": bar_salud.get_theme_stylebox("fill"),
		"bar_comida": col_comida["barra"],
		"bar_sueno": col_sueno["barra"]
	}
	return panel

func _on_estado_actualizado(astro: Personaje) -> void:
	if not _tarjetas.has(astro):
		return
	var ui: Dictionary = _tarjetas[astro]
	ui["bar_salud"].value = astro.salud
	ui["bar_comida"].value = 100.0 - astro.hambre
	ui["bar_sueno"].value = 100.0 - astro.sueno
	ui["lbl_estado"].text = astro.estado_alerta

	var fill_salud: StyleBoxFlat = ui["estilo_salud"]
	if astro.salud > 60.0:
		fill_salud.bg_color = Color(0.2, 0.85, 0.35)
		ui["lbl_estado"].modulate = Color(0.6, 0.95, 0.65)
	elif astro.salud > 30.0:
		fill_salud.bg_color = Color(0.95, 0.75, 0.15)
		ui["lbl_estado"].modulate = Color(1.0, 0.85, 0.35)
	else:
		fill_salud.bg_color = Color(0.9, 0.2, 0.2)
		ui["lbl_estado"].modulate = Color(1.0, 0.4, 0.4)

# --- Mantenimiento -----------------------------------------------------------

func _crear_tarjeta_maquina(m: Maquina) -> PanelContainer:
	var estilo_panel := _estilo_panel()
	var panel := _crear_panel(estilo_panel, Vector2(ANCHO_TARJETA - 10, 0))
	panel.tooltip_text = "Clic: mandar al astronauta seleccionado a trabajar acá"
	# PASS: la rueda del mouse sigue llegando al scroll
	panel.mouse_filter = Control.MOUSE_FILTER_PASS

	# Clic en la tarjeta: el astronauta seleccionado va a trabajar en esa máquina
	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			maquina_clicada.emit(m)
			panel.accept_event()
	)

	var vbox := _vbox(2)
	panel.add_child(vbox)

	var fila := _hbox(0)
	vbox.add_child(fila)
	var lbl_nombre := _label(m.nombre_maquina, 11)
	lbl_nombre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(lbl_nombre)
	var lbl_porcentaje := _label("100%", 10)
	fila.add_child(lbl_porcentaje)

	var barra := _crear_barra(6, m.color_estado())
	vbox.add_child(barra)

	var lbl_detalle := _label("", 9)
	lbl_detalle.modulate = Color(0.8, 0.85, 0.9)
	vbox.add_child(lbl_detalle)

	_tarjetas_maquinas[m] = {
		"estilo_panel": estilo_panel,
		"barra": barra,
		"estilo_barra": barra.get_theme_stylebox("fill"),
		"lbl_porcentaje": lbl_porcentaje,
		"lbl_detalle": lbl_detalle
	}
	return panel

func _on_maquina_actualizada(m: Maquina) -> void:
	if not _tarjetas_maquinas.has(m):
		return
	var ui: Dictionary = _tarjetas_maquinas[m]
	ui["barra"].value = m.mantenimiento
	ui["lbl_porcentaje"].text = "%d%%" % roundi(m.mantenimiento)
	var color := m.color_estado()
	(ui["estilo_barra"] as StyleBoxFlat).bg_color = color
	ui["lbl_porcentaje"].modulate = color.lightened(0.3)

	var detalle := m.obtener_estado()
	if not m.trabajadores.is_empty():
		var nombres: PackedStringArray = []
		for p in m.trabajadores:
			nombres.append(p.obtener_nombre())
		detalle += " · " + ", ".join(nombres)
	ui["lbl_detalle"].text = detalle

	# Borde rojo cuando está crítica o fuera de servicio
	var estilo: StyleBoxFlat = ui["estilo_panel"]
	estilo.border_color = Color(0.9, 0.25, 0.25) if m.mantenimiento <= 30.0 else Color(0.25, 0.28, 0.35)

# --- Recursos y alertas ------------------------------------------------------

func _agregar_barra_recurso(clave: String, titulo: String, color: Color) -> void:
	var fila := _hbox(0)
	var lbl := _label(titulo, 9)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fila.add_child(lbl)
	var lbl_valor := _label("100%", 9)
	fila.add_child(lbl_valor)
	_caja_barras.add_child(fila)
	var barra := _crear_barra(6, color)
	_caja_barras.add_child(barra)
	_barras_recursos[clave] = {"barra": barra, "lbl": lbl_valor}

func _on_recursos_actualizados(r: Recursos) -> void:
	_lbl_reloj.text = r.texto_reloj()
	var visibles := r.comunicaciones_activas
	_caja_barras.visible = visibles
	_aviso_comunicaciones.visible = not visibles
	titulo_mantenimiento.visible = false
	_scroll_maquinas.visible = false
	_boton_atencion.visible = visibles and not _maquinas.is_empty()
	_actualizar_boton_atencion()
	_alertas.visible = visibles
	if not visibles:
		return
	for clave in ["energia", "oxigeno", "radiacion"]:
		var valor: float = r.get(clave)
		var ui: Dictionary = _barras_recursos[clave]
		ui["barra"].value = valor
		ui["lbl"].text = "%d%%" % roundi(valor)
	var lbl_rad: Label = _barras_recursos["radiacion"]["lbl"]
	lbl_rad.modulate = Color(1.0, 0.4, 0.4) if r.radiacion > 80.0 else Color.WHITE

## Agrega un aviso arriba a la derecha que desaparece solo. nivel: 0 info, 1 aviso, 2 peligro.
## Si la alerta tiene un objetivo (una máquina, un astronauta), un clic en ella centra la cámara ahí.
func agregar_alerta(texto: String, nivel: int = 1, objetivo: Node2D = null) -> void:
	var estilo := _estilo_panel()
	var colores := [Color(0.3, 0.6, 0.9), Color(0.95, 0.75, 0.15), Color(0.9, 0.25, 0.25)]
	estilo.border_color = colores[clampi(nivel, 0, 2)]
	estilo.set_border_width_all(2)
	var panel := _crear_panel(estilo, Vector2(220, 0))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if objetivo != null:
		texto += "  (ver)"
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.tooltip_text = "Clic: centrar la cámara"
		panel.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT \
					and is_instance_valid(objetivo):
				enfocar.emit(objetivo)
				panel.accept_event()
		)
	var lbl := _label(texto, 10)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(lbl)
	_alertas.add_child(panel)
	while _alertas.get_child_count() > MAX_ALERTAS:
		var vieja := _alertas.get_child(0)
		_alertas.remove_child(vieja)
		vieja.queue_free()
	var tween := panel.create_tween()
	tween.tween_interval(DURACION_ALERTA)
	tween.tween_property(panel, "modulate:a", 0.0, 0.6)
	tween.tween_callback(panel.queue_free)

# --- Máquinas con problemas --------------------------------------------------

## Las máquinas que necesitan atención (con borde de estado), de la más urgente a la menos.
func _maquinas_con_problemas() -> Array[Maquina]:
	var lista: Array[Maquina] = []
	for m in _maquinas:
		if is_instance_valid(m) and m.mantenimiento < m.umbral_borde:
			lista.append(m)
	lista.sort_custom(func(a, b): return a.mantenimiento < b.mantenimiento)
	return lista

func _actualizar_boton_atencion() -> void:
	var lista := _maquinas_con_problemas()
	if lista.is_empty():
		_boton_atencion.text = "Máquinas: todo en orden"
		_boton_atencion.disabled = true
		_boton_atencion.modulate = Color(0.6, 0.95, 0.65)
		return
	_boton_atencion.disabled = false
	var peor := lista[0]
	var n := lista.size()
	_boton_atencion.text = "%d %s atención\nPeor: %s %d%% (clic para ver)" % [
			n, "máquina necesita" if n == 1 else "máquinas necesitan",
			peor.nombre_maquina, roundi(peor.mantenimiento)]
	_boton_atencion.modulate = Color(1.0, 0.45, 0.4) if peor.mantenimiento <= peor.umbral_critico \
			else Color(1.0, 0.85, 0.35)

func _ir_a_siguiente_maquina() -> void:
	var lista := _maquinas_con_problemas()
	if lista.is_empty():
		return
	_idx_atencion = (_idx_atencion + 1) % lista.size()
	enfocar.emit(lista[_idx_atencion])

# --- Helpers de UI -----------------------------------------------------------

func _estilo_panel() -> StyleBoxFlat:
	var e := StyleBoxFlat.new()
	e.bg_color = Color(0.11, 0.13, 0.18, 0.88)
	e.set_corner_radius_all(6)
	e.set_border_width_all(1)
	e.border_color = Color(0.25, 0.28, 0.35)
	e.content_margin_left = 8
	e.content_margin_right = 8
	e.content_margin_top = 6
	e.content_margin_bottom = 6
	return e

func _crear_panel(estilo: StyleBoxFlat, tam_min: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = tam_min
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", estilo)
	return panel

## Los hijos ignoran el mouse para que el clic llegue al panel.
func _vbox(separacion: int) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_constant_override("separation", separacion)
	return b

func _hbox(separacion: int) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_constant_override("separation", separacion)
	return b

func _label(texto: String, tam_fuente: int) -> Label:
	var l := Label.new()
	l.text = texto
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", tam_fuente)
	return l

func _crear_barra(alto: int, color_relleno: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(0, alto)
	pb.show_percentage = false
	pb.value = 100.0
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.07, 0.1)
	bg.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = color_relleno
	fill.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("fill", fill)
	return pb

func _crear_sub_indicador(titulo: String, color: Color) -> Dictionary:
	var box := _vbox(1)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := _label(titulo, 9)
	lbl.modulate = Color(0.8, 0.85, 0.9)
	box.add_child(lbl)

	var bar := _crear_barra(5, color)
	box.add_child(bar)
	return {"box": box, "barra": bar}
