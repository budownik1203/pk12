extends Node
## Piłowanie: na każdej desce leżącej w świecie jest punkt pracy (w połowie
## długości). Z piłą w ręce: prawy przycisk i ruchy myszy w dół, pociągnięcie
## za pociągnięciem. Przepiłowana deska rozpada się na dwie deszczułki (opał,
## szyny na złamania). Pole "saw_into" w items.json: {"result", "count", "strokes"}.

const ItemScript := preload("res://scripts/inventory/item.gd")

var main
var points := {}        # bryła -> punkt pracy
var progress := {}      # bryła -> postęp 0..strokes


func setup(main_node) -> void:
	main = main_node


func _physics_process(_delta: float) -> void:
	if main == null or main.world_items == null:
		return
	for b in main.world_items.bodies:
		if not is_instance_valid(b) or points.has(b):
			continue
		var it = b.get_meta("item")
		if it.get_def().has("saw_into"):
			points[b] = main.work.add_point(self, b, Vector3.ZERO, "lever",
					{"ability": "pilowanie", "label": "WORK_SAW", "id": "pila%d" % b.get_instance_id(), "data": {"body": b, "reach": 2.1}})
	for b in points.keys():
		if not is_instance_valid(b) or not main.world_items.bodies.has(b):
			forget(b)


func forget(b) -> void:
	if points.has(b):
		main.work.points.erase(points[b])
		if main.work.active == points[b]:
			main.work.active = null
		points.erase(b)
	progress.erase(b)


func _need(b) -> float:
	return float(b.get_meta("item").get_def()["saw_into"].get("strokes", 3.0))


func work_status(p) -> Dictionary:
	var b = p.data["body"]
	var r: float = progress.get(b, 0.0) / _need(b)
	return {"text": tr("WORK_PROGRESS_SAW") % int(r * 100.0), "ratio": r}


func work_apply(p, ev: Dictionary) -> void:
	if str(ev.get("type", "")) != "lever":
		return
	var b = p.data["body"]
	if not is_instance_valid(b):
		return
	var step: float = float(ev.get("amount", 0.0)) * (1.0 + main.character.level("stolarstwo") * 0.08)
	var before: float = progress.get(b, 0.0)
	progress[b] = before + step
	var tool = ev.get("tool")
	if tool != null and float(tool.get_def().get("wear", 0.0)) > 0.0:
		tool.props["condition"] = maxf(0.0, tool.condition() - float(tool.get_def()["wear"]) * step)
	if int(progress[b] * 3.0) != int(before * 3.0):
		main.sound.play("saw", b.global_position, -4.0, randf_range(0.9, 1.1))
		main.noise.emit_noise(b.global_position, 9.0, "NOISE_SAW")
	if progress[b] < _need(b):
		return
	var it = b.get_meta("item")
	var s: Dictionary = it.get_def()["saw_into"]
	var xf: Transform3D = b.global_transform
	var n := int(s.get("count", 2))
	var stack: int = it.count
	main.work.active = null
	forget(b)
	main.world_items.remove(b)
	# jedna przepiłowana sztuka ze stosu, reszta zostaje deską
	if stack > 1:
		main.world_items.spawn(ItemScript.new(it.def_id, stack - 1), xf.translated(Vector3.UP * 0.08))
	var axis: Vector3 = xf.basis.x.normalized()
	for k in n:
		var off := (float(k) - (n - 1) * 0.5) * 0.4
		main.world_items.spawn(ItemScript.new(str(s["result"]), 1), Transform3D(xf.basis, xf.origin + axis * off + Vector3.UP * 0.03))
	main.character.add_xp("stolarstwo", 6.0)
	main.sound.play("crack", xf.origin, -6.0, 1.4)
	main.hud.show_message(tr("MSG_SAWN"))
