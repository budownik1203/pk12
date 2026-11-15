extends Node3D
## Praca na przedmiocie trzymanym w lewej ręce (dziś: otwieranie puszki).
## Punkt pracy wisi przy lewej dłoni; gdy nie celujesz w żaden punkt w świecie,
## a w lewej ręce jest coś z polem "open" w items.json, a w prawej narzędzie
## z wymaganą zdolnością, przytrzymany prawy przycisk i kręcenie myszą otwiera.
## Otwieracz robi to czysto, nóż wolniej i się tępi, łom czy śrubokręt wolno
## i z rozlaniem części zawartości.

const ItemScript := preload("res://scripts/inventory/item.gd")

var main
var point = null
var progress := 0.0


func setup(main_node) -> void:
	main = main_node
	name = "PracaWDloni"
	main.world.add_child(self)
	point = main.work.add_point(self, self, Vector3.ZERO, "rotate",
			{"ability": "otwieranie", "label": "WORK_OPEN_CAN", "id": "dlon", "data": {"what": "open"}})
	main.work.points.erase(point)  # nie jest punktem świata: work_system pyta o niego osobno


## Rodzaje pracy w dłoni: pole w items.json -> [rodzaj ruchu, etykieta].
## open: puszka (kręcenie), cut: krojenie, rip: darcie na szmaty (ruch w dół).
## clean: czyszczenie broni (szmata, wycior, WD-40), ruchy w dół.
const MODES := {"open": ["rotate", "WORK_OPEN_CAN"], "cut": ["lever", "WORK_CUT"], "rip": ["lever", "WORK_RIP"],
		"clean": ["lever", "WORK_CLEAN"]}

var mode := ""


## Punkt pracy, jeśli w lewej ręce jest coś do obrobienia (inaczej null).
func candidate():
	var it = main.inventory.hand("l")
	if it == null:
		progress = 0.0
		return null
	for m in MODES:
		var o: Dictionary = it.get_def().get(m, {})
		if o.is_empty():
			continue
		if mode != m:
			progress = 0.0
		mode = m
		point.kind = MODES[m][0]
		point.label_key = MODES[m][1]
		point.ability = str(o.get("ability", "otwieranie"))
		point.enabled = true
		return point
	return null


func _physics_process(_delta: float) -> void:
	if main == null or main.player == null:
		return
	var body = main.player.body
	if body != null and body.joints.has("dlon_l"):
		global_position = body.joints["dlon_l"]


func work_category(_p) -> String:
	return "remove"


func _need() -> float:
	var it = main.inventory.hand("l")
	if it == null or mode == "":
		return 1.5
	var o: Dictionary = it.get_def().get(mode, {})
	return float(o.get("turns", o.get("strokes", 1.5)))


func work_status(_p) -> Dictionary:
	var need := _need()
	return {"text": tr("WORK_PROGRESS_" + mode.to_upper()) % int(progress / need * 100.0), "ratio": progress / need}


## Koniec czyszczenia broni: wycior czyści do zera, WD-40 prawie do zera i smaruje
## (mniej zacięć przez kilkadziesiąt strzałów), szmata tylko z grubsza.
func _clean(gun, tool) -> void:
	var lvl: int = main.work.tool_level(tool, "czyszczenie")
	var dirt := float(gun.props.get("dirt", 0.0))
	match lvl:
		3:
			dirt = 0.0
		2:
			dirt *= 0.15
		_:
			dirt = minf(dirt, maxf(dirt * 0.5, 0.15))
	gun.props["dirt"] = dirt
	if tool != null and tool.get_def().has("oil"):
		gun.props["oiled"] = int(tool.get_def()["oil"])
		var doses := int(tool.props.get("doses", int(tool.get_def().get("doses", 15)))) - 1
		if doses <= 0:
			main.inventory.remove_item(tool)
		else:
			tool.props["doses"] = doses
	main.character.add_xp("bron_palna", 4.0)
	main.sound.play("gun_rack", global_position, -6.0)
	main.hud.show_message(tr("MSG_GUN_CLEANED") % int(dirt * 100.0))
	main.inventory.changed.emit()


func work_apply(_p, ev: Dictionary) -> void:
	var it = main.inventory.hand("l")
	if it == null or mode == "":
		return
	var o: Dictionary = it.get_def().get(mode, {})
	var step := 0.0
	match str(ev.get("type", "")):
		"rotate":
			step = absf(float(ev.get("turns", 0.0)))  # w obie strony
		"lever":
			step = float(ev.get("amount", 0.0))
		_:
			return
	progress += step
	var tool = ev.get("tool")
	if tool != null and float(tool.get_def().get("wear", 0.0)) > 0.0:
		tool.props["condition"] = maxf(0.0, tool.condition() - float(tool.get_def()["wear"]) * step * 0.5)
	if int(progress * 4.0) != int((progress - step) * 4.0):
		match mode:
			"open":
				main.sound.play("screw", global_position, -8.0, 1.7)
			"cut":
				main.sound.play("chop", global_position, -6.0)
				main.character.add_xp("gotowanie", 1.0)
			"rip":
				main.sound.play("rip", global_position, -6.0)
			"clean":
				main.sound.play("rip", global_position, -14.0, 1.6)
	if progress < _need():
		return
	progress = 0.0
	if mode == "clean":
		_clean(it, tool)
		main.work.active = null
		return
	var lvl: int = main.work.tool_level(tool, point.ability)
	var result := str(o.get("result", ""))
	var count := int(o.get("count", 1))
	var out = ItemScript.new(result, count)
	if mode == "open":
		if lvl <= 1:
			# prowizoryczne narzędzie: część zawartości się wylewa
			var portions := int(out.get_def().get("food", {}).get("portions", 1))
			if portions > 1:
				out.props["portions"] = portions - 1
			main.hud.show_message(tr("MSG_SPILLED"))
		out.props["made"] = main.clock.minutes / 1440.0
		main.sound.play("screw_tight", global_position, -6.0, 1.3)
	else:
		if out.get_def().get("food", {}).has("rot_days"):
			out.props["made"] = float(it.props.get("made", main.clock.minutes / 1440.0))
		main.hud.show_message(tr("MSG_MADE") % [out.display_name(), count])
	# zawartość kieszeni ciętego ubrania nie przepada
	for g in it.grids:
		for x in g.items.duplicate():
			g.remove(x)
			main.inventory.give(x)
	# obrabiany przedmiot ubywa z lewej ręki (ze stosu jedna sztuka), wynik trafia do lewej
	if it.count > 1:
		it.count -= 1
		main.inventory.give(out)
	else:
		main.inventory.take_hand("l")
		main.inventory.slots[main.inventory.LEFT_HAND] = out
		out.slot = main.inventory.LEFT_HAND
	main.inventory.changed.emit()
	main.work.active = null  # przycisk dalej trzymany: kamera stoi do puszczenia
