extends Node
## Drzwi do komórki: zatrzask, klamka, zamek z nakładką na wkręty, klucz,
## wyważanie łomem.
##   zatrzask: zamknięte drzwi trzymają się na zatrzasku (bryła zamrożona);
##     F na drzwiach naciska klamkę i pcha je, chwyt T i pociągnięcie myszą
##     w dół naciska klamkę ręką; domknięte drzwi same zaskakują,
##   zamek: nakładka (2 wkręty) na ościeżnicy i zamek (4 wkręty) na skrzydle;
##     zamek działa, gdy oba trzymają; zamyka się kluczem albo od środka (F),
##   wkręty: kręcenie myszą; otwór wykręcany i wkręcany ponownie trzyma słabiej;
##     zużyta końcówka może zerwać łeb wkrętu; wykręcenie wszystkich wkrętów
##     zdejmuje część do ręki,
##   wyważanie: łom w szczelinie przy zamku; opór zależy od tego, czy drzwi
##     są zamknięte na klucz i jak mocno trzymają wkręty; wyłamany zamek
##     i nakładka spadają na ziemię.

const ItemScript := preload("res://scripts/inventory/item.gd")
const Fasteners := preload("res://scripts/world/fasteners.gd")

const SCREW_TURNS := 4.0            # pełne obroty na wkręt (narzędzie poziomu 3)
const HOLE_WEAR := 0.35             # każde wykręcenie osłabia otwór
const STRIP_BELOW := 0.3            # poniżej tego stanu końcówka zrywa łby
const STRIP_CHANCE := 0.08          # na obrót
const LATCH_ANGLE := 0.08           # radiany: tak blisko zamknięcia drzwi zaskakują (ok. 4,5°)
const HANDLE_PULL := 0.17           # radiany pochylenia wzroku, by nacisnąć klamkę ręką
const PRY_LATCHED := 1.2
const PRY_LOCKED := 2.0
const PRY_PER_SCREW := 0.6

var main
var work
var door: RigidBody3D
var closed: Transform3D
var latched := true
var locked := false
var parts := {}
var rng := RandomNumberGenerator.new()

var _handles: Array = []
var _handle_angle := 0.0
var _handle_hold := 0.0
var _relatch_block := 0.0
var _pry := 0.0
var _zbang := 0.0
var _pry_point = null
var _turn_acc := 0.0
var _msg_cool := 0.0


func setup(main_node, work_system, door_body: RigidBody3D, jamb: Vector3) -> void:
	main = main_node
	work = work_system
	door = door_body
	rng.seed = 5
	closed = door.global_transform
	door.set_meta("door_sys", self)
	_make_handles()
	parts["nakladka"] = _part(main.world, jamb, Vector3(0.026, 0.12, 0.006),
			[Vector3(0, 0.04, -0.006), Vector3(0, -0.04, -0.006)], "nakladka")
	parts["zamek"] = _part(door, Vector3(0.036, 0.08, 0.36), Vector3(0.03, 0.16, 0.1),
			[Vector3(0.053, 0.14, 0.33), Vector3(0.053, 0.14, 0.39), Vector3(0.053, 0.02, 0.33), Vector3(0.053, 0.02, 0.39)], "zamek")
	_pry_point = work.add_point(self, door, Vector3(-0.03, 0.01, 0.465), "lever",
			{"ability": "podwazanie", "min_level": 2, "label": "WORK_PRY_DOOR", "data": {"what": "pry"}})
	_set_latched(true)
	_refresh()


func _make_handles() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.46, 0.36)
	mat.metallic = 0.5
	mat.roughness = 0.5
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.03, -0.04, 0.4)
		door.add_child(pivot)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.025, 0.022, 0.11)
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(side * 0.018, 0, -0.045)
		pivot.add_child(mi)
		_handles.append(pivot)


