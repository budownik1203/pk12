extends RefCounted
## Okno zdrowia (H) rysowane wewnątrz okna ekwipunku: sylwetka z 17 częściami
## ciała (widok z przodu: prawa strona postaci po lewej stronie ekranu),
## szczegóły wybranej części (rany, opatrunki, ubranie, które ją chroni) i stan
## ogólny. Przeciągnięcie przedmiotu medycznego z ekwipunku na część ciała
## zaczyna opatrywanie; prawy przycisk na części zdejmuje opatrunek albo szynę.

const W := 660.0
const H := 590.0
const FIG := Vector2(24, 46)        # sylwetka względem panelu
const DETAIL_X := 300.0

## prostokąty części ciała w sylwetce 240 × 450 (lewa strona ekranu = prawa strona postaci)
const SHAPES := {
	"glowa": Rect2(100, 0, 40, 46), "szyja": Rect2(108, 47, 24, 13),
	"klatka": Rect2(78, 61, 84, 78), "brzuch": Rect2(82, 140, 76, 55), "miednica": Rect2(80, 196, 80, 40),
	"ramie_p": Rect2(48, 63, 28, 74), "przedramie_p": Rect2(42, 138, 27, 70), "dlon_p": Rect2(38, 209, 26, 32),
	"udo_p": Rect2(82, 237, 37, 96), "lydka_p": Rect2(85, 334, 32, 94), "stopa_p": Rect2(80, 429, 38, 21),
}

var ui                               # inventory_ui.gd (Control, na którym rysujemy)
var health
var origin := Vector2.ZERO
var seg_rects := {}
var selected := "klatka"
var hovered := ""


func _init(owner_ui, health_node) -> void:
	ui = owner_ui
	health = health_node


func layout(at: Vector2) -> Rect2:
	origin = at
	seg_rects.clear()
	for id in SHAPES:
		var r: Rect2 = SHAPES[id]
		seg_rects[id] = Rect2(origin + FIG + r.position, r.size)
		if id.ends_with("_p"):
			# lustro dla lewej strony postaci (prawa strona ekranu)
			var lid: String = id.trim_suffix("_p") + "_l"
			seg_rects[lid] = Rect2(origin + FIG + Vector2(240.0 - r.position.x - r.size.x, r.position.y), r.size)
	return Rect2(origin, Vector2(W, H))


func segment_at(p: Vector2) -> String:
	for id in seg_rects:
		if (seg_rects[id] as Rect2).grow(2.0).has_point(p):
			return id
	return ""


func _color_for(id: String) -> Color:
	var hp: float = health.segment_hp(id)
	var c := Color(0.3, 0.36, 0.29).lerp(Color(0.78, 0.18, 0.13), 1.0 - hp / 100.0)
	if health.segments[id]["wounds"].is_empty():
		c = Color(0.26, 0.3, 0.25)
	return c


func draw(drag_item) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	ui._text(origin + Vector2(0, 22), ui.tr("HP_TITLE"), 17, ui.C_ACCENT)
	# sylwetka
	for id in seg_rects:
		var r: Rect2 = seg_rects[id]
		ui.draw_rect(r, _color_for(id))
		var bleeding := false
		var dressed := ""
		var dirt := 0.0
		var splint := false
		var fracture := false
		var infected := false
		for w in health.segments[id]["wounds"]:
			if health.wound_bleed(w) > 0.005:
				bleeding = true
			if w["bandage"] != "":
				dressed = w["bandage"]
				dirt = maxf(dirt, float(w["dirt"]))
			if w["splint"]:
				splint = true
			if w["type"] == "zlamanie":
				fracture = true
			if float(w["infection"]) > 0.15:
				infected = true
		if dressed != "":
			var bc := Color(0.92, 0.9, 0.84).lerp(Color(0.55, 0.3, 0.22), dirt)
			ui.draw_rect(r.grow(-3.0), bc, false, 3.0)
		if fracture:
			ui.draw_line(r.position + Vector2(3, 3), r.end - Vector2(3, 3), Color(0.92, 0.92, 0.95), 2.0)
		if splint:
			ui.draw_rect(Rect2(r.position + Vector2(r.size.x * 0.4, 1), Vector2(r.size.x * 0.2, r.size.y - 2)), Color(0.6, 0.5, 0.35))
		if infected:
			ui.draw_circle(r.get_center(), 4.0, Color(0.6, 0.85, 0.35))
		if bleeding:
			var a := 0.55 + 0.45 * sin(t * 6.0)
			ui.draw_rect(r.grow(1.0), Color(1.0, 0.15, 0.1, a), false, 2.0)
		else:
			ui.draw_rect(r, ui.C_LINE, false, 1.0)
		if drag_item != null and r.has_point(ui.mouse):
			var ok: bool = not health.treatment_for(drag_item, id).has("error")
			ui.draw_rect(r, ui.C_OK if ok else ui.C_BAD)
		if id == selected:
			ui.draw_rect(r.grow(3.0), ui.C_ACCENT, false, 2.0)
	ui._text(origin + FIG + Vector2(30, 14), ui.tr("HP_SIDE_RIGHT"), 12, ui.C_DIM)
	ui._text(origin + FIG + Vector2(176, 14), ui.tr("HP_SIDE_LEFT"), 12, ui.C_DIM)
	_draw_detail()
	_draw_summary()


