extends Node
## Pogoda. Rodzaje: pogodnie, pochmurno, deszcz, burza, mgła. Co 2–6 godzin gry
## pogoda losuje następny rodzaj (prawdopodobieństwa zależne od obecnego),
## a parametry (zachmurzenie, deszcz, mgła, wiatr, zmiana temperatury) płynnie
## dochodzą do nowych wartości w około pół godziny gry.
## Skutki: mniej światła dziennego i chłodniej, deszcz widoczny i słyszalny
## (w środku ciszej), grzmoty z błyskiem, przemakanie ubrań na zewnątrz
## i schnięcie w środku, deszczówka w pojemnikach stojących na dworze,
## zombie słabiej słyszą w deszczu i gorzej widzą we mgle.

const ItemScript := preload("res://scripts/inventory/item.gd")

const KINDS := {
	"pogodnie": {"cloud": 0.1, "rain": 0.0, "fog": 0.0, "wind": 0.2, "temp": 0.0},
	"pochmurno": {"cloud": 0.65, "rain": 0.0, "fog": 0.1, "wind": 0.35, "temp": -1.5},
	"deszcz": {"cloud": 0.85, "rain": 0.6, "fog": 0.2, "wind": 0.45, "temp": -3.0},
	"burza": {"cloud": 1.0, "rain": 1.0, "fog": 0.15, "wind": 0.9, "temp": -4.0},
	"mgla": {"cloud": 0.5, "rain": 0.0, "fog": 0.9, "wind": 0.05, "temp": -1.0},
}
const NEXT := {
	"pogodnie": {"pogodnie": 3, "pochmurno": 4, "mgla": 1},
	"pochmurno": {"pogodnie": 3, "pochmurno": 2, "deszcz": 4, "mgla": 1},
	"deszcz": {"pochmurno": 4, "deszcz": 2, "burza": 2},
	"burza": {"deszcz": 5, "pochmurno": 2},
	"mgla": {"pogodnie": 3, "pochmurno": 3},
}
const WET_RATE := 0.9               # przemakanie na godzinę gry w pełnym deszczu
const DRY_RATE := 0.25              # schnięcie na godzinę gry w środku
const RAIN_FILL := 0.4              # litry deszczówki na godzinę gry w pełnym deszczu
const OUT_AREA := Rect2(-4.8, 3.6, 5.0, 3.6)  # grunt za oknem (x, z) dla kropli

var main
var kind := "pogodnie"
var cloud := 0.1
var rain := 0.0
var fog := 0.0
var wind := 0.2
var temp_mod := 0.0
var next_change := 3.0              # godziny gry do następnej zmiany
var thunders := 0

var _particles: CPUParticles3D
var _rain_player: AudioStreamPlayer
var _thunder_t := 20.0
var _flash := 0.0
var _rng := RandomNumberGenerator.new()


func setup(main_node) -> void:
	main = main_node
	_rng.randomize()
	_build_rain()


func _build_rain() -> void:
	_particles = CPUParticles3D.new()
	_particles.name = "Deszcz"
	_particles.amount = 900
	_particles.lifetime = 0.7
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_particles.emission_box_extents = Vector3(OUT_AREA.size.x / 2.0, 0.1, OUT_AREA.size.y / 2.0)
	_particles.direction = Vector3(0, -1, 0)
	_particles.spread = 3.0
	_particles.gravity = Vector3(0, -9.8, 0)
	_particles.initial_velocity_min = 6.0
	_particles.initial_velocity_max = 8.0
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.28)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.7, 0.75, 0.82, 0.45)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	q.material = m
	_particles.mesh = q
	_particles.position = Vector3(OUT_AREA.position.x + OUT_AREA.size.x / 2.0, 4.2, OUT_AREA.position.y + OUT_AREA.size.y / 2.0)
	_particles.emitting = false
	_particles.set_meta("psx_skip", true)
	main.world.add_child(_particles)
	_rain_player = AudioStreamPlayer.new()
	_rain_player.stream = main.sound.rain_loop()
	_rain_player.volume_db = -60.0
	add_child(_rain_player)


func set_kind(k: String, instant: bool = false) -> void:
	kind = k
	next_change = _rng.randf_range(2.0, 6.0)
	if instant:
		var p: Dictionary = KINDS[k]
		cloud = p["cloud"]
		rain = p["rain"]
		fog = p["fog"]
		wind = p["wind"]
		temp_mod = p["temp"]


func _pick_next() -> String:
	var w: Dictionary = NEXT[kind]
	var total := 0
	for k in w:
		total += int(w[k])
	var r := _rng.randi_range(1, total)
	for k in w:
		r -= int(w[k])
		if r <= 0:
			return k
	return kind


func _physics_process(delta: float) -> void:
	if main == null or main.clock == null:
		return
	var hours: float = main.clock.game_hours(delta)
	next_change -= hours
	if next_change <= 0.0:
		set_kind(_pick_next())
	var p: Dictionary = KINDS[kind]
	var k := clampf(hours * 2.0, 0.0, 1.0)  # około pół godziny gry do nowych wartości
	cloud = lerpf(cloud, p["cloud"], k)
	rain = lerpf(rain, p["rain"], k)
	fog = lerpf(fog, p["fog"], k)
	wind = lerpf(wind, p["wind"], k)
	temp_mod = lerpf(temp_mod, p["temp"], k)
	_update_rain_fx(delta)
	_update_wetness(hours)
	_collect_rainwater(hours)


