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
##   "estructura": "rover",                  (opcional: a dónde tienen que ir los astronautas)
##   "opcion_a": { "texto": "...", "gana": {...}, "pierde": {...},
##                 "estructura": "escudo" },  (opcional: otra estructura para esta opción;
##                                            "" = esta opción no necesita ir a ningún lado)
##   "opcion_b": { "texto": "...", "gana": {...}, "pierde": {...} },
##   "dato_nasa": "Dato real",               (opcional)
##   "fuente": "De dónde sale el dato"       (opcional)
## }
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
## Si los astronautas no llegan en este tiempo, la decisión se aplica igual.
const ESPERA_MAXIMA := 120.0


func _ready() -> void:
	cargar()
	_t = Ajustes.actual().primer_evento


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
				and ev.get("opcion_b") is Dictionary:
			_eventos.append(ev)
		else:
			push_warning("%s: el evento %d está incompleto (falta descripcion, opcion_a u opcion_b)" % [RUTA, i])
	print("Eventos críticos cargados: %d" % _eventos.size())


func _process(delta: float) -> void:
	_actualizar_retirados(delta)
	_revisar_pendiente(delta)
	for i in range(_pospuestos.size() - 1, -1, -1):
		_pospuestos[i]["t"] -= delta
		if _pospuestos[i]["t"] <= 0.0 and not _abierto:
			var ev: Dictionary = _pospuestos[i]["ev"]
			_pospuestos.remove_at(i)
			lanzar(ev)
	var aj := Ajustes.actual()
	if not aj.eventos_activados or _eventos.is_empty() or _abierto:
		return
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
	get_tree().paused = true
	evento_iniciado.emit(ev)
	# Una opción que necesita elegir un astronauta no se puede tomar si no hay nadie disponible
	var bloqueadas: Array[String] = []
	for clave in ["opcion_a", "opcion_b"]:
		if _requiere_elegir(ev.get(clave, {})) and _disponibles().is_empty():
			bloqueadas.append(clave)
	hud.mostrar_evento(ev, _describir_opcion(ev, "opcion_a"), _describir_opcion(ev, "opcion_b"),
			func(clave: String): _elegir(ev, clave), " · ".join(iniciales), bloqueadas)


func _elegir(ev: Dictionary, clave: String) -> void:
	var opcion: Dictionary = ev.get(clave, {})
	if _requiere_elegir(opcion):
		# Primero el jugador elige quién va; el juego sigue en pausa
		hud.elegir_astronauta(_disponibles(), String(opcion.get("texto", "")), func(p: Personaje):
			_elegido = p
			_resolver(ev, clave))
	else:
		_resolver(ev, clave)


## Después de decidir: si la opción tiene estructura, primero caminan hasta ahí.
func _resolver(ev: Dictionary, clave: String) -> void:
	var opcion: Dictionary = ev.get(clave, {})
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
	_pendiente = {"ev": ev, "clave": clave, "caminantes": en_camino, "t": ESPERA_MAXIMA}
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
	_pendiente = {}
	_aplicar_opcion(ev, clave)


func _aplicar_opcion(ev: Dictionary, clave: String) -> void:
	_ev_actual = ev
	var opcion: Dictionary = ev.get(clave, {})
	var textos: PackedStringArray = []
	for efecto in _lista(opcion.get("gana", {})):
		var t := _aplicar(efecto, 1)
		if t != "":
			textos.append(t)
	for efecto in _lista(opcion.get("pierde", {})):
		var t := _aplicar(efecto, -1)
		if t != "":
			textos.append(t)
	_elegido = null
	_fijados.clear()
	get_tree().paused = false
	_abierto = false
	evento_resuelto.emit(ev, clave)
	var titulo: String = ev.get("titulo", "Evento")
	hud.agregar_alerta("%s: %s" % [titulo, " · ".join(textos) if not textos.is_empty() else "sin efectos"], 1)
	if not _cola.is_empty():
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
	var nombre := _estructura_de(ev, clave)
	if nombre != "":
		var lista := _buscar_estructuras(nombre)
		var donde := _nombre_estructura(lista[0]) if not lista.is_empty() else nombre
		texto = "Ir a %s · %s" % [donde, texto] if texto != "" else "Ir a %s" % donde
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
	for efecto in _lista(opcion.get("gana", {})):
		var t := _describir_efecto(efecto, 1)
		if t != "":
			partes.append(t)
	for efecto in _lista(opcion.get("pierde", {})):
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
	_retirados.append({"p": p, "t": dur})
	astronauta_retirado.emit(p)
	var d := int(dur)
	return "%s %s (%s) %d:%02d" % [p.obtener_nombre(), "fuera de la base" if fuera else "ocupado",
			motivo, d / 60, d % 60]


func _actualizar_retirados(delta: float) -> void:
	for i in range(_retirados.size() - 1, -1, -1):
		var r := _retirados[i]
		var p: Personaje = r["p"]
		r["t"] -= delta
		if not is_instance_valid(p):
			_retirados.remove_at(i)
			continue
		p.tiempo_evento = r["t"]
		if r["t"] <= 0.0:
			p.terminar_evento()
			_retirados.remove_at(i)
			hud.agregar_alerta("%s volvió y está disponible" % p.obtener_nombre(), 0, p)


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
