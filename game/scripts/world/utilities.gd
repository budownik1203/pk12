extends Node
## Sieć: prąd i woda. Każda nowa gra losuje dzień awarii (data/sandbox.json:
## "power_off_days", "water_off_days"). Awaria jest stopniowa:
##   prąd: dzień przed wyłączeniem światło migocze i gaśnie na chwile (coraz
##         częściej), potem sieć pada na dobre,
##   woda: dzień przed wyłączeniem ciśnienie słabnie (kran napełnia pół naczynia),
##         po wyłączeniu w rurach każdego domu zostaje kilka litrów.
## Co potrzebuje prądu: lampy (włączniki w domu startowym i w domach osiedla),
## lodówki (spowalniają psucie jedzenia), telewizory, alarmy. Po awarii prąd daje
## tylko generator stojący przy budynku (devices.gd).
## Alarm: część domów ma alarm; wybicie szyby albo wyważenie drzwi przy prądzie
## włącza syrenę, która przez półtorej minuty ściąga zombie z całej okolicy.

const FRIDGE_SLOW := 0.75            # lodówka z prądem: jedzenie psuje się 4 razy wolniej
const RESIDUAL_WATER := 4.0          # litry w rurach domu po odcięciu wody
const SIREN_TIME := 90.0             # sekundy wycia alarmu
const LAMP_RANGE := 5.5

var main
var power_off_day := 5
var water_off_day := 7
var residual := {}                   # "start" / "dom3" -> litry w rurach po odcięciu
var house_lights := {}               # indeks domu -> {"on", "lights": [], "glows": []}
var alarms := {}                     # indeks domu -> {"armed": bool, "siren": sekundy}
var announced := {"power_flicker": false, "power_off": false, "water_low": false, "water_off": false}
var _flicker_off := false
var _flicker_t := 0.0
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _siren: AudioStreamPlayer3D


func setup(main_node, world_seed: int) -> void:
	main = main_node
	_rng.seed = world_seed + 1414
	var s: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sandbox.json"))
	var pd: Array = s.get("power_off_days", [4, 7])
	var wd: Array = s.get("water_off_days", [5, 9])
	power_off_day = _rng.randi_range(int(pd[0]), int(pd[1]))
	water_off_day = _rng.randi_range(int(wd[0]), int(wd[1]))
	_siren = AudioStreamPlayer3D.new()
	_siren.stream = main.sound.siren_loop()
	_siren.unit_size = 30.0
	_siren.max_distance = 160.0
	_siren.volume_db = 6.0
	main.world.add_child(_siren)


# --- stan sieci ------------------------------------------------------------------

## Dzień gry z ułamkiem (1.0 = północ pierwszego dnia).
func _day_f() -> float:
	return 1.0 + main.clock.minutes / 1440.0


## "on", "flicker" (dzień przed awarią), "off".
func power_state() -> String:
	var d := _day_f()
	if d >= power_off_day:
		return "off"
	if d >= power_off_day - 1.0:
		return "flicker"
	return "on"


func water_state() -> String:
	var d := _day_f()
	if d >= water_off_day:
		return "off"
	if d >= water_off_day - 1.0:
		return "low"
	return "on"


## Prąd z sieci w tej chwili (podczas migotania gaśnie na chwile).
func grid_power() -> bool:
	match power_state():
		"on":
			return true
		"flicker":
			return not _flicker_off
	return false


## Czy budynek ("start" albo indeks domu) ma teraz prąd: sieć albo generator.
func powered(building) -> bool:
	if grid_power():
		return true
	return main.devices != null and main.devices.generator_powers(building)


## Budynek, w którym leży punkt: "start", indeks domu albo null (na dworze).
func building_of(p: Vector3):
	if main.town.in_start_house(p):
		return "start"
	var h: Dictionary = main.town.house_of(p)
	return int(h["index"]) if not h.is_empty() else null


# --- woda --------------------------------------------------------------------------

## Woda z kranu w budynku: ile litrów da się nalać (do max). Zużywa resztkę z rur.
func take_water(building, max_l: float) -> float:
	var key := str(building)
	match water_state():
		"on":
			return max_l
		"low":
			return max_l * 0.5  # słabe ciśnienie: leci cienko
	var left := float(residual.get(key, RESIDUAL_WATER))
	var got := minf(left, max_l)
	residual[key] = left - got
	return got


# --- lampy domów osiedla ---------------------------------------------------------

## Lampa sufitowa w pokoju domu (wołane przez town.gd przy budowie).
func add_house_lamp(house: int, parent: Node3D, pos: Vector3) -> void:
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.66)
	lamp.light_energy = 1.1
	lamp.omni_range = LAMP_RANGE
	lamp.omni_attenuation = 1.3
	lamp.shadow_enabled = false
	lamp.visible = false
	lamp.position = pos
	parent.add_child(lamp)
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	mesh.radial_segments = 8
	mesh.rings = 4
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(0.16, 0.15, 0.13)
	mesh.material = glow
	var bulb := MeshInstance3D.new()
	bulb.mesh = mesh
	bulb.position = pos + Vector3(0, 0.1, 0)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bulb.set_meta("psx_skip", true)
	parent.add_child(bulb)
	if not house_lights.has(house):
		house_lights[house] = {"on": false, "lights": [], "glows": []}
	house_lights[house]["lights"].append(lamp)
	house_lights[house]["glows"].append(glow)


