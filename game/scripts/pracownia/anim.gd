extends RefCounted
## Pracownia: animacje broni jako ścieżki z kluczami.
##
## Animacja to słownik kroków: {"krok": {"time": sekundy, "tracks": {"ścieżka": [[t, wartość], ...]},
##   "events": [[t, "dzwiek:nazwa"]]}}. t to część kroku 0..1, między kluczami wartość płynie
## łagodnie (smoothstep). Gra (guns.gd) i Pracownia liczą to tym samym kodem.
##
## Ścieżki:
##   x, y, z       przesunięcie broni w układzie kamery (m; z dodatnie = do siebie)
##   pochyl        lufa w górę (stopnie), odchyl (w lewo/prawo), przechyl (obrót wokół lufy)
##   lewa_x/y/z    lewa dłoń w układzie broni w dłoni (m; -z do przodu); bez nich: punkt podparcia
##   zamek, czolenko  przesunięcie części do tyłu (m)
##   magazynek     magazynek niżej o (m)
##   lufy, kurek, beben  obrót części (stopnie)

const STEPS := {
	"semi": ["fire", "mag_out", "mag_in", "rack", "clear"],
	"pump": ["fire", "pump", "shell", "rack"],
	"break": ["fire", "open", "bshell", "close"],
	"item": [],
}
const STEP_LABELS := {"fire": "Strzał", "mag_out": "Wyjęcie magazynka", "mag_in": "Włożenie magazynka",
		"rack": "Przeładowanie zamka", "clear": "Usunięcie zacięcia", "pump": "Pompka", "shell": "Ładowanie naboju",
		"open": "Złamanie", "bshell": "Nabój do komory", "close": "Zatrzaśnięcie"}
const TRACKS := ["x", "y", "z", "pochyl", "odchyl", "przechyl", "lewa_x", "lewa_y", "lewa_z",
		"zamek", "czolenko", "magazynek", "lufy", "kurek", "beben"]
const TRACK_LABELS := {"x": "Broń: w bok", "y": "Broń: w górę", "z": "Broń: do siebie", "pochyl": "Broń: pochylenie",
		"odchyl": "Broń: odchylenie", "przechyl": "Broń: przechył", "lewa_x": "Lewa dłoń: bok", "lewa_y": "Lewa dłoń: góra",
		"lewa_z": "Lewa dłoń: przód/tył", "zamek": "Zamek", "czolenko": "Czółenko", "magazynek": "Magazynek",
		"lufy": "Lufy", "kurek": "Kurek", "beben": "Bęben"}
const ANGLE_TRACKS := ["pochyl", "odchyl", "przechyl", "lufy", "kurek", "beben"]


