extends Node
## Dźwięki syntetyzowane przy starcie gry (bez plików audio): krótkie próbki
## 22 kHz, po kilka wariantów każdej, odtwarzane w przestrzeni 3D.
## Źródła: zdarzenia hałasu (noise.gd: młotek, podważanie, wkręcanie, zamek...),
## kroki i lądowanie gracza, uderzenia brył o otoczenie (zmiana prędkości),
## oraz wywołania wprost (gwóźdź dobity, wkręt dokręcony, rzut, podniesienie).

const RATE := 22050
const VARIANTS := 3
const POOL := 20
const STEP_WALK := 0.72        # metry między krokami
const IMPACT_DV := 1.3         # m/s zmiany prędkości, od której bryła stuka

## etykieta hałasu -> [dźwięk, głośność dB, wysokość]
const NOISE_SOUNDS := {
	"NOISE_HAMMER": ["hammer", 0.0, 1.0],
	"NOISE_BOARD_OFF": ["crack", 0.0, 1.0],
	"NOISE_DOOR_BREAK": ["crack", 3.0, 0.75],
	"NOISE_DOOR_CLICK": ["latch", -4.0, 1.0],
	"NOISE_HANDLE": ["handle", -6.0, 1.0],
	"NOISE_LOCK": ["lock", -3.0, 1.0],
	"NOISE_PLACE": ["place", -2.0, 1.0],
	"NOISE_PRY": ["pry", -1.0, 1.0],
	"NOISE_PULL": ["pry", -3.0, 1.35],
	"NOISE_SCREW": ["screw", -7.0, 1.0],
}

var main
var lib := {}
var played: Array = []         # ostatnie odtworzone nazwy (ekran deweloperski)
var counts := {}               # ile razy zagrał każdy dźwięk (testy)

var _pool: Array = []
var _next := 0
var _ui: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _step_dist := 0.0
var _was_floor := true
var _fall_speed := 0.0
var _bodies: Array = []
var _prev_vel := {}
var _scan := 0.0


func setup(main_node) -> void:
	main = main_node
	_rng.seed = 1203
	_build_library()
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 2.5
		p.max_distance = 30.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		main.world.add_child(p)
		_pool.append(p)
	_ui = AudioStreamPlayer.new()
	add_child(_ui)


