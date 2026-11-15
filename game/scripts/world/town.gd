extends Node
## Ulica wokół domu startowego: grunt, jezdnia z chodnikami, granice terenu
## i kilka domów generowanych z ziarna świata (data/sandbox.json "world_seed").
## Dom: prostokąt 8–11 × 7–9 m, ściany z otworami (drzwi wejściowe od strony
## ulicy, 2–3 okna z szybami), 2–3 pokoje rozdzielone ścianami z przejściami,
## każdy pokój z rodzajem (kuchnia, łazienka, sypialnia, salon, garaż) i meblami;
## meble-pojemniki dostają łupy z data/loot.json przy nowej grze.

const Tex := preload("res://scripts/textures.gd")
const RoomBuilder := preload("res://scripts/room_builder.gd")
const DoorScript := preload("res://scripts/world/simple_door.gd")
const GlassScript := preload("res://scripts/world/glass_pane.gd")
const ItemScript := preload("res://scripts/inventory/item.gd")

const H := 2.8
const WALL := 0.18
const AREA := Rect2(-42.0, -24.0, 84.0, 60.0)        # teren (x, z)
const ROAD_Z0 := 9.0
const ROAD_Z1 := 15.0
const START_RECT := Rect2(-4.8, -3.8, 12.6, 7.6)      # dom startowy (sala + komórka)
## działki: [x0, z0, drzwi od strony "N" albo "S"]
const LOTS := [[-24.0, -4.0, "S"], [12.0, -4.0, "S"], [-22.0, 17.5, "N"], [-5.0, 17.5, "N"], [12.0, 17.5, "N"]]
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
	_ground()
	for i in LOTS.size():
		var lot: Array = LOTS[i]
		_house(i, float(lot[0]), float(lot[1]), str(lot[2]))


func _mat(key: String, color: Color) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.95
		_mats[key] = m
	return _mats[key]


