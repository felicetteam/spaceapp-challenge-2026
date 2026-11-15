class_name Eventos
extends Node
## Eventos críticos: cada tanto pausa el juego y muestra un aviso con dos decisiones.
## Las dos tienen un costo. Se leen de res://Eventos/eventos_criticos.json.
##
## Formato de cada evento:
## {
##   "id": "tormenta_polvo",                 (opcional, para identificarlo)
##   "titulo": "Tormenta de polvo",          (opcional)
##   "descripcion": "Texto del anuncio",
##   "peso": 1,                              (opcional: más alto = sale más seguido)
##   "al_iniciar": [ {...}, {...} ],         (opcional: efectos que pasan apenas aparece el
##                                           evento, antes de elegir; cantidad negativa = baja)
##   "consejo": "Cómo se soluciona",         (opcional)
##   "duracion": 180,                        (opcional: segundos que dura; arriba se ve cuánto queda)
##   "mientras_dura": [ {...} ],             (opcional: energia/oxigeno/radiacion por segundo
##                                           mientras dura, por ejemplo +0.08 de radiación)
##   "lluvia": true,                         (opcional: lluvia de partículas mientras dura: daña
##                                           a los astronautas que están afuera)
##   "estructura": "rover",                  (opcional: a dónde tienen que ir los astronautas)
##   "opcion_a": { "texto": "...", "gana": {...}, "pierde": {...},
##                 "estructura": "escudo" },  (opcional: otra estructura para esta opción;
##                                            "" = esta opción no necesita ir a ningún lado)
##   "opcion_b": { "texto": "...", "gana": {...}, "pierde": {...},
##                 "trabajo": 25 },          (opcional: segundos de trabajo en la estructura)
##   "trabajo": 25,                          (opcional: lo mismo para las dos opciones)
##   "dato_nasa": "Dato real",               (opcional, ya no se muestra en el juego)
##   "fuente": "De dónde sale el dato"       (opcional, ya no se muestra en el juego)
## }
##
## Todo evento que manda a alguien a una estructura tiene una duración o un trabajo:
## - Si la opción deja a un astronauta "ocupado" o "fuera" con "duracion", eso es lo que dura.
## - Si no, al llegar trabaja en la estructura "trabajo" segundos (TRABAJO_POR_DEFECTO si no se
##   indica) y recién al terminar se aplican los efectos. Con más astronautas trabajando ahí
##   (mandá a otro a esa máquina) avanza más rápido, como el trabajo en equipo de las reparaciones.
## El tiempo hasta el próximo evento recién empieza a correr cuando el anterior terminó del
## todo: su duración (tormenta, lluvia), su trabajo y los astronautas que dejó ocupados o fuera.
##
## Reparaciones ("reparar": "rover", tipo o nombre de máquina): al salir el evento, esas
## máquinas bajan a estado crítico (rojo). El evento no termina por tiempo: sigue en curso
## (con un cartel arriba) hasta que todas vuelven a verde (umbral_borde) reparándolas.
## Una opción con "reparar": true manda al astronauta elegido ("elegir") o al más cercano a
## reparar la máquina de verdad (como un clic del jugador: se le pueden sumar otros y es
## trabajo en equipo). Sus otros efectos de recursos se aplican al decidir.
##
## Exploraciones ("exploracion": true): no abren una ventana de decisión ni se posponen. Quedan
## pendientes en un botón (abajo a la derecha) que se puede tocar cuando se quiera. Ahí se elige
## quién sale (o se cierra la ventana): solo se puede elegir a alguien disponible con al menos
## "salud_minima" de salud (60 por defecto) y energía para pagar "costo_energia" (40 por
## defecto). Sale con lo que dice "opcion_a" y vuelve cansado: pierde esa energía al volver.
## "opcion_b" no hace falta.
##
## "gana" y "pierde" llevan { "recurso": ..., "cantidad": ... }, o una lista de varios de esos.
## Estructura: después de decidir, los astronautas de la opción (el elegido, el nombrado o,
## si la opción no nombra a nadie, el disponible más cercano) caminan hasta la estructura y
## recién al llegar se aplican los efectos. Puede ser el tipo de máquina (fotovoltaica,
## comunicaciones, o2, invernadero, escudo, rover, escritorio), el nombre que se ve en el juego
## o el nombre del nodo (Comedor, cama_hospital...). Si hay varias, van a la más cercana.
## "posponer" nunca necesita caminar.
##
## Recursos posibles:
##   "energia", "oxigeno", "radiacion"      puntos del recurso global (0 a 100)
##   "comida", "descanso", "salud"          para toda la tripulación; "comida:Juan" para uno solo
##   "mantenimiento"                        todas las máquinas; "mantenimiento:fotovoltaica"
##                                          (por tipo: fotovoltaica, comunicaciones, o2,
##                                          invernadero, escudo, rover) o por nombre de máquina
##   "investigacion"                        progreso del escritorio
##   "nada"                                 sin efecto
##   "desbloqueo"                           desbloquea una investigación para el escritorio
##                                          (sin investigaciones desbloqueadas no se investiga)
##   "posponer"                             { "segundos": 300 }: el evento vuelve más tarde
##   "apagar:invernadero"                   { "segundos": 60 }: apaga máquinas (por tipo o nombre)
##                                          y no se pueden reparar durante ese tiempo
##   "elegir": el jugador elige qué astronauta va (se abre una lista al tocar la opción).
##     Si no hay nadie disponible, la opción queda deshabilitada.
##   nombre de un astronauta ("Juan", "Laika", "Feli", "Andy") o "cualquiera" (al azar):
##     en "pierde" lo saca de servicio: { "duracion": segundos, "modo": "fuera" | "ocupado",
##     "motivo": "texto" }. "fuera" lo saca del mapa; "ocupado" lo deja en su lugar trabajando
##     sin aceptar órdenes. En "gana" lo deja descansado y comido.

signal evento_iniciado(evento: Dictionary)
signal evento_resuelto(evento: Dictionary, opcion: String)
## Un astronauta quedó fuera de servicio por un evento (base.gd lo deselecciona).
signal astronauta_retirado(personaje: Personaje)

