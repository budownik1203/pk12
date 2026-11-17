extends RefCounted
## Pracownia: szablony startowe (broń i narzędzia) i biblioteka własnych zestawów modułów.

const Core := preload("res://scripts/pracownia/core.gd")
const ItemDB := preload("res://scripts/inventory/item_db.gd")
const PRESET_DIR := "res://data/warsztat/zestawy"

const LIST := {
	"pistolet": {"label": "Pistolet", "cat": "Broń", "template": "semi", "item_from": "pistolet", "desc": "Półautomat z zamkiem i magazynkiem w chwycie"},
	"strzelba": {"label": "Strzelba pompka", "cat": "Broń", "template": "pump", "item_from": "strzelba", "desc": "Rura magazynka, czółenko, kolba"},
	"dwururka": {"label": "Dwururka", "cat": "Broń", "template": "break", "item_from": "", "desc": "Łamana, dwie lufy w pionie"},
	"obrzyn": {"label": "Obrzyn", "cat": "Broń", "template": "break", "item_from": "", "desc": "Dwururka z uciętymi lufami i kolbą"},
	"karabinek": {"label": "Karabinek", "cat": "Broń", "template": "semi", "item_from": "pistolet", "desc": "Długa broń z magazynkiem łukowym"},
	"mlotek": {"label": "Młotek", "cat": "Narzędzia", "template": "item", "item_from": "mlotek", "desc": "Trzonek i obuch; chwyt pionowy"},
	"lom": {"label": "Łom", "cat": "Narzędzia", "template": "item", "item_from": "lom", "desc": "Zgięty pręt sześciokątny"},
	"siekiera": {"label": "Siekiera", "cat": "Narzędzia", "template": "item", "item_from": "lom", "desc": "Trzonek i ostrze z profilu"},
	"noz": {"label": "Nóż", "cat": "Narzędzia", "template": "item", "item_from": "noz", "desc": "Ostrze z profilu z klinem, rękojeść"},
	"srubokret": {"label": "Śrubokręt", "cat": "Narzędzia", "template": "item", "item_from": "srubokret", "desc": "Rękojeść i grot"},
	"pusty": {"label": "Pusty projekt", "cat": "Ogólne", "template": "item", "item_from": "", "desc": "Zaczynasz od zera"},
}


static func _m(type: String, name: String, pos: Array, params: Dictionary = {}, extra: Dictionary = {}) -> Dictionary:
	var m := Core.default_module(type)
	m["name"] = name
	m["pos"] = [float(pos[0]), float(pos[1]), float(pos[2]) if pos.size() > 2 else 0.0]
	for k in params:
		m["params"][k] = float(params[k])
	for k in extra:
		m[k] = extra[k]
	return m


static func item_base(src: String) -> Dictionary:
	if src == "":
		return {}
	var base: Dictionary = ItemDB.get_def(src).duplicate(true)
	base.erase("model")
	for k in ["pl", "en", "short_pl", "short_en"]:
		base.erase(k)
	return base


