@tool
class_name Personaje extends CharacterBody2D

signal estado_actualizado(personaje: Personaje)

enum Cabeza { FELI, LAIKA, JUAN, ANDY }
enum ModoLaburar { MANTENER, ALTERNAR }
## NINGUNA: control manual (teclado) o quieto. MOVER: va hacia un punto clicado.
## TRABAJAR: va a una máquina y trabaja dando vueltas alrededor.
## USAR: va a un mueble (por ejemplo, un asiento del comedor) y lo usa.
## PASEO: idle, caminando solo por la base (no es una orden del jugador).
enum Orden { NINGUNA, MOVER, TRABAJAR, USAR, PASEO }

const NOMBRES := {
	Cabeza.FELI: "Feli",
	Cabeza.LAIKA: "Laika",
	Cabeza.JUAN: "Juan",
	Cabeza.ANDY: "Andy"
}
# Las afinidades (salud, trabajo, investigación) de cada uno están en Personaje/afinidades.gd

@export var cabeza: Cabeza = Cabeza.ANDY:
	set(valor):
		cabeza = valor
		if is_node_ready():
			_aplicar_cabeza()

@export var con_casco := true:
	set(valor):
		con_casco = valor
		if is_node_ready():
			_aplicar_casco()

@export_group("Movimiento")
## Al dejar de controlarlo, si estaba en control manual, queda en idle.
## Si tenía una orden (ir a un punto o trabajar), la sigue cumpliendo solo.
@export var controlado_por_jugador := true:
	set(valor):
		controlado_por_jugador = valor
		if not valor and is_node_ready() and not Engine.is_editor_hint() and orden == Orden.NINGUNA:
			_quedar_idle()
@export var velocidad := 80.0

@export_group("Trabajo")
## Cuánto tiempo labura en cada puesto antes de moverse a otro lado de la máquina.
@export var tiempo_por_puesto_min := 2.5
@export var tiempo_por_puesto_max := 5.0

@export_group("Paseo en idle")
## Si es true, cuando no tiene nada que hacer pasea por la base.
@export var pasear_en_idle := true
## Espera entre un paseo y el siguiente, en segundos.
@export var espera_paseo_min := 2.0
@export var espera_paseo_max := 5.0
## Distancia de cada paseo, en píxeles.
@export var distancia_paseo_min := 48.0
@export var distancia_paseo_max := 200.0
## Cantidad de paseos antes de volver al punto de inicio (al azar entre los dos).
@export var paseos_antes_de_volver_min := 1
@export var paseos_antes_de_volver_max := 3
## Velocidad al pasear, relativa a la velocidad normal.
@export_range(0.1, 1.0) var velocidad_paseo := 0.6

@export_group("Salud")
## Con salud 0 (o con el sueño al máximo) queda inconsciente durante
## Ajustes.tiempo_inconsciente segundos, sin importar dónde esté; después puede moverse.
## Con la comida en 0 pierde esta cantidad de salud por segundo (x Ajustes.dano_hambre).
@export var dano_por_hambre := 1.0

@export_group("Necesidades")
## Desde este hambre (0-100) aparece el globo de comida y, en idle, pasea hacia el comedor.
@export var umbral_globo_hambre := 70.0
## Desde este sueño (0-100) aparece el globo de sueño y, en idle, pasea hacia las camas.
@export var umbral_globo_sueno := 75.0
## Trabajando en un evento, con este hambre o sueño se toma una pausa para comer o dormir.
@export var umbral_pausa_hambre := 85.0
@export var umbral_pausa_sueno := 85.0

@export_group("Linterna")
## De noche alumbra con un cono hacia donde camina.
@export var usar_linterna := true
@export var energia_linterna := 0.7
## Largo del cono, en píxeles.
@export var alcance_linterna := 70.0
## Cuánto más adelante del cuerpo empieza el cono, en píxeles.
@export var separacion_linterna := 9.0

@export_group("Encuentros")
## A qué distancia (px, entre pies) detecta a otro astronauta adelante en su camino.
@export var distancia_deteccion := 18.0
## Sonido de la moneda que se tira para decidir quién se corre.
@export var sonido_moneda: AudioStream = preload("res://assets/sonidos/sonido_moneda.wav")

@export_group("Input")
@export var modo_laburar := ModoLaburar.MANTENER
@export var accion_izquierda: StringName = &"ui_left"
@export var accion_derecha: StringName = &"ui_right"
@export var accion_arriba: StringName = &"ui_up"
@export var accion_abajo: StringName = &"ui_down"
@export var accion_laburar: StringName = &"ui_accept"

@onready var sprite_cuerpo: AnimatedSprite2D = $Sprite_Cuerpo
@onready var sprite_brazo: AnimatedSprite2D = $Sprite_Brazo
@onready var sprite_cabeza: AnimatedSprite2D = $Sprite_Cabeza
@onready var sprite_casco: AnimatedSprite2D = $Sprite_Casco
@onready var barra_salud: ProgressBar = $Barra_Salud
@onready var forma_colision: CollisionShape2D = $CollisionShape2D

# Variables de estado vital (0 a 100)
var salud: float = 100.0
var hambre: float = 0.0        # 0 = lleno, 100 = hambriento
var sueno: float = 0.0         # 0 = descansado, 100 = agotado
var dano_ambiental: float = 0.0

# Estados de sala / entorno
var en_refugio := false
var en_exterior := false
var durmiendo := false
var corriendo := false
var laburando := false
var estado_alerta: String = "Óptimo"

# Point and click (base.gd asigna la navegación)
var navegacion: Navegacion
var orden := Orden.NINGUNA
var maquina_actual: Maquina = null
## Lo marca la cama mientras está acostado: no se lo puede correr para dejar pasar a otro.
var en_cama := false
## Salud 0: no responde a órdenes hasta que se recupera (la roomba lo lleva a una cama).
var desmayado := false
## El desmayo es por agotamiento (sueño al máximo), no por salud 0: la roomba lo lleva a una
## cama común y se despierta al descansar.
var dormido_agotado := false
## Segundos que le quedan de Descansado (energía al 100: no baja) y de Satisfecho (comida al
## 100: no baja). Con los dos a la vez está Feliz y trabaja más rápido.
var _t_descansado := 0.0
var _t_satisfecho := 0.0
var _sueno_previo := 0.0
var _hambre_previa := 0.0
## Segundos que lleva inconsciente.
var _t_inconsciente := 0.0
## Segundos que le quedan sin poder desmayarse de nuevo, después de despertarse.
var _t_gracia := 0.0
## Lo marca la roomba mientras lo transporta.
var siendo_llevado := false
## La roomba que viene a buscarlo.
var reservado_por: Node = null
## Fuera de servicio por un evento crítico (ver Eventos): fuera del mapa u ocupado en su lugar.
var en_evento := false
var evento_fuera := false
var motivo_evento := ""
## Trabajando en un evento (modo ocupado) se puede tomar una pausa para comer o dormir:
## mientras dura, el tiempo del evento no corre. Después vuelve a su lugar de trabajo.
var pausa_evento := false
var _volviendo_a_evento := false
var _punto_evento := Vector2.INF
var _t_revisar_pausa := 0.0
var _t_pausa_sin_orden := 0.0
## Está sobre suelo marciano (fuera de la base): lleva el casco puesto.
var afuera := false
var _tween_casco: Tween
var _globo: Globo
var _linterna: PointLight2D
var _dir_linterna := Vector2.RIGHT
static var _textura_cono: ImageTexture
## Camina hacia la estructura de un evento crítico (ver Eventos): no acepta otras órdenes.
## Lo pone en false al llegar, o si no pudo llegar (Eventos lo revisa para aplicar la decisión).
var yendo_a_evento := false
## true si llegó a la estructura del evento.
var llego_a_evento := false
## Segundos que le faltan para volver (lo actualiza Eventos).
var tiempo_evento := 0.0
## Última vez que comió en el comedor (Time.get_ticks_msec()).
var ultima_comida_ms := -1000000000
## Mueble que está usando con la orden USAR (por ejemplo, el comedor).
var mueble_actual: Node = null
var _usando := false
## El jugador lo mandó a una cama (o lo movió con el teclado): si se queda quieto sobre una, se acuesta.
## Paseando solo, nunca se acuesta por accidente.
var quiere_acostarse := false

