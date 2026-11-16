extends RefCounted
## Charlas entre astronautas: cuando dos se cruzan en el camino, uno le cuenta al otro un dato
## curioso de Marte y, unos segundos después, el otro le responde asombrado.
## Las charlas también quedan en el historial del HUD (los últimos 10 mensajes).
## Agregá o cambiá frases acá (y su traducción en Idiomas/en.json).

const Idioma := preload("res://Base/idioma.gd")

## Segundos mínimos entre una charla y la siguiente (para que no hablen en cada cruce).
const ESPERA_ENTRE_CHARLAS := 25.0
## Cuánto tarda en responder el otro y cuánto se ve cada globo.
const DEMORA_RESPUESTA := 3.0
const DURACION_DATO := 6.0
const DURACION_RESPUESTA := 3.0

const DATOS := [
	"¿Sabías que Marte tiene como la mitad del tamaño de la Tierra?",
	"¿Sabías que Marte tiene los volcanes más grandes del sistema solar? Aunque seguramente ya están todos extintos.",
	"Encontrar señales de que hubo agua en Marte es interesante porque significa que hace mucho tiempo el planeta podría haber tenido vida.",
	"A los científicos les encanta buscar agua en Marte.",
	"¿Sabías que en Marte un día dura 24:39 horas terrestres?",
	"¿Sabías que un mensaje puede tardar hasta 24 minutos en viajar entre Marte y la Tierra? A veces, el Sol queda entre Marte y la Tierra y tenemos que dejar de enviar mensajes durante unos días.",
	"¿Sabías que la NASA tiene antenas gigantes en Australia, España y California para comunicarse con las naves espaciales?",
	"¿Sabías que el escudo de radiación tiene agua dentro? El agua nos protege.",
	"No podemos respirar el aire de Marte, casi todo es dióxido de carbono.",
	"La NASA creó un experimento llamado MOXIE que logró fabricar oxígeno usando el aire de Marte.",
	"¡En Marte la gravedad es mucho más débil que en la Tierra! Pesamos menos y podemos saltar más alto.",
	"¡Brrr! En algunas noches de Marte la temperatura puede bajar hasta unos -90 °C.",
	"Perseverance recolectó muestras de rocas marcianas y también grabó sonidos del planeta.",
	"¿Sabías que un año marciano dura 687 días terrestres?",
	"Marte tiene dos lunas: una se llama Fobos y la otra Deimos.",
	"¿Sabías que Marte tiene el volcán más grande de todo el sistema solar? ¡Se llama Olympus Mons!",
	"Aunque hoy Marte es muy seco, todavía tiene agua congelada bajo la superficie y en sus regiones polares.",
	"En Marte existen pequeños torbellinos de polvo llamados diablos de polvo.",
	"En Marte, el cielo puede verse rojizo y lleno de polvo.",
	"¡Marte también tiene primavera, verano, otoño e invierno! Pero como su año es más largo, sus estaciones también duran más.",
	"¡El robot Curiosity puede disparar un láser contra rocas que están a varios metros! Así estudia de qué están hechas sin acercarse.",
]

const RESPUESTAS := [
	"¡Wow!",
	"¡No sabía eso!",
	"¡Increíble!",
	"¡Qué interesante!",
	"¿En serio? ¡Asombroso!",
	"¡Uau, no tenía idea!",
	"¡Eso es genial!",
	"¡Mirá vos!",
	"¡Impresionante!",
	"¡Qué loco!",
	"¡Me encanta Marte!",
	"¡Tengo que anotarlo en el diario!",
]

## Datos que todavía no salieron (se reparten sin repetir hasta usarlos todos).
static var _bolsa: Array[int] = []
static var _ultima_ms := -1000000


## true si ya pasó el tiempo de espera desde la última charla (y la marca como empezada).
static func puede_charlar() -> bool:
	var ahora := Time.get_ticks_msec()
	if ahora - _ultima_ms < int(ESPERA_ENTRE_CHARLAS * 1000.0):
		return false
	_ultima_ms = ahora
	return true


static func dato_al_azar() -> String:
	if _bolsa.is_empty():
		for i in DATOS.size():
			_bolsa.append(i)
		_bolsa.shuffle()
	return Idioma.t(DATOS[_bolsa.pop_back()])


static func respuesta_al_azar() -> String:
	return Idioma.t(RESPUESTAS.pick_random())
