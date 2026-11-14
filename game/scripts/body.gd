extends Node3D
## Widoczne ciało postaci, build 2b.
## Ciało składa się z osobnych brył na stawach (jak modele z ery PS1), bez
## skórowania. Nogi i ręce ustawia odwrotna kinematyka dwóch kości:
##   nogi: krok proceduralny zależny od prędkości, kucanie zgina kolana samo,
##   ręce: luźno zwisają i bujają się w marszu; trzymając przedmiot sięgają do
##   punktu chwytu (ciężkie rzeczy obiema rękami); lewa trzyma latarkę.
## Dłonie mają własną fizykę: cel dłoni wynika z kamery, ale dłoń goni go
## na sprężynie, więc przy szybkim obrocie zostaje w tyle jak w Tarkovie.

const SEGMENTS := preload("res://models/cialo_segmenty.glb")
const Tex := preload("res://scripts/textures.gd")
const WorldItems := preload("res://scripts/world_items.gd")

# wymiary w metrach
const HIP_HEIGHT := 0.93          # staw biodrowy w pozycji stojącej (kolana minimalnie ugięte)
const HIP_HALF := 0.1
const THIGH := 0.44
const SHIN := 0.44
const ANKLE := 0.075              # kostka nad podłogą
const SHOULDER_HALF := 0.205
const UPPER_ARM := 0.31
const FOREARM := 0.29
const PALM := 0.07                # od nadgarstka do środka dłoni
const NECK_BELOW_EYE := 0.2
const NECK_BEHIND_EYE := 0.07
const BODY_BACK := 0.17           # ciało jest za kamerą, by patrząc w dół widzieć tors i nogi
const CROUCH_PELVIS_BACK := 0.3

# chód
const STEP_LIFT := 0.11
const ARM_SWING := 0.13

# dłonie
const HAND_STIFF_FREE := 260.0    # luźne ręce: szybko wracają
const HAND_STIFF_VIEW := 110.0    # latarka przed sobą: wyraźne opóźnienie
const HAND_STIFF_GRIP := 900.0    # dłoń na trzymanym przedmiocie
const HAND_TURN_RATE := 9.0       # jak szybko dłoń dogania obrót kamery
const LAMP_HAND := Vector3(-0.17, -0.2, -0.38)  # latarka w lewej dłoni (układ kamery)
const ITEM_HAND := Vector3(0.19, -0.24, -0.4)   # przedmiot w prawej dłoni (układ kamery)
const TWO_HAND_MASS := 8.0        # od tej masy przedmiot trzyma się obiema rękami
const TWO_HAND_SPREAD := 0.16     # rozstaw dłoni na boki od punktu chwytu

var player                        # player.gd (bez typu: unikamy zależności cyklicznej)
var camera: Camera3D

var _parts := {}
var _phase := 0.0
var _gait := 0.0                  # 0 stoi, 1 pełny krok

# stan dłoni: pozycja, prędkość, orientacja (dla każdej ręki osobno)
var hand_pos := {"l": Vector3.ZERO, "r": Vector3.ZERO}
var _hand_vel := {"l": Vector3.ZERO, "r": Vector3.ZERO}
var hand_rot := {"l": Quaternion.IDENTITY, "r": Quaternion.IDENTITY}
var _initialized := false
const CARRY_BOARD_GAP := 0.027     # odstęp desek w niesionym stosie
const GRIP_UP_OFFSET := 0.12       # środek młotka nad dłonią (ułamek długości)

var _hand_visuals := {"l": null, "r": null}
var _hand_visual_uids := {"l": -1, "r": -1}

# punkty z ostatniej klatki (do testów i diagnostyki)
var joints := {}


func setup(owner_player, cam: Camera3D) -> void:
	player = owner_player
	camera = cam
	_build()