func toggle_house(house: int) -> void:
	if not house_lights.has(house):
		return
	house_lights[house]["on"] = not bool(house_lights[house]["on"])
	main.sound.play("switch", main.player.camera.global_position, -6.0)
	if bool(house_lights[house]["on"]) and not powered(house):
		main.hud.show_message(tr("MSG_NO_POWER"))
	_apply_lights()


func _apply_lights() -> void:
	for h in house_lights:
		var e: Dictionary = house_lights[h]
		var lit: bool = bool(e["on"]) and powered(h)
		for l in e["lights"]:
			l.visible = lit
		for g in e["glows"]:
			g.albedo_color = Color(1.0, 0.9, 0.7) if lit else Color(0.16, 0.15, 0.13)
	# włącznik w domu startowym: lampa świeci, gdy włączona i jest prąd
	for id in main.switches:
		var sw: Dictionary = main.switches[id]
		var lit2: bool = bool(sw["on"]) and powered("start")
		sw["light"].visible = lit2
		sw["glow"].albedo_color = Color(1.0, 0.9, 0.7) if lit2 else Color(0.16, 0.15, 0.13)


# --- alarmy ----------------------------------------------------------------------

func add_alarm(house: int) -> void:
	alarms[house] = {"armed": true, "siren": 0.0}


## Włamanie: szyba albo drzwi domu o danym id ("dom3" / "dom3_5").
func on_break_in(id: String) -> void:
	if not id.begins_with("dom"):
		return
	var num := id.substr(3).split("_")[0]
	if not num.is_valid_int():
		return
	var h := int(num)
	if not alarms.has(h) or not bool(alarms[h]["armed"]) or not powered(h):
		return
	alarms[h]["armed"] = false  # wyje raz, potem akumulator pada
	alarms[h]["siren"] = SIREN_TIME
	var rect: Rect2 = main.town.buildings[h]
	_siren.global_position = Vector3(rect.get_center().x, 2.5, rect.get_center().y)
	_siren.play()
	main.hud.show_message(tr("MSG_ALARM"))


# --- klatka ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if main == null or main.clock == null:
		return
	# migotanie: losowe przerwy, częstsze bliżej awarii
	if power_state() == "flicker":
		_flicker_t -= delta
		if _flicker_t <= 0.0:
			var closeness := clampf(_day_f() - (power_off_day - 1.0), 0.0, 1.0)
			_flicker_off = not _flicker_off if _rng.randf() < 0.3 + closeness * 0.5 else false
			_flicker_t = _rng.randf_range(0.08, 0.4) if _flicker_off else _rng.randf_range(1.0, 12.0) * (1.2 - closeness)
	else:
		_flicker_off = false
	_announce()
	_apply_lights()
	# syreny alarmów: hałas co półtorej sekundy
	for h in alarms:
		var a: Dictionary = alarms[h]
		if float(a["siren"]) > 0.0:
			var before := float(a["siren"])
			a["siren"] = maxf(0.0, before - delta)
			if int(before / 1.5) != int(float(a["siren"]) / 1.5):
				main.noise.emit_noise(_siren.global_position, 120.0, "NOISE_ALARM")
			if float(a["siren"]) <= 0.0:
				_siren.stop()
	_t += delta
	if _t >= 1.0:
		_fridges(main.clock.game_hours(_t))
		_t = 0.0


func _announce() -> void:
	var ps := power_state()
	if ps == "flicker" and not announced["power_flicker"]:
		announced["power_flicker"] = true
		main.hud.show_message(tr("MSG_POWER_FLICKER"))
	elif ps == "off" and not announced["power_off"]:
		announced["power_off"] = true
		main.hud.show_message(tr("MSG_POWER_OFF"))
		main.sound.play("switch", main.player.camera.global_position, -2.0, 0.5)
	var ws := water_state()
	if ws == "low" and not announced["water_low"]:
		announced["water_low"] = true
	elif ws == "off" and not announced["water_off"]:
		announced["water_off"] = true


## Lodówki z prądem spowalniają psucie: przesuwamy datę przygotowania jedzenia.
func _fridges(hours: float) -> void:
	for spot in main.town.loot_spots:
		if spot[1] != "lodowka":
			continue
		var num := str(spot[0]).substr(3).split("_")[0]
		if not num.is_valid_int() or not powered(int(num)):
			continue
		for g in main.inventory.containers[spot[0]]["grids"]:
			for it in g.items:
				if it.get_def().get("food", {}).has("rot_days") and it.props.has("made"):
					it.props["made"] = float(it.props["made"]) + hours / 24.0 * FRIDGE_SLOW


func to_dict() -> Dictionary:
	var lights := {}
	for h in house_lights:
		lights[str(h)] = house_lights[h]["on"]
	var al := {}
	for h in alarms:
		al[str(h)] = alarms[h]["armed"]
	return {"power_off_day": power_off_day, "water_off_day": water_off_day, "residual": residual.duplicate(),
			"lights": lights, "alarms": al, "announced": announced.duplicate()}


func from_dict(d: Dictionary) -> void:
	power_off_day = int(d.get("power_off_day", power_off_day))
	water_off_day = int(d.get("water_off_day", water_off_day))
	residual = (d.get("residual", {}) as Dictionary).duplicate()
	for k in d.get("lights", {}):
		if house_lights.has(int(k)):
			house_lights[int(k)]["on"] = bool(d["lights"][k])
	for k in d.get("alarms", {}):
		if alarms.has(int(k)):
			alarms[int(k)]["armed"] = bool(d["alarms"][k])
			alarms[int(k)]["siren"] = 0.0
	for k in d.get("announced", {}):
		announced[k] = bool(d["announced"][k])
	_apply_lights()
