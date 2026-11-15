extends Control
## Ekran tworzenia postaci przed startem (i po śmierci, dla nowego ocalałego):
## imię, zawód, dobre i złe cechy z bilansem punktów jak w PZ, opis zaznaczonej
## pozycji i podgląd startowych umiejętności. Świat stoi (pauza), dopóki gracz
## nie kliknie „Rozpocznij”.

var main
var character
var prof := "bezrobotny"
var chosen: Array = []

var _name: LineEdit
var _profs: ItemList
var _good: ItemList
var _bad: ItemList
var _chosen_list: ItemList
var _desc: RichTextLabel
var _points: Label
var _start: Button
var _prof_ids: Array = []
var _good_ids: Array = []
var _bad_ids: Array = []

signal finished


func setup(main_node) -> void:
	main = main_node
	character = main.character
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.045, 0.04, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 60
	root.offset_right = -60
	root.offset_top = 40
	root.offset_bottom = -40
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	var title := Label.new()
	title.text = tr("CC_TITLE")
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.5))
	root.add_child(title)
	var name_row := HBoxContainer.new()
	root.add_child(name_row)
	var nl := Label.new()
	nl.text = tr("CC_NAME")
	name_row.add_child(nl)
	_name = LineEdit.new()
	_name.text = tr("CC_DEFAULT_NAME")
	_name.custom_minimum_size = Vector2(320, 0)
	name_row.add_child(_name)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	root.add_child(cols)
	_profs = _column(cols, tr("CC_PROFESSION"))
	_good = _column(cols, tr("CC_GOOD"))
	_bad = _column(cols, tr("CC_BAD"))
	_chosen_list = _column(cols, tr("CC_CHOSEN"))
	_desc = RichTextLabel.new()
	_desc.custom_minimum_size = Vector2(0, 150)
	_desc.bbcode_enabled = true
	root.add_child(_desc)
	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	_points = Label.new()
	_points.add_theme_font_size_override("font_size", 20)
	_points.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_points)
	_start = Button.new()
	_start.text = tr("CC_START")
	_start.custom_minimum_size = Vector2(220, 44)
	bottom.add_child(_start)
	_start.pressed.connect(_on_start)

	var d: Dictionary = character.data
	for id in d["professions"]:
		var p: Dictionary = d["professions"][id]
		_profs.add_item("%s (%+d)" % [character.local(p), int(p["points"])])
		_prof_ids.append(id)
	for id in d["traits"]:
		var t: Dictionary = d["traits"][id]
		var cost := int(t["cost"])
		if cost > 0:
			_good.add_item("%s (−%d)" % [character.local(t), cost])
			_good_ids.append(id)
		else:
			_bad.add_item("%s (+%d)" % [character.local(t), -cost])
			_bad_ids.append(id)
	_profs.item_selected.connect(func(i): prof = _prof_ids[i]; _refresh(); _describe_prof())
	_good.item_activated.connect(func(i): _toggle(_good_ids[i]))
	_bad.item_activated.connect(func(i): _toggle(_bad_ids[i]))
	_good.item_selected.connect(func(i): _describe_trait(_good_ids[i]))
	_bad.item_selected.connect(func(i): _describe_trait(_bad_ids[i]))
	_chosen_list.item_activated.connect(func(i): _toggle(chosen[i]))
	_profs.select(0)
	_refresh()
	_describe_prof()


func _column(parent: Container, label: String) -> ItemList:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", Color(0.85, 0.75, 0.5))
	box.add_child(l)
	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(list)
	return list


## Dwuklik dodaje lub usuwa cechę (cechy wykluczające się nie wejdą razem).
func _toggle(id: String) -> void:
	if chosen.has(id):
		chosen.erase(id)
	else:
		var excl: Array = character.data["traits"][id].get("excl", [])
		for e in excl:
			if chosen.has(e):
				main.hud.show_message(tr("CC_EXCLUSIVE"))
				return
		chosen.append(id)
	_refresh()
	_describe_trait(id)


func _refresh() -> void:
	_chosen_list.clear()
	for id in chosen:
		_chosen_list.add_item(character.local(character.data["traits"][id]))
	var pts: int = character.points_for(prof, chosen)
	_points.text = tr("CC_POINTS") % pts
	_points.add_theme_color_override("font_color", Color(0.6, 0.85, 0.5) if pts >= 0 else Color(0.95, 0.4, 0.35))
	_start.disabled = pts < 0


func _describe_prof() -> void:
	var p: Dictionary = character.data["professions"][prof]
	var lines: PackedStringArray = []
	for s in p.get("skills", {}):
		lines.append("%s +%d" % [character.skill_name(s), int(p["skills"][s])])
	_desc.text = "[b]%s[/b]\n%s\n%s" % [character.local(p), character.local(p, "desc_"), ", ".join(lines)]


func _describe_trait(id: String) -> void:
	var t: Dictionary = character.data["traits"][id]
	_desc.text = "[b]%s[/b]\n%s\n[i]%s[/i]" % [character.local(t), character.local(t, "desc_"), tr("CC_DOUBLECLICK")]


func _on_start() -> void:
	if character.points_for(prof, chosen) < 0:
		return
	character.create(_name.text.strip_edges(), prof, chosen)
	finished.emit()
	queue_free()
