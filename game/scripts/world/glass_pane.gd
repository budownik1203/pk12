extends StaticBody3D
## Szyba w oknie domu. Cios ją tłucze (głośno). W ramie zostają odłamki:
## przełażenie przez okno z odłamkami kaleczy ręce (rękawice chronią),
## F na ramie wybija resztki szkła. Wybite okno da się przejść (parapet 0,9 m).

var main
var pane_id := ""
var broken := false
var shards := false
var _mesh: MeshInstance3D
var _trigger: Area3D


func setup(main_node, id: String, size: Vector2) -> void:
	main = main_node
	pane_id = id
	name = "Szyba_" + id
	set_meta("glass", self)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.65, 0.7, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	var box := BoxMesh.new()
	box.size = Vector3(size.x, size.y, 0.01)
	box.material = mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	add_child(_mesh)
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y, 0.03)
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
	# strefa w otworze: kto przez nią przełazi przy odłamkach, ten się kaleczy
	_trigger = Area3D.new()
	var ts := BoxShape3D.new()
	ts.size = Vector3(size.x, size.y, 0.5)
	var tc := CollisionShape3D.new()
	tc.shape = ts
	_trigger.add_child(tc)
	_trigger.monitoring = false
	add_child(_trigger)
	_trigger.body_entered.connect(_on_body)


## Cios w szybę (ten sam interfejs co zombie): tłucze ją.
func take_hit(_damage: float, at: Vector3, _dir: Vector3, _heavy: bool) -> bool:
	if broken:
		if shards:
			clear_shards()
		return false
	shatter(at)
	return true


func shatter(at: Vector3) -> void:
	broken = true
	shards = true
	_apply()
	main.sound.play("glass", at, 2.0)
	main.noise.emit_noise(at, 75.0, "NOISE_GLASS")
	if main.get("utilities") != null and main.utilities != null:
		main.utilities.on_break_in(pane_id)  # wybita szyba domu z alarmem: syrena


func clear_shards() -> void:
	if not shards:
		return
	shards = false
	_apply()
	main.sound.play("glass", global_position, -8.0, 1.4)
	main.noise.emit_noise(global_position, 30.0, "NOISE_GLASS")
	main.hud.show_message(tr("MSG_SHARDS_CLEARED"))


func _apply() -> void:
	_mesh.visible = not broken
	collision_layer = 0 if broken else 1
	_trigger.monitoring = broken
	# rama z odłamkami nadal łapie promień F (żeby dało się je wybić)
	if broken and shards:
		set_collision_layer_value(20, true)


func _on_body(body: Node) -> void:
	if not shards or body != main.player:
		return
	var seg: String = ["przedramie_l", "przedramie_p", "dlon_l", "dlon_p"][randi() % 4]
	var w: Dictionary = main.health.wound(seg, "rana_cieta", 0.45)
	main.hud.show_message(tr("MSG_GLASS_CUT") if not w.is_empty() else tr("MSG_GLASS_SAFE"))


func to_dict() -> Dictionary:
	return {"broken": broken, "shards": shards}


func from_dict(d: Dictionary) -> void:
	broken = bool(d.get("broken", false))
	shards = bool(d.get("shards", false))
	_apply()
