class_name Maquina
extends Node2D
## Comportamiento común de todas las máquinas (va en la raíz de cada escena de Maquinas/).
## - El mantenimiento baja con el tiempo, más rápido cuanto más radiación hay.
## - Los astronautas que trabajan en ella (laburar_brazo) lo suben.
## - Necesita energía para cumplir su función (salvo que requiere_energia sea false).
## - Muestra una barra flotante, como la de salud de los personajes, si las comunicaciones andan.
## Funciona con raíz StaticBody2D, AnimatableBody2D o Node2D.
##
## Para una máquina con función propia, extendé este script y sobreescribí _funcion(delta)
## (se llama cada frame mientras la máquina funciona).

signal estado_actualizado(maquina: Maquina)
signal fuera_de_servicio(maquina: Maquina)

## Nombre en la interfaz. Si queda vacío, usa el nombre del nodo.
@export var nombre_maquina := ""
@export_range(0.0, 100.0) var mantenimiento := 100.0
## Si es false, no se desgasta ni aparece en el panel de mantenimiento (por ejemplo, el escritorio).
@export var tiene_desgaste := true
## true desde que el mantenimiento llegó a 0 hasta que la reparan por encima de umbral_critico.
var averiada := false
## Cuánto baja por segundo sin radiación (la radiación lo multiplica hasta x3).
@export var desgaste_por_segundo := 0.15
## Cuánto sube por segundo por cada astronauta que está laburando en ella.
@export var reparacion_por_segundo := 6.0

@export_group("Energía")
@export var requiere_energia := true
## Energía que consume por segundo mientras está en servicio.
@export var consumo := 0.02

@export_group("Trabajo")
## Distancia mínima y máxima (en píxeles, desde el borde del sprite) de los puestos de trabajo.
@export var margen_trabajo_min := 2.0
@export var margen_trabajo_max := 18.0
## Si es true, los caminos rodean el sprite en lugar de atravesarlo.
@export var bloquea_camino := true

@export_group("Barra flotante")
@export var mostrar_barra := true
@export var ancho_barra := 24.0

@export_group("Borde de estado")
## Debajo de este mantenimiento aparece un borde amarillo que pasa a rojo a medida que baja.
@export var umbral_borde := 75.0
## Con este mantenimiento (o menos) el borde ya es rojo y titila.
@export var umbral_critico := 25.0
## Grosor del borde en píxeles del mundo.
@export var grosor_borde := 1.5

var trabajadores: Array[Personaje] = []
var _escritorio_buscado := false
var _escritorio_debajo: Escritorio = null
var _sprite: Node2D
## Todos los sprites de la máquina (por ejemplo, los 3 paneles de la fotovoltaica): el rectángulo,
## el borde de estado y el gris de "apagada" los abarcan a todos.
var _sprites: Array[Node2D] = []
## Segundos que le quedan apagada por un evento: no funciona ni se puede reparar.
var _t_apagada := 0.0
var _barra: ProgressBar
var _estilo_relleno: StyleBoxFlat
var _estaba_fuera := false
var _recursos: Recursos
var _material_borde: ShaderMaterial


func _ready() -> void:
	add_to_group("maquinas")
	if tiene_desgaste:
		# Cada máquina arranca con un mantenimiento al azar (por defecto entre 90 y 100)
		var aj := Ajustes.actual()
		mantenimiento = randf_range(aj.mantenimiento_inicial_min, aj.mantenimiento_inicial_max)
	if requiere_energia:
		add_to_group("consumidores_energia")
	if nombre_maquina.is_empty():
		nombre_maquina = String(name).capitalize()
	_sprite = _buscar_sprite(self)
	for hijo in get_children():
		if (hijo is Sprite2D or hijo is AnimatedSprite2D) and not String(hijo.name).begins_with("Silla"):
			_sprites.append(hijo)
	if mostrar_barra and tiene_desgaste:
		_crear_barra()
	_crear_borde()
	_actualizar_barra()
	boton_jugar.pressed.connect(_on_jugar_pressed)
	boton_diario.pressed.connect(_on_diario_pressed)
	boton_salir.pressed.connect(_on_salir_pressed)


func _process(delta: float) -> void:
	_t_apagada = maxf(0.0, _t_apagada - delta)
	if tiene_desgaste and not esta_apagada():
		var mult := recursos().multiplicador_desgaste() if recursos() != null else 1.0
		mult *= Ajustes.actual().desgaste_de(tipo_ajuste())
		mantenimiento = clampf(mantenimiento - desgaste_por_segundo * mult * delta, 0.0, 100.0)
		# Rota (mantenimiento 0) queda averiada hasta que la reparen por encima de umbral_critico
		# (es decir, hasta volver al amarillo); recién ahí vuelve a funcionar.
		if mantenimiento <= 0.0:
			averiada = true
		elif averiada and mantenimiento > umbral_critico:
			averiada = false
		if averiada and not _estaba_fuera:
			fuera_de_servicio.emit(self)
		_estaba_fuera = averiada

	var activa := funcionando()
	if activa:
		_funcion(delta)
	for spr in _sprites:
		spr.modulate = Color.WHITE if activa else Color(0.55, 0.55, 0.62)
	_actualizar_barra()
	_actualizar_borde()
	estado_actualizado.emit(self)


