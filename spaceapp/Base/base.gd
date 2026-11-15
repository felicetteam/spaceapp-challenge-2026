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
## Grilla de la roomba: solo las paredes la frenan (pasa por debajo de máquinas y muebles).
var navegacion_roomba: Navegacion
var recursos: Recursos
var eventos: Eventos
# Con preload (y no por su class_name) para no depender de que el editor ya haya registrado
# la clase: si no, base.gd entero no compila y el juego arranca sin nada.
const TutorialScript := preload("res://Base/tutorial.gd")
var tutorial: Node
## Para el tutorial: si el jugador ya usó la rueda del mouse y arrastró el mapa.
var uso_rueda := false
var uso_arrastre := false
var _luz: CanvasModulate
## Tiles de suelo marciano (afuera de la base): Vector3i(fuente, x, y) del atlas -> true.
var _tiles_exterior := {}

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
	_detectar_tiles_exterior()
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

	tutorial = TutorialScript.new()
	tutorial.name = "Tutorial"
	tutorial.base = self
	tutorial.hud = hud
	tutorial.eventos = eventos
	add_child(tutorial)
	eventos.tutorial = tutorial  # no salen eventos mientras el tutorial explica algo
	_mostrar_ajustes("Ajustes cargados")
	for astro in tripulacion:
		astro.controlado_por_jugador = false
	hud.marcar_activo(null)
	# El tutorial arranca recién con la grilla de caminos lista: si pausa antes, la grilla se
	# arma sin colisiones y los astronautas no encuentran el camino a las máquinas.
	await _construir_navegacion()
	tutorial.iniciar()

func _construir_navegacion() -> void:
	navegacion = Navegacion.new()
	navegacion.name = "Navegacion"
	add_child(navegacion)
	for astro in tripulacion:
		astro.navegacion = navegacion
	# La roomba tiene su propia grilla: pasa por debajo de máquinas y muebles, pero no
	# atraviesa paredes (solo la frena el mapa)
	navegacion_roomba = Navegacion.new()
	navegacion_roomba.name = "NavegacionRoomba"
	add_child(navegacion_roomba)
	for r in get_tree().get_nodes_in_group("roombas"):
		r.navegacion = navegacion_roomba

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

	# Grilla de la roomba: además de los astronautas, ignora los cuerpos de máquinas y muebles
	var excluir_roomba: Array[RID] = excluir.duplicate()
	for grupo in ["maquinas", "camas", "comedores", "roombas"]:
		for n in get_tree().get_nodes_in_group(grupo):
			_agregar_cuerpos(n, excluir_roomba)
	navegacion_roomba.construir(tilemap, ref.tamano_pies(), ref.collision_mask, excluir_roomba)


## Junta los RID de todos los cuerpos con colisión del nodo y sus hijos.
func _agregar_cuerpos(nodo: Node, lista: Array[RID]) -> void:
	if nodo is CollisionObject2D and not lista.has(nodo.get_rid()):
		lista.append(nodo.get_rid())
	for hijo in nodo.get_children():
		_agregar_cuerpos(hijo, lista)

## Al maximizar o agrandar la ventana, el juego (mundo y HUD) se escala en proporción a
## resolucion_base. Con "expand", si la ventana tiene otra proporción se ve un poco más de mapa
## en lugar de dejar barras negras.
func _configurar_pantalla() -> void:
	var ventana := get_window()
	ventana.content_scale_size = resolucion_base
	ventana.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	ventana.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

## Marca como "afuera" los tiles que son casi todos suelo naranja (Marte) o amarillo. Se calcula mirando
## los colores de la textura del tileset, así sigue andando si cambian el tileset.
func _detectar_tiles_exterior() -> void:
	_tiles_exterior.clear()
	var ts := tilemap.tile_set
	if ts == null:
		return
	for i in ts.get_source_count():
		var id := ts.get_source_id(i)
		var fuente := ts.get_source(id) as TileSetAtlasSource
		if fuente == null or fuente.texture == null:
			continue
		var img := fuente.texture.get_image()
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		for t in fuente.get_tiles_count():
			var coords := fuente.get_tile_id(t)
			var r := fuente.get_tile_texture_region(coords)
			var naranjas := 0
			var total := 0
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var c := img.get_pixel(x, y)
					if c.a < 0.5:
						continue
					total += 1
					var naranja := c.r > 0.67 and c.g >= 0.35 and c.g <= 0.69 and c.b < 0.47 and c.r - c.b > 0.35
					var amarillo := c.r > 0.75 and c.g > 0.6 and c.b < 0.35
					if naranja or amarillo:
						naranjas += 1
			if total > 0 and float(naranjas) / total >= 0.5:
				_tiles_exterior[Vector3i(id, coords.x, coords.y)] = true


## true si en esa posición del mapa hay suelo marciano (afuera de la base).
func es_exterior(pos: Vector2) -> bool:
	var celda := tilemap.local_to_map(tilemap.to_local(pos))
	var id := tilemap.get_cell_source_id(celda)
	if id == -1:
		return false
	var a := tilemap.get_cell_atlas_coords(celda)
	return _tiles_exterior.has(Vector3i(id, a.x, a.y))


func _configurar_camara() -> void:
	camara.position_smoothing_enabled = true
	camara.position_smoothing_speed = suavizado_camara
	camara.limit_smoothed = true  # con suavizado, que frene en el borde y no muestre afuera
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
	var lluvia := eventos != null and eventos.lluvia_activa()
	for astro in tripulacion:
		astro.set_afuera(es_exterior(astro.pies()))
		astro.actualizar_salud(delta, recursos.oxigeno, recursos.radiacion, lluvia)
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
	_limitar_offset()

