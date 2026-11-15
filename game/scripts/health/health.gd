extends Node
## Zdrowie postaci: 17 segmentów ciała, rany, krew, ból i zakażenie.
## Każda rana ma rodzaj, ciężkość, krwawienie, gojenie i stan opatrzenia
## (opatrunek czysty/brudny, dezynfekcja, szwy, szyna). Ubrania z polem
## "protection" w items.json chronią zakryte segmenty przed cięciem,
## ugryzieniem i uderzeniem. Opatrywanie to przeciągnięcie przedmiotu na
## segment w oknie zdrowia (H); czynność trwa i ma pasek postępu.
## Czasy gojenia są przyspieszone (minuty zamiast dni), bo gra nie ma jeszcze
## zegara doby; zegar przyjdzie z buildem świata i wtedy przeskalujemy.

const ItemScript := preload("res://scripts/inventory/item.gd")

## id, nazwa w tłumaczeniu: SEG_<id>, waga w zdrowiu ogólnym
const SEGMENTS := {
	"glowa": 2.5, "szyja": 2.0, "klatka": 2.0, "brzuch": 1.6, "miednica": 1.2,
	"ramie_l": 0.8, "przedramie_l": 0.6, "dlon_l": 0.5,
	"ramie_p": 0.8, "przedramie_p": 0.6, "dlon_p": 0.5,
	"udo_l": 1.0, "lydka_l": 0.7, "stopa_l": 0.5,
	"udo_p": 1.0, "lydka_p": 0.7, "stopa_p": 0.5,
}
const LEGS := ["udo_l", "lydka_l", "stopa_l", "udo_p", "lydka_p", "stopa_p"]
const ARM_L := ["ramie_l", "przedramie_l", "dlon_l"]
const ARM_R := ["ramie_p", "przedramie_p", "dlon_p"]
const FRACTURABLE := ["ramie_l", "przedramie_l", "dlon_l", "ramie_p", "przedramie_p", "dlon_p",
		"udo_l", "lydka_l", "stopa_l", "udo_p", "lydka_p", "stopa_p", "klatka", "glowa"]

## rodzaj rany: obrażenia segmentu, krwawienie (% krwi na sekundę przy ciężkości 1),
## czas samoistnego krzepnięcia (s, 0 = nie krzepnie), ból, czas gojenia (s), typ ochrony
const WOUNDS := {
	"zadrapanie": {"dmg": 8.0, "bleed": 0.03, "clot": 45.0, "pain": 6.0, "heal": 240.0, "prot": "cut"},
	"rana_cieta": {"dmg": 18.0, "bleed": 0.12, "clot": 220.0, "pain": 18.0, "heal": 720.0, "prot": "cut"},
	"gleboka_rana": {"dmg": 32.0, "bleed": 0.32, "clot": 0.0, "pain": 35.0, "heal": 1800.0, "prot": "cut"},
	"ugryzienie": {"dmg": 28.0, "bleed": 0.18, "clot": 400.0, "pain": 30.0, "heal": 1500.0, "prot": "bite"},
	"stluczenie": {"dmg": 10.0, "bleed": 0.0, "clot": 0.0, "pain": 12.0, "heal": 300.0, "prot": "blunt"},
	"zlamanie": {"dmg": 40.0, "bleed": 0.0, "clot": 0.0, "pain": 45.0, "heal": 3600.0, "prot": "blunt"},
}

const BLOOD_REGEN := 0.015          # % krwi na sekundę bez krwawienia
const BLOOD_FAINT := 55.0           # poniżej: obraz ciemnieje, zdrowie spada
const BLOOD_DEATH := 38.0
const BANDAGE_FACTOR := 0.1         # opatrunek zatrzymuje 90% krwawienia
const STITCH_FACTOR := 0.15
const DIRT_BLEEDING := 0.006        # brudzenie opatrunku na sekundę, gdy rana krwawi
const DIRT_IDLE := 0.0008
const INFECT_RATE := 0.0025         # zakażenie na sekundę dla rany niezdezynfekowanej i brudnej
const DISINFECT_STING := 25.0       # ból po spirytusie, opada w 20 s
const PAINKILLER := 35.0            # ile bólu ucisza tabletka
const PAINKILLER_TIME := 240.0
const FALL_SAFE := 6.5              # m/s: od tej prędkości upadek boli
const FALL_FRACTURE := 9.5

