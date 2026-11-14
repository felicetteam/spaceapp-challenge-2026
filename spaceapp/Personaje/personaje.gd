@tool
class_name Personaje
extends CharacterBody2D
## Astronauta con capas animadas en simultáneo, usando sprite_frames_personaje.tres.
##   Sprite_Cuerpo : idle_base / correr_base
##   Sprite_Brazo  : idle_brazo / correr_brazo / laburar_brazo
##   Sprite_Cabeza : "Cabezas" (un frame por personaje, quieto)
##   Sprite_Casco  : "Casco" (frame 0, quieto)
## laburar_brazo se superpone en los brazos, tanto en idle como corriendo.

## Mismo orden que los frames de la animación "Cabezas".
enum Cabeza { FELICITTE, LAIKA, JUAN, NEIL }
enum ModoLaburar { MANTENER, ALTERNAR }

@export var cabeza: Cabeza = Cabeza.NEIL:
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
@export var controlado_por_jugador := true
@export var velocidad := 80.0

@export_group("Input")
## MANTENER: labura mientras la tecla está apretada. ALTERNAR: cada toque prende o apaga.
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

var corriendo := false
var laburando := false


func _ready() -> void:
	_aplicar_cabeza()
	_aplicar_casco()
	if Engine.is_editor_hint():
		return
	_actualizar_animaciones(true)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not controlado_por_jugador:
		return

	# Vista desde arriba. Para un plataformero, usá solo el eje X y sumá gravedad.
	var dir := Input.get_vector(accion_izquierda, accion_derecha, accion_arriba, accion_abajo)
	velocity = dir * velocidad
	move_and_slide()

	set_corriendo(dir != Vector2.ZERO)
	mirar(dir.x)

	match modo_laburar:
		ModoLaburar.MANTENER:
			set_laburando(Input.is_action_pressed(accion_laburar))
		ModoLaburar.ALTERNAR:
			if Input.is_action_just_pressed(accion_laburar):
				alternar_laburar()


# --- API pública (también sirve para NPCs con controlado_por_jugador = false) --

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


## dir_x < 0 mira a la izquierda, dir_x > 0 a la derecha, 0 no cambia nada.
func mirar(dir_x: float) -> void:
	if dir_x == 0.0:
		return
	for s in [sprite_cuerpo, sprite_brazo, sprite_cabeza, sprite_casco]:
		s.flip_h = dir_x < 0.0


func cabeza_aleatoria() -> void:
	cabeza = Cabeza.values().pick_random()


# --- Interno -----------------------------------------------------------------

func _actualizar_animaciones(forzar := false) -> void:
	var anim_cuerpo := &"correr_base" if corriendo else &"idle_base"
	var anim_brazo: StringName
	if laburando:
		anim_brazo = &"laburar_brazo"
	elif corriendo:
		anim_brazo = &"correr_brazo"
	else:
		anim_brazo = &"idle_brazo"

	_reproducir(sprite_cuerpo, anim_cuerpo, null, forzar)
	# Los brazos toman el ritmo del cuerpo cuando tienen la misma cantidad de frames
	# (por ejemplo, correr_base + laburar_brazo), así no quedan desfasados.
	_reproducir(sprite_brazo, anim_brazo, sprite_cuerpo, forzar)


func _reproducir(sprite: AnimatedSprite2D, anim: StringName, referencia: AnimatedSprite2D, forzar: bool) -> void:
	if not forzar and sprite.animation == anim and sprite.is_playing():
		return  # ya está en esa animación: no la reinicia
	sprite.play(anim)
	if referencia != null and referencia.sprite_frames.get_frame_count(referencia.animation) \
			== sprite.sprite_frames.get_frame_count(anim):
		sprite.set_frame_and_progress(referencia.frame, referencia.frame_progress)
	else:
		sprite.set_frame_and_progress(0, 0.0)


func _aplicar_cabeza() -> void:
	sprite_cabeza.stop()
	sprite_cabeza.animation = &"Cabezas"
	sprite_cabeza.frame = int(cabeza)


func _aplicar_casco() -> void:
	sprite_casco.stop()
	sprite_casco.animation = &"Casco"
	sprite_casco.frame = 0
	sprite_casco.visible = con_casco