static func make(key: String) -> Dictionary:
	var spec: Dictionary = LIST.get(key, LIST["pusty"])
	var d := {"version": 2, "id": key if key != "pusty" else "nowy_projekt", "pl": str(spec["label"]), "en": str(spec["label"]),
			"kind": "gun" if str(spec["cat"]) == "Broń" else "item", "template": str(spec["template"]), "replace": "",
			"modules": [], "anchors": {}, "anim": {}, "item": item_base(str(spec.get("item_from", "")))}
	var mods: Array = d["modules"]
	match key:
		"pistolet":
			mods.append(_m("komora", "Szkielet", [-0.042, 0.037, 0], {"dlugosc": 0.15, "wysokosc": 0.018, "szerokosc": 0.021, "zaokraglenie": 6.0}))
			mods.append(_m("zamek", "Zamek", [-0.045, 0.06, 0], {}, {"part": "zamek", "uid": "zamek"}))
			mods.append(_m("chwyt", "Chwyt", [-0.004, 0.03, 0], {"wysokosc": 0.095, "glebokosc": 0.032}))
			mods.append(_m("kablak", "Kabłąk i spust", [0.012, 0.024, 0]))
			mods.append(_m("magazynek", "Magazynek", [-0.004, 0.026, 0], {"dlugosc": 0.098}, {"part": "magazynek"}))
			mods.append(_m("muszka", "Muszka", [0.153, 0.0, 0], {}, {"parent": "zamek"}))
			mods.append(_m("szczerbinka", "Szczerbinka", [0.007, 0.0, 0], {}, {"parent": "zamek"}))
			mods.append(_m("kurek", "Kurek", [-0.052, 0.045, 0]))
			mods[5]["pos"] = [0.153, 0.014, 0.0]
			mods[6]["pos"] = [0.007, 0.014, 0.0]
			d["anchors"] = {"wyrzutnik": [0.03, 0.068, 0.012]}
		"strzelba":
			mods.append(_m("kolba", "Kolba", [0, 0, 0], {"opad": 0.025}))
			mods.append(_m("komora", "Komora", [0.01, 0.017, 0], {"dlugosc": 0.18}))
			mods.append(_m("lufy", "Lufa", [0.19, 0.026, 0], {"dlugosc": 0.53}))
			mods.append(_m("rura", "Rura magazynka", [0.19, -0.003, 0]))
			mods.append(_m("czolenko", "Czółenko", [0.27, -0.004, 0], {"rowki": 6.0}, {"part": "czolenko"}))
			mods.append(_m("kablak", "Kabłąk i spust", [0.02, -0.01, 0]))
			mods.append(_m("muszka", "Muszka", [0.71, 0.04, 0], {"wysokosc": 0.004}, {"mat": "mosiadz"}))
			mods.append(_m("pierscien", "Obejma", [0.6, 0.011, 0], {"promien": 0.02, "szerokosc": 0.01}))
			d["anchors"] = {"lewa": [0.36, -0.02, 0.0]}
		"dwururka", "obrzyn":
			var src := Core.load_project("dwururka")
			if not src.is_empty():
				d["modules"] = (src["modules"] as Array).duplicate(true)
				d["anchors"] = (src["anchors"] as Dictionary).duplicate(true)
				d["item"] = (src.get("item", {}) as Dictionary).duplicate(true)
			if key == "obrzyn":
				for m in d["modules"]:
					match str(m["type"]):
						"lufy": m["params"]["dlugosc"] = 0.3; m["params"]["szyna"] = 0.0
						"kolba":
							m["params"]["dlugosc"] = 0.13
							m["params"]["gumowa"] = 0.0
							m["params"]["stopka"] = 0.07
							m["wear"] = {"zuzycie": 0.7, "brud": 0.6}
						"czolenko": m["params"]["dlugosc"] = 0.17
						"muszka": m["hidden"] = true
				d["id"] = "obrzyn"
		"karabinek":
			mods.append(_m("kolba", "Kolba", [0, 0, 0], {"dlugosc": 0.3, "garb": 0.02, "grzbiet": 0.01}, {"mat": "drewno_ciemne"}))
			mods.append(_m("komora", "Komora", [0.0, 0.02, 0], {"dlugosc": 0.22, "wysokosc": 0.05, "szerokosc": 0.034, "zaokraglenie": 9.0}, {"mat": "parkeryzowana"}))
			mods.append(_m("lufy", "Lufa", [0.22, 0.03, 0], {"dlugosc": 0.38, "srednica": 0.016, "szyna": 0.0, "zwezenie": 1.0}, {"mat": "parkeryzowana"}))
			mods.append(_m("czolenko", "Łoże", [0.21, 0.018, 0], {"dlugosc": 0.22, "wysokosc": 0.04, "szerokosc": 0.04, "rowki": 0.0, "wybrzuszenie": 0.0}, {"mat": "drewno_ciemne"}))
			mods.append(_m("magazynek", "Magazynek łukowy", [0.09, 0.0, 0], {"dlugosc": 0.17, "glebokosc": 0.05, "szerokosc": 0.024, "kat": 8.0, "wygiecie": 0.04}, {"part": "magazynek", "mat": "parkeryzowana"}))
			mods.append(_m("kablak", "Kabłąk i spust", [0.03, -0.004, 0]))
			mods.append(_m("muszka", "Muszka", [0.55, 0.04, 0], {"wysokosc": 0.022, "oslona": 1.0}))
			mods.append(_m("szczerbinka", "Celownik", [0.18, 0.044, 0], {"wysokosc": 0.012}))
			mods.append(_m("plytka", "Rączka zamka", [0.12, 0.03, 0.028], {"dlugosc": 0.006, "wysokosc": 0.008, "szerokosc": 0.03}, {"part": "zamek"}))
			d["anchors"] = {"lewa": [0.3, -0.005, 0.0]}
			d["item"]["two_handed"] = true
			d["item"]["shape"] = ["######"]
		"mlotek":
			mods.append(_m("trzonek", "Trzonek", [-0.1, 0, 0], {"dlugosc": 0.4, "srednica": 0.032, "zwezenie": 0.78, "wygiecie": 0.0, "galka": 0.006}))
			mods.append(_m("plytka", "Obuch", [0.285, 0, 0], {"dlugosc": 0.11, "wysokosc": 0.026, "szerokosc": 0.028, "zaokraglenie": 4.0, "zwezenie": 0.75}, {"mat": "stal", "rot": [0, 90.0, 0], "wear": {"zuzycie": 0.6, "rdza": 0.15}}))
			mods.append(_m("walec", "Główka", [0.285, 0, -0.055], {"dlugosc": 0.02, "srednica": 0.03, "boki": 8.0}, {"rot": [0, 90.0, 0], "mat": "stal_jasna"}))
			mods.append(_m("pierscien", "Klin", [0.29, 0, 0], {"promien": 0.017, "szerokosc": 0.02, "grubosc": 0.003}, {"mat": "stal"}))
		"lom":
			mods.append(_m("pret_zgiety", "Łom", [-0.35, 0, 0], {"dlugosc1": 0.62, "kat": 55.0, "dlugosc2": 0.07}, {"wear": {"zuzycie": 0.6, "rdza": 0.25}}))
			mods.append(_m("plytka", "Pazur", [-0.36, 0, 0], {"dlugosc": 0.04, "wysokosc": 0.006, "szerokosc": 0.03, "zwezenie": 0.6}, {"mat": "farba_zielona", "rot": [0, 0, -12.0]}))
		"siekiera":
			mods.append(_m("trzonek", "Trzonek", [-0.2, 0, 0], {"dlugosc": 0.55, "srednica": 0.032, "splaszczenie": 0.7, "wygiecie": 0.02, "galka": 0.01}))
			var blade := _m("profil", "Ostrze", [0.34, 0.0, 0.0], {"grubosc": 0.026, "klin": 0.12, "klin_od": 0.35, "fazka": 0.002}, {"mat": "stal", "rot": [0, 0, -90.0], "wear": {"zuzycie": 0.55, "rdza": 0.3}})
			blade["profile"] = (Core.PROFILE_PRESETS["ostrze_siekiery"] as Array).duplicate(true)
			mods.append(blade)
		"noz":
			var b2 := _m("profil", "Ostrze", [0.035, 0.0, 0.0], {"grubosc": 0.004, "klin": 0.25, "klin_od": 0.0, "fazka": 0.0005}, {"mat": "stal_jasna"})
			b2["profile"] = (Core.PROFILE_PRESETS["ostrze_noza"] as Array).duplicate(true)
			mods.append(b2)
			mods.append(_m("plytka", "Jelec", [0.03, 0.0, 0], {"dlugosc": 0.008, "wysokosc": 0.036, "szerokosc": 0.016}, {"mat": "mosiadz"}))
			mods.append(_m("trzonek", "Rękojeść", [-0.08, 0.0, 0], {"dlugosc": 0.11, "srednica": 0.026, "splaszczenie": 0.72, "zwezenie": 0.9, "wygiecie": 0.0}, {"mat": "drewno_ciemne"}))
			mods.append(_m("pierscien", "Nity", [-0.05, 0.0, 0], {"promien": 0.0025, "grubosc": 0.0025, "szerokosc": 0.021}, {"mat": "mosiadz", "rot": [0, 90.0, 0], "mod": {"lustro": 0, "powtorz": 2, "krok": [0.05, 0.0, 0.0]}}))
		"srubokret":
			mods.append(_m("trzonek", "Rękojeść", [-0.06, 0, 0], {"dlugosc": 0.1, "srednica": 0.03, "splaszczenie": 1.0, "zwezenie": 0.85, "galka": 0.004}, {"mat": "plastik_czerwony"}))
			mods.append(_m("walec", "Grot", [0.04, 0, 0], {"dlugosc": 0.11, "srednica": 0.006, "boki": 6.0}, {"mat": "chrom"}))
			mods.append(_m("plytka", "Końcówka", [0.155, 0, 0], {"dlugosc": 0.012, "wysokosc": 0.001, "szerokosc": 0.006, "zwezenie": 0.6}, {"mat": "chrom"}))
	if key == "mlotek":
		d["replace"] = "mlotek"
	elif key in ["lom", "noz", "srubokret"]:
		d["replace"] = key
	return d


# --- biblioteka zestawów (zaznaczone moduły zapisane do ponownego użycia) ---------------

static func list_presets() -> Array:
	var out: Array = []
	var dir := DirAccess.open(PRESET_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(f.trim_suffix(".json"))
	out.sort()
	return out


static func save_preset(name: String, modules: Array) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PRESET_DIR))
	var f := FileAccess.open("%s/%s.json" % [PRESET_DIR, name], FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"modules": modules}, "\t"))
	return true


static func load_preset(name: String) -> Array:
	var path := "%s/%s.json" % [PRESET_DIR, name]
	if not FileAccess.file_exists(path):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (d.get("modules", []) as Array) if typeof(d) == TYPE_DICTIONARY else []
