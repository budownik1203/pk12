extends Node
## PSK-12, build 4: narzędzia i montaż w pokoju testowym.
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
const InventoryScript := preload("res://scripts/inventory/inventory.gd")
const WorldItemsScript := preload("res://scripts/world_items.gd")
const InventoryUIScript := preload("res://scripts/ui/inventory_ui.gd")
const WorkScript := preload("res://scripts/work/work_system.gd")
const NoiseScript := preload("res://scripts/noise.gd")
const SoundScript := preload("res://scripts/sound.gd")
const CombatScript := preload("res://scripts/combat.gd")
const HealthScript := preload("res://scripts/health/health.gd")
const NeedsScript := preload("res://scripts/health/needs.gd")
const ClockScript := preload("res://scripts/world/clock.gd")
const HandWorkScript := preload("res://scripts/work/hand_work.gd")
const ZombiesScript := preload("res://scripts/zombie/zombies.gd")
const WeatherScript := preload("res://scripts/world/weather.gd")
const HeatScript := preload("res://scripts/craft/heat.gd")
const SawScript := preload("res://scripts/craft/saw.gd")
const RecorderScript := preload("res://scripts/recorder.gd")
const CharacterScript := preload("res://scripts/character/character.gd")
const CharCreateScript := preload("res://scripts/ui/char_create.gd")
const CharPanelScript := preload("res://scripts/ui/char_panel.gd")
const TownScript := preload("res://scripts/world/town.gd")
const WindowScript := preload("res://scripts/world/window_boards.gd")
const DoorScript := preload("res://scripts/world/door_system.gd")
const POST_SHADER := preload("res://shaders/retro_post.gdshader")
const Psx := preload("res://scripts/psx.gd")

## Warianty stylu PS1 (build 4.2): bez szumu na ekranie. Wygląd robi geometria
## (psx.gd: wierzchołki przyciągane do siatki pikseli, tekstury bez korekcji
## perspektywy) oraz nieruchomy dithering z kolorem 15-bitowym (32 poziomy).
## shrink: ile razy mniejsza jest rozdzielczość świata od ekranu (3 = 360 linii
## w Full HD, blisko 240 linii PS1 na monitorze 720p). snap: rozmiar oczka siatki
## wierzchołków w pikselach świata. affine: 0 tekstury poprawne, 1 jak na PS1.
const STYLES := [
	{"key": "STYLE_SOFT", "shrink": 2, "snap": 1.5, "affine": 0.35, "levels": 32.0, "dither": 0.45, "vignette": 0.2, "on": true},
	{"key": "STYLE_CLEAR", "shrink": 3, "snap": 1.0, "affine": 0.8, "levels": 32.0, "dither": 0.8, "vignette": 0.25, "on": true},
	{"key": "STYLE_RAW", "shrink": 4, "snap": 1.0, "affine": 1.0, "levels": 16.0, "dither": 1.0, "vignette": 0.35, "on": true},
	{"key": "STYLE_OFF", "shrink": 1, "snap": 0.0, "affine": 0.0, "levels": 256.0, "dither": 0.0, "vignette": 0.0, "on": false},
]
const DEFAULT_STYLE := 0

var container: SubViewportContainer
var viewport: SubViewport
var world: Node3D
var player: PlayerScript
var interaction: InteractionScript
var hud: HudScript
var inventory: InventoryScript
var world_items: WorldItemsScript
var inv_ui: InventoryUIScript
var work: WorkScript
var noise: NoiseScript
var sound: SoundScript
var combat: CombatScript
var health: HealthScript
var needs: NeedsScript
var clock: ClockScript
var sink: StaticBody3D
var zombies: ZombiesScript
var weather: WeatherScript
var heat: HeatScript
var creating_character := false  # ekran tworzenia postaci: kursor wolny
var saw: SawScript
var recorder: RecorderScript
var character: CharacterScript
var char_panel: CharPanelScript
var town: TownScript
var _flash := 0.0
var _stream_time := 0.0
var window_boards: WindowScript
var door_sys: DoorScript
var bodies: Array = []
var switches := {}
var style_index := DEFAULT_STYLE
var dev_visible := true
var _post: ShaderMaterial