## Część montowana: węzeł z modelem (ukryty, dopóki nie przyłożona) i punkty pracy.
func _part(parent: Node3D, pos: Vector3, size: Vector3, screw_locals: Array, mount: String) -> Dictionary:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.48, 0.42) if mount == "nakladka" else Color(0.42, 0.4, 0.35)
	mat.metallic = 0.4
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.visible = false
	parent.add_child(node)
	var p := {"placed": false, "item": null, "node": node, "screws": [], "holes": [], "points": [], "mount": mount, "vis": []}
	var outward := Vector3.FORWARD if mount == "nakladka" else Vector3.RIGHT
	p["attach"] = work.add_point(self, node, Vector3(0, 0, -0.01) if mount == "nakladka" else Vector3(0.02, 0, 0), "attach",
			{"accepts": mount, "label": "WORK_PLACE_" + mount.to_upper(), "data": {"what": "attach", "part": mount}})
	for k in screw_locals.size():
		p["screws"].append({"in": false, "t": 0.0, "stripped": false})
		p["holes"].append(0)
		var local: Vector3 = screw_locals[k] - (Vector3.ZERO if mount == "nakladka" else pos)
		p["vis"].append(Fasteners.make("screw", node, local, outward))
		p["points"].append(work.add_point(self, node, local, "rotate",
				{"ability": "wkrecanie", "label": "WORK_SCREW", "data": {"what": "screw", "part": mount, "screw": k}}))
	return p


## Wkręt dokręcony do oporu świeci na czerwono (do wykręcenia), inaczej na niebiesko.
func work_category(point) -> String:
	var d: Dictionary = point.data
	if d.get("what", "") != "screw":
		return ""
	var p: Dictionary = parts[d["part"]]
	var sc: Dictionary = p["screws"][d["screw"]]
	var cap: float = 1.0 / (1.0 + HOLE_WEAR * p["holes"][d["screw"]])
	return "remove" if sc["in"] and sc["t"] >= cap - 0.001 else "mount"


func _refresh() -> void:
	for name in parts:
		var p: Dictionary = parts[name]
		p["node"].visible = p["placed"]
		p["attach"].enabled = not p["placed"]
		for k in p["points"].size():
			p["points"][k].enabled = p["placed"] and not p["screws"][k]["stripped"]
			var sc: Dictionary = p["screws"][k]
			# wkręt chowa się z każdym obrotem, nacięcie łba obraca się z wkrętakiem
			Fasteners.set_state(p["vis"][k], Fasteners.SCREW_LEN * 0.9 * (1.0 - sc["t"]) + 0.0004,
					sc["t"] * SCREW_TURNS, false, p["placed"] and sc["in"])
	_pry_point.enabled = latched


# --- stan drzwi ------------------------------------------------------------------------

func door_angle() -> float:
	return closed.basis.get_rotation_quaternion().angle_to(door.global_transform.basis.get_rotation_quaternion())


func _set_latched(value: bool) -> void:
	latched = value
	if value:
		door.linear_velocity = Vector3.ZERO
		door.angular_velocity = Vector3.ZERO
		door.global_transform = closed
	door.freeze = value
	if not value:
		door.sleeping = false
		_relatch_block = 0.8
	if _pry_point != null:
		_refresh()


static func part_strength(p: Dictionary) -> float:
	var s := 0.0
	if not p["placed"]:
		return 0.0
	for sc in p["screws"]:
		if sc["in"]:
			s += sc["t"]
	return s


static func _held_screws(p: Dictionary, min_t: float) -> int:
	var n := 0
	for sc in p["screws"]:
		if sc["in"] and sc["t"] >= min_t:
			n += 1
	return n


## Zamek działa, gdy zamek trzyma się na co najmniej 2 wkrętach, a nakładka na 1.
func lock_works() -> bool:
	return _held_screws(parts["zamek"], 0.5) >= 2 and _held_screws(parts["nakladka"], 0.5) >= 1


func pry_effort() -> float:
	if locked:
		return PRY_LOCKED + (part_strength(parts["zamek"]) + part_strength(parts["nakladka"])) * PRY_PER_SCREW
	return PRY_LATCHED


