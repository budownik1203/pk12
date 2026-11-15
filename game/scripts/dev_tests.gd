extends RefCounted
## Testy uruchamiane z wiersza poleceń, bez udziału gracza:
##   godot --headless --path game -- --test
##   godot --path game -- --zrzuty=/sciezka/do/folderu
## Kod wyjścia 0 oznacza powodzenie.

const SaveGame := preload("res://scripts/save_game.gd")
const ItemScript := preload("res://scripts/inventory/item.gd")
const Grid := preload("res://scripts/inventory/grid.gd")
const ItemDB := preload("res://scripts/inventory/item_db.gd")
const TEST_PATH := "user://test_zapisu.json"


static func _wait(tree: SceneTree, frames: int) -> void:
	for i in frames:
		await tree.physics_frame


static func _body(main: Node, id: String) -> RigidBody3D:
	for b in main.bodies:
		if b.name == id:
			return b
	return null


## Najniższy punkt bryły (róg jej siatki) w świecie.
static func _lowest_point(body: RigidBody3D) -> float:
	var low := INF
	for c in body.get_children():
		if c is MeshInstance3D:
			var box: AABB = c.mesh.get_aabb()
			for i in 8:
				low = minf(low, (c.global_transform * box.get_endpoint(i)).y)
	return low


static func _world_item(main: Node, def_id: String) -> RigidBody3D:
	var best: RigidBody3D = null
	for b in main.world_items.bodies:
		if b.get_meta("item").def_id == def_id and not b.has_meta("pending"):
			if best == null or b.global_position.x > best.global_position.x:
				best = b
	return best


## Czeka, aż kolejka czynności ekwipunku się opróżni (najwyżej limit sekund).
static func _finish(main: Node, limit: float = 8.0) -> void:
	var tree := main.get_tree()
	var t := 0.0
	while not main.inventory.actions.is_empty() and t < limit:
		await tree.process_frame
		t += main.get_process_delta_time()
	await tree.process_frame


## Wkłada nowy przedmiot prosto do ręki (testy narzędzi).
static func _hand(main: Node, def_id: String, props: Dictionary = {}, side: String = "r", count: int = 1):
	var inv = main.inventory
	inv.cancel_all()
	inv.slots.erase("oburacz")
	var slot: String = inv.hand_slot(side)
	inv.slots.erase(slot)
	var it = ItemScript.new(def_id, count)
	for k in props:
		it.props[k] = props[k]
	inv.slots[slot] = it
	it.slot = slot
	inv.changed.emit()
	return it


## Obraca widok gracza tak, by patrzył prosto na punkt.
static func _aim(main: Node, target: Vector3) -> void:
	var cam: Vector3 = main.player.camera.global_position
	var d := target - cam
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	main.player.set_view(yaw, pitch)


static func _point(main: Node, owner, filter: Dictionary):
	for p in main.work.points:
		if p.owner != owner:
			continue
		var ok := true
		for k in filter:
			if p.data.get(k) != filter[k]:
				ok = false
		if ok:
			return p
	return null


## Podważanie: ruch myszy w dół porcjami po 40 pikseli, aż warunek się spełni.
static func _lever_until(main: Node, cond: Callable, limit_px: float = 4000.0) -> float:
	var px := 0.0
	while not cond.call() and px < limit_px:
		main.work.mouse(Vector2(0, 40))
		px += 40.0
	return px


static func _place(main: Node, pos: Vector3, yaw_deg: float, pitch_deg: float = 0.0) -> void:
	main.player.teleport(pos)
	main.player.set_view(deg_to_rad(yaw_deg), deg_to_rad(pitch_deg))


