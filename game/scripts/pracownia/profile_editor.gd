extends Control
## Edytor profilu: kontur w płaszczyźnie X-Y (widok z boku), wyciągany potem na grubość.
## LPM na punkcie: przeciąganie · LPM na krawędzi: nowy punkt · PPM na punkcie: usunięcie
## kółko: przybliżenie · środkowy: przesuwanie widoku · Shift: bez przyciągania do siatki.

signal changed
signal committed

const UI := preload("res://scripts/pracownia/ui_kit.gd")

var points: Array = []           # [[x, y], ...] w metrach (wspólna tablica z modułem)
var ghosts: Array = []           # [Rect2] obrysy innych modułów (tło do odrysowania)
var snap := 0.001
var _scale := 1600.0             # pikseli na metr
var _pan := Vector2.ZERO
var _drag := -1
var _panning := false
var _hover := -1


func _init() -> void:
	custom_minimum_size = Vector2(0, 260)
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_points(p: Array) -> void:
	points = p
	fit()


func fit() -> void:
	if points.is_empty() or size.x < 10.0:
		_pan = Vector2.ZERO
		queue_redraw()
		return
	var r := Rect2(_v(points[0]), Vector2.ZERO)
	for p in points:
		r = r.expand(_v(p))
	var span := maxf(r.size.x, r.size.y * 1.6)
	_scale = clampf((size.x - 40.0) / maxf(0.01, span), 200.0, 20000.0)
	_pan = -r.get_center()
	queue_redraw()


static func _v(p) -> Vector2:
	return Vector2(float(p[0]), float(p[1]))


func _to_screen(p: Vector2) -> Vector2:
	return size * 0.5 + Vector2(p.x + _pan.x, -(p.y + _pan.y)) * _scale


func _to_world(s: Vector2) -> Vector2:
	var d := (s - size * 0.5) / _scale
	return Vector2(d.x - _pan.x, -d.y - _pan.y)


func _snap(p: Vector2) -> Vector2:
	if snap <= 0.0 or Input.is_key_pressed(KEY_SHIFT):
		return p
	return Vector2(snappedf(p.x, snap), snappedf(p.y, snap))


func _point_at(s: Vector2) -> int:
	for i in points.size():
		if _to_screen(_v(points[i])).distance_to(s) < 8.0:
			return i
	return -1


func _edge_at(s: Vector2) -> int:
	var n := points.size()
	for i in n:
		var a := _to_screen(_v(points[i]))
		var b := _to_screen(_v(points[(i + 1) % n]))
		var c := Geometry2D.get_closest_point_to_segment(s, a, b)
		if c.distance_to(s) < 6.0:
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var i := _point_at(mb.position)
				if i < 0:
					var e := _edge_at(mb.position)
					if e >= 0:
						var w := _snap(_to_world(mb.position))
						points.insert(e + 1, [w.x, w.y])
						i = e + 1
						changed.emit()
					elif mb.double_click:
						var w2 := _snap(_to_world(mb.position))
						points.append([w2.x, w2.y])
						i = points.size() - 1
						changed.emit()
				_drag = i
			else:
				if _drag >= 0:
					committed.emit()
				_drag = -1
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var i := _point_at(mb.position)
			if i >= 0 and points.size() > 3:
				points.remove_at(i)
				changed.emit()
				committed.emit()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			accept_event()
		elif mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and mb.pressed:
			var before := _to_world(mb.position)
			_scale = clampf(_scale * (1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 100.0, 40000.0)
			var after := _to_world(mb.position)
			_pan += after - before
			accept_event()
		queue_redraw()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag >= 0 and _drag < points.size():
			var w := _snap(_to_world(mm.position))
			points[_drag] = [w.x, w.y]
			changed.emit()
		elif _panning:
			_pan += Vector2(mm.relative.x, -mm.relative.y) / _scale
		_hover = _point_at(mm.position)
		queue_redraw()


## Odbija kontur w pionie (góra-dół) i dokleja: z połówki robi się symetryczny kształt.
func mirror_vertical() -> void:
	var n := points.size()
	for i in range(n - 1, -1, -1):
		var p: Array = points[i]
		if absf(float(p[1])) > 0.0005:
			points.append([float(p[0]), -float(p[1])])
	changed.emit()
	committed.emit()
	fit()


func flip_horizontal() -> void:
	for p in points:
		p[0] = -float(p[0])
	points.reverse()
	changed.emit()
	committed.emit()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UI.BG)
	# siatka: co 1 cm, mocniej co 5 cm
	var step := 0.01
	var a := _to_world(Vector2.ZERO)
	var b := _to_world(size)
	var x0 := floorf(minf(a.x, b.x) / step) * step
	var y0 := floorf(minf(a.y, b.y) / step) * step
	var x := x0
	while x < maxf(a.x, b.x):
		var sx := _to_screen(Vector2(x, 0)).x
		var major := absf(fmod(absf(x) + 0.0001, 0.05)) < 0.001
		draw_line(Vector2(sx, 0), Vector2(sx, size.y), Color(1, 1, 1, 0.09 if major else 0.035))
		x += step
	var y := y0
	while y < maxf(a.y, b.y):
		var sy := _to_screen(Vector2(0, y)).y
		var major := absf(fmod(absf(y) + 0.0001, 0.05)) < 0.001
		draw_line(Vector2(0, sy), Vector2(size.x, sy), Color(1, 1, 1, 0.09 if major else 0.035))
		y += step
	var o := _to_screen(Vector2.ZERO)
	draw_line(Vector2(o.x, 0), Vector2(o.x, size.y), Color(UI.GREEN, 0.35))
	draw_line(Vector2(0, o.y), Vector2(size.x, o.y), Color(UI.RED, 0.35))
	for g in ghosts:
		var r: Rect2 = g
		var p0 := _to_screen(Vector2(r.position.x, r.position.y + r.size.y))
		draw_rect(Rect2(p0, r.size * _scale), Color(1, 1, 1, 0.12), false, 1.0)
	if points.size() >= 3:
		var poly := PackedVector2Array()
		for p in points:
			poly.append(_to_screen(_v(p)))
		if Geometry2D.triangulate_polygon(poly).size() > 0:
			draw_colored_polygon(poly, Color(UI.ACCENT, 0.13))
		var closed := poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, UI.ACCENT, 2.0, true)
	for i in points.size():
		var s := _to_screen(_v(points[i]))
		var hot := i == _hover or i == _drag
		draw_rect(Rect2(s - Vector2(4, 4), Vector2(8, 8)), UI.ACCENT.lightened(0.3) if hot else UI.TEXT)
	var font := get_theme_default_font()
	draw_string(font, Vector2(8, size.y - 8), "LPM: przeciągnij / klik na krawędzi: nowy punkt · 2×klik: punkt na końcu · PPM: usuń · kółko/środkowy: widok · siatka 1 cm",
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 11, UI.DIM)
	if _hover >= 0 and _hover < points.size():
		var p: Vector2 = _v(points[_hover])
		draw_string(font, _to_screen(p) + Vector2(8, -8), "%.1f, %.1f mm" % [p.x * 1000.0, p.y * 1000.0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UI.ACCENT)