const RUTA := "res://Eventos/eventos_criticos.json"

var hud: Node
## Mientras el tutorial está mostrando algo, no salen eventos nuevos (se ven mal encima).
var tutorial: Node = null
var recursos: Recursos
var tripulacion: Array[Personaje] = []

var _eventos: Array[Dictionary] = []
var _bolsa: Array[int] = []
var _t := 0.0
var _abierto := false
var _cola: Array[Dictionary] = []
var _retirados: Array[Dictionary] = []  # { "p": Personaje, "t": segundos restantes }
var _pospuestos: Array[Dictionary] = []  # { "ev": evento, "t": segundos restantes }
var _ev_actual: Dictionary = {}
var _primero_lanzado := false  # ya salió el primer evento (Ajustes.primer_evento_id)
var _elegido: Personaje = null  # el astronauta que eligió el jugador para la opción actual
## Astronautas ya decididos para la opción en curso (nombre normalizado o "cualquiera" -> Personaje).
var _fijados := {}
## Decisión tomada, esperando que los astronautas lleguen a la estructura.
## { "ev", "clave", "caminantes": Array[Personaje], "t": segundos que quedan de espera }
var _pendiente: Dictionary = {}
## Estructura a la que fueron los astronautas en la opción que se está aplicando (o null).
var _estructura_actual: Node2D = null
## Eventos de reparación en curso: { "ev", "maquinas": Array[Maquina] }
var _reparaciones: Array[Dictionary] = []
## Exploraciones esperando que el jugador elija quién sale (eventos con "exploracion": true).
var _exploraciones: Array[Dictionary] = []
## Energía que pierde al volver el astronauta de la exploración en curso (se fija al elegirlo).
var _cansancio_exploracion := 0.0
const SALUD_MINIMA_EXPLORACION := 60.0
const COSTO_ENERGIA_EXPLORACION := 40.0
## Si los astronautas no llegan en este tiempo, la decisión se aplica igual.
const ESPERA_MAXIMA := 120.0
## Eventos con duración que siguen activos: { "ev": evento, "t": segundos que quedan }
var _activos: Array[Dictionary] = []
## Trabajos de evento en una estructura: { "ev", "clave", "caminantes", "estructura",
## "restante", "total", "elegido", "fijados", "n" (cuántos trabajaban en el último cuadro) }
var _trabajos: Array[Dictionary] = []
const TRABAJO_POR_DEFECTO := 25.0


func _ready() -> void:
	cargar()
	_t = Ajustes.actual().primer_evento
	if hud != null and hud.has_signal("exploracion_pedida"):
		hud.exploracion_pedida.connect(abrir_exploracion)


## Lee (o vuelve a leer) el archivo de eventos.
func cargar() -> void:
	_eventos.clear()
	_bolsa.clear()
	if not FileAccess.file_exists(RUTA):
		push_warning("No existe %s: no habrá eventos críticos" % RUTA)
		return
	var datos = JSON.parse_string(FileAccess.get_file_as_string(RUTA))
	if datos == null:
		push_error("%s tiene un error de formato JSON" % RUTA)
		return
	var lista = datos.get("eventos", []) if datos is Dictionary else datos
	if not (lista is Array):
		push_error("%s: se esperaba una lista de eventos" % RUTA)
		return
	for i in lista.size():
		var ev = lista[i]
		if ev is Dictionary and ev.has("descripcion") and ev.get("opcion_a") is Dictionary \
				and (ev.get("opcion_b") is Dictionary or bool(ev.get("exploracion", false))):
			_eventos.append(ev)
		else:
			push_warning("%s: el evento %d está incompleto (falta descripcion, opcion_a u opcion_b)" % [RUTA, i])
	print("Eventos críticos cargados: %d" % _eventos.size())


## true mientras hay un evento en pantalla o esperando que los astronautas lleguen.
func ocupado() -> bool:
	return _abierto


## true mientras el último evento sigue en curso (ventana, caminata, trabajo, duración o
## astronautas ocupados por él). Mientras tanto no corre el tiempo hasta el próximo.
func en_curso() -> bool:
	return _abierto or not _pendiente.is_empty() or not _trabajos.is_empty() \
			or not _activos.is_empty() or not _retirados.is_empty() or not _reparaciones.is_empty()


func _process(delta: float) -> void:
	_actualizar_retirados(delta)
	_revisar_pendiente(delta)
	_actualizar_trabajos(delta)
	_actualizar_reparaciones()
	_actualizar_activos(delta)
	# Con el tutorial explicando algo, los eventos esperan (y dejan unos segundos al terminar)
	if tutorial != null and tutorial.ocupado():
		_t = maxf(_t, 8.0)
		for p in _pospuestos:
			p["t"] = maxf(p["t"], 8.0)
		return
	for i in range(_pospuestos.size() - 1, -1, -1):
		_pospuestos[i]["t"] -= delta
		if _pospuestos[i]["t"] <= 0.0 and not _abierto:
			var ev: Dictionary = _pospuestos[i]["ev"]
			_pospuestos.remove_at(i)
			lanzar(ev)
	var aj := Ajustes.actual()
	if not aj.eventos_activados or _eventos.is_empty() or en_curso():
		return  # el tiempo hasta el próximo evento recién corre cuando terminó el anterior
	_t -= delta
	if _t <= 0.0:
		_t = randf_range(aj.intervalo_eventos_min, aj.intervalo_eventos_max)
		lanzar_aleatorio()


## Elige un evento al azar sin repetir hasta que salgan todos (respeta "peso").
## El primero de la partida es siempre Ajustes.primer_evento_id (si existe en el archivo).
func lanzar_aleatorio() -> void:
	if _eventos.is_empty():
		return
	var primero := -1
	if not _primero_lanzado:
		_primero_lanzado = true
		var id := str(Ajustes.actual().primer_evento_id)
		for i in _eventos.size():
			if id != "" and str(_eventos[i].get("id", "")) == id:
				primero = i
				break
		if id != "" and primero < 0:
			push_warning("Eventos: no hay ningún evento con id \"%s\" para salir primero" % id)
	if _bolsa.is_empty():
		for i in _eventos.size():
			for _r in maxi(1, int(_eventos[i].get("peso", 1))):
				_bolsa.append(i)
		_bolsa.shuffle()
	if primero >= 0:
		_bolsa.erase(primero)  # ya salió en esta vuelta: no se repite enseguida
		lanzar(_eventos[primero])
		return
	lanzar(_eventos[_bolsa.pop_back()])


