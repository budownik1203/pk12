extends SceneTree
## Sprawdzenie prawdziwego startu gry (bez --test): ekran tworzenia postaci
## z widocznym kursorem, klikanie myszką w cechy i w „Rozpocznij”, potem
## złapana mysz, odpauzowany świat i zombie na ulicy.
## Uruchomienie: godot --path game -s res://tests/start_check.gd

var _fails: Array = []


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		root.push_input(e)
		await process_frame


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		root.push_input(e)
		await process_frame


func _check(ok: bool, what: String) -> void:
	print("START: %s %s" % ["OK  " if ok else "BŁĄD", what])
	if not ok:
		_fails.append(what)


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	for i in 30:
		await process_frame
	var main = current_scene
	var cc = main.hud.get_node_or_null("TworzeniePostaci")
	_check(cc != null and cc.visible, "ekran tworzenia postaci widoczny")
	if cc == null:
		quit(1)
		return
	_check(paused, "świat stoi na ekranie postaci")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "kursor widoczny na ekranie postaci")
	var good: ItemList = cc._good
	var p: Vector2 = good.get_global_rect().position + good.get_item_rect(0).get_center()
	await _click(p)
	_check(cc.chosen.size() == 1, "jedno kliknięcie wybiera cechę")
	var ch: ItemList = cc._chosen_list
	await _click(ch.get_global_rect().position + ch.get_item_rect(0).get_center())
	_check(cc.chosen.is_empty(), "kliknięcie na liście wybranych odznacza cechę")
	await _click(cc._start.get_global_rect().get_center())
	for i in 30:
		await process_frame
	_check(not paused, "po „Rozpocznij” świat rusza")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "po „Rozpocznij” mysz steruje kamerą")
	_check(not (is_instance_valid(cc) and cc.is_inside_tree()), "ekran postaci zamknięty")
	_check(main.zombies.alive_count() > int(main.zombies.settings.get("start_zombies", 8)), "zombie na start (mieszkańcy i włóczędzy): %d" % main.zombies.alive_count())
	# ekwipunek: Tab pokazuje kursor, drugi Tab oddaje mysz kamerze;
	# trzymana garda nie zostaje „wciśnięta” po otwarciu okna
	main.combat.blocking = true
	await _key(KEY_TAB)
	_check(not main.combat.blocking and main.work.active == null, "otwarcie ekwipunku puszcza trzymane przyciski")
	_check(main.inv_ui.is_open() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "ekwipunek otwarty z kursorem")
	await _key(KEY_TAB)
	_check(not main.inv_ui.is_open() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "ekwipunek zamknięty, mysz przy kamerze")
	# śmierć i nowa postać (Enter): ekran postaci znów z kursorem
	main.health._die()
	await process_frame
	await _key(KEY_ENTER)
	for i in 30:
		await process_frame
	var cc2 = current_scene.hud.get_node_or_null("TworzeniePostaci")
	_check(cc2 != null and cc2.visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "po śmierci nowy ekran postaci z kursorem")
	print("START: %s" % ("OK" if _fails.is_empty() else "BŁĘDY: %d" % _fails.size()))
	quit(0 if _fails.is_empty() else 1)
