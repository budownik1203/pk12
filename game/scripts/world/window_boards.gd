extends Node3D
## Okno zabite deskami. Trzy miejsca na deski; każda deska ma dwa końce,
## a każdy koniec dwa gwoździe.
##   zrywanie: łom (albo słabiej pazur młotka) na końcu deski, ruch myszy w dół;
##     opór rośnie z liczbą wbitych gwoździ; po uwolnieniu obu końców deska
##     spada jako przedmiot, a część gwoździ da się odzyskać,
##   barykadowanie: deska w ręce, lewy przycisk na pustym miejscu przykłada ją,
##     potem młotek: zamach i uderzenie, 3 uderzenia na gwóźdź; za mocny zamach
##     wygina gwóźdź, który trzeba wyciągnąć, zanim wbije się nowy.
## Deska trzyma, gdy na każdym końcu jest przynajmniej jeden wbity gwóźdź.

const ItemScript := preload("res://scripts/inventory/item.gd")
const Tex := preload("res://scripts/textures.gd")

const SLOTS := 3
const HEIGHTS := [-0.36, 0.0, 0.36]
const BOARD_SIZE := Vector3(1.5, 0.14, 0.025)
const END_X := 0.66                 # koniec deski od środka okna (deski zachodzą na mur)
const NAIL_X := 0.7
const NAIL_DY := 0.035
const STRIKES_PER_NAIL := 3.0
const PRY_BASE := 1.0
const PRY_PER_NAIL := 0.8
const PULL_EFFORT := 0.6
const NAIL_RECOVERY := 0.5          # szansa odzyskania gwoździa ze zrywanej deski

var main
var work
var boards: Array = []
var rng := RandomNumberGenerator.new()
var _wood: Material


func setup(main_node, work_system) -> void:
	main = main_node
	work = work_system
	rng.seed = 7
	_wood = Tex.material("wood", false, 1.0)
	for i in SLOTS:
		boards.append(_fresh(i))
		_make_points(i)
		_set_nailed(i)


func _fresh(_i: int) -> Dictionary:
	return {"state": "none", "body": null, "recovered": 0, "points": [],
			"ends": [{"nails": [0.0, 0.0], "pry": 0.0, "free": false, "pull": [0.0, 0.0]},
					{"nails": [0.0, 0.0], "pry": 0.0, "free": false, "pull": [0.0, 0.0]}]}


func _set_nailed(i: int) -> void:
	var b: Dictionary = boards[i]
	b["state"] = "nailed"
	for e in b["ends"]:
		e["nails"] = [STRIKES_PER_NAIL, STRIKES_PER_NAIL]
		e["free"] = false
		e["pry"] = 0.0
	_build_body(i)
	_refresh(i)


# --- geometria ----------------------------------------------------------------------

func _slot_origin(i: int) -> Vector3:
	return Vector3(0.0, HEIGHTS[i], -BOARD_SIZE.z / 2.0 - 0.003)


func _build_body(i: int) -> void:
	var b: Dictionary = boards[i]
	if b["body"] != null:
		b["body"].queue_free()
	var body := StaticBody3D.new()
	body.name = "Deska_%d" % i
	var mesh := BoxMesh.new()
	mesh.size = BOARD_SIZE
	mesh.material = _wood
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = BOARD_SIZE
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	add_child(body)
	b["body"] = body
	_pose_body(i)


## Deska z jednym wolnym końcem obwisa na drugim.
func _pose_body(i: int) -> void:
	var b: Dictionary = boards[i]
	var body: StaticBody3D = b["body"]
	if body == null:
		return
	var xf := Transform3D(Basis(), _slot_origin(i))
	var e0: bool = b["ends"][0]["free"]
	var e1: bool = b["ends"][1]["free"]
	if e0 != e1:
		var pivot_x := END_X if e0 else -END_X
		var angle := deg_to_rad(9.0) * (1.0 if e0 else -1.0)
		var pivot := Vector3(pivot_x, HEIGHTS[i], _slot_origin(i).z)
		xf = Transform3D(Basis(Vector3.BACK, angle), Vector3.ZERO).translated(pivot) * Transform3D(Basis(), _slot_origin(i) - pivot)
	body.transform = xf


