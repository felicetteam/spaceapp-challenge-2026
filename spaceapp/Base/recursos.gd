class_name Recursos
extends Node
const Idioma := preload("res://Base/idioma.gd")
## Recursos globales de la base y reloj marciano (un sol dura 24:39).
## Los multiplicadores de velocidad están en Base/ajustes.gd.
## base.gd lo crea como hijo. Cualquier nodo lo encuentra con Recursos.de(self).
##
## Energía: la suman los "generadores_energia" y la restan los "consumidores_energia"
##   (grupos con los métodos generacion_energia() / consumo_energia()). Sin energía
##   las máquinas dejan de funcionar.
## Oxígeno: mientras haya una máquina de O2 funcionando, sigue a la energía: se mantiene
##   al 100% con energía >= 75%; por debajo baja despacio hasta el nivel de la energía,
##   y si la energía sube, sube despacio hasta alcanzarla. Sin máquina de O2, baja solo.
##   Si la máquina está desgastada pone un tope: borde amarillo hasta 75%, rojo hasta 50%
##   (bajando muy despacio). Rota (mantenimiento 0) ya no funciona y el oxígeno cae a 0.
## Radiación: sube sola salvo que haya un escudo funcionando. Con un escudo en amarillo o mejor
##   (sin llegar al rojo) además baja sola, bastante rápido; en rojo solo la frena. Acelera el desgaste de las
##   máquinas y, por encima de 80%, daña la salud de los astronautas.

signal actualizado(recursos: Recursos)
## nivel: 0 info, 1 aviso, 2 peligro. objetivo: lo que causó la alerta (o null), para centrar la cámara.
signal alerta(texto: String, nivel: int, objetivo: Node2D)
signal amanecer
signal anochecer

const DURACION_SOL_HORAS := 24.65  # 24 h 39 min

@export_group("Inicio")
@export_range(0.0, 100.0) var energia := 100.0
@export_range(0.0, 100.0) var oxigeno := 100.0
@export_range(0.0, 100.0) var radiacion := 10.0

@export_group("Reloj")
## Cuántos segundos reales dura un sol completo (por defecto, 1 hora de juego = 1 minuto real).
@export var duracion_sol_segundos := DURACION_SOL_HORAS * 60.0
@export var hora_inicial := 8.0
@export var hora_amanecer := 6.0
## Desde esta hora los paneles empiezan a perder efectividad.
@export var hora_inicio_declive := 12.0
@export var hora_anochecer := 18.5
## Efectividad de los paneles justo antes de anochecer.
@export_range(0.0, 1.0) var efectividad_al_anochecer := 0.15

@export_group("Energía")
## Consumo fijo de la base (iluminación, soporte vital), por segundo.
@export var consumo_base := 0.03

@export_group("Oxígeno")
## Debajo de este nivel de energía, el oxígeno baja hasta igualarla.
@export var umbral_energia_o2 := 75.0
## Qué tan rápido el oxígeno se acerca a su objetivo, por segundo.
@export var ritmo_o2 := 0.4
## Cuánto baja por segundo si ninguna máquina de O2 funciona.
@export var perdida_o2_sin_maquina := 0.2
## Cuánto baja por segundo, como mucho, cuando la máquina desgastada no da para más (muy lento).
@export var perdida_o2_desgaste := 0.05

@export_group("Radiación")
## Cuánto sube por segundo cuando no hay escudos funcionando.
@export var aumento_radiacion := 0.04
## Cuánto baja por segundo con un escudo en amarillo o mejor (de 100% a 0% en unos 7 minutos).
@export var descenso_radiacion := 0.25

var sol := 1
## Investigaciones habilitadas por exploraciones (sin ninguna, el escritorio no avanza).
var investigaciones_desbloqueadas := 0
var hora := 8.0
var comunicaciones_activas := false
var generacion_actual := 0.0
var consumo_actual := 0.0

# Banderas que las máquinas encienden cada frame en que funcionan
var _o2_regulado := false
## Máximo de oxígeno que pueden sostener las máquinas de O2 este frame (según su desgaste).
var _tope_o2 := 0.0
var _escudo_activo := false
## Algún escudo funcionando está en amarillo o mejor: la radiación baja.
var _escudo_bajando := false
var _comunicaciones := false
var _era_de_dia := true
var _t_alertas := 0.0
var _alertas_disparadas := {}


