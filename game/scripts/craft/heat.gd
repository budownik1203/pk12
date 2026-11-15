extends Node
## Ogień i gotowanie.
## Ognisko: z drewna leżącego na ziemi na dworze (deski, deszczułki, książki...;
##   pole "fuel" w items.json to minuty palenia w czasie gry). F z zapalniczką
##   albo zapałkami w ręce na drewnie zbiera stos w promieniu 1 m i go zapala.
##   F na płonącym ognisku dokłada drewno z ręki. Ogień grzeje, świeci (zombie
##   widzą z daleka), trzaska i gaśnie, gdy skończy się opał albo pada ulewa.
## Kuchenka turystyczna: przedmiot postawiony w świecie, F włącza i wyłącza
##   (zużywa gaz), Shift+F podnosi. Działa też pod dachem.
## Gotowanie: garnek albo patelnia postawione na ogniu (nad źródłem ciepła)
##   gotują to, co mają w środku: pole "cook" przedmiotu (wynik i czas w minutach
##   gry). Za długo na ogniu: spalenizna. Garnek z wodą i pokrojonymi warzywami
##   robi zupę (płyn "zupa" z wartością odżywczą), którą je się porcjami.

const FireScript := preload("res://scripts/craft/fire.gd")
const ItemScript := preload("res://scripts/inventory/item.gd")

const COOK_RADIUS := 0.45           # jak daleko w poziomie od źródła ciepła
const COOK_HEIGHT := 0.7            # i jak wysoko nad nim
const BURN_AT := 1.7                # gotowanie ponad tyle: spalenizna
const LIGHT_RANGE := 4.0
const WARM_RANGE := 3.0

var main
var fires: Array = []


func setup(main_node) -> void:
	main = main_node


## Źródła ciepła: płonące ogniska i włączone kuchenki (pozycja płomienia).
func sources() -> Array:
	var out: Array = []
	for f in fires:
		if is_instance_valid(f) and f.burning():
			out.append({"pos": f.global_position + Vector3.UP * 0.15, "kind": "fire", "node": f})
	for b in main.world_items.bodies:
		if not is_instance_valid(b):
			continue
		var it = b.get_meta("item")
		if it.get_def().has("appliance") and bool(it.props.get("on", false)):
			out.append({"pos": b.global_position + Vector3.UP * 0.12, "kind": "stove", "node": b})
	return out


func _physics_process(delta: float) -> void:
	if main == null or main.clock == null:
		return
	var minutes: float = main.clock.game_hours(delta) * 60.0
	_stoves(minutes)
	var srcs := sources()
	if srcs.is_empty():
		return
	for b in main.world_items.bodies:
		if not is_instance_valid(b):
			continue
		var it = b.get_meta("item")
		if not it.get_def().has("cookware"):
			continue
		for s in srcs:
			var d: Vector3 = b.global_position - s["pos"]
			if Vector2(d.x, d.z).length() < COOK_RADIUS and d.y > -0.1 and d.y < COOK_HEIGHT:
				cook(it, minutes, b.global_position)
				break


## Kuchenki zużywają gaz; pusta gaśnie.
func _stoves(minutes: float) -> void:
	for b in main.world_items.bodies:
		if not is_instance_valid(b):
			continue
		var it = b.get_meta("item")
		if not it.get_def().has("appliance") or not bool(it.props.get("on", false)):
			continue
		var gas := float(it.props.get("gas", float(it.get_def()["appliance"].get("gas", 240.0)))) - minutes
		it.props["gas"] = maxf(0.0, gas)
		if gas <= 0.0:
			it.props["on"] = false
			main.hud.show_message(tr("MSG_STOVE_EMPTY"))
		_stove_flame(b, bool(it.props["on"]))


func _stove_flame(b: RigidBody3D, on: bool) -> void:
	var flame: Node3D = b.get_node_or_null("Plomien")
	if flame == null and on:
		var mi := MeshInstance3D.new()
		mi.name = "Plomien"
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 0.05
		c.height = 0.07
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.35, 0.5, 1.0)
		c.material = m
		mi.mesh = c
		mi.position = Vector3(0, 0.08, 0)
		var light := OmniLight3D.new()
		light.light_color = Color(0.5, 0.6, 1.0)
		light.light_energy = 0.4
		light.omni_range = 1.5
		mi.add_child(light)
		b.add_child(mi)
		flame = mi
	if flame != null:
		flame.visible = on