## Pausa el juego y muestra el evento. Si ya hay uno abierto, queda en cola.
func lanzar(ev: Dictionary) -> void:
	if bool(ev.get("exploracion", false)):
		_agregar_exploracion(ev)
		return
	if _abierto:
		_cola.append(ev)
		return
	_abierto = true
	_ev_actual = ev
	# Lo que pasa apenas aparece el evento (por ejemplo, sube la radiación)
	var iniciales: PackedStringArray = []
	var al_iniciar = ev.get("al_iniciar", [])
	if al_iniciar is Dictionary:
		al_iniciar = [al_iniciar]
	for efecto in al_iniciar:
		if efecto is Dictionary:
			var t := _aplicar(efecto, 1)
			if t != "":
				iniciales.append(t)
	# Reparación: la máquina baja a crítico y el evento sigue hasta que vuelva a verde
	if ev.has("reparar"):
		var t_rep := _iniciar_reparacion(ev)
		if t_rep != "":
			iniciales.append(t_rep)
	# Eventos que duran un rato (tormenta, lluvia): arriba de la pantalla se ve cuánto queda
	if ev.has("duracion"):
		var dur := float(ev.get("duracion", 0))
		var ya := false
		for a in _activos:
			if a["ev"] == ev:
				a["t"] = dur
				ya = true
		if not ya:
			_activos.append({"ev": ev, "t": dur})
		iniciales.append("Dura %d:%02d" % [int(dur) / 60, int(dur) % 60])
	get_tree().paused = true
	evento_iniciado.emit(ev)
	# Una opción que necesita elegir un astronauta no se puede tomar si no hay nadie disponible
	var bloqueadas: Array[String] = []
	for clave in ["opcion_a", "opcion_b"]:
		if _requiere_elegir(ev.get(clave, {})) and _disponibles().is_empty():
			bloqueadas.append(clave)
	hud.mostrar_evento(ev, _describir_opcion(ev, "opcion_a"), _describir_opcion(ev, "opcion_b"),
			func(clave: String): _elegir(ev, clave), " · ".join(iniciales), bloqueadas)


# --- Exploraciones pendientes -----------------------------------------------------

## La exploración no interrumpe: queda en el botón de exploraciones pendientes.
func _agregar_exploracion(ev: Dictionary) -> void:
	_exploraciones.append(ev)
	hud.mostrar_exploraciones_pendientes(_exploraciones.size())
	hud.agregar_alerta("%s: tocá el botón de abajo a la derecha para elegir quién sale" \
			% String(ev.get("titulo", "Nueva exploración")), 1, _rover())
	evento_iniciado.emit(ev)  # (el tutorial la explica la primera vez)


func _rover() -> Rover:
	for m in get_tree().get_nodes_in_group("maquinas"):
		if m is Rover:
			return m
	return null


## Por qué no puede salir a explorar este astronauta ("" = puede).
func _motivo_no_explora(p: Personaje, ev: Dictionary) -> String:
	var salud_min := float(ev.get("salud_minima", SALUD_MINIMA_EXPLORACION))
	var costo := float(ev.get("costo_energia", COSTO_ENERGIA_EXPLORACION))
	if p.en_evento:
		return "está explorando" if p.evento_fuera else "está ocupado"
	if p.desmayado or p.siendo_llevado:
		return "está inconsciente"
	if p.yendo_a_evento:
		return "está yendo a otra tarea"
	if p.salud < salud_min:
		return "salud %d%% (necesita %d%%)" % [roundi(p.salud), roundi(salud_min)]
	var energia := 100.0 - p.sueno
	if energia < costo:
		return "energía %d%% (necesita %d%%)" % [roundi(energia), roundi(costo)]
	return ""


## Abre la ventana de la exploración pendiente (botón del HUD). Se puede cerrar sin elegir.
func abrir_exploracion() -> void:
	if _exploraciones.is_empty():
		return
	var ev: Dictionary = _exploraciones[0]
	var costo := float(ev.get("costo_energia", COSTO_ENERGIA_EXPLORACION))
	var aviso := ""
	var rover := _rover()
	if _abierto:
		aviso = "Hay otro evento en curso: esperá a que termine."
	elif rover != null and rover.en_exploracion:
		aviso = "El rover ya está explorando: las exploraciones se hacen de a una."
	elif rover != null and rover.averiada:
		aviso = "El rover está roto: reparalo antes de salir."
	var candidatos: Array[Dictionary] = []
	for p in tripulacion:
		if is_instance_valid(p):
			candidatos.append({"p": p, "motivo": aviso if aviso != "" else _motivo_no_explora(p, ev)})
	var pausa_previa := get_tree().paused
	get_tree().paused = true
	var texto := "%s\nCuesta %d%% de energía: el astronauta vuelve cansado. Necesita al menos %d%% de salud." % [
			String(ev.get("descripcion", "")), roundi(costo),
			roundi(float(ev.get("salud_minima", SALUD_MINIMA_EXPLORACION)))]
	var al_elegir := func(p: Personaje):
		get_tree().paused = pausa_previa
		_salir_a_explorar(ev, p)
	var al_salir := func():
		get_tree().paused = pausa_previa
	hud.mostrar_exploracion(String(ev.get("titulo", "Exploración")), texto, candidatos, aviso,
			al_elegir, al_salir)


func _salir_a_explorar(ev: Dictionary, p: Personaje) -> void:
	if _abierto or _motivo_no_explora(p, ev) != "":
		return
	_exploraciones.erase(ev)
	hud.mostrar_exploraciones_pendientes(_exploraciones.size())
	_abierto = true
	_ev_actual = ev
	_elegido = p
	_cansancio_exploracion = float(ev.get("costo_energia", COSTO_ENERGIA_EXPLORACION))
	_resolver(ev, "opcion_a")


