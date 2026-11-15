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


## Punkt pracy, jeśli w lewej ręce jest coś do otwarcia (inaczej null).
func candidate():
	var it = main.inventory.hand("l")
	if it == null:
		progress = 0.0
		return null
	var o: Dictionary = it.get_def().get("open", {})
	if o.is_empty():
		return null
	point.ability = str(o.get("ability", "otwieranie"))
	point.enabled = true
	return point


func _physics_process(_delta: float) -> void:
	if main == null or main.player == null:
		return
	var body = main.player.body
	if body != null and body.joints.has("dlon_l"):
		global_position = body.joints["dlon_l"]


func work_category(_p) -> String:
	return "remove"


func work_status(_p) -> Dictionary:
	var it = main.inventory.hand("l")
	var need := 1.5
	if it != null:
		need = float(it.get_def().get("open", {}).get("turns", 1.5))
	return {"text": tr("WORK_OPENING") % int(progress / need * 100.0), "ratio": progress / need}


func work_apply(_p, ev: Dictionary) -> void:
	if ev.get("type", "") != "rotate":
		return
	var it = main.inventory.hand("l")
	if it == null:
		return
	var o: Dictionary = it.get_def().get("open", {})
	var turns := absf(float(ev.get("turns", 0.0)))  # w obie strony
	progress += turns
	var tool = ev.get("tool")
	if tool != null and float(tool.get_def().get("wear", 0.0)) > 0.0:
		tool.props["condition"] = maxf(0.0, tool.condition() - float(tool.get_def()["wear"]) * turns * 0.5)
	if int(progress * 4.0) != int((progress - turns) * 4.0):
		main.sound.play("screw", global_position, -8.0, 1.7)
	if progress >= float(o.get("turns", 1.5)):
		progress = 0.0
		var lvl: int = main.work.tool_level(tool, point.ability)
		var opened = ItemScript.new(str(o.get("result", "")), 1)
		if lvl <= 1:
			# prowizoryczne narzędzie: część zawartości się wylewa
			var portions := int(opened.get_def().get("food", {}).get("portions", 1))
			if portions > 1:
				opened.props["portions"] = portions - 1
			main.hud.show_message(tr("MSG_SPILLED"))
		opened.props["made"] = main.clock.minutes / 1440.0
		main.inventory.take_hand("l")
		main.inventory.slots[main.inventory.LEFT_HAND] = opened
		opened.slot = main.inventory.LEFT_HAND
		main.inventory.changed.emit()
		main.sound.play("screw_tight", global_position, -6.0, 1.3)
		main.work.active = null  # przycisk dalej trzymany: kamera stoi do puszczenia
