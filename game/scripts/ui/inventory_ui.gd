extends Control
## Okno ekwipunku (Tab). Rysowane w pełnej rozdzielczości, bez zatrzymywania gry.
##   lewa kolumna: sloty na ciele,
##   środek: siatki założonych pojemników (kieszenie, kamizelka, pas, plecak),
##   prawa kolumna: otwarty pojemnik świata (szafka) i otwarte pojemniki
##   zagnieżdżone (dwuklik na apteczce),
##   dół: masa niesiona i odczuwana, trwająca czynność.
## Przeciąganie lewym przyciskiem, R obraca, Ctrl przy chwycie dzieli stos,
## upuszczenie poza oknami wyrzuca przedmiot na ziemię, klawisz 1–9 nad
## przedmiotem w kamizelce albo pasie przypisuje skrót.

const ItemDB := preload("res://scripts/inventory/item_db.gd")
const HealthPanel := preload("res://scripts/ui/health_panel.gd")

const CELL := 44
const TOP := 64
const SLOT_X := 40
const SLOT_W := 250
const SLOT_H := 50
const WORN_X := 330
const OPEN_X := 1220
const COL_GAP := 30
const HEADER_H := 26
const BLOCK_GAP := 16

const C_BG := Color(0.03, 0.035, 0.04, 0.78)
const C_PANEL := Color(0.1, 0.105, 0.1, 0.92)
const C_CELL := Color(0.16, 0.165, 0.155, 1.0)
const C_LINE := Color(0.27, 0.27, 0.25, 1.0)
const C_TEXT := Color(0.9, 0.88, 0.82)
const C_DIM := Color(0.6, 0.59, 0.55)
const C_OK := Color(0.45, 0.7, 0.4, 0.55)
const C_BAD := Color(0.75, 0.25, 0.2, 0.55)
const C_ACCENT := Color(0.85, 0.72, 0.4)

const CATEGORY_COLORS := {
	"narzedzie": Color(0.36, 0.3, 0.22),
	"bron": Color(0.25, 0.25, 0.28),
	"amunicja": Color(0.42, 0.36, 0.18),
	"material": Color(0.3, 0.31, 0.32),
	"medyczne": Color(0.45, 0.2, 0.19),
	"jedzenie": Color(0.3, 0.36, 0.22),
	"pojemnik": Color(0.24, 0.28, 0.22),
	"odziez": Color(0.22, 0.25, 0.3),
}

var inv                         # inventory.gd
var main                        # main.gd (dźwięk przekładania, zdrowie)
var health_open := false        # okno zdrowia (H) zamiast otwartych pojemników
var hp_panel                    # health_panel.gd
var font: Font
var blocks: Array = []          # {"grid", "rect": Rect2}
var headers: Array = []         # {"pos": Vector2, "text": String, "close": Rect2, "item"}
var slot_rects := {}
var panels: Array = []          # obszary okien (upuszczenie poza nimi = na ziemię)
var open_items: Array = []      # otwarte pojemniki zagnieżdżone
var open_container := ""        # otwarty pojemnik świata

var drag_item = null
var drag_rot := 0
var drag_grab := Vector2i.ZERO
var drag_split := false
var hover_item = null
var mouse := Vector2.ZERO
var message := ""
var _message_time := 0.0
var _last_click_item = null
var _last_click_time := 0.0


func setup(inventory) -> void:
	inv = inventory
	font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	visible = false
	inv.changed.connect(_on_changed)


func is_open() -> bool:
	return visible


func open(container_id: String = "") -> void:
	open_container = container_id
	if container_id != "":
		health_open = false
	visible = true
	_layout()
	queue_redraw()


func close() -> void:
	drag_item = null
	visible = false
	health_open = false
	open_items.clear()
	open_container = ""


func show_message(text: String) -> void:
	message = text
	_message_time = 2.5
	queue_redraw()


func _on_changed() -> void:
	# zamknij widoki pojemników, których już nie mamy przy sobie
	for it in open_items.duplicate():
		if it.parent_grid == null and it.slot == "":
			open_items.erase(it)
	if visible:
		_layout()
		queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	if _message_time > 0.0:
		_message_time -= delta
	if open_container != "" and inv.containers.has(open_container):
		if not inv._in_reach(inv.containers[open_container]["node"]):
			open_container = ""
			_layout()
	queue_redraw()  # paski postępu czynności


