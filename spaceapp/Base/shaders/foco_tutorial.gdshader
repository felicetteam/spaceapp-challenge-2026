shader_type canvas_item;
// Oscurece toda la pantalla menos un rectángulo (la zona que indica el tutorial).
// zona: x, y, ancho, alto en UV (0..1) del ColorRect que cubre la pantalla.
uniform vec4 zona = vec4(0.0);
uniform vec2 tam_pantalla = vec2(1280.0, 720.0);
uniform float oscuridad : hint_range(0.0, 1.0) = 0.65;
uniform vec4 color_borde : source_color = vec4(0.35, 0.85, 1.0, 1.0);
uniform float grosor_borde = 2.0;

void fragment() {
	vec2 p = UV * tam_pantalla;
	vec2 a = zona.xy * tam_pantalla;
	vec2 b = (zona.xy + zona.zw) * tam_pantalla;
	bool dentro = p.x >= a.x && p.y >= a.y && p.x <= b.x && p.y <= b.y;
	if (dentro) {
		float d = min(min(p.x - a.x, b.x - p.x), min(p.y - a.y, b.y - p.y));
		COLOR = d < grosor_borde ? color_borde : vec4(0.0);
	} else {
		COLOR = vec4(0.0, 0.0, 0.0, oscuridad);
	}
}