func _draw_detail() -> void:
	var x := origin.x + DETAIL_X
	var y := origin.y + 52.0
	var id := hovered if hovered != "" else selected
	ui._text(Vector2(x, y), ui.tr("SEG_" + id), 18, ui.C_TEXT)
	y += 24
	ui._text(Vector2(x, y), ui.tr("HP_SEG_STATE") % health.segment_hp(id), 14, ui.C_DIM)
	y += 26
	var wounds: Array = health.segments[id]["wounds"]
	if wounds.is_empty():
		ui._text(Vector2(x, y), ui.tr("HP_NO_WOUNDS"), 15, ui.C_DIM)
		y += 24
	for w in wounds:
		var sev: float = w["sev"]
		var sev_key := "HP_SEV_LIGHT" if sev < 0.45 else ("HP_SEV_MED" if sev < 0.75 else "HP_SEV_HEAVY")
		ui._text(Vector2(x, y), "%s (%s)" % [ui.tr("WOUND_" + w["type"]), ui.tr(sev_key)], 15, Color(0.95, 0.75, 0.65))
		y += 19
		var notes: PackedStringArray = []
		var b: float = health.wound_bleed(w)
		if b > 0.15:
			notes.append(ui.tr("HP_N_BLEED_HEAVY"))
		elif b > 0.005:
			notes.append(ui.tr("HP_N_BLEED"))
		if w["bandage"] != "":
			notes.append(ui.tr("HP_N_DRESSED") % [ui.tr("HP_DRESS_" + w["bandage"]), int(float(w["dirt"]) * 100.0)])
		if w["disinfected"]:
			notes.append(ui.tr("HP_N_CLEAN"))
		if w["stitched"]:
			notes.append(ui.tr("HP_N_STITCHED"))
		if w["type"] == "gleboka_rana" and not w["stitched"]:
			notes.append(ui.tr("HP_N_NEEDS_STITCH"))
		if w["type"] == "zlamanie":
			notes.append(ui.tr("HP_N_SPLINT") if w["splint"] else ui.tr("HP_N_NEEDS_SPLINT"))
		if float(w["infection"]) > 0.05:
			notes.append(ui.tr("HP_N_INFECTED") % int(float(w["infection"]) * 100.0))
		notes.append(ui.tr("HP_N_HEAL") % int(float(w["heal"]) * 100.0))
		for n in notes:
			ui._text(Vector2(x + 12, y), "· " + n, 13, ui.C_DIM, 330.0)
			y += 17
		y += 6
		if y > origin.y + H - 150:
			break
	y += 6
	var cover: Array = health.covering(id)
	if not cover.is_empty():
		ui._text(Vector2(x, y), ui.tr("HP_COVERED"), 14, ui.C_ACCENT)
		y += 19
		for it in cover:
			var p: Dictionary = it.get_def().get("protection", {})
			ui._text(Vector2(x + 12, y), ui.tr("HP_PROT_LINE") % [it.display_name(), int(float(p.get("cut", 0.0)) * 100.0),
					int(float(p.get("bite", 0.0)) * 100.0), int(float(p.get("blunt", 0.0)) * 100.0)], 13, ui.C_DIM, 340.0)
			y += 17
			var blood: float = float(it.props.get("blood", 0.0))
			if blood > 0.05:
				ui._text(Vector2(x + 24, y), ui.tr("HP_BLOODY") % int(blood * 100.0), 12, Color(0.8, 0.45, 0.4))
				y += 16


func _draw_summary() -> void:
	var y := origin.y + H - 88.0
	var x := origin.x + 4.0
	ui.draw_line(Vector2(x, y - 22), Vector2(origin.x + W - 20, y - 22), ui.C_LINE, 1.0)
	ui._text(Vector2(x, y), ui.tr("HP_SUMMARY") % [health.overall(), health.blood, health.pain,
			int(health.max_infection() * 100.0)], 15, ui.C_TEXT)
	y += 20
	var nd = health.main.needs
	ui._text(Vector2(x, y), ui.tr("HP_NEEDS") % [nd.hunger, nd.thirst, nd.fatigue, nd.body_temp], 14, ui.C_DIM)
	y += 22
	if not health.action.is_empty():
		var label: String = ui.tr("HP_ACT_" + str(health.action["kind"]).to_upper())
		ui._text(Vector2(x, y), label, 14, ui.C_ACCENT)
		ui.draw_rect(Rect2(x + 180, y - 11, 220, 10), Color(0, 0, 0, 0.6))
		ui.draw_rect(Rect2(x + 182, y - 9, 216.0 * health.action_ratio(), 6), ui.C_ACCENT)
	else:
		ui._text(Vector2(x, y), ui.tr("HP_HINT"), 13, ui.C_DIM, W - 30)
