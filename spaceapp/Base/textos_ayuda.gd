extends RefCounted
## Textos de ayuda: los usa el tutorial y la ventana de Información (Base > Máquinas y
## Base > Mecánicas). Cambiá un texto acá y cambia en los dos lados.

## Máquinas y muebles: clave -> [nombre, descripción]. La clave es el tipo de máquina
## (tipo_ajuste) o el del mueble ("comedor", "cama", "cama_hospital", "roomba").
const MAQUINAS := {
	"fotovoltaica": ["Paneles solares",
		"Juntan la luz del Sol y la convierten en energía. Rinden mucho a la mañana, menos a la tarde y nada de noche. Si se gastan, generan menos: ¡mantenelos sanos para tener energía para la noche!"],
	"comunicaciones": ["Comunicaciones",
		"La antena conecta la base con la Tierra. Mientras funciona, ves los recursos, los desgastes y las alertas. Si se rompe, aparece un ! rojo encima y te quedás a ciegas: arreglala primero."],
	"o2": ["Máquina de oxígeno",
		"Fabrica el aire que respira la tripulación. Necesita energía. Si está gastada (borde amarillo o rojo) no da abasto y el oxígeno baja de a poco; si se rompe, el oxígeno se acaba."],
	"invernadero": ["Invernadero",
		"Acá crecen las plantas. Cuanto mejor esté, más comida da cada visita al comedor."],
	"escudo": ["Escudo de radiación",
		"Protege la base de la radiación del Sol. Sano (sin borde o en amarillo) hace bajar la radiación; en rojo solo evita que aumente; si se rompe, la radiación empieza a filtrarse."],
	"rover": ["Rover",
		"El vehículo para explorar Marte. Un astronauta se sube y sale a investigar lugares nuevos. Cada salida lo gasta un poco."],
	"escritorio": ["Escritorio de investigación",
		"Acá se investiga, sentado en la silla. Primero hay que explorar con el rover: cada exploración desbloquea una investigación en el diario. Si hay varias, se investiga primero la más vieja."],
	"comedor": ["Comedor",
		"Acá come la tripulación. Cuanto mejor está el invernadero, más llena cada comida. Si comen hasta llenar la comida quedan Satisfechos."],
	"cama": ["Cama",
		"Para dormir y recuperar energía. Si duermen hasta llenar la energía quedan Descansados. Cuando todos duermen de noche, el tiempo pasa más rápido."],
	"cama_hospital": ["Cama de hospital",
		"Si un astronauta queda inconsciente, la roomba lo trae acá para que se recupere."],
	"roomba": ["Roomba",
		"El robot ayudante: lleva a la cama a los astronautas que quedan inconscientes."],
	"otras": ["Máquina",
		"Las máquinas se gastan con el tiempo (más rápido con radiación alta). Mandá a un astronauta a repararlas antes de que se rompan."],
}

