class_name Tutorial
extends Node
## Tutorial: ventanas que pausan el juego y explican controles y mecánicas.
## Se activa con Ajustes.tutorial_activado. Cada ventana sale una sola vez por partida.
##
## Al empezar: objetivo, elegir astronauta, reparar una máquina rota, cámara, la tripulación
## y cada recurso global. Después, cuando pasa por primera vez: tocar cada máquina, el primer
## astronauta con hambre o sueño (la cámara muestra el comedor o la cama) y la primera
## exploración (justo cuando aparece).

var base: Node   # base.gd
var hud: Node
var eventos: Eventos

var _cola: Array[Dictionary] = []
var _abierta := false
var _en_cadena := false
var _pausa_previa := false
var _vistos := {}
var _t_revisar := 0.0

const TEXTOS_MAQUINAS := {
	"fotovoltaica": ["Paneles solares",
		"Juntan la luz del Sol y la convierten en energía. Rinden mucho a la mañana, menos a la tarde y nada de noche. Si se gastan, generan menos: ¡mantenelos sanos para tener energía para la noche!"],
	"comunicaciones": ["Comunicaciones",
		"La antena que conecta la base con la Tierra. Mientras funciona, ves los recursos, los desgastes y las alertas. Si se rompe, aparece un ! rojo encima y te quedás a ciegas: arreglala primero."],
	"o2": ["Máquina de oxígeno",
		"Fabrica el aire que respira la tripulación. Necesita energía. Si está gastada (borde amarillo o rojo) no da abasto y el oxígeno baja de a poco; si se rompe, el oxígeno se acaba."],
	"invernadero": ["Invernadero",
		"Acá crecen las plantas. Cuanto mejor esté, más comida da cada visita al comedor."],
	"escudo": ["Escudo de radiación",
		"Protege la base de la radiación del Sol. Sano (sin borde o en amarillo) hace bajar la radiación; en rojo solo la frena; roto, la radiación sube."],
	"rover": ["Rover",
		"El vehículo para explorar Marte. Un astronauta se sube y sale a investigar lugares nuevos. Cada salida lo gasta un poco."],
	"escritorio": ["Escritorio de investigación",
		"Acá se investiga, sentado en la silla. Primero hay que explorar con el rover: cada exploración desbloquea una investigación nueva."],
	"otras": ["Máquina",
		"Las máquinas se gastan con el tiempo (más rápido con radiación alta). Mandá a un astronauta a repararlas antes de que se rompan."],
}


func iniciar() -> void:
	if not Ajustes.actual().tutorial_activado:
		return
	eventos.evento_iniciado.connect(_al_iniciar_evento)
	_agregar("objetivo", "Objetivo del juego", "(Texto pendiente)")
	_agregar("elegir", "Elegir un astronauta",
		"Hacé clic en un astronauta para elegirlo: se marca con un borde verde. También podés tocar su tarjeta a la izquierda, las teclas 1, 2 y 3, o las flechas ← →. Para soltarlo, volvé a hacerle clic o tocá Esc.")
	_agregar("reparar", "Reparar una máquina",
		"Las máquinas se gastan. Cuando tienen borde amarillo necesitan ayuda; en rojo están por romperse. Con un astronauta elegido, hacé clic en la máquina y va a repararla. Con las flechas ↑ ↓ recorrés las que necesitan atención.",
		_peor_maquina())
	_agregar("camara", "Mover la cámara",
		"Rueda del mouse: acercar y alejar. Clic y arrastrar: mover el mapa. Con un astronauta elegido la cámara lo sigue; llevá el mouse al borde de la pantalla para mirar alrededor.")
	_agregar("tripulacion", "Tu tripulación",
		"Cada tarjeta muestra la salud, la comida y la energía de un astronauta. Si la comida o la energía llegan a cero, la salud baja. Llevalos al comedor a comer y a las camas a dormir.")
	_agregar("rec_energia", "Recurso: Energía",
		"La barra amarilla de arriba a la izquierda. La generan los paneles solares de día y la usan todas las máquinas. Sin energía, las máquinas se apagan.")
	_agregar("rec_oxigeno", "Recurso: Oxígeno",
		"La barra celeste. Lo fabrica la máquina de oxígeno, que necesita energía. Con poco oxígeno la tripulación se cansa mucho más rápido y, muy bajo, pierde salud.")
	_agregar("rec_radiacion", "Recurso: Radiación",
		"La barra violeta. Viene del Sol y sube sola. Gasta las máquinas más rápido y, arriba de 80%, daña a la tripulación. El escudo de radiación la mantiene baja.")
	_mostrar_siguiente.call_deferred()