## czynności opatrywania: czas w sekundach
const TREAT_TIME := {"bandage": 3.0, "plaster": 1.5, "disinfect": 2.0, "stitch": 6.0,
		"splint": 5.0, "pills": 1.5, "remove": 1.5, "eat": 3.5, "drink": 2.0}

var main
var segments := {}                  # id -> {"wounds": Array}
var blood := 100.0
var pain := 0.0
var dead := false
var action := {}                    # trwające opatrywanie
var knox := -1.0                    # zakażenie zombie: godziny gry od zakażenia (-1: zdrowy)
var knox_total := 48.0              # po tylu godzinach zakażenie zabija (piaskownica)
var rng := RandomNumberGenerator.new()

var _sting := 0.0
var _painkiller := 0.0
var _was_floor := true
var _fall_speed := 0.0
var _uid := 0

signal changed
signal died


func setup(main_node) -> void:
	main = main_node
	rng.randomize()
	reset()


func reset() -> void:
	segments.clear()
	for id in SEGMENTS:
		segments[id] = {"wounds": []}
	blood = 100.0
	pain = 0.0
	dead = false
	knox = -1.0
	action = {}
	_sting = 0.0
	_painkiller = 0.0
	changed.emit()


# --- stan ----------------------------------------------------------------------------

func segment_hp(id: String) -> float:
	var d := 0.0
	for w in segments[id]["wounds"]:
		d += float(WOUNDS[w["type"]]["dmg"]) * float(w["sev"]) * (1.0 - float(w["heal"]) * 0.85)
	return clampf(100.0 - d, 0.0, 100.0)


func overall() -> float:
	var loss := 0.0
	for id in SEGMENTS:
		loss += (100.0 - segment_hp(id)) * float(SEGMENTS[id]) * 0.12
	loss += maxf(0.0, 92.0 - blood) * 1.4
	loss += max_infection() * 40.0
	loss += knox_damage()
	if main != null and main.get("needs") != null:
		loss += main.needs.damage  # głód, pragnienie, wychłodzenie, zatrucie
	return clampf(100.0 - loss, 0.0, 100.0)


func bleed_rate() -> float:
	var r := 0.0
	for id in segments:
		for w in segments[id]["wounds"]:
			r += wound_bleed(w)
	return r


func wound_bleed(w: Dictionary) -> float:
	var base: float = float(WOUNDS[w["type"]]["bleed"]) * float(w["sev"])
	if base <= 0.0:
		return 0.0
	var clot: float = WOUNDS[w["type"]]["clot"]
	if clot > 0.0:
		base *= clampf(1.0 - float(w["age"]) / clot, 0.0, 1.0)
	if w["stitched"]:
		base *= STITCH_FACTOR
	if w["bandage"] != "":
		base *= BANDAGE_FACTOR * (1.0 + float(w["dirt"]) * 2.0)
	return base * (1.0 - float(w["heal"]))


func max_infection() -> float:
	var m := 0.0
	for id in segments:
		for w in segments[id]["wounds"]:
			m = maxf(m, float(w["infection"]))
	return m


## Zakażenie zombie: objawy dopiero po czasie (mdłości, gorączka), na końcu śmierć.
func infect_knox() -> void:
	if knox < 0.0:
		knox = 0.0
		if main != null and main.get("zombies") != null:
			knox_total = float(main.zombies.settings.get("knox_hours", 48.0))


## 0 brak objawów, 1 mdłości, 2 gorączka, 3 agonia.
func knox_stage() -> int:
	if knox < 0.0:
		return 0
	var r := knox / knox_total
	if r < 0.35:
		return 0
	if r < 0.6:
		return 1
	if r < 0.85:
		return 2
	return 3


func knox_damage() -> float:
	if knox < 0.0:
		return 0.0
	var r := knox / knox_total
	return clampf((r - 0.5) / 0.5, 0.0, 1.0) * 110.0


