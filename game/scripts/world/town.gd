extends Node
## Osiedle wokół domu startowego: grunt, trzy ulice z chodnikami (Lipowa, Polna
## i łącząca je Krótka), granice terenu i 16 domów generowanych z ziarna świata
## (data/sandbox.json "world_seed").
## Dom składa się z modułów: parter (zawsze), piętro ze schodami (mniej więcej co
## drugi dom), piwnica ze schodami w dół (co trzeci). Parter i piętro mają pokoje
## z rodzajem (kuchnia, łazienka, sypialnia, salon, garaż) i meblami-pojemnikami.
## Każdy dom ma adres (ulica i numer, tabliczka z nazwiskiem) i mieszkańców
## (data/residents.json): ich zawody dokładają rzeczy do domu, a mieszkańcy,
## którzy zmienili się w zombie, noszą przy sobie klucz do domu i rzeczy z życia.
## Dom, z którego wszyscy uciekli, zwykle jest zamknięty; zapasowy klucz bywa
## pod wycieraczką. Łupy losują się raz, przy nowej grze, i nic się nie odnawia.

const Tex := preload("res://scripts/textures.gd")
const RoomBuilder := preload("res://scripts/room_builder.gd")
const DoorScript := preload("res://scripts/world/simple_door.gd")
const GlassScript := preload("res://scripts/world/glass_pane.gd")
const ItemScript := preload("res://scripts/inventory/item.gd")

const H := 2.8
const WALL := 0.18
const SLAB := 0.2
const STEP_RISE := 0.2
const STEP_RUN := 0.28
const CELLAR := 2.6
const STAIR_W := 1.2                                   # głębokość piwnicy
const AREA := Rect2(-50.0, -26.0, 106.0, 90.0)        # teren (x, z)
const ROAD_Z0 := 9.0                                  # ul. Lipowa (testy, pogoda)
const ROAD_Z1 := 15.0
## ulice: [nazwa, jezdnia (x, z, szerokość, długość), oś "x" albo "z"]
const STREETS := [["Lipowa", Rect2(-50.0, 9.0, 106.0, 6.0), "x"], ["Polna", Rect2(-50.0, 43.0, 106.0, 6.0), "x"],
		["Krótka", Rect2(26.0, 15.0, 6.0, 28.0), "z"]]
const START_RECT := Rect2(-4.8, -3.8, 12.6, 7.6)      # dom startowy (sala + komórka)
## działki: [x0, z0, drzwi od strony "N" albo "S", ulica, numer]
const LOTS := [[-24.0, -4.0, "S", "Lipowa", 3], [12.0, -4.0, "S", "Lipowa", 7], [-22.0, 17.5, "N", "Lipowa", 4],
		[-5.0, 17.5, "N", "Lipowa", 6], [12.0, 17.5, "N", "Lipowa", 8], [-40.0, -4.0, "S", "Lipowa", 1],
		[36.0, -4.0, "S", "Lipowa", 9], [-40.0, 17.5, "N", "Lipowa", 2], [36.0, 17.5, "N", "Lipowa", 10],
		[-40.0, 30.5, "S", "Polna", 1], [-22.0, 30.5, "S", "Polna", 3], [-5.0, 30.5, "S", "Polna", 5],
		[36.0, 30.5, "S", "Polna", 7], [-22.0, 51.5, "N", "Polna", 2], [-5.0, 51.5, "N", "Polna", 4],
		[12.0, 51.5, "N", "Polna", 6]]
const ROOM_KINDS := ["kuchnia", "salon", "sypialnia", "lazienka", "garaz"]
## pojemniki w pokojach: [rodzaj łupu, rozmiar siatki, wymiary mebla, kolor]
const FURNITURE := {
	"kuchnia": [["lodowka", [4, 5], Vector3(0.7, 1.8, 0.65), Color(0.78, 0.78, 0.74)],
			["szafka_kuchenna", [5, 4], Vector3(1.2, 0.9, 0.6), Color(0.45, 0.33, 0.2)]],
	"lazienka": [["apteczka_scienna", [3, 3], Vector3(0.5, 0.6, 0.18), Color(0.85, 0.85, 0.82)]],
	"sypialnia": [["szafa", [5, 6], Vector3(1.2, 2.0, 0.6), Color(0.35, 0.25, 0.16)]],
	"salon": [["regal", [4, 4], Vector3(1.0, 1.7, 0.4), Color(0.4, 0.3, 0.2)]],
	"garaz": [["skrzynka_narzedziowa", [5, 3], Vector3(0.8, 0.5, 0.45), Color(0.6, 0.15, 0.1)]],
}
var main
var world: Node3D
var rng := RandomNumberGenerator.new()
var buildings: Array = []           # Rect2 (x, z) wnętrz domów, bez domu startowego
var houses: Array = []              # opis domów: adres, moduły, mieszkańcy, zamek
var ground_holes: Array = []        # Rect2 otworów w gruncie (zejścia do piwnic)
var doormats: Array = []            # [id pojemnika wycieraczki, numer domu]
var _res := {}
var _families: Array = []
var _parent: Node3D = null          # węzeł bieżącego domu (doczytywanie: dom włącza się i wyłącza w całości)
var house_nodes: Array = []         # Node3D domów w kolejności LOTS
var doors: Array = []
var panes: Array = []
var loot_spots: Array = []          # [id pojemnika, rodzaj łupu]
var _loot := {}
var _mats := {}


func setup(main_node, world_seed: int) -> void:
	main = main_node
	world = main.world
	rng.seed = world_seed
	var f := FileAccess.open("res://data/loot.json", FileAccess.READ)
	_loot = JSON.parse_string(f.get_as_text())
	_res = JSON.parse_string(FileAccess.get_file_as_string("res://data/residents.json"))
	_door(-1, RoomBuilder.exit_hinge(), "wyjscie")  # drzwi domu startowego na podwórko
	for i in LOTS.size():
		var lot: Array = LOTS[i]
		_house(i, float(lot[0]), float(lot[1]), str(lot[2]))
	_ground()  # po domach: grunt dostaje otwory nad zejściami do piwnic


