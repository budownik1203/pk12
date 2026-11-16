extends RefCounted
## Teksturowane materiały broni (styl Iron Blight): oksydowana stal z przetarciami,
## orzechowe drewno z słojami, bakelit z radełkowaniem, mosiądz łusek.
## Modele z models/bron.glb mają materiały o tych nazwach; gra podmienia je tutaj.

const SIZE := 128
const SCALE := 7.0   # ile powtórzeń tekstury na metr (współrzędne modelu)

static var _cache := {}


## Materiał dla nazwy materiału z Blendera (null: nie podmieniamy).
static func for_name(mat_name: String) -> StandardMaterial3D:
	var kind := ""
	match mat_name:
		"stal": kind = "steel"
		"stal_jasna": kind = "steel_light"
		"stal_grawer": kind = "engraved"
		"guma": kind = "rubber"
		"drewno": kind = "wood"
		"bakelit": kind = "bakelite"
		"mosiadz": kind = "brass"
		"plastik_czerwony": kind = "red"
	if kind == "":
		return null
	if _cache.has(kind):
		return _cache[kind]
	var m := StandardMaterial3D.new()
	m.resource_name = "bron_" + kind
	m.albedo_texture = ImageTexture.create_from_image(_image(kind))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * SCALE
	match kind:
		"steel", "steel_light", "engraved":
			m.metallic = 0.55
			m.roughness = 0.45
		"brass":
			m.metallic = 0.7
			m.roughness = 0.35
		"wood":
			m.roughness = 0.7
		_:
			m.roughness = 0.6
	_cache[kind] = m
	return m


static func _image(kind: String) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("bron_" + kind)
	var wobble: Array = []
	for i in SIZE:
		wobble.append(rng.randf_range(-1.0, 1.0))
	for y in SIZE:
		for x in SIZE:
			var n := rng.randf_range(-1.0, 1.0)
			var c: Color
			match kind:
				"steel":
					# oksyda: prawie czarna, niebieskawa, przetarcia jaśniejsze, drobna rdza
					c = Color(0.11, 0.115, 0.13) + Color(n, n, n) * 0.012
					c = c.lightened(0.05 * float(wobble[y]) * 0.5)
					if rng.randf() < 0.015:
						c = Color(0.3, 0.3, 0.31)
					if rng.randf() < 0.004:
						c = Color(0.3, 0.17, 0.09)
				"steel_light":
					c = Color(0.32, 0.32, 0.33) + Color(n, n, n) * 0.025
					if (x + y * 3) % 29 == 0:
						c = c.lightened(0.2)  # rysy
				"wood":
					# słoje wzdłuż długości z falowaniem i ciemniejsze pasy
					var g := sin(float(y) * 0.55 + float(wobble[x]) * 0.6 + sin(float(x) * 0.09) * 1.8)
					c = Color(0.35, 0.19, 0.085).darkened(0.18 * (g * 0.5 + 0.5)) + Color(n, n * 0.8, n * 0.6) * 0.02
					if rng.randf() < 0.01:
						c = c.darkened(0.3)
				"engraved":
					# grawerowana baskila: jasna stal z ciemnymi zawijasami
					var sw := sin(float(x) * 0.35 + sin(float(y) * 0.21) * 3.0) * sin(float(y) * 0.33 + sin(float(x) * 0.17) * 2.5)
					c = Color(0.42, 0.42, 0.43) + Color(n, n, n) * 0.03
					if absf(sw) < 0.12:
						c = c.darkened(0.45)
					if x < 3 or y < 3 or x > SIZE - 4 or y > SIZE - 4:
						c = c.darkened(0.3)
				"rubber":
					c = Color(0.06, 0.06, 0.06) + Color(n, n, n) * 0.015
					if y % 6 == 0:
						c = c.lightened(0.04)
				"bakelite":
					# radełkowanie w romby
					var d := (x + y) % 6 == 0 or (x - y + SIZE) % 6 == 0
					c = Color(0.17, 0.085, 0.055).darkened(0.35 if d else 0.0) + Color(n, n, n) * 0.015
				"brass":
					c = Color(0.7, 0.54, 0.24) + Color(n, n * 0.8, n * 0.4) * 0.04
				"red":
					c = Color(0.55, 0.08, 0.06) + Color(n, n, n) * 0.02
					if y % 8 == 0:
						c = c.darkened(0.12)  # karbowanie łuski
				_:
					c = Color(0.5, 0.5, 0.5)
			img.set_pixel(x, y, Color(clampf(c.r, 0, 1), clampf(c.g, 0, 1), clampf(c.b, 0, 1)))
	return img
