class_name Navegacion
extends Node
## Grilla de caminos para el point and click.
## Recorre el TileMapLayer en celdas chicas y prueba, con una consulta de física,
## si los pies del personaje entran en cada una. Así respeta las paredes finas,
## las diagonales y cualquier cuerpo con colisión (muebles, máquinas con forma).
##
## Reglas de validez:
## - Un camino nunca cruza un muro (la prueba de cada celda cubre el espacio hasta sus vecinas).
## - Si hay un muro entre el punto buscado y la celda elegida como destino, el destino no vale,
##   aunque esté muy cerca. No hay caminos "parciales" salvo que se pidan explícitamente.

signal lista

const SIN_CELDA := Vector2i(-99999, -99999)

## Tamaño de cada celda de la grilla, en píxeles (los tiles miden 16).
@export var tamano_celda := 8
## Holgura extra alrededor de los pies al probar si una celda es transitable.
@export var margen_pies := Vector2(1, 1)

var astar := AStarGrid2D.new()
var listo := false

var _espacio: PhysicsDirectSpaceState2D
var _mascara := 1
var _excluir: Array[RID] = []


## Arma la grilla. Llamar después de que el TileMapLayer haya creado sus colisiones
## (base.gd espera dos frames de física antes de llamarla).
func construir(tilemap: TileMapLayer, tamano_pies: Vector2, mascara: int, excluir: Array[RID]) -> void:
	_espacio = tilemap.get_world_2d().direct_space_state
	_mascara = mascara
	_excluir = excluir

	var usado := tilemap.get_used_rect()
	var tam_tile := Vector2(tilemap.tile_set.tile_size)
	var esquina := tilemap.to_global(Vector2(usado.position) * tam_tile)
	var tam_px := Vector2(usado.size) * tam_tile
	var cols := int(ceil(tam_px.x / tamano_celda))
	var filas := int(ceil(tam_px.y / tamano_celda))

	astar.region = Rect2i(0, 0, cols, filas)
	astar.cell_size = Vector2(tamano_celda, tamano_celda)
	astar.offset = esquina + astar.cell_size * 0.5
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()

	# La forma de prueba mide al menos una celda + 1 px en cada eje: así las formas de dos
	# celdas vecinas se tocan y una pared fina entre ellas siempre bloquea a alguna de las dos.
	# Sin esto, un muro de 2 px que cae justo entre dos centros de celda se podía atravesar.
	var forma := RectangleShape2D.new()
	forma.size = Vector2(
		maxf(tamano_pies.x + margen_pies.x * 2.0, tamano_celda + 1.0),
		maxf(tamano_pies.y + margen_pies.y * 2.0, tamano_celda + 1.0))
	var consulta := PhysicsShapeQueryParameters2D.new()
	consulta.shape = forma
	consulta.collide_with_bodies = true
	consulta.collide_with_areas = false
	consulta.collision_mask = mascara
	consulta.exclude = excluir

	for y in filas:
		for x in cols:
			var celda := Vector2i(x, y)
			consulta.transform = Transform2D(0.0, astar.get_point_position(celda))
			if not _espacio.intersect_shape(consulta, 1).is_empty():
				astar.set_point_solid(celda, true)

	listo = true
	lista.emit()


## Marca como intransitable todo lo que cae dentro de un rectángulo global (por ejemplo, una máquina).
func bloquear_rect(rect: Rect2) -> void:
	var a := celda_de(rect.position)
	var b := celda_de(rect.end)
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var c := Vector2i(x, y)
			if astar.is_in_boundsv(c) and rect.has_point(astar.get_point_position(c)):
				astar.set_point_solid(c, true)


func celda_de(pos: Vector2) -> Vector2i:
	return Vector2i(((pos - astar.offset) / astar.cell_size).round())


func posicion_de(celda: Vector2i) -> Vector2:
	return astar.get_point_position(celda)