func _mat(key: String, color: Color) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.95
		_mats[key] = m
	return _mats[key]


func _box(node_name: String, center: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	return RoomBuilder._static_box(_parent if _parent != null else world, node_name, center, size, mat)


# --- teren -----------------------------------------------------------------------

func _ground() -> void:
	var c := AREA.get_center()
	# wierzch gruntu minimalnie pod podłogą domów, żeby nie migotał; z otworami nad piwnicami
	var grass := Tex.material("grass", true, 0.25)
	for r in subtract_rects(AREA, ground_holes):
		var rr := r as Rect2
		_box("Grunt", Vector3(rr.get_center().x, -0.16, rr.get_center().y), Vector3(rr.size.x, 0.3, rr.size.y), grass)
	var asphalt := Tex.material("asphalt", true, 0.3)
	var curb := Tex.material("concrete", true, 0.5)
	var line := _mat("pasy", Color(0.75, 0.72, 0.6))
	for st in STREETS:
		var r: Rect2 = st[1]
		var along_x: bool = st[2] == "x"
		_box("Jezdnia" + str(st[0]), Vector3(r.get_center().x, -0.005, r.get_center().y), Vector3(r.size.x, 0.01, r.size.y), asphalt)
		if along_x:
			_box("Chodnik" + str(st[0]) + "N", Vector3(r.get_center().x, 0.04, r.position.y - 0.75), Vector3(r.size.x, 0.1, 1.5), curb)
			_box("Chodnik" + str(st[0]) + "S", Vector3(r.get_center().x, 0.04, r.end.y + 0.75), Vector3(r.size.x, 0.1, 1.5), curb)
			var x := r.position.x + 2.0
			while x < r.end.x - 2.0:
				if x < 25.0 or x > 33.0:  # bez pasów na skrzyżowaniu z Krótką
					_box("Pas", Vector3(x, 0.002, r.get_center().y), Vector3(2.0, 0.006, 0.15), line)
				x += 5.0
		else:
			# poprzeczna: chodniki między chodnikami ulic głównych
			var z0 := r.position.y + 1.5
			var z1 := r.end.y - 1.5
			_box("Chodnik" + str(st[0]) + "W", Vector3(r.position.x - 0.75, 0.04, (z0 + z1) / 2.0), Vector3(1.5, 0.1, z1 - z0), curb)
			_box("Chodnik" + str(st[0]) + "E", Vector3(r.end.x + 0.75, 0.04, (z0 + z1) / 2.0), Vector3(1.5, 0.1, z1 - z0), curb)
			var z := r.position.y + 3.0
			while z < r.end.y - 3.0:
				_box("Pas", Vector3(r.get_center().x, 0.002, z), Vector3(0.15, 0.006, 2.0), line)
				z += 5.0
		# tabliczka z nazwą ulicy przy wjeździe
		_street_sign(str(st[0]), Vector3(r.position.x + 3.0, 0, r.position.y - 1.7) if along_x else Vector3(r.position.x - 1.7, 0, r.position.y + 3.0))
	# granice terenu (niewidzialne)
	for b in [[Vector3(c.x, 2.0, AREA.position.y), Vector3(AREA.size.x, 4.0, 0.2)],
			[Vector3(c.x, 2.0, AREA.end.y), Vector3(AREA.size.x, 4.0, 0.2)],
			[Vector3(AREA.position.x, 2.0, c.y), Vector3(0.2, 4.0, AREA.size.y)],
			[Vector3(AREA.end.x, 2.0, c.y), Vector3(0.2, 4.0, AREA.size.y)]]:
		var wall := StaticBody3D.new()
		wall.name = "GranicaTerenu"
		wall.position = b[0]
		var shape := BoxShape3D.new()
		shape.size = b[1]
		var col := CollisionShape3D.new()
		col.shape = shape
		wall.add_child(col)
		world.add_child(wall, true)
	# kilka drzew (pień i korona z prostopadłościanów)
	var bark := _mat("kora", Color(0.25, 0.18, 0.12))
	var leaves := _mat("liscie", Color(0.16, 0.24, 0.13))
	for k in 40:
		var p := Vector2(rng.randf_range(AREA.position.x + 3, AREA.end.x - 3), rng.randf_range(AREA.position.y + 3, AREA.end.y - 3))
		if _blocked(p, 4.0):
			continue
		var t := _box("Drzewo", Vector3(p.x, 1.5, p.y), Vector3(0.35, 3.0, 0.35), bark)
		var crown := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(2.4, 2.0, 2.4)
		cm.material = leaves
		crown.mesh = cm
		crown.position = Vector3(0, 2.2, 0)
		t.add_child(crown)


## Czy punkt (x, z) wypada na drodze, domu albo ich otoczeniu.
func _blocked(p: Vector2, margin: float) -> bool:
	for st in STREETS:
		if (st[1] as Rect2).grow(margin + 1.5).has_point(p):
			return true
	if START_RECT.grow(margin).has_point(p):
		return true
	for lot in LOTS:
		if Rect2(float(lot[0]) - margin, float(lot[1]) - margin, 11.0 + margin * 2.0, 9.0 + margin * 2.0).has_point(p):
			return true
	return false


# --- ściany ----------------------------------------------------------------------

## Ściana od a do b (pozioma wzdłuż X albo Z) z otworami [od, szerokość, dół, góra].
func _wall(base: String, a: Vector3, b: Vector3, openings: Array, mat: Material, y0: float = 0.0, h: float = H) -> void:
	var along := b - a
	var length := along.length()
	var dir := along / length
	var along_x := absf(dir.x) > 0.5
	openings.sort_custom(func(o1, o2): return o1[0] < o2[0])
	var cursor := 0.0
	var k := 0
	for o in openings:
		var s := float(o[0])
		var w := float(o[1])
		if s > cursor + 0.01:
			_wall_piece(base + str(k), a, dir, cursor, s, y0, y0 + h, along_x, mat)
			k += 1
		if float(o[2]) > 0.01:
			_wall_piece(base + str(k) + "d", a, dir, s, s + w, y0, y0 + float(o[2]), along_x, mat)
		if float(o[3]) < h - 0.01:
			_wall_piece(base + str(k) + "g", a, dir, s, s + w, y0 + float(o[3]), y0 + h, along_x, mat)
		cursor = s + w
		k += 1
	if cursor < length - 0.01:
		_wall_piece(base + str(k), a, dir, cursor, length, y0, y0 + h, along_x, mat)


func _wall_piece(n: String, a: Vector3, dir: Vector3, t0: float, t1: float, y0: float, y1: float, along_x: bool, mat: Material) -> void:
	var mid := a + dir * ((t0 + t1) / 2.0)
	var size := Vector3(t1 - t0, y1 - y0, WALL) if along_x else Vector3(WALL, y1 - y0, t1 - t0)
	_box(n, Vector3(mid.x, (y0 + y1) / 2.0, mid.z), size, mat)


# --- dom -------------------------------------------------------------------------

func _house(i: int, x0: float, z0: float, door_side: String) -> void:
	_parent = Node3D.new()
	_parent.name = "Dom_%d" % i
	world.add_child(_parent)
	house_nodes.append(_parent)
	_build_house(i, x0, z0, door_side)
	_parent = null


func _build_house(i: int, x0: float, z0: float, door_side: String) -> void:
	var lot: Array = LOTS[i]
	var w := rng.randf_range(8.0, 11.0)
	var d := rng.randf_range(7.0, 9.0)
	var x1 := x0 + w
	var z1 := z0 + d
	var two_floors := rng.randf() < 0.5
	var cellar := rng.randf() < 0.5
	buildings.append(Rect2(x0, z0, w, d))
	var outer := _mat("elewacja%d" % (i % 3), [Color(0.55, 0.5, 0.42), Color(0.45, 0.42, 0.4), Color(0.5, 0.38, 0.3)][i % 3])
	var inner := Tex.material("wall", true, 0.4)
	var floor_m := Tex.material("floor" if i % 2 == 0 else "tiles", true, 0.5)
	# ściana od ulicy: drzwi i dwa okna; tylna: jedno okno; boczne pełne
	var front_z := z1 if door_side == "S" else z0
	var back_z := z0 if door_side == "S" else z1
	var back_dir := 1.0 if back_z == z0 else -1.0     # od tylnej ściany w głąb domu
	var back_in := back_z + back_dir * WALL / 2.0     # wewnętrzna strona tylnej ściany
	var door_off := rng.randf_range(1.5, w - 2.5)
	var win_a := 0.6 if door_off > 3.0 else door_off + 1.8
	var win_b := w - 1.8 if door_off < w - 3.5 else door_off - 2.0
	var front_open := [[door_off, 1.0, 0.0, 2.1], [win_a, 1.1, 0.9, 2.0], [win_b, 1.1, 0.9, 2.0]]
	_wall("Dom%dFront" % i, Vector3(x0, 0, front_z), Vector3(x1, 0, front_z), front_open, outer)
	var back_win := rng.randf_range(1.0, w - 2.2)
	_wall("Dom%dTyl" % i, Vector3(x0, 0, back_z), Vector3(x1, 0, back_z), [[back_win, 1.1, 0.9, 2.0]], outer)
	_wall("Dom%dBokW" % i, Vector3(x0, 0, z0), Vector3(x0, 0, z1), [], outer)
	_wall("Dom%dBokE" % i, Vector3(x1, 0, z0), Vector3(x1, 0, z1), [], outer)
	# drzwi wejściowe na zawiasie
	var door_ctl = _door(i, Vector3(x0 + door_off, 0, front_z))
	# szyby
	for o in [[win_a, front_z], [win_b, front_z], [back_win, back_z]]:
		_pane(i, Vector3(x0 + float(o[0]) + 0.55, 1.45, float(o[1])), Vector2(1.06, 1.06))
	# pokoje: podział wzdłuż X, czasem jeszcze wzdłuż Z
	var split_x := x0 + w * rng.randf_range(0.42, 0.58)
	var door_cx := x0 + door_off + 0.5
	if absf(split_x - door_cx) < 1.0:
		# ścianka działowa nie może wypaść na drzwiach wejściowych
		split_x = door_cx + (1.1 if door_cx < x0 + w * 0.5 else -1.1)
	# przejścia między pokojami z dala od ścian z meblami (tylnej i frontowej)
	_wall("Dom%dDzialowaX" % i, Vector3(split_x, 0, z0), Vector3(split_x, 0, z1), [[rng.randf_range(1.4, d - 2.4), 1.0, 0.0, 2.1]], inner)
	var rooms: Array = [Rect2(x0, z0, split_x - x0, d)]
	if rng.randf() < 0.7 and not cellar:  # dom z piwnicą: pokój wschodni na całą głębokość (miejsce na zejście)
		var split_z := z0 + d * rng.randf_range(0.4, 0.6)
		_wall("Dom%dDzialowaZ" % i, Vector3(split_x, 0, split_z), Vector3(x1, 0, split_z), [[rng.randf_range(0.6, maxf(0.7, x1 - split_x - 1.7)), 1.0, 0.0, 2.1]], inner)
		rooms.append(Rect2(split_x, z0, x1 - split_x, split_z - z0))
		rooms.append(Rect2(split_x, split_z, x1 - split_x, z1 - split_z))
	else:
		rooms.append(Rect2(split_x, z0, x1 - split_x, d))
	# schody na piętro: przy ścianie zachodniej, górny stopień przy tylnej ścianie
	var stair_len := STEP_RUN * roundi((H + SLAB) / STEP_RISE)
	var up_hole := Rect2()
	if two_floors:
		var sz := back_in if back_dir > 0.0 else back_in - stair_len
		up_hole = Rect2(x0 + WALL / 2.0, sz, STAIR_W + 0.05, stair_len)
		_stairs("Dom%dSchody" % i, Vector3(x0 + WALL / 2.0 + STAIR_W / 2.0, 0.0, back_in), back_dir, roundi((H + SLAB) / STEP_RISE), 0.0, true)
	# piwnica pod pokojem przy tylnej ścianie po wschodniej stronie; schody w dół przy ścianie wschodniej
	var cellar_room := Rect2()
	var down_hole := Rect2()
	if cellar:
		for r in rooms.slice(1):
			var rr := r as Rect2
			if absf((rr.position.y if back_dir > 0.0 else rr.end.y) - back_z) < 0.05 and rr.size.y > STEP_RUN * 13 + 1.2:
				cellar_room = rr
		if cellar_room.size.x <= 0.0:
			cellar = false
	if cellar:
		var clen := STEP_RUN * roundi(CELLAR / STEP_RISE)
		var cz := back_in if back_dir > 0.0 else back_in - clen
		down_hole = Rect2(x1 - WALL / 2.0 - STAIR_W - 0.05, cz, STAIR_W + 0.05, clen)
		ground_holes.append(down_hole)
		_cellar(i, cellar_room, down_hole, back_in, back_dir)
	# podłoga parteru z otworem nad zejściem do piwnicy
	for r in subtract_rects(Rect2(x0, z0, w, d), [down_hole] if cellar else []):
		var rr := r as Rect2
		_box("Dom%dPodloga" % i, Vector3(rr.get_center().x, -0.09, rr.get_center().y), Vector3(rr.size.x, 0.2, rr.size.y), floor_m)
	var roof_m := _mat("dach", Color(0.22, 0.12, 0.1))
	var kinds := ROOM_KINDS.duplicate()
	kinds.shuffle()
	kinds.erase("kuchnia")
	kinds.push_front("kuchnia")  # każdy dom ma kuchnię
	for r in rooms.size():
		var room_r: Rect2 = rooms[r]
		var skip_w := STAIR_W + 0.3 if r == 0 and two_floors else 0.0
		var skip_e := STAIR_W + 1.3 if cellar and room_r == cellar_room else 0.0  # metr dojścia do zejścia
		_furnish(i, r, room_r, kinds[r % kinds.size()], back_z, 0.0, skip_w, skip_e, x0 + door_off + 0.5)
	# prąd: lampa w każdym pokoju, jeden włącznik przy drzwiach wejściowych, czasem alarm
	if main.utilities != null:
		for r in rooms:
			var rr := r as Rect2
			main.utilities.add_house_lamp(i, _parent, Vector3(rr.get_center().x, H - 0.15, rr.get_center().y))
		var sw := _box("Wlacznik_dom%d" % i, Vector3(x0 + door_off + 1.25, 1.2, front_z - back_dir * (WALL / 2.0 + 0.02)), Vector3(0.08, 0.12, 0.03), _mat("wlacznik", Color(0.78, 0.76, 0.68)))
		sw.set_meta("house_switch", i)
		if rng.randf() < 0.3:
			main.utilities.add_alarm(i)
	var info := {"index": i, "street": str(lot[3]), "number": int(lot[4]), "rect": Rect2(x0, z0, w, d),
			"floors": 2 if two_floors else 1, "cellar": cellar, "door": door_ctl, "front_z": front_z,
			"door_x": x0 + door_off + 0.5, "rooms": rooms, "key_id": 100 + i}
	# punkty kontrolne (testy, zombie): wejście, schody, piwnica
	info["front"] = Vector3(x0 + door_off + 0.5, 0.0, front_z + back_dir * 1.5)    # przed domem
	info["inside"] = Vector3(x0 + door_off + 0.5, 0.0, front_z - back_dir * 1.2)   # za drzwiami
	if two_floors:
		info["stair_bottom"] = Vector3(up_hole.get_center().x, 0.0, back_in + back_dir * (stair_len + 0.5))
		info["stair_top"] = Vector3(up_hole.get_center().x, H + SLAB, back_in + back_dir * 0.42)
		info["upstairs"] = Vector3(up_hole.end.x + 0.7, H + SLAB, back_in + back_dir * 0.6)
	if cellar:
		info["cellar_entry"] = Vector3(down_hole.position.x - 0.6, 0.0, back_in + back_dir * 0.7)
		info["cellar_bottom"] = Vector3(down_hole.get_center().x, -CELLAR, back_in + back_dir * (down_hole.size.y + 0.5))
	if two_floors:
		_upper_floor(i, x0, z0, w, d, front_z, back_z, back_dir, up_hole, split_x, outer, inner, floor_m)
		info["upper_y"] = H + SLAB
		_box("Dom%dDach" % i, Vector3((x0 + x1) / 2.0, 2.0 * H + SLAB + 0.1, (z0 + z1) / 2.0), Vector3(w + 0.6, 0.2, d + 0.6), roof_m)
	else:
		_box("Dom%dDach" % i, Vector3((x0 + x1) / 2.0, H + 0.1, (z0 + z1) / 2.0), Vector3(w + 0.6, 0.2, d + 0.6), roof_m)
	_residents(info)
	_address(info)
	houses.append(info)


## Schody w górę z pełnych bloków (bez szpar pod stopniami). top: środek
## górnego końca przy ścianie, dir: kierunek biegu od ściany w głąb (+1/-1 wzdłuż Z).
func _stairs(n: String, top: Vector3, dir: float, steps: int, y0: float, _up: bool) -> void:
	var m := Tex.material("wood", true, 0.6)
	for j in steps:
		var zc := top.z + dir * (j + 0.5) * STEP_RUN
		var y_top := y0 + (steps - j) * STEP_RISE  # przy ścianie najwyżej, równo z piętrem
		_box(n + str(j), Vector3(top.x, (y_top + y0) / 2.0, zc), Vector3(STAIR_W, y_top - y0, STEP_RUN), m)


## Piwnica: betonowe ściany pod pokojem, podłoga, schody w dół od otworu w podłodze.
func _cellar(i: int, room: Rect2, hole: Rect2, back_in: float, back_dir: float) -> void:
	var conc := Tex.material("concrete", true, 0.5)
	var y_floor := -CELLAR
	var r := room
	_box("Dom%dPiwnicaPodloga" % i, Vector3(r.get_center().x, y_floor - 0.1, r.get_center().y), Vector3(r.size.x, 0.2, r.size.y), conc)
	var hh := CELLAR - 0.3  # do spodu gruntu
	for wdef in [[Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, 0, r.position.y)], [Vector3(r.position.x, 0, r.end.y), Vector3(r.end.x, 0, r.end.y)],
			[Vector3(r.position.x, 0, r.position.y), Vector3(r.position.x, 0, r.end.y)], [Vector3(r.end.x, 0, r.position.y), Vector3(r.end.x, 0, r.end.y)]]:
		_wall("Dom%dPiwnicaSciana" % i, wdef[0], wdef[1], [], conc, y_floor, hh)
	# schody: wejście przy tylnej ścianie (górny stopień równo z podłogą), bieg w dół
	# od ściany w głąb domu, ostatni stopień schodzi na środek piwnicy
	var steps := roundi(CELLAR / STEP_RISE)
	for j in steps:
		var zc := back_in + back_dir * (j + 0.5) * STEP_RUN
		var y_top := -float(j) * STEP_RISE
		if j == 0:
			y_top = -0.02  # spocznik równo z podłogą
		_box("Dom%dPiwnicaSchody%d" % [i, j], Vector3(hole.position.x + 0.05 + STAIR_W / 2.0, (y_top + y_floor) / 2.0, zc), Vector3(STAIR_W, y_top - y_floor, STEP_RUN), conc)
	# barierki na parterze: zachodnia krawędź otworu poza wejściem przy ścianie i koniec otworu
	var rail := _mat("barierka", Color(0.3, 0.3, 0.32))
	var near := back_in + back_dir * 1.2
	var far := back_in + back_dir * hole.size.y
	_box("Dom%dPiwnicaBarierka" % i, Vector3(hole.position.x - 0.03, 0.45, (near + far) / 2.0), Vector3(0.05, 0.9, absf(far - near)), rail)
	_box("Dom%dPiwnicaBarierkaKoniec" % i, Vector3(hole.get_center().x, 0.45, far + back_dir * 0.03), Vector3(hole.size.x, 0.9, 0.05), rail)
	# regał z zapasami przy ścianie zachodniej piwnicy
	var id := "dom%d_piwnica" % i
	var size := Vector3(0.45, 1.7, 1.2)
	var shelf := _box("Mebel_" + id, Vector3(r.position.x + WALL / 2.0 + size.x / 2.0 + 0.05, y_floor + size.y / 2.0, r.get_center().y), size, _mat("mebel_regal", Color(0.4, 0.3, 0.2)))
	shelf.set_meta("container_id", id)
	main.inventory.register_container(id, [[4, 5]], shelf, "INV_CONTAINER_piwnica")
	loot_spots.append([id, "piwnica"])