## Lo marca base.gd: muestra un borde verde alrededor del personaje.
var seleccionado := false
var _grupo_seleccion: CanvasGroup
var _material_seleccion: ShaderMaterial

# Paseo en idle
var _punto_inicio := Vector2.ZERO
var _t_idle := 0.0
var _paseos_restantes := 0

var _camino := PackedVector2Array()
var _idx_camino := 0
var _destino := Vector2.ZERO        # punto al que lleva el camino actual
var _destino_orden := Vector2.ZERO  # punto de la orden (se retoma después de un desvío)
var _en_puesto := false
var _t_puesto := 0.0
var _t_atascado := 0.0
var _reintentos := 0

# Encuentros con otros astronautas
## ESPERANDO: ganó la moneda y espera a que el otro se corra.
## CEDIENDO: perdió y camina hasta un costado. CEDIDO: ya está al costado, esperando que el otro pase.
enum Desvio { NINGUNO, ESPERANDO, CEDIENDO, CEDIDO }
var _desvio := Desvio.NINGUNO
var _otro: Personaje = null
var _t_desvio := 0.0
var _volver_a := Vector2.INF        # si estaba quieto sin orden, vuelve a este lugar después de ceder
var _ignorar_hasta := {}            # Personaje -> msec: no volver a detectarlo enseguida
var _intentos_rodear := 0

var _estilo_relleno: StyleBoxFlat
var _reproductor_moneda: AudioStreamPlayer2D
var _cartel: Label
var _tween_cartel: Tween

func _ready() -> void:
	_aplicar_cabeza()
	_aplicar_casco()
	if Engine.is_editor_hint():
		return
	add_to_group("astronautas")
	_punto_inicio = pies()
	_t_idle = randf_range(espera_paseo_min, espera_paseo_max)
	_paseos_restantes = randi_range(paseos_antes_de_volver_min, paseos_antes_de_volver_max)
	_configurar_barra_flotante()
	_crear_cartel_y_sonido()
	_crear_globo_y_linterna()
	_actualizar_animaciones(true)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_actualizar_globo()
	_actualizar_linterna(delta)
	_actualizar_borde_seleccion()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Inconsciente: no se mueve, no pasea y sus animaciones quedan en pausa
	if desmayado or siendo_llevado:
		velocity = Vector2.ZERO
		return
	# Ocupado por un evento: se queda en su lugar laburando, sin aceptar órdenes.
	# Si tiene mucha hambre o sueño se toma una pausa (y después vuelve).
	if en_evento:
		if evento_fuera:
			velocity = Vector2.ZERO
			return
		if not pausa_evento and not _volviendo_a_evento:
			velocity = Vector2.ZERO
			set_corriendo(false)
			set_laburando(true)  # mantenimiento de la misión: animación de laburo
			_revisar_pausa_evento(delta)
			return
		_vigilar_pausa(delta)

	# Camino a un evento: si la orden se cortó (por ejemplo, sin camino), ya no va
	if yendo_a_evento and orden != Orden.MOVER:
		yendo_a_evento = false

	# Sin control por flechas: las flechas cambian de astronauta y de máquina (ver base.gd)
	var dir := Vector2.ZERO
	# Mover con el teclado cancela cualquier orden de point and click
	if dir != Vector2.ZERO and (orden != Orden.NINGUNA or _desvio != Desvio.NINGUNO):
		detener()

	if _desvio != Desvio.NINGUNO:
		_proceso_desvio(delta)
		return

	match orden:
		Orden.NINGUNA:
			_mover_manual(dir)
		Orden.MOVER:
			if _seguir_camino(delta):
				if _volviendo_a_evento:
					_volviendo_a_evento = false
					detener()
					set_laburando(true)
					mostrar_cartel("De vuelta al trabajo")
					return
				if yendo_a_evento:
					yendo_a_evento = false
					llego_a_evento = true
				detener()
		Orden.TRABAJAR:
			_proceso_trabajo(delta)
		Orden.USAR:
			_proceso_uso(delta)
		Orden.PASEO:
			if _seguir_camino(delta):
				_fin_de_paseo()

func _mover_manual(dir: Vector2) -> void:
	if not controlado_por_jugador:
		if corriendo or laburando or velocity != Vector2.ZERO:
			_quedar_idle()
		_contar_idle()
		return

	if dir != Vector2.ZERO:
		quiere_acostarse = true  # caminando con el teclado se puede acostar en una cama
		_t_idle = randf_range(espera_paseo_min, espera_paseo_max)
	velocity = dir * _velocidad_actual()
	move_and_slide()
	set_corriendo(dir != Vector2.ZERO)
	mirar(dir.x)

	match modo_laburar:
		ModoLaburar.MANTENER:
			set_laburando(Input.is_action_pressed(accion_laburar))
		ModoLaburar.ALTERNAR:
			if Input.is_action_just_pressed(accion_laburar):
				alternar_laburar()
	if dir == Vector2.ZERO and not laburando:
		_contar_idle()

func _velocidad_actual() -> float:
	# Penalización de velocidad si tiene mucha hambre (> 70%)
	var v := velocidad * (0.75 if hambre > 70.0 else 1.0)
	if orden == Orden.PASEO and _desvio == Desvio.NINGUNO:
		v *= velocidad_paseo
	return v

# --- Selección ---------------------------------------------------------------

func set_seleccionado(valor: bool) -> void:
	seleccionado = valor
	_actualizar_borde_seleccion()

## El borde verde se dibuja con un CanvasGroup que junta las cuatro capas del personaje, así el
## contorno sigue la silueta completa. Solo existe mientras está seleccionado; en la cama no se
## usa, para que la cabeza pueda seguir por encima de la sábana.
func _actualizar_borde_seleccion() -> void:
	var quiere := seleccionado and not en_cama
	if quiere and _grupo_seleccion == null:
		if _material_seleccion == null:
			_material_seleccion = ShaderMaterial.new()
			_material_seleccion.shader = preload("res://Base/shaders/contorno_seleccion.gdshader")
		_grupo_seleccion = CanvasGroup.new()
		_grupo_seleccion.name = "BordeSeleccion"
		_grupo_seleccion.fit_margin = 6.0
		_grupo_seleccion.material = _material_seleccion
		add_child(_grupo_seleccion)
		move_child(_grupo_seleccion, 0)
		for s in _capas():
			s.reparent(_grupo_seleccion, false)
	elif not quiere and _grupo_seleccion != null:
		var i := 0
		for s in _capas():
			s.reparent(self, false)
			move_child(s, i)
			i += 1
		_grupo_seleccion.queue_free()
		_grupo_seleccion = null
	if _grupo_seleccion != null:
		# Más o menos 1 píxel del mundo, sin importar el zoom ni el tamaño de la ventana
		var escala := get_viewport().get_screen_transform().get_scale().x \
				* get_global_transform_with_canvas().get_scale().x
		_material_seleccion.set_shader_parameter("grosor", maxf(1.0, roundf(escala)))

func _capas() -> Array[AnimatedSprite2D]:
	return [sprite_cuerpo, sprite_brazo, sprite_casco, sprite_cabeza]

# --- Paseo en idle -----------------------------------------------------------

## Cuenta el tiempo quieto en idle y, cuando se cumple, sale a pasear.
func _contar_idle() -> void:
	if not pasear_en_idle or en_cama or desmayado or siendo_llevado or en_evento:
		return
	_t_idle -= get_physics_process_delta_time()
	if _t_idle <= 0.0:
		_t_idle = randf_range(espera_paseo_min, espera_paseo_max)
		_siguiente_paseo()