# --- układ ------------------------------------------------------------------------

func _layout() -> void:
	blocks.clear()
	headers.clear()
	slot_rects.clear()
	panels.clear()
	var bottom_limit := size.y - 120.0

	var y := float(TOP + 36)
	# ręce w jednym wierszu: lewa, oburącz, prawa
	var rows: int = inv.SLOT_ORDER.size() - 2
	var slot_h := clampf((size.y - 44.0 - y) / rows - 4.0, 40.0, SLOT_H)
	var third := (SLOT_W - 8.0) / 3.0
	for s in inv.SLOT_ORDER:
		if s == inv.LEFT_HAND:
			slot_rects[s] = Rect2(SLOT_X, y, third, slot_h)
			continue
		if s == inv.TWO_HANDS:
			slot_rects[s] = Rect2(SLOT_X + third + 4.0, y, third, slot_h)
			continue
		if s == inv.HAND:
			slot_rects[s] = Rect2(SLOT_X + (third + 4.0) * 2.0, y, third, slot_h)
		else:
			slot_rects[s] = Rect2(SLOT_X, y, SLOT_W, slot_h)
		y += slot_h + 4
	panels.append(Rect2(SLOT_X - 12, TOP, SLOT_W + 24, y - TOP + 6))

	var col_x := float(WORN_X)
	var col_right := col_x
	y = TOP + 36
	for s in inv.GRID_SLOTS:
		if not inv.slots.has(s):
			continue
		var it = inv.slots[s]
		var block_w := 0.0
		var block_h := 0.0
		for g in it.grids:
			block_w += g.w * CELL + 10
			block_h = maxf(block_h, g.h * CELL)
		if y + HEADER_H + block_h > bottom_limit and y > TOP + 40:
			col_x = col_right + COL_GAP
			y = TOP + 36
		var title: String = it.display_name()
		if it.reduction() > 0.0:
			title += "  −%d%%" % int(round(it.reduction() * 100.0))
		headers.append({"pos": Vector2(col_x, y + 17), "text": title, "item": it, "close": Rect2()})
		var gx := col_x
		for g in it.grids:
			blocks.append({"grid": g, "rect": Rect2(gx, y + HEADER_H, g.w * CELL, g.h * CELL)})
			gx += g.w * CELL + 10
		col_right = maxf(col_right, col_x + block_w)
		y += HEADER_H + block_h + BLOCK_GAP
	panels.append(Rect2(WORN_X - 12, TOP, maxf(col_right - WORN_X + 14, 300), bottom_limit - TOP))

	if health_open and main != null and main.health != null:
		if hp_panel == null:
			hp_panel = HealthPanel.new(self, main.health)
		panels.append(hp_panel.layout(Vector2(minf(OPEN_X, size.x - HealthPanel.W - 12.0), TOP)).grow(8.0))
		return
	var ox := float(OPEN_X)
	y = TOP + 36
	if open_container != "" and inv.containers.has(open_container):
		headers.append({"pos": Vector2(ox, y + 17), "text": tr("INV_CONTAINER_" + open_container), "item": null,
				"close": Rect2(ox + 610, y, 22, 22), "container": open_container})
		var gx := ox
		var gh := 0.0
		for g in inv.containers[open_container]["grids"]:
			blocks.append({"grid": g, "rect": Rect2(gx, y + HEADER_H, g.w * CELL, g.h * CELL)})
			gx += g.w * CELL + 10
			gh = maxf(gh, g.h * CELL)
		y += HEADER_H + gh + BLOCK_GAP
	for it in open_items:
		headers.append({"pos": Vector2(ox, y + 17), "text": it.display_name(), "item": it,
				"close": Rect2(ox + 610, y, 22, 22)})
		var gx := ox
		var gh := 0.0
		for g in it.grids:
			blocks.append({"grid": g, "rect": Rect2(gx, y + HEADER_H, g.w * CELL, g.h * CELL)})
			gx += g.w * CELL + 10
			gh = maxf(gh, g.h * CELL)
		y += HEADER_H + gh + BLOCK_GAP
	if open_container != "" or not open_items.is_empty():
		panels.append(Rect2(OPEN_X - 12, TOP, 660, maxf(y - TOP, 120)))