## Piętro: strop z otworem nad schodami, ściany z oknami, ścianka działowa,
## barierka przy otworze, meble (sypialnie i łazienka).
func _upper_floor(i: int, x0: float, z0: float, w: float, d: float, front_z: float, back_z: float, back_dir: float,
		hole: Rect2, split_x: float, outer: Material, inner: Material, floor_m: Material) -> void:
	var x1 := x0 + w
	var z1 := z0 + d
	var y0 := H + SLAB
	for r in subtract_rects(Rect2(x0, z0, w, d), [hole]):
		var rr := r as Rect2
		_box("Dom%dStrop" % i, Vector3(rr.get_center().x, H + SLAB / 2.0, rr.get_center().y), Vector3(rr.size.x, SLAB, rr.size.y), floor_m)
	var fa := rng.randf_range(0.8, w * 0.5 - 1.2)
	var fb := rng.randf_range(w * 0.5 + 0.3, w - 1.9)
	_wall("Dom%dPietroFront" % i, Vector3(x0, 0, front_z), Vector3(x1, 0, front_z), [[fa, 1.1, 0.9, 2.0], [fb, 1.1, 0.9, 2.0]], outer, y0)
	var bw := rng.randf_range(w * 0.5, w - 2.0)
	_wall("Dom%dPietroTyl" % i, Vector3(x0, 0, back_z), Vector3(x1, 0, back_z), [[bw, 1.1, 0.9, 2.0]], outer, y0)
	_wall("Dom%dPietroBokW" % i, Vector3(x0, 0, z0), Vector3(x0, 0, z1), [], outer, y0)
	_wall("Dom%dPietroBokE" % i, Vector3(x1, 0, z0), Vector3(x1, 0, z1), [], outer, y0)
	for o in [[fa, front_z], [fb, front_z], [bw, back_z]]:
		_pane(i, Vector3(x0 + float(o[0]) + 0.55, y0 + 1.45, float(o[1])), Vector2(1.06, 1.06))
	var door_z := rng.randf_range(0.6, d - 1.6)
	_wall("Dom%dPietroDzialowa" % i, Vector3(split_x, 0, z0), Vector3(split_x, 0, z1), [[door_z, 0.9, 0.0, 2.1]], inner, y0)
	# barierka wzdłuż wschodniej krawędzi otworu; przy tylnej ścianie zostaje wyjście ze schodów
	var rail := _mat("barierka", Color(0.3, 0.3, 0.32))
	var near := hole.position.y if back_dir > 0.0 else hole.end.y  # krawędź przy tylnej ścianie
	var far := hole.end.y if back_dir > 0.0 else hole.position.y
	var r0 := near + back_dir * 1.2
	_box("Dom%dBarierka" % i, Vector3(hole.end.x + 0.03, y0 + 0.45, (r0 + far) / 2.0), Vector3(0.05, 0.9, absf(far - r0)), rail)
	_box("Dom%dBarierkaKoniec" % i, Vector3(hole.get_center().x, y0 + 0.45, far), Vector3(hole.size.x, 0.9, 0.05), rail)
	var west := Rect2(x0, z0, split_x - x0, d)
	var east := Rect2(split_x, z0, x1 - split_x, d)
	_furnish(i, 10, west, "sypialnia", back_z, y0, STAIR_W + 1.3, 0.0)  # metr przejścia przy wyjściu ze schodów
	if main.utilities != null:
		for rr in [west, east]:
			main.utilities.add_house_lamp(i, _parent, Vector3(rr.get_center().x, y0 + H - 0.15, rr.get_center().y))
	_furnish(i, 11, east, "sypialnia" if rng.randf() < 0.5 else "lazienka", back_z, y0, 0.0, 0.0)