func play(sound_name: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not lib.has(sound_name):
		return
	played.append(sound_name)
	counts[sound_name] = int(counts.get(sound_name, 0)) + 1
	if played.size() > 60:
		played.pop_front()
	var p: AudioStreamPlayer3D = _pool[_next]
	_next = (_next + 1) % _pool.size()
	var variants: Array = lib[sound_name]
	p.stream = variants[_rng.randi() % variants.size()]
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = pitch * _rng.randf_range(0.94, 1.06)
	p.play()


## Dźwięk interfejsu (bez położenia): przekładanie w ekwipunku.
func play_ui(sound_name: String, volume_db: float = -8.0) -> void:
	if not lib.has(sound_name):
		return
	played.append(sound_name)
	var variants: Array = lib[sound_name]
	_ui.stream = variants[_rng.randi() % variants.size()]
	_ui.volume_db = volume_db
	_ui.pitch_scale = _rng.randf_range(0.95, 1.05)
	_ui.play()


func on_noise(pos: Vector3, label_key: String) -> void:
	if NOISE_SOUNDS.has(label_key):
		var s: Array = NOISE_SOUNDS[label_key]
		play(s[0], pos, s[1], s[2])


func count(sound_name: String) -> int:
	return int(counts.get(sound_name, 0))


# --- kroki i uderzenia brył ----------------------------------------------------

func _physics_process(delta: float) -> void:
	if main == null or main.player == null:
		return
	var pl = main.player
	var feet: Vector3 = pl.global_position
	var on_floor: bool = pl.is_on_floor()
	if on_floor:
		var hv := Vector3(pl.velocity.x, 0.0, pl.velocity.z)
		_step_dist += hv.length() * delta
		var crouch: bool = pl.height < pl.STAND_HEIGHT - 0.1
		var stride := STEP_WALK * (0.8 if crouch else 1.0) + (0.25 if hv.length() > 4.0 else 0.0)
		if _step_dist >= stride:
			_step_dist = 0.0
			var vol := -14.0 if crouch else (-6.0 if hv.length() > 4.0 else -10.0)
			play("step", feet, vol + pl.load_factor * 3.0)
			# kroki słychać: bieg daleko, chód blisko, kucanie prawie wcale
			var ch = main.character
			var quiet: float = ch.effect("noise") * (1.0 - ch.level("skradanie") * 0.06)
			if not crouch:
				main.noise.emit_noise(feet, (20.0 if hv.length() > 4.0 else 7.0) * quiet, "NOISE_STEP")
			else:
				# skradanie rośnie od kucania, szybciej, gdy zombie są blisko
				var near := false
				for z in main.zombies.zombies:
					if not z.is_dead() and z.global_position.distance_to(feet) < 12.0:
						near = true
						break
				ch.add_xp("skradanie", 1.5 if near else 0.3)
			if hv.length() > 4.0:
				ch.add_xp("kondycja", 0.6)
			if pl.load_factor < 0.95 or main.inventory.hands_bulky():
				ch.add_xp("sila", 0.4)
		if not _was_floor and _fall_speed > 2.5:
			play("land", feet, clampf(-12.0 + _fall_speed * 2.0, -12.0, 0.0))
	else:
		_fall_speed = maxf(0.0, -pl.velocity.y)
	_was_floor = on_floor

	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.5
		_bodies = main.world.find_children("*", "RigidBody3D", true, false)
	for b in _bodies:
		if not is_instance_valid(b):
			continue
		var body := b as RigidBody3D
		if body.sleeping or body.freeze:
			_prev_vel.erase(body)
			continue
		var v := body.linear_velocity
		var prev: Vector3 = _prev_vel.get(body, v)
		_prev_vel[body] = v
		var dv := (prev - v).length()
		if dv > IMPACT_DV and body != pl.held_body:
			var metal: bool = body.has_meta("item") and body.get_meta("item").material() == "metal"
			var vol := clampf(-20.0 + dv * 3.0 + log(maxf(body.mass, 0.05)) * 2.5, -26.0, 2.0)
			play("impact_metal" if metal else "impact_wood", body.global_position, vol,
					clampf(1.4 - body.mass * 0.03, 0.6, 1.5))


# --- synteza -------------------------------------------------------------------

func _build_library() -> void:
	var gens := {
		"hammer": [0.32, _hammer], "nail_done": [0.7, _nail_done], "screw": [0.17, _screw],
		"screw_tight": [0.14, _screw_tight], "pry": [0.45, _pry], "crack": [0.55, _crack],
		"place": [0.22, _place], "lock": [0.28, _lock], "latch": [0.12, _latch],
		"handle": [0.2, _handle], "switch": [0.08, _switch], "step": [0.14, _step],
		"land": [0.25, _land], "impact_wood": [0.28, _impact_wood],
		"impact_metal": [0.4, _impact_metal], "pickup": [0.2, _pickup],
		"whoosh": [0.3, _whoosh], "inv": [0.11, _inv],
		"water": [1.3, _water], "eat": [0.5, _eat], "drink": [0.6, _drink],
		"thunder": [3.2, _thunder],
		"glass": [0.7, _glass],
		"gunshot": [0.9, _gunshot], "shotgun": [1.2, _shotgun], "gun_click": [0.08, _gun_click],
		"gun_rack": [0.35, _gun_rack], "gun_pump": [0.4, _gun_pump], "mag_out": [0.2, _mag_out],
		"mag_in": [0.22, _mag_in], "shell_in": [0.18, _shell_in], "casing": [0.35, _casing],
		"crank": [1.0, _crank], "beep": [0.25, _beep], "ring": [0.9, _ring],
		"saw": [0.42, _saw], "rip": [0.45, _rip], "chop": [0.12, _chop], "sizzle": [1.0, _sizzle],
		"groan": [1.4, _groan], "snarl": [0.6, _snarl], "hit_flesh": [0.25, _hit_flesh], "bodyfall": [0.5, _bodyfall],
	}
	for n in gens:
		var arr: Array = []
		for v in VARIANTS:
			var g: Array = gens[n]
			arr.append(_wav(_render(g[0], g[1])))
		lib[n] = arr


func _render(dur: float, gen: Callable) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var st := {"lp": 0.0, "lp2": 0.0, "ph": 0.0, "seed": _rng.randf()}
	for i in n:
		out[i] = gen.call(float(i) / RATE, dur, st)
	# bez przesterowania: szczyt najwyżej 0,85
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(out[i]))
	if peak > 0.85:
		for i in n:
			out[i] *= 0.85 / peak
	# łagodne wyciszenie końcówki, żeby nie trzaskało
	var fade := mini(n, int(0.01 * RATE))
	for i in fade:
		out[n - 1 - i] *= float(i) / fade
	return out


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