## Elige un paseo: varios a lugares al azar y, después de 1 a 3, vuelve al punto de inicio.
func _siguiente_paseo() -> void:
	if navegacion == null or not navegacion.listo:
		return
	quiere_acostarse = false
	var destino := Vector2.INF
	if _paseos_restantes <= 0:
		_paseos_restantes = randi_range(paseos_antes_de_volver_min, paseos_antes_de_volver_max)
		if pies().distance_to(_punto_inicio) > 12.0:
			destino = _punto_inicio
	# Con hambre o sueño, pasea un poco hacia el comedor o las camas (sin usarlos solo)
	var meta := _meta_necesidad()
	if meta != Vector2.INF:
		destino = _paso_hacia(meta)
	if destino == Vector2.INF:
		destino = navegacion.punto_aleatorio(pies(), distancia_paseo_min, distancia_paseo_max)
		_paseos_restantes -= 1
	if destino == Vector2.INF:
		return
	orden = Orden.PASEO
	if not _calcular_camino(destino):
		orden = Orden.NINGUNA

## Comedor (con hambre) o cama libre más cercana (con sueño). Vector2.INF si no necesita nada.
func _meta_necesidad() -> Vector2:
	var con_hambre := hambre >= umbral_globo_hambre
	var con_sueno := sueno >= umbral_globo_sueno
	if con_hambre and (not con_sueno or hambre >= sueno):
		var c := _comedor_mas_cercano()
		if c != null:
			return c.global_position
	if con_sueno:
		var cama := _cama_comun_libre()
		if cama != null:
			return cama.global_position
	return Vector2.INF

func _comedor_mas_cercano() -> Node2D:
	var mejor: Node2D = null
	for c in get_tree().get_nodes_in_group("comedores"):
		if mejor == null or pies().distance_to(c.global_position) < pies().distance_to(mejor.global_position):
			mejor = c
	return mejor

## Un paseo corto en dirección a la meta: avanza la mitad del camino (como mucho un paseo largo)
## y se queda cerca cuando ya llegó.
func _paso_hacia(meta: Vector2) -> Vector2:
	var dif := meta - pies()
	if dif.length() < 36.0:
		return Vector2.INF
	var largo := minf(dif.length() * 0.5, distancia_paseo_max)
	var punto := pies() + dif.normalized() * largo + Vector2(randf_range(-12, 12), randf_range(-12, 12))
	var celda := navegacion.celda_transitable_cercana(punto, 6)
	if celda == Navegacion.SIN_CELDA:
		return Vector2.INF
	return navegacion.posicion_de(celda)

func _fin_de_paseo() -> void:
	orden = Orden.NINGUNA
	_camino = PackedVector2Array()
	_quedar_idle()
	_t_idle = randf_range(espera_paseo_min, espera_paseo_max)

## Terminó lo que estaba haciendo (máquina reparada, comida, descanso): vuelve al idle.
func terminar_tarea(mensaje := "") -> void:
	if mensaje != "":
		mostrar_cartel(mensaje)
	if en_evento and pausa_evento:
		_volver_al_evento()  # terminó la pausa: vuelve a trabajar en el evento
		return
	detener()
	_t_idle = randf_range(0.8, 2.0)  # sale a pasear enseguida

# --- Point and click ---------------------------------------------------------

## Posición global de los pies (el centro de la forma de colisión).
func pies() -> Vector2:
	return to_global(forma_colision.position)

func tamano_pies() -> Vector2:
	var r := forma_colision.shape as RectangleShape2D
	return r.size if r != null else Vector2(14, 2)

## Camina hasta un punto del mapa. Si el punto no es alcanzable (o hay un muro entre
## el punto y la celda libre más cercana), no se mueve y muestra "Sin camino".
func ir_a(destino_global: Vector2) -> void:
	if _no_responde():
		return
	quiere_acostarse = false
	_terminar_desvio()
	_soltar_maquina()
	orden = Orden.MOVER
	if not _calcular_camino(destino_global):
		mostrar_cartel("Sin camino")
		detener()

## Va hasta la máquina y se queda trabajando alrededor de ella.
func trabajar_en(m: Maquina) -> void:
	if m == null:
		return
	if orden == Orden.TRABAJAR and maquina_actual == m:
		return
	if _no_responde():
		return
	if m.esta_apagada():
		mostrar_cartel("Apagada: no se puede reparar")
		return
	quiere_acostarse = false
	_terminar_desvio()
	_soltar_maquina()
	maquina_actual = m
	m.agregar_trabajador(self)
	orden = Orden.TRABAJAR
	_ir_a_puesto_nuevo()

## Va a un mueble usable (por ahora, el comedor): reserva un lugar, camina hasta ahí y lo usa.
func usar(mueble: Node) -> void:
	if mueble == null:
		return
	if en_evento and not evento_fuera and not desmayado and not pausa_evento:
		pausa_evento = true  # el jugador lo manda a comer en medio del trabajo del evento
		mostrar_cartel("Pausa para comer")
	if _no_responde():
		return
	quiere_acostarse = false
	if orden == Orden.USAR and mueble_actual == mueble:
		return
	_terminar_desvio()
	_soltar_maquina()
	var lugar: Vector2 = mueble.reservar_asiento(self)
	if lugar == Vector2.INF:
		mostrar_cartel("No hay lugar")
		detener()
		return
	mueble_actual = mueble
	orden = Orden.USAR
	_usando = false
	if not _calcular_camino(lugar):
		mostrar_cartel("Sin camino")
		detener()

## true si está libre para acostarse solo en una cama: sin órdenes ni desvíos.
func esta_libre() -> bool:
	return orden == Orden.NINGUNA and _desvio == Desvio.NINGUNO and not siendo_llevado

## Cancela la orden actual (y cualquier desvío) y queda en idle.
func detener() -> void:
	_terminar_desvio()
	_soltar_maquina()
	orden = Orden.NINGUNA
	_camino = PackedVector2Array()
	_quedar_idle()
	_t_idle = randf_range(espera_paseo_min, espera_paseo_max)

## true si ya llegó a su puesto en la máquina y está laburando.
func esta_en_puesto() -> bool:
	return orden == Orden.TRABAJAR and _en_puesto

func esta_trabajando() -> bool:
	return orden == Orden.TRABAJAR

# --- Eventos críticos --------------------------------------------------------

## Camina hasta la estructura de un evento (al punto alcanzable más cercano de destinos).
## Mientras va no acepta órdenes. Devuelve false si no hay camino a ninguno.
func ir_a_evento(destinos: Array[Vector2], motivo: String) -> bool:
	if desmayado or siendo_llevado or en_evento:
		return false
	if en_cama:
		for c in get_tree().get_nodes_in_group("camas"):
			if c.ocupante == self:
				c.levantar()
	detener()
	quiere_acostarse = false
	llego_a_evento = false
	var ordenados := destinos.duplicate()
	var desde := pies()
	ordenados.sort_custom(func(a, b): return desde.distance_squared_to(a) < desde.distance_squared_to(b))
	for d in ordenados:
		if desde.distance_to(d) < 4.0:
			llego_a_evento = true  # ya está ahí
			return true
		orden = Orden.MOVER
		if _calcular_camino(d):
			yendo_a_evento = true
			motivo_evento = motivo
			mostrar_cartel("Va a: %s" % motivo, 2.0)
			return true
	detener()
	return false

## Lo saca de servicio por un evento. fuera = true: desaparece del mapa; false: se queda en su
## lugar con la animación de laburo y no acepta órdenes.
func iniciar_evento(fuera: bool, motivo: String, _segundos: float) -> void:
	if en_cama:
		for c in get_tree().get_nodes_in_group("camas"):
			if c.ocupante == self:
				c.levantar()
	detener()
	quiere_acostarse = false
	en_evento = true
	evento_fuera = fuera
	motivo_evento = motivo
	controlado_por_jugador = false
	set_seleccionado(false)
	if fuera:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED  # también lo saca de la física
	else:
		_punto_evento = pies()
		pausa_evento = false
		_volviendo_a_evento = false
		set_laburando(true)
		mostrar_cartel("Ocupado: %s" % motivo)