func es_transitable(celda: Vector2i) -> bool:
	return astar.is_in_boundsv(celda) and not astar.is_point_solid(celda)


## true si no hay ningún muro (cuerpo con colisión, sin contar a los astronautas) entre a y b.
func hay_vista(a: Vector2, b: Vector2) -> bool:
	if _espacio == null or a.is_equal_approx(b):
		return true
	var rayo := PhysicsRayQueryParameters2D.create(a, b, _mascara, _excluir)
	rayo.collide_with_areas = false
	rayo.hit_from_inside = true
	return _espacio.intersect_ray(rayo).is_empty()


## La celda transitable más cercana a una posición (busca en anillos hasta radio_max celdas).
## Con requerir_vista, descarta las celdas que tienen un muro en el medio respecto de pos.
func celda_transitable_cercana(pos: Vector2, radio_max := 12, requerir_vista := true) -> Vector2i:
	var centro := celda_de(pos)
	if es_transitable(centro) and (not requerir_vista or hay_vista(pos, posicion_de(centro))):
		return centro
	for r in range(1, radio_max + 1):
		var candidatas: Array[Vector2i] = []
		for y in range(centro.y - r, centro.y + r + 1):
			for x in range(centro.x - r, centro.x + r + 1):
				if absi(x - centro.x) != r and absi(y - centro.y) != r:
					continue  # solo el borde del anillo
				var c := Vector2i(x, y)
				if es_transitable(c):
					candidatas.append(c)
		candidatas.sort_custom(func(a, b): return pos.distance_squared_to(posicion_de(a)) < pos.distance_squared_to(posicion_de(b)))
		for c in candidatas:
			if not requerir_vista or hay_vista(pos, posicion_de(c)):
				return c
	return SIN_CELDA


## Camino en posiciones globales (centros de celda) desde/hasta posiciones de pies.
## Devuelve vacío si el destino no es válido o no se puede alcanzar.
## Con permitir_parcial llega lo más cerca posible en lugar de fallar (no se usa por defecto).
func camino(desde: Vector2, hasta: Vector2, permitir_parcial := false) -> PackedVector2Array:
	var vacio := PackedVector2Array()
	if not listo:
		return vacio
	var a := celda_transitable_cercana(desde)
	var b := celda_transitable_cercana(hasta)
	if a == SIN_CELDA or b == SIN_CELDA:
		return vacio
	if a == b:
		return PackedVector2Array([posicion_de(b)])
	var puntos := astar.get_point_path(a, b, permitir_parcial)
	# El primer punto es la celda donde ya está parado: se saltea si está muy cerca.
	if puntos.size() > 1 and desde.distance_to(puntos[0]) < tamano_celda * 0.75:
		puntos.remove_at(0)
	return puntos


## Igual que camino(), pero tratando como obstáculo un círculo alrededor de cada punto de `evitar`
## (por ejemplo, la posición de otro astronauta que no se va a mover).
func camino_evitando(desde: Vector2, hasta: Vector2, evitar: Array[Vector2], radio := 10.0) -> PackedVector2Array:
	var marcadas := _bloquear_temporal(evitar, radio, desde)
	var c := camino(desde, hasta)
	_desbloquear(marcadas)
	return c


