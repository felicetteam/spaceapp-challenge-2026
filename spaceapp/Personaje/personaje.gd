@tool
class_name Personaje extends CharacterBody2D

signal estado_actualizado(personaje: Personaje)

enum Cabeza { FELICITTE, LAIKA, JUAN, NEIL }
enum ModoLaburar { MANTENER, ALTERNAR }

const NOMBRES := {
	Cabeza.FELICITTE: "Félicette",
	Cabeza.LAIKA: "Laika",
	Cabeza.JUAN: "Juan",
	Cabeza.NEIL: "Neil"
}

# Multiplicadores de gasto de Hambre y Sueño según la tabla de afinidades
const FACTOR_SALUD := {
	Cabeza.FELICITTE: 0.8, # Salud Positiva (-20% desgaste)
	Cabeza.LAIKA: 1.0,     # Neutral
	Cabeza.JUAN: 1.2,      # Salud Negativa (+20% desgaste)
	Cabeza.NEIL: 1.0       # Neutral
}

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
@onready var barra_salud: ProgressBar = $Barra_Salud

# Variables de estado vital (0 a 100)
var salud: float = 100.0
var hambre: float = 0.0        # 0 = lleno, 100 = hambriento
var sueno: float = 0.0         # 0 = descansado, 100 = agotado
var dano_ambiental: float = 0.0

# Estados de sala / entorno
var en_refugio := false
var en_exterior := false
var durmiendo := false
var corriendo := false
var laburando := false
var estado_alerta: String = "Óptimo"

var _estilo_relleno: StyleBoxFlat

func _ready() -> void:
	_aplicar_cabeza()
	_aplicar_casco()
	if Engine.is_editor_hint():
		return
	add_to_group("astronautas")
	_configurar_barra_flotante()
	_actualizar_animaciones(true)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not controlado_por_jugador:
		return

	var dir := Input.get_vector(accion_izquierda, accion_derecha, accion_arriba, accion_abajo)
	# Penalización de velocidad si tiene mucha hambre (> 70%)
	var mult_vel := 0.75 if hambre > 70.0 else 1.0
	velocity = dir * velocidad * mult_vel
	move_and_slide()

	set_corriendo(dir != Vector2.ZERO)
	mirar(dir.x)

	match modo_laburar:
		ModoLaburar.MANTENER:
			set_laburando(Input.is_action_pressed(accion_laburar))
		ModoLaburar.ALTERNAR:
			if Input.is_action_just_pressed(accion_laburar):
				alternar_laburar()

# Llamado desde base.gd en cada frame con las condiciones de la base
func actualizar_salud(delta: float, oxigeno: float, radiacion: float, lluvia_particulas: bool) -> void:
	var factor_afin: float = FACTOR_SALUD.get(cabeza, 1.0)

	# 1. Alta radiación multiplica el desgaste de hambre y sueño
	var mult_rad := 1.0
	if radiacion > 75.0:
		mult_rad = 2.0
	elif radiacion >= 40.0:
		mult_rad = 1.5

	# 2. Oxígeno bajo cansa más rápido
	var mult_o2_sueno := 1.5 if oxigeno < 50.0 else 1.0

	# 3. Avance de hambre y sueño
	var gasto_base := 0.25 * factor_afin * delta
	var extra_trabajo := 1.3 if laburando else 1.0

	if not durmiendo:
		hambre = clampf(hambre + gasto_base * extra_trabajo * mult_rad, 0.0, 100.0)
		sueno = clampf(sueno + gasto_base * mult_rad * mult_o2_sueno, 0.0, 100.0)
	else:
		sueno = clampf(sueno - 6.0 * delta, 0.0, 100.0)
		dano_ambiental = maxf(0.0, dano_ambiental - 2.5 * delta)

	# 4. Daño ambiental directo
	var dano_extra := 0.0
	if oxigeno < 20.0:
		dano_extra += 1.5 * delta
	elif oxigeno < 50.0:
		dano_extra += 0.25 * delta

	if radiacion > 75.0 and not en_refugio:
		dano_extra += 0.5 * delta

	if lluvia_particulas and en_exterior:
		dano_extra += 2.0 * delta

	dano_ambiental = clampf(dano_ambiental + dano_extra, 0.0, 100.0)

	# 5. Cálculo final de Salud
	var saciedad := 100.0 - hambre
	var descanso := 100.0 - sueno
	var salud_base := (saciedad + descanso) * 0.5
	salud = clampf(salud_base - dano_ambiental, 0.0, 100.0)

	_actualizar_alerta(oxigeno, radiacion, lluvia_particulas)
	_actualizar_barra_flotante()
	estado_actualizado.emit(self)

func comer(cantidad: float = 40.0, bonus_calidad: float = 0.0) -> void:
	hambre = maxf(0.0, hambre - cantidad)
	dano_ambiental = maxf(0.0, dano_ambiental - bonus_calidad)

func obtener_nombre() -> String:
	return NOMBRES.get(cabeza, "Astronauta")

func _actualizar_alerta(oxigeno: float, radiacion: float, lluvia: bool) -> void:
	if lluvia and en_exterior:
		estado_alerta = "¡Partículas!"
	elif oxigeno < 20.0:
		estado_alerta = "¡Sin O2!"
	elif radiacion > 75.0 and not en_refugio:
		estado_alerta = "¡Radiación!"
	elif hambre > 70.0:
		estado_alerta = "Hambre"
	elif sueno > 75.0:
		estado_alerta = "Sueño"
	else:
		estado_alerta = "Bien"

func _configurar_barra_flotante() -> void:
	if barra_salud == null:
		return
	var sb_fondo := StyleBoxFlat.new()
	sb_fondo.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	barra_salud.add_theme_stylebox_override("background", sb_fondo)

	_estilo_relleno = StyleBoxFlat.new()
	_estilo_relleno.bg_color = Color(0.2, 0.85, 0.35)
	barra_salud.add_theme_stylebox_override("fill", _estilo_relleno)

func _actualizar_barra_flotante() -> void:
	if barra_salud == null:
		return
	barra_salud.value = salud
	if _estilo_relleno != null:
		if salud > 60.0:
			_estilo_relleno.bg_color = Color(0.2, 0.85, 0.35)  # Verde
		elif salud > 30.0:
			_estilo_relleno.bg_color = Color(0.95, 0.75, 0.15) # Amarillo
		else:
			_estilo_relleno.bg_color = Color(0.9, 0.2, 0.2)    # Rojo

# --- API pública de animaciones (sin cambios) ---
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

func mirar(dir_x: float) -> void:
	if dir_x == 0.0:
		return
	for s in [sprite_cuerpo, sprite_brazo, sprite_cabeza, sprite_casco]:
		s.flip_h = dir_x < 0.0

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
	_reproducir(sprite_brazo, anim_brazo, sprite_cuerpo, forzar)

func _reproducir(sprite: AnimatedSprite2D, anim: StringName, referencia: AnimatedSprite2D, forzar: bool) -> void:
	if not forzar and sprite.animation == anim and sprite.is_playing():
		return
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