## donde: dónde reaparece si estaba fuera de la base (INF = su punto de inicio).
func terminar_evento(donde := Vector2.INF) -> void:
	if not en_evento:
		return
	en_evento = false
	pausa_evento = false
	_volviendo_a_evento = false
	if evento_fuera:
		process_mode = Node.PROCESS_MODE_INHERIT
		visible = true
		# Reaparece en su punto de inicio (o donde lo deja el rover)
		var lugar := _punto_inicio if donde == Vector2.INF else donde
		if navegacion != null and navegacion.listo:
			var celda := navegacion.celda_transitable_cercana(lugar, 8, false)
			if celda != Navegacion.SIN_CELDA:
				lugar = navegacion.posicion_de(celda)
		global_position += lugar - pies()
	evento_fuera = false
	motivo_evento = ""
	_quedar_idle()
	mostrar_cartel("De vuelta")

## true mientras el tiempo de su tarea de evento está frenado (comiendo, durmiendo o volviendo).
func en_pausa_evento() -> bool:
	return en_evento and not evento_fuera and (pausa_evento or _volviendo_a_evento)

## Revisa (cada segundo) si necesita parar a comer o a dormir.
func _revisar_pausa_evento(delta: float) -> void:
	_t_revisar_pausa -= delta
	if _t_revisar_pausa > 0.0:
		return
	_t_revisar_pausa = 1.0
	if hambre >= umbral_pausa_hambre:
		var comedor := _comedor_para_comer()
		if comedor != null:
			pausa_evento = true
			mostrar_cartel("Pausa para comer")
			usar(comedor)
			return
	if sueno >= umbral_pausa_sueno:
		var cama := _cama_comun_libre()
		if cama != null:
			acostarse_en(cama)

## Durante la pausa: si se quedó sin nada que hacer (no llegó, no había lugar), vuelve.
func _vigilar_pausa(delta: float) -> void:
	if pausa_evento and orden == Orden.NINGUNA and not en_cama:
		_t_pausa_sin_orden += delta
		if _t_pausa_sin_orden > 0.8:
			terminar_tarea()
	else:
		_t_pausa_sin_orden = 0.0

## Termina la pausa y camina de vuelta a donde estaba trabajando.
func _volver_al_evento() -> void:
	pausa_evento = false
	_t_pausa_sin_orden = 0.0
	detener()
	if _punto_evento == Vector2.INF or pies().distance_to(_punto_evento) < 4.0:
		set_laburando(true)
		return
	_volviendo_a_evento = true
	orden = Orden.MOVER
	if not _calcular_camino(_punto_evento):
		_volviendo_a_evento = false
		detener()
		set_laburando(true)

## Va a acostarse en una cama común. En medio de un trabajo de evento, es una pausa.
func acostarse_en(cama: Node2D) -> void:
	if en_evento and not evento_fuera and not desmayado:
		pausa_evento = true
		mostrar_cartel("Pausa para dormir")
	ir_a(cama.global_position + cama.offset_personaje)
	quiere_acostarse = true

func _comedor_para_comer() -> Node2D:
	var mejor: Node2D = null
	for c in get_tree().get_nodes_in_group("comedores"):
		if c.lugares_libres() > 0 and c._puede_comer(self):
			if mejor == null or pies().distance_to(c.global_position) < pies().distance_to(mejor.global_position):
				mejor = c
	return mejor

func _cama_comun_libre() -> Node2D:
	var mejor: Node2D = null
	for c in get_tree().get_nodes_in_group("camas"):
		if c.solo_desmayados or not c.esta_libre():
			continue
		if mejor == null or pies().distance_to(c.global_position) < pies().distance_to(mejor.global_position):
			mejor = c
	return mejor

## true si está en una tarea: trabajando en una máquina o usando un mueble (comedor).
func esta_en_tarea() -> bool:
	return orden == Orden.TRABAJAR or orden == Orden.USAR

## Lo que le queda por recorrer (vacío si está quieto).
func camino_restante() -> PackedVector2Array:
	if not _moviendose():
		return PackedVector2Array()
	return _camino.slice(_idx_camino)

## Si se lo puede correr para dejar pasar a otro.
## No se corre si está acostado o si el jugador lo maneja con el teclado sin una orden.
func puede_ceder() -> bool:
	if en_cama or desmayado or siendo_llevado or en_evento:
		return false
	return not (controlado_por_jugador and orden == Orden.NINGUNA)

func _moviendose() -> bool:
	if _desvio == Desvio.CEDIENDO:
		return true
	if _desvio != Desvio.NINGUNO:
		return false
	if orden == Orden.MOVER or orden == Orden.PASEO or (orden == Orden.TRABAJAR and not _en_puesto) \
			or (orden == Orden.USAR and not _usando):
		return _idx_camino < _camino.size()
	return false

func _quedar_idle() -> void:
	velocity = Vector2.ZERO
	set_corriendo(false)
	set_laburando(false)

## Suelta la máquina o el mueble que estaba usando.
func _soltar_maquina() -> void:
	if maquina_actual != null:
		maquina_actual.quitar_trabajador(self)
		var escritorio := maquina_actual.escritorio_de_silla()
		if escritorio != null:
			escritorio.liberar_silla(self)
	maquina_actual = null
	_en_puesto = false
	if mueble_actual != null and is_instance_valid(mueble_actual):
		mueble_actual.terminar_uso(self)
	mueble_actual = null
	_usando = false

func _no_responde() -> bool:
	if desmayado or siendo_llevado:
		mostrar_cartel("Inconsciente")
		return true
	if en_evento and not pausa_evento:
		mostrar_cartel("Ocupado: %s" % motivo_evento)
		return true
	if yendo_a_evento:
		mostrar_cartel("En camino: %s" % motivo_evento)
		return true
	return false

## Calcula el camino al destino. Si es el destino de la orden, lo guarda para poder retomarlo.
func _calcular_camino(destino: Vector2, es_destino_de_orden := true) -> bool:
	if navegacion == null or not navegacion.listo:
		return false
	var c := navegacion.camino(pies(), destino)
	if c.is_empty():
		return false
	_poner_camino(c, destino)
	if es_destino_de_orden:
		_destino_orden = destino
	return true

func _poner_camino(c: PackedVector2Array, destino: Vector2) -> void:
	_camino = c
	_idx_camino = 0
	_destino = destino
	_t_atascado = 0.0

## Avanza por el camino. Devuelve true cuando llegó (o cuando quedó trabado sin remedio).
func _seguir_camino(delta: float) -> bool:
	if _idx_camino >= _camino.size():
		return true

	var objetivo := _camino[_idx_camino]
	var dif := objetivo - pies()
	var paso := _velocidad_actual() * delta
	if dif.length() <= paso:
		_idx_camino += 1
		if _idx_camino >= _camino.size():
			velocity = dif / delta  # termina justo sobre el punto
			move_and_slide()
			velocity = Vector2.ZERO
			return true
		objetivo = _camino[_idx_camino]
		dif = objetivo - pies()

	var direccion := dif.normalized()

	# ¿Hay otro astronauta adelante? (no se revisa mientras se está corriendo para dejar pasar)
	if _desvio == Desvio.NINGUNO:
		var otro := _personaje_adelante(direccion)
		if otro != null and _resolver_encuentro(otro):
			return false

	velocity = direccion * _velocidad_actual()
	move_and_slide()
	set_corriendo(true)
	set_laburando(false)
	mirar(velocity.x)

	# Chocó de costado con otro astronauta que no vio venir
	if _desvio == Desvio.NINGUNO:
		for i in get_slide_collision_count():
			var otro := get_slide_collision(i).get_collider() as Personaje
			if otro != null and not _ignorado(otro) and _resolver_encuentro(otro):
				return false

	# Si algo lo frena (un mueble, una esquina), recalcula; si sigue trabado, se rinde.
	if get_real_velocity().length() < _velocidad_actual() * 0.1:
		_t_atascado += delta
		if _t_atascado > 0.6:
			_reintentos += 1
			if _reintentos > 2 or not _recalcular_actual():
				_reintentos = 0
				return true
	else:
		_t_atascado = 0.0
		_reintentos = 0
	return false