func _ready() -> void:
	Controls.register()
	Lang.setup()
	Psx.init()
	get_tree().node_added.connect(Psx.on_node_added)
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

	character = CharacterScript.new()
	character.name = "Postac"
	add_child(character)
	character.setup(self)
	player.set_view(deg_to_rad(-35.0), deg_to_rad(-8.0))

	hud = HudScript.new()
	add_child(hud)
	hud.refresh_static()
	set_style(style_index, false)

	interaction = InteractionScript.new()
	interaction.name = "Interakcja"
	add_child(interaction)
	interaction.setup(self)

	world_items = WorldItemsScript.new()
	world_items.name = "PrzedmiotyWSwiecie"
	add_child(world_items)
	world_items.setup(world)
	world_items.on_removed = func(b): if interaction.held == b: interaction.release()

	sound = SoundScript.new()
	sound.name = "Dzwiek"
	add_child(sound)
	sound.setup(self)
	noise = NoiseScript.new()
	noise.name = "Halas"
	noise.sound = sound
	add_child(noise)

	work = WorkScript.new()
	work.name = "PracaNarzedziem"
	add_child(work)
	work.setup(self)

	combat = CombatScript.new()
	combat.name = "Walka"
	add_child(combat)
	combat.setup(self)

	window_boards = WindowScript.new()
	window_boards.name = "OknoZDeskami"
	world.add_child(window_boards)
	window_boards.position = RoomBuilder.window_center()
	window_boards.setup(self, work)

	door_sys = DoorScript.new()
	door_sys.name = "Drzwi"
	add_child(door_sys)
	for b in bodies:
		if b.name == "drzwi_komorka":
			door_sys.setup(self, work, b, RoomBuilder.door_jamb())

	inventory = InventoryScript.new()
	inventory.name = "Ekwipunek"
	add_child(inventory)
	inventory.setup(self)
	for id in room["containers"]:
		inventory.register_container(id, [[6, 6]], room["containers"][id])
	inventory.load_start()

	# ulica i domy (ziarno świata z piaskownicy: ten sam świat po śmierci i wczytaniu)
	town = TownScript.new()
	town.name = "Miasto"
	add_child(town)
	var sandbox_seed := 1203
	var sf := FileAccess.open("res://data/sandbox.json", FileAccess.READ)
	if sf != null:
		sandbox_seed = int(JSON.parse_string(sf.get_as_text()).get("world_seed", 1203))
	town.setup(self, sandbox_seed)
	town.fill_loot()

	health = HealthScript.new()
	health.name = "Zdrowie"
	add_child(health)
	health.setup(self)
	health.died.connect(_on_died)

	clock = ClockScript.new()
	clock.name = "Zegar"
	add_child(clock)
	clock.setup(world)
	needs = NeedsScript.new()
	needs.name = "Potrzeby"
	add_child(needs)
	needs.setup(self)
	sink = room["sink"]
	var hand_work := HandWorkScript.new()
	hand_work.setup(self)
	work.hand_work = hand_work
	zombies = ZombiesScript.new()
	zombies.name = "Zombie"
	add_child(zombies)
	zombies.setup(self)
	weather = WeatherScript.new()
	weather.name = "Pogoda"
	add_child(weather)
	weather.setup(self)
	clock.weather = weather
	heat = HeatScript.new()
	heat.name = "Ogien"
	add_child(heat)
	heat.setup(self)
	recorder = RecorderScript.new()
	recorder.name = "Nagrywanie"
	recorder.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(recorder)
	recorder.setup(self)
	saw = SawScript.new()
	saw.name = "Pila"
	add_child(saw)
	saw.setup(self)
	var dev_run := false
	for a in OS.get_cmdline_user_args():
		if a == "--test" or a.begins_with("--zrzuty"):
			dev_run = true
	if not dev_run:
		_show_char_create()  # zombie pojawią się po rozpoczęciu (mapa nawigacji stoi w pauzie)
	else:
		# testy i zrzuty: postać umiejąca to, czego wymagają sprawdzane czynności
		character.create("Test", "bezrobotny", [])
		character.levels["majsterkowanie"] = 3
		character.levels["pierwsza_pomoc"] = 3
	player.health = health

	char_panel = CharPanelScript.new()
	char_panel.name = "OknoPostaci"
	hud.add_child(char_panel)
	char_panel.setup(self)

	inv_ui = InventoryUIScript.new()
	inv_ui.name = "OknoEkwipunku"
	hud.add_child(inv_ui)
	inv_ui.setup(inventory)
	inv_ui.main = self

	var args := OS.get_cmdline_user_args()
	var shots := false
	for a in args:
		if a.begins_with("--zrzuty="):
			shots = true
	if "--test" in args:
		DevTests.run_tests(self)
	elif shots:
		DevTests.take_screenshots(self, args)
	elif not creating_character:
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
	Psx.set_style(s["snap"], s["affine"])
	_post.set_shader_parameter("vignette", s["vignette"])
	if announce:
		hud.show_message(tr("MSG_STYLE") % tr(s["key"]))


