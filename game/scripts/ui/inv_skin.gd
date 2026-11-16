extends RefCounted
## Oprawa okna ekwipunku: tekstury materiałów generowane kodem (płótno plecaka,
## materiał ubrania, drewno szafki, metal lodówki, papier karteczek).
## Każda siatka dostaje tło z materiału swojego pojemnika, opisy są na karteczkach.

const SIZE := 128

var _tex := {}


func tex(mat: String) -> Texture2D:
	if not _tex.has(mat):
		_tex[mat] = ImageTexture.create_from_image(_make(mat))
	return _tex[mat]


## Materiał tła dla pojemnika noszonego (po przedmiocie) albo w świecie (po etykiecie).
static func material_for_item(def_id: String) -> String:
	if def_id.begins_with("plecak") or def_id.begins_with("torba"):
		return "canvas"
	if def_id.begins_with("kamizelka") or def_id.begins_with("pas"):
		return "canvas_dark"
	return "cloth"


static func material_for_container(label: String) -> String:
	var k := label.trim_prefix("INV_CONTAINER_")
	match k:
		"lodowka", "apteczka_scienna":
			return "metal"
		"skrzynka_narzedziowa":
			return "metal_red"
		"wycieraczka":
			return "rubber"
		"szafka", "szafka_kuchenna", "szafa", "regal", "piwnica":
			return "wood"
	return "cloth_dirty"  # zwłoki: przy pasie i w kieszeniach trupa


static func is_soft(mat: String) -> bool:
	return mat.begins_with("canvas") or mat.begins_with("cloth")


func _make(mat: String) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(mat)
	var base: Color
	match mat:
		"canvas": base = Color(0.30, 0.28, 0.19)
		"canvas_dark": base = Color(0.21, 0.22, 0.17)
		"cloth": base = Color(0.17, 0.19, 0.22)
		"cloth_dirty": base = Color(0.24, 0.21, 0.17)
		"wood": base = Color(0.34, 0.22, 0.13)
		"metal": base = Color(0.58, 0.59, 0.56)
		"metal_red": base = Color(0.42, 0.12, 0.09)
		"rubber": base = Color(0.12, 0.12, 0.11)
		"paper": base = Color(0.85, 0.81, 0.69)
		_: base = Color(0.2, 0.2, 0.2)
	var stains: Array = []
	if mat == "cloth_dirty" or mat == "canvas" or mat == "wood":
		for i in 5:
			stains.append([Vector2(rng.randf() * SIZE, rng.randf() * SIZE), rng.randf_range(8.0, 22.0)])
	var grain_off: Array = []
	for y in SIZE:
		grain_off.append(rng.randf_range(-1.0, 1.0))
	for y in SIZE:
		for x in SIZE:
			var n := rng.randf_range(-0.035, 0.035)
			var c := base
			match mat:
				"canvas", "canvas_dark":
					var weave := 0.04 if ((x % 4 < 2) != (y % 4 < 2)) else -0.03
					c = c.lightened(weave) if weave > 0 else c.darkened(-weave)
				"cloth", "cloth_dirty":
					if (x + y) % 6 < 2:
						c = c.lightened(0.05)
				"wood":
					var g := sin(float(y) * 0.45 + float(grain_off[y]) * 0.8 + sin(float(x) * 0.05) * 2.0)
					c = c.darkened(0.08 * (g * 0.5 + 0.5))
					if y % 32 == 0:
						c = c.darkened(0.35)  # łączenie desek
				"metal", "metal_red":
					c = c.lightened(float(grain_off[y]) * 0.04)
					if rng.randf() < 0.002:
						c = c.lightened(0.25)
				"rubber":
					if x % 8 == 4 and y % 8 == 4:
						c = c.lightened(0.12)
				"paper":
					if rng.randf() < 0.01:
						c = c.darkened(0.08)  # włókna
			for st in stains:
				var d: float = (st[0] as Vector2).distance_to(Vector2(x, y))
				if d < float(st[1]):
					var dark: Color = Color(0.25, 0.08, 0.05) if mat == "cloth_dirty" else Color(0.1, 0.08, 0.05)
					c = c.lerp(dark, 0.25 * (1.0 - d / float(st[1])))
			c = Color(clampf(c.r + n, 0, 1), clampf(c.g + n, 0, 1), clampf(c.b + n, 0, 1), 1.0)
			img.set_pixel(x, y, c)
	return img