# --- Para sobreescribir ------------------------------------------------------

## Lo que hace la máquina cada frame mientras funciona.
func _funcion(_delta: float) -> void:
	pass


# --- API ---------------------------------------------------------------------

func recursos() -> Recursos:
	if _recursos == null:
		_recursos = Recursos.de(self)
	return _recursos


## true si tiene mantenimiento y (si la necesita) energía.
func funcionando() -> bool:
	if esta_apagada():
		return false
	if tiene_desgaste and averiada:
		return false
	if requiere_energia and (recursos() == null or not recursos().hay_energia()):
		return false
	return true


## Energía que pide este frame (la suma Recursos).
func consumo_energia() -> float:
	if requiere_energia and (not tiene_desgaste or not averiada):
		return consumo
	return 0.0


## La llama el Personaje mientras está laburando en un puesto de esta máquina.
## Reparar no necesita energía.
func trabajar(delta: float) -> void:
	reparar(delta)


func reparar(delta: float) -> void:
	if tiene_desgaste and not esta_apagada():
		var mult := Ajustes.actual().trabajo_de(tipo_ajuste())
		# Trabajo en equipo: cada astronauta extra en la máquina acelera la reparación
		mult *= 1.0 + Ajustes.actual().bonus_equipo * maxi(trabajadores_activos() - 1, 0)
		mantenimiento = clampf(mantenimiento + reparacion_por_segundo * mult * delta, 0.0, 100.0)


## Clave de este tipo de máquina en Base/ajustes.gd (trabajo_<tipo>). Las subclases la
## sobreescriben; las máquinas genéricas usan trabajo_otras.
func tipo_ajuste() -> StringName:
	return &"otras"


func agregar_trabajador(p: Personaje) -> void:
	if not trabajadores.has(p):
		trabajadores.append(p)


func quitar_trabajador(p: Personaje) -> void:
	trabajadores.erase(p)


## Cuántos astronautas están reparando ahora (ya en su puesto, no los que vienen caminando).
func trabajadores_activos() -> int:
	var n := 0
	for p in trabajadores:
		if is_instance_valid(p) and p.esta_en_puesto():
			n += 1
	return n


## true si hay más de un astronauta reparando a la vez.
func en_equipo() -> bool:
	return tiene_desgaste and trabajadores_activos() > 1


func obtener_estado() -> String:
	if esta_apagada():
		var t := int(ceilf(_t_apagada))
		return "Apagada %d:%02d (no se puede reparar)" % [t / 60, t % 60]
	if tiene_desgaste and averiada:
		if mantenimiento <= 0.0:
			return "Fuera de servicio"
		return "Averiada: reparar hasta %d%%" % roundi(umbral_critico)
	if requiere_energia and recursos() != null and not recursos().hay_energia():
		return "Sin energía"
	if not tiene_desgaste:
		return "Operativa"
	if mantenimiento >= umbral_borde:
		return "Operativa"
	elif mantenimiento > umbral_critico:
		return "Desgastada"
	return "Crítica"


## Mismo criterio que el borde: verde sin borde; debajo de umbral_borde pasa de amarillo a rojo,
## y desde umbral_critico es rojo. Lo usan la barra sobre la máquina y el panel del HUD.
func color_estado() -> Color:
	if not tiene_desgaste or mantenimiento >= umbral_borde:
		return Color(0.2, 0.85, 0.35)
	return color_desgaste()


## Color del borde y de la barra cuando hay desgaste (amarillo -> rojo).
func color_desgaste() -> Color:
	var t := clampf(inverse_lerp(umbral_borde, umbral_critico, mantenimiento), 0.0, 1.0)
	return Color(1.0, 0.85, 0.1).lerp(Color(0.95, 0.12, 0.08), t)


## Apaga la máquina por un evento: no funciona ni se puede reparar durante esos segundos.
func apagar(segundos: float) -> void:
	_t_apagada = maxf(_t_apagada, segundos)


func esta_apagada() -> bool:
	return _t_apagada > 0.0


## Rectángulo global que abarca todos los sprites (clics, puestos de trabajo, bloqueo de caminos).
func rect_global() -> Rect2:
	if _sprites.is_empty():
		if _sprite == null:
			return Rect2(global_position - Vector2(8, 8), Vector2(16, 16))
		return _rect_de(_sprite)
	var r := _rect_de(_sprites[0])
	for i in range(1, _sprites.size()):
		r = r.merge(_rect_de(_sprites[i]))
	return r


