extends RefCounted
## Pracownia: biblioteka materiałów i shader zużycia.
##
## Każdy moduł dostaje własny materiał (ShaderMaterial), bo zużycie ustawia się osobno:
## przetarcia na krawędziach (kolor wierzchołka R = wypukłość), brud w zagłębieniach
## (G = wklęsłość), rdza, rysy, odcień. Tekstury bazowe są generowane kodem (128 px,
## bez UV: rzut z trzech stron jak w reszcie gry). Shader ma też drgania wierzchołków PS1
## (te same globalne parametry co psx.gd), więc model z Pracowni wygląda w grze spójnie.

const Psx := preload("res://scripts/psx.gd")
const SIZE := 128

## nazwa -> [etykieta, kolor przetarcia, kolor brudu, szorstkość, metaliczność, skala tekstury]
const LIBRARY := {
	"stal": ["Stal oksydowana", Color(0.52, 0.53, 0.55), Color(0.06, 0.05, 0.04), 0.45, 0.6, 7.0],
	"stal_jasna": ["Stal jasna", Color(0.7, 0.7, 0.72), Color(0.08, 0.07, 0.06), 0.4, 0.7, 7.0],
	"stal_grawer": ["Stal grawerowana", Color(0.75, 0.75, 0.76), Color(0.06, 0.05, 0.04), 0.4, 0.7, 7.0],
	"parkeryzowana": ["Stal parkeryzowana", Color(0.48, 0.5, 0.48), Color(0.07, 0.07, 0.05), 0.75, 0.35, 7.0],
	"chrom": ["Chrom", Color(0.85, 0.85, 0.88), Color(0.1, 0.09, 0.08), 0.2, 0.9, 6.0],
	"rdza": ["Rdza", Color(0.45, 0.25, 0.12), Color(0.08, 0.04, 0.02), 0.9, 0.2, 6.0],
	"polimer": ["Polimer czarny", Color(0.25, 0.25, 0.25), Color(0.05, 0.05, 0.05), 0.7, 0.0, 9.0],
	"farba_zielona": ["Farba wojskowa", Color(0.45, 0.45, 0.45), Color(0.08, 0.07, 0.04), 0.75, 0.0, 6.0],
	"drewno": ["Drewno: orzech", Color(0.55, 0.36, 0.2), Color(0.1, 0.06, 0.03), 0.6, 0.0, 7.0],
	"drewno_jasne": ["Drewno: buk", Color(0.75, 0.6, 0.42), Color(0.15, 0.1, 0.05), 0.65, 0.0, 7.0],
	"drewno_ciemne": ["Drewno: ciemne", Color(0.4, 0.25, 0.13), Color(0.05, 0.03, 0.02), 0.55, 0.0, 7.0],
	"bakelit": ["Bakelit", Color(0.3, 0.17, 0.1), Color(0.05, 0.03, 0.02), 0.55, 0.0, 9.0],
	"guma": ["Guma", Color(0.18, 0.18, 0.18), Color(0.03, 0.03, 0.03), 0.9, 0.0, 9.0],
	"skora": ["Skóra", Color(0.5, 0.35, 0.22), Color(0.08, 0.05, 0.03), 0.7, 0.0, 6.0],
	"tkanina": ["Tkanina", Color(0.45, 0.42, 0.35), Color(0.1, 0.08, 0.05), 0.95, 0.0, 10.0],
	"mosiadz": ["Mosiądz", Color(0.9, 0.78, 0.45), Color(0.15, 0.1, 0.03), 0.35, 0.85, 7.0],
	"miedz": ["Miedź", Color(0.9, 0.6, 0.45), Color(0.1, 0.12, 0.08), 0.35, 0.85, 7.0],
	"plastik_czerwony": ["Plastik czerwony", Color(0.75, 0.25, 0.2), Color(0.1, 0.03, 0.02), 0.6, 0.0, 9.0],
	"skora_dloni": ["Skóra dłoni", Color(0.7, 0.55, 0.45), Color(0.3, 0.2, 0.15), 0.7, 0.0, 9.0],
}

## Zużycie domyślne (każdy moduł może je nadpisać w polu "wear").
const DEFAULT_WEAR := {"tint": [1.0, 1.0, 1.0], "zuzycie": 0.35, "brud": 0.35, "rdza": 0.0, "rysy": 0.3, "skala": 1.0, "polysk": 0.0}

