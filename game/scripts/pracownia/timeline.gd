extends Control
## Oś czasu kroku animacji: wiersz na ścieżkę, romby kluczy, głowica odtwarzania.
## LPM na osi: przewijanie · LPM na rombie: zaznaczenie i przeciąganie w czasie
## 2×klik w wierszu: klucz z bieżącą wartością · Delete: usuwa zaznaczony klucz.

signal scrubbed(t: float)
signal key_added(track: String, t: float)
signal edited
signal track_selected(track: String)

const UI := preload("res://scripts/pracownia/ui_kit.gd")
const Anim := preload("res://scripts/pracownia/anim.gd")
const LABEL_W := 150.0
const ROW_H := 20.0
const TOP := 22.0

var step: Dictionary = {}
var t := 0.0
var rows: Array = []
var selected_track := ""
var _sel_key := -1
var _drag_key := false
var _scrub := false


func _init() -> void:
	custom_minimum_size = Vector2(0, 170)
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK


func set_step(s: Dictionary, extra_track: String = "") -> void:
	step = s
	_sel_key = -1
	refresh_rows(extra_track)


func refresh_rows(extra_track: String = "") -> void:
	rows = []
	var tracks: Dictionary = step.get("tracks", {})
	for k in Anim.TRACKS:
		if tracks.has(k) or k == extra_track or k == selected_track:
			rows.append(k)
	custom_minimum_size.y = TOP + maxf(5.0, rows.size()) * ROW_H + 8.0
	queue_redraw()


func _x_of(tt: float) -> float:
	return LABEL_W + tt * (size.x - LABEL_W - 12.0)


func _t_of(x: float) -> float:
	return clampf((x - LABEL_W) / maxf(1.0, size.x - LABEL_W - 12.0), 0.0, 1.0)


func _row_of(y: float) -> int:
	var r := int(floor((y - TOP) / ROW_H))
	return r if r >= 0 and r < rows.size() else -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			grab_focus()
			var r := _row_of(mb.position.y)
			if mb.position.x < LABEL_W:
				if r >= 0:
					selected_track = rows[r]
					track_selected.emit(selected_track)
				queue_redraw()
				return
			if r >= 0:
				var track: String = rows[r]
				var keys: Array = step.get("tracks", {}).get(track, [])
				for i in keys.size():
					if absf(_x_of(float(keys[i][0])) - mb.position.x) < 7.0:
						selected_track = track
						_sel_key = i
						_drag_key = true
						track_selected.emit(track)
						queue_redraw()
						return
				if mb.double_click:
					selected_track = track
					key_added.emit(track, snappedf(_t_of(mb.position.x), 0.01))
					return
			_scrub = true
			t = _t_of(mb.position.x)
			scrubbed.emit(t)
		else:
			if _drag_key:
				edited.emit()
			_drag_key = false
			_scrub = false
		queue_redraw()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_key and selected_track != "":
			var keys: Array = step.get("tracks", {}).get(selected_track, [])
			if _sel_key >= 0 and _sel_key < keys.size():
				var nt := snappedf(_t_of(mm.position.x), 0.01)
				keys[_sel_key][0] = nt
				var moved: Array = keys[_sel_key]
				keys.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
				_sel_key = keys.find(moved)
				scrubbed.emit(nt)
				t = nt
		elif _scrub:
			t = _t_of(mm.position.x)
			scrubbed.emit(t)
		queue_redraw()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode in [KEY_DELETE, KEY_BACKSPACE]:
		if selected_track != "" and _sel_key >= 0:
			var keys: Array = step.get("tracks", {}).get(selected_track, [])
			if _sel_key < keys.size():
				keys.remove_at(_sel_key)
				if keys.is_empty():
					step["tracks"].erase(selected_track)
			_sel_key = -1
			refresh_rows()
			edited.emit()
			accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UI.BG)
	var font := get_theme_default_font()
	var dur := float(step.get("time", 0.5))
	# podziałka w sekundach
	var ticks := 10
	for i in ticks + 1:
		var x := _x_of(float(i) / ticks)
		draw_line(Vector2(x, TOP - 6), Vector2(x, size.y), Color(1, 1, 1, 0.05 if i % 5 else 0.1))
		if i % 2 == 0:
			draw_string(font, Vector2(x + 2, 13), "%.2fs" % (dur * float(i) / ticks), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UI.DIM)
	for r in rows.size():
		var y := TOP + r * ROW_H
		var track: String = rows[r]
		if r % 2 == 0:
			draw_rect(Rect2(0, y, size.x, ROW_H), Color(1, 1, 1, 0.025))
		if track == selected_track:
			draw_rect(Rect2(0, y, size.x, ROW_H), Color(UI.ACCENT, 0.08))
		draw_string(font, Vector2(8, y + 14), str(Anim.TRACK_LABELS.get(track, track)), HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 12, 12,
				UI.ACCENT if track == selected_track else UI.TEXT)
		var keys: Array = step.get("tracks", {}).get(track, [])
		# linia przebiegu: wartość względem zakresu ścieżki
		if keys.size() > 1:
			var mn := INF
			var mx := -INF
			for k in keys:
				mn = minf(mn, float(k[1]))
				mx = maxf(mx, float(k[1]))
			if mx - mn > 0.00001:
				var pts := PackedVector2Array()
				for s in 41:
					var tt := float(s) / 40.0
					var v = Anim.sample(step, track, tt)
					pts.append(Vector2(_x_of(tt), y + ROW_H - 4 - (float(v) - mn) / (mx - mn) * (ROW_H - 8)))
				draw_polyline(pts, Color(UI.BLUE, 0.55), 1.0, true)
		for i in keys.size():
			var c := Vector2(_x_of(float(keys[i][0])), y + ROW_H * 0.5)
			var hot := track == selected_track and i == _sel_key
			var d := PackedVector2Array([c + Vector2(0, -6), c + Vector2(6, 0), c + Vector2(0, 6), c + Vector2(-6, 0)])
			draw_colored_polygon(d, UI.ACCENT.lightened(0.35) if hot else UI.ACCENT)
	for e in step.get("events", []):
		var ex := _x_of(float(e[0]))
		draw_line(Vector2(ex, TOP - 6), Vector2(ex, TOP + 2), UI.GREEN, 2.0)
	var px := _x_of(t)
	draw_line(Vector2(px, 0), Vector2(px, size.y), UI.RED, 2.0)
	draw_string(font, Vector2(px + 4, size.y - 6), "%.2fs" % (t * dur), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UI.RED)
	if rows.is_empty():
		draw_string(font, Vector2(LABEL_W + 10, TOP + 30), "Brak ścieżek: wybierz ścieżkę po prawej i dodaj klucz", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.DIM)