## Meble w pokoju przy ścianie tylnej (z dala od drzwi wejściowych); y0: wysokość
## podłogi, skip_w/skip_e: pas przy ścianie zachodniej/wschodniej zajęty przez schody.
func _furnish(house: int, room: int, rect: Rect2, kind: String, back_z: float, y0: float = 0.0, skip_w: float = 0.0, skip_e: float = 0.0, door_cx: float = -9999.0) -> void:
	var list: Array = FURNITURE[kind]
	var against_back := absf(back_z - rect.position.y) < 0.1 or absf(back_z - rect.end.y) < 0.1
	var at_z0 := absf(back_z - rect.position.y) < 0.1 if against_back else absf(rect.position.y - back_z) > absf(rect.end.y - back_z)
	var x := rect.position.x + 0.4 + skip_w
	var x_end := rect.end.x - skip_e
	for k in list.size():
		var f: Array = list[k]
		var size: Vector3 = f[2]
		# przy ścianie z drzwiami wejściowymi: nie zastawiamy wejścia
		if not against_back and absf(x + size.x / 2.0 - door_cx) < size.x / 2.0 + 0.9:
			x = door_cx + 0.9
		var z := rect.position.y + WALL / 2.0 + size.z / 2.0 + 0.02 if at_z0 else rect.end.y - WALL / 2.0 - size.z / 2.0 - 0.02
		var y := y0 + size.y / 2.0
		if kind == "lazienka":
			y = y0 + 1.4  # apteczka wisi na ścianie
		if x + size.x > x_end - 0.3:
			break
		var id := "dom%d_%d_%d" % [house, room, k]
		var body := _box("Mebel_" + id, Vector3(x + size.x / 2.0, y, z), size, _mat("mebel_" + str(f[0]), f[3]))
		body.set_meta("container_id", id)
		main.inventory.register_container(id, [f[1]], body, "INV_CONTAINER_" + str(f[0]))
		loot_spots.append([id, str(f[0])])
		x += size.x + 0.3
	if kind == "kuchnia" and x + 0.6 < x_end - 0.3:
		var zs := rect.position.y + WALL / 2.0 + 0.32 if at_z0 else rect.end.y - WALL / 2.0 - 0.32
		var sink := _box("Zlew_%d_%d" % [house, room], Vector3(x + 0.3, y0 + 0.45, zs), Vector3(0.6, 0.9, 0.6), _mat("zlew", Color(0.7, 0.72, 0.74)))
		sink.set_meta("sink", house)
		x += 0.9
	if kind == "salon" and main.devices != null and x + 0.9 < x_end - 0.3:
		var zt := rect.position.y + WALL / 2.0 + 0.25 if at_z0 else rect.end.y - WALL / 2.0 - 0.25
		var tv := _box("Telewizor_%d_%d" % [house, room], Vector3(x + 0.4, y0 + 0.55, zt), Vector3(0.7, 0.5, 0.4), _mat("telewizor", Color(0.08, 0.08, 0.09)))
		var face := 1.0 if at_z0 else -1.0
		main.devices.add_tv(house, tv, Vector3(x + 0.4, y0 + 0.57, zt + face * 0.205), 0.0 if face > 0.0 else PI)
		_box("Szafka_TV_%d_%d" % [house, room], Vector3(x + 0.4, y0 + 0.15, zt), Vector3(0.9, 0.3, 0.45), _mat("mebel_regal", Color(0.4, 0.3, 0.2)))
		x += 1.2
	if kind == "sypialnia" and x + 0.9 < x_end - 0.2:
		var bed := _box("Lozko_%d_%d" % [house, room], Vector3(x + 0.45, y0 + 0.22, rect.get_center().y), Vector3(0.9, 0.44, 1.9), _mat("posciel", Color(0.4, 0.38, 0.45)))
		bed.set_meta("bed", 1.15)  # łóżko: sen lepszy niż na materacu
	if kind == "salon" and x + 1.8 < x_end - 0.2:
		_box("Kanapa_%d_%d" % [house, room], Vector3(x + 0.9, y0 + 0.4, rect.get_center().y), Vector3(1.8, 0.8, 0.8), _mat("kanapa", Color(0.3, 0.2, 0.18)))