func _elegir(ev: Dictionary, clave: String) -> void:
	var opcion: Dictionary = ev.get(clave, {})
	if _requiere_elegir(opcion):
		# Primero el jugador elige quién va; el juego sigue en pausa
		hud.elegir_astronauta(_disponibles(), String(opcion.get("texto", "")), func(p: Personaje):
			_elegido = p
			_resolver(ev, clave))
	else:
		_resolver(ev, clave)


# --- Eventos de reparación ---------------------------------------------------------

func _maquinas_a_reparar(ev: Dictionary) -> Array[Maquina]:
	var lista: Array[Maquina] = []
	var detalle := String(ev.get("reparar", ""))
	for m in get_tree().get_nodes_in_group("maquinas"):
		if m is Maquina and m.tiene_desgaste and _maquina_coincide(m, detalle):
			lista.append(m)
	return lista


## Baja las máquinas a crítico y empieza a seguir la reparación. Devuelve el texto del efecto.
func _iniciar_reparacion(ev: Dictionary) -> String:
	var maquinas := _maquinas_a_reparar(ev)
	if maquinas.is_empty():
		push_warning("Evento '%s': no hay ninguna máquina '%s' para reparar" % [ev.get("id", ""), ev.get("reparar", "")])
		return ""
	var nombres: PackedStringArray = []
	for m in maquinas:
		m.mantenimiento = minf(m.mantenimiento, m.umbral_critico * 0.8)
		nombres.append(m.nombre_maquina)
	for r in _reparaciones:
		if r["ev"] == ev:
			r["maquinas"] = maquinas
			return ""
	_reparaciones.append({"ev": ev, "maquinas": maquinas})
	return "%s en estado crítico: hay que repararlo hasta verde" % ", ".join(nombres)


func _actualizar_reparaciones() -> void:
	for i in range(_reparaciones.size() - 1, -1, -1):
		var r := _reparaciones[i]
		var ev: Dictionary = r["ev"]
		var id := "reparar_" + String(ev.get("id", ev.get("titulo", "evento")))
		var peor: Maquina = null
		for m in r["maquinas"]:
			if is_instance_valid(m) and m.mantenimiento < m.umbral_borde \
					and (peor == null or m.mantenimiento < peor.mantenimiento):
				peor = m
		if peor != null:
			var equipo := " · ¡Trabajo en Equipo!" if peor.en_equipo() else ""
			hud.mostrar_banner(id, "%s · reparar %s: %d%% (verde desde %d%%)%s" % [
					String(ev.get("titulo", "Evento")), peor.nombre_maquina, roundi(peor.mantenimiento),
					roundi(peor.umbral_borde), equipo])
			continue
		_reparaciones.remove_at(i)
		hud.quitar_banner(id)
		hud.agregar_alerta("Solucionado: %s" % String(ev.get("titulo", "evento")), 0)


## Opción "reparar": manda al elegido (o al disponible más cercano) a reparar de verdad.
func _mandar_a_reparar(ev: Dictionary, clave: String) -> void:
	var maquinas := _maquinas_a_reparar(ev)
	var p := _elegido
	if not maquinas.is_empty() and p == null:
		var libres := _disponibles()
		var centro := maquinas[0].global_position
		libres.sort_custom(func(a, b): return a.pies().distance_squared_to(centro) < b.pies().distance_squared_to(centro))
		if not libres.is_empty():
			p = libres[0]
	if p != null and not maquinas.is_empty():
		p.trabajar_en(maquinas[0])
		hud.agregar_alerta("%s va a reparar %s (mandá a más astronautas para ir más rápido)" % [
				p.obtener_nombre(), maquinas[0].nombre_maquina], 0, maquinas[0])
	_aplicar_opcion(ev, clave)


## Después de decidir: si la opción tiene estructura, primero caminan hasta ahí.
func _resolver(ev: Dictionary, clave: String) -> void:
	var opcion: Dictionary = ev.get(clave, {})
	if bool(opcion.get("reparar", false)):
		_mandar_a_reparar(ev, clave)
		return
	var nombre_estructura := _estructura_de(ev, clave)
	if nombre_estructura == "":
		_aplicar_opcion(ev, clave)
		return
	var estructuras := _buscar_estructuras(nombre_estructura)
	if estructuras.is_empty():
		push_warning("Evento '%s': no hay ninguna estructura '%s' en el mapa" % [ev.get("id", ""), nombre_estructura])
		_aplicar_opcion(ev, clave)
		return
	var caminantes := _caminantes(opcion, estructuras)
	var motivo := String(opcion.get("texto", ev.get("titulo", "evento")))
	var en_camino: Array[Personaje] = []
	for p in caminantes:
		var destino := _mas_cercana(estructuras, p.pies())
		if p.ir_a_evento(_destinos(destino, p), motivo):
			en_camino.append(p)
	if en_camino.is_empty():
		_aplicar_opcion(ev, clave)
		return
	_pendiente = {"ev": ev, "clave": clave, "caminantes": en_camino, "t": ESPERA_MAXIMA,
			"estructura": _mas_cercana(estructuras, en_camino[0].pies())}
	get_tree().paused = false  # el evento sigue abierto: no salen otros hasta aplicarlo
	var quienes: PackedStringArray = []
	for p in en_camino:
		quienes.append(p.obtener_nombre())
	var donde := _nombre_estructura(_mas_cercana(estructuras, en_camino[0].pies()))
	hud.agregar_alerta("%s va%s a %s: %s" % [", ".join(quienes), "n" if en_camino.size() > 1 else "",
			donde, motivo], 0, en_camino[0])


