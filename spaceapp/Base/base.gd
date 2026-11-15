extends Node2D
## Escena principal: crea los recursos globales y la navegación, conecta el HUD y maneja
## los clics del point and click.

@export_group("Cámara")
## Zoom de la cámara mientras sigue al astronauta seleccionado.
@export var zoom_camara := 2.0
## Qué tan rápido la cámara alcanza al astronauta (más alto = más pegada).
@export var suavizado_camara := 8.0
## Con el mouse a esta distancia (px de pantalla) del borde, la cámara se corre hacia ese lado.
@export var borde_paneo := 24.0
## Velocidad del paneo por borde, en px de pantalla por segundo.
@export var velocidad_paneo := 360.0
## Cuánto se puede alejar la cámara del astronauta con el paneo, en px de pantalla.
@export var paneo_maximo := 320.0
## Qué tan rápido vuelve la cámara al astronauta cuando el mouse sale del borde.
@export var retorno_paneo := 5.0

@export_group("Pantalla")
## Resolución de diseño: al agrandar o maximizar la ventana, todo se escala desde este tamaño.
@export var resolucion_base := Vector2i(1152, 648)

@export_group("Día y noche")
## Color del mundo a medianoche (de día no se tiñe).
@export var color_noche := Color(0.38, 0.4, 0.62)
## Si es false, no se oscurece de noche.
@export var ciclo_dia_noche_visible := true

@onready var hud: CanvasLayer = $HUD
@onready var tilemap: TileMapLayer = $TileMapLayer
@onready var camara: Camera2D = $Camera2D

var tripulacion: Array[Personaje] = []
var maquinas: Array[Maquina] = []
var indice_activo: int = -1
var navegacion: Navegacion
var recursos: Recursos
var _luz: CanvasModulate
## Vista de todo el mapa (se activa al volver a seleccionar al astronauta ya seleccionado).
var camara_global := false
var _paneo := Vector2.ZERO  # corrimiento de la cámara por el mouse en el borde, en px de pantalla
var _tween_zoom: Tween

func _ready() -> void:
	_configurar_pantalla()
	_configurar_camara()

	recursos = Recursos.new()
	recursos.name = "Recursos"
	add_child(recursos)

	if ciclo_dia_noche_visible:
		_luz = CanvasModulate.new()
		add_child(_luz)

	for nodo in get_tree().get_nodes_in_group("astronautas"):
		if nodo is Personaje:
			tripulacion.append(nodo)
	for nodo in get_tree().get_nodes_in_group("maquinas"):
		if nodo is Maquina:
			maquinas.append(nodo)

	if tripulacion.is_empty():
		return

	hud.inicializar(tripulacion, maquinas, recursos)
	hud.astronauta_clicado.connect(_seleccionar_personaje)
	hud.maquina_clicada.connect(_mandar_a_trabajar)
	_seleccionar_indice(0)
	_construir_navegacion()

func _construir_navegacion() -> void:
	navegacion = Navegacion.new()
	navegacion.name = "Navegacion"
	add_child(navegacion)
	for astro in tripulacion:
		astro.navegacion = navegacion
	for r in get_tree().get_nodes_in_group("roombas"):
		r.navegacion = navegacion

	# Esperar a que el TileMapLayer cree sus colisiones en el espacio de física
	await get_tree().physics_frame
	await get_tree().physics_frame

	var excluir: Array[RID] = []
	for astro in tripulacion:
		excluir.append(astro.get_rid())
	var ref := tripulacion[0]
	navegacion.construir(tilemap, ref.tamano_pies(), ref.collision_mask, excluir)
	for m in maquinas:
		if m.bloquea_camino:
			navegacion.bloquear_rect(m.rect_global())
	for c in get_tree().get_nodes_in_group("comedores"):
		navegacion.bloquear_rect(c.rect_mesa())

## Al maximizar o agrandar la ventana, el juego (mundo y HUD) se escala en proporción a
## resolucion_base. Con "expand", si la ventana tiene otra proporción se ve un poco más de mapa
## en lugar de dejar barras negras.
func _configurar_pantalla() -> void:
	var ventana := get_window()
	ventana.content_scale_size = resolucion_base
	ventana.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	ventana.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

func _configurar_camara() -> void:
	camara.zoom = Vector2(zoom_camara, zoom_camara)
	get_viewport().size_changed.connect(func():
		if camara_global:
			_animar_zoom(_zoom_global()))
	camara.position_smoothing_enabled = true
	camara.position_smoothing_speed = suavizado_camara
	# Que no muestre lo que está fuera del mapa
	var usado := tilemap.get_used_rect()
	var tam_tile := Vector2(tilemap.tile_set.tile_size)
	var esquina := tilemap.to_global(Vector2(usado.position) * tam_tile)
	var fin := tilemap.to_global(Vector2(usado.end) * tam_tile)
	camara.limit_left = int(esquina.x)
	camara.limit_top = int(esquina.y)
	camara.limit_right = int(fin.x)
	camara.limit_bottom = int(fin.y)

func _process(delta: float) -> void:
	_actualizar_camara(delta)
	for astro in tripulacion:
		astro.actualizar_salud(delta, recursos.oxigeno, recursos.radiacion, false)
	if _luz != null:
		_luz.color = color_noche.lerp(Color.WHITE, recursos.luz())

# --- Cámara ------------------------------------------------------------------