func outside() -> bool:
	return main.zombies.zone_of(main.player.global_position) == "out"


func _update_rain_fx(delta: float) -> void:
	_particles.emitting = rain > 0.05
	var want := int(round(lerpf(150.0, 900.0, clampf(rain, 0.0, 1.0)) / 150.0)) * 150
	if want != _particles.amount:
		_particles.amount = want
	_particles.direction = Vector3(wind * 0.35, -1.0, wind * 0.15).normalized()
	# dźwięk deszczu: na dworze pełny, przy oknie wyraźny, w głębi pokoju stłumiony
	var vol := -60.0
	if rain > 0.02:
		var pz: float = main.player.global_position.z
		var near_window := clampf((pz - 0.5) / 3.0, 0.0, 1.0)
		var atten := 0.0 if outside() else lerpf(-16.0, -7.0, near_window)
		vol = linear_to_db(rain) - 4.0 + atten
	_rain_player.volume_db = vol
	if vol > -55.0 and not _rain_player.playing:
		_rain_player.play()
	elif vol <= -55.0 and _rain_player.playing:
		_rain_player.stop()
	# burza: błysk i grzmot
	if kind == "burza" and rain > 0.7:
		_thunder_t -= delta
		if _thunder_t <= 0.0:
			_thunder_t = _rng.randf_range(12.0, 40.0)
			thunder()
	_flash = maxf(0.0, _flash - delta * 6.0)


func thunder() -> void:
	thunders += 1
	_flash = 1.0
	var far := Vector3(_rng.randf_range(-30, 30), 20.0, _rng.randf_range(15, 40))
	main.sound.play_ui("thunder", -2.0 if outside() else -8.0)
	main.noise.events.append({"pos": far, "loud": 0.0, "label": "NOISE_THUNDER", "time": Time.get_ticks_msec() / 1000.0})


## Błysk pioruna (0..1) dla nieba i światła otoczenia.
func flash() -> float:
	return _flash


func _worn() -> Array:
	var out: Array = []
	for s in main.inventory.slots:
		if s in ["w_reku", "w_lewej", "oburacz"]:
			continue
		out.append(main.inventory.slots[s])
	return out


func _update_wetness(hours: float) -> void:
	var out := outside() and rain > 0.02
	for it in _worn():
		if out:
			var shield := float(it.get_def().get("waterproof", 0.0))
			it.wet = minf(1.0, it.wet + rain * WET_RATE * (1.0 - shield) * hours)
			# plecak przepuszcza trochę wody do środka
			if it.is_container():
				for g in it.grids:
					for inner in g.items:
						inner.wet = minf(1.0, inner.wet + rain * WET_RATE * 0.15 * (1.0 - shield) * hours)
		else:
			var warm: float = 1.0 + main.needs.exertion
			it.wet = maxf(0.0, it.wet - DRY_RATE * warm * hours)


## Średnie przemoczenie założonych ubrań (0..1).
func clothes_wet() -> float:
	var s := 0.0
	var n := 0
	for it in _worn():
		if float(it.get_def().get("insulation", 0.0)) > 0.0:
			s += it.wet
			n += 1
	return s / n if n > 0 else 0.0


func _collect_rainwater(hours: float) -> void:
	if rain < 0.05:
		return
	for b in main.world_items.bodies:
		if not is_instance_valid(b):
			continue
		var it = b.get_meta("item")
		var cap := float(it.get_def().get("liquid_capacity", 0.0))
		if cap <= 0.0 or main.zombies.zone_of(b.global_position) != "out":
			continue
		if b.global_transform.basis.y.dot(Vector3.UP) < 0.7:
			continue  # przewrócone naczynie nie łapie wody
		var amount := float(it.liquid.get("amount", 0.0)) + rain * RAIN_FILL * hours
		it.liquid = {"type": "woda", "amount": minf(cap, amount)}


## Mnożnik słuchu zombie (deszcz zagłusza).
func hearing_factor() -> float:
	return 1.0 - rain * 0.35


## Mnożnik wzroku zombie (deszcz, mgła).
func sight_factor() -> float:
	return clampf(1.0 - rain * 0.2 - fog * 0.5, 0.3, 1.0)


func text() -> String:
	return tr("WEATHER_" + kind)


func to_dict() -> Dictionary:
	return {"kind": kind, "cloud": cloud, "rain": rain, "fog": fog, "wind": wind, "temp": temp_mod, "next": next_change}


func from_dict(d: Dictionary) -> void:
	kind = str(d.get("kind", "pogodnie"))
	if not KINDS.has(kind):
		kind = "pogodnie"
	cloud = float(d.get("cloud", 0.1))
	rain = float(d.get("rain", 0.0))
	fog = float(d.get("fog", 0.0))
	wind = float(d.get("wind", 0.2))
	temp_mod = float(d.get("temp", 0.0))
	next_change = float(d.get("next", 3.0))