func _recalcular_actual() -> bool:
	if navegacion == null or not navegacion.listo:
		return false
	var c := navegacion.camino(pies(), _destino)
	if c.is_empty():
		return false
	_poner_camino(c, _destino)
	return true

func _ir_a_puesto_nuevo() -> void:
	_en_puesto = false
	set_laburando(false)
	if navegacion == null or not navegacion.listo or maquina_actual == null:
		return
	# Escritorio (o máquina encima de uno): se trabaja sentado en la silla, sin dar vueltas
	var escritorio := maquina_actual.escritorio_de_silla()
	if escritorio != null:
		var lugar := escritorio.reservar_silla(self)
		if lugar == Vector2.INF:
			mostrar_cartel("Silla ocupada")
			detener()
		elif not _calcular_camino(lugar):
			escritorio.liberar_silla(self)
			mostrar_cartel("Sin acceso")
			detener()
		return
	var puestos := maquina_actual.puntos_de_trabajo(navegacion)
	puestos.shuffle()
	var aca := pies()
	# Prefiere moverse a otro lado de la máquina, no quedarse en el mismo lugar
	puestos.sort_custom(func(a, b): return (a.distance_to(aca) > 12.0) and not (b.distance_to(aca) > 12.0))
	for p in puestos.slice(0, 10):
		if _calcular_camino(p):
			return
	# Ningún puesto alcanzable sin atravesar un muro: no puede trabajar ahí
	mostrar_cartel("Sin acceso")
	detener()

func _proceso_trabajo(delta: float) -> void:
	if maquina_actual == null or not is_instance_valid(maquina_actual):
		detener()
		return
	if not _en_puesto:
		if _seguir_camino(delta):
			if _lejos_del_puesto():
				# Sin camino calculado (por ejemplo, la grilla todavía no estaba): reintenta
				_t_puesto -= delta
				if _t_puesto <= 0.0:
					_t_puesto = 0.5
					_ir_a_puesto_nuevo()
				return
			_empezar_en_puesto()
		return

	velocity = Vector2.ZERO
	if maquina_actual.esta_apagada():
		terminar_tarea("Apagada: no se puede reparar")
		return
	var mult := afinidad("investigacion") if maquina_actual is Escritorio else afinidad("trabajo")
	if esta_feliz():
		mult *= Ajustes.actual().bonus_feliz
	maquina_actual.trabajar(delta * mult)
	# Tarea terminada: la máquina quedó al 100%
	if maquina_actual.tiene_desgaste and maquina_actual.mantenimiento >= 100.0:
		terminar_tarea("%s lista" % maquina_actual.nombre_maquina)
		return
	_t_puesto -= delta
	if _t_puesto <= 0.0 and maquina_actual.escritorio_de_silla() == null:  # en la silla no se mueve
		_ir_a_puesto_nuevo()

func _proceso_uso(delta: float) -> void:
	if mueble_actual == null or not is_instance_valid(mueble_actual):
		detener()
		return
	if not _usando:
		if _seguir_camino(delta):
			_usando = true
			_quedar_idle()
			mueble_actual.empezar_uso(self)
		return
	velocity = Vector2.ZERO
	mueble_actual.proceso_uso(self, delta)

## true si "llegó" pero en realidad está lejos de la máquina (o de la silla del escritorio).
func _lejos_del_puesto() -> bool:
	if maquina_actual == null:
		return false
	var escritorio := maquina_actual.escritorio_de_silla()
	if escritorio != null:
		return pies().distance_to(escritorio.posicion_silla()) > 10.0
	return not maquina_actual.rect_global().grow(margen_trabajo_max + 8.0).has_point(pies())

func _empezar_en_puesto() -> void:
	_en_puesto = true
	_t_puesto = randf_range(tiempo_por_puesto_min, tiempo_por_puesto_max)
	velocity = Vector2.ZERO
	set_corriendo(false)
	set_laburando(true)
	mirar(maquina_actual.rect_global().get_center().x - global_position.x)

# --- Encuentros con otros astronautas ----------------------------------------

## El primer astronauta que está adelante, cerca y en la dirección en la que camina.
func _personaje_adelante(direccion: Vector2) -> Personaje:
	var mis_pies := pies()
	for nodo in get_tree().get_nodes_in_group("astronautas"):
		var p := nodo as Personaje
		if p == null or p == self or _ignorado(p):
			continue
		var d := p.pies() - mis_pies
		var dist := d.length()
		if dist > 0.01 and dist < distancia_deteccion and direccion.dot(d / dist) > 0.6:
			return p
	return null

func _ignorado(p: Personaje) -> bool:
	if p._otro == self:
		return true  # ya estamos resolviendo un encuentro entre los dos
	return _ignorar_hasta.get(p, 0) > Time.get_ticks_msec()

func _ignorar(p: Personaje, segundos: float) -> void:
	_ignorar_hasta[p] = Time.get_ticks_msec() + int(segundos * 1000.0)

## Decide qué hacer con otro astronauta que está en el camino. Devuelve true si
## este personaje cambió de estado (espera, cede o rodea) y no tiene que avanzar este frame.
func _resolver_encuentro(otro: Personaje) -> bool:
	# Si el otro no se puede correr (está acostado, lo maneja el jugador, o ya está
	# resolviendo otro encuentro), no hay moneda: lo rodeo.
	if not otro.puede_ceder() or otro._desvio != Desvio.NINGUNO:
		return _rodear(otro)

	# Se tira una moneda para ver quién se corre
	var cedo_yo := randi() % 2 == 0
	var perdedor: Personaje = self if cedo_yo else otro
	var ganador: Personaje = otro if cedo_yo else self
	_tirar_moneda(perdedor)
	_ignorar(otro, 2.0)
	otro._ignorar(self, 2.0)

	# El ganador está quieto (trabajando o parado) y el que perdió es el que viene caminando:
	# correrse no sirve, así que el perdedor lo rodea.
	if perdedor._moviendose() and not ganador._moviendose():
		return perdedor._rodear(ganador) or perdedor == self

	if perdedor._ceder_a(ganador):
		if ganador._moviendose():
			ganador._esperar_a(perdedor)
		return true
	# El perdedor no encontró dónde correrse: prueba el otro
	if ganador._moviendose() and ganador._rodear(perdedor):
		return ganador == self
	return _rodear(otro)

## Busca un costado fuera del camino del otro y camina hasta ahí.
func _ceder_a(ganador: Personaje) -> bool:
	if navegacion == null or not navegacion.listo:
		return false
	var c := navegacion.camino_para_ceder(pies(), ganador.pies(), ganador.camino_restante())
	if c.is_empty():
		return false
	if orden == Orden.NINGUNA:
		_volver_a = pies()  # estaba quieto: después vuelve a su lugar
	if orden == Orden.TRABAJAR and _en_puesto:
		_en_puesto = false  # deja el puesto y después vuelve
	if orden == Orden.USAR and _usando:
		_usando = false  # se levanta del asiento (lo sigue teniendo reservado) y después vuelve
	_desvio = Desvio.CEDIENDO
	_otro = ganador
	_t_desvio = 0.0
	_poner_camino(c, c[c.size() - 1])
	set_laburando(false)
	return true

func _esperar_a(perdedor: Personaje) -> void:
	_desvio = Desvio.ESPERANDO
	_otro = perdedor
	_t_desvio = 0.0
	velocity = Vector2.ZERO
	set_corriendo(false)