func _build() -> void:
	var scene: Node = SEGMENTS.instantiate()
	var meshes := {}
	for child in scene.find_children("*", "MeshInstance3D", true, false):
		meshes[child.name] = (child as MeshInstance3D).mesh
	scene.free()

	var jacket := _mat(Color(0.24, 0.26, 0.21))
	var jeans := _mat(Color(0.17, 0.2, 0.27))
	var boots := _mat(Color(0.11, 0.09, 0.075))
	var skin := _mat(Color(0.6, 0.47, 0.39))
	var metal := _mat(Color(0.12, 0.12, 0.13))

	_part("tors", meshes["tors"], jacket)
	_part("miednica", meshes["miednica"], jeans)
	for s in ["l", "r"]:
		_part("udo_" + s, meshes["udo"], jeans)
		_part("lydka_" + s, meshes["lydka"], jeans)
		_part("stopa_" + s, meshes["stopa"], boots)
		_part("ramie_" + s, meshes["ramie"], jacket)
		_part("przedramie_" + s, meshes["przedramie"], jacket)
		_part("dlon_" + s, meshes["dlon"], skin)
	var head := _part("glowa", meshes["glowa"], skin)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_part("latarka", meshes["latarka"], metal)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	return m


func _part(id: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = id
	mi.mesh = mesh
	mi.material_override = mat
	mi.top_level = true
	add_child(mi)
	_parts[id] = mi
	return mi


# --- pomocnicze -------------------------------------------------------------

func _update_hand_visual(side: String, item) -> void:
	var uid: int = item.uid * 100 + (item.count if item.is_bulky() else 0) if item != null else -1
	if uid == _hand_visual_uids[side]:
		return
	if _hand_visuals[side] != null:
		_hand_visuals[side].queue_free()
		_hand_visuals[side] = null
	_hand_visual_uids[side] = uid
	if item != null:
		var vis: Node3D
		if item.is_bulky():
			# niesiony stos: każda sztuka osobno, lekko przesunięte
			vis = Node3D.new()
			for k in item.count:
				var piece := WorldItems.make_visual(item)
				piece.position = Vector3(0.012 * ((k * 7) % 3 - 1), CARRY_BOARD_GAP * k, 0.006 * ((k * 5) % 3 - 1))
				vis.add_child(piece)
		else:
			vis = WorldItems.make_visual(item)
		vis.top_level = true
		add_child(vis)
		_hand_visuals[side] = vis


## Odwrotna kinematyka dwóch kości. Zwraca [staw środkowy, koniec].
static func solve_two_bone(root: Vector3, target: Vector3, pole: Vector3, l1: float, l2: float) -> Array:
	var d := target - root
	var dist := clampf(d.length(), 0.01, l1 + l2 - 0.001)
	var dir := d.normalized() if d.length() > 0.0001 else Vector3.DOWN
	var x := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(0.0, l1 * l1 - x * x))
	var to_pole := pole - root
	var bend := to_pole - dir * to_pole.dot(dir)
	if bend.length() < 0.0001:
		bend = dir.cross(Vector3.RIGHT)
	bend = bend.normalized()
	return [root + dir * x + bend * h, root + dir * dist]


## Ustawia kończynę o jednostkowej długości od p0 do p1.
func _limb(id: String, p0: Vector3, p1: Vector3, side: Vector3) -> void:
	var y := p1 - p0
	var length := y.length()
	if length < 0.0001:
		return
	var yn := y / length
	var x := (side - yn * side.dot(yn))
	x = x.normalized() if x.length() > 0.0001 else yn.cross(Vector3.FORWARD).normalized()
	var z := x.cross(yn)
	_parts[id].global_transform = Transform3D(Basis(x, yn * length, z), p0)


func _place(id: String, basis: Basis, origin: Vector3) -> void:
	_parts[id].global_transform = Transform3D(basis, origin)