func has_wound(id: String, type: String) -> bool:
	for w in segments[id]["wounds"]:
		if w["type"] == type:
			return true
	return false


func wound_count() -> int:
	var n := 0
	for id in segments:
		n += segments[id]["wounds"].size()
	return n


## Mnożnik prędkości od nóg (złamanie, głęboka rana, ból).
func leg_factor() -> float:
	var f := 1.0
	for id in LEGS:
		for w in segments[id]["wounds"]:
			match w["type"]:
				"zlamanie":
					f = minf(f, 0.8 if w["splint"] else 0.5)
				"gleboka_rana", "ugryzienie":
					f = minf(f, 0.85)
	if pain > 60.0:
		f = minf(f, 0.85)
	return f


## Sprawność ręki (0,3–1): cios, dźwignia i szybkość pracy.
func arm_factor(side: String) -> float:
	var ids: Array = ARM_R if side == "r" else ARM_L
	var f := 1.0
	for id in ids:
		f -= (100.0 - segment_hp(id)) / 100.0 * 0.4
		for w in segments[id]["wounds"]:
			if w["type"] == "zlamanie":
				f -= 0.2 if w["splint"] else 0.45
	return clampf(f, 0.3, 1.0)


func can_sprint() -> bool:
	for id in LEGS:
		if has_wound(id, "zlamanie"):
			return false
	return blood > BLOOD_FAINT


# --- rany ----------------------------------------------------------------------------

## Ochrona z założonych ubrań dla segmentu i typu ("cut", "bite", "blunt").
func protection(id: String, kind: String) -> float:
	var through := 1.0
	for it in covering(id):
		var p: Dictionary = it.get_def().get("protection", {})
		through *= 1.0 - float(p.get(kind, 0.0)) * clampf(it.condition() * 1.2, 0.2, 1.0)
	return 1.0 - through


## Założone przedmioty zakrywające segment.
func covering(id: String) -> Array:
	var out: Array = []
	if main == null or main.inventory == null:
		return out
	for s in main.inventory.slots:
		var it = main.inventory.slots[s]
		var p: Dictionary = it.get_def().get("protection", {})
		if (p.get("segments", []) as Array).has(id) and not s in ["w_reku", "w_lewej", "oburacz"]:
			out.append(it)
	return out


## Zadaje ranę. Zwraca ranę albo pusty słownik, gdy ubranie ochroniło.
func wound(id: String, type: String, sev: float = 0.6, ignore_armor: bool = false) -> Dictionary:
	if dead or not segments.has(id) or not WOUNDS.has(type):
		return {}
	var kind: String = WOUNDS[type]["prot"]
	if not ignore_armor:
		var prot := protection(id, kind)
		for it in covering(id):
			it.props["condition"] = maxf(0.0, it.condition() - 0.02 * sev)  # ubranie się niszczy
		if kind == "blunt":
			sev *= 1.0 - prot * 0.6
		elif rng.randf() < prot:
			return {}  # przecięcie / ugryzienie zatrzymane przez materiał
	if type == "zlamanie" and has_wound(id, "zlamanie"):
		return {}
	_uid += 1
	var w := {"id": _uid, "type": type, "sev": clampf(sev, 0.1, 1.0), "age": 0.0, "heal": 0.0,
			"bandage": "", "dirt": 0.0, "disinfected": false, "stitched": false, "splint": false,
			"infection": 0.0}
	segments[id]["wounds"].append(w)
	changed.emit()
	return w


## Upadek: od 6,5 m/s stłuczenia stóp i łydek, od 9,5 m/s możliwe złamanie.
func on_fall(speed: float) -> void:
	if speed < FALL_SAFE:
		return
	var sev := clampf((speed - FALL_SAFE) / 6.0, 0.15, 1.0)
	for id in ["stopa_l", "stopa_p", "lydka_l", "lydka_p"]:
		if rng.randf() < 0.5 + sev * 0.4:
			wound(id, "stluczenie", sev)
	if speed >= FALL_FRACTURE:
		var chance := clampf((speed - FALL_FRACTURE) / 4.0 + 0.35, 0.0, 0.95)
		for id in ["lydka_l", "lydka_p"]:
			if rng.randf() < chance:
				wound(id, "zlamanie", 0.8, true)
	main.hud.show_message(tr("MSG_FALL_HURT"))