# --- trafianie myszą ---------------------------------------------------------------

func cell_at(p: Vector2) -> Dictionary:
	for b in blocks:
		var r: Rect2 = b["rect"]
		if r.has_point(p):
			var c := Vector2i(floori((p.x - r.position.x) / CELL), floori((p.y - r.position.y) / CELL))
			return {"grid": b["grid"], "cell": c}
	return {}


func slot_at(p: Vector2) -> String:
	for s in slot_rects:
		if slot_rects[s].has_point(p):
			return s
	return ""


func item_at(p: Vector2):
	var hit := cell_at(p)
	if not hit.is_empty():
		var it = hit["grid"].item_at(hit["cell"])
		if it != null and hit["grid"].items.has(it):
			return it
		return null
	var s := slot_at(p)
	if s != "":
		return inv.slots.get(s)
	return null


func over_panel(p: Vector2) -> bool:
	for r in panels:
		if r.has_point(p):
			return true
	return false


## Środek komórki siatki na ekranie (do testów i podpowiedzi).
func cell_center(grid, cell: Vector2i) -> Vector2:
	for b in blocks:
		if b["grid"] == grid:
			var r: Rect2 = b["rect"]
			return r.position + Vector2(cell.x + 0.5, cell.y + 0.5) * CELL
	return Vector2(-1, -1)


# --- wejście -----------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse = event.position
		hover_item = item_at(mouse)
		if health_open and hp_panel != null:
			hp_panel.hovered = hp_panel.segment_at(mouse)
		queue_redraw()
	elif event is InputEventMouseButton:
		mouse = event.position
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_press(mouse, event.ctrl_pressed)
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if drag_item != null:
				drop_at(mouse)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if drag_item == null and health_open and hp_panel != null and hp_panel.segment_at(mouse) != "":
				main.health.remove_dressing(hp_panel.segment_at(mouse))
			drag_item = null
		accept_event()
		queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R and drag_item != null:
			drag_rot = posmod(drag_rot + 1, 4)
			drag_grab = Vector2i.ZERO
			accept_event()
		elif event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9 and hover_item != null:
			if not inv.set_hotkey(event.physical_keycode - KEY_0, hover_item):
				show_message(tr(inv.last_error))
			accept_event()
		queue_redraw()


func _press(p: Vector2, ctrl: bool) -> void:
	if health_open and hp_panel != null and hp_panel.segment_at(p) != "":
		hp_panel.selected = hp_panel.segment_at(p)
		return
	for h in headers:
		var r: Rect2 = h["close"]
		if r.size.x > 0 and r.has_point(p):
			if h.get("container", "") != "":
				open_container = ""
			else:
				open_items.erase(h["item"])
			_layout()
			return
	var it = item_at(p)
	if it == null or it.pending:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if it == _last_click_item and now - _last_click_time < 0.35 and it.is_container() and it.slot == "":
		if not open_items.has(it):
			open_items.append(it)
		_last_click_item = null
		_layout()
		return
	_last_click_item = it
	_last_click_time = now
	begin_drag(it, ctrl and it.count > 1)
	var hit := cell_at(p)
	if not hit.is_empty() and it.parent_grid == hit["grid"]:
		drag_grab = hit["cell"] - it.pos


func begin_drag(it, split: bool = false) -> void:
	drag_item = it
	drag_rot = it.rot
	drag_grab = Vector2i.ZERO
	drag_split = split