## Wywoływane przez system interakcji, gdy gracz użyje obiektu (F).
func use_object(target: Object) -> void:
	if target.has_meta("switch_id"):
		var id: String = target.get_meta("switch_id")
		set_switch(id, not switches[id]["on"])
		sound.play("switch", interaction.focus_point(), -8.0)
	elif target.has_meta("door_sys"):
		target.get_meta("door_sys").on_use(interaction.focus_point())
	elif target.has_meta("glass"):
		target.get_meta("glass").clear_shards()
	elif target.has_meta("sink"):
		use_sink()
	elif target.has_meta("bed"):
		needs.try_sleep(float(target.get_meta("bed")))
	elif target.has_meta("container_id"):
		open_inventory(target.get_meta("container_id"))
	elif target.has_meta("fire"):
		_feed_fire(target.get_meta("fire"))
	elif target.has_meta("item") and _use_world_item(target):
		pass
	elif target.has_meta("item"):
		var at: Vector3 = (target as Node3D).global_position
		if not inventory.pick_up(target):
			hud.show_message(tr(inventory.last_error))
		else:
			sound.play("pickup", at, -6.0)


## F na przedmiocie w świecie, zanim zostanie podniesiony: kuchenka (włącz,
## Shift+F podnosi), drewno z zapalniczką w ręce (rozpalenie). Zwraca, czy obsłużone.
func _use_world_item(body) -> bool:
	var it = body.get_meta("item")
	var d: Dictionary = it.get_def()
	if d.has("appliance") and not Input.is_key_pressed(KEY_SHIFT):
		var on := not bool(it.props.get("on", false))
		if on and float(it.props.get("gas", float(d["appliance"].get("gas", 240.0)))) <= 0.0:
			hud.show_message(tr("MSG_STOVE_EMPTY"))
			return true
		it.props["on"] = on
		heat._stove_flame(body, on)
		sound.play("switch", body.global_position, -6.0, 0.8)
		hud.show_message(tr("MSG_STOVE_ON" if on else "MSG_STOVE_OFF"))
		return true
	if d.has("fuel") and heat.has_lighter() != null:
		return heat.try_ignite(body)
	return false


## F na ognisku: dokłada drewno (jedną sztukę) z ręki.
func _feed_fire(fire) -> void:
	for side in ["r", "l"]:
		var it = inventory.hand(side)
		if it == null:
			continue
		var f := float(it.get_def().get("fuel", 0.0))
		if f <= 0.0:
			continue
		fire.add_fuel(f)
		hud.show_message(tr("MSG_FUEL_ADDED") % it.display_name())
		if it.count > 1:
			it.count -= 1
			inventory.changed.emit()
		else:
			inventory.take_hand(side)
		sound.play("place", fire.global_position, -6.0, 0.8)
		return
	hud.show_message(tr("MSG_NOT_FUEL"))