func random_wound() -> void:
	var ids := SEGMENTS.keys()
	var types := ["zadrapanie", "rana_cieta", "gleboka_rana", "stluczenie", "zlamanie", "ugryzienie"]
	var t: String = types[rng.randi() % types.size()]
	var id: String = ids[rng.randi() % ids.size()]
	if t == "zlamanie" and not FRACTURABLE.has(id):
		id = "lydka_l"
	wound(id, t, rng.randf_range(0.4, 0.9), true)


func heal_all() -> void:
	reset()


# --- upływ czasu ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if main == null or main.player == null or dead:
		return
	_fall_check()
	var bleeding := 0.0
	var wound_pain := 0.0
	for id in segments:
		var list: Array = segments[id]["wounds"]
		for w in list.duplicate():
			w["age"] = float(w["age"]) + delta
			var b := wound_bleed(w)
			bleeding += b
			if w["bandage"] != "":
				w["dirt"] = minf(1.0, float(w["dirt"]) + (DIRT_BLEEDING if b > 0.005 else DIRT_IDLE) * delta)
			_infect(w, delta)
			_heal(w, delta)
			var info: Dictionary = WOUNDS[w["type"]]
			wound_pain += float(info["pain"]) * float(w["sev"]) * (1.0 - float(w["heal"]) * 0.8)
			if w["type"] == "zlamanie" and not w["splint"]:
				wound_pain += 10.0
			if float(w["heal"]) >= 1.0:
				list.erase(w)
				changed.emit()
		if bleeding > 0.0:
			_stain_clothes(id, delta)
	blood = clampf(blood - bleeding * delta + (BLOOD_REGEN * delta if bleeding < 0.001 else 0.0), 0.0, 100.0)
	_sting = maxf(0.0, _sting - DISINFECT_STING / 20.0 * delta)
	_painkiller = maxf(0.0, _painkiller - delta)
	var calm := PAINKILLER * clampf(_painkiller / 60.0, 0.0, 1.0)
	pain = clampf(wound_pain + _sting + max_infection() * 30.0 - calm, 0.0, 100.0)
	if knox >= 0.0 and main.get("clock") != null:
		knox += main.clock.game_hours(delta)
		pain = clampf(pain + knox_stage() * 8.0, 0.0, 100.0)
	_update_action(delta)
	_apply_effects()
	if blood <= BLOOD_DEATH or overall() <= 0.0 or segment_hp("glowa") <= 0.0:
		_die()


func _infect(w: Dictionary, delta: float) -> void:
	if WOUNDS[w["type"]]["prot"] == "blunt" or float(w["heal"]) > 0.9:
		return
	var dirty: bool = w["bandage"] == "" or float(w["dirt"]) > 0.5 or w["bandage"] == "szmata"
	if w["disinfected"] and not (w["bandage"] != "" and float(w["dirt"]) > 0.7):
		w["infection"] = maxf(0.0, float(w["infection"]) - INFECT_RATE * 0.5 * delta)
	elif dirty:
		var rate := INFECT_RATE * (1.6 if w["type"] == "ugryzienie" else 1.0)
		w["infection"] = minf(1.0, float(w["infection"]) + rate * delta * float(w["sev"]))


func _heal(w: Dictionary, delta: float) -> void:
	var info: Dictionary = WOUNDS[w["type"]]
	var mult := 1.0
	if w["bandage"] != "" and float(w["dirt"]) < 0.5:
		mult *= 1.3
	if w["type"] == "gleboka_rana":
		mult *= 2.0 if w["stitched"] else 0.25  # niezszyta głęboka rana prawie się nie goi
	if w["type"] == "zlamanie":
		mult *= 1.0 if w["splint"] else 0.3
	if float(w["infection"]) > 0.3:
		mult *= 0.0
	if wound_bleed(w) > 0.05:
		mult *= 0.3
	w["heal"] = minf(1.0, float(w["heal"]) + delta / float(info["heal"]) * mult)