## Domyślna animacja szablonu (odtwarza wcześniejsze, wpisane w kod ruchy).
static func default_anim(template: String) -> Dictionary:
	match template:
		"semi":
			var rload := {"x": [[0, -0.07]], "y": [[0, 0.05]], "z": [[0, 0.06]], "pochyl": [[0, 12.0]]}
			return {
				"fire": {"time": 0.14, "tracks": {"y": [[0, 0], [0.15, 0.012], [1, 0]], "z": [[0, 0], [0.15, 0.035], [1, 0]],
						"pochyl": [[0, 0], [0.15, 15.0], [1, 0]], "zamek": [[0, 0], [0.12, 0.028], [0.6, 0]]}},
				"mag_out": {"time": 0.45, "tracks": {"x": [[0, 0], [0.3, -0.07]], "y": [[0, 0], [0.3, 0.05]], "z": [[0, 0], [0.3, 0.06]],
						"pochyl": [[0, 0], [0.3, 12.0]], "przechyl": [[0, 0], [0.35, -60.0]],
						"lewa_x": [[0, -0.05]], "lewa_y": [[0, -0.1], [1, -0.16]], "lewa_z": [[0, 0.06]]},
						"events": [[0.6, "dzwiek:mag_out"]]},
				"mag_in": {"time": 0.6, "tracks": _merge(rload, {"przechyl": [[0, -60.0]], "lewa_x": [[0, -0.01]],
						"lewa_y": [[0, -0.17], [0.9, -0.04]], "lewa_z": [[0, 0.03]], "magazynek": [[0, 0.12], [0.9, 0.0]]})},
				"rack": {"time": 0.4, "tracks": {"x": [[0, -0.07], [1, 0]], "y": [[0, 0.05], [1, 0]], "z": [[0, 0.06], [1, 0]],
						"pochyl": [[0, 12.0], [1, 0]], "przechyl": [[0, -60.0], [0.4, -10.0], [1, 0]],
						"lewa_x": [[0, 0.0]], "lewa_y": [[0, 0.07]], "lewa_z": [[0, 0.03], [0.5, 0.07], [1, 0.03]],
						"zamek": [[0, 0], [0.5, 0.028], [1, 0]]}},
				"clear": {"time": 0.7, "tracks": {"x": [[0, 0], [0.3, -0.04], [1, 0]], "y": [[0, 0], [0.3, 0.03], [1, 0]],
						"przechyl": [[0, 0], [0.3, -20.0], [1, 0]], "lewa_y": [[0, 0.07]], "lewa_z": [[0, 0.03], [0.5, 0.07], [1, 0.03]],
						"lewa_x": [[0, 0.0]], "zamek": [[0, 0], [0.5, 0.028], [1, 0]]}},
			}
		"pump":
			return {
				"fire": {"time": 0.18, "tracks": {"y": [[0, 0], [0.15, 0.012], [1, 0]], "z": [[0, 0], [0.15, 0.06], [1, 0]],
						"pochyl": [[0, 0], [0.15, 22.0], [1, 0]]}},
				"pump": {"time": 0.55, "tracks": {"czolenko": [[0, 0], [0.5, 0.08], [1, 0]]}},
				"rack": {"time": 0.45, "tracks": {"czolenko": [[0, 0], [0.5, 0.08], [1, 0]]}},
				"shell": {"time": 0.5, "tracks": {"x": [[0, -0.05]], "y": [[0, 0.04]], "z": [[0, 0.05]], "przechyl": [[0, 70.0]],
						"lewa_x": [[0, 0.0]], "lewa_y": [[0, -0.1], [0.5, -0.04], [1, -0.1]], "lewa_z": [[0, -0.12]]}},
			}
		"break":
			return {
				"fire": {"time": 0.2, "tracks": {"y": [[0, 0], [0.15, 0.012], [1, 0]], "z": [[0, 0], [0.15, 0.06], [1, 0]],
						"pochyl": [[0, 0], [0.15, 22.0], [1, 0]]}},
				"open": {"time": 0.45, "tracks": {"x": [[0, 0], [0.4, -0.06]], "y": [[0, 0], [0.4, 0.05]], "z": [[0, 0], [0.4, 0.08]],
						"pochyl": [[0, 0], [0.5, -25.0]], "lufy": [[0, 0], [0.6, 32.0]],
						"lewa_x": [[0, 0.0]], "lewa_y": [[0, 0.0]], "lewa_z": [[0, -0.22]]}},
				"bshell": {"time": 0.42, "tracks": {"x": [[0, -0.06]], "y": [[0, 0.05]], "z": [[0, 0.08]], "pochyl": [[0, -25.0]],
						"lufy": [[0, 32.0]], "lewa_x": [[0, -0.02]], "lewa_y": [[0, 0.02], [0.5, -0.12], [1, 0.02]],
						"lewa_z": [[0, -0.06], [0.5, -0.12], [1, -0.06]]}},
				"close": {"time": 0.35, "tracks": {"x": [[0, -0.06], [1, 0]], "y": [[0, 0.05], [1, 0]], "z": [[0, 0.08], [1, 0]],
						"pochyl": [[0, -25.0], [0.5, 20.0], [1, 0]], "lufy": [[0, 32.0], [0.3, 32.0], [0.7, 0.0]],
						"lewa_x": [[0, 0.0]], "lewa_y": [[0, 0.0]], "lewa_z": [[0, -0.22]]}},
			}
	return {}


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for k in b:
		out[k] = b[k]
	return out


## Animacja broni: z pliku Pracowni (jeśli ma kroki) uzupełniona domyślną dla szablonu.
static func resolve(anim: Dictionary, template: String) -> Dictionary:
	var out := default_anim(template)
	for k in anim:
		out[k] = anim[k]
	return out


## Wartość ścieżki w chwili t (0..1); brak ścieżki: null.
static func sample(step: Dictionary, track: String, t: float):
	var tr: Array = step.get("tracks", {}).get(track, [])
	if tr.is_empty():
		return null
	if tr.size() == 1 or t <= float(tr[0][0]):
		return float(tr[0][1])
	for i in range(1, tr.size()):
		var a: Array = tr[i - 1]
		var b: Array = tr[i]
		if t <= float(b[0]):
			var span := maxf(0.0001, float(b[0]) - float(a[0]))
			var u := clampf((t - float(a[0])) / span, 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			return lerpf(float(a[1]), float(b[1]), u)
	return float(tr[tr.size() - 1][1])


## Wszystkie ścieżki naraz: słownik ścieżka -> wartość (tylko istniejące).
static func pose(step: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in step.get("tracks", {}):
		var v = sample(step, str(k), t)
		if v != null:
			out[str(k)] = float(v)
	return out


## Zdarzenia między t0 a t1 (do dźwięków w trakcie kroku).
static func events_between(step: Dictionary, t0: float, t1: float) -> Array:
	var out: Array = []
	for e in step.get("events", []):
		var t := float(e[0])
		if t > t0 and t <= t1:
			out.append(str(e[1]))
	return out


## Wstawia lub zmienia klucz (t zaokrąglone do 0.01).
static func set_key(step: Dictionary, track: String, t: float, value: float) -> void:
	if not step.has("tracks"):
		step["tracks"] = {}
	var tr: Array = step["tracks"].get(track, [])
	t = snappedf(clampf(t, 0.0, 1.0), 0.01)
	for k in tr:
		if absf(float(k[0]) - t) < 0.005:
			k[1] = value
			step["tracks"][track] = tr
			return
	tr.append([t, value])
	tr.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	step["tracks"][track] = tr


static func remove_key(step: Dictionary, track: String, t: float) -> bool:
	var tr: Array = step.get("tracks", {}).get(track, [])
	for i in tr.size():
		if absf(float(tr[i][0]) - t) < 0.02:
			tr.remove_at(i)
			if tr.is_empty():
				step["tracks"].erase(track)
			return true
	return false