## Aplica la decisión cuando todos llegaron (o no pueden llegar, o pasó la espera máxima).
func _revisar_pendiente(delta: float) -> void:
	if _pendiente.is_empty():
		return
	_pendiente["t"] -= delta
	var listos := true
	for p in _pendiente["caminantes"]:
		if is_instance_valid(p) and p.yendo_a_evento:
			listos = false
	if not listos and _pendiente["t"] > 0.0:
		return
	var ev: Dictionary = _pendiente["ev"]
	var clave: String = _pendiente["clave"]
	for p in _pendiente["caminantes"]:
		if is_instance_valid(p) and p.yendo_a_evento:
			p.yendo_a_evento = false
			p.detener()
	var estructura = _pendiente.get("estructura")
	var caminantes: Array[Personaje] = []
	for p in _pendiente["caminantes"]:
		if is_instance_valid(p) and not p.desmayado and not p.en_evento:
			caminantes.append(p)
	_pendiente = {}
	if is_instance_valid(estructura) and not caminantes.is_empty() \
			and _necesita_trabajo(ev.get(clave, {})):
		_iniciar_trabajo(ev, clave, caminantes, estructura)
		return
	_estructura_actual = estructura if is_instance_valid(estructura) else null
	_aplicar_opcion(ev, clave)
	_estructura_actual = null


## La opción no deja a nadie ocupado o fuera por un tiempo: entonces, al llegar, hay que
## trabajar en la estructura.
func _necesita_trabajo(opcion: Dictionary) -> bool:
	for efecto in _lista(opcion.get("pierde", {})):
		if _es_efecto_de_astronauta(efecto):
			return false
	return true


func _es_efecto_de_astronauta(efecto: Dictionary) -> bool:
	var c := _normalizar(String(_partes(efecto)[0]))
	return c != "" and not NOMBRES_RECURSO.has(c) and not (c in ["nada", "desbloqueo", "posponer", "apagar"])


func _segundos_de_trabajo(ev: Dictionary, clave: String) -> float:
	var opcion: Dictionary = ev.get(clave, {})
	return maxf(1.0, float(opcion.get("trabajo", ev.get("trabajo", TRABAJO_POR_DEFECTO))))


## Los que llegaron se ponen a trabajar en la estructura; los efectos se aplican al terminar.
## La ventana del evento ya se cerró, así que pueden salir avisos del tutorial mientras tanto.
func _iniciar_trabajo(ev: Dictionary, clave: String, caminantes: Array[Personaje], estructura: Node2D) -> void:
	var opcion: Dictionary = ev.get(clave, {})
	var motivo := String(opcion.get("texto", ev.get("titulo", "evento")))
	var total := _segundos_de_trabajo(ev, clave)
	for p in caminantes:
		p.iniciar_evento(false, motivo, total)
		p.mirar(estructura.global_position.x - p.global_position.x)
	_trabajos.append({"ev": ev, "clave": clave, "caminantes": caminantes, "estructura": estructura,
			"restante": total, "total": total, "elegido": _elegido, "fijados": _fijados.duplicate(), "n": 0})
	_elegido = null
	_fijados.clear()
	_abierto = false
	hud.agregar_alerta("%s: trabajando en %s (más rápido si van más astronautas)" % [
			String(ev.get("titulo", "Evento")), _nombre_estructura(estructura)], 0, estructura)
	if not _cola.is_empty():
		lanzar(_cola.pop_front())


## Avanza los trabajos de evento: cada astronauta extra trabajando ahí suma Ajustes.bonus_equipo
## (los del evento y también los que el jugador mande a reparar esa máquina).
func _actualizar_trabajos(delta: float) -> void:
	for i in range(_trabajos.size() - 1, -1, -1):
		var tb := _trabajos[i]
		var ev: Dictionary = tb["ev"]
		var estructura = tb["estructura"]
		var id := "trabajo_" + String(ev.get("id", ev.get("titulo", "evento")))
		var activos: Array[Personaje] = []
		for p in tb["caminantes"]:
			if is_instance_valid(p) and p.en_evento and not p.en_pausa_evento():
				activos.append(p)
		if is_instance_valid(estructura):
			for p in tripulacion:
				if is_instance_valid(p) and not activos.has(p) and p.esta_trabajando() \
						and p.maquina_actual == estructura and p.esta_en_puesto():
					activos.append(p)
		var n := activos.size()
		if n > tb["n"] and n > 1:
			for p in activos:
				p.mostrar_cartel("¡Trabajo en Equipo!")
		tb["n"] = n
		var ritmo: float = 0.0 if n == 0 else 1.0 + Ajustes.actual().bonus_equipo * (n - 1)
		tb["restante"] -= delta * ritmo
		var nadie := true
		for p in tb["caminantes"]:
			if is_instance_valid(p) and p.en_evento:
				nadie = false
		if tb["restante"] > 0.0 and not nadie:
			var pct := int(100.0 * (1.0 - tb["restante"] / tb["total"]))
			var texto := "%s · trabajo %d%%" % [String(ev.get("titulo", "Evento")), pct]
			if n > 1:
				texto += " · ¡Trabajo en Equipo! x%s" % String.num(ritmo, 1)
			elif n == 0:
				texto += " · en pausa"
			hud.mostrar_banner(id, texto)
			continue
		# Terminado: se liberan los astronautas y recién ahora pasa lo que decía la opción
		_trabajos.remove_at(i)
		hud.quitar_banner(id)
		for p in tb["caminantes"]:
			if is_instance_valid(p) and p.en_evento and not p.evento_fuera:
				p.terminar_evento()
				p.mostrar_cartel("¡Listo!")
		_elegido = tb["elegido"] if is_instance_valid(tb["elegido"]) else null
		_fijados = tb["fijados"]
		_estructura_actual = estructura if is_instance_valid(estructura) else null
		_aplicar_opcion(ev, tb["clave"], false)
		_estructura_actual = null


