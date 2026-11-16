extends RefCounted
## Warsztat broni: moduły z parametrami (kolba, komora, lufy, czółenko, chwyt, zamek,
## magazynek, kabłąk, muszka, szczerbinka, rura, kurek, płytka) i budowanie z nich modelu.
##
## Broń to plik data/bronie/<id>.json:
##   {"id", "pl", "en", "modules": [{"type", "params", "pos": [x,y,z], "rot": stopnie wokół Z,
##     "mat": materiał, "part": "" | "zamek" | "magazynek" | "lufy" | "czolenko"}],
##    "anchors": {"hinge": [x, y]}, "item": {pola przedmiotu jak w items.json}}
## Układ jak w całej broni gry: X do przodu (lufa), Y w górę, Z w prawo, początek w punkcie
## chwytu prawej dłoni. Gra buduje model z tego samego pliku co warsztat (bez eksportu).

const GunMats := preload("res://scripts/gun_materials.gd")
const DIR := "res://data/bronie"

const PARTS := ["", "zamek", "magazynek", "lufy", "czolenko"]
const MATERIALS := ["stal", "stal_jasna", "stal_grawer", "drewno", "bakelit", "guma", "mosiadz"]

## Moduły: parametr -> [min, max, domyślna, etykieta]
const MODULES := {
	"kolba": {"label": "Kolba", "mat": "drewno", "params": {
		"dlugosc": [0.22, 0.48, 0.36, "Długość"], "stopka": [0.07, 0.15, 0.124, "Wysokość stopki"],
		"szyjka": [0.028, 0.055, 0.04, "Grubość szyjki"], "opad": [0.0, 0.08, 0.03, "Opad"],
		"szerokosc": [0.028, 0.05, 0.041, "Szerokość"], "garb": [0.0, 0.03, 0.0, "Chwyt pistoletowy"],
		"gumowa": [0.0, 1.0, 1.0, "Stopka gumowa (0/1)"]}},
	"komora": {"label": "Komora zamkowa", "mat": "stal", "params": {
		"dlugosc": [0.03, 0.26, 0.075, "Długość"], "wysokosc": [0.02, 0.08, 0.056, "Wysokość"],
		"szerokosc": [0.018, 0.055, 0.042, "Szerokość"], "zaokraglenie": [2.5, 12.0, 7.0, "Kanciastość"]}},
	"lufy": {"label": "Lufa / lufy", "mat": "stal", "params": {
		"dlugosc": [0.08, 0.85, 0.64, "Długość"], "srednica": [0.012, 0.032, 0.0236, "Średnica"],
		"liczba": [1.0, 2.0, 1.0, "Liczba luf"], "uklad": [0.0, 1.0, 0.0, "Układ (0 pion, 1 poziom)"],
		"zwezenie": [0.75, 1.0, 0.92, "Zwężenie u wylotu"], "szyna": [0.0, 1.0, 1.0, "Szyna (0/1)"]}},
	"czolenko": {"label": "Czółenko", "mat": "drewno", "params": {
		"dlugosc": [0.06, 0.4, 0.25, "Długość"], "wysokosc": [0.012, 0.05, 0.026, "Wysokość"],
		"szerokosc": [0.025, 0.06, 0.044, "Szerokość"], "rowki": [0.0, 8.0, 0.0, "Rowki"]}},
	"chwyt": {"label": "Chwyt pistoletowy", "mat": "bakelit", "params": {
		"wysokosc": [0.05, 0.13, 0.1, "Wysokość"], "glebokosc": [0.022, 0.05, 0.034, "Głębokość"],
		"szerokosc": [0.016, 0.036, 0.027, "Szerokość"], "kat": [0.0, 30.0, 10.0, "Pochylenie"]}},
	"zamek": {"label": "Zamek pistoletu", "mat": "stal", "params": {
		"dlugosc": [0.08, 0.24, 0.165, "Długość"], "wysokosc": [0.016, 0.042, 0.028, "Wysokość"],
		"szerokosc": [0.016, 0.032, 0.024, "Szerokość"], "rowki": [0.0, 14.0, 8.0, "Rowki z tyłu"]}},
	"magazynek": {"label": "Magazynek", "mat": "stal_jasna", "params": {
		"dlugosc": [0.04, 0.3, 0.1, "Długość"], "glebokosc": [0.014, 0.06, 0.028, "Głębokość"],
		"szerokosc": [0.01, 0.034, 0.017, "Szerokość"], "kat": [-30.0, 30.0, 10.0, "Pochylenie"],
		"wygiecie": [0.0, 0.06, 0.0, "Wygięcie"]}},
	"kablak": {"label": "Kabłąk i spust", "mat": "stal", "params": {
		"dlugosc": [0.025, 0.08, 0.048, "Długość"], "glebokosc": [0.012, 0.035, 0.022, "Głębokość"],
		"spusty": [1.0, 2.0, 1.0, "Liczba spustów"]}},
	"muszka": {"label": "Muszka", "mat": "stal", "params": {
		"wysokosc": [0.002, 0.02, 0.006, "Wysokość"], "szerokosc": [0.002, 0.008, 0.0032, "Szerokość"]}},
	"szczerbinka": {"label": "Szczerbinka", "mat": "stal", "params": {
		"wysokosc": [0.003, 0.02, 0.007, "Wysokość"], "szerokosc": [0.008, 0.03, 0.017, "Szerokość"],
		"szczelina": [0.002, 0.008, 0.004, "Szczelina"]}},
	"rura": {"label": "Rura magazynka", "mat": "stal_jasna", "params": {
		"dlugosc": [0.08, 0.7, 0.45, "Długość"], "srednica": [0.012, 0.03, 0.021, "Średnica"]}},
	"kurek": {"label": "Kurek", "mat": "stal_jasna", "params": {
		"rozmiar": [0.006, 0.02, 0.012, "Rozmiar"]}},
	"plytka": {"label": "Płytka / dźwignia", "mat": "stal", "params": {
		"dlugosc": [0.004, 0.3, 0.03, "Długość"], "wysokosc": [0.002, 0.1, 0.008, "Wysokość"],
		"szerokosc": [0.002, 0.06, 0.012, "Szerokość"], "zaokraglenie": [2.0, 12.0, 6.0, "Kanciastość"]}},
}

