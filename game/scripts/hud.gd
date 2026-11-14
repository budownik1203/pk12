extends CanvasLayer
## Interfejs w pełnej rozdzielczości ekranu: celownik zmieniający się w dłoń,
## pasek wytrzymałości, podpowiedzi klawiszy, komunikaty, ekran deweloperski.

const ICON_SCALE := 3

const HAND_OPEN := [
	"..#.#.#....",
	"..#.#.#.#..",
	"..#.#.#.#..",
	"..#.#.#.#..",
	"#.#######..",
	"#.#######..",
	"#########..",
	"#########..",
	".########..",
	".#######...",
	"..######...",
	"..#####....",
]
const HAND_FIST := [
	"...........",
	"...........",
	"...........",
	"..#.#.#.#..",
	".########..",
	"#########..",
	"#########..",
	"#########..",
	".########..",
	".#######...",
	"..######...",
	"..#####....",
]

var hints: Label
var message: Label
var dev: Label
var _dot: ColorRect
var _icon: TextureRect
var _key: Label
var _stamina_back: ColorRect
var _stamina_fill: ColorRect
var _textures := {}
var _cursor := ""
var _message_time := 0.0
var _work_label: Label
var _mode_label: Label
var _work_back: ColorRect
var _work_fill: ColorRect


func _init() -> void:
	layer = 10
	hints = _label(20)
	hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hints.modulate = Color(1, 1, 1, 0.7)

	message = _label(30)
	message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 60)
	message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.visible = false

	dev = _label(20)
	dev.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 24)

	# celownik: kropka, dłoń otwarta, dłoń zaciśnięta
	var center := Control.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_dot = ColorRect.new()
	_dot.color = Color(1, 1, 1, 0.55)
	_dot.size = Vector2(4, 4)
	_dot.position = Vector2(-2, -2)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_dot)

	_textures["hand"] = _pixel_icon(HAND_OPEN)
	_textures["fist"] = _pixel_icon(HAND_FIST)
	_icon = TextureRect.new()
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.stretch_mode = TextureRect.STRETCH_SCALE
	_icon.size = Vector2(13, 14) * ICON_SCALE
	_icon.position = -_icon.size / 2.0
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.visible = false
	center.add_child(_icon)

	_key = _label(22)
	_key.position = Vector2(26, 6)
	_key.visible = false
	remove_child(_key)
	center.add_child(_key)

	# pasek wytrzymałości: widoczny tylko, gdy nie jest pełny
	var bottom := Control.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	_stamina_back = ColorRect.new()
	_stamina_back.color = Color(0, 0, 0, 0.55)
	_stamina_back.size = Vector2(244, 10)
	_stamina_back.position = Vector2(-122, -46)
	bottom.add_child(_stamina_back)
	_stamina_fill = ColorRect.new()
	_stamina_fill.color = Color(0.82, 0.78, 0.62, 0.9)
	_stamina_fill.size = Vector2(240, 6)
	_stamina_fill.position = Vector2(2, 2)
	_stamina_back.add_child(_stamina_fill)
	_stamina_back.visible = false

	# podpowiedź i postęp pracy narzędziem pod celownikiem
	_work_label = _label(19)
	_work_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_work_label.size = Vector2(700, 30)
	remove_child(_work_label)
	center.add_child(_work_label)
	_work_label.position = Vector2(-350, 30)
	# tryb rąk (walka) nad celownikiem
	_mode_label = _label(15)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label.size = Vector2(300, 24)
	_mode_label.modulate = Color(1.0, 0.55, 0.45)
	remove_child(_mode_label)
	center.add_child(_mode_label)
	_mode_label.position = Vector2(-150, -44)
	_mode_label.visible = false
	_work_back = ColorRect.new()
	_work_back.color = Color(0, 0, 0, 0.6)
	_work_back.size = Vector2(160, 8)
	_work_back.position = Vector2(-80, 64)
	center.add_child(_work_back)
	_work_fill = ColorRect.new()
	_work_fill.color = Color(0.85, 0.72, 0.4, 0.95)
	_work_fill.size = Vector2(0, 4)
	_work_fill.position = Vector2(2, 2)
	_work_back.add_child(_work_fill)
	_work_back.visible = false

	set_cursor("dot")


func _label(font_size: int) -> Label:
	var l := Label.new()
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.92, 0.9, 0.84))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## Ikona z mapy znaków: biały kształt z ciemnym obrysem o grubości 1 piksela.
func _pixel_icon(rows: Array) -> ImageTexture:
	var h := rows.size()
	var w: int = rows[0].length()
	var img := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			if rows[y][x] == "#":
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if img.get_pixel(x + 1 + dx, y + 1 + dy).a < 0.5:
							img.set_pixel(x + 1 + dx, y + 1 + dy, Color(0, 0, 0, 0.75))
	for y in h:
		for x in w:
			if rows[y][x] == "#":
				img.set_pixel(x + 1, y + 1, Color(0.95, 0.93, 0.86, 1.0))
	return ImageTexture.create_from_image(img)


## state: "dot", "hand" (można chwycić), "fist" (trzymasz), "use" (można użyć),
## "item" (przedmiot: T chwyt, F podniesienie do ekwipunku)
func set_cursor(state: String) -> void:
	if state == _cursor:
		return
	_cursor = state
	_dot.visible = state == "dot" or state == "use"
	_icon.visible = state == "hand" or state == "fist" or state == "item" or state == "hand_idle"
	if _icon.visible:
		_icon.texture = _textures["hand" if state == "item" or state == "hand_idle" else state]
		_icon.modulate.a = 0.35 if state == "hand_idle" else 1.0
	_key.visible = state == "hand" or state == "use" or state == "item"
	if state == "hand":
		_key.text = tr("KEY_GRAB")
	elif state == "item":
		_key.text = "T · F"
	elif state == "use":
		_key.text = "F"


## Podpowiedź pracy (pusty tekst ukrywa) i postęp 0..1 (ujemny: bez paska).
func set_work(text: String, ratio: float) -> void:
	_work_label.text = text
	_work_label.visible = text != ""
	_work_back.visible = ratio >= 0.0
	_work_fill.size.x = 156.0 * clampf(ratio, 0.0, 1.0)


func set_mode(text: String) -> void:
	_mode_label.text = text
	_mode_label.visible = text != ""


func work_text() -> String:
	return _work_label.text


func cursor_state() -> String:
	return _cursor


func set_stamina(value: float, max_value: float, exhausted: bool) -> void:
	var ratio := clampf(value / max_value, 0.0, 1.0)
	_stamina_back.visible = ratio < 0.995
	_stamina_fill.size.x = 240.0 * ratio
	_stamina_fill.color = Color(0.72, 0.3, 0.24, 0.9) if exhausted else Color(0.82, 0.78, 0.62, 0.9)


func refresh_static() -> void:
	hints.text = tr("HINTS")


func show_message(text: String) -> void:
	message.text = text
	message.visible = true
	_message_time = 2.2


func set_dev_text(text: String) -> void:
	dev.text = text


func _process(delta: float) -> void:
	if _message_time > 0.0:
		_message_time -= delta
		if _message_time <= 0.0:
			message.visible = false
