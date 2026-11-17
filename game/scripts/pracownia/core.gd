extends RefCounted
## Pracownia: rdzeń. Moduły z parametrami, profil rysowany punktami, modyfikatory
## (lustro, powtórzenie), hierarchia (moduł przypięty do innego), krzywizna do zużycia,
## zapis i odczyt plików, kotwice i wartości wyliczane dla gry.
##
## Plik projektu: data/warsztat/<id>.json
##   {"version": 2, "id", "pl", "en", "kind": "gun" | "item", "template": "semi"|"pump"|"break"|"item",
##    "replace": "" (id istniejącego przedmiotu, któremu podmieniamy tylko model),
##    "modules": [moduł], "anchors": {"wylot": [x,y,z], "lewa": [...], "zawias": [...], ...},
##    "anim": {krok: {"time": s, "tracks": {ścieżka: [[t, wartość], ...]}}}, "item": {pola przedmiotu}}
## Moduł: {"uid", "type", "name", "params", "pos", "rot": [x,y,z] stopnie, "scale": [x,y,z],
##   "mat", "wear": {...}, "part", "parent": uid, "mod": {"lustro", "powtorz", "krok"},
##   "profile": [[x, y], ...], "hidden": bool}
## Układ: X do przodu, Y w górę, Z w prawo, początek = chwyt prawej dłoni.

const Mats := preload("res://scripts/pracownia/materials.gd")
const DIR := "res://data/warsztat"
const OLD_DIR := "res://data/bronie"

const PARTS := ["", "zamek", "magazynek", "lufy", "czolenko", "kurek", "beben"]
const PART_LABELS := {"": "stała część", "zamek": "zamek (odskakuje)", "magazynek": "magazynek (wypada)",
		"lufy": "lufy (łamane)", "czolenko": "czółenko (pompka)", "kurek": "kurek (obraca się)", "beben": "bęben (obraca się)"}
const ANCHORS := {"wylot": "Wylot lufy", "lewa": "Lewa dłoń", "gniazdo": "Gniazdo magazynka",
		"wyrzutnik": "Wyrzutnik łusek", "zawias": "Zawias luf", "os_bebna": "Oś bębna", "os_kurka": "Oś kurka"}
const CATEGORIES := ["Broń", "Narzędzia", "Ogólne"]

