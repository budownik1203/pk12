extends Node
## Urządzenia stawiane w świecie (pole "device" w items.json). F na urządzeniu
## je obsługuje, Shift+F podnosi.
##   generator: F włącza i wyłącza (potrzebne paliwo), F z kanistrem benzyny
##              w ręce dolewa. Pracujący generator zasila budynek, przy którym
##              stoi (do kilku metrów od ściany), i głośno warczy (zombie słyszą).
##   radio:     F włącza i wyłącza, działa na bateriach; podaje komunikaty
##              zależne od dnia (data/broadcasts.json), potem tylko szum.
##   budzik:    F nastawia (5, 15, 30, 60 minut gry, wyłączony); dzwoni długo
##              i głośno: wabik, który odciąga zombie.
##   czujnik:   czujnik ruchu na baterie; F włącza; piszczy, gdy zombie przejdzie
##              obok, i daje znać, jeśli gracz jest w pobliżu.
## Telewizor (mebel w salonach domów) działa na prąd i pokazuje komunikaty, dopóki
## stacje nadają.

const GEN_REACH := 6.0              # jak daleko od budynku może stać generator
const SENSOR_RANGE := 6.0
const ALARM_STEPS := [0, 5, 15, 30, 60]

var main
var tvs: Array = []                 # {"house", "body", "label", "on"}
var _broad := {}
var _radio_t := 0.0
var _radio_line := 0
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(main_node) -> void:
	main = main_node
	_broad = JSON.parse_string(FileAccess.get_file_as_string("res://data/broadcasts.json"))
	_rng.seed = 4242


static func kind_of(it) -> String:
	return str(it.get_def().get("device", {}).get("kind", ""))


func _devices() -> Array:
	var out: Array = []
	for b in main.world_items.bodies:
		if is_instance_valid(b) and kind_of(b.get_meta("item")) != "":
			out.append(b)
	return out


# --- obsługa F -------------------------------------------------------------------

## F na urządzeniu leżącym w świecie. Zwraca, czy obsłużone.
func use(body) -> bool:
	var it = body.get_meta("item")
	var kind := kind_of(it)
	if kind == "" or Input.is_key_pressed(KEY_SHIFT):
		return false
	match kind:
		"generator":
			_use_generator(body, it)
		"radio", "sensor":
			if not bool(it.props.get("on", false)) and float(it.props.get("battery", it.get_def()["device"].get("battery", 10.0))) <= 0.0:
				main.hud.show_message(tr("MSG_BATTERY_DEAD"))
				return true
			it.props["on"] = not bool(it.props.get("on", false))
			main.sound.play("switch", body.global_position, -6.0)
			main.hud.show_message(tr("MSG_DEVICE_ON" if it.props["on"] else "MSG_DEVICE_OFF") % it.display_name())
			if kind == "radio" and it.props["on"]:
				_radio_t = 1.0
		"alarm_clock":
			var cur := int(it.props.get("set", 0))
			var idx := ALARM_STEPS.find(cur)
			var nxt: int = ALARM_STEPS[(idx + 1) % ALARM_STEPS.size()]
			it.props["set"] = nxt
			it.props["ring_at"] = main.clock.minutes + nxt if nxt > 0 else -1.0
			it.props["ringing"] = 0.0
			main.sound.play("switch", body.global_position, -8.0, 1.6)
			main.hud.show_message(tr("MSG_ALARM_SET") % nxt if nxt > 0 else tr("MSG_ALARM_UNSET"))
	main.inventory.changed.emit()
	return true


