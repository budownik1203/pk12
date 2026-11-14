extends RefCounted
## Zapis i odczyt stanu gry do pliku JSON.
## Format ma numer wersji od pierwszego builda; każdy nowy system dopisuje
## tu swoją sekcję i podbija VERSION, gdy zmienia znaczenie istniejących pól.

const VERSION := 1
const DEFAULT_PATH := "user://zapis_1.json"

enum Result { OK, NO_FILE, BAD_FILE }


static func save(main: Node, path: String = DEFAULT_PATH) -> bool:
	var player = main.player
	var data := {
		"version": VERSION,
		"build": 1,
		"style": main.style_index,
		"locale": TranslationServer.get_locale(),
		"player": {
			"position": _v3(player.global_position),
			"velocity": _v3(player.velocity),
			"yaw": player.rotation.y,
			"pitch": player.pitch,
			"flashlight": player.lamp.visible,
		},
		"bodies": {},
	}
	for body in main.bodies:
		var q: Quaternion = body.global_transform.basis.get_rotation_quaternion()
		data["bodies"][body.get_meta("save_id")] = {
			"position": _v3(body.global_position),
			"rotation": [q.x, q.y, q.z, q.w],
			"linear_velocity": _v3(body.linear_velocity),
			"angular_velocity": _v3(body.angular_velocity),
			"sleeping": body.sleeping,
		}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Nie można zapisać: %s (błąd %d)" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


static func load_into(main: Node, path: String = DEFAULT_PATH) -> int:
	if not FileAccess.file_exists(path):
		return Result.NO_FILE
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return Result.BAD_FILE
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", -1)) != VERSION:
		return Result.BAD_FILE
	var p = data.get("player", {})
	var bodies_data = data.get("bodies", {})
	if typeof(p) != TYPE_DICTIONARY or typeof(bodies_data) != TYPE_DICTIONARY:
		return Result.BAD_FILE

	var player = main.player
	player.global_position = _to_v3(p.get("position"), player.global_position)
	player.velocity = _to_v3(p.get("velocity"), Vector3.ZERO)
	player.set_view(float(p.get("yaw", 0.0)), float(p.get("pitch", 0.0)))
	player.lamp.visible = bool(p.get("flashlight", false))

	for body in main.bodies:
		var b = bodies_data.get(body.get_meta("save_id"))
		if typeof(b) != TYPE_DICTIONARY:
			continue  # bryła dodana po tym zapisie zostaje na swoim miejscu
		var r = b.get("rotation", [0, 0, 0, 1])
		var q := Quaternion(float(r[0]), float(r[1]), float(r[2]), float(r[3])).normalized()
		body.global_transform = Transform3D(Basis(q), _to_v3(b.get("position"), body.global_position))
		body.linear_velocity = _to_v3(b.get("linear_velocity"), Vector3.ZERO)
		body.angular_velocity = _to_v3(b.get("angular_velocity"), Vector3.ZERO)
		body.sleeping = bool(b.get("sleeping", false))

	main.set_style(int(data.get("style", main.style_index)), false)
	TranslationServer.set_locale(str(data.get("locale", "pl")))
	return Result.OK


static func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _to_v3(a, fallback: Vector3) -> Vector3:
	if typeof(a) != TYPE_ARRAY or a.size() != 3:
		return fallback
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
