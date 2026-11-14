extends CanvasLayer
## Interfejs builda 1 w pełnej rozdzielczości ekranu: podpowiedzi klawiszy,
## komunikaty, celownik-kropka i ekran deweloperski.

var hints: Label
var message: Label
var dev: Label
var _message_time := 0.0


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
	dev.visible = true

	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.55)
	dot.custom_minimum_size = Vector2(4, 4)
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)


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