static func _lp(st: Dictionary, x: float, a: float, key: String = "lp") -> float:
	st[key] = st[key] + a * (x - st[key])
	return st[key]


static func _sin(f: float, t: float) -> float:
	return sin(TAU * f * t)


func _hammer(t: float, _d: float, st: Dictionary) -> float:
	var thud := _lp(st, _noise(), 0.35) * exp(-t * 55.0) * 1.2
	var body := _sin(105.0, t) * exp(-t * 35.0) * 0.55
	var ring := (_sin(1720.0, t) * 0.32 + _sin(2610.0, t) * 0.18) * exp(-t * 24.0)
	return thud + body + ring


func _nail_done(t: float, _d: float, _st: Dictionary) -> float:
	# dźwięczne „tiiing” nakładane na zwykłe uderzenie: gwóźdź siedzi do końca
	return (_sin(3180.0, t) * 0.32 + _sin(4740.0, t) * 0.14 + _sin(2120.0, t) * 0.12) * exp(-t * 6.5)


func _screw(t: float, d: float, st: Dictionary) -> float:
	var f := 620.0 + 520.0 * t / d
	st["ph"] += f / RATE
	var squeak := sin(TAU * st["ph"]) * (0.55 + 0.45 * _sin(55.0, t))
	var grit := (_noise() - _lp(st, _noise(), 0.2)) * 0.25
	return (squeak * 0.45 + grit) * sin(PI * t / d)


func _screw_tight(t: float, _d: float, _st: Dictionary) -> float:
	return _noise() * exp(-t * 320.0) * 0.8 + _sin(2350.0, t) * exp(-t * 85.0) * 0.45 \
			+ _sin(175.0, t) * exp(-t * 45.0) * 0.4


func _pry(t: float, d: float, st: Dictionary) -> float:
	# drewno skrzypi: piła o drżącej wysokości przerywana szarpnięciami (stick-slip)
	var f := 92.0 + 38.0 * sin(TAU * 2.7 * t + st["seed"] * 6.0) + _noise() * 6.0
	st["ph"] = fmod(st["ph"] + f / RATE, 1.0)
	var saw: float = st["ph"] * 2.0 - 1.0
	var grab := 0.5 + 0.5 * signf(sin(TAU * (34.0 + st["seed"] * 20.0) * t))
	return _lp(st, saw * grab, 0.25) * sin(PI * t / d) * 0.9


func _crack(t: float, _d: float, st: Dictionary) -> float:
	var burst := _lp(st, _noise(), 0.45) * exp(-t * 13.0)
	var splinters := 0.0
	if t < 0.18 and _rng.randf() < 0.004:
		splinters = _noise() * 3.0
	return burst * 0.9 + splinters + _sin(68.0, t) * exp(-t * 16.0) * 0.6


func _place(t: float, _d: float, st: Dictionary) -> float:
	return _sin(142.0, t) * exp(-t * 26.0) * 0.7 + _lp(st, _noise(), 0.3) * exp(-t * 48.0) * 0.6


