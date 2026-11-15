extends Node2D
## Escena principal: crea los recursos globales y la navegación, conecta el HUD y maneja
## la cámara y los clics del point and click.
##
## Cámara:
## - Rueda del mouse: zoom entre "todo el mapa" y zoom_maximo. Con un astronauta seleccionado,
##   cuanto más te acercás más lo sigue (a zoom_seguimiento ya lo sigue del todo).
## - Clic y arrastrar: mueve el mapa (deja de seguir al astronauta hasta que vuelvas a acercarte
##   con la rueda o lo selecciones de nuevo).
## - Mouse contra un borde (siguiendo a alguien): la cámara se corre hacia ese lado y vuelve sola.
## Selección:
## - Clic en un astronauta lo selecciona; clic en el seleccionado (o cerca de él) lo deselecciona.
## - Sin nadie seleccionado, los clics en el mapa no dan órdenes.

@export_group("Cámara")
## Zoom al que la cámara sigue del todo al astronauta seleccionado (y al que va al seleccionarlo).
@export var zoom_seguimiento := 2.0
## Zoom máximo con la rueda.
@export var zoom_maximo := 4.0
## Cuánto cambia el zoom por cada paso de la rueda.
@export var paso_zoom := 1.12
## Qué tan rápido la cámara alcanza su posición (más alto = más pegada).
@export var suavizado_camara := 8.0
## Píxeles de pantalla que hay que mover el mouse con el botón apretado para que sea un arrastre
## y no un clic.
@export var umbral_arrastre := 6.0
## Con el mouse a esta distancia (px de pantalla) del borde, la cámara se corre hacia ese lado.
@export var borde_paneo := 24.0
## Velocidad del paneo por borde, en px de pantalla por segundo.
@export var velocidad_paneo := 360.0
## Cuánto se puede alejar la cámara del astronauta con el paneo, en px de pantalla.
@export var paneo_maximo := 320.0
## Qué tan rápido vuelve la cámara al astronauta cuando el mouse sale del borde.
@export var retorno_paneo := 5.0

@export_group("Selección")
## Un clic a menos de esta distancia (px de mundo) del seleccionado lo deselecciona en lugar
## de moverlo, para no sacarlo de su puesto sin querer.
@export var tolerancia_deseleccion := 14.0

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
var eventos: Eventos
var _luz: CanvasModulate

# Cámara
var _zoom_objetivo := 1.0
var _pos_libre := Vector2.ZERO     # dónde mira la cámara cuando no sigue a nadie
var _siguiendo := false            # false después de arrastrar el mapa
var _paneo := Vector2.ZERO         # corrimiento por el mouse en el borde, en px de pantalla
var _ancla_zoom := Vector2.INF     # punto del mundo que queda fijo bajo el mouse al hacer zoom

# Clic / arrastre con el botón izquierdo
var _apretado := false
var _arrastrando := false
var _pos_apretado := Vector2.ZERO

func _ready() -> void:
	_configurar_pantalla()

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

	_configurar_camara()
	if tripulacion.is_empty():
		return

	hud.inicializar(tripulacion, maquinas, recursos)
	hud.astronauta_clicado.connect(_seleccionar_personaje)
	hud.maquina_clicada.connect(_mandar_a_trabajar)
	hud.enfocar.connect(_enfocar)

	eventos = Eventos.new()
	eventos.name = "Eventos"
	eventos.hud = hud
	eventos.recursos = recursos
	eventos.tripulacion = tripulacion
	eventos.astronauta_retirado.connect(func(p: Personaje):
		if p == _activo():
			_deseleccionar())
	add_child(eventos)
	_mostrar_ajustes("Ajustes cargados")
	for astro in tripulacion:
		astro.controlado_por_jugador = false
	hud.marcar_activo(null)
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
	camara.position_smoothing_enabled = true
	camara.position_smoothing_speed = suavizado_camara
	# Que no muestre lo que está fuera del mapa
	var mapa := _rect_mapa()
	camara.limit_left = int(mapa.position.x)
	camara.limit_top = int(mapa.position.y)
	camara.limit_right = int(mapa.end.x)
	camara.limit_bottom = int(mapa.end.y)
	# Arranca viendo todo el mapa, sin nadie seleccionado
	_pos_libre = mapa.get_center()
	_zoom_objetivo = _zoom_global()
	camara.zoom = Vector2(_zoom_objetivo, _zoom_objetivo)
	camara.global_position = _pos_libre
	camara.reset_smoothing()

func _process(delta: float) -> void:
	_actualizar_camara(delta)
	for astro in tripulacion:
		astro.actualizar_salud(delta, recursos.oxigeno, recursos.radiacion, false)
	if _luz != null:
		_luz.color = color_noche.lerp(Color.WHITE, recursos.luz())