## Los límites de la cámara no frenan el offset del paneo por borde: lo recortamos para que
## nunca se vea fuera del mapa.
func _limitar_offset() -> void:
	var mapa := _rect_mapa()
	var medio := get_viewport().get_visible_rect().size / camara.zoom * 0.5
	var minimo := mapa.position + medio
	var maximo := mapa.end - medio
	if minimo.x > maximo.x:
		minimo.x = mapa.get_center().x
		maximo.x = minimo.x
	if minimo.y > maximo.y:
		minimo.y = mapa.get_center().y
		maximo.y = minimo.y
	var centro := camara.global_position.clamp(minimo, maximo)
	camara.offset = (centro + camara.offset).clamp(minimo, maximo) - centro

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

## Zoom más alejado posible: el mapa llena la pantalla sin que se vea nada de afuera.
func _zoom_global() -> float:
	var vista := get_viewport().get_visible_rect().size
	var mapa := _rect_mapa().size
	return maxf(vista.x / mapa.x, vista.y / mapa.y)

func _zoom_con_rueda(acercar: bool) -> void:
	uso_rueda = true
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

## La cámara vuelve a seguir al astronauta elegido (para el tutorial).
func seguir_activo() -> void:
	if _activo() != null:
		_siguiendo = true
		_paneo = Vector2.ZERO
		_zoom_objetivo = maxf(_zoom_objetivo, zoom_seguimiento)

## Centra la cámara en algo, moviéndose suave (para el tutorial).
func enfocar(objetivo: Node2D) -> void:
	_enfocar(objetivo)

## Como _enfocar, pero la cámara llega al instante (para el tutorial, con el juego en pausa).
func enfocar_inmediato(objetivo: Node2D) -> void:
	_enfocar(objetivo)
	_zoom_objetivo = clampf(_zoom_objetivo, _zoom_global(), maxf(zoom_maximo, _zoom_global()))
	camara.zoom = Vector2(_zoom_objetivo, _zoom_objetivo)
	camara.offset = Vector2.ZERO
	camara.global_position = _pos_libre.clamp(_rect_mapa().position, _rect_mapa().end)
	camara.reset_smoothing()

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
		# Flechas: izquierda/derecha cambian de astronauta (después del último, ninguno);
		# arriba/abajo recorren las máquinas con problemas (después de la última, vista general)
		match event.keycode:
			KEY_RIGHT:
				_ciclar_astronauta(1)
			KEY_LEFT:
				_ciclar_astronauta(-1)
			KEY_DOWN:
				_ciclar_maquina(1)
			KEY_UP:
				_ciclar_maquina(-1)
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
						uso_arrastre = true  # (tutorial) cuenta recién cuando suelta el arrastre
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
	var tocada := _maquina_en(punto)
	if tocada != null and tutorial != null:
		tutorial.maquina_tocada(tocada)  # la primera vez explica para qué sirve
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
			activo.acostarse_en(cama)  # en medio de un trabajo de evento es una pausa
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
		if m.seleccionable() and m.contiene_punto(punto):
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

var _idx_maquina_foco := -1

## Pasa al astronauta siguiente (paso 1) o anterior (-1). Hay un lugar más: ninguno seleccionado.
func _ciclar_astronauta(paso: int) -> void:
	var n := tripulacion.size()
	if n == 0:
		return
	var idx := indice_activo
	for _i in n + 1:
		idx += paso
		if idx >= n:
			idx = -1
		elif idx < -1:
			idx = n - 1
		if idx == -1:
			_deseleccionar()
			_vista_general()
			return
		if not (tripulacion[idx].en_evento and tripulacion[idx].evento_fuera):
			if idx != indice_activo:
				_seleccionar_indice(idx)
			return

## Centra la cámara en la máquina con problemas siguiente o anterior (de la peor a la mejor).
## Después de la última vuelve a la vista general.
func _ciclar_maquina(paso: int) -> void:
	var lista: Array[Maquina] = []
	for m in maquinas:
		if is_instance_valid(m) and m.tiene_desgaste and m.seleccionable() \
				and m.mantenimiento < m.umbral_borde:
			lista.append(m)
	lista.sort_custom(func(a, b): return a.mantenimiento < b.mantenimiento)
	if lista.is_empty():
		_idx_maquina_foco = -1
		hud.agregar_alerta("Ninguna máquina necesita atención", 0)
		return
	_idx_maquina_foco += paso
	if _idx_maquina_foco >= lista.size():
		_idx_maquina_foco = -1
	elif _idx_maquina_foco < -1:
		_idx_maquina_foco = lista.size() - 1
	if _idx_maquina_foco == -1:
		_vista_general()
		return
	var m := lista[_idx_maquina_foco]
	_enfocar(m)
	hud.agregar_alerta("%s: %d%% (%d/%d)" % [m.nombre_maquina, roundi(m.mantenimiento),
			_idx_maquina_foco + 1, lista.size()], 0, m)

## Cámara viendo todo el mapa (también la usa el tutorial al terminar).
func vista_general() -> void:
	_vista_general()

func _vista_general() -> void:
	_soltar_camara()
	_ancla_zoom = Vector2.INF
	_paneo = Vector2.ZERO
	_pos_libre = _rect_mapa().get_center()
	_zoom_objetivo = _zoom_global()

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
