class_name Tutorial
extends Node
## Tutorial: explica controles y mecánicas. Se activa con Ajustes.tutorial_activado.
## Cada paso sale una sola vez por partida. Hay tres tipos de paso:
## - "info": ventana que pausa el juego y se cierra con "Siguiente" (puede destacar algo del
##   HUD; si no destaca nada, pone gris toda la pantalla).
## - "tarea": instrucción que NO pausa; avanza sola cuando el jugador hace lo que pide
##   (se tilda y, un segundo después, pasa al siguiente). Se puede "Saltar paso".
## - "aviso": explicación de una máquina que NO pausa; queda hasta que se toca "Siguiente".
## Tareas y avisos oscurecen toda la pantalla menos la zona indicada (sin bloquear los clics).
##
## Al empezar: objetivo, elegir un astronauta, reparar una máquina, trabajo en equipo, mover
## la cámara, la tripulación, sus bonos (satisfecho/descansado/feliz) y cada recurso; al terminar, la cámara se aleja para ver el mapa.
## Después, la primera vez: tocar cada máquina, un astronauta con hambre o sueño (hay que
## llevarlo al comedor o a una cama) y la primera exploración.

var base: Node   # base.gd
var hud: Node
var eventos: Eventos

var _cola: Array[Dictionary] = []
var _abierta := false
var _en_cadena := false
var _pausa_previa := false
var _vistos := {}
var _t_revisar := 0.0
var _tarea: Dictionary = {}
var _intro := false
var _siguiendo_reparacion := false
var _completando := false   # tarea cumplida: muestra el tilde un segundo antes de avanzar
var _t_aviso := 0.0
const ESPERA_TILDE := 1.0
const DURACION_AVISO := 10.0

## Los textos de las máquinas y mecánicas están en Base/textos_ayuda.gd (también los usa la
## ventana de Información).
const TextosAyuda := preload("res://Base/textos_ayuda.gd")


