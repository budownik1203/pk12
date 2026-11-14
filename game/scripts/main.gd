extends Node
## PSK-12, build 2a: ruch i chwyt w pokoju testowym.
## Świat renderuje się w niskiej rozdzielczości w SubViewporcie i jest
## powiększany bez wygładzania; interfejs rysuje się osobno, w pełnej
## rozdzielczości ekranu.

const PlayerScript := preload("res://scripts/player.gd")
const InteractionScript := preload("res://scripts/interaction.gd")
const RoomBuilder := preload("res://scripts/room_builder.gd")
const SaveGame := preload("res://scripts/save_game.gd")
const Lang := preload("res://scripts/lang.gd")
const Controls := preload("res://scripts/controls.gd")
const HudScript := preload("res://scripts/hud.gd")
const DevTests := preload("res://scripts/dev_tests.gd")
const POST_SHADER := preload("res://shaders/retro_post.gdshader")

## Warianty stylu. Wybrany 14.11.2026: łagodny (indeks 0); pozostałe zostają
## pod F2 do F4 do porównań. shrink: ile razy mniejsza jest rozdzielczość
## świata od ekranu (2 = 540 linii w Full HD, 3 = 360 linii).
const STYLES := [
	{"key": "STYLE_SOFT", "shrink": 2, "levels": 48.0, "dither": 0.35, "grain": 0.05, "vignette": 0.25, "on": true},
	{"key": "STYLE_CLEAR", "shrink": 2, "levels": 32.0, "dither": 0.65, "grain": 0.11, "vignette": 0.38, "on": true},
	{"key": "STYLE_RAW", "shrink": 3, "levels": 16.0, "dither": 1.0, "grain": 0.2, "vignette": 0.5, "on": true},
	{"key": "STYLE_OFF", "shrink": 1, "levels": 256.0, "dither": 0.0, "grain": 0.0, "vignette": 0.0, "on": false},
]
const DEFAULT_STYLE := 0

var container: SubViewportContainer
var viewport: SubViewport
var world: Node3D
var player: PlayerScript
var interaction: InteractionScript
var hud: HudScript
var bodies: Array = []
var switches := {}
var style_index := DEFAULT_STYLE
var dev_visible := true
var _post: ShaderMaterial


func _ready() -> void:
	Controls.register()
	Lang.setup()
	_build_view()

	world = Node3D.new()
	world.name = "Swiat"
	viewport.add_child(world)
	var room: Dictionary = RoomBuilder.build(world)
	bodies = room["bodies"]
	switches = room["switches"]

	player = PlayerScript.new()
	player.name = "Gracz"
	player.position = Vector3(-1.0, 0.02, 2.6)
	world.add_child(player)
	player.set_view(deg_to_rad(-35.0), deg_to_rad(-8.0))

	hud = HudScript.new()
	add_child(hud)
	hud.refresh_static()
	set_style(style_index, false)

	interaction = InteractionScript.new()
	interaction.name = "Interakcja"
	add_child(interaction)
	interaction.setup(self)

	var args := OS.get_cmdline_user_args()
	var shots := false
	for a in args:
		if a.begins_with("--zrzuty="):
			shots = true
	if "--test" in args:
		DevTests.run_tests(self)
	elif shots:
		DevTests.take_screenshots(self, args)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_view() -> void:
	container = SubViewportContainer.new()
	container.name = "WidokSwiata"
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post = ShaderMaterial.new()
	_post.shader = POST_SHADER
	container.material = _post
	add_child(container)

	viewport = SubViewport.new()
	viewport.name = "Swiat3D"
	viewport.handle_input_locally = false
	viewport.audio_listener_enable_3d = true
	container.add_child(viewport)


func set_style(index: int, announce: bool = true) -> void:
	style_index = clampi(index, 0, STYLES.size() - 1)
	var s: Dictionary = STYLES[style_index]
	container.stretch_shrink = s["shrink"]
	_post.set_shader_parameter("enabled", s["on"])
	_post.set_shader_parameter("levels", s["levels"])
	_post.set_shader_parameter("dither_amount", s["dither"])
	_post.set_shader_parameter("grain", s["grain"])
	_post.set_shader_parameter("vignette", s["vignette"])
	if announce:
		hud.show_message(tr("MSG_STYLE") % tr(s["key"]))


## Wywoływane przez system interakcji, gdy gracz użyje obiektu (F).
func use_object(target: Object) -> void:
	if target.has_meta("switch_id"):
		var id: String = target.get_meta("switch_id")
		set_switch(id, not switches[id]["on"])


func set_switch(id: String, on: bool) -> void:
	if not switches.has(id):
		return
	switches[id]["on"] = on
	RoomBuilder.apply_switch(switches[id])


func save_game() -> void:
	if SaveGame.save(self):
		hud.show_message(tr("MSG_SAVED"))


func load_game() -> void:
	match SaveGame.load_into(self):
		SaveGame.Result.OK:
			hud.refresh_static()
			hud.show_message(tr("MSG_LOADED"))
		SaveGame.Result.NO_FILE:
			hud.show_message(tr("MSG_NO_SAVE"))
		_:
			hud.show_message(tr("MSG_BAD_SAVE"))


func awake_body_count() -> int:
	var n := 0
	for b in bodies:
		if not b.sleeping:
			n += 1
	return n


func _input(event: InputEvent) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion:
		if captured:
			player.look(event.relative)
	elif event is InputEventMouseButton:
		if not event.pressed:
			return
		if not captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			interaction.throw_held()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			interaction.adjust_distance(0.08)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			interaction.adjust_distance(-0.08)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.is_action("grab"):
			interaction.toggle_grab()
		elif event.is_action("interact"):
			interaction.use()
		elif event.is_action("flashlight"):
			player.toggle_flashlight()
		else:
			_dev_key(event.physical_keycode)


func _dev_key(key: int) -> void:
	match key:
		KEY_F1: set_style(0)
		KEY_F2: set_style(1)
		KEY_F3: set_style(2)
		KEY_F4: set_style(3)
		KEY_F5: save_game()
		KEY_F9: load_game()
		KEY_F6:
			Lang.toggle()
			hud.refresh_static()
			hud.show_message(tr("MSG_LANG"))
		KEY_F10:
			dev_visible = not dev_visible
			hud.dev.visible = dev_visible
		KEY_F11:
			var w := get_window()
			w.mode = Window.MODE_WINDOWED if w.mode != Window.MODE_WINDOWED else Window.MODE_FULLSCREEN
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	hud.set_stamina(player.stamina, player.STAMINA_MAX, player.exhausted)
	if not dev_visible:
		return
	var lines := PackedStringArray()
	lines.append(tr("DEV_BUILD"))
	lines.append(tr("DEV_FPS") % int(Engine.get_frames_per_second()))
	lines.append(tr("DEV_RES") % [viewport.size.x, viewport.size.y])
	lines.append(tr("DEV_BODIES") % [awake_body_count(), bodies.size()])
	lines.append(tr("DEV_STYLE") % tr(STYLES[style_index]["key"]))
	lines.append(tr("DEV_STAMINA") % int(player.stamina))
	if interaction.held != null and is_instance_valid(interaction.held):
		lines.append(tr("DEV_HELD") % [interaction.held.name, interaction.held.mass])
	var ver: Dictionary = Engine.get_version_info()
	var physics := str(ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	lines.append(tr("DEV_ENGINE") % ["%d.%d.%d" % [ver["major"], ver["minor"], ver["patch"]], physics])
	hud.set_dev_text("\n".join(lines))