## Moduły: kategoria, etykieta, materiał, parametry {klucz: [min, max, domyślna, etykieta, jednostka]}
## jednostki: m (pokazywane w mm), deg, n (całkowita), x (współczynnik)
const MODULES := {
	"kolba": {"cat": "Broń", "label": "Kolba", "mat": "drewno", "params": {
		"dlugosc": [0.18, 0.5, 0.36, "Długość", "m"], "stopka": [0.06, 0.16, 0.124, "Wysokość stopki", "m"],
		"szyjka": [0.026, 0.06, 0.04, "Grubość szyjki", "m"], "opad": [-0.02, 0.1, 0.03, "Opad", "m"],
		"szerokosc": [0.026, 0.055, 0.041, "Szerokość", "m"], "garb": [0.0, 0.04, 0.0, "Chwyt pistoletowy", "m"],
		"grzbiet": [0.0, 0.03, 0.0, "Podpórka policzka", "m"], "gumowa": [0.0, 1.0, 1.0, "Stopka gumowa", "n"]}},
	"komora": {"cat": "Broń", "label": "Komora zamkowa", "mat": "stal", "params": {
		"dlugosc": [0.02, 0.4, 0.075, "Długość", "m"], "wysokosc": [0.012, 0.1, 0.056, "Wysokość", "m"],
		"szerokosc": [0.012, 0.07, 0.042, "Szerokość", "m"], "zaokraglenie": [2.2, 14.0, 7.0, "Kanciastość", "x"],
		"fazka": [0.0, 0.01, 0.004, "Fazka końców", "m"], "zwezenie": [0.5, 1.2, 1.0, "Zwężenie przodu", "x"]}},
	"lufy": {"cat": "Broń", "label": "Lufa / lufy", "mat": "stal", "params": {
		"dlugosc": [0.05, 0.9, 0.64, "Długość", "m"], "srednica": [0.01, 0.036, 0.0236, "Średnica", "m"],
		"liczba": [1.0, 2.0, 1.0, "Liczba luf", "n"], "uklad": [0.0, 1.0, 0.0, "Układ: 0 pion, 1 poziom", "n"],
		"zwezenie": [0.7, 1.0, 0.92, "Zwężenie u wylotu", "x"], "szyna": [0.0, 1.0, 1.0, "Szyna celownicza", "n"],
		"wentylacja": [0.0, 20.0, 0.0, "Mostki szyny", "n"]}},
	"czolenko": {"cat": "Broń", "label": "Czółenko / łoże", "mat": "drewno", "params": {
		"dlugosc": [0.05, 0.5, 0.25, "Długość", "m"], "wysokosc": [0.012, 0.06, 0.026, "Wysokość", "m"],
		"szerokosc": [0.022, 0.07, 0.044, "Szerokość", "m"], "rowki": [0.0, 10.0, 0.0, "Rowki", "n"],
		"wybrzuszenie": [0.0, 0.5, 0.1, "Wybrzuszenie", "x"]}},
	"chwyt": {"cat": "Broń", "label": "Chwyt pistoletowy", "mat": "bakelit", "params": {
		"wysokosc": [0.04, 0.14, 0.1, "Wysokość", "m"], "glebokosc": [0.02, 0.055, 0.034, "Głębokość", "m"],
		"szerokosc": [0.014, 0.04, 0.027, "Szerokość", "m"], "kat": [-10.0, 35.0, 10.0, "Pochylenie", "deg"],
		"brzuch": [0.0, 0.25, 0.08, "Wybrzuszenie", "x"]}},
	"zamek": {"cat": "Broń", "label": "Zamek pistoletu", "mat": "stal", "params": {
		"dlugosc": [0.06, 0.26, 0.165, "Długość", "m"], "wysokosc": [0.014, 0.045, 0.028, "Wysokość", "m"],
		"szerokosc": [0.014, 0.034, 0.024, "Szerokość", "m"], "rowki": [0.0, 16.0, 8.0, "Rowki z tyłu", "n"],
		"okno": [0.0, 1.0, 1.0, "Okno wyrzutnika", "n"]}},
	"magazynek": {"cat": "Broń", "label": "Magazynek", "mat": "stal_jasna", "params": {
		"dlugosc": [0.03, 0.32, 0.1, "Długość", "m"], "glebokosc": [0.012, 0.07, 0.028, "Głębokość", "m"],
		"szerokosc": [0.01, 0.036, 0.017, "Szerokość", "m"], "kat": [-35.0, 35.0, 10.0, "Pochylenie", "deg"],
		"wygiecie": [0.0, 0.08, 0.0, "Wygięcie", "m"], "stopka": [0.0, 1.0, 1.0, "Stopka", "n"]}},
	"kablak": {"cat": "Broń", "label": "Kabłąk i spust", "mat": "stal", "params": {
		"dlugosc": [0.02, 0.09, 0.048, "Długość", "m"], "glebokosc": [0.01, 0.04, 0.022, "Głębokość", "m"],
		"spusty": [0.0, 2.0, 1.0, "Liczba spustów", "n"], "grubosc": [0.002, 0.008, 0.0035, "Grubość", "m"]}},
	"muszka": {"cat": "Broń", "label": "Muszka", "mat": "stal", "params": {
		"wysokosc": [0.002, 0.03, 0.006, "Wysokość", "m"], "szerokosc": [0.0015, 0.01, 0.0032, "Szerokość", "m"],
		"oslona": [0.0, 1.0, 0.0, "Osłona (kaptur)", "n"]}},
	"szczerbinka": {"cat": "Broń", "label": "Szczerbinka", "mat": "stal", "params": {
		"wysokosc": [0.002, 0.025, 0.007, "Wysokość", "m"], "szerokosc": [0.006, 0.035, 0.017, "Szerokość", "m"],
		"szczelina": [0.0015, 0.01, 0.004, "Szczelina", "m"], "dioptra": [0.0, 1.0, 0.0, "Przeziernik", "n"]}},
	"rura": {"cat": "Broń", "label": "Rura magazynka", "mat": "stal_jasna", "params": {
		"dlugosc": [0.05, 0.8, 0.45, "Długość", "m"], "srednica": [0.01, 0.034, 0.021, "Średnica", "m"]}},
	"kurek": {"cat": "Broń", "label": "Kurek", "mat": "stal_jasna", "params": {
		"rozmiar": [0.005, 0.025, 0.012, "Rozmiar", "m"], "pierscien": [0.0, 1.0, 0.0, "Z pierścieniem", "n"]}},
	"beben": {"cat": "Broń", "label": "Bęben rewolweru", "mat": "stal", "params": {
		"dlugosc": [0.02, 0.06, 0.038, "Długość", "m"], "srednica": [0.025, 0.05, 0.038, "Średnica", "m"],
		"komory": [5.0, 8.0, 7.0, "Komory", "n"], "zlobki": [0.0, 1.0, 1.0, "Żłobki", "n"]}},
	"luneta": {"cat": "Broń", "label": "Luneta", "mat": "stal", "params": {
		"dlugosc": [0.1, 0.4, 0.28, "Długość", "m"], "srednica": [0.018, 0.035, 0.026, "Średnica tubusu", "m"],
		"obiektyw": [0.025, 0.06, 0.042, "Średnica obiektywu", "m"], "montaz": [0.0, 1.0, 1.0, "Pierścienie montażu", "n"]}},
	"tlumik": {"cat": "Broń", "label": "Tłumik", "mat": "parkeryzowana", "params": {
		"dlugosc": [0.06, 0.25, 0.15, "Długość", "m"], "srednica": [0.02, 0.05, 0.032, "Średnica", "m"]}},
	"trzonek": {"cat": "Narzędzia", "label": "Trzonek", "mat": "drewno_jasne", "params": {
		"dlugosc": [0.1, 0.9, 0.38, "Długość", "m"], "srednica": [0.015, 0.05, 0.03, "Grubość", "m"],
		"splaszczenie": [0.5, 1.0, 0.75, "Spłaszczenie", "x"], "zwezenie": [0.6, 1.3, 0.85, "Zwężenie do głowicy", "x"],
		"galka": [0.0, 0.02, 0.008, "Zgrubienie na końcu", "m"], "wygiecie": [-0.06, 0.06, 0.015, "Wygięcie", "m"]}},
	"pret_zgiety": {"cat": "Narzędzia", "label": "Pręt zgięty (łom)", "mat": "farba_zielona", "params": {
		"dlugosc1": [0.05, 0.9, 0.5, "Długość prosta", "m"], "kat": [0.0, 180.0, 40.0, "Kąt zgięcia", "deg"],
		"promien": [0.01, 0.1, 0.03, "Promień zgięcia", "m"], "dlugosc2": [0.0, 0.3, 0.06, "Długość za zgięciem", "m"],
		"srednica": [0.008, 0.04, 0.02, "Grubość", "m"], "kanty": [2.0, 10.0, 3.5, "Kanciastość (sześciokąt)", "x"],
		"plaski_koniec": [0.0, 1.0, 1.0, "Spłaszczony koniec", "n"]}},
	"pierscien": {"cat": "Ogólne", "label": "Pierścień / opaska", "mat": "stal_jasna", "params": {
		"promien": [0.005, 0.08, 0.016, "Promień", "m"], "grubosc": [0.001, 0.02, 0.003, "Grubość", "m"],
		"szerokosc": [0.001, 0.05, 0.006, "Szerokość", "m"]}},
	"walec": {"cat": "Ogólne", "label": "Walec", "mat": "stal", "params": {
		"dlugosc": [0.002, 0.8, 0.05, "Długość", "m"], "srednica": [0.002, 0.15, 0.02, "Średnica", "m"],
		"srednica2": [0.0, 0.15, 0.0, "Średnica końca (0 = ta sama)", "m"], "boki": [3.0, 24.0, 14.0, "Liczba ścian", "n"]}},
	"kula": {"cat": "Ogólne", "label": "Kula / gałka", "mat": "stal_jasna", "params": {
		"srednica": [0.004, 0.12, 0.02, "Średnica", "m"], "splaszczenie": [0.2, 1.5, 1.0, "Spłaszczenie", "x"]}},
	"plytka": {"cat": "Ogólne", "label": "Pudełko / płytka", "mat": "stal", "params": {
		"dlugosc": [0.002, 0.5, 0.03, "Długość", "m"], "wysokosc": [0.001, 0.2, 0.008, "Wysokość", "m"],
		"szerokosc": [0.001, 0.1, 0.012, "Szerokość", "m"], "zaokraglenie": [2.0, 14.0, 6.0, "Kanciastość", "x"],
		"fazka": [0.0, 0.01, 0.0015, "Fazka końców", "m"], "zwezenie": [0.2, 1.5, 1.0, "Zwężenie końca", "x"]}},
	"profil": {"cat": "Ogólne", "label": "Profil (rysowany)", "mat": "stal", "params": {
		"grubosc": [0.001, 0.08, 0.012, "Grubość", "m"], "fazka": [0.0, 0.01, 0.0015, "Fazka krawędzi", "m"],
		"wygladzenie": [0.0, 3.0, 0.0, "Wygładzenie konturu", "n"], "klin": [0.05, 1.0, 1.0, "Klin (ostrze)", "x"],
		"klin_od": [0.0, 1.0, 0.5, "Klin od (część długości)", "x"]}},
}

## Gotowe kształty profilu (do szybkiego startu rysowania).
const PROFILE_PRESETS := {
	"prostokat": [[-0.03, -0.01], [0.03, -0.01], [0.03, 0.01], [-0.03, 0.01]],
	"ostrze_siekiery": [[-0.02, -0.02], [0.03, -0.03], [0.085, -0.06], [0.095, -0.02], [0.095, 0.03], [0.085, 0.06], [0.03, 0.025], [-0.02, 0.018]],
	"ostrze_noza": [[0.0, -0.012], [0.11, -0.006], [0.135, 0.004], [0.1, 0.012], [0.0, 0.012]],
	"kolba_wojskowa": [[0.0, -0.03], [-0.12, -0.05], [-0.34, -0.09], [-0.36, -0.09], [-0.36, 0.03], [-0.15, 0.025], [0.0, 0.02]],
	"chwyt_rewolweru": [[0.0, 0.0], [0.02, 0.0], [0.012, -0.06], [-0.005, -0.09], [-0.03, -0.085], [-0.025, -0.02]],
	"glowica_mlotka": [[-0.03, -0.012], [0.035, -0.012], [0.04, -0.008], [0.04, 0.008], [0.035, 0.012], [-0.03, 0.012], [-0.045, 0.004], [-0.045, -0.004]],
}

