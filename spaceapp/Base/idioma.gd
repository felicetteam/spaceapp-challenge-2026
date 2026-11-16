extends RefCounted
## Idioma del juego: español (el idioma en el que está escrito todo) o inglés.
##
## Las traducciones están en Idiomas/en.json: { "texto en español": "English text" }. Si un
## texto no está ahí, se ve en español (no se rompe nada). Para traducir uno nuevo, agregalo
## al archivo con el texto en español EXACTO como clave (con los mismos %s / %d).
##
## Cómo se aplica:
## - Los Label y Button traducen solos su texto si es exactamente una clave del archivo.
## - Los textos armados con % o con + pasan por Idioma.t("plantilla") antes de armarse.
## - Los datos (eventos, investigaciones) se traducen al cargarlos con traducir_datos().
## Se elige en el menú de inicio y queda guardado en user://idioma.cfg.

const RUTA_TRADUCCION := "res://Idiomas/en.json"
const RUTA_CONFIG := "user://idioma.cfg"
const IDIOMAS := ["es", "en"]
const NOMBRES := {"es": "Español", "en": "English"}

static var _idioma := "es"
static var _iniciado := false
static var _traduccion: Translation = null
static var _agregada := false


## Carga el idioma guardado (una sola vez por sesión).
static func iniciar() -> void:
	if _iniciado:
		return
	_iniciado = true
	var cfg := ConfigFile.new()
	var codigo := "es"
	if cfg.load(RUTA_CONFIG) == OK:
		codigo = String(cfg.get_value("juego", "idioma", "es"))
	aplicar(codigo, false)


static func actual() -> String:
	return _idioma


## Cambia el idioma de todo el juego (los textos en pantalla se actualizan solos).
static func aplicar(codigo: String, guardar := true) -> void:
	_iniciado = true
	if not IDIOMAS.has(codigo):
		codigo = "es"
	_idioma = codigo
	if codigo == "en":
		_cargar_traduccion()
		if _traduccion != null and not _agregada:
			TranslationServer.add_translation(_traduccion)
			_agregada = true
	elif _traduccion != null and _agregada:
		TranslationServer.remove_translation(_traduccion)
		_agregada = false
	TranslationServer.set_locale(codigo)
	if guardar:
		var cfg := ConfigFile.new()
		cfg.load(RUTA_CONFIG)
		cfg.set_value("juego", "idioma", codigo)
		cfg.save(RUTA_CONFIG)


## Traduce un texto (o una plantilla con %s / %d) al idioma actual.
static func t(texto: String) -> String:
	if _idioma == "es" or _traduccion == null:
		return texto
	var traducido := String(_traduccion.get_message(texto))
	return traducido if traducido != "" else texto


## Traduce, dentro de un diccionario o lista cargado de un JSON, los textos de esas claves.
static func traducir_datos(datos, claves: Array) -> void:
	if _idioma == "es":
		return
	if datos is Dictionary:
		for k in datos.keys():
			var v = datos[k]
			if claves.has(k) and v is String:
				datos[k] = t(v)
			elif claves.has(k) and v is Array:
				for i in v.size():
					if v[i] is String:
						v[i] = t(v[i])
					else:
						traducir_datos(v[i], claves)
			elif v is Dictionary or v is Array:
				traducir_datos(v, claves)
	elif datos is Array:
		for v in datos:
			traducir_datos(v, claves)


static func _cargar_traduccion() -> void:
	if _traduccion != null:
		return
	if not FileAccess.file_exists(RUTA_TRADUCCION):
		push_warning("No se encontró %s: el juego queda en español" % RUTA_TRADUCCION)
		return
	var datos = JSON.parse_string(FileAccess.get_file_as_string(RUTA_TRADUCCION))
	if not (datos is Dictionary):
		push_error("%s tiene un error de formato" % RUTA_TRADUCCION)
		return
	_traduccion = Translation.new()
	_traduccion.locale = "en"
	for k in datos:
		_traduccion.add_message(String(k), String(datos[k]))
