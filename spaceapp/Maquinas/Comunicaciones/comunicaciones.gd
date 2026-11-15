class_name Comunicaciones
extends Maquina
## Mientras funciona, habilita las alertas y las interfaces de recursos globales y desgastes.
## Si no funciona (rota o sin energía) muestra un "!" rojo encima.

var _aviso: Label
var _t := 0.0


func _ready() -> void:
	super._ready()
	_aviso = Label.new()
	_aviso.text = "!"
	_aviso.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aviso.add_theme_font_size_override("font_size", 16)
	_aviso.add_theme_color_override("font_color", Color(1.0, 0.15, 0.15))
	_aviso.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.0))
	_aviso.add_theme_constant_override("outline_size", 4)
	_aviso.z_index = 20
	_aviso.visible = false
	add_child(_aviso)
	var rect := get_global_transform().affine_inverse() * rect_global()
	_aviso.position = Vector2(rect.get_center().x - 3.0, rect.position.y - 24.0)


func _process(delta: float) -> void:
	super._process(delta)
	_aviso.visible = not funcionando()
	if _aviso.visible:
		_t += delta
		_aviso.modulate.a = 0.6 + 0.4 * absf(sin(_t * 4.0))  # titila


func _funcion(_delta: float) -> void:
	recursos().reportar_comunicaciones()


## Clave de este tipo de máquina en ajustes_juego.tres (trabajo_comunicaciones).
func tipo_ajuste() -> StringName:
	return &"comunicaciones"