func _rect_de(spr: Node2D) -> Rect2:
	var local := Rect2()
	if spr is Sprite2D:
		local = (spr as Sprite2D).get_rect()
	elif spr is AnimatedSprite2D:
		var a := spr as AnimatedSprite2D
		if a.sprite_frames != null and a.sprite_frames.has_animation(a.animation) \
				and a.sprite_frames.get_frame_count(a.animation) > 0:
			var tam := a.sprite_frames.get_frame_texture(a.animation, a.frame).get_size()
			local = Rect2(-tam * 0.5 if a.centered else Vector2.ZERO, tam)
			local.position += a.offset
	return spr.get_global_transform() * local


func contiene_punto(p: Vector2) -> bool:
	return rect_global().has_point(p)


## Si se la puede elegir (clic, flechas, lista de problemas). El rover no, mientras explora.
func seleccionable() -> bool:
	return true


## Si la máquina está puesta encima de un escritorio, se trabaja sentado en la silla de ese
## escritorio (alrededor no hay lugar). null si se trabaja dando vueltas alrededor.
func escritorio_de_silla() -> Escritorio:
	if not _escritorio_buscado:
		_escritorio_buscado = true
		var mio := rect_global()
		for n in get_tree().get_nodes_in_group("maquinas"):
			if n is Escritorio and n != self and n.posicion_silla() != Vector2.INF \
					and n.rect_global().intersects(mio):
				_escritorio_debajo = n
				break
	return _escritorio_debajo if is_instance_valid(_escritorio_debajo) else null


func puntos_de_trabajo(nav: Navegacion) -> Array[Vector2]:
	return nav.puntos_alrededor(rect_global(), margen_trabajo_min, margen_trabajo_max)


# --- Interno -----------------------------------------------------------------

func _buscar_sprite(nodo: Node) -> Node2D:
	for hijo in nodo.get_children():
		if hijo is Sprite2D or hijo is AnimatedSprite2D:
			return hijo
	return null


func _crear_barra() -> void:
	var rect_local := get_global_transform().affine_inverse() * rect_global()
	_barra = ProgressBar.new()
	_barra.show_percentage = false
	_barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_barra.z_index = 10
	_barra.size = Vector2(ancho_barra, 4)
	_barra.position = Vector2(rect_local.get_center().x - ancho_barra * 0.5, rect_local.position.y - 6.0)

	var fondo := StyleBoxFlat.new()
	fondo.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	_barra.add_theme_stylebox_override("background", fondo)
	_estilo_relleno = StyleBoxFlat.new()
	_barra.add_theme_stylebox_override("fill", _estilo_relleno)
	add_child(_barra)


func _crear_borde() -> void:
	if not tiene_desgaste or not (_sprite is Sprite2D):
		return
	_material_borde = ShaderMaterial.new()
	_material_borde.shader = preload("res://Base/shaders/contorno_maquina.gdshader")
	var escala := absf(_sprite.global_scale.x)
	_material_borde.set_shader_parameter("grosor", grosor_borde / maxf(escala, 0.01))
	# El mismo material en todos los sprites: el borde rodea a cada uno (los 3 paneles, etc.)
	for spr in _sprites:
		if spr is Sprite2D:
			spr.material = _material_borde


## Borde que aparece amarillo cuando la máquina empieza a desgastarse y pasa a rojo (titilando)
## cuando está crítica. Como los desgastes, solo se ve con las comunicaciones funcionando.
func _actualizar_borde() -> void:
	if _material_borde == null:
		return
	var visible_borde := mantenimiento < umbral_borde and recursos() != null \
			and recursos().comunicaciones_activas
	_material_borde.set_shader_parameter("activo", visible_borde)
	if not visible_borde:
		return
	_material_borde.set_shader_parameter("color_borde", color_desgaste())
	_material_borde.set_shader_parameter("parpadeo", mantenimiento <= umbral_critico)


func _actualizar_barra() -> void:
	if _barra == null:
		return
	# Los desgastes solo se ven con las comunicaciones funcionando
	_barra.visible = recursos() != null and recursos().comunicaciones_activas
	_barra.value = mantenimiento
	_estilo_relleno.bg_color = color_estado()

@onready var boton_jugar: Button = $CenterContainer/VBoxContainer/BotonJugar
@onready var boton_diario: Button = $CenterContainer/VBoxContainer/BotonDiario
@onready var boton_salir: Button = $CenterContainer/VBoxContainer/BotonSalir

func _on_jugar_pressed() -> void:
	get_tree().change_scene_to_file("res://escenas/juego.tscn") # ajusta la ruta a tu escena de juego

func _on_diario_pressed() -> void:
	get_tree().change_scene_to_file("res://escenas/diario.tscn") # ajusta o crea esta escena

func _on_salir_pressed() -> void:
	get_tree().quit()