## Recalcula el camino rodeando al otro. Si no hay forma, espera un momento y vuelve a intentar;
## después de varios intentos abandona la orden.
func _rodear(otro: Personaje) -> bool:
	_ignorar(otro, 1.5)
	if navegacion != null and navegacion.listo:
		var evitar: Array[Vector2] = [otro.pies()]
		var c := navegacion.camino_evitando(pies(), _destino, evitar)
		if not c.is_empty():
			_poner_camino(c, _destino)
			_intentos_rodear = 0
			return false  # sigue caminando por el camino nuevo
	_intentos_rodear += 1
	if _intentos_rodear > 3:
		_intentos_rodear = 0
		mostrar_cartel("Sin paso")
		if orden == Orden.TRABAJAR:
			_ir_a_puesto_nuevo()
		else:
			detener()
		return true
	# Espera un ratito sin otro asignado y reintenta
	_desvio = Desvio.ESPERANDO
	_otro = null
	_t_desvio = 1.6  # el timeout de ESPERANDO es 2.5 s: espera ~0.9 s
	velocity = Vector2.ZERO
	set_corriendo(false)
	return true

func _proceso_desvio(delta: float) -> void:
	_t_desvio += delta
	if _otro != null and not is_instance_valid(_otro):
		_otro = null
	match _desvio:
		Desvio.ESPERANDO:
			velocity = Vector2.ZERO
			var listo := _otro == null or _otro._desvio == Desvio.CEDIDO or _otro._desvio == Desvio.NINGUNO
			if (listo and _otro != null) or _t_desvio > 2.5:
				_desvio = Desvio.NINGUNO
				_otro = null
		Desvio.CEDIENDO:
			if _seguir_camino(delta) or _t_desvio > 3.0:
				_desvio = Desvio.CEDIDO
				_t_desvio = 0.0
				_quedar_idle()
		Desvio.CEDIDO:
			velocity = Vector2.ZERO
			var paso := _otro == null or _otro.pies().distance_to(pies()) > 32.0 or not _otro._moviendose()
			if (paso and _t_desvio > 0.3) or _t_desvio > 4.0:
				_retomar()

## Termina el desvío y vuelve a lo que estaba haciendo.
func _retomar() -> void:
	var otro := _otro
	_desvio = Desvio.NINGUNO
	_otro = null
	if otro != null:
		_ignorar(otro, 1.0)
	match orden:
		Orden.MOVER:
			if not _calcular_camino(_destino_orden):
				detener()
		Orden.TRABAJAR:
			# Vuelve al puesto en el que estaba (o a uno nuevo si ya no se llega)
			if not _calcular_camino(_destino_orden):
				_ir_a_puesto_nuevo()
		Orden.USAR:
			if not _calcular_camino(_destino_orden):
				detener()
		Orden.PASEO:
			if not _calcular_camino(_destino_orden):
				_fin_de_paseo()
		Orden.NINGUNA:
			if _volver_a != Vector2.INF and _calcular_camino(_volver_a):
				orden = Orden.MOVER
			else:
				_quedar_idle()
	_volver_a = Vector2.INF

## Corta el desvío sin retomar (por ejemplo, al recibir una orden nueva) y avisa al otro.
func _terminar_desvio() -> void:
	var otro := _otro
	_desvio = Desvio.NINGUNO
	_otro = null
	_volver_a = Vector2.INF
	if otro != null and is_instance_valid(otro) and otro._otro == self:
		if otro._desvio == Desvio.ESPERANDO:
			otro._desvio = Desvio.NINGUNO
			otro._otro = null
		elif otro._desvio == Desvio.CEDIENDO or otro._desvio == Desvio.CEDIDO:
			otro._retomar()

func _tirar_moneda(perdedor: Personaje) -> void:
	if _reproductor_moneda != null and sonido_moneda != null:
		_reproductor_moneda.play()
	mostrar_cartel("Moneda: cede %s" % perdedor.obtener_nombre())

## Muestra un texto corto sobre la cabeza durante un momento.
func mostrar_cartel(texto: String, segundos := 1.4) -> void:
	if _cartel == null:
		return
	_cartel.text = texto
	_cartel.visible = true
	_cartel.modulate.a = 1.0
	if _tween_cartel != null:
		_tween_cartel.kill()
	_tween_cartel = create_tween()
	_tween_cartel.tween_interval(segundos)
	_tween_cartel.tween_property(_cartel, "modulate:a", 0.0, 0.4)
	_tween_cartel.tween_callback(func(): _cartel.visible = false)

func _crear_cartel_y_sonido() -> void:
	_reproductor_moneda = AudioStreamPlayer2D.new()
	_reproductor_moneda.stream = sonido_moneda
	add_child(_reproductor_moneda)

	_cartel = Label.new()
	_cartel.visible = false
	_cartel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cartel.z_index = 20
	_cartel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cartel.add_theme_font_size_override("font_size", 8)
	_cartel.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_cartel.add_theme_constant_override("outline_size", 3)
	_cartel.size = Vector2(90, 12)
	_cartel.position = Vector2(-45, -36)
	add_child(_cartel)

# --- Salud -------------------------------------------------------------------

# Llamado desde base.gd en cada frame con las condiciones de la base
# Llamado desde base.gd en cada frame con los recursos de la base
func actualizar_salud(delta: float, oxigeno: float, radiacion: float, lluvia_particulas: bool) -> void:
	# Fuera de la base por un evento: sus valores quedan como estaban hasta que vuelva
	if en_evento and evento_fuera:
		var t := int(maxf(tiempo_evento, 0.0))
		estado_alerta = "Fuera %d:%02d" % [t / 60, t % 60]
		estado_actualizado.emit(self)
		return
	var factor_afin := afinidad("salud")

	# 1. El oxígeno marca qué tan rápido baja la vida: con 100% es normal, con 0% va 5 veces más rápido
	var mult_o2 := 1.0 + (100.0 - oxigeno) / 25.0

	# 2. Avance de hambre y sueño (las camas los recuperan mientras está acostado)
	var aj := Ajustes.actual()
	var gasto_base := 0.25 * factor_afin * delta * mult_o2
	var extra_trabajo := 1.3 if laburando and orden == Orden.TRABAJAR else 1.0  # comer no da más hambre

	_t_descansado = maxf(0.0, _t_descansado - delta)
	_t_satisfecho = maxf(0.0, _t_satisfecho - delta)
	if desmayado:
		# Inconsciente: no gasta, y recupera energía más lento (en la cama la recupera la cama)
		if not en_cama:
			sueno = maxf(0.0, sueno - ritmo_recuperar_sueno() * delta)
	elif not durmiendo:
		if _t_satisfecho <= 0.0:
			hambre = clampf(hambre + gasto_base * extra_trabajo * aj.hambre, 0.0, 100.0)
		if _t_descansado <= 0.0:
			sueno = clampf(sueno + ritmo_cansancio() * factor_afin * mult_o2 * aj.sueno * delta, 0.0, 100.0)
	if durmiendo:
		dano_ambiental = maxf(0.0, dano_ambiental - 2.5 * delta)

	# Llegó al 100 de energía o de comida: un rato sin que baje
	var era_feliz := esta_feliz()
	if sueno <= 0.0 and _sueno_previo > 0.0:
		_t_descansado = aj.duracion_descansado
		mostrar_cartel("¡Descansado!")
	if hambre <= 0.0 and _hambre_previa > 0.0:
		_t_satisfecho = aj.duracion_satisfecho
		mostrar_cartel("¡Satisfecho!")
	if esta_feliz() and not era_feliz:
		mostrar_cartel("¡Feliz! Trabaja más rápido", 2.0)
	_sueno_previo = sueno
	_hambre_previa = hambre

	# Comida en 0: la salud baja directamente
	if hambre >= 100.0:
		dano_ambiental = clampf(dano_ambiental + dano_por_hambre * aj.dano_hambre * delta, 0.0, 100.0)

	# 3. Daño ambiental directo
	var dano_extra := 0.0
	if oxigeno < 20.0:
		dano_extra += 1.5 * delta
	if radiacion > 80.0:
		dano_extra += 0.5 * delta  # por encima de 80% de radiación la salud empieza a bajar
	if lluvia_particulas and en_exterior:
		dano_extra += 2.0 * delta

	dano_ambiental = clampf(dano_ambiental + dano_extra * aj.dano_salud, 0.0, 100.0)

	# 4. Cálculo final de Salud
	var saciedad := 100.0 - hambre
	var descanso := 100.0 - sueno
	var salud_base := (saciedad + descanso) * 0.5
	salud = clampf(salud_base - dano_ambiental, 0.0, 100.0)

	# 5. Inconsciencia: dura un tiempo fijo, en el piso o en cualquier cama
	_t_gracia = maxf(0.0, _t_gracia - delta)
	if desmayado:
		_t_inconsciente += delta
		if dormido_agotado and salud <= 0.0:
			dormido_agotado = false  # ahora es por salud: la roomba lo lleva al hospital
		# Mientras la roomba lo lleva espera a que lo deje en la cama
		if _t_inconsciente >= aj.tiempo_inconsciente and not siendo_llevado:
			_despertar()
	elif _t_gracia <= 0.0:
		if salud <= 0.0:
			_desmayar()
		elif sueno >= 100.0:
			_desmayar(true)  # agotado: se duerme donde esté

	_actualizar_alerta(oxigeno, radiacion, lluvia_particulas)
	_actualizar_barra_flotante()
	estado_actualizado.emit(self)