## Puszcza wszystko, co trzymają przyciski myszy (praca, garda), gdy puszczenie
## przycisku nie dotrze do gry: otwarte okno, przełączenie na inny program.
func release_mouse_holds() -> void:
	work.end()
	if combat != null:
		combat.blocking = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and work != null:
		release_mouse_holds()


func open_inventory(container_id: String = "", with_health: bool = false) -> void:
	interaction.release()
	release_mouse_holds()
	inv_ui.health_open = with_health and container_id == ""
	inv_ui.open(container_id)
	hud.hints.visible = false
	hud.dev.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_inventory() -> void:
	inv_ui.close()
	hud.hints.visible = true
	hud.dev.visible = dev_visible
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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


func _update_health_hud() -> void:
	var m: Array = []
	var bleed := health.bleed_rate()
	if bleed > 0.15:
		m.append([tr("MOOD_BLEED_HEAVY"), Color(1.0, 0.3, 0.25)])
	elif bleed > 0.005:
		m.append([tr("MOOD_BLEED"), Color(0.95, 0.45, 0.35)])
	if health.blood < 85.0:
		m.append([tr("MOOD_BLOOD") % health.blood, Color(0.9, 0.6, 0.55)])
	if health.pain > 15.0:
		m.append([tr("MOOD_PAIN_HEAVY" if health.pain > 55.0 else "MOOD_PAIN"), Color(0.95, 0.75, 0.4)])
	for id in health.LEGS + health.ARM_L + health.ARM_R + ["klatka", "glowa"]:
		if health.has_wound(id, "zlamanie"):
			m.append([tr("MOOD_FRACTURE"), Color(0.85, 0.85, 0.9)])
			break
	if health.max_infection() > 0.15:
		m.append([tr("MOOD_INFECTION"), Color(0.6, 0.85, 0.4)])
	var lv := func(v: float, keys: Array, col: Color) -> void:
		if v > 85.0:
			m.append([tr(keys[2]), col])
		elif v > 60.0:
			m.append([tr(keys[1]), col])
		elif v > 35.0:
			m.append([tr(keys[0]), col.lerp(Color(0.8, 0.8, 0.8), 0.4)])
	lv.call(needs.hunger, ["MOOD_HUNGRY", "MOOD_VERY_HUNGRY", "MOOD_STARVING"], Color(0.95, 0.7, 0.45))
	lv.call(needs.thirst, ["MOOD_THIRSTY", "MOOD_VERY_THIRSTY", "MOOD_DEHYDRATED"], Color(0.5, 0.75, 0.95))
	lv.call(needs.fatigue, ["MOOD_TIRED", "MOOD_VERY_TIRED", "MOOD_EXHAUSTED"], Color(0.75, 0.7, 0.9))
	if needs.body_temp < 35.5:
		m.append([tr("MOOD_HYPOTHERMIA"), Color(0.5, 0.7, 1.0)])
	elif needs.body_temp < 36.4:
		m.append([tr("MOOD_COLD"), Color(0.65, 0.8, 1.0)])
	elif needs.body_temp > 37.8:
		m.append([tr("MOOD_HOT"), Color(1.0, 0.6, 0.4)])
	var wet: float = weather.clothes_wet()
	if wet > 0.6:
		m.append([tr("MOOD_SOAKED"), Color(0.55, 0.7, 0.95)])
	elif wet > 0.2:
		m.append([tr("MOOD_WET"), Color(0.65, 0.78, 0.95)])
	if needs.poison > 0.1:
		m.append([tr("MOOD_POISON"), Color(0.6, 0.8, 0.3)])
	match health.knox_stage():
		1:
			m.append([tr("MOOD_QUEASY"), Color(0.7, 0.8, 0.5)])
		2, 3:
			m.append([tr("MOOD_FEVER"), Color(0.95, 0.5, 0.4)])
	hud.set_health(health.overall(), m)
	if not health.action.is_empty():
		hud.set_treatment("%s %d%%" % [tr("HP_ACT_" + str(health.action["kind"]).to_upper()), int(health.action_ratio() * 100.0)])
	else:
		hud.set_treatment("")