## Mecánicas, en el orden en que se muestran: id, título, texto y (opcional) el mueble o la
## máquina cuyo dibujo las acompaña.
const MECANICAS := [
	{"id": "tripulacion", "titulo": "Tu tripulación",
		"texto": "Cada tarjeta muestra la salud, la comida y la energía de un astronauta. Si la comida o la energía llegan a cero, la salud baja. Llevalos al comedor a comer y a las camas a dormir."},
	{"id": "hambre", "titulo": "Hambre", "icono": "comedor",
		"texto": "La manzana sobre la cabeza avisa que un astronauta necesita comer: elegilo y hacé clic en el comedor. Si la comida llega a cero, pierde salud."},
	{"id": "sueno", "titulo": "Sueño", "icono": "cama",
		"texto": "El \"Zz\" sobre la cabeza avisa que necesita dormir: elegilo y hacé clic en una cama. Si la energía llega a cero, se duerme donde esté y la roomba lo lleva a su cama."},
	{"id": "bonos", "titulo": "Bonos de salud",
		"texto": "Cuidarlos bien tiene premio. Si comen hasta llenar la comida quedan Satisfechos: no les da hambre durante un minuto. Si duermen hasta llenar la energía quedan Descansados: no se cansan durante un minuto. Con los dos a la vez están Felices y además trabajan un 10% más rápido."},
	{"id": "reparar", "titulo": "Reparar máquinas", "icono": "o2",
		"texto": "Las máquinas se gastan: con borde amarillo necesitan ayuda y en rojo están por romperse. Elegí un astronauta y hacé clic en la máquina: camina hasta ella y la repara."},
	{"id": "equipo", "titulo": "Trabajo en equipo",
		"texto": "Si mandás a dos o más astronautas a reparar la misma máquina, trabajan en equipo: cada uno extra suma un 50% de velocidad y verás \"¡Trabajo en Equipo!\" en su estado. Ideal para salvar una máquina que está por romperse."},
	{"id": "rec_energia", "titulo": "Recurso: Energía", "icono": "fotovoltaica",
		"texto": "La barra amarilla. La generan los paneles solares de día y la usan todas las máquinas. Sin energía, las máquinas se apagan."},
	{"id": "rec_oxigeno", "titulo": "Recurso: Oxígeno", "icono": "o2",
		"texto": "La barra celeste. Lo fabrica la máquina de oxígeno, que necesita energía. Con poco oxígeno la tripulación se cansa mucho más rápido y, muy bajo, pierde salud."},
	{"id": "rec_radiacion", "titulo": "Recurso: Radiación", "icono": "escudo",
		"texto": "La barra violeta. Viene del Sol y sube sola. Gasta las máquinas más rápido y, arriba de 80%, daña a la tripulación. El escudo de radiación la mantiene baja."},
	{"id": "exploracion", "titulo": "Exploraciones", "icono": "rover",
		"texto": "Un astronauta se sube al rover y sale a investigar un lugar nuevo de Marte. Mientras explora no está en la base. La exploración espera en el botón de abajo a la derecha: elegí quién sale (al menos 60% de salud y energía suficiente, porque vuelve cansado). Al volver, su investigación aparece en el diario y enseguida hay una exploración nueva."},
	{"id": "investigacion", "titulo": "Investigación", "icono": "escritorio",
		"texto": "Cada exploración desbloquea una investigación en el diario. Se completa trabajando en el escritorio; si hay varias desbloqueadas, se investiga primero la más vieja. Miralas en Información > Diario."},
	{"id": "eventos", "titulo": "Eventos críticos",
		"texto": "Cada tanto pasa algo grave (tormentas, fallas) y tenés que decidir qué hacer. Algunos duran un rato, otros piden trabajar en una estructura y otros se solucionan recién cuando reparás la máquina hasta verde. Hasta que termina uno, no sale el siguiente."},
	{"id": "camara", "titulo": "Cámara y controles",
		"texto": "Rueda del mouse (o la barra de la derecha) para acercar y alejar; clic y arrastrar para mover el mapa. Teclas 1, 2 y 3 o su tarjeta para elegir astronauta. Abajo a la izquierda, pausa y play: en pausa podés seguir dando órdenes."},
	{"id": "victoria", "titulo": "Ganar y perder",
		"texto": "Ganás cuando completás las investigaciones de la misión y respondés sus reportes (si falta alguno, abajo a la derecha aparece \"Reporte pendiente\"). Las investigaciones de las partidas ganadas quedan en el diario global (Ver Diario, en el menú). Perdés si los tres astronautas quedan inconscientes por falta de salud al mismo tiempo."},
	{"id": "noche", "titulo": "Día y noche",
		"texto": "De noche los paneles no generan energía. Cuando todos los que están en la base duermen, el tiempo pasa al triple hasta que alguien se despierta o amanece."},
]


## Astronautas (Información > Base > Astronautas), en el orden en que se muestran. "nombre" es
## el de Personaje.NOMBRES; sus bonos y penalidades salen de Personaje/afinidades.gd.
const ASTRONAUTAS := [
	{"nombre": "Juan", "titulo": "Juan – El astronauta argentino",
		"texto": "¡Argentina también tuvo un astronauta muy especial! El 23 de diciembre de 1969, un mono capuchino llamado Juan viajó en un cohete desde Chamical, La Rioja. Su aventura duró unos ocho minutos y llegó aproximadamente a los 90 kilómetros de altura. ¡Y lo mejor es que regresó sano y salvo!",
		"dato": "Después de su viaje, Juan vivió durante más de dos años en el zoológico de Córdoba.",
		"fuente": "Diario Uno (diariouno.com.ar, nota «Hace 50 años»)"},
	{"nombre": "Laika", "titulo": "Laika – La pionera del espacio",
		"texto": "¡Laika hizo historia! El 3 de noviembre de 1957 viajó a bordo del Sputnik 2 y se convirtió en el primer animal en orbitar la Tierra. Aunque antes otros animales ya habían realizado viajes espaciales más cortos, ella fue la primera en dar una vuelta alrededor de nuestro planeta.",
		"dato": "Antes de Laika, en 1947, unas moscas de la fruta viajaron al espacio.",
		"fuente": "NASA History, «60 Years Ago: The First Animal in Orbit» (nasa.gov/history/60-years-ago-the-first-animal-in-orbit/)"},
	{"nombre": "Feli", "titulo": "Félicette – La gata astronauta",
		"texto": "¡Una gata también llegó al espacio! Félicette era una gata de las calles de París que participó en una misión espacial francesa el 18 de octubre de 1963. Su cápsula descendió en paracaídas y ella regresó sana y salva. Hasta hoy, es la única gata que ha viajado al espacio y vuelto con vida.",
		"dato": "Su viaje fue suborbital, es decir, llegó al espacio, pero no dio una vuelta completa alrededor de la Tierra.",
		"fuente": "Guinness World Records (guinnessworldrecords.com/world-records/779823-first-cat-in-space)"},
	{"nombre": "Andy", "titulo": "Andy – El astronauta misterioso",
		"texto": "Nadie sabe muy bien de dónde vino Andy. Es un astronauta misterioso de desempeño promedio: no se destaca en nada, pero tampoco tiene puntos débiles. Siempre cumple."},
]

## Texto de una mecánica por su id ("" si no existe).
static func texto(id: String) -> String:
	for m in MECANICAS:
		if m["id"] == id:
			return m["texto"]
	return ""
