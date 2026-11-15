extends Control
## Okno postaci (C): imię i zawód, cechy, umiejętności z poziomem 0–10
## (kwadraciki jak w PZ) i paskiem postępu do następnego poziomu, oznaczenie
## przeczytanej książki. Gra toczy się dalej, okno tylko nakrywa obraz.

var main
var character


func setup(main_node) -> void:
	main = main_node
	character = main.character
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func toggle() -> void:
	visible = not visible
	queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _text(p: Vector2, s: String, size_px: int, col: Color) -> void:
	draw_string(ThemeDB.fallback_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, col)


func _draw() -> void:
	var o := Vector2(60, 90)
	var w := 560.0
	var skills: Dictionary = character.data["skills"]
	var h := 150.0 + skills.size() * 40.0 + 30.0
	draw_rect(Rect2(o - Vector2(20, 40), Vector2(w + 40, h)), Color(0.05, 0.055, 0.05, 0.92))
	draw_rect(Rect2(o - Vector2(20, 40), Vector2(w + 40, h)), Color(0.35, 0.33, 0.25), false, 1.0)
	var accent := Color(0.85, 0.75, 0.5)
	var prof_name: String = character.local(character.data["professions"].get(character.profession, {}))
	_text(o, "%s · %s" % [character.char_name if character.char_name != "" else tr("CC_DEFAULT_NAME"), prof_name], 20, accent)
	var tnames: PackedStringArray = []
	for t in character.traits:
		tnames.append(character.local(character.data["traits"].get(t, {})))
	_text(o + Vector2(0, 28), tr("CP_TRAITS") % (", ".join(tnames) if not tnames.is_empty() else "—"), 14, Color(0.75, 0.75, 0.7))
	var y := o.y + 70.0
	for s in skills:
		var lvl: int = character.level(s)
		_text(Vector2(o.x, y + 14), character.skill_name(s), 16, Color(0.88, 0.88, 0.84))
		for k in 10:
			var r := Rect2(o.x + 200 + k * 22, y, 18, 18)
			draw_rect(r, accent if k < lvl else Color(0.18, 0.18, 0.16))
			draw_rect(r, Color(0.35, 0.33, 0.25), false, 1.0)
		var bar := Rect2(o.x + 200, y + 22, 218, 4)
		draw_rect(bar, Color(0.12, 0.12, 0.11))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * character.xp_ratio(s), bar.size.y)), Color(0.55, 0.7, 0.45))
		if character.books.has(s) and lvl < int(character.books[s]):
			_text(Vector2(o.x + 440, y + 14), tr("CP_BOOK") % int(character.books[s]), 13, Color(0.6, 0.8, 0.95))
		y += 40.0
	_text(Vector2(o.x, y + 18), tr("CP_HINT"), 13, Color(0.55, 0.55, 0.5))
