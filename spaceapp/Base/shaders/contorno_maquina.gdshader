// Borde alrededor de un Sprite2D (las máquinas). El quad se agranda `grosor` píxeles de textura
// para que el contorno entre aunque el dibujo llegue al borde de la imagen.
shader_type canvas_item;

uniform vec4 color_borde : source_color = vec4(1.0, 0.85, 0.1, 1.0);
// Grosor en píxeles de la textura.
uniform float grosor = 1.0;
uniform bool activo = false;
// Titila (máquina crítica o rota).
uniform bool parpadeo = false;

varying vec4 color_vertice;

void vertex() {
	color_vertice = COLOR;
	if (activo) {
		vec2 tam = 1.0 / TEXTURE_PIXEL_SIZE;
		VERTEX += (UV * 2.0 - 1.0) * grosor;
		UV = (UV - 0.5) * (tam + 2.0 * grosor) / tam + 0.5;
	}
}

float alfa(sampler2D tex, vec2 uv) {
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	return texture(tex, uv).a;
}

void fragment() {
	vec4 tex = vec4(0.0);
	if (UV.x >= 0.0 && UV.y >= 0.0 && UV.x <= 1.0 && UV.y <= 1.0) {
		tex = texture(TEXTURE, UV);
	}
	vec4 c = tex * color_vertice;
	if (activo && tex.a < 0.5) {
		vec2 d = TEXTURE_PIXEL_SIZE * grosor;
		float a = max(max(alfa(TEXTURE, UV + vec2(d.x, 0.0)), alfa(TEXTURE, UV - vec2(d.x, 0.0))),
				max(alfa(TEXTURE, UV + vec2(0.0, d.y)), alfa(TEXTURE, UV - vec2(0.0, d.y))));
		if (a > 0.5) {
			float brillo = parpadeo ? 0.55 + 0.45 * sin(TIME * 6.0) : 1.0;
			c = vec4(color_borde.rgb, color_borde.a * brillo);
		}
	}
	COLOR = c;
}
