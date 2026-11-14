extends RefCounted
## Siatka pojemnika: kieszeń, przegroda plecaka, szafka. Przedmiot zajmuje
## swój kształt; komórki zarezerwowane przez trwające przekładanie liczą się
## jako zajęte, żeby dwa przedmioty nie trafiły w to samo miejsce.

var w: int
var h: int
var items: Array = []
var reserved: Array = []      # [{"item": ..., "pos": Vector2i, "rot": int}]
var _owner: WeakRef = null
## Przedmiot-pojemnik, do którego należy siatka (null: pojemnik świata).
## Odwołanie słabe: przedmiot trzyma siatkę, siatka nie trzyma przedmiotu.
var owner_item:
	get:
		return _owner.get_ref() if _owner != null else null
	set(v):
		_owner = weakref(v) if v != null else null
var access_time := 0.5        # ile sekund dodaje sięgnięcie do tej siatki
var container_id := ""        # dla pojemników świata (np. "szafka")


func _init(width: int, height: int, access: float = 0.5) -> void:
	w = width
	h = height
	access_time = access


func occupied(exclude = null) -> Dictionary:
	var occ := {}
	for it in items:
		if it == exclude:
			continue
		for c in it.cells_for(it.rot):
			occ[it.pos + c] = it
	for r in reserved:
		if r["item"] == exclude:
			continue
		for c in r["item"].cells_for(r["rot"]):
			occ[r["pos"] + c] = r["item"]
	return occ


func fits_cells(cell_list: Array, pos: Vector2i, exclude = null) -> bool:
	var occ := occupied(exclude)
	for c in cell_list:
		var q: Vector2i = pos + c
		if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or occ.has(q):
			return false
	return true


func can_place(item, pos: Vector2i, rot: int) -> bool:
	return fits_cells(item.cells_for(rot), pos, item)


func place(item, pos: Vector2i, rot: int) -> void:
	item.pos = pos
	item.rot = rot
	item.parent_grid = self
	item.slot = ""
	if not items.has(item):
		items.append(item)


func remove(item) -> void:
	items.erase(item)
	if item.parent_grid == self:
		item.parent_grid = null


func reserve(item, pos: Vector2i, rot: int) -> void:
	reserved.append({"item": item, "pos": pos, "rot": rot})


func unreserve(item) -> void:
	for i in range(reserved.size() - 1, -1, -1):
		if reserved[i]["item"] == item:
			reserved.remove_at(i)


## Pierwsze wolne miejsce: {"pos": Vector2i, "rot": int} albo pusty słownik.
func find_space(item) -> Dictionary:
	for rot in [0, 1, 2, 3]:
		var cl: Array = item.cells_for(rot)
		for y in h:
			for x in w:
				if fits_cells(cl, Vector2i(x, y), item):
					return {"pos": Vector2i(x, y), "rot": rot}
	return {}


func item_at(cell: Vector2i):
	var occ := occupied()
	return occ.get(cell)


func is_empty() -> bool:
	return items.is_empty() and reserved.is_empty()