func _stain_clothes(id: String, delta: float) -> void:
	for it in covering(id):
		it.props["blood"] = minf(1.0, float(it.props.get("blood", 0.0)) + 0.01 * delta)


func _fall_check() -> void:
	var pl = main.player
	var on_floor: bool = pl.is_on_floor()
	if on_floor and not _was_floor:
		on_fall(_fall_speed)
	if not on_floor:
		_fall_speed = maxf(0.0, -pl.velocity.y)
	_was_floor = on_floor


func _apply_effects() -> void:
	var pl = main.player
	pl.injury_speed = leg_factor()
	pl.injury_sprint = can_sprint()
	pl.pain_regen = clampf(1.0 - pain / 150.0, 0.35, 1.0)
	var dim := clampf((95.0 - blood) / (95.0 - BLOOD_DEATH), 0.0, 1.0)
	main.set_hurt_effect(dim, pain / 100.0)


func _die() -> void:
	if dead:
		return
	dead = true
	action = {}
	main.hud.show_message(tr("MSG_DEAD_KNOX" if knox_stage() >= 3 else "MSG_DEAD"))
	died.emit()


# --- opatrywanie ---------------------------------------------------------------------

## Co dany przedmiot robi na segmencie: {"kind", "wound"} albo {"error"}.
func treatment_for(item, id: String) -> Dictionary:
	if item == null:
		return {"error": "HP_ERR_NOTHING"}
	var use := str(item.get_def().get("medical", ""))
	# jedzenie i picie: przeciągnięte na postać
	var food: Dictionary = item.get_def().get("food", {})
	if not food.is_empty():
		if bool(food.get("sealed", false)):
			return {"error": "HP_ERR_SEALED"}
		return {"kind": "eat", "wound": {}}
	if not item.liquid.is_empty():
		if str(item.liquid.get("type", "")) == "woda" and float(item.liquid.get("amount", 0.0)) > 0.001:
			return {"kind": "drink", "wound": {}}
		return {"error": "HP_ERR_EMPTY"}
	if item.get_def().has("liquid_capacity"):
		return {"error": "HP_ERR_EMPTY"}
	if use == "":
		return {"error": "HP_ERR_NOT_MEDICAL"}
	var list: Array = segments[id]["wounds"]
	match use:
		"bandage", "plaster":
			for w in list:
				if w["bandage"] == "" and WOUNDS[w["type"]]["prot"] != "blunt":
					if use == "plaster" and w["type"] != "zadrapanie":
						continue
					return {"kind": use, "wound": w}
			return {"error": "HP_ERR_NO_OPEN_WOUND"}
		"disinfect":
			for w in list:
				if not w["disinfected"] and WOUNDS[w["type"]]["prot"] != "blunt":
					return {"kind": "disinfect", "wound": w}
			return {"error": "HP_ERR_NOTHING_TO_CLEAN"}
		"stitch":
			for w in list:
				if w["type"] == "gleboka_rana" and not w["stitched"]:
					return {"kind": "stitch", "wound": w}
			return {"error": "HP_ERR_NO_DEEP"}
		"splint":
			for w in list:
				if w["type"] == "zlamanie" and not w["splint"]:
					return {"kind": "splint", "wound": w}
			return {"error": "HP_ERR_NO_FRACTURE"}
		"pills":
			return {"kind": "pills", "wound": {}}
	return {"error": "HP_ERR_NOT_MEDICAL"}


## Rozpoczyna opatrywanie: przeciągnięty przedmiot na segment.
func treat(item, id: String) -> bool:
	if dead:
		return false
	if not action.is_empty():
		main.hud.show_message(tr("HP_ERR_BUSY"))
		return false
	var t := treatment_for(item, id)
	if t.has("error"):
		main.hud.show_message(tr(t["error"]))
		return false
	var dur: float = TREAT_TIME[t["kind"]]
	# ranną ręką opatruje się wolniej
	dur /= maxf(0.5, (arm_factor("l") + arm_factor("r")) / 2.0)
	action = {"kind": t["kind"], "seg": id, "item": item, "wound": t["wound"], "t": 0.0, "dur": dur}
	main.sound.play_ui("pickup")
	return true


