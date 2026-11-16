extends RefCounted
## Música de las pantallas (menú de inicio y selección de tripulación): la lista
## assets/musica/menus_playlist.tres (temas mezclados, uno detrás de otro).
## El reproductor vive en la raíz del árbol (no en la escena), así que sigue sonando sin
## cortarse al pasar de una pantalla a la otra. Al entrar al juego se detiene: ahí suena
## la lista del juego (assets/musica/juego_playlist.tres, en el AudioStreamPlayer de base.tscn).

const RUTA_MUSICA := "res://assets/musica/menus_playlist.tres"
## Todo lo que se precarga al abrir el menú (las dos listas con todos sus temas). Quedan en
## memoria toda la partida, así no se cargan del disco justo cuando tienen que sonar.
const RUTAS_PRECARGA := [
	"res://assets/musica/menus_playlist.tres",
	"res://assets/musica/juego_playlist.tres",
]
static var _precargadas := {}  # ruta -> recurso (mientras esté acá, no se descarga)
const NOMBRE := "MusicaMenu"
const VOLUMEN_DB := -6.0


## Carga una vez las listas de música y sus temas, y las deja en memoria.
static func precargar() -> void:
	for ruta in RUTAS_PRECARGA:
		if _precargadas.has(ruta) or not ResourceLoader.exists(ruta):
			continue
		var recurso := load(ruta)
		_precargadas[ruta] = recurso
		# Los temas de la lista también: se guardan uno por uno
		if recurso is AudioStreamPlaylist:
			for i in recurso.stream_count:
				var tema: AudioStream = recurso.get_list_stream(i)
				if tema != null:
					_precargadas["%s#%d" % [ruta, i]] = tema


## Empieza la música si no está sonando (si ya suena, sigue desde donde iba).
static func sonar(arbol: SceneTree) -> void:
	precargar()
	var raiz := arbol.root
	var reproductor := raiz.get_node_or_null(NOMBRE) as AudioStreamPlayer
	if reproductor != null:
		if not reproductor.playing:
			reproductor.play()
		return
	if not ResourceLoader.exists(RUTA_MUSICA):
		push_warning("No se encontró la música de los menús: %s" % RUTA_MUSICA)
		return
	reproductor = AudioStreamPlayer.new()
	reproductor.name = NOMBRE
	reproductor.stream = _precargadas.get(RUTA_MUSICA, load(RUTA_MUSICA))
	reproductor.volume_db = VOLUMEN_DB
	reproductor.process_mode = Node.PROCESS_MODE_ALWAYS
	# Si la lista termina (por ejemplo, sin loop), vuelve a empezar
	reproductor.finished.connect(reproductor.play)
	raiz.add_child.call_deferred(reproductor)
	reproductor.play.call_deferred()


## Corta la música (al empezar la partida).
static func detener(arbol: SceneTree) -> void:
	var reproductor := arbol.root.get_node_or_null(NOMBRE)
	if reproductor != null:
		reproductor.queue_free()