## Tło siatki: materiał pojemnika z obszyciem (płótno) albo śrubkami (metal).
func draw_backing(ci: CanvasItem, r: Rect2, mat: String) -> void:
	var back := r.grow(9.0)
	ci.draw_rect(back.grow(2.0), Color(0, 0, 0, 0.45))
	ci.draw_texture_rect(tex(mat), back, true)
	if is_soft(mat):
		_stitch(ci, back.grow(-4.0), Color(0.75, 0.68, 0.5, 0.55))
	elif mat.begins_with("metal"):
		for p in [back.position, Vector2(back.end.x, back.position.y), Vector2(back.position.x, back.end.y), back.end]:
			var q: Vector2 = p + Vector2(5 if p.x == back.position.x else -5, 5 if p.y == back.position.y else -5)
			ci.draw_circle(q, 2.2, Color(0.25, 0.25, 0.24))
			ci.draw_circle(q - Vector2(0.6, 0.6), 1.0, Color(0.85, 0.85, 0.8))
	else:
		ci.draw_rect(back, Color(0, 0, 0, 0.6), false, 2.0)


func _stitch(ci: CanvasItem, r: Rect2, col: Color) -> void:
	var step := 9.0
	var x := r.position.x
	while x < r.end.x - 4.0:
		ci.draw_line(Vector2(x, r.position.y), Vector2(minf(x + 5.0, r.end.x), r.position.y), col, 1.0)
		ci.draw_line(Vector2(x, r.end.y), Vector2(minf(x + 5.0, r.end.x), r.end.y), col, 1.0)
		x += step
	var y := r.position.y
	while y < r.end.y - 4.0:
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.position.x, minf(y + 5.0, r.end.y)), col, 1.0)
		ci.draw_line(Vector2(r.end.x, y), Vector2(r.end.x, minf(y + 5.0, r.end.y)), col, 1.0)
		y += step


## Etykieta jak kawałek taśmy malarskiej z napisem.
func draw_tag(ci: CanvasItem, font: Font, p: Vector2, text: String, sz: int) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var r := Rect2(p + Vector2(-6, -sz - 2), Vector2(w + 12, sz + 9))
	ci.draw_set_transform(r.get_center(), -0.012, Vector2.ONE)
	var rr := Rect2(-r.size * 0.5, r.size)
	ci.draw_rect(rr.grow(1.0), Color(0, 0, 0, 0.35))
	ci.draw_texture_rect(tex("paper"), rr, true, Color(1.0, 0.97, 0.85))
	ci.draw_string(font, rr.position + Vector2(6, sz + 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0.16, 0.13, 0.1))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Karteczka z opisem przedmiotu: papier, pinezka, tekst atramentem.
func draw_card(ci: CanvasItem, font: Font, p: Vector2, lines: PackedStringArray) -> void:
	var w := 0.0
	for i in lines.size():
		w = maxf(w, font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 17 if i == 0 else 15).x)
	var h := lines.size() * 20.0 + 26.0
	var size := Vector2(w + 28.0, h)
	ci.draw_set_transform(p + size * 0.5, -0.018, Vector2.ONE)
	var r := Rect2(-size * 0.5, size)
	ci.draw_rect(Rect2(r.position + Vector2(5, 6), r.size), Color(0, 0, 0, 0.4))
	ci.draw_texture_rect(tex("paper"), r, true)
	# linie zeszytu
	var y := r.position.y + 30.0
	while y < r.end.y - 4.0:
		ci.draw_line(Vector2(r.position.x + 6, y + 4), Vector2(r.end.x - 6, y + 4), Color(0.45, 0.55, 0.7, 0.25), 1.0)
		y += 20.0
	ci.draw_line(Vector2(r.position.x + 22, r.position.y + 4), Vector2(r.position.x + 22, r.end.y - 4), Color(0.75, 0.3, 0.3, 0.35), 1.0)
	# pinezka
	var pin := Vector2(0, r.position.y + 6)
	ci.draw_circle(pin + Vector2(1, 2), 5.0, Color(0, 0, 0, 0.35))
	ci.draw_circle(pin, 5.0, Color(0.7, 0.12, 0.1))
	ci.draw_circle(pin - Vector2(1.5, 1.5), 1.6, Color(1, 0.6, 0.55))
	for i in lines.size():
		var col := Color(0.12, 0.1, 0.09) if i == 0 else Color(0.18, 0.16, 0.2)
		ci.draw_string(font, r.position + Vector2(28, 30 + i * 20), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 17 if i == 0 else 15, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