static var _cache := {}
static var _data := {}
static var _uid_counter := 0


# --- dane i pliki -----------------------------------------------------------------

static func new_uid() -> String:
	_uid_counter += 1
	return "m%d_%d" % [Time.get_ticks_usec() % 1000000, _uid_counter]


static func default_module(type: String) -> Dictionary:
	var spec: Dictionary = MODULES.get(type, {})
	var params := {}
	for k in spec.get("params", {}):
		params[k] = float(spec["params"][k][2])
	var m := {"uid": new_uid(), "type": type, "name": str(spec.get("label", type)), "params": params,
			"pos": [0.0, 0.0, 0.0], "rot": [0.0, 0.0, 0.0], "scale": [1.0, 1.0, 1.0],
			"mat": str(spec.get("mat", "stal")), "wear": {}, "part": "", "parent": "",
			"mod": {"lustro": 0, "powtorz": 1, "krok": [0.01, 0.0, 0.0]}}
	if type == "profil":
		m["profile"] = (PROFILE_PRESETS["prostokat"] as Array).duplicate(true)
	return m


## Stary format (data/bronie, etap 1) -> nowy: rot liczba -> wektor, brakujące pola.
static func upgrade(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	out["version"] = 2
	if not out.has("kind"):
		out["kind"] = "gun" if (out.get("item", {}) as Dictionary).has("gun") else "item"
	if not out.has("template"):
		var action := str(out.get("item", {}).get("gun", {}).get("action", ""))
		out["template"] = {"semi": "semi", "pump": "pump", "break": "break"}.get(action, "item")
	if not out.has("anchors"):
		out["anchors"] = {}
	var anchors: Dictionary = out["anchors"]
	if anchors.has("hinge") and not anchors.has("zawias"):
		var h: Array = anchors["hinge"]
		anchors["zawias"] = [float(h[0]), float(h[1]), 0.0]
		anchors.erase("hinge")
	for m in out.get("modules", []):
		if typeof(m.get("rot", 0)) != TYPE_ARRAY:
			m["rot"] = [0.0, 0.0, float(m.get("rot", 0.0))]
		for k in ["scale", "wear", "mod", "parent", "uid", "name"]:
			if not m.has(k):
				m[k] = {"scale": [1.0, 1.0, 1.0], "wear": {}, "mod": {"lustro": 0, "powtorz": 1, "krok": [0.01, 0.0, 0.0]},
						"parent": "", "uid": new_uid(), "name": str(MODULES.get(str(m.get("type", "")), {}).get("label", ""))}[k]
		var p: Array = m.get("pos", [0, 0, 0])
		while p.size() < 3:
			p.append(0.0)
		m["pos"] = p
	return out


static func list_files() -> Array:
	var out: Array = []
	for d in [DIR, OLD_DIR]:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".json") and not out.has(f.trim_suffix(".json")):
				out.append(f.trim_suffix(".json"))
	out.sort()
	return out


static func load_project(id: String) -> Dictionary:
	if _data.has(id):
		return _data[id]
	for d in [DIR, OLD_DIR]:
		var path := "%s/%s.json" % [d, id]
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(parsed) == TYPE_DICTIONARY:
				var up := upgrade(parsed)
				_data[id] = up
				return up
	return {}


static func save_project(data: Dictionary, path: String = "") -> bool:
	if path == "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
		path = "%s/%s.json" % [DIR, str(data.get("id", "projekt"))]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	forget(str(data.get("id", "")))
	return true


static func forget(id: String) -> void:
	_cache.erase(id)
	_data.erase(id)


static func param(m: Dictionary, key: String) -> float:
	var spec: Dictionary = MODULES.get(str(m.get("type", "")), {}).get("params", {})
	var d: float = float(spec[key][2]) if spec.has(key) else 0.0
	return float(m.get("params", {}).get(key, d))


static func find_uid(data: Dictionary, uid: String) -> int:
	var mods: Array = data.get("modules", [])
	for i in mods.size():
		if str(mods[i].get("uid", "")) == uid:
			return i
	return -1


# --- geometria --------------------------------------------------------------------

static func _ring(c: Vector3, t: Vector3, h: float, w: float, p: float, sides: int) -> PackedVector3Array:
	var s := Vector3(0, 0, 1)
	if absf(t.z) > 0.95:
		s = Vector3(0, 1, 0)
	var up := s.cross(t).normalized()
	s = t.cross(up).normalized()
	var out := PackedVector3Array()
	for i in sides:
		var a := TAU * float(i) / float(sides) + PI / float(sides)
		var ca := cos(a)
		var sa := sin(a)
		var yy: float = signf(sa) * pow(absf(sa), 2.0 / p) * h * 0.5
		var zz: float = signf(ca) * pow(absf(ca), 2.0 / p) * w * 0.5
		out.append(c + up * yy + s * zz)
	return out


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Bryła z przekrojów: sections = [{c, h, w, p}] wzdłuż dowolnej ścieżki.
static func loft(st: SurfaceTool, sections: Array, sides: int = 14, caps: bool = true) -> void:
	if sections.size() < 2:
		return
	var rings: Array = []
	for i in sections.size():
		var sc: Dictionary = sections[i]
		var c: Vector3 = sc["c"]
		var nxt: Vector3 = sections[mini(i + 1, sections.size() - 1)]["c"]
		var prv: Vector3 = sections[maxi(i - 1, 0)]["c"]
		var t := (nxt - prv).normalized()
		if t.length() < 0.001:
			t = Vector3.RIGHT
		rings.append(_ring(c, t, maxf(0.0002, float(sc["h"])), maxf(0.0002, float(sc["w"])), float(sc.get("p", 2.6)), sides))
	st.set_smooth_group(0)
	for r in rings.size() - 1:
		var a: PackedVector3Array = rings[r]
		var b: PackedVector3Array = rings[r + 1]
		for i in sides:
			var j := (i + 1) % sides
			_tri(st, a[i], b[i], b[j])
			_tri(st, a[i], b[j], a[j])
	if caps:
		st.set_smooth_group(0xFFFFFFFF)
		for which in [0, rings.size() - 1]:
			var ring: PackedVector3Array = rings[which]
			var center := Vector3.ZERO
			for v in ring:
				center += v
			center /= float(ring.size())
			for i in sides:
				var j := (i + 1) % sides
				if which == 0:
					_tri(st, center, ring[i], ring[j])
				else:
					_tri(st, center, ring[j], ring[i])


