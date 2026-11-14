extends RefCounted
## Egzemplarz przedmiotu: definicja z danych plus stan (ilość w stosie,
## zawartość cieczy, zawilgocenie, obrót, miejsce, zawartość pojemnika).
## Ten sam egzemplarz leży w siatce albo jako bryła w świecie i przechodzi
## między nimi bez utraty stanu.

const ItemDB := preload("res://scripts/inventory/item_db.gd")
const Grid := preload("res://scripts/inventory/grid.gd")

static var _next_uid := 1

var def_id: String
var uid: int
var count := 1
var rot := 0
var pos := Vector2i.ZERO
var liquid := {}              # {"type": "woda", "amount": litry}
var wet := 0.0                # 0..1, przemoczenie (system pogody w buildzie 8)
var grids: Array = []         # siatki pojemnika
var _parent: WeakRef = null
## Siatka, w której leży przedmiot (odwołanie słabe, bez cyklu z siatką).
var parent_grid:
	get:
		return _parent.get_ref() if _parent != null else null
	set(v):
		_parent = weakref(v) if v != null else null
var slot := ""                # slot na ciele, jeśli założony
var pending := false          # trwa przekładanie


func _init(id: String, n: int = 1, with_start_liquid: bool = true) -> void:
	def_id = id
	count = maxi(1, n)
	uid = _next_uid
	_next_uid += 1
	var d := get_def()
	var access := float(d.get("access", 0.5))
	for g in d.get("grids", []):
		var grid: Grid = Grid.new(int(g["w"]), int(g["h"]), access)
		grid.owner_item = self
		grids.append(grid)
	if with_start_liquid and d.has("liquid_start"):
		liquid = (d["liquid_start"] as Dictionary).duplicate()


func get_def() -> Dictionary:
	return ItemDB.get_def(def_id)


func display_name() -> String:
	return ItemDB.name_of(def_id)


func max_stack() -> int:
	return int(get_def().get("stack", 1))


func is_container() -> bool:
	return not grids.is_empty()


func is_empty_container() -> bool:
	for g in grids:
		if not g.is_empty():
			return false
	return true


func shape() -> Array:
	var d := get_def()
	if d.has("shape_empty") and is_empty_container():
		return d["shape_empty"]
	return d.get("shape", ["#"])


func full_shape() -> Array:
	return get_def().get("shape", ["#"])


func cells_for(r: int) -> Array:
	return ItemDB.cells(shape(), r)


func material() -> String:
	return str(get_def().get("material", ""))


func reduction() -> float:
	return float(get_def().get("reduction", 0.0))


## Masa samego przedmiotu (stos i ciecz), bez zawartości siatek.
func own_mass() -> float:
	var m := float(get_def().get("mass", 0.1)) * count
	if not liquid.is_empty():
		m += float(liquid.get("amount", 0.0)) * ItemDB.liquid_density(str(liquid.get("type", "")))
	return m


func contents_mass() -> float:
	var m := 0.0
	for g in grids:
		for it in g.items:
			m += it.total_mass()
	return m


func total_mass() -> float:
	return own_mass() + contents_mass()


## Odczuwana masa, gdy przedmiot jest założony: pojemnik zmniejsza wagę zawartości.
func felt_mass() -> float:
	return own_mass() + contents_mass() * (1.0 - reduction())


## Czy siatka należy do tego przedmiotu albo do czegoś w nim zagnieżdżonego.
func owns_grid(grid) -> bool:
	for g in grids:
		if g == grid:
			return true
		for it in g.items:
			if it.owns_grid(grid):
				return true
	return false


## Czy w poddrzewie trwa jakieś przekładanie (wtedy nie wolno ruszać całości).
func subtree_busy() -> bool:
	if pending:
		return true
	for g in grids:
		if not g.reserved.is_empty():
			return true
		for it in g.items:
			if it.subtree_busy():
				return true
	return false


func all_items() -> Array:
	var out: Array = []
	for g in grids:
		for it in g.items:
			out.append(it)
			out.append_array(it.all_items())
	return out


func to_dict() -> Dictionary:
	var d := {"def": def_id, "uid": uid, "count": count, "rot": rot, "pos": [pos.x, pos.y]}
	if not liquid.is_empty():
		d["liquid"] = liquid.duplicate()
	if wet > 0.0:
		d["wet"] = wet
	if is_container():
		var gl: Array = []
		for g in grids:
			var arr: Array = []
			for it in g.items:
				arr.append(it.to_dict())
			gl.append(arr)
		d["grids"] = gl
	return d


## Odtworzenie z zapisu albo z danych startowych. Pola pos/rot w danych
## startowych są opcjonalne: brak oznacza "ułóż sam".
static func from_dict(d: Dictionary, script: Script):
	var it = script.new(str(d.get("def", "")), int(d.get("count", 1)), not d.has("liquid"))
	if d.has("uid"):
		it.uid = int(d["uid"])
		_next_uid = maxi(_next_uid, it.uid + 1)
	it.rot = int(d.get("rot", 0))
	var p = d.get("pos", [0, 0])
	it.pos = Vector2i(int(p[0]), int(p[1]))
	if d.has("liquid"):
		it.liquid = (d["liquid"] as Dictionary).duplicate()
	it.wet = float(d.get("wet", 0.0))
	var lists: Array = d.get("grids", d.get("contents", []))
	for gi in mini(lists.size(), it.grids.size()):
		var g = it.grids[gi]
		for cd in lists[gi]:
			var child = from_dict(cd, script)
			if cd.has("pos"):
				g.place(child, child.pos, child.rot)
			else:
				var spot: Dictionary = g.find_space(child)
				if not spot.is_empty():
					g.place(child, spot["pos"], spot["rot"])
	return it
