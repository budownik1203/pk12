extends Node
## Zegar doby. Doba gry trwa godzinę prawdziwego czasu (jak domyślnie w PZ),
## czyli minuta gry to 2,5 sekundy. Słońce wschodzi o 6, zachodzi o 20 i świeci
## od południa, czyli przez okno pokoju; nocą tło za oknem i światło otoczenia
## gasną, zostają lampy i latarka. Temperatura na zewnątrz ma cykl dobowy
## (jesień: 4–15 °C, najcieplej około 15:00). Podczas snu czas biegnie szybciej.

const GAME_SECONDS_PER_REAL := 24.0  # 1 godzina = 1 doba
const START_MINUTE := 8 * 60          # dzień 1, 8:00
const SUNRISE := 6.0
const SUNSET := 20.0

var minutes := float(START_MINUTE)    # minuty od północy dnia 1
var speed := 1.0                      # mnożnik (sen)
var sun: DirectionalLight3D
var env: Environment
var weather                           # weather.gd: chmury przyciemniają, mgła gęstnieje


func setup(world: Node3D) -> void:
	for n in world.find_children("*", "WorldEnvironment", true, false):
		env = (n as WorldEnvironment).environment
	sun = DirectionalLight3D.new()
	sun.name = "Slonce"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 25.0
	sun.light_color = Color(1.0, 0.92, 0.8)
	world.add_child(sun)
	_update_sky()


func _process(delta: float) -> void:
	advance(delta * GAME_SECONDS_PER_REAL * speed / 60.0)


## Przesuwa czas o podaną liczbę minut gry.
func advance(game_minutes: float) -> void:
	minutes += game_minutes
	_update_sky()


func day() -> int:
	return int(minutes / 1440.0) + 1


func hour() -> float:
	return fmod(minutes, 1440.0) / 60.0


## Ułamek doby gry, który mija w jednej sekundzie prawdziwej (do potrzeb i gojenia).
func game_hours(real_delta: float) -> float:
	return real_delta * GAME_SECONDS_PER_REAL * speed / 3600.0


func is_night() -> bool:
	var h := hour()
	return h < SUNRISE or h > SUNSET


func text() -> String:
	var h := int(hour())
	var m := int(fmod(minutes, 60.0))
	return tr("CLOCK") % [day(), h, m]


## Temperatura na zewnątrz w °C.
func outside_temp() -> float:
	var h := hour()
	var t := 9.5 + 5.5 * cos((h - 15.0) / 24.0 * TAU)
	if weather != null:
		t += weather.temp_mod
	return t


## 0 w nocy, 1 w południe (ilość światła dziennego).
func daylight() -> float:
	var h := hour()
	if h <= SUNRISE - 0.5 or h >= SUNSET + 0.5:
		return 0.0
	var t := (h - (SUNRISE - 0.5)) / (SUNSET - SUNRISE + 1.0)
	return clampf(sin(t * PI) * 1.3, 0.0, 1.0)


func _update_sky() -> void:
	if sun == null:
		return
	var d := daylight()
	var cloud := 0.0
	var fog := 0.0
	var flash := 0.0
	if weather != null:
		cloud = weather.cloud
		fog = weather.fog
		flash = weather.flash()
	d *= 1.0 - cloud * 0.55
	var h := hour()
	# słońce idzie ze wschodu (-X) przez południe (+Z) na zachód (+X)
	var t := clampf((h - SUNRISE) / (SUNSET - SUNRISE), 0.0, 1.0)
	var azimuth := lerpf(-1.3, 1.3, t)
	var elevation := maxf(0.05, sin(t * PI) * 0.75)
	# kierunek padania światła: od słońca (południe to +Z za oknem) do wnętrza
	var dir := Vector3(-sin(azimuth), -sin(elevation), -cos(azimuth)).normalized()
	sun.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(0, 10, 0))
	sun.light_energy = d * 1.6 * (1.0 - cloud * 0.5) + flash * 2.5
	sun.visible = d > 0.01 or flash > 0.0
	var warm := 1.0 - clampf(elevation / 0.5, 0.0, 1.0)
	sun.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.62, 0.38), warm)
	if env != null:
		env.background_color = Color(0.02, 0.025, 0.04).lerp(Color(0.48, 0.58, 0.68), d).lerp(Color(0.75, 0.5, 0.35), warm * d * 0.6)
		env.background_color = env.background_color.lerp(Color(0.35, 0.37, 0.4) * (0.15 + d), cloud * 0.7).lerp(Color(0.85, 0.88, 1.0), flash * 0.8)
		env.ambient_light_energy = 0.1 + d * 0.28 + flash * 0.6
		env.fog_density = 0.014 + fog * 0.09  # na otwartej ulicy rzadka mgła, gęsta tylko w pogodzie „mgła”
		env.fog_light_color = Color(0.06, 0.07, 0.09).lerp(Color(0.3, 0.32, 0.34), d)


func to_dict() -> Dictionary:
	return {"minutes": minutes}


func from_dict(d: Dictionary) -> void:
	minutes = float(d.get("minutes", START_MINUTE))
	speed = 1.0
	_update_sky()