func _use_generator(body, it) -> void:
	# kanister z benzyną w ręce: dolewanie
	for side in ["r", "l"]:
		var c = main.inventory.hand(side)
		if c != null and str(c.liquid.get("type", "")) == "benzyna" and float(c.liquid.get("amount", 0.0)) > 0.01:
			var cap := float(it.get_def()["device"].get("tank", 10.0))
			var fuel := float(it.props.get("fuel", 0.0))
			var pour := minf(cap - fuel, float(c.liquid["amount"]))
			if pour <= 0.01:
				main.hud.show_message(tr("MSG_TANK_FULL"))
				return
			it.props["fuel"] = fuel + pour
			c.liquid["amount"] = float(c.liquid["amount"]) - pour
			if float(c.liquid["amount"]) <= 0.01:
				c.liquid = {}
			main.sound.play("water", body.global_position, -8.0, 0.7)
			main.hud.show_message(tr("MSG_FUELED") % pour)
			return
	if not bool(it.props.get("on", false)) and float(it.props.get("fuel", 0.0)) <= 0.0:
		main.hud.show_message(tr("MSG_NO_FUEL"))
		return
	it.props["on"] = not bool(it.props.get("on", false))
	main.sound.play("crank", body.global_position, 0.0)
	main.hud.show_message(tr("MSG_DEVICE_ON" if it.props["on"] else "MSG_DEVICE_OFF") % it.display_name())


## Telewizor: mebel w salonie (town.gd go stawia).
func add_tv(house: int, body: StaticBody3D, screen_pos: Vector3, facing: float) -> void:
	var label := Label3D.new()
	label.font_size = 40
	label.pixel_size = 0.0011
	label.width = 540  # ok. 0,6 m: mieści się na ekranie 0,7 m
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(0.8, 0.9, 1.0)
	label.outline_size = 0
	label.position = screen_pos
	label.rotation.y = facing
	label.visible = false
	body.get_parent().add_child(label)
	body.set_meta("tv", tvs.size())
	tvs.append({"house": house, "body": body, "label": label, "on": false})


func use_tv(idx: int) -> void:
	var tv: Dictionary = tvs[idx]
	tv["on"] = not bool(tv["on"])
	main.sound.play("switch", tv["body"].global_position, -6.0)
	if bool(tv["on"]) and not main.utilities.powered(int(tv["house"])):
		main.hud.show_message(tr("MSG_NO_POWER"))


# --- zasilanie z generatora ------------------------------------------------------

## Czy pracujący generator stoi przy budynku ("start" albo indeks domu).
func generator_powers(building) -> bool:
	var rect: Rect2
	if str(building) == "start":
		rect = main.town.START_RECT
	elif typeof(building) == TYPE_INT and building >= 0 and building < main.town.buildings.size():
		rect = main.town.buildings[building]
	else:
		return false
	for b in _devices():
		var it = b.get_meta("item")
		if kind_of(it) != "generator" or not bool(it.props.get("on", false)):
			continue
		var q := Vector2(b.global_position.x, b.global_position.z)
		var cx := clampf(q.x, rect.position.x, rect.end.x)
		var cy := clampf(q.y, rect.position.y, rect.end.y)
		if q.distance_to(Vector2(cx, cy)) <= GEN_REACH:
			return true
	return false


# --- komunikaty --------------------------------------------------------------------

## Linie nadawane w danym dniu (pusta tablica: cisza).
func broadcast_lines(day: int, tv: bool) -> Array:
	if day > int(_broad.get("tv_until" if tv else "radio_until", 9)):
		return []
	var lang := "pl" if TranslationServer.get_locale().begins_with("pl") else "en"
	for e in _broad.get("entries", []):
		if day >= int(e["from"]) and day <= int(e["to"]):
			return e.get(lang, [])
	return []


