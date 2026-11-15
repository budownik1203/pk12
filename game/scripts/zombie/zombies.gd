extends Node
## Zombie w świecie: ustawienia piaskownicy (data/sandbox.json), siatka
## nawigacji pieczona przy starcie z brył statycznych, strefy (grunt za oknem
## i pokój), zasięg wzroku zależny od światła, słuch z hałasu, rany zadawane
## graczowi i zakażenie zgodnie z piaskownicą.

const ZombieScript := preload("res://scripts/zombie/zombie.gd")
const RoomBuilder := preload("res://scripts/room_builder.gd")

var main
var settings := {}
var zombies: Array = []
var region: NavigationRegion3D
var window_sill := RoomBuilder.WINDOW_SILL
var door_wall_x := RoomBuilder.ROOM_W / 2.0
var kills := 0
var hits_on_player := 0
var _next_id := 1
var _rng := RandomNumberGenerator.new()


func setup(main_node) -> void:
	main = main_node
	_rng.randomize()
	var f := FileAccess.open("res://data/sandbox.json", FileAccess.READ)
	settings = JSON.parse_string(f.get_as_text()) if f != null else {}
	_bake_navigation()
	main.noise.noise_made.connect(_on_noise)


func start_population() -> void:
	# siatka nawigacji jest gotowa dopiero po pierwszej synchronizacji mapy;
	# wcześniej losowanie punktów zawodzi i nikt by się nie pojawił
	var m: RID = main.world.get_world_3d().navigation_map
	for i in 120:
		if NavigationServer3D.map_get_iteration_id(m) > 0:
			break
		await get_tree().physics_frame
	var placed := 0
	var tries := 0
	while placed < int(settings.get("start_zombies", 10)) and tries < 200:
		tries += 1
		var p := random_point("out", _rng)
		if p.distance_to(main.player.global_position) < 14.0:
			continue  # nie tuż przy starcie
		spawn(p)
		placed += 1


func _bake_navigation() -> void:
	region = NavigationRegion3D.new()
	region.name = "Nawigacja"
	var nm := NavigationMesh.new()
	# wymiary w pełnych oczkach siatki (0,25 m), żeby wypiekanie nie zaokrąglało
	nm.agent_radius = 0.25
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, main.world)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	region.navigation_mesh = nm
	main.world.add_child(region)


# --- przestrzeń ----------------------------------------------------------------------

func zone_of(p: Vector3) -> String:
	return "in" if main.town.in_start_house(p) else "out"


## Punkt przed oknem po danej stronie (tam zombie wyrywa deski albo przełazi).
func window_point(zone: String) -> Vector3:
	var x := (RoomBuilder.WINDOW_X0 + RoomBuilder.WINDOW_X1) / 2.0
	var wall_out := RoomBuilder.ROOM_D / 2.0 + RoomBuilder.WALL
	return Vector3(x, 0.02, wall_out + 0.45) if zone == "out" else Vector3(x, 0.02, RoomBuilder.ROOM_D / 2.0 - 0.45)


func random_point(zone: String, rng: RandomNumberGenerator) -> Vector3:
	var p: Vector3
	if zone == "out":
		# losowy punkt po siatce nawigacji poza domem startowym (ulica, podwórka, domy)
		var m: RID = main.world.get_world_3d().navigation_map
		for attempt in 12:
			var q := NavigationServer3D.map_get_random_point(m, 1, false)
			if zone_of(q) == "out" and q != Vector3.ZERO:
				return q
		var z0 := RoomBuilder.ROOM_D / 2.0 + RoomBuilder.WALL
		p = Vector3(rng.randf_range(-4.1, -0.7), 0.02, rng.randf_range(z0 + 0.4, z0 + 2.6))
	elif rng.randf() < 0.8:
		p = Vector3(rng.randf_range(-4.0, 4.0), 0.02, rng.randf_range(-3.0, 3.0))
	else:
		p = Vector3(rng.randf_range(4.9, 7.1), 0.02, rng.randf_range(-3.0, 3.0))
	var map: RID = main.world.get_world_3d().navigation_map
	var c := NavigationServer3D.map_get_closest_point(map, p)
	return c if c != Vector3.ZERO else p