## Upuszczenie przeciąganego przedmiotu w punkcie ekranu.
func drop_at(p: Vector2) -> bool:
	var it = drag_item
	drag_item = null
	if health_open and hp_panel != null and hp_panel.segment_at(p) != "":
		# przedmiot medyczny upuszczony na część ciała: opatrywanie
		hp_panel.selected = hp_panel.segment_at(p)
		return main.health.treat(it, hp_panel.selected)
	if it == null:
		return false
	var ok := false
	var hit := cell_at(p)
	if not hit.is_empty():
		var g = hit["grid"]
		var target = g.item_at(hit["cell"])
		var pos: Vector2i = hit["cell"] - drag_grab
		if target != null and target != it and target.def_id == it.def_id and it.max_stack() > 1 and g.items.has(target):
			ok = inv.merge_into(it, target)
		elif drag_split:
			ok = inv.split_to_grid(it, it.count / 2, g, pos, drag_rot)
		else:
			ok = inv.move_to_grid(it, g, pos, drag_rot)
	else:
		var s := slot_at(p)
		if s != "":
			ok = inv.move_to_slot(it, s)
		elif not over_panel(p):
			ok = inv.move_to_world(it)
		else:
			return false
	if not ok:
		show_message(tr(inv.last_error))
	elif main != null and main.get("sound") != null:
		main.sound.play_ui("inv")
	return ok


# --- rysowanie ---------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	for r in panels:
		draw_rect(r, C_PANEL)
	_text(Vector2(SLOT_X, TOP + 22), tr("INV_TITLE_BODY"), 17, C_ACCENT)
	_text(Vector2(WORN_X, TOP + 22), tr("INV_TITLE_WORN"), 17, C_ACCENT)
	if open_container != "" or not open_items.is_empty():
		_text(Vector2(OPEN_X, TOP + 22), tr("INV_TITLE_OPEN"), 17, C_ACCENT)

	for s in slot_rects:
		_draw_slot(s, slot_rects[s])
	for h in headers:
		_text(h["pos"], h["text"], 15, C_DIM)
		var cr: Rect2 = h["close"]
		if cr.size.x > 0:
			draw_rect(cr, C_LINE, false, 1.0)
			_text(cr.position + Vector2(6, 17), "×", 16, C_TEXT)
	for b in blocks:
		_draw_grid(b["grid"], b["rect"])

	if health_open and hp_panel != null:
		hp_panel.draw(drag_item)
	_draw_ghost()
	_draw_footer()
	if hover_item != null and drag_item == null:
		_draw_tooltip(hover_item)
	if _message_time > 0.0 and message != "":
		var w := font.get_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		var mp := Vector2((size.x - w) / 2.0, size.y - 128)
		draw_rect(Rect2(mp - Vector2(12, 24), Vector2(w + 24, 34)), Color(0.35, 0.1, 0.08, 0.9))
		_text(mp, message, 20, C_TEXT)


func _text(p: Vector2, t: String, sz: int, col: Color, width: float = -1.0) -> void:
	draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, width, sz, col)


func _draw_slot(s: String, r: Rect2) -> void:
	var it = inv.slots.get(s)
	var reserved: bool = inv.slot_reserved.has(s)
	var bg := C_CELL
	if drag_item != null and r.has_point(mouse):
		bg = C_OK if inv.slot_accepts(drag_item, s) and not inv.slots.has(s) else C_BAD
	draw_rect(r, bg)
	draw_rect(r, C_LINE, false, 1.0)
	_text(r.position + Vector2(8, 17), ItemDB.slot_name(s), 13, C_DIM)
	if it != null:
		var col: Color = C_TEXT if not it.pending else C_DIM
		var nm: String = it.display_name() if r.size.x > 120.0 else ItemDB.short_name_of(it.def_id)
		if it.count > 1:
			nm += " ×%d" % it.count
		_text(r.position + Vector2(8, r.size.y - 9), nm, 16 if r.size.x > 120.0 else 13, col, r.size.x - 12)
	elif reserved:
		_text(r.position + Vector2(8, r.size.y - 9), "…", 16, C_DIM)
	else:
		_text(r.position + Vector2(8, r.size.y - 9), "—", 16, Color(0.4, 0.4, 0.38))


func _draw_grid(g, r: Rect2) -> void:
	for y in g.h:
		for x in g.w:
			var cr := Rect2(r.position + Vector2(x, y) * CELL, Vector2(CELL, CELL))
			draw_rect(cr.grow(-1), C_CELL)
	for res in g.reserved:
		for c in res["item"].cells_for(res["rot"]):
			var cr := Rect2(r.position + Vector2(res["pos"] + c) * CELL, Vector2(CELL, CELL))
			draw_rect(cr.grow(-3), C_ACCENT, false, 1.0)
	for it in g.items:
		if it == drag_item:
			continue
		_draw_item(it, r.position + Vector2(it.pos) * CELL, it.rot, 0.35 if it.pending else 1.0)