## Pręt od a do b o przekroju h x w (p: kanciastość), z fazowanymi końcami i zwężeniem.
static func bar(st: SurfaceTool, a: Vector3, b: Vector3, h: float, w: float, p: float, bevel: float = 0.0, sides: int = 14, h2: float = -1.0, w2: float = -1.0) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 0.00005:
		return
	var t := d / ln
	if h2 < 0.0:
		h2 = h
	if w2 < 0.0:
		w2 = w
	var bv := minf(bevel, ln * 0.3)
	var secs: Array = []
	if bv > 0.0:
		secs.append({"c": a, "h": maxf(0.0005, h - bv * 2.0), "w": maxf(0.0005, w - bv * 2.0), "p": p})
	secs.append({"c": a + t * bv, "h": h, "w": w, "p": p})
	secs.append({"c": b - t * bv, "h": h2, "w": w2, "p": p})
	if bv > 0.0:
		secs.append({"c": b, "h": maxf(0.0005, h2 - bv * 2.0), "w": maxf(0.0005, w2 - bv * 2.0), "p": p})
	loft(st, secs, sides)


## Profil boczny (punkty X-Y) wyciągnięty na grubość, z fazką i klinem (ostrze).
static func profile_mesh(st: SurfaceTool, pts_in: Array, thick: float, bevel: float, smooth: int, wedge: float, wedge_from: float) -> void:
	var pts := PackedVector2Array()
	for p in pts_in:
		pts.append(Vector2(float(p[0]), float(p[1])))
	if pts.size() < 3:
		return
	for k in smooth:
		pts = _chaikin(pts)
	if Geometry2D.is_polygon_clockwise(pts):
		pts.reverse()
	var minx := INF
	var maxx := -INF
	for p in pts:
		minx = minf(minx, p.x)
		maxx = maxf(maxx, p.x)
	var span := maxf(0.0001, maxx - minx)
	var zscale := func(x: float) -> float:
		var u := (x - minx) / span
		if u <= wedge_from:
			return 1.0
		return lerpf(1.0, wedge, (u - wedge_from) / maxf(0.0001, 1.0 - wedge_from))
	var bv := minf(bevel, thick * 0.45)
	var inner := _inset(pts, bv) if bv > 0.0 else pts
	var half := thick * 0.5
	# warstwy: czoło (wcięte), krawędź (pełny kontur) x2, czoło
	var layers: Array = [[inner, -half], [pts, -half + bv], [pts, half - bv], [inner, half]]
	if bv <= 0.0:
		layers = [[pts, -half], [pts, half]]
	var rings: Array = []
	for L in layers:
		var poly: PackedVector2Array = L[0]
		var z: float = L[1]
		var ring := PackedVector3Array()
		for p in poly:
			ring.append(Vector3(p.x, p.y, z * float(zscale.call(p.x))))
		rings.append(ring)
	var n := pts.size()
	st.set_smooth_group(0xFFFFFFFF)
	for r in rings.size() - 1:
		var a: PackedVector3Array = rings[r]
		var b: PackedVector3Array = rings[r + 1]
		for i in n:
			var j := (i + 1) % n
			_tri(st, a[i], a[j], b[j])
			_tri(st, a[i], b[j], b[i])
	var tri := Geometry2D.triangulate_polygon(inner)
	var front: PackedVector3Array = rings[rings.size() - 1]
	var back: PackedVector3Array = rings[0]
	for k in range(0, tri.size(), 3):
		_tri(st, front[tri[k]], front[tri[k + 1]], front[tri[k + 2]])
		_tri(st, back[tri[k]], back[tri[k + 2]], back[tri[k + 1]])


static func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	return out