func _box(node_name: String, center: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	return RoomBuilder._static_box(world, node_name, center, size, mat)


# --- teren -----------------------------------------------------------------------

func _ground() -> void:
	var c := AREA.get_center()
	# wierzch gruntu minimalnie pod podłogą domów, żeby nie migotał
	_box("Grunt", Vector3(c.x, -0.16, c.y), Vector3(AREA.size.x, 0.3, AREA.size.y), Tex.material("grass", true, 0.25))
	_box("Jezdnia", Vector3(c.x, -0.005, (ROAD_Z0 + ROAD_Z1) / 2.0), Vector3(AREA.size.x, 0.01, ROAD_Z1 - ROAD_Z0), Tex.material("asphalt", true, 0.3))
	var curb := Tex.material("concrete", true, 0.5)
	_box("ChodnikN", Vector3(c.x, 0.04, ROAD_Z0 - 0.75), Vector3(AREA.size.x, 0.1, 1.5), curb)
	_box("ChodnikS", Vector3(c.x, 0.04, ROAD_Z1 + 0.75), Vector3(AREA.size.x, 0.1, 1.5), curb)
	# pasy na jezdni
	var line := _mat("pasy", Color(0.75, 0.72, 0.6))
	var x := AREA.position.x + 2.0
	while x < AREA.end.x - 2.0:
		_box("Pas", Vector3(x, 0.002, (ROAD_Z0 + ROAD_Z1) / 2.0), Vector3(2.0, 0.006, 0.15), line)
		x += 5.0
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
	for k in 14:
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
	if p.y > ROAD_Z0 - margin and p.y < ROAD_Z1 + margin:
		return true
	if START_RECT.grow(margin).has_point(p):
		return true
	for lot in LOTS:
		if Rect2(float(lot[0]) - margin, float(lot[1]) - margin, 11.0 + margin * 2.0, 9.0 + margin * 2.0).has_point(p):
			return true
	return false


# --- ściany ----------------------------------------------------------------------

## Ściana od a do b (pozioma wzdłuż X albo Z) z otworami [od, szerokość, dół, góra].
func _wall(base: String, a: Vector3, b: Vector3, openings: Array, mat: Material) -> void:
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
			_wall_piece(base + str(k), a, dir, cursor, s, 0.0, H, along_x, mat)
			k += 1
		if float(o[2]) > 0.01:
			_wall_piece(base + str(k) + "d", a, dir, s, s + w, 0.0, float(o[2]), along_x, mat)
		if float(o[3]) < H - 0.01:
			_wall_piece(base + str(k) + "g", a, dir, s, s + w, float(o[3]), H, along_x, mat)
		cursor = s + w
		k += 1
	if cursor < length - 0.01:
		_wall_piece(base + str(k), a, dir, cursor, length, 0.0, H, along_x, mat)


func _wall_piece(n: String, a: Vector3, dir: Vector3, t0: float, t1: float, y0: float, y1: float, along_x: bool, mat: Material) -> void:
	var mid := a + dir * ((t0 + t1) / 2.0)
	var size := Vector3(t1 - t0, y1 - y0, WALL) if along_x else Vector3(WALL, y1 - y0, t1 - t0)
	_box(n, Vector3(mid.x, (y0 + y1) / 2.0, mid.z), size, mat)


# --- dom -------------------------------------------------------------------------

func _house(i: int, x0: float, z0: float, door_side: String) -> void:
	var w := rng.randf_range(8.0, 11.0)
	var d := rng.randf_range(7.0, 9.0)
	var x1 := x0 + w
	var z1 := z0 + d
	buildings.append(Rect2(x0, z0, w, d))
	var outer := _mat("elewacja%d" % (i % 3), [Color(0.55, 0.5, 0.42), Color(0.45, 0.42, 0.4), Color(0.5, 0.38, 0.3)][i % 3])
	var inner := Tex.material("wall", true, 0.4)
	var floor_m := Tex.material("floor" if i % 2 == 0 else "tiles", true, 0.5)
	_box("Dom%dPodloga" % i, Vector3((x0 + x1) / 2.0, -0.09, (z0 + z1) / 2.0), Vector3(w, 0.2, d), floor_m)
	_box("Dom%dDach" % i, Vector3((x0 + x1) / 2.0, H + 0.1, (z0 + z1) / 2.0), Vector3(w + 0.6, 0.2, d + 0.6), _mat("dach", Color(0.22, 0.12, 0.1)))
	# ściana od ulicy: drzwi i dwa okna; tylna: jedno okno; boczne pełne
	var front_z := z1 if door_side == "S" else z0
	var back_z := z0 if door_side == "S" else z1
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
	_door(i, Vector3(x0 + door_off, 0, front_z))
	# szyby
	for o in [[win_a, front_z], [win_b, front_z], [back_win, back_z]]:
		_pane(i, Vector3(x0 + float(o[0]) + 0.55, 1.45, float(o[1])), Vector2(1.06, 1.06))
	# pokoje: podział wzdłuż X, czasem jeszcze wzdłuż Z
	var split_x := x0 + w * rng.randf_range(0.42, 0.58)
	_wall("Dom%dDzialowaX" % i, Vector3(split_x, 0, z0), Vector3(split_x, 0, z1), [[rng.randf_range(0.6, d - 1.6), 0.9, 0.0, 2.1]], inner)
	var rooms: Array = [Rect2(x0, z0, split_x - x0, d)]
	if rng.randf() < 0.7:
		var split_z := z0 + d * rng.randf_range(0.4, 0.6)
		_wall("Dom%dDzialowaZ" % i, Vector3(split_x, 0, split_z), Vector3(x1, 0, split_z), [[rng.randf_range(0.5, x1 - split_x - 1.5), 0.9, 0.0, 2.1]], inner)
		rooms.append(Rect2(split_x, z0, x1 - split_x, split_z - z0))
		rooms.append(Rect2(split_x, split_z, x1 - split_x, z1 - split_z))
	else:
		rooms.append(Rect2(split_x, z0, x1 - split_x, d))
	var kinds := ROOM_KINDS.duplicate()
	kinds.shuffle()
	kinds.erase("kuchnia")
	kinds.push_front("kuchnia")  # każdy dom ma kuchnię
	for r in rooms.size():
		_furnish(i, r, rooms[r], kinds[r % kinds.size()], back_z)


## Meble w pokoju przy ścianie tylnej (z dala od drzwi wejściowych).
func _furnish(house: int, room: int, rect: Rect2, kind: String, back_z: float) -> void:
	var list: Array = FURNITURE[kind]
	var against_back := absf(back_z - rect.position.y) < 0.1  # tylna ściana od strony z0
	var x := rect.position.x + 0.4
	for k in list.size():
		var f: Array = list[k]
		var size: Vector3 = f[2]
		var z := rect.position.y + WALL / 2.0 + size.z / 2.0 + 0.02 if against_back else rect.end.y - WALL / 2.0 - size.z / 2.0 - 0.02
		var y := size.y / 2.0
		if kind == "lazienka":
			y = 1.4  # apteczka wisi na ścianie
		if x + size.x > rect.end.x - 0.3:
			break
		var id := "dom%d_%d_%d" % [house, room, k]
		var body := _box("Mebel_" + id, Vector3(x + size.x / 2.0, y, z), size, _mat("mebel_" + str(f[0]), f[3]))
		body.set_meta("container_id", id)
		main.inventory.register_container(id, [f[1]], body, "INV_CONTAINER_" + str(f[0]))
		loot_spots.append([id, str(f[0])])
		x += size.x + 0.3
	if kind == "sypialnia" and x + 0.9 < rect.end.x - 0.2:
		var bed := _box("Lozko_%d_%d" % [house, room], Vector3(x + 0.45, 0.22, rect.get_center().y), Vector3(0.9, 0.44, 1.9), _mat("posciel", Color(0.4, 0.38, 0.45)))
		bed.set_meta("bed", 1.15)  # łóżko: sen lepszy niż na materacu
	if kind == "salon" and x + 1.8 < rect.end.x - 0.2:
		_box("Kanapa_%d_%d" % [house, room], Vector3(x + 0.9, 0.4, rect.get_center().y), Vector3(1.8, 0.8, 0.8), _mat("kanapa", Color(0.3, 0.2, 0.18)))


func _door(house: int, at: Vector3) -> void:
	var size := Vector3(0.94, 2.04, 0.04)
	var center := at + Vector3(0.03 + size.x / 2.0, 0.02 + size.y / 2.0, 0)
	var body := RoomBuilder._rigid("drzwi_dom%d" % house, center, 30.0)
	body.angular_damp = 4.0
	RoomBuilder._add_box(body, size, Tex.material("wood", false, 1.0))
	world.add_child(body)
	var joint := HingeJoint3D.new()
	joint.name = "Zawias_dom%d" % house
	joint.position = at + Vector3(0.02, center.y, 0)
	joint.rotation_degrees = Vector3(90, 0, 0)
	world.add_child(joint)
	joint.node_a = joint.get_path_to(body)
	joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-100.0))
	joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(100.0))
	var ctl := DoorScript.new()
	add_child(ctl)
	ctl.setup(main, body, "dom%d" % house)
	doors.append(ctl)


func _pane(house: int, center: Vector3, size: Vector2) -> void:
	var p := GlassScript.new()
	world.add_child(p)
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