func player_inside() -> bool:
	return main.player.global_position.x > closed.origin.x


func _say(key: String) -> void:
	if _msg_cool <= 0.0:
		main.hud.show_message(tr(key))
		_msg_cool = 1.0


## Naciśnięcie klamki (F albo chwyt i pociągnięcie w dół).
func try_unlatch() -> bool:
	if not latched:
		return true
	if locked:
		_say("MSG_DOOR_LOCKED")
		main.noise.emit_noise(door.global_position, 25.0, "NOISE_HANDLE")
		return false
	_set_latched(false)
	_handle_hold = 0.3
	main.noise.emit_noise(door.global_position, 25.0, "NOISE_HANDLE")
	return true


## F na drzwiach: zamek (z kluczem albo od środka), zdjęcie nieprzykręconej
## części, a w pozostałych przypadkach klamka i pchnięcie.
func on_use(hit: Vector3) -> void:
	for name in parts:
		var p: Dictionary = parts[name]
		if p["placed"] and hit.distance_to(p["node"].global_position) < 0.12:
			if part_strength(p) <= 0.0 and _held_screws(p, 0.0) == 0:
				_detach(name)
				return
			if name == "zamek" and lock_works():
				toggle_lock()
				return
	if latched:
		if try_unlatch():
			_push_away()
	else:
		_push_away()


func toggle_lock() -> bool:
	var key_id = parts["zamek"]["item"].props.get("key_id", -1) if parts["zamek"]["item"] != null else -1
	if not player_inside() and not main.inventory.has_key(key_id):
		_say("MSG_NEED_KEY")
		return false
	if not latched:
		_say("MSG_DOOR_OPEN")
		return false
	locked = not locked
	main.hud.show_message(tr("MSG_LOCKED" if locked else "MSG_UNLOCKED"))
	main.noise.emit_noise(door.global_position, 20.0, "NOISE_LOCK")
	return true


## Pchnięcie skrzydła od gracza (otwiera albo domyka, zależnie od strony).
## Otwarcie po naciśnięciu klamki: skrzydło idzie zawsze do pokoju (jedyna strona,
## w którą się otwiera); z komórki to pchnięcie, z pokoju pociągnięcie do siebie.
func _push_away() -> void:
	var edge := door.global_transform * Vector3(0, 0, 0.4)
	door.sleeping = false
	door.apply_impulse(Vector3.LEFT * 20.0, edge - door.global_position)


## Czy skrzydło porusza się w stronę framugi (krawędź drzwi jedzie w +X).
func _swinging_shut() -> bool:
	var edge := door.global_transform * Vector3(0, 0, 0.4)
	var v: Vector3 = door.angular_velocity.cross(edge - door.global_position)
	return v.x > 0.05


## Chwyt T na drzwiach z zatrzaskiem: pochylenie wzroku naciska klamkę.
func handle_pull(pitch_drop: float) -> void:
	_handle_angle = clampf(pitch_drop * 2.5, 0.0, 0.7)
	if pitch_drop >= HANDLE_PULL:
		try_unlatch()


func _physics_process(delta: float) -> void:
	_msg_cool -= delta
	if _relatch_block > 0.0:
		_relatch_block -= delta
	if _handle_hold > 0.0:
		_handle_hold -= delta
		_handle_angle = 0.6
	elif main.interaction == null or main.interaction.held != door:
		_handle_angle = move_toward(_handle_angle, 0.0, 3.0 * delta)
	for h in _handles:
		h.rotation.x = -_handle_angle
	# domknięte drzwi zaskakują: wystarczy machnąć nimi w stronę framugi, także
	# trzymając je w ręce (wtedy chwyt puszcza); otwarcie wymaga znów klamki
	if not latched and _relatch_block <= 0.0 and door_angle() < LATCH_ANGLE:
		var held: bool = main.interaction.held == door
		var closing: bool = _swinging_shut() or (not held and door.angular_velocity.length() < 0.6)
		if closing:
			if main.interaction.held == door:
				main.interaction.release()
			_set_latched(true)
			main.noise.emit_noise(door.global_position, 35.0, "NOISE_DOOR_CLICK")