## Sueño que recupera por segundo durmiendo: de 0 a 100 en Ajustes.noche_para_dormir de la noche.
## Inconsciente, Ajustes.recuperacion_inconsciente de eso. Lo usan las camas y el piso.
func ritmo_recuperar_sueno() -> float:
	var aj := Ajustes.actual()
	var ritmo := 100.0 / maxf(_horas_durmiendo() * _segundos_por_hora(), 0.01) * aj.velocidad_dormir
	if desmayado:
		ritmo *= aj.recuperacion_inconsciente
	return ritmo


## Sueño que gana por segundo despierto: lo que recuperó en la noche le dura el resto del sol.
func ritmo_cansancio() -> float:
	var horas_despierto := maxf(Recursos.DURACION_SOL_HORAS - _horas_durmiendo(), 1.0)
	return 100.0 / (horas_despierto * _segundos_por_hora())


func _horas_durmiendo() -> float:
	var r := Recursos.de(self)
	var noche := r.horas_de_noche() if r != null else 12.15
	return noche * Ajustes.actual().noche_para_dormir


func _segundos_por_hora() -> float:
	var r := Recursos.de(self)
	return r.segundos_por_hora() if r != null else 60.0


func esta_descansado() -> bool:
	return _t_descansado > 0.0


func esta_satisfecho() -> bool:
	return _t_satisfecho > 0.0


## Descansado y satisfecho a la vez: trabaja Ajustes.bonus_feliz veces más rápido.
func esta_feliz() -> bool:
	return esta_descansado() and esta_satisfecho()


func _desmayar(por_sueno := false) -> void:
	detener()
	yendo_a_evento = false
	desmayado = true
	dormido_agotado = por_sueno
	_t_inconsciente = 0.0
	corriendo = false
	laburando = false
	_pausar_animaciones()
	if not en_cama:
		rotation = -PI / 2.0  # queda tirado en el piso
	mostrar_cartel("¡Se quedó dormido!" if por_sueno else "¡Inconsciente!")

func _despertar() -> void:
	desmayado = false
	dormido_agotado = false
	_t_gracia = Ajustes.actual().gracia_desmayo
	_actualizar_animaciones(true)  # vuelve a animarse
	if not en_cama and not siendo_llevado:
		rotation = 0.0
	mostrar_cartel("¡Puede moverse!", 2.5)
	var r := Recursos.de(self)
	if r != null:
		r.avisar("%s recuperó la conciencia y puede moverse" % obtener_nombre(), 0, self)

func comer(cantidad: float = 40.0, bonus_calidad: float = 0.0) -> void:
	hambre = maxf(0.0, hambre - cantidad)
	dano_ambiental = maxf(0.0, dano_ambiental - bonus_calidad)

## Multiplicador de Personaje/afinidades.gd: "salud", "trabajo" o "investigacion".
func afinidad(tipo: String) -> float:
	return Afinidades.de(obtener_nombre(), tipo)

func obtener_nombre() -> String:
	return NOMBRES.get(cabeza, "Astronauta")

func _actualizar_alerta(oxigeno: float, radiacion: float, lluvia: bool) -> void:
	if desmayado:
		var falta := int(ceilf(maxf(Ajustes.actual().tiempo_inconsciente - _t_inconsciente, 0.0)))
		estado_alerta = ("Dormido (agotado) %ds" if dormido_agotado else "Inconsciente %ds") % falta
	elif en_evento:
		var t := int(maxf(tiempo_evento, 0.0))
		estado_alerta = ("Pausa %d:%02d" if en_pausa_evento() else "Ocupado %d:%02d") % [t / 60, t % 60]
	elif lluvia and en_exterior:
		estado_alerta = "¡Partículas!"
	elif oxigeno < 20.0:
		estado_alerta = "¡Sin O2!"
	elif radiacion > 80.0:
		estado_alerta = "¡Radiación!"
	elif hambre >= 100.0:
		estado_alerta = "¡Sin comida!"
	elif hambre > 70.0:
		estado_alerta = "Hambre"
	elif sueno > 75.0:
		estado_alerta = "Sueño"
	elif en_cama and durmiendo:
		estado_alerta = "Descansando"
	elif orden == Orden.TRABAJAR:
		if _en_puesto and maquina_actual != null and maquina_actual.en_equipo():
			estado_alerta = "¡Trabajo en Equipo!"
		else:
			estado_alerta = "Trabajando (feliz)" if esta_feliz() else "Trabajando"
	elif orden == Orden.USAR and _usando:
		estado_alerta = "Comiendo"
	elif esta_feliz():
		estado_alerta = "Feliz"
	elif esta_descansado():
		estado_alerta = "Descansado"
	elif esta_satisfecho():
		estado_alerta = "Satisfecho"
	else:
		estado_alerta = "Bien"

# --- Globos de pensamiento y linterna -----------------------------------------

func _crear_globo_y_linterna() -> void:
	_globo = Globo.new()
	_globo.position = Vector2(9, -30)
	_globo.z_index = 15
	_globo.visible = false
	add_child(_globo)
	if usar_linterna:
		_linterna = PointLight2D.new()
		_linterna.texture = _cono()
		_linterna.texture_scale = alcance_linterna / (TAM_CONO * 0.5)
		_linterna.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # luz pixelada
		_linterna.position = Vector2(0, 6)
		_linterna.color = Color(1.0, 0.95, 0.8)
		_linterna.energy = 0.0
		_linterna.enabled = false
		add_child(_linterna)

func _actualizar_globo() -> void:
	if _globo == null:
		return
	var con_hambre := hambre >= umbral_globo_hambre
	var con_sueno := sueno >= umbral_globo_sueno
	_globo.visible = (con_hambre or con_sueno) and not desmayado and not siendo_llevado and visible
	if not _globo.visible:
		return
	var tipo := Globo.Tipo.COMIDA if con_hambre else Globo.Tipo.SUENO
	if con_hambre and con_sueno and int(Time.get_ticks_msec() / 1500) % 2 == 1:
		tipo = Globo.Tipo.SUENO  # con las dos cosas, alterna
	_globo.set_tipo(tipo)

func _actualizar_linterna(delta: float) -> void:
	if _linterna == null:
		return
	var r := Recursos.de(self)
	var oscuridad := 1.0 - (r.luz() if r != null else 1.0)
	var prendida := oscuridad > 0.05 and not en_cama and not desmayado and not siendo_llevado and visible
	_linterna.enabled = prendida
	if not prendida:
		return
	_linterna.energy = energia_linterna * oscuridad
	if velocity.length() > 1.0:
		_dir_linterna = velocity.normalized()
	_linterna.rotation = lerp_angle(_linterna.rotation, _dir_linterna.angle(), minf(1.0, delta * 10.0))
	# El cono arranca un poco adelante del cuerpo, no desde el centro
	_linterna.position = Vector2(0, 6) + Vector2.from_angle(_linterna.rotation) * separacion_linterna

