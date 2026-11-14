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
static func _hand(main: Node, def_id: String, props: Dictionary = {}):
	var inv = main.inventory
	inv.cancel_all()
	inv.slots.erase("w_reku")
	var it = ItemScript.new(def_id)
	for k in props:
		it.props[k] = props[k]
	inv.slots["w_reku"] = it
	it.slot = "w_reku"
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
	if cab_grid.items.size() != 14:
		errors.append("szafka ma %d przedmiotów zamiast 14" % cab_grid.items.size())
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
	inv.give(ItemScript.new("gwozdzie", 10))
	var nails_before: int = inv.count_of("gwozdzie")
	for e in 2:
		var np = _point(main, win, {"slot": 2, "end": e, "nail": 0, "what": "nail"})
		_aim(main, np.world_pos())
		await _wait(tree, 3)
		if ws.candidate != np:
			var c = ws.candidate
			errors.append("celownik nie znajduje gwoździa na końcu %d (włączony: %s, kandydat: %s, odl. %.2f)" % [e, np.enabled,
					str(c.data) if c != null else "brak", main.player.camera.global_position.distance_to(np.world_pos())])
		ws.begin()
		for k in 3:
			ws.mouse(Vector2(0, -120))
			ws.mouse(Vector2(0, 80))
		ws.end()
	if win.boards[2]["state"] != "nailed" or inv.count_of("gwozdzie") != nails_before - 2:
		errors.append("przybijanie: stan %s, gwoździ zużyto %d" % [win.boards[2]["state"], nails_before - inv.count_of("gwozdzie")])
	# 16d. za mocny zamach wygina gwóźdź; pazur młotka go wyciąga
	var bent_p = _point(main, win, {"slot": 2, "end": 0, "nail": 1, "what": "nail"})
	ws.active = bent_p
	ws.mouse(Vector2(0, -320))
	ws.mouse(Vector2(0, 80))
	ws.end()
	if win.boards[2]["ends"][0]["nails"][1] >= 0.0:
		errors.append("zamach 320 px nie wygiął gwoździa")
	var pull = _point(main, win, {"slot": 2, "end": 0, "nail": 1, "what": "pull"})
	ws.active = pull
	_lever_until(main, func(): return win.boards[2]["ends"][0]["nails"][1] >= 0.0)
	ws.end()
	if win.boards[2]["ends"][0]["nails"][1] != 0.0:
		errors.append("wygiętego gwoździa nie da się wyciągnąć młotkiem")
	if main.noise.count_label("NOISE_HAMMER") < 6:
		errors.append("uderzenia młotkiem nie robią hałasu")
	# 16e. nakładka i zamek na wkręty
	ds._set_latched(true)
	ds.locked = false
	_hand(main, "nakladka")
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
	if absf(coin_step - 0.25 / 3.0) > 0.01:
		errors.append("moneta wykręciła %.3f zamiast %.3f obrotu wkrętu" % [coin_step, 0.25 / 3.0])
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
	await _wait(tree, 120)
	main.inventory.slots.erase("w_reku")

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
	var np = _point(main, win, {"slot": 0, "end": 1, "nail": 0, "what": "nail"})
	win.boards[0]["ends"][1]["nails"][0] = 1.0
	win._refresh(0)
	_aim(main, np.world_pos())
	await _wait(tree, 20)
	await _shot(main, dir + "/okno_mlotek.png")
	# kadr 9: zamek na drzwiach od strony komórki, wkręcanie śrubokrętem
	var ds = main.door_sys
	main.set_switch("lampa_komorka", true)
	ds._set_latched(true)
	_hand(main, "nakladka")
	ws.candidate = ds.parts["nakladka"]["attach"]
	ws.attach()
	_hand(main, "zamek_drzwiowy", {"key_id": 7})
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
	tree.quit(0)


static func _shot(main: Node, path: String) -> void:
	var tree := main.get_tree()
	for k in 10:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png(path)