func _click(t: float, f: float) -> float:
	if t < 0.0:
		return 0.0
	return _noise() * exp(-t * 420.0) * 0.8 + _sin(f, t) * exp(-t * 140.0) * 0.4


func _lock(t: float, _d: float, _st: Dictionary) -> float:
	return _click(t, 2900.0) + _click(t - 0.09, 2300.0) * 1.2 + _sin(1180.0, t) * exp(-t * 30.0) * 0.12


func _latch(t: float, _d: float, _st: Dictionary) -> float:
	return _click(t, 2100.0) + _sin(260.0, t) * exp(-t * 60.0) * 0.3


func _handle(t: float, d: float, st: Dictionary) -> float:
	return _click(t, 1600.0) * 0.7 + _screw(t, d, st) * 0.15


func _switch(t: float, _d: float, _st: Dictionary) -> float:
	return _click(t, 3600.0)


func _step(t: float, _d: float, st: Dictionary) -> float:
	return _lp(st, _noise(), 0.16) * exp(-t * 42.0) * 1.3 + _sin(82.0, t) * exp(-t * 38.0) * 0.45


func _land(t: float, d: float, st: Dictionary) -> float:
	return _step(t, d, st) * 1.2 + _sin(58.0, t) * exp(-t * 20.0) * 0.6


func _impact_wood(t: float, _d: float, st: Dictionary) -> float:
	return _sin(118.0, t) * exp(-t * 24.0) * 0.6 + _lp(st, _noise(), 0.28) * exp(-t * 40.0) * 0.8


func _impact_metal(t: float, _d: float, _st: Dictionary) -> float:
	var ring := (_sin(910.0, t) * 0.3 + _sin(1435.0, t) * 0.22 + _sin(2215.0, t) * 0.14) * exp(-t * 11.0)
	return ring + _noise() * exp(-t * 260.0) * 0.6


func _pickup(t: float, d: float, st: Dictionary) -> float:
	var band := _lp(st, _noise(), 0.6) - _lp(st, _noise(), 0.08, "lp2")
	return band * sin(PI * t / d) * 0.7


func _whoosh(t: float, d: float, st: Dictionary) -> float:
	var a := 0.04 + 0.3 * sin(PI * t / d)
	return _lp(st, _noise(), a) * sin(PI * t / d) * 0.9


func _inv(t: float, d: float, st: Dictionary) -> float:
	return _pickup(t, d, st) * 0.8


func _water(t: float, d: float, st: Dictionary) -> float:
	# strumień z kranu: szum z bulgotaniem, narasta i cichnie
	var env := minf(1.0, t / 0.08) * minf(1.0, (d - t) / 0.25)
	var hiss := _lp(st, _noise(), 0.5) - _lp(st, _noise(), 0.05, "lp2")
	var gurgle := 0.5 + 0.5 * sin(TAU * (7.0 + sin(t * 3.0) * 3.0) * t)
	return hiss * env * (0.6 + gurgle * 0.4)


func _eat(t: float, _d: float, st: Dictionary) -> float:
	# trzy kęsy: chrupnięcia
	var s := 0.0
	for k in 3:
		var tk := t - k * 0.15
		if tk >= 0.0:
			s += _lp(st, _noise(), 0.4) * exp(-tk * 30.0)
	return s * 1.2


func _drink(t: float, _d: float, st: Dictionary) -> float:
	# dwa łyki: niskie bulgotnięcia
	var s := 0.0
	for k in 2:
		var tk := t - k * 0.28
		if tk >= 0.0:
			s += _sin(180.0 + 60.0 * exp(-tk * 10.0), tk) * exp(-tk * 14.0) + _lp(st, _noise(), 0.15) * exp(-tk * 20.0) * 0.5
	return s * 0.8