func _make_points(i: int) -> void:
	var b: Dictionary = boards[i]
	var pts: Array = []
	var o := _slot_origin(i)
	var front := -BOARD_SIZE.z / 2.0 - 0.004
	pts.append(work.add_point(self, self, o + Vector3(0, 0, -0.02), "attach",
			{"accepts": "deska", "label": "WORK_PLACE_BOARD", "data": {"slot": i, "what": "attach"}}))
	for e in 2:
		var sx := -1.0 if e == 0 else 1.0
		pts.append(work.add_point(self, self, o + Vector3(sx * (END_X - 0.07), 0, front), "lever",
				{"ability": "podwazanie", "label": "WORK_PRY_BOARD", "data": {"slot": i, "end": e, "what": "pry"}}))
		for n in 2:
			var ny := NAIL_DY if n == 0 else -NAIL_DY
			var at := o + Vector3(sx * NAIL_X, ny, front)
			pts.append(work.add_point(self, self, at, "strike",
					{"ability": "wbijanie", "label": "WORK_NAIL", "data": {"slot": i, "end": e, "nail": n, "what": "nail"}}))
			pts.append(work.add_point(self, self, at, "lever",
					{"ability": "podwazanie", "label": "WORK_PULL_NAIL", "data": {"slot": i, "end": e, "nail": n, "what": "pull"}}))
	b["points"] = pts


func _refresh(i: int) -> void:
	var b: Dictionary = boards[i]
	var st: String = b["state"]
	var on_wall: bool = st == "placed" or st == "nailed"
	for p in b["points"]:
		var d: Dictionary = p.data
		match d["what"]:
			"attach":
				p.enabled = st == "none"
			"pry":
				p.enabled = on_wall and not b["ends"][d["end"]]["free"]
			"nail":
				var v: float = b["ends"][d["end"]]["nails"][d["nail"]]
				p.enabled = on_wall and not b["ends"][d["end"]]["free"] and v >= 0.0 and v < STRIKES_PER_NAIL
			"pull":
				p.enabled = on_wall and b["ends"][d["end"]]["nails"][d["nail"]] < 0.0


static func driven(end: Dictionary) -> int:
	var n := 0
	for v in end["nails"]:
		if v >= STRIKES_PER_NAIL:
			n += 1
	return n


func pry_effort(end: Dictionary) -> float:
	return PRY_BASE + driven(end) * PRY_PER_NAIL


func is_secure(i: int) -> bool:
	for e in boards[i]["ends"]:
		if driven(e) < 1:
			return false
	return true


func secure_count() -> int:
	var n := 0
	for i in SLOTS:
		if boards[i]["state"] == "nailed":
			n += 1
	return n


# --- praca ----------------------------------------------------------------------------

func work_apply(point, ev: Dictionary) -> void:
	var d: Dictionary = point.data
	var i: int = d["slot"]
	var b: Dictionary = boards[i]
	match d["what"]:
		"attach":
			if b["state"] != "none" or ev.get("item") == null:
				return
			main.inventory.take_hand()
			b["state"] = "placed"
			for e in b["ends"]:
				e["nails"] = [0.0, 0.0]
				e["free"] = false
				e["pry"] = 0.0
			_build_body(i)
			main.noise.emit_noise(point.world_pos(), 30.0, "NOISE_PLACE")
		"pry":
			var end: Dictionary = b["ends"][d["end"]]
			var before: float = end["pry"]
			end["pry"] += float(ev.get("amount", 0.0))
			if floorf(end["pry"] / 0.5) > floorf(before / 0.5):
				main.noise.emit_noise(point.world_pos(), 55.0, "NOISE_PRY")
			if end["pry"] >= pry_effort(end):
				_free_end(i, d["end"])
		"nail":
			if ev.get("type", "") != "strike":
				return
			var end: Dictionary = b["ends"][d["end"]]
			var v: float = end["nails"][d["nail"]]
			if v <= 0.0:
				if not main.inventory.consume("gwozdzie", 1):
					main.hud.show_message(tr("MSG_NO_NAILS"))
					return
			main.noise.emit_noise(point.world_pos(), 70.0, "NOISE_HAMMER")
			if bool(ev.get("bend", false)):
				end["nails"][d["nail"]] = -1.0
				main.hud.show_message(tr("MSG_NAIL_BENT"))
			else:
				end["nails"][d["nail"]] = minf(v + float(ev.get("amount", 1.0)), STRIKES_PER_NAIL)
				if b["state"] == "placed" and is_secure(i):
					b["state"] = "nailed"
		"pull":
			var end: Dictionary = b["ends"][d["end"]]
			end["pull"][d["nail"]] += float(ev.get("amount", 0.0))
			if end["pull"][d["nail"]] >= PULL_EFFORT:
				end["pull"][d["nail"]] = 0.0
				end["nails"][d["nail"]] = 0.0
				main.noise.emit_noise(point.world_pos(), 40.0, "NOISE_PULL")
	_refresh(i)