func _actualizar_camara(delta: float) -> void:
	if camara_global:
		_paneo = Vector2.ZERO
		camara.offset = Vector2.ZERO
		camara.global_position = _rect_mapa().get_center()
		return
	var activo := _activo()
	if activo == null:
		return
	camara.global_position = activo.global_position

	# Paneo por borde: con el mouse contra un borde, la cámara se corre hacia ese lado;
	# cuando el mouse vuelve hacia el centro, regresa sola al astronauta (efecto elástico).
	var dir := _direccion_borde()
	if dir != Vector2.ZERO:
		_paneo += dir * velocidad_paneo * delta
		_paneo = _paneo.limit_length(paneo_maximo)
	else:
		_paneo = _paneo.lerp(Vector2.ZERO, 1.0 - exp(-retorno_paneo * delta))
	camara.offset = _paneo / camara.zoom

## Dirección hacia el borde de la pantalla en el que está el mouse (cero si no está en ninguno,
## si está sobre el HUD o si la ventana no tiene el foco).
func _direccion_borde() -> Vector2:
	var vp := get_viewport()
	var rect := vp.get_visible_rect()
	var m := vp.get_mouse_position()
	if not rect.has_point(m) or vp.gui_get_hovered_control() != null or not DisplayServer.window_is_focused():
		return Vector2.ZERO
	var dir := Vector2.ZERO
	if m.x < rect.position.x + borde_paneo:
		dir.x = -1.0
	elif m.x > rect.end.x - borde_paneo:
		dir.x = 1.0
	if m.y < rect.position.y + borde_paneo:
		dir.y = -1.0
	elif m.y > rect.end.y - borde_paneo:
		dir.y = 1.0
	return dir.normalized()

func _rect_mapa() -> Rect2:
	var usado := tilemap.get_used_rect()
	var tam_tile := Vector2(tilemap.tile_set.tile_size)
	var esquina := tilemap.to_global(Vector2(usado.position) * tam_tile)
	return Rect2(esquina, Vector2(usado.size) * tam_tile)

## Zoom con el que entra todo el mapa en pantalla.
func _zoom_global() -> float:
	var vista := get_viewport().get_visible_rect().size
	var mapa := _rect_mapa().size
	return minf(vista.x / mapa.x, vista.y / mapa.y)

func _animar_zoom(z: float) -> void:
	if _tween_zoom != null:
		_tween_zoom.kill()
	_tween_zoom = create_tween()
	_tween_zoom.tween_property(camara, "zoom", Vector2(z, z), 0.35) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _poner_camara_global(activa: bool) -> void:
	camara_global = activa
	_paneo = Vector2.ZERO
	_animar_zoom(_zoom_global() if activa else zoom_camara)

# --- Entrada -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# F11: pantalla completa
		if event.keycode == KEY_F11:
			var ventana := get_window()
			ventana.mode = Window.MODE_WINDOWED if ventana.mode == Window.MODE_FULLSCREEN \
					else Window.MODE_FULLSCREEN
			return
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			_seleccionar_indice(event.keycode - KEY_1)

	elif event is InputEventMouseButton and event.pressed:
		var activo := _activo()
		if activo == null:
			return
		var punto := get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			# 1) Clic sobre un astronauta: lo selecciona
			var astro := _astronauta_en(punto)
			if astro != null:
				_seleccionar_personaje(astro)
				return
			# 2) Clic sobre una máquina o el escritorio: el seleccionado va a trabajar ahí
			var maquina := _maquina_en(punto)
			if maquina != null:
				activo.trabajar_en(maquina)
				return
			# 3) Clic sobre el comedor: va a sentarse
			var comedor := _en_grupo("comedores", punto)
			if comedor != null:
				activo.usar(comedor)
				return
			# 4) Clic sobre una cama: va a acostarse (la de hospital es solo para inconscientes)
			var cama := _en_grupo("camas", punto) as CamaHospital
			if cama != null:
				if cama.solo_desmayados:
					activo.mostrar_cartel("Solo para inconscientes")
				else:
					activo.ir_a(cama.global_position + cama.offset_personaje)
					activo.quiere_acostarse = true
				return
			# 5) Clic en el piso: camina hasta ahí
			activo.ir_a(punto)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			activo.detener()

func _activo() -> Personaje:
	if indice_activo < 0 or indice_activo >= tripulacion.size():
		return null
	return tripulacion[indice_activo]

func _astronauta_en(punto: Vector2) -> Personaje:
	for astro in tripulacion:
		var r := Rect2(astro.global_position - Vector2(8, 16), Vector2(16, 32))
		if r.has_point(punto):
			return astro
	return null

func _maquina_en(punto: Vector2) -> Maquina:
	for m in maquinas:
		if m.contiene_punto(punto):
			return m
	return null

func _en_grupo(grupo: StringName, punto: Vector2) -> Node:
	for n in get_tree().get_nodes_in_group(grupo):
		if n.contiene_punto(punto):
			return n
	return null

func _mandar_a_trabajar(m: Maquina) -> void:
	var activo := _activo()
	if activo != null:
		activo.trabajar_en(m)

## Seleccionar al astronauta que ya estaba seleccionado alterna entre seguirlo y ver todo el mapa.
## Seleccionar a otro siempre vuelve a seguirlo.
func _seleccionar_indice(idx: int) -> void:
	if idx < 0 or idx >= tripulacion.size():
		return
	if idx == indice_activo:
		_poner_camara_global(not camara_global)
		return
	if camara_global:
		_poner_camara_global(false)
	indice_activo = idx
	for i in tripulacion.size():
		tripulacion[i].controlado_por_jugador = (i == idx)
	hud.marcar_activo(tripulacion[idx])
	# La cámara salta directo al nuevo seleccionado en lugar de deslizarse por todo el mapa
	if camara != null:
		camara.global_position = tripulacion[idx].global_position
		camara.reset_smoothing()

func _seleccionar_personaje(astro: Personaje) -> void:
	var idx := tripulacion.find(astro)
	if idx != -1:
		_seleccionar_indice(idx)