## Cono de luz: vértice en el centro de la textura, abierto hacia la derecha (+x).
const TAM_CONO := 48  # textura chica con filtro nearest: se ve pixelada

static func _cono() -> ImageTexture:
	if _textura_cono != null:
		return _textura_cono
	var tam := TAM_CONO
	var img := Image.create(tam, tam, false, Image.FORMAT_RGBA8)
	var centro := Vector2(tam, tam) * 0.5
	var apertura := deg_to_rad(28.0)
	for y in tam:
		for x in tam:
			var d := Vector2(x + 0.5, y + 0.5) - centro
			var dist := d.length() / (tam * 0.5)
			var a := 0.0
			if dist <= 1.0:
				var ang := absf(d.angle())
				var borde := clampf(1.0 - (ang - apertura * 0.6) / (apertura * 0.4), 0.0, 1.0)
				var cerca := clampf(1.0 - dist, 0.0, 1.0)
				a = borde * cerca * cerca
				a = maxf(a, clampf(1.0 - dist * 6.0, 0.0, 1.0) * 0.6)  # un poco de luz alrededor de los pies
			a = floorf(a * 4.0 + 0.5) / 4.0  # pocos niveles de brillo: bordes escalonados, estilo pixel
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_textura_cono = ImageTexture.create_from_image(img)
	return _textura_cono

func _configurar_barra_flotante() -> void:
	if barra_salud == null:
		return
	barra_salud.mouse_filter = Control.MOUSE_FILTER_IGNORE  # que no tape los clics del point and click
	var sb_fondo := StyleBoxFlat.new()
	sb_fondo.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	barra_salud.add_theme_stylebox_override("background", sb_fondo)

	_estilo_relleno = StyleBoxFlat.new()
	_estilo_relleno.bg_color = Color(0.2, 0.85, 0.35)
	barra_salud.add_theme_stylebox_override("fill", _estilo_relleno)

func _actualizar_barra_flotante() -> void:
	if barra_salud == null:
		return
	barra_salud.value = salud
	if _estilo_relleno != null:
		if salud > 60.0:
			_estilo_relleno.bg_color = Color(0.2, 0.85, 0.35)  # Verde
		elif salud > 30.0:
			_estilo_relleno.bg_color = Color(0.95, 0.75, 0.15) # Amarillo
		else:
			_estilo_relleno.bg_color = Color(0.9, 0.2, 0.2)    # Rojo

# --- API pública de animaciones ----------------------------------------------
func set_corriendo(valor: bool) -> void:
	if valor != corriendo:
		corriendo = valor
		_actualizar_animaciones()

func set_laburando(valor: bool) -> void:
	if valor != laburando:
		laburando = valor
		_actualizar_animaciones()

func alternar_laburar() -> void:
	set_laburando(not laburando)

func mirar(dir_x: float) -> void:
	if dir_x == 0.0:
		return
	for s in [sprite_cuerpo, sprite_brazo, sprite_cabeza, sprite_casco]:
		s.flip_h = dir_x < 0.0
	if velocity.length() <= 1.0:
		_dir_linterna = Vector2(signf(dir_x), 0.0)

func _actualizar_animaciones(forzar := false) -> void:
	if desmayado:
		_pausar_animaciones()
		return
	var anim_cuerpo := &"correr_base" if corriendo else &"idle_base"
	var anim_brazo: StringName
	if laburando:
		anim_brazo = &"laburar_brazo"
	elif corriendo:
		anim_brazo = &"correr_brazo"
	else:
		anim_brazo = &"idle_brazo"
	_reproducir(sprite_cuerpo, anim_cuerpo, null, forzar)
	_reproducir(sprite_brazo, anim_brazo, sprite_cuerpo, forzar)

func _reproducir(sprite: AnimatedSprite2D, anim: StringName, referencia: AnimatedSprite2D, forzar: bool) -> void:
	if not forzar and sprite.animation == anim and sprite.is_playing():
		return
	sprite.play(anim)
	if referencia != null and referencia.sprite_frames.get_frame_count(referencia.animation) \
			== sprite.sprite_frames.get_frame_count(anim):
		sprite.set_frame_and_progress(referencia.frame, referencia.frame_progress)
	else:
		sprite.set_frame_and_progress(0, 0.0)

## Congela el cuadro actual de todas las capas (por ejemplo, al quedar inconsciente).
func _pausar_animaciones() -> void:
	for s in [sprite_cuerpo, sprite_brazo, sprite_cabeza, sprite_casco]:
		if s != null:
			s.pause()

func _aplicar_cabeza() -> void:
	sprite_cabeza.stop()
	sprite_cabeza.animation = &"Cabezas"
	sprite_cabeza.frame = int(cabeza)

## Fuera de la base (suelo marciano) se pone el casco; al volver se lo saca.
func set_afuera(valor: bool) -> void:
	if valor == afuera:
		return
	afuera = valor
	en_exterior = valor
	if not con_casco:
		return
	# Animación "Casco": cuadro 0 vacío, cuadro 1 el casco puesto
	if _tween_casco != null:
		_tween_casco.kill()
	sprite_casco.stop()
	sprite_casco.animation = &"Casco"
	sprite_casco.visible = true
	_tween_casco = create_tween()
	if valor:
		sprite_casco.frame = 0
		_tween_casco.tween_interval(0.2)
		_tween_casco.tween_callback(func(): sprite_casco.frame = 1)
		mostrar_cartel("Casco puesto", 1.0)
	else:
		sprite_casco.frame = 1
		_tween_casco.tween_interval(0.2)
		_tween_casco.tween_callback(func():
			sprite_casco.frame = 0
			sprite_casco.visible = false)

func _aplicar_casco() -> void:
	sprite_casco.stop()
	sprite_casco.animation = &"Casco"
	sprite_casco.frame = 1 if afuera else 0
	sprite_casco.visible = con_casco and afuera


## Globo de pensamiento sobre la cabeza: una manzana (hambre) o "Zz" (sueño).
class Globo extends Node2D:
	enum Tipo { COMIDA, SUENO }
	var tipo := Tipo.COMIDA
	var _t := 0.0

	func set_tipo(t: Tipo) -> void:
		if t != tipo:
			tipo = t
			queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		position.y = -30.0 + sin(_t * 3.0) * 1.0  # flota un poquito
		queue_redraw()

	func _draw() -> void:
		var borde := Color(0.15, 0.17, 0.22)
		var fondo := Color(1, 1, 1, 0.95)
		# Burbujitas hacia la cabeza y el globo
		draw_circle(Vector2(-6, 9), 1.6, borde)
		draw_circle(Vector2(-6, 9), 1.0, fondo)
		draw_circle(Vector2(-3, 6), 2.4, borde)
		draw_circle(Vector2(-3, 6), 1.7, fondo)
		draw_circle(Vector2(3, -2), 7.5, borde)
		draw_circle(Vector2(3, -2), 6.7, fondo)
		if tipo == Tipo.COMIDA:
			draw_circle(Vector2(3, -1), 3.2, Color(0.88, 0.2, 0.2))      # manzana
			draw_rect(Rect2(2.6, -6.2, 0.9, 2.2), Color(0.4, 0.25, 0.1)) # cabito
			draw_circle(Vector2(4.6, -5.0), 1.1, Color(0.3, 0.75, 0.3))   # hojita
		else:
			var f := ThemeDB.fallback_font
			draw_string(f, Vector2(-1.5, 1), "Z", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.25, 0.35, 0.8))
			draw_string(f, Vector2(3.5, -2), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Color(0.25, 0.35, 0.8))
