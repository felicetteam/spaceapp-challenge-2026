extends RefCounted
## La tripulación que el jugador eligió en la pantalla de selección (Pantallas/Seleccion).
## base.gd la aplica a los tres astronautas del mapa al empezar. Vacía = se usan los que
## están puestos en la escena (por ejemplo, al probar la base directo desde el editor).
## Se usa con preload (no class_name), así comparten la misma lista las dos escenas.

## Valores de Personaje.Cabeza, en orden (el primero va en el lugar del primer astronauta).
static var cabezas: Array[int] = []
