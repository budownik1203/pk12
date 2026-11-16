extends Node
## Zwykłe drzwi w domach: skrzydło na zawiasie z zatrzaskiem, bez zamka.
## F: na zatrzasku naciska klamkę i pcha skrzydło od gracza; otwarte domyka.
## Chwyt (T) za klamkę i pochylenie wzroku też otwiera, jak w drzwiach komórki.
## Domknięte zaskakują. Zombie wali w zatrzaśnięte drzwi i po chwili je wyważa.

const LATCH_ANGLE := 0.08
const BANG_NEEDED := 6.0

var main
var door: RigidBody3D
var door_id := ""
var latched := true
var _closed: Transform3D
var _relatch := 0.0
var _closing := false
var _bang := 0.0
var locked := false                # zamknięte na klucz (domy osiedla)
var key_id := -1
var _width_axis := Vector3.RIGHT   # lokalnie: od zawiasu do wolnej krawędzi
var _half_width := 0.47


func setup(main_node, body: RigidBody3D, id: String) -> void:
	main = main_node
	door = body
	door_id = id
	name = "Drzwi_" + id
	_closed = door.global_transform
	# oś szerokości skrzydła (od zawiasu do krawędzi) i oś grubości, z wymiarów bryły
	for c in door.get_children():
		if c is CollisionShape3D and c.shape is BoxShape3D:
			var bs: Vector3 = (c.shape as BoxShape3D).size
			_width_axis = Vector3.RIGHT if bs.x >= bs.z else Vector3.BACK
			_half_width = maxf(bs.x, bs.z) * 0.5
	door.set_meta("door_sys", self)
	_set_latched(true)


func _set_latched(v: bool) -> void:
	latched = v
	if v:
		door.global_transform = _closed
		door.linear_velocity = Vector3.ZERO
		door.angular_velocity = Vector3.ZERO
	door.freeze = v


func door_angle() -> float:
	return door.global_transform.basis.z.angle_to(_closed.basis.z)


func try_unlatch() -> bool:
	if not latched:
		return true
	if locked:
		main.sound.play("handle", door.global_position, -4.0, 0.8)
		return false
	_set_latched(false)
	_relatch = 0.8
	main.noise.emit_noise(door.global_position, 25.0, "NOISE_HANDLE")
	return true


func handle_pull(pitch_drop: float) -> void:
	if pitch_drop > 0.25:
		try_unlatch()


func on_use(_hit: Vector3) -> void:
	if locked and latched:
		if main.inventory.has_key(key_id):
			locked = false
			main.sound.play("screw_tight", door.global_position, -4.0, 1.6)
			main.hud.show_message(tr("MSG_DOOR_UNLOCKED"))
		else:
			main.sound.play("handle", door.global_position, -4.0, 0.8)
			main.hud.show_message(tr("MSG_DOOR_LOCKED_KEY"))
		return
	if latched:
		try_unlatch()
		_push_from(main.player.global_position, 30.0)
	elif door_angle() > LATCH_ANGLE:
		_closing = true  # domykanie
		_relatch = 0.0


## Pchnięcie skrzydła od podanego punktu (gracza albo zombie).
func _push_from(from: Vector3, strength: float) -> void:
	# pchamy przy wolnej krawędzi, prostopadle do skrzydła (wcześniej siła szła
	# w płaszczyźnie drzwi i skrzydło uchylało się tylko na szparę)
	var edge := door.global_transform * (_width_axis * _half_width * 0.85)
	var thick_axis := Vector3.BACK if _width_axis == Vector3.RIGHT else Vector3.RIGHT
	var n := (door.global_transform.basis * thick_axis).normalized()
	var side := signf(n.dot(edge - from))
	if side == 0.0:
		side = 1.0
	door.sleeping = false
	door.apply_impulse(n * side * strength, edge - door.global_position)


func _physics_process(delta: float) -> void:
	if door == null:
		return
	_relatch = maxf(0.0, _relatch - delta)
	if latched:
		return
	if _closing:
		# skrzydło wraca do framugi
		var target := _closed.basis.get_rotation_quaternion()
		var cur := door.global_transform.basis.get_rotation_quaternion()
		var diff := (target * cur.inverse()).normalized()
		var axis := diff.get_axis()
		var ang := diff.get_angle()
		if ang > PI:
			ang -= TAU
		door.angular_velocity = axis * clampf(ang * 6.0, -3.0, 3.0)
	var held: bool = main.interaction.held == door
	if _relatch <= 0.0 and door_angle() < LATCH_ANGLE and (door.angular_velocity.length() < 1.5 or _closing) and not held:
		_closing = false
		_set_latched(true)
		main.noise.emit_noise(door.global_position, 35.0, "NOISE_DOOR_CLICK")


## Zombie wali w zatrzaśnięte drzwi; po chwili wyważa i pcha je od siebie.
func zombie_bang(delta: float, from: Vector3 = Vector3.ZERO) -> void:
	if not latched:
		return
	_bang += delta
	if int(_bang * 1.5) != int((_bang - delta) * 1.5):
		main.noise.emit_noise(door.global_position, 65.0, "NOISE_DOOR_BANG")
	if _bang >= BANG_NEEDED * (1.6 if locked else 1.0):
		_bang = 0.0
		locked = false  # wyważone: zamek puścił
		_set_latched(false)
		if main.get("utilities") != null and main.utilities != null:
			main.utilities.on_break_in(door_id)
		_relatch = 1.5
		main.noise.emit_noise(door.global_position, 80.0, "NOISE_DOOR_BREAK")
		_push_from(from if from != Vector3.ZERO else door.global_position + door.global_transform.basis.x, 30.0)


func to_dict() -> Dictionary:
	var t := door.global_transform
	return {"latched": latched, "locked": locked, "o": [t.origin.x, t.origin.y, t.origin.z],
			"q": [t.basis.get_rotation_quaternion().x, t.basis.get_rotation_quaternion().y,
				t.basis.get_rotation_quaternion().z, t.basis.get_rotation_quaternion().w]}


func from_dict(d: Dictionary) -> void:
	locked = bool(d.get("locked", locked))
	if bool(d.get("latched", true)):
		_set_latched(true)
		return
	_set_latched(false)
	var o: Array = d.get("o", [0, 0, 0])
	var q: Array = d.get("q", [0, 0, 0, 1])
	door.global_transform = Transform3D(Basis(Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3]))),
			Vector3(float(o[0]), float(o[1]), float(o[2])))
	_relatch = 1.0
