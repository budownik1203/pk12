extends RefCounted
## Tłumaczenia: polski i angielski od pierwszego builda.
## Teksty leżą w data/lang/<kod>.json; w kodzie używamy tylko kluczy i tr().

const LOCALES := ["pl", "en"]


static func setup() -> void:
	for code in LOCALES:
		var path := "res://data/lang/%s.json" % code
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) != TYPE_DICTIONARY:
			push_error("Nie można wczytać tłumaczenia: " + path)
			continue
		var t := Translation.new()
		t.locale = code
		for key in data:
			t.add_message(key, str(data[key]))
		TranslationServer.add_translation(t)
	TranslationServer.set_locale("pl")


static func current() -> String:
	var loc := TranslationServer.get_locale()
	return "en" if loc.begins_with("en") else "pl"


static func set_locale(code: String) -> void:
	if code in LOCALES:
		TranslationServer.set_locale(code)


static func toggle() -> void:
	set_locale("en" if current() == "pl" else "pl")