## Prostokąt pomniejszony o otwory: lista prostokątów pokrywających resztę.
static func subtract_rects(base: Rect2, holes: Array) -> Array:
	var parts: Array = [base]
	for h in holes:
		var hole := h as Rect2
		if hole.size.x <= 0.0:
			continue
		var next: Array = []
		for p in parts:
			var r := p as Rect2
			if not r.intersects(hole):
				next.append(r)
				continue
			var cut := r.intersection(hole)
			if cut.position.y > r.position.y:
				next.append(Rect2(r.position.x, r.position.y, r.size.x, cut.position.y - r.position.y))
			if cut.end.y < r.end.y:
				next.append(Rect2(r.position.x, cut.end.y, r.size.x, r.end.y - cut.end.y))
			if cut.position.x > r.position.x:
				next.append(Rect2(r.position.x, cut.position.y, cut.position.x - r.position.x, cut.size.y))
			if cut.end.x < r.end.x:
				next.append(Rect2(cut.end.x, cut.position.y, r.end.x - cut.end.x, cut.size.y))
		parts = next
	return parts


func _door(house: int, at: Vector3, id: String = ""):
	if id == "":
		id = "dom%d" % house
	var size := Vector3(0.94, 2.04, 0.04)
	var center := at + Vector3(0.03 + size.x / 2.0, 0.02 + size.y / 2.0, 0)
	var body := RoomBuilder._rigid("drzwi_" + id, center, 30.0)
	body.angular_damp = 4.0
	RoomBuilder._add_box(body, size, Tex.material("wood", false, 1.0))
	var par: Node3D = _parent if _parent != null else world
	par.add_child(body)
	var joint := HingeJoint3D.new()
	joint.name = "Zawias_" + id
	joint.position = at + Vector3(0.02, center.y, 0)
	joint.rotation_degrees = Vector3(90, 0, 0)
	par.add_child(joint)
	joint.node_a = joint.get_path_to(body)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-100.0))
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(100.0))
	var ctl := DoorScript.new()
	add_child(ctl)
	ctl.setup(main, body, id)
	doors.append(ctl)
	return ctl


