extends Node
## Postać: imię, zawód, cechy i umiejętności (data/character.json).
## Umiejętności mają poziom 0–10 i rosną od używania (add_xp). Siła i kondycja
## zaczynają od 5 i rosną wolno. Cechy dają mnożniki dla systemów gry:
##   xp (nauka), noise (kroki), heal (gojenie), bleed (krwawienie),
##   infection (zakażenie ran), hunger, fatigue, work (szybkość pracy rękami).
## Książki (pole "book" w items.json) mnożą naukę danej umiejętności do
## określonego poziomu. Wymagania (szycie, montaż zamka) blokują czynność,
## dopóki umiejętność nie osiągnie progu.

const MAX_LEVEL := 10

var main
var data := {}
var char_name := ""
var profession := "bezrobotny"
var traits: Array = []
var levels := {}                    # umiejętność -> poziom
var xp := {}                        # umiejętność -> punkty w obecnym poziomie
var books := {}                     # umiejętność -> do jakiego poziomu działa przeczytana książka
var created := false

signal leveled(skill: String, level: int)


func setup(main_node) -> void:
	main = main_node
	var f := FileAccess.open("res://data/character.json", FileAccess.READ)
	data = JSON.parse_string(f.get_as_text())
	create("", "bezrobotny", [])
	created = false


## Tworzy postać od zera: poziomy z bazy, zawodu i cech.
func create(name_text: String, prof: String, trait_ids: Array) -> void:
	char_name = name_text
	profession = prof if data["professions"].has(prof) else "bezrobotny"
	traits = trait_ids.duplicate()
	levels.clear()
	xp.clear()
	books.clear()
	for s in data["skills"]:
		levels[s] = int(data["skills"][s].get("base", 0))
		xp[s] = 0.0
	var bonus: Dictionary = data["professions"][profession].get("skills", {})
	for s in bonus:
		levels[s] = clampi(int(levels[s]) + int(bonus[s]), 0, MAX_LEVEL)
	for t in traits:
		var ts: Dictionary = data["traits"].get(t, {}).get("skills", {})
		for s in ts:
			levels[s] = clampi(int(levels[s]) + int(ts[s]), 0, MAX_LEVEL)
	created = true
	_apply()


## Punkty do wydania: zawód plus złe cechy minus dobre.
func points_for(prof: String, trait_ids: Array) -> int:
	var p := int(data["professions"].get(prof, {}).get("points", 0))
	for t in trait_ids:
		p -= int(data["traits"].get(t, {}).get("cost", 0))
	return p


func level(skill: String) -> int:
	return int(levels.get(skill, 0))


## Punkty doświadczenia potrzebne na następny poziom.
func xp_needed(skill: String) -> float:
	var lvl := level(skill)
	var rate := float(data["skills"].get(skill, {}).get("rate", 1.0))
	return 40.0 * pow(float(lvl + 1), 1.35) / rate


func add_xp(skill: String, amount: float) -> void:
	if not levels.has(skill) or level(skill) >= MAX_LEVEL:
		return
	var mult := effect("xp")
	if books.has(skill) and level(skill) < int(books[skill]):
		mult *= 2.5
	xp[skill] = float(xp[skill]) + amount * mult
	while level(skill) < MAX_LEVEL and float(xp[skill]) >= xp_needed(skill):
		xp[skill] = float(xp[skill]) - xp_needed(skill)
		levels[skill] = level(skill) + 1
		leveled.emit(skill, level(skill))
		if main != null and main.hud != null:
			main.hud.show_message(tr("MSG_LEVEL_UP") % [skill_name(skill), level(skill)])
			main.sound.play_ui("pickup", -4.0)
		_apply()


func xp_ratio(skill: String) -> float:
	return clampf(float(xp.get(skill, 0.0)) / xp_needed(skill), 0.0, 1.0)


## Mnożnik z cech (iloczyn wszystkich cech, które go mają).
func effect(key: String) -> float:
	var m := 1.0
	for t in traits:
		m *= float(data["traits"].get(t, {}).get("effects", {}).get(key, 1.0))
	return m


func skill_name(skill: String) -> String:
	var s: Dictionary = data["skills"].get(skill, {})
	return str(s.get("pl" if TranslationServer.get_locale().begins_with("pl") else "en", skill))


func local(entry: Dictionary, key: String = "") -> String:
	var lang := "pl" if TranslationServer.get_locale().begins_with("pl") else "en"
	return str(entry.get(key + lang if key != "" else lang, ""))


## Czy postać spełnia wymaganie (np. "stitch"); jeśli nie, pokazuje komunikat.
func meets(req_id: String, say: bool = true) -> bool:
	var r: Dictionary = data["requirements"].get(req_id, {})
	if r.is_empty():
		return true
	if level(str(r["skill"])) >= int(r["level"]):
		return true
	if say and main != null:
		main.hud.show_message(tr("MSG_NEEDS_SKILL") % [skill_name(str(r["skill"])), int(r["level"])])
	return false


## Przeczytana książka: nauka danej umiejętności ×2,5 aż do poziomu z danych.
func read_book(item) -> bool:
	var b: Dictionary = item.get_def().get("book", {})
	if b.is_empty():
		return false
	var skill := str(b.get("skill", ""))
	books[skill] = maxi(int(books.get(skill, 0)), int(b.get("up_to", 3)))
	add_xp(skill, float(b.get("xp", 20.0)))
	main.hud.show_message(tr("MSG_BOOK_READ") % [item.display_name(), skill_name(skill), int(books[skill])])
	return true


## Przenosi poziomy na systemy gry (siła, kondycja).
func _apply() -> void:
	if main == null or main.player == null:
		return
	main.player.strength = level("sila")
	main.player.fitness = level("kondycja")


func to_dict() -> Dictionary:
	return {"name": char_name, "profession": profession, "traits": traits.duplicate(),
			"levels": levels.duplicate(), "xp": xp.duplicate(), "books": books.duplicate()}


func from_dict(d: Dictionary) -> void:
	if d.is_empty():
		return
	char_name = str(d.get("name", ""))
	profession = str(d.get("profession", "bezrobotny"))
	traits = (d.get("traits", []) as Array).duplicate()
	for s in data["skills"]:
		levels[s] = int(d.get("levels", {}).get(s, levels.get(s, 0)))
		xp[s] = float(d.get("xp", {}).get(s, 0.0))
	books = {}
	var bk: Dictionary = d.get("books", {})
	for s in bk:
		books[s] = int(bk[s])
	created = true
	_apply()