static var _cache := {}       # id broni -> {"data", "meshes"}


# --- dane ---------------------------------------------------------------------------

static func default_module(type: String) -> Dictionary:
	var spec: Dictionary = MODULES.get(type, {})
	var params := {}
	for k in spec.get("params", {}):
		params[k] = float(spec["params"][k][2])
	return {"type": type, "params": params, "pos": [0.0, 0.0, 0.0], "rot": 0.0,
			"mat": str(spec.get("mat", "stal")), "part": ""}


static func param(m: Dictionary, key: String) -> float:
	var spec: Dictionary = MODULES.get(str(m.get("type", "")), {}).get("params", {})
	var d: float = float(spec[key][2]) if spec.has(key) else 0.0
	return float(m.get("params", {}).get(key, d))


static func list_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(f.trim_suffix(".json"))
	out.sort()
	return out


static var _data := {}


static func load_gun(id: String) -> Dictionary:
	if _data.has(id):
		return _data[id]
	var path := "%s/%s.json" % [DIR, id]
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	_data[id] = d
	return d


static func save_gun(data: Dictionary, path: String = "") -> bool:
	if path == "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
		path = "%s/%s.json" % [DIR, str(data.get("id", "bron"))]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	_cache.erase(str(data.get("id", "")))
	_data.erase(str(data.get("id", "")))
	return true


# --- budowanie --------------------------------------------------------------------

## Pierścień przekroju: superelipsa (p=2 elipsa, większe p = zaokrąglony prostokąt).
static func _ring(c: Vector3, t: Vector3, h: float, w: float, p: float, sides: int) -> PackedVector3Array:
	var s := Vector3(0, 0, 1)
	var up := s.cross(t).normalized()
	var out := PackedVector3Array()
	for i in sides:
		var a := TAU * float(i) / float(sides) + PI / float(sides)
		var ca := cos(a)
		var sa := sin(a)
		var yy: float = signf(sa) * pow(absf(sa), 2.0 / p) * h * 0.5
		var zz: float = signf(ca) * pow(absf(ca), 2.0 / p) * w * 0.5
		out.append(c + up * yy + s * zz)
	return out