## cerrar: false cuando se aplica al terminar un trabajo (la ventana ya estaba cerrada y no hay
## que tocar la pausa, que puede ser de otra ventana).
func _aplicar_opcion(ev: Dictionary, clave: String, cerrar := true) -> void:
	_ev_actual = ev
	var opcion: Dictionary = ev.get(clave, {})
	var textos: PackedStringArray = []
	# En una opción de reparar, el astronauta ya fue a reparar: no se lo saca de servicio
	var solo_recursos := bool(opcion.get("reparar", false))
	for efecto in _lista(opcion.get("gana", {})):
		if solo_recursos and _es_efecto_de_astronauta(efecto):
			continue
		var t := _aplicar(efecto, 1)
		if t != "":
			textos.append(t)
	for efecto in _lista(opcion.get("pierde", {})):
		if solo_recursos and _es_efecto_de_astronauta(efecto):
			continue
		var t := _aplicar(efecto, -1)
		if t != "":
			textos.append(t)
	_elegido = null
	_fijados.clear()
	_cansancio_exploracion = 0.0
	if cerrar:
		get_tree().paused = false
		_abierto = false
	evento_resuelto.emit(ev, clave)
	var titulo: String = ev.get("titulo", "Evento")
	hud.agregar_alerta("%s: %s" % [titulo, " · ".join(textos) if not textos.is_empty() else "sin efectos"], 1)
	if cerrar and not _cola.is_empty():
		lanzar(_cola.pop_front())


## Estructura a la que hay que ir para esta opción ("" = ninguna).
func _estructura_de(ev: Dictionary, clave: String) -> String:
	var opcion: Dictionary = ev.get(clave, {})
	var nombre := String(opcion.get("estructura", ev.get("estructura", ""))).strip_edges()
	if nombre == "" or _solo_posponer(opcion):
		return ""
	return nombre


func _solo_posponer(opcion: Dictionary) -> bool:
	var hay_posponer := false
	for efecto in _lista(opcion.get("gana", {})) + _lista(opcion.get("pierde", {})):
		var c := _normalizar(String(efecto.get("recurso", "nada")))
		if c == "posponer":
			hay_posponer = true
		elif c != "nada" and c != "":
			return false
	return hay_posponer


func _describir_opcion(ev: Dictionary, clave: String) -> String:
	var texto := describir(ev.get(clave, {}))
	if bool(ev.get(clave, {}).get("reparar", false)):
		var maquinas := _maquinas_a_reparar(ev)
		var nombre := maquinas[0].nombre_maquina if not maquinas.is_empty() else String(ev.get("reparar", ""))
		var r := "Reparar %s hasta verde (más rápido en equipo)" % nombre
		return r + (" · " + texto if texto != "" else "")
	var nombre := _estructura_de(ev, clave)
	if nombre != "":
		var lista := _buscar_estructuras(nombre)
		var donde := _nombre_estructura(lista[0]) if not lista.is_empty() else nombre
		texto = "Ir a %s · %s" % [donde, texto] if texto != "" else "Ir a %s" % donde
		if _necesita_trabajo(ev.get(clave, {})):
			texto += " · Trabajo %d s (más rápido en equipo)" % int(_segundos_de_trabajo(ev, clave))
	return texto


## Todas las estructuras del mapa que coinciden con el nombre (tipo, nombre visible o nodo).
func _buscar_estructuras(nombre: String) -> Array[Node2D]:
	var buscado := _normalizar(nombre)
	var lista: Array[Node2D] = []
	for grupo in ["maquinas", "comedores", "camas", "roombas"]:
		for n in get_tree().get_nodes_in_group(grupo):
			if not (n is Node2D) or lista.has(n):
				continue
			var nombres := [_normalizar(n.name)]
			if n is Maquina:
				nombres.append(_normalizar(String(n.tipo_ajuste())))
				nombres.append(_normalizar(n.nombre_maquina))
			if buscado in nombres:
				lista.append(n)
	if lista.is_empty() and get_tree().current_scene != null:
		var n := get_tree().current_scene.find_child(nombre, true, false)
		if n is Node2D:
			lista.append(n)
	return lista


func _mas_cercana(estructuras: Array[Node2D], desde: Vector2) -> Node2D:
	var mejor: Node2D = estructuras[0]
	for e in estructuras:
		if desde.distance_squared_to(e.global_position) < desde.distance_squared_to(mejor.global_position):
			mejor = e
	return mejor


func _nombre_estructura(n: Node2D) -> String:
	if n is Maquina and n.nombre_maquina != "":
		return n.nombre_maquina
	return String(n.name)


## Puntos alrededor de la estructura donde puede pararse el astronauta.
func _destinos(n: Node2D, p: Personaje) -> Array[Vector2]:
	var nav := p.navegacion
	var resultado: Array[Vector2] = []
	if nav == null:
		resultado.append(n.global_position)
		return resultado
	var rect := Rect2(n.global_position - Vector2(12, 12), Vector2(24, 24))
	if n is Maquina:
		resultado = n.puntos_de_trabajo(nav)
		if not resultado.is_empty():
			return resultado
		rect = n.rect_global()
	resultado = nav.puntos_alrededor(rect, 2.0, 18.0)
	if resultado.is_empty():
		resultado.append(nav.posicion_de(nav.celda_transitable_cercana(n.global_position, 12, false)))
	return resultado


## Quiénes tienen que ir: el elegido, los nombrados en los efectos y, si no hay nadie,
## el disponible más cercano a la estructura. Quedan fijados para cuando se apliquen los efectos.
func _caminantes(opcion: Dictionary, estructuras: Array[Node2D]) -> Array[Personaje]:
	var lista: Array[Personaje] = []
	if _elegido != null:
		lista.append(_elegido)
	for efecto in _lista(opcion.get("gana", {})) + _lista(opcion.get("pierde", {})):
		var partes := _partes(efecto)
		for nombre in [partes[0], partes[1]]:
			var n := _normalizar(String(nombre))
			if n == "" or n == "elegir" or n == "cualquiera" or NOMBRES_RECURSO.has(n) \
					or n in ["nada", "desbloqueo", "posponer"]:
				continue
			var p := _buscar_astronauta(String(nombre))
			if p != null and not lista.has(p) and _disponibles().has(p):
				lista.append(p)
	if lista.is_empty():
		var libres := _disponibles()
		if not libres.is_empty():
			var centro := estructuras[0].global_position
			libres.sort_custom(func(a, b): return a.pies().distance_squared_to(centro) < b.pies().distance_squared_to(centro))
			lista.append(libres[0])
	if not lista.is_empty():
		_fijados["cualquiera"] = lista[0]  # "salud:cualquiera" le toca al que fue
	return lista


