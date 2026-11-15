shader_type canvas_item;
// Styl PSK-12 (build 4.2): obraz jak z PS1. Kolor 15-bitowy (32 poziomy na kanał)
// z nieruchomym ditheringiem Bayera 4x4, jak robiła to konsola; delikatna winieta.
// Bez ziarna i bez niczego, co zmienia się w czasie: piksele stoją w miejscu,
// a ruch obrazu biorą na siebie drgające wierzchołki (psx.gd).

uniform bool enabled = true;
uniform float levels = 32.0;        // liczba poziomów na kanał koloru
uniform float dither_amount = 0.6;  // siła ditheringu (0..1)
uniform float vignette = 0.25;      // przyciemnienie rogów
uniform float hurt = 0.0;           // utrata krwi: obraz ciemnieje i traci kolor
uniform float pain = 0.0;           // ból: czerwonawa winieta

// macierz Bayera 4x4 z PS1 (wartości -4..3)
const float PSX_DITHER[16] = float[16](
	-4.0, 0.0, -3.0, 1.0,
	2.0, -2.0, 3.0, -1.0,
	-3.0, 1.0, -4.0, 0.0,
	3.0, -1.0, 2.0, -2.0
);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (enabled) {
		ivec2 px = ivec2(floor(UV / TEXTURE_PIXEL_SIZE));
		float d = PSX_DITHER[(px.y % 4) * 4 + (px.x % 4)] / 8.0;
		c.rgb += d * dither_amount / levels;
		c.rgb = floor(c.rgb * levels + 0.5) / levels;
		vec2 q = UV - 0.5;
		c.rgb *= 1.0 - vignette * dot(q, q) * 2.0;
	}
	// stan zdrowia działa w każdym stylu
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(c.rgb, vec3(g), hurt * 0.8);
	vec2 v = UV - 0.5;
	float edge = dot(v, v) * 2.0;
	c.rgb *= 1.0 - hurt * (0.35 + edge * 0.9);
	c.rgb = mix(c.rgb, c.rgb * vec3(1.0, 0.55, 0.5), clamp(pain - 0.3, 0.0, 1.0) * edge * 1.2);
	COLOR = vec4(clamp(c.rgb, 0.0, 1.0), 1.0);
}