# --- klatka ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if main == null or main.clock == null:
		return
	var hours: float = main.clock.game_hours(delta)
	var day: int = main.clock.day()
	_t += delta
	var tick := _t >= 0.5
	if tick:
		_t = 0.0
	var radio_on := false
	for b in _devices():
		var it = b.get_meta("item")
		var dev: Dictionary = it.get_def()["device"]
		match kind_of(it):
			"generator":
				var on := bool(it.props.get("on", false))
				if on:
					it.props["fuel"] = maxf(0.0, float(it.props.get("fuel", 0.0)) - float(dev.get("burn", 0.8)) * hours)
					if float(it.props["fuel"]) <= 0.0:
						it.props["on"] = false
						on = false
						main.hud.show_message(tr("MSG_GEN_EMPTY"))
					elif tick and _rng.randf() < 0.35:
						main.noise.emit_noise(b.global_position, float(dev.get("noise", 55.0)), "NOISE_GENERATOR")
				_loop(b, "SilnikGeneratora", main.sound.engine_loop(), on, 2.0)
			"radio":
				var on := bool(it.props.get("on", false))
				if on:
					it.props["battery"] = maxf(0.0, float(it.props.get("battery", float(dev.get("battery", 10.0)))) - hours)
					if float(it.props["battery"]) <= 0.0:
						it.props["on"] = false
						on = false
						main.hud.show_message(tr("MSG_BATTERY_DEAD"))
				_loop(b, "SzumRadia", main.sound.static_loop(), on, -10.0)
				if on and b.global_position.distance_to(main.player.global_position) < 12.0:
					radio_on = true
			"sensor":
				if bool(it.props.get("on", false)):
					it.props["battery"] = maxf(0.0, float(it.props.get("battery", float(dev.get("battery", 72.0)))) - hours)
					if float(it.props["battery"]) <= 0.0:
						it.props["on"] = false
					elif tick:
						_sensor(b, it)
			"alarm_clock":
				_alarm_clock(b, it, delta)
	if radio_on:
		_radio_t -= delta
		if _radio_t <= 0.0:
			var lines := broadcast_lines(day, false)
			if lines.is_empty():
				main.hud.show_message(tr("MSG_RADIO_STATIC"))
			else:
				main.hud.show_message(tr("RADIO_PREFIX") + str(lines[_radio_line % lines.size()]))
				_radio_line += 1
			_radio_t = 14.0
	if tick:
		_update_tvs(day)


func _update_tvs(day: int) -> void:
	for tv in tvs:
		var lit: bool = bool(tv["on"]) and main.utilities.powered(int(tv["house"]))
		tv["label"].visible = lit
		if lit:
			var lines := broadcast_lines(day, true)
			tv["label"].text = tr("TV_NO_SIGNAL") if lines.is_empty() else str(lines[int(main.clock.minutes / 3.0) % lines.size()])


func _sensor(b, it) -> void:
	var last := float(it.props.get("beep_t", -99.0))
	var now := Time.get_ticks_msec() / 1000.0
	if now - last < 4.0:
		return
	for z in main.zombies.zombies:
		if z.is_dead() or z.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		if z.global_position.distance_to(b.global_position) < SENSOR_RANGE:
			it.props["beep_t"] = now
			main.sound.play("beep", b.global_position, -2.0)
			if b.global_position.distance_to(main.player.global_position) < 40.0:
				main.hud.show_message(tr("MSG_SENSOR"))
			return


func _alarm_clock(b, it, delta: float) -> void:
	var ring_at := float(it.props.get("ring_at", -1.0))
	var ringing := float(it.props.get("ringing", 0.0))
	if ring_at > 0.0 and main.clock.minutes >= ring_at and ringing <= 0.0:
		it.props["ringing"] = 20.0
		it.props["ring_at"] = -1.0
		it.props["set"] = 0
		ringing = 20.0
	if ringing > 0.0:
		var after := ringing - delta
		it.props["ringing"] = maxf(0.0, after)
		if int(ringing) != int(after):
			main.sound.play("ring", b.global_position, 4.0)
			main.noise.emit_noise(b.global_position, 80.0, "NOISE_ALARM_CLOCK")


## Zapętlony dźwięk przyczepiony do urządzenia (włącza się i wyłącza z nim).
func _loop(b: Node3D, n: String, stream: AudioStream, on: bool, vol: float) -> void:
	var p: AudioStreamPlayer3D = b.get_node_or_null(n)
	if on and p == null:
		p = AudioStreamPlayer3D.new()
		p.name = n
		p.stream = stream
		p.volume_db = vol
		p.unit_size = 4.0
		b.add_child(p)
		p.play()
	elif not on and p != null:
		p.queue_free()


func to_dict() -> Dictionary:
	var t: Array = []
	for tv in tvs:
		t.append(tv["on"])
	return {"tvs": t}


func from_dict(d: Dictionary) -> void:
	var t: Array = d.get("tvs", [])
	for k in mini(t.size(), tvs.size()):
		tvs[k]["on"] = bool(t[k])
