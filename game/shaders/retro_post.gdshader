shader_type canvas_item;
// Styl PSK-12: redukcja głębi kolorów z ditheringiem, ziarno filmowe, winieta.
// Nakładany na obraz świata wyrenderowany w niskiej rozdzielczości.

uniform bool enabled = true;
uniform float levels = 32.0;        // liczba poziomów na kanał koloru
uniform float dither_amount = 0.6;  // siła ditheringu (0..1)
uniform float grain = 0.1;          // siła ziarna
uniform float vignette = 0.35;      // przyciemnienie rogów

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x / 2.0 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (enabled) {
		// współrzędne w pikselach niskiej rozdzielczości
		vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
		// ziarno zmienia się 24 razy na sekundę, mocniejsze w cieniach
		float t = floor(TIME * 24.0);
		float n = hash(px + vec2(t * 17.0, t * 29.0)) - 0.5;
		float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		c.rgb += n * grain * (1.0 - lum * 0.6);
		// dithering uporządkowany, potem kwantyzacja
		c.rgb += (bayer4(px) - 0.5) * dither_amount / levels;
		c.rgb = floor(c.rgb * levels + 0.5) / levels;
		vec2 q = UV - 0.5;
		c.rgb *= 1.0 - vignette * dot(q, q) * 2.0;
	}
	COLOR = vec4(clamp(c.rgb, 0.0, 1.0), 1.0);
}