func _process(delta: float) -> void:
	if _cola.is_empty() and _abierta:
		return
	_t_revisar -= delta
	if _t_revisar > 0.0 or not Ajustes.actual().tutorial_activado or eventos == null:
		return
	_t_revisar = 0.5
	for p in eventos.tripulacion:
		if not is_instance_valid(p) or not p.visible or p.desmayado:
			continue
		if p.hambre >= p.umbral_globo_hambre and not _vistos.has("hambre"):
			_agregar("hambre", "¡%s tiene hambre!" % p.obtener_nombre(),
				"Cuando aparece una manzana sobre su cabeza, necesita comer. Elegilo y hacé clic en el comedor (acá en pantalla). Si la comida llega a cero, pierde salud.",
				_mas_cercano("comedores", p, false))
			_mostrar_siguiente()
			return
		if p.sueno >= p.umbral_globo_sueno and not _vistos.has("sueno"):
			_agregar("sueno", "¡%s tiene sueño!" % p.obtener_nombre(),
				"Cuando aparece \"Zz\" sobre su cabeza, necesita dormir. Elegilo y hacé clic en una cama (acá en pantalla). Si la energía llega a cero, se duerme donde esté.",
				_mas_cercano("camas", p, true))
			_mostrar_siguiente()
			return


## La primera vez que se toca cada tipo de máquina, explica para qué sirve.
func maquina_tocada(m: Maquina) -> void:
	if not Ajustes.actual().tutorial_activado:
		return
	var tipo := String(m.tipo_ajuste())
	var datos: Array = TEXTOS_MAQUINAS.get(tipo, TEXTOS_MAQUINAS["otras"])
	_agregar("maq_" + tipo, datos[0], datos[1], m)
	_mostrar_siguiente.call_deferred()


func _al_iniciar_evento(ev: Dictionary) -> void:
	if _es_exploracion(ev):
		_agregar("exploracion", "Las exploraciones",
			"Un astronauta se sube al rover y sale a investigar un lugar nuevo de Marte. Mientras explora no está en la base, así que no puede reparar ni ayudar. Al volver, desbloquea una investigación para el escritorio: sin explorar, no se puede investigar. Podés salir ahora o posponerla.",
			_rover())
		_mostrar_siguiente.call_deferred()  # aparece encima de la ventana del evento


# --- Interno -----------------------------------------------------------------

func _agregar(id: String, titulo: String, texto: String, foco: Node2D = null) -> void:
	if _vistos.has(id):
		return
	_vistos[id] = true
	_cola.append({"titulo": titulo, "texto": texto, "foco": foco})


func _mostrar_siguiente() -> void:
	if _abierta or _cola.is_empty():
		return
	var paso: Dictionary = _cola.pop_front()
	if not _en_cadena:
		_en_cadena = true
		_pausa_previa = get_tree().paused  # por ejemplo, si hay una ventana de evento abierta
	_abierta = true
	var foco = paso["foco"]
	if foco != null and is_instance_valid(foco):
		base.enfocar_inmediato(foco)
	get_tree().paused = true
	var boton := "Siguiente" if not _cola.is_empty() else "Entendido"
	hud.mostrar_tutorial(paso["titulo"], paso["texto"], boton, func():
		_abierta = false
		if _cola.is_empty():
			_en_cadena = false
			get_tree().paused = _pausa_previa
		else:
			_mostrar_siguiente())


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


func _peor_maquina() -> Node2D:
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