## Zdjęcie opatrunku albo szyny z segmentu (prawy przycisk w oknie zdrowia).
func remove_dressing(id: String) -> bool:
	if not action.is_empty() or dead:
		return false
	for w in segments[id]["wounds"]:
		if w["bandage"] != "" or w["splint"]:
			action = {"kind": "remove", "seg": id, "item": null, "wound": w, "t": 0.0, "dur": TREAT_TIME["remove"]}
			return true
	main.hud.show_message(tr("HP_ERR_NO_DRESSING"))
	return false


func action_ratio() -> float:
	if action.is_empty():
		return -1.0
	return clampf(float(action["t"]) / float(action["dur"]), 0.0, 1.0)


func _update_action(delta: float) -> void:
	if action.is_empty():
		return
	var it = action["item"]
	if it != null and main.inventory.find_uid(it.uid) == null:
		action = {}  # przedmiot zniknął z ekwipunku
		return
	action["t"] = float(action["t"]) + delta
	if float(action["t"]) >= float(action["dur"]):
		var a := action
		action = {}
		_finish(a)


func _finish(a: Dictionary) -> void:
	var w: Dictionary = a["wound"]
	var it = a["item"]
	var still := w.is_empty() or _wound_exists(w)
	if not still:
		return
	match a["kind"]:
		"bandage", "plaster":
			w["bandage"] = it.def_id
			# brudny opatrunek albo szmata od razu niosą brud
			w["dirt"] = float(it.get_def().get("dirt", 0.0))
			_consume(it)
		"disinfect":
			w["disinfected"] = true
			w["infection"] = maxf(0.0, float(w["infection"]) - 0.15)
			_sting = DISINFECT_STING
			if w["bandage"] != "":
				w["dirt"] = maxf(0.0, float(w["dirt"]) - 0.3)
			_use_dose(it)
		"stitch":
			w["stitched"] = true
			_sting = DISINFECT_STING * 0.8
			_use_dose(it)
		"splint":
			w["splint"] = true
			_consume(it)
		"pills":
			_painkiller = PAINKILLER_TIME
			_use_dose(it)
		"eat":
			main.needs.eat(it)
		"drink":
			main.needs.drink(it)
		"remove":
			if w["bandage"] != "":
				var used: String = w["bandage"]
				w["bandage"] = ""
				w["dirt"] = 0.0
				if used == "bandaz":
					main.inventory.give(ItemScript.new("bandaz_brudny", 1))
				elif used == "bandaz_brudny" or used == "szmata":
					main.inventory.give(ItemScript.new(used, 1))
			elif w["splint"]:
				w["splint"] = false
				main.inventory.give(ItemScript.new("szyna", 1))
	main.sound.play_ui("inv")
	changed.emit()


func _wound_exists(w: Dictionary) -> bool:
	for id in segments:
		if segments[id]["wounds"].has(w):
			return true
	return false


func _consume(it) -> void:
	it.count -= 1
	if it.count <= 0:
		main.inventory.remove_item(it)
	main.inventory.changed.emit()


func _use_dose(it) -> void:
	var doses := int(it.props.get("doses", int(it.get_def().get("doses", 1))))
	doses -= 1
	if doses <= 0:
		_consume(it)
	else:
		it.props["doses"] = doses
		main.inventory.changed.emit()


# --- zapis ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var segs := {}
	for id in segments:
		segs[id] = segments[id]["wounds"].duplicate(true)
	return {"blood": blood, "segments": segs, "painkiller": _painkiller, "knox": knox}


func from_dict(d: Dictionary) -> void:
	reset()
	blood = float(d.get("blood", 100.0))
	_painkiller = float(d.get("painkiller", 0.0))
	knox = float(d.get("knox", -1.0))
	var segs: Dictionary = d.get("segments", {})
	for id in segs:
		if segments.has(id):
			for w in segs[id]:
				var ww: Dictionary = w
				ww["id"] = int(ww.get("id", 0))
				segments[id]["wounds"].append(ww)
				_uid = maxi(_uid, int(ww["id"]))
	changed.emit()