## Texto corto de los efectos de una opción, para el botón ("+25 Energía · −30 Oxígeno").
func describir(opcion: Dictionary) -> String:
	var partes: PackedStringArray = []
	var solo_recursos := bool(opcion.get("reparar", false))
	for efecto in _lista(opcion.get("gana", {})):
		if solo_recursos and _es_efecto_de_astronauta(efecto):
			continue
		var t := _describir_efecto(efecto, 1)
		if t != "":
			partes.append(t)
	for efecto in _lista(opcion.get("pierde", {})):
		if solo_recursos and _es_efecto_de_astronauta(efecto):
			continue
		var t := _describir_efecto(efecto, -1)
		if t != "":
			partes.append(t)
	return " · ".join(partes)


## "gana"/"pierde" pueden ser un efecto o una lista de efectos.
func _lista(x) -> Array:
	if x is Dictionary:
		return [] if x.is_empty() else [x]
	if x is Array:
		return x.filter(func(e): return e is Dictionary)
	return []


func _requiere_elegir(opcion: Dictionary) -> bool:
	for efecto in _lista(opcion.get("gana", {})) + _lista(opcion.get("pierde", {})):
		if _normalizar(String(efecto.get("recurso", ""))) == "elegir":
			return true
	return false


## Astronautas que pueden ir a una tarea de evento.
func _disponibles() -> Array[Personaje]:
	var lista: Array[Personaje] = []
	for p in tripulacion:
		if is_instance_valid(p) and not p.en_evento and not p.desmayado and not p.siendo_llevado \
				and not p.yendo_a_evento:
			lista.append(p)
	return lista


# --- Efectos -----------------------------------------------------------------

const NOMBRES_RECURSO := {
	"energia": "Energía", "oxigeno": "Oxígeno", "radiacion": "Radiación",
	"comida": "Comida", "descanso": "Descanso", "salud": "Salud",
	"mantenimiento": "Mantenimiento", "investigacion": "Investigación",
}

func _partes(efecto: Dictionary) -> Array:
	var r := String(efecto.get("recurso", "nada")).strip_edges()
	var i := r.find(":")
	if i == -1:
		return [r, ""]
	return [r.substr(0, i), r.substr(i + 1)]


func _describir_efecto(efecto: Dictionary, signo: int) -> String:
	if efecto.is_empty():
		return ""
	var partes := _partes(efecto)
	var clave: String = _normalizar(partes[0])
	var detalle: String = partes[1]
	if clave == "" or clave == "nada":
		return ""
	var cantidad := float(efecto.get("cantidad", 0)) * signo
	if clave == "desbloqueo":
		var n := maxi(1, int(efecto.get("cantidad", 1)))
		return "Desbloquea %s" % ("una investigación" if n == 1 else "%d investigaciones" % n)
	if clave == "posponer":
		var s := int(efecto.get("segundos", 300))
		return "Vuelve en %d:%02d" % [s / 60, s % 60]
	if clave == "apagar":
		var s := int(efecto.get("segundos", 60))
		return "%s apagado %d:%02d (sin reparar)" % [detalle.capitalize() if detalle != "" else "Todo", s / 60, s % 60]
	if NOMBRES_RECURSO.has(clave):
		var nombre: String = NOMBRES_RECURSO[clave]
		if detalle != "":
			nombre += " (%s)" % ("un astronauta" if _normalizar(detalle) == "cualquiera" else detalle)
		return "%s%d %s" % ["+" if cantidad >= 0.0 else "−", roundi(absf(cantidad)), nombre]
	# Astronauta
	var quien: String = partes[0]
	if clave == "cualquiera":
		quien = "un astronauta al azar"
	elif clave == "elegir":
		quien = "el astronauta que elijas"
	if signo > 0:
		return "%s se recupera" % quien
	var dur := int(efecto.get("duracion", 0))
	var modo := "fuera de la base" if String(efecto.get("modo", "fuera")) == "fuera" else "ocupado"
	return "%s %s %d:%02d" % [quien, modo, dur / 60, dur % 60]


## Aplica un efecto. signo: +1 gana, -1 pierde. Devuelve el texto de lo que pasó.
func _aplicar(efecto: Dictionary, signo: int) -> String:
	if efecto.is_empty():
		return ""
	var partes := _partes(efecto)
	var clave: String = _normalizar(partes[0])
	var detalle: String = partes[1]
	var cantidad := float(efecto.get("cantidad", 0)) * signo
	match clave:
		"", "nada":
			return ""
		"energia", "oxigeno", "radiacion":
			recursos.set(clave, clampf(float(recursos.get(clave)) + cantidad, 0.0, 100.0))
		"comida":
			for p in _astronautas_destino(detalle):
				p.hambre = clampf(p.hambre - cantidad, 0.0, 100.0)
		"descanso":
			for p in _astronautas_destino(detalle):
				p.sueno = clampf(p.sueno - cantidad, 0.0, 100.0)
		"salud":
			for p in _astronautas_destino(detalle):
				p.dano_ambiental = clampf(p.dano_ambiental - cantidad, 0.0, 100.0)
		"mantenimiento":
			for m in get_tree().get_nodes_in_group("maquinas"):
				if m.tiene_desgaste and _maquina_coincide(m, detalle):
					m.mantenimiento = clampf(m.mantenimiento + cantidad, 0.0, 100.0)
		"investigacion":
			for e in get_tree().get_nodes_in_group("maquinas"):
				if e is Escritorio:
					e.progreso_investigacion = maxf(0.0, e.progreso_investigacion + cantidad)
					break
		"desbloqueo":
			if signo > 0:
				recursos.investigaciones_desbloqueadas += maxi(1, int(efecto.get("cantidad", 1)))
		"apagar":
			for m in get_tree().get_nodes_in_group("maquinas"):
				if _maquina_coincide(m, detalle):
					m.apagar(float(efecto.get("segundos", 60)))
		"posponer":
			if not _ev_actual.is_empty():
				_pospuestos.append({"ev": _ev_actual, "t": float(efecto.get("segundos", 300))})
		_:
			return _aplicar_astronauta(partes[0], efecto, signo)
	return _describir_efecto(efecto, signo)