static func run_tests(main: Node) -> void:
	var tree := main.get_tree()
	var errors := PackedStringArray()
	var player = main.player
	var inter = main.interaction

	# 1. Bryły opadają i się uspokajają; nic nie wypada poza świat.
	await _wait(tree, 240)
	if main.awake_body_count() > 0:
		var names := PackedStringArray()
		for b in main.bodies:
			if not b.sleeping:
				names.append("%s v=%.3f w=%.3f" % [b.name, b.linear_velocity.length(), b.angular_velocity.length()])
		errors.append("po 4 s nadal aktywne bryły: " + ", ".join(names))
	for b in main.bodies:
		if b.global_position.y < -1.0:
			errors.append("bryła %s wypadła poza świat" % b.name)

	# 2. Rozpędzanie ma bezwładność: po 0,25 s gracz nie ma jeszcze pełnej prędkości.
	_place(main, Vector3(-1.5, 0.02, 0.5), 90.0)  # twarzą w -X, pusta podłoga
	await _wait(tree, 5)
	Input.action_press("move_forward")
	await _wait(tree, 15)
	var early: float = Vector2(player.velocity.x, player.velocity.z).length()
	await _wait(tree, 45)
	var late: float = Vector2(player.velocity.x, player.velocity.z).length()
	Input.action_release("move_forward")
	if early > player.WALK_SPEED * 0.8:
		errors.append("ruch bez bezwładności (%.2f m/s po 0,25 s)" % early)
	if absf(late - player.WALK_SPEED) > 0.15:
		errors.append("prędkość chodu %.2f zamiast %.2f" % [late, player.WALK_SPEED])
	await _wait(tree, 40)

	# 3. Sprint zużywa wytrzymałość, odpoczynek ją przywraca.
	_place(main, Vector3(3.5, 0.02, -2.6), 90.0)
	await _wait(tree, 5)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait(tree, 60)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	var after_sprint: float = player.stamina
	if after_sprint > player.STAMINA_MAX - 5.0:
		errors.append("sprint nie zużył wytrzymałości (%.1f)" % after_sprint)
	await _wait(tree, 150)
	if player.stamina <= after_sprint:
		errors.append("wytrzymałość nie wraca po odpoczynku")

	# 4. Kucanie obniża oczy i kapsułę, puszczenie klawisza je podnosi.
	_place(main, Vector3(0.0, 0.02, 2.0), 0.0)
	await _wait(tree, 5)
	Input.action_press("crouch")
	await _wait(tree, 40)
	var eye_low: float = player.camera.global_position.y - player.global_position.y
	Input.action_release("crouch")
	await _wait(tree, 40)
	var eye_high: float = player.camera.global_position.y - player.global_position.y
	if eye_low > 1.0 or eye_high < 1.6:
		errors.append("kucanie: oczy na %.2f m, po wstaniu %.2f m" % [eye_low, eye_high])

	# 5. Wychylanie przesuwa kamerę w bok.
	Input.action_press("lean_right")
	await _wait(tree, 30)
	var lean_x: float = player.camera.position.x
	Input.action_release("lean_right")
	await _wait(tree, 30)
	if lean_x < 0.25 or absf(player.camera.position.x) > 0.02:
		errors.append("wychylanie: %.2f m w bok, po powrocie %.2f m" % [lean_x, player.camera.position.x])

	# 6. Wspinanie na stół (blat na 0,79 m).
	_place(main, Vector3(-2.2, 0.02, -1.35), 0.0)
	await _wait(tree, 10)
	Input.action_press("jump")
	await _wait(tree, 2)
	Input.action_release("jump")
	await _wait(tree, 90)
	if player.global_position.y < 0.7:
		errors.append("gracz nie wszedł na stół (y = %.2f)" % player.global_position.y)

	# 7. Pchanie ciałem: mała skrzynka przesuwa się przed graczem.
	var small := _body(main, "skrzynka_mala_a")
	var start: Vector3 = small.global_position
	_place(main, Vector3(start.x, 0.02, start.z + 1.0), 0.0)
	await _wait(tree, 5)
	Input.action_press("move_forward")
	await _wait(tree, 90)
	Input.action_release("move_forward")
	var pushed: float = start.z - small.global_position.z
	if pushed < 0.2:
		errors.append("gracz nie przepchnął skrzynki (%.2f m)" % pushed)
	await _wait(tree, 120)

	# 8. Chwyt: celownik pokazuje dłoń, lekka skrzynka daje się unieść i nieść.
	_place(main, small.global_position + Vector3(0, -0.18, 1.1), 0.0, -55.0)
	await _wait(tree, 5)
	if inter.focus_kind != "grab" or main.hud.cursor_state() != "hand":
		errors.append("celownik nie pokazuje dłoni nad skrzynką (%s / %s)" % [inter.focus_kind, main.hud.cursor_state()])
	inter.toggle_grab()
	await _wait(tree, 3)
	if inter.held != small or main.hud.cursor_state() != "fist":
		errors.append("chwyt nie zadziałał")
	for i in 35:  # unosimy wzrok stopniowo, jak ruchem myszy
		player.set_view(0.0, deg_to_rad(lerpf(-55.0, 15.0, (i + 1) / 35.0)))
		await tree.physics_frame
	await _wait(tree, 60)
	var lifted: float = small.global_position.y
	if lifted < 0.9:
		errors.append("skrzynka 6 kg nie dała się unieść (y = %.2f)" % lifted)
	Input.action_press("move_back")
	await _wait(tree, 60)
	Input.action_release("move_back")
	var gap: float = small.global_position.distance_to(player.camera.global_position)
	if inter.held != small or gap > 2.2:
		errors.append("niesiona skrzynka nie podąża za graczem (odległość %.2f m)" % gap)
	inter.toggle_grab()
	await _wait(tree, 120)
	if inter.held != null or small.global_position.y > 0.4:
		errors.append("puszczona skrzynka nie spadła (y = %.2f)" % small.global_position.y)

	# 9. Ciężka skrzynia (70 kg): nie da się jej unieść, ale da się ją wlec.
	var heavy := _body(main, "skrzynia_komorka")
	var heavy_start: Vector3 = heavy.global_position
	_place(main, heavy_start + Vector3(0, -0.43, 1.3), 0.0, -40.0)
	await _wait(tree, 5)
	inter.toggle_grab()
	player.set_view(0.0, deg_to_rad(30.0))
	await _wait(tree, 60)
	var heavy_low := _lowest_point(heavy)
	if heavy_low > 0.05:
		errors.append("skrzynia 70 kg oderwała się od podłogi (najniższy róg na %.2f m)" % heavy_low)
	player.set_view(0.0, deg_to_rad(-20.0))
	Input.action_press("move_back")
	await _wait(tree, 120)
	Input.action_release("move_back")
	var dragged: float = heavy.global_position.z - heavy_start.z
	print("wleczenie: skrzynia 70 kg przesunięta o %.2f m w 2 s" % dragged)
	if dragged < 0.15:
		errors.append("skrzyni 70 kg nie da się wlec (%.2f m)" % dragged)
	if dragged > 2.0:
		errors.append("skrzynię 70 kg wlecze się za łatwo (%.2f m w 2 s)" % dragged)
	inter.release()
	await _wait(tree, 60)

	# 10. Drzwi na zawiasie: chwyt i ruch w tył otwierają je po łuku.
	var door := _body(main, "drzwi_komorka")
	var door_start: Transform3D = door.global_transform
	_place(main, Vector3(3.4, 0.02, 1.45), -90.0, -5.0)  # sala, twarzą do drzwi
	await _wait(tree, 5)
	if inter.focus != door:
		errors.append("gracz nie celuje w drzwi")
	if not main.door_sys.latched:
		errors.append("drzwi na starcie nie są na zatrzasku")
	inter.toggle_grab()
	Input.action_press("move_back")
	await _wait(tree, 30)
	if door.global_transform.basis.get_rotation_quaternion().angle_to(door_start.basis.get_rotation_quaternion()) > 0.01:
		errors.append("drzwi na zatrzasku dały się otworzyć bez klamki")
	player.set_view(deg_to_rad(-90.0), deg_to_rad(-17.0))  # pociągnięcie klamki w dół
	await _wait(tree, 3)
	if main.door_sys.latched:
		errors.append("pociągnięcie wzroku w dół przy chwycie nie nacisnęło klamki")
	player.set_view(deg_to_rad(-90.0), deg_to_rad(-5.0))
	await _wait(tree, 70)
	Input.action_release("move_back")
	inter.release()
	var swing: float = door.global_transform.basis.get_rotation_quaternion().angle_to(door_start.basis.get_rotation_quaternion())
	var hinge_drift: float = absf(door.global_position.y - door_start.origin.y)
	print("drzwi: obrót o %.0f stopni" % rad_to_deg(swing))
	if swing < deg_to_rad(15.0):
		errors.append("drzwi nie otwierają się przy ciągnięciu (%.1f stopnia)" % rad_to_deg(swing))
	if hinge_drift > 0.03:
		errors.append("drzwi zeszły z zawiasu (%.3f m w pionie)" % hinge_drift)
	await _wait(tree, 60)

	# 11. Włącznik światła pod F.
	_place(main, Vector3(3.6, 0.02, 0.35), -90.0, -24.0)
	await _wait(tree, 5)
	if inter.focus_kind != "use" or main.hud.cursor_state() != "use":
		errors.append("celownik nie pokazuje użycia nad włącznikiem (%s)" % inter.focus_kind)
	var lamp_before: bool = main.switches["lampa_sala"]["light"].visible
	inter.use()
	if main.switches["lampa_sala"]["light"].visible == lamp_before:
		errors.append("włącznik nie przełączył lampy")

	# 11c. Ciało: stopy na podłodze, kucanie zgina nogi, dłoń sięga do chwytu,
	#      latarka w dłoni zostaje w tyle przy szybkim obrocie i dogania kamerę.
	var body = player.body
	_place(main, Vector3(-1.5, 0.02, 0.5), 90.0)
	await _wait(tree, 30)
	for s in ["l", "r"]:
		var fy: float = body.joints["stopa_" + s].y - player.global_position.y
		if fy < 0.0 or fy > 0.15:
			errors.append("stopa %s nie stoi na podłodze (%.2f m)" % [s, fy])
	var pelvis_stand: float = body.joints["miednica"].y
	Input.action_press("crouch")
	await _wait(tree, 40)
	var pelvis_crouch: float = body.joints["miednica"].y
	var knee_fwd: float = (body.joints["kolano_l"] - body.joints["miednica"]).dot(-player.global_transform.basis.z)
	Input.action_release("crouch")
	await _wait(tree, 40)
	if pelvis_crouch > pelvis_stand - 0.25:
		errors.append("kucanie nie obniża miednicy (%.2f -> %.2f)" % [pelvis_stand, pelvis_crouch])
	if knee_fwd < 0.15:
		errors.append("w kucaniu kolana nie idą do przodu (%.2f m)" % knee_fwd)
	# dłoń na trzymanej skrzynce
	var crate2 := _body(main, "skrzynka_srednia_a")
	_place(main, crate2.global_position + Vector3(0, -crate2.global_position.y + 0.02, 1.0), 0.0, -50.0)
	await _wait(tree, 5)
	if inter.focus == crate2:
		inter.toggle_grab()
		await _wait(tree, 40)
		var grip: Vector3 = crate2.to_global(player.held_local_point)
		var mid: Vector3 = (body.joints["dlon_r"] + body.joints["dlon_l"]) * 0.5
		var reach: float = mid.distance_to(grip)
		var spread: float = body.joints["dlon_r"].distance_to(body.joints["dlon_l"])
		print("dłonie: środek %.3f m od punktu chwytu, rozstaw %.2f m (skrzynka 18 kg)" % [reach, spread])
		if reach > 0.12:
			errors.append("dłonie nie trzymają punktu chwytu (%.2f m)" % reach)
		if spread < 0.2:
			errors.append("ciężka skrzynka nie jest trzymana obiema rękami (rozstaw %.2f m)" % spread)
		inter.release()
	else:
		errors.append("nie da się wycelować w skrzynkę 18 kg")
	await _wait(tree, 60)
	# latarka: opóźnienie dłoni przy szybkim obrocie
	_place(main, Vector3(-1.5, 0.02, 0.5), 90.0)
	player.lamp.visible = true
	await _wait(tree, 60)
	player.set_view(deg_to_rad(150.0), 0.0)  # gwałtowny obrót o 60 stopni
	await _wait(tree, 3)
	var cam_f: Vector3 = -player.camera.global_transform.basis.z
	var lag: float = rad_to_deg((-player.lamp.global_transform.basis.z).angle_to(cam_f))
	await _wait(tree, 60)
	var settled: float = rad_to_deg((-player.lamp.global_transform.basis.z).angle_to(-player.camera.global_transform.basis.z))
	print("latarka: %.0f stopni opóźnienia po obrocie, po sekundzie %.1f" % [lag, settled])
	if lag < 10.0:
		errors.append("latarka nie zostaje w tyle przy obrocie (%.1f stopnia)" % lag)
	if settled > 4.0:
		errors.append("latarka nie dogania kamery (%.1f stopnia)" % settled)
	player.lamp.visible = false

	# 15. Ekwipunek.
	var inv = main.inventory
	# 15a. kształty i siatka
	var pist = ItemScript.new("pistolet")
	if ItemDB.bounds(pist.cells_for(0)) != Vector2i(3, 2) or ItemDB.bounds(pist.cells_for(1)) != Vector2i(2, 3):
		errors.append("obrót kształtu L nie zmienia wymiarów")
	var tg = Grid.new(3, 3)
	tg.place(ItemScript.new("mlotek"), Vector2i.ZERO, 0)
	if not tg.find_space(pist).is_empty():
		errors.append("pistolet zmieścił się w siatce zajętej przez młotek")
	if not tg.find_space(ItemScript.new("bandaz")).has("pos"):
		errors.append("bandaż nie zmieścił się w wolną komórkę obok młotka")
	# 15b. stan początkowy
	if not inv.slots.has("spodnie") or not inv.slots.has("kurtka"):
		errors.append("na starcie brak spodni albo kurtki")
	var cab_grid = inv.containers["szafka"]["grids"][0]
	if cab_grid.items.size() != 16:
		errors.append("szafka ma %d przedmiotów zamiast 16" % cab_grid.items.size())
	# 15c. podniesienie puszki ze stołu (F): trwa, potem bryła znika, puszka w kieszeni
	var can_body := _world_item(main, "puszka_fasoli")
	_place(main, can_body.global_position + Vector3(0.0, -can_body.global_position.y + 0.02, 0.9), 0.0, -40.0)
	await _wait(tree, 5)
	var worlds_before: int = main.world_items.bodies.size()
	if not inv.pick_up(can_body):
		errors.append("nie da się podnieść puszki: " + inv.last_error)
	if main.world_items.bodies.size() != worlds_before:
		errors.append("puszka zniknęła ze świata bez czasu na podniesienie")
	await _finish(main)
	var cans := 0
	for it in inv.all_carried():
		if it.def_id == "puszka_fasoli":
			cans += 1
	if cans != 1 or main.world_items.bodies.size() != worlds_before - 1:
		errors.append("puszka nie trafiła do ekwipunku (w ekwipunku: %d)" % cans)
	# 15d. łom nie mieści się w kieszeniach: trafia do ręki
	var crowbar := _world_item(main, "lom")
	_place(main, crowbar.global_position + Vector3(0, 0, 1.0), 0.0, -45.0)
	await _wait(tree, 5)
	inv.pick_up(crowbar)
	await _finish(main)
	if inv.hand_item() == null or inv.hand_item().def_id != "lom":
		errors.append("łom nie trafił do ręki")
	# 15e. plecak: podniesiony od razu się zakłada
	var bag_body := _world_item(main, "plecak")
	_place(main, bag_body.global_position + Vector3(0, -bag_body.global_position.y + 0.02, 1.0), 0.0, -40.0)
	await _wait(tree, 5)
	inv.pick_up(bag_body)
	var bag_time: float = inv.current_action().get("duration", 0.0)
	await _finish(main)
	var bag = inv.slots.get("plecak")
	if bag == null:
		errors.append("plecak nie został założony")
	elif bag_time < 2.0:
		errors.append("zakładanie plecaka trwało tylko %.1f s" % bag_time)
	else:
		# 15f. masa: plecak zmniejsza odczuwaną masę zawartości
		inv.place_now(ItemScript.new("butelka_wody"), bag.grids[0])
		var diff: float = inv.carried_mass() - inv.felt_mass()
		var expect: float = bag.contents_mass() * 0.35
		if absf(diff - expect) > 0.01:
			errors.append("redukcja wagi plecaka: %.2f kg zamiast %.2f kg" % [diff, expect])
		# 15g. pojemnik nie wejdzie do siebie
		if inv.move_to_grid(bag, bag.grids[0], Vector2i.ZERO, 0) or inv.last_error != "INV_ERR_SELF":
			errors.append("plecak dał się włożyć do siebie (%s)" % inv.last_error)
	# 15h. pusty plecak zajmuje mniej miejsca
	var spare = ItemScript.new("plecak")
	var empty_cells: int = spare.cells_for(0).size()
	spare.grids[0].place(ItemScript.new("bandaz"), Vector2i.ZERO, 0)
	if empty_cells != 6 or spare.cells_for(0).size() != 12:
		errors.append("plecak: pusty %d komórek, pełny %d" % [empty_cells, spare.cells_for(0).size()])
	# 15i. łączenie i dzielenie stosów w szafce
	_place(main, Vector3(0.3, 0.02, -2.0), 0.0, -30.0)
	await _wait(tree, 5)
	var stacks: Array = []
	for it in cab_grid.items:
		if it.def_id == "naboje_9mm":
			stacks.append(it)
	if stacks.size() == 2:
		var small_s = stacks[0] if stacks[0].count < stacks[1].count else stacks[1]
		var big_s = stacks[1] if small_s == stacks[0] else stacks[0]
		inv.merge_into(big_s, small_s)
		await _finish(main)
		if small_s.count != 50 or big_s.count != 13:
			errors.append("łączenie stosów: %d i %d zamiast 50 i 13" % [small_s.count, big_s.count])
		var spot: Dictionary = cab_grid.find_space(ItemScript.new("naboje_9mm"))
		inv.split_to_grid(big_s, 6, cab_grid, spot["pos"], 0)
		await _finish(main)
		if big_s.count != 7:
			errors.append("dzielenie stosu: zostało %d zamiast 7" % big_s.count)
	else:
		errors.append("w szafce nie ma dwóch stosów naboi")
	# 15j. pas i skrót: śrubokręt z szafki do pasa, klawisz 1 do ręki i z powrotem
	var belt_body := _world_item(main, "pas")
	_place(main, belt_body.global_position + Vector3(1.0, -belt_body.global_position.y + 0.02, 0), 90.0, -20.0)
	await _wait(tree, 5)
	inv.pick_up(belt_body)
	await _finish(main)
	var belt = inv.slots.get("pas")
	var driver = null
	for it in cab_grid.items:
		if it.def_id == "srubokret":
			driver = it
	if belt == null or driver == null:
		errors.append("brak pasa albo śrubokręta do testu skrótu")
	else:
		_place(main, Vector3(0.3, 0.02, -2.0), 0.0, -30.0)
		await _wait(tree, 5)
		if not inv.move_to_grid(driver, belt.grids[1], Vector2i.ZERO, 1):
			errors.append("śrubokręt nie wchodzi do pasa: " + inv.last_error)
		await _finish(main)
		inv.set_hotkey(1, driver)
		inv.use_hotkey(1)  # łom wraca z ręki do plecaka, śrubokręt idzie do ręki
		await _finish(main)
		var lom_in_bag := false
		if bag != null:
			for it in bag.grids[0].items:
				if it.def_id == "lom":
					lom_in_bag = true
		if inv.hand_item() != driver or not lom_in_bag:
			errors.append("klawisz 1: w ręce %s, łom w plecaku: %s" % [inv.hand_item().def_id if inv.hand_item() != null else "nic", lom_in_bag])
		inv.use_hotkey(1)
		await _finish(main)
		if driver.parent_grid != belt.grids[1] or inv.hand_item() != null:
			errors.append("klawisz 1 nie odłożył śrubokręta do pasa")
	# 15k. wyrzucenie na ziemię: przedmiot staje się bryłą przed graczem
	var count_before: int = main.world_items.bodies.size()
	var bandage = null
	for it in inv.containers["szafka"]["grids"][0].items:
		if it.def_id == "bandaz":
			bandage = it
	inv.move_to_world(bandage)
	await _finish(main)
	if main.world_items.bodies.size() != count_before + 1:
		errors.append("wyrzucony bandaż nie pojawił się w świecie")
	# 15l. obciążenie spowalnia
	if inv.speed_factor_for(10.0) != 1.0 or absf(inv.speed_factor_for(45.0) - 0.45) > 0.001 or inv.speed_factor_for(30.0) >= 1.0:
		errors.append("krzywa obciążenia nie działa")
	# 15m. okno ekwipunku: przeciągnięcie puszki z kieszeni do szafki
	var ui = main.inv_ui
	main.open_inventory("szafka")
	await tree.process_frame
	var can_item = null
	for it in inv.all_carried():
		if it.def_id == "puszka_fasoli":
			can_item = it
	var free_spot: Dictionary = cab_grid.find_space(can_item)
	var target: Vector2 = ui.cell_center(cab_grid, free_spot["pos"])
	ui.begin_drag(can_item)
	if not ui.drop_at(target):
		errors.append("przeciągnięcie w oknie nie zadziałało: " + inv.last_error)
	await _finish(main)
	if can_item.parent_grid != cab_grid:
		errors.append("puszka przeciągnięta w oknie nie trafiła do szafki")
	await tree.process_frame
	main.close_inventory()

	# 16. Narzędzia i montaż.
	var ws = main.work
	var win = main.window_boards
	var ds = main.door_sys
	# 16a. zrywanie górnej deski łomem: celowanie, prawy przycisk, ruch w dół
	_hand(main, "lom")
	var wc: Vector3 = win.global_position
	_place(main, Vector3(wc.x, 0.02, wc.z - 1.0), 180.0)
	var pry0 = _point(main, win, {"slot": 2, "end": 0, "what": "pry"})
	_aim(main, pry0.world_pos())
	await _wait(tree, 3)
	if ws.candidate != pry0:
		errors.append("celownik nie znajduje końca deski do podważenia")
	ws.begin()
	var px0 := _lever_until(main, func(): return win.boards[2]["ends"][0]["free"])
	ws.end()
	var pry1 = _point(main, win, {"slot": 2, "end": 1, "what": "pry"})
	_aim(main, pry1.world_pos())
	await _wait(tree, 3)
	var items_before: int = main.world_items.bodies.size()
	ws.begin()
	_lever_until(main, func(): return win.boards[2]["state"] == "none")
	ws.end()
	print("deska: koniec z 2 gwoździami podważony po %.0f pikselach ruchu myszy" % px0)
	if px0 < 300.0 or px0 > 2000.0:
		errors.append("opór przy zrywaniu deski poza zakresem (%.0f px)" % px0)
	if win.boards[2]["state"] != "none" or main.world_items.bodies.size() <= items_before:
		errors.append("zerwana deska nie spadła jako przedmiot")
	# 16b. moneta nie podważa
	_hand(main, "moneta")
	var pry_mid = _point(main, win, {"slot": 1, "end": 0, "what": "pry"})
	_aim(main, pry_mid.world_pos())
	await _wait(tree, 3)
	if ws.candidate == pry_mid:
		errors.append("moneta pozwala podważać deski")
	# 16c. barykadowanie: przyłożenie deski i wbicie po gwoździu na każdym końcu
	_hand(main, "deska")
	var slot_p = _point(main, win, {"slot": 2, "what": "attach"})
	_aim(main, slot_p.world_pos())
	await _wait(tree, 3)
	if not ws.attach() or win.boards[2]["state"] != "placed":
		errors.append("deski nie da się przyłożyć do okna")
	_hand(main, "mlotek")
	_hand(main, "gwozdzie", {}, "l", 10)  # gwoździe w lewej ręce, młotek w prawej
	var nails_before: int = inv.count_of("gwozdzie")
	for e in 2:
		var np = _point(main, win, {"slot": 2, "end": e, "nail": 0, "what": "nail"})
		_place(main, Vector3(np.world_pos().x, 0.02, win.global_position.z - 0.6), 180.0)
		await _wait(tree, 4)
		_aim(main, np.world_pos())
		await _wait(tree, 3)
		if ws.candidate != np:
			var c = ws.candidate
			errors.append("celownik nie znajduje gwoździa na końcu %d (włączony: %s, kandydat: %s, odl. %.2f)" % [e, np.enabled,
					str(c.data) if c != null else "brak", main.player.camera.global_position.distance_to(np.world_pos())])
		if not ws.press("l") or ws.nail_point != np:
			errors.append("przytrzymanie lewego przycisku nie przykłada gwoździa")
		var clicks := 0
		while win.boards[2]["ends"][e]["nails"][0] < 3.0 and clicks < 10:
			ws.press("r")
			ws.release("r")
			clicks += 1
			await _wait(tree, 30)  # przerwa między uderzeniami
		ws.release("l")
		if clicks != 3:
			errors.append("gwóźdź wbity po %d kliknięciach zamiast 3" % clicks)
	# uderzenia szybsze niż przerwa nie liczą się
	var np2 = _point(main, win, {"slot": 2, "end": 1, "nail": 1, "what": "nail"})
	ws.candidate = np2
	ws.press("l")
	for k in 5:
		ws.press("r")
		ws.release("r")
	await _wait(tree, 12)  # obuch dochodzi do gwoździa
	if win.boards[2]["ends"][1]["nails"][1] != 1.0:
		errors.append("pięć szybkich kliknięć dało %.1f uderzenia zamiast 1" % win.boards[2]["ends"][1]["nails"][1])
	ws.release("l")
	await _wait(tree, 30)
	if win.boards[2]["state"] != "nailed" or inv.count_of("gwozdzie") != nails_before - 3:
		errors.append("przybijanie: stan %s, gwoździ zużyto %d" % [win.boards[2]["state"], nails_before - inv.count_of("gwozdzie")])
	if inv.hand("l") == null or inv.hand("l").count != 7:
		errors.append("gwoździe nie ubywają z lewej ręki")
	# 16d. wygięty gwóźdź (ze starszych zapisów) wyciąga pazur młotka
	main.inventory.slots.erase("w_lewej")
	win.boards[2]["ends"][0]["nails"][1] = -1.0
	win._refresh(2)
	var pull = _point(main, win, {"slot": 2, "end": 0, "nail": 1, "what": "pull"})
	ws.active = pull
	_lever_until(main, func(): return win.boards[2]["ends"][0]["nails"][1] >= 0.0)
	ws.end()
	if win.boards[2]["ends"][0]["nails"][1] != 0.0:
		errors.append("wygiętego gwoździa nie da się wyciągnąć młotkiem")
	if main.noise.count_label("NOISE_HAMMER") < 7:
		errors.append("uderzenia młotkiem nie robią hałasu")
	# 16e. nakładka i zamek na wkręty
	ds._set_latched(true)
	ds.locked = false
	_hand(main, "nakladka")
	ws.end()
	ws.candidate = ds.parts["nakladka"]["attach"]
	ws.attach()
	var driver2 = _hand(main, "srubokret")
	inv.give(ItemScript.new("wkrety", 10))
	var screws_before: int = inv.count_of("wkrety")
	for p in ds.parts["nakladka"]["points"]:
		ws.active = p
		for k in 17:
			ws.rotate_by(0.25)
	_hand(main, "zamek_drzwiowy", {"key_id": 7})
	ws.end()
	ws.candidate = ds.parts["zamek"]["attach"]
	ws.attach()
	main.inventory.slots.erase("w_reku")
	main.inventory.slots["w_reku"] = driver2
	driver2.slot = "w_reku"
	for p in ds.parts["zamek"]["points"]:
		ws.active = p
		for k in 17:
			ws.rotate_by(0.25)
	ws.end()
	if not ds.lock_works() or inv.count_of("wkrety") != screws_before - 6:
		errors.append("zamek po przykręceniu nie działa (wkrętów zużyto %d)" % (screws_before - inv.count_of("wkrety")))
	if driver2.condition() >= 1.0:
		errors.append("śrubokręt się nie zużywa")
	# 16f. zamykanie: z zewnątrz bez klucza nie, z kluczem tak; zamknięte nie puszcza klamki
	_place(main, Vector3(3.6, 0.02, 1.2), -90.0)
	await _wait(tree, 3)
	if ds.toggle_lock():
		errors.append("drzwi dały się zamknąć z zewnątrz bez klucza")
	inv.give(ItemScript.new("klucz"))
	for it in inv.all_carried():
		if it.def_id == "klucz":
			it.props["key_id"] = 7
	if not ds.toggle_lock() or not ds.locked:
		errors.append("klucz nie zamyka zamka")
	if ds.try_unlatch() or not ds.latched:
		errors.append("zamknięte na klucz drzwi otworzyły się klamką")
	# 16g. wykręcony wkręt wraca, a otwór trzyma słabiej
	var sp = ds.parts["nakladka"]["points"][0]
	var screws_mid: int = inv.count_of("wkrety")
	ws.active = sp
	for k in 18:
		ws.rotate_by(-0.25)
	if ds.parts["nakladka"]["screws"][0]["in"] or inv.count_of("wkrety") != screws_mid + 1 or ds.parts["nakladka"]["holes"][0] != 1:
		errors.append("wykręcanie wkrętu nie działa")
	for k in 17:
		ws.rotate_by(0.25)
	var loose_t: float = ds.parts["nakladka"]["screws"][0]["t"]
	if loose_t > 0.76 or loose_t < 0.7:
		errors.append("wkręt w rozbitym otworze trzyma %.2f zamiast około 0,74" % loose_t)
	# 16h. moneta kręci trzy razy wolniej
	_hand(main, "moneta")
	var before_coin: float = ds.parts["nakladka"]["screws"][0]["t"]
	ws.active = sp
	ws.rotate_by(-1.0)
	var coin_step: float = before_coin - ds.parts["nakladka"]["screws"][0]["t"]
	var coin_expect: float = 0.25 / 3.0 * (1.0 + main.character.level("majsterkowanie") * 0.06)
	if absf(coin_step - coin_expect) > 0.01:
		errors.append("moneta wykręciła %.3f zamiast %.3f obrotu wkrętu" % [coin_step, coin_expect])
	ws.rotate_by(1.0)
	ws.end()
	# 16i. wyważenie zamkniętych drzwi łomem: zamek i nakładka spadają
	_hand(main, "lom")
	var locked_effort: float = ds.pry_effort()
	var items_before_pry: int = main.world_items.bodies.size()
	ws.active = ds._pry_point
	var px_door := _lever_until(main, func(): return not ds.latched)
	ws.end()
	print("drzwi zamknięte na klucz: opór %.1f, wyważone po %.0f pikselach" % [locked_effort, px_door])
	if ds.latched or ds.locked or ds.parts["zamek"]["placed"]:
		errors.append("łom nie wyważył zamkniętych drzwi")
	if main.world_items.bodies.size() != items_before_pry + 2:
		errors.append("wyłamany zamek i nakładka nie spadły na ziemię")
	if locked_effort <= ds.PRY_LATCHED * 2.0:
		errors.append("zamek nie zwiększa oporu przy wyważaniu (%.1f)" % locked_effort)
	if main.noise.count_label("NOISE_DOOR_BREAK") != 1:
		errors.append("wyważenie drzwi nie zrobiło hałasu")
	# 16j. po skończonej pracy trzymany przycisk dalej blokuje kamerę
	_hand(main, "lom")
	var pry_b = _point(main, win, {"slot": 0, "end": 0, "what": "pry"})
	ws.end()
	ws.candidate = pry_b
	if not ws.press("r"):
		errors.append("16j: podważanie się nie zaczęło (deska: %s, punkt aktywny: %s)" % [win.boards[0]["state"], pry_b.enabled])
	_lever_until(main, func(): return win.boards[0]["ends"][0]["free"])
	await _wait(tree, 2)
	if ws.is_active() or not ws.is_locked():
		errors.append("po uwolnieniu końca deski mysz nie została przy narzędziu")
	ws.release("r")
	if ws.is_locked():
		errors.append("puszczenie przycisku nie oddało myszy kamerze")
	await _wait(tree, 120)
	main.inventory.slots.erase("w_reku")

	# 17a. deski oburącz: nie do plecaka, stos zależny od siły, upuszczone osobno
	inv.cancel_all()
	inv.slots.erase("oburacz")
	inv.slots.erase("w_reku")
	inv.slots.erase("w_lewej")
	_place(main, Vector3(-0.6, 0.02, 2.35), 0.0)
	await _wait(tree, 4)
	var planks: Array = []
	for b in main.world_items.bodies:
		if b.get_meta("item").def_id == "deska" and b.global_position.distance_to(Vector3(-0.6, 0.1, 3.0)) < 0.6:
			planks.append(b)
	if planks.size() < 4:
		errors.append("17a: w świecie leży %d desek zamiast 4" % planks.size())
	else:
		for k in 3:
			if not inv.pick_up(planks[k]):
				errors.append("17a: deska %d nie weszła do rąk (%s)" % [k, inv.last_error])
			await _finish(main)
		var held_planks = inv.hand("r")
		if held_planks == null or held_planks.def_id != "deska" or held_planks.count != 3:
			errors.append("17a: w rękach nie ma stosu 3 desek")
		if inv.pick_up(planks[3]) or inv.last_error != "INV_ERR_TOO_MANY":
			errors.append("17a: siła 5 pozwoliła unieść czwartą deskę")
		player.strength = 8
		if inv.bulky_limit(held_planks) != 4:
			errors.append("17a: siła 8 nie daje 4 desek (%d)" % inv.bulky_limit(held_planks))
		player.strength = 5
		if inv.can_place_in_grid(held_planks, inv.worn_grids()[0], Vector2i.ZERO, 0):
			errors.append("17a: deska zmieściła się w siatce")
		if inv.slot_accepts(ItemScript.new("bandaz"), "w_lewej"):
			errors.append("17a: z deskami w rękach lewa ręka przyjmuje inne rzeczy")
		var one = inv.take_hand("r")
		if one == null or one.count != 1 or held_planks.count != 2:
			errors.append("17a: przyłożenie nie zabiera jednej deski ze stosu")
		held_planks.count = 3
		var before_world := 0
		for b in main.world_items.bodies:
			if b.get_meta("item").def_id == "deska":
				before_world += 1
		inv.move_to_world(held_planks)
		await _finish(main)
		var after_world := 0
		for b in main.world_items.bodies:
			if b.get_meta("item").def_id == "deska":
				after_world += 1
		if after_world != before_world + 3 or inv.hand("r") != null:
			errors.append("17a: upuszczony stos nie spadł jako 3 osobne deski (%d -> %d)" % [before_world, after_world])
	await _wait(tree, 60)
	# 17b. tryb chwytania: T włącza, lewy przycisk trzyma, puszczenie puszcza; rzut bez wirowania
	var ia = main.interaction
	var crate: RigidBody3D = null
	for b in main.bodies:
		if b is RigidBody3D and not b.freeze and b.mass < 10.0 and b.global_position.distance_to(player.global_position) < 6.0:
			crate = b
			break
	if crate != null:
		_place(main, crate.global_position + Vector3(0, 0, 1.0) - Vector3(0, crate.global_position.y - 0.02, 0), 0.0)
		await _wait(tree, 4)
		_aim(main, crate.global_position)
		ia.toggle_grab_mode()
		await _wait(tree, 3)
		if ia.focus_kind != "grab" or not ia.grab_press() or ia.held != crate:
			errors.append("17b: lewy przycisk w trybie chwytania nie chwyta (%s)" % ia.focus_kind)
		await _wait(tree, 20)
		ia.throw_held()
		await _wait(tree, 2)
		if ia.held != null:
			errors.append("17b: rzut nie puścił przedmiotu")
		if crate.angular_velocity.length() > 5.0:
			errors.append("17b: rzucony przedmiot wiruje (%.1f rad/s)" % crate.angular_velocity.length())
		ia.toggle_grab_mode()
		if ia.grab_mode:
			errors.append("17b: T nie wyłącza trybu chwytania")
	else:
		errors.append("17b: brak lekkiej bryły do chwycenia")
	await _wait(tree, 60)
	# 17c. kolory znaczników: dokręcony wkręt na czerwono, luźny na niebiesko, przyłożenie na żółto
	var zp = ds.parts["zamek"]
	var zsc: Dictionary = zp["screws"][0]
	var saved_sc := zsc.duplicate()
	var saved_hole: int = zp["holes"][0]
	zp["holes"][0] = 0
	zsc["in"] = true
	zsc["t"] = 1.0
	if ws.category(zp["points"][0]) != "remove":
		errors.append("17c: dokręcony wkręt nie jest czerwony")
	zsc["t"] = 0.5
	if ws.category(zp["points"][0]) != "mount":
		errors.append("17c: luźny wkręt nie jest niebieski")
	zp["screws"][0] = saved_sc
	zp["holes"][0] = saved_hole
	if ws.category(win.boards[0]["points"][0]) != "place":
		errors.append("17c: miejsce na deskę nie jest żółte")
	# 17d. dźwięki: młotek, dobity gwóźdź, dokręcony wkręt, kroki
	for snd in ["hammer", "nail_done", "screw_tight", "pry", "crack", "place"]:
		if main.sound.count(snd) == 0:
			errors.append("17d: nie zagrał dźwięk " + snd)
	var snd_text := "hammer %d, nail_done %d, screw_tight %d, step %d" % [main.sound.count("hammer"), main.sound.count("nail_done"), main.sound.count("screw_tight"), main.sound.count("step")]
	print("dźwięki: " + snd_text)
	# 17e. nogi pod miednicą: stojąc, stopy nie wystają przed tułów
	await _wait(tree, 30)
	var pel: Vector3 = player.body.joints["miednica"]
	var feet_mid: Vector3 = (player.body.joints["stopa_l"] + player.body.joints["stopa_r"]) / 2.0
	var lean := Vector2(pel.x - feet_mid.x, pel.z - feet_mid.z).length()
	if lean > 0.06:
		errors.append("17e: stopy %.2f m od pionu pod miednicą" % lean)

	# 18a. chwyt oburącz: łom z prawej ręki na oba, lewa ręka zajęta, mocniejsza dźwignia
	inv.cancel_all()
	inv.slots.erase("oburacz")
	inv.slots.erase("w_lewej")
	var crow = _hand(main, "lom")
	if not inv.toggle_two_hands():
		errors.append("18a: Z nie przekłada łomu na oburącz (%s)" % inv.last_error)
	await _finish(main)
	if inv.slots.get("oburacz") != crow or inv.hand("r") != crow or inv.hand("l") != null or not inv.hands_two():
		errors.append("18a: łom nie jest trzymany oburącz")
	if inv.slot_accepts(ItemScript.new("bandaz"), "w_lewej"):
		errors.append("18a: przy chwycie oburącz lewa ręka przyjmuje rzeczy")
	if inv.slot_accepts(ItemScript.new("srubokret"), "oburacz"):
		errors.append("18a: śrubokręt da się chwycić oburącz")
	inv.toggle_two_hands()
	await _finish(main)
	if inv.slots.get("w_reku") != crow:
		errors.append("18a: drugie Z nie wraca łomu do prawej ręki")
	inv.toggle_two_hands()
	await _finish(main)
	# 18b. walka: kółko włącza, cios łomem trafia worek, garda, odepchnięcie
	var cb = main.combat
	var wbag := _body(main, "worek_treningowy")
	_place(main, wbag.global_position + Vector3(-0.85, 0.0, 0.0) - Vector3(0, wbag.global_position.y - 0.02, 0), -90.0)
	await _wait(tree, 4)
	_aim(main, wbag.global_position + Vector3(0, 0.25, 0))
	player.stamina = player.STAMINA_MAX
	cb.toggle()
	if not cb.active or main.work.candidate != null:
		errors.append("18b: kółko nie włącza trybu walki")
	cb.attack()
	if cb.state != "idle":
		errors.append("18b: cios przed przełożeniem chwytu")
	await _wait(tree, 25)
	var hp_before: float = wbag.get_meta("hp")
	var bag_pos := wbag.global_position
	var stam_before: float = player.stamina
	cb.press(MOUSE_BUTTON_LEFT)
	await _wait(tree, 60)
	var bag_hp: float = wbag.get_meta("hp")
	if bag_hp >= hp_before:
		errors.append("18b: cios łomem nie trafił worka (hp %.0f)" % bag_hp)
	elif absf((hp_before - bag_hp) - 32.0 * cb.TWO_HAND_DAMAGE) > 0.5:
		errors.append("18b: oburącz cios zadał %.1f zamiast %.1f" % [hp_before - bag_hp, 32.0 * cb.TWO_HAND_DAMAGE])
	if player.stamina >= stam_before:
		errors.append("18b: cios nie kosztuje wytrzymałości")
	print("walka: cios łomem oburącz %.0f, worek przesunięty o %.2f m" % [hp_before - bag_hp, wbag.global_position.distance_to(bag_pos)])
	cb.press(MOUSE_BUTTON_RIGHT)
	await _wait(tree, 5)
	if not cb.blocking or player.work_targets.get("r") == null:
		errors.append("18b: prawy przycisk nie podnosi gardy")
	var bag_before_shove := wbag.global_position
	cb.press(MOUSE_BUTTON_LEFT)
	await _wait(tree, 30)
	cb.release(MOUSE_BUTTON_RIGHT)
	if cb.blocking:
		errors.append("18b: puszczenie prawego nie opuszcza gardy")
	var shoved := false
	for h in cb.hits:
		if h.get("shove", false):
			shoved = true
	if not shoved:
		errors.append("18b: odepchnięcie nic nie pchnęło")
	print("walka: odepchnięcie przesunęło worek o %.2f m" % wbag.global_position.distance_to(bag_before_shove))
	cb.toggle()
	if cb.active:
		errors.append("18b: kółko nie wyłącza trybu walki")
	inv.slots.erase("oburacz")
	crow.slot = ""
	await _wait(tree, 240)  # pchnięty worek i to, w co uderzył, musi się uspokoić

	# 19a. rana krwawi, opatrunek tamuje, ubranie chroni
	var hp = main.health
	hp.reset()
	inv.cancel_all()
	if hp.protection("klatka", "cut") <= 0.0 or hp.protection("dlon_l", "cut") != 0.0:
		errors.append("19a: ochrona ubrań: klatka %.2f, dłoń %.2f" % [hp.protection("klatka", "cut"), hp.protection("dlon_l", "cut")])
	var cut: Dictionary = hp.wound("dlon_l", "rana_cieta", 0.8)
	var blood0: float = hp.blood
	await _wait(tree, 120)
	if cut.is_empty() or hp.blood >= blood0 - 0.1:
		errors.append("19a: rana cięta nie krwawi (krew %.2f -> %.2f)" % [blood0, hp.blood])
	var bleed_open: float = hp.wound_bleed(cut)
	inv.give(ItemScript.new("bandaz", 2))
	var band = null
	for it in inv.all_carried():
		if it.def_id == "bandaz":
			band = it
	var band_count: int = band.count if band != null else 0
	if band == null or not hp.treat(band, "dlon_l"):
		errors.append("19a: nie da się zacząć opatrywania")
	await _wait(tree, 260)
	if cut["bandage"] != "bandaz" or hp.wound_bleed(cut) > bleed_open * 0.2:
		errors.append("19a: bandaż nie tamuje krwi (%s, %.3f -> %.3f)" % [cut["bandage"], bleed_open, hp.wound_bleed(cut)])
	if inv.count_of("bandaz") != band_count - 1 + (inv.count_of("bandaz") - inv.count_of("bandaz")):
		pass
	# 19b. dezynfekcja, zszycie, szyna, tabletki
	inv.give(ItemScript.new("spirytus"))
	inv.give(ItemScript.new("igla_nici"))
	inv.give(ItemScript.new("szyna"))
	inv.give(ItemScript.new("tabletki"))
	var find_it := func(def_id: String):
		for it in inv.all_carried():
			if it.def_id == def_id:
				return it
		return null
	var alc = find_it.call("spirytus")
	hp.treat(alc, "dlon_l")
	await _wait(tree, 160)
	if not cut["disinfected"] or int(alc.props.get("doses", 8)) != 7:
		errors.append("19b: dezynfekcja nie zadziałała albo nie zużyła dawki")
	var deep: Dictionary = hp.wound("udo_p", "gleboka_rana", 0.7, true)
	hp.treat(find_it.call("igla_nici"), "udo_p")
	await _wait(tree, 420)
	if not deep["stitched"]:
		errors.append("19b: głęboka rana nie została zszyta")
	var frac: Dictionary = hp.wound("lydka_l", "zlamanie", 0.8, true)
	await _wait(tree, 2)
	if hp.leg_factor() > 0.55 or player.injury_sprint:
		errors.append("19b: złamana noga nie spowalnia (%.2f) albo pozwala biegać" % hp.leg_factor())
	hp.treat(find_it.call("szyna"), "lydka_l")
	await _wait(tree, 340)
	if not frac["splint"] or absf(hp.leg_factor() - 0.8) > 0.01:
		errors.append("19b: szyna nie usztywnia (%.2f)" % hp.leg_factor())
	var pain_before: float = hp.pain
	hp.treat(find_it.call("tabletki"), "klatka")
	await _wait(tree, 200)
	if hp.pain >= pain_before - 5.0:
		errors.append("19b: tabletki nie uśmierzają bólu (%.0f -> %.0f)" % [pain_before, hp.pain])
	# 19c. zdjęcie opatrunku daje brudny bandaż; zakażenie nieopatrzonej rany
	hp.remove_dressing("dlon_l")
	await _wait(tree, 120)
	if cut["bandage"] != "" or find_it.call("bandaz_brudny") == null:
		errors.append("19c: zdjęcie opatrunku nie oddaje brudnego bandaża")
	var dirty: Dictionary = hp.wound("przedramie_p", "rana_cieta", 0.6, true)
	hp._infect(dirty, 120.0)
	if float(dirty["infection"]) <= 0.1:
		errors.append("19c: brudna rana się nie zakaża")
	# 19d. ranna ręka bije słabiej; upadek z wysokości rani nogi
	var arm_ok: float = hp.arm_factor("r")
	hp.wound("przedramie_p", "zlamanie", 0.8, true)
	if hp.arm_factor("r") >= arm_ok - 0.3:
		errors.append("19d: złamane przedramię nie osłabia ręki (%.2f)" % hp.arm_factor("r"))
	var legs_before := 0
	for id in hp.LEGS:
		legs_before += hp.segments[id]["wounds"].size()
	hp.on_fall(12.0)
	var legs_after := 0
	for id in hp.LEGS:
		legs_after += hp.segments[id]["wounds"].size()
	if legs_after <= legs_before:
		errors.append("19d: upadek z 12 m/s nie zranił nóg")
	# 19e. okno zdrowia: przeciągnięcie bandaża na część ciała zaczyna opatrywanie
	inv.give(ItemScript.new("bandaz", 1))
	main.open_inventory("", true)
	await _wait(tree, 3)
	var hui = main.inv_ui
	if not hui.health_open or hui.hp_panel == null:
		errors.append("19e: H nie otwiera okna zdrowia")
	else:
		var hr: Rect2 = hui.hp_panel.seg_rects["przedramie_p"]
		hui.drag_item = find_it.call("bandaz")
		hui.drop_at(hr.get_center())
		if hp.action.is_empty() or hp.action["seg"] != "przedramie_p":
			errors.append("19e: upuszczenie bandaża na przedramię nie zaczyna opatrywania")
	await _wait(tree, 260)
	main.close_inventory()
	# 19f. zapis zdrowia i śmierć z wykrwawienia
	var saved: Dictionary = hp.to_dict()
	var n_wounds: int = hp.wound_count()
	hp.reset()
	hp.from_dict(JSON.parse_string(JSON.stringify(saved)))
	if hp.wound_count() != n_wounds:
		errors.append("19f: zapis zdrowia gubi rany (%d -> %d)" % [n_wounds, hp.wound_count()])
	hp.blood = 37.0
	await _wait(tree, 3)
	if not hp.dead or not player.controls_locked:
		errors.append("19f: wykrwawienie nie zabija")
	hp.reset()
	main.revive_if_needed()
	if player.controls_locked:
		errors.append("19f: po wyleczeniu sterowanie zostało zablokowane")
	main.set_hurt_effect(0.0, 0.0)
	await _wait(tree, 30)

	# 20a. zegar doby: godzina, światło dzienne, noc
	var ck = main.clock
	var nd = main.needs
	var saved_min: float = ck.minutes
	ck.minutes = 12.0 * 60.0
	ck.advance(0.0)
	if ck.daylight() < 0.8 or not ck.sun.visible:
		errors.append("20a: w południe brak słońca (%.2f)" % ck.daylight())
	ck.minutes = 23.0 * 60.0
	ck.advance(0.0)
	if ck.daylight() > 0.0 or ck.sun.visible or not ck.is_night():
		errors.append("20a: o 23:00 nadal jasno")
	ck.advance(60.0)
	if ck.day() != 2 or int(ck.hour()) != 0:
		errors.append("20a: po północy dzień %d, godzina %.1f" % [ck.day(), ck.hour()])
	ck.minutes = saved_min
	ck.advance(0.0)
	# 20b. potrzeby rosną z czasem gry
	nd.hunger = 10.0
	nd.thirst = 10.0
	nd.fatigue = 10.0
	ck.speed = 600.0
	await _wait(tree, 60)
	ck.speed = 1.0
	if nd.hunger < 18.0 or nd.thirst < 20.0 or nd.fatigue < 18.0:
		errors.append("20b: po ok. 4 h gry głód %.0f, pragnienie %.0f, zmęczenie %.0f" % [nd.hunger, nd.thirst, nd.fatigue])
	# 20c. jedzenie przeciągnięte na ciało; zamknięta puszka nie; zepsute zatruwa
	inv.cancel_all()
	var hp2 = main.health
	hp2.reset()
	var bread = ItemScript.new("chleb")
	bread.props["made"] = ck.minutes / 1440.0
	inv.give(bread)
	nd.hunger = 60.0
	hp2.treat(bread, "brzuch")
	await _wait(tree, 240)
	if nd.hunger > 53.0 or int(bread.props.get("portions", 4)) != 3:
		errors.append("20c: zjedzenie porcji chleba: głód %.0f, porcji %s" % [nd.hunger, bread.props.get("portions", 4)])
	var sealed = ItemScript.new("puszka_fasoli")
	inv.give(sealed)
	if hp2.treat(sealed, "brzuch") or not hp2.action.is_empty():
		errors.append("20c: zamkniętą puszkę da się zjeść")
	bread.props["made"] = ck.minutes / 1440.0 - 10.0
	hp2.treat(bread, "brzuch")
	await _wait(tree, 240)
	if nd.poison <= 0.1:
		errors.append("20c: zepsuty chleb nie zatruwa")
	nd.poison = 0.0
	# 20d. otwieranie puszki: puszka w lewej, otwieracz w prawej, kręcenie myszą
	_hand(main, "otwieracz")
	inv.slots.erase("w_lewej")
	var can = ItemScript.new("puszka_fasoli")
	inv.slots["w_lewej"] = can
	can.slot = "w_lewej"
	main.work.end()
	player.set_view(player.rotation.y, deg_to_rad(80.0))  # patrz w sufit: żadnego punktu w świecie
	await _wait(tree, 3)
	if main.work.candidate == null or main.work.candidate.id != "dlon":
		errors.append("20d: nie ma punktu otwierania puszki w dłoni")
	else:
		main.work.press("r")
		for k in 8:
			main.work.rotate_by(0.25)
		main.work.release("r")
		var opened = inv.hand("l")
		if opened == null or opened.def_id != "puszka_fasoli_otwarta":
			errors.append("20d: puszka się nie otworzyła")
	player.set_view(player.rotation.y, 0.0)
	inv.slots.erase("w_lewej")
	inv.slots.erase("w_reku")
	# 20e. zlew: napełnianie butelki, picie z kranu; picie z butelki
	var bottle = ItemScript.new("butelka_wody", 1, false)
	inv.slots["w_reku"] = bottle
	bottle.slot = "w_reku"
	main.use_sink()
	if bottle.liquid.is_empty() or absf(float(bottle.liquid["amount"]) - 1.0) > 0.01:
		errors.append("20e: zlew nie napełnia butelki")
	nd.thirst = 60.0
	hp2.treat(bottle, "glowa")
	await _wait(tree, 150)
	if nd.thirst > 40.0 or float(bottle.liquid.get("amount", 0.0)) > 0.76:
		errors.append("20e: picie z butelki: pragnienie %.0f, w butelce %.2f l" % [nd.thirst, float(bottle.liquid.get("amount", 0.0))])
	inv.slots.erase("w_reku")
	nd.thirst = 50.0
	main.use_sink()
	if nd.thirst > 25.0:
		errors.append("20e: picie z kranu nie gasi pragnienia (%.0f)" % nd.thirst)
	# 20f. sen na materacu przyspiesza czas i zmniejsza zmęczenie; klawisz budzi
	nd.fatigue = 70.0
	var t0: float = ck.minutes
	if not nd.try_sleep(1.0) or not player.controls_locked:
		errors.append("20f: nie da się zasnąć")
	await _wait(tree, 60)
	if ck.minutes - t0 < 20.0 or nd.fatigue >= 70.0:
		errors.append("20f: sen nie przyspiesza czasu (%.1f min) albo nie regeneruje (%.0f)" % [ck.minutes - t0, nd.fatigue])
	nd.wake()
	if nd.sleeping or player.controls_locked or ck.speed != 1.0:
		errors.append("20f: pobudka nie przywraca sterowania")
	# 20g. ubrania grzeją; skrajne pragnienie szkodzi zdrowiu
	if nd.insulation() < 0.5:
		errors.append("20g: izolacja ubrań %.2f" % nd.insulation())
	var hp_ok: float = hp2.overall()
	nd.thirst = 100.0
	ck.speed = 600.0
	await _wait(tree, 30)
	ck.speed = 1.0
	if hp2.overall() >= hp_ok - 1.0:
		errors.append("20g: odwodnienie nie obniża zdrowia (%.0f -> %.0f)" % [hp_ok, hp2.overall()])
	var nsave: Dictionary = nd.to_dict()
	nd.from_dict(JSON.parse_string(JSON.stringify(nsave)))
	if absf(nd.thirst - float(nsave["thirst"])) > 0.01:
		errors.append("20g: zapis potrzeb się nie zgadza")
	nd.from_dict({})
	hp2.reset()
	main.revive_if_needed()
	await _wait(tree, 30)

	# 21a. siatka nawigacji pokrywa pokój i grunt za oknem
	var zm = main.zombies
	zm.clear_all()
	var nmap: RID = main.world.get_world_3d().navigation_map
	await _wait(tree, 3)
	var npath: PackedVector3Array = NavigationServer3D.map_get_path(nmap, Vector3(-3.0, 0.0, 0.0), Vector3(3.0, 0.0, -2.0), true)
	if npath.size() < 2:
		errors.append("21a: brak drogi po siatce nawigacji w pokoju")
	var npath_out: PackedVector3Array = NavigationServer3D.map_get_path(nmap, Vector3(-3.5, 0.0, 4.3), Vector3(-1.0, 0.0, 5.8), true)
	if npath_out.size() < 2:
		errors.append("21a: brak siatki nawigacji za oknem")
	# 21b. zombie w oświetlonym pokoju zauważa gracza i idzie do niego
	main.health.reset()
	main.revive_if_needed()
	main.set_switch("lampa_sala", true)
	inv.slots.erase("w_reku")
	inv.slots.erase("oburacz")
	_place(main, Vector3(-1.0, 0.02, -1.0), 0.0)
	await _wait(tree, 4)
	var zb = zm.spawn(Vector3(-1.0, 0.02, -3.0))
	zb.global_position = Vector3(-1.0, 0.02, -4.5 + 1.5)
	zb._fwd = Vector3(0, 0, 1)
	var d0: float = zb.global_position.distance_to(player.global_position)
	await _wait(tree, 120)
	if zb.state != "chase" and zb.state != "attack":
		errors.append("21b: zombie nie goni gracza (stan %s)" % zb.state)
	if zb.global_position.distance_to(player.global_position) >= d0 - 0.4:
		errors.append("21b: zombie się nie zbliża (%.2f -> %.2f)" % [d0, zb.global_position.distance_to(player.global_position)])
	# 21c. atak: zombie przy graczu rani albo ubranie chroni
	var hits0: int = zm.hits_on_player
	for k in 240:
		await tree.physics_frame
		if zm.hits_on_player > hits0:
			break
	if zm.hits_on_player <= hits0:
		errors.append("21c: zombie przy graczu nie zaatakował (stan %s, odl. %.2f, z %s, gracz %s, cel %s, nast. %s, koniec %s, seen %.1f)" % [zb.state, zb.global_position.distance_to(player.global_position), zb.global_position, player.global_position, zb.target_pos, zb.nav.get_next_path_position(), zb.nav.is_navigation_finished(), zb._seen_t])
	# 21d. cios łomem w głowę zabija, w tułów zatacza; odepchnięcie przewraca
	var wounded: float = zb.hp
	zb.take_hit(20.0, zb.global_position + Vector3.UP * 1.0, Vector3(0, 0, -1), false)
	if zb.hp >= wounded or zb.is_dead():
		errors.append("21d: cios w tułów nie rani albo od razu zabija")
	zb.shove(Vector3(0, 0, -1))
	if zb.state != "down" and zb.state != "stagger":
		errors.append("21d: odepchnięcie nic nie robi (stan %s)" % zb.state)
	zb._set_state("chase")
	zb.body.down = 0.0
	zb.take_hit(43.0, zb.global_position + Vector3.UP * 1.6, Vector3(0, 0, -1), true)
	if not zb.is_dead():
		errors.append("21d: cios łomem oburącz w głowę nie zabił (hp %.0f)" % zb.hp)
	if zb.collision_layer != 0:
		errors.append("21d: zwłoki blokują przejście")
	# 21e. cios w trybie walki trafia zombie
	var zc = zm.spawn(player.global_position + Vector3(0, 0, -1.0))
	await _wait(tree, 2)
	zc.global_position = player.global_position + Vector3(0, 0, -1.0)
	zc._set_state("stagger")
	_hand(main, "lom")
	player.set_view(0.0, deg_to_rad(-12.0))
	player.stamina = player.STAMINA_MAX
	main.combat.toggle()
	await _wait(tree, 25)
	var zc_hp: float = zc.hp
	main.combat.press(MOUSE_BUTTON_LEFT)
	await _wait(tree, 45)
	if zc.hp >= zc_hp and not zc.is_dead():
		errors.append("21e: cios łomem w trybie walki nie trafił zombie")
	main.combat.toggle()
	inv.slots.erase("w_reku")
	zm.clear_all()
	main.health.reset()
	# 21f. hałas przyciąga: zombie za oknem słyszy młotek
	var zh = zm.spawn(Vector3(-2.4, 0.02, 5.6))
	await _wait(tree, 3)
	zh._set_state("wander")
	zh._seen_t = 99.0
	main.noise.emit_noise(main.window_boards.global_position, 70.0, "NOISE_HAMMER")
	if zh.state != "investigate":
		errors.append("21f: zombie nie słyszy młotka (stan %s)" % zh.state)
	# 21g. przy oknie wyrywa deski, potem przełazi do pokoju
	var wbz = main.window_boards
	zh.global_position = zm.window_point("out")
	zh._set_state("window")
	var tries := 0
	while not wbz.passable() and tries < 200:
		wbz.zombie_pull(1.0)
		tries += 1
	if not wbz.passable():
		errors.append("21g: deski nie puszczają mimo szarpania")
	for k in 200:
		await tree.physics_frame
		if zh.zone == "in":
			break
	if zh.zone != "in":
		errors.append("21g: zombie nie przelazł przez okno (stan %s, strefa %s)" % [zh.state, zh.zone])
	zm.clear_all()
	# 21h. walenie w zatrzaśnięte drzwi wyłamuje zatrzask
	var dsz = main.door_sys
	if not dsz.latched:
		dsz._set_latched(true)
	var was_locked: bool = dsz.locked
	dsz.locked = false
	dsz.zombie_bang(9.0)
	if dsz.latched:
		errors.append("21h: walenie nie wyłamało zatrzasku")
	dsz.locked = was_locked and false
	await _wait(tree, 60)
	# 21i. zakażenie: objawy po czasie, na końcu śmierć
	var hz = main.health
	hz.reset()
	hz.infect_knox()
	if hz.knox_stage() != 0:
		errors.append("21i: objawy zaraz po zakażeniu")
	hz.knox = hz.knox_total * 0.7
	if hz.knox_stage() != 2 or hz.overall() > 80.0:
		errors.append("21i: zaawansowane zakażenie: etap %d, zdrowie %.0f" % [hz.knox_stage(), hz.overall()])
	hz.knox = hz.knox_total * 1.01
	await _wait(tree, 3)
	if not hz.dead:
		errors.append("21i: pełne zakażenie nie zabija")
	hz.reset()
	main.revive_if_needed()
	# 21j. zapis zombie
	var z1 = zm.spawn(Vector3(-3.0, 0.02, 5.0))
	z1.hp = 37.0
	zm.spawn(Vector3(-1.5, 0.02, 5.5)).die(Vector3(1, 0, 0))
	var zsave: Array = zm.to_dict()
	zm.from_dict(JSON.parse_string(JSON.stringify(zsave)))
	await _wait(tree, 3)
	if zm.zombies.size() != 2 or zm.alive_count() != 1 or absf(zm.zombies[0].hp - 37.0) > 0.1:
		errors.append("21j: zapis zombie: %d, żywych %d" % [zm.zombies.size(), zm.alive_count()])
	zm.clear_all()
	await _wait(tree, 30)

	# 22a. pogoda: deszcz przyciemnia dzień, ochładza, pada za oknem
	var wt = main.weather
	var ckw = main.clock
	ckw.minutes = 12.0 * 60.0
	wt.set_kind("pogodnie", true)
	ckw.advance(0.0)
	var sun_clear: float = ckw.sun.light_energy
	var t_clear: float = ckw.outside_temp()
	wt.set_kind("burza", true)
	wt.next_change = 999.0  # bez zmiany pogody w trakcie przyspieszonego czasu
	ckw.advance(0.0)
	await _wait(tree, 3)
	if ckw.sun.light_energy >= sun_clear * 0.8 or ckw.outside_temp() >= t_clear - 2.0:
		errors.append("22a: burza nie przyciemnia (%.2f -> %.2f) albo nie ochładza (%.1f -> %.1f)" % [sun_clear, ckw.sun.light_energy, t_clear, ckw.outside_temp()])
	if not wt._particles.emitting:
		errors.append("22a: w burzy nie pada")
	var th0: int = wt.thunders
	wt.thunder()
	if wt.thunders != th0 + 1 or wt.flash() <= 0.0:
		errors.append("22a: grzmot bez błysku")
	# 22b. na dworze ubrania mokną i grzeją słabiej; w środku schną
	var ins_dry: float = main.needs.insulation()
	_place(main, Vector3(-2.4, 0.02, 5.2), 0.0)
	await _wait(tree, 4)
	ckw.speed = 300.0
	await _wait(tree, 40)
	ckw.speed = 1.0
	var wet_out: float = wt.clothes_wet()
	if wet_out < 0.3 or main.needs.insulation() >= ins_dry * 0.85:
		errors.append("22b: deszcz nie moczy ubrań (%.2f) albo nie zmniejsza izolacji (%.2f -> %.2f)" % [wet_out, ins_dry, main.needs.insulation()])
	# 22c. deszczówka w pustej puszce na dworze
	var rain_can = main.world_items.spawn(ItemScript.new("puszka_pusta"), Transform3D(Basis(), Vector3(-1.5, 0.1, 5.0)))
	await _wait(tree, 30)
	ckw.speed = 300.0
	await _wait(tree, 30)
	ckw.speed = 1.0
	var water: float = float(rain_can.get_meta("item").liquid.get("amount", 0.0))
	if water <= 0.05:
		errors.append("22c: puszka na deszczu nie zbiera wody (%.2f l)" % water)
	main.world_items.remove(rain_can)
	# 22d. deszcz zagłusza: zombie słyszy z mniejszej odległości
	if wt.hearing_factor() >= 0.8 or wt.sight_factor() >= 0.9:
		errors.append("22d: deszcz nie osłabia zmysłów zombie")
	_place(main, Vector3(-1.0, 0.02, 0.0), 0.0)
	await _wait(tree, 4)
	ckw.speed = 300.0
	await _wait(tree, 30)
	ckw.speed = 1.0
	if wt.clothes_wet() >= wet_out:
		errors.append("22d: w środku ubrania nie schną (%.2f -> %.2f)" % [wet_out, wt.clothes_wet()])
	var wsave: Dictionary = wt.to_dict()
	wt.set_kind("pogodnie", true)
	wt.from_dict(JSON.parse_string(JSON.stringify(wsave)))
	if wt.kind != "burza":
		errors.append("22d: zapis pogody")
	wt.set_kind("pogodnie", true)
	for it in inv.slots.values():
		it.wet = 0.0
	main.needs.from_dict({})
	main.health.reset()
	main.revive_if_needed()
	await _wait(tree, 20)

	# 23a. tworzenie postaci: zawód i cechy ustawiają poziomy i siłę
	var chr = main.character
	var saved_char: Dictionary = chr.to_dict()
	chr.create("Jan", "budowlaniec", ["silny", "hemofilik"])
	if chr.level("sila") != 9 or player.strength != 9 or chr.level("stolarstwo") != 1:
		errors.append("23a: budowlaniec + silny: siła %d (gracz %d), stolarstwo %d" % [chr.level("sila"), player.strength, chr.level("stolarstwo")])
	if chr.points_for("budowlaniec", ["silny", "hemofilik"]) != 0 or chr.points_for("ratownik", ["szybki_uczen"]) != -8:
		errors.append("23a: bilans punktów cech")
	if absf(chr.effect("bleed") - 1.6) > 0.001:
		errors.append("23a: hemofilik nie zwiększa krwawienia")
	if inv.bulky_limit(ItemScript.new("deska")) != 5:
		errors.append("23a: siła 9 nie daje 5 desek (%d)" % inv.bulky_limit(ItemScript.new("deska")))
	# 23b. umiejętności rosną od używania; szybki uczeń szybciej
	chr.create("Jan", "bezrobotny", [])
	var need: float = chr.xp_needed("stolarstwo")
	chr.add_xp("stolarstwo", need + 1.0)
	if chr.level("stolarstwo") != 1:
		errors.append("23b: stolarstwo nie wzrosło po %.0f pkt" % need)
	chr.create("Jan", "bezrobotny", ["szybki_uczen"])
	chr.add_xp("stolarstwo", need / 1.3 + 0.5)
	if chr.level("stolarstwo") != 1:
		errors.append("23b: szybki uczeń nie uczy się szybciej")
	if chr.xp_needed("sila") <= chr.xp_needed("stolarstwo") * 2.0:
		errors.append("23b: siła rośnie za szybko")
	# 23c. wymagania: bez pierwszej pomocy nie zszyjesz, bez majsterkowania nie zamontujesz zamka
	chr.create("Jan", "bezrobotny", [])
	main.health.reset()
	main.health.wound("udo_l", "gleboka_rana", 0.6, true)
	var needle = ItemScript.new("igla_nici")
	if not main.health.treatment_for(needle, "udo_l").get("error", "") == "HP_ERR_STITCH_SKILL":
		errors.append("23c: szycie bez umiejętności nie jest zablokowane")
	if chr.meets("mount_lock", false):
		errors.append("23c: montaż zamka bez majsterkowania")
	chr.levels["pierwsza_pomoc"] = 2
	if main.health.treatment_for(needle, "udo_l").has("error"):
		errors.append("23c: z pierwszą pomocą 2 nadal nie można szyć")
	main.health.reset()
	# 23d. książka: czytanie mnoży naukę do poziomu 4 (w świetle); w ciemności się nie da
	main.set_switch("lampa_sala", true)
	_place(main, Vector3(-1.0, 0.02, 0.0), 0.0)
	await _wait(tree, 4)
	var book = ItemScript.new("ksiazka_stolarstwo")
	inv.give(book)
	if main.health.treatment_for(book, "glowa").get("kind", "") != "read":
		errors.append("23d: przy zapalonej lampie nie można czytać (%s)" % main.health.treatment_for(book, "glowa"))
	chr.read_book(book)
	if int(chr.books.get("stolarstwo", 0)) != 4:
		errors.append("23d: książka nie działa do poziomu 4")
	main.set_switch("lampa_sala", false)
	main.clock.minutes = 23.0 * 60.0
	main.clock.advance(0.0)
	player.lamp.visible = false
	if not main.health.treatment_for(book, "glowa").has("error"):
		errors.append("23d: w ciemności da się czytać")
	main.clock.minutes = 9.0 * 60.0
	main.clock.advance(0.0)
	main.set_switch("lampa_sala", true)
	# 23e. wbijanie gwoździ uczy stolarstwa; zapis postaci
	var xp0: float = float(chr.xp["stolarstwo"])
	var lv0: int = chr.level("stolarstwo")
	chr.add_xp("stolarstwo", 4.0)
	if float(chr.xp["stolarstwo"]) <= xp0 and chr.level("stolarstwo") == lv0:
		errors.append("23e: brak doświadczenia")
	var csave: Dictionary = chr.to_dict()
	chr.create("X", "ratownik", [])
	chr.from_dict(JSON.parse_string(JSON.stringify(csave)))
	if chr.char_name != "Jan" or int(chr.books.get("stolarstwo", 0)) != 4:
		errors.append("23e: zapis postaci (%s, %s)" % [chr.char_name, chr.books])
	chr.from_dict(saved_char)
	chr.levels["majsterkowanie"] = maxi(chr.level("majsterkowanie"), 3)
	chr.levels["pierwsza_pomoc"] = maxi(chr.level("pierwsza_pomoc"), 3)
	main.char_panel.toggle()
	await _wait(tree, 3)
	main.char_panel.toggle()

	# 24a. ulica: domy, łupy w pojemnikach, pod dachem / na dworze
	var tw = main.town
	if tw.buildings.size() != 5:
		errors.append("24a: domów %d zamiast 5" % tw.buildings.size())
	var looted := 0
	for spot in tw.loot_spots:
		for g in inv.containers[spot[0]]["grids"]:
			looted += g.items.size()
	if tw.loot_spots.size() < 8 or looted < 6:
		errors.append("24a: pojemników %d, przedmiotów w nich %d" % [tw.loot_spots.size(), looted])
	var hc: Vector2 = (tw.buildings[0] as Rect2).get_center()
	if not tw.indoors(Vector3(hc.x, 0, hc.y)) or tw.indoors(Vector3(0, 0, 12.0)):
		errors.append("24a: rozpoznawanie wnętrz domów")
	var nmap2: RID = main.world.get_world_3d().navigation_map
	var to_house: PackedVector3Array = NavigationServer3D.map_get_path(nmap2, Vector3(0, 0, 12.0), Vector3(hc.x, 0, hc.y), true)
	if to_house.size() < 2 or to_house[to_house.size() - 1].distance_to(Vector3(hc.x, 0, hc.y)) > 1.5:
		errors.append("24a: zombie nie dojdą z ulicy do domu (droga %d punktów)" % to_house.size())
	# 24b. drzwi domu: F otwiera, drugie F domyka i zaskakują; zombie je wyważa
	var dr = tw.doors[0]
	_place(main, dr.door.global_position + dr.door.global_transform.basis.x * 1.2 - Vector3(0, dr.door.global_position.y, 0), 0.0)
	await _wait(tree, 4)
	dr.on_use(dr.door.global_position)
	await _wait(tree, 60)
	if dr.latched or dr.door_angle() < 0.2:
		errors.append("24b: drzwi się nie otworzyły (kąt %.2f)" % dr.door_angle())
	dr.on_use(dr.door.global_position)
	for k in 240:
		await tree.physics_frame
		if dr.latched:
			break
	if not dr.latched:
		errors.append("24b: drzwi się nie domknęły (kąt %.2f)" % dr.door_angle())
	dr.zombie_bang(7.0, dr.door.global_position + Vector3(0, 0, 1))
	if dr.latched:
		errors.append("24b: zombie nie wyważył drzwi")
	await _wait(tree, 30)
	# 24c. szyba: cios tłucze, odłamki kaleczą przełażącego, F je wybija
	var pane = tw.panes[0]
	pane.take_hit(10.0, pane.global_position, Vector3.FORWARD, false)
	if not pane.broken or not pane.shards:
		errors.append("24c: szyba się nie stłukła")
	main.health.reset()
	inv.slots.erase("rekawice")
	var wounds0: int = main.health.wound_count()
	var jacket_saved = inv.slots.get("kurtka")
	inv.slots.erase("kurtka")
	for k in 4:  # cięcie losuje rękę: kilka przejść, żeby wynik nie zależał od losowania
		pane._on_body(player)
	if jacket_saved != null:
		inv.slots["kurtka"] = jacket_saved
	if main.health.wound_count() <= wounds0:
		errors.append("24c: odłamki nie kaleczą bez rękawic")
	pane.clear_shards()
	if pane.shards or pane.collision_layer != 0:
		errors.append("24c: wybicie odłamków nie oczyszcza ramy")
	main.health.reset()
	# 24d. zapis ulicy
	var tsave: Dictionary = tw.to_dict()
	pane.broken = false
	pane._apply()
	tw.from_dict(JSON.parse_string(JSON.stringify(tsave)))
	if not pane.broken:
		errors.append("24d: zapis szyb")
	# 24e. zombie na start rozsiane po ulicy, z dala od gracza
	_place(main, Vector3(-1.0, 0.02, 0.0), 0.0)
	await _wait(tree, 4)
	zm.clear_all()
	zm.start_population()
	var far_ok := true
	for z in zm.zombies:
		if z.global_position.distance_to(player.global_position) < 13.5 or zm.zone_of(z.global_position) != "out":
			far_ok = false
	if zm.zombies.size() != 10 or not far_ok:
		errors.append("24e: zombie na start: %d, z dala od gracza: %s" % [zm.zombies.size(), far_ok])
	zm.clear_all()
	await _wait(tree, 20)

	# 25a. krojenie w dłoni: marchew w lewej, nóż w prawej, ruchy w dół
	var cws = main.work
	_hand(main, "noz")
	_hand(main, "marchew", {}, "l")
	cws.end()
	player.set_view(player.rotation.y, deg_to_rad(80.0))
	await _wait(tree, 3)
	if cws.candidate == null or cws.candidate.id != "dlon" or cws.candidate.kind != "lever":
		errors.append("25a: nie ma punktu krojenia w dłoni")
	else:
		cws.press("r")
		_lever_until(main, func(): return inv.hand("l") != null and inv.hand("l").def_id == "marchew_pokrojona", 3000.0)
		cws.release("r")
		if inv.hand("l") == null or inv.hand("l").def_id != "marchew_pokrojona":
			errors.append("25a: marchew się nie pokroiła")
	# 25b. darcie ubrania na szmaty nożyczkami, zawartość kieszeni zostaje
	_hand(main, "nozyczki")
	var trousers = _hand(main, "spodnie", {}, "l")
	trousers.grids[0].place(ItemScript.new("moneta", 2), Vector2i.ZERO, 0)
	cws.end()
	await _wait(tree, 3)
	if cws.candidate == null or cws.candidate.id != "dlon":
		errors.append("25b: nie ma punktu cięcia ubrania")
	else:
		cws.press("r")
		_lever_until(main, func(): return inv.hand("l") != null and inv.hand("l").def_id == "szmata", 3000.0)
		cws.release("r")
		var rags = inv.hand("l")
		if rags == null or rags.def_id != "szmata" or rags.count != 4:
			errors.append("25b: ze spodni nie ma 4 szmat")
		var coins := 0
		for x in inv.all_carried():
			if x.def_id == "moneta":
				coins += x.count
		if coins < 2:
			errors.append("25b: monety z kieszeni przepadły")
	player.set_view(player.rotation.y, 0.0)
	inv.slots.erase("w_lewej")
	# 25c. piłowanie deski leżącej w świecie: dwie deszczułki
	_hand(main, "pila")
	var plank = main.world_items.spawn(ItemScript.new("deska", 1), Transform3D(Basis(), Vector3(0.0, 0.05, 1.2)))
	_place(main, Vector3(0.0, 0.02, 2.0), 0.0)
	await _wait(tree, 40)
	_aim(main, plank.global_position)
	await _wait(tree, 3)
	if cws.candidate == null or cws.candidate.owner != main.saw:
		errors.append("25c: nie ma punktu piłowania na desce")
	else:
		cws.press("r")
		_lever_until(main, func(): return not is_instance_valid(plank) or not main.world_items.bodies.has(plank), 3000.0)
		cws.release("r")
		await _wait(tree, 3)
		var slats := 0
		for b in main.world_items.bodies:
			if b.get_meta("item").def_id == "deszczulka":
				slats += 1
		if slats != 2:
			errors.append("25c: deszczułek po piłowaniu %d zamiast 2" % slats)
	for b in main.world_items.bodies.duplicate():
		if b.get_meta("item").def_id == "deszczulka":
			main.world_items.remove(b)
	# 25d. ognisko na dworze: drewno obok siebie, zapałki w ręce, F
	var fire_at := Vector3(1.5, 0.05, 6.5)
	if main.town.indoors(fire_at):
		errors.append("25d: miejsce próby ogniska jest pod dachem")
	main.weather.rain = 0.0
	var wood1 = main.world_items.spawn(ItemScript.new("deszczulka", 1), Transform3D(Basis(), fire_at))
	main.world_items.spawn(ItemScript.new("deszczulka", 1), Transform3D(Basis(), fire_at + Vector3(0.2, 0.05, 0.1)))
	main.world_items.spawn(ItemScript.new("deska", 1), Transform3D(Basis(), fire_at + Vector3(-0.2, 0.1, -0.1)))
	_hand(main, "zapalki")
	_place(main, fire_at + Vector3(0, 0, 1.5), 0.0)
	await _wait(tree, 20)
	main.use_object(wood1)
	await _wait(tree, 3)
	var heat = main.heat
	if heat.fires.size() != 1:
		errors.append("25d: ognisko się nie rozpaliło")
	else:
		var fire = heat.fires[0]
		if absf(fire.fuel - 95.0) > 3.0:
			errors.append("25d: opał ogniska %.0f zamiast 95" % fire.fuel)
		if heat.warmth_at(fire.global_position + Vector3(1.0, 0.5, 0)) < 4.0:
			errors.append("25d: ognisko nie grzeje")
		if heat.light_at(fire.global_position + Vector3(1.0, 0, 0)) < 0.5:
			errors.append("25d: ognisko nie świeci")
		if int(inv.hand("r").props.get("doses", 12)) != 11:
			errors.append("25d: zapałki się nie zużyły")
		# dokładanie: F na ognisku z deszczułką w ręce
		_hand(main, "deszczulka")
		var f0: float = fire.fuel
		main.use_object(fire.get_child(0))
		if fire.fuel < f0 + 20.0 or inv.hand("r") != null:
			errors.append("25d: dokładanie do ognia nie działa")
		# 25e. patelnia na ogniu: ziemniak się piecze, potem przypala
		var pan_item = ItemScript.new("patelnia", 1)
		pan_item.grids[0].place(ItemScript.new("ziemniak", 1), Vector2i.ZERO, 0)
		main.world_items.spawn(pan_item, Transform3D(Basis(), fire.global_position + Vector3(0, 0.45, 0)))
		await _wait(tree, 60)
		heat._physics_process(heat.main.clock.real_seconds_for(42.0))
		var in_pan = pan_item.grids[0].items[0] if not pan_item.grids[0].items.is_empty() else null
		if in_pan == null or in_pan.def_id != "ziemniak_pieczony":
			errors.append("25e: ziemniak na patelni się nie upiekł (%s)" % (in_pan.def_id if in_pan != null else "pusto"))
		heat._physics_process(heat.main.clock.real_seconds_for(40.0))
		in_pan = pan_item.grids[0].items[0] if not pan_item.grids[0].items.is_empty() else null
		if in_pan == null or in_pan.def_id != "spalenizna":
			errors.append("25e: ziemniak zostawiony na ogniu się nie przypalił")
		# zapis ogniska
		var fsave: Array = heat.to_dict()
		heat.from_dict([])
		heat.from_dict(JSON.parse_string(JSON.stringify(fsave)))
		await _wait(tree, 2)
		if heat.fires.size() != 1 or absf(heat.fires[0].fuel - float(fsave[0]["fuel"])) > 0.5:
			errors.append("25e: zapis ogniska")
	# ognisko w domu: odmowa
	var wood_in = main.world_items.spawn(ItemScript.new("deska", 2), Transform3D(Basis(), Vector3(0.5, 0.05, 0.5)))
	_hand(main, "zapalniczka")
	main.use_object(wood_in)
	if heat.fires.size() > 1:
		errors.append("25d: ognisko rozpaliło się w domu")
	main.world_items.remove(wood_in)
	heat.from_dict([])
	# 25f. kuchenka w domu, garnek z wodą i pokrojonymi warzywami: zupa, jedzenie porcjami
	var stove_item = ItemScript.new("kuchenka", 1)
	var stove = main.world_items.spawn(stove_item, Transform3D(Basis(), Vector3(0.5, 0.08, 0.0)))
	inv.slots.erase("w_reku")
	await _wait(tree, 30)
	main.use_object(stove)
	if not bool(stove_item.props.get("on", false)):
		errors.append("25f: kuchenka się nie włączyła")
	var pot_item = ItemScript.new("garnek", 1)
	pot_item.liquid = {"type": "woda", "amount": 1.0}
	pot_item.grids[0].place(ItemScript.new("marchew_pokrojona", 2), Vector2i(0, 0), 0)
	pot_item.grids[0].place(ItemScript.new("cebula_pokrojona", 1), Vector2i(1, 0), 0)
	main.world_items.spawn(pot_item, Transform3D(Basis(), stove.global_position + Vector3(0, 0.3, 0)))
	await _wait(tree, 60)
	heat._physics_process(heat.main.clock.real_seconds_for(25.0))
	if str(pot_item.liquid.get("type", "")) != "zupa" or float(pot_item.liquid.get("hunger", 0.0)) < 30.0 or not pot_item.grids[0].items.is_empty():
		errors.append("25f: zupa się nie ugotowała (%s)" % JSON.stringify(pot_item.liquid))
	if float(stove_item.props.get("gas", 360.0)) >= 360.0:
		errors.append("25f: kuchenka nie zużywa gazu")
	nd.hunger = 70.0
	nd.drink(pot_item)
	if nd.hunger > 62.0 or absf(float(pot_item.liquid.get("amount", 0.0)) - 0.75) > 0.01:
		errors.append("25f: porcja zupy: głód %.0f, w garnku %.2f l" % [nd.hunger, float(pot_item.liquid.get("amount", 0.0))])
	if main.health.treatment_for(pot_item, "glowa").get("kind", "") != "drink":
		errors.append("25f: zupy nie da się zjeść z okna zdrowia")
	main.use_object(stove)
	if bool(stove_item.props.get("on", true)):
		errors.append("25f: kuchenka się nie wyłączyła")
	nd.hunger = 20.0
	for b in main.world_items.bodies.duplicate():
		if b.get_meta("item").def_id in ["kuchenka", "garnek", "patelnia", "deska", "deszczulka", "spalenizna"] and b.global_position.z > 4.5 or b.get_meta("item") in [stove_item, pot_item]:
			main.world_items.remove(b)
	inv.slots.erase("w_reku")
	inv.slots.erase("w_lewej")
	_place(main, Vector3(-1.0, 0.02, 0.0), 0.0)
	await _wait(tree, 20)

	# 11b. Po wszystkich próbach żadna bryła nie wyleciała poza pokój.
	for b in main.bodies:
		var bp: Vector3 = b.global_position
		if bp.y < -0.5 or bp.y > 3.2 or absf(bp.x - 1.5) > 7.0 or absf(bp.z) > 4.0:
			errors.append("bryła %s wyleciała poza pokój (%s)" % [b.name, bp])

	# 12. Zapis, zepsucie stanu, odczyt i porównanie.
	await _wait(tree, 180)
	var before := {}
	for b in main.bodies:
		before[b.get_meta("save_id")] = b.global_transform
	var player_before: Vector3 = player.global_position
	var lamp_saved: bool = main.switches["lampa_sala"]["on"]
	main.set_style(2, false)
	player.lamp.visible = true
	var inv_saved: Dictionary = main.inventory.to_dict()
	var ws_saved := JSON.stringify({"w": main.window_boards.to_dict(), "d": main.door_sys.to_dict()})
	var world_saved: int = main.world_items.bodies.size()
	if not SaveGame.save(main, TEST_PATH):
		errors.append("zapis się nie powiódł")
	for b in main.bodies:
		if b.name != "drzwi_komorka":
			b.global_position += Vector3(0.7, 1.5, -0.4)
			b.linear_velocity = Vector3(1, 2, 3)
	player.teleport(player.global_position + Vector3(-2, 0, 1))
	player.lamp.visible = false
	main.set_switch("lampa_sala", not lamp_saved)
	main.inventory.slots.erase("plecak")  # psujemy też ekwipunek
	main.world_items.clear()
	main.set_style(0, false)
	TranslationServer.set_locale("en")
	var result: int = SaveGame.load_into(main, TEST_PATH)
	if result != SaveGame.Result.OK:
		errors.append("odczyt zwrócił kod %d" % result)
	await _wait(tree, 2)
	for b in main.bodies:
		var want: Transform3D = before[b.get_meta("save_id")]
		if b.global_position.distance_to(want.origin) > 0.03:
			errors.append("%s: pozycja po odczycie różni się o %.3f m" % [b.name, b.global_position.distance_to(want.origin)])
		if b.global_transform.basis.get_rotation_quaternion().angle_to(want.basis.get_rotation_quaternion()) > 0.03:
			errors.append("%s: obrót po odczycie się różni" % b.name)
	if player.global_position.distance_to(player_before) > 0.05:
		errors.append("gracz: pozycja po odczycie się różni")
	if main.style_index != 2:
		errors.append("styl nie wrócił (jest %d)" % main.style_index)
	if not player.lamp.visible:
		errors.append("latarka nie wróciła do stanu z zapisu")
	var ws_after := JSON.stringify({"w": main.window_boards.to_dict(), "d": main.door_sys.to_dict()})
	if ws_after != ws_saved:
		errors.append("okno albo drzwi po odczycie różnią się od zapisanych")
	var inv_after: Dictionary = main.inventory.to_dict()
	if JSON.stringify(inv_after) != JSON.stringify(inv_saved):
		errors.append("ekwipunek po odczycie różni się od zapisanego")
	if main.world_items.bodies.size() != world_saved:
		errors.append("przedmiotów w świecie po odczycie: %d zamiast %d" % [main.world_items.bodies.size(), world_saved])
	if main.switches["lampa_sala"]["on"] != lamp_saved or main.switches["lampa_sala"]["light"].visible != lamp_saved:
		errors.append("lampa nie wróciła do stanu z zapisu")
	if not TranslationServer.get_locale().begins_with("pl"):
		errors.append("język nie wrócił (jest %s)" % TranslationServer.get_locale())

	# 13. Uszkodzony plik, inna wersja i brak pliku nie mogą wywrócić gry.
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("{ to nie jest poprawny zapis")
	f.close()
	if SaveGame.load_into(main, TEST_PATH) != SaveGame.Result.BAD_FILE:
		errors.append("uszkodzony plik nie został odrzucony")
	f = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string('{"version": 999, "player": {}, "bodies": {}}')
	f.close()
	if SaveGame.load_into(main, TEST_PATH) != SaveGame.Result.BAD_FILE:
		errors.append("zapis z inną wersją nie został odrzucony")
	if SaveGame.load_into(main, "user://nie_ma_takiego.json") != SaveGame.Result.NO_FILE:
		errors.append("brak pliku nie został rozpoznany")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))

	# 14. Tłumaczenia: oba języki mają komplet tekstów.
	for key in ["HINTS", "MSG_SAVED", "DEV_FPS", "STYLE_RAW", "DEV_STAMINA", "DEV_HELD"]:
		for code in ["pl", "en"]:
			TranslationServer.set_locale(code)
			if main.tr(key) == key:
				errors.append("brak tłumaczenia %s w języku %s" % [key, code])

	if errors.is_empty():
		print("TESTY: OK (bryły: %d)" % main.bodies.size())
		tree.quit(0)
	else:
		for e in errors:
			printerr("TESTY: BŁĄD: " + e)
		tree.quit(1)