# --- Cámara ------------------------------------------------------------------

func _actualizar_camara(delta: float) -> void:
	var z_min := _zoom_global()
	_zoom_objetivo = clampf(_zoom_objetivo, z_min, maxf(zoom_maximo, z_min))

	# Zoom suave; en modo libre, el punto bajo el mouse queda fijo
	var z_antes := camara.zoom.x
	var z := lerpf(z_antes, _zoom_objetivo, 1.0 - exp(-12.0 * delta))
	if absf(z - _zoom_objetivo) < 0.001:
		z = _zoom_objetivo
	camara.zoom = Vector2(z, z)
	if _ancla_zoom != Vector2.INF and not _hay_seguimiento():
		_pos_libre = _ancla_zoom + (_pos_libre - _ancla_zoom) * (z_antes / z)
	if z == _zoom_objetivo:
		_ancla_zoom = Vector2.INF

	var mapa := _rect_mapa()
	_pos_libre = _pos_libre.clamp(mapa.position, mapa.end)
	camara.position_smoothing_enabled = not _arrastrando

	var activo := _activo()
	if not _hay_seguimiento():
		_paneo = Vector2.ZERO
		camara.offset = Vector2.ZERO
		camara.global_position = _pos_libre
		return

	# Cuanto más cerca del zoom de seguimiento, más sigue al astronauta
	var t := clampf(inverse_lerp(z_min, zoom_seguimiento, z), 0.0, 1.0) if zoom_seguimiento > z_min else 1.0
	t = smoothstep(0.0, 1.0, t)
	_pos_libre = mapa.get_center()  # al alejarse del todo, se ve el mapa entero
	camara.global_position = _pos_libre.lerp(activo.global_position, t)

	# Paneo por borde: con el mouse contra un borde, la cámara se corre hacia ese lado;
	# cuando el mouse vuelve hacia el centro, regresa sola al astronauta (efecto elástico).
	var dir := _direccion_borde() if t > 0.5 else Vector2.ZERO
	if dir != Vector2.ZERO:
		_paneo += dir * velocidad_paneo * delta
		_paneo = _paneo.limit_length(paneo_maximo)
	else:
		_paneo = _paneo.lerp(Vector2.ZERO, 1.0 - exp(-retorno_paneo * delta))
	camara.offset = _paneo / camara.zoom

func _hay_seguimiento() -> bool:
	return _siguiendo and _activo() != null

## Dirección hacia el borde de la pantalla en el que está el mouse (cero si no está en ninguno,
## si está sobre el HUD o si la ventana no tiene el foco).
func _direccion_borde() -> Vector2:
	var vp := get_viewport()
	var rect := vp.get_visible_rect()
	var m := vp.get_mouse_position()
	if _apretado or not rect.has_point(m) or vp.gui_get_hovered_control() != null \
			or not DisplayServer.window_is_focused():
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

func _zoom_con_rueda(acercar: bool) -> void:
	_zoom_objetivo *= paso_zoom if acercar else 1.0 / paso_zoom
	_ancla_zoom = get_global_mouse_position()
	# Acercarse con alguien seleccionado vuelve a seguirlo
	if acercar and _activo() != null and not _siguiendo:
		_siguiendo = true

## Centra la cámara en un objeto (deja de seguir al astronauta) y se acerca si estaba lejos.
func _enfocar(objetivo: Node2D) -> void:
	if not is_instance_valid(objetivo):
		return
	_soltar_camara()
	_ancla_zoom = Vector2.INF
	if objetivo.has_method("rect_global"):
		var rect: Rect2 = objetivo.call("rect_global")
		_pos_libre = rect.get_center()
	else:
		_pos_libre = objetivo.global_position
	_zoom_objetivo = maxf(_zoom_objetivo, zoom_seguimiento)

## Muestra en la salida de Godot (y como aviso en el juego) qué multiplicadores están activos,
## para confirmar qué valores de Base/ajustes.gd está usando.
func _mostrar_ajustes(titulo: String) -> void:
	var resumen := Ajustes.actual().resumen()
	print("%s (Base/ajustes.gd): %s" % [titulo, resumen])
	hud.agregar_alerta("%s: %s" % [titulo, resumen], 0)

## Deja de seguir y fija la cámara donde está mirando ahora.
func _soltar_camara() -> void:
	if _siguiendo:
		_pos_libre = camara.get_screen_center_position()
		_paneo = Vector2.ZERO
	_siguiendo = false