# --- adresy i mieszkańcy -----------------------------------------------------------

## Mieszkańcy domu (z ziarna świata): imiona, zawody, losy; zamek drzwi.
func _residents(info: Dictionary) -> void:
	if _families.is_empty():
		_families = (_res["surnames"] as Array).duplicate()
		for k in range(_families.size() - 1, 0, -1):  # tasowanie z ziarna świata
			var j := rng.randi() % (k + 1)
			var tmp = _families[k]
			_families[k] = _families[j]
			_families[j] = tmp
	var fam: Array = _families.pop_back()
	info["family"] = str(fam[2])
	var n := rng.randi_range(1, 3)
	var people: Array = []
	var profs: Dictionary = _res["professions"]
	var fates: Dictionary = _res["fates"]
	for k in n:
		var female := rng.randf() < 0.5
		var first: Array = _res["first_f"] if female else _res["first_m"]
		var prof := _weighted(profs, "weight")
		var fate := _weighted_simple(fates)
		people.append({"name": "%s %s" % [first[rng.randi() % first.size()], fam[1] if female else fam[0]],
				"profession": prof, "fate": fate})
	info["residents"] = people
	var all_fled := true
	for pp in people:
		if pp["fate"] != "uciekl":
			all_fled = false
	# kto uciekał, zamykał za sobą; w domu z zombie bywa otwarte
	var locked := rng.randf() < (0.85 if all_fled else 0.55)
	info["locked"] = locked
	info["spare_key"] = rng.randf() < 0.45
	if info["door"] != null:
		info["door"].locked = locked
		info["door"].key_id = int(info["key_id"])