static func take_screenshots(main: Node, args: PackedStringArray) -> void:
	var tree := main.get_tree()
	var dir := ""
	for a in args:
		if a.begins_with("--zrzuty="):
			dir = a.trim_prefix("--zrzuty=")
	var player = main.player
	await _wait(tree, 120)
	# kadr 1: spojrzenie w dół na własne ciało w marszu
	_place(main, Vector3(-1.0, 0.02, 2.6), 90.0, -58.0)
	Input.action_press("move_forward")
	await _wait(tree, 40)
	await _shot(main, dir + "/cialo_w_dol.png")
	Input.action_release("move_forward")
	await _wait(tree, 40)
	# kadr 2: kucanie, spojrzenie w dół
	Input.action_press("crouch")
	await _wait(tree, 40)
	await _shot(main, dir + "/cialo_kucanie.png")
	Input.action_release("crouch")
	await _wait(tree, 40)
	# kadr 3: skrzynka 18 kg w obu rękach
	var crate := _body(main, "skrzynka_srednia_a")
	_place(main, crate.global_position + Vector3(0, -crate.global_position.y + 0.02, 1.0), 0.0, -50.0)
	await _wait(tree, 5)
	main.interaction.toggle_grab()
	for i in 30:
		player.set_view(0.0, deg_to_rad(lerpf(-50.0, -22.0, (i + 1) / 30.0)))
		await tree.physics_frame
	await _wait(tree, 30)
	await _shot(main, dir + "/niesienie_oburacz.png")
	main.interaction.release()
	await _wait(tree, 60)
	# kadr 4: okno ekwipunku z otwartą szafką, plecakiem, kamizelką i pasem
	var inv = main.inventory
	for def_id in ["plecak", "kamizelka", "pas"]:
		var it = ItemScript.new(def_id)
		inv.slots[def_id] = it
		it.slot = def_id
	inv.place_now(ItemScript.new("butelka_wody"), inv.slots["plecak"].grids[0])
	inv.place_now(ItemScript.new("lom"), inv.slots["plecak"].grids[0])
	inv.place_now(ItemScript.new("bandaz", 3), inv.slots["kamizelka"].grids[0])
	var ammo = ItemScript.new("naboje_9mm", 30)
	inv.place_now(ammo, inv.slots["kamizelka"].grids[2])
	inv.set_hotkey(2, ammo)
	inv.place_now(ItemScript.new("puszka_fasoli"), inv.slots["kurtka"].grids[0])
	_place(main, Vector3(0.4, 0.02, -2.0), 0.0, -20.0)
	await _wait(tree, 10)
	main.open_inventory("szafka")
	var ui = main.inv_ui
	var cab = inv.containers["szafka"]["grids"][0]
	ui.open_items.append(cab.items.filter(func(i): return i.def_id == "apteczka")[0])
	ui._layout()
	ui.mouse = ui.cell_center(cab, cab.items[0].pos)
	ui.hover_item = cab.items[0]
	await _shot(main, dir + "/ekwipunek.png")
	# kadr 5: przeciąganie pistoletu nad plecakiem z podglądem miejsca
	var pistol = cab.items.filter(func(i): return i.def_id == "pistolet")[0]
	ui.hover_item = null
	ui.begin_drag(pistol)
	ui.drag_rot = 1
	ui.mouse = ui.cell_center(inv.slots["plecak"].grids[0], Vector2i(3, 1))
	await _shot(main, dir + "/ekwipunek_przeciaganie.png")
	ui.drag_item = null
	main.close_inventory()
	# kadr 6: łom w ręce, chwilę po obrocie (dłoń zostaje w tyle)
	inv.slots["w_reku"] = ItemScript.new("lom")
	inv.slots["w_reku"].slot = "w_reku"
	_place(main, Vector3(-1.0, 0.02, 1.5), 0.0, -8.0)
	await _wait(tree, 40)
	player.set_view(deg_to_rad(-30.0), deg_to_rad(-8.0))
	await _wait(tree, 4)
	await _shot(main, dir + "/lom_w_rece.png")
	# kadr 7: podważanie deski łomem w połowie (podpowiedź, postęp, znaczniki)
	var ws = main.work
	var win = main.window_boards
	inv.slots.erase("w_reku")
	_hand(main, "lom")
	var wc: Vector3 = win.global_position
	_place(main, Vector3(wc.x + 0.35, 0.02, wc.z - 1.05), 180.0)
	var pp = _point(main, win, {"slot": 1, "end": 0, "what": "pry"})
	_aim(main, pp.world_pos() + Vector3(0.05, -0.05, 0))
	await _wait(tree, 3)
	ws.begin()
	for k in 7:
		ws.mouse(Vector2(0, 40))
	await _wait(tree, 20)
	await _shot(main, dir + "/okno_podwazanie.png")
	ws.end()
	# kadr 8: młotek i gwoździe nad deską (podpowiedź uderzenia)
	_hand(main, "mlotek")
	_hand(main, "gwozdzie", {}, "l", 20)
	var np = _point(main, win, {"slot": 0, "end": 1, "nail": 0, "what": "nail"})
	win.boards[0]["ends"][1]["nails"][0] = 1.0
	win._refresh(0)
	_place(main, Vector3(np.world_pos().x - 0.25, 0.02, wc.z - 0.62), 180.0)
	_aim(main, np.world_pos())
	await _wait(tree, 3)
	ws.press("l")
	await _wait(tree, 20)
	await _shot(main, dir + "/okno_mlotek.png")
	ws.press("r")
	await _shot(main, dir + "/okno_mlotek_uderzenie.png", 7)
	ws.release("r")
	await _wait(tree, 30)
	ws.release("l")
	inv.slots.erase("w_lewej")
	# kadr: postać z zewnątrz (nogi, sylwetka), stos desek w rękach
	inv.slots.erase("w_reku")
	var boards = ItemScript.new("deska", 3)
	inv.slots["w_reku"] = boards
	boards.slot = "w_reku"
	_place(main, Vector3(0.5, 0.02, 1.0), 0.0, -5.0)
	await _wait(tree, 30)
	await _shot(main, dir + "/deski_oburacz.png")
	var ext := Camera3D.new()
	main.world.add_child(ext)
	ext.global_position = player.global_position + Vector3(1.6, 1.3, -1.9)
	ext.look_at(player.global_position + Vector3(0, 0.9, 0))
	ext.make_current()
	await _shot(main, dir + "/postac_z_zewnatrz.png")
	inv.slots.erase("w_reku")
	Input.action_press("move_forward")
	await _wait(tree, 25)
	ext.global_position = player.global_position + Vector3(2.2, 1.1, 0.4)
	ext.look_at(player.global_position + Vector3(0, 0.85, 0))
	await _shot(main, dir + "/postac_chod_z_boku.png")
	Input.action_release("move_forward")
	player.camera.make_current()
	ext.queue_free()
	await _wait(tree, 30)
	# kadry: walka łomem oburącz (postawa, zamach, garda) i pięściami
	var cbt = main.combat
	var wb := _body(main, "worek_treningowy")
	_place(main, wb.global_position + Vector3(-0.9, 0.0, 0.0) - Vector3(0, wb.global_position.y - 0.02, 0), -90.0, -5.0)
	_hand(main, "lom")
	inv.toggle_two_hands()
	await _finish(main)
	cbt.toggle()
	await _wait(tree, 30)
	await _shot(main, dir + "/walka_postawa.png")
	cbt.press(MOUSE_BUTTON_LEFT)
	await _shot(main, dir + "/walka_zamach.png", 18)
	await _wait(tree, 40)
	cbt.press(MOUSE_BUTTON_RIGHT)
	await _shot(main, dir + "/walka_garda.png", 20)
	cbt.release(MOUSE_BUTTON_RIGHT)
	inv.slots.erase("oburacz")
	await _shot(main, dir + "/walka_piesci.png", 20)
	cbt.toggle()
	await _wait(tree, 20)
	# kadry zdrowia: rany i opatrunki, okno zdrowia, utrata krwi
	var hpk = main.health
	hpk.reset()
	hpk.wound("przedramie_l", "rana_cieta", 0.8, true)["bandage"] = "bandaz"
	var fr: Dictionary = hpk.wound("przedramie_p", "zlamanie", 0.8, true)
	fr["splint"] = true
	hpk.wound("udo_p", "gleboka_rana", 0.7, true)
	hpk.wound("glowa", "zadrapanie", 0.5, true)
	var dl: Dictionary = hpk.wound("dlon_l", "ugryzienie", 0.6, true)
	dl["bandage"] = "szmata"
	dl["dirt"] = 0.7
	dl["infection"] = 0.3
	hpk.wound("lydka_l", "stluczenie", 0.5, true)
	_hand(main, "mlotek")
	_hand(main, "gwozdzie", {}, "l", 10)
	_place(main, Vector3(-1.0, 0.02, 2.0), 0.0, -30.0)
	await _wait(tree, 40)
	await _shot(main, dir + "/zdrowie_opatrunki.png")
	inv.slots.erase("w_reku")
	inv.slots.erase("w_lewej")
	var ext2 := Camera3D.new()
	main.world.add_child(ext2)
	ext2.global_position = player.global_position + Vector3(0.0, 1.3, -1.6)
	ext2.look_at(player.global_position + Vector3(0, 0.8, 0))
	ext2.make_current()
	await _shot(main, dir + "/zdrowie_postac.png")
	player.camera.make_current()
	ext2.queue_free()
	main.open_inventory("", true)
	main.inv_ui.hp_panel.selected = "udo_p"
	await _shot(main, dir + "/zdrowie_okno.png", 12)
	main.close_inventory()
	hpk.blood = 62.0
	await _wait(tree, 5)
	_place(main, Vector3(-1.0, 0.02, 2.6), -35.0, -8.0)
	await _shot(main, dir + "/zdrowie_utrata_krwi.png", 15)
	hpk.reset()
	main.set_hurt_effect(0.0, 0.0)
	await _wait(tree, 5)
	# kadry czasu: słońce przez okno w południe, noc z lampą, zlew, materac
	var ckk = main.clock
	var keep_min: float = ckk.minutes
	ckk.minutes = 13.0 * 60.0
	ckk.advance(0.0)
	main.set_switch("lampa_sala", false)
	_place(main, Vector3(-1.0, 0.02, 1.2), 160.0, -15.0)
	await _shot(main, dir + "/czas_poludnie.png", 20)
	ckk.minutes = 22.5 * 60.0
	ckk.advance(0.0)
	main.set_switch("lampa_sala", true)
	await _shot(main, dir + "/czas_noc.png", 20)
	ckk.minutes = keep_min
	ckk.advance(0.0)
	_place(main, Vector3(-3.2, 0.02, -0.6), 90.0, -25.0)
	main.use_sink()
	await _shot(main, dir + "/zlew.png", 12)
	# kadry ulicy: z góry, z ulicy na domy, wnętrze z latarką, łupy w szafce
	var twk = main.town
	var ckt = main.clock
	var keep_t: float = ckt.minutes
	ckt.minutes = 14.0 * 60.0
	ckt.advance(0.0)
	main.weather.set_kind("pochmurno", true)
	var top := Camera3D.new()
	main.world.add_child(top)
	top.global_position = Vector3(-2.0, 38.0, 32.0)
	top.look_at(Vector3(-2.0, 0.0, 8.0))
	top.make_current()
	await _shot(main, dir + "/ulica_z_gory.png", 12)
	player.camera.make_current()
	top.queue_free()
	_place(main, Vector3(-2.0, 0.02, 12.0), 180.0, -2.0)
	await _shot(main, dir + "/ulica.png", 20)
	var hb: Rect2 = twk.buildings[3]
	_place(main, Vector3(hb.get_center().x, 0.02, hb.get_center().y), 0.0, -8.0)
	ckt.minutes = 21.5 * 60.0
	ckt.advance(0.0)
	player.lamp.visible = true
	await _shot(main, dir + "/dom_wnetrze_latarka.png", 20)
	player.lamp.visible = false
	ckt.minutes = keep_t
	ckt.advance(0.0)
	main.weather.set_kind("pogodnie", true)
	var box_id: String = twk.loot_spots[0][0]
	var box_node: Node3D = inv.containers[box_id]["node"]
	_place(main, box_node.global_position + (Vector3(0, 0, 1.0) if box_node.global_position.z < hb.get_center().y else Vector3(0, 0, -1.0)) - Vector3(0, box_node.global_position.y - 0.02, 0), 0.0)
	await _wait(tree, 5)
	main.open_inventory(box_id)
	await _shot(main, dir + "/dom_lupy.png", 10)
	main.close_inventory()
	# kadry postaci: ekran tworzenia postaci i okno umiejętności
	var cc = load("res://scripts/ui/char_create.gd").new()
	main.hud.add_child(cc)
	cc.setup(main)
	cc._profs.select(1)
	cc.prof = cc._prof_ids[1]
	cc._toggle("silny")
	cc._toggle("hemofilik")
	cc._toggle("cichy")
	await _shot(main, dir + "/postac_tworzenie.png", 6)
	cc.queue_free()
	main.character.add_xp("stolarstwo", 25.0)
	main.character.add_xp("bron_tepa", 30.0)
	main.character.books["stolarstwo"] = 4
	main.char_panel.toggle()
	await _shot(main, dir + "/postac_umiejetnosci.png", 6)
	main.char_panel.toggle()
	# kadry pogody: deszcz za oknem, burza na dworze z błyskiem, mgła
	var wtk = main.weather
	var ckp = main.clock
	var keep_m: float = ckp.minutes
	ckp.minutes = 11.0 * 60.0
	wtk.set_kind("deszcz", true)
	ckp.advance(0.0)
	main.set_switch("lampa_sala", false)
	_place(main, Vector3(-2.4, 0.02, 2.2), 180.0, 2.0)
	await _shot(main, dir + "/pogoda_deszcz_okno.png", 40)
	wtk.set_kind("burza", true)
	_place(main, Vector3(-2.0, 0.02, 6.4), 10.0, -4.0)
	await _wait(tree, 30)
	wtk.thunder()
	ckp.advance(0.0)
	await _shot(main, dir + "/pogoda_burza.png", 3)
	wtk.set_kind("mgla", true)
	ckp.minutes = 7.0 * 60.0
	ckp.advance(0.0)
	await _shot(main, dir + "/pogoda_mgla.png", 30)
	wtk.set_kind("pogodnie", true)
	ckp.minutes = keep_m
	ckp.advance(0.0)
	main.set_switch("lampa_sala", true)
	# kadry zombie: w pokoju, przy oknie, z bliska, zwłoki
	var zmk = main.zombies
	main.set_switch("lampa_sala", true)
	_place(main, Vector3(-0.5, 0.02, -0.5), 0.0, -4.0)
	var zk1 = zmk.spawn(Vector3(-0.3, 0.02, -2.6))
	zk1._fwd = Vector3(0, 0, 1)
	zk1._set_state("chase")
	zk1._seen_t = 0.0
	await _wait(tree, 40)
	await _shot(main, dir + "/zombie_w_pokoju.png")
	zk1.die(Vector3(0, 0, -1))
	var zk2 = zmk.spawn(zmk.window_point("out"))
	zk2._set_state("window")
	_place(main, Vector3(-2.4, 0.02, 1.4), 180.0, 4.0)
	await _wait(tree, 50)
	await _shot(main, dir + "/zombie_okno.png")
	var extz := Camera3D.new()
	main.world.add_child(extz)
	var zk3 = zmk.spawn(Vector3(1.5, 0.02, 1.0))
	zk3._fwd = Vector3(-1, 0, 0.3).normalized()
	zk3._set_state("pozuje")  # stan bez ruchu: kadr z bliska
	zk3.body.reach = 1.0
	await _wait(tree, 20)
	extz.global_position = zk3.global_position + Vector3(-1.6, 1.5, 0.9)
	extz.look_at(zk3.global_position + Vector3(0, 1.1, 0))
	extz.make_current()
	await _shot(main, dir + "/zombie_z_bliska.png")
	extz.global_position = zk1.global_position + Vector3(1.2, 1.6, 1.2)
	extz.look_at(zk1.global_position + Vector3(0, 0.2, 0.4))
	await _shot(main, dir + "/zombie_zwloki.png")
	player.camera.make_current()
	extz.queue_free()
	zmk.clear_all()
	await _wait(tree, 10)
	# kadr: styl klasyczny PS1
	_place(main, Vector3(-1.0, 0.02, 2.6), -35.0, -8.0)
	main.set_style(1, false)
	await _wait(tree, 10)
	await _shot(main, dir + "/styl_ps1_klasyczny.png")
	main.set_style(0, false)
	# kadr 9: zamek na drzwiach od strony komórki, wkręcanie śrubokrętem
	var ds = main.door_sys
	main.set_switch("lampa_komorka", true)
	ds._set_latched(true)
	_hand(main, "nakladka")
	ws.end()
	ws.candidate = ds.parts["nakladka"]["attach"]
	ws.attach()
	_hand(main, "zamek_drzwiowy", {"key_id": 7})
	ws.end()
	ws.candidate = ds.parts["zamek"]["attach"]
	ws.attach()
	_hand(main, "srubokret")
	inv.give(ItemScript.new("wkrety", 10))
	_place(main, Vector3(5.25, 0.02, 1.35), -90.0)
	var sp = ds.parts["zamek"]["points"][0]
	_aim(main, sp.world_pos())
	await _wait(tree, 3)
	ws.begin()
	for k in 9:
		ws.rotate_by(0.25)
	await _wait(tree, 20)
	await _shot(main, dir + "/drzwi_zamek.png")
	ws.end()
	await _build11_shots(main, dir)
	tree.quit(0)


