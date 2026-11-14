extends CanvasLayer

signal astronauta_clicado(personaje: Personaje)

@onready var contenedor: HBoxContainer = $ContenedorTripulacion

var _tarjetas := {} # Personaje -> Dictionary con referencias a sus nodos UI

func inicializar(tripulacion: Array[Personaje]) -> void:
	for hijo in contenedor.get_children():
		hijo.queue_free()
	_tarjetas.clear()

	for i in tripulacion.size():
		var astro := tripulacion[i]
		var panel := _crear_tarjeta(astro, i + 1)
		contenedor.add_child(panel)
		astro.estado_actualizado.connect(_on_estado_actualizado)
		_on_estado_actualizado(astro)

func marcar_activo(activo: Personaje) -> void:
	for astro in _tarjetas.keys():
		var estilo: StyleBoxFlat = _tarjetas[astro]["estilo_panel"]
		if astro == activo:
			estilo.border_color = Color(0.3, 0.85, 1.0) # Borde celeste brillante
			estilo.set_border_width_all(2)
		else:
			estilo.border_color = Color(0.25, 0.28, 0.35)
			estilo.set_border_width_all(1)

func _crear_tarjeta(astro: Personaje, numero: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(145, 78)

	var estilo_panel := StyleBoxFlat.new()
	estilo_panel.bg_color = Color(0.11, 0.13, 0.18, 0.88)
	estilo_panel.set_corner_radius_all(6)
	estilo_panel.set_border_width_all(1)
	estilo_panel.border_color = Color(0.25, 0.28, 0.35)
	estilo_panel.content_margin_left = 8
	estilo_panel.content_margin_right = 8
	estilo_panel.content_margin_top = 6
	estilo_panel.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", estilo_panel)

	# Permite seleccionar al astronauta haciendo clic en su tarjeta
	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			astronauta_clicado.emit(astro)
	)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	# Fila superior: Nombre + Estado
	var fila_top := HBoxContainer.new()
	vbox.add_child(fila_top)

	var lbl_nombre := Label.new()
	lbl_nombre.text = "[%d] %s" % [numero, astro.obtener_nombre()]
	lbl_nombre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_nombre.add_theme_font_size_override("font_size", 11)
	fila_top.add_child(lbl_nombre)

	var lbl_estado := Label.new()
	lbl_estado.text = "Bien"
	lbl_estado.add_theme_font_size_override("font_size", 10)
	fila_top.add_child(lbl_estado)

	# Barra de Salud
	var bar_salud := _crear_barra(10, Color(0.2, 0.85, 0.35))
	vbox.add_child(bar_salud)

	# Mini-barras: Comida (izquierda) y Sueño/Descanso (derecha)
	var fila_sub := HBoxContainer.new()
	fila_sub.add_theme_constant_override("separation", 6)
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

func _crear_barra(alto: int, color_relleno: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(0, alto)
	pb.show_percentage = false
	pb.value = 100.0

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
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 1)

	var lbl := Label.new()
	lbl.text = titulo
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.modulate = Color(0.8, 0.85, 0.9)
	box.add_child(lbl)

	var bar := _crear_barra(5, color)
	box.add_child(bar)
	return {"box": box, "barra": bar}

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