const SHADER := """
shader_type spatial;
render_mode diffuse_lambert, cull_back;
global uniform float psx_snap;
global uniform float psx_affine;
uniform sampler2D base_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint = vec3(1.0);
uniform vec3 worn_color = vec3(0.5);
uniform vec3 grime_color = vec3(0.05);
uniform vec3 rust_color = vec3(0.4, 0.18, 0.07);
uniform float tex_scale = 7.0;
uniform float wear = 0.35;
uniform float grime = 0.35;
uniform float rust = 0.0;
uniform float scratches = 0.3;
uniform float rough = 0.5;
uniform float metal = 0.5;
uniform float gloss = 0.0;
uniform float seed = 0.0;
uniform float highlight = 0.0;
varying vec3 lp;
varying vec3 ln;
varying vec4 vc;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	if (psx_snap > 0.0 && clip.w > 0.0) {
		vec2 grid = VIEWPORT_SIZE * 0.5 / psx_snap;
		clip.xy = round(clip.xy / clip.w * grid) / grid * clip.w;
	}
	POSITION = clip;
	lp = VERTEX;
	ln = NORMAL;
	vc = COLOR;
}

vec2 tri_uv(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.x >= a.y && a.x >= a.z) { return p.zy; }
	if (a.y >= a.z) { return p.xz; }
	return p.xy;
}

void fragment() {
	vec3 n = normalize(ln);
	vec2 uv = tri_uv(lp * tex_scale, n);
	vec3 col = texture(base_tex, uv).rgb * tint;
	vec2 nuv = tri_uv(lp * 3.1 + vec3(seed), n);
	float n1 = texture(noise_tex, nuv).r;
	float n2 = texture(noise_tex, nuv * 2.7 + 0.31).r;
	float n3 = texture(noise_tex, nuv * 0.6 + 0.77).r;
	// przetarcia: krawędzie wypukłe, poszarpane szumem
	float edge = clamp(vc.r * (0.4 + 0.8 * n1), 0.0, 1.0);
	float wm = smoothstep(1.0 - wear * 0.85, 1.0 - wear * 0.85 + 0.22, edge) * 0.85;
	col = mix(col, worn_color * (0.75 + 0.35 * n2), wm);
	// rysy: wydłużony szum wzdłuż osi broni
	float s = texture(noise_tex, vec2(lp.x * 2.0, (lp.y + lp.z) * 45.0) + vec2(seed)).r;
	float sm = step(1.0 - 0.07 * scratches, s) * scratches;
	col = mix(col, worn_color, sm * 0.7);
	// brud: zagłębienia i plamy
	float gm = clamp((vc.g * 1.6 + (1.0 - n2) * 0.35) * grime * (0.6 + 0.8 * n3), 0.0, 1.0);
	col = mix(col, grime_color, gm * 0.85);
	// rdza: plamy, chętniej w zagłębieniach
	float rm = smoothstep(1.0 - rust, 1.0 - rust + 0.25, n3 * 0.8 + vc.g * 0.4 + n1 * 0.2) * step(0.001, rust);
	col = mix(col, rust_color * (0.7 + 0.5 * n1), rm);
	col = mix(col, vec3(1.0, 0.8, 0.25), highlight * 0.35);
	ALBEDO = col;
	ROUGHNESS = clamp(mix(rough - gloss * 0.3, 0.95, max(rm, gm * 0.5)) - wm * 0.15, 0.05, 1.0);
	METALLIC = clamp(metal * (1.0 - rm) + wm * 0.25 * step(0.3, metal), 0.0, 1.0);
	SPECULAR = 0.35 + gloss * 0.3;
}
"""

static var _shader: Shader
static var _tex := {}
static var _noise: Texture2D


static func label(name: String) -> String:
	return str(LIBRARY.get(name, [name])[0])


static func names() -> Array:
	return LIBRARY.keys()


static func shader() -> Shader:
	if _shader == null:
		Psx.init()
		_shader = Shader.new()
		_shader.code = SHADER
	return _shader


static func noise() -> Texture2D:
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.seed = 1203
		fn.frequency = 0.035
		fn.fractal_octaves = 4
		var img: Image = fn.get_seamless_image(128, 128)
		img.generate_mipmaps()
		_noise = ImageTexture.create_from_image(img)
	return _noise


## Materiał modułu: rodzaj z biblioteki + zużycie (słownik jak DEFAULT_WEAR).
static func make(mat_name: String, wear: Dictionary = {}, seed: float = 0.0) -> ShaderMaterial:
	var lib: Array = LIBRARY.get(mat_name, LIBRARY["stal"])
	var w := DEFAULT_WEAR.duplicate()
	for k in wear:
		w[k] = wear[k]
	var m := ShaderMaterial.new()
	m.shader = shader()
	m.set_shader_parameter("base_tex", texture(mat_name))
	m.set_shader_parameter("noise_tex", noise())
	var t: Array = w["tint"]
	m.set_shader_parameter("tint", Vector3(float(t[0]), float(t[1]), float(t[2])))
	var wc: Color = lib[1]
	var gc: Color = lib[2]
	m.set_shader_parameter("worn_color", Vector3(wc.r, wc.g, wc.b))
	m.set_shader_parameter("grime_color", Vector3(gc.r, gc.g, gc.b))
	m.set_shader_parameter("tex_scale", float(lib[5]) * float(w["skala"]))
	m.set_shader_parameter("wear", float(w["zuzycie"]))
	m.set_shader_parameter("grime", float(w["brud"]))
	m.set_shader_parameter("rust", float(w["rdza"]))
	m.set_shader_parameter("scratches", float(w["rysy"]))
	m.set_shader_parameter("rough", float(lib[3]))
	m.set_shader_parameter("metal", float(lib[4]))
	m.set_shader_parameter("gloss", float(w["polysk"]))
	m.set_shader_parameter("seed", seed)
	return m