## Zlew: napełnia pojemnik z ręki, a z pustymi rękami pije się z kranu.
func use_sink() -> void:
	var it = inventory.hand("r")
	if it == null or not it.get_def().has("liquid_capacity"):
		it = inventory.hand("l")
	_stream_time = 1.4
	sound.play("water", sink.global_position + Vector3(0, 0.6, 0), -6.0)
	if it != null and it.get_def().has("liquid_capacity"):
		var cap := float(it.get_def()["liquid_capacity"])
		it.liquid = {"type": "woda", "amount": cap}
		inventory.changed.emit()
		hud.show_message(tr("MSG_FILLED") % it.display_name())
	elif needs.thirst > 3.0:
		needs.drink_water(0.3)
		hud.show_message(tr("MSG_DRANK_TAP"))
	else:
		hud.show_message(tr("MSG_NOT_THIRSTY"))


## Ekran tworzenia postaci: świat stoi, dopóki gracz nie kliknie „Rozpocznij”.
func _show_char_create() -> void:
	var cc := CharCreateScript.new()
	cc.name = "TworzeniePostaci"
	hud.add_child(cc)
	cc.setup(self)
	get_tree().paused = true
	creating_character = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cc.finished.connect(func():
		creating_character = false
		get_tree().paused = false
		zombies.start_population()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		hud.show_message(tr("MSG_WELCOME") % (character.char_name if character.char_name != "" else tr("CC_DEFAULT_NAME"))))


## Poziom światła przy graczu (0 ciemno, 1 jasno): lampy, dzień przy oknie, latarka.
func light_level() -> float:
	var pp: Vector3 = player.global_position
	var light := 0.15
	if not town.in_start_house(pp) and town.indoors(pp):
		light = 0.15 + clock.daylight() * 0.3 * (1.0 - weather.cloud * 0.4)  # cudzy dom: ciemno, tylko okna
	elif zombies.zone_of(pp) == "in":
		if pp.x < zombies.door_wall_x and switches.get("lampa_sala", {}).get("on", false):
			light = 1.0
		elif pp.x >= zombies.door_wall_x and switches.get("lampa_komorka", {}).get("on", false):
			light = 1.0
		if pp.z > 1.5:
			light = maxf(light, clock.daylight() * 0.8 * (1.0 - weather.cloud * 0.4))
	else:
		light = maxf(light, clock.daylight() * (1.0 - weather.cloud * 0.4))
	if player.lamp.visible:
		light = maxf(light, 0.75)
	if heat != null:
		light = maxf(light, heat.light_at(pp))
	return light


## Krótki czerwony błysk przy trafieniu przez zombie.
func set_hurt_flash() -> void:
	_flash = 1.0


## Ciemnienie i odbarwienie obrazu przy utracie krwi, drżenie przy bólu.
func set_hurt_effect(dim: float, pain_level: float) -> void:
	_post.set_shader_parameter("hurt", dim)
	_flash = maxf(0.0, _flash - get_process_delta_time() * 3.0)
	_post.set_shader_parameter("pain", maxf(pain_level, _flash * 1.3))
	var shake := maxf(0.0, pain_level - 0.45) * 0.006
	player.camera.h_offset = randf_range(-shake, shake)
	player.camera.v_offset = randf_range(-shake, shake)


func _on_died() -> void:
	player.controls_locked = true
	interaction.release()
	work.end()
	if combat.active:
		combat.toggle()
	if inv_ui.is_open():
		close_inventory()
	hud.show_death(true)


## Po wczytaniu zapisu z żywą postacią odblokowuje sterowanie.
func revive_if_needed() -> void:
	if not health.dead:
		player.controls_locked = false
		hud.show_death(false)


func awake_body_count() -> int:
	var n := 0
	for b in bodies + world_items.bodies:
		if is_instance_valid(b) and not b.sleeping and not b.freeze:
			n += 1
	return n