## Bryła z przekrojów: sections = [{c: Vector3, h, w, p}], sides ścian.
static func loft(st: SurfaceTool, sections: Array, sides: int = 14, caps: bool = true) -> void:
	var rings: Array = []
	for i in sections.size():
		var sc: Dictionary = sections[i]
		var c: Vector3 = sc["c"]
		var nxt: Vector3 = sections[mini(i + 1, sections.size() - 1)]["c"]
		var prv: Vector3 = sections[maxi(i - 1, 0)]["c"]
		var t := (nxt - prv).normalized()
		if t.length() < 0.001:
			t = Vector3.RIGHT
		rings.append(_ring(c, t, float(sc["h"]), float(sc["w"]), float(sc.get("p", 2.6)), sides))
	st.set_smooth_group(0)
	for r in rings.size() - 1:
		var a: PackedVector3Array = rings[r]
		var b: PackedVector3Array = rings[r + 1]
		for i in sides:
			var j := (i + 1) % sides
			st.add_vertex(a[i]); st.add_vertex(b[i]); st.add_vertex(b[j])
			st.add_vertex(a[i]); st.add_vertex(b[j]); st.add_vertex(a[j])
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
					st.add_vertex(center); st.add_vertex(ring[j]); st.add_vertex(ring[i])
				else:
					st.add_vertex(center); st.add_vertex(ring[i]); st.add_vertex(ring[j])


## Pręt prosty z fazowanymi końcami (pudełko o zaokrąglonych krawędziach albo walec).
static func bar(st: SurfaceTool, a: Vector3, b: Vector3, h: float, w: float, p: float, bevel: float = 0.0, sides: int = 14, h2: float = -1.0, w2: float = -1.0) -> void:
	var d := (b - a)
	var ln := d.length()
	if ln < 0.0001:
		return
	var t := d / ln
	if h2 < 0.0:
		h2 = h
	if w2 < 0.0:
		w2 = w
	var bv := minf(bevel, ln * 0.3)
	var secs: Array = []
	if bv > 0.0:
		secs.append({"c": a, "h": maxf(0.001, h - bv * 2.0), "w": maxf(0.001, w - bv * 2.0), "p": p})
	secs.append({"c": a + t * bv, "h": h, "w": w, "p": p})
	secs.append({"c": b - t * bv, "h": h2, "w": w2, "p": p})
	if bv > 0.0:
		secs.append({"c": b, "h": maxf(0.001, h2 - bv * 2.0), "w": maxf(0.001, w2 - bv * 2.0), "p": p})
	loft(st, secs, sides)


