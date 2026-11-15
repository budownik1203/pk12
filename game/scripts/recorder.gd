extends Node
## Nagrywanie sesji do sprawdzania błędów.
## F12 włącza i wyłącza zapis klatek (co 0,5 s, JPG 960×540) do folderu
## nagrania/<data_godzina>/ obok folderu gry. Do każdej klatki dopisuje linijkę
## w klatki.txt: czas, pozycja i patrzenie gracza, zdrowie, stan walki, liczba
## zombie, FPS. Niezależnie od nagrywania wszystkie błędy i ostrzeżenia silnika
## lądują w nagrania/log_<data>.txt (z godziną).

const INTERVAL := 0.5
const SIZE := Vector2i(960, 540)

var main
var recording := false
var dir_path := ""
var _t := 0.0
var _frame := 0
var _index: FileAccess
var _label: Label
var _logger


## Zapis błędów silnika do pliku (Godot 4.5+: OS.add_logger).
class FileLogger extends Logger:
	var file: FileAccess
	var mutex := Mutex.new()

	func _init(path: String) -> void:
		file = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
		if file != null:
			file.seek_end()
			file.store_line("=== start gry %s ===" % Time.get_datetime_string_from_system(false, true))
			file.flush()

	func _write(text: String) -> void:
		if file == null:
			return
		mutex.lock()
		file.store_line("[%s] %s" % [Time.get_time_string_from_system(), text])
		file.flush()
		mutex.unlock()

	func _log_error(function: String, path: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
		var kind: String = ["BŁĄD", "OSTRZEŻENIE", "BŁĄD SKRYPTU", "SHADER"][clampi(error_type, 0, 3)]
		var msg := rationale if rationale != "" else code
		var where := "%s:%d (%s)" % [path, line, function]
		for bt in script_backtrace:
			if bt != null and not bt.is_empty():
				where += "\n" + bt.format(2)
				break
		_write("%s: %s\n  %s" % [kind, msg, where])

	func _log_message(message: String, error: bool) -> void:
		if error:
			_write("stderr: " + message.strip_edges())


## Folder nagrań: obok folderu gry (repo/nagrania), a w wyeksportowanej grze obok pliku gry.
static func base_dir() -> String:
	var root := ProjectSettings.globalize_path("res://")
	if OS.has_feature("template"):
		root = OS.get_executable_path().get_base_dir()
	return root.trim_suffix("/").get_base_dir().path_join("nagrania")


func setup(main_node) -> void:
	main = main_node
	DirAccess.make_dir_recursive_absolute(base_dir())
	_logger = FileLogger.new(base_dir().path_join("log_%s.txt" % Time.get_date_string_from_system()))
	OS.add_logger(_logger)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_label = Label.new()
	_label.text = "● REC"
	_label.add_theme_color_override("font_color", Color(0.95, 0.2, 0.15))
	_label.add_theme_font_size_override("font_size", 22)
	_label.position = Vector2(20, 14)
	_label.visible = false
	layer.add_child(_label)


func _exit_tree() -> void:
	if _logger != null:
		OS.remove_logger(_logger)
	if recording:
		stop()


## F12 działa wszędzie: w grze, w oknach, na ekranie postaci i po śmierci.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F12:
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if recording:
		stop()
	else:
		start()


func start() -> void:
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	dir_path = base_dir().path_join(stamp)
	DirAccess.make_dir_recursive_absolute(dir_path)
	_index = FileAccess.open(dir_path.path_join("klatki.txt"), FileAccess.WRITE)
	_index.store_line("klatka\tczas_s\tgodzina_gry\tpozycja\tpatrzenie\tzdrowie\twalka\tzombie\tfps")
	_frame = 0
	_t = 0.0
	recording = true
	_label.visible = true
	main.hud.show_message(tr("MSG_REC_START"))
	print("NAGRYWANIE: ", dir_path)


func stop() -> void:
	recording = false
	if _label != null:
		_label.visible = false
	if _index != null:
		_index.close()
		_index = null
	if main != null and main.hud != null:
		main.hud.show_message(tr("MSG_REC_STOP") % _frame)


func _process(delta: float) -> void:
	if not recording:
		return
	_t += delta
	if _t < INTERVAL:
		return
	_t -= INTERVAL
	_capture()


func _capture() -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_BILINEAR)
	_frame += 1
	img.save_jpg(dir_path.path_join("%05d.jpg" % _frame), 0.8)
	var p = main.player
	var look := "%.0f/%.0f" % [rad_to_deg(p.rotation.y), rad_to_deg(p.head.rotation.x)]
	var hp := "%.0f" % main.health.overall()
	var combat := "tak" if main.combat != null and main.combat.active else "nie"
	_index.store_line("%05d\t%.1f\t%s\t%.2f,%.2f,%.2f\t%s\t%s\t%s\t%d\t%d" % [_frame, _frame * INTERVAL,
			main.clock.text(),
			p.global_position.x, p.global_position.y, p.global_position.z, look, hp, combat,
			main.zombies.alive_count(), Engine.get_frames_per_second()])
	_index.flush()