func _spring(side: String, target: Vector3, stiff: float, delta: float) -> void:
	var pos: Vector3 = hand_pos[side]
	var vel: Vector3 = _hand_vel[side]
	var acc := (target - pos) * stiff - vel * 2.0 * sqrt(stiff)
	vel += acc * delta
	pos += vel * delta
	# dłoń nie może odjechać daleko od celu (np. po teleporcie)
	if pos.distance_to(target) > 0.6:
		pos = target
		vel = Vector3.ZERO
	hand_pos[side] = pos
	_hand_vel[side] = vel


func _turn_hand(side: String, target: Quaternion, delta: float) -> void:
	var q: Quaternion = hand_rot[side]
	hand_rot[side] = q.slerp(target, 1.0 - exp(-HAND_TURN_RATE * delta)).normalized()


# --- klatka -------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var root: Transform3D = player.global_transform
	var up := Vector3.UP
	var fwd := -root.basis.z
	var right := root.basis.x
	var feet := root.origin

	# --- chód: faza kroku od prędkości poziomej
	var vel: Vector3 = player.velocity
	var hv := Vector3(vel.x, 0.0, vel.z)
	var speed := hv.length()
	var on_floor: bool = player.is_on_floor() and not player.is_mantling()
	var stride := 0.38 + speed * 0.17
	if on_floor and speed > 0.05:
		_phase = fmod(_phase + speed / stride * PI * delta, TAU)
	_gait = move_toward(_gait, clampf(speed / 1.2, 0.0, 1.0) if on_floor else 0.0, 4.0 * delta)
	var move_dir := hv / speed if speed > 0.05 else fwd

	# --- tułów: od miednicy do podstawy szyi pod oczami
	var crouch_t := clampf((player.STAND_HEIGHT - player.height) / (player.STAND_HEIGHT - player.CROUCH_HEIGHT), 0.0, 1.0)
	var eye := camera.global_position
	var neck := eye - up * NECK_BELOW_EYE - fwd * NECK_BEHIND_EYE
	var pelvis_h := lerpf(HIP_HEIGHT, 0.56, crouch_t) + sin(_phase * 2.0) * 0.015 * _gait
	var pelvis := feet + up * pelvis_h - fwd * (BODY_BACK + CROUCH_PELVIS_BACK * crouch_t)
	var spine := neck - pelvis
	var torso_up := spine.normalized()
	var torso_fwd := (fwd - torso_up * fwd.dot(torso_up)).normalized()
	var torso_right := torso_up.cross(-torso_fwd).normalized()
	_limb("tors", pelvis, neck, right)
	_place("miednica", Basis(right, up, -fwd), pelvis)
	_place("glowa", Basis(right, up, -fwd), eye + up * 0.02 - fwd * 0.02)

	# --- nogi
	for s in ["l", "r"]:
		var sign := -1.0 if s == "l" else 1.0
		var ph := _phase + (0.0 if s == "l" else PI)
		var hip := pelvis + right * HIP_HALF * sign
		var swing := sin(ph) * stride * 0.5 * _gait
		var lift := maxf(0.0, cos(ph)) * STEP_LIFT * _gait
		# stopa pod biodrem: nogi pionowo pod miednicą, nie wysunięte przed tułów
		var under_hip := Vector3(hip.x, feet.y, hip.z) + right * 0.015 * sign
		var foot := under_hip + move_dir * swing + up * (ANKLE + lift)
		if not on_floor:
			foot += up * 0.18 - fwd * 0.05  # w powietrzu i przy wspinaniu nogi podkurczone
		var knee_pole := hip + fwd * 0.6 + right * sign * 0.05
		var leg := solve_two_bone(hip, foot, knee_pole, THIGH, SHIN)
		var knee: Vector3 = leg[0]
		var ankle: Vector3 = leg[1]
		_limb("udo_" + s, hip, knee, right)
		_limb("lydka_" + s, knee, ankle, right)
		_place("stopa_" + s, Basis(right, up, -fwd), ankle)
		joints["stopa_" + s] = ankle
		joints["kolano_" + s] = knee
	joints["miednica"] = pelvis

	# --- ręce
	var shoulder_base := neck - torso_up * 0.04
	var cam_basis := camera.global_transform.basis
	var cam_q := cam_basis.get_rotation_quaternion()
	var targets := {}
	var stiff := {}
	var held: RigidBody3D = player.held_body
	var has_held := held != null and is_instance_valid(held)
	var two_hands := has_held and held.mass >= TWO_HAND_MASS
	var lamp_on: bool = player.lamp.visible
	var lamp_visible := lamp_on

	for s in ["l", "r"]:
		var sign := -1.0 if s == "l" else 1.0
		var shoulder := shoulder_base + torso_right * SHOULDER_HALF * sign
		joints["bark_" + s] = shoulder
		var ph := _phase + (PI if s == "l" else 0.0)  # ręka chodzi przeciwnie do nogi
		# luźno zwisająca ręka
		var hang := shoulder - up * (UPPER_ARM + FOREARM - 0.03) + right * sign * 0.06 \
				+ move_dir * sin(ph) * ARM_SWING * _gait + fwd * 0.03
		targets[s] = hang
		stiff[s] = HAND_STIFF_FREE
		hand_rot[s] = hand_rot[s].slerp(Basis(right, up, -fwd).get_rotation_quaternion(), 1.0 - exp(-12.0 * delta))

	if has_held:
		var grip: Vector3 = held.to_global(player.held_local_point)
		targets["r"] = grip
		stiff["r"] = HAND_STIFF_GRIP
		if two_hands:
			# ciężki przedmiot: dłonie po obu stronach punktu chwytu
			targets["r"] = grip + right * TWO_HAND_SPREAD
			targets["l"] = grip - right * TWO_HAND_SPREAD
			stiff["l"] = HAND_STIFF_GRIP
	var left_busy: bool = player.hand_items["l"] != null
	var bulky = player.hand_items["r"]
	if bulky != null and not bulky.is_bulky():
		bulky = null
	var carry_xf := Transform3D()
	if bulky != null and not has_held:
		# duży przedmiot oburącz: stos przed piersią, wzdłuż kierunku patrzenia, lekko w bok
		left_busy = true
		var pitch_q := Quaternion(right, player.pitch * 0.35)
		var d: Vector3 = (pitch_q * Quaternion(up, deg_to_rad(28.0)) * Quaternion(right, deg_to_rad(8.0)) * fwd).normalized()
		var c_up: Vector3 = (pitch_q * up).normalized()
		var side_ax := d.cross(c_up).normalized()
		var center := neck - up * 0.38 + fwd * 0.3 + right * 0.16
		carry_xf = Transform3D(Basis(d, c_up, d.cross(c_up)), center)
		var hq := Basis(side_ax, c_up, -d).get_rotation_quaternion()
		targets["r"] = center + side_ax * 0.1 + c_up * 0.01
		targets["l"] = center - side_ax * 0.1 + c_up * 0.01
		stiff["r"] = HAND_STIFF_GRIP
		stiff["l"] = HAND_STIFF_GRIP
		_turn_hand("r", hq, delta * 4.0)
		_turn_hand("l", hq, delta * 4.0)
		_update_hand_visual("r", bulky)
		_update_hand_visual("l", null)
	for side in ["l", "r"]:
		var item = player.hand_items[side]
		if bulky != null and not has_held:
			break
		if item == null or (side == "r" and has_held) or (side == "l" and two_hands):
			_update_hand_visual(side, null)
			continue
		var wt = player.work_targets.get(side)
		var wr = player.work_rots.get(side)
		if wt != null and wr != null:
			# praca z zadanym ułożeniem dłoni (zamach młotkiem, trzymanie gwoździa)
			targets[side] = wt
			stiff[side] = HAND_STIFF_GRIP
			_turn_hand(side, wr, delta * 3.0)
		elif wt != null:
			# praca: dłoń na punkcie pracy, przy wkręcaniu obraca się
			targets[side] = wt
			stiff[side] = HAND_STIFF_GRIP
			var roll: float = player.work_roll if player.work_side == side else 0.0
			var roll_q := Quaternion(cam_basis.z, -roll)
			_turn_hand(side, (roll_q * cam_q).normalized(), delta * 3.0)
		else:
			var rest := ITEM_HAND if side == "r" else Vector3(-ITEM_HAND.x, ITEM_HAND.y, ITEM_HAND.z)
			targets[side] = camera.global_transform * rest
			stiff[side] = HAND_STIFF_VIEW
			_turn_hand(side, cam_q, delta)
		_update_hand_visual(side, item)
	lamp_on = lamp_on and not left_busy  # z czymś w lewej ręce latarka wisi na piersi
	if lamp_on and not two_hands:
		targets["l"] = camera.global_transform * LAMP_HAND
		stiff["l"] = HAND_STIFF_VIEW
		_turn_hand("l", cam_q, delta)

	if not _initialized:
		for s in ["l", "r"]:
			hand_pos[s] = targets[s]
		_initialized = true

	for s in ["l", "r"]:
		var sign := -1.0 if s == "l" else 1.0
		_spring(s, targets[s], stiff[s], delta)
		var shoulder: Vector3 = joints["bark_" + s]
		var elbow_pole := shoulder - up * 0.5 + right * sign * 0.35 - fwd * 0.25
		# celujemy środkiem dłoni, więc nadgarstek jest o długość dłoni bliżej barku
		var palm_target: Vector3 = hand_pos[s]
		var wrist_target := palm_target - (palm_target - shoulder).normalized() * PALM
		var arm := solve_two_bone(shoulder, wrist_target, elbow_pole, UPPER_ARM, FOREARM)
		_limb("ramie_" + s, shoulder, arm[0], right)
		_limb("przedramie_" + s, arm[0], arm[1], right)
		var wrist: Vector3 = arm[1]
		var elbow: Vector3 = arm[0]
		var along := (wrist - elbow).normalized()
		_limb("dlon_" + s, wrist, wrist + along, right)
		joints["dlon_" + s] = wrist + along * PALM

	for side in ["l", "r"]:
		var vis: Node3D = _hand_visuals[side]
		if vis == null:
			continue
		if bulky != null and side == "r" and not has_held:
			vis.global_transform = carry_xf
			continue
		var hb := Basis(hand_rot[side])
		var def: Dictionary = player.hand_items[side].get_def()
		var model: Dictionary = def.get("model", {})
		var length := float(model.get("size", [0.4])[0]) if model.get("type", "box") == "box" else 0.12
		if str(def.get("grip", "")) == "up":
			# trzonek pionowo w pięści (młotek): oś X modelu idzie w górę dłoni,
			# dłoń trzyma trzonek w połowie, obuch patrzy do przodu
			vis.global_transform = Transform3D(hb * Basis(Vector3.BACK, PI / 2.0), joints["dlon_" + side] + hb * Vector3(0, length * GRIP_UP_OFFSET, 0))
		else:
			# modele leżą wzdłuż osi X; w dłoni kierujemy je do przodu (-Z)
			vis.global_transform = Transform3D(hb * Basis(Vector3.UP, PI / 2.0), joints["dlon_" + side] + hb * Vector3(0, 0, -length * 0.3))

	# --- latarka: w lewej dłoni, a gdy lewa jest zajęta, przypięta do piersi
	var lamp_xf: Transform3D
	if not two_hands and lamp_on:
		lamp_xf = Transform3D(Basis(hand_rot["l"]), joints["dlon_l"] + Basis(hand_rot["l"]) * Vector3(0.0, 0.02, -0.04))
	else:
		var chest := neck - torso_up * 0.16 + torso_fwd * 0.12 - torso_right * 0.08
		lamp_xf = Transform3D(Basis(right, up, -fwd), chest)
	_parts["latarka"].global_transform = lamp_xf
	_parts["latarka"].visible = lamp_visible
	player.lamp.global_transform = lamp_xf.translated_local(Vector3(0, 0, -0.18))