func _input(event: InputEvent) -> void:
	if health != null and health.dead:
		get_viewport().set_input_as_handled()  # przed przeładowaniem sceny: potem węzła już nie ma w drzewie
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_ENTER:
				get_tree().reload_current_scene()  # nowy ocalały (permadeath: świat zostanie od buildu świata)
			elif event.physical_keycode == KEY_F9:
				load_game()
		return
	if needs != null and needs.sleeping:
		if event is InputEventKey and event.pressed and not event.echo:
			needs.wake()  # każdy klawisz budzi
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.is_action("inventory"):
		if inv_ui.is_open():
			close_inventory()
		else:
			open_inventory()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.is_action("health"):
		# H: okno zdrowia (razem z ekwipunkiem, żeby przeciągać opatrunki na ciało)
		if inv_ui.is_open() and inv_ui.health_open:
			close_inventory()
		elif inv_ui.is_open():
			inv_ui.health_open = true
			inv_ui.open_container = ""
			inv_ui.open()
		else:
			open_inventory("", true)
		get_viewport().set_input_as_handled()
		return
	if inv_ui.is_open():
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			close_inventory()
			get_viewport().set_input_as_handled()
		return  # resztę obsługuje okno ekwipunku; ruch postaci działa dalej
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion:
		if captured:
			if work.is_locked():
				work.mouse(event.relative)  # trzymany przycisk pracy: mysz prowadzi narzędzie
			else:
				player.look(event.relative)
	elif event is InputEventMouseButton:
		if captured and event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				combat.toggle()  # kółko: tryb walki
			return
		if combat.active and captured:
			if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
				if event.pressed:
					combat.press(event.button_index)
				else:
					combat.release(event.button_index)
			return
		if interaction.grab_mode and captured:
			_grab_mode_button(event)
			return
		if not event.pressed:
			if event.button_index == MOUSE_BUTTON_RIGHT:
				work.release("r")
			elif event.button_index == MOUSE_BUTTON_LEFT:
				work.release("l")
			return
		if not event.pressed:
			return
		if not captured:
			if not creating_character:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if interaction.held == null:
				work.press("r")  # prawa ręka
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if interaction.held != null:
				interaction.throw_held()
			else:
				work.press("l")  # lewa ręka
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if work.is_active():
				work.wheel(-1.0)
			else:
				interaction.adjust_distance(0.08)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if work.is_active():
				work.wheel(1.0)
			else:
				interaction.adjust_distance(-0.08)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.is_action("grab"):
			work.end()
			if combat.active:
				combat.toggle()
			interaction.toggle_grab_mode()
		elif event.physical_keycode == KEY_Z:
			if not inventory.toggle_two_hands():
				hud.show_message(tr(inventory.last_error))
		elif event.is_action("interact"):
			interaction.use()
		elif event.is_action("flashlight"):
			player.toggle_flashlight()
		elif event.is_action("drop_hand"):
			var it = inventory.hand("l" if event.shift_pressed else "r")
			if it == null or not inventory.move_to_world(it):
				hud.show_message(tr(inventory.last_error if it != null else "INV_ERR_HAND_EMPTY"))
		elif event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
			if not inventory.use_hotkey(event.physical_keycode - KEY_0):
				hud.show_message(tr(inventory.last_error))
		else:
			_dev_key(event.physical_keycode)