## Geometria jednego modułu w jego własnym układzie (przed pos/rot). Zwraca
## [{"mat": nazwa lub "" (materiał modułu), "build": Callable(st)}].
static func module_pieces(m: Dictionary) -> Array:
	var P := func(k): return param(m, k)
	var pieces: Array = []
	var main_build: Callable
	match str(m.get("type", "")):
		"kolba":
			var L: float = P.call("dlugosc")
			var butt: float = P.call("stopka")
			var wrist: float = P.call("szyjka")
			var drop: float = P.call("opad")
			var wid: float = P.call("szerokosc")
			var bump: float = P.call("garb")
			main_build = func(st):
				var secs: Array = []
				var n := 9
				for i in n:
					var u := float(i) / float(n - 1)
					var x := 0.012 - u * L
					var top := 0.038 - (drop + 0.012) * u
					var hh := lerpf(wrist, butt, pow(u, 1.25))
					# chwyt pistoletowy: wybrzuszenie pod szyjką
					var bulge := bump * exp(-pow((u - 0.12) / 0.08, 2.0))
					hh += bulge
					secs.append({"c": Vector3(x, top - hh * 0.5, 0), "h": hh, "w": lerpf(wid * 0.85, wid, u), "p": 2.8})
				loft(st, secs, 16)
			if P.call("gumowa") > 0.5:
				var Lb: float = P.call("dlugosc")
				var top_b: float = 0.038 - (float(P.call("opad")) + 0.012)
				var hb: float = P.call("stopka")
				var wb: float = P.call("szerokosc")
				pieces.append({"mat": "guma", "build": func(st):
					bar(st, Vector3(0.012 - Lb - 0.001, top_b - hb * 0.5, 0), Vector3(0.012 - Lb - 0.017, top_b - hb * 0.5, 0), hb * 1.01, wb * 1.03, 3.2, 0.003, 16)})
		"komora":
			var L: float = P.call("dlugosc")
			var H: float = P.call("wysokosc")
			var W: float = P.call("szerokosc")
			var R: float = P.call("zaokraglenie")
			main_build = func(st): bar(st, Vector3(0, 0, 0), Vector3(L, 0, 0), H, W, R, minf(0.004, L * 0.1), 20)
		"lufy":
			var L: float = P.call("dlugosc")
			var D: float = P.call("srednica")
			var n := int(round(P.call("liczba")))
			var horiz: bool = P.call("uklad") > 0.5
			var tap: float = P.call("zwezenie")
			var rail: bool = P.call("szyna") > 0.5
			main_build = func(st):
				for k in n:
					var off := (float(k) - (n - 1) * 0.5) * D * 1.0
					var o := Vector3(0, 0, off) if horiz else Vector3(0, -off, 0)
					bar(st, o, o + Vector3(L, 0, 0), D, D, 2.0, 0.0, 16, D * tap, D * tap)
				if n == 2:
					# szyny boczne między lufami
					for zs in [-1.0, 1.0]:
						if horiz:
							bar(st, Vector3(0.01, zs * D * 0.33, 0), Vector3(L - 0.01, zs * D * 0.33, 0), 0.004, 0.006, 6.0)
						else:
							bar(st, Vector3(0.01, 0, zs * D * 0.36), Vector3(L - 0.01, 0, zs * D * 0.36), D * 0.3, 0.004, 6.0)
				if rail:
					var top := (D * 0.5 + (D * 0.5 if n == 2 and not horiz else 0.0)) + 0.0015
					bar(st, Vector3(0.02, top, 0), Vector3(L - 0.01, top, 0), 0.003, 0.007, 8.0, 0.0008)
			pieces.append({"mat": "stal_jasna", "build": func(st):
				for k in n:
					var off := (float(k) - (n - 1) * 0.5) * D
					var o := Vector3(0, 0, off) if horiz else Vector3(0, -off, 0)
					bar(st, o + Vector3(L - 0.006, 0, 0), o + Vector3(L + 0.0005, 0, 0), D * tap * 1.03, D * tap * 1.03, 2.0, 0.0, 16)})
		"czolenko":
			var L: float = P.call("dlugosc")
			var H: float = P.call("wysokosc")
			var W: float = P.call("szerokosc")
			var grooves := int(round(P.call("rowki")))
			main_build = func(st):
				loft(st, [{"c": Vector3(0, 0, 0), "h": H * 0.65, "w": W * 0.75, "p": 2.6},
						{"c": Vector3(L * 0.1, -H * 0.05, 0), "h": H, "w": W, "p": 2.6},
						{"c": Vector3(L * 0.9, 0, 0), "h": H * 0.95, "w": W * 0.97, "p": 2.6},
						{"c": Vector3(L, H * 0.12, 0), "h": H * 0.55, "w": W * 0.75, "p": 2.6}], 16)
			if grooves > 0:
				pieces.append({"mat": "guma", "build": func(st):
					for i in grooves:
						var x := L * (0.2 + 0.6 * float(i) / float(maxi(1, grooves - 1)))
						bar(st, Vector3(x - 0.002, 0, 0), Vector3(x + 0.002, 0, 0), H * 1.03, W * 1.03, 2.6, 0.0, 16)})
		"chwyt":
			var Hh: float = P.call("wysokosc")
			var Dd: float = P.call("glebokosc")
			var Ww: float = P.call("szerokosc")
			var A := deg_to_rad(P.call("kat"))
			main_build = func(st):
				var dir := Vector3(sin(A), -cos(A), 0)  # w dół, pochylony do tyłu
				var secs: Array = []
				for i in 5:
					var u := float(i) / 4.0
					var c := dir * (u * Hh)
					var bulge := 1.0 + 0.08 * sin(u * PI)
					secs.append({"c": c, "h": Dd * bulge, "w": Ww * (0.95 + 0.05 * sin(u * PI)), "p": 3.6})
				loft(st, secs, 16)
		"zamek":
			var L: float = P.call("dlugosc")
			var H: float = P.call("wysokosc")
			var W: float = P.call("szerokosc")
			var grooves := int(round(P.call("rowki")))
			main_build = func(st): bar(st, Vector3(0, 0, 0), Vector3(L, 0, 0), H, W, 5.5, 0.0025, 20)
			if grooves > 0:
				pieces.append({"mat": "stal_jasna", "build": func(st):
					for i in grooves:
						var x := 0.006 + i * 0.0042
						bar(st, Vector3(x, 0, 0), Vector3(x + 0.0014, 0, 0), H * 0.82, W * 1.02, 8.0, 0.0, 8)})
		"magazynek":
			var L: float = P.call("dlugosc")
			var Dd: float = P.call("glebokosc")
			var Ww: float = P.call("szerokosc")
			var A := deg_to_rad(P.call("kat"))
			var bend: float = P.call("wygiecie")
			main_build = func(st):
				var secs: Array = []
				for i in 6:
					var u := float(i) / 5.0
					var dir := Vector3(sin(A), -cos(A), 0)
					var side := Vector3(cos(A), sin(A), 0)
					var c := dir * (u * L) + side * (bend * u * u)
					secs.append({"c": c, "h": Dd, "w": Ww, "p": 7.0})
				loft(st, secs, 12)
		"kablak":
			var L: float = P.call("dlugosc")
			var Dd: float = P.call("glebokosc")
			var nt := int(round(P.call("spusty")))
			main_build = func(st):
				var secs: Array = []
				for i in 10:
					var a := PI * (1.0 + float(i) / 9.0)  # półokrąg pod spodem
					secs.append({"c": Vector3(L * 0.5 + cos(a) * L * 0.5, sin(a) * Dd, 0), "h": 0.0035, "w": 0.009, "p": 4.0})
				loft(st, secs, 8)
			pieces.append({"mat": "stal_jasna", "build": func(st):
				for k in nt:
					var x := L * (0.45 + 0.22 * float(k))
					bar(st, Vector3(x, 0, 0), Vector3(x - 0.004, -Dd * 0.75, 0), 0.005, 0.005, 4.0, 0.001, 8)})
		"muszka":
			var Hh: float = P.call("wysokosc")
			var Ww: float = P.call("szerokosc")
			main_build = func(st): bar(st, Vector3(-0.004, Hh * 0.5, 0), Vector3(0.004, Hh * 0.5, 0), Hh, Ww, 6.0, 0.001, 10)
		"szczerbinka":
			var Hh: float = P.call("wysokosc")
			var Ww: float = P.call("szerokosc")
			var gap: float = P.call("szczelina")
			main_build = func(st):
				for zs in [-1.0, 1.0]:
					var zc: float = zs * (gap * 0.5 + (Ww - gap) * 0.25)
					bar(st, Vector3(-0.004, Hh * 0.5, zc), Vector3(0.004, Hh * 0.5, zc), Hh, (Ww - gap) * 0.5, 6.0, 0.0008, 10)
		"rura":
			var L: float = P.call("dlugosc")
			var D: float = P.call("srednica")
			main_build = func(st): bar(st, Vector3.ZERO, Vector3(L, 0, 0), D, D, 2.0, 0.001, 14)
		"kurek":
			var S: float = P.call("rozmiar")
			main_build = func(st):
				bar(st, Vector3(0, S * 0.5, -S * 0.3), Vector3(0, S * 0.5, S * 0.3), S, S, 2.0, 0.0, 12)
				bar(st, Vector3(S * 0.5, S * 0.1, 0), Vector3(-S * 0.1, S * 0.5, 0), S * 0.6, S * 0.55, 4.0, 0.001, 8)
		"plytka":
			var L: float = P.call("dlugosc")
			var H: float = P.call("wysokosc")
			var W: float = P.call("szerokosc")
			var R: float = P.call("zaokraglenie")
			main_build = func(st): bar(st, Vector3(-L * 0.5, 0, 0), Vector3(L * 0.5, 0, 0), H, W, R, minf(0.002, minf(H, W) * 0.2), 14)
	if main_build.is_valid():
		pieces.push_front({"mat": "", "build": main_build})
	return pieces