func _draw_item(it, origin: Vector2, r: int, alpha: float) -> void:
	var cl: Array = it.cells_for(r)
	var col: Color = CATEGORY_COLORS.get(str(it.get_def().get("category", "")), Color(0.3, 0.3, 0.3))
	col.a = alpha
	var occ := {}
	for c in cl:
		occ[c] = true
	for c in cl:
		var cr := Rect2(origin + Vector2(c) * CELL, Vector2(CELL, CELL))
		draw_rect(cr.grow(-2), col)
	# obrys kształtu: krawędzie komórek bez sąsiada z tego samego przedmiotu
	var edge := Color(0.85, 0.82, 0.72, 0.8 * alpha)
	for c in cl:
		var p := origin + Vector2(c) * CELL
		if not occ.has(c + Vector2i.UP):
			draw_line(p + Vector2(2, 2), p + Vector2(CELL - 2, 2), edge, 1.0)
		if not occ.has(c + Vector2i.DOWN):
			draw_line(p + Vector2(2, CELL - 2), p + Vector2(CELL - 2, CELL - 2), edge, 1.0)
		if not occ.has(c + Vector2i.LEFT):
			draw_line(p + Vector2(2, 2), p + Vector2(2, CELL - 2), edge, 1.0)
		if not occ.has(c + Vector2i.RIGHT):
			draw_line(p + Vector2(CELL - 2, 2), p + Vector2(CELL - 2, CELL - 2), edge, 1.0)
	var b := ItemDB.bounds(cl)
	var first: Vector2i = cl[0]
	var tc := C_TEXT
	tc.a = alpha
	var small: bool = cl.size() <= 2
	var label: String = ItemDB.short_name_of(it.def_id) if small else it.display_name()
	_text(origin + Vector2(first) * CELL + Vector2(4, 14), label, 10 if small else 12, tc, b.x * CELL - 4)
	if it.max_stack() > 1:
		var t: String = "×%d" % it.count
		var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var last: Vector2i = cl[cl.size() - 1]
		_text(origin + Vector2(last + Vector2i.ONE) * CELL - Vector2(tw + 5, 6), t, 13, tc)
	if not it.liquid.is_empty():
		var cap: float = float(it.get_def().get("liquid_capacity", 1.0))
		var ratio: float = clampf(float(it.liquid.get("amount", 0.0)) / cap, 0.0, 1.0)
		var h := b.y * CELL - 10.0
		var base := origin + Vector2(b.x * CELL - 8, 5)
		draw_rect(Rect2(base, Vector2(3, h)), Color(0, 0, 0, 0.5 * alpha))
		draw_rect(Rect2(base + Vector2(0, h * (1.0 - ratio)), Vector2(3, h * ratio)), Color(0.4, 0.6, 0.85, alpha))
	var hk: int = inv.hotkey_of(it)
	if hk > 0:
		_text(origin + Vector2(b.x * CELL - 13, b.y * CELL - 6), str(hk), 13, C_ACCENT)


func _draw_ghost() -> void:
	if drag_item == null:
		return
	_draw_item(drag_item, mouse - Vector2(drag_grab) * CELL - Vector2(CELL, CELL) * 0.5, drag_rot, 0.5)
	var hit := cell_at(mouse)
	if not hit.is_empty():
		var g = hit["grid"]
		var pos: Vector2i = hit["cell"] - drag_grab
		var origin := Vector2(-1, -1)
		for b in blocks:
			if b["grid"] == g:
				origin = (b["rect"] as Rect2).position
		var target = g.item_at(hit["cell"])
		var merge: bool = target != null and target != drag_item and target.def_id == drag_item.def_id \
				and drag_item.max_stack() > 1 and target.count < target.max_stack()
		var ok: bool = merge or inv.can_place_in_grid(drag_item, g, pos, drag_rot)
		for c in drag_item.cells_for(drag_rot):
			var cell: Vector2i = pos + c
			if cell.x < 0 or cell.y < 0 or cell.x >= g.w or cell.y >= g.h:
				continue
			var cr := Rect2(origin + Vector2(cell) * CELL, Vector2(CELL, CELL)).grow(-2)
			draw_rect(cr, C_OK if ok else C_BAD)
			draw_rect(cr, (C_OK if ok else C_BAD).lightened(0.4), false, 2.0)
	if drag_split:
		_text(mouse + Vector2(16, -14), "½", 16, C_ACCENT)
	if hit.is_empty() and slot_at(mouse) == "" and not over_panel(mouse):
		_text(mouse + Vector2(18, 30), tr("INV_DROP_GROUND"), 15, C_ACCENT)