static func _inset(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var res := Geometry2D.offset_polygon(pts, -d, Geometry2D.JOIN_MITER)
	if res.is_empty():
		return pts
	var poly: PackedVector2Array = res[0]
	if poly.size() != pts.size():
		# przesunięcie zmieniło liczbę punktów: przesuwamy każdy punkt wzdłuż dwusiecznej
		var out := PackedVector2Array()
		var n := pts.size()
		for i in n:
			var a := pts[(i - 1 + n) % n]
			var b := pts[i]
			var c := pts[(i + 1) % n]
			var n1 := Vector2(-(b - a).y, (b - a).x).normalized()
			var n2 := Vector2(-(c - b).y, (c - b).x).normalized()
			var bis := (n1 + n2).normalized()
			out.append(b + bis * d)
		return out
	return poly


# --- moduły -----------------------------------------------------------------------

## Części geometrii jednego modułu: [{"mat": "" (materiał modułu) albo nazwa, "build": Callable(st)}].
static func module_pieces(m: Dictionary) -> Array:
	var P := func(k: String) -> float: return param(m, k)
	var pieces: Array = []
	var main_build := Callable()
	match str(m.get("type", "")):
		"kolba":
			var L: float = P.call("dlugosc")
			var butt: float = P.call("stopka")
			var wrist: float = P.call("szyjka")
			var drop: float = P.call("opad")
			var wid: float = P.call("szerokosc")
			var bump: float = P.call("garb")
			var comb: float = P.call("grzbiet")
			var top_at := func(u: float) -> float: return 0.038 - (drop + 0.012) * u
			main_build = func(st):
				var secs: Array = []
				var n := 11
				for i in n:
					var u := float(i) / float(n - 1)
					var x := 0.012 - u * L
					var top: float = top_at.call(u) + comb * smoothstep(0.25, 0.5, u) * (1.0 - smoothstep(0.85, 1.0, u))
					var hh := lerpf(wrist, butt, pow(u, 1.25)) + comb * smoothstep(0.25, 0.5, u) * (1.0 - smoothstep(0.85, 1.0, u))
					hh += bump * exp(-pow((u - 0.12) / 0.08, 2.0))
					secs.append({"c": Vector3(x, top - hh * 0.5, 0), "h": hh, "w": lerpf(wid * 0.85, wid, u), "p": 2.8})
				loft(st, secs, 16)
			if P.call("gumowa") > 0.5:
				pieces.append({"mat": "guma", "build": func(st):
					var tb: float = top_at.call(1.0)
					bar(st, Vector3(0.012 - L - 0.001, tb - butt * 0.5, 0), Vector3(0.012 - L - 0.017, tb - butt * 0.5, 0), butt * 1.01, wid * 1.03, 3.2, 0.003, 16)})
		"komora":
			var L: float = P.call("dlugosc")
			var H: float = P.call("wysokosc")
			var W: float = P.call("szerokosc")
			var R: float = P.call("zaokraglenie")
			var tp: float = P.call("zwezenie")
			var fz: float = P.call("fazka")
			main_build = func(st): bar(st, Vector3.ZERO, Vector3(L, 0, 0), H, W, R, minf(fz, L * 0.2), 20, H * tp, W * tp)
		"lufy":
			var L: float = P.call("dlugosc")
			var D: float = P.call("srednica")
			var n := int(round(P.call("liczba")))
			var horiz: bool = P.call("uklad") > 0.5
			var tap: float = P.call("zwezenie")
			var rail: bool = P.call("szyna") > 0.5
			var vents := int(round(P.call("wentylacja")))
			var off_of := func(k: int) -> Vector3:
				var off := (float(k) - (n - 1) * 0.5) * D
				return Vector3(0, 0, off) if horiz else Vector3(0, -off, 0)
			main_build = func(st):
				for k in n:
					var o: Vector3 = off_of.call(k)
					bar(st, o, o + Vector3(L, 0, 0), D, D, 2.0, 0.0, 16, D * tap, D * tap)
				if n == 2:
					for zs in [-1.0, 1.0]:
						if horiz:
							bar(st, Vector3(0.01, zs * D * 0.33, 0), Vector3(L - 0.01, zs * D * 0.33, 0), 0.004, 0.006, 6.0)
						else:
							bar(st, Vector3(0.01, 0, zs * D * 0.36), Vector3(L - 0.01, 0, zs * D * 0.36), D * 0.3, 0.004, 6.0)
				if rail:
					var top := D * 0.5 + (D * 0.5 if n == 2 and not horiz else 0.0)
					var rail_y := top + (0.004 if vents > 0 else 0.0015)
					bar(st, Vector3(0.02, rail_y, 0), Vector3(L - 0.01, rail_y, 0), 0.003, 0.007, 8.0, 0.0008)
					for v in vents:
						var x := 0.03 + (L - 0.06) * float(v) / float(maxi(1, vents - 1))
						bar(st, Vector3(x - 0.002, top + 0.001, 0), Vector3(x + 0.002, top + 0.001, 0), 0.006, 0.004, 6.0)
			pieces.append({"mat": "stal_jasna", "build": func(st):
				for k in n:
					var o: Vector3 = off_of.call(k)
					bar(st, o + Vector3(L - 0.006, 0, 0), o + Vector3(L + 0.0005, 0, 0), D * tap * 1.03, D * tap * 1.03, 2.0, 0.0, 16)})
		"czolenko":
			var L: float = P.call("dlugosc")
			var H: float = P.call("wysokosc")
			var W: float = P.call("szerokosc")
			var grooves := int(round(P.call("rowki")))
			var bul: float = P.call("wybrzuszenie")
			main_build = func(st):
				loft(st, [{"c": Vector3(0, 0, 0), "h": H * 0.65, "w": W * 0.75, "p": 2.6},
						{"c": Vector3(L * 0.1, -H * 0.05, 0), "h": H, "w": W, "p": 2.6},
						{"c": Vector3(L * 0.5, -H * bul * 0.5, 0), "h": H * (1.0 + bul), "w": W * (1.0 + bul * 0.3), "p": 2.6},
						{"c": Vector3(L * 0.9, 0, 0), "h": H * 0.95, "w": W * 0.97, "p": 2.6},
						{"c": Vector3(L, H * 0.12, 0), "h": H * 0.55, "w": W * 0.75, "p": 2.6}], 16)
			if grooves > 0:
				pieces.append({"mat": "guma", "build": func(st):
					for i in grooves:
						var x := L * (0.2 + 0.6 * float(i) / float(maxi(1, grooves - 1)))
						bar(st, Vector3(x - 0.002, -H * bul * 0.25, 0), Vector3(x + 0.002, -H * bul * 0.25, 0), H * (1.03 + bul * 0.5), W * 1.03, 2.6, 0.0, 16)})
		"chwyt":
			var Hh: float = P.call("wysokosc")
			var Dd: float = P.call("glebokosc")
			var Ww: float = P.call("szerokosc")
			var A := deg_to_rad(P.call("kat"))
			var bel: float = P.call("brzuch")
			main_build = func(st):
				var dir := Vector3(sin(A), -cos(A), 0)
				var secs: Array = []
				for i in 6:
					var u := float(i) / 5.0
					secs.append({"c": dir * (u * Hh), "h": Dd * (1.0 + bel * sin(u * PI)), "w": Ww * (0.95 + 0.05 * sin(u * PI)), "p": 3.6})
				loft(st, secs, 16)
		"zamek":
			var L: float = P.call("dlugosc")
			var H: float = P.call("wysokosc")
			var W: float = P.call("szerokosc")
			var grooves := int(round(P.call("rowki")))
			var window: bool = P.call("okno") > 0.5
			main_build = func(st): bar(st, Vector3.ZERO, Vector3(L, 0, 0), H, W, 5.5, 0.0025, 20)
			if grooves > 0 or window:
				pieces.append({"mat": "stal_jasna", "build": func(st):
					for i in grooves:
						var x := 0.006 + i * 0.0042
						bar(st, Vector3(x, 0, 0), Vector3(x + 0.0014, 0, 0), H * 0.82, W * 1.02, 8.0, 0.0, 8)
					if window:
						bar(st, Vector3(L * 0.42, H * 0.18, W * 0.5), Vector3(L * 0.62, H * 0.18, W * 0.5), H * 0.4, 0.0012, 8.0, 0.0004, 8)})
		"magazynek":
			var L: float = P.call("dlugosc")
			var Dd: float = P.call("glebokosc")
			var Ww: float = P.call("szerokosc")
			var A := deg_to_rad(P.call("kat"))
			var bend: float = P.call("wygiecie")
			var plate: bool = P.call("stopka") > 0.5
			var dir := Vector3(sin(A), -cos(A), 0)
			var side := Vector3(cos(A), sin(A), 0)
			main_build = func(st):
				var secs: Array = []
				for i in 7:
					var u := float(i) / 6.0
					secs.append({"c": dir * (u * L) + side * (bend * u * u), "h": Dd, "w": Ww, "p": 7.0})
				loft(st, secs, 12)
			if plate:
				pieces.append({"mat": "", "build": func(st):
					var e := dir * L + side * bend
					bar(st, e - dir * 0.001, e + dir * 0.006, Dd * 1.18, Ww * 1.25, 5.0, 0.001, 12)})
		"kablak":
			var L: float = P.call("dlugosc")
			var Dd: float = P.call("glebokosc")
			var nt := int(round(P.call("spusty")))
			var th: float = P.call("grubosc")
			main_build = func(st):
				var secs: Array = []
				for i in 12:
					var a := PI * (1.0 + float(i) / 11.0)
					secs.append({"c": Vector3(L * 0.5 + cos(a) * L * 0.5, sin(a) * Dd, 0), "h": th, "w": 0.009, "p": 4.0})
				loft(st, secs, 8)
			if nt > 0:
				pieces.append({"mat": "stal_jasna", "build": func(st):
					for k in nt:
						var x := L * (0.45 + 0.22 * float(k))
						loft(st, [{"c": Vector3(x, 0, 0), "h": 0.005, "w": 0.005, "p": 4.0},
								{"c": Vector3(x - 0.002, -Dd * 0.4, 0), "h": 0.0045, "w": 0.005, "p": 4.0},
								{"c": Vector3(x - 0.0055, -Dd * 0.75, 0), "h": 0.004, "w": 0.005, "p": 4.0}], 8)})
		"muszka":
			var Hh: float = P.call("wysokosc")
			var Ww: float = P.call("szerokosc")
			var hood: bool = P.call("oslona") > 0.5
			main_build = func(st):
				bar(st, Vector3(-0.004, Hh * 0.5, 0), Vector3(0.004, Hh * 0.5, 0), Hh, Ww, 6.0, 0.001, 10)
				if hood:
					var secs: Array = []
					for i in 9:
						var a := PI * float(i) / 8.0
						secs.append({"c": Vector3(0, Hh * 0.2 + sin(a) * Hh * 1.1, cos(a) * Hh * 0.8), "h": 0.0015, "w": 0.01, "p": 4.0})
					loft(st, secs, 6)
		"szczerbinka":
			var Hh: float = P.call("wysokosc")
			var Ww: float = P.call("szerokosc")
			var gap: float = P.call("szczelina")
			var peep: bool = P.call("dioptra") > 0.5
			main_build = func(st):
				if peep:
					var secs: Array = []
					for i in 13:
						var a := TAU * float(i) / 12.0
						secs.append({"c": Vector3(0, Hh + sin(a) * gap * 1.4, cos(a) * gap * 1.4), "h": 0.002, "w": 0.004, "p": 3.0})
					loft(st, secs, 6, false)
					bar(st, Vector3(0, 0, 0), Vector3(0, Hh - gap * 1.4, 0), 0.003, 0.004, 6.0)
				else:
					for zs in [-1.0, 1.0]:
						var zc: float = zs * (gap * 0.5 + (Ww - gap) * 0.25)
						bar(st, Vector3(-0.004, Hh * 0.5, zc), Vector3(0.004, Hh * 0.5, zc), Hh, (Ww - gap) * 0.5, 6.0, 0.0008, 10)
		"rura":
			var L: float = P.call("dlugosc")
			var D: float = P.call("srednica")
			main_build = func(st): bar(st, Vector3.ZERO, Vector3(L, 0, 0), D, D, 2.0, 0.001, 14)
		"kurek":
			var S: float = P.call("rozmiar")
			var ring: bool = P.call("pierscien") > 0.5
			main_build = func(st):
				if ring:
					var secs: Array = []
					for i in 13:
						var a := TAU * float(i) / 12.0
						secs.append({"c": Vector3(-S * 0.3 + cos(a) * S * 0.45, S * 0.6 + sin(a) * S * 0.45, 0), "h": S * 0.22, "w": S * 0.5, "p": 3.0})
					loft(st, secs, 6, false)
				else:
					bar(st, Vector3(0, S * 0.5, -S * 0.3), Vector3(0, S * 0.5, S * 0.3), S, S, 2.0, 0.0, 12)
				bar(st, Vector3(S * 0.4, 0.0, 0), Vector3(-S * 0.1, S * 0.5, 0), S * 0.6, S * 0.55, 4.0, 0.001, 8)
		"beben":
			var L: float = P.call("dlugosc")
			var D: float = P.call("srednica")
			var nc := int(round(P.call("komory")))
			var flutes: bool = P.call("zlobki") > 0.5
			main_build = func(st): bar(st, Vector3.ZERO, Vector3(L, 0, 0), D, D, 2.0, 0.002, nc * 2 if flutes else 18)
			pieces.append({"mat": "guma", "build": func(st):
				for k in nc:
					var a := TAU * float(k) / float(nc)
					var o := Vector3(L + 0.0002, sin(a) * D * 0.3, cos(a) * D * 0.3)
					bar(st, o - Vector3(0.0015, 0, 0), o, D * 0.2, D * 0.2, 2.0, 0.0, 8)})
		"luneta":
			var L: float = P.call("dlugosc")
			var D: float = P.call("srednica")
			var O: float = P.call("obiektyw")
			var mount: bool = P.call("montaz") > 0.5
			main_build = func(st):
				loft(st, [{"c": Vector3(0, 0, 0), "h": D * 1.45, "w": D * 1.45, "p": 2.0},
						{"c": Vector3(L * 0.15, 0, 0), "h": D * 1.45, "w": D * 1.45, "p": 2.0},
						{"c": Vector3(L * 0.25, 0, 0), "h": D, "w": D, "p": 2.0},
						{"c": Vector3(L * 0.65, 0, 0), "h": D, "w": D, "p": 2.0},
						{"c": Vector3(L * 0.8, 0, 0), "h": O, "w": O, "p": 2.0},
						{"c": Vector3(L, 0, 0), "h": O, "w": O, "p": 2.0}], 18)
			if mount:
				pieces.append({"mat": "stal_jasna", "build": func(st):
					for x in [L * 0.3, L * 0.6]:
						bar(st, Vector3(x - 0.006, 0, 0), Vector3(x + 0.006, 0, 0), D * 1.25, D * 1.25, 2.0, 0.001, 16)
						bar(st, Vector3(x - 0.005, -D * 0.9, 0), Vector3(x + 0.005, -D * 0.9, 0), D * 0.8, D * 0.6, 6.0, 0.001, 8)})
		"tlumik":
			var L: float = P.call("dlugosc")
			var D: float = P.call("srednica")
			main_build = func(st): bar(st, Vector3.ZERO, Vector3(L, 0, 0), D, D, 2.0, 0.003, 18)
		"trzonek":
			var L: float = P.call("dlugosc")
			var D: float = P.call("srednica")
			var fl: float = P.call("splaszczenie")
			var tp: float = P.call("zwezenie")
			var knob: float = P.call("galka")
			var bend: float = P.call("wygiecie")
			main_build = func(st):
				var secs: Array = []
				for i in 10:
					var u := float(i) / 9.0
					var d := D * lerpf(1.0, tp, u)
					if u < 0.12:
						d += knob * (1.0 - u / 0.12)
					secs.append({"c": Vector3(u * L, bend * sin(u * PI), 0), "h": d, "w": d * fl, "p": 2.4})
				loft(st, secs, 12)
		"pret_zgiety":
			var L1: float = P.call("dlugosc1")
			var A := deg_to_rad(P.call("kat"))
			var R: float = P.call("promien")
			var L2: float = P.call("dlugosc2")
			var D: float = P.call("srednica")
			var pw: float = P.call("kanty")
			var flat: bool = P.call("plaski_koniec") > 0.5
			main_build = func(st):
				var secs: Array = [{"c": Vector3.ZERO, "h": D, "w": D, "p": pw}, {"c": Vector3(L1, 0, 0), "h": D, "w": D, "p": pw}]
				var steps := 8
				for i in range(1, steps + 1):
					var a := A * float(i) / float(steps)
					secs.append({"c": Vector3(L1 + sin(a) * R, (1.0 - cos(a)) * R, 0), "h": D, "w": D, "p": pw})
				var end := Vector3(L1 + sin(A) * R, (1.0 - cos(A)) * R, 0)
				var dir := Vector3(cos(A), sin(A), 0)
				if L2 > 0.001:
					secs.append({"c": end + dir * L2 * 0.6, "h": D, "w": D, "p": pw})
					secs.append({"c": end + dir * L2, "h": D * (0.35 if flat else 1.0), "w": D * (1.4 if flat else 1.0), "p": pw})
				loft(st, secs, 10)
		"pierscien":
			var R: float = P.call("promien")
			var T: float = P.call("grubosc")
			var W: float = P.call("szerokosc")
			main_build = func(st):
				var secs: Array = []
				for i in 21:
					var a := TAU * float(i) / 20.0
					secs.append({"c": Vector3(0, sin(a) * R, cos(a) * R), "h": T, "w": W, "p": 2.6})
				loft(st, secs, 8, false)
		"walec":
			var L: float = P.call("dlugosc")
			var D: float = P.call("srednica")
			var D2: float = P.call("srednica2")
			var sides := int(round(P.call("boki")))
			main_build = func(st): bar(st, Vector3.ZERO, Vector3(L, 0, 0), D, D, 2.0, 0.0, sides, D2 if D2 > 0.0 else D, D2 if D2 > 0.0 else D)
		"kula":
			var D: float = P.call("srednica")
			var fl: float = P.call("splaszczenie")
			main_build = func(st):
				var secs: Array = []
				for i in 9:
					var a := PI * float(i) / 8.0
					var r := maxf(0.0002, sin(a) * D)
					secs.append({"c": Vector3(-cos(a) * D * 0.5 * fl, 0, 0), "h": r, "w": r, "p": 2.0})
				loft(st, secs, 14)
		"plytka":
			var L: float = P.call("dlugosc")
			var H: float = P.call("wysokosc")
			var W: float = P.call("szerokosc")
			var R: float = P.call("zaokraglenie")
			var fz: float = P.call("fazka")
			var tp: float = P.call("zwezenie")
			main_build = func(st): bar(st, Vector3(-L * 0.5, 0, 0), Vector3(L * 0.5, 0, 0), H, W, R, minf(fz, minf(H, W) * 0.3), 14, H * tp, W * tp)
		"profil":
			var pts: Array = m.get("profile", PROFILE_PRESETS["prostokat"])
			var T: float = P.call("grubosc")
			var B: float = P.call("fazka")
			var S := int(round(P.call("wygladzenie")))
			var K: float = P.call("klin")
			var KF: float = P.call("klin_od")
			main_build = func(st): profile_mesh(st, pts, T, B, S, K, KF)
	if main_build.is_valid():
		pieces.push_front({"mat": "", "build": main_build})
	return pieces


## Położenie modułu względem rodzica (rot w stopniach, kolejność Z, Y, X jak w broni: najpierw pochylenie).
static func local_xform(m: Dictionary) -> Transform3D:
	var p: Array = m.get("pos", [0, 0, 0])
	var r = m.get("rot", [0, 0, 0])
	var rv := Vector3.ZERO
	if typeof(r) == TYPE_ARRAY:
		rv = Vector3(float(r[0]), float(r[1]), float(r[2]))
	else:
		rv = Vector3(0, 0, float(r))
	var s: Array = m.get("scale", [1, 1, 1])
	var b := Basis.from_euler(Vector3(deg_to_rad(rv.x), deg_to_rad(rv.y), deg_to_rad(rv.z)), EULER_ORDER_YXZ)
	b = b.scaled_local(Vector3(float(s[0]), float(s[1]), float(s[2])))
	return Transform3D(b, Vector3(float(p[0]), float(p[1]), float(p[2]) if p.size() > 2 else 0.0))


## Położenie w układzie broni (z rodzicami).
static func module_xform(data: Dictionary, m: Dictionary, depth: int = 0) -> Transform3D:
	var xf := local_xform(m)
	var pu := str(m.get("parent", ""))
	if pu != "" and depth < 16:
		var pi := find_uid(data, pu)
		if pi >= 0:
			return module_xform(data, data["modules"][pi], depth + 1) * xf
	return xf


## Część ruchoma modułu (dziedziczona po rodzicu, jeśli sam nie ma).
static func module_part(data: Dictionary, m: Dictionary, depth: int = 0) -> String:
	var part := str(m.get("part", ""))
	if part != "" or depth > 16:
		return part
	var pu := str(m.get("parent", ""))
	if pu == "":
		return ""
	var pi := find_uid(data, pu)
	return module_part(data, data["modules"][pi], depth + 1) if pi >= 0 else ""


## Kopie z modyfikatorów: lustro (odbicie w osi Z broni) i powtórzenie (n kopii co krok).
static func modifier_xforms(m: Dictionary) -> Array:
	var mod: Dictionary = m.get("mod", {})
	var count := maxi(1, int(mod.get("powtorz", 1)))
	var step: Array = mod.get("krok", [0.01, 0, 0])
	var stepv := Vector3(float(step[0]), float(step[1]), float(step[2]))
	var out: Array = []
	for k in count:
		out.append([Transform3D(Basis(), stepv * float(k)), false])
	if int(mod.get("lustro", 0)) > 0:
		var mirrored: Array = []
		for o in out:
			mirrored.append([Transform3D(Basis().scaled(Vector3(1, 1, -1)), Vector3.ZERO) * (o[0] as Transform3D), true])
		out.append_array(mirrored)
	return out


## Siatka jednego kawałka modułu ze zużyciem w kolorach wierzchołków.
static func piece_mesh(build: Callable, xf: Transform3D, flip: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	build.call(st)
	st.generate_normals()
	var arr := st.commit_to_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return null
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var nb := xf.basis.inverse().transposed()
	for i in verts.size():
		verts[i] = xf * verts[i]
		norms[i] = (nb * norms[i]).normalized()
	if flip:
		# odbicie lustrzane odwraca kolejność trójkątów
		for i in range(0, verts.size(), 3):
			var t := verts[i + 1]
			verts[i + 1] = verts[i + 2]
			verts[i + 2] = t
			var tn := norms[i + 1]
			norms[i + 1] = norms[i + 2]
			norms[i + 2] = tn
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = curvature_colors(verts, norms)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Krzywizna w wierzchołkach: R = wypukłość (krawędzie do przetarć), G = wklęsłość (brud).
static func curvature_colors(verts: PackedVector3Array, norms: PackedVector3Array) -> PackedColorArray:
	var key := func(v: Vector3) -> Vector3i: return Vector3i(roundi(v.x * 4000.0), roundi(v.y * 4000.0), roundi(v.z * 4000.0))
	var nsum := {}
	var nmin := {}
	var neigh := {}
	var ncount := {}
	for i in verts.size():
		var k: Vector3i = key.call(verts[i])
		if not nsum.has(k):
			nsum[k] = Vector3.ZERO
			nmin[k] = []
			neigh[k] = Vector3.ZERO
			ncount[k] = 0
		nsum[k] += norms[i]
		(nmin[k] as Array).append(norms[i])
	for t in range(0, verts.size() - 2, 3):
		for a in 3:
			var ka: Vector3i = key.call(verts[t + a])
			for b in 3:
				if a != b:
					neigh[ka] += verts[t + b]
					ncount[ka] += 1
	var out := PackedColorArray()
	out.resize(verts.size())
	var cache := {}
	for i in verts.size():
		var k: Vector3i = key.call(verts[i])
		if not cache.has(k):
			var n: Vector3 = (nsum[k] as Vector3).normalized()
			var spread := 0.0
			for nn in nmin[k]:
				spread = maxf(spread, 1.0 - (nn as Vector3).dot(n))
			var c: Vector3 = neigh[k] / maxf(1.0, float(ncount[k]))
			var d := verts[i] - c
			var el := maxf(0.0005, d.length() + 0.001)
			var curv := n.dot(d) / el
			var edge := clampf(curv * 1.6 + spread * 1.2 * signf(curv + 0.05), 0.0, 1.0)
			var cav := clampf(-curv * 1.8, 0.0, 1.0)
			cache[k] = Color(edge, cav, 0.0, 1.0)
		out[i] = cache[k]
	return out


## Budowa: lista kawałków {"module": idx, "part": nazwa, "mesh": ArrayMesh, "mat": ShaderMaterial}.
static func build(data: Dictionary, only: int = -1) -> Array:
	var out: Array = []
	var mods: Array = data.get("modules", [])
	for idx in mods.size():
		if only >= 0 and idx != only:
			continue
		var m: Dictionary = mods[idx]
		if bool(m.get("hidden", false)):
			continue
		var base := module_xform(data, m)
		var part := module_part(data, m)
		var mods_x := modifier_xforms(m)
		for pc in module_pieces(m):
			var mat_name: String = str(pc["mat"]) if str(pc["mat"]) != "" else str(m.get("mat", "stal"))
			var material := Mats.make(mat_name, m.get("wear", {}), float(idx) * 1.37)
			for mx in mods_x:
				var mesh := piece_mesh(pc["build"], (mx[0] as Transform3D) * base, bool(mx[1]))
				if mesh != null:
					out.append({"module": idx, "part": part, "mesh": mesh, "mat": material})
	return out


## Punkt obrotu części ruchomej.
static func part_pivot(data: Dictionary, part: String) -> Vector3:
	var a: Dictionary = data.get("anchors", {})
	var key: String = str({"lufy": "zawias", "beben": "os_bebna", "kurek": "os_kurka"}.get(part, ""))
	if key != "" and a.has(key):
		var h: Array = a[key]
		return Vector3(float(h[0]), float(h[1]), float(h[2]) if h.size() > 2 else 0.0)
	return Vector3.ZERO


## Model do gry: korzeń z częściami stałymi, części ruchome jako dzieci (meta "rest").
## editor=true: każdy moduł osobnym węzłem (meta "module") do zaznaczania myszą.
static func make_visual(data: Dictionary, editor: bool = false) -> MeshInstance3D:
	var root := MeshInstance3D.new()
	root.set_meta("psx_skip", true)
	var pieces: Array
	var id := str(data.get("id", ""))
	if not editor and id != "" and _cache.has(id):
		pieces = _cache[id]
	else:
		pieces = build(data)
		if not editor and id != "":
			_cache[id] = pieces
	var part_nodes := {}
	var static_mesh := ArrayMesh.new()
	for pc in pieces:
		var part := str(pc["part"])
		var mesh: ArrayMesh = pc["mesh"]
		if part == "" and not editor:
			var arr := mesh.surface_get_arrays(0)
			static_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			static_mesh.surface_set_material(static_mesh.get_surface_count() - 1, pc["mat"])
			continue
		var parent: Node3D = root
		var pivot := Vector3.ZERO
		if part != "":
			if not part_nodes.has(part):
				var pn := MeshInstance3D.new()
				pn.name = part
				pivot = part_pivot(data, part)
				pn.transform = Transform3D(Basis(), pivot)
				pn.set_meta("rest", pn.transform)
				pn.set_meta("psx_skip", true)
				root.add_child(pn)
				part_nodes[part] = pn
			parent = part_nodes[part]
			pivot = (parent as Node3D).transform.origin
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = pc["mat"]
		mi.position = -pivot
		mi.set_meta("module", int(pc["module"]))
		mi.set_meta("psx_skip", true)
		parent.add_child(mi)
	if static_mesh.get_surface_count() > 0:
		root.mesh = static_mesh
	return root


## Obrys całości.
static func aabb(data: Dictionary) -> AABB:
	var box := AABB()
	var first := true
	for pc in build(data):
		var b: AABB = (pc["mesh"] as ArrayMesh).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Wylot lufy i linia celowania (kotwice mają pierwszeństwo przed wyliczeniem z modułów).
static func derived(data: Dictionary) -> Dictionary:
	var muzzle := Vector3(0.15, 0.06, 0.0)
	var sight := -1.0
	var top := -1.0
	var found_barrel := false
	for m in data.get("modules", []):
		var xf := module_xform(data, m)
		match str(m.get("type", "")):
			"lufy":
				if not found_barrel:
					muzzle = xf * Vector3(param(m, "dlugosc"), 0, 0)
					found_barrel = true
				var dd := param(m, "srednica")
				var stacked: bool = int(round(param(m, "liczba"))) == 2 and param(m, "uklad") < 0.5
				top = maxf(top, (xf * Vector3(0, dd * (1.0 if stacked else 0.5), 0)).y)
			"zamek":
				if not found_barrel:
					muzzle = xf * Vector3(param(m, "dlugosc"), 0, 0)
				top = maxf(top, (xf * Vector3(0, param(m, "wysokosc") * 0.5, 0)).y)
			"szczerbinka":
				sight = maxf(sight, (xf * Vector3(0, param(m, "wysokosc"), 0)).y)
			"muszka":
				sight = maxf(sight, (xf * Vector3(0, param(m, "wysokosc"), 0)).y)
	var a: Dictionary = data.get("anchors", {})
	if a.has("wylot"):
		var w: Array = a["wylot"]
		muzzle = Vector3(float(w[0]), float(w[1]), float(w[2]))
	if sight < 0.0:
		sight = top + 0.003 if top > 0.0 else 0.07
	var out := {"muzzle": [snappedf(muzzle.x, 0.001), snappedf(muzzle.y, 0.001), snappedf(muzzle.z, 0.001)], "sight_y": snappedf(sight, 0.001)}
	if a.has("lewa"):
		var l: Array = a["lewa"]
		# w układzie dłoni gry: -Z do przodu, Y w górę, X w prawo
		out["support"] = [snappedf(float(l[2]), 0.001), snappedf(float(l[1]), 0.001), snappedf(-float(l[0]), 0.001)]
	return out


## Masa z objętości (przybliżona: obrys każdego modułu) i gęstości materiału.
static func estimate_mass(data: Dictionary) -> float:
	var dens := {"drewno": 650.0, "drewno_jasne": 700.0, "drewno_ciemne": 800.0, "guma": 1100.0, "bakelit": 1300.0,
			"polimer": 1200.0, "tkanina": 400.0, "skora": 900.0, "plastik_czerwony": 1000.0}
	var mass := 0.0
	for pc in build(data):
		var b: AABB = (pc["mesh"] as ArrayMesh).get_aabb()
		var mat_name := str(data["modules"][int(pc["module"])].get("mat", "stal"))
		mass += b.size.x * b.size.y * b.size.z * 0.55 * float(dens.get(mat_name, 7800.0)) * (0.35 if mat_name.begins_with("stal") or mat_name in ["parkeryzowana", "chrom", "rdza", "farba_zielona"] else 1.0)
	return snappedf(mass, 0.05)


## Kształt w siatce ekwipunku z obrysu (pola po 10 cm, najmniej 1x1, najwięcej 7x3).
static func inventory_shape(data: Dictionary) -> Array:
	var b := aabb(data)
	var w := clampi(int(ceil(b.size.x / 0.12)), 1, 7)
	var h := clampi(int(ceil(maxf(b.size.y, b.size.z) / 0.12)), 1, 3)
	var rows: Array = []
	for y in h:
		rows.append("#".repeat(w))
	return rows


static func triangle_count(data: Dictionary) -> int:
	var n := 0
	for pc in build(data):
		n += (pc["mesh"] as ArrayMesh).surface_get_array_len(0) / 3
	return n