# --- Entrada -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# F11: pantalla completa
		if event.keycode == KEY_F11:
			var ventana := get_window()
			ventana.mode = Window.MODE_WINDOWED if ventana.mode == Window.MODE_FULLSCREEN \
					else Window.MODE_FULLSCREEN
			return
		# F7: fuerza un evento crítico al azar (para probar el archivo de eventos)
		if event.keycode == KEY_F7 and eventos != null:
			eventos.cargar()
			eventos.lanzar_aleatorio()
			return
		# F6: vuelve a aplicar Base/ajustes.gd sin reiniciar el juego
		if event.keycode == KEY_F6:
			Ajustes.recargar()
			_mostrar_ajustes("Ajustes recargados")
			return
		if event.keycode == KEY_ESCAPE:
			_deseleccionar()
			return
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			_seleccionar_indice(event.keycode - KEY_1)
		return

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_con_rueda(true)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_con_rueda(false)
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					_apretado = true
					_arrastrando = false
					_pos_apretado = event.position
				elif _apretado:
					_apretado = false
					if _arrastrando:
						_arrastrando = false
					else:
						_clic_izquierdo(get_global_mouse_position())
			MOUSE_BUTTON_RIGHT:
				if event.pressed and _activo() != null:
					_activo().detener()
		return

	if event is InputEventMouseMotion and _apretado:
		if not _arrastrando and event.position.distance_to(_pos_apretado) > umbral_arrastre:
			_arrastrando = true
			_soltar_camara()
		if _arrastrando:
			# Arrastrar mueve el mapa con el mouse
			_pos_libre -= event.relative / camara.zoom

func _clic_izquierdo(punto: Vector2) -> void:
	var activo := _activo()

	# 1) Clic sobre un astronauta: lo selecciona (o lo deselecciona si ya lo estaba)
	var astro := _astronauta_en(punto)
	if astro != null:
		_seleccionar_personaje(astro)
		return
	if activo == null:
		return  # sin nadie seleccionado, el clic no da órdenes
	# Clic justo al lado del seleccionado: es un intento de deseleccionar, no de moverlo
	if punto.distance_to(activo.global_position) < tolerancia_deseleccion:
		_deseleccionar()
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
	# 5) Clic en el piso: camina hasta ahí. Si está en una tarea (trabajando o comiendo), el piso
	#    no lo saca de lo que hace: solo otra máquina, el comedor o una cama pueden interrumpirla.
	#    (Clic derecho o el teclado sí cancelan la tarea.)
	if activo.esta_en_tarea():
		activo.mostrar_cartel("Ocupado: clic en otra máquina o clic derecho")
		return
	activo.ir_a(punto)

func _activo() -> Personaje:
	if indice_activo < 0 or indice_activo >= tripulacion.size():
		return null
	return tripulacion[indice_activo]

## El astronauta bajo el punto (zona de clic un poco más grande que el sprite).
## Si hay varios, el más cercano.
func _astronauta_en(punto: Vector2) -> Personaje:
	var mejor: Personaje = null
	var mejor_d := INF
	for astro in tripulacion:
		if not astro.visible:
			continue  # fuera de la base por un evento
		var r := Rect2(astro.global_position - Vector2(10, 18), Vector2(20, 36))
		if r.has_point(punto):
			var d := punto.distance_squared_to(astro.global_position)
			if d < mejor_d:
				mejor_d = d
				mejor = astro
	return mejor

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
	else:
		hud.agregar_alerta("Seleccioná un astronauta primero", 0)

# --- Selección ---------------------------------------------------------------

## Seleccionar al que ya estaba seleccionado lo deselecciona.
func _seleccionar_indice(idx: int) -> void:
	if idx < 0 or idx >= tripulacion.size():
		return
	if idx == indice_activo:
		_deseleccionar()
		return
	if tripulacion[idx].en_evento and tripulacion[idx].evento_fuera:
		hud.agregar_alerta("%s está fuera de la base (%s)" % [tripulacion[idx].obtener_nombre(),
				tripulacion[idx].motivo_evento], 0)
		return
	indice_activo = idx
	_aplicar_seleccion()
	# Sigue al nuevo seleccionado y se acerca si estaba lejos
	_siguiendo = true
	_paneo = Vector2.ZERO
	_zoom_objetivo = maxf(_zoom_objetivo, zoom_seguimiento)

func _deseleccionar() -> void:
	if indice_activo == -1:
		return
	_soltar_camara()
	indice_activo = -1
	_aplicar_seleccion()

func _aplicar_seleccion() -> void:
	var activo := _activo()
	for astro in tripulacion:
		astro.controlado_por_jugador = astro == activo
		astro.set_seleccionado(astro == activo)
	hud.marcar_activo(activo)

func _seleccionar_personaje(astro: Personaje) -> void:
	var idx := tripulacion.find(astro)
	if idx != -1:
		_seleccionar_indice(idx)
