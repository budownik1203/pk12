extends RefCounted
## Pracownia: wygląd interfejsu (ciemny warsztat, bursztynowy akcent) i małe klocki
## do budowy paneli: nagłówki, suwaki z polem liczby, przyciski, siatki próbek.

const BG := Color(0.085, 0.085, 0.09)
const PANEL := Color(0.115, 0.113, 0.118, 0.97)
const PANEL_2 := Color(0.15, 0.147, 0.152)
const LINE := Color(0.26, 0.24, 0.21)
const TEXT := Color(0.86, 0.84, 0.8)
const DIM := Color(0.56, 0.55, 0.52)
const ACCENT := Color(0.96, 0.68, 0.26)
const ACCENT_DARK := Color(0.42, 0.29, 0.1)
const BLUE := Color(0.38, 0.62, 0.95)
const RED := Color(0.92, 0.33, 0.28)
const GREEN := Color(0.45, 0.8, 0.4)

static var _theme: Theme


static func box(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 4, pad: float = 6.0, bw: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 14
	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 6, 10))
	t.set_stylebox("panel", "Panel", box(PANEL, LINE, 6, 10))
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var bg := PANEL_2
		var bd := LINE
		match st:
			"hover": bg = PANEL_2.lightened(0.08); bd = ACCENT_DARK
			"pressed": bg = ACCENT_DARK; bd = ACCENT
			"disabled": bg = PANEL_2.darkened(0.3)
			"focus": bg = Color(0, 0, 0, 0); bd = ACCENT_DARK
		t.set_stylebox(st, "Button", box(bg, bd, 4, 8))
		t.set_stylebox(st, "OptionButton", box(bg, bd, 4, 8))
		t.set_stylebox(st, "MenuButton", box(bg, bd, 4, 8))
	for k in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(k, "Button", TEXT)
		t.set_color(k, "OptionButton", TEXT)
		t.set_color(k, "CheckBox", TEXT)
		t.set_color(k, "Label", TEXT)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_stylebox("normal", "LineEdit", box(BG, LINE, 4, 6))
	t.set_stylebox("focus", "LineEdit", box(BG, ACCENT_DARK, 4, 6))
	t.set_stylebox("slider", "HSlider", _track(Color(0.05, 0.05, 0.055), 2))
	t.set_stylebox("grabber_area", "HSlider", _track(ACCENT_DARK.lightened(0.15), 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", _track(ACCENT.darkened(0.25), 2))
	t.set_icon("grabber", "HSlider", _dot(10, ACCENT))
	t.set_icon("grabber_highlight", "HSlider", _dot(12, ACCENT.lightened(0.2)))
	t.set_stylebox("panel", "Tree", box(BG, LINE, 4, 4))
	t.set_stylebox("panel", "ItemList", box(BG, LINE, 4, 4))
	t.set_stylebox("selected", "Tree", box(ACCENT_DARK, ACCENT, 3, 2))
	t.set_stylebox("selected_focus", "Tree", box(ACCENT_DARK, ACCENT, 3, 2))
	t.set_stylebox("selected", "ItemList", box(ACCENT_DARK, ACCENT, 3, 2))
	t.set_stylebox("selected_focus", "ItemList", box(ACCENT_DARK, ACCENT, 3, 2))
	t.set_color("font_color", "Tree", TEXT)
	t.set_color("font_color", "ItemList", TEXT)
	t.set_stylebox("panel", "PopupMenu", box(PANEL, LINE, 4, 6))
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.05, 0.05, 0.05, 0.95), ACCENT_DARK, 4, 8))
	t.set_stylebox("normal", "SpinBox", box(BG, LINE, 4, 4))
	t.set_stylebox("scroll", "VScrollBar", box(BG, Color(0, 0, 0, 0), 3, 0))
	t.set_stylebox("grabber", "VScrollBar", box(LINE, Color(0, 0, 0, 0), 3, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(ACCENT_DARK, Color(0, 0, 0, 0), 3, 0))
	t.set_constant("separation", "VBoxContainer", 5)
	t.set_constant("separation", "HBoxContainer", 5)
	_theme = t
	return t


static func _track(c: Color, h: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(2)
	s.content_margin_top = h
	s.content_margin_bottom = h
	return s


static func _dot(size: int, c: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(c, clampf(r - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func header(parent: Control, text: String, big: bool = false) -> Label:
	var l := Label.new()
	l.text = text.to_upper() if not big else text
	l.add_theme_color_override("font_color", ACCENT if not big else TEXT)
	l.add_theme_font_size_override("font_size", 12 if not big else 19)
	parent.add_child(l)
	if not big:
		var sep := ColorRect.new()
		sep.color = LINE
		sep.custom_minimum_size = Vector2(0, 1)
		parent.add_child(sep)
	return l


static func hint(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", DIM)
	l.add_theme_font_size_override("font_size", 12)
	parent.add_child(l)
	return l


static func button(parent: Control, text: String, cb: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


static func row(parent: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	parent.add_child(h)
	return h


static func grow(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if c is Button:
		(c as Button).clip_text = true
		c.custom_minimum_size.x = maxf(c.custom_minimum_size.x, 30.0)
	return c


static func fmt(v: float, unit: String) -> String:
	match unit:
		"m": return "%.1f mm" % (v * 1000.0)
		"deg": return "%.1f°" % v
		"n": return "%d" % int(round(v))
		"%": return "%d%%" % int(round(v * 100.0))
	return "%.2f" % v


## Suwak z etykietą, wartością i polem do wpisania liczby. cb(v) przy każdej zmianie.
## Wpis w polu przyjmuje mm dla jednostki "m". Zwraca słownik {slider, set(v)}.
static func slider(parent: Control, label: String, mn: float, mx: float, value: float, cb: Callable, unit: String = "", step: float = 0.0, tip: String = "") -> HSlider:
	var box_v := VBoxContainer.new()
	box_v.add_theme_constant_override("separation", 1)
	parent.add_child(box_v)
	var top := HBoxContainer.new()
	box_v.add_child(top)
	var l := Label.new()
	l.text = label
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.add_theme_font_size_override("font_size", 13)
	l.clip_text = true
	grow(l)
	top.add_child(l)
	var ed := LineEdit.new()
	ed.custom_minimum_size = Vector2(78, 0)
	ed.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ed.add_theme_font_size_override("font_size", 12)
	ed.add_theme_stylebox_override("normal", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 3, 2))
	top.add_child(ed)
	var s := HSlider.new()
	s.min_value = minf(mn, value)
	s.max_value = maxf(mx, value)
	if unit == "n":
		s.step = 1.0
	else:
		s.step = step if step > 0.0 else (mx - mn) / 1000.0
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.tooltip_text = tip
	box_v.add_child(s)
	ed.text = fmt(value, unit)
	s.value_changed.connect(func(v): ed.text = fmt(v, unit); cb.call(v))
	ed.text_submitted.connect(func(t):
		var num: float = t.replace(",", ".").replace("mm", "").replace("°", "").replace("%", "").strip_edges().to_float()
		if unit == "m":
			num /= 1000.0
		elif unit == "%":
			num /= 100.0
		s.min_value = minf(s.min_value, num)
		s.max_value = maxf(s.max_value, num)
		s.value = num
		ed.release_focus())
	return s


static func option(parent: Control, items: Array, selected_key: String, cb: Callable, labels: Dictionary = {}) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for k in items:
		o.add_item(str(labels.get(k, k)))
		o.set_item_metadata(o.item_count - 1, k)
		if str(k) == selected_key:
			o.select(o.item_count - 1)
	o.item_selected.connect(func(i): cb.call(o.get_item_metadata(i)))
	parent.add_child(o)
	return o


static func check(parent: Control, text: String, on: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(cb)
	parent.add_child(c)
	return c


static func scroll_panel(parent: Control) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var v := VBoxContainer.new()
	grow(v)
	sc.add_child(v)
	return v


static func clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()