func _weighted(dict: Dictionary, field: String) -> String:
	var total := 0.0
	for k in dict:
		total += float(dict[k].get(field, 1.0))
	var x := rng.randf() * total
	for k in dict:
		x -= float(dict[k].get(field, 1.0))
		if x <= 0.0:
			return str(k)
	return str(dict.keys()[0])


func _weighted_simple(dict: Dictionary) -> String:
	var total := 0.0
	for k in dict:
		total += float(dict[k])
	var x := rng.randf() * total
	for k in dict:
		x -= float(dict[k])
		if x <= 0.0:
			return str(k)
	return str(dict.keys()[0])


## Tabliczka z adresem i nazwiskiem przy drzwiach, wycieraczka (pojemnik na
## zapasowy klucz) przed drzwiami.
func _address(info: Dictionary) -> void:
	var i: int = info["index"]
	var fz: float = info["front_z"]
	var out_dir := 1.0 if absf(fz - (info["rect"] as Rect2).end.y) < 0.05 else -1.0
	var plate := Label3D.new()
	plate.text = "%s %d\n%s" % [info["street"], info["number"], info["family"]]
	plate.font_size = 48
	plate.pixel_size = 0.004
	plate.modulate = Color(0.92, 0.9, 0.8)
	plate.outline_size = 8
	plate.position = Vector3(float(info["door_x"]) + 0.9, 2.15, fz + out_dir * (WALL / 2.0 + 0.01))
	plate.rotation.y = 0.0 if out_dir > 0.0 else PI
	house_nodes[i].add_child(plate)
	var mat_id := "wycieraczka_%d" % i
	var mat := _box("Wycieraczka_%d" % i, Vector3(float(info["door_x"]), 0.025, fz + out_dir * (WALL / 2.0 + 0.35)), Vector3(0.8, 0.03, 0.5), _mat("wycieraczka", Color(0.3, 0.22, 0.12)))
	mat.collision_layer = 1 << 9  # nie potyka się o nią nikt; da się ją podnieść (F)
	mat.set_meta("container_id", mat_id)
	main.inventory.register_container(mat_id, [[2, 1]], mat, "INV_CONTAINER_wycieraczka")
	doormats.append([mat_id, i])


func _street_sign(street: String, at: Vector3) -> void:
	var post := _box("Slupek_" + street, at + Vector3(0, 1.2, 0), Vector3(0.06, 2.4, 0.06), _mat("slupek", Color(0.4, 0.4, 0.42)))
	var sign := Label3D.new()
	sign.text = "ul. " + street
	sign.font_size = 64
	sign.pixel_size = 0.005
	sign.outline_size = 10
	sign.modulate = Color(0.95, 0.95, 0.9)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.position = Vector3(0, 1.25, 0)
	post.add_child(sign)


## Dom pod adresem (ulica, numer); pusty słownik, gdy nie ma.
func house_at(street: String, number: int) -> Dictionary:
	for h in houses:
		if h["street"] == street and int(h["number"]) == number:
			return h
	return {}


## Dom, w którym (pod którego dachem) jest punkt; pusty, gdy na dworze.
func house_of(p: Vector3) -> Dictionary:
	for h in houses:
		if (h["rect"] as Rect2).has_point(Vector2(p.x, p.z)):
			return h
	return {}


## Klucz do drzwi domu: z etykietą adresu w podpowiedzi.
func make_key(info: Dictionary):
	var k = ItemScript.new("klucz", 1)
	k.props["key_id"] = int(info["key_id"])
	k.props["label"] = "%s %d" % [info["street"], info["number"]]
	return k