func _free_end(i: int, e: int) -> void:
	var b: Dictionary = boards[i]
	var end: Dictionary = b["ends"][e]
	for n in 2:
		if end["nails"][n] >= STRIKES_PER_NAIL and rng.randf() < NAIL_RECOVERY:
			b["recovered"] += 1
	end["nails"] = [0.0, 0.0]
	end["free"] = true
	end["pry"] = 0.0
	main.noise.emit_noise(to_global(_slot_origin(i)), 60.0, "NOISE_BOARD_OFF")
	if b["ends"][0]["free"] and b["ends"][1]["free"]:
		_drop_board(i)
	else:
		if b["state"] == "nailed":
			b["state"] = "placed"
		_pose_body(i)


func _drop_board(i: int) -> void:
	var b: Dictionary = boards[i]
	var body: StaticBody3D = b["body"]
	var xf: Transform3D = body.global_transform
	body.queue_free()
	b["body"] = null
	# model deski leży płasko: obracamy go do pionu, w jakim wisiała na oknie
	var item_xf := Transform3D(xf.basis * Basis(Vector3.RIGHT, PI / 2.0), xf.origin + xf.basis.z * -0.05)
	main.world_items.spawn(ItemScript.new("deska"), item_xf)
	if b["recovered"] > 0:
		var nails_xf := Transform3D(Basis(), xf.origin + xf.basis.z * -0.25 + Vector3.DOWN * 0.2)
		main.world_items.spawn(ItemScript.new("gwozdzie", b["recovered"]), nails_xf)
	var fresh := _fresh(i)
	b["state"] = "none"
	b["recovered"] = 0
	b["ends"] = fresh["ends"]


func work_status(point) -> Dictionary:
	var d: Dictionary = point.data
	var b: Dictionary = boards[d["slot"]]
	match d["what"]:
		"pry":
			var end: Dictionary = b["ends"][d["end"]]
			return {"text": tr("WORK_STATUS_PRY") % driven(end), "ratio": end["pry"] / pry_effort(end)}
		"nail":
			var v: float = b["ends"][d["end"]]["nails"][d["nail"]]
			return {"text": tr("WORK_STATUS_NAIL"), "ratio": maxf(v, 0.0) / STRIKES_PER_NAIL}
		"pull":
			return {"text": tr("WORK_STATUS_PULL"), "ratio": b["ends"][d["end"]]["pull"][d["nail"]] / PULL_EFFORT}
	return {"text": "", "ratio": -1.0}


# --- zapis ------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var out: Array = []
	for b in boards:
		var ends: Array = []
		for e in b["ends"]:
			ends.append({"nails": e["nails"].duplicate(), "pry": e["pry"], "free": e["free"]})
		out.append({"state": b["state"], "recovered": b["recovered"], "ends": ends})
	return {"boards": out}


func from_dict(d: Dictionary) -> void:
	var list: Array = d.get("boards", [])
	for i in mini(list.size(), SLOTS):
		var b: Dictionary = boards[i]
		var src: Dictionary = list[i]
		b["state"] = str(src.get("state", "none"))
		b["recovered"] = int(src.get("recovered", 0))
		var ends: Array = src.get("ends", [])
		for e in mini(ends.size(), 2):
			b["ends"][e]["nails"] = [float(ends[e]["nails"][0]), float(ends[e]["nails"][1])]
			b["ends"][e]["pry"] = float(ends[e].get("pry", 0.0))
			b["ends"][e]["free"] = bool(ends[e].get("free", false))
		if b["state"] == "none":
			if b["body"] != null:
				b["body"].queue_free()
				b["body"] = null
		else:
			_build_body(i)
		_refresh(i)
