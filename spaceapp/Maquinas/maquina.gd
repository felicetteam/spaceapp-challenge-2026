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
var _sprite: Node2D
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
	if mostrar_barra and tiene_desgaste:
		_crear_barra()
	_crear_borde()
	_actualizar_barra()


func _process(delta: float) -> void:
	if tiene_desgaste:
		var mult := recursos().multiplicador_desgaste() if recursos() != null else 1.0
		mult *= Ajustes.actual().desgaste_de(tipo_ajuste())
		mantenimiento = clampf(mantenimiento - desgaste_por_segundo * mult * delta, 0.0, 100.0)
		var fuera := mantenimiento <= 0.0
		if fuera and not _estaba_fuera:
			fuera_de_servicio.emit(self)
		_estaba_fuera = fuera

	var activa := funcionando()
	if activa:
		_funcion(delta)
	if _sprite != null:
		_sprite.modulate = Color.WHITE if activa else Color(0.55, 0.55, 0.62)
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
	if tiene_desgaste and mantenimiento <= 0.0:
		return false
	if requiere_energia and (recursos() == null or not recursos().hay_energia()):
		return false
	return true


## Energía que pide este frame (la suma Recursos).
func consumo_energia() -> float:
	if requiere_energia and (not tiene_desgaste or mantenimiento > 0.0):
		return consumo
	return 0.0


## La llama el Personaje mientras está laburando en un puesto de esta máquina.
## Reparar no necesita energía.
func trabajar(delta: float) -> void:
	reparar(delta)


func reparar(delta: float) -> void:
	if tiene_desgaste:
		var mult := Ajustes.actual().trabajo_de(tipo_ajuste())
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


func obtener_estado() -> String:
	if tiene_desgaste and mantenimiento <= 0.0:
		return "Fuera de servicio"
	if requiere_energia and recursos() != null and not recursos().hay_energia():
		return "Sin energía"
	if not tiene_desgaste:
		return "Operativa"
	if mantenimiento > 60.0:
		return "Operativa"
	elif mantenimiento > 30.0:
		return "Desgastada"
	return "Crítica"


func color_estado() -> Color:
	if mantenimiento > 60.0:
		return Color(0.2, 0.85, 0.35)
	elif mantenimiento > 30.0:
		return Color(0.95, 0.75, 0.15)
	return Color(0.9, 0.2, 0.2)


## Rectángulo global del sprite (sirve para clics, puestos de trabajo y bloqueo de caminos).
func rect_global() -> Rect2:
	if _sprite == null:
		return Rect2(global_position - Vector2(8, 8), Vector2(16, 16))
	var local := Rect2()
	if _sprite is Sprite2D:
		local = (_sprite as Sprite2D).get_rect()
	elif _sprite is AnimatedSprite2D:
		var a := _sprite as AnimatedSprite2D
		if a.sprite_frames != null and a.sprite_frames.has_animation(a.animation) \
				and a.sprite_frames.get_frame_count(a.animation) > 0:
			var tam := a.sprite_frames.get_frame_texture(a.animation, a.frame).get_size()
			local = Rect2(-tam * 0.5 if a.centered else Vector2.ZERO, tam)
			local.position += a.offset
	return _sprite.get_global_transform() * local


func contiene_punto(p: Vector2) -> bool:
	return rect_global().has_point(p)


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
	_sprite.material = _material_borde


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
	var t := clampf(inverse_lerp(umbral_borde, umbral_critico, mantenimiento), 0.0, 1.0)
	var color := Color(1.0, 0.85, 0.1).lerp(Color(0.95, 0.12, 0.08), t)
	_material_borde.set_shader_parameter("color_borde", color)
	_material_borde.set_shader_parameter("parpadeo", mantenimiento <= umbral_critico)


func _actualizar_barra() -> void:
	if _barra == null:
		return
	# Los desgastes solo se ven con las comunicaciones funcionando
	_barra.visible = recursos() != null and recursos().comunicaciones_activas
	_barra.value = mantenimiento
	_estilo_relleno.bg_color = color_estado()