# --- praca ------------------------------------------------------------------------------

func work_apply(point, ev: Dictionary) -> void:
	var d: Dictionary = point.data
	match d["what"]:
		"attach":
			var p: Dictionary = parts[d["part"]]
			if p["placed"] or ev.get("item") == null:
				return
			p["item"] = main.inventory.take_hand(str(ev.get("side", "r")))
			p["placed"] = true
			for sc in p["screws"]:
				sc["in"] = false
				sc["t"] = 0.0
				sc["stripped"] = false
			main.noise.emit_noise(point.world_pos(), 20.0, "NOISE_PLACE")
		"screw":
			_screw(parts[d["part"]], d["part"], d["screw"], ev)
			_refresh()
		"pry":
			var before := _pry
			_pry += float(ev.get("amount", 0.0))
			if floorf(_pry / 0.5) > floorf(before / 0.5):
				main.noise.emit_noise(point.world_pos(), 60.0, "NOISE_PRY")
			if _pry >= pry_effort():
				_force_open()
	_refresh()


func _screw(p: Dictionary, name: String, k: int, ev: Dictionary) -> void:
	var sc: Dictionary = p["screws"][k]
	if sc["stripped"]:
		return
	var turns := float(ev.get("turns", 0.0))
	if not sc["in"]:
		if turns <= 0.0:
			return
		if not main.inventory.consume("wkrety", 1):
			_say("MSG_NO_SCREWS")
			return
		sc["in"] = true
	var cap: float = 1.0 / (1.0 + HOLE_WEAR * p["holes"][k])
	var before: float = sc["t"]
	sc["t"] = clampf(sc["t"] + turns / SCREW_TURNS, 0.0, cap)
	if turns > 0.0 and before >= cap - 0.0001 and cap < 1.0:
		_say("MSG_LOOSE_HOLE")
	if turns > 0.0 and before < cap - 0.0001 and sc["t"] >= cap - 0.0001 and main.get("sound") != null:
		main.sound.play("screw_tight", p["node"].global_position, -4.0)  # dokręcony: klik
	# zużycie narzędzia i zrywanie łbów
	var tool = ev.get("tool")
	var raw := absf(float(ev.get("raw", 0.0)))
	if tool != null and sc["t"] != before:
		_turn_acc += raw
		while _turn_acc >= 1.0:
			_turn_acc -= 1.0
			var wear := float(tool.get_def().get("wear", 0.0))
			if wear > 0.0:
				tool.props["condition"] = maxf(0.0, tool.condition() - wear)
			if tool.condition() < STRIP_BELOW and rng.randf() < STRIP_CHANCE:
				sc["stripped"] = true
				_say("MSG_STRIPPED")
				main.noise.emit_noise(door.global_position, 15.0, "NOISE_SCREW")
				return
			main.noise.emit_noise(p["node"].global_position, 15.0, "NOISE_SCREW")
	# wykręcony wkręt wraca do ekwipunku, a otwór jest odtąd słabszy
	if sc["in"] and sc["t"] <= 0.0 and turns < 0.0:
		sc["in"] = false
		p["holes"][k] += 1
		main.inventory.give(ItemScript.new("wkrety", 1))
		if _held_screws(p, 0.0) == 0:
			_detach(name)


## Zdjęcie części bez wkrętów: wraca do ręki (albo do ekwipunku, albo na ziemię).
func _detach(name: String) -> void:
	var p: Dictionary = parts[name]
	if not p["placed"]:
		return
	if name == "nakladka" or name == "zamek":
		locked = false
	var item = p["item"]
	p["placed"] = false
	p["item"] = null
	for sc in p["screws"]:
		sc["in"] = false
		sc["t"] = 0.0
	if item != null:
		main.inventory.give(item)
	_refresh()


