extends Node
## Ekwipunek postaci: sloty na ciele, pojemniki świata, kolejka czynności.
## Każde przełożenie trwa (sięgnięcie do źródła i celu plus masa), czynności
## wykonują się po kolei, a gra się przy tym nie zatrzymuje. Cel jest
## rezerwowany od razu, żeby nic innego nie zajęło tego miejsca.

signal changed

const ItemScript := preload("res://scripts/inventory/item.gd")
const Grid := preload("res://scripts/inventory/grid.gd")
const ItemDB := preload("res://scripts/inventory/item_db.gd")
const START_PATH := "res://data/start.json"

const SLOT_ORDER := ["glowa", "twarz", "kurtka", "kamizelka", "plecak", "pas", "spodnie", "rekawice", "buty", "plecy", "w_lewej", "oburacz", "w_reku"]
const GRID_SLOTS := ["spodnie", "kurtka", "kamizelka", "pas", "plecak"]   # kolejność szukania miejsca
const HAND := "w_reku"        # prawa ręka
const LEFT_HAND := "w_lewej"  # lewa ręka
const TWO_HANDS := "oburacz"  # chwyt oburącz (łom, deski): zajmuje obie ręce

const COMFORT_MASS := 18.0     # kg odczuwane: do tej masy bez kar
const HEAVY_MASS := 45.0       # kg odczuwane: najwolniej
const MIN_SPEED := 0.45
const WORLD_ACCESS := 0.6      # sekundy: sięgnięcie do świata lub szafki
const HAND_ACCESS := 0.25
const WEAR_TIME := 2.0         # zakładanie i zdejmowanie odzieży i pojemników
const MASS_TIME := 0.04        # sekundy na kilogram
const PICKUP_RANGE := 3.0

var main
var slots := {}                # slot -> przedmiot
var slot_reserved := {}        # slot -> przedmiot w drodze
var containers := {}           # id -> {"grids": [Grid], "node": Node3D}
var hotkeys := {}              # 1..9 -> uid
var hand_origin := {}          # uid -> {"grid": Grid, "pos": Vector2i, "rot": int}
var actions: Array = []
var last_error := ""


func setup(main_node) -> void:
	main = main_node
	ItemDB.ensure_loaded()


# --- stan początkowy i zapis --------------------------------------------------