func iniciar() -> void:
	if not Ajustes.actual().tutorial_activado:
		return
	eventos.evento_iniciado.connect(_al_iniciar_evento)
	_intro = true
	_agregar_info("objetivo", "Objetivo del juego", "¡Tu misión en Marte!
Explorá Marte, descubrí sus secretos y completá 4 investigaciones.
Pero no te olvides de tu equipo: cuidá la base, mantené la energía y el oxígeno, ¡y protegé a todos de la radiación!
¡Marte cuenta con vos, astronauta!", null, false, Callable(), true)
	_agregar_tarea("elegir", "Elegí un astronauta",
		"Hacé clic en un astronauta para elegirlo: se marca con un borde verde. También podés elegirlos con su tarjeta de la izquierda, las teclas 1, 2 y 3 o las flechas ← →.",
		func(): return _rect_astronauta(_primer_astronauta()),
		func(): return base._activo() != null)
	var peor := _peor_maquina()
	_agregar_tarea("reparar", "Repará una máquina",
		"Las máquinas se gastan: con borde amarillo necesitan ayuda y en rojo están por romperse. Con el astronauta elegido, hacé clic en esta máquina y mirá cómo camina hasta ella para repararla.",
		func(): return _zona_reparacion(peor),
		func(): return _alguien_reparando(),
		peor,
		func(): return "Caminando hacia la máquina..." if _quien_va_a_reparar() != null else "")
	_agregar_info("equipo", "Trabajo en equipo",
		TextosAyuda.texto("equipo"))
	_agregar_tarea("camara", "Mové la cámara",
		"Usá la rueda del mouse (o la barra de zoom de la derecha) para acercar y alejar, y hacé clic y arrastrá para mover el mapa. Al elegir un astronauta, lo seguimos por la base.",
		Callable(),
		func(): return base.uso_rueda and base.uso_arrastre,
		null,
		func(): return "%s Zoom    %s Arrastrar" % ["✔" if base.uso_rueda else "○", "✔" if base.uso_arrastre else "○"])
	_agregar_info("tripulacion", "Tu tripulación",
		TextosAyuda.texto("tripulacion"),
		null, false, func(): return hud.rect_tripulacion())
	_agregar_info("bonos", "Bonos de salud",
		TextosAyuda.texto("bonos"),
		null, false, func(): return hud.rect_tripulacion())
	_agregar_info("rec_energia", "Recurso: Energía",
		TextosAyuda.texto("rec_energia"),
		null, false, func(): return hud.rect_recurso("energia"))
	_agregar_info("rec_oxigeno", "Recurso: Oxígeno",
		TextosAyuda.texto("rec_oxigeno"),
		null, false, func(): return hud.rect_recurso("oxigeno"))
	_agregar_info("rec_radiacion", "Recurso: Radiación",
		TextosAyuda.texto("rec_radiacion"),
		null, false, func(): return hud.rect_recurso("radiacion"))
	_mostrar_siguiente.call_deferred()


## true mientras el tutorial tiene algo en pantalla o pendiente (los eventos esperan).
func ocupado() -> bool:
	return _abierta or not _cola.is_empty()


func _process(delta: float) -> void:
	if not _tarea.is_empty():
		_seguir_tarea(delta)
	elif not _abierta and not _cola.is_empty():
		_mostrar_siguiente()  # quedó esperando a que terminara un evento
	_t_revisar -= delta
	if _t_revisar > 0.0 or not Ajustes.actual().tutorial_activado or eventos == null:
		return
	_t_revisar = 0.5
	for p in eventos.tripulacion:
		if not is_instance_valid(p) or not p.visible or p.desmayado or p.en_evento:
			continue
		if p.hambre >= p.umbral_globo_hambre and not _vistos.has("hambre"):
			var comedor := _mas_cercano("comedores", p, false)
			if comedor != null:
				_agregar_tarea("hambre", "¡%s tiene hambre!" % p.obtener_nombre(),
					"La manzana sobre su cabeza avisa que necesita comer. Elegilo y hacé clic en el comedor. Si la comida llega a cero, pierde salud.",
					func(): return comedor.rect_mesa().grow(16.0),
					func(): return p.orden == Personaje.Orden.USAR or p.hambre < p.umbral_globo_hambre,
					comedor)
				_mostrar_siguiente()
				return
		if p.sueno >= p.umbral_globo_sueno and not _vistos.has("sueno"):
			var cama := _mas_cercano("camas", p, true)
			if cama != null:
				_agregar_tarea("sueno", "¡%s tiene sueño!" % p.obtener_nombre(),
					"El \"Zz\" sobre su cabeza avisa que necesita dormir. Elegilo y hacé clic en esta cama. Si la energía llega a cero, se duerme donde esté.",
					func(): return Rect2(cama.global_position - Vector2(14, 22), Vector2(28, 44)),
					func(): return p.en_cama or p.quiere_acostarse or p.sueno < p.umbral_globo_sueno,
					cama)
				_mostrar_siguiente()
				return


## La primera vez que se toca cada tipo de máquina, explica para qué sirve.
func maquina_tocada(m: Maquina) -> void:
	if not Ajustes.actual().tutorial_activado:
		return
	var tipo := String(m.tipo_ajuste())
	var datos: Array = TextosAyuda.MAQUINAS.get(tipo, TextosAyuda.MAQUINAS["otras"])
	_agregar({"id": "maq_" + tipo, "tipo": "aviso", "titulo": datos[0], "texto": datos[1],
			"foco": m, "zona": func(): return m.rect_global() if is_instance_valid(m) else Rect2(),
			"condicion": func(): return false}, true)
	_mostrar_siguiente.call_deferred()


func _al_iniciar_evento(ev: Dictionary) -> void:
	if _es_exploracion(ev):
		_agregar_info("exploracion", "Las exploraciones",
			TextosAyuda.texto("exploracion"),
			_rover(), true)
		_mostrar_siguiente.call_deferred()  # aparece encima de la ventana del evento


# --- Cola de pasos ---------------------------------------------------------------

## zona_pantalla: Callable que devuelve un rectángulo de la pantalla a destacar (por ejemplo,
## una barra del HUD); Callable() = sin foco.
## grande: ventana grande y centrada (el objetivo del juego).
func _agregar_info(id: String, titulo: String, texto: String, foco: Node2D = null, primero := false,
		zona_pantalla: Callable = Callable(), grande := false) -> void:
	_agregar({"id": id, "tipo": "info", "titulo": titulo, "texto": texto, "foco": foco,
			"zona_pantalla": zona_pantalla, "grande": grande}, primero)


## zona: Callable que devuelve el rectángulo del mundo a destacar (Callable() = sin oscurecer).
## condicion: Callable que devuelve true cuando el jugador ya hizo lo que se pide.
func _agregar_tarea(id: String, titulo: String, texto: String, zona: Callable, condicion: Callable,
		foco: Node2D = null, progreso: Callable = Callable()) -> void:
	_agregar({"id": id, "tipo": "tarea", "titulo": titulo, "texto": texto, "zona": zona,
			"condicion": condicion, "foco": foco, "progreso": progreso}, false)


func _agregar(paso: Dictionary, primero: bool) -> void:
	if _vistos.has(paso["id"]):
		return
	_vistos[paso["id"]] = true
	if primero:
		_cola.push_front(paso)
	else:
		_cola.append(paso)


func _mostrar_siguiente() -> void:
	if _abierta or _cola.is_empty():
		return
	# Con un evento en pantalla (o en camino) no se explica nada encima, salvo la explicación
	# de la exploración, que va justamente sobre ese evento
	if eventos != null and eventos.ocupado() and _cola[0]["id"] != "exploracion":
		return
	var paso: Dictionary = _cola.pop_front()
	if not _en_cadena:
		_en_cadena = true
		_pausa_previa = get_tree().paused  # por ejemplo, si hay una ventana de evento abierta
	_abierta = true
	var foco = paso.get("foco")
	if paso["tipo"] == "tarea" or paso["tipo"] == "aviso":
		# No pausa: en las tareas hay que jugar para cumplirlas; los avisos solo se leen
		get_tree().paused = _pausa_previa
		_tarea = paso
		_completando = false
		_t_aviso = DURACION_AVISO
		if foco != null and is_instance_valid(foco):
			base.enfocar(foco)
		if paso["tipo"] == "aviso":
			hud.mostrar_instruccion(paso["titulo"], paso["texto"], _cerrar_tarea, "Siguiente")
		else:
			hud.mostrar_instruccion(paso["titulo"], paso["texto"], _cerrar_tarea)
		_seguir_tarea(0.0)
		return
	if foco != null and is_instance_valid(foco):
		base.enfocar_inmediato(foco)
	get_tree().paused = true
	var zona: Callable = paso.get("zona_pantalla", Callable())
	var con_foco := zona.is_valid()
	if con_foco:
		hud.poner_foco(zona.call(), true)
	var boton := "Siguiente"  # las explicaciones siempre avanzan con "Siguiente"
	var al_cerrar := func():
		hud.poner_foco(Rect2(), false)
		_paso_terminado()
	# Gris parejo en toda la pantalla; más suave si la cámara está mostrando algo del mapa,
	# más fuerte para el objetivo, y nada si el foco ya oscurece todo menos una zona
	var grande := bool(paso.get("grande", false))
	var gris := 0.72 if grande else 0.6
	if con_foco:
		gris = 0.0
	elif foco != null and is_instance_valid(foco):
		gris = 0.3
	hud.mostrar_tutorial(paso["titulo"], paso["texto"], boton, al_cerrar, gris, grande)


## Actualiza el foco oscuro (la zona se mueve con la cámara) y revisa si ya se cumplió.
func _seguir_tarea(delta: float) -> void:
	if _tarea.is_empty():
		return
	var zona: Callable = _tarea.get("zona", Callable())
	var rect := Rect2()
	if zona.is_valid():
		rect = zona.call()
	if rect.has_area():
		var pantalla: Rect2 = base.get_viewport().get_canvas_transform() * rect.grow(6.0)
		hud.poner_foco(pantalla, true)
	else:
		hud.poner_foco(Rect2(), false)
	if _completando:
		return
	if _tarea["tipo"] == "aviso":
		return  # las explicaciones de máquinas quedan hasta tocar "Siguiente"

	var progreso: Callable = _tarea.get("progreso", Callable())
	if progreso.is_valid():
		hud.progreso_instruccion(progreso.call())
	var condicion: Callable = _tarea["condicion"]
	if condicion.call():
		_completar_tarea()


## Tarea cumplida: se tilda, espera un segundo y recién ahí pasa al siguiente paso.
func _completar_tarea() -> void:
	if _tarea.is_empty() or _completando:
		return
	_completando = true
	var progreso: Callable = _tarea.get("progreso", Callable())
	var antes: String = progreso.call() + "    " if progreso.is_valid() else ""
	hud.progreso_instruccion(antes + "✔ ¡Listo!")
	var tarea := _tarea
	get_tree().create_timer(ESPERA_TILDE).timeout.connect(func():
		if _tarea == tarea:
			_cerrar_tarea())


## Cierra la tarea o el aviso ya mismo (Saltar paso, Siguiente, o después del tilde).
func _cerrar_tarea() -> void:
	if _tarea.is_empty():
		return
	_tarea = {}
	_completando = false
	hud.ocultar_instruccion()
	_paso_terminado()


func _paso_terminado() -> void:
	_abierta = false
	if not _cola.is_empty():
		_mostrar_siguiente()
		return
	_en_cadena = false
	get_tree().paused = _pausa_previa
	if _intro:
		_intro = false
		base.vista_general()  # terminó el tutorial inicial: la cámara se aleja


# --- Ayudas -------------------------------------------------------------------

func _primer_astronauta() -> Personaje:
	for p in eventos.tripulacion:
		if is_instance_valid(p) and p.visible:
			return p
	return null


func _rect_astronauta(p: Personaje) -> Rect2:
	if p == null or not is_instance_valid(p):
		return Rect2()
	return Rect2(p.global_position - Vector2(10, 18), Vector2(20, 36))


## Ya llegó a la máquina y está reparando.
func _alguien_reparando() -> bool:
	for p in eventos.tripulacion:
		if is_instance_valid(p) and p.esta_en_puesto() and p.maquina_actual != null \
				and p.maquina_actual.tiene_desgaste:
			return true
	return false


## El astronauta que va (o ya está) reparando una máquina, o null.
func _quien_va_a_reparar() -> Personaje:
	for p in eventos.tripulacion:
		if is_instance_valid(p) and p.orden == Personaje.Orden.TRABAJAR and p.maquina_actual != null \
				and p.maquina_actual.tiene_desgaste:
			return p
	return null


## Antes de la orden, la máquina; después, el astronauta caminando y la máquina a la que va
## (y la cámara lo sigue).
func _zona_reparacion(peor: Maquina) -> Rect2:
	var p := _quien_va_a_reparar()
	if p != null:
		if not _siguiendo_reparacion:
			_siguiendo_reparacion = true
			base.seguir_activo()
		return _rect_astronauta(p).merge(p.maquina_actual.rect_global())
	return peor.rect_global() if is_instance_valid(peor) else Rect2()


func _es_exploracion(ev: Dictionary) -> bool:
	if String(ev.get("id", "")) == "nueva_exploracion":
		return true
	for clave in ["opcion_a", "opcion_b"]:
		var op: Dictionary = ev.get(clave, {})
		for lado in ["gana", "pierde"]:
			var x = op.get(lado, {})
			var lista: Array = x if x is Array else [x]
			for e in lista:
				if e is Dictionary and String(e.get("recurso", "")) == "desbloqueo":
					return true
	return false


func _peor_maquina() -> Maquina:
	var peor: Maquina = null
	for m in base.maquinas:
		if is_instance_valid(m) and m.tiene_desgaste and m.seleccionable():
			if peor == null or m.mantenimiento < peor.mantenimiento:
				peor = m
	return peor


func _rover() -> Node2D:
	for m in base.maquinas:
		if m is Rover:
			return m
	return null


## El mueble más cercano del grupo (para las camas, solo las comunes y, si hay, libres).
func _mas_cercano(grupo: String, p: Personaje, solo_comunes: bool) -> Node2D:
	var mejor: Node2D = null
	var mejor_libre := false
	for n in get_tree().get_nodes_in_group(grupo):
		if not (n is Node2D):
			continue
		if solo_comunes and n.solo_desmayados:
			continue
		var libre: bool = n.esta_libre() if n.has_method("esta_libre") else true
		var d: float = p.pies().distance_to(n.global_position)
		if mejor == null or (libre and not mejor_libre) \
				or (libre == mejor_libre and d < p.pies().distance_to(mejor.global_position)):
			mejor = n
			mejor_libre = libre
	return mejor
