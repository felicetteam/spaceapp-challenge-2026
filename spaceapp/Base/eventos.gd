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
##   "opcion_a": { "texto": "...", "gana": {...}, "pierde": {...} },
##   "opcion_b": { "texto": "...", "gana": {...}, "pierde": {...} }
## }
##
## "gana" y "pierde" llevan { "recurso": ..., "cantidad": ... }. Recursos posibles:
##   "energia", "oxigeno", "radiacion"      puntos del recurso global (0 a 100)
##   "comida", "descanso", "salud"          para toda la tripulación; "comida:Juan" para uno solo
##   "mantenimiento"                        todas las máquinas; "mantenimiento:fotovoltaica"
##                                          (por tipo: fotovoltaica, comunicaciones, o2,
##                                          invernadero, escudo, rover) o por nombre de máquina
##   "investigacion"                        progreso del escritorio
##   "nada"                                 sin efecto
##   nombre de un astronauta ("Juan", "Laika", "Félicette", "Neil") o "cualquiera":
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
	var aj := Ajustes.actual()
	if not aj.eventos_activados or _eventos.is_empty() or _abierto:
		return
	_t -= delta
	if _t <= 0.0:
		_t = randf_range(aj.intervalo_eventos_min, aj.intervalo_eventos_max)
		lanzar_aleatorio()


## Elige un evento al azar sin repetir hasta que salgan todos (respeta "peso").
func lanzar_aleatorio() -> void:
	if _eventos.is_empty():
		return
	if _bolsa.is_empty():
		for i in _eventos.size():
			for _r in maxi(1, int(_eventos[i].get("peso", 1))):
				_bolsa.append(i)
		_bolsa.shuffle()
	lanzar(_eventos[_bolsa.pop_back()])


## Pausa el juego y muestra el evento. Si ya hay uno abierto, queda en cola.
func lanzar(ev: Dictionary) -> void:
	if _abierto:
		_cola.append(ev)
		return
	_abierto = true
	get_tree().paused = true
	evento_iniciado.emit(ev)
	hud.mostrar_evento(ev, describir(ev.get("opcion_a", {})), describir(ev.get("opcion_b", {})),
			func(clave: String): _elegir(ev, clave))


func _elegir(ev: Dictionary, clave: String) -> void:
	var opcion: Dictionary = ev.get(clave, {})
	var textos: PackedStringArray = []
	for t in [_aplicar(opcion.get("gana", {}), 1), _aplicar(opcion.get("pierde", {}), -1)]:
		if t != "":
			textos.append(t)
	get_tree().paused = false
	_abierto = false
	evento_resuelto.emit(ev, clave)
	var titulo: String = ev.get("titulo", "Evento")
	hud.agregar_alerta("%s: %s" % [titulo, " · ".join(textos) if not textos.is_empty() else "sin efectos"], 1)
	if not _cola.is_empty():
		lanzar(_cola.pop_front())


## Texto corto de los efectos de una opción, para el botón ("+25 Energía · −30 Oxígeno").
func describir(opcion: Dictionary) -> String:
	var partes: PackedStringArray = []
	var g := _describir_efecto(opcion.get("gana", {}), 1)
	var p := _describir_efecto(opcion.get("pierde", {}), -1)
	if g != "":
		partes.append(g)
	if p != "":
		partes.append(p)
	return " · ".join(partes)


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
	var cantidad := float(efecto.get("cantidad", 0))
	if NOMBRES_RECURSO.has(clave):
		var nombre: String = NOMBRES_RECURSO[clave]
		if detalle != "":
			nombre += " (%s)" % detalle
		return "%s%d %s" % ["+" if signo > 0 else "−", roundi(cantidad), nombre]
	# Astronauta
	var quien := "un astronauta" if clave == "cualquiera" else partes[0]
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
		_:
			return _aplicar_astronauta(partes[0], efecto, signo)
	return _describir_efecto(efecto, signo)


func _aplicar_astronauta(nombre: String, efecto: Dictionary, signo: int) -> String:
	var p := _buscar_astronauta(nombre)
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