## Tryb chwytania (T): lewy przycisk chwyta i trzyma, prawy rzuca, kółko odsuwa.
func _grab_mode_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				interaction.grab_press()
			else:
				interaction.release()
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				interaction.throw_held()
		MOUSE_BUTTON_WHEEL_UP:
			interaction.adjust_distance(0.08)
		MOUSE_BUTTON_WHEEL_DOWN:
			interaction.adjust_distance(-0.08)


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
		KEY_C:
			char_panel.toggle()
		KEY_KP_DIVIDE:
			var kinds := weather.KINDS.keys()
			weather.set_kind(kinds[(kinds.find(weather.kind) + 1) % kinds.size()], true)
			hud.show_message(tr("MSG_DEV_WEATHER") % weather.text())
		KEY_KP_ADD:
			zombies.spawn(zombies.random_point("out", RandomNumberGenerator.new()))
			hud.show_message(tr("MSG_DEV_ZOMBIE"))
		KEY_KP_SUBTRACT:
			zombies.clear_all()
			hud.show_message(tr("MSG_DEV_NO_ZOMBIES"))
		KEY_F7:
			if Input.is_key_pressed(KEY_SHIFT):
				needs.hunger = 0.0
				needs.thirst = 0.0
				needs.fatigue = 0.0
				needs.body_temp = 37.0
				needs.damage = 0.0
			else:
				clock.advance(60.0)
			hud.show_message(clock.text())
		KEY_F8:
			if Input.is_key_pressed(KEY_SHIFT):
				health.heal_all()
				hud.show_message(tr("MSG_DEV_HEALED"))
			else:
				health.random_wound()
				hud.show_message(tr("MSG_DEV_WOUND"))
		KEY_KP_0:
			work.show_bars = not work.show_bars
			hud.show_message(tr("MSG_BARS_ON" if work.show_bars else "MSG_BARS_OFF"))
		KEY_O:
			work.highlights = not work.highlights
			hud.show_message(tr("MSG_HIGHLIGHT_ON" if work.highlights else "MSG_HIGHLIGHT_OFF"))
		KEY_F10:
			dev_visible = not dev_visible
			hud.dev.visible = dev_visible
		KEY_F11:
			var w := get_window()
			w.mode = Window.MODE_WINDOWED if w.mode != Window.MODE_WINDOWED else Window.MODE_FULLSCREEN
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	player.load_factor = inventory.speed_factor()
	player.load_stamina = inventory.stamina_factor()
	player.hand_items = {"l": inventory.hand("l"), "r": inventory.hand("r"), "two": inventory.hands_two()}
	hud.set_stamina(player.stamina, player.STAMINA_MAX, player.exhausted)
	_update_health_hud()
	hud.set_clock("%s · %s %.0f °C" % [clock.text(), weather.text(), clock.outside_temp()])
	if _stream_time > 0.0:
		_stream_time -= _delta
	sink.get_node("Strumien").visible = _stream_time > 0.0
	if not dev_visible:
		return
	var lines := PackedStringArray()
	lines.append(tr("DEV_BUILD"))
	lines.append(tr("DEV_FPS") % int(Engine.get_frames_per_second()))
	lines.append(tr("DEV_RES") % [viewport.size.x, viewport.size.y])
	lines.append(tr("DEV_BODIES") % [awake_body_count(), bodies.size()])
	lines.append(tr("DEV_STYLE") % tr(STYLES[style_index]["key"]))
	lines.append(tr("DEV_STAMINA") % int(player.stamina))
	lines.append(tr("DEV_MASS") % [inventory.carried_mass(), inventory.felt_mass(), int(round(inventory.speed_factor() * 100.0))])
	lines.append(tr("DEV_RATTLE") % inventory.rattle_count())
	lines.append(tr("DEV_ZOMBIES") % [zombies.alive_count(), zombies.kills])
	lines.append(tr("DEV_NEEDS") % [needs.hunger, needs.thirst, needs.fatigue, needs.body_temp, needs.felt_temp()])
	var act: Dictionary = inventory.current_action()
	if not act.is_empty():
		lines.append(tr("DEV_ACTION") % [act["item"].display_name(), act["duration"] - act["time"]])
	var last_noise: Dictionary = noise.last()
	if not last_noise.is_empty():
		lines.append(tr("DEV_NOISE") % [tr(last_noise["label"]), last_noise["loud"]])
	if interaction.held != null and is_instance_valid(interaction.held):
		lines.append(tr("DEV_HELD") % [interaction.held.name, interaction.held.mass])
	var ver: Dictionary = Engine.get_version_info()
	var physics := str(ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	lines.append(tr("DEV_ENGINE") % ["%d.%d.%d" % [ver["major"], ver["minor"], ver["patch"]], physics])
	hud.set_dev_text("\n".join(lines))