func _groan(t: float, d: float, st: Dictionary) -> float:
	# jęk: niski, chrapliwy ton z formantem i drżeniem
	var f := 85.0 + 25.0 * sin(t * 2.3 + st["seed"] * 5.0) + _noise() * 8.0
	st["ph"] = fmod(st["ph"] + f / RATE, 1.0)
	var buzz: float = st["ph"] * 2.0 - 1.0
	var formant := _lp(st, buzz + _noise() * 0.35, 0.18)
	return formant * sin(PI * t / d) * (0.7 + 0.3 * sin(t * 11.0)) * 1.4


func _snarl(t: float, d: float, st: Dictionary) -> float:
	var f := 140.0 + 90.0 * (1.0 - t / d)
	st["ph"] = fmod(st["ph"] + f / RATE, 1.0)
	var rasp: float = (st["ph"] * 2.0 - 1.0) * 0.6 + _noise() * 0.5
	return _lp(st, rasp, 0.35) * minf(1.0, t / 0.03) * exp(-t * 3.5) * 1.5


func _hit_flesh(t: float, _d: float, st: Dictionary) -> float:
	return _lp(st, _noise(), 0.3) * exp(-t * 35.0) * 1.2 + _sin(75.0, t) * exp(-t * 25.0) * 0.7


func _bodyfall(t: float, _d: float, st: Dictionary) -> float:
	return _lp(st, _noise(), 0.12) * exp(-t * 12.0) * 1.3 + _sin(52.0, t) * exp(-t * 10.0) * 0.8


func _thunder(t: float, d: float, st: Dictionary) -> float:
	# grzmot: trzask na początku, potem długie niskie dudnienie
	var crack := _noise() * exp(-t * 18.0) * 0.6
	var rumble := _lp(st, _noise(), 0.03) * 6.0 * (0.6 + 0.4 * sin(t * 7.0 + st["seed"] * 4.0))
	return (crack + rumble) * minf(1.0, t / 0.02) * exp(-t * 1.1) * (1.0 - t / d)


func _gunshot(t: float, _d: float, st: Dictionary) -> float:
	# huk: ostry trzask, niski grzmot i pogłos ulicy
	var crack := _noise() * exp(-t * 90.0) * 1.6
	var boom := (_lp(st, _noise(), 0.12) * 2.2 + _sin(70.0, t) * 0.6) * exp(-t * 14.0)
	var tail := _lp(st, _noise(), 0.04, "lp2") * exp(-t * 4.0) * 1.4
	return crack + boom + tail


func _shotgun(t: float, _d: float, st: Dictionary) -> float:
	var crack := _noise() * exp(-t * 60.0) * 1.5
	var boom := (_lp(st, _noise(), 0.07) * 3.0 + _sin(48.0, t) * 0.8) * exp(-t * 9.0)
	var tail := _lp(st, _noise(), 0.03, "lp2") * exp(-t * 2.8) * 1.6
	return crack + boom + tail


func _gun_click(t: float, _d: float, _st: Dictionary) -> float:
	return (_noise() * 0.6 + _sin(3200.0, t) * 0.4) * exp(-t * 160.0)


func _casing(t: float, _d: float, _st: Dictionary) -> float:
	# łuska dzwoni o podłogę: dwa krótkie podskoki
	var a := (_sin(5200.0, t) * 0.6 + _sin(7900.0, t) * 0.3 + _noise() * 0.1) * exp(-t * 45.0)
	var t2 := t - 0.12
	var b := 0.0 if t2 < 0.0 else (_sin(5600.0, t2) * 0.5 + _sin(8300.0, t2) * 0.2) * exp(-t2 * 60.0) * 0.5
	return a + b


func _gun_rack(t: float, _d: float, _st: Dictionary) -> float:
	# zamek do tyłu i z trzaskiem do przodu
	var back := (_noise() * 0.5 + _sin(1800.0, t) * 0.3) * exp(-t * 70.0)
	var t2 := t - 0.16
	var fwd := 0.0 if t2 < 0.0 else (_noise() * 0.8 + _sin(2400.0, t2) * 0.4 + _sin(900.0, t2) * 0.3) * exp(-t2 * 55.0)
	return back + fwd