## Wyważenie: zatrzask puszcza; zamknięte na klucz drzwi wyłamują zamek i nakładkę.
## Zombie wali w zatrzaśnięte drzwi: po chwili wyłamuje zatrzask, a z zamkiem
## (zależnie od tego, jak mocno trzyma) trwa to znacznie dłużej.
func zombie_bang(delta: float) -> void:
	if not latched:
		return
	_zbang += delta
	if int(_zbang * 1.5) != int((_zbang - delta) * 1.5):
		main.noise.emit_noise(door.global_position, 65.0, "NOISE_DOOR_BANG")
	var need := 8.0
	if locked:
		need = 14.0 + 10.0 * (part_strength(parts["zamek"]) + part_strength(parts["nakladka"]))
	if _zbang >= need:
		_zbang = 0.0
		_force_open()


func _force_open() -> void:
	_pry = 0.0
	if locked:
		for name in ["zamek", "nakladka"]:
			var p: Dictionary = parts[name]
			if p["placed"] and p["item"] != null:
				var it = p["item"]
				it.props["condition"] = 0.3  # wyłamany: uszkodzony
				var at: Vector3 = p["node"].global_position + Vector3(-0.3, 0.0, 0.0)
				main.world_items.spawn(it, Transform3D(Basis(), at))
			p["placed"] = false
			p["item"] = null
			for sc in p["screws"]:
				sc["in"] = false
				sc["t"] = 0.0
		locked = false
		main.hud.show_message(tr("MSG_DOOR_BROKEN"))
	main.noise.emit_noise(door.global_position, 85.0, "NOISE_DOOR_BREAK")
	_set_latched(false)
	_push_away()


func work_status(point) -> Dictionary:
	var d: Dictionary = point.data
	match d["what"]:
		"screw":
			var p: Dictionary = parts[d["part"]]
			var sc: Dictionary = p["screws"][d["screw"]]
			var cap: float = 1.0 / (1.0 + HOLE_WEAR * p["holes"][d["screw"]])
			var key := "WORK_STATUS_SCREW_LOOSE" if cap < 1.0 else "WORK_STATUS_SCREW"
			return {"text": tr(key) % (sc["t"] * SCREW_TURNS), "ratio": sc["t"]}
		"pry":
			return {"text": tr("WORK_STATUS_PRY_DOOR_LOCKED" if locked else "WORK_STATUS_PRY_DOOR"), "ratio": _pry / pry_effort()}
	return {"text": "", "ratio": -1.0}


# --- zapis --------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var ps := {}
	for name in parts:
		var p: Dictionary = parts[name]
		var screws: Array = []
		for sc in p["screws"]:
			screws.append(sc.duplicate())
		ps[name] = {"placed": p["placed"], "item": p["item"].to_dict() if p["item"] != null else null,
				"screws": screws, "holes": p["holes"].duplicate()}
	return {"latched": latched, "locked": locked, "pry": _pry, "parts": ps}


func from_dict(d: Dictionary) -> void:
	var ps: Dictionary = d.get("parts", {})
	for name in parts:
		if not ps.has(name):
			continue
		var p: Dictionary = parts[name]
		var src: Dictionary = ps[name]
		p["placed"] = bool(src.get("placed", false))
		p["item"] = ItemScript.from_dict(src["item"], ItemScript) if src.get("item") != null else null
		var screws: Array = src.get("screws", [])
		for k in mini(screws.size(), p["screws"].size()):
			p["screws"][k] = {"in": bool(screws[k].get("in", false)), "t": float(screws[k].get("t", 0.0)),
					"stripped": bool(screws[k].get("stripped", false))}
		var holes: Array = src.get("holes", [])
		for k in mini(holes.size(), p["holes"].size()):
			p["holes"][k] = int(holes[k])
	locked = bool(d.get("locked", false))
	_pry = float(d.get("pry", 0.0))
	var want_latched := bool(d.get("latched", true))
	if want_latched:
		_set_latched(true)
	else:
		latched = false
		door.freeze = false
	_refresh()
