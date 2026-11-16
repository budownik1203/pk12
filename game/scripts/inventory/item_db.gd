extends RefCounted
## Definicje przedmiotów, slotów i cieczy z data/items.json oraz pomocnicze
## funkcje kształtów na siatce. Kod gry zna przedmioty tylko przez te dane.

const PATH := "res://data/items.json"
const Gunsmith := preload("res://scripts/gunsmith/gunsmith.gd")

static var defs: Dictionary = {}
static var slots: Array = []
static var liquids: Dictionary = {}
static var fists: Dictionary = {}     # walka bez niczego w rękach


static func ensure_loaded() -> void:
	if not defs.is_empty():
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Nie można wczytać " + PATH)
		return
	defs = data.get("items", {})
	_load_gunsmith()
	slots = data.get("slots", [])
	liquids = data.get("liquids", {})
	fists = data.get("fists", {})


static func get_def(id: String) -> Dictionary:
	ensure_loaded()
	return defs.get(id, {})


static func _loc_key() -> String:
	return "en" if TranslationServer.get_locale().begins_with("en") else "pl"


static func name_of(id: String) -> String:
	return str(get_def(id).get(_loc_key(), id))


## Krótka nazwa do małych przedmiotów na siatce (gdy brak, pełna nazwa).
static func short_name_of(id: String) -> String:
	var d := get_def(id)
	return str(d.get("short_" + _loc_key(), d.get(_loc_key(), id)))


static func desc_of(id: String) -> String:
	return str(get_def(id).get("desc_" + _loc_key(), ""))


static func slot_def(id: String) -> Dictionary:
	ensure_loaded()
	for s in slots:
		if s["id"] == id:
			return s
	return {}


static func slot_name(id: String) -> String:
	return str(slot_def(id).get(_loc_key(), id))


static func liquid_name(id: String) -> String:
	ensure_loaded()
	return str(liquids.get(id, {}).get(_loc_key(), id))


static func liquid_density(id: String) -> float:
	ensure_loaded()
	return float(liquids.get(id, {}).get("density", 1.0))


## Komórki kształtu po obrocie o rot × 90° w prawo, z lewym górnym rogiem w (0, 0).
static func cells(shape: Array, rot: int) -> Array:
	var out: Array = []
	for y in shape.size():
		var row: String = shape[y]
		for x in row.length():
			if row[x] == "#":
				out.append(Vector2i(x, y))
	for i in posmod(rot, 4):
		var h := 0
		for c in out:
			h = maxi(h, c.y + 1)
		var turned: Array = []
		for c in out:
			turned.append(Vector2i(h - 1 - c.y, c.x))
		out = turned
	return out


static func bounds(cell_list: Array) -> Vector2i:
	var b := Vector2i.ZERO
	for c in cell_list:
		b.x = maxi(b.x, c.x + 1)
		b.y = maxi(b.y, c.y + 1)
	return b


## Bronie z warsztatu (data/bronie/*.json): przedmiot z pola "item", model budowany z modułów.
static func _load_gunsmith() -> void:
	for id in Gunsmith.list_files():
		var g: Dictionary = Gunsmith.load_gun(id)
		if g.is_empty():
			continue
		var item: Dictionary = (g.get("item", {}) as Dictionary).duplicate(true)
		var gid := str(g.get("id", id))
		item["pl"] = str(g.get("pl", item.get("pl", gid)))
		item["en"] = str(g.get("en", item.get("en", gid)))
		var box: AABB = Gunsmith.aabb(g)
		var c := box.get_center()
		item["model"] = {"gunsmith": gid, "size": [box.size.x, box.size.y, box.size.z], "center": [c.x, c.y, c.z], "grip_at": [0.0, 0.0, 0.0]}
		if item.has("gun"):
			var dv: Dictionary = Gunsmith.derived(g)
			var gun: Dictionary = item["gun"]
			gun["muzzle"] = dv["muzzle"]
			gun["sight_y"] = float(dv["sight_y"]) + float(gun.get("ads_drop", 0.0))  # niżej przy oku: mniej kolby w kadrze
			var h: Array = g.get("anchors", {}).get("hinge", [])
			if h.size() == 2:
				gun["hinge"] = h
		defs[gid] = item