static func texture(kind: String) -> Texture2D:
	if _tex.has(kind):
		return _tex[kind]
	var img := _image(kind)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[kind] = t
	return t


## Próbka materiału do listy w interfejsie (kwadrat z teksturą).
static func swatch(kind: String) -> Texture2D:
	return texture(kind)


static func _image(kind: String) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("pracownia_" + kind)
	var fn := FastNoiseLite.new()
	fn.seed = hash(kind) % 10000
	fn.frequency = 0.05
	var wob: Array = []
	for i in SIZE:
		wob.append(rng.randf_range(-1.0, 1.0))
	for y in SIZE:
		for x in SIZE:
			var n := rng.randf_range(-1.0, 1.0)
			var f := fn.get_noise_2d(x, y)   # -1..1, płynny
			var c: Color
			match kind:
				"stal":
					c = Color(0.11, 0.115, 0.13).lightened(0.04 * f + 0.02 * float(wob[y]))
					if rng.randf() < 0.01:
						c = c.lightened(0.15)
				"stal_jasna":
					c = Color(0.33, 0.33, 0.34).lightened(0.05 * f) + Color(n, n, n) * 0.015
				"stal_grawer":
					var sw := sin(float(x) * 0.35 + sin(float(y) * 0.21) * 3.0) * sin(float(y) * 0.33 + sin(float(x) * 0.17) * 2.5)
					c = Color(0.42, 0.42, 0.43).lightened(0.04 * f)
					if absf(sw) < 0.12:
						c = c.darkened(0.45)
				"parkeryzowana":
					c = Color(0.2, 0.21, 0.19).lightened(0.05 * f) + Color(n, n, n) * 0.03
				"chrom":
					c = Color(0.6, 0.61, 0.64).lightened(0.12 * sin(float(y) * 0.1 + f))
				"rdza":
					c = Color(0.4, 0.2, 0.08).lerp(Color(0.25, 0.12, 0.05), f * 0.5 + 0.5) + Color(n, n * 0.6, 0) * 0.05
				"polimer":
					c = Color(0.07, 0.07, 0.075) + Color(n, n, n) * 0.02
					if (x / 2 + y / 2) % 2 == 0 and rng.randf() < 0.3:
						c = c.lightened(0.04)  # faktura
				"farba_zielona":
					c = Color(0.24, 0.27, 0.17).lightened(0.05 * f) + Color(n, n, n) * 0.02
				"drewno", "drewno_jasne", "drewno_ciemne":
					var base := Color(0.35, 0.19, 0.085)
					if kind == "drewno_jasne":
						base = Color(0.55, 0.38, 0.22)
					elif kind == "drewno_ciemne":
						base = Color(0.2, 0.11, 0.05)
					var g := sin(float(y) * 0.5 + float(wob[x]) * 0.5 + f * 3.0)
					c = base.darkened(0.2 * (g * 0.5 + 0.5)) + Color(n, n * 0.8, n * 0.6) * 0.02
					if rng.randf() < 0.004:
						c = c.darkened(0.35)  # sęczek
				"bakelit":
					var d := (x + y) % 6 == 0 or (x - y + SIZE) % 6 == 0
					c = Color(0.17, 0.085, 0.055).darkened(0.35 if d else 0.0).lightened(0.03 * f)
				"guma":
					c = Color(0.06, 0.06, 0.06) + Color(n, n, n) * 0.012
					if y % 6 == 0:
						c = c.lightened(0.04)
				"skora":
					c = Color(0.32, 0.2, 0.11).lightened(0.08 * f) + Color(n, n, n) * 0.02
					if rng.randf() < 0.02:
						c = c.darkened(0.2)
				"tkanina":
					var wv := ((x % 4) < 2) != ((y % 4) < 2)
					c = Color(0.3, 0.28, 0.22).lightened(0.05 if wv else -0.03) + Color(n, n, n) * 0.02
				"mosiadz":
					c = Color(0.7, 0.54, 0.24).lightened(0.05 * f) + Color(n, n * 0.8, n * 0.4) * 0.03
				"miedz":
					c = Color(0.65, 0.35, 0.2).lightened(0.05 * f)
				"plastik_czerwony":
					c = Color(0.55, 0.08, 0.06) + Color(n, n, n) * 0.02
					if y % 8 == 0:
						c = c.darkened(0.12)
				"skora_dloni":
					c = Color(0.62, 0.46, 0.37).lightened(0.04 * f) + Color(n, n * 0.9, n * 0.8) * 0.015
				_:
					c = Color(0.5, 0.5, 0.5)
			img.set_pixel(x, y, Color(clampf(c.r, 0, 1), clampf(c.g, 0, 1), clampf(c.b, 0, 1)))
	return img