static func module_xform(m: Dictionary) -> Transform3D:
	var p: Array = m.get("pos", [0, 0, 0])
	var basis := Basis(Vector3(0, 0, 1), deg_to_rad(float(m.get("rot", 0.0))))
	return Transform3D(basis, Vector3(float(p[0]), float(p[1]), float(p[2]) if p.size() > 2 else 0.0))


## Siatki broni: {"": ArrayMesh (stałe części), "zamek": ArrayMesh, ...} i punkty obrotu części.
static func build_meshes(data: Dictionary, only_module: int = -1) -> Dictionary:
	var by_part := {}   # part -> {mat -> SurfaceTool}
	var mods: Array = data.get("modules", [])
	for idx in mods.size():
		if only_module >= 0 and idx != only_module:
			continue
		var m: Dictionary = mods[idx]
		var part := str(m.get("part", ""))
		var xf := module_xform(m)
		for pc in module_pieces(m):
			var mat_name: String = str(pc["mat"]) if str(pc["mat"]) != "" else str(m.get("mat", "stal"))
			if not by_part.has(part):
				by_part[part] = {}
			if not by_part[part].has(mat_name):
				var nst := SurfaceTool.new()
				nst.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_part[part][mat_name] = [nst, []]
			var tmp := SurfaceTool.new()
			tmp.begin(Mesh.PRIMITIVE_TRIANGLES)
			(pc["build"] as Callable).call(tmp)
			var arr: Array = by_part[part][mat_name][1]
			arr.append([tmp, xf])
	var out := {}
	for part in by_part:
		var mesh := ArrayMesh.new()
		for mat_name in by_part[part]:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var added := 0
			for pair in by_part[part][mat_name][1]:
				var tmp: SurfaceTool = pair[0]
				tmp.generate_normals()
				var tm := tmp.commit()
				if tm.get_surface_count() > 0:
					st.append_from(tm, 0, pair[1])
					added += 1
			if added == 0:
				continue
			st.set_material(GunMats.for_name(mat_name))
			st.commit(mesh)
		out[part] = mesh
	return out