func _aplicar_astronauta(nombre: String, efecto: Dictionary, signo: int) -> String:
	var p := _elegido if _normalizar(nombre) == "elegir" else _buscar_astronauta(nombre)
	if p == null:
		push_warning("Evento: no hay ningún astronauta disponible para '%s'" % nombre)
		return ""
	if signo > 0:
		p.hambre = 0.0
		p.sueno = 0.0
		p.dano_ambiental = 0.0
		return "%s se recupera" % p.obtener_nombre()
	var dur := float(efecto.get("duracion", 60))
	var fuera := String(efecto.get("modo", "fuera")) == "fuera"
	var motivo := String(efecto.get("motivo", "evento"))
	p.iniciar_evento(fuera, motivo, dur)
	var entrada := {"p": p, "t": dur}
	# Explorar en el rover: se sube y el rover sale manejando del mapa (y después vuelve)
	if fuera and _estructura_actual is Rover and not _estructura_actual.en_exploracion:
		_estructura_actual.partir(p)
		entrada["rover"] = _estructura_actual
	if fuera and _cansancio_exploracion > 0.0:
		entrada["cansancio"] = _cansancio_exploracion  # vuelve cansado de explorar
		_cansancio_exploracion = 0.0
	_retirados.append(entrada)
	astronauta_retirado.emit(p)
	var d := int(dur)
	return "%s %s (%s) %d:%02d" % [p.obtener_nombre(), "fuera de la base" if fuera else "ocupado",
			motivo, d / 60, d % 60]


## true mientras dura una lluvia de partículas (base.gd se lo pasa a los astronautas).
func lluvia_activa() -> bool:
	for a in _activos:
		if bool(a["ev"].get("lluvia", false)):
			return true
	return false


func _actualizar_activos(delta: float) -> void:
	for i in range(_activos.size() - 1, -1, -1):
		var a := _activos[i]
		var ev: Dictionary = a["ev"]
		var id := String(ev.get("id", ev.get("titulo", "evento")))
		a["t"] -= delta
		for efecto in _lista(ev.get("mientras_dura", [])):
			var clave := _normalizar(String(efecto.get("recurso", "")))
			if clave in ["energia", "oxigeno", "radiacion"]:
				var valor := float(recursos.get(clave)) + float(efecto.get("cantidad", 0)) * delta
				recursos.set(clave, clampf(valor, 0.0, 100.0))
		if a["t"] <= 0.0:
			_activos.remove_at(i)
			hud.quitar_banner(id)
			hud.agregar_alerta("Terminó: %s" % String(ev.get("titulo", "evento")), 0)
			continue
		var t := int(ceilf(a["t"]))
		hud.mostrar_banner(id, "%s · quedan %d:%02d" % [String(ev.get("titulo", "Evento")), t / 60, t % 60])


func _actualizar_retirados(delta: float) -> void:
	for i in range(_retirados.size() - 1, -1, -1):
		var r := _retirados[i]
		var p: Personaje = r["p"]
		if not is_instance_valid(p):
			_retirados.remove_at(i)
			continue
		if p.en_pausa_evento():
			continue  # comiendo o durmiendo en medio del trabajo: el tiempo no corre
		r["t"] -= delta
		if not is_instance_valid(p):
			_retirados.remove_at(i)
			continue
		p.tiempo_evento = r["t"]
		if r["t"] <= 0.0:
			_retirados.remove_at(i)
			var rover = r.get("rover")
			if rover != null and is_instance_valid(rover):
				# Primero vuelve el rover manejando; al llegar, el astronauta se baja
				var cansancio := float(r.get("cansancio", 0.0))
				rover.volver(func():
					p.terminar_evento(rover.punto_de_bajada())
					_cansar(p, cansancio)
					hud.agregar_alerta("%s volvió de explorar con el rover%s" % [p.obtener_nombre(),
							" (cansado)" if cansancio > 0.0 else ""], 0, p))
				continue
			p.terminar_evento()
			_cansar(p, float(r.get("cansancio", 0.0)))
			hud.agregar_alerta("%s volvió y está disponible" % p.obtener_nombre(), 0, p)


## Al volver de explorar pierde la energía que costó la exploración.
func _cansar(p: Personaje, cansancio: float) -> void:
	if cansancio > 0.0 and is_instance_valid(p):
		p.sueno = clampf(p.sueno + cansancio, 0.0, 100.0)


func _astronautas_destino(detalle: String) -> Array[Personaje]:
	var lista: Array[Personaje] = []
	if detalle == "":
		lista.assign(tripulacion)
	else:
		var p := _buscar_astronauta(detalle)
		if p != null:
			lista.append(p)
	return lista


## Por nombre (sin importar tildes ni mayúsculas) o "cualquiera" = uno al azar disponible.
func _buscar_astronauta(nombre: String) -> Personaje:
	var buscado := _normalizar(nombre)
	if _fijados.has(buscado) and is_instance_valid(_fijados[buscado]):
		return _fijados[buscado]
	if buscado == "cualquiera":
		var disponibles: Array[Personaje] = []
		for p in tripulacion:
			if not p.en_evento and not p.desmayado:
				disponibles.append(p)
		return disponibles.pick_random() if not disponibles.is_empty() else null
	for p in tripulacion:
		if _normalizar(p.obtener_nombre()) == buscado:
			return p
	return null


func _maquina_coincide(m: Maquina, detalle: String) -> bool:
	if detalle == "" or _normalizar(detalle) == "todas":
		return true
	var d := _normalizar(detalle)
	return d == _normalizar(String(m.tipo_ajuste())) or d == _normalizar(m.nombre_maquina)


func _normalizar(texto: String) -> String:
	var t := texto.strip_edges().to_lower()
	for par in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ñ", "n"]]:
		t = t.replace(par[0], par[1])
	return t
