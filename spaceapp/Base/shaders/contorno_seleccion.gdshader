// Borde alrededor de un grupo de sprites (va en un CanvasGroup).
// Se usa para marcar al astronauta seleccionado: dibuja la silueta completa del personaje
// (cuerpo, brazos, casco y cabeza juntos) con un contorno de color.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec4 color_borde : source_color = vec4(0.25, 1.0, 0.35, 1.0);
// Grosor en píxeles de pantalla (el personaje lo ajusta según el zoom).
uniform float grosor = 2.0;

void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);
	if (c.a > 0.0001) {
		c.rgb /= c.a;
	}
	if (c.a < 0.5) {
		vec2 d = SCREEN_PIXEL_SIZE * grosor;
		float a = 0.0;
		a = max(a, textureLod(screen_texture, SCREEN_UV + vec2(d.x, 0.0), 0.0).a);
		a = max(a, textureLod(screen_texture, SCREEN_UV - vec2(d.x, 0.0), 0.0).a);
		a = max(a, textureLod(screen_texture, SCREEN_UV + vec2(0.0, d.y), 0.0).a);
		a = max(a, textureLod(screen_texture, SCREEN_UV - vec2(0.0, d.y), 0.0).a);
		if (a > 0.5) {
			c = color_borde;
		}
	}
	COLOR = c;
}