func load_start() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(START_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Nie można wczytać " + START_PATH)
		return
	_reset()
	for s in data.get("slots", {}):
		slots[s] = _make(data["slots"][s])
		slots[s].slot = s
	for cid in data.get("containers", {}):
		if not containers.has(cid):
			continue
		for d in data["containers"][cid]:
			var it = _make(d)
			for g in containers[cid]["grids"]:
				var spot: Dictionary = g.find_space(it)
				if not spot.is_empty():
					g.place(it, spot["pos"], spot["rot"])
					break
	if main != null and main.world_items != null:
		main.world_items.clear()
		for d in data.get("world", []):
			var p: Array = d.get("position", [0, 1, 0])
			main.world_items.spawn(_make(d), Transform3D(Basis(), Vector3(float(p[0]), float(p[1]), float(p[2]))))
	changed.emit()


func _make(d: Dictionary):
	return ItemScript.from_dict(d, ItemScript)


func register_container(id: String, grid_sizes: Array, node: Node3D, label: String = "") -> void:
	var grids: Array = []
	for s in grid_sizes:
		var g: Grid = Grid.new(int(s[0]), int(s[1]), WORLD_ACCESS)
		g.container_id = id
		grids.append(g)
	containers[id] = {"grids": grids, "node": node, "label": label if label != "" else "INV_CONTAINER_" + id}


func _reset() -> void:
	cancel_all()
	slots.clear()
	slot_reserved.clear()
	hotkeys.clear()
	hand_origin.clear()
	for cid in containers:
		for g in containers[cid]["grids"]:
			g.items.clear()
			g.reserved.clear()


func to_dict() -> Dictionary:
	var s := {}
	for k in slots:
		s[k] = slots[k].to_dict()
	var c := {}
	for cid in containers:
		var gl: Array = []
		for g in containers[cid]["grids"]:
			var arr: Array = []
			for it in g.items:
				arr.append(it.to_dict())
			gl.append(arr)
		c[cid] = gl
	var hk := {}
	for n in hotkeys:
		hk[str(n)] = hotkeys[n]
	return {"slots": s, "containers": c, "hotkeys": hk}


func from_dict(d: Dictionary) -> void:
	_reset()
	var s: Dictionary = d.get("slots", {})
	for k in s:
		slots[k] = _make(s[k])
		slots[k].slot = k
	var c: Dictionary = d.get("containers", {})
	for cid in c:
		if not containers.has(cid):
			continue
		var gl: Array = c[cid]
		for gi in mini(gl.size(), containers[cid]["grids"].size()):
			var g = containers[cid]["grids"][gi]
			for itd in gl[gi]:
				var it = _make(itd)
				g.place(it, it.pos, it.rot)
	var hk: Dictionary = d.get("hotkeys", {})
	for n in hk:
		hotkeys[int(n)] = int(hk[n])
	changed.emit()


# --- zapytania ------------------------------------------------------------------

func worn_grids() -> Array:
	var out: Array = []
	for s in GRID_SLOTS:
		if slots.has(s):
			out.append_array(slots[s].grids)
	return out


func quick_grids() -> Array:
	var out: Array = []
	for s in GRID_SLOTS:
		if slots.has(s) and bool(slots[s].get_def().get("quick", false)):
			out.append_array(slots[s].grids)
	return out


func all_carried() -> Array:
	var out: Array = []
	for s in slots:
		out.append(slots[s])
		out.append_array(slots[s].all_items())
	return out


func find_uid(uid: int):
	for it in all_carried():
		if it.uid == uid:
			return it
	for cid in containers:
		for g in containers[cid]["grids"]:
			for it in g.items:
				if it.uid == uid:
					return it
				for sub in it.all_items():
					if sub.uid == uid:
						return sub
	return null


func carried_mass() -> float:
	var m := 0.0
	for s in slots:
		m += slots[s].total_mass()
	return m


func felt_mass() -> float:
	var m := 0.0
	for s in slots:
		var it = slots[s]
		m += it.felt_mass() if s != HAND and s != LEFT_HAND and s != TWO_HANDS else it.total_mass()
	return m


static func speed_factor_for(felt: float) -> float:
	var t := clampf((felt - COMFORT_MASS) / (HEAVY_MASS - COMFORT_MASS), 0.0, 1.0)
	return lerpf(1.0, MIN_SPEED, t)


func speed_factor() -> float:
	return speed_factor_for(felt_mass())


func stamina_factor() -> float:
	return 1.0 + maxf(0.0, felt_mass() - COMFORT_MASS) / 15.0


## Liczba luźnych metalowych przedmiotów, które grzechoczą przy biegu.
func rattle_count() -> int:
	var n := 0
	for g in worn_grids():
		for it in g.items:
			if it.material() == "metal":
				n += 1
	return n


func hand_item():
	return hand("r")


## Przedmiot w ręce: "l" lewa, "r" prawa.
## Przy chwycie oburącz przedmiot liczy się jako trzymany w prawej ręce, lewa jest zajęta.
func hand(side: String):
	if slots.has(TWO_HANDS):
		return slots[TWO_HANDS] if side == "r" else null
	return slots.get(LEFT_HAND if side == "l" else HAND)


func hand_slot(side: String) -> String:
	if side == "r" and slots.has(TWO_HANDS):
		return TWO_HANDS
	return LEFT_HAND if side == "l" else HAND


## Coś jest trzymane oburącz (i nie właśnie odkładane).
func hands_two() -> bool:
	var it = slots.get(TWO_HANDS)
	return it != null and not _leaving(it)


## Przełącza przedmiot z prawej ręki na chwyt oburącz i z powrotem (klawisz Z).
func toggle_two_hands() -> bool:
	var it = slots.get(TWO_HANDS)
	if it != null:
		if it.is_bulky():
			return _fail("INV_ERR_BULKY")
		return move_to_slot(it, HAND)
	it = slots.get(HAND)
	if it == null:
		return _fail("INV_ERR_HAND_EMPTY")
	return move_to_slot(it, TWO_HANDS)


static func can_two_hand(item) -> bool:
	return item.is_bulky() or bool(item.get_def().get("two_hand", false))


## Ile sztuk dużego przedmiotu postać uniesie naraz (siła × współczynnik z danych).
func bulky_limit(item) -> int:
	var strength: float = float(main.player.strength) if main != null and main.player != null else 5.0
	var per: float = float(item.get_def().get("bulky", {}).get("per_strength", 0.2))
	return maxi(1, int(floor(strength * per + 0.0001)))


## Duży przedmiot w obu rękach.
func hands_bulky() -> bool:
	var it = slots.get(TWO_HANDS)
	return it != null and it.is_bulky() and not _leaving(it)


func slot_accepts(item, slot: String) -> bool:
	if item.is_bulky():
		return slot == TWO_HANDS
	if slot == TWO_HANDS:
		return can_two_hand(item)
	if (slot == LEFT_HAND or slot == HAND) and hands_two() and slots[TWO_HANDS] != item:
		return false
	var sd: Dictionary = ItemDB.slot_def(slot)
	if sd.is_empty():
		return false
	if bool(sd.get("any", false)):
		return true
	var d: Dictionary = item.get_def()
	if str(d.get("slot", "")) == slot:
		return true
	return sd.has("tag") and (d.get("tags", []) as Array).has(sd["tag"])


func is_quick(item) -> bool:
	return item.parent_grid != null and quick_grids().has(item.parent_grid)


func hotkey_of(item) -> int:
	for n in hotkeys:
		if hotkeys[n] == item.uid:
			return n
	return 0


# --- położenie i czasy ----------------------------------------------------------

func _location(item) -> Dictionary:
	if item.parent_grid != null:
		return {"kind": "grid", "grid": item.parent_grid}
	if item.slot != "":
		return {"kind": "slot", "slot": item.slot}
	for b in (main.world_items.bodies if main != null else []):
		if b.get_meta("item") == item:
			return {"kind": "world", "body": b}
	return {}


func _access(loc: Dictionary, item) -> float:
	match loc.get("kind", ""):
		"grid":
			return loc["grid"].access_time
		"slot":
			return HAND_ACCESS if loc["slot"] in [HAND, LEFT_HAND, TWO_HANDS] else WEAR_TIME * 0.5
		"world":
			return WORLD_ACCESS
	return 0.3


func _duration(src: Dictionary, dst: Dictionary, item) -> float:
	var t: float = _access(src, item) + _access(dst, item) + item.total_mass() * MASS_TIME
	if dst.get("kind", "") == "slot" and not dst["slot"] in [HAND, LEFT_HAND, TWO_HANDS]:
		t = maxf(t, WEAR_TIME)
	return snappedf(t, 0.05)


func _fail(msg_key: String) -> bool:
	last_error = msg_key
	return false


func _can_move(item) -> bool:
	if item.subtree_busy():
		return _fail("INV_ERR_BUSY")
	var loc := _location(item)
	if loc.is_empty():
		return _fail("INV_ERR_GONE")
	if loc["kind"] == "world" and not _in_reach(loc["body"]):
		return _fail("INV_ERR_FAR")
	return true


func _in_reach(node: Node3D) -> bool:
	if main == null or node == null or not is_instance_valid(node):
		return false
	return main.player.global_position.distance_to(node.global_position) <= PICKUP_RANGE


## Czy przedmiot można położyć w siatce w danym miejscu (bez kolejkowania).
func can_place_in_grid(item, grid, pos: Vector2i, rot: int) -> bool:
	if item.is_bulky():
		return _fail("INV_ERR_BULKY")
	if item.is_container() and item.owns_grid(grid):
		return _fail("INV_ERR_SELF")
	if not grid.can_place(item, pos, rot):
		return _fail("INV_ERR_NO_ROOM")
	# pusty plecak w innej siatce zajmuje mniej; po włożeniu czegoś musi się zmieścić rozłożony
	var owner = grid.owner_item
	if owner != null and owner.parent_grid != null and owner.is_empty_container() \
			and owner.get_def().has("shape_empty"):
		var full := ItemDB.cells(owner.full_shape(), owner.rot)
		if not owner.parent_grid.fits_cells(full, owner.pos, owner):
			return _fail("INV_ERR_NO_EXPAND")
	if grid.container_id != "" and not _in_reach(containers[grid.container_id]["node"]):
		return _fail("INV_ERR_FAR")
	return true


# --- czynności ----------------------------------------------------------------------

func move_to_grid(item, grid, pos: Vector2i, rot: int) -> bool:
	if not _can_move(item) or not can_place_in_grid(item, grid, pos, rot):
		return false
	var src := _location(item)
	if src["kind"] == "grid" and src["grid"].container_id != "" and not _in_reach(containers[src["grid"].container_id]["node"]):
		return _fail("INV_ERR_FAR")
	var dst := {"kind": "grid", "grid": grid, "pos": pos, "rot": rot}
	grid.reserve(item, pos, rot)
	_queue(item, src, dst)
	return true


func move_to_slot(item, slot: String) -> bool:
	if not _can_move(item):
		return false
	if not slot_accepts(item, slot):
		return _fail("INV_ERR_SLOT")
	if item.slot == slot:
		return _fail("INV_ERR_SAME")
	if slot_reserved.has(slot) or (slots.has(slot) and not _leaving(slots[slot])):
		return _fail("INV_ERR_SLOT_TAKEN")
	if slot == TWO_HANDS:
		for hs in [HAND, LEFT_HAND]:
			if slot_reserved.has(hs) or (slots.has(hs) and slots[hs] != item and not _leaving(slots[hs])):
				return _fail("INV_ERR_HANDS_FULL")
	var src := _location(item)
	slot_reserved[slot] = item
	_queue(item, src, {"kind": "slot", "slot": slot})
	return true


func move_to_world(item) -> bool:
	if not _can_move(item):
		return false
	var src := _location(item)
	if src["kind"] == "world":
		return _fail("INV_ERR_SAME")
	_queue(item, src, {"kind": "world"})
	return true


## Łączenie stosów: przenosi tyle sztuk, ile zmieści się w stosie docelowym.
func merge_into(item, target) -> bool:
	if item == target or item.def_id != target.def_id or target.count >= target.max_stack():
		return _fail("INV_ERR_NO_ROOM")
	if not _can_move(item) or target.pending:
		return _fail("INV_ERR_BUSY")
	var src := _location(item)
	_queue(item, src, {"kind": "merge", "target": target})
	target.pending = true
	return true


## Dzielenie stosu: n sztuk ląduje w nowym miejscu jako osobny stos.
func split_to_grid(item, n: int, grid, pos: Vector2i, rot: int) -> bool:
	if n <= 0 or n >= item.count:
		return _fail("INV_ERR_SPLIT")
	if not _can_move(item):
		return false
	var part = ItemScript.new(item.def_id, n, false)
	part.liquid = item.liquid.duplicate()
	if not can_place_in_grid(part, grid, pos, rot):
		return false
	grid.reserve(part, pos, rot)
	var src := _location(item)
	_queue(item, src, {"kind": "split", "grid": grid, "pos": pos, "rot": rot, "part": part, "n": n})
	return true


## Podniesienie bryły ze świata do pierwszego wolnego miejsca (albo do ręki).
func pick_up(body: RigidBody3D) -> bool:
	var item = body.get_meta("item")
	if not _can_move(item):
		return false
	if item.is_bulky():
		return _pick_up_bulky(item)
	if item.is_container() and str(item.get_def().get("slot", "")) != "" and not slots.has(item.get_def()["slot"]) \
			and not slot_reserved.has(item.get_def()["slot"]):
		return move_to_slot(item, item.get_def()["slot"])  # plecak czy kamizelkę od razu zakładamy
	for g in worn_grids():
		var spot: Dictionary = g.find_space(item)
		if not spot.is_empty() and can_place_in_grid(item, g, spot["pos"], spot["rot"]):
			return move_to_grid(item, g, spot["pos"], spot["rot"])
	if not hands_two():
		for hs in [HAND, LEFT_HAND]:
			if not slots.has(hs) and not slot_reserved.has(hs):
				return move_to_slot(item, hs)
	return _fail("INV_ERR_NO_ROOM")


## Duży przedmiot trafia do obu rąk; kolejna sztuka dokłada się do niesionego stosu.
func _pick_up_bulky(item) -> bool:
	var held = slots.get(TWO_HANDS)
	if held != null and held.def_id == item.def_id and held.is_bulky():
		if held.pending:
			return _fail("INV_ERR_BUSY")
		if held.count + item.count > bulky_limit(held):
			return _fail("INV_ERR_TOO_MANY")
		return merge_into(item, held)
	if held != null or slot_reserved.has(TWO_HANDS):
		return _fail("INV_ERR_HANDS_FULL")
	if item.count > bulky_limit(item):
		return _fail("INV_ERR_TOO_MANY")
	return move_to_slot(item, TWO_HANDS)


## Klawisz 1–9: wyjęcie przypisanego przedmiotu do ręki albo odłożenie z ręki.
func use_hotkey(n: int) -> bool:
	if not hotkeys.has(n):
		return _fail("INV_ERR_NO_HOTKEY")
	var item = find_uid(hotkeys[n])
	if item == null:
		return _fail("INV_ERR_GONE")
	if item.slot == HAND or item.slot == TWO_HANDS:
		return put_away_hand()
	if not is_quick(item):
		return _fail("INV_ERR_NOT_QUICK")
	if (slots.has(HAND) or slots.has(TWO_HANDS)) and not put_away_hand():
		return false
	hand_origin[item.uid] = {"grid": item.parent_grid, "pos": item.pos, "rot": item.rot}
	return move_to_slot(item, HAND)


## Odłożenie przedmiotu z ręki: na jego poprzednie miejsce, a jak zajęte, gdziekolwiek.
func put_away_hand() -> bool:
	var item = slots.get(TWO_HANDS, slots.get(HAND))
	if item == null:
		return _fail("INV_ERR_HAND_EMPTY")
	var o: Dictionary = hand_origin.get(item.uid, {})
	if not o.is_empty() and worn_grids().has(o["grid"]) and o["grid"].can_place(item, o["pos"], o["rot"]):
		return move_to_grid(item, o["grid"], o["pos"], o["rot"])
	for g in worn_grids():
		var spot: Dictionary = g.find_space(item)
		if not spot.is_empty() and can_place_in_grid(item, g, spot["pos"], spot["rot"]):
			return move_to_grid(item, g, spot["pos"], spot["rot"])
	return _fail("INV_ERR_NO_ROOM")


func set_hotkey(n: int, item) -> bool:
	if not is_quick(item) and item.slot != HAND and item.slot != TWO_HANDS:
		return _fail("INV_ERR_NOT_QUICK")
	for k in hotkeys.keys():
		if hotkeys[k] == item.uid:
			hotkeys.erase(k)
	hotkeys[n] = item.uid
	changed.emit()
	return true


## Czy przedmiot ma już w kolejce czynność, która go stąd zabierze.
## Kolejka wykonuje się po kolei, więc jego miejsce zwolni się przed następnymi.
func _leaving(item) -> bool:
	for a in actions:
		if a["item"] == item:
			return true
	return false


func _queue(item, src: Dictionary, dst: Dictionary) -> void:
	item.pending = true
	if src.get("kind", "") == "world":
		src["body"].set_meta("pending", true)
	actions.append({"item": item, "src": src, "dst": dst, "time": 0.0,
			"duration": _duration(src, dst, item)})
	last_error = ""
	changed.emit()


func current_action() -> Dictionary:
	return actions[0] if not actions.is_empty() else {}


func cancel_all() -> void:
	for a in actions.duplicate():
		_cancel(a)
	actions.clear()


func _cancel(a: Dictionary) -> void:
	var item = a["item"]
	item.pending = false
	var dst: Dictionary = a["dst"]
	match dst["kind"]:
		"grid":
			dst["grid"].unreserve(item)
		"split":
			dst["grid"].unreserve(dst["part"])
		"slot":
			slot_reserved.erase(dst["slot"])
		"merge":
			dst["target"].pending = false
	if a["src"].get("kind", "") == "world" and is_instance_valid(a["src"]["body"]):
		a["src"]["body"].remove_meta("pending")
	actions.erase(a)
	changed.emit()


func _process(delta: float) -> void:
	if actions.is_empty():
		return
	var a: Dictionary = actions[0]
	# podnoszenie przerywa się, gdy gracz odejdzie od przedmiotu albo pojemnika
	var src: Dictionary = a["src"]
	if src.get("kind", "") == "world" and not _in_reach(src["body"]):
		last_error = "INV_ERR_FAR"
		_cancel(a)
		return
	a["time"] += delta
	if a["time"] >= a["duration"]:
		actions.pop_front()
		_complete(a)
		changed.emit()


func _detach(item, src: Dictionary) -> void:
	match src.get("kind", ""):
		"grid":
			src["grid"].remove(item)
		"slot":
			slots.erase(src["slot"])
			item.slot = ""
		"world":
			if is_instance_valid(src["body"]):
				main.world_items.remove(src["body"])


func _complete(a: Dictionary) -> void:
	var item = a["item"]
	var src: Dictionary = a["src"]
	var dst: Dictionary = a["dst"]
	item.pending = false
	match dst["kind"]:
		"grid":
			dst["grid"].unreserve(item)
			_detach(item, src)
			dst["grid"].place(item, dst["pos"], dst["rot"])
		"slot":
			slot_reserved.erase(dst["slot"])
			if slots.has(dst["slot"]) and slots[dst["slot"]] != item:
				last_error = "INV_ERR_SLOT_TAKEN"  # poprzednia czynność nie zwolniła miejsca
				return
			_detach(item, src)
			slots[dst["slot"]] = item
			item.slot = dst["slot"]
			item.parent_grid = null
		"world":
			_detach(item, src)
			var xf := _drop_transform()
			if item.is_bulky() and item.count > 1:
				# stos desek spada jako osobne deski, jedna na drugiej
				for k in item.count - 1:
					main.world_items.spawn(ItemScript.new(item.def_id, 1), xf.translated(Vector3.UP * 0.05 * (k + 1)))
				item.count = 1
			main.world_items.spawn(item, xf)
		"merge":
			var target = dst["target"]
			target.pending = false
			var n := mini(item.count, target.max_stack() - target.count)
			target.count += n
			item.count -= n
			if item.count <= 0:
				_detach(item, src)
				_forget_hotkey(item)
		"split":
			var part = dst["part"]
			dst["grid"].unreserve(part)
			var n: int = mini(dst["n"], item.count - 1)
			if n > 0:
				item.count -= n
				part.count = n
				dst["grid"].place(part, dst["pos"], dst["rot"])


func _forget_hotkey(item) -> void:
	for k in hotkeys.keys():
		if hotkeys[k] == item.uid:
			hotkeys.erase(k)


func _drop_transform() -> Transform3D:
	var cam: Camera3D = main.player.camera
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var p: Vector3 = main.player.global_position + fwd * 0.55 + Vector3.UP * 1.0
	return Transform3D(Basis(Vector3.UP, main.player.rotation.y), p)


# --- zużywanie i oddawanie przedmiotów (praca narzędziem) ------------------

## Liczba sztuk przedmiotu przy sobie (w siatkach i w ręce).
func count_of(def_id: String) -> int:
	var n := 0
	for it in all_carried():
		if it.def_id == def_id:
			n += it.count
	return n


## Zabiera n sztuk przedmiotu z ekwipunku (gwoździe, wkręty). Natychmiast.
func consume(def_id: String, n: int = 1) -> bool:
	if count_of(def_id) < n:
		return false
	var left := n
	for it in all_carried():
		if left <= 0:
			break
		if it.def_id != def_id or it.pending:
			continue
		var take := mini(left, it.count)
		it.count -= take
		left -= take
		if it.count <= 0:
			if it.parent_grid != null:
				it.parent_grid.remove(it)
			elif it.slot != "":
				slots.erase(it.slot)
			_forget_hotkey(it)
	changed.emit()
	return left <= 0


## Zabiera przedmiot z ręki (przyłożony do gniazda staje się częścią świata).
func take_hand(side: String = "r"):
	var hs := hand_slot(side)
	var it = slots.get(hs)
	if it == null:
		return null
	if it.is_bulky() and it.count > 1:
		it.count -= 1  # z niesionego stosu odchodzi jedna sztuka
		changed.emit()
		return ItemScript.new(it.def_id, 1)
	slots.erase(hs)
	it.slot = ""
	_forget_hotkey(it)
	changed.emit()
	return it


## Oddaje przedmiot postaci: dokłada do stosów, potem pierwsze wolne miejsce,
## potem ręka, a gdy nigdzie się nie mieści, upada na ziemię.
func give(item) -> String:
	if item.max_stack() > 1:
		for it in all_carried():
			if it.def_id == item.def_id and it != item and not it.pending and it.count < it.max_stack():
				var n := mini(item.count, it.max_stack() - it.count)
				it.count += n
				item.count -= n
				if item.count <= 0:
					changed.emit()
					return "stack"
	for g in worn_grids():
		if place_now(item, g):
			return "grid"
	for hs in [HAND, LEFT_HAND]:
		if not hands_two() and not slots.has(hs) and not slot_reserved.has(hs):
			slots[hs] = item
			item.slot = hs
			changed.emit()
			return "hand"
	main.world_items.spawn(item, _drop_transform())
	changed.emit()
	return "world"


## Zabiera n sztuk z ręki (gwóźdź z garści); gdy w ręce brak, z reszty ekwipunku.
func consume_hand(side: String, def_id: String, n: int = 1) -> bool:
	var it = hand(side)
	if it == null or it.def_id != def_id or it.count < n:
		return consume(def_id, n)
	it.count -= n
	if it.count <= 0:
		slots.erase(hand_slot(side))
		it.slot = ""
		_forget_hotkey(it)
	changed.emit()
	return true


## Usuwa przedmiot z miejsca, w którym leży (zużyty opatrunek, pusty spirytus).
func remove_item(item) -> void:
	if item.parent_grid != null:
		item.parent_grid.remove(item)
	elif item.slot != "":
		slots.erase(item.slot)
		item.slot = ""
	_forget_hotkey(item)
	changed.emit()


func has_key(key_id) -> bool:
	for it in all_carried():
		if it.def_id == "klucz" and it.props.get("key_id", -1) == key_id:
			return true
	return false


## Natychmiastowe położenie przedmiotu (dane startowe, testy). Pomija czas.
func place_now(item, grid) -> bool:
	var spot: Dictionary = grid.find_space(item)
	if spot.is_empty():
		return false
	grid.place(item, spot["pos"], spot["rot"])
	changed.emit()
	return true