func _gun_pump(t: float, _d: float, st: Dictionary) -> float:
	var slide := _lp(st, _noise(), 0.3) * (0.4 if t < 0.3 else 0.0)
	var c1 := (_noise() * 0.7 + _sin(1300.0, t) * 0.3) * exp(-t * 60.0)
	var t2 := t - 0.22
	var c2 := 0.0 if t2 < 0.0 else (_noise() * 0.9 + _sin(1100.0, t2) * 0.4) * exp(-t2 * 50.0)
	return slide * 0.5 + c1 + c2


func _mag_out(t: float, _d: float, st: Dictionary) -> float:
	return (_lp(st, _noise(), 0.4) * 0.6 + _sin(1500.0, t) * 0.25) * exp(-t * 30.0)


func _mag_in(t: float, _d: float, _st: Dictionary) -> float:
	var t2 := t - 0.08
	var click := 0.0 if t2 < 0.0 else (_noise() * 0.9 + _sin(2100.0, t2) * 0.5) * exp(-t2 * 70.0)
	return _noise() * 0.25 * exp(-t * 40.0) + click


func _shell_in(t: float, _d: float, st: Dictionary) -> float:
	return (_lp(st, _noise(), 0.5) * 0.5 + _sin(1700.0, t) * 0.3) * exp(-t * 45.0)


func _crank(t: float, _d: float, st: Dictionary) -> float:
	# szarpnięcie linki rozrusznika i zapłon silnika
	var pull := _lp(st, _noise(), 0.3) * (0.6 if t < 0.35 else 0.0)
	var fire := 0.0 if t < 0.35 else (_sin(48.0, t) * 0.5 + _lp(st, _noise(), 0.15, "lp2") * 0.6) * minf(1.0, (t - 0.35) * 6.0)
	return pull + fire * (1.0 - t * 0.3)


func _beep(t: float, _d: float, _st: Dictionary) -> float:
	return _sin(2600.0, t) * 0.45 * (1.0 if fmod(t, 0.12) < 0.07 else 0.0)


func _ring(t: float, _d: float, _st: Dictionary) -> float:
	# dzwonek budzika: młoteczek o dwa dzwonki
	var hit := 1.0 if fmod(t, 0.05) < 0.025 else -1.0
	return (_sin(2200.0, t) * 0.4 + _sin(3100.0, t) * 0.25) * (0.6 + 0.4 * hit)


func _saw(t: float, d: float, st: Dictionary) -> float:
	# piła: szorstki szum z pulsowaniem zębów, rośnie i opada z ruchem ręki
	var teeth := 0.5 + 0.5 * sin(TAU * 38.0 * t)
	var x := (_noise() - _lp(st, _noise(), 0.08)) * teeth
	return x * sin(PI * t / d) * 0.8


func _rip(t: float, d: float, st: Dictionary) -> float:
	# darcie materiału: trzeszczące włókna
	var x := _noise() if _rng.randf() < 0.35 + 0.4 * sin(t * 60.0 + st["seed"] * 9.0) else 0.0
	return _lp(st, x, 0.5) * sin(PI * t / d) * 1.2


func _chop(t: float, _d: float, st: Dictionary) -> float:
	# nóż w deskę: stuk i chrupnięcie
	return (_lp(st, _noise(), 0.3) * 1.5 + _sin(320.0, t) * 0.3) * exp(-t * 45.0)


func _sizzle(t: float, d: float, st: Dictionary) -> float:
	var x := _noise() - _lp(st, _noise(), 0.2)
	var pop := _noise() * 1.2 if _rng.randf() < 0.004 else 0.0
	return (x * 0.35 + pop) * minf(1.0, t / 0.05) * (1.0 - t / d)


var _loops := {}