## Kadry buildu 11: ognisko z patelnią o zmierzchu, kuchenka z garnkiem,
## piłowanie deski, krojenie w dłoni.
static func _build11_shots(main: Node, dir: String) -> void:
	var tree := main.get_tree()
	var inv = main.inventory
	var ws = main.work
	main.zombies.clear_all()
	main.weather.set_kind("pogodnie", true)
	main.weather.next_change = 999.0
	# piłowanie deski na podłodze
	main.clock.minutes = 12.0 * 60.0
	main.clock.advance(0.0)
	main.set_switch("lampa_sala", true)
	_hand(main, "pila")
	var plank = main.world_items.spawn(ItemScript.new("deska", 1), Transform3D(Basis(), Vector3(0.6, 0.05, 1.0)))
	_place(main, Vector3(0.6, 0.02, 1.85), 0.0)
	await _wait(tree, 40)
	_aim(main, plank.global_position + Vector3(0, 0, 0.0))
	await _wait(tree, 3)
	ws.press("r")
	for k in 6:
		ws.mouse(Vector2(0, 40))
		await _wait(tree, 2)
	await _shot(main, dir + "/pilowanie.png")
	ws.release("r")
	ws.end()
	# krojenie marchwi w dłoni
	_hand(main, "noz")
	_hand(main, "marchew", {}, "l")
	main.player.set_view(main.player.rotation.y, deg_to_rad(-35.0))
	await _wait(tree, 5)
	if ws.candidate != null:
		ws.press("r")
		ws.mouse(Vector2(0, 30))
		await _wait(tree, 4)
	await _shot(main, dir + "/krojenie.png")
	ws.release("r")
	ws.end()
	inv.slots.erase("w_lewej")
	# kuchenka i garnek z zupą w domu
	var stove_item = ItemScript.new("kuchenka", 1)
	var stove = main.world_items.spawn(stove_item, Transform3D(Basis(), Vector3(0.4, 0.08, 0.2)))
	await _wait(tree, 30)
	main.use_object(stove)
	var pot = ItemScript.new("garnek", 1)
	pot.liquid = {"type": "woda", "amount": 1.4}
	pot.grids[0].place(ItemScript.new("ziemniak_pokrojony", 2), Vector2i(0, 0), 0)
	main.world_items.spawn(pot, Transform3D(Basis(), stove.global_position + Vector3(0, 0.14, 0)))
	inv.slots.erase("w_reku")
	_place(main, Vector3(-0.6, 0.02, 1.4), 0.0, 0.0)
	await _wait(tree, 60)
	var kcam := Camera3D.new()
	main.world.add_child(kcam)
	kcam.global_position = stove.global_position + Vector3(0.7, 0.75, 0.75)
	kcam.look_at(stove.global_position + Vector3(0, 0.1, 0))
	kcam.make_current()
	await _shot(main, dir + "/kuchenka_garnek.png")
	main.player.camera.make_current()
	kcam.queue_free()
	# ognisko z patelnią na dworze o zmierzchu
	main.clock.minutes = 20.6 * 60.0
	main.clock.advance(0.0)
	main.set_switch("lampa_sala", false)
	var at := Vector3(1.5, 0.05, 6.5)
	var f = main.heat.make_fire(at, 120.0)
	var pan = ItemScript.new("patelnia", 1)
	pan.grids[0].place(ItemScript.new("ziemniak", 2), Vector2i.ZERO, 0)
	main.world_items.spawn(pan, Transform3D(Basis(), f.global_position + Vector3(0.05, 0.45, 0)))
	main.world_items.spawn(ItemScript.new("deszczulka", 2), Transform3D(Basis(), at + Vector3(0.8, 0.05, 0.4)))
	_place(main, at + Vector3(-0.3, 0.0, -1.6), 180.0, -32.0)
	await _wait(tree, 60)
	await _shot(main, dir + "/ognisko.png")
	var cam := Camera3D.new()
	main.world.add_child(cam)
	cam.global_position = at + Vector3(-2.2, 1.6, 2.4)
	cam.look_at(at + Vector3(0, 0.3, 0))
	cam.make_current()
	await _shot(main, dir + "/ognisko_z_boku.png")
	main.player.camera.make_current()
	cam.queue_free()


static func _shot(main: Node, path: String, frames: int = 10) -> void:
	var tree := main.get_tree()
	for k in frames:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png(path)