static func de(nodo: Node) -> Recursos:
	if nodo == null or not nodo.is_inside_tree():
		return null
	return nodo.get_tree().get_first_node_in_group("recursos") as Recursos


func _ready() -> void:
	add_to_group("recursos")
	hora = hora_inicial
	_era_de_dia = es_de_dia()
	# Se procesa después de las máquinas, que encienden sus banderas en su propio _process
	process_priority = 100


func _process(delta: float) -> void:
	_avanzar_reloj(delta)

	var aj := Ajustes.actual()

	# Energía
	generacion_actual = 0.0
	for g in get_tree().get_nodes_in_group("generadores_energia"):
		generacion_actual += g.generacion_energia()
	generacion_actual *= aj.generacion_energia
	consumo_actual = consumo_base
	for c in get_tree().get_nodes_in_group("consumidores_energia"):
		consumo_actual += c.consumo_energia()
	consumo_actual *= aj.consumo_energia
	energia = clampf(energia + (generacion_actual - consumo_actual) * delta, 0.0, 100.0)

	# Oxígeno
	if _o2_regulado:
		var objetivo := 100.0 if energia >= umbral_energia_o2 else energia
		var ritmo := ritmo_o2 * (aj.caida_oxigeno if objetivo < oxigeno else 1.0)
		if _tope_o2 < objetivo:
			# La máquina desgastada no llega: baja muy despacio hasta su tope
			objetivo = _tope_o2
			if oxigeno > objetivo:
				ritmo = perdida_o2_desgaste * aj.caida_oxigeno
		oxigeno = move_toward(oxigeno, objetivo, ritmo * delta)
	else:
		oxigeno = move_toward(oxigeno, 0.0, perdida_o2_sin_maquina * aj.caida_oxigeno * delta)

	# Radiación
	if not _escudo_activo:
		radiacion = minf(100.0, radiacion + aumento_radiacion * aj.subida_radiacion * delta)
	elif _escudo_bajando:
		radiacion = maxf(0.0, radiacion - descenso_radiacion * delta)

	comunicaciones_activas = _comunicaciones
	_o2_regulado = false
	_tope_o2 = 0.0
	_escudo_activo = false
	_escudo_bajando = false
	_comunicaciones = false

	_t_alertas -= delta
	if _t_alertas <= 0.0:
		_t_alertas = 0.5
		_revisar_alertas()

	actualizado.emit(self)


# --- Lo que llaman las máquinas mientras funcionan -----------------------------

## tope: el máximo de oxígeno que sostiene la máquina (100 si está sana). Con varias
## máquinas de O2 vale la que esté mejor.
func regular_oxigeno(tope := 100.0) -> void:
	_o2_regulado = true
	_tope_o2 = maxf(_tope_o2, tope)

## baja: el escudo está en amarillo o mejor, así que además de frenarla hace bajar la radiación.
func activar_escudo(baja := false) -> void:
	_escudo_activo = true
	_escudo_bajando = _escudo_bajando or baja

func reportar_comunicaciones() -> void:
	_comunicaciones = true

func hay_energia() -> bool:
	return energia > 0.0


# --- Consultas -----------------------------------------------------------------

## Multiplicador del desgaste de las máquinas por la radiación (1x sin radiación, 3x al 100%).
func multiplicador_desgaste() -> float:
	return 1.0 + radiacion / 50.0

## Qué tanto rinde la comida del comedor según los invernaderos (0..1).
## Si no hay ningún invernadero en la base, rinde al 100%.
func efectividad_comida() -> float:
	var invernaderos := get_tree().get_nodes_in_group("invernaderos")
	if invernaderos.is_empty():
		return 1.0
	var mejor := 0.0
	for i in invernaderos:
		if i.funcionando():
			mejor = maxf(mejor, i.mantenimiento / 100.0)
	return mejor

## Segundos reales que dura una hora de juego (con el multiplicador del reloj).
func segundos_por_hora() -> float:
	return duracion_sol_segundos / DURACION_SOL_HORAS / maxf(Ajustes.actual().velocidad_reloj, 0.001)