## Zasięg wzroku zombie na gracza: w ciemności kilka metrów, w świetle kilkanaście.
func sight_range(z) -> float:
	var pl = main.player
	var pp: Vector3 = pl.global_position
	var pzone := zone_of(pp)
	var light: float = main.light_level()
	light *= 1.0 - main.character.level("skradanie") * 0.04  # skradanie: trudniej zauważyć
	if pl.height < pl.STAND_HEIGHT - 0.1:
		light *= 0.6  # kucający trudniej zauważyć
	if zone_of(z.global_position) != pzone:
		light *= 0.7  # przez okno
	var r := lerpf(3.0, 15.0, clampf(light, 0.0, 1.0))
	if main.get("weather") != null:
		r *= main.weather.sight_factor()  # deszcz i mgła
	return r


func _on_noise(pos: Vector3, loudness: float) -> void:
	for z in zombies:
		if not z.is_dead():
			z.hear(pos, loudness)


# --- populacja -----------------------------------------------------------------------

func spawn(pos: Vector3):
	var z = ZombieScript.new()
	main.world.add_child(z)
	var speed := {"powolne": 0.8, "zwykle": 1.0, "szybkie": 1.6, "biegacze": 3.0}
	z.setup(main, self, _next_id, pos, float(speed.get(str(settings.get("speed", "zwykle")), 1.0)))
	z.hp = float(settings.get("zombie_hp", 100.0))
	_next_id += 1
	zombies.append(z)
	return z


func alive_count() -> int:
	var n := 0
	for z in zombies:
		if not z.is_dead():
			n += 1
	return n


func on_zombie_died(_z) -> void:
	kills += 1


func clear_all() -> void:
	for z in zombies:
		z.queue_free()
	zombies.clear()


# --- rany gracza ---------------------------------------------------------------------

const TARGET_SEGMENTS := {
	"ramie_l": 9, "ramie_p": 9, "przedramie_l": 12, "przedramie_p": 12, "dlon_l": 8, "dlon_p": 8,
	"klatka": 10, "brzuch": 8, "szyja": 6, "glowa": 4, "udo_l": 3, "udo_p": 3, "lydka_l": 2, "lydka_p": 2,
}


func _pick(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := _rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return weights.keys()[0]


## Trafienie zombie: rana na losowej części ciała (ubranie może zatrzymać)
## i zakażenie według piaskownicy.
func wound_player(_z) -> void:
	hits_on_player += 1
	var seg := _pick(TARGET_SEGMENTS)
	var types: Dictionary = settings.get("wound_types", {"zadrapanie": 50, "rana_cieta": 30, "ugryzienie": 20})
	var type := _pick(types)
	var w: Dictionary = main.health.wound(seg, type, _rng.randf_range(0.45, 0.85))
	main.sound.play("hit_flesh", main.player.camera.global_position + Vector3.DOWN * 0.4, 0.0, 1.2)
	main.set_hurt_flash()
	if w.is_empty():
		main.hud.show_message(tr("MSG_ZOMBIE_CLOTHES") % tr("SEG_" + seg))
		return
	main.hud.show_message(tr("MSG_ZOMBIE_WOUND") % [tr("WOUND_" + type), tr("SEG_" + seg)])
	var chance: Dictionary = settings.get("infection", {"zadrapanie": 0.07, "rana_cieta": 0.25, "ugryzienie": 1.0})
	if _rng.randf() < float(chance.get(type, 0.0)):
		main.health.infect_knox()


func to_dict() -> Array:
	var out: Array = []
	for z in zombies:
		out.append(z.to_dict())
	return out


func from_dict(list: Array) -> void:
	clear_all()
	for d in list:
		var p: Array = d.get("pos", [0, 0, 0])
		var z = spawn(Vector3(float(p[0]), float(p[1]), float(p[2])))
		z.hp = float(d.get("hp", 100.0))
		if bool(d.get("dead", false)):
			z.die(Vector3(float(d.get("fwd", [0, 1])[0]), 0, float(d.get("fwd", [0, 1])[1])))
			kills -= 1