## Zapętlony dźwięk z funkcji próbki (generator, szum radia, syrena alarmu).
func _make_loop(key: String, seconds: float, f: Callable) -> AudioStreamWAV:
	if _loops.has(key):
		return _loops[key]
	var n := int(RATE * seconds)
	var out := PackedFloat32Array()
	out.resize(n)
	var st := {"lp": 0.0, "lp2": 0.0, "seed": 0.3}
	for i in n:
		out[i] = f.call(float(i) / RATE, st)
	var peak := 0.001
	for v in out:
		peak = maxf(peak, absf(v))
	for i in n:
		out[i] = out[i] / peak * 0.8
	var w := _wav(out)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	_loops[key] = w
	return w


func engine_loop() -> AudioStreamWAV:
	# warkot silnika spalinowego: 25 zapłonów na sekundę (całkowita liczba w pętli)
	return _make_loop("engine", 1.0, func(t: float, st: Dictionary) -> float:
		var pulse := maxf(0.0, sin(TAU * 25.0 * t)) ** 3
		return pulse * 0.8 + _lp(st, _noise(), 0.2) * 0.4 + sin(TAU * 50.0 * t) * 0.2)


func static_loop() -> AudioStreamWAV:
	return _make_loop("static", 1.0, func(_t: float, st: Dictionary) -> float:
		return _noise() * 0.6 - _lp(st, _noise(), 0.05) * 0.3)


func siren_loop() -> AudioStreamWAV:
	# syrena alarmu: ton wznoszący i opadający co sekundę (pełny okres w pętli)
	return _make_loop("siren", 2.0, func(t: float, st: Dictionary) -> float:
		var f := 700.0 + 500.0 * (0.5 - 0.5 * cos(PI * t))
		st["ph"] = float(st.get("ph", 0.0)) + TAU * f / RATE
		return sign(sin(float(st["ph"]))) * 0.5)


var _crackle_loop: AudioStreamWAV


## Zapętlony trzask ogniska (2 s).
func crackle_loop() -> AudioStreamWAV:
	if _crackle_loop != null:
		return _crackle_loop
	var n := RATE * 2
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var pop := 0.0
	for i in n:
		lp += 0.02 * (_noise() - lp)
		if _rng.randf() < 0.0012:
			pop = _noise() * 1.6
		pop *= 0.985
		out[i] = lp * 0.9 + pop * _noise() * 0.6
	var blend := int(0.1 * RATE)
	for i in blend:
		var a := float(i) / blend
		out[i] = out[i] * a + out[n - blend + i] * (1.0 - a)
	out.resize(n - blend)
	_crackle_loop = _wav(out)
	_crackle_loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_crackle_loop.loop_begin = 0
	_crackle_loop.loop_end = out.size()
	return _crackle_loop


var _rain_loop: AudioStreamWAV


## Zapętlony szum deszczu (2 s, bez szwu).
func rain_loop() -> AudioStreamWAV:
	if _rain_loop != null:
		return _rain_loop
	var n := RATE * 2
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var x := _noise()
		lp += 0.45 * (x - lp)
		lp2 += 0.04 * (x - lp2)
		var drop := 0.0
		if _rng.randf() < 0.0015:
			drop = _noise() * 1.5  # pojedyncze krople
		out[i] = (lp - lp2) * 0.5 + drop * 0.3
	# płynne przejście końca w początek
	var blend := int(0.1 * RATE)
	for i in blend:
		var a := float(i) / blend
		out[i] = out[i] * a + out[n - blend + i] * (1.0 - a)
	out.resize(n - blend)
	_rain_loop = _wav(out)
	_rain_loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_rain_loop.loop_begin = 0
	_rain_loop.loop_end = out.size()
	return _rain_loop


func _glass(t: float, _d: float, st: Dictionary) -> float:
	# tłuczone szkło: trzask i dzwoniące odłamki
	var crash := (_noise() - _lp(st, _noise(), 0.3)) * exp(-t * 9.0)
	var tink := 0.0
	if _rng.randf() < 0.006 * exp(-t * 3.0):
		st["lp2"] = _rng.randf_range(2500.0, 5200.0)
	tink = _sin(float(st["lp2"]), t) * exp(-fmod(t, 0.09) * 40.0) * 0.3
	return crash * 1.1 + tink