func _draw_footer() -> void:
	var carried: float = inv.carried_mass()
	var felt: float = inv.felt_mass()
	var y := size.y - 70.0
	var x := float(WORN_X)
	var w := 560.0
	_text(Vector2(x, y - 10), tr("INV_MASS") % [carried, felt, inv.COMFORT_MASS], 16, C_TEXT)
	draw_rect(Rect2(x, y, w, 10), Color(0, 0, 0, 0.6))
	var ratio: float = clampf(felt / inv.HEAVY_MASS, 0.0, 1.0)
	var col: Color = Color(0.75, 0.72, 0.55) if felt <= inv.COMFORT_MASS else Color(0.8, 0.4, 0.25)
	draw_rect(Rect2(x, y, w * ratio, 10), col)
	var mark: float = w * inv.COMFORT_MASS / inv.HEAVY_MASS
	draw_line(Vector2(x + mark, y - 3), Vector2(x + mark, y + 13), C_TEXT, 1.0)
	if felt > inv.COMFORT_MASS:
		_text(Vector2(x + w + 16, y + 10), tr("INV_SLOWED") % int(round(inv.speed_factor() * 100.0)), 15, col)

	var a: Dictionary = inv.current_action()
	if not a.is_empty():
		var ax := float(OPEN_X)
		var t: String = tr("INV_ACTION") % [a["item"].display_name(), maxf(0.0, a["duration"] - a["time"])]
		if inv.actions.size() > 1:
			t += "  (+%d)" % (inv.actions.size() - 1)
		_text(Vector2(ax, y - 10), t, 16, C_TEXT)
		draw_rect(Rect2(ax, y, 400, 10), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(ax, y, 400 * clampf(a["time"] / a["duration"], 0.0, 1.0), 10), C_ACCENT)
	_text(Vector2(SLOT_X, size.y - 24), tr("INV_HINTS"), 14, C_DIM)


func _draw_tooltip(it) -> void:
	var lines := PackedStringArray()
	lines.append(it.display_name())
	var m: float = it.total_mass()
	lines.append(tr("INV_TIP_MASS") % m)
	if it.max_stack() > 1:
		lines.append(tr("INV_TIP_COUNT") % [it.count, it.max_stack()])
	if not it.liquid.is_empty():
		lines.append(tr("INV_TIP_LIQUID") % [ItemDB.liquid_name(str(it.liquid.get("type", ""))),
				float(it.liquid.get("amount", 0.0)), float(it.get_def().get("liquid_capacity", 1.0))])
	if it.is_container():
		lines.append(tr("INV_TIP_CONTENTS") % it.contents_mass())
		if it.reduction() > 0.0:
			lines.append(tr("INV_TIP_REDUCTION") % int(round(it.reduction() * 100.0)))
	var desc: String = ItemDB.desc_of(it.def_id)
	if desc != "":
		lines.append(desc)
	var hk: int = inv.hotkey_of(it)
	if hk > 0:
		lines.append(tr("INV_TIP_HOTKEY") % hk)
	var w := 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x)
	var h := lines.size() * 20 + 10
	var p := mouse + Vector2(18, 18)
	if p.x + w + 20 > size.x:
		p.x = mouse.x - w - 30
	if p.y + h > size.y:
		p.y = mouse.y - h - 10
	draw_rect(Rect2(p, Vector2(w + 20, h)), Color(0.05, 0.05, 0.05, 0.95))
	draw_rect(Rect2(p, Vector2(w + 20, h)), C_LINE, false, 1.0)
	for i in lines.size():
		_text(p + Vector2(10, 22 + i * 20), lines[i], 15, C_ACCENT if i == 0 else C_TEXT)