## Punkt obrotu ruchomej części (lufy: zawias; reszta: początek układu).
static func part_pivot(data: Dictionary, part: String) -> Vector3:
	if part == "lufy":
		var h: Array = data.get("anchors", {}).get("hinge", [0.08, -0.004])
		return Vector3(float(h[0]), float(h[1]), 0.0)
	return Vector3.ZERO


## Model w dłoni i w świecie: stałe części jako siatka, ruchome jako węzły-dzieci z meta "rest".
static func make_visual(data: Dictionary) -> MeshInstance3D:
	var id := str(data.get("id", ""))
	var meshes: Dictionary
	if id != "" and _cache.has(id):
		meshes = _cache[id]
	else:
		meshes = build_meshes(data)
		if id != "":
			_cache[id] = meshes
	var root := MeshInstance3D.new()
	root.mesh = meshes.get("", ArrayMesh.new())
	for part in meshes:
		if part == "":
			continue
		# siatka części jest w układzie broni: węzeł stoi w punkcie obrotu, siatka cofnięta o niego
		var pivot := part_pivot(data, part)
		var child := MeshInstance3D.new()
		child.name = part
		child.transform = Transform3D(Basis(), pivot)
		child.set_meta("rest", child.transform)
		root.add_child(child)
		var inner := MeshInstance3D.new()
		inner.name = "siatka"
		inner.mesh = meshes[part]
		inner.position = -pivot
		child.add_child(inner)
	return root


## Obrys całej broni (do kolizji i ikon).
static func aabb(data: Dictionary) -> AABB:
	var meshes := build_meshes(data)
	var box := AABB()
	var first := true
	for part in meshes:
		var mesh: ArrayMesh = meshes[part]
		if mesh.get_surface_count() == 0:
			continue
		box = mesh.get_aabb() if first else box.merge(mesh.get_aabb())
		first = false
	return box


## Wylot lufy (koniec pierwszego modułu luf) i wysokość linii celowania nad chwytem.
static func derived(data: Dictionary) -> Dictionary:
	var muzzle := Vector3(0.15, 0.06, 0.0)
	var sight := 0.07
	var top := -1.0
	for m in data.get("modules", []):
		var xf := module_xform(m)
		match str(m.get("type", "")):
			"lufy":
				muzzle = xf * Vector3(param(m, "dlugosc"), 0, 0)
				var dd := param(m, "srednica")
				var stacked: bool = int(round(param(m, "liczba"))) == 2 and param(m, "uklad") < 0.5
				top = maxf(top, (xf * Vector3(0, dd * (1.0 if stacked else 0.5), 0)).y)
			"zamek":
				if muzzle.x <= 0.15001:
					muzzle = xf * Vector3(param(m, "dlugosc"), 0, 0)
				top = maxf(top, (xf * Vector3(0, param(m, "wysokosc") * 0.5, 0)).y)
			"szczerbinka":
				sight = (xf * Vector3(0, param(m, "wysokosc"), 0)).y
	if top > 0.0 and sight == 0.07:
		sight = top + 0.003
	return {"muzzle": [snappedf(muzzle.x, 0.001), snappedf(muzzle.y, 0.001), snappedf(muzzle.z, 0.001)], "sight_y": snappedf(sight, 0.001)}