## Gotowanie zawartości naczynia (siatki i płynu) przez podaną liczbę minut gry.
func cook(pot, minutes: float, at: Vector3) -> void:
	var skill: int = main.character.level("gotowanie")
	var burn_at := BURN_AT + skill * 0.06
	var veg_ready := true
	var veg: Array = []
	for g in pot.grids:
		for it in g.items.duplicate():
			var d: Dictionary = it.get_def()
			if it.def_id == "spalenizna" or not (d.has("cook") or d.has("food")):
				continue
			var c: Dictionary = d.get("cook", {})
			var t := float(c.get("minutes", 30.0))
			var before := float(it.props.get("cooked", 0.0))
			var now := before + minutes / t
			it.props["cooked"] = now
			if d.has("soup"):
				veg.append(it)
				if now < 1.0:
					veg_ready = false
				continue  # w garnku warzywa idą do zupy, nie przypalają się
			if now >= burn_at:
				_replace(g, it, "spalenizna", 0.0)
				main.hud.show_message(tr("MSG_BURNED"))
				main.sound.play("sizzle", at, -2.0, 0.6)
			elif before < 1.0 and now >= 1.0 and c.has("result"):
				_replace(g, it, str(c["result"]), now)
				main.character.add_xp("gotowanie", 4.0)
				main.sound.play("sizzle", at, -6.0)
	# zupa: woda w garnku i ugotowane warzywa
	var water := float(pot.liquid.get("amount", 0.0)) if str(pot.liquid.get("type", "")) == "woda" else 0.0
	if water >= 0.3 and not veg.is_empty() and veg_ready:
		var hunger := 0.0
		var thirst := 0.0
		for it in veg:
			var sp: Dictionary = it.get_def()["soup"]
			hunger += float(sp.get("hunger", 8.0)) * it.count
			thirst += float(sp.get("thirst", 2.0)) * it.count
			it.parent_grid.remove(it)
		hunger *= 1.15 + skill * 0.05  # gotowana zupa syci lepiej niż surowe składniki
		pot.liquid = {"type": "zupa", "amount": water, "hunger": hunger, "thirst": thirst + water * 60.0}
		main.character.add_xp("gotowanie", 10.0)
		main.hud.show_message(tr("MSG_SOUP_READY"))
		main.sound.play("sizzle", at, -4.0, 0.7)
	main.inventory.changed.emit()


func _replace(grid, it, new_id: String, cooked: float) -> void:
	var pos: Vector2i = it.pos
	var rot: int = it.rot
	var out = ItemScript.new(new_id, it.count)
	if cooked > 0.0:
		out.props["cooked"] = cooked  # dalej na ogniu: zacznie się przypalać
	if out.get_def().get("food", {}).has("rot_days"):
		out.props["made"] = main.clock.minutes / 1440.0
	grid.remove(it)
	if grid.can_place(out, pos, rot):
		grid.place(out, pos, rot)
	else:
		var spot: Dictionary = grid.find_space(out)
		if not spot.is_empty():
			grid.place(out, spot["pos"], spot["rot"])


# --- ognisko -----------------------------------------------------------------------

func has_lighter() -> Object:
	for side in ["r", "l"]:
		var it = main.inventory.hand(side)
		if it != null and it.get_def().has("lighter"):
			return it
	return null


## F z zapalniczką na drewnie: stos z drewna w promieniu 1 m zamienia się w ognisko.
func try_ignite(target_body: RigidBody3D) -> bool:
	var lighter = has_lighter()
	if lighter == null:
		return false
	var at: Vector3 = target_body.global_position
	if main.town.indoors(at):
		main.hud.show_message(tr("MSG_NO_FIRE_INDOORS"))
		return true
	if main.weather.rain > 0.7:
		main.hud.show_message(tr("MSG_TOO_WET"))
		return true
	var fuel := 0.0
	var used: Array = []
	for b in main.world_items.bodies.duplicate():
		if not is_instance_valid(b) or b.global_position.distance_to(at) > 1.0:
			continue
		var it = b.get_meta("item")
		var f := float(it.get_def().get("fuel", 0.0))
		if f > 0.0:
			fuel += f * it.count
			used.append(b)
	if fuel < 20.0:
		main.hud.show_message(tr("MSG_NEED_MORE_WOOD"))
		return true
	_use_lighter(lighter)
	var center := Vector3.ZERO
	for b in used:
		center += b.global_position
		main.world_items.remove(b)
	center /= used.size()
	make_fire(Vector3(center.x, maxf(0.0, center.y - 0.1), center.z), fuel)
	main.hud.show_message(tr("MSG_FIRE_LIT"))
	return true


func _use_lighter(it) -> void:
	var doses := int(it.props.get("doses", int(it.get_def().get("doses", 20)))) - 1
	if doses <= 0:
		main.inventory.remove_item(it)
	else:
		it.props["doses"] = doses
	main.sound.play("switch", main.player.camera.global_position, -8.0, 0.7)


func make_fire(at: Vector3, fuel_minutes: float):
	var f = FireScript.new()
	main.world.add_child(f)
	f.global_position = at
	f.setup(main, fuel_minutes)
	fires.append(f)
	return f


## Ciepło od ognia w danym miejscu (°C do odczuwanej temperatury).
func warmth_at(p: Vector3) -> float:
	var w := 0.0
	for s in sources():
		var d: float = p.distance_to(s["pos"])
		var r := WARM_RANGE if s["kind"] == "fire" else 1.2
		var strength := 14.0 if s["kind"] == "fire" else 3.0
		if d < r:
			w = maxf(w, strength * (1.0 - d / r))
	return w


## Światło ognia przy graczu (0..1), dla zombie i czytania.
func light_at(p: Vector3) -> float:
	var l := 0.0
	for f in fires:
		if is_instance_valid(f) and f.burning():
			var d: float = p.distance_to(f.global_position)
			if d < LIGHT_RANGE:
				l = maxf(l, 0.85 * (1.0 - d / LIGHT_RANGE * 0.6))
	return l


func to_dict() -> Array:
	var out: Array = []
	for f in fires:
		if is_instance_valid(f) and f.burning():
			out.append({"pos": [f.global_position.x, f.global_position.y, f.global_position.z], "fuel": f.fuel})
	return out


func from_dict(list: Array) -> void:
	for f in fires:
		if is_instance_valid(f):
			f.queue_free()
	fires.clear()
	for d in list:
		var p: Array = d.get("pos", [0, 0, 0])
		make_fire(Vector3(float(p[0]), float(p[1]), float(p[2])), float(d.get("fuel", 30.0)))