## Nowa gra: mieszkańcy-zombie wychodzą na świat (w domu albo przed nim) z kluczem
## i rzeczami z życia. Zwraca liczbę zombie.
func spawn_residents() -> int:
	var lr := RandomNumberGenerator.new()
	lr.seed = rng.seed + 313
	var n := 0
	var profs: Dictionary = _res["professions"]
	for h in houses:
		for pp in h["residents"]:
			if pp["fate"] == "uciekl":
				continue
			var pos: Vector3
			var rect: Rect2 = h["rect"]
			if pp["fate"] == "zombie_dom":
				var room: Rect2 = (h["rooms"] as Array)[lr.randi() % (h["rooms"] as Array).size()]
				pos = Vector3(lr.randf_range(room.position.x + 0.8, room.end.x - 0.8), 0.05, lr.randf_range(room.position.y + 0.8, room.end.y - 0.8))
			else:
				var fz: float = h["front_z"]
				var out_dir := 1.0 if absf(fz - rect.end.y) < 0.05 else -1.0
				pos = Vector3(lr.randf_range(rect.position.x, rect.end.x), 0.05, fz + out_dir * lr.randf_range(2.0, 4.5))
			if pos.distance_to(main.player.global_position) < 8.0:
				continue  # nie tuż przy graczu na start
			var z = main.zombies.spawn(pos)
			var carry: Array = [make_key(h).to_dict()]
			for c in profs[pp["profession"]].get("carry", []):
				if lr.randf() < float(c[1]):
					carry.append(ItemScript.new(str(c[0]), int(c[2])).to_dict())
			z.carry = carry
			z.who = "%s, %s (%s %d)" % [pp["name"], tr("PROF_" + str(pp["profession"])), h["street"], h["number"]]
			n += 1
	return n


func _pane(house: int, center: Vector3, size: Vector2) -> void:
	var p := GlassScript.new()
	(_parent if _parent != null else world).add_child(p)
	p.global_position = center
	p.setup(main, "dom%d_%d" % [house, panes.size()], size)
	panes.append(p)


# --- łupy, zapytania, zapis -------------------------------------------------------

## Nowa gra: pojemniki domów dostają łupy z tabel.
func fill_loot() -> void:
	var lr := RandomNumberGenerator.new()
	lr.seed = rng.seed + 77
	for spot in loot_spots:
		var table: Dictionary = _loot.get(spot[1], {})
		if table.is_empty():
			continue
		var rolls: Array = table["rolls"]
		var n := lr.randi_range(int(rolls[0]), int(rolls[1]))
		for r in n:
			var e := _pick(table["items"], lr)
			if e.is_empty():
				continue
			var it = ItemScript.new(str(e[0]), lr.randi_range(int(e[2]), int(e[3])))
			if it.get_def().has("food") and it.get_def()["food"].has("rot_days"):
				it.props["made"] = -lr.randf_range(0.0, 3.0)  # część jedzenia już nieświeża
			for g in main.inventory.containers[spot[0]]["grids"]:
				var place: Dictionary = g.find_space(it)
				if not place.is_empty():
					g.place(it, place["pos"], place["rot"])
					break


## Rzeczy z zawodów mieszkańców i zapasowe klucze pod wycieraczkami (nowa gra).
func fill_residents_loot() -> void:
	var lr := RandomNumberGenerator.new()
	lr.seed = rng.seed + 211
	var profs: Dictionary = _res["professions"]
	for h in houses:
		var i: int = h["index"]
		var own: Array = []  # pojemniki domu: [id, rodzaj]
		for spot in loot_spots:
			if str(spot[0]).begins_with("dom%d_" % i):
				own.append(spot)
		for pp in h["residents"]:
			for e in profs[pp["profession"]].get("house", []):
				if lr.randf() > 0.75:
					continue
				var it = ItemScript.new(str(e[0]), int(e[1]))
				var placed := false
				for kind in e[2]:
					for spot in own:
						if placed or spot[1] != kind:
							continue
						for g in main.inventory.containers[spot[0]]["grids"]:
							if not placed and main.inventory.place_now(it, g):
								placed = true
				if not placed:
					for spot in own:
						for g in main.inventory.containers[spot[0]]["grids"]:
							if not placed and main.inventory.place_now(it, g):
								placed = true
		if bool(h["spare_key"]):
			for g in main.inventory.containers["wycieraczka_%d" % i]["grids"]:
				main.inventory.place_now(make_key(h), g)
		# co czwarty dom: generator za domem i kanister z resztką benzyny
		if lr.randf() < 0.25:
			var rect: Rect2 = h["rect"]
			var back_out: float = rect.position.y - 1.2 if absf(float(h["front_z"]) - rect.end.y) < 0.05 else rect.end.y + 1.2
			var gx := lr.randf_range(rect.position.x + 1.0, rect.end.x - 1.0)
			main.world_items.spawn(ItemScript.new("generator", 1), Transform3D(Basis(), Vector3(gx, 0.3, back_out)))
			var can = ItemScript.new("kanister", 1)
			can.liquid = {"type": "benzyna", "amount": snappedf(lr.randf_range(2.0, 7.0), 0.1)}
			main.world_items.spawn(can, Transform3D(Basis(), Vector3(gx + 0.8, 0.2, back_out)))


func _pick(entries: Array, lr: RandomNumberGenerator) -> Array:
	var total := 0.0
	for e in entries:
		total += float(e[1])
	var x := lr.randf() * total
	for e in entries:
		x -= float(e[1])
		if x <= 0.0:
			return e
	return []


## Czy punkt jest pod dachem (dom startowy albo któryś z domów).
func indoors(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	if START_RECT.has_point(q):
		return true
	for b in buildings:
		if (b as Rect2).has_point(q):
			return true
	return false


func in_start_house(p: Vector3) -> bool:
	return START_RECT.has_point(Vector2(p.x, p.z))


func to_dict() -> Dictionary:
	var d: Array = []
	for door in doors:
		d.append(door.to_dict())
	var g: Array = []
	for p in panes:
		g.append(p.to_dict())
	return {"doors": d, "panes": g}


func from_dict(data: Dictionary) -> void:
	var d: Array = data.get("doors", [])
	for k in mini(d.size(), doors.size()):
		doors[k].from_dict(d[k])
	var g: Array = data.get("panes", [])
	for k in mini(g.size(), panes.size()):
		panes[k].from_dict(g[k])