## Horas de juego que dura la noche (de hora_anochecer a hora_amanecer).
func horas_de_noche() -> float:
	return fposmod(hora_amanecer - hora_anochecer, DURACION_SOL_HORAS)


func es_de_dia() -> bool:
	return hora >= hora_amanecer and hora < hora_anochecer

## Efectividad de los paneles solares según la hora (0..1).
func factor_solar() -> float:
	if not es_de_dia():
		return 0.0
	if hora < hora_inicio_declive:
		return 1.0
	var t := inverse_lerp(hora_inicio_declive, hora_anochecer, hora)
	return lerpf(1.0, efectividad_al_anochecer, t)

## Luz ambiente para el ciclo día/noche (0 noche, 1 día), con una hora de transición.
func luz() -> float:
	var amanecer_t := clampf(hora - hora_amanecer + 0.5, 0.0, 1.0)
	var anochecer_t := clampf(hora_anochecer + 0.5 - hora, 0.0, 1.0)
	return minf(amanecer_t, anochecer_t)

func texto_reloj() -> String:
	var h := int(hora)
	var m := int((hora - h) * 60.0)
	return Idioma.t("Sol %d · %02d:%02d %s") % [sol, h, m, Idioma.t("Día") if es_de_dia() else Idioma.t("Noche")]


# --- Interno -------------------------------------------------------------------

func _avanzar_reloj(delta: float) -> void:
	hora += delta * DURACION_SOL_HORAS / duracion_sol_segundos * Ajustes.actual().velocidad_reloj
	if hora >= DURACION_SOL_HORAS:
		hora -= DURACION_SOL_HORAS
		sol += 1
	var de_dia := es_de_dia()
	if de_dia != _era_de_dia:
		_era_de_dia = de_dia
		if de_dia:
			amanecer.emit()
			_avisar(Idioma.t("Amanece: los paneles vuelven a cargar"), 0)
		else:
			anochecer.emit()
			_avisar(Idioma.t("Anochece: los paneles dejan de generar"), 0)


func _avisar(texto: String, nivel: int) -> void:
	if comunicaciones_activas:
		alerta.emit(texto, nivel, null)


## Aviso de otro nodo (por ejemplo, un astronauta que se despertó). Como todas las alertas,
## solo llega con las comunicaciones funcionando.
func avisar(texto: String, nivel: int, objetivo: Node2D = null) -> void:
	if comunicaciones_activas:
		alerta.emit(texto, nivel, objetivo)


## Las alertas solo llegan con las comunicaciones funcionando. Cada condición avisa una vez
## y se rearma cuando deja de cumplirse.
func _revisar_alertas() -> void:
	_condicion("energia", energia < 25.0, Idioma.t("Energía baja (%d%%)") % roundi(energia), 1)
	_condicion("energia0", energia <= 0.0, Idioma.t("Sin energía: las máquinas se detuvieron"), 2)
	_condicion("o2", oxigeno < 50.0, Idioma.t("Oxígeno bajo (%d%%)") % roundi(oxigeno), 1)
	_condicion("radiacion", radiacion > 80.0, Idioma.t("Radiación peligrosa (%d%%)") % roundi(radiacion), 2)
	for m in get_tree().get_nodes_in_group("maquinas"):
		if not m.tiene_desgaste:
			continue
		var id := str(m.get_instance_id())
		_condicion("crit" + id, m.mantenimiento <= m.umbral_critico and not m.averiada,
				Idioma.t("%s: mantenimiento crítico") % Idioma.t(m.nombre_maquina), 1, m)
		_condicion("rota" + id, m.averiada, Idioma.t("%s fuera de servicio") % Idioma.t(m.nombre_maquina), 2, m)
	for a in get_tree().get_nodes_in_group("astronautas"):
		_condicion("desm" + str(a.get_instance_id()), a.desmayado,
				Idioma.t("%s está inconsciente") % a.obtener_nombre(), 2, a)


func _condicion(clave: String, activa: bool, texto: String, nivel: int, objetivo: Node2D = null) -> void:
	if not activa:
		_alertas_disparadas.erase(clave)
		return
	if _alertas_disparadas.has(clave) or not comunicaciones_activas:
		return
	_alertas_disparadas[clave] = true
	alerta.emit(texto, nivel, objetivo)