## Busca un lugar cercano donde correrse para dejar pasar a otro astronauta.
## El lugar queda a `separacion` px o más del camino que le queda al otro y de su posición,
## y se llega sin atravesarlo. Devuelve el camino hasta ese lugar (vacío si no hay).
func camino_para_ceder(desde: Vector2, pos_otro: Vector2, camino_otro: PackedVector2Array,
		radio_busqueda := 48.0, separacion := 16.0) -> PackedVector2Array:
	var vacio := PackedVector2Array()
	if not listo:
		return vacio
	var origen := celda_transitable_cercana(desde, 4, false)
	if origen == SIN_CELDA:
		return vacio

	# Solo importa el tramo del camino del otro que pasa cerca
	var tramo: Array[Vector2] = [pos_otro]
	for p in camino_otro:
		if p.distance_to(desde) <= radio_busqueda + separacion:
			tramo.append(p)

	var candidatas: Array[Vector2i] = []
	var r := int(ceil(radio_busqueda / tamano_celda))
	for y in range(origen.y - r, origen.y + r + 1):
		for x in range(origen.x - r, origen.x + r + 1):
			var c := Vector2i(x, y)
			if not es_transitable(c):
				continue
			var p := posicion_de(c)
			if p.distance_to(desde) > radio_busqueda:
				continue
			var lejos := true
			for q in tramo:
				if p.distance_to(q) < separacion:
					lejos = false
					break
			if lejos:
				candidatas.append(c)
	candidatas.sort_custom(func(a, b): return desde.distance_squared_to(posicion_de(a)) < desde.distance_squared_to(posicion_de(b)))

	var evitar: Array[Vector2] = [pos_otro]
	var marcadas := _bloquear_temporal(evitar, 10.0, desde)
	var resultado := vacio
	for c in candidatas.slice(0, 12):
		var puntos := astar.get_point_path(origen, c, false)
		if not puntos.is_empty():
			resultado = puntos
			break
	_desbloquear(marcadas)
	return resultado


## Un punto transitable al azar a una distancia entre d_min y d_max de `desde`, al que se
## puede llegar caminando (por ejemplo, para pasear). Vector2.INF si no encuentra ninguno.
func punto_aleatorio(desde: Vector2, d_min: float, d_max: float, intentos := 16) -> Vector2:
	if not listo:
		return Vector2.INF
	var origen := celda_transitable_cercana(desde, 4)
	if origen == SIN_CELDA:
		return Vector2.INF
	for i in intentos:
		var p := desde + Vector2.from_angle(randf() * TAU) * randf_range(d_min, d_max)
		var c := celda_de(p)
		if not es_transitable(c) or c == origen:
			continue
		if not astar.get_id_path(origen, c, false).is_empty():
			return posicion_de(c)
	return Vector2.INF


## Celdas transitables alrededor de un rectángulo global: dentro de rect.grow(margen_max)
## pero fuera de rect.grow(margen_min), y sin un muro entre el centro del rectángulo y la celda.
func puntos_alrededor(rect: Rect2, margen_min: float, margen_max: float) -> Array[Vector2]:
	var resultado: Array[Vector2] = []
	var externo := rect.grow(margen_max)
	var interno := rect.grow(margen_min)
	var centro := rect.get_center()
	var a := celda_de(externo.position)
	var b := celda_de(externo.end)
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var c := Vector2i(x, y)
			if not es_transitable(c):
				continue
			var p := posicion_de(c)
			if externo.has_point(p) and not interno.has_point(p) and hay_vista(centro, p):
				resultado.append(p)
	return resultado


# --- Interno -----------------------------------------------------------------

## Marca celdas como sólidas por un momento. Nunca bloquea las celdas pegadas a `proteger`
## (donde está parado el que busca el camino), para que siempre pueda arrancar.
func _bloquear_temporal(puntos: Array[Vector2], radio: float, proteger: Vector2) -> Array[Vector2i]:
	var marcadas: Array[Vector2i] = []
	var r := int(ceil(radio / tamano_celda))
	for pos in puntos:
		var centro := celda_de(pos)
		for y in range(centro.y - r, centro.y + r + 1):
			for x in range(centro.x - r, centro.x + r + 1):
				var c := Vector2i(x, y)
				var p := posicion_de(c)
				if es_transitable(c) and p.distance_to(pos) <= radio and p.distance_to(proteger) >= tamano_celda:
					astar.set_point_solid(c, true)
					marcadas.append(c)
	return marcadas


func _desbloquear(marcadas: Array[Vector2i]) -> void:
	for c in marcadas:
		astar.set_point_solid(c, false)
