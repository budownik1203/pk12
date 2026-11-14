extends RefCounted
## Proceduralne tekstury zastępcze w niskiej rozdzielczości (bez filtrowania).
## Docelowo zastąpią je tekstury z Blendera; styl i rozmiar zostają.

const SIZE := 64


static func material(kind: String, world_space: bool, scale: float = 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _texture(kind)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world_space
	m.uv1_scale = Vector3(scale, scale, scale)
	m.roughness = 0.6 if kind == "metal" or kind == "can" else 0.95
	m.metallic = 0.5 if kind == "metal" or kind == "can" else 0.0
	return m


static func _texture(kind: String) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			img.set_pixel(x, y, _pixel(kind, x, y, rng))
	return ImageTexture.create_from_image(img)


static func _pixel(kind: String, x: int, y: int, rng: RandomNumberGenerator) -> Color:
	var n := rng.randf_range(-1.0, 1.0)
	match kind:
		"floor":
			# deski: ciemne szczeliny co 16 pikseli, każda deska w innym odcieniu
			var plank := y / 16
			var tint := 0.04 * float((plank * 37) % 5 - 2)
			var c := Color(0.27 + tint, 0.20 + tint, 0.14 + tint)
			if y % 16 == 0 or (x + plank * 23) % 48 == 0:
				c = c.darkened(0.55)
			return c + Color(n, n, n) * 0.035
		"wall":
			# brudny tynk z nieregularnymi plamami
			var c := Color(0.42, 0.43, 0.40)
			var streak := 0.022 * sin(float(x) * 0.31) * sin(float(y) * 0.23)
			return c + Color(n, n, n) * 0.03 - Color(streak, streak, streak)
		"ceiling":
			return Color(0.33, 0.33, 0.32) + Color(n, n, n) * 0.02
		"crate":
			# skrzynka: rama i przekątna
			var c := Color(0.45, 0.33, 0.19)
			var edge := x < 5 or y < 5 or x >= SIZE - 5 or y >= SIZE - 5
			var diag := absi(x - y) < 3
			if edge or diag:
				c = c.darkened(0.3)
			if x == 5 or y == 5 or x == SIZE - 6 or y == SIZE - 6:
				c = c.darkened(0.6)
			return c + Color(n, n, n) * 0.04
		"wood":
			var c := Color(0.36, 0.27, 0.17)
			if x % 21 == 0:
				c = c.darkened(0.4)
			return c + Color(n, n, n) * 0.035
		"metal":
			# beczka: rdzawe pasy
			var c := Color(0.20, 0.27, 0.30)
			if y % 22 < 3:
				c = Color(0.33, 0.20, 0.12)
			return c + Color(n, n * 0.7, n * 0.5) * 0.05
		"can":
			var c := Color(0.62, 0.62, 0.60)
			if y > 14 and y < 46:
				c = Color(0.55, 0.16, 0.13)
			return c + Color(n, n, n) * 0.03
	return Color(0.5, 0.5, 0.5) + Color(n, n, n) * 0.05
