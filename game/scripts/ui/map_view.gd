extends Control
## Mapa i kompas trzymane w rękach. Mapa (przedmiot z polem "map") w którejś
## ręce: kartka w lewym dolnym rogu z planem osiedla (ulice z nazwami, domy
## z numerami, dom startowy). Nie pokazuje gracza: trzeba się odnaleźć po
## tabliczkach. Kompas (pole "compass") w ręce: tarcza z igłą na północ. Mapa
## i kompas razem: mapa obraca się zgodnie z kierunkiem patrzenia.

const PAPER := Vector2(470, 400)
const MARGIN := 18.0
const C_PAPER := Color(0.86, 0.82, 0.68)
const C_INK := Color(0.22, 0.18, 0.14)
const C_ROAD := Color(0.62, 0.6, 0.56)
const C_HOUSE := Color(0.55, 0.38, 0.28)

var main
var font: Font
var showing_map := false
var showing_compass := false


func setup(main_node) -> void:
	main = main_node
	font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _held(field: String) -> bool:
	for side in ["l", "r"]:
		var it = main.inventory.hand(side)
		if it != null and it.get_def().has(field):
			return true
	return false


func _process(_delta: float) -> void:
	if main == null or main.inventory == null:
		return
	var m := _held("map")
	var c := _held("compass")
	var inv_open: bool = main.inv_ui != null and main.inv_ui.is_open()
	m = m and not inv_open
	c = c and not inv_open
	if m != showing_map or c != showing_compass or m or c:
		showing_map = m
		showing_compass = c
		queue_redraw()


func _yaw() -> float:
	return main.player.rotation.y


func _draw() -> void:
	if showing_map:
		_draw_map()
	if showing_compass:
		var center := Vector2(size.x - 120.0, size.y - 190.0) if not showing_map else Vector2(PAPER.x + 120.0, size.y - 190.0)
		_draw_compass(center, 70.0)


func _draw_map() -> void:
	var town = main.town
	var area: Rect2 = town.AREA
	var origin := Vector2(24.0, size.y - PAPER.y - 110.0)  # nad paskiem podpowiedzi klawiszy
	draw_rect(Rect2(origin + Vector2(6, 6), PAPER), Color(0, 0, 0, 0.35))
	draw_rect(Rect2(origin, PAPER), C_PAPER)
	draw_rect(Rect2(origin, PAPER), C_INK, false, 2.0)
	draw_string(font, origin + Vector2(MARGIN, 26), tr("MAP_TITLE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_INK)
	var inner := Rect2(origin + Vector2(MARGIN, 38), PAPER - Vector2(MARGIN * 2.0, 38 + MARGIN))
	var k := minf(inner.size.x / area.size.x, inner.size.y / area.size.y)
	var off := inner.position + (inner.size - area.size * k) * 0.5
	var center := off + area.size * k * 0.5
	# z kompasem: obrót tak, by kierunek patrzenia był w górę kartki
	var rot := _yaw() if showing_compass else 0.0
	draw_set_transform(center, rot, Vector2.ONE)
	var to_map := func(p: Vector2) -> Vector2: return (p - area.position) * k + off - center
	for st in town.STREETS:
		var r: Rect2 = st[1]
		var a: Vector2 = to_map.call(r.position)
		draw_rect(Rect2(a, r.size * k), C_ROAD)
	for h in town.houses:
		var r: Rect2 = h["rect"]
		var a: Vector2 = to_map.call(r.position)
		draw_rect(Rect2(a, r.size * k), C_HOUSE.lightened(0.25) if int(h["floors"]) > 1 else C_HOUSE.lightened(0.4))
		draw_rect(Rect2(a, r.size * k), C_INK, false, 1.0)
		draw_string(font, a + r.size * k * 0.5 + Vector2(-6, 5), str(h["number"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, C_INK)
	var sr: Rect2 = town.START_RECT
	var sa: Vector2 = to_map.call(sr.position)
	draw_rect(Rect2(sa, sr.size * k), C_HOUSE.darkened(0.1))
	draw_rect(Rect2(sa, sr.size * k), C_INK, false, 1.0)
	draw_string(font, sa + Vector2(0, -3), tr("MAP_START"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_INK)
	for st in town.STREETS:
		var r: Rect2 = st[1]
		var lp: Vector2 = to_map.call(r.get_center())
		var label := "ul. " + str(st[0])
		if st[2] == "z":
			draw_set_transform(center + lp.rotated(rot), rot - PI / 2.0, Vector2.ONE)
			draw_string(font, Vector2(-30, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_INK)
			draw_set_transform(center, rot, Vector2.ONE)
		else:
			draw_string(font, lp + Vector2(-110, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_INK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# róża: strzałka północy (obrócona razem z mapą)
	var nr := origin + Vector2(PAPER.x - 36, 36)
	var dir := Vector2(0, -1).rotated(rot)
	draw_line(nr - dir * 14.0, nr + dir * 14.0, C_INK, 2.0)
	draw_circle(nr + dir * 14.0, 3.0, C_INK)
	draw_string(font, nr + dir * 26.0 + Vector2(-8, 5), tr("MAP_NORTH"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_INK)


func _draw_compass(c: Vector2, r: float) -> void:
	draw_circle(c + Vector2(4, 4), r + 6.0, Color(0, 0, 0, 0.35))
	draw_circle(c, r + 6.0, Color(0.42, 0.36, 0.22))
	draw_circle(c, r, Color(0.9, 0.88, 0.8))
	# tarcza obraca się z postacią: północ tam, gdzie naprawdę jest
	var yaw := _yaw()
	for k in 8:
		var a := yaw + k * PI / 4.0
		var d := Vector2(0, -1).rotated(a)
		draw_line(c + d * (r - (10.0 if k % 2 == 0 else 6.0)), c + d * r, C_INK, 2.0 if k % 2 == 0 else 1.0)
	for pair in [["N", 0.0], ["E", PI / 2.0], ["S", PI], ["W", -PI / 2.0]]:
		var label: String = tr("MAP_NORTH") if pair[0] == "N" else str(pair[0])
		var d := Vector2(0, -1).rotated(yaw + float(pair[1]))
		draw_string(font, c + d * (r - 22.0) + Vector2(-6, 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.1, 0.08) if pair[0] == "N" else C_INK)
	var n := Vector2(0, -1).rotated(yaw)
	var side := n.orthogonal() * 6.0
	draw_colored_polygon(PackedVector2Array([c + n * (r - 14.0), c + side, c - side]), Color(0.75, 0.12, 0.08))
	draw_colored_polygon(PackedVector2Array([c - n * (r - 14.0), c + side, c - side]), Color(0.3, 0.3, 0.32))
	draw_circle(c, 4.0, C_INK)
